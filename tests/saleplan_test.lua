-- SalePlan.lua: the playground's salePlan.test.ts cases, in Lua.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["SalePlan.lua"], "@SalePlan.lua"))("GoldForever", ns)
local P, E = ns.SalePlan, ns.Encode

local function lv(u, q, own) return { unitPrice = u, quantity = q, own = own or 0 } end
local function prices(levels) local out = {} for i, l in ipairs(levels) do out[i] = l.unitPrice end return table.concat(out, ",") end

-- cleanLevels: the sneaky-price guard
local kept, ignored = P.clean({ lv(500, 1), lv(1900, 20), lv(2000, 40) }, nil, 2000)
eq(prices(ignored), "500", "one cheap unit far under the market")
eq(kept[1].unitPrice, 1900, "the real first price")
kept, ignored = P.clean({ lv(400, 1), lv(600, 1), lv(1900, 20) }, nil, nil)
eq(prices(ignored), "400,600", "a few cheap units over levels, up to the limit")
kept, ignored = P.clean({ lv(500, 30), lv(1900, 20) }, nil, 2000)
eq(#ignored, 0, "real supply behind a cheap level")
_, ignored = P.clean({ lv(1800, 1), lv(1900, 20) }, nil, nil)
eq(#ignored, 0, "a little cheaper is kept")
kept = P.clean({ lv(1800, 5, 5), lv(1900, 20, 2) }, nil, nil)
eq(#kept .. ":" .. kept[1].unitPrice .. "x" .. kept[1].quantity, "1:1900x18", "own units left out")
_, ignored = P.clean({ lv(500, 1) }, nil, 2000)
eq(#ignored, 1, "a few units judged against the market")
_, ignored = P.clean({ lv(500, 1) }, nil, nil)
eq(#ignored, 0, "no market: kept")

-- percentilePrice
local book = { lv(100, 10), lv(200, 10), lv(300, 80) }
eq(P.percentile(book, 10), 100, "10%")
eq(P.percentile(book, 15), 200, "15%")
eq(P.percentile(book, 90), 300, "90%")
eq(P.percentile({}, 50), nil, "empty")

-- planSell
local undercut = { itemID = 1, keep = 200, price = { kind = "undercut", by = 1 }, floorPct = 80 }
local s = P.sell(undercut, 260, { lv(500, 1), lv(1900, 20) }, 2000)
eq(s.action .. s.reason .. s.quantity .. ":" .. s.unitPrice .. ":" .. s.ignored, "postundercut60:1899:1", "over the keep, a copper under the real lowest")
s = P.sell(undercut, 200, { lv(1900, 20) }, 2000)
eq(s.action .. s.reason .. s.quantity, "skipkeeping0", "at the keep")
s = P.sell(undercut, 260, { lv(1000, 50) }, 2000)
eq(s.action .. s.reason .. s.floor, "holdunder-floor1600", "under the floor")
s = P.sell(undercut, 260, {}, 2000)
eq(s.action .. s.reason .. s.unitPrice, "postno-competition2000", "nobody else: market value")
s = P.sell(undercut, 260, {}, nil)
eq(s.action .. s.reason, "holdno-price", "no price at all")
-- The floor is checked after rounding to the auction house's step (review B-14): floor 1650, a copper
-- under 1661 is 1660, whole silver 1600, under the floor.
local function silver(c) return math.max(100, math.floor(c / 100) * 100) end
local tight = { itemID = 1, keep = 0, price = { kind = "undercut", by = 1 }, floorPct = 100 }
s = P.sell(tight, 10, { lv(1661, 20) }, 1650)
eq(s.action .. s.unitPrice, "post1660", "unrounded: over the floor")
s = P.sell(tight, 10, { lv(1661, 20) }, 1650, nil, silver)
eq(s.action .. s.reason, "holdunder-floor", "rounded to the silver: under the floor, held")
s = P.sell(tight, 10, { lv(1801, 20) }, 1650, nil, silver)
eq(s.action .. s.unitPrice, "post1800", "rounded and still over the floor: posted at the rounded price")
local fixed = { itemID = 1, keep = 0, price = { kind = "fixed", unit = 2000, askIfMovedPct = 15 }, floorPct = 0 }
s = P.sell(fixed, 20, { lv(1900, 20) }, 2000)
eq(s.action .. s.reason .. s.unitPrice, "postfixed2000", "fixed while the market is near")
s = P.sell(fixed, 20, { lv(1500, 20) }, 2000)
eq(s.action .. s.reason .. s.choices.plan .. "/" .. s.choices.undercut, "askmarket-moved2000/1499", "asks once it moved")
local pct = { itemID = 1, keep = 0, price = { kind = "percentile", pct = 90 }, floorPct = 0 }
s = P.sell(pct, 5, { lv(10, 1), lv(100, 10), lv(300, 90) }, nil)
eq(s.action .. s.reason .. s.unitPrice .. ":" .. s.ignored, "postpercentile300:1", "a point in the supply")

-- planBuy
local b = P.buy({ itemID = 1, upTo = 200, maxUnit = 2000 }, 170, { lv(1900, 20), lv(500, 1), lv(2100, 50) })
eq(b.quantity .. ":" .. b.topUnit .. ":" .. b.total, "21:1900:" .. (500 + 20 * 1900), "cheapest first up to the target")
eq(P.buy({ itemID = 1, upTo = 10, maxUnit = 2000 }, 10, { lv(100, 5) }).quantity, 0, "held enough")
eq(P.buy({ itemID = 1, upTo = 10, maxUnit = 50 }, 0, { lv(100, 5) }).quantity, 0, "nothing cheap enough")
eq(P.buy({ itemID = 1, upTo = 10, maxUnit = 200 }, 0, { lv(100, 5, 5) }).quantity, 0, "never the player's own")

-- The profile string
local profile = {
	name = "Cloth seller", author = "Zulkara",
	sell = {
		{ itemID = 2592, keep = 200, price = { kind = "undercut", by = 1 }, floorPct = 80 },
		{ itemID = 13444, keep = 5, price = { kind = "fixed", unit = 70000, askIfMovedPct = 15 }, floorPct = 0 },
		{ itemID = 14047, keep = 0, price = { kind = "percentile", pct = 10 }, floorPct = 70 },
	},
	buy = { { itemID = 2589, upTo = 200, maxUnit = 300 } },
}
eq(P.text(profile), table.concat({ "name Cloth seller", "by Zulkara", "sell 2592 keep 200 undercut 1 floor 80", "sell 13444 keep 5 fixed 70000 ask 15 floor 0", "sell 14047 keep 0 percentile 10 floor 70", "buy 2589 upto 200 max 300" }, "\n"), "plain lines")
local str = P.encode(profile)
eq(str:sub(1, 5), "GFP1:", "the prefix")
eq(P.text(P.decode(str)), P.text(profile), "reads back what it wrote")
local function wrap(t) return "GFP1:" .. E.base64(t) end
eq(P.decode(wrap("name |cffff0000Free gold|r |Hitem:1|h\nby x")).name, "cffff0000Free goldr Hitem:1h", "escapes stripped")
local _, err = P.decode("hello")
eq(err:find("GFP1:", 1, true) ~= nil, true, "names the prefix")
_, err = P.decode("GFP1:!!!")
eq(err:find("damaged", 1, true) ~= nil, true, "damaged")
_, err = P.decode(wrap("name a\nsell 1 keep -5 undercut 1"))
eq(err:find("Line 2", 1, true) ~= nil, true, "names the line")
eq((P.decode(wrap("sell 1 keep 5 undercut 1 extra 3"))), nil, "an extra word")
eq((P.decode(wrap("sell 1 keep 5 percentile 101"))), nil, "over 100%")
eq((P.decode(wrap("buy 1 upto 5 max 99999999999999"))), nil, "too much copper")
eq((P.decode(wrap("rm 1 keep 5"))), nil, "an unknown rule")
eq(P.decode(wrap("sell 1 keep 5 undercut 1")).sell[1].floorPct, 0, "no floor is none")
eq(P.ruleFor(profile, 13444).keep, 5, "the rule for an item")

return checks()
