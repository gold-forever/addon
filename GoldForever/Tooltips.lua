-- Gold Forever: tooltips. An item's gets what the own scan, a vendor and disenchanting give for it; a
-- mob's what the characters have looted from it (MobStats.lua).

local _, ns = ...
local Encode = ns.Encode
local Catalogue = ns.Catalogue
local price = ns.price
local ownMarket, vendor, worth, disenchantWorth, enchanting, coins = price.own, price.vendor, price.worth, price.disenchant, price.enchanting, price.coins

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
	return string.format("looted %d× · ~%s a loot", m.loots, coins(value)), #top > 0 and table.concat(top, " · ") or nil,
		#starters > 0 and ("Drops a quest starter: " .. table.concat(starters, ", ")) or nil
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function mobTooltip(tooltip, data)
		if tooltip ~= GameTooltip or not data or not ns.db() then
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

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function itemTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not data.id or not ns.db() then
			return
		end
		local m, v = ownMarket(data.id), vendor(data.id) -- the own scan's line; the pool has its own
		local de, skill = disenchantWorth(data.id)
		if not m and not v and not de then
			return
		end
		local parts = {}
		if m then
			parts[#parts + 1] = "Your scan " .. coins(m)
		end
		if v then
			parts[#parts + 1] = (m and "vendor " or "Vendor ") .. coins(v)
		end
		if #parts > 0 then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. table.concat(parts, " · "), 1, 1, 1)
		end
		if de and de > 0 then
			local sale = worth(data.id) or 0
			local verdict = de > sale and " · |cff56c98fbetter than selling|r" or ""
			local short = enchanting() < skill and string.format(" |cff999999(needs Enchanting %d)|r", skill) or ""
			tooltip:AddLine("Disenchant ≈ " .. coins(de) .. verdict .. short, 1, 1, 1)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("appraiser tooltip", itemTooltip, tooltip, data)
	end)
end
