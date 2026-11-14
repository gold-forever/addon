-- Market.lua: an auction house scan names every item it reads to the catalogue (gf#392), a listing with no
-- buyout (bid only) too, each item once a scan; Catalogue.lua reads them from the game at its own pace.

local listings = {
	{ item = 2589, count = 5, buyout = 500 },
	{ item = 2592, count = 1, buyout = 0 }, -- bid only: no price, but an item seen
	{ item = 2589, count = 2, buyout = 300 },
	{ item = 4306, count = 1, buyout = 900 },
}
C_AuctionHouse = {
	ReplicateItems = function() end,
	GetNumReplicateItems = function() return #listings end,
	GetReplicateItemInfo = function(index)
		local l = listings[index + 1]
		return "x", nil, l.count, nil, nil, nil, nil, nil, nil, l.buyout, nil, nil, nil, nil, nil, nil, l.item
	end,
	GetReplicateItemLink = function(index) return "|Hitem:" .. listings[index + 1].item .. "::::::::1:::::::|h[x]|h" end,
}
C_Map = { GetBestMapForUnit = function() return 1453 end, GetMapInfo = function() return nil end }
function UnitExists() return false end
function UnitGUID() return nil end
function GetSubZoneText() return "" end

local clock = 1792517535
local save = { scans = {}, catalogue = {} }
local handlers, timers, named = {}, {}, {}
local ns = {
	on = function(event, _, fn) handlers[event] = fn end,
	after = function(seconds, _, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end,
	emit = function() end,
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
	catalogueItem = function(key) named[#named + 1] = tostring(key) end,
}
loadEncode(ns)
assert(load(SOURCES["Market.lua"], "@Market.lua"))("GoldForever", ns)

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

handlers.AUCTION_HOUSE_SHOW()
wait(1)
handlers.REPLICATE_ITEM_LIST_UPDATE()
wait(5)
table.sort(named)
eq(table.concat(named, " "), "2589 2592 4306", "every item the scan read, a bid-only one too, named once")

return checks()
