-- Loot.lua: one loot row per source of a loot window, with the items that source gave. An area-loot
-- window (retail) shows the corpses around the one clicked as one window: an item two corpses dropped
-- is one slot listing both, each with its own count. The window's coin is the rise in money it is
-- matched to, which can come before its money slot clears, after the window closed, or in parts.

local handlers = {}
local rows = {} -- the loot rows recorded
local clock = 100
local timers = {} -- { at, fn }, run by wait()
local LOOT_COLUMNS -- Schema.lua's loot columns, by name (below)
local ns = {
	FIELDS = {},
	db = function()
		return { catalogue = { questStarters = {} }, events = {}, fields = {} }
	end,
	on = function(event, _, fn)
		handlers[event] = fn
	end,
	after = function(seconds, _, fn)
		timers[#timers + 1] = { at = clock + seconds, fn = fn }
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
			for name in pairs(row) do
				eq(LOOT_COLUMNS[name] ~= nil, true, "the loot row's column " .. name .. " is in the schema")
			end
			rows[#rows + 1] = row
		end
	end,
	catalogueItem = function() end,
	instanceId = function() end, -- Levelling.lua's: outside an instance until set below
}
loadEncode(ns)
-- The loot stream's columns as Schema.lua declares them: ns.record refuses a row with any other.
local schema = { Encode = ns.Encode }
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", schema)
LOOT_COLUMNS = ns.Encode.columns(schema.FIELDS.loot)
function hooksecurefunc() end
function GetTime()
	return clock
end
local purse = 0
function GetMoney()
	return purse
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
function GetLootSlotType(s)
	return slots[s].coin and 2 or 1
end
function GetLootSlotInfo(s)
	return nil, nil, slots[s].qty
end
function GetLootSlotLink(s)
	return slots[s].item and "|Hitem:" .. slots[s].item .. "::::::::80|h[x]|h" or nil
end
function GetLootSourceInfo(s)
	return table.unpack(slots[s].sources)
end

-- Lets the seconds pass, running the timers that come due, in order.
local function wait(seconds)
	local stop = clock + seconds
	while true do
		local next
		for _, timer in ipairs(timers) do
			if timer.at <= stop and (not next or timer.at < next.at) then
				next = timer
			end
		end
		if not next then
			break
		end
		for i, timer in ipairs(timers) do
			if timer == next then
				table.remove(timers, i)
				break
			end
		end
		clock = math.max(clock, next.at)
		next.fn()
	end
	clock = stop
end

-- The purse rises by the copper.
local function earn(copper)
	purse = purse + copper
	handlers.PLAYER_MONEY()
end
handlers.PLAYER_MONEY() -- the purse the first rise is measured from

-- Opens the window, takes every slot and closes it; the rows it recorded, by source, once written.
local function lootAll()
	rows = {}
	handlers.LOOT_READY()
	for slot in ipairs(slots) do
		handlers.LOOT_SLOT_CLEARED(slot)
	end
	handlers.LOOT_CLOSED()
	wait(1)
	return rows
end

-- Opens the window and takes every slot, leaving it open.
local function take()
	rows = {}
	handlers.LOOT_READY()
	for slot in ipairs(slots) do
		handlers.LOOT_SLOT_CLEARED(slot)
	end
end

-- The coin each row was given, in order, and their sum.
local function coins(got)
	local each, sum = {}, 0
	for i, row in ipairs(got) do
		each[i] = row.coin
		sum = sum + row.coin
	end
	return table.concat(each, " "), sum
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

-- Coin -------------------------------------------------------------------------------------------

-- A raid's area-loot window of two corpses: the coin comes as two shares, one rise each, after it closed,
-- the second more than a second after.
slots = { { coin = true, qty = 0, sources = { A, 3000, B, 3000 } } }
take()
handlers.LOOT_CLOSED()
wait(0.8)
earn(1000)
wait(0.7)
earn(1200)
wait(5)
eq(select(2, coins(rows)), 2200, "a window's coin as two rises: both are its coin")
eq(coins(rows), "1100 1100", "split by the corpses' coin")

-- The rise comes more than a second after the window closed.
slots = { { coin = true, qty = 0, sources = { A, 700 } } }
take()
handlers.LOOT_CLOSED()
wait(1.5)
earn(700)
wait(5)
eq(coins(rows), "700", "a rise after the window closed is its coin")

-- Twelve corpses in one area-loot window: two shares come before the money slot clears, one after.
local corpses, sources = {}, {}
for i = 1, 12 do
	corpses[i] = string.format("Creature-0-4620-2395-12-256862-%04X", 0x100 + i)
	sources[#sources + 1] = corpses[i]
	sources[#sources + 1] = 100
end
slots = { { coin = true, qty = 0, sources = sources }, { item = 242639, qty = 1, sources = { corpses[1], 1 } } }
rows = {}
handlers.LOOT_READY()
earn(400)
wait(0.1)
earn(400)
handlers.LOOT_SLOT_CLEARED(1)
handlers.LOOT_SLOT_CLEARED(2)
handlers.LOOT_CLOSED()
wait(0.3)
earn(400)
wait(5)
eq(#rows, 12, "twelve corpses: a row each")
eq(select(2, coins(rows)), 1200, "an area-loot window of twelve: every rise is its coin")
eq(coins(rows), "100 100 100 100 100 100 100 100 100 100 100 100", "a twelfth each")

-- Corpse after corpse: the next window opens before the first one's rows are written, and each window
-- keeps its own coin, the second's rise coming before its money slot clears.
slots = { { coin = true, qty = 0, sources = { A, 300 } } }
take()
handlers.LOOT_CLOSED()
wait(0.1)
earn(300)
slots = { { coin = true, qty = 0, sources = { B, 500 } } }
handlers.LOOT_READY()
earn(500)
wait(0.1)
handlers.LOOT_SLOT_CLEARED(1)
handlers.LOOT_CLOSED()
wait(5)
eq(coins(rows), "300 500", "corpse after corpse: each window its own coin")

-- In a group the shares are less than the slots show: the first window's share comes late, the second's
-- early, and the rows are still written in the order the windows closed.
slots = { { coin = true, qty = 0, sources = { A, 0 } } }
take()
handlers.LOOT_CLOSED()
wait(0.9)
earn(30)
slots = { { coin = true, qty = 0, sources = { B, 0 } } }
handlers.LOOT_READY()
earn(50)
handlers.LOOT_SLOT_CLEARED(1)
handlers.LOOT_CLOSED()
wait(5)
eq(coins(rows), "30 50", "group shares: each window its own, in the order they closed")

-- Fast auto-loot of coin-only windows (addon#90). The money slot's LOOT_SLOT_CLEARED can come after
-- LOOT_CLOSED, when the window is gone: the rise, before or after the close, is still its coin.
slots = { { coin = true, qty = 0, sources = { A, 400 } } }
rows = {}
handlers.LOOT_READY()
earn(400)
handlers.LOOT_CLOSED()
handlers.LOOT_SLOT_CLEARED(1)
wait(5)
eq(coins(rows), "400", "slot cleared after the close, the rise before it: the window's coin")

slots = { { coin = true, qty = 0, sources = { A, 600 } } }
rows = {}
handlers.LOOT_READY()
handlers.LOOT_CLOSED()
handlers.LOOT_SLOT_CLEARED(1)
wait(0.4)
earn(600)
wait(5)
eq(coins(rows), "600", "slot cleared after the close, the rise after it: the window's coin")

-- The rise comes more than a second before the money slot clears.
slots = { { coin = true, qty = 0, sources = { A, 800 } } }
rows = {}
handlers.LOOT_READY()
earn(800)
wait(1.5)
handlers.LOOT_SLOT_CLEARED(1)
handlers.LOOT_CLOSED()
wait(5)
eq(coins(rows), "800", "a rise 1.5 s before the money slot clears: the window's coin")

-- Three corpses at once, each window's slot clearing after its close: each its own rise, none twice.
local got3 = {}
for i, copper in ipairs({ 110, 220, 330 }) do
	slots = { { coin = true, qty = 0, sources = { corpses[i], copper } } }
	rows = {}
	handlers.LOOT_READY()
	handlers.LOOT_CLOSED()
	handlers.LOOT_SLOT_CLEARED(1)
	earn(copper)
	wait(0.2)
end
rows = {}
wait(5)
eq(coins(rows), "110 220 330", "three corpses looted fast: each window its own rise, none given twice")

-- A window closed with its coin left on the corpse takes no rise long after it.
slots = { { coin = true, qty = 0, sources = { A, 900 } } }
rows = {}
handlers.LOOT_READY()
handlers.LOOT_CLOSED()
wait(3)
earn(900)
wait(5)
eq(coins(rows), "0", "a rise 3 s after a window closed with its coin untaken is not its coin")

-- A rise claimed by a window closed with its money slot showing is not claimed again by the next window's
-- money slot.
slots = { { coin = true, qty = 0, sources = { A, 100 } } }
rows = {}
handlers.LOOT_READY()
earn(100)
handlers.LOOT_CLOSED()
handlers.LOOT_SLOT_CLEARED(1)
slots = { { coin = true, qty = 0, sources = { B, 200 } } }
handlers.LOOT_READY()
handlers.LOOT_SLOT_CLEARED(1)
earn(200)
handlers.LOOT_CLOSED()
wait(5)
eq(coins(rows), "100 200", "a rise claimed once: the next window's money slot does not take it again")

-- Where the game gives no map (old raids such as Molten Core), the loot row names the instance instead
-- (Levelling.lua's ns.instanceId, which catalogues it); with a map it is left empty.
ns.instanceId = function()
	return 409
end
slots = { { item = 242639, qty = 1, sources = { A, 1 } } }
got = lootAll()
eq(got[1].map, nil, "no map in an old raid")
eq(got[1].instanceId, 409, "the loot row names the instance instead")
C_Map.GetBestMapForUnit = function()
	return 1429
end
C_Map.GetPlayerMapPosition = function() end
got = lootAll()
eq(got[1].map .. " " .. tostring(got[1].instanceId), "1429 nil", "with a map, no instance")

return checks()
