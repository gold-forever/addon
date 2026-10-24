-- Knowledge.lua: a mob's and an object's name reach the catalogue only when readable. Newer clients
-- (retail) keep a restricted unit's GUID and name secret, and an unloaded name reads "Unknown": such a
-- name is never written and never errors, and a later readable name fills the row. WoW: Forever reads
-- every name and keeps recording as it did.

local SECRET = setmetatable({}, {
	-- Any string use of a secret fails, as the game's "string conversion on a secret" does.
	__tostring = function()
		error("attempt to perform string conversion on a secret string value")
	end,
	__concat = function()
		error("attempt to perform string conversion on a secret string value")
	end,
})

local handlers, tooltipHooks = {}, {}
local catalogue = { npcs = {}, objects = {}, maps = {}, trainers = {} }
local ns = {
	FIELDS = {},
	commands = {},
	db = function()
		return { catalogue = catalogue }
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
}
function ns.secret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end
function ns.readable(v)
	if ns.secret(v) then
		return nil
	end
	return v
end

local function fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(...)
	end
end

TooltipDataProcessor = { AllTypes = "ALL", AddTooltipPostCall = function(_, fn)
	tooltipHooks[#tooltipHooks + 1] = fn
end }
local clock = 100
function GetTime()
	return clock
end
UNKNOWNOBJECT = "Unknown"

-- The unit "target" as the test sets it.
local unit = {}
function UnitExists(u)
	return u == "target" and unit.guid ~= nil
end
function UnitIsPlayer()
	return false
end
function UnitGUID(u)
	return u == "target" and unit.guid or nil
end
function UnitName(u)
	return u == "target" and unit.name or nil
end
function UnitLevel(u)
	return u == "target" and unit.level or 0
end
function UnitClassification()
	return unit.classification or "normal"
end
function UnitCreatureType()
	return unit.kind
end

assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Knowledge.lua"], "@Knowledge.lua"))("GoldForever", ns)

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end
local function target(t)
	unit = t
	fire("PLAYER_TARGET_CHANGED")
end
local function tooltip(data)
	for _, h in ipairs(tooltipHooks) do
		h(nil, data)
	end
end

-- WoW: Forever: no secrets, every name read (no issecretvalue on that client).
issecretvalue = nil
target({ guid = "Creature-0-4620-0-12-1922-000A", name = "Gray Forest Wolf", level = 9, kind = "Beast" })
eq(catalogue.npcs[1922], "Gray Forest Wolf,9,9,normal,Beast", "Forever: a mob recorded as before")
target({ guid = "Creature-0-4620-0-12-1922-000B", name = "Gray Forest Wolf", level = 11, kind = "Beast" })
eq(catalogue.npcs[1922], "Gray Forest Wolf,9,11,normal,Beast", "Forever: the level range widens")
fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-1", 2366)
ns.lootSource = "o1618"
fire("LOOT_READY")
eq(catalogue.objects[1618], "Peacebloom", "Forever: a gathered object named from its cast")
tooltip({ guid = "GameObject-0-4620-0-12-180682-000D", lines = { { leftText = "Oily Blackmouth School" } } })
eq(catalogue.objects[180682], "Oily Blackmouth School", "Forever: an object named from its tooltip")
-- A name the client has not loaded yet is "Unknown": no name, and the real one fills it later.
target({ guid = "Creature-0-4620-0-12-237399-000C", name = "Unknown", level = 80, kind = "Beast" })
eq(catalogue.npcs[237399], ",80,80,normal,Beast", "\"Unknown\" is never written as a name")
target({ guid = "Creature-0-4620-0-12-237399-000C", name = "Thornspine", level = 80, kind = "Beast" })
eq(catalogue.npcs[237399], "Thornspine,80,80,normal,Beast", "the real name fills the row at the same level")
target({ guid = "Creature-0-4620-0-12-237399-000C", name = "Unknown", level = 83, kind = "Beast" })
eq(catalogue.npcs[237399], "Thornspine,80,83,normal,Beast", "a later \"Unknown\" never replaces a real name")
-- A row from an older save named "Unknown" takes the real name.
catalogue.npcs[237400] = "Unknown,80,83,normal,Beast"
target({ guid = "Creature-0-4620-0-12-237400-000C", name = "Bramblehide", level = 81, kind = "Beast" })
eq(catalogue.npcs[237400], "Bramblehide,80,83,normal,Beast", "a saved \"Unknown\" row takes the real name")

-- Retail: the client keeps a restricted unit's identity secret.
function issecretvalue(v)
	return v == SECRET
end
-- A secret name on a readable GUID: the row is written without a name, and no error.
target({ guid = "Creature-0-4620-0-12-5000-000A", name = SECRET, level = 70, kind = SECRET, classification = SECRET })
eq(catalogue.npcs[5000], ",70,70,,", "a secret name, type and classification are not written")
-- A secret GUID: nothing to key the row by; nothing written, no error.
target({ guid = SECRET, name = SECRET, level = 70 })
-- Out of combat the client shows the unit: the name fills the row.
unit = { guid = "Creature-0-4620-0-12-5000-000A", name = "Ashfang Prowler", level = 70, kind = "Beast" }
fire("PLAYER_REGEN_ENABLED")
eq(catalogue.npcs[5000], "Ashfang Prowler,70,70,normal,Beast", "a readable name out of combat fills the row")
-- A unit met with a secret GUID is looked at again out of combat.
unit = { guid = SECRET, name = SECRET, level = 72 }
fire("PLAYER_TARGET_CHANGED")
eq(catalogue.npcs[5001], nil, "nothing recorded for a secret GUID")
unit = { guid = "Creature-0-4620-0-12-5001-000A", name = "Duskmire Lurker", level = 72, kind = "Beast" }
fire("PLAYER_REGEN_ENABLED")
eq(catalogue.npcs[5001], "Duskmire Lurker,72,72,normal,Beast", "the unit hidden in combat is recorded after it")
-- A mob's tooltip names a catalogued mob still without one; never one already named.
catalogue.npcs[5002] = ",60,61,elite,Humanoid"
tooltip({ guid = "Creature-0-4620-0-12-5002-000A", lines = { { leftText = SECRET } } })
eq(catalogue.npcs[5002], ",60,61,elite,Humanoid", "a secret tooltip line names nothing")
tooltip({ guid = "Creature-0-4620-0-12-5002-000A", lines = { { leftText = "Grimtotem Raider" } } })
eq(catalogue.npcs[5002], "Grimtotem Raider,60,61,elite,Humanoid", "a readable tooltip fills the name")
tooltip({ guid = "Creature-0-4620-0-12-5002-000A", lines = { { leftText = "Someone Else" } } })
eq(catalogue.npcs[5002], "Grimtotem Raider,60,61,elite,Humanoid", "a named mob keeps its name")
tooltip({ guid = SECRET, lines = { { leftText = SECRET } } })
-- Objects: a secret or "Unknown" cast or tooltip line names no object; a readable one does.
fire("UNIT_SPELLCAST_SENT", "player", SECRET, "Cast-2", 2366)
ns.lootSource = "o2000"
fire("LOOT_READY")
eq(catalogue.objects[2000], nil, "a secret cast target names no object")
fire("UNIT_SPELLCAST_SENT", "player", "Unknown", "Cast-3", 2366)
fire("LOOT_READY")
eq(catalogue.objects[2000], nil, "an \"Unknown\" cast target names no object")
tooltip({ guid = "GameObject-0-4620-0-12-2000-000D", lines = { { leftText = SECRET } } })
eq(catalogue.objects[2000], nil, "a secret tooltip line names no object")
tooltip({ guid = "GameObject-0-4620-0-12-2000-000D", lines = { { leftText = "Unknown" } } })
eq(catalogue.objects[2000], nil, "an \"Unknown\" tooltip line names no object")
tooltip({ guid = "GameObject-0-4620-0-12-2000-000D", lines = { { leftText = "Argentleaf" } } })
eq(catalogue.objects[2000], "Argentleaf", "a later readable tooltip names the object")
fire("UNIT_SPELLCAST_SENT", "player", "Argentleaf", "Cast-4", 2366)
fire("LOOT_READY")
eq(catalogue.objects[2000], "Argentleaf", "a readable cast names it as before")
issecretvalue = nil

return checks
