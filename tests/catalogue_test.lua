-- Catalogue.lua: every item a scan names reaches the catalogue. A retail scan names about 19,000 items
-- while the queue is draining; on the owner's first retail scan (2026-10-22) exactly half never did.

local asked = {} -- item ID -> how often its info was asked for
GetItemInfo = function(id)
	asked[id] = (asked[id] or 0) + 1
	return "Item " .. id, nil, 1, 1, 1, nil, nil, 20, "", 1, 1, 7, 5, 0
end
C_TooltipInfo = {
	GetItemByID = function(id)
		return { lines = { { leftText = "Item " .. id }, { leftText = "Two-Hand", rightText = "Staff" } } }
	end,
}

-- One session of the addon on the saved table db: Catalogue.lua loaded afresh, its timers in `tick`.
local function session(db, lean)
	local scheduled = {}
	local ns = {
		lean = lean,
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

return checks()
