-- Post.lua: the price to post at, the playground's suggestPost rule in whole silver.

local ns = {}
assert(load(SOURCES["Post.lua"], "@Post.lua"))("GoldForever", ns)
local P = ns.Post

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

local rule = P.DEFAULT
-- Market value 1g: floor 80s, normal 1g 20s.
local s = P.suggest(rule, 10000, nil)
eq(s.reason, "alone", "nobody else")
eq(s.unit, 12000, "the normal price")
eq(s.floor, 8000, "floor at 80%")

s = P.suggest(rule, 10000, 9550)
eq(s.reason, "undercut", "undercut")
eq(s.unit, 9400, "a silver under 95s 50c, in whole silver")

s = P.suggest(rule, 10000, 30000)
eq(s.reason, "normal", "everyone dearer than normal")
eq(s.unit, 12000, "capped at normal")

s = P.suggest(rule, 10000, 7000)
eq(s.reason, "hold", "the cheapest is under the floor")
eq(s.unit, nil, "nothing to post")

s = P.suggest({ undercut = "1s", floor = 80, normal = 120, belowFloor = "floor" }, 10000, 7000)
eq(s.reason, "floor", "post at the floor instead")
eq(s.unit, 8000, "at the floor")

s = P.suggest({ undercut = "5%", floor = 80, normal = 120 }, 10000, 10000)
eq(s.unit, 9500, "five percent under")

s = P.suggest(rule, 10000, 8050)
eq(s.reason, "hold", "a silver under would round below the floor")

-- Cheap items: never under a silver.
eq(P.silver(37), 100, "at least a silver")
eq(P.suggest(rule, 50, nil).unit, 100, "a copper item posts at a silver")

-- Sanity checks ask for a second press.
eq(P.check(100, 10000, 50, 0.05), "more than half under the market value", "far under market")
eq(P.check(100, nil, 200, 0.05), "under what a vendor pays", "under vendor after the cut")
eq(P.check(9400, 10000, 200, 0.05), nil, "a normal post")

-- Cancel undercut: how far under, as the playground's undercutPct.
eq(P.undercutPct(2100, 1900), 9.5, "9.5% under")
eq(P.undercutPct(2100, 2100), 0, "level")
eq(P.undercutPct(2100, 2500), 0, "dearer")
eq(P.undercutPct(2100, nil), 0, "nobody")
-- The sneaky-price guard: one unit far under the next is passed over; two units, or close, count.
local function lv(u, q, own) return { unitPrice = u, quantity = q, own = own or 0 } end
eq(P.honestCheapest({ lv(1000, 1), lv(2000, 20) }), 2000, "a single cheap unit far under is a sneaky price")
eq(P.honestCheapest({ lv(1000, 2), lv(2000, 20) }), 1000, "two units count")
eq(P.honestCheapest({ lv(1900, 1), lv(2000, 20) }), 1900, "one unit close to the next counts")
eq(P.honestCheapest({ lv(1500, 5, 5), lv(2000, 20) }), 2000, "the player's own units are left out")
eq(P.honestCheapest({}), nil, "an empty book")

-- Overrides: an item's over its category's over the default; only the fields an override holds change.
local base = { undercut = "1s", floor = 80, normal = 120, belowFloor = "hold" }
local overrides = { items = { [2589] = { floor = 50 } }, classes = { [7] = { undercut = "5%", normal = 150 } } }
local r, from = P.resolve(base, overrides, 2589, 7)
eq(from .. r.floor .. r.undercut .. r.normal, "item501s120", "the item's override, the rest the default's")
r, from = P.resolve(base, overrides, 2592, 7)
eq(from .. r.undercut .. r.normal .. r.floor, "category5%15080", "the category's")
r, from = P.resolve(base, overrides, 1, 2)
eq(from, "default", "no override")
eq(r, base, "the default itself")
eq(P.resolve(base, nil, 1, nil), base, "no overrides at all")

-- A client whose auction house takes copper: copper prices, a copper undercut.
P.copper = true
eq(P.silver(9437), 9437, "copper kept")
eq(P.suggest({ undercut = "1c", floor = 80, normal = 120 }, 10000, 9550).unit, 9549, "a copper under")
P.copper = false
eq(P.suggest({ undercut = "1c", floor = 80, normal = 120 }, 10000, 9550).unit, 9500, "whole silver otherwise")

-- The trend's advice: rising at 10% over the 7-day average, falling at 10% under, else none.
eq(P.trendHint(12), "rising: maybe wait", "well over the week's average")
eq(P.trendHint(10), "rising: maybe wait", "at the threshold")
eq(P.trendHint(-15), "falling", "well under")
eq(P.trendHint(9), nil, "near the average: no advice")
eq(P.trendHint(nil), nil, "no trend known")

-- What a rule does, in sentences for an item worth 10g (manual test run 001: the rule was hard to read).
local ex = P.examples(P.DEFAULT, function(c) return c .. "c" end)
eq(#ex, 4, "four situations")
eq(ex[1], "Someone lists it at 95000c: you post at 94900c (undercut)", "a little under the market")
eq(ex[2], "No one else lists it: you post at 120000c (no one else)", "alone")
eq(ex[3], "The cheapest is 50000c: you hold it, as it is under your floor", "under the floor, held")
eq(ex[4], "The cheapest is 200000c: you post at 120000c (normal price)", "far over")
local atFloor = P.examples({ undercut = "1s", floor = 80, normal = 120, belowFloor = "floor" }, function(c) return c .. "c" end)
eq(atFloor[3], "The cheapest is 50000c: you post at 80000c (at floor)", "or posted at the floor")

return checks
