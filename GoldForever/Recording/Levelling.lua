-- Gold Forever: the levelling history. Every level-up with the time played (`level` rows), every
-- XP gain with where it came from (`xp` rows), and every zone entered (`zone` rows), so the web app
-- can show how long each level took, in game and in real time, where its XP came from and where it
-- was spent. Gold per level comes from the `money` stream, between two level rows. Bosses killed
-- (`boss` rows) and the instance in each zone row make a dungeon run's report: its XP, from bosses
-- and the rest.

local _, ns = ...
local Encode = ns.Encode

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
		ns.record("level", { t = p.t, char = me.ref, kind = p.kind, level = p.level, played = played, levelPlayed = levelPlayed, money = p.money, map = p.map, x = p.x, y = p.y })
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
local function loggedIn()
	local t = ns.now()
	ns.after(3, "played", function()
		askPlayed("login", UnitLevel("player"), t)
	end)
end

ns.on("PLAYER_LEVEL_UP", "levelling", function(level)
	local reached, t = tonumber(level) or UnitLevel("player"), ns.now()
	-- The time played this level restarts at the level-up; asked a moment later, it has.
	ns.after(1, "played", function()
		askPlayed("up", reached, t)
	end)
end)

-- XP -------------------------------------------------------------------------------------------------

local seen -- { cur, max, rested }: the last reading
local zoneAt, bossAt, exploredAt, gatheredAt = -math.huge, -math.huge, -math.huge, -math.huge

-- Herb Gathering, Mining and Skinning, each rank's ID. A client's own gathering spells (retail's, one an
-- expansion) share the base spell's name, so a cast of that name in the client's language counts too.
local GATHERING = { [2366] = true, [2368] = true, [3570] = true, [11993] = true, [2575] = true, [2576] = true,
	[3564] = true, [10248] = true, [8613] = true, [8617] = true, [8618] = true, [10768] = true }
local GATHERING_BASE = { 2366, 2575, 8613 }

local function spellName(id)
	if C_Spell and C_Spell.GetSpellName then
		return C_Spell.GetSpellName(id)
	end
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end

local function gathering(spell)
	if GATHERING[spell] then
		return true
	end
	local name = spellName(spell)
	if not name then
		return false
	end
	for _, base in ipairs(GATHERING_BASE) do
		if spellName(base) == name then
			return true
		end
	end
	return false
end

local function read()
	return { cur = UnitXP("player"), max = UnitXPMax("player"), rested = GetXPExhaustion() or 0 }
end

-- What earned XP gained at `at`: a quest handed in, a boss killed, a place discovered (the game's
-- "Discovered …: N experience gained"), a kill (XP while in combat), a herb, vein or corpse gathered
-- (unless the client told of a kill), a kill just after a fight, a new zone (exploration the message
-- missed), else something else (a profession, an event). The combat log would name the kill, but the client keeps
-- it for the Blizzard UI: an addon registering for it is blocked.
local function kindAt(at, fighting, killTold)
	local function near(t)
		return math.abs(at - t) <= WINDOW
	end
	if near(ns.questAt or -math.huge) then
		return "quest"
	elseif near(bossAt) then
		return "boss"
	elseif near(exploredAt) then
		return "explore"
	elseif fighting then
		return "kill"
	elseif near(gatheredAt) and not killTold then
		return "gather"
	elseif near(ns.combatEnded()) then
		return "kill"
	elseif near(zoneAt) then
		return "explore"
	end
	return "other"
end

-- The kills the client told of since the last reading ("Kobold dies, you gain 120 experience."), each
-- its XP and mob, or false where the client kept the message secret. It tells each kill as it comes and
-- raises the XP bar once for kills close together, so one reading can hold several.
local kills = {}
local KILLED = Encode.pattern(COMBATLOG_XPGAIN_FIRSTPERSON or "%s dies, you gain %d experience.")

ns.on("CHAT_MSG_COMBAT_XP_GAIN", "xp", function(message)
	if ns.secret(message) then
		kills[#kills + 1] = false
		return
	end
	local mob, xp = string.match(message or "", KILLED)
	if xp then
		kills[#kills + 1] = { xp = tonumber(xp), mob = Encode.text(mob) }
	end
end)

-- A gain split into the kills told: each its own XP and mob, those kept secret sharing what is left
-- evenly, unnamed. One share for the whole gain when fewer than two were told (named for a kill told
-- with that very XP), or the XP told does not fit the gain.
local function shares(gained, told)
	if #told < 2 then
		local kill = told[1]
		return { { xp = gained, mob = kill and kill.xp == gained and kill.mob or nil } }
	end
	local known, secret = 0, 0
	for _, kill in ipairs(told) do
		if kill then
			known = known + kill.xp
		else
			secret = secret + 1
		end
	end
	local left = gained - known
	if left < 0 or (secret == 0 and left > 0) or (secret > 0 and left < secret) then
		return { { xp = gained } }
	end
	local out, sum = {}, 0
	for i, kill in ipairs(told) do
		out[i] = kill or { xp = math.floor(left / secret) }
		sum = sum + out[i].xp
	end
	-- What an even split leaves over goes to the last kill.
	out[#out].xp = out[#out].xp + gained - sum
	return out
end

local function xpChanged()
	local me, now, before, told = ns.me(), read(), seen, kills
	seen, kills = now, {}
	if not me or not before or now.max == 0 then
		return
	end
	-- XP only goes down at a level-up, whatever UnitLevel says at this moment.
	local gained = Encode.xpGained(before.cur, before.max, now.cur, now.cur < before.cur)
	if gained <= 0 then
		return
	end
	local at, fighting = GetTime(), UnitAffectingCombat("player")
	local row = { t = ns.now(), rested = math.max(0, before.rested - now.rested), instance = instance(), level = UnitLevel("player") }
	row.map, row.x, row.y = ns.position() -- where it was earned (no coordinates in instances)
	-- What earned it may come just after the XP (a quest's event follows its XP), so wait a moment.
	ns.after(WINDOW, "xp", function()
		local kind = kindAt(at, fighting, #told > 0)
		local split = kind == "kill" and shares(gained, told) or { { xp = gained } }
		local restedLeft = row.rested
		for i, share in ipairs(split) do
			local xp = share.xp
			-- The rested XP spent, shared in proportion to each kill's XP.
			local rested = i == #split and restedLeft or math.floor(row.rested * xp / gained)
			restedLeft = restedLeft - rested
			ns.record("xp", { t = row.t, char = me.ref, xp = xp, kind = kind, rested = rested > 0 and rested or nil, instance = row.instance, map = row.map, level = row.level, x = row.x, y = row.y, mob = share.mob })
			for _, listener in ipairs(ns.xpListeners) do
				ns.safely("xp listener", listener, xp, kind)
			end
		end
	end)
end

ns.on("PLAYER_XP_UPDATE", "xp", xpChanged)
-- Rested XP grows while resting; taking the rise keeps it from counting as rested XP spent. A fall is
-- XP being earned, which the XP update counts (whichever of the two events comes first).
ns.on("UPDATE_EXHAUSTION", "xp", function()
	local rested = GetXPExhaustion() or 0
	if seen and rested > seen.rested then
		seen.rested = rested
	end
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
	ns.record("boss", { t = ns.now(), char = me.ref, encounter = encounter, name = Encode.name(name or "?"), difficulty = difficulty, size = size, success = success == 1, map = map(), instanceId = instanceId() })
end)

-- A gathering spell cast: a herb picked, a vein mined, a corpse skinned.
ns.on("UNIT_SPELLCAST_SUCCEEDED", "gather", function(unit, _, spell)
	if unit == "player" and gathering(spell) then
		gatheredAt = GetTime()
	end
end, "player")

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
	ns.record("zone", { t = ns.now(), char = me.ref, map = m, instance = instance(), instanceId = id })
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	ns.on(event, "zone", zoneChanged)
end

-- At a loading screen: the login row at a login, XP read again, and the zone, as at any zone change.
ns.module("Levelling", {
	requires = { "Store" },
	world = function(isInitialLogin)
		if isInitialLogin then
			loggedIn()
		end
		ns.safely("xp", function()
			seen, kills = read(), {}
		end)
		ns.safely("zone", zoneChanged)
	end,
})
