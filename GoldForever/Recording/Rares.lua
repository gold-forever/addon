-- Gold Forever: a rare announcer. A rare (or rare elite) NPC seen on a nameplate, as the target or
-- under the mouse, or as a minimap marker, gets a mid-screen message, a sound and a chat line, once
-- per spawn. Each sighting is recorded (`rare` stream), so the web app learns where rares spawn.
-- The skull is set only by "/gf mark": the live client blocks SetRaidTarget from an event handler
-- ("blocked from an action only available to the Blizzard UI", owner, 2026-11-08), and allows it from
-- a typed or macro command, which is a key press.

local _, ns = ...
local L = ns.L
local Encode = ns.Encode

local SKULL = 8
local RARE = { rare = true, rareelite = true }

local announced = {} -- spawn GUID -> true, this session; never written
local vignettes = {} -- minimap marker GUID -> true
local lastRare -- { unit, guid } of the latest rare seen with a unit, for "/gf mark"

local function settings()
	return ns.settings("rares")
end

-- Marks may be set solo, or in a group as its leader or an assistant.
local function mayMark()
	return not IsInGroup() or UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")
end

-- The alert on screen, and with "tell my party" on (off by default; design 009: party only, never say
-- or yell, once per spawn as the alert itself) a line in party chat, not in a raid.
local function alert(text)
	ns.alert(text)
	local s = settings()
	if s.party and IsInGroup and IsInGroup() and not (IsInRaid and IsInRaid()) then
		-- C_ChatInfo.SendChatMessage where the client has it; the global is its older name.
		local send = C_ChatInfo and C_ChatInfo.SendChatMessage or SendChatMessage
		if send then
			send(Encode.chatLine(text), "PARTY")
		end
	end
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
		ns.record("rare", { t = ns.now(), char = me.ref, npc = npc, map = map, x = x, y = y, how = how })
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
	local guid = ns.readable(UnitGUID(unit))
	local s = settings()
	if not guid then
		return
	end
	lastRare = { unit = unit, guid = guid }
	if announced[guid] then
		return
	end
	announced[guid] = true
	local npc = Encode.npcId(guid)
	if npc then
		record(npc, how)
	end
	if s.announce then
		local _, _, _, at = where()
		local level = UnitLevel(unit)
		local kind = UnitClassification(unit) == "rareelite" and L[" elite"] or ""
		local name = ns.readable(UnitName(unit))
		local hint = s.mark and mayMark() and L[" · /gf mark to skull it"] or ""
		alert(string.format(L["Rare: %s (%s%s)%s%s"], not Encode.noName(name) and name or "?", level and level > 0 and level or "??", kind,
			at and string.format(L[" near %s"], at) or "", hint))
	end
end

-- Off on retail for now: its cities are full of minimap markers for ordinary NPCs, which the marker
-- handler below takes for rares, so the announcer fired constantly in Silvermoon (owner, 2026-10-22).
if ns.retail then
	ns.commands.rares = function()
		ns.say(L["the rare announcer is off on retail."])
	end
	return
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
	local npc = Encode.npcId(info.objectGUID)
	if not npc then
		return -- a treasure or an event, not an NPC
	end
	vignettes[vignette] = true
	-- Often a rare's only sighting: its marker names it in the catalogue when nothing else has.
	ns.nameNpc(npc, info.name)
	if announced[info.objectGUID] then
		return
	end
	announced[info.objectGUID] = true
	record(npc, "minimap")
	if settings().announce then
		alert(string.format(L["Rare nearby: %s (on the minimap)"], not Encode.noName(info.name) and info.name or "?"))
	end
end)

-- "/gf mark" puts the skull on the rare: the target or the mouseover when one is a rare, else the latest
-- rare seen while its unit still is. Typed or from a macro, so the client allows it.
local function markable(unit)
	return UnitExists(unit) and not UnitIsPlayer(unit) and not UnitIsDead(unit) and RARE[UnitClassification(unit)]
end
ns.commands.mark = function()
	if not mayMark() then
		ns.say(L["only the group's leader or an assistant can mark."])
		return
	end
	local unit = markable("target") and "target" or markable("mouseover") and "mouseover"
	if not unit and lastRare and markable(lastRare.unit) and ns.readable(UnitGUID(lastRare.unit)) == lastRare.guid then
		unit = lastRare.unit
	end
	if not unit then
		ns.say(L["no rare to mark: target it or hold the mouse over it."])
		return
	end
	SetRaidTarget(unit, SKULL)
end

-- "/gf rares" turns announcing on or off; "/gf rares mark" the "/gf mark" hint.
ns.commands.rares = function(arg)
	local s = settings()
	if arg == "mark" then
		s.mark = not s.mark
		ns.say(s.mark and L["rares get a skull mark."] or L["rares are not marked."])
	else
		s.announce = not s.announce
		ns.say(s.announce and L["rares are announced."] or L["rares are not announced."])
	end
end
