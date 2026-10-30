-- Knowledge.lua and ns.record: every map a stream row records is in the catalogue with its parents, a
-- dungeon floor reached without a zone event too (addon#70). A map is looked up at most once a session,
-- and in combat only once the fight ends.

unpack = table.unpack
local handlers = {}
local catalogue = { npcs = {}, objects = {}, maps = {}, trainers = {} }
local db = { catalogue = catalogue }
local appended = {}
local ns = {
	commands = {},
	db = function()
		return db
	end,
	after = function() end,
	throttle = function()
		return function() end
	end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	module = function() end,
	fail = function(_, message)
		error(message)
	end,
	append = function(stream, row)
		appended[#appended + 1] = stream .. " " .. row
	end,
	stopped = function()
		return false
	end,
	lootListeners = {},
}
function ns.secret()
	return false
end
function ns.readable(v)
	return v
end

local function fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(...)
	end
end

function GetTime()
	return 100
end
function CreateFrame()
	return { SetScript = function() end, RegisterEvent = function() end }
end
TooltipDataProcessor = { AllTypes = "ALL", AddTooltipPostCall = function() end }
-- Windrunner Spire's floors, as retail's map tree has them: each floor's parent is the dungeon's zone.
local here
local INFO = {
	[2494] = { name = "Windrunner Spire", mapType = 4, parentMapID = 2492 },
	[2492] = { name = "Windrunner Spire", mapType = 4, parentMapID = 2395 },
	[2395] = { name = "Eversong Woods", mapType = 3, parentMapID = 0 },
}
local lookups = {}
C_Map = {
	GetBestMapForUnit = function()
		return here
	end,
	GetMapInfo = function(map)
		lookups[map] = (lookups[map] or 0) + 1
		return INFO[map]
	end,
}

assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
-- The real message bus; game events still come from the test.
local on = ns.on
assert(load(SOURCES["Events.lua"], "@Events.lua"))("GoldForever", ns)
ns.on = on
assert(load(SOURCES["Combat.lua"], "@Combat.lua"))("GoldForever", ns)
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
assert(load(SOURCES["Knowledge.lua"], "@Knowledge.lua"))("GoldForever", ns)

-- A kill's XP on a floor no zone event told of: the floor and the maps above it are catalogued.
here = 2494
ns.record("xp", { t = 1, char = 1, xp = 25, kind = "kill", map = 2494 })
eq(catalogue.maps[2494], "Windrunner Spire,4,2492", "the floor a row records is catalogued")
eq(catalogue.maps[2492], "Windrunner Spire,4,2395", "with its parent")
eq(catalogue.maps[2395], "Eversong Woods,3,0", "and the zone above it")
eq(#appended, 1, "the row is still written")

-- A map already catalogued is not looked up again.
ns.record("xp", { t = 2, char = 1, xp = 25, kind = "kill", map = 2494 })
eq(lookups[2494], 1, "a catalogued map is not looked up again")

-- A map the client has no info for is asked about once a session, not at every row.
ns.record("pos", { t = 3, char = 1, map = 9999 })
ns.record("pos", { t = 4, char = 1, map = 9999 })
eq(lookups[9999], 1, "a map without info is asked about once a session")
eq(catalogue.maps[9999], nil, "and not catalogued")

-- A row without a map catalogues nothing.
ns.record("pos", { t = 5, char = 1 })
eq(#appended, 5, "every row is written")

-- In combat the lookup waits for the fight's end.
INFO[2497] = { name = "Windrunner Spire", mapType = 4, parentMapID = 2492 }
fire("PLAYER_REGEN_DISABLED")
ns.record("xp", { t = 6, char = 1, xp = 25, kind = "kill", map = 2497 })
ns.record("loot", { t = 7, char = 1, map = 2497, src = "", coin = 1 })
eq(lookups[2497], nil, "no map lookup in combat")
eq(catalogue.maps[2497], nil, "the floor waits for the fight's end")
fire("PLAYER_REGEN_ENABLED")
eq(catalogue.maps[2497], "Windrunner Spire,4,2492", "the floor is catalogued once the fight ends")
eq(lookups[2497], 1, "looked up once for both rows")

return checks()
