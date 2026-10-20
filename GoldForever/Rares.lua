-- Gold Forever: a rare announcer. A rare (or rare elite) NPC seen on a nameplate, as the target or
-- under the mouse, or as a minimap marker, gets a mid-screen message, a sound and a chat line, once
-- per spawn, and a skull raid mark when the addon may set one. Each sighting is recorded (`rare`
-- stream), so the web app learns where rares spawn.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.rare = "t,char,npc,map,x,y,how"

local SKULL = 8
local RARE = { rare = true, rareelite = true }

local announced = {} -- spawn GUID -> true, this session; never written
local vignettes = {} -- minimap marker GUID -> true

local function settings()
	local s = ns.db().settings
	s.rares = s.rares or { announce = true, mark = true }
	return s.rares
end

-- Marks may be set solo, or in a group as its leader or an assistant.
local function mayMark()
	return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

local function alert(text)
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.82, b = 0 })
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
	print("|cffe0ac45Gold Forever|r " .. text)
end

-- "52.3, 34.1": the player's position on the map, close to the rare when it is seen.
local function where()
	local map, x, y = ns.position()
	return map, x, y, x and string.format("%.1f, %.1f", x / 10, y / 10) or nil
end

local function record(npc, how)
	local me = ns.me()
	if me then
		local map, x, y = where()
		ns.append("rare", Encode.row(ns.now(), me.ref, npc, map, x, y, how))
	end
end

-- A unit token that may be a rare: announce it once per spawn, record it, and mark it.
local function seeUnit(unit, how)
	if not UnitExists(unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then
		return
	end
	if not RARE[UnitClassification(unit)] then
		return
	end
	local guid = UnitGUID(unit)
	local s = settings()
	if s.mark and mayMark() and GetRaidTargetIndex(unit) ~= SKULL then
		pcall(SetRaidTarget, unit, SKULL)
	end
	if not guid or announced[guid] then
		return
	end
	announced[guid] = true
	local npc = tonumber(string.match(Encode.source(guid) or "", "^n(%d+)$"))
	if npc then
		record(npc, how)
	end
	if s.announce then
		local _, _, _, at = where()
		local level = UnitLevel(unit)
		local kind = UnitClassification(unit) == "rareelite" and " elite" or ""
		alert(string.format("Rare: %s (%s%s)%s", UnitName(unit) or "?", level and level > 0 and level or "??", kind, at and (" near " .. at) or ""))
	end
end

ns.on("NAME_PLATE_UNIT_ADDED", "rares", function(unit)
	seeUnit(unit, "nameplate")
end)
ns.on("PLAYER_TARGET_CHANGED", "rares", function()
	seeUnit("target", "target")
end)
ns.on("UPDATE_MOUSEOVER_UNIT", "rares", function()
	seeUnit("mouseover", "mouseover")
end)

-- Minimap markers: the client puts one on many rares before their nameplate is in range.
ns.on("VIGNETTE_MINIMAP_UPDATED", "rares", function(vignette, onMinimap)
	if not onMinimap or vignettes[vignette] or not (C_VignetteInfo and C_VignetteInfo.GetVignetteInfo) then
		return
	end
	local info = C_VignetteInfo.GetVignetteInfo(vignette)
	if not info or not info.objectGUID then
		return
	end
	local npc = tonumber(string.match(Encode.source(info.objectGUID) or "", "^n(%d+)$"))
	if not npc then
		return -- a treasure or an event, not an NPC
	end
	vignettes[vignette] = true
	if announced[info.objectGUID] then
		return
	end
	announced[info.objectGUID] = true
	record(npc, "minimap")
	if settings().announce then
		alert(string.format("Rare nearby: %s (on the minimap)", info.name or "?"))
	end
end)

-- "/gf rares" turns announcing on or off; "/gf rares mark" the skull.
ns.commands.rares = function(arg)
	local s = settings()
	if arg == "mark" then
		s.mark = not s.mark
		print("|cffe0ac45Gold Forever|r: rares " .. (s.mark and "get a skull mark" or "are not marked") .. ".")
	else
		s.announce = not s.announce
		print("|cffe0ac45Gold Forever|r: rares are " .. (s.announce and "announced" or "not announced") .. ".")
	end
end
