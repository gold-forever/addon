-- Views.lua: characters and rested XP, the ledger by source, and levelling, from saved rows.

local ns = {}
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
local V = ns.Views

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

-- Rows: each saved day's chunks, by the declared columns, empty ones nil, in time order.
local db = {
	fields = { money = "t,char,delta,ctx", flight = "t,char,from,to,cost,map" },
	events = {
		["2026-10-20"] = { money = { "200,1,-50,gossip;100,1,30,loot", "300,2,25," }, flight = { "201,1,4,2,50,1429" } },
		["2026-10-19"] = { money = { "50,1,-10,merchant" } },
	},
}
local money = V.rows(db, "money")
eq(#money, 4, "every row of every day")
eq(money[1].t, 50, "in time order")
eq(money[2].ctx, "loot", "by column name")
eq(money[4].ctx, nil, "an empty column is nil")
eq(money[4].char, 2, "the character as a number")

-- Rested: as read when online, grown by the inn rule since the save, never past 1.5 levels.
local xp = { cur = 100, max = 1000, rested = 200, resting = 1, t = 0 }
eq(V.rested(xp, 8 * 3600, true), 200, "online: as read")
eq(V.rested(xp, 8 * 3600, false), 250, "5% of a level per 8 hours at an inn")
eq(V.rested({ cur = 0, max = 1000, rested = 200, t = 0 }, 8 * 3600, false), 212.5, "a quarter of that elsewhere")
local rested, cap = V.rested(xp, 1000 * 3600, false)
eq(rested, 1500, "capped")
eq(cap, 1500, "the cap is 1.5 levels")
eq(V.rested(nil, 0, false), 0, "at the level cap: none")

-- Characters: the one to play next has the most rested waiting, and is not the one online.
local rows, best = V.characters({
	A = { name = "Jemmou", level = 12, money = 500, xp = { cur = 0, max = 1000, rested = 900, t = 0 } },
	B = { name = "Testchar", level = 20, money = 100, xp = { cur = 500, max = 2000, rested = 200, resting = 1, t = 0 }, seen = 0 },
	C = { name = "Cap", level = 60, money = 9 },
}, 0, "A")
eq(#rows, 3, "a row each")
eq(best.name, "Testchar", "the one online is left out")
eq(best.restedLevels, 0.1, "rested in levels")
local named = {}
for _, r in ipairs(V.characters({
	A = { name = "Testchar", surname = "Raine", realm = "PvE" },
	B = { name = "Testchar", realm = "PvE" },
	C = { name = "Testchar", realm = "PvP" },
}, 0, nil)) do
	named[r.guid] = r.display
end
eq(named.A, "Testchar Raine", "the surname tells them apart")
eq(named.B .. " / " .. named.C, "Testchar · PvE / Testchar · PvP", "else the realm")
local _, none = V.characters({ C = { name = "Cap", level = 60 } }, 0, nil)
eq(none, nil, "none to play next at the cap")

-- Ledger: by the windows open, a flight by its cost a moment after, one character or all.
eq(V.category("gossip+mail+merchant"), "vendor", "the merchant over the mail")
eq(V.category("loot"), "loot", "loot")
eq(V.category("auctioneer+mailinfo"), "auction", "the auction house over the mail")
eq(V.category(nil), "other", "no window")
local flights = V.rows(db, "flight")
local ledger = V.ledger(money, flights, 1, 0, function(t) return t < 100 and "19" or "20" end)
local by = {}
for _, c in ipairs(ledger.categories) do
	by[c.key] = c
end
eq(by.travel and by.travel.spent, 50, "a flight's cost within seconds is travel")
eq(by.loot.gained, 30, "loot in")
eq(by.vendor.net, -10, "a purchase out")
eq(ledger.gained .. " " .. ledger.spent .. " " .. ledger.net, "30 60 -30", "totals")
eq(ledger.days["20"], -20, "net by day")
eq(V.ledger(money, flights, nil, 0).gained, 55, "all characters")
eq(V.ledger(money, flights, 1, 150).spent, 50, "since a time")
local other = V.ledger(V.rows({ fields = db.fields, events = { d = { money = { "200,1,-40,gossip" } } } }, "money"), flights, 1, 0)
eq(other.categories[1].key, "other", "a payment of another amount than the flight's stays other")

-- Levelling: a level lasts from its start (played - levelPlayed) to the next one's.
local levelRows = V.rows({
	fields = { level = "t,char,kind,level,played,levelPlayed,money,map,x,y" },
	events = { d = { level = { "1000,1,up,5,3600,1,800;5000,1,login,6,7200,3000,900;6000,1,up,7,8000,2,1200;10,2,up,9,1,1," } } },
}, "level")
local lv = V.levelling(levelRows, {}, 1)
eq(#lv.levels, 3, "three levels of this character")
eq(lv.levels[1].level, 7, "newest first")
eq(lv.levels[1].seconds, nil, "the current level has no end yet")
eq(lv.levels[2].seconds, 8000 - 2 - (7200 - 3000), "level 6 from its start to level 7's")
eq(lv.levels[3].seconds, 4200 - 3599, "level 5")
eq(lv.levels[1].money, 1200, "gold when reached")

local xpRows = V.rows({
	fields = { xp = "t,char,xp,kind,rested,instance,map,level,x,y" },
	events = { d = { xp = { "0,1,100,kill,50;300,1,200,quest;600,1,100,kill;5000,1,300,kill;5300,1,50,explore;9,2,999,kill" } } },
}, "xp")
lv = V.levelling({}, xpRows, 1)
eq(lv.xp, 750, "XP of this character")
eq(lv.sources.kill, 500, "by kind")
eq(lv.rested, 50, "of it rested bonus")
eq(lv.playSeconds, 900, "time between gains, gaps over ten minutes left out")
eq(lv.perHour, 3000, "XP an hour of play")

-- Time as people say it.
eq(V.duration(59), "under a minute", "seconds")
eq(V.duration(45 * 60), "45m", "minutes")
eq(V.duration(3 * 3600 + 12 * 60), "3h 12m", "hours")
eq(V.duration(2 * 86400 + 4 * 3600 + 5), "2d 4h", "days")
eq(V.ago(100, 130), "now", "just now")
eq(V.ago(0, 3 * 3600 + 1800), "3h ago", "hours ago, whole")
eq(V.ago(0, 2 * 86400 + 7200), "2d ago", "days ago, whole")

return checks
