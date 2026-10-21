-- Gold Forever: the levelling history. Every level-up with the time played (`level` rows), every
-- XP gain with where it came from (`xp` rows), and every zone entered (`zone` rows), so the web app
-- can show how long each level took, in game and in real time, where its XP came from and where it
-- was spent. Gold per level comes from the `money` stream, between two level rows. Bosses killed
-- (`boss` rows) and the instance in each zone row make a dungeon run's report: its XP, from bosses
-- and the rest.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.level = "t,char,kind,level,played,levelPlayed,money,map,x,y"
ns.FIELDS.xp = "t,char,xp,kind,rested,instance,map,level,x,y"
ns.FIELDS.zone = "t,char,map,instance,instanceId"
ns.FIELDS.boss = "t,char,encounter,name,difficulty,size,success,map,instanceId"
ns.FIELDS.instance = "name,type"

local WINDOW = 3 -- seconds between an XP gain and what earned it (a kill, a quest, a new zone)
local PLAYED_TIMEOUT = 10 -- seconds to wait for /played before writing a level row without it

local function instance()
	local inside, kind = IsInInstance()
	return inside and kind ~= "none" and kind or nil
end

-- The instance the player is in (its ID, with its name kept in the catalogue), nil outside one.
local function instanceId()
	if not instance() or not GetInstanceInfo then
		return nil
	end
	local name, kind, _, _, _, _, _, id = GetInstanceInfo()
	if id then
		local catalogue = ns.db().catalogue
		catalogue.instances = catalogue.instances or {}
		catalogue.instances[id] = Encode.row(Encode.name(name or "?"), kind)
	end
	return id
end

local function map()
	return C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player") or nil
end

-- Time played --------------------------------------------------------------------------------------

-- /played without the chat line: chat frames stop listening while the addon asks, and listen again
-- once every answer is in. Answers come in the order asked, so each goes to its own request (a
-- level-up soon after a login asks twice).
local asked = {} -- level rows waiting for their time played: { t, kind, level, money, map }, oldest first
local muted = {} -- chat frames that stopped listening for these requests

local function unmute()
	for _, f in ipairs(muted) do
		f:RegisterEvent("TIME_PLAYED_MSG")
	end
	muted = {}
end

local function write(p, played, levelPlayed)
	local me = ns.me()
	if me then
		ns.append("level", Encode.row(p.t, me.ref, p.kind, p.level, played, levelPlayed, p.money, p.map, p.x, p.y))
	end
end

-- [t] is when it happened (a level-up, a login), not when /played is asked a moment later: the web
-- app splits levels there.
local function askPlayed(kind, level, t)
	local request = { t = t, kind = kind, level = level, money = GetMoney() }
	request.map, request.x, request.y = ns.position() -- where: the levelling map (no coordinates in instances)
	if not RequestTimePlayed then
		write(request)
		return
	end
	asked[#asked + 1] = request
	for i = 1, NUM_CHAT_WINDOWS or 10 do
		local f = _G["ChatFrame" .. i]
		if f and f:IsEventRegistered("TIME_PLAYED_MSG") then
			f:UnregisterEvent("TIME_PLAYED_MSG")
			muted[#muted + 1] = f
		end
	end
	RequestTimePlayed()
	ns.after(PLAYED_TIMEOUT, "played", function()
		for i, waiting in ipairs(asked) do
			if waiting == request then
				table.remove(asked, i)
				write(request) -- no answer came: the row without its time played
				break
			end
		end
		if #asked == 0 then
			unmute()
		end
	end)
end

ns.on("TIME_PLAYED_MSG", "played", function(total, thisLevel)
	local request = table.remove(asked, 1)
	if request then
		write(request, total, thisLevel)
	end
	-- After this event has reached every listener, so the muted frames skip this one.
	if #asked == 0 then
		C_Timer.After(0, function()
			ns.safely("played", unmute)
		end)
	end
end)

-- A login row tells when the current level started even when its level-up was never seen.
ns.on("PLAYER_ENTERING_WORLD", "levelling", function(isInitialLogin)
	if isInitialLogin then
		local t = ns.now()
		ns.after(3, "played", function()
			askPlayed("login", UnitLevel("player"), t)
		end)
	end
end)

ns.on("PLAYER_LEVEL_UP", "levelling", function(level)
	local reached, t = tonumber(level) or UnitLevel("player"), ns.now()
	-- The time played this level restarts at the level-up; asked a moment later, it has.
	ns.after(1, "played", function()
		askPlayed("up", reached, t)
	end)
end)

-- XP -------------------------------------------------------------------------------------------------

local seen -- { cur, max, rested }: the last reading
local questAt, combatAt, zoneAt, bossAt, exploredAt = -math.huge, -math.huge, -math.huge, -math.huge, -math.huge

local function read()
	return { cur = UnitXP("player"), max = UnitXPMax("player"), rested = GetXPExhaustion() or 0 }
end

-- What earned XP gained at `at`: a quest handed in, a boss killed, a place discovered (the game's
-- "Discovered …: N experience gained"), a kill (XP while in combat, or just after it), a new zone
-- (exploration the message missed), else something else (a profession, an event). The combat log would
-- name the kill, but the client keeps it for the Blizzard UI: an addon registering for it is blocked.
local function kindAt(at, fighting)
	local function near(t)
		return math.abs(at - t) <= WINDOW
	end
	if near(questAt) then
		return "quest"
	elseif near(bossAt) then
		return "boss"
	elseif near(exploredAt) then
		return "explore"
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
	local row = { t = ns.now(), xp = gained, rested = math.max(0, before.rested - now.rested), instance = instance(), level = UnitLevel("player") }
	row.map, row.x, row.y = ns.position() -- where it was earned (no coordinates in instances)
	-- What earned it may come just after the XP (a quest's event follows its XP), so wait a moment.
	ns.after(WINDOW, "xp", function()
		local kind = kindAt(at, fighting)
		ns.append("xp", Encode.row(row.t, me.ref, row.xp, kind, row.rested > 0 and row.rested or nil, row.instance, row.map, row.level, row.x, row.y))
		for _, listener in ipairs(ns.xpListeners) do
			ns.safely("xp listener", listener, row.xp, kind)
		end
	end)
end

ns.on("PLAYER_ENTERING_WORLD", "xp", function()
	seen = read()
end)
ns.on("PLAYER_XP_UPDATE", "xp", xpChanged)
-- Rested XP grows while resting; taking the rise keeps it from counting as rested XP spent. A fall is
-- XP being earned, which the XP update counts (whichever of the two events comes first).
ns.on("UPDATE_EXHAUSTION", "xp", function()
	local rested = GetXPExhaustion() or 0
	if seen and rested > seen.rested then
		seen.rested = rested
	end
end)
ns.on("QUEST_TURNED_IN", "xp", function()
	questAt = GetTime()
end)
-- A boss fight's end: won, its kill's XP is boss XP. Every fight is kept, wipes too.
ns.on("ENCOUNTER_END", "boss", function(encounter, name, difficulty, size, success)
	local me = ns.me()
	if not me then
		return
	end
	if success == 1 then
		bossAt = GetTime()
	end
	ns.append("boss", Encode.row(ns.now(), me.ref, encounter, Encode.name(name or "?"), difficulty, size, success == 1, map(), instanceId()))
end)

-- "Discovered Razor Hill: 55 experience gained", as a pattern from the client's own text.
local DISCOVERED = Encode.pattern(ERR_ZONE_EXPLORED_XP or "Discovered %s: %d experience gained")

local function discovered(message)
	-- A message the client keeps from addons (in combat) cannot be read; that is no discovery.
	local ok, found = pcall(string.find, message, DISCOVERED)
	if ok and found then
		exploredAt = GetTime()
	end
end
ns.on("UI_INFO_MESSAGE", "explore", function(_, message)
	discovered(message)
end)
ns.on("CHAT_MSG_SYSTEM", "explore", discovered)

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
	local id = instanceId()
	local here = m .. "," .. (instance() or "") .. "," .. (id or "")
	if here == lastZone then
		return
	end
	lastZone = here
	ns.append("zone", Encode.row(ns.now(), me.ref, m, instance(), id))
end

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	ns.on(event, "zone", zoneChanged)
end
