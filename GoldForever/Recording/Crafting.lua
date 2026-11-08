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

-- One reagent's line: where it is bought and at what, and how many are held and still to buy; spend is
-- what it adds to the craft's cost (nil when unknown).
local function reagentLine(id, count, price, stock, cut)
	local vendor, auction = price.vendorBuy(id), price.buy(id)
	local from, unit
	if vendor and (not auction or vendor <= auction) then
		from, unit = "vendor", vendor
	elseif auction then
		from, unit = "auction", auction
	end
	local market = price.market(id)
	local sell = market and market * (1 - cut)
	local owned = math.min(count, stock(id) or 0)
	local line = { id = id, needed = count, owned = owned, toBuy = count - owned, unit = unit, from = from }
	line.cash, line.ownedValue = times(line.toBuy, unit), times(owned, lower(unit, sell))
	line.spend = plus(line.cash, line.ownedValue)
	return line
end

-- A slot filled with the player's choice of reagent (retail: any of several herbs, or a herb's qualities):
-- the line of the choice that costs least, held or bought; with none priced, the first.
function Crafting.choice(r, price, stock, cut)
	local best
	for _, id in ipairs(r.options) do
		local line = reagentLine(id, r.count, price, stock, cut)
		if not best or (line.spend and (not best.spend or line.spend < best.spend)) then
			best = line
		end
	end
	best.options = r.options
	return best
end

-- recipe: { output = itemId, yield = n, reagents = { { id, count } or { options = { id, … }, count }, … } }
-- price: { market = fn(id), buy = fn(id), vendorBuy = fn(id) }, each a copper value or nil: buy is what
-- one costs at the auction house
-- stock: fn(id) → units owned. Returns { revenue, cost, cash, ownedValue, profit, lines = { … } },
-- where profit is "use what I have" and any unknown price makes the sums it touches nil. A choice slot's
-- line is its cheapest choice, with options.
function Crafting.quote(recipe, price, stock, cut)
	local cost, cash, ownedValue = 0, 0, 0
	local lines = {}
	for _, r in ipairs(recipe.reagents) do
		local line = r.options and Crafting.choice(r, price, stock, cut) or reagentLine(r.id, r.count, price, stock, cut)
		lines[#lines + 1] = line
		cost = plus(cost, times(line.needed, line.unit))
		cash = plus(cash, line.cash)
		ownedValue = plus(ownedValue, line.ownedValue)
	end
	local output = price.market(recipe.output)
	local revenue = output and math.floor(output * recipe.yield * (1 - cut) + 0.5) or nil
	return {
		revenue = revenue,
		cost = cost,
		cash = cash,
		ownedValue = ownedValue,
		-- What crafting costs the player (owner's answer, 2026-10-24): the reagents still to buy, and the
		-- ones held at what they would sell for. Profit, Cost and Margin share this base.
		spend = plus(cash, ownedValue),
		profit = minus(minus(revenue, cash), ownedValue),
		lines = lines,
	}
end

-- Profit over what crafting costs (a quote's spend; else its cost), in whole percent; nil without both.
function Crafting.margin(q)
	local base = q and (q.spend or q.cost)
	if not q or not q.profit or not base or base <= 0 then
		return nil
	end
	return math.floor(q.profit / base * 100 + 0.5)
end

-- Whether a recipe's result is random or can fail (Wild Experimentation, a transmutation, prospecting),
-- from its output's item class and market price. The client names such a recipe's output as a placeholder
-- recipe item, which nobody sells; a priced recipe item is a real output.
local RECIPE_CLASS = 9
function Crafting.randomResult(class, market)
	return class == RECIPE_CLASS and market == nil
end

-- Whether an item is a recipe item: a salvage that makes one has a random result, and its count is the
-- items it takes (Professions.lua).
function Crafting.recipeItem(class)
	return class == RECIPE_CLASS
end

-- Profit with "I have these": what the player holds costs nothing, only what is still to buy does.
function Crafting.profitHeld(q)
	if not q or not q.revenue or not q.cash then
		return nil
	end
	return q.revenue - q.cash
end

-- What a recipe item teaches, from its name (the site's PATTERN, CatalogueNames.kt); nil for any other item.
local TEACHING = { Pattern = true, Recipe = true, Formula = true, Plans = true, Schematic = true, Manual = true, Design = true, Technique = true }
function Crafting.taughtName(itemName)
	local kind, taught = string.match(itemName, "^(%a+): (.+)$")
	return TEACHING[kind] and taught or nil
end

-- Recipe name -> recipe ID, the lowest of a name that makes an item; built at the first recipe item shown
-- and again once the profession window has added recipes.
local recipeByName
function Crafting.forgetRecipeNames()
	recipeByName = nil
end

function Crafting.recipeNamed(name)
	local Encode = ns.Encode
	if not recipeByName then
		recipeByName = {}
		local cols = Encode.columns(ns.db().fields.recipe)
		for id, row in pairs(ns.db().catalogue.recipes) do
			local values = { strsplit(",", row) }
			local key = values[cols.name]
			if key and values[cols.output] ~= "" and (not recipeByName[key] or id < recipeByName[key]) then
				recipeByName[key] = id
			end
		end
	end
	return recipeByName[Encode.name(name)]
end

-- What a recipe item costs: a vendor's price, limited stock too as a recipe is bought once, else market(id).
function Crafting.teachingPrice(id, market)
	local row = ns.db().catalogue.vendor[id]
	if row then
		local buy, _, _, qty = strsplit(",", row)
		buy = tonumber(buy)
		if buy and buy > 0 then
			return buy / math.max(1, tonumber(qty) or 1)
		end
	end
	return market(id)
end

-- What learning a recipe is worth: its item's price over a craft's profit, in whole crafts. Unknown price
-- or profit: nil. money formats a copper value; gear: the output is gear, its price one for every quality.
local GEAR_NOTE = ", gear prices are rough"
function Crafting.paybackLine(itemPrice, profit, money, gear)
	if not itemPrice or itemPrice <= 0 or not profit then
		return nil
	end
	if profit <= 0 then
		return "No profit at today's prices" .. (gear and GEAR_NOTE or "")
	end
	local crafts = math.ceil(itemPrice / profit)
	return string.format("Pays back in %d craft%s at today's margin (%s a craft)%s", crafts, crafts == 1 and "" or "s", money(profit), gear and GEAR_NOTE or "")
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
-- recipe with its reagents): item ID -> units. A recipe the catalogue lacks needs nothing. A slot of
-- choices needs the one pick(slot) names (the cheapest: Crafting.choice), else its first.
function Crafting.queueReagents(queue, recipeOf, pick)
	local need = {}
	for _, q in ipairs(queue or {}) do
		local r = recipeOf(q.recipe)
		for _, x in ipairs(r and r.reagents or {}) do
			local id = x.options and pick and pick(x) or x.id
			need[id] = (need[id] or 0) + x.count * (q.count or 1)
		end
	end
	return need
end

return Crafting
