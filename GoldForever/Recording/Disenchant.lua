-- Gold Forever: what disenchanting an item gives, from the Classic Era disenchant table (the same as
-- the web app's frontend/src/domain/disenchant.ts). Pure Lua with no game API, so it is unit-tested
-- outside the client. WoW: Forever may differ: of the beta's two disenchants, the green gave what the
-- table says, the blue gave 3 Strange Dust, not a shard.

local _, ns = ...
ns = ns or {}

local Disenchant = {}
ns.Disenchant = Disenchant

local STRANGE_DUST, SOUL_DUST, VISION_DUST, DREAM_DUST, ILLUSION_DUST = 10940, 11083, 11137, 11176, 16204
local LESSER_MAGIC, GREATER_MAGIC, LESSER_ASTRAL, GREATER_ASTRAL = 10938, 10939, 10998, 11082
local LESSER_MYSTIC, GREATER_MYSTIC, LESSER_NETHER, GREATER_NETHER = 11134, 11135, 11174, 11175
local LESSER_ETERNAL, GREATER_ETERNAL = 16202, 16203
local SMALL_GLIMMERING, LARGE_GLIMMERING, SMALL_GLOWING, LARGE_GLOWING = 10978, 11084, 11138, 11139
local SMALL_RADIANT, LARGE_RADIANT, SMALL_BRILLIANT, LARGE_BRILLIANT = 11177, 11178, 14343, 14344
local NEXUS_CRYSTAL = 20725

local WEAPON, ARMOR = 2, 4
local UNCOMMON, RARE, EPIC = 2, 3, 4

local function o(id, chance, min, max)
	return { id = id, chance = chance, min = min, max = max or min }
end

-- Greens by the highest item level of each band: max level, skill, dust, dust count, essence,
-- essence count, shard (0: none). Armor gives mostly dust, weapons mostly essence.
local GREEN = {
	{ 15, 1, STRANGE_DUST, 1, 2, LESSER_MAGIC, 1, 2, 0 },
	{ 20, 1, STRANGE_DUST, 2, 3, GREATER_MAGIC, 1, 2, SMALL_GLIMMERING },
	{ 25, 25, STRANGE_DUST, 4, 6, LESSER_ASTRAL, 1, 2, SMALL_GLIMMERING },
	{ 30, 50, SOUL_DUST, 1, 2, GREATER_ASTRAL, 1, 2, LARGE_GLIMMERING },
	{ 35, 75, SOUL_DUST, 2, 5, LESSER_MYSTIC, 1, 2, SMALL_GLOWING },
	{ 40, 100, VISION_DUST, 1, 2, GREATER_MYSTIC, 1, 2, LARGE_GLOWING },
	{ 45, 125, VISION_DUST, 2, 5, LESSER_NETHER, 1, 2, SMALL_RADIANT },
	{ 50, 150, DREAM_DUST, 1, 2, GREATER_NETHER, 1, 2, LARGE_RADIANT },
	{ 55, 175, DREAM_DUST, 2, 5, LESSER_ETERNAL, 1, 2, SMALL_BRILLIANT },
	{ 60, 200, ILLUSION_DUST, 1, 2, GREATER_ETERNAL, 1, 2, LARGE_BRILLIANT },
	{ math.huge, 225, ILLUSION_DUST, 2, 5, GREATER_ETERNAL, 2, 3, LARGE_BRILLIANT },
}

-- Blues: one shard by band; from item level 56 a small chance of a Nexus Crystal.
local BLUE = {
	{ 25, 1, SMALL_GLIMMERING },
	{ 30, 50, LARGE_GLIMMERING },
	{ 35, 75, SMALL_GLOWING },
	{ 40, 100, LARGE_GLOWING },
	{ 45, 125, SMALL_RADIANT },
	{ 50, 150, LARGE_RADIANT },
	{ 55, 175, SMALL_BRILLIANT },
	{ math.huge, 200, LARGE_BRILLIANT },
}

-- Purples.
local PURPLE = {
	{ 45, 125, { o(SMALL_RADIANT, 1, 2, 4) } },
	{ 50, 150, { o(LARGE_RADIANT, 1, 2, 4) } },
	{ 55, 175, { o(SMALL_BRILLIANT, 1, 2, 4) } },
	{ 60, 200, { o(NEXUS_CRYSTAL, 1, 1) } },
	{ math.huge, 225, { o(NEXUS_CRYSTAL, 1, 1, 2) } },
}

local function band(bands, level)
	for _, b in ipairs(bands) do
		if level <= b[1] then
			return b
		end
	end
end

-- { skill, outcomes = { { id, chance, min, max }, … } } for an item of that quality (0 poor … 4 epic),
-- item level and class, or nil when it cannot be disenchanted.
function Disenchant.of(quality, itemLevel, classId)
	if not itemLevel or (classId ~= WEAPON and classId ~= ARMOR) then
		return nil
	end
	if quality == UNCOMMON then
		local b = band(GREEN, itemLevel)
		local shard = b[9] ~= 0 and 0.05 or 0
		local main = 1 - shard - 0.2
		local weapon = classId == WEAPON
		local outcomes = {
			o(b[3], weapon and 0.2 or main, b[4], b[5]),
			o(b[6], weapon and main or 0.2, b[7], b[8]),
		}
		if shard > 0 then
			outcomes[3] = o(b[9], shard, 1)
		end
		table.sort(outcomes, function(x, y)
			return x.chance > y.chance
		end)
		return { skill = b[2], outcomes = outcomes }
	elseif quality == RARE then
		local b = band(BLUE, itemLevel)
		local outcomes = itemLevel >= 56 and { o(b[3], 0.995, 1), o(NEXUS_CRYSTAL, 0.005, 1) } or { o(b[3], 1, 1) }
		return { skill = b[2], outcomes = outcomes }
	elseif quality == EPIC and itemLevel >= 40 then
		local b = band(PURPLE, itemLevel)
		return { skill = b[2], outcomes = b[3] }
	end
	return nil
end

-- Expected worth of one disenchant: chance × average count × unit worth, summed; worth(id) gives a
-- unit's worth or nil, and unpriced materials count as nothing.
function Disenchant.value(outcomes, worth)
	local total = 0
	for _, x in ipairs(outcomes) do
		total = total + x.chance * (x.min + x.max) / 2 * (worth(x.id) or 0)
	end
	return math.floor(total + 0.5)
end

return Disenchant
