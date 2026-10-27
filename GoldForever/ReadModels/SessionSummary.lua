-- Gold Forever: what the farming session (Session.lua) is worth: the loot at the prices (ns.price), the
-- gold and XP per hour with the time to the next level, and when the bags will be full; big drops and
-- quest starters are called out as they come. The HUD (Hud.lua) and the hub's Session page show it.

local _, ns = ...
local Encode = ns.Encode
local Catalogue = ns.Catalogue
local Session = ns.Session

local TOP_ITEMS = 4
local BIG_DROP = 10000 -- 1 gold: the default big-drop threshold
ns.BIG_DROP = BIG_DROP

local price = ns.price
local worth, itemInfo, disenchantWorth, enchanting, coins = price.worth, price.itemInfo, price.disenchant, price.enchanting, price.coins

local function settings()
	return ns.settings("appraiser")
end

local function number(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function itemsValue(session)
	local total, unpriced = 0, 0
	for id, n in pairs(session.items) do
		local w = worth(id)
		if w then
			total = total + w * n
		else
			unpriced = unpriced + n
		end
	end
	return total, unpriced
end

-- The seconds the session has run: an ended one stops its clock at its last loot (or at Stop).
local function elapsed(session)
	return (Session.idle() and session.last or GetTime()) - session.start
end

-- The session in figures, for the HUD and the hub's Session page: nil before any session, or when the
-- last one is not shown (Session.get).
function ns.sessionSummary()
	local session = Session.get()
	if not session then
		return nil
	end
	local xpSeen = Session.xpBar()
	local secs = elapsed(session)
	local value, unpriced = itemsValue(session)
	local toLevel = xpSeen and xpSeen.max > 0 and (xpSeen.max - xpSeen.cur) or 0
	local used = session.bagBase - session.bagFree
	local filling = GetTime() - session.bagBaseAt
	local ranked = {}
	for id, n in pairs(session.items) do
		ranked[#ranked + 1] = { id = id, n = n, value = (worth(id) or 0) * n }
	end
	table.sort(ranked, function(a, b)
		return a.value > b.value
	end)
	return {
		ended = Session.idle(), elapsed = secs, coin = session.coin, value = value, unpriced = unpriced,
		rates = ns.Views.sessionRates(session, secs, value, toLevel),
		xp = session.xp, kills = session.kills, nextLevel = xpSeen and (xpSeen.level or 0) + 1,
		bagFree = session.bagFree,
		fullIn = session.bagFree > 0 and used >= 1 and filling >= 120 and session.bagFree / (used / filling) or nil,
		ranked = ranked,
		bigDrop = settings().bigDrop or BIG_DROP,
	}
end

-- What the item info gives for a looted item: quality and name.
function ns.sessionItem(id)
	local quality, _, _, _, name = itemInfo(id)
	return quality, name
end

-- The session in words, from its figures (ns.sessionSummary).
local function text()
	local sum = ns.sessionSummary()
	if not sum then
		return Session.automatic() and "Loot something to start a session." or "Press Start on the HUD to start a session."
	end
	local session, xpSeen = Session.get(), Session.xpBar()
	local elapsed, r = sum.elapsed, sum.rates
	local lines = {
		string.format("%s%d:%02d", sum.ended and "Ended after " or "Farming ", math.floor(elapsed / 60), math.floor(elapsed % 60)),
		"Coin: " .. coins(sum.coin),
		"Items: " .. coins(sum.value) .. (sum.unpriced > 0 and string.format(" (+%d unpriced)", sum.unpriced) or ""),
		"|cffffffffTotal: " .. coins(r.total) .. "|r",
	}
	if r.rated then
		table.insert(lines, "|cffffd100Per hour: " .. coins(r.goldPerHour) .. "|r")
	else
		table.insert(lines, "|cff999999Per hour: after a minute|r")
	end
	-- XP, and when the next level comes at this pace (not at the level cap: no XP to gain).
	if sum.xp > 0 and xpSeen and xpSeen.max > 0 then
		local line = "XP: " .. number(sum.xp)
		if r.rated then
			line = line .. " · " .. number(r.xpPerHour) .. "/h · level " .. sum.nextLevel .. " in " .. Encode.duration(r.dingIn or 0)
		end
		if (session.xpKills or 0) > 0 and session.killXp > 0 then
			line = line .. string.format(" (~%s kills)", number(r.killsToLevel or 0))
		end
		table.insert(lines, line)
	end
	-- Bags: free slots, and when they run out at the rate they have been filling.
	local bags = "Bags: " .. sum.bagFree .. " free"
	if sum.bagFree == 0 then
		bags = "|cffff5555Bags full|r"
	elseif sum.fullIn then
		bags = bags .. " · full in ~" .. Encode.duration(sum.fullIn)
	end
	table.insert(lines, bags)
	-- The most valuable items so far.
	for i = 1, math.min(TOP_ITEMS, #sum.ranked) do
		local item = sum.ranked[i]
		local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item.id)) or ("item " .. item.id)
		table.insert(lines, string.format("|cffaaaaaa%d× %s: %s|r", item.n, name, item.value > 0 and coins(item.value) or "no price"))
	end
	return table.concat(lines, "\n")
end

-- The session in words, for the tests.
ns.test.sessionText = text

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
				ns.alert(text .. " — right-click it in your bags to start it.")
			elseif not quest and ((threshold > 0 and value >= threshold) or (quality or 0) >= 3) then
				local text = string.format("Big drop: %s%s — %s", n > 1 and (n .. "× ") or "", name or ("item " .. id), value > 0 and coins(value) or "no price")
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

-- "/gf session": the session in words, in the chat.
ns.commands.session = function()
	ns.say("\n" .. text())
end
