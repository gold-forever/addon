-- Views.lua: characters and rested XP, the ledger by source, and levelling, from saved rows.

local ns = {}
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
local V = ns.Views

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
local mine = V.rows(db, "money", 1)
eq(#mine, 3, "one character's rows")
eq(mine[1].t, 50, "still in time order")
local recent = V.rows(db, "money", 1, 100)
eq(#recent, 2, "one character's rows from a time on")
eq(recent[1].t, 100, "the row at the time itself is kept")
eq(#V.rows(db, "money", nil, 250), 1, "every character's rows from a time on")

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

-- The session HUD: no rates in the first minute, then gold, XP and kills an hour and the ding.
local early = V.sessionRates({ coin = 5000, xp = 900, killXp = 900, kills = 3 }, 30, 1000, 9000)
eq(early.rated, false, "no rate before a minute")
eq(early.goldPerHour, nil, "no gold an hour yet")
eq(early.total, 6000, "coin and loot")
eq(early.killsToLevel, 30, "kills to level: 9000 XP at 300 a kill")
local hour = V.sessionRates({ coin = 10000, xp = 30000, killXp = 24000, kills = 120 }, 1800, 20000, 45000)
eq(hour.goldPerHour, 60000, "30 silver in half an hour: 6 gold an hour")
eq(hour.xpPerHour, 60000, "XP an hour")
eq(hour.killsPerHour, 240, "kills an hour")
eq(hour.dingIn, 2700, "45k XP at 60k an hour: 45 minutes")
eq(V.sessionRates({ coin = 0, xp = 500 }, 600, 0, 0).dingIn, nil, "no ding at the level cap")
eq(V.short(12345), "12.3k", "thousands")
eq(V.short(2500000), "2.5m", "millions")
eq(V.short(240.4), "240", "whole below a thousand")

-- The Home page: bags by worth, most first, unpriced counted apart.
local worths = { [1] = 100, [2] = 5000, [3] = nil, [4] = 100 }
local list, total, unpriced = V.worthList({ [1] = 3, [2] = 2, [3] = 7, [4] = 3 }, function(id) return worths[id] end)
eq(#list, 3, "priced items listed")
eq(list[1].id, 2, "the most valuable first")
eq(list[2].id, 1, "ties by item id")
eq(total, 10600, "the total")
eq(unpriced, 7, "units without a price")
-- Where each sells best, when worth says (manual test run 001: "the better of auction and vendor" was vague).
local placed = V.worthList({ [1] = 1, [2] = 1 }, function(id) return 100, id == 1 and "auction" or "vendor" end)
eq(placed[1].where .. " " .. placed[2].where, "auction vendor", "where each sells best")
eq(V.dayStart(86400 * 3 + 5000), 86400 * 3, "the UTC day's start")

-- Across fights: a corpse looted after its fight closed is the kill its XP already counted.
do
  local pending, seen = {}, {}
  eq(V.creditKills(pending, 1, {}, seen, 100), 1, "killed; the fight closes before the loot")
  eq(V.creditKills(pending, 0, { "Creature-0-1-a" }, seen, 110), 0, "its corpse, looted late, is no second kill")
  -- Kill one, pull the next before looting, loot both in the second fight: two kills, not three.
  eq(V.creditKills(pending, 1, {}, seen, 200), 1, "the first fight")
  eq(V.creditKills(pending, 1, { "Creature-0-1-b", "Creature-0-1-c" }, seen, 215), 1, "the second fight with both corpses")
  eq(#pending, 0, "every XP kill has its corpse")
  -- A grey mob: no XP, a corpse, a kill.
  eq(V.creditKills(pending, 0, { "Creature-0-1-rat" }, seen, 300), 1, "a grey mob")
  -- A kill never looted is let go after MATCH_SECONDS: a later grey mob still counts.
  eq(V.creditKills(pending, 1, {}, seen, 400), 1, "killed, never looted")
  eq(V.creditKills(pending, 0, { "Creature-0-1-rat2" }, seen, 400 + V.MATCH_SECONDS + 1), 1, "a grey mob long after")
  eq(V.creditKills(pending, 0, { "Creature-0-1-rat2" }, seen, 900), 0, "a corpse looted again is no new kill")
  eq(V.creditKills(pending, 0, { "GameObject-0-1-chest" }, seen, 900), 0, "a chest is no kill")
end
eq(V.sessionRates({ coin = 0, xp = 900, killXp = 900, kills = 5, xpKills = 3 }, 30, 0, 9000).killsToLevel, 30, "XP a kill from the kills that gave XP")

-- Rares: one row a rare, how often seen, the last sighting's place and how, the latest first.
local rares = V.rares({
	{ t = 100, npc = "61", map = "1429", x = "412", y = "679", how = "nameplate" },
	{ t = 300, npc = "79", map = "1433", x = "100", y = "200", how = "minimap" },
	{ t = 200, npc = "61", map = "1429", x = "500", y = "600", how = "target" },
	{ t = 400, npc = "x" },
})
eq(#rares, 2, "two rares, a bad row left out")
eq(rares[1].npc, 79, "the latest first")
eq(rares[2].seen, 2, "seen twice")
eq(rares[2].how, "target", "the last sighting's way")
eq(rares[2].x, 500, "and place")

-- Auction sales: one character's or all, newest first, net of the cut, the deposit not counted.
local sales = V.sales({
	{ t = 100, char = 1, item = "Linen Cloth", qty = "20", price = "2000", deposit = "60", cut = "100" },
	{ t = 300, char = 2, item = "Wool Cloth", qty = "5", price = "5000", deposit = "0", cut = "250" },
	{ t = 200, char = 1, item = "Silk Cloth", qty = "1", price = "900", cut = "45" },
	{ t = 400, char = 1, item = "Bad", price = "x" },
}, 1, 0)
eq(sales.count, 2, "this character's sales, a bad row left out")
eq(sales.list[1].item, "Silk Cloth", "newest first")
eq(sales.gross, 2900, "gross")
eq(sales.cut, 145, "the cut")
eq(sales.net, 2755, "after the cut")
eq(V.sales({ { t = 100, char = 1, item = "A", price = "100", cut = "5" }, { t = 50, char = 2, item = "B", price = "10", cut = "1" } }, nil, 60).count, 1, "all characters, from a time")

-- The Inventory tab: filters by character, place, quality and text; totals follow them.
local chars = {
	a = { name = "Zerie", bags = { items = "2589*7" }, bank = { items = "2589*3;14047*1" } },
	b = { name = "Alt", mail = { items = "2589*20" } },
}
local function parse(s)
	local out = {}
	for id, n in string.gmatch(s or "", "(%d+)%*(%d+)") do out[tonumber(id)] = (out[tonumber(id)] or 0) + tonumber(n) end
	return out
end
local worthOf = { [2589] = 10, [14047] = 1000 }
local qualityOf = { [2589] = 1, [14047] = 2 }
local function inv(f) return V.inventory(chars, parse, function(id) return worthOf[id] end, function(id) return qualityOf[id] end, function(id) return id == 2589 and "Linen Cloth" or "Runecloth" end, f) end
local rows, t = inv()
eq(t.items .. "/" .. t.units .. "/" .. t.worth, "2/31/1300", "all: two items, 31 units, 1300c")
rows, t = inv({ char = "a" })
eq(t.units, 11, "one character")
rows, t = inv({ place = "bank" })
eq(t.units .. "/" .. t.worth, "4/1030", "the bank only")
rows, t = inv({ quality = 2 })
eq(#rows .. ":" .. rows[1].id, "1:14047", "green and better")
rows, t = inv({ query = "linen" })
eq(rows[1].where, "Alt 20 (mail), Zerie 3 (bank), Zerie 7 (bags)", "where it is held, sorted")
-- Soulbound units are worth what a vendor pays; Tradeable only leaves them out; equipped gear is its own
-- place, worth nothing here (owner's answers, 2026-10-24).
do
	local bc = { a = { name = "Zerie", bags = { items = "14047*3", bound = "14047*2" }, gear = { [1] = "14047", [5] = "2589", t = 1 } } }
	local function bi(f) return V.inventory(bc, parse, function() return 1000 end, function() return 2 end, function() return "x" end, f, function() return 10 end) end
	local r, tt = bi()
	eq(r[1].bound .. "/" .. tt.worth, "2/1020", "one tradeable at 1000, two bound at the vendor's 10")
	r, tt = bi({ tradeable = true })
	eq(tt.units .. "/" .. tt.worth, "1/1000", "tradeable only")
	r, tt = bi({ place = "gear" })
	eq(tt.units .. "/" .. tt.worth, "2/0", "equipped: listed, worth nothing")
	eq(#bi() , 1, "equipped gear is not in the default view")
end

-- The craft queue's plan: 20 Linen needed, 5 in the bags, 8 in the bank, none in the mail: 7 missing,
-- 3 in the guild bank, Alt holds 10: 3 from the guild, 4 from Alt, nothing to buy. 6 Wool, none anywhere:
-- buy 6.
do
	local plan = V.queuePlan({ [2589] = 20, [2592] = 6 },
		{ bags = { [2589] = 5 }, bank = { [2589] = 8 }, mail = {} }, { [2589] = 3 }, { [2589] = { { name = "Alt", total = 10 } } })
	eq(plan[1].id .. ":" .. plan[1].buy, "2592:6", "most to buy first")
	local l = plan[2]
	eq(l.bags .. "/" .. l.bank .. "/" .. l.guild .. "/" .. l.others[1].name .. " " .. l.others[1].n .. "/" .. l.buy, "5/8/3/Alt 4/0", "bags, bank, guild, Alt, nothing to buy")
	local enough = V.queuePlan({ [2589] = 4 }, { bags = { [2589] = 1 }, bank = { [2589] = 8 }, mail = {} }, {}, {})
	eq(enough[1].bank .. "/" .. enough[1].buy, "3/0", "only what is needed from the bank")
	local mailed = V.queuePlan({ [2589] = 10 }, { bags = {}, bank = { [2589] = 10 }, mail = { [2589] = 10 } }, {}, {})
	eq(mailed[1].bank .. "/" .. mailed[1].buy, "0/0", "the mail covers it: nothing from the bank")
	local some = V.queuePlan({ [2589] = 10 }, { bags = { [2589] = 2 }, bank = { [2589] = 10 }, mail = { [2589] = 5 } }, {}, {})
	eq(some[1].bank, 3, "the bank gives what the bags and mail leave")
end

-- A gold goal: 1,000g in 10 days with 640g now needs 36g a day.
local g = V.goal(0, 6400000, { gold = 10000000, by = 10 * 86400 })
eq(g.pct .. "/" .. g.left .. "/" .. g.daysLeft .. "/" .. g.perDay, "64/3600000/10/360000", "64%, 360g left, 36g a day")
eq(V.goal(0, 12000000, { gold = 10000000, by = 86400 }).reached, true, "reached")
eq(V.goal(0, 12000000, { gold = 10000000, by = 86400 }).pct, 100, "never over 100%")
local late = V.goal(2 * 86400, 100, { gold = 10000000, by = 86400 })
eq(tostring(late.late) .. tostring(late.perDay), "truenil", "past the date, not reached")

-- Elsewhere: the bank's and mailbox's items the auction house pays for, dearest first; no price, not shown.
do
  local function parse(text)
    local out = {}
    for id, n in string.gmatch(text or "", "(%d+)%*(%d+)") do out[tonumber(id)] = (out[tonumber(id)] or 0) + tonumber(n) end
    return out
  end
  local me = { bags = { items = "1*5" }, bank = { items = "2589*40+6948*1" }, mail = { items = "4306*3" } }
  local prices = { [1] = 999, [2589] = 30, [4306] = 500 }
  local e = V.elsewhere(me, parse, function(id) return prices[id] end, function(id) return "item " .. id end)
  eq(e.count, 2, "Linen in the bank and Silk in the mail; the bound Hearthstone has no price")
  eq(e.items[1].id, 4306, "the dearest first: 3 × 500")
  eq(e.items[2].place, "bank", "where it is")
  eq(e.total, 1500 + 1200, "their worth together")
  eq(V.elsewhere(nil, parse, function() return 1 end, tostring).count, 0, "no character, nothing")
end
-- Holdings: what every character holds of an item, most first, for the tooltip's Held line.
do
  local function parse(text)
    local out = {}
    for id, n in string.gmatch(text or "", "(%d+)%*(%d+)") do out[tonumber(id)] = (out[tonumber(id)] or 0) + tonumber(n) end
    return out
  end
  local chars = {
    a = { name = "Zerie", bags = { items = "2589*8+4306*1" }, bank = { items = "2589*2" } },
    b = { name = "Zeripala", mail = { items = "2589*2" } },
    c = { name = "Alt", bags = { items = "4306*3" } },
  }
  local index = V.holdings(chars, parse)
  eq(index[2589].total, 12, "every character's Linen")
  eq(index[2589].by[1].name, "Zerie", "the most first")
  eq(V.heldText(index[2589]), "Held 12: Zerie 10 (bags 8, bank 2), Zeripala 2 (mail)", "where each holds it")
  eq(V.heldText(index[4306]), "Held 4: Alt 3 (bags), Zerie 1 (bags)", "a place alone without its count")
  eq(V.heldText(index[2589], 1), "Held 12: Zerie 10 (bags 8, bank 2), +1 more", "at most so many characters")
  eq(V.heldText(index[9999]), nil, "nobody holds it")
end
do
	local e = V.elsewhere({ bank = { items = "2589*5", bound = "2589*5" }, mail = { items = "14047*1" } }, parse, function() return 100 end, function() return "x" end)
	eq(e.count .. "/" .. e.total, "1/100", "soulbound bank items are not for the auction house")
end

return checks()
