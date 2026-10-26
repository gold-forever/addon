-- HomeView.lua: Home's gold across the characters, today's money for this one, and what its bags would
-- sell for, from a save.

local DAY = 20 * 86400
local me = { ref = 1, money = 500, bags = { items = "14047*3+2589*4", bound = "2589*1" } }
local save = {
	fields = { money = "t,char,delta,ctx", flight = "t,char,from,to,cost,map" },
	characters = { A = me, B = { ref = 2, money = 250 }, C = { ref = 3 } },
	events = {
		["1970-01-21"] = {
			money = { (DAY + 100) .. ",1,30,loot;" .. (DAY + 200) .. ",1,-50,gossip;" .. (DAY + 300) .. ",2,999,loot" },
			flight = { (DAY + 201) .. ",1,4,2,50,1429" },
		},
		["1970-01-20"] = { money = { (DAY - 100) .. ",1,7000,loot" } },
	},
}
local ns = { db = function() return save end, me = function() return me end }
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
for _, file in ipairs({ "Views.lua", "ViewsMoney.lua", "ViewsSession.lua", "ViewsItems.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["HomeView.lua"], "@HomeView.lua"))("GoldForever", ns)
local H = ns.HomeView

local worth = function(id) return id == 14047 and 100 or nil end
local home = H.home(DAY + 500, worth)
eq(home.gold, 750, "gold across the characters")
eq(home.today.net, -20, "today's money, this character's, from the day's start")
eq(#home.today.categories, 2, "by where it came from")
eq(#home.bags.list, 1, "the priced bag items")
eq(home.bags.total, 300, "what they would sell for")
eq(home.bags.unpriced, 3, "the unpriced units, the soulbound left out")

me = nil
home = H.home(DAY + 500, worth)
eq(home.gold, 750, "no character yet: the gold still counted")
eq(#home.today.categories .. " " .. home.today.net, "0 0", "no money today")
eq(#home.bags.list, 0, "no bags")
return checks()
