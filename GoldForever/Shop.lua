-- Gold Forever: the recipes the character knows, quoted at the latest prices (the same rules as the
-- web app's Crafting view, "use what I have": Crafting.lua), and the craft queue, for the hub's Home and
-- Crafting pages, the crafting strip and the Buy tab's "Craft queue" list. The floating "crafts to make"
-- window at the auction house is gone (manual test run 001): the Crafting page shows the same, and more.

local _, ns = ...

local Encode = ns.Encode
local itemList = Encode.parseItems

-- Columns by name from fields.<format>, so a row is read as the file declares it.
local function columns(format)
	return Encode.columns(ns.db().fields[format])
end

-- What the character holds: bags and bank, as last read.
local function stock()
	local me = ns.me()
	local held = itemList(me.bags and me.bags.items)
	for id, n in pairs(itemList(me.bank and me.bank.items)) do
		held[id] = (held[id] or 0) + n
	end
	return held
end

local function recipe(id, cols)
	local row = ns.db().catalogue.recipes[id]
	if not row then
		return nil
	end
	local values = { strsplit(",", row) }
	local output = tonumber(values[cols.output] or "")
	if not output then
		return nil -- enchants on gear make no item
	end
	local min = tonumber(values[cols.min] or "") or 1
	local max = tonumber(values[cols.max] or "") or min
	local reagents = {}
	for rid, n in pairs(itemList(values[cols.reagents])) do
		reagents[#reagents + 1] = { id = rid, count = n }
	end
	return { id = id, output = output, yield = (min + max) / 2, reagents = reagents }
end

-- Whether a recipe makes gear (a weapon or armor): its price is one for every quality and item level,
-- so its profit is not to be trusted (owner's answer, 2026-10-24: Tracker's Chitin Cuffs "sold for"
-- 1,425g at skill 4). Gear is marked, its profit greyed, and it is never "the best craft".
-- Anything worn counts, profession tools and gear too (class 19: Skinner's Cap at 6,760g, 39,665%).
local GEAR_CLASS = { [2] = true, [4] = true, [19] = true }
local function isGear(id)
	if C_Item and C_Item.IsEquippableItem and C_Item.IsEquippableItem(id) then
		return true
	end
	local _, _, class = ns.price.itemInfo(id)
	if not class and C_Item and C_Item.GetItemInfoInstant then
		class = select(6, C_Item.GetItemInfoInstant(id))
	end
	return GEAR_CLASS[class] == true
end
ns.isGear = isGear

-- Every known recipe that makes a profit, best first, each with its quote; gear left out.
local function profitable()
	local me = ns.me()
	if not me then
		return {}
	end
	local p, cols, held = ns.price, columns("recipe"), stock()
	local have = function(id)
		return held[id] or 0
	end
	local out = {}
	for _, prof in pairs(me.prof or {}) do
		for id in string.gmatch(prof.recipes or "", "%d+") do
			local r = recipe(tonumber(id), cols)
			if r then
				local q = ns.Crafting.quote(r, p, have, p.cut)
				if q.profit and q.profit > 0 and not isGear(r.output) then
					q.recipe = r
					local fromStock = math.huge
					for _, x in ipairs(r.reagents) do
						fromStock = math.min(fromStock, math.floor(have(x.id) / x.count))
					end
					q.fromStock = fromStock == math.huge and 0 or fromStock
					out[#out + 1] = q
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.profit > b.profit
	end)
	return out
end

-- The craft queue (owner's answer, 2026-10-24): recipes and how many of each, kept in the settings;
-- the Shop lists the reagents still missing for all of it.
local function queue()
	local s = ns.settings("crafting", { strip = true })
	s.queue = s.queue or {}
	return s.queue
end
-- The auction panel's Buy tab shows the queue as a list: it follows every change (manual test run 001:
-- a cleared queue's list stayed). `how` is "added", "crafted" or "cleared".
local function changed(how)
	if ns.auctionRefresh then
		ns.auctionRefresh()
	end
	if ns.craftQueueChanged then
		ns.craftQueueChanged(how)
	end
end
function ns.queueAdd(recipeId, n)
	local q = queue()
	for _, x in ipairs(q) do
		if x.recipe == recipeId then
			x.count = x.count + n
			changed("added")
			return
		end
	end
	q[#q + 1] = { recipe = recipeId, count = n }
	changed("added")
end
-- A queued recipe crafted: one fewer in the queue, and gone at none (manual test run 001: the window
-- stayed with everything in the bags). The cast's spell is the recipe's ID.
ns.on("UNIT_SPELLCAST_SUCCEEDED", "craft queue", function(unit, _, spell)
	if unit ~= "player" or not spell then
		return
	end
	local q = queue()
	for i, x in ipairs(q) do
		if x.recipe == spell then
			x.count = x.count - 1
			if x.count <= 0 then
				table.remove(q, i)
			end
			changed("crafted")
			return
		end
	end
end)

function ns.queueClear()
	local s = ns.settings("crafting", { strip = true })
	s.queue = {}
	changed("cleared")
end
function ns.queueList()
	return queue()
end
-- The queue's reagents in all: item ID -> units.
function ns.queueNeeds()
	return ns.Crafting.queueReagents(queue(), ns.recipeOf)
end

-- A recipe from the catalogue (output, yield, reagents), for the craft queue.
function ns.recipeOf(id)
	return recipe(id, columns("recipe"))
end

-- For the hub's Home page: the best crafts now.
ns.profitableCrafts = profitable

-- For the hub's Crafting page: every known recipe that makes an item, each with its quote and name.
function ns.allCraftQuotes()
	local me = ns.me()
	if not me or not ns.price then
		return {}
	end
	local cols, held = columns("recipe"), stock()
	local have = function(id)
		return held[id] or 0
	end
	local out, seen = {}, {}
	for line, prof in pairs(me.prof or {}) do
		for id in string.gmatch(prof.recipes or "", "%d+") do
			id = tonumber(id)
			local r = not seen[id] and recipe(id, cols)
			seen[id] = true
			if r then
				local q = ns.Crafting.quote(r, ns.price, have, ns.price.cut)
				q.recipe = r
				q.prof = prof.name or ("Profession " .. tostring(line)) -- for the page's profession filter
				q.gear = isGear(r.output)
				out[#out + 1] = q
			end
		end
	end
	return out
end

-- For the crafting strip: one recipe's quote from the catalogue, with what this character holds; nil
-- for a recipe the catalogue lacks or one that makes no item (an enchant).
function ns.quoteRecipe(id)
	if not ns.me() or not ns.price then
		return nil
	end
	local r = recipe(id, columns("recipe"))
	if not r then
		return nil
	end
	local held = stock()
	local q = ns.Crafting.quote(r, ns.price, function(x)
		return held[x] or 0
	end, ns.price.cut)
	q.recipe = r
	return q
end

-- /gf shop: the Crafting page, recipes by profit.
ns.commands.shop = function()
	ns.openPage("crafting")
end
