-- Catalogue.lua: every item a scan names reaches the catalogue. A retail scan names about 19,000 items
-- while the queue is draining; on the owner's first retail scan (2026-10-22) exactly half never did.
-- Each session, an item seen is read from the game again and its row rewritten, stamped with readAt
-- (schema 12, gf#392): a row carried from an earlier session is no evidence of today's price.

local lastDelay -- the seconds of the latest ns.after
local NOW = 1792600000 -- ns.now() in the session under test
local T = tostring(NOW)
local clock = 0 -- ns.frameStart()'s milliseconds; nil for a client without the timer
local timed = false

local asked = {} -- item ID -> how often its info was asked for
local links = {} -- item ID -> the link GetItemInfo answers (none by default)
local expansions = {} -- item ID -> the expansionID GetItemInfo answers (none by default)
GetItemInfo = function(id)
	asked[id] = (asked[id] or 0) + 1
	return "Item " .. id, links[id], 1, 1, 1, nil, nil, 20, "", 1, 1, 7, 5, 0, expansions[id]
end
C_TooltipInfo = {
	GetItemByID = function(id)
		return { lines = { { leftText = "Item " .. id }, { leftText = "Two-Hand", rightText = "Staff" } } }
	end,
}

-- Whether the player is fighting, and what waits for the fight's end (ns.afterCombat).
local fighting = false
local afterFight = {}
local function endFight()
	fighting = false
	local due = afterFight
	afterFight = {}
	for _, fn in ipairs(due) do
		fn()
	end
end

-- One session of the addon on the saved table db: Catalogue.lua loaded afresh, its timers in `tick`.
local function session(db, lean)
	local scheduled = {}
	local handlers = {} -- event -> its handlers, for ns.fire
	local catalogueModule
	local ns = {
		lean = lean,
		retail = lean,
		db = function()
			return db
		end,
		after = function(seconds, _, fn)
			lastDelay = seconds
			scheduled[#scheduled + 1] = fn
		end,
		safely = function(_, fn, ...)
			return fn(...)
		end,
		on = function(event, _, fn)
			handlers[event] = handlers[event] or {}
			table.insert(handlers[event], fn)
		end,
		module = function(_, def)
			catalogueModule = def
		end,
		inCombat = function()
			return fighting
		end,
		now = function()
			return NOW
		end,
		frameStart = function()
			return timed and clock or nil
		end,
		afterCombat = function(_, fn)
			if fighting then
				afterFight[#afterFight + 1] = fn
			else
				fn()
			end
		end,
	}
	loadEncode(ns)
	assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
	assert(load(SOURCES["Migrations.lua"], "@Migrations.lua"))("GoldForever", ns)
	assert(load(SOURCES["Catalogue.lua"], "@Catalogue.lua"))("GoldForever", ns)
	-- The game firing an event.
	ns.fire = function(event, ...)
		for _, fn in ipairs(handlers[event] or {}) do
			fn(...)
		end
	end
	-- The game enabling the module at login.
	ns.enableCatalogue = function()
		catalogueModule.enable()
	end
	-- Runs the earliest scheduled callback, as the game's timer would.
	local function tick()
		local fn = table.remove(scheduled, 1)
		if fn then
			fn()
		end
		return fn ~= nil
	end
	return ns, tick
end

local function count(t)
	local n = 0
	for _ in pairs(t) do
		n = n + 1
	end
	return n
end

-- A scan reads its listings in batches, and the queue drains between them.
local db = { catalogue = { items = {}, tooltips = {} } }
local ns, tick = session(db, false)
local N = 5000
local id = 100000
for _ = 1, N / 250 do
	for _ = 1, 250 do
		id = id + 1
		ns.catalogueItem(id)
	end
	tick()
end
while tick() do
end

local catalogued = 0
for i = 100001, 100000 + N do
	if asked[i] == 1 then
		catalogued = catalogued + 1
	end
end
eq(catalogued, N, "items catalogued after a scan named them while the queue drained")
eq(count(db.catalogue.items), N, "a row for each in the saved catalogue")
eq(count(db.catalogue.tooltips), N, "and its tooltip")
eq(db.catalogue.items[100001], "Item 100001,1,1,7,5,20,1,0,1,1,," .. T, "the item's row, read now")
eq(db.catalogue.tooltips[100001], "Item 100001\nTwo-Hand\tStaff", "the item's tooltip")

-- Asked again in the same session: nothing queued, nothing asked.
ns.catalogueItem(100001)
while tick() do
end
eq(asked[100001], 1, "an item catalogued is not asked for again")

-- The next session on the same save: an item seen is read again, its row rewritten with this session's
-- readAt, even with its row and tooltip kept; an item not seen keeps its row as it was.
db.catalogue.tooltips[100002] = nil
db.catalogue.items[100001] = "Item 100001,1,1,7,5,20,960,0,1,1,,1780000000" -- a beta-era price, carried
NOW = NOW + 86400
local T2 = tostring(NOW)
ns, tick = session(db, false)
ns.catalogueItem(100001)
ns.catalogueItem(100002)
ns.catalogueItem(100001)
while tick() do
end
eq(asked[100001], 2, "next session: a catalogued item seen is asked for again, once")
eq(db.catalogue.items[100001], "Item 100001,1,1,7,5,20,1,0,1,1,," .. T2, "and rewritten from the game: today's price and readAt")
eq(asked[100002], 2, "next session: an item without its tooltip is asked for")
eq(db.catalogue.tooltips[100002], "Item 100002\nTwo-Hand\tStaff", "and its tooltip is written")
eq(db.catalogue.items[100003], "Item 100003,1,1,7,5,20,1,0,1,1,," .. T, "an item not seen this session keeps its row and its readAt")
NOW = NOW - 86400

-- A lean (retail) save keeps rows and no tooltips: a row is enough.
local leanDb = { catalogue = { items = {}, tooltips = {} } }
ns, tick = session(leanDb, true)
ns.catalogueItem(200001)
ns.catalogueItem("200002:612")
while tick() do
end
eq(leanDb.catalogue.items[200001], "Item 200001,1,1,7,5,20,1,0,1,1,,,," .. T, "lean: the item's row, readAt after tier and expansion")
eq(leanDb.catalogue.items[200002] ~= nil, true, "lean: an item key's item")
eq(count(leanDb.catalogue.tooltips), 0, "lean: no tooltips kept")
ns.catalogueItem(200001)
while tick() do
end
eq(asked[200001], 1, "lean: an item catalogued is not asked for again")
leanDb.catalogue.items[200001] = leanDb.catalogue.items[200001] .. ",,10"
ns, tick = session(leanDb, true)
ns.catalogueItem(200001)
while tick() do
end
eq(asked[200001], 2, "lean, next session: an item seen is read again, though a lean save keeps no tooltip")

-- Columns read by name (ns.FIELDS), not by place.
local rowsDb = { catalogue = { items = { [7] = "Linen Cloth,1,5,7,5,20,13", [8] = ",3,5", [9] = "Odd" }, npcs = { [42] = "Hogger,9,11,elite" }, tooltips = {} } }
ns = session(rowsDb, true)
local C = ns.Catalogue
eq(C.name("item", 7), "Linen Cloth", "an item's name")
eq(C.quality(7), 1, "an item's quality, a number")
eq(C.name("npc", 42), "Hogger", "an NPC's name")
eq(C.name("item", 8), nil, "an empty name is none")
eq(C.quality(8), 3, "the quality of a row without a name")
eq(C.quality(9), nil, "a row too short for the column")
eq(C.name("item", 10), nil, "an item not catalogued")
eq(C.name("object", 1), nil, "a kind the save has no section for")

-- A retail item's crafting-quality tier, after equipLoc: from C_TradeSkillUI, or from the quality markup in
-- its link when the API answers nothing. Without either (Forever) the row ends at equipLoc, as before.
local ROW = "Item %d,1,1,7,5,20,1,0,1,1,"
local TIER2 = "|cff1eff00|Hitem:%d::::::::80|h[Item %d |A:Professions-ChatIcon-Quality-Tier2:17:15::1|a]|h|r"
local PLAIN = "|cff1eff00|Hitem:%d::::::::80|h[Item %d]|h|r"
local function catalogued(id, api, link)
	C_TradeSkillUI = api
	links[id] = link and string.format(link, id, id)
	local tierDb = { catalogue = { items = {}, tooltips = {} } }
	local tierNs, tierTick = session(tierDb, true)
	tierNs.catalogueItem(id)
	while tierTick() do
	end
	C_TradeSkillUI = nil
	return tierDb.catalogue.items[id]
end
local answers = { [300001] = 3, [300004] = 1 }
local retail = { GetItemReagentQualityByItemInfo = function(id) return answers[id] end }
local failing = { GetItemReagentQualityByItemInfo = function() error("no such item") end }

eq(catalogued(300001, retail, PLAIN), string.format(ROW, 300001) .. ",3,," .. T, "retail: the API's tier after equipLoc")
eq(catalogued(300002, retail, PLAIN), string.format(ROW, 300002) .. ",,," .. T, "retail: an untiered item has no tier column")
eq(catalogued(300003, retail, TIER2), string.format(ROW, 300003) .. ",2,," .. T, "retail: the link's markup when the API answers nil")
eq(catalogued(300004, retail, TIER2), string.format(ROW, 300004) .. ",1,," .. T, "the API's answer before the link's")
eq(catalogued(300005, nil, nil), string.format(ROW, 300005) .. ",,," .. T, "Forever: no C_TradeSkillUI and no link, no tier")
eq(catalogued(300006, {}, PLAIN), string.format(ROW, 300006) .. ",,," .. T, "Forever: C_TradeSkillUI without the call, no tier")
eq(catalogued(300007, nil, TIER2), string.format(ROW, 300007) .. ",2,," .. T, "no API: the link's markup still counts")
eq(catalogued(300008, failing, PLAIN), string.format(ROW, 300008) .. ",,," .. T, "an API that errors: no error, no tier")
eq(catalogued(300009, failing, TIER2), string.format(ROW, 300009) .. ",2,," .. T, "an API that errors: the link's markup")
eq(catalogued(300010, { GetItemReagentQualityByItemInfo = function() return "x" end }, PLAIN), string.format(ROW, 300010) .. ",,," .. T,
	"an answer that is not a tier is none")
eq(ns.FIELDS.item:match(",([^,]*),([^,]*),([^,]*)$"), "tier", "retail: tier, expansion, readAt end the item columns")
eq(ns.FIELDS.item:match(",([^,]*),[^,]*$"), "expansion", "retail: expansion is the last but one")
eq(ns.FIELDS.item:match(",([^,]*)$"), "readAt", "retail: readAt is the last")

-- A crafted item (gear, a consumable) answers GetItemCraftedQualityByItemInfo, 1–5; a reagent answers the
-- reagent call, 1–3.
local craftedAnswers = { [300012] = 5 }
local both = {
	GetItemReagentQualityByItemInfo = function(id) return answers[id] end,
	GetItemCraftedQualityByItemInfo = function(id) return craftedAnswers[id] end,
}
eq(catalogued(300012, both, PLAIN), string.format(ROW, 300012) .. ",5,," .. T, "retail: a crafted item's tier")
eq(catalogued(300001, both, PLAIN), string.format(ROW, 300001) .. ",3,," .. T, "retail: a reagent's tier")
eq(catalogued(300002, both, PLAIN), string.format(ROW, 300002) .. ",,," .. T, "retail: an item without tiers has none")

-- Never in combat: an item named in a fight is catalogued, its tier with it, once the fight ends.
fighting = true
C_TradeSkillUI = both
local fightDb = { catalogue = { items = {}, tooltips = {} } }
local fightNs, fightTick = session(fightDb, true)
fightNs.catalogueItem(300012)
while fightTick() do
end
eq(fightDb.catalogue.items[300012], nil, "in combat: nothing is read")
endFight()
while fightTick() do
end
C_TradeSkillUI = nil
eq(fightDb.catalogue.items[300012], string.format(ROW, 300012) .. ",5,," .. T, "after the fight: the row and its tier")

-- Forever: no tier column declared, and none written even where the client would answer one.
C_TradeSkillUI = retail
links[300011] = string.format(TIER2, 300011, 300011)
local foreverDb = { catalogue = { items = {}, tooltips = {} } }
ns, tick = session(foreverDb, false)
ns.catalogueItem(300001)
ns.catalogueItem(300011)
while tick() do
end
C_TradeSkillUI = nil
eq(ns.FIELDS.item:match(",([^,]*,[^,]*)$"), "equipLoc,readAt", "Forever: the schema's item columns end with equipLoc, readAt")
eq(foreverDb.catalogue.items[300001], string.format(ROW, 300001) .. "," .. T, "Forever: no tier from the API")
eq(foreverDb.catalogue.items[300011], string.format(ROW, 300011) .. "," .. T, "Forever: no tier from the link")

-- A retail item's expansion, GetItemInfo's 15th return, after tier: 0 is Classic, and a value the server would
-- not store (the 254 the client's docs give for Classic clients) is none.
expansions[500001], expansions[500002], expansions[500003], expansions[500004] = 10, 10, 0, 99
expansions[500005], expansions[500006], expansions[500007], expansions[500008] = 254, 100, 1.5, "x"
expansions[500009] = -1
local reagent = { GetItemReagentQualityByItemInfo = function(id) return id == 500002 and 3 or nil end }
eq(catalogued(500001, nil, nil), string.format(ROW, 500001) .. ",,10," .. T, "retail: an untiered item's expansion, its tier column empty")
eq(catalogued(500002, reagent, nil), string.format(ROW, 500002) .. ",3,10," .. T, "retail: the expansion after the tier")
eq(catalogued(500003, nil, nil), string.format(ROW, 500003) .. ",,0," .. T, "retail: expansion 0 is written")
eq(catalogued(500004, nil, nil), string.format(ROW, 500004) .. ",,99," .. T, "retail: the server's highest")
for id = 500005, 500009 do
	eq(catalogued(id, nil, nil), string.format(ROW, id) .. ",,," .. T, "retail: not an expansion, nothing written: " .. tostring(expansions[id]))
end

local foreverExpansion = { catalogue = { items = {}, tooltips = {} } }
ns, tick = session(foreverExpansion, false)
ns.catalogueItem(500001)
while tick() do
end
eq(foreverExpansion.catalogue.items[500001], string.format(ROW, 500001) .. "," .. T, "Forever: no expansion even where the client answers one")

-- Forever too: an item named in a fight is read once it ends (an AH scan's thousands never stutter a fight).
fighting = true
local foreverFightDb = { catalogue = { items = {}, tooltips = {} } }
local foreverFightNs, foreverFightTick = session(foreverFightDb, false)
foreverFightNs.catalogueItem(300013)
while foreverFightTick() do
end
eq(foreverFightDb.catalogue.items[300013], nil, "Forever, in combat: nothing is read")
endFight()
while foreverFightTick() do
end
eq(foreverFightDb.catalogue.items[300013], string.format(ROW, 300013) .. "," .. T, "Forever, after the fight: the row")

-- A frame budget: a batch stops once its milliseconds are spent, and the rest follows in the next one.
timed = true
local budgetDb = { catalogue = { items = {}, tooltips = {} } }
local realInfo = GetItemInfo
GetItemInfo = function(...)
	clock = clock + 1 -- each read costs a millisecond
	return realInfo(...)
end
local budgetNs, budgetTick = session(budgetDb, false) -- after the stand-in: Catalogue.lua keeps the one it loads with
for n = 1, 10 do
	budgetNs.catalogueItem(310000 + n)
end
eq(count(budgetDb.catalogue.items), 1, "the first item at once; the rest named meanwhile wait for the queue")
budgetTick()
eq(count(budgetDb.catalogue.items), 3, "the next batch stops at its 2 ms: two more")
while budgetTick() do
end
eq(count(budgetDb.catalogue.items), 10, "the rest in the next batches")
GetItemInfo = realInfo
timed = false

-- Rows catalogued before a column (a retail row without tier or expansion, before schema 9, addon#72; the
-- test save had 25,121 rows and not one tier) are read again after login, in the queue, and rewritten whole.
local OLD = "Azeroot,1,1,7,5,20,1,0,1,1,INVTYPE_NON_EQUIP_IGNORE"
local function oldSave()
	return { catalogue = { items = {
		[400001] = OLD, -- a reagent
		[400002] = OLD, -- a crafted item
		[400004] = "Old,1,1,7,5,20,1,0,1", -- a row from before minLevel and equipLoc
		[400006] = OLD .. ",1,9," .. T, -- read this way already
	}, tooltips = {} } }
end
C_TradeSkillUI = both
answers[400001], craftedAnswers[400002], expansions[400002] = 2, 5, 9
local oldDb = oldSave()
local oldNs, oldTick = session(oldDb, true)
oldNs.enableCatalogue()
while oldTick() do
end
eq(oldDb.catalogue.items[400001], string.format(ROW, 400001) .. ",2,," .. T, "old retail row, after login: rewritten, its tier and readAt")
eq(oldDb.catalogue.items[400002], string.format(ROW, 400002) .. ",5,9," .. T, "a crafted item's: its tier and expansion")
eq(oldDb.catalogue.items[400004], string.format(ROW, 400004) .. ",,," .. T, "a short row: rewritten whole")
eq(oldDb.catalogue.items[400006], OLD .. ",1,9," .. T, "a row read since: not asked at login")
eq(asked[400006], nil, "and its info not asked")

-- Never in combat.
fighting = true
local combatDb = oldSave()
local combatNs, combatTick = session(combatDb, true)
combatNs.enableCatalogue()
while combatTick() do
end
eq(combatDb.catalogue.items[400001], OLD, "in combat: nothing asked")
endFight()
while combatTick() do
end
eq(combatDb.catalogue.items[400001], string.format(ROW, 400001) .. ",2,," .. T, "after the fight: the row")
C_TradeSkillUI = nil

-- Forever: an old row seen gets readAt, never a tier or an expansion column.
local foreverOld = oldSave()
for id in pairs(foreverOld.catalogue.items) do
	foreverOld.catalogue.tooltips[id] = "kept"
end
C_TradeSkillUI = both
local fNs, fTick = session(foreverOld, false)
fNs.enableCatalogue()
while fTick() do
end
eq(foreverOld.catalogue.items[400002], OLD, "Forever, after login, no ticker: a row with its tooltip is not queued")
fNs.catalogueItem(400001)
while fTick() do
end
eq(foreverOld.catalogue.items[400001], string.format(ROW, 400001) .. "," .. T, "Forever: an old row seen is rewritten, no tier")
C_TradeSkillUI = nil

-- The background re-read (gf#392): every row without readAt is read once, one each PASS on a ticker, out of
-- combat and while neither the auction house nor a profession window is open; where it stands is saved
-- (reread.after, then reread.done), so the next session goes on from there and no item is read twice.
local tickers = {}
C_Timer = {
	NewTicker = function(seconds, fn)
		local t = { every = seconds, fn = fn }
		function t:Cancel()
			self.cancelled = true
		end
		tickers[#tickers + 1] = t
		return t
	end,
}
-- One beat of every ticker still running; false when none is.
local function beat()
	local any = false
	for _, t in ipairs(tickers) do
		if not t.cancelled then
			any = true
			t.fn()
		end
	end
	return any
end
local function rereadSave(n, from)
	local items, tooltips = {}, {}
	for k = 1, n do
		items[from + k] = "Old " .. k .. ",1,1,7,5,20,99,0,1,1,"
		tooltips[from + k] = "kept" -- no tooltip backfill: only the re-read
	end
	return { catalogue = { items = items, tooltips = tooltips } }
end
local function withReadAt(db)
	local n = 0
	for _, row in pairs(db.catalogue.items) do
		if string.match(row, "," .. T .. "$") then
			n = n + 1
		end
	end
	return n
end
local function readRows(n, from, db)
	for k = 1, n do
		db.catalogue.items[from + k] = "Read,1,1,7,5,20,1,0,1,1,,1790000000"
		db.catalogue.tooltips[from + k] = "kept"
	end
	return db
end
-- A session at login: the backfill's turn, then the re-read's start (its first item).
local function login(db)
	tickers = {}
	local s, t = session(db, false)
	s.enableCatalogue()
	t()
	t()
	return s, t
end

-- Pacing: one item a beat, four beats a second.
local paceDb = rereadSave(5, 710000)
login(paceDb)
local reads = { withReadAt(paceDb) }
for _ = 1, 4 do
	beat()
	reads[#reads + 1] = withReadAt(paceDb)
end
eq(table.concat(reads, " "), "1 2 3 4 5", "one item a beat, the first at the start")
eq(tickers[1].every, 0.25, "a beat every quarter second: four items a second")
beat()
eq(paceDb.reread and paceDb.reread.done, true, "once every row is read: done, saved")
eq(paceDb.reread.after, nil, "and the place dropped")
eq(beat(), false, "and the ticker stopped")
eq(paceDb.catalogue.items[710001], "Item 710001,1,1,7,5,20,1,0,1,1,," .. T, "a row re-read from the game, readAt stamped")

-- Rows already read are skipped, a bounded number a beat: without the client's timer, 200.
local skipDb = readRows(300, 720000, rereadSave(3, 720300))
login(skipDb)
eq(withReadAt(skipDb), 0, "the start checks 200 rows already read and reads none")
beat()
eq(withReadAt(skipDb), 1, "the next beat reaches the first row without readAt")

-- With the timer: a beat stops checking once its millisecond is spent (each check costs 0.015 ms here).
timed = true
local frameDb = readRows(300, 730000, rereadSave(1, 730300))
local realGsub = string.gsub
string.gsub = function(...)
	clock = clock + 0.015
	return realGsub(...)
end
login(frameDb)
local steps = 1
while withReadAt(frameDb) == 0 and steps < 10 do
	beat()
	steps = steps + 1
end
string.gsub = realGsub
timed = false
eq(steps, 5, "67 checks a beat: four beats skip the 300 rows read, the fifth reads (200 a beat without the timer)")

-- Paused while the auction house or a profession window is open, and never in combat.
local busyDb = rereadSave(4, 740000)
tickers = {}
local busyNs, busyTick = session(busyDb, false)
busyNs.enableCatalogue()
busyTick()
busyNs.fire("AUCTION_HOUSE_SHOW")
busyTick()
beat()
beat()
eq(withReadAt(busyDb), 0, "the auction house open: nothing read")
busyNs.fire("AUCTION_HOUSE_CLOSED")
beat()
eq(withReadAt(busyDb), 1, "closed: the re-read goes on")
busyNs.fire("TRADE_SKILL_SHOW")
beat()
eq(withReadAt(busyDb), 1, "a profession window open: nothing read")
busyNs.fire("TRADE_SKILL_CLOSE")
beat()
eq(withReadAt(busyDb), 2, "closed: on again")
fighting = true
beat()
eq(withReadAt(busyDb), 2, "in combat: nothing read")
endFight()
beat()
eq(withReadAt(busyDb), 3, "after the fight: on again")

-- Resume: a session that ends partway leaves its place; the next goes on after it, and an item the game
-- never answered is not asked again.
local resumeDb = rereadSave(4, 750000)
local realInfo2 = GetItemInfo
GetItemInfo = function(id)
	if id == 750002 then
		asked[id] = (asked[id] or 0) + 1
		return nil -- never loads (no Item API in this stand-in)
	end
	return realInfo2(id)
end
login(resumeDb)
beat()
eq(resumeDb.reread.after, 750002, "two taken, the place saved")
eq(withReadAt(resumeDb), 1, "750001 read; 750002 asked, no answer")
login(resumeDb) -- logout, login
eq(withReadAt(resumeDb), 2, "next session: on after the place")
beat()
beat()
GetItemInfo = realInfo2
eq(asked[750002], 1, "the unanswered item is not asked again")
eq(withReadAt(resumeDb), 3, "the rest read")
eq(resumeDb.reread.done, true, "and the re-read done")
local askedBefore = asked[750001]
login(resumeDb)
eq(beat(), false, "a session after it is done starts no ticker")
eq(asked[750001], askedBefore, "and reads nothing again")
C_Timer = nil

return checks()
