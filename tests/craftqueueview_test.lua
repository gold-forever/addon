-- CraftQueueView.lua: the craft queue's guild bank and what the other characters hold, from a save.

local me = { name = "Zerie", faction = "Alliance", bags = { items = "2589*4" } }
local save = {
	guildBanks = {
		["EU-Realm-alliance:Gilde"] = { tabs = { { items = "2589*10+2592*1" }, { items = "2589*5" } } },
		["EU-Realm-horde:Gilde"] = { tabs = { { items = "2589*99" } } },
	},
	characters = {
		A = me,
		B = { name = "Zeripala", bags = { items = "2589*2" }, mail = { items = "2589*1+2592*3" } },
		C = { name = "Zerie", bank = { items = "2589*7+14047*9" } },
	},
}
local ns = {
	db = function() return save end,
	market = function(side) return "EU-Realm-" .. side end,
}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
assert(load(SOURCES["CraftQueueView.lua"], "@CraftQueueView.lua"))("GoldForever", ns)
local V = ns.CraftQueueView

local bank = V.guildCounts(me, "Gilde")
eq(bank[2589], 15, "the guild bank of this side's market, every tab counted")
eq(bank[2592], 1, "each item")
eq(next(V.guildCounts(me, nil)), nil, "no guild: nothing")
eq(next(V.guildCounts(nil, "Gilde")), nil, "no character: nothing")
eq(next(V.guildCounts(me, "Other")), nil, "a guild bank never read: nothing")

local others = V.others({ [2589] = true, [2592] = true }, me)
eq(#others[2589], 2, "the other characters holding a reagent, this one left out")
eq(others[2589][1].name .. " " .. others[2589][1].total, "Zerie 7", "most first: an alt of the same name is another character")
eq(others[2589][2].name .. " " .. others[2589][2].total, "Zeripala 3", "bags and mail together")
eq(others[2592][1].total, 3, "each reagent")
eq(others[14047], nil, "only the reagents asked for")
return checks()
