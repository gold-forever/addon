-- Gold Forever: game knowledge that exists nowhere else once WoW: Forever is gone — names and
-- levels of NPCs and objects the player meets, zone maps, what trainers teach, and the client's
-- API. Catalogue only: never anything about other players.

local _, ns = ...
local Encode = ns.Encode

-- NPCs -------------------------------------------------------------------------------------------

local levels = {} -- npc ID -> { min, max } seen this session, to widen the level range

-- A name worth keeping: readable (newer clients keep a restricted unit's name secret), not empty,
-- and not the client's "Unknown" for a name it has not loaded yet. nil otherwise: such a name is
-- never written, so a later real one fills the row (the server reads "" and "Unknown" as no name).
local function realName(v)
	v = ns.readable(v)
	if type(v) ~= "string" or v == "" or v == "?" or v == "Unknown" or v == UNKNOWNOBJECT or v == UNKNOWN then
		return nil
	end
	return v
end

-- A stored row's fields: name, minLevel, maxLevel, classification, type.
local function fields(row)
	local out = {}
	for v in string.gmatch((row or "") .. ",", "([^,]*),") do
		out[#out + 1] = v
	end
	return out
end

-- Units met while their identity was secret (in combat on newer clients): looked at again out of
-- combat, when the client shows them.
local missed = false
local seeAgain
local function miss()
	missed = true
	if ns.inCombat() then
		ns.afterCombat("npcs", seeAgain)
	end
end

local function seeUnit(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then
		return
	end
	local id = Encode.npcId(ns.readable(UnitGUID(unit)))
	if not id then
		if ns.secret(UnitGUID(unit)) then
			miss()
		end
		return
	end
	local npcs = ns.db().catalogue.npcs
	local stored = npcs[id] and fields(npcs[id])
	local named = stored and realName(stored[1]) and stored[1] -- already encoded
	local name = realName(UnitName(unit))
	if not name then
		miss()
	end
	local level = ns.readable(UnitLevel(unit))
	if type(level) ~= "number" or level <= 0 then
		-- "??": too far above the player to show; the range stays as it was. A row without a name
		-- still takes one.
		if stored and not named and name then
			stored[1] = Encode.name(name)
			npcs[id] = table.concat(stored, ",")
		end
		return
	end
	local range = levels[id]
	if not range and stored then
		range = { tonumber(stored[2]), tonumber(stored[3]) }
	end
	if range and range[1] and range[2] and level >= range[1] and level <= range[2] and (named or not name) then
		levels[id] = range
		return
	end
	range = range or {}
	range[1] = math.min(range[1] or level, level)
	range[2] = math.max(range[2] or level, level)
	levels[id] = range
	local kind = ns.readable(UnitCreatureType(unit))
	local classification = ns.readable(UnitClassification(unit))
	npcs[id] = Encode.row(name and Encode.name(name) or named or "", range[1], range[2],
		classification or (stored and stored[4]) or nil, kind and Encode.name(kind) or (stored and stored[5]) or nil)
end

ns.on("PLAYER_TARGET_CHANGED", "npcs", function()
	seeUnit("target")
end)
ns.on("UPDATE_MOUSEOVER_UNIT", "npcs", function()
	seeUnit("mouseover")
end)
ns.on("NAME_PLATE_UNIT_ADDED", "npcs", seeUnit)
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW",
	"TRAINER_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
	ns.on(event, "npcs", function()
		seeUnit("npc")
	end)
end

-- Out of combat, and at a corpse's loot window, the units around are looked at again when one was
-- met unreadable: what combat hid is shown now.
function seeAgain()
	if not missed then
		return
	end
	missed = false
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		seeUnit(unit)
	end
	for i = 1, 40 do
		seeUnit("nameplate" .. i)
	end
end
ns.on("LOOT_READY", "npcs", seeAgain)

-- Objects: a gathering or opening cast names its target; the loot window that follows gives the
-- object's ID.
local cast -- { name, at }

-- A cast on a unit (a buff on oneself or a friend, a spell on a mob) names no object: it is never
-- kept, so no player's name can end up as an object's (design 002: no other players' names).
local function onUnit(target)
	for _, unit in ipairs({ "player", "target", "mouseover", "focus" }) do
		if UnitExists(unit) and ns.readable(UnitName(unit)) == target then
			return true
		end
	end
	return false
end

ns.on("UNIT_SPELLCAST_SENT", "objects", function(unit, target)
	if unit ~= "player" then
		return
	end
	-- Every cast replaces the last, so an older cast never names the next loot.
	target = realName(target)
	cast = target and not onUnit(target) and { name = target, at = GetTime() } or nil
end, "player")
ns.on("LOOT_READY", "objects", function()
	local id = ns.lootSource and string.match(ns.lootSource, "^o(%d+)$")
	if id and cast and GetTime() - cast.at < 10 then
		ns.db().catalogue.objects[tonumber(id)] = Encode.name(cast.name)
	end
	cast = nil
end)

-- Objects by tooltip: mousing over a herb, vein, chest or fishing pool shows a tooltip whose
-- data carries the object's GUID on newer clients.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	-- A mob's tooltip names it too: a catalogued mob still without a name takes the name it shows.
	local function objectTooltip(_, data)
		-- The GUID and the first line are secret for a unit whose identity the client keeps.
		local guid = data and ns.readable(data.guid)
		local src = guid and type(guid) == "string" and Encode.source(guid)
		local kind, id
		if src then
			kind, id = string.match(src, "^([on])(%d+)$")
		end
		local line = id and data.lines and data.lines[1] and realName(data.lines[1].leftText)
		if not (line and ns.db()) then
			return
		end
		id = tonumber(id)
		local catalogue = ns.db().catalogue
		if kind == "o" then
			catalogue.objects[id] = Encode.name(line)
		elseif catalogue.npcs[id] then
			local stored = fields(catalogue.npcs[id])
			if not realName(stored[1]) then
				stored[1] = Encode.name(line)
				catalogue.npcs[id] = table.concat(stored, ",")
			end
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(_, data)
		ns.safely("objects", objectTooltip, _, data)
	end)
end

-- Maps -------------------------------------------------------------------------------------------

local function seeMap()
	local maps = ns.db().catalogue.maps
	local map = C_Map.GetBestMapForUnit("player")
	while map and map ~= 0 and not maps[map] do
		local info = C_Map.GetMapInfo(map)
		if not info then
			return
		end
		maps[map] = Encode.row(Encode.name(info.name or "?"), info.mapType, info.parentMapID)
		map = info.parentMapID
	end
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	ns.on(event, "maps", seeMap)
end

-- Map art: which texture files draw each map, and how they tile. The web app draws routes over
-- the zone's own map, cut from the player's installed client by tools/maps (never from the web).
-- Read once per client build, every map with art, a batch a frame-step so the login does not stall.
-- db.mapArt = { build, maps = { [uiMapID] = "layerWidth,layerHeight,tileWidth,tileHeight;id+id+…" },
--   rects = { [uiMapID] = "continentID,left,right,top,bottom" } }: where each map lies on its
--   continent (0–1), so the web app can tile zones together into one map.
local MAP_IDS = 3000 -- uiMapIDs searched; Classic's are well under it
local MAP_BATCH = 100

local function readMapArt(manual)
	local db = ns.db()
	local build = db.client and db.client.build
	if not manual and (ns.lean or (db.mapArt and db.mapArt.build == build and db.mapArt.rects)) then
		return
	end
	if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures and C_Map.GetMapInfo) then
		return
	end
	local maps, rects = {}, {}
	local id = 0
	local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	local function continentOf(map)
		for _ = 1, 10 do
			local info = C_Map.GetMapInfo(map)
			if not info then
				return nil
			end
			if info.mapType == CONTINENT then
				return map
			end
			map = info.parentMapID
		end
	end
	local function step()
		local last = math.min(MAP_IDS, id + MAP_BATCH)
		for map = id + 1, last do
			local layers = C_Map.GetMapInfo(map) and C_Map.GetMapArtLayers(map)
			local layer = layers and layers[1]
			local textures = layer and C_Map.GetMapArtLayerTextures(map, 1)
			if textures and #textures > 0 then
				maps[map] = string.format("%d,%d,%d,%d;%s", layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight,
					table.concat(textures, "+"))
				local continent = C_Map.GetMapRectOnMap and continentOf(map)
				if continent and continent ~= map then
					local left, right, top, bottom = C_Map.GetMapRectOnMap(map, continent)
					if left and right and right > left then
						rects[map] = string.format("%d,%.5f,%.5f,%.5f,%.5f", continent, left, right, top, bottom)
					end
				end
			end
		end
		id = last
		if id < MAP_IDS then
			ns.after(0.05, "map art", step)
		else
			db.mapArt = { build = build, t = ns.now(), maps = maps, rects = rects }
			if manual then
				local n = 0
				for _ in pairs(maps) do
					n = n + 1
				end
				ns.say(string.format("map art of %d maps recorded; /reload to write it.", n))
			end
		end
	end
	step()
end

ns.commands.maps = function()
	readMapArt(true)
end

-- Trainers ---------------------------------------------------------------------------------------

local FILTERS = { "available", "unavailable", "used" }

-- Everything the trainer teaches, with cost and requirements, keyed by trainer NPC. Every filter
-- is switched on while reading, then put back as the player had it.
local function readTrainerNow()
	local id = Encode.npcId(ns.readable(UnitGUID("npc")))
	if not id or not GetNumTrainerServices then
		return
	end
	local saved = {}
	if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
		for _, f in ipairs(FILTERS) do
			saved[f] = GetTrainerServiceTypeFilter(f)
			SetTrainerServiceTypeFilter(f, true)
		end
	end
	local rows = {}
	local classSpells = false -- spells with a level and no profession skill: a class trainer
	for i = 1, GetNumTrainerServices() do
		local name, category, icon = GetTrainerServiceInfo(i)
		if name and category ~= "header" then
			local skill, skillRank = nil, nil
			if GetTrainerServiceSkillReq then
				skill, skillRank = GetTrainerServiceSkillReq(i)
			end
			local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
			local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
			classSpells = classSpells or (not skill and (level or 0) > 0)
			rows[#rows + 1] = Encode.row(Encode.name(name), category, icon, cost,
				skill and Encode.name(skill) or nil, skillRank, level)
		end
	end
	for f, on in pairs(saved) do
		SetTrainerServiceTypeFilter(f, on and true or false)
	end
	-- One string per trainer, rows joined by ";" like a stream chunk. An empty read is the window gone
	-- before it was read, not a trainer with nothing to teach: the stored list stays.
	if #rows > 0 then
		local catalogue = ns.db().catalogue
		catalogue.trainers[id] = table.concat(rows, ";")
		-- A class trainer teaches only the visitor's class: kept, for the training ahead at a level-up.
		if classSpells then
			catalogue.trainerClasses = catalogue.trainerClasses or {}
			catalogue.trainerClasses[id] = select(2, UnitClass("player"))
		end
	end
end

-- At a level-up: what is new at the character's class trainer, and what it costs, from the trainers
-- seen (any character of the class, any save).
ns.on("PLAYER_LEVEL_UP", "training", function(level)
	level = tonumber(level)
	local catalogue = ns.db().catalogue
	local class = select(2, UnitClass("player"))
	if not level or not catalogue.trainerClasses then
		return
	end
	local spells, cost, seen = {}, 0, {}
	for trainer, trainerClass in pairs(catalogue.trainerClasses) do
		if trainerClass == class and catalogue.trainers[trainer] then
			for row in string.gmatch(catalogue.trainers[trainer], "[^;]+") do
				local name, _, _, price, skill, _, at = strsplit(",", row)
				if tonumber(at) == level and skill == "" and not seen[name] then
					seen[name] = true
					spells[#spells + 1] = name
					cost = cost + (tonumber(price) or 0)
				end
			end
		end
	end
	if #spells > 0 then
		ns.say(string.format("level %d: %s at your trainer, %s.", level, table.concat(spells, ", "), Encode.money(cost)))
	end
end)

-- Switching the filters while reading may fire TRAINER_UPDATE, which would read again, and again: an
-- update while reading is the read's own.
local reading = false
local function readTrainer()
	reading = true
	local ok, err = pcall(readTrainerNow)
	reading = false
	if not ok then
		error(err, 0)
	end
end

local trainerSoon = ns.throttle("trainer", 1, readTrainer)
ns.on("TRAINER_SHOW", "trainer", function()
	ns.after(0.5, "trainer", readTrainer)
end)
ns.on("TRAINER_UPDATE", "trainer", function()
	if not reading then
		trainerSoon()
	end
end)

-- Client API -------------------------------------------------------------------------------------

-- The names of every C_ namespace's functions, once per client build: Forever-only APIs (Legacy
-- perks, for one) can then be found after the client is gone.
local function dumpApi()
	local db = ns.db()
	local build = db.client and db.client.build
	if db.api and db.api.build == build then
		return
	end
	local api = { build = build, namespaces = {}, globals = {} }
	for name, value in pairs(_G) do
		if type(name) == "string" then
			if type(value) == "table" and string.find(name, "^C_") then
				local functions = {}
				-- A protected namespace may refuse to be walked; skip it, keep the rest.
				pcall(function()
					for key, v in pairs(value) do
						if type(v) == "function" then
							functions[#functions + 1] = key
						end
					end
				end)
				table.sort(functions)
				api.namespaces[name] = table.concat(functions, " ")
			elseif type(value) == "function" and (string.find(name, "Legacy") or string.find(name, "Forever")
				or string.find(name, "Favor")) then
				api.globals[#api.globals + 1] = name
			end
		end
	end
	table.sort(api.globals)
	api.globals = table.concat(api.globals, " ")
	if Enum then
		local enums = {}
		for name in pairs(Enum) do
			enums[#enums + 1] = name
		end
		table.sort(enums)
		api.enums = table.concat(enums, " ")
	end
	db.api = api
end

-- Game rules -------------------------------------------------------------------------------------

-- A plain copy of an API result, depth- and size-limited, for the saved file.
local function copy(value, depth)
	if type(value) ~= "table" then
		if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
			return type(value)
		end
		return value
	end
	if depth <= 0 then
		return "…"
	end
	local out, n = {}, 0
	for k, v in pairs(value) do
		n = n + 1
		if n > 200 then
			break
		end
		if type(k) == "string" or type(k) == "number" then
			out[k] = copy(v, depth - 1)
		end
	end
	return out
end

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local results = { pcall(fn, ...) }
	if not results[1] then
		return nil
	end
	table.remove(results, 1)
	if #results <= 1 then
		return copy(results[1], 4)
	end
	return copy(results, 4)
end

-- The realm's ruleset and Forever's settings, per character since realms differ (checklist #8).
local function readGameRules()
	local me = ns.me()
	local rules = C_GameRules
	if not me or not rules then
		return
	end
	local active = {}
	for name, id in pairs(Enum and Enum.GameRule or {}) do
		local ok, on = pcall(rules.IsGameRuleActive, id)
		if ok and on then
			local okValue, value = pcall(rules.GetGameRuleAsFloat, id)
			active[name] = okValue and value or true
		end
	end
	me.gameRules = {
		t = ns.now(),
		mode = call(rules.GetActiveGameMode),
		modeRecord = call(rules.GetCurrentGameModeRecordID),
		modeInfo = call(rules.GetCurrentGameModeDisplayInfo),
		foreverExperience = call(rules.GetForeverExperiencePreset),
		hardcore = call(rules.IsHardcoreActive),
		selfFound = call(rules.IsSelfFoundAllowed),
		standard = call(rules.IsStandard),
		rulesets = C_Roleset and call(C_Roleset.GetActiveAllowedRolesets) or nil,
		active = active,
	}
end

ns.module("Knowledge", {
	requires = { "Store" },
	enable = function()
		ns.after(10, "map art", readMapArt)
	end,
	-- The map is seen on every zone change, a loading screen's too; the API and the game rules are read
	-- again after every loading screen.
	world = function()
		ns.safely("maps", seeMap)
		ns.after(10, "api", dumpApi)
		ns.after(6, "gameRules", readGameRules)
	end,
})

-- Legacy perks ------------------------------------------------------------------------------------

-- No API is named for Legacy, so /gf legacy finds it: every C_ function is watched (hooksecurefunc
-- does not taint), the Legacy window is opened, and the read-only functions only the window calls
-- are called again with the same arguments and their results kept. Watching stays on until the
-- next /reload.
local hooked = false
local phase -- "before" while measuring the background, "open" while the window is open
local seen = {} -- "C_X.Fn" -> { phase, args }

local function hookAll()
	if hooked then
		return
	end
	hooked = true
	for name, namespace in pairs(_G) do
		if type(name) == "string" and string.find(name, "^C_") and type(namespace) == "table" then
			local functions = {}
			pcall(function()
				for fn, f in pairs(namespace) do
					if type(f) == "function" then
						functions[#functions + 1] = fn
					end
				end
			end)
			for _, fn in ipairs(functions) do
				local key = name .. "." .. fn
				pcall(hooksecurefunc, namespace, fn, function(...)
					if phase and not seen[key] then
						seen[key] = { phase = phase, args = { ... } }
					end
				end)
			end
		end
	end
end

local function finishTrace()
	phase = nil
	local found = {}
	for key, s in pairs(seen) do
		if s.phase == "open" then
			local namespace, fn = string.match(key, "^([^.]+)%.(.+)$")
			local entry = { args = copy(s.args, 3) }
			if string.find(fn, "^Get") or string.find(fn, "^Is") or string.find(fn, "^Has") or string.find(fn, "^Can") then
				entry.result = call(_G[namespace][fn], unpack(s.args))
			end
			found[key] = entry
		end
	end
	ns.db().legacyTrace = { t = ns.now(), calls = found }
	local n = 0
	for _ in pairs(found) do
		n = n + 1
	end
	ns.say(string.format("the Legacy window called %d functions; saved. /reload to stop watching.", n))
end

ns.commands.legacy = function()
	hookAll()
	seen = {}
	phase = "before"
	ns.say("watching the API for 3 s, then opening the Legacy window…")
	ns.after(3, "legacy", function()
		phase = "open"
		if not pcall(ToggleLegacySystemUI) and LegacySystemFrame_LoadUI then
			pcall(LegacySystemFrame_LoadUI)
			pcall(ToggleLegacySystemUI)
		end
		ns.say("open the Legacy window if it did not open, and click through its pages — 20 s.")
		ns.after(20, "legacy", finishTrace)
	end)
end
