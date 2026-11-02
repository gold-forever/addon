-- Gold Forever: big drops and quest starters called out as they are looted.

local _, ns = ...
local Encode = ns.Encode
local Catalogue = ns.Catalogue

local BIG_DROP = ns.BIG_DROP
local price = ns.price
local worth, itemInfo, disenchantWorth, enchanting, coins = price.worth, price.itemInfo, price.disenchant, price.enchanting, price.coins

local function settings()
	return ns.settings("appraiser")
end

-- Big drops: an item worth the threshold or more (sold or, for an enchanter who can, disenchanted),
-- or any rare or better, gets a message mid-screen and a sound; so does a quest starter, once per
-- item a session (a starter known only from its tooltip cannot say whether its quest is done).
local startersAlerted = {} -- item ID -> true
local function bigDrops(taken)
	local threshold = settings().bigDrop or BIG_DROP
	for key, n in pairs(taken) do
		local id = Encode.itemId(key)
		local quality, _, _, _, name = itemInfo(id or 0)
		if id then
			local value = (worth(id) or 0) * n
			local de, skill = disenchantWorth(id)
			if de and enchanting() >= skill then
				value = math.max(value, de * n)
			end
			local quest = Catalogue.startsQuest(id)
			if quest and not Catalogue.questDone(quest) and not startersAlerted[id] then
				startersAlerted[id] = true
				local text = "Starts a quest: " .. (name or ("item " .. id))
				ns.alert(text .. " - right-click it in your bags to start it.")
			elseif not quest and ((threshold > 0 and value >= threshold) or (quality or 0) >= 3) then
				local text = string.format("Big drop: %s%s - %s", n > 1 and (n .. "x ") or "", name or ("item " .. id), value > 0 and coins(value) or "no price")
				ns.alert(text)
			end
		end
	end
end

table.insert(ns.lootListeners, function(_, taken)
	ns.safely("big drop", bigDrops, taken)
end)

-- "/gf bigdrop 2" alerts on drops worth 2 gold or more; "/gf bigdrop 0" on rares only.
ns.commands.bigdrop = function(arg)
	local gold = tonumber(arg)
	if not gold then
		ns.say(string.format("big drops are worth %s or more, and every rare. /gf bigdrop <gold> changes it.", coins(settings().bigDrop or BIG_DROP)))
		return
	end
	settings().bigDrop = math.floor(gold * 10000)
	ns.say(string.format("big drops from %s.", gold > 0 and coins(gold * 10000) or "rare quality (no gold threshold)"))
end
