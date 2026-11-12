-- Gold Forever: tooltips. An item's gets how many each character holds (HeldView.lua) and one price
-- block (vendor, AH, AH min, disenchant, suggestion), one price a line with its label on the left. A
-- mob's gets what the characters have looted from it (MobStats.lua).

local _, ns = ...
local L = ns.L
local Encode = ns.Encode
local Catalogue = ns.Catalogue
local SaveView = ns.SaveView
local price = ns.price
local worth, coins = price.worth, price.coins

-- Tooltip lines -----------------------------------------------------------------------------------------------

-- Every line the addon adds to a tooltip, in Settings' order; each is Off, shown with Shift, or Always
-- (settings.tooltip, its defaults in Save.lua; addon#98).
ns.TOOLTIP_LINES = {
	{ key = "bagVerdict", name = L["Suggestion"], blurb = L["On a bag or bank item: post, vendor, disenchant or keep, and why."] },
	{ key = "vendor", name = L["Vendor"], blurb = L["What a vendor pays for it."] },
	{ key = "price", name = L["AH"], blurb = L["Its auction house market value: everyone's price, else your scan's."] },
	{ key = "minBuyout", name = L["AH (min)"], blurb = L["The cheapest listing's buyout."] },
	{ key = "disenchant", name = L["Disenchant"], blurb = L["What disenchanting one gives on average, on items that can be disenchanted."] },
	{ key = "payback", name = L["Recipe payback"], blurb = L["On a recipe item: how many crafts pay back its price at today's margin."] },
	{ key = "held", name = L["Held counts"], blurb = L["How many each of your characters holds, in bags, bank and mail."] },
	{ key = "mob", name = L["Mob loot"], blurb = L["On a mob you have looted: what a loot is worth and its likeliest drops."] },
	{ key = "starter", name = L["Quest starters"], blurb = L["On a mob: the quest-starting items it drops, and whether you did the quest."] },
	{ key = "bestReward", name = L["Best quest reward"], blurb = L["On the quest reward worth the most: what it sells for."] },
	{ key = "bagMark", name = L["Cheapest in your bags"], blurb = L["On the marked stack in full bags: what it is worth in all."] },
	{ key = "vendorResale", name = L["Vendor resale"], blurb = L["At a merchant, on an item that sells for more on the auction house: what it fetches."] },
}

local function shiftHeld()
	return IsShiftKeyDown and IsShiftKeyDown() or false
end

-- Whether the line `key` shows in a tooltip drawn now.
function ns.tipLine(key)
	local mode = ns.settings("tooltip")[key]
	return mode == "always" or (mode == "shift" and shiftHeld())
end

-- Only the lines there are: a saved mode for a line gone (supply, gf#367) waits on nothing.
local function anyOnShift()
	local modes = ns.settings("tooltip")
	for _, line in ipairs(ns.TOOLTIP_LINES) do
		if modes[line.key] == "shift" then
			return true
		end
	end
	return false
end

-- An open tooltip drawn again, so lines on Shift come and go with the key: its data asked for again, or,
-- on a tooltip without, its owner's OnEnter run again.
local function redraw(tooltip)
	if not tooltip or not tooltip.IsShown or not tooltip:IsShown() then
		return
	end
	if tooltip.RefreshData then
		tooltip:RefreshData()
		return
	end
	local owner = tooltip.GetOwner and tooltip:GetOwner()
	local onEnter = owner and owner.GetScript and owner:GetScript("OnEnter")
	if onEnter then
		onEnter(owner)
	end
end

local SHIFT = { LSHIFT = true, RSHIFT = true }
ns.on("MODIFIER_STATE_CHANGED", "tooltip lines", function(key)
	if not SHIFT[key] or not SaveView.loaded() or not anyOnShift() then
		return
	end
	redraw(GameTooltip)
	redraw(ItemRefTooltip)
end)

local function itemName(id)
	return Catalogue.name("item", id) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or string.format(L["item %d"], id)
end

-- "looted 40× · ~7c a loot" and the three likeliest drops, for an NPC looted before.
local function mobLines(npc)
	local mobs = ns.mobStats()
	if not mobs then
		return nil
	end
	local m = mobs[npc]
	if not m then
		return nil
	end
	local value = ns.Views.mobValue(m, worth)
	local drops = {}
	for id, d in pairs(m.items) do
		drops[#drops + 1] = { id = id, chance = d.dropped / m.loots }
	end
	table.sort(drops, function(a, b)
		return a.chance > b.chance
	end)
	local top = {}
	for i = 1, math.min(3, #drops) do
		top[i] = string.format("%s %d%%", itemName(drops[i].id), math.floor(drops[i].chance * 100 + 0.5))
	end
	-- Quest starters among its drops, with whether this character has done the quest.
	local starters = {}
	for id, d in pairs(m.items) do
		local quest = Catalogue.startsQuest(id)
		if quest then
			local done = Catalogue.questDone(quest)
			starters[#starters + 1] = string.format(L["%s (%d%% of loots)%s"], itemName(id), math.floor(d.dropped / m.loots * 100 + 0.5),
				done == false and L[" · not done"] or done and L[" · done"] or "")
		end
	end
	return string.format(L["looted %dx · ~%s a loot"], m.loots, coins(value)), #top > 0 and table.concat(top, " · ") or nil,
		#starters > 0 and string.format(L["Drops a quest starter: %s"], table.concat(starters, ", ")) or nil
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function mobTooltip(tooltip, data)
		if tooltip ~= GameTooltip or not data or not SaveView.loaded() then
			return
		end
		-- A unit the client keeps secret: nothing to look up (tested before any other use of the value).
		if ns.secret(data.guid) then
			return
		end
		local guid = data.guid or (tooltip.GetUnit and select(2, tooltip:GetUnit()))
		if ns.secret(guid) then
			return
		end
		local npc = Encode.npcId(guid)
		if not npc then
			return
		end
		local summary, drops, starters = mobLines(npc)
		if not summary then
			return
		end
		if ns.tipLine("mob") then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. summary, 1, 1, 1)
			if drops then
				tooltip:AddLine(drops, 0.7, 0.7, 0.7, true)
			end
		end
		if starters and ns.tipLine("starter") then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. starters, 1, 0.82, 0, true)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		ns.safely("mob tooltip", mobTooltip, tooltip, data)
	end)
end

-- Item tooltips ----------------------------------------------------------------------------------------------

-- "Held": how many every character holds (HeldView.lua), first of the addon's item lines.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function heldTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not data.id or not SaveView.loaded() then
			return
		end
		if not ns.tipLine("held") then
			return
		end
		local line = ns.HeldView.line(data.id)
		if line then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. line, 0.8, 0.8, 0.8, true)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("held tooltip", heldTooltip, tooltip, data)
	end)
end

-- The price block (gf#360, gf#367): one line each for the bag's suggestion, what a vendor pays, the market
-- value, the cheapest listing and disenchanting one, in that order, each with its own mode; a line with no
-- value is left out. On a stack, a price reads "2s (50c/each)", one item the price alone.
local BLOCK = {
	{ key = "bagVerdict", label = L["Suggestion"], text = true },
	{ key = "vendor", label = L["Vendor"] },
	{ key = "price", label = L["AH"] },
	{ key = "minBuyout", label = L["AH (min)"] },
	{ key = "disenchant", label = L["Disenchant"] },
}

local TooltipBlock = {}
ns.TooltipBlock = TooltipBlock

local function priced(unit, count, coins)
	if count > 1 then
		return string.format(L["%s (%s/each)"], coins(unit * count), coins(unit))
	end
	return coins(unit)
end

-- The block's { label, value } rows for `count` of item `id`: values[key](id, slot) is asked only for a
-- line that shows (shown(key)); a price is one unit's, the suggestion's value its words.
function TooltipBlock.rows(id, count, values, shown, coins, slot)
	local rows = {}
	for _, line in ipairs(BLOCK) do
		local value = shown(line.key) and values[line.key](id, slot)
		if value and (line.text or value > 0) then
			rows[#rows + 1] = { line.label, line.text and value or priced(value, count, coins) }
		end
	end
	return rows
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- The bag verdict of the slot under the pointer, drawn for the item shown (BagVerdict.lua).
	local function bagSlot(tooltip, id)
		local owner = tooltip == GameTooltip and tooltip.GetOwner and tooltip:GetOwner()
		return owner and ns.BagVerdict and ns.BagVerdict.at(owner, id)
	end
	local VALUES = {
		vendor = function(id) return price.vendor(id) end,
		price = function(id) return price.market(id) end,
		minBuyout = function(id) return ns.Prices.cheapest(id) end,
		disenchant = function(id) return (price.disenchant(id)) end,
		bagVerdict = function(id, slot)
			return slot and ns.BagVerdict.line(slot, coins, slot.word == "post" and ns.BagVerdict.listing(id) or nil)
		end,
	}
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function blockTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not data.id or not SaveView.loaded() or not ns.me() then
			return
		end
		local slot = bagSlot(tooltip, data.id)
		local rows = TooltipBlock.rows(data.id, slot and slot.count or 1, VALUES, ns.tipLine, coins, slot)
		for _, row in ipairs(rows) do
			tooltip:AddDoubleLine(ns.tipPrefix(tooltip) .. row[1], row[2], 1, 1, 1, 1, 1, 1)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("price block tooltip", blockTooltip, tooltip, data)
	end)
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local STALE_SHADE = 0.6 -- the tooltip's grey, as the addon's muted text (|cff999999)
	ns.listen("recipesRead", "payback tooltip", ns.Crafting.forgetRecipeNames)
	local function paybackTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not ns.me() or not ns.tipLine("payback") then
			return
		end
		local taught = ns.Crafting.taughtName(itemName(data.id))
		local recipe = taught and ns.Crafting.recipeNamed(taught)
		local quote = recipe and ns.quoteRecipe(recipe)
		if not quote then
			return
		end
		local gear = ns.isGear(quote.recipe.output)
		local line = ns.Crafting.paybackLine(ns.Crafting.teachingPrice(data.id, price.market), quote.profit, coins, gear)
		if line then
			local shade = gear and STALE_SHADE or 0.8
			tooltip:AddLine(ns.tipPrefix(tooltip) .. line, shade, shade, shade, true)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("payback tooltip", paybackTooltip, tooltip, data)
	end)
end
