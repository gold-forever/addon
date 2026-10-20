-- Gold Forever: records the player's characters into GoldForeverDB (design 002, schema v1).
-- The addon only records; everything else happens in the web app.

local addonName, ns = ...
local Encode = ns.Encode

local SCHEMA = 1
local VERSION = "0.1.0"

local FIELDS = {
	sys = "t,char,kind",
}

local db -- GoldForeverDB, once loaded
local me -- this character's entry in db.characters
local reloading = false -- set by the ReloadUI hook just before the UI unloads

-- Setup ------------------------------------------------------------------------------------------

-- Creates or upgrades the saved table. Existing data is kept; only missing parts are added.
local function init()
	GoldForeverDB = GoldForeverDB or {}
	db = GoldForeverDB
	if db.schema and db.schema > SCHEMA then
		print("|cffe0ac45Gold Forever|r: this file was written by a newer version. Update the addon.")
	end
	db.schema = SCHEMA
	db.addon = VERSION
	db.fields = db.fields or {}
	for name, columns in pairs(FIELDS) do
		db.fields[name] = columns -- columns only ever grow (design 002, rule 2)
	end
	db.characters = db.characters or {}
	db.events = db.events or {}
	db.settings = db.settings or { retentionDays = 14, sampleSeconds = 5, share = false }

	local version, build, _, interface = GetBuildInfo()
	db.client = {
		build = version .. "." .. build,
		interface = interface,
		locale = GetLocale(),
		region = GetCurrentRegionName and GetCurrentRegionName() or nil,
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
	me.name = UnitName("player")
	me.race = race
	me.class = class
	me.faction = UnitFactionGroup("player")
	me.level = UnitLevel("player")
	me.region = db.client.region
	-- Design 002 checklist #8: the ruleset may be readable from the mega-realm's name. Keep the
	-- raw name until we know; the upload page can ask when it cannot tell.
	me.realm = GetRealmName()
end

-- State that changes during play; written at every save so a file read after /reload is current.
local function recordState()
	if not me then
		return
	end
	local now = GetServerTime()
	me.level = UnitLevel("player")
	me.money = GetMoney()
	me.seen = now

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

-- Events -----------------------------------------------------------------------------------------

local function sys(kind)
	if not me then
		return
	end
	local now = GetServerTime()
	local day = Encode.day(now)
	db.events[day] = db.events[day] or {}
	local bucket = db.events[day]
	bucket.sys = bucket.sys or {}
	Encode.append(bucket.sys, Encode.row(now, me.ref, kind))
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
	}
	return db.diag
end

local function printCheck()
	local diag = diagnose()
	local names = {}
	for name in pairs(diag) do
		if name ~= "t" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	print("|cffe0ac45Gold Forever|r " .. VERSION .. " · schema " .. SCHEMA .. " · " .. db.client.build)
	for _, name in ipairs(names) do
		print(string.format("  %s %s", diag[name] and "|cff56c98fyes|r" or "|cffe8615ano|r", name))
	end
	print("  realm: " .. tostring(me and me.realm) .. " · region: " .. tostring(db.client.region))
end

local function printStatus()
	local characters, rows = 0, 0
	for _ in pairs(db.characters) do
		characters = characters + 1
	end
	local today = db.events[Encode.day(GetServerTime())]
	for _, chunk in ipairs(today and today.sys or {}) do
		rows = rows + Encode.count(chunk)
	end
	print(string.format(
		"|cffe0ac45Gold Forever|r: %d characters, %d events today. The file is written at logout and /reload.",
		characters,
		rows
	))
end

-- Wiring -----------------------------------------------------------------------------------------

local frame = CreateFrame("Frame")

local handlers = {}

function handlers.ADDON_LOADED(name)
	if name ~= addonName then
		return
	end
	init()
	prune()
	frame:UnregisterEvent("ADDON_LOADED")
end

function handlers.PLAYER_LOGIN()
	recordIdentity()
	recordState()
end

function handlers.PLAYER_ENTERING_WORLD(isInitialLogin, isReloadingUi)
	-- In the world now, so the position check is meaningful.
	diagnose()
	if isInitialLogin then
		sys("login")
	elseif isReloadingUi then
		sys("resume")
	end
end

function handlers.PLAYER_LEVEL_UP()
	recordIdentity()
end

function handlers.PLAYER_UPDATE_RESTING()
	recordState()
end

-- The last chance before the client writes the file; also fires on /reload.
function handlers.PLAYER_LOGOUT()
	recordState()
	sys(reloading and "reload" or "logout")
	db.writtenAt = GetServerTime()
end

frame:SetScript("OnEvent", function(_, event, ...)
	handlers[event](...)
end)
for event in pairs(handlers) do
	frame:RegisterEvent(event)
end

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

SLASH_GOLDFOREVER1 = "/gf"
SLASH_GOLDFOREVER2 = "/goldforever"
SlashCmdList.GOLDFOREVER = function(message)
	if message == "check" then
		printCheck()
	else
		printStatus()
		print("  /gf check — which APIs this client has (saved into the file too)")
	end
end
