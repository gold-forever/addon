-- Disenchant.lua: the Classic disenchant table, the same cases as the web app's disenchant.test.ts.

local ns = {}
assert(load(SOURCES["Disenchant.lua"], "@Disenchant.lua"))("GoldForever", ns)
local D = ns.Disenchant

-- Violet Sash: uncommon armor, item level 36; the beta's disenchant gave 2 Vision Dust.
local sash = D.of(2, 36, 4)
eq(sash.skill, 100, "Enchanting 100")
eq(sash.outcomes[1].id, 11137, "Vision Dust first")
eq(sash.outcomes[1].chance, 0.75, "at 75%")
eq(#sash.outcomes, 3, "dust, essence and a shard")

-- Weapons give essence where armor gives dust.
eq(D.of(2, 36, 2).outcomes[1].id, 11135, "Greater Mystic Essence first for a weapon")

-- Low greens have no shard.
eq(#D.of(2, 10, 4).outcomes, 2, "no shard below 16")
eq(D.of(2, 10, 4).outcomes[1].chance, 0.8, "80% dust")

-- Blues: one shard, and a rare Nexus Crystal from item level 56.
eq(D.of(3, 20, 4).outcomes[1].id, 10978, "Small Glimmering Shard")
eq(#D.of(3, 60, 4).outcomes, 2, "a shard or a Nexus Crystal")

-- What cannot be disenchanted.
eq(D.of(1, 30, 4), nil, "common")
eq(D.of(2, 30, 7), nil, "trade goods")
eq(D.of(2, nil, 4), nil, "no item level")
eq(D.of(4, 30, 4), nil, "purples below 40")

-- Expected worth.
local prices = { [1] = 100, [2] = 400 }
eq(D.value({ { id = 1, chance = 0.75, min = 1, max = 3 }, { id = 2, chance = 0.25, min = 1, max = 1 } }, function(id)
	return prices[id]
end), 250, "0.75 × 2 × 100 + 0.25 × 400")
eq(D.value({ { id = 9, chance = 1, min = 1, max = 1 } }, function()
	return nil
end), 0, "unpriced counts as nothing")

return checks()
