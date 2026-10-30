-- Gold Forever: tooltips. An item's gets how many each character holds (HeldView.lua), what the own scan
-- and disenchanting give for it, and the pool's prices (Prices.lua), one price a line with its label on
-- the left; no vendor value, as the game's own Sell Price line shows it (addon#20). A mob's gets what the
-- characters have looted from it (MobStats.lua).

local _, ns = ...
local Encode = ns.Encode
local Catalogue = ns.Catalogue
local SaveView = ns.SaveView
local price = ns.price
local ownMarket, worth, disenchantWorth, enchanting, coins = price.own, price.worth, price.disenchant, price.enchanting, price.coins

local function itemName(id)
	return Catalogue.name("item", id) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or ("item " .. id)
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
			starters[#starters + 1] = string.format("%s (%d%% of loots)%s", itemName(id), math.floor(d.dropped / m.loots * 100 + 0.5),
				done == false and " · not done" or done and " · done" or "")
		end
	end
	return string.format("looted %dx · ~%s a loot", m.loots, coins(value)), #top > 0 and table.concat(top, " · ") or nil,
		#starters > 0 and ("Drops a quest starter: " .. table.concat(starters, ", ")) or nil
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
		if summary then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. summary, 1, 1, 1)
			if drops then
				tooltip:AddLine(drops, 0.7, 0.7, 0.7, true)
			end
			if starters then
				tooltip:AddLine(starters, 1, 0.82, 0, true)
			end
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
		if ns.settings("prices").held == false then
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

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function itemTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not data.id or not SaveView.loaded() then
			return
		end
		local m = ownMarket(data.id) -- the own scan's line; the pool has its own
		if m then
			tooltip:AddDoubleLine(ns.tipPrefix(tooltip) .. "Your scan", coins(m), 1, 1, 1, 1, 1, 1)
		end
		local de, skill = disenchantWorth(data.id)
		if de and de > 0 then
			local sale = worth(data.id) or 0
			local verdict = de > sale and " |cff56c98f(better than selling)|r" or ""
			local short = enchanting() < skill and string.format(" |cff999999(needs Enchanting %d)|r", skill) or ""
			tooltip:AddDoubleLine(ns.tipPrefix(tooltip) .. "Disenchant" .. verdict .. short, "~" .. coins(de), 1, 1, 1, 1, 1, 1)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("appraiser tooltip", itemTooltip, tooltip, data)
	end)
end

-- The pool's prices from the companion's file (ReadModels/Prices.lua), under the own scan's line.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local STALE_SHADE = 0.6 -- the tooltip's grey, as the addon's muted text (|cff999999)
	-- Each { label, value } row as a double line, greyed when stale.
	local function addRows(tooltip, rows, stale)
		if not rows then
			return
		end
		local shade = stale and STALE_SHADE or 1
		for _, row in ipairs(rows) do
			tooltip:AddDoubleLine(ns.tipPrefix(tooltip) .. row[1], row[2], shade, shade, shade, shade, shade, shade)
		end
	end
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function poolTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not ns.me() then
			return
		end
		-- Settings → Modules can switch the line off.
		if ns.settings("prices").tooltip == false then
			return
		end
		local Prices = ns.Prices -- loaded after this file
		local now = GetServerTime()
		-- In a zone with a neutral auction house, its market's rows first (design 009 decision 9).
		local neutral = Prices.neutralMarkets()
		if neutral then
			addRows(tooltip, Prices.rows(GoldForever_Prices, neutral, data.id, now, "Neutral AH"))
		end
		addRows(tooltip, Prices.rows(GoldForever_Prices, Prices.mine(), data.id, now))
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("pool tooltip", poolTooltip, tooltip, data)
	end)
end
