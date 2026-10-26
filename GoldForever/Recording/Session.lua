-- Gold Forever: the farming session. What the loot is worth, in coin and items, the gold and XP per
-- hour with the time to the next level, the kills, and when the bags will be full; big drops and quest
-- starters are called out as they come. The session survives a /reload. The HUD (Hud.lua) shows it.

local _, ns = ...
local Encode = ns.Encode
local Catalogue = ns.Catalogue

local IDLE_SECONDS = 15 * 60 -- the web app's session split
local SHORTEST = 10 * 60 -- an ended session shorter than this, first loot to last, is no session (the site's rule too)
local TOP_ITEMS = 4
local BIG_DROP = 10000 -- 1 gold: the default big-drop threshold
ns.BIG_DROP = BIG_DROP

local price = ns.price
local worth, itemInfo, disenchantWorth, enchanting, coins = price.worth, price.itemInfo, price.disenchant, price.enchanting, price.coins

local Session = {}
ns.Session = Session

-- { start, last, firstLoot, lastLoot, byHand, coin, items = { [id] = count }, xp, killXp, kills, bagBase,
-- bagBaseAt, bagFree }
local session

local function settings()
	return ns.settings("appraiser")
end

-- "Start and stop sessions by themselves": on (the default), loot or kill XP starts a session and 15
-- minutes without loot ends it; off, only the HUD's Start and Stop do.
local function automatic()
	return settings().autoSession ~= false
end

-- A session ends the way it started: one started with Start runs until Stop, whatever the toggle says now.
local function idle()
	return not session or session.stopped or (not session.byHand and GetTime() - session.last > IDLE_SECONDS)
end

-- Whether the session is shown: a running one, or an ended one of 10 minutes or more from its first loot
-- to its last.
local function counts()
	if idle() then
		return session ~= nil and session.firstLoot ~= nil and session.lastLoot - session.firstLoot >= SHORTEST
	end
	return true
end

-- Free slots in general-purpose bags (profession bags take only their own kind of item).
local function freeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, bagType = C_Container.GetContainerNumFreeSlots(bag)
		if (bagType or 0) == 0 then
			free = free + (n or 0)
		end
	end
	return free
end

local function fresh(now)
	local free = freeSlots()
	return {
		start = now, last = now, coin = 0, items = {},
		xp = 0, killXp = 0, kills = 0, xpKills = 0,
		bagBase = free, bagBaseAt = now, bagFree = free,
	}
end

-- The current session, started now when there is none or the last one went idle, if sessions start by
-- themselves; nil otherwise. A kill's XP comes before its loot, so either starts one.
local function current()
	local now = GetTime()
	if idle() then
		if not automatic() then
			return nil
		end
		session = fresh(now)
	end
	session.last = now
	return session
end

-- Bags: the fill rate from slots used since the baseline; selling or emptying bags (free slots go
-- up) starts a new baseline.
local function bagsChanged()
	if idle() then
		return
	end
	local free = freeSlots()
	if free > session.bagFree then
		session.bagBase, session.bagBaseAt = free, GetTime()
	end
	session.bagFree = free
end

-- XP: quest XP counts toward XP per hour, not per kill.
-- The XP bar now, for the time to the next level. The gains come from Levelling.lua, which tells
-- what earned each: only kills count toward "~N kills".
local xpSeen -- { cur, max, level }

local function readXp()
	return { cur = UnitXP("player"), max = UnitXPMax("player"), level = UnitLevel("player") }
end

-- Kills without the combat log (forbidden on Forever): a fight opens when combat starts and closes a
-- few seconds after it ends, once its loot is in; its kills are the larger of its kill-XP gains and the
-- creature corpses looted for the first time, so a grey mob counts too; a corpse looted after its
-- fight closed matches the kill XP already counted rather than counting again (Views.creditKills).
local FIGHT_GRACE = 8 -- seconds after combat for the kill XP (classified 3 s late) and the loot
local fight -- { xpKills, corpses = { guid } } while one is open
local corpsesSeen = {} -- corpse GUIDs already counted
local uncorpsed = {} -- times of kills credited by XP whose corpse is not looted yet (Views.creditKills)

local function closeFight()
	local f = fight
	fight = nil
	if f and not idle() then
		session.kills = session.kills + ns.Views.creditKills(uncorpsed, f.xpKills, f.corpses, corpsesSeen, GetTime())
	end
end

ns.on("PLAYER_REGEN_DISABLED", "session fights", function()
	closeFight() -- a new pull before the last fight's loot was in
	local f = { xpKills = 0, corpses = {} }
	fight = f
	ns.afterCombat("session fights", function()
		ns.after(FIGHT_GRACE, "session fights", function()
			if fight == f then
				closeFight()
			end
		end)
	end)
end)

table.insert(ns.xpListeners, function(gained, kind)
	local s = current()
	if not s then
		return
	end
	s.xp = s.xp + gained
	if kind == "kill" or kind == "boss" then
		s.killXp = s.killXp + gained
		s.xpKills = (s.xpKills or 0) + 1
		if fight then
			fight.xpKills = fight.xpKills + 1
		else
			-- a kill outside any fight (a pet's, a DoT's after combat)
			s.kills = s.kills + ns.Views.creditKills(uncorpsed, 1, nil, corpsesSeen, GetTime())
		end
	end
end)

local function number(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function itemsValue()
	local total, unpriced = 0, 0
	for id, n in pairs(session.items) do
		local w = worth(id)
		if w then
			total = total + w * n
		else
			unpriced = unpriced + n
		end
	end
	return total, unpriced
end

-- The session in words, from its figures (ns.sessionSummary).
local function text()
	local sum = ns.sessionSummary()
	if not sum then
		return automatic() and "Loot something to start a session." or "Press Start on the HUD to start a session."
	end
	local elapsed, r = sum.elapsed, sum.rates
	local lines = {
		string.format("%s%d:%02d", sum.ended and "Ended after " or "Farming ", math.floor(elapsed / 60), math.floor(elapsed % 60)),
		"Coin: " .. coins(sum.coin),
		"Items: " .. coins(sum.value) .. (sum.unpriced > 0 and string.format(" (+%d unpriced)", sum.unpriced) or ""),
		"|cffffffffTotal: " .. coins(r.total) .. "|r",
	}
	if r.rated then
		table.insert(lines, "|cffffd100Per hour: " .. coins(r.goldPerHour) .. "|r")
	else
		table.insert(lines, "|cff999999Per hour: after a minute|r")
	end
	-- XP, and when the next level comes at this pace (not at the level cap: no XP to gain).
	if sum.xp > 0 and xpSeen and xpSeen.max > 0 then
		local line = "XP: " .. number(sum.xp)
		if r.rated then
			line = line .. " · " .. number(r.xpPerHour) .. "/h · level " .. sum.nextLevel .. " in " .. Encode.duration(r.dingIn or 0)
		end
		if (session.xpKills or 0) > 0 and session.killXp > 0 then
			line = line .. string.format(" (~%s kills)", number(r.killsToLevel or 0))
		end
		table.insert(lines, line)
	end
	-- Bags: free slots, and when they run out at the rate they have been filling.
	local bags = "Bags: " .. sum.bagFree .. " free"
	if sum.bagFree == 0 then
		bags = "|cffff5555Bags full|r"
	elseif sum.fullIn then
		bags = bags .. " · full in ~" .. Encode.duration(sum.fullIn)
	end
	table.insert(lines, bags)
	-- The most valuable items so far.
	for i = 1, math.min(TOP_ITEMS, #sum.ranked) do
		local item = sum.ranked[i]
		local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item.id)) or ("item " .. item.id)
		table.insert(lines, string.format("|cffaaaaaa%d× %s: %s|r", item.n, name, item.value > 0 and coins(item.value) or "no price"))
	end
	return table.concat(lines, "\n")
end

-- The session in words, and its kills, for the tests.
ns.test.sessionText = text
ns.test.sessionKills = function()
	return session and session.kills
end

-- The seconds the session has run: an ended one stops its clock at its last loot (or at Stop).
local function elapsed()
	return (idle() and session.last or GetTime()) - session.start
end

-- The session in figures, for the HUD and the hub's Session page: nil before any session, or when the
-- last one is not shown (counts).
function ns.sessionSummary()
	if not counts() then
		return nil
	end
	local secs = elapsed()
	local value, unpriced = itemsValue()
	local toLevel = xpSeen and xpSeen.max > 0 and (xpSeen.max - xpSeen.cur) or 0
	local used = session.bagBase - session.bagFree
	local filling = GetTime() - session.bagBaseAt
	local ranked = {}
	for id, n in pairs(session.items) do
		ranked[#ranked + 1] = { id = id, n = n, value = (worth(id) or 0) * n }
	end
	table.sort(ranked, function(a, b)
		return a.value > b.value
	end)
	return {
		ended = idle(), elapsed = secs, coin = session.coin, value = value, unpriced = unpriced,
		rates = ns.Views.sessionRates(session, secs, value, toLevel),
		xp = session.xp, kills = session.kills, nextLevel = xpSeen and (xpSeen.level or 0) + 1,
		bagFree = session.bagFree,
		fullIn = session.bagFree > 0 and used >= 1 and filling >= 120 and session.bagFree / (used / filling) or nil,
		ranked = ranked,
		bigDrop = settings().bigDrop or BIG_DROP,
	}
end

-- What the item info gives for a looted item: quality and name.
function ns.sessionItem(id)
	local quality, _, _, _, name = itemInfo(id)
	return quality, name
end

-- What shows the session (the HUD) is told when it changes: "loot" and "restored" may bring it up,
-- "xp", "bags", "reset", "start", "stop" and "mode" redraw it.
local watchers = {}
function Session.watch(fn)
	watchers[#watchers + 1] = fn
end
local function changed(how)
	for _, fn in ipairs(watchers) do
		fn(how)
	end
end

-- For the HUD: the session (nil before any, or when it is not shown), whether it has ended, the toggle,
-- and Start and Stop, each recorded as a system event so the site's session is the game's.
function Session.get()
	return counts() and session or nil
end
Session.idle = idle
Session.automatic = automatic
function Session.setAutomatic(on)
	settings().autoSession = on and true or false
	changed("mode")
end
function Session.start()
	if not idle() then
		return
	end
	session = fresh(GetTime())
	session.byHand = true
	ns.sys("session_start")
	changed("start")
end
function Session.stop()
	if session and not idle() then
		session.stopped = true
		session.last = GetTime()
		ns.sys("session_stop")
		changed("stop")
	end
end

-- Big drops: an item worth the threshold or more (sold or, for an enchanter who can, disenchanted),
-- or any rare or better, gets a message mid-screen and a sound; so does a quest starter, once per
-- item a session (a starter known only from its tooltip cannot say whether its quest is done).
local startersAlerted = {} -- item ID -> true
local function bigDrops(taken)
	local threshold = settings().bigDrop or BIG_DROP
	for key, n in pairs(taken) do
		local id = Encode.itemId(key)
		local quality, _, _, _, name = itemInfo(id or 0)
		if id then
			local value = (worth(id) or 0) * n
			local de, skill = disenchantWorth(id)
			if de and enchanting() >= skill then
				value = math.max(value, de * n)
			end
			local quest = Catalogue.startsQuest(id)
			if quest and not Catalogue.questDone(quest) and not startersAlerted[id] then
				startersAlerted[id] = true
				local text = "Starts a quest: " .. (name or ("item " .. id))
				ns.alert(text .. " — right-click it in your bags to start it.")
			elseif not quest and ((threshold > 0 and value >= threshold) or (quality or 0) >= 3) then
				local text = string.format("Big drop: %s%s — %s", n > 1 and (n .. "× ") or "", name or ("item " .. id), value > 0 and coins(value) or "no price")
				ns.alert(text)
			end
		end
	end
end

table.insert(ns.lootListeners, function(coin, taken, rows)
	ns.safely("big drop", bigDrops, taken)
	if not current() then
		changed("loot") -- outside a session: the HUD offers Start
		return
	end
	local now = GetTime()
	session.firstLoot = session.firstLoot or now
	session.lastLoot = now
	-- Creature corpses looted for the first time: in the open fight, or a fight of their own.
	local corpses = {}
	for _, row in ipairs(rows or {}) do
		if row.first and row.guid then
			corpses[#corpses + 1] = row.guid
		end
	end
	if fight then
		for _, guid in ipairs(corpses) do
			table.insert(fight.corpses, guid)
		end
	elseif #corpses > 0 then
		session.kills = session.kills + ns.Views.creditKills(uncorpsed, 0, corpses, corpsesSeen, GetTime())
	end
	session.coin = session.coin + coin
	for key, n in pairs(taken) do
		local id = Encode.itemId(key)
		if id then
			session.items[id] = (session.items[id] or 0) + n
		end
	end
	changed("loot")
end)

-- A /reload (or a quick relog) keeps the session: it is saved when the file is written, and picked
-- up on load for the same character unless it went idle meanwhile. Times are kept as ages, since the
-- client's clock (GetTime) and the server's differ. A logout ends a session started with Start, as the
-- site ends every session at a logout: only a /reload keeps it.
ns.on("PLAYER_LOGOUT", "appraiser", function()
	local db, me = ns.db(), ns.me()
	if session and session.byHand and not ns.reloading() then
		Session.stop()
	end
	if not session or idle() or not me then
		db.appraiserSession = nil
		return
	end
	local now = GetTime()
	db.appraiserSession = {
		character = me.ref,
		savedAt = GetServerTime(),
		age = now - session.start,
		sinceLoot = now - session.last,
		sinceBagBase = now - session.bagBaseAt,
		sinceFirstLoot = session.firstLoot and now - session.firstLoot,
		sinceLastLoot = session.lastLoot and now - session.lastLoot,
		byHand = session.byHand,
		coin = session.coin,
		items = session.items,
		xp = session.xp,
		killXp = session.killXp,
		kills = session.kills,
		xpKills = session.xpKills,
		bagBase = session.bagBase,
	}
end)

local function restore(reloaded)
	local db, me = ns.db(), ns.me()
	local saved = db.appraiserSession
	db.appraiserSession = nil
	if not saved or not me or saved.character ~= me.ref or (saved.byHand and not reloaded) then
		return
	end
	local gap = math.max(0, GetServerTime() - (saved.savedAt or 0))
	if not saved.byHand and saved.sinceLoot + gap > IDLE_SECONDS then
		return
	end
	local now = GetTime()
	session = {
		start = now - saved.age - gap,
		last = now - saved.sinceLoot - gap,
		coin = saved.coin or 0,
		items = saved.items or {},
		xp = saved.xp or 0,
		killXp = saved.killXp or 0,
		kills = saved.kills or 0,
		xpKills = saved.xpKills or saved.kills or 0,
		bagBase = saved.bagBase or freeSlots(),
		bagBaseAt = now - (saved.sinceBagBase or 0) - gap,
		bagFree = freeSlots(),
		firstLoot = saved.sinceFirstLoot and now - saved.sinceFirstLoot - gap,
		lastLoot = saved.sinceLastLoot and now - saved.sinceLastLoot - gap,
		byHand = saved.byHand,
	}
	changed("restored")
end

-- XP is read again after every loading screen; a login or a /reload restores the session.
ns.module("Session", {
	requires = { "Store" },
	world = function(isInitialLogin, isReloadingUi)
		xpSeen = readXp()
		if isInitialLogin or isReloadingUi then
			restore(isReloadingUi)
		end
	end,
})
ns.on("PLAYER_XP_UPDATE", "appraiser", function()
	xpSeen = readXp()
	changed("xp")
end)
ns.on("BAG_UPDATE_DELAYED", "appraiser", function()
	bagsChanged()
	changed("bags")
end)

-- "/gf bigdrop 2" alerts on drops worth 2 gold or more; "/gf bigdrop 0" on rares only.
ns.commands.bigdrop = function(arg)
	local gold = tonumber(arg)
	if not gold then
		ns.say(string.format("big drops are worth %s or more, and every rare. /gf bigdrop <gold> changes it.", coins(settings().bigDrop or BIG_DROP)))
		return
	end
	settings().bigDrop = math.floor(gold * 10000)
	ns.say(string.format("big drops from %s.", gold > 0 and coins(gold * 10000) or "rare quality (no gold threshold)"))
end

-- "/gf session": the session in words, in the chat.
ns.commands.session = function()
	ns.say("\n" .. text())
end

ns.commands.reset = function()
	if not idle() then
		ns.sys("session_stop")
	end
	session = nil
	changed("reset")
	ns.say("farming session reset.")
end
