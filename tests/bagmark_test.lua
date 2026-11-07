-- BagMark.lua: with the bags full, the stack worth least in all (a unit's worth, by the addon's prices, times
-- the stack) is the one to make room with; soulbound and quest items are never it, nor one with no price.

local ns = { on = function() end, listen = function() end, module = function() end, price = {} }
assert(load(SOURCES["BagMark.lua"], "@BagMark.lua"))("GoldForever", ns)
local pick = ns.BagMark.pick

-- A unit's worth by item: Linen 10c, Violet Sash 150c, Skin 1c, Quest Note 0c... none for 999.
local WORTH = { [2589] = 10, [251962] = 150, [271206] = 1, [3000] = 2 }
local function worth(id) return WORTH[id] end
local function stack(bag, slot, id, count, flags)
	flags = flags or {}
	return { bag = bag, slot = slot, id = id, count = count, bound = flags.bound, quest = flags.quest }
end

local s, total = pick({ stack(0, 1, 2589, 20), stack(0, 2, 251962, 1) }, worth)
eq(s and s.slot, 2, "the stack worth least in all: one Sash at 1s 50c, not 20 Linen at 2s")
eq(total, 150, "its total")

s = pick({ stack(0, 1, 2589, 20), stack(0, 2, 271206, 1, { bound = true }) }, worth)
eq(s and s.slot, 1, "a soulbound item is never it")

s = pick({ stack(0, 1, 2589, 20), stack(1, 4, 3000, 1, { quest = true }) }, worth)
eq(s and s.slot, 1, "a quest item is never it")

s = pick({ stack(0, 1, 2589, 20), stack(0, 2, 999, 1) }, worth)
eq(s and s.slot, 1, "an item with no price is never it")

s = pick({ stack(0, 1, 2589, 5), stack(1, 1, 2589, 5) }, worth)
eq(s and s.bag, 0, "equal totals: the first in bag order")

eq(pick({ stack(0, 1, 271206, 1, { bound = true }), stack(0, 2, 999, 3) }, worth), nil, "none can go: no mark")
eq(pick({}, worth), nil, "empty bags: no mark")

return checks()
