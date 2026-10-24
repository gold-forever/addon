-- Gold Forever: records the player's characters into GoldForeverDB (design 002, schema v1).
-- The addon only records; everything else happens in the web app.
--
-- Core owns the saved table, the event wiring and the character state. Collectors in their own
-- files subscribe with ns.on; a collector that fails records its error in db.errors and leaves
-- the others running.

local addonName, ns = ...
local Encode = ns.Encode

local SCHEMA = 1
local VERSION = "0.16.0"
ns.VERSION = VERSION

-- A retail client keeps a lean save (owner's answer, 2026-10-24): the catalogue exists to keep
-- WoW: Forever's knowledge, which retail's does not need, so tooltip text, the achievement catalogue
-- and map art are neither recorded there nor kept. Forever keeps everything.
ns.lean = (select(4, GetBuildInfo()) or 0) >= 110000

-- Column dictionary; each collector adds its own entries when its file loads.
ns.FIELDS = {
	sys = "t,char,kind",
}

local db -- GoldForeverDB, once loaded
local me -- this character's entry in db.characters
local reloading = false -- set by the ReloadUI hook just before the UI unloads

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

function ns.me()
	return me
end

ns.now = GetServerTime

-- Errors ------------------------------------------------------------------------------------------

local errors = {} -- collector -> { n, msg, t }; becomes db.errors once the file is loaded
local told = {} -- collectors already reported in chat this session

function ns.fail(name, err)
	local e = errors[name] or { n = 0 }
	errors[name] = e
	e.n = e.n + 1
	e.msg = tostring(err)
	e.t = GetServerTime()
	if not told[name] then
		told[name] = true
		ns.say(name .. " failed: " .. tostring(err))
	end
end

-- Runs fn(...) and records an error instead of raising it.
function ns.safely(name, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		ns.fail(name, err)
	end
	return ok
end

-- Work spread over frames takes about FRAME_MS a frame: ns.frameStart() when a frame's share begins,
-- then ns.frameSpent(started, done, fallback) every so often says whether to yield. Where the client has
-- no profiling timer, `fallback` units of work a frame instead.
local FRAME_MS = 3
function ns.frameStart()
	return debugprofilestop and debugprofilestop() or nil
end
function ns.frameSpent(started, done, fallback)
	if started then
		return done % 25 == 0 and debugprofilestop() - started >= FRAME_MS
	end
	return done >= fallback
end

function ns.after(seconds, name, fn)
	C_Timer.After(seconds, function()
		ns.safely(name, fn)
	end)
end

-- fn at most once per `seconds`; calls during the wait collapse into one run at its end.
function ns.throttle(name, seconds, fn)
	local waiting, last = false, -math.huge
	return function()
		if waiting then
			return
		end
		local wait = last + seconds - GetTime()
		if wait <= 0 then
			last = GetTime()
			ns.safely(name, fn)
		else
			waiting = true
			C_Timer.After(wait, function()
				waiting = false
				last = GetTime()
				ns.safely(name, fn)
			end)
		end
	end
end

-- Events -----------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")
local listeners = {} -- event -> { { name, fn } }
local missing = {} -- events this client does not know, for the diagnostics

function ns.on(event, name, fn)
	if not listeners[event] then
		listeners[event] = {}
		if not pcall(frame.RegisterEvent, frame, event) then
			missing[#missing + 1] = event
		end
	end
	table.insert(listeners[event], { name = name, fn = fn })
end

frame:SetScript("OnEvent", function(_, event, ...)
	for _, l in ipairs(listeners[event]) do
		ns.safely(l.name, l.fn, ...)
	end
end)

-- Chat ------------------------------------------------------------------------------------------

ns.PREFIX = "|cffe0ac45Gold Forever|r"

-- "Gold Forever: …" in the chat frame.
function ns.say(text)
	print(ns.PREFIX .. ": " .. text)
end

-- A message mid-screen with the raid-warning sound, and in chat: big drops, quest starters, rares.
function ns.alert(text)
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.82, b = 0 })
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
	print(ns.PREFIX .. " " .. text)
end

-- A feature's settings table in the saved file, made with its defaults the first time.
function ns.settings(name, defaults)
	local s = ns.db().settings
	s[name] = s[name] or defaults
	return s[name]
end

-- Called with (gained, kind) for every XP gain once Levelling.lua knows what earned it (`quest`,
-- `boss`, `kill`, `explore`, `other`), a few seconds after the gain: the appraiser listens.
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

-- Creates or upgrades the saved table. Existing data is kept; only missing parts are added.
local function init()
	GoldForeverDB = GoldForeverDB or {}
	db = GoldForeverDB
	if db.schema and db.schema > SCHEMA then
		ns.say("this file was written by a newer version. Update the addon.")
	end
	db.schema = SCHEMA
	-- Errors are of the build that recorded them (owner's answer, 2026-10-24): a new version starts with
	-- none, so what the player and the site see is only from the build running.
	if db.addon ~= VERSION then
		db.errors = nil
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
	for name, e in pairs(errors) do
		db.errors[name] = e
	end
	errors = db.errors

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

-- Drops event days older than the retention window (design 002, Retention).
local function prune()
	local keep = (db.settings.retentionDays or 14) * 86400
	local cutoff = Encode.day(GetServerTime() - keep)
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

-- Market of the auction house or guild bank the player is at: region, realm (until the ruleset
-- is known, checklist #8) and side. On retail the realm is the connected group's key (Realms.lua).
function ns.market(side)
	local realm = ns.Realms.marketRealm(db.client.interface, me and me.realm,
		GetNormalizedRealmName and GetNormalizedRealmName(), ns.Realms.connected())
	return (db.client.region or "?") .. "-" .. (realm or "?") .. "-" .. side
end

local function sys(kind)
	if me then
		ns.append("sys", Encode.row(GetServerTime(), me.ref, kind))
	end
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
		missingEvents = #missing > 0 and table.concat(missing, " ") or nil,
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
	print(ns.PREFIX .. " " .. VERSION .. " · schema " .. SCHEMA .. " · " .. db.client.build)
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
		print(string.format("  %s: %d paid flights, %s", me.name, me.flights.n, GetCoinTextureString and GetCoinTextureString(me.flights.cost) or me.flights.cost .. "c"))
	end
	for name, e in pairs(db.errors) do
		print(string.format("  |cffe8615a%s|r failed %d× — %s", name, e.n, e.msg))
	end
	print("  The file is written at logout and /reload.")
end

-- Wiring -----------------------------------------------------------------------------------------

ns.on("ADDON_LOADED", "core", function(name)
	if name ~= addonName then
		return
	end
	init()
	prune()
end)

ns.on("PLAYER_LOGIN", "core", function()
	recordIdentity()
	recordState()
	C_Timer.NewTicker(60, function()
		ns.safely("core", recordState)
	end)
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

-- Collectors add subcommands: ns.commands.scan = function() ... end
ns.commands = {
	-- For bug reports: what the client offers, then what the addon has stored and any failures.
	check = function()
		printCheck()
		printStatus()
	end,
}

SLASH_GOLDFOREVER1 = "/gf"
SLASH_GOLDFOREVER2 = "/goldforever"
-- "/gf bigdrop 2" runs ns.commands.bigdrop("2").
-- "/gf" alone opens or closes the hub; "/gf help" lists the commands a player uses, "/gf help all" the
-- rest. The stored counts and failures are for bug reports, under "/gf check" (manual test run 001).
local function help(rest)
	print(ns.PREFIX .. " commands:")
	print("  /gf — open or close the window")
	print("  /gf hud — show or hide the session HUD")
	print("  /gf ah — show or hide the auction panel · /gf scan — scan the auction house")
	print("  /gf bags — what to do with your loot · /gf shop — crafts to make")
	print("  /gf look web|classic|arcane — change the look · /gf minimap — the minimap button")
	if rest == "all" then
		print("  /gf ui <page> — open a page · /gf session — the session in chat · /gf reset — a new session")
		print("  /gf bigdrop <gold> — big-drop alerts · /gf accent #rrggbb · /gf dings on|off · /gf welcome — the first-run card")
		print("  /gf prices — the prices file · /gf rares [mark] · /gf claim <code> · /gf export · /gf check — details for a bug report")
	else
		print("  More: /gf help all")
	end
end

SlashCmdList.GOLDFOREVER = function(message)
	local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
	name = string.lower(name or "")
	local command = ns.commands[name]
	if command then
		ns.safely("/gf " .. name, command, rest)
	elseif name == "" and ns.commands.ui then
		ns.safely("/gf", ns.commands.ui, "")
	elseif name == "help" or name == "" then
		help(rest)
	else
		print(ns.PREFIX .. ": no command \"" .. name .. "\". /gf help lists them.")
	end
end
