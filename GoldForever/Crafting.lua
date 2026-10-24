-- Gold Forever: what a craft costs and earns, the same rules as the web app's
-- frontend/src/domain/pricing.ts. Pure Lua with no game API, so it is unit-tested outside the client.
--
-- A reagent is bought where it is cheapest, a vendor or the cheapest listing; the output sells at
-- its market value after the cut. "Use what I have" takes owned reagents first and charges them at
-- the lower of buying them again and selling them, so a craft only pays if it beats selling them raw.

local _, ns = ...
ns = ns or {}

local Crafting = {}
ns.Crafting = Crafting

local function times(count, unit)
	if count == 0 then
		return 0
	end
	return unit and math.floor(count * unit + 0.5) or nil
end

local function plus(a, b)
	return a and b and a + b or nil
end

local function minus(a, b)
	return a and b and a - b or nil
end

local function lower(a, b)
	if not a then
		return b
	end
	if not b then
		return a
	end
	return math.min(a, b)
end

-- recipe: { output = itemId, yield = n, reagents = { { id, count }, … } }
-- price: { market = fn(id), cheapest = fn(id), vendorBuy = fn(id) }, each a copper value or nil
-- stock: fn(id) → units owned. Returns { revenue, cost, cash, ownedValue, profit, lines = { … } },
-- where profit is "use what I have" and any unknown price makes the sums it touches nil.
function Crafting.quote(recipe, price, stock, cut)
	local cost, cash, ownedValue = 0, 0, 0
	local lines = {}
	for _, r in ipairs(recipe.reagents) do
		local vendor, auction = price.vendorBuy(r.id), price.cheapest(r.id)
		local from, unit
		if vendor and (not auction or vendor <= auction) then
			from, unit = "vendor", vendor
		elseif auction then
			from, unit = "auction", auction
		end
		local market = price.market(r.id)
		local sell = market and market * (1 - cut)
		local owned = math.min(r.count, stock(r.id) or 0)
		local line = { id = r.id, needed = r.count, owned = owned, toBuy = r.count - owned, unit = unit, from = from }
		lines[#lines + 1] = line
		cost = plus(cost, times(r.count, unit))
		cash = plus(cash, times(line.toBuy, unit))
		ownedValue = plus(ownedValue, times(owned, lower(unit, sell)))
	end
	local output = price.market(recipe.output)
	local revenue = output and math.floor(output * recipe.yield * (1 - cut) + 0.5) or nil
	return {
		revenue = revenue,
		cost = cost,
		cash = cash,
		ownedValue = ownedValue,
		profit = minus(minus(revenue, cash), ownedValue),
		lines = lines,
	}
end

-- Profit over what the reagents cost, in whole percent; nil without both. The strip's "margin".
function Crafting.margin(q)
	if not q or not q.profit or not q.cost or q.cost <= 0 then
		return nil
	end
	return math.floor(q.profit / q.cost * 100 + 0.5)
end

-- Profit with "I have these": what the player holds costs nothing, only what is still to buy does.
function Crafting.profitHeld(q)
	if not q or not q.revenue or not q.cash then
		return nil
	end
	return q.revenue - q.cash
end

-- The margin band a profit falls in (design 009, Crafting): "loss" (under 0), "thin" (under 10%), "fair",
-- "good" (from 30%), or nil when unknown.
function Crafting.band(margin)
	if not margin then
		return nil
	end
	if margin < 0 then
		return "loss"
	elseif margin < 10 then
		return "thin"
	elseif margin < 30 then
		return "fair"
	end
	return "good"
end

-- The reagents a craft queue needs in all ({ { recipe = id, count = n } }; recipeOf(id) gives the
-- recipe with its reagents): item ID -> units. A recipe the catalogue lacks needs nothing.
function Crafting.queueReagents(queue, recipeOf)
	local need = {}
	for _, q in ipairs(queue or {}) do
		local r = recipeOf(q.recipe)
		for _, x in ipairs(r and r.reagents or {}) do
			need[x.id] = (need[x.id] or 0) + x.count * (q.count or 1)
		end
	end
	return need
end

return Crafting
