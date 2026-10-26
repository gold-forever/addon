-- LedgerView.lua: the Ledger's tabs (money, characters, inventory, auction sales) from a save.

local NOW = 30 * 86400
local me = { ref = 1, name = "Testchar", level = 12, money = 500, xp = { cur = 0, max = 1000, rested = 0, t = NOW },
	bags = { items = "14047*3+2589*4", bound = "2589*1" } }
local save = {
	fields = { money = "t,char,delta,ctx", flight = "t,char,from,to,cost,map", sale = "t,char,item,qty,price,deposit,cut" },
	characters = { A = me, B = { ref = "2", name = "Alt", level = 20, money = 250, xp = { cur = 0, max = 2000, rested = 1000, t = NOW },
		bank = { items = "14047*2" } } },
	events = {
		["1970-01-30"] = {
			money = { (NOW - 100) .. ",1,30,loot;" .. (NOW - 90) .. ",2,-50,merchant" },
			sale = { (NOW - 50) .. ",1,Linen Cloth,5,1000,20,50;" .. (NOW - 40) .. ",2,Copper Ore,1,400,10,20" },
		},
		["1970-01-01"] = { money = { "100,1,7000,loot" }, sale = { "100,1,Old,1,9,0,0" } },
	},
}
local ns = { db = function() return save end, me = function() return me end }
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
assert(load(SOURCES["LedgerView.lua"], "@LedgerView.lua"))("GoldForever", ns)
local L = ns.LedgerView

-- Money: this character's or everyone's, over the days the save keeps, with the net a day.
local mine = L.money("me", NOW)
eq(mine.net, 30, "this character's money, the days the save keeps")
eq(mine.days["1970-01-30"], 30, "the net a day")
eq(L.money("all", NOW).net, -20, "every character's")

-- Characters: a row each, and the one to play next.
local rows, best = L.characters(NOW, "A")
eq(#rows, 2, "a row a character")
eq(best.name, "Alt", "the one to play next")

-- Inventory: the characters to choose from, and what they hold.
local names = {}
for _, c in ipairs(L.characterNames()) do
	names[#names + 1] = c.guid .. "=" .. c.name
end
table.sort(names)
eq(table.concat(names, " "), "A=Testchar B=Alt", "the characters to choose from")
local held, totals = L.inventory(function(id) return id == 14047 and 100 or nil end, function() return 1 end, function(id) return "item " .. id end,
	{ query = "" }, function() return 5 end)
eq(#held .. " " .. totals.units .. " " .. totals.worth, "2 9 " .. (5 * 100 + 3 * 0 + 1 * 5), "every place of every character, the bound at a vendor's price")
eq(#L.inventory(function() end, function() return 1 end, function(id) return "item " .. id end, { char = "B", query = "" }, nil), 1, "one character's")

-- Sales: this character's or everyone's, the save's days, and the characters' names by reference.
local sales, refs = L.sales("me", NOW)
eq(sales.count .. " " .. sales.gross .. " " .. sales.net, "1 1000 950", "this character's sales")
eq(L.sales("all", NOW).count, 2, "every character's")
eq(refs[1] .. " " .. refs[2], "Testchar Alt", "the names by reference, a string one as a number")
return checks()
