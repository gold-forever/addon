-- The size guard (gf#404): Market.lua drops the oldest scans of a save over 8 MiB (Scans.keepUnder) at
-- login, after each scan and at logout. The login says so in chat at once, and what the logout dropped the
-- next load; /gf check counts them, and db.sizeGuard says how far the last logout's guard got.

date = os.date
C_Map = { GetBestMapForUnit = function() return nil end, GetMapInfo = function() return nil end }
function UnitExists() return false end
function UnitGUID() return nil end
function GetSubZoneText() return "" end
-- A stand-in auction house of one listing, for a scan stored in the session.
C_AuctionHouse = {
	ReplicateItems = function() end,
	GetNumReplicateItems = function() return 1 end,
	GetReplicateItemInfo = function()
		return "Linen Cloth", nil, 5, nil, nil, nil, nil, nil, nil, 500, nil, nil, nil, nil, nil, nil, 2589
	end,
	GetReplicateItemLink = function() return "|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h" end,
}

local MIB = 1048576
local function scan(market, t, kind)
	local rows = {}
	for i = 1, 640 do
		rows[i] = string.rep("1", 1024)
	end
	return { kind = kind or "full", partial = kind and true or nil, market = market, t = t, rows = rows }
end
-- The owner's save of 2026-11-15: 10.0 MiB, 11 scans in three Forever markets, full a day apart (the
-- login's pruning keeps those) and two cut short in the last day.
local T, DAY = 1792000000, 86400
local AT = { [9] = T + 11.2 * DAY, [10] = T + 11.4 * DAY, [11] = T + 11.6 * DAY }
local function owner()
	local plan = { "EU-normal-horde", "EU-pvp-horde", "EU-normal-neutral", "EU-normal-horde", "EU-normal-horde",
		"EU-pvp-horde", "EU-normal-neutral", "EU-normal-horde", "EU-pvp-horde", "EU-normal-horde", "EU-normal-horde" }
	local save = { catalogue = { text = string.rep("x", 3 * MIB) }, scans = {} }
	for i, market in ipairs(plan) do
		save.scans[i] = scan(market, AT[i] or T + i * DAY, (i == 9 or i == 10) and "throttled" or nil)
	end
	return save
end
local save = owner()

-- One load of the addon's Store and Market files on the save: its module, its handlers, what it said.
local timers
local clock = T + 11.9 * DAY
local function load_()
	local handlers, modules, said = {}, {}, {}
	timers = {}
	local ns = {
		on = function(event, _, fn) handlers[event] = fn end,
		after = function(seconds, _, fn) timers[#timers + 1] = { at = clock + seconds, fn = fn } end,
		emit = function() end,
		throttle = function(_, _, fn) return fn end,
		module = function(name, m) modules[name] = m end,
		safely = function(_, fn, ...) return fn(...) end,
		commands = {},
		db = function() return save end,
		now = function() return clock end,
		say = function(text) said[#said + 1] = text end,
		plural = function(n, one, other) return string.format(n == 1 and one or other, n) end,
		readable = function(v) return v end,
		settings = function() return { auto = true } end,
		market = function(side) return "EU-normal-" .. side end,
		me = function() return { faction = "Horde" } end,
		frameStart = function() return nil end,
		frameSpent = function() return false end,
		catalogueItem = function() end,
	}
	loadEncode(ns)
	for _, file in ipairs({ "Scans.lua", "Diagnostics.lua", "Market.lua" }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	modules.Market.enable()
	return ns, handlers, said
end
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

-- The owner's case: the login drops what the logout did not, and says so at once.
local ns, handlers, said = load_()
eq(string.format("%.1f", ns.saveSize(owner()) / MIB), "10.0", "the owner's save")
eq(table.concat(said, "|"), "kept the save under 8 MiB by dropping 4 old scans", "the login drops and says so")
eq(#save.scans, 7, "the four oldest went")
eq(save.scans[1].t, T + 5 * DAY, "the oldest kept")
eq(ns.saveSize(save) < 8 * MIB, true, "under 8 MiB: " .. ns.saveSize(save) / MIB)
eq(ns.Scans.dropped, 4, "counted this session, for /gf check")
eq(ns.Scans.lastLogout, nil, "a save from before has no record of the last logout's guard")
eq(save.sizeGuard, "waiting", "until the logout's guard runs")
handlers.PLAYER_LOGOUT()
eq(save.sizeGuard, "ran", "the logout's guard ran to its end")
eq(save.scansDropped, nil, "a save under it drops nothing at logout")

-- The save grew over in the session: the logout drops, and the next load says it.
ns, handlers, said = load_()
eq(ns.Scans.lastLogout, "ran", "the next load reads how far the logout's guard got")
eq(#said, 0, "nothing dropped: nothing said")
table.insert(save.scans, 1, scan("EU-pvp-horde", T - 1 * DAY))
table.insert(save.scans, 1, scan("EU-pvp-horde", T - 2 * DAY))
table.insert(save.scans, 1, scan("EU-pvp-horde", T - 3 * DAY))
handlers.PLAYER_LOGOUT()
eq(save.scansDropped, 3, "the logout dropped three, for the next load to say")
ns, handlers, said = load_()
eq(table.concat(said, "|"), "kept the save under 8 MiB by dropping 3 old scans", "the next load says so")
eq(ns.Scans.dropped, 3, "and counts them")
eq(save.scansDropped, nil, "said once")

-- A logout whose guard never ran (a listener before it stopped by the client) reads as "waiting".
ns, handlers, said = load_()
eq(ns.Scans.lastLogout, "waiting", "the logout's guard did not run")
eq(ns.Scans.dropped, 0, "none dropped this session")

-- A scan stored in the session that takes the save over: the guard runs after it and says so.
table.insert(save.scans, 1, scan("EU-pvp-horde", T - 4 * DAY))
table.insert(save.scans, 1, scan("EU-pvp-horde", T - 5 * DAY))
handlers.AUCTION_HOUSE_SHOW()
wait(1)
handlers.REPLICATE_ITEM_LIST_UPDATE()
wait(1)
eq(said[#said], "kept the save under 8 MiB by dropping 2 old scans", "said after the scan")
eq(ns.Scans.dropped, 2, "counted this session")
eq(ns.saveSize(save) < 8 * MIB, true, "under 8 MiB after the scan: " .. ns.saveSize(save) / MIB)
eq(save.scans[#save.scans].auctions, 1, "the new scan kept")

return checks()
