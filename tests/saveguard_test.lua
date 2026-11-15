-- The size guard (gf#404): at logout and /reload, Market.lua drops the oldest scans of a save over 8 MiB
-- (Scans.keepUnder), and the next load says so in chat once; /gf check counts them.

date = os.date
C_Map = { GetBestMapForUnit = function() return nil end, GetMapInfo = function() return nil end }

local MIB = 1048576
local function scan(market, t)
	local rows = {}
	for i = 1, 630 do
		rows[i] = string.rep("1", 1024)
	end
	return { kind = "full", market = market, t = t, rows = rows }
end
local save = { catalogue = { text = string.rep("x", 3 * MIB) }, scans = {} }
local markets = { "EU-Aszune-alliance", "EU-Aszune-horde", "EU-Aszune-neutral" }
for i = 1, 11 do
	save.scans[i] = scan(markets[i % 3 + 1], 1792000000 + i * 86400) -- a day apart: the login's pruning keeps them
end

-- One load of the addon's Store and Market files on the save: its module, its handlers, what it said.
local function load_()
	local handlers, modules, said = {}, {}, {}
	local ns = {
		on = function(event, _, fn) handlers[event] = fn end,
		after = function() end,
		throttle = function(_, _, fn) return fn end,
		module = function(name, m) modules[name] = m end,
		safely = function(_, fn, ...) return fn(...) end,
		commands = {},
		db = function() return save end,
		now = function() return 3000 end,
		say = function(text) said[#said + 1] = text end,
		plural = function(n, one, other) return string.format(n == 1 and one or other, n) end,
	}
	loadEncode(ns)
	for _, file in ipairs({ "Scans.lua", "Diagnostics.lua", "Market.lua" }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	modules.Market.enable()
	return ns, handlers, said
end

local ns, handlers, said = load_()
eq(#save.scans, 11, "the login keeps them all")
eq(#said, 0, "nothing dropped before: nothing said")
eq(ns.Scans.dropped, 0, "none dropped this session")
handlers.PLAYER_LOGOUT()
eq(ns.saveSize(save) < 8 * MIB, true, "the save at logout is under 8 MiB: " .. ns.saveSize(save) / MIB)
eq(#save.scans, 7, "the four oldest scans went")
eq(save.scans[1].t, 1792000000 + 5 * 86400, "the oldest kept")

ns, handlers, said = load_()
eq(table.concat(said, "|"), "kept the save under 8 MiB by dropping 4 old scans", "the next load says so")
eq(ns.Scans.dropped, 4, "counted this session, for /gf check")
eq(save.scansDropped, nil, "said once")
handlers.PLAYER_LOGOUT()
eq(save.scansDropped, nil, "a save under it drops nothing")
ns, handlers, said = load_()
eq(#said, 0, "and the load after says nothing")

return checks()
