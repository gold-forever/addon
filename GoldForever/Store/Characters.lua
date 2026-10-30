-- Gold Forever: this character's entry in the save (db.characters), kept current during play, its market,
-- the sys stream's login, resume, reload and logout rows, and /gf check's report of the client and the save.

local _, ns = ...
local Encode = ns.Encode

local me -- this character's entry in db.characters

function ns.me()
	return me
end

-- Market of the auction house or guild bank the player is at: region, realm (until the ruleset
-- is known, checklist #8) and side. On retail the realm is the connected group's key (Realms.marketRealm).
function ns.market(side)
	local client = ns.db().client
	local realm = ns.Realms.marketRealm(client.interface, me and me.realm,
		GetNormalizedRealmName and GetNormalizedRealmName(), ns.Realms.connected())
	return (client.region or "?") .. "-" .. (realm or "?") .. "-" .. side
end

-- Characters -------------------------------------------------------------------------------------

local function nextRef()
	local db = ns.db()
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
	local db = ns.db()
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
end

-- This character's guild: { name, rank, rankIndex, seen }, or { none = true, seen } in none. Left as it was
-- while the client knows of a guild it cannot yet name (at login, until the guild has loaded).
local function recordGuild()
	if not me then
		return
	end
	local name, rank, rankIndex = GetGuildInfo("player")
	if name then
		me.guild = { name = name, rank = rank, rankIndex = rankIndex, seen = GetServerTime() }
	elseif IsInGuild and not IsInGuild() then
		me.guild = { none = true, seen = GetServerTime() }
	end
end

-- Never in combat: a change then is read once when the fight ends.
local function guildChanged()
	ns.afterCombat("core", recordGuild)
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

-- Launch-week checks -----------------------------------------------------------------------------

-- Which of the APIs design 002 depends on exist on this client. Booleans only, so the file
-- answers the checklist without recording anything personal.
local function diagnose()
	local db = ns.db()
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

local function checkLines(out)
	local db = ns.db()
	local diag = diagnose()
	local names = {}
	for name, value in pairs(diag) do
		if type(value) == "boolean" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	table.insert(out, ns.PREFIX .. " " .. ns.VERSION .. " · schema " .. ns.SCHEMA .. " · " .. db.client.build)
	for _, name in ipairs(names) do
		table.insert(out, string.format("  %s %s", diag[name] and "|cff56c98fyes|r" or "|cffe8615ano|r", name))
	end
	if diag.missingEvents then
		table.insert(out, "  unknown events: " .. diag.missingEvents)
	end
	table.insert(out, "  realm: " .. tostring(me and me.realm) .. " · region: " .. tostring(db.client.region))
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

local function statusLines(out)
	local db = ns.db()
	local today = db.events[Encode.day(GetServerTime())] or {}
	table.insert(out, string.format(
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
	table.insert(out, string.format("  today %d crafts, %d skill-ups, %d quests, %d money changes, %d flights",
		count(today.craft), count(today.skill), count(today.quest), count(today.money), count(today.flight)))
	if me and me.flights then
		table.insert(out, string.format("  %s: %d paid flights, %s", me.name, me.flights.n, ns.Money.format(me.flights.cost, "icons")))
	end
	for name, e in pairs(db.errors) do
		table.insert(out, string.format("  |cffe8615a%s|r failed %dx - %s", name, e.n, e.msg))
	end
	for name, e in pairs(db.stopped or {}) do
		table.insert(out, string.format("  |cffe8615a%s|r stopped by the client for running too long %dx", name, e.n))
	end
	table.insert(out, "  The file is written at logout and /reload.")
end

-- Wiring -----------------------------------------------------------------------------------------

ns.on("PLAYER_LOGIN", "core", function()
	recordIdentity()
	recordState()
	guildChanged()
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
ns.on("PLAYER_GUILD_UPDATE", "core", function(unit)
	if unit == nil or unit == "player" then
		guildChanged()
	end
end)
ns.on("GUILD_ROSTER_UPDATE", "core", guildChanged)

-- The last chance before the client writes the file; also fires on /reload. Collectors that
-- save on logout subscribe to it too.
ns.on("PLAYER_LOGOUT", "core", function()
	local db = ns.db()
	recordState()
	sys(ns.reloading() and "reload" or "logout")
	db.writtenAt = GetServerTime()
end)

-- For bug reports: what the client offers, then what the addon has stored and any failures. In chat, and
-- as plain text to copy ("checked": the copy box shows it).
ns.commands.check = function()
	local out = {}
	checkLines(out)
	statusLines(out)
	for i, line in ipairs(out) do
		print(line)
		out[i] = ns.plainText(line)
	end
	ns.emit("checked", table.concat(out, "\n"))
end
