-- Ledger.lua with Loot.lua: a rise in money the loot matcher takes as a loot window's coin is tagged
-- "loot" in its money row, however late it comes within the matcher's wait; a rise it does not take is not.

local clock, purse = 100, 0
function GetTime() return clock end
function GetMoney() return purse end
function hooksecurefunc() end
C_Map = { GetBestMapForUnit = function() return nil end }

local handlers, timers, money = {}, {}, {}
local ns = {
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	after = function(seconds, _, fn)
		timers[#timers + 1] = { at = clock + seconds, fn = fn }
	end,
	module = function() end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	db = function()
		return { catalogue = { questStarters = {} } }
	end,
	me = function() return { ref = 1 } end,
	now = function() return 1793175968 end,
	tornDown = function() return false end,
	catalogueItem = function() end,
	record = function(stream, row)
		if stream == "money" then
			money[#money + 1] = row.delta .. "," .. row.ctx
		end
	end,
}
local function fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(...)
	end
end
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Loot.lua"], "@Loot.lua"))("GoldForever", ns)
assert(load(SOURCES["Ledger.lua"], "@Ledger.lua"))("GoldForever", ns)

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

local function earn(copper)
	purse = purse + copper
	fire("PLAYER_MONEY")
end

-- A corpse with one money slot.
function GetNumLootItems() return 1 end
function GetLootSlotType() return 2 end
function GetLootSlotInfo() return nil, nil, 0 end
function GetLootSourceInfo() return "Creature-0-4620-2395-12-256862-000A", 0 end

fire("PLAYER_MONEY") -- the purse the changes are measured from

-- The window is read for 10 s and closed; its coin comes 3 s later, 13 s after the loot.
fire("LOOT_READY")
wait(9)
fire("LOOT_SLOT_CLEARED", 1)
wait(1)
fire("LOOT_CLOSED")
wait(3)
earn(11107)
eq(money[#money], "11107,loot", "coin 13 s after the loot, 3 s after the window closed, is loot")
wait(6)

-- The window stays open; its coin comes 11 s after the loot, while it shows.
fire("LOOT_READY")
wait(10.5)
fire("LOOT_SLOT_CLEARED", 1)
wait(0.5)
earn(29229)
eq(money[#money], "29229,loot", "coin 11 s after the loot, the window still open, is loot")
fire("LOOT_CLOSED")
wait(6)

-- The window is closed at once; its coin comes 4.5 s later, near the end of the matcher's wait (15 s
-- after a loot read for 10.5 s).
fire("LOOT_READY")
wait(10)
fire("LOOT_SLOT_CLEARED", 1)
wait(0.5)
fire("LOOT_CLOSED")
wait(4.5)
earn(5000)
eq(money[#money], "5000,loot", "coin 15 s after the loot, within the matcher's wait, is loot")
wait(6)

-- No coin comes; the matcher gives up and a rise after that is no loot's.
fire("LOOT_READY")
fire("LOOT_SLOT_CLEARED", 1)
fire("LOOT_CLOSED")
wait(6)
earn(700)
eq(money[#money], "700,", "a rise after the matcher stopped waiting is not loot")
wait(2)

-- A fall while a window waits for its coin is not its coin.
fire("LOOT_READY")
fire("LOOT_SLOT_CLEARED", 1)
fire("LOOT_CLOSED")
wait(3)
earn(-50)
eq(money[#money], "-50,", "money spent while coin is awaited is not loot")

return checks()
