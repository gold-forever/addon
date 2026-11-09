-- The bag verdict: what to do with one bag item. SalePlan.verdict is the rule; BagVerdict.line its tooltip words.

local ns = { on = function() end, listen = function() end, module = function() end, throttle = function(_, _, f) return f end, price = {}, BagMark = {}, commands = {} }
loadEncode(ns)
assert(load(SOURCES["SalePlan.lua"], "@SalePlan.lua"))("GoldForever", ns)
assert(load(SOURCES["BagVerdict.lua"], "@BagVerdict.lua"))("GoldForever", ns)
local verdict, line = ns.SalePlan.verdict, ns.BagVerdict.line
local function coins(c) return c .. "c" end
local function item(over)
	local i = { worth = 120, where = "auction", vendor = 15, enchanting = 300 }
	for k, v in pairs(over or {}) do i[k] = v end
	return i
end

eq(verdict(item()).word, "post", "worth most after the cut on the auction house: post")
eq(line(verdict(item()), coins), "Verdict: post (AH 120c after the cut, vendor 15c)", "post's line")
eq(line(verdict(item({ vendor = false })), coins), "Verdict: post (AH 120c after the cut)", "no vendor price: only the AH")

local v = verdict(item({ worth = 15, where = "vendor" }))
eq(v.word, "vendor", "worth most to a vendor: vendor")
eq(line(v, coins), "Verdict: vendor (vendor 15c)", "vendor's line")

v = verdict(item({ disenchant = 200, skill = 100 }))
eq(v.word, "disenchant", "disenchanting beats the best sale")
eq(line(v, coins), "Verdict: disenchant (~200c, best sale 120c)", "disenchant's line")
eq(verdict(item({ disenchant = 120, skill = 100 })).word, "post", "a tie is sold, not disenchanted")
eq(verdict(item({ disenchant = 200, skill = 301 })).word, "post", "beyond this character's Enchanting: sold")
eq(line(verdict(item({ worth = false, where = false, vendor = false, disenchant = 5, skill = 1 })), coins), "Verdict: disenchant (~5c)", "no sale at all: only the disenchant")

for _, rule in ipairs({
	{ { quest = true }, "a quest item" },
	{ { listed = true }, "on a shopping list" },
	{ { queued = true }, "in the craft queue" },
	{ { bound = true, gear = true }, "soulbound gear" },
}) do
	v = verdict(item(rule[1]))
	eq(v.word, "keep", rule[2] .. ": keep")
	eq(line(v, coins), "Verdict: keep (" .. rule[2] .. ")", rule[2] .. ": its line")
	rule[1].disenchant, rule[1].skill = 500, 1
	eq(verdict(item(rule[1])).word, "keep", rule[2] .. ": keep, though disenchanting pays")
end

eq(verdict(item({ worth = false, where = false, vendor = false })).word, "keep", "no price at all: keep")
v = verdict(item({ bound = true }))
eq(v.word .. v.sale, "vendor15", "soulbound and not gear cannot be posted: the vendor, at the vendor's price")
eq(verdict(item({ bound = true, vendor = false })).word, "keep", "soulbound with no vendor price: keep")

return checks()
