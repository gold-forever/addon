-- Rares.lua: a rare seen only as a minimap marker gives its marker's name to the catalogue when the NPC
-- has none yet (on WoW: Forever the marker is often its only sighting); never over a name it has.

local handlers = {}
local catalogue = { npcs = {}, objects = {} }
local db = { catalogue = catalogue }
local ns = {
	FIELDS = {},
	commands = {},
	lootListeners = {},
	db = function()
		return db
	end,
	after = function() end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	module = function() end,
	secret = function()
		return false
	end,
	readable = function(v)
		return v
	end,
	settings = function()
		return { announce = false }
	end,
	me = function()
		return { ref = 1 }
	end,
	now = function()
		return 1000
	end,
	position = function() end,
	record = function() end,
	alert = function() end,
}
UNKNOWNOBJECT = "Unknown"

local markers = {}
C_VignetteInfo = { GetVignetteInfo = function(vignette)
	return markers[vignette]
end }
local function marker(vignette, guid, name)
	markers[vignette] = { objectGUID = guid, name = name }
	for _, fn in ipairs(handlers.VIGNETTE_MINIMAP_UPDATED) do
		fn(vignette, true)
	end
end

assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Combat.lua"], "@Combat.lua"))("GoldForever", ns)
assert(load(SOURCES["Knowledge.lua"], "@Knowledge.lua"))("GoldForever", ns)
assert(load(SOURCES["Rares.lua"], "@Rares.lua"))("GoldForever", ns)

marker("V-1", "Creature-0-4620-0-12-61-000A", "Thuros Lightfingers")
eq(catalogue.npcs[61], "Thuros Lightfingers,,,,", "a rare seen only on the minimap is named")
catalogue.npcs[62] = ",24,24,rare,Humanoid"
marker("V-2", "Creature-0-4620-0-12-62-000A", "Gruff Swiftbite")
eq(catalogue.npcs[62], "Gruff Swiftbite,24,24,rare,Humanoid", "a row without a name takes the marker's")
catalogue.npcs[63] = "Mother Fang,10,10,rare,Beast"
marker("V-3", "Creature-0-4620-0-12-63-000A", "Something Else")
eq(catalogue.npcs[63], "Mother Fang,10,10,rare,Beast", "a named NPC keeps its name")
marker("V-4", "Creature-0-4620-0-12-64-000A", "Unknown")
eq(catalogue.npcs[64], nil, "a placeholder name names nothing")
marker("V-5", "GameObject-0-4620-0-12-65-000A", "Treasure")
eq(catalogue.objects[65], nil, "a treasure marker names nothing")

C_VignetteInfo = nil
return checks()
