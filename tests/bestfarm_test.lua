-- BestFarm.lua: after new prices (20 seconds after login, after a scan), one chat line when this character's best farm,
-- the mob whose loot is worth the most among those looted 10 times or more, is another than the one saved.

local NAMES = { [3260] = "Bristleback Quilboar", [3272] = "Kolkar Centaur" }

-- One load with the character's counts `byNpc`, item prices `prices` and the prices settings. Returns
-- prices() (the "pricesReady" event), login(), the lines said and the settings.
local function start(byNpc, prices, settings)
	local said, heard, on = {}, {}, {}
	settings = settings or { bestFarm = true }
	C_Map = { GetMapInfo = function(map) return map == 17 and { name = "Barrens" } or nil end }
	local ns = {
		listen = function(event, _, fn) heard[event] = fn end,
		module = function(name, def) on[name] = def.enable end,
		after = function(_, _, fn) fn() end,
		me = function() return { ref = 1 } end,
		settings = function(name) assert(name == "prices") return settings end,
		charMobStats = type(byNpc) == "function" and byNpc or function(char) assert(char == 1) return byNpc end,
		price = { worth = function(id) return prices[id] end },
		Catalogue = { name = function(kind, id) return kind == "npc" and NAMES[id] or nil end },
	}
	for _, file in ipairs({ "Views.lua", "ViewsSession.lua", "Money.lua", "Chat.lua", "BestFarm.lua" }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	ns.say = function(text) said[#said + 1] = ns.plainText(text) end
	ns.Money.paint(function() return "" end)
	return heard.pricesReady, on.BestFarm, said, settings
end

local function mob(loots, coin, map, items)
	return { loots = loots, coin = coin, map = map, items = items or {} }
end

-- The pick: the most a loot among mobs looted 10 times or more.
local function views()
	local ns = {}
	for _, file in ipairs({ "Views.lua", "ViewsSession.lua" }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	return ns.Views
end
local Views = views()
local worth = function(id) return ({ [2318] = 100 })[id] end
local best = Views.bestFarm({ [3260] = mob(10, 1000, 17, { [2318] = { dropped = 10, units = 20 } }), [3272] = mob(12, 1500, 15) }, worth)
eq(best and best.npc, 3260, "the most a loot, its items at their worth: (1000 + 20 × 100) / 10 = 300 over 1500 / 12 = 125")
eq(best.value, 300, "its worth a loot")
eq(best.map, 17, "and the map of its last loot")
eq(Views.bestFarm({ [3260] = mob(9, 90000, 17), [3272] = mob(10, 10, 15) }, worth).npc, 3272, "a mob looted under 10 times is no farm")
eq(Views.bestFarm({ [3260] = mob(9, 9000, 17) }, worth), nil, "none looted 10 times: no best")
eq(Views.bestFarm({ [3272] = mob(10, 100, 15), [3260] = mob(10, 100, 17) }, worth).npc, 3260, "a tie: the lower NPC ID, so the pick holds still")

-- Changed: one line, with the zone and the worth a loot, and the new best saved.
local counts = { [3260] = mob(10, 24000, 17), [3272] = mob(10, 1000, 15) }
local prices, login, said, settings = start(counts, {}, { bestFarm = true, bestFarmBy = { [1] = 3272 } })
login()
eq(said[1], "best farm now Bristleback Quilboar (Barrens), about 24s a loot (was Kolkar Centaur)", "the login check against last session's best")
eq(#said, 1, "one line")
eq(settings.bestFarmBy[1], 3260, "the new best is saved for this character")

-- Same: no line, after a scan as at login.
prices()
eq(#said, 1, "the same best after a scan: no line")

-- Changed after a scan: new prices make another mob the best.
counts[3272].items = { [2318] = { dropped = 10, units = 100 } }
local p = { [2318] = 500 }
prices, login, said, settings = start(counts, p, { bestFarm = true, bestFarmBy = { [1] = 3260 } })
prices()
eq(said[1], "best farm now Kolkar Centaur, about 51s a loot (was Bristleback Quilboar)", "after a scan; a map with no name: no zone")

-- First check, nothing saved: no line, the best saved.
prices, login, said, settings = start(counts, {}, { bestFarm = true })
login()
eq(#said, 0, "the first check ever: no line")
eq(settings.bestFarmBy[1], 3260, "but the best is saved, for the next check")

-- Off (the default): no line, nothing saved.
prices, login, said, settings = start(counts, {}, { bestFarmBy = { [1] = 3272 } })
login()
prices()
eq(#said, 0, "off: no line")
eq(settings.bestFarmBy[1], 3272, "off: nothing saved")

-- No mob looted 10 times: no line, the saved best kept.
prices, login, said, settings = start({ [3260] = mob(3, 99999, 17) }, {}, { bestFarm = true, bestFarmBy = { [1] = 3272 } })
prices()
eq(#said, 0, "no farm yet: no line")
eq(settings.bestFarmBy[1], 3272, "and the saved best kept")

-- Counts still being built: the check waits for them, once, then runs.
local waiters, built = {}, nil
local function lateCounts(_, whenBuilt)
	if built then return built end
	waiters[#waiters + 1] = whenBuilt
end
prices, login, said, settings = start(lateCounts, {}, { bestFarm = true, bestFarmBy = { [1] = 3272 } })
login()
prices()
eq(#waiters, 1, "a check while the counts are built waits once")
eq(#said, 0, "and says nothing yet")
built = counts
waiters[1]()
eq(said[1], "best farm now Bristleback Quilboar (Barrens), about 24s a loot (was Kolkar Centaur)", "once built, the check runs")
eq(#said, 1, "one line for the two checks that waited")
return checks()
