-- The bag verdict: what to do with one bag item. SalePlan.verdict is the rule; BagVerdict.line its tooltip words.

local ns = { on = function() end, listen = function() end, module = function() end, throttle = function(_, _, f) return f end, price = { cut = 0.05 }, BagMark = {}, commands = {} }
loadEncode(ns)
assert(load(SOURCES["SalePlan.lua"], "@SalePlan.lua"))("GoldForever", ns)
assert(load(SOURCES["Post.lua"], "@Post.lua"))("GoldForever", ns)
assert(load(SOURCES["BagVerdict.lua"], "@BagVerdict.lua"))("GoldForever", ns)
local verdict, line = ns.SalePlan.verdict, ns.BagVerdict.line
local function coins(c) return c .. "c" end
local function item(over)
	local i = { worth = 120, where = "auction", vendor = 15, enchanting = 300 }
	for k, v in pairs(over or {}) do i[k] = v end
	return i
end

eq(verdict(item()).word, "post", "worth most after the cut on the auction house: post")
eq(line(verdict(item()), coins, 410), "Post at 410c (you get 389c)", "post's line: the listing price and what arrives after the 5% cut")
eq(line(verdict(item({ vendor = false })), coins, 200), "Post at 200c (you get 190c)", "no vendor price: the same")

-- The listing price: what the Sell tab would post at against the last scan's cheapest, else the market value.
local cheapest, market = nil, 1000
ns.price.valued = function() return market, "market", nil, nil end
ns.price.cheapest = function() return cheapest end
ns.price.itemInfo = function() return 1, 10, 7 end
ns.Prices = { sellBase = function(value, from) return value, from end }
ns.auctionSettings = function() return { rule = ns.Post.DEFAULT, overrides = {} } end
local vendor, volatile, day = nil, false, nil
ns.price.vendor = function() return vendor end
ns.price.today = function() return volatile, day end
eq(ns.BagVerdict.listing(2589), 1200, "no listing in the last scan: the Sell tab's price alone, 120% of the market value")
day = 1500
eq(ns.BagVerdict.listing(2589), 1500, "alone with today's price above it: today's price, as the Sell tab")
day = nil
cheapest = 1050
eq(ns.BagVerdict.listing(2589), 900, "a listing in the scan: the Sell tab's undercut, to the silver")
cheapest = 4000
eq(ns.BagVerdict.listing(2589), 3000, "everyone above 3x the market value: the maximum")
volatile = true
eq(ns.BagVerdict.listing(2589), 3900, "a volatile item: the 5x maximum, so the undercut stands")
volatile = false
cheapest, vendor = 1050, 950
eq(ns.BagVerdict.listing(2589), 1000, "the undercut under the vendor floor after the cut: held, so the market value")
vendor = nil
cheapest = 500
eq(ns.BagVerdict.listing(2589), 1000, "held under the floor: the market value")
market = nil
eq(ns.BagVerdict.listing(2589), nil, "no market value: no listing price")

local v = verdict(item({ worth = 15, where = "vendor" }))
eq(v.word, "vendor", "worth most to a vendor: vendor")
eq(line(v, coins), "vendor (vendor 15c)", "vendor's line")

v = verdict(item({ disenchant = 200, skill = 100 }))
eq(v.word, "disenchant", "disenchanting beats the best sale")
eq(line(v, coins), "disenchant (~200c, best sale 120c)", "disenchant's line")
eq(verdict(item({ disenchant = 120, skill = 100 })).word, "post", "a tie is sold, not disenchanted")
eq(verdict(item({ disenchant = 200, skill = 301 })).word, "post", "beyond this character's Enchanting: sold")
eq(line(verdict(item({ worth = false, where = false, vendor = false, disenchant = 5, skill = 1 })), coins), "disenchant (~5c)", "no sale at all: only the disenchant")

for _, rule in ipairs({
	{ { quest = true }, "a quest item" },
	{ { listed = true }, "on a shopping list" },
	{ { queued = true }, "in the craft queue" },
	{ { bound = true, gear = true }, "soulbound gear" },
}) do
	v = verdict(item(rule[1]))
	eq(v.word, "keep", rule[2] .. ": keep")
	eq(line(v, coins), "keep (" .. rule[2] .. ")", rule[2] .. ": its line")
	rule[1].disenchant, rule[1].skill = 500, 1
	eq(verdict(item(rule[1])).word, "keep", rule[2] .. ": keep, though disenchanting pays")
end

eq(verdict(item({ worth = false, where = false, vendor = false })).word, "keep", "no price at all: keep")
v = verdict(item({ bound = true }))
eq(v.word .. v.sale, "vendor15", "soulbound and not gear cannot be posted: the vendor, at the vendor's price")
eq(verdict(item({ bound = true, vendor = false })).word, "keep", "soulbound with no vendor price: keep")

return checks()
