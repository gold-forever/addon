-- Gold Forever: the levelling history. Every level-up with the time played (`level` rows), every
-- XP gain with where it came from (`xp` rows), and every zone entered (`zone` rows), so the web app
-- can show how long each level took, in game and in real time, where its XP came from and where it
-- was spent. Gold per level comes from the `money` stream, between two level rows.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.level = "t,char,kind,level,played,levelPlayed,money,map"
ns.FIELDS.xp = "t,char,xp,kind,rested,instance,map,level"
ns.FIELDS.zone = "t,char,map,instance"

local WINDOW = 3 -- seconds between an XP gain and what earned it (a kill, a quest, a new zone)
local PLAYED_TIMEOUT = 10 -- seconds to wait for /played before writing a level row without it

local function instance()
	local inside, kind = IsInInstance()
	return inside and kind ~= "none" and kind or nil
end

local function map()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

-- Time played --------------------------------------------------------------------------------------

-- /played without the chat line: chat frames stop listening while the addon asks, and listen again
-- once the answer is in.
local pending -- { t, kind, level, money, map }: the level row waiting for its time played
local muted = {} -- chat frames that stopped listening for this request

local function unmute()
	for _, f in ipairs(muted) do
		f:RegisterEvent("TIME_PLAYED_MSG")
	end
	muted = {}
end

local function write(played, levelPlayed)
	local p, me = pending, ns.me()
	pending = nil
	if p and me then
		ns.append("level", Encode.row(p.t, me.ref, p.kind, p.level, played, levelPlayed, p.money, p.map))
	end
end

local function askPlayed(kind, level)
	if pending then
		write(nil, nil) -- the earlier request never got its answer
	end
	pending = { t = ns.now(), kind = kind, level = level, money = GetMoney(), map = map() }
	if not RequestTimePlayed then
		write(nil, nil)
		return
	end
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local f = _G["ChatFrame" .. i]
		if f and f:IsEventRegistered("TIME_PLAYED_MSG") then
			f:UnregisterEvent("TIME_PLAYED_MSG")
			muted[#muted + 1] = f
		end
	end
	RequestTimePlayed()
	local asked = pending
	ns.after(PLAYED_TIMEOUT, "played", function()
		if pending == asked then
			write(nil, nil)
			unmute()
		end
	end)
end

ns.on("TIME_PLAYED_MSG", "played", function(total, thisLevel)
	if pending then
		write(total, thisLevel)
	end
	-- After this event has reached every listener, so the muted frames skip this one.
	C_Timer.After(0, function()
		ns.safely("played", unmute)
	end)
end)

-- A login row tells when the current level started even when its level-up was never seen.
ns.on("PLAYER_ENTERING_WORLD", "levelling", function(isInitialLogin)
	if isInitialLogin then
		ns.after(3, "played", function()
			askPlayed("login", UnitLevel("player"))
		end)
	end
end)

ns.on("PLAYER_LEVEL_UP", "levelling", function(level)
	local reached = tonumber(level) or UnitLevel("player")
	-- The time played this level restarts at the level-up; asked a moment later, it has.
	ns.after(1, "played", function()
		askPlayed("up", reached)
	end)
end)

-- XP -------------------------------------------------------------------------------------------------

local seen -- { cur, max, rested }: the last reading
local questAt, combatAt, zoneAt = -math.huge, -math.huge, -math.huge

local function read()
	return { cur = UnitXP("player"), max = UnitXPMax("player"), rested = GetXPExhaustion() or 0 }
end

-- What earned XP gained at `at`: a quest handed in, a kill (XP while in combat, or just after it),
-- a new zone (exploration), else something else (a profession, an event). The combat log would
-- name the kill, but the client keeps it for the Blizzard UI: an addon registering for it is blocked.
local function kindAt(at, fighting)
	local function near(t)
		return math.abs(at - t) <= WINDOW
	end
	if near(questAt) then
		return "quest"
	elseif fighting or near(combatAt) then
		return "kill"
	elseif near(zoneAt) then
		return "explore"
	end
	return "other"
end

local function xpChanged()
	local me, now, before = ns.me(), read(), seen
	seen = now
	if not me or not before or now.max == 0 then
		return
	end
	-- XP only goes down at a level-up, whatever UnitLevel says at this moment.
	local gained = Encode.xpGained(before.cur, before.max, now.cur, now.cur < before.cur)
	if gained <= 0 then
		return
	end
	local at, fighting = GetTime(), UnitAffectingCombat("player")
	local row = { t = ns.now(), xp = gained, rested = math.max(0, before.rested - now.rested), instance = instance(), map = map(), level = UnitLevel("player") }
	-- What earned it may come just after the XP (a quest's event follows its XP), so wait a moment.
	ns.after(WINDOW, "xp", function()
		ns.append("xp", Encode.row(row.t, me.ref, row.xp, kindAt(at, fighting), row.rested > 0 and row.rested or nil, row.instance, row.map, row.level))
	end)
end

ns.on("PLAYER_ENTERING_WORLD", "xp", function()
	seen = read()
end)
ns.on("PLAYER_XP_UPDATE", "xp", xpChanged)
-- Rested XP grows while resting; a new reading keeps that from counting as rested XP spent.
ns.on("UPDATE_EXHAUSTION", "xp", function()
	if seen then
		seen.rested = GetXPExhaustion() or 0
	end
end)
ns.on("QUEST_TURNED_IN", "xp", function()
	questAt = GetTime()
end)
-- Combat's end: a kill's XP can come a moment after it.
ns.on("PLAYER_REGEN_ENABLED", "xp", function()
	combatAt = GetTime()
end)

-- Zones ------------------------------------------------------------------------------------------------

local lastZone

local function zoneChanged()
	local me, m = ns.me(), map()
	if not me or not m then
		return
	end
	zoneAt = GetTime()
	local here = m .. "," .. (instance() or "")
	if here == lastZone then
		return
	end
	lastZone = here
	ns.append("zone", Encode.row(ns.now(), me.ref, m, instance()))
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	ns.on(event, "zone", zoneChanged)
end
