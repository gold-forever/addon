-- Store/Migrations.lua: the Store upgrades an older save to ns.SCHEMA at load, one migration at a time and in
-- order, before any module that requires it starts; each run is recorded in the save. A migration that fails,
-- or a save from a newer addon, leaves the save as it was, is reported (ns.fail), and what requires the Store
-- does not start.

local Dump = assert(load(SAVEDUMP, "@savedump.lua"))()

local handler
local said = {}
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
function print(text) said[#said + 1] = text end
unpack = table.unpack
SlashCmdList = {}

-- The kernel and the Store loaded afresh, as at a /reload, with `migrations` to schema `schema`; then
-- ADDON_LOADED and PLAYER_LOGIN (without `schema`, the addon's own). Returns what a module that requires the Store got to run.
local function load(schema, migrations)
	handler = nil
	local ns = {}
	for _, file in ipairs({ "Encode.lua", "Realms.lua", "Modules.lua", "Errors.lua", "Events.lua", "Chat.lua", "Commands.lua", "Save.lua", "Characters.lua", "Core.lua", "Schema.lua", "Migrations.lua" }) do
		assert(_G.load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	if schema then
		ns.SCHEMA, ns.MIGRATIONS = schema, migrations
	end
	local started = {}
	ns.module("Reader", {
		requires = { "Store" },
		init = function() started[#started + 1] = "init" end,
		enable = function() started[#started + 1] = "enable" end,
	})
	handler(nil, "ADDON_LOADED", "GoldForever")
	handler(nil, "PLAYER_LOGIN")
	return table.concat(started, ", "), ns
end

local ran = {}
local function step(from, to)
	return {
		from = from,
		to = to,
		run = function(save)
			ran[#ran + 1] = from .. ">" .. to
			save.trail = (save.trail or "") .. to
		end,
	}
end

-- Today's schema, two migrations on from the baseline.
GoldForeverDB = nil
local started, shipped = load()
eq(shipped.SCHEMA, 4, "schema 4 is today's")
eq(#shipped.MIGRATIONS, 3, "three migrations beyond the baseline")
eq(GoldForeverDB.schema, 4, "a new save starts at the current schema")
eq(GoldForeverDB.migrated, nil, "with no migration recorded")
eq(started, "init, enable", "and the modules that require the Store start")

-- 1 to 2: a character's guild, a name until now, is the guild record, seen when the character was; its rank
-- unknown. A character with none recorded stays unknown, not "no guild".
local upgraded = shipped.upgrade({ schema = 1, characters = {
	a = { name = "Ann", guild = "Vault", seen = 1761000000 },
	b = { name = "Bo", seen = 1761000500 },
} }, 4, shipped.MIGRATIONS, 1761148800)
local a, b = upgraded.characters.a.guild, upgraded.characters.b.guild
eq(a.name .. " " .. a.seen .. " " .. tostring(a.rank) .. " " .. tostring(a.rankIndex) .. " " .. tostring(a.none), "Vault 1761000000 nil nil nil", "a guild name becomes the guild record")
eq(b, nil, "no guild name stays unknown")

-- 2 to 3: the retired "Announce dings on Discord" choices leave the save; the rest stays.
upgraded = shipped.upgrade({ schema = 2, dings = { ["Player-1-a"] = { on = true, t = 1761000000 } }, characters = { a = { name = "Ann" } } }, 4, shipped.MIGRATIONS, 1761148800)
eq(upgraded.dings, nil, "the dings choices are gone")
eq(upgraded.characters.a.name, "Ann", "the rest is kept")

-- 3 to 4: an NPC row named with the client's placeholder for a name not yet loaded ("Unknown", or the
-- client's own word for it) loses that name and keeps the rest; a later sighting names it.
UNKNOWNOBJECT = "Unbekannt"
upgraded = shipped.upgrade({ schema = 3, catalogue = { npcs = {
	[1] = "Unknown,80,83,normal,Beast",
	[2] = "Unbekannt,10,12,elite,Humanoid",
	[3] = "Thornspine,80,80,normal,Beast",
	[4] = ",70,70,,",
} } }, 4, shipped.MIGRATIONS, 1761148800)
local npcs = upgraded.catalogue.npcs
eq(npcs[1], ",80,83,normal,Beast", "an English \"Unknown\" name is dropped, the row kept")
eq(npcs[2], ",10,12,elite,Humanoid", "and the client's own word for it")
eq(npcs[3], "Thornspine,80,80,normal,Beast", "a real name is kept")
eq(npcs[4], ",70,70,,", "a row without a name is as it was")
UNKNOWNOBJECT = nil
eq(shipped.upgrade({ schema = 3 }, 4, shipped.MIGRATIONS, 1761148800).schema, 4, "a save without a catalogue upgrades")

-- Two migrations in order, recorded with their time.
GoldForeverDB = { schema = 1, events = {} }
ran = {}
started = load(3, { step(1, 2), step(2, 3) })
eq(table.concat(ran, " "), "1>2 2>3", "each migration the save needs runs once, in order")
eq(GoldForeverDB.trail, "23", "on the save")
eq(GoldForeverDB.schema, 3, "the save is at the current schema")
eq(#GoldForeverDB.migrated, 2, "each run is recorded")
eq(GoldForeverDB.migrated[1].from .. ">" .. GoldForeverDB.migrated[1].to .. "@" .. GoldForeverDB.migrated[1].t, "1>2@1761148800", "with its versions and time")
eq(GoldForeverDB.migrated[2].from .. ">" .. GoldForeverDB.migrated[2].to, "2>3", "in the order run")
eq(started, "init, enable", "before the modules that require the Store start")

-- Loaded again: nothing left to run.
ran = {}
started = load(3, { step(1, 2), step(2, 3) })
eq(#ran, 0, "a save already upgraded runs no migration again")
eq(GoldForeverDB.trail .. " " .. #GoldForeverDB.migrated .. " " .. GoldForeverDB.schema, "23 2 3", "and keeps what they did")
eq(started, "init, enable", "and the modules that require the Store start")

-- Only the migrations from the save's schema on.
GoldForeverDB = { schema = 2 }
ran = {}
load(3, { step(1, 2), step(2, 3) })
eq(table.concat(ran, " "), "2>3", "a save at schema 2 runs only 2 to 3")

-- A failing migration: the upgrade stops and the save is as it was.
said = {}
GoldForeverDB = { schema = 1, events = { ["2026-10-22"] = { sys = { "1761148800,1,login" } } } }
local before = Dump.save(GoldForeverDB)
local saved = GoldForeverDB
local failing = step(2, 3)
failing.run = function(save)
	save.trail = "half"
	error("bad row")
end
ran = {}
local ns
started, ns = load(3, { step(1, 2), failing })
eq(table.concat(ran, " "), "1>2", "the upgrade stops at the failing migration")
eq(GoldForeverDB, saved, "the save is the same table")
eq(Dump.save(GoldForeverDB), before, "and holds what it held")
eq(started, "", "the modules that require the Store do not start")
eq(#said, 1, "the player is told once")
eq(said[1]:find("Store failed: migration 2 to 3: ", 1, true) ~= nil and said[1]:find("bad row", 1, true) ~= nil, true, "which migration failed and why: " .. tostring(said[1]))

-- A gap in the chain is a failed upgrade too.
said = {}
GoldForeverDB = { schema = 1 }
before = Dump.save(GoldForeverDB)
started = load(3, { step(2, 3) })
eq(Dump.save(GoldForeverDB), before, "a save no migration starts from is left as it was")
eq(started, "", "and the modules that require the Store do not start")
eq(said[1] and said[1]:find("Store failed: no migration from schema 1", 1, true) ~= nil, true, "reported: " .. tostring(said[1]))

-- A save from a newer addon is not touched.
said = {}
GoldForeverDB = { schema = 4, addon = "9.0.0", fields = { sys = "t,char,kind,more" }, events = {} }
before = Dump.save(GoldForeverDB)
started = load(3, { step(1, 2), step(2, 3) })
handler(nil, "PLAYER_ENTERING_WORLD", true, false)
handler(nil, "PLAYER_MONEY")
handler(nil, "PLAYER_LOGOUT")
eq(Dump.save(GoldForeverDB), before, "a newer save is left as it was, through a session and its logout")
eq(started, "", "the modules that require the Store do not start")
eq(#said, 1, "reported once: " .. table.concat(said, " | "))
eq(said[1]:find("Store failed: this file was written by a newer version of the addon (schema 4, this one reads 3). Update the addon.", 1, true) ~= nil, true, "as a newer file: " .. tostring(said[1]))

return checks()
