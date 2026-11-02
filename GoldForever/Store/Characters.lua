-- Gold Forever: this character's entry in the save (db.characters), kept current during play, its market,
-- and the sys stream's login, resume, reload and logout rows.

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
