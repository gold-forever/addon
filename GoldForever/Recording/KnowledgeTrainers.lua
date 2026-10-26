-- Gold Forever: game knowledge (as Knowledge.lua): what trainers teach. Catalogue only: never anything
-- about other players.

local _, ns = ...
local Encode = ns.Encode

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
