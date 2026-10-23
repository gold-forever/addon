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
