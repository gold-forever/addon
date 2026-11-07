-- QuestRewards.lua: at a quest's reward choice, the reward worth the most to sell (worth × count, the better
-- of the auction price after the cut and the vendor's) is marked; unpriced rewards are counted, not marked.

local ns = { on = function() end, settings = function() return {} end, price = {}, Money = {} }
assert(load(SOURCES["QuestRewards.lua"], "@QuestRewards.lua"))("GoldForever", ns)
local best = ns.QuestRewards.best

local function marked(pick)
	local out = {}
	for i in pairs(pick.marked) do
		out[#out + 1] = i
	end
	table.sort(out)
	return table.concat(out, ",")
end

local pick = best({ 500, 12000, 800 }, 3)
eq(marked(pick), "2", "the reward worth the most")
eq(pick.value, 12000, "its value")
eq(pick.unpriced, 0, "every reward priced")

pick = best({ nil, 300, nil, 200, nil }, 5)
eq(marked(pick), "2", "the best of the priced ones")
eq(pick.unpriced, 3, "three rewards unpriced, the last too")

pick = best({ nil, nil }, 2)
eq(marked(pick), "", "none priced: nothing marked")
eq(pick.value, nil, "and no value")

pick = best({ 400, 400, 100 }, 3)
eq(marked(pick), "1,2", "a tie: each reward worth the most is marked")

pick = best({ 0, 0 }, 2)
eq(marked(pick), "", "worth nothing: nothing marked")

pick = best({ 900 }, 1)
eq(marked(pick), "", "one reward is no choice: nothing marked")

-- A reward's value: one unit's worth (Pricing.lua's worth) times how many the quest gives.
ns.price.worth = function(id) return ({ [2589] = 50, [858] = 1900 })[id] end
eq(ns.QuestRewards.value(2589, 5), 250, "five Linen Cloth")
eq(ns.QuestRewards.value(858, 1), 1900, "one potion")
eq(ns.QuestRewards.value(6070, 1), nil, "no price: unpriced")
eq(ns.QuestRewards.value(nil, 1), nil, "no item id: unpriced")

-- The tooltip line.
ns.Money.auction = function(copper) return copper .. "c" end
eq(ns.QuestRewards.line({ value = 12000, unpriced = 0 }), "Best to sell: 12000c", "the line")
eq(ns.QuestRewards.line({ value = 12000, unpriced = 1 }), "Best to sell: 12000c (1 reward unpriced)", "one unpriced")
eq(ns.QuestRewards.line({ value = 12000, unpriced = 2 }), "Best to sell: 12000c (2 rewards unpriced)", "two unpriced")

return checks()
