-- Gold Forever: after new prices, one chat line when this character's best farm changed (addon#99): the mob
-- whose loot is worth the most (Views.bestFarm, from MobStats' counts), checked at login (the companion's
-- prices file, against the best saved last session) and after every full scan of your own ("pricesReady").
-- Opt-in (prices.bestFarm); the last best is kept per character in settings (prices.bestFarmBy), not in a stream.

local _, ns = ...

local LOGIN_DELAY = 20 -- seconds after login, as MobStats builds its counts, not in the login's own frames

local function npcName(id)
	return ns.Catalogue.name("npc", id) or ("NPC " .. id)
end

local function zoneOf(map)
	local info = map and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(map)
	return info and info.name
end

local waiting = false -- a check waits for the counts to be built
local function check()
	local s = ns.settings("prices")
	local me = ns.me()
	if s.bestFarm ~= true or not me or waiting then
		return
	end
	local byNpc = ns.charMobStats(me.ref, function()
		waiting = false
		check()
	end)
	if not byNpc then
		waiting = true
		return
	end
	local best = ns.Views.bestFarm(byNpc, ns.price.worth)
	if not best then
		return
	end
	s.bestFarmBy = s.bestFarmBy or {}
	local last = s.bestFarmBy[me.ref]
	s.bestFarmBy[me.ref] = best.npc
	if not last or last == best.npc then
		return
	end
	local zone = zoneOf(best.map)
	ns.say(string.format("best farm now %s%s, about %s a loot (was %s)", npcName(best.npc), zone and (" (" .. zone .. ")") or "",
		ns.Money.auction(math.floor(best.value + 0.5)), npcName(last)))
end

ns.listen("pricesReady", "best farm", check)
ns.module("BestFarm", {
	requires = { "MobStats" },
	enable = function()
		ns.after(LOGIN_DELAY, "best farm", check)
	end,
})
