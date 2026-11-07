-- Crafting.lua: the web app's pricing rules (pricing.ts), on the beta's Bolt of Linen Cloth.

local ns = {}
assert(load(SOURCES["Crafting.lua"], "@Crafting.lua"))("GoldForever", ns)
local C = ns.Crafting

local market = { [2589] = 40, [2996] = 120, [2320] = 12 }
local cheapest = { [2589] = 37, [2996] = 110 }
local vendor = { [2320] = 9 }
local price = {
	market = function(id) return market[id] end,
	buy = function(id) return cheapest[id] end,
	vendorBuy = function(id) return vendor[id] end,
}
local bolt = { output = 2996, yield = 1, reagents = { { id = 2589, count = 2 } } }

-- Buying everything: 2 Linen at the cheapest listing (37c), sold at 120c after 5%.
local q = C.quote(bolt, price, function() return 0 end, 0.05)
eq(q.revenue, 114, "120c after the 5% cut")
eq(q.cost, 74, "2 × 37c")
eq(q.profit, 40, "114 − 74")
eq(q.lines[1].from, "auction", "bought on the auction house")

-- Using owned Linen: charged at the lower of buying (37c) and selling (40c × 0.95 = 38c).
q = C.quote(bolt, price, function(id) return id == 2589 and 5 or 0 end, 0.05)
eq(q.cash, 0, "nothing to buy")
eq(q.ownedValue, 74, "2 × 37c")
eq(q.profit, 40, "the same profit: owning it is not free")
eq(q.spend, 74, "what it costs: nothing to buy, the held Linen at 37c each")

-- A vendor reagent is bought at the vendor when that is cheaper.
local shirt = { output = 2996, yield = 1, reagents = { { id = 2320, count = 1 } } }
eq(C.quote(shirt, price, function() return 0 end, 0.05).lines[1].from, "vendor", "Coarse Thread at the vendor")

-- An unpriced reagent makes the profit unknown, not zero.
local mystery = { output = 2996, yield = 1, reagents = { { id = 99999, count = 1 } } }
eq(C.quote(mystery, price, function() return 0 end, 0.05).profit, nil, "unknown")

-- An unpriced output too.
eq(C.quote({ output = 99999, yield = 1, reagents = {} }, price, function() return 0 end, 0.05).profit, nil, "no sale price")

-- The margin: profit over cost, whole percent; unknown without both.
eq(C.margin({ profit = 50, cost = 200 }), 25, "a quarter")
eq(C.margin({ profit = -30, cost = 200 }), -15, "a loss")
eq(C.margin({ profit = nil, cost = 200 }), nil, "no profit known")
eq(C.margin({ profit = 10, cost = 0 }), nil, "nothing to buy: no margin")
-- One base: sells for 100, 80 of reagents held that would sell for 48: costs 48, profit 52, margin 108%.
eq(C.margin({ profit = 52, cost = 80, spend = 48 }), 108, "profit over what crafting costs, held reagents at their sale value")

-- "I have these": only what is still to buy counts against the sale.
eq(C.profitHeld({ revenue = 1000, cash = 300, ownedValue = 200 }), 700, "held reagents cost nothing")
eq(C.profitHeld({ revenue = nil, cash = 300 }), nil, "no sale price")
-- Margin bands.
eq(C.band(-5), "loss", "a loss")
eq(C.band(9), "thin", "under 10%")
eq(C.band(10), "fair", "from 10%")
eq(C.band(30), "good", "from 30%")
eq(C.band(nil), nil, "unknown")

-- A craft queue's reagents in all.
local recipes = { [1] = { reagents = { { id = 2589, count = 2 } } }, [2] = { reagents = { { id = 2589, count = 1 }, { id = 2320, count = 3 } } } }
local need = C.queueReagents({ { recipe = 1, count = 5 }, { recipe = 2, count = 2 }, { recipe = 9, count = 1 } }, function(id) return recipes[id] end)
eq(need[2589], 12, "5 × 2 + 2 × 1 Linen")
eq(need[2320], 6, "2 × 3 thread")
eq(next(C.queueReagents({}, function() end)), nil, "an empty queue needs nothing")
-- A choice slot needs the choice the pick makes (the cheapest), not every choice; without a pick, the first.
recipes[3] = { reagents = { { id = 101, options = { 101, 102 }, count = 20 } } }
need = C.queueReagents({ { recipe = 3, count = 2 } }, function(id) return recipes[id] end, function(x) return x.options[2] end)
eq(need[102] .. " " .. tostring(need[101]), "40 nil", "the picked choice, 2 × 20")
eq(C.queueReagents({ { recipe = 3, count = 1 } }, function(id) return recipes[id] end)[101], 20, "no pick: the first")

-- A random result (Wild Experimentation, a transmutation): the client names a recipe item (class 9) as
-- its output, which has no price. A priced recipe item is a real sale; anything else is a fixed result.
eq(C.randomResult(9, nil), true, "a recipe item without a price: random, or it fails")
eq(C.randomResult(9, 5000), false, "a recipe item that sells: a real output")
eq(C.randomResult(7, nil), false, "an unpriced trade good: unknown, not random")
eq(C.randomResult(nil, nil), false, "an item not read yet: unknown, not random")

-- A slot you fill with your choice of reagent (Wild Experimentation: any of several herbs): one line,
-- priced at the cheapest choice you hold or can buy, its options kept for the strip's "any of".
local herbs = { [101] = 50, [102] = 30, [103] = nil }
local choicePrice = {
	market = function(id) return herbs[id] end,
	buy = function(id) return herbs[id] end,
	vendorBuy = function() return nil end,
}
local wild = { output = 9, yield = 1, reagents = { { options = { 101, 102, 103 }, count = 20 }, { id = 2320, count = 1 } } }
q = C.quote(wild, choicePrice, function() return 0 end, 0.05)
eq(#q.lines, 2, "the choice slot is one line, the fixed reagent another")
eq(q.lines[1].id, 102, "the cheapest choice to buy")
eq(q.lines[1].unit, 30, "priced at it")
eq(#q.lines[1].options, 3, "every choice kept")
eq(q.lines[1].toBuy, 20, "all 20 to buy")
eq(q.lines[2].options, nil, "a fixed reagent has no choices")
-- Held herbs count at the lower of buying and selling them (47.5c here), so a cheaper herb to buy wins.
q = C.quote(wild, choicePrice, function(id) return id == 101 and 20 or 0 end, 0.05)
eq(q.lines[1].id, 102, "held at 47 each still dearer than buying at 30")
q = C.quote(wild, choicePrice, function(id) return id == 103 and 20 or 0 end, 0.05)
eq(q.lines[1].id, 102, "a held choice of unknown value is not cheapest")
local cheapHeld = { [101] = 50, [102] = 30, [103] = 10 }
q = C.quote(wild, { market = function(id) return cheapHeld[id] end, buy = function() return nil end, vendorBuy = function() return nil end },
	function(id) return id == 101 and 20 or 0 end, 0.05)
eq(q.lines[1].id, 101, "only the held choice is known: it")
eq(q.lines[1].toBuy, 0, "nothing to buy")
q = C.quote(wild, { market = function() return nil end, buy = function() return nil end, vendorBuy = function() return nil end },
	function() return 0 end, 0.05)
eq(q.lines[1].id, 101, "no choice priced: the first, unknown")
eq(q.spend, nil, "and the cost unknown")
-- The queue's pick is the quote's: the choice a slot is priced at.
eq(C.choice({ options = { 101, 102, 103 }, count = 20 }, choicePrice, function() return 0 end, 0.05).id, 102, "the cheapest choice")

return checks()
