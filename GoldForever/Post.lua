-- Gold Forever: the price to post at (design 009, Auction house module), as the web playground's
-- suggestPost has it: undercut the cheapest listing by someone else, never under a floor of the market
-- value, never over a normal price; with nobody to undercut, the normal price. Pure Lua 5.1 with no game
-- API, so it is tested outside the client.

local _, ns = ...
ns = ns or {}

local Post = {}
ns.Post = Post

-- The default rule: 1 silver under the cheapest (the auction house takes whole silver), a floor of 80%
-- of the market value, a normal price of 120%, and hold when the cheapest is under the floor.
Post.DEFAULT = { undercut = "1s", floor = 80, normal = 120, belowFloor = "hold" }

-- The undercuts a player can pick: an amount in copper, or a share of the cheapest price.
Post.UNDERCUTS = {
	{ value = "1c", label = "1 copper (where the auction house takes copper)", copper = 1 },
	{ value = "1s", label = "1 silver", copper = 100 },
	{ value = "1%", label = "1 percent", pct = 1 },
	{ value = "5%", label = "5 percent", pct = 5 },
}

-- Whether this client's auction house takes copper (C_AuctionHouse.SupportsCopperValues, read when it
-- opens); without it prices are whole silver, as Blizzard's own sell window assumes.
Post.copper = false

-- A unit price the auction house takes: whole silver (down to it, at least one), or whole copper (at
-- least one) where the client takes copper.
function Post.silver(copper)
	if Post.copper then
		return math.max(1, math.floor(copper))
	end
	return math.max(100, math.floor(copper / 100) * 100)
end

local function undercutBy(rule, cheapest)
	for _, u in ipairs(Post.UNDERCUTS) do
		if u.value == rule.undercut then
			return u.copper or math.max(1, math.floor(cheapest * u.pct / 100 + 0.5))
		end
	end
	return 100
end

-- The price for one unit from the market value and the cheapest buyout by someone else (nil: nobody).
-- Returns { unit (nil to hold), reason, floor, normal }; reason is "undercut", "alone" (nobody else),
-- "normal" (everyone dearer than the normal price), "floor" (posted at the floor) or "hold".
function Post.suggest(rule, market, cheapest)
	rule = rule or Post.DEFAULT
	local floor = Post.silver(math.ceil(market * (rule.floor or 80) / 100))
	-- To the nearest silver where the auction house takes silver; where it takes copper, to the copper.
	local normal = math.max(floor, Post.silver(market * (rule.normal or 120) / 100 + (Post.copper and 0 or 50)))
	if not cheapest then
		return { unit = normal, reason = "alone", floor = floor, normal = normal }
	end
	local under = cheapest - undercutBy(rule, cheapest)
	if under > normal then
		return { unit = normal, reason = "normal", floor = floor, normal = normal }
	end
	if under >= floor then
		-- What the auction house takes (whole silver, or copper), and still under the cheapest one.
		local unit = Post.copper and math.floor(under) or math.floor(under / 100) * 100
		if unit >= floor then
			return { unit = unit, reason = "undercut", floor = floor, normal = normal }
		end
	end
	if rule.belowFloor == "floor" then
		return { unit = floor, reason = "floor", floor = floor, normal = normal }
	end
	return { unit = nil, reason = "hold", floor = floor, normal = normal }
end

-- What a rule does, as four sentences for an item worth `market` (10g unless given): someone a little
-- under the market, no one else, someone far under (past the floor), someone far over. money(copper)
-- formats an amount.
function Post.examples(rule, money, market)
	market = market or 100000
	local out = {}
	local function say(situation, cheapest)
		local s = Post.suggest(rule, market, cheapest)
		out[#out + 1] = situation .. ": " .. (s.unit and ("you post at " .. money(s.unit) .. " (" .. string.lower(Post.REASONS[s.reason]) .. ")")
			or "you hold it, as it is under your floor")
	end
	local near, low, high = math.floor(market * 0.95), math.floor(market / 2), market * 2
	say("Someone lists it at " .. money(near), near)
	say("No one else lists it", nil)
	say("The cheapest is " .. money(low), low)
	say("The cheapest is " .. money(high), high)
	return out
end

-- Advice from the market's trend against its 7-day average (owner's answer, 2026-10-24), in percent:
-- 10% or more above it, "rising: maybe wait"; 10% or more under, "falling"; else nil. Advice only.
Post.TREND_HINT = 10
function Post.trendHint(pct)
	if not pct then
		return nil
	end
	if pct >= Post.TREND_HINT then
		return "rising: maybe wait"
	elseif pct <= -Post.TREND_HINT then
		return "falling"
	end
	return nil
end

-- What each reason says in the panel.
Post.REASONS = {
	undercut = "Undercut",
	alone = "No one else",
	normal = "Normal price",
	floor = "At floor",
	hold = "Under your floor", -- not "Hold", read as "keep this many" (manual test run 001)
	plan = "Plan", -- a sale plan's step; the panel shows the step's own label
}

-- A second press is asked for when a post looks like a mistake: under what a vendor pays after the
-- auction house's cut, or more than half under the market value. Returns the warning, or nil.
function Post.check(unit, market, vendor, cut)
	if vendor and vendor > 0 and math.floor(unit * (1 - (cut or 0.05))) < vendor then
		return "under what a vendor pays"
	end
	if market and market > 0 and unit < market * 0.5 then
		return "more than half under the market value"
	end
end

-- How far under the player's unit price the cheapest other listing sits, in percent to one decimal; 0
-- when nobody is cheaper (the playground's undercutPct). Cancel undercut acts past a tolerance only.
function Post.undercutPct(mine, other)
	if not other or other >= mine then
		return 0
	end
	return math.floor((mine - other) / mine * 1000 + 0.5) / 10
end

-- The cheapest other listing worth reacting to, from levels { unitPrice, quantity, own }: the sale
-- plans' sneaky-price guard (SalePlan.clean, design 009 decision 13), so Sell, Cancel and a sale plan
-- undercut the same price. `market` judges a book of a few units only. Returns the unit price, or nil.
function Post.honestCheapest(levels, market)
	local kept = ns.SalePlan.clean(levels, nil, market)
	return kept[1] and kept[1].unitPrice or nil
end

-- The rule an item posts by (design 009: one default, overridable per item category and per item): the
-- default with an item's override over it, else its category's; each override holds only what it
-- changes. Returns the rule and where it came from: "item", "category" or "default".
function Post.resolve(base, overrides, itemID, classID)
	overrides = overrides or {}
	local over, from = overrides.items and overrides.items[itemID], "item"
	if not over then
		over, from = classID and overrides.classes and overrides.classes[classID], "category"
	end
	if not over then
		return base, "default"
	end
	local rule = {}
	for k, v in pairs(base) do
		rule[k] = v
	end
	for k, v in pairs(over) do
		rule[k] = v
	end
	return rule, from
end
