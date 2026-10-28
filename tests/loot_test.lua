-- Loot.lua: one loot row per source of a loot window, with the items that source gave. An area-loot
-- window (retail) shows the corpses around the one clicked as one window: an item two corpses dropped
-- is one slot listing both, each with its own count.

local handlers = {}
local rows = {} -- the loot rows recorded
local ns = {
	FIELDS = {},
	db = function()
		return { catalogue = { questStarters = {} }, events = {}, fields = {} }
	end,
	on = function(event, _, fn)
		handlers[event] = fn
	end,
	after = function(_, _, fn)
		fn()
	end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	module = function() end,
	now = function()
		return 1793175968
	end,
	me = function()
		return { ref = 2 }
	end,
	record = function(stream, row)
		if stream == "loot" then
			rows[#rows + 1] = row
		end
	end,
	catalogueItem = function() end,
}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
function hooksecurefunc() end
function GetTime()
	return 100
end
C_Map = { GetBestMapForUnit = function() return nil end }
assert(load(SOURCES["Loot.lua"], "@Loot.lua"))("GoldForever", ns)
-- The mob tooltip's count, kept up per loot once built (from a save with no loot rows here).
assert(load(SOURCES["MobStats.lua"], "@MobStats.lua"))("GoldForever", ns)
local mobs = ns.mobStats()

local slots
function GetNumLootItems()
	return #slots
end
function GetLootSlotType()
	return 1
end
function GetLootSlotInfo(s)
	return nil, nil, slots[s].qty
end
function GetLootSlotLink(s)
	return "|Hitem:" .. slots[s].item .. "::::::::80|h[x]|h"
end
function GetLootSourceInfo(s)
	return table.unpack(slots[s].sources)
end

-- Opens the window, takes every slot and closes it; the rows it recorded, by source.
local function lootAll()
	rows = {}
	handlers.LOOT_READY()
	for slot in ipairs(slots) do
		handlers.LOOT_SLOT_CLEARED(slot)
	end
	handlers.LOOT_CLOSED()
	return rows
end

-- Two Hawkstriders in one area-loot window: what both dropped is one slot of two, one from each.
local A, B = "Creature-0-4620-2395-12-256862-000A", "Creature-0-4620-2395-12-256862-000B"
slots = {
	{ item = 242639, qty = 2, sources = { A, 1, B, 1 } },
	{ item = 260656, qty = 1, sources = { A, 1 } },
	{ item = 275281, qty = 2, sources = { A, 1, B, 1 } },
	{ item = 260643, qty = 1, sources = { B, 1 } },
}
local got = lootAll()
eq(#got, 2, "two mobs in one window: one row each")
eq(got[1].src .. " " .. got[1].items, "n256862 242639*1+260656*1+275281*1", "the first mob's row: its own items")
eq(got[2].src .. " " .. got[2].items, "n256862 242639*1+260643*1+275281*1", "the second mob's row: its own items")
eq(mobs[256862].loots, 2, "the mob tooltip counts the window's two Hawkstriders as two loots")
eq(mobs[256862].items[242639].units, 2, "and the item both dropped once each as two")

return checks()
