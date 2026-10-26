-- Gold Forever: records the player's characters into GoldForeverDB (design 002, schema v1).
-- The addon only records; everything else happens in the web app.
--
-- Core owns the saved table and the character state, and wires the kernel's parts together: the error
-- path (Errors.lua), the event bus (Events.lua), chat (Chat.lua) and /gf (Commands.lua). Collectors in
-- their own files subscribe with ns.on; a collector that fails records its error in db.errors and leaves
-- the others running.

local addonName, ns = ...
local Encode = ns.Encode

local VERSION = "0.16.1"
ns.VERSION = VERSION

-- A retail client keeps a lean save (owner's answer, 2026-10-24): the catalogue exists to keep
-- WoW: Forever's knowledge, which retail's does not need, so tooltip text, the achievement catalogue
-- and map art are neither recorded there nor kept. Forever keeps everything.
ns.lean = (select(4, GetBuildInfo()) or 0) >= 110000

local db -- GoldForeverDB, once loaded
local me -- this character's entry in db.characters
local reloading = false -- set by the ReloadUI hook just before the UI unloads
-- Why the save could not be loaded (Migrations.lua): the addon then stands down for the session, so nothing
-- is recorded into a save it cannot read and the player is told once.
local stopped

-- What the tests reach in a file and the addon itself does not use: kept apart from the names the files share.
ns.test = {}

function ns.db()
	return db
end

-- Whether the client handed us a "secret" value (newer clients hide some unit and marker values from
-- addons): such a value may be passed back to the client but not compared or read here.
function ns.secret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

-- A value the addon may read, or nil when the client keeps it secret (UnitGUID, UnitName and
-- UnitCreatureType are, for a unit whose identity is restricted).
function ns.readable(v)
	if ns.secret(v) then
		return nil
	end
	return v
end

function ns.stopped()
	return stopped
end

function ns.me()
	return me
end

ns.now = GetServerTime

-- Each feature's settings section and its defaults, in one place (db.settings[section]).
ns.DEFAULTS = {
	window = {}, -- the look, the accent, the hub's place and its pages' choices
	appraiser = { shown = true }, -- the session HUD
	advisor = { shown = true },
	rares = { announce = true, mark = true },
	crafting = { strip = true }, -- the crafting strip, and the craft queue's recipes
	craftQueue = { closed = false },
	scan = { auto = false },
	prices = { tooltip = true },
	auction = { rule = {}, duration = 2 },
	mail = { helper = true },
	minimap = { angle = 225, hidden = false },
	firstRun = {},
	fetch = {},
}

-- A deep copy: the saved file never holds the defaults' own tables, and a save is upgraded on a copy.
function ns.copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = ns.copy(v)
	end
	return out
end

-- A feature's settings table in the saved file, made with its defaults the first time (ns.DEFAULTS
-- unless others are given). A default added in a later version reaches a table saved before it; what the
-- player set stays.
function ns.settings(name, defaults)
	defaults = defaults or ns.DEFAULTS[name]
	local s = ns.db().settings
	if not s[name] then
		s[name] = ns.copy(defaults)
	elseif defaults then
		local saved = s[name]
		for key, value in pairs(defaults) do
			if saved[key] == nil then
				saved[key] = ns.copy(value)
			end
		end
	end
	return s[name]
end

-- Called with (gained, kind) for every XP gain once Levelling.lua knows what earned it (`quest`,
-- `boss`, `kill`, `explore`, `other`), a few seconds after the gain: the session listens (Session.lua).
ns.xpListeners = {}

-- Appends a row to today's bucket of a stream.
function ns.append(stream, row)
	local day = Encode.day(GetServerTime())
	db.events[day] = db.events[day] or {}
	local bucket = db.events[day]
	bucket[stream] = bucket[stream] or {}
	Encode.append(bucket[stream], row)
end

-- Setup ------------------------------------------------------------------------------------------

local REGIONS = { "US", "KR", "EU", "TW", "CN" }

-- GetCurrentRegionName returns "" on the Forever client; fall back to the region number.
local function region()
	local name = GetCurrentRegionName and GetCurrentRegionName()
	if name and name ~= "" then
		return name
	end
	local id = GetCurrentRegion and GetCurrentRegion()
	return id and (REGIONS[id] or tostring(id)) or nil
end

-- Creates or upgrades the saved table: its migrations first (Migrations.lua), then only missing parts are
-- added. A save that cannot be upgraded, or one from a newer version, is left as it is and not loaded.
local function init()
	local upgraded, why = ns.upgrade(GoldForeverDB or {}, ns.SCHEMA, ns.MIGRATIONS, GetServerTime())
	if not upgraded then
		stopped = why
		error(why, 0)
	end
	GoldForeverDB = upgraded
	db = upgraded
	db.schema = ns.SCHEMA
	-- Errors are of the build that recorded them (owner's answer, 2026-10-24): a new version starts with
	-- none, so what the player and the site see is only from the build running.
	if db.addon ~= VERSION then
		db.errors, db.stopped = nil, nil
	end
	db.addon = VERSION
	db.fields = db.fields or {}
	for name, columns in pairs(ns.FIELDS) do
		db.fields[name] = columns -- columns only ever grow (design 002, rule 2)
	end
	db.characters = db.characters or {}
	db.events = db.events or {}
	db.scans = db.scans or {}
	db.guildBanks = db.guildBanks or {}
	db.catalogue = db.catalogue or {}
	db.catalogue.items = db.catalogue.items or {}
	db.catalogue.recipes = db.catalogue.recipes or {}
	db.catalogue.vendor = db.catalogue.vendor or {}
	db.catalogue.questNames = db.catalogue.questNames or {}
	db.catalogue.taxiNodes = db.catalogue.taxiNodes or {}
	db.catalogue.tooltips = db.catalogue.tooltips or {}
	db.catalogue.npcs = db.catalogue.npcs or {}
	db.catalogue.objects = db.catalogue.objects or {}
	db.catalogue.maps = db.catalogue.maps or {}
	db.catalogue.trainers = db.catalogue.trainers or {}
	db.catalogue.merchants = db.catalogue.merchants or {}
	db.catalogue.currencies = db.catalogue.currencies or {}
	db.catalogue.factions = db.catalogue.factions or {}
	db.catalogue.legacyPerks = db.catalogue.legacyPerks or {}
	db.catalogue.questStarters = db.catalogue.questStarters or {}
	db.catalogue.legacyRewards = db.catalogue.legacyRewards or {}
	db.catalogue.achievements = db.catalogue.achievements or {}
	db.catalogue.statistics = db.catalogue.statistics or {}
	if ns.lean then
		db.catalogue.tooltips = {}
		db.catalogue.achievements = {}
		db.mapArt = nil
	end
	db.settings = db.settings or { retentionDays = 14, sampleSeconds = 5, share = false }
	db.errors = db.errors or {}
	ns.recordErrorsIn(db.errors)

	local version, build, _, interface = GetBuildInfo()
	db.client = {
		build = version .. "." .. build,
		interface = interface,
		locale = GetLocale(),
		region = region(),
		regionId = GetCurrentRegion and GetCurrentRegion() or nil,
		portal = GetCVar and GetCVar("portal") or nil,
	}
end

-- Drops event days older than the retention window (design 002, Retention). A player who exports keeps
-- the days not yet exported too (an export holds the last one's day on), up to KEEP_MOST days so the file
-- stays under what the site takes. The companion app uploads the whole file and leaves no mark, so
-- without an export the window alone decides.
local KEEP_MOST = 30
local function prune()
	local now = GetServerTime()
	local keep = (db.settings.retentionDays or 14) * 86400
	local cutoff = Encode.day(now - keep)
	if db.exportedAt then
		local exported = Encode.day(math.max(db.exportedAt, now - KEEP_MOST * 86400))
		if exported < cutoff then
			cutoff = exported
		end
	end
	for day in pairs(db.events) do
		if day < cutoff then
			db.events[day] = nil
		end
	end
end

-- Characters -------------------------------------------------------------------------------------

local function nextRef()
	local max = 0
	for _, c in pairs(db.characters) do
		if c.ref and c.ref > max then
			max = c.ref
		end
	end
	return max + 1
end

-- Identity: everything that only changes on login or level up.
local function recordIdentity()
	local guid = UnitGUID("player")
	me = db.characters[guid] or { ref = nextRef() }
	db.characters[guid] = me

	local _, race = UnitRace("player")
	local _, class = UnitClass("player")
	-- On Forever every character has a surname too, UnitName's second value (elsewhere the realm,
	-- empty for the player).
	me.name, me.surname = UnitName("player")
	me.names = nil -- 0.8.2's probe of the name APIs
	me.race = race
	me.class = class
	me.faction = UnitFactionGroup("player")
	me.level = UnitLevel("player")
	me.region = db.client.region
	-- Design 002 checklist #8: the ruleset may be readable from the mega-realm's name. Keep the
	-- raw name until we know; the upload page can ask when it cannot tell.
	me.realm = GetRealmName()
	me.guild = GetGuildInfo("player")
end

-- On a real logout the client has already cleared money, XP and bags when PLAYER_LOGOUT fires
-- (a /reload has not), so values read then are zeros, not the character's state.
function ns.tornDown()
	return UnitXPMax("player") == 0 and GetMoney() == 0
end

-- State that changes during play; kept current during play and at every save, so a file read
-- after /reload or logout is current.
local function recordState()
	if not me then
		return
	end
	local now = GetServerTime()
	me.seen = now
	if ns.tornDown() then
		return
	end
	me.level = UnitLevel("player")
	me.money = GetMoney()

	local maxLevel = GetMaxPlayerLevel and GetMaxPlayerLevel() or 60
	if me.level < maxLevel then
		me.xp = {
			cur = UnitXP("player"),
			max = UnitXPMax("player"),
			rested = GetXPExhaustion() or 0,
			resting = IsResting() and 1 or nil,
			t = now,
		}
	else
		me.xp = nil
	end

	me.loc = {
		zone = GetZoneText(),
		sub = GetSubZoneText() ~= "" and GetSubZoneText() or nil,
		map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil,
	}
end

local function sys(kind)
	if me then
		ns.append("sys", Encode.row(GetServerTime(), me.ref, kind))
	end
end
ns.sys = sys -- for the session's Start and Stop (Session.lua)
-- Whether the UI is unloading for a /reload, not a logout (the session ends at a logout only).
function ns.reloading()
	return reloading
end

-- Launch-week checks -----------------------------------------------------------------------------

-- Which of the APIs design 002 depends on exist on this client. Booleans only, so the file
-- answers the checklist without recording anything personal.
local function diagnose()
	local function has(path)
		local value = _G
		for part in string.gmatch(path, "[^.]+") do
			if type(value) ~= "table" then
				return false
			end
			value = value[part]
		end
		return value ~= nil
	end
	local position = false
	if has("C_Map.GetPlayerMapPosition") then
		local map = C_Map.GetBestMapForUnit("player")
		position = map ~= nil and C_Map.GetPlayerMapPosition(map, "player") ~= nil
	end
	db.diag = {
		t = GetServerTime(),
		reloadHook = has("ReloadUI"),
		lootSource = has("GetLootSourceInfo"),
		mapPosition = position,
		tradeSkillUI = has("C_TradeSkillUI.GetAllRecipeIDs"),
		recipeSchematic = has("C_TradeSkillUI.GetRecipeSchematic"),
		container = has("C_Container.GetContainerItemInfo"),
		replicate = has("C_AuctionHouse.ReplicateItems"),
		guildBank = has("GetGuildBankItemInfo"),
		regionName = has("GetCurrentRegionName"),
		professions = has("GetProfessions"),
		skillLines = has("GetSkillLineInfo"),
		merchantInfo = has("C_MerchantFrame.GetItemInfo"),
		itemGUID = has("C_Item.GetItemGUID"),
		missingEvents = #ns.unknownEvents() > 0 and table.concat(ns.unknownEvents(), " ") or nil,
	}
	return db.diag
end

local function printCheck()
	local diag = diagnose()
	local names = {}
	for name, value in pairs(diag) do
		if type(value) == "boolean" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	print(ns.PREFIX .. " " .. VERSION .. " · schema " .. ns.SCHEMA .. " · " .. db.client.build)
	for _, name in ipairs(names) do
		print(string.format("  %s %s", diag[name] and "|cff56c98fyes|r" or "|cffe8615ano|r", name))
	end
	if diag.missingEvents then
		print("  unknown events: " .. diag.missingEvents)
	end
	print("  realm: " .. tostring(me and me.realm) .. " · region: " .. tostring(db.client.region))
end

local function count(stream)
	local rows = 0
	for _, chunk in ipairs(stream or {}) do
		rows = rows + Encode.count(chunk)
	end
	return rows
end

local function size(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

local function printStatus()
	local today = db.events[Encode.day(GetServerTime())] or {}
	print(string.format(
		ns.PREFIX .. ": %d characters · today %d loot, %d positions, %d sys · %d scans · catalogue %d items, %d recipes, %d vendor",
		size(db.characters),
		count(today.loot),
		count(today.pos),
		count(today.sys),
		#db.scans,
		size(db.catalogue.items),
		size(db.catalogue.recipes),
		size(db.catalogue.vendor)
	))
	print(string.format("  today %d crafts, %d skill-ups, %d quests, %d money changes, %d flights",
		count(today.craft), count(today.skill), count(today.quest), count(today.money), count(today.flight)))
	if me and me.flights then
		print(string.format("  %s: %d paid flights, %s", me.name, me.flights.n, ns.Money.format(me.flights.cost, "icons")))
	end
	for name, e in pairs(db.errors) do
		print(string.format("  |cffe8615a%s|r failed %d× — %s", name, e.n, e.msg))
	end
	for name, e in pairs(db.stopped or {}) do
		print(string.format("  |cffe8615a%s|r stopped by the client for running too long %d×", name, e.n))
	end
	print("  The file is written at logout and /reload.")
end

-- Wiring -----------------------------------------------------------------------------------------

-- The Store: the saved table, loaded and upgraded before any module that requires it starts.
ns.module("Store", {
	init = function()
		init()
		prune()
		ns.emit("ready")
	end,
})

ns.on("ADDON_LOADED", "core", function(name)
	if name ~= addonName then
		return
	end
	ns.startModules("init")
end)

ns.on("PLAYER_LOGIN", "core", function()
	recordIdentity()
	recordState()
	C_Timer.NewTicker(60, function()
		ns.safely("core", recordState)
	end)
end)
ns.on("PLAYER_LOGIN", "modules", function()
	ns.startModules("enable")
end)

ns.on("PLAYER_ENTERING_WORLD", "core", function(isInitialLogin, isReloadingUi)
	-- In the world now, so the position check is meaningful.
	diagnose()
	if isInitialLogin then
		sys("login")
	elseif isReloadingUi then
		sys("resume")
	end
end)

-- UnitLevel may still say the old level at this event; its first argument is the new one.
ns.on("PLAYER_LEVEL_UP", "core", function(level)
	recordIdentity()
	if me and tonumber(level) then
		me.level = tonumber(level)
	end
end)
ns.on("PLAYER_UPDATE_RESTING", "core", recordState)
ns.on("PLAYER_MONEY", "core", recordState)
ns.on("PLAYER_XP_UPDATE", "core", recordState)
ns.on("PLAYER_LEAVING_WORLD", "core", recordState)
ns.on("PLAYER_GUILD_UPDATE", "core", function()
	if me then
		me.guild = GetGuildInfo("player")
	end
end)

-- The last chance before the client writes the file; also fires on /reload. Collectors that
-- save on logout subscribe to it too.
ns.on("PLAYER_LOGOUT", "core", function()
	recordState()
	sys(reloading and "reload" or "logout")
	db.writtenAt = GetServerTime()
end)

-- /reload and addons call ReloadUI; flag it so PLAYER_LOGOUT records a reload, not a logout.
if ReloadUI then
	hooksecurefunc("ReloadUI", function()
		reloading = true
	end)
end
if C_UI and C_UI.Reload then
	hooksecurefunc(C_UI, "Reload", function()
		reloading = true
	end)
end

-- For bug reports: what the client offers, then what the addon has stored and any failures.
ns.commands.check = function()
	printCheck()
	printStatus()
end
