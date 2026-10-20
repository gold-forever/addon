-- Gold Forever: game knowledge that exists nowhere else once WoW: Forever is gone — names and
-- levels of NPCs and objects the player meets, zone maps, what trainers teach, and the client's
-- API. Catalogue only: never anything about other players.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.npc = "name,minLevel,maxLevel,classification,type"
ns.FIELDS.object = "name"
ns.FIELDS.map = "name,type,parent"
ns.FIELDS.trainerService = "name,rank,category,cost,skill,skillRank,level"

-- NPCs -------------------------------------------------------------------------------------------

local levels = {} -- npc ID -> { min, max } seen this session, to widen the level range

local function seeUnit(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then
		return
	end
	local src = Encode.source(UnitGUID(unit))
	local id = src and string.match(src, "^n(%d+)$")
	if not id then
		return
	end
	id = tonumber(id)
	local npcs = ns.db().catalogue.npcs
	local level = UnitLevel(unit)
	local range = levels[id]
	if not range and npcs[id] then
		local min, max = string.match(npcs[id], "^[^,]*,([^,]*),([^,]*)")
		range = { tonumber(min), tonumber(max) }
	end
	if range and range[1] and range[2] and level >= range[1] and level <= range[2] then
		levels[id] = range
		return
	end
	range = range or {}
	range[1] = math.min(range[1] or level, level)
	range[2] = math.max(range[2] or level, level)
	levels[id] = range
	npcs[id] = Encode.row(Encode.name(UnitName(unit) or "?"), range[1], range[2], UnitClassification(unit),
		UnitCreatureType(unit) and Encode.name(UnitCreatureType(unit)) or nil)
end
ns.seeUnit = seeUnit

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

-- Objects: a gathering or opening cast names its target; the loot window that follows gives the
-- object's ID.
local cast -- { name, at }

ns.on("UNIT_SPELLCAST_SENT", "objects", function(unit, target)
	if unit == "player" and target and target ~= "" then
		cast = { name = target, at = GetTime() }
	end
end)
ns.on("LOOT_READY", "objects", function()
	local id = ns.lootSource and string.match(ns.lootSource, "^o(%d+)$")
	if id and cast and GetTime() - cast.at < 10 then
		ns.db().catalogue.objects[tonumber(id)] = Encode.name(cast.name)
	end
	cast = nil
end)

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

for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	ns.on(event, "maps", seeMap)
end

-- Trainers ---------------------------------------------------------------------------------------

local FILTERS = { "available", "unavailable", "used" }

-- Everything the trainer teaches, with cost and requirements, keyed by trainer NPC. Every filter
-- is switched on while reading, then put back as the player had it.
local function readTrainer()
	local src = Encode.source(UnitGUID("npc"))
	local id = src and tonumber(string.match(src, "^n(%d+)$"))
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
	for i = 1, GetNumTrainerServices() do
		local name, rank, category = GetTrainerServiceInfo(i)
		if name and category ~= "header" then
			local skill, skillRank = nil, nil
			if GetTrainerServiceSkillReq then
				skill, skillRank = GetTrainerServiceSkillReq(i)
			end
			local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
			local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
			rows[#rows + 1] = Encode.row(Encode.name(name), rank and rank ~= "" and Encode.name(rank) or nil, category, cost,
				skill and Encode.name(skill) or nil, skillRank, level)
		end
	end
	for f, on in pairs(saved) do
		SetTrainerServiceTypeFilter(f, on and true or false)
	end
	-- One string per trainer, rows joined by ";" like a stream chunk.
	ns.db().catalogue.trainers[id] = table.concat(rows, ";")
end

local trainerSoon = ns.throttle("trainer", 1, readTrainer)
ns.on("TRAINER_SHOW", "trainer", function()
	ns.after(0.5, "trainer", readTrainer)
end)
ns.on("TRAINER_UPDATE", "trainer", trainerSoon)

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

ns.on("PLAYER_ENTERING_WORLD", "api", function()
	ns.after(10, "api", dumpApi)
end)

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
ns.copy = copy

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

ns.on("PLAYER_ENTERING_WORLD", "gameRules", function()
	ns.after(6, "gameRules", readGameRules)
end)

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
	print(string.format("|cffe0ac45Gold Forever|r: the Legacy window called %d functions; saved. /reload to stop watching.", n))
end

ns.commands.legacy = function()
	hookAll()
	seen = {}
	phase = "before"
	print("|cffe0ac45Gold Forever|r: watching the API for 3 s, then opening the Legacy window…")
	ns.after(3, "legacy", function()
		phase = "open"
		if not pcall(ToggleLegacySystemUI) and LegacySystemFrame_LoadUI then
			pcall(LegacySystemFrame_LoadUI)
			pcall(ToggleLegacySystemUI)
		end
		print("|cffe0ac45Gold Forever|r: open the Legacy window if it did not open, and click through its pages — 20 s.")
		ns.after(20, "legacy", finishTrace)
	end)
end
