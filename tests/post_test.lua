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

return checks
