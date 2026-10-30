-- Knowledge.lua: a mob's and an object's name reach the catalogue only when readable. Newer clients
-- (retail) keep a restricted unit's GUID and name secret, and an unloaded name reads "Unknown": such a
-- name is never written and never errors, and a later readable name fills the row. WoW: Forever reads
-- every name and keeps recording as it did.

-- Anything but type() and issecretvalue() on a secret fails, as in game: reading it as text, comparing it,
-- indexing it, counting it, doing sums with it.
local function refuse()
	error("attempt to use a secret value", 2)
end
local SECRET = setmetatable({}, {
	__tostring = refuse,
	__concat = refuse,
	__eq = refuse,
	__lt = refuse,
	__le = refuse,
	__index = refuse,
	__newindex = refuse,
	__len = refuse,
	__call = refuse,
	__unm = refuse,
	__add = refuse,
	__sub = refuse,
	__mul = refuse,
	__div = refuse,
	__mod = refuse,
	__pow = refuse,
})
-- The stand-in refuses as the game does (an __eq between two tables only: Lua 5.1 asks no other).
assert(not pcall(function() return SECRET.find end) and not pcall(function() return SECRET < 1 end)
	and not pcall(function() return SECRET == setmetatable({}, getmetatable(SECRET)) end), "a secret refuses use")

local handlers, tooltipHooks = {}, {}
local catalogue = { npcs = {}, objects = {}, maps = {}, trainers = {} }
local db = { catalogue = catalogue }
local knowledge -- the module Knowledge.lua declares
local ns = {
	FIELDS = {},
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
	listen = function() end,
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	module = function(name, def)
		if name == "Knowledge" then
			knowledge = def
		end
	end,
	lootListeners = {},
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
Enum = { TooltipDataType = { Unit = 2, Object = 33 } }
local inInstance = false
C_Map = { GetBestMapForUnit = function() end }
function IsInInstance()
	return inInstance
end

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
assert(load(SOURCES["Combat.lua"], "@Combat.lua"))("GoldForever", ns)
assert(load(SOURCES["Knowledge.lua"], "@Knowledge.lua"))("GoldForever", ns)

local function target(t)
	unit = t
	fire("PLAYER_TARGET_CHANGED")
end
-- A loot window's rows as the loot collector hands them to its listeners, one a source.
local function loot(...)
	local rows = {}
	for i, guid in ipairs({ ... }) do
		rows[i] = { src = "", coin = 0, items = {}, guid = guid }
	end
	for _, listener in ipairs(ns.lootListeners) do
		listener(0, {}, rows)
	end
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

-- A client in another language: its own word for the placeholder (UNKNOWNOBJECT) is never a name either.
UNKNOWNOBJECT = "Inconnu"
target({ guid = "Creature-0-4620-0-12-237401-000C", name = "Inconnu", level = 80, kind = "Beast" })
eq(catalogue.npcs[237401], ",80,80,normal,Beast", "the client's own placeholder is never written as a name")
target({ guid = "Creature-0-4620-0-12-237401-000C", name = "Épineux", level = 80, kind = "Beast" })
eq(catalogue.npcs[237401], "Épineux,80,80,normal,Beast", "the real name fills the row")
UNKNOWNOBJECT = "Unknown"

-- Retail: the client keeps a restricted unit's identity secret.
function issecretvalue(v)
	return rawequal(v, SECRET)
end
-- A secret name on a readable GUID, in a fight: the row is written without a name, and no error.
fire("PLAYER_REGEN_DISABLED")
target({ guid = "Creature-0-4620-0-12-5000-000A", name = SECRET, level = 70, kind = SECRET, classification = SECRET })
eq(catalogue.npcs[5000], ",70,70,,", "a secret name, type and classification are not written")
-- A secret GUID: nothing to key the row by; nothing written, no error.
target({ guid = SECRET, name = SECRET, level = 70 })
-- Out of combat the client shows the unit: the name fills the row.
unit = { guid = "Creature-0-4620-0-12-5000-000A", name = "Ashfang Prowler", level = 70, kind = "Beast" }
fire("PLAYER_REGEN_ENABLED")
eq(catalogue.npcs[5000], "Ashfang Prowler,70,70,normal,Beast", "a readable name out of combat fills the row")
-- A unit met with a secret GUID is looked at again out of combat.
fire("PLAYER_REGEN_DISABLED")
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
-- A mob looted in a fight: its GUID and name secret on every unit while it lasts, and its corpse no
-- unit to look at once it ends. The loot window's GUID names it then, by the client's unit tooltip.
local hyperlinks = {} -- "unit:<GUID>" -> the tooltip's first line
local asked = 0
C_TooltipInfo = { GetHyperlink = function(link)
	asked = asked + 1
	local shown = hyperlinks[link]
	if shown == nil then
		return nil
	end
	local lines = {}
	for i, text in ipairs(type(shown) == "table" and shown or { shown }) do
		lines[i] = { leftText = (ns.inCombat() or inInstance) and SECRET or text }
	end
	return { lines = lines }
end }
hyperlinks["unit:Creature-0-4620-0-12-5003-000A"] = "Ironjaw Basilisk"
fire("PLAYER_REGEN_DISABLED")
target({ guid = SECRET, name = SECRET, level = 74 })
loot("Creature-0-4620-0-12-5003-000A")
eq(catalogue.npcs[5003], nil, "a mob looted in a fight is not named while it lasts")
unit = {}
fire("PLAYER_REGEN_ENABLED")
eq(catalogue.npcs[5003], "Ironjaw Basilisk,,,,", "a mob looted in a fight is named once it ends")
-- A row without a name keeps its levels; a named one is not asked again.
catalogue.npcs[5004] = ",75,76,normal,Beast"
hyperlinks["unit:Creature-0-4620-0-12-5004-000B"] = "Rimeclaw"
asked = 0
loot("Creature-0-4620-0-12-5003-000B", "Creature-0-4620-0-12-5004-000B", "GameObject-0-4620-0-12-2001-000C", "?")
eq(catalogue.npcs[5004], "Rimeclaw,75,76,normal,Beast", "a looted row without a name takes one out of combat")
eq(asked, 1, "only the unnamed mob is looked up")
-- A tooltip with no readable name yet (the client has not loaded it): asked again at the next loot.
loot("Creature-0-4620-0-12-5005-000A")
eq(catalogue.npcs[5005], nil, "no name: nothing written")
hyperlinks["unit:Creature-0-4620-0-12-5005-000A"] = "Unknown"
loot("Creature-0-4620-0-12-5003-000C")
eq(catalogue.npcs[5005], nil, "\"Unknown\": nothing written")
hyperlinks["unit:Creature-0-4620-0-12-5005-000A"] = "Frostbitten Yeti"
loot("Creature-0-4620-0-12-5003-000D")
eq(catalogue.npcs[5005], "Frostbitten Yeti,,,,", "a mob whose name loads later is named at the next loot")
-- An instance (a dungeon, a delve, a scenario): the unit tooltip for a looted GUID is secret there in
-- and out of combat, so a mob looted in one is named only once out of it, at the loading screen.
-- Until then it waits in the save, so a /reload or a logout in between loses nothing.
local function reload()
	for event in pairs(handlers) do
		handlers[event] = nil
	end
	for i = #tooltipHooks, 1, -1 do
		tooltipHooks[i] = nil
	end
	for i = #ns.lootListeners, 1, -1 do
		ns.lootListeners[i] = nil
	end
	assert(load(SOURCES["Combat.lua"], "@Combat.lua"))("GoldForever", ns)
	assert(load(SOURCES["Knowledge.lua"], "@Knowledge.lua"))("GoldForever", ns)
end
inInstance = true
hyperlinks["unit:Creature-0-4620-0-12-258955-000A"] = "Shadowguard Acolyte"
fire("PLAYER_REGEN_DISABLED")
loot("Creature-0-4620-0-12-258955-000A")
fire("PLAYER_REGEN_ENABLED")
eq(catalogue.npcs[258955], nil, "instance: a looted mob is not named while in it")
eq(db.unnamedNpcs and db.unnamedNpcs[258955] ~= nil, true, "instance: the unnamed mob is remembered in the save")
eq(catalogue.unnamedNpcs, nil, "and not in the catalogue, which is uploaded")
reload()
knowledge.world()
eq(catalogue.npcs[258955], nil, "a loading screen still in the instance names nothing")
inInstance = false
knowledge.world()
eq(catalogue.npcs[258955], "Shadowguard Acolyte,,,,", "the loading screen out of it names the mob, after a /reload")
eq(db.unnamedNpcs, nil, "and the save no longer holds it")
-- A mob the client never names is tried once a session, for 10 sessions, then forgotten.
loot("Creature-0-4620-0-12-258956-000A")
for _ = 1, 3 do
	knowledge.world()
end
for session = 2, 9 do
	reload()
	knowledge.world()
	knowledge.world()
end
eq(db.unnamedNpcs and db.unnamedNpcs[258956] ~= nil, true, "a mob still unnamed after 9 sessions is tried again")
reload()
knowledge.world()
eq(db.unnamedNpcs, nil, "after its 10th session it is forgotten")
eq(catalogue.npcs[258956], nil, "and nothing is written for it")
-- A mob's tooltip adds a row for an NPC with none yet, and the save stops waiting for it.
inInstance = true
loot("Creature-0-4620-0-12-258957-000A")
tooltip({ guid = "Creature-0-4620-0-12-258957-000A", type = 2, lines = { { leftText = "Darkway Sentinel" } } })
eq(catalogue.npcs[258957], "Darkway Sentinel,,,,", "a tooltip adds a named row for an NPC without one")
eq(db.unnamedNpcs, nil, "a mob named by its tooltip is no longer waited for")
-- A chest in an instance: its cast target and its tooltip's GUID secret, its tooltip's first line not.
-- The object looted next, within 10 seconds, takes the name its tooltip showed.
tooltip({ guid = SECRET, type = 33, lines = { { leftText = "Darkway Coffer" } } })
fire("UNIT_SPELLCAST_SENT", "player", SECRET, "Cast-5", 6478)
ns.lootSource = "o584517"
fire("LOOT_READY")
eq(catalogue.objects[584517], "Darkway Coffer", "instance: a chest is named from its tooltip's line")
tooltip({ guid = SECRET, type = 2, lines = { { leftText = "Someone" } } })
ns.lootSource = "o584518"
fire("LOOT_READY")
eq(catalogue.objects[584518], nil, "a unit's tooltip never names an object")
tooltip({ guid = SECRET, type = 33, lines = { { leftText = "Old Coffer" } } })
clock = clock + 11
ns.lootSource = "o584519"
fire("LOOT_READY")
eq(catalogue.objects[584519], nil, "a tooltip more than 10 seconds old names nothing")
tooltip({ guid = SECRET, type = 33, lines = { { leftText = "Spent Coffer" } } })
ns.lootSource = "o584520"
fire("LOOT_READY")
ns.lootSource = "o584521"
fire("LOOT_READY")
eq(catalogue.objects[584521], nil, "a tooltip names one loot only")
inInstance = false

-- A mob named later gets its level, classification and type from its tooltip's level line, as the
-- client words it (TOOLTIP_UNIT_LEVEL, ELITE, BOSS, RARE, the creature type names); "??" is no level.
TOOLTIP_UNIT_LEVEL = "Level %s"
ELITE, BOSS, RARE = "Elite", "Boss", "Rare"
local TYPES = { [1] = "Beast", [7] = "Humanoid", [6] = "Undead" }
C_CreatureInfo = {
	GetCreatureTypeIDs = function()
		return { 1, 6, 7 }
	end,
	GetCreatureTypeInfo = function(id)
		return { name = TYPES[id] }
	end,
}
hyperlinks["unit:Creature-0-4620-0-12-6001-000A"] = { "Grimward Guard", "Level 80 Humanoid (Elite)" }
hyperlinks["unit:Creature-0-4620-0-12-6002-000A"] = { "Vexthar the Unbroken", "<The Hollow Court>", "Level ?? Humanoid (Boss)" }
hyperlinks["unit:Creature-0-4620-0-12-6003-000A"] = { "Bog Stalker", "Level 78 Beast" }
hyperlinks["unit:Creature-0-4620-0-12-6004-000A"] = { "Old Bonegrinder", "Level 81 Rare Elite Undead" }
loot("Creature-0-4620-0-12-6001-000A", "Creature-0-4620-0-12-6002-000A", "Creature-0-4620-0-12-6003-000A",
	"Creature-0-4620-0-12-6004-000A")
eq(catalogue.npcs[6001], "Grimward Guard,80,80,elite,Humanoid", "a mob named later: its level, elite and type")
eq(catalogue.npcs[6002], "Vexthar the Unbroken,,,worldboss,Humanoid", "a boss named later: no level, boss and type")
eq(catalogue.npcs[6003], "Bog Stalker,78,78,normal,Beast", "a normal mob named later")
eq(catalogue.npcs[6004], "Old Bonegrinder,81,81,rareelite,Undead", "a rare elite named later")
-- A mob catalogued with a name but no level gets it on a later sighting: its tooltip, or its unit.
catalogue.npcs[6005] = "Hollow Sentry,,,,"
tooltip({ guid = "Creature-0-4620-0-12-6005-000A", lines = { { leftText = "Hollow Sentry" }, { leftText = "Level 79 Humanoid (Elite)" } } })
eq(catalogue.npcs[6005], "Hollow Sentry,79,79,elite,Humanoid", "a named row without a level takes its tooltip's")
tooltip({ guid = "Creature-0-4620-0-12-6005-000A", lines = { { leftText = "Hollow Sentry" }, { leftText = "Level 81 Humanoid" } } })
eq(catalogue.npcs[6005], "Hollow Sentry,79,81,elite,Humanoid", "a later tooltip widens the range and keeps the classification")
tooltip({ guid = "Creature-0-4620-0-12-6005-000A", lines = { { leftText = "Hollow Sentry" }, { leftText = SECRET } } })
eq(catalogue.npcs[6005], "Hollow Sentry,79,81,elite,Humanoid", "a secret level line changes nothing")
catalogue.npcs[6006] = "Vexthar's Shade,,,,"
target({ guid = "Creature-0-4620-0-12-6006-000A", name = "Vexthar's Shade", level = -1, classification = "worldboss", kind = "Undead" })
eq(catalogue.npcs[6006], "Vexthar's Shade,,,worldboss,Undead", "a boss seen at level ?? still takes its classification and type")
target({ guid = "Creature-0-4620-0-12-6007-000A", name = "Hollow Warden", level = -1, classification = "elite", kind = "Humanoid" })
eq(catalogue.npcs[6007], "Hollow Warden,,,elite,Humanoid", "a mob first seen at level ?? is catalogued with its classification")
target({ guid = "Creature-0-4620-0-12-6008-000A", name = SECRET, level = -1, classification = SECRET, kind = SECRET })
eq(catalogue.npcs[6008], nil, "a mob at level ?? with nothing readable writes no empty row")
TOOLTIP_UNIT_LEVEL, ELITE, BOSS, RARE, C_CreatureInfo = nil, nil, nil, nil, nil
unit = {}

-- "/gf probe" (temporary): what the naming reads, told as secret, empty or the value; never an error.
local said = {}
ns.say = function(text)
	said[#said + 1] = text
end
inInstance = true
hyperlinks["unit:Creature-0-4620-0-12-258957-000A"] = "Darkway Sentinel"
unit = { guid = SECRET, name = SECRET }
tooltip({ guid = SECRET, type = SECRET, lines = { { leftText = SECRET } } })
fire("UNIT_SPELLCAST_SENT", "player", SECRET, "Cast-6", 6478)
ns.commands.probe()
local told = table.concat(said, "\n")
eq(told:find("target: GUID secret, name secret", 1, true) ~= nil, true, "probe: a secret target")
eq(told:find("mouseover: GUID empty, name empty", 1, true) ~= nil, true, "probe: no mouseover")
eq(told:find("unit tooltip secret", 1, true) ~= nil, true, "probe: the looted mob's tooltip, secret in an instance")
eq(told:find("last cast target secret", 1, true) ~= nil, true, "probe: a secret cast target")
eq(told:find("last object tooltip: GUID secret, type secret, line secret", 1, true) ~= nil, true, "probe: a secret tooltip")
unit = {}
inInstance = false
C_TooltipInfo = nil
issecretvalue = nil

return checks()
