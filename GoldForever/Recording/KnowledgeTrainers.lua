-- Gold Forever: game knowledge (as Knowledge.lua): what trainers teach. Catalogue only: never anything
-- about other players.

local _, ns = ...
local L = ns.L
local Encode = ns.Encode

-- Trainers ---------------------------------------------------------------------------------------

local FILTERS = { "available", "unavailable", "used" }

-- Every filter switched on, and how the player had them, to put back.
local function showAllServices()
	local saved = {}
	if GetTrainerServiceTypeFilter and SetTrainerServiceTypeFilter then
		for _, f in ipairs(FILTERS) do
			saved[f] = GetTrainerServiceTypeFilter(f)
			SetTrainerServiceTypeFilter(f, true)
		end
	end
	return saved
end

local function restoreFilters(saved)
	for f, on in pairs(saved) do
		SetTrainerServiceTypeFilter(f, on and true or false)
	end
end

local SIDES = { Horde = "H", Alliance = "A" }

-- Where the trainer stands and the visitor's side. A read with no map keeps the place already stored.
local function recordPlace(catalogue, id)
	local map, x, y = ns.position()
	if not map then
		return
	end
	catalogue.trainerPlaces = catalogue.trainerPlaces or {}
	catalogue.trainerPlaces[id] = Encode.row(map, x, y, SIDES[UnitFactionGroup("player")])
end

-- A hidden tooltip of the addon's own, so the one the player looks at is never changed; made at the first read.
local tip
local function scanTip()
	tip = tip or CreateFrame("GameTooltip", "GoldForeverTrainerTip", nil, "GameTooltipTemplate")
	return tip
end

-- The spell service i teaches, from the tooltip's GetSpell; nil where the client's tooltip cannot show a
-- trainer's service (not yet probed on Forever), names no spell or raises: the service's other columns are
-- kept either way. GetSpell's spell ID is its one number.
local function readSpell(i)
	local t = scanTip()
	if not (t.SetTrainerService and t.GetSpell) then
		return nil
	end
	t:SetOwner(WorldFrame, "ANCHOR_NONE")
	t:SetTrainerService(i)
	for _, v in ipairs({ t:GetSpell() }) do
		if type(v) == "number" then
			return v
		end
	end
end

local function serviceSpell(i)
	local ok, id = pcall(readSpell, i)
	return ok and id or nil
end

-- The service's catalogue row, and whether it is a class spell (a level and no profession skill); nil for a
-- header.
local function serviceRow(i)
	local name, category, icon = GetTrainerServiceInfo(i)
	if not name or category == "header" then
		return nil
	end
	local skill, skillRank = nil, nil
	if GetTrainerServiceSkillReq then
		skill, skillRank = GetTrainerServiceSkillReq(i)
	end
	local level = GetTrainerServiceLevelReq and GetTrainerServiceLevelReq(i)
	local cost = GetTrainerServiceCost and GetTrainerServiceCost(i)
	return Encode.row(Encode.name(name), category, icon, cost, skill and Encode.name(skill) or nil, skillRank, level, serviceSpell(i)),
		not skill and (level or 0) > 0
end

-- Everything the trainer teaches, with cost and requirements, keyed by trainer NPC. Every filter
-- is switched on while reading, then put back as the player had it.
local function readTrainerNow()
	local id = Encode.npcId(ns.readable(UnitGUID("npc")))
	if not id or not GetNumTrainerServices then
		return
	end
	local saved = showAllServices()
	local rows = {}
	local classSpells = false -- spells with a level and no profession skill: a class trainer
	for i = 1, GetNumTrainerServices() do
		local row, classSpell = serviceRow(i)
		if row then
			rows[#rows + 1] = row
			classSpells = classSpells or classSpell
		end
	end
	restoreFilters(saved)
	-- One string per trainer, rows joined by ";" like a stream chunk. An empty read is the window gone
	-- before it was read, not a trainer with nothing to teach: the stored list stays.
	if #rows == 0 then
		return
	end
	local catalogue = ns.db().catalogue
	catalogue.trainers[id] = table.concat(rows, ";")
	recordPlace(catalogue, id)
	-- A class trainer teaches only the visitor's class: kept, for the training ahead at a level-up.
	if classSpells then
		catalogue.trainerClasses = catalogue.trainerClasses or {}
		catalogue.trainerClasses[id] = select(2, UnitClass("player"))
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
		ns.say(string.format(L["level %d: %s at your trainer, %s."], level, table.concat(spells, ", "), Encode.money(cost)))
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
