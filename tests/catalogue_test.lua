-- Catalogue.lua: every item a scan names reaches the catalogue. A retail scan names about 19,000 items
-- while the queue is draining; on the owner's first retail scan (2026-10-22) exactly half never did.

local asked = {} -- item ID -> how often its info was asked for
local links = {} -- item ID -> the link GetItemInfo answers (none by default)
GetItemInfo = function(id)
	asked[id] = (asked[id] or 0) + 1
	return "Item " .. id, links[id], 1, 1, 1, nil, nil, 20, "", 1, 1, 7, 5, 0
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
	local ns = {
		lean = lean,
		retail = lean,
		db = function()
			return db
		end,
		after = function(_, _, fn)
			scheduled[#scheduled + 1] = fn
		end,
		safely = function(_, fn, ...)
			return fn(...)
		end,
		on = function() end,
		module = function() end,
		inCombat = function()
			return fighting
		end,
		afterCombat = function(_, fn)
			if fighting then
				afterFight[#afterFight + 1] = fn
			else
				fn()
			end
		end,
	}
	assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
	assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
	assert(load(SOURCES["Migrations.lua"], "@Migrations.lua"))("GoldForever", ns)
	assert(load(SOURCES["Catalogue.lua"], "@Catalogue.lua"))("GoldForever", ns)
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
eq(db.catalogue.items[100001], "Item 100001,1,1,7,5,20,1,0,1,1,", "the item's row")
eq(db.catalogue.tooltips[100001], "Item 100001\nTwo-Hand\tStaff", "the item's tooltip")

-- Asked again in the same session: nothing queued, nothing asked.
ns.catalogueItem(100001)
while tick() do
end
eq(asked[100001], 1, "an item catalogued is not asked for again")

-- The next session on the same save: an item with its row and tooltip is not asked for; one with a row
-- and no tooltip (catalogued before 0.4.0) is.
db.catalogue.tooltips[100002] = nil
ns, tick = session(db, false)
ns.catalogueItem(100001)
ns.catalogueItem(100002)
while tick() do
end
eq(asked[100001], 1, "next session: a catalogued item is not asked for")
eq(asked[100002], 2, "next session: an item without its tooltip is")
eq(db.catalogue.tooltips[100002], "Item 100002\nTwo-Hand\tStaff", "and its tooltip is written")

-- A lean (retail) save keeps rows and no tooltips: a row is enough.
local leanDb = { catalogue = { items = {}, tooltips = {} } }
ns, tick = session(leanDb, true)
ns.catalogueItem(200001)
ns.catalogueItem("200002:612")
while tick() do
end
eq(leanDb.catalogue.items[200001], "Item 200001,1,1,7,5,20,1,0,1,1,", "lean: the item's row")
eq(leanDb.catalogue.items[200002] ~= nil, true, "lean: an item key's item")
eq(count(leanDb.catalogue.tooltips), 0, "lean: no tooltips kept")
ns.catalogueItem(200001)
while tick() do
end
eq(asked[200001], 1, "lean: an item catalogued is not asked for again")
ns, tick = session(leanDb, true)
ns.catalogueItem(200001)
while tick() do
end
eq(asked[200001], 1, "lean, next session: a row without a tooltip is not asked for")

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

eq(catalogued(300001, retail, PLAIN), string.format(ROW, 300001) .. ",3", "retail: the API's tier after equipLoc")
eq(catalogued(300002, retail, PLAIN), string.format(ROW, 300002), "retail: an untiered item has no tier column")
eq(catalogued(300003, retail, TIER2), string.format(ROW, 300003) .. ",2", "retail: the link's markup when the API answers nil")
eq(catalogued(300004, retail, TIER2), string.format(ROW, 300004) .. ",1", "the API's answer before the link's")
eq(catalogued(300005, nil, nil), string.format(ROW, 300005), "Forever: no C_TradeSkillUI and no link, no tier")
eq(catalogued(300006, {}, PLAIN), string.format(ROW, 300006), "Forever: C_TradeSkillUI without the call, no tier")
eq(catalogued(300007, nil, TIER2), string.format(ROW, 300007) .. ",2", "no API: the link's markup still counts")
eq(catalogued(300008, failing, PLAIN), string.format(ROW, 300008), "an API that errors: no error, no tier")
eq(catalogued(300009, failing, TIER2), string.format(ROW, 300009) .. ",2", "an API that errors: the link's markup")
eq(catalogued(300010, { GetItemReagentQualityByItemInfo = function() return "x" end }, PLAIN), string.format(ROW, 300010),
	"an answer that is not a tier is none")
eq(ns.FIELDS.item:match(",([^,]*)$"), "tier", "retail: the schema's item columns end with tier")

-- A crafted item (gear, a consumable) answers GetItemCraftedQualityByItemInfo, 1–5; a reagent answers the
-- reagent call, 1–3.
local craftedAnswers = { [300012] = 5 }
local both = {
	GetItemReagentQualityByItemInfo = function(id) return answers[id] end,
	GetItemCraftedQualityByItemInfo = function(id) return craftedAnswers[id] end,
}
eq(catalogued(300012, both, PLAIN), string.format(ROW, 300012) .. ",5", "retail: a crafted item's tier")
eq(catalogued(300001, both, PLAIN), string.format(ROW, 300001) .. ",3", "retail: a reagent's tier")
eq(catalogued(300002, both, PLAIN), string.format(ROW, 300002), "retail: an item without tiers has none")

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
eq(fightDb.catalogue.items[300012], string.format(ROW, 300012) .. ",5", "after the fight: the row and its tier")

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
eq(ns.FIELDS.item:match(",([^,]*)$"), "equipLoc", "Forever: the schema's item columns end with equipLoc")
eq(foreverDb.catalogue.items[300001], string.format(ROW, 300001), "Forever: no tier from the API")
eq(foreverDb.catalogue.items[300011], string.format(ROW, 300011), "Forever: no tier from the link")

return checks()
