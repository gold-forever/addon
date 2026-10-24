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
	{ value = "1s", label = "1 silver", copper = 100 },
	{ value = "1%", label = "1 percent", pct = 1 },
	{ value = "5%", label = "5 percent", pct = 5 },
}

-- Unit prices are whole silver on the auction house: down to the silver, at least one.
function Post.silver(copper)
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
	local normal = math.max(floor, Post.silver(market * (rule.normal or 120) / 100 + 50))
	if not cheapest then
		return { unit = normal, reason = "alone", floor = floor, normal = normal }
	end
	local under = cheapest - undercutBy(rule, cheapest)
	if under > normal then
		return { unit = normal, reason = "normal", floor = floor, normal = normal }
	end
	if under >= floor then
		-- Whole silver, and still under the cheapest one.
		local unit = math.floor(under / 100) * 100
		if unit >= floor then
			return { unit = unit, reason = "undercut", floor = floor, normal = normal }
		end
	end
	if rule.belowFloor == "floor" then
		return { unit = floor, reason = "floor", floor = floor, normal = normal }
	end
	return { unit = nil, reason = "hold", floor = floor, normal = normal }
end

-- What each reason says in the panel.
Post.REASONS = {
	undercut = "Undercut",
	alone = "No one else",
	normal = "Normal price",
	floor = "At floor",
	hold = "Hold",
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

-- The cheapest other listing worth reacting to, from levels { unitPrice, quantity, own }: a level of
-- fewer than `units` (2) other units more than `pct` (30%) under the next level is a "sneaky price"
-- and is passed over (design 009 decision 13's defaults). Returns the unit price, or nil.
function Post.honestCheapest(levels, units, pct)
	units, pct = units or 2, pct or 30
	local others = {}
	for _, l in ipairs(levels or {}) do
		local n = (l.quantity or 0) - (l.own or 0)
		if n > 0 then
			others[#others + 1] = { unit = l.unitPrice, n = n }
		end
	end
	table.sort(others, function(a, b)
		return a.unit < b.unit
	end)
	for i, o in ipairs(others) do
		local nextUnit = others[i + 1] and others[i + 1].unit
		if not (o.n < units and nextUnit and o.unit < nextUnit * (1 - pct / 100)) then
			return o.unit
		end
	end
	return nil
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
