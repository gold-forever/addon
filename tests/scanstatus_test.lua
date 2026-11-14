-- The auction house scan's status line (gf#394): Market.lua says where the scan stands (scanning, then
-- scanned or failed, cut short or throttled), and the Scan tab's line turns that into "Currently scanning
-- AH, please do not close" in yellow, pulsing, then a green "AH scanned" that fades, or a line saying why
-- it failed.

-- Market.lua on a stand-in auction house of three listings; `given` is how many of them the client gives.
local given = 3
C_AuctionHouse = {
	ReplicateItems = function() end,
	GetNumReplicateItems = function() return 3 end,
	GetReplicateItemInfo = function(index)
		if index >= given then
			return nil, nil, nil
		end
		return "Linen Cloth", nil, 5, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 2589
	end,
	GetReplicateItemLink = function() return "|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h" end,
}
C_Map = { GetBestMapForUnit = function() return 1453 end, GetMapInfo = function() return nil end }
function UnitExists() return false end
function UnitGUID() return nil end
function GetSubZoneText() return "" end

local clock = 1792517535
local save = { scans = {}, catalogue = {} }
local handlers, timers, states = {}, {}, {}
local ns = {
	on = function(event, _, fn) handlers[event] = fn end,
	after = function(seconds, _, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end,
	emit = function(event, ...)
		if event == "scanState" then
			states[#states + 1] = table.concat({ ... }, " ")
		end
	end,
	throttle = function(_, _, fn) return fn end,
	module = function() end,
	commands = {},
	db = function() return save end,
	now = function() return clock end,
	readable = function(v) return v end,
	say = function() end,
	settings = function() return { auto = true } end,
	market = function(side) return "eu-Realm-" .. side end,
	me = function() return { faction = "Alliance" } end,
	frameStart = function() return nil end,
	frameSpent = function() return false end,
	catalogueItem = function() end,
}
loadEncode(ns)
assert(load(SOURCES["Market.lua"], "@Market.lua"))("GoldForever", ns)

-- Moves the clock on by `seconds`, running each timer due on the way.
local function wait(seconds)
	local stop = clock + seconds
	while true do
		table.sort(timers, function(a, b) return a.at < b.at end)
		local t = timers[1]
		if not t or t.at > stop then
			break
		end
		table.remove(timers, 1)
		clock = math.max(clock, t.at)
		t.fn()
	end
	clock = stop
end

local function visit(answered)
	states, timers = {}, {}
	save.lastReplicate = nil
	handlers.AUCTION_HOUSE_SHOW()
	wait(1)
	if answered then
		handlers.REPLICATE_ITEM_LIST_UPDATE()
	end
	wait(70)
	handlers.AUCTION_HOUSE_CLOSED()
	return table.concat(states, ", ")
end

eq(visit(true), "scanning, scanned", "a scan read whole: scanning, then scanned")
given = 1
eq(visit(true), "scanning, failed cut short", "a scan the client gave a third of: failed, cut short")
given = 3
eq(visit(false), "scanning, failed throttled", "no answer within a minute: failed, throttled")
-- In the cooldown nothing starts, so the line says nothing.
states = {}
handlers.AUCTION_HOUSE_SHOW()
wait(2)
handlers.AUCTION_HOUSE_CLOSED()
eq(#states, 0, "in the cooldown: no scan, no state")

-- The line: the Scan tab's file on the parts of the namespace it reads when loaded.
local tab = { Theme = {}, UI = {}, ah = { WIDTH = 420 }, listen = function() end, on = function() end, module = function() end }
assert(load(SOURCES["AuctionScanTab.lua"], "@AuctionScanTab.lua"))("GoldForever_Auctions", tab)
local Line = tab.ScanLine

-- What the line holds after each state, from idle.
local s = Line.idle()
eq(Line.view(s, 0), nil, "idle: no line")
s = Line.heard(s, "scanning", nil, 100)
local v = Line.view(s, 100)
eq(v.text, "Currently scanning AH, please do not close", "scanning: the warning")
eq(v.color, Line.YELLOW, "scanning: yellow")
-- A gentle pulse: full at the start, never gone, back to full after a period.
eq(v.alpha, 1, "scanning: full at the start of a pulse")
local low = Line.view(s, 100 + Line.PULSE / 2).alpha
eq(low >= 0.4 and low < 0.6, true, "half a pulse on: dimmed, still readable (" .. low .. ")")
near(Line.view(s, 100 + Line.PULSE).alpha, 1, "a pulse later: full again")

-- The auction house opened again while the scan reads: the warning stays.
eq(Line.heard(s, "opened", nil, 120).phase, "scanning", "reopened while scanning: still scanning")

s = Line.heard(s, "scanned", nil, 130)
v = Line.view(s, 130)
eq(v.text, "AH scanned", "scanned: AH scanned")
eq(v.color, Line.GREEN, "scanned: green")
eq(v.alpha, 1, "scanned: steady")
eq(Line.view(s, 130 + Line.SHOWN).alpha, 1, "scanned: shown for its seconds")
local fading = Line.view(s, 130 + Line.SHOWN + Line.FADE / 2).alpha
eq(fading > 0 and fading < 1, true, "then fading (" .. fading .. ")")
eq(Line.view(s, 130 + Line.SHOWN + Line.FADE), nil, "faded: no line")
eq(Line.heard(s, "opened", nil, 135).phase, "idle", "the next visit starts idle")

local cut = Line.view(Line.heard(Line.idle(), "failed", "cut short", 200), 9999)
eq(cut.text, "AH scan cut short: not used for prices", "cut short: says so, and stays")
eq(cut.color, Line.RED, "failed: red")
eq(Line.view(Line.heard(Line.idle(), "failed", "throttled", 200), 200).text, "AH scan failed: the server did not answer", "throttled: says so")
eq(Line.heard(Line.heard(Line.idle(), "failed", "throttled", 200), "opened", nil, 300).phase, "idle", "a failure is not carried to the next visit")

return checks()
