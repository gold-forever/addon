-- Gold Forever: what the farming session (Session.lua) is worth: the loot at the prices (ns.price), the
-- gold and XP per hour with the time to the next level, and when the bags will be full. The HUD (Hud.lua)
-- and the hub's Session page show it; big drops are called out by BigDrops.lua.

local _, ns = ...
local L = ns.L
local Encode = ns.Encode
local Session = ns.Session

local TOP_ITEMS = 4
local BIG_DROP = 10000 -- 1 gold: the default big-drop threshold
ns.BIG_DROP = BIG_DROP

local price = ns.price
local worth, itemInfo, coins = price.worth, price.itemInfo, price.coins

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

-- XP, and when the next level comes at this pace; nil at the level cap (no XP to gain).
local function xpLine(sum, session, xpSeen)
	if not (sum.xp > 0 and xpSeen and xpSeen.max > 0) then
		return nil
	end
	local r = sum.rates
	local line = string.format(L["XP: %s"], number(sum.xp))
	if r.rated then
		line = line .. string.format(L[" · %s/h · level %d in %s"], number(r.xpPerHour), sum.nextLevel, Encode.duration(r.dingIn or 0))
	end
	if (session.xpKills or 0) > 0 and session.killXp > 0 then
		line = line .. string.format(L[" (~%s kills)"], number(r.killsToLevel or 0))
	end
	return line
end

-- Free slots, and when they run out at the rate they have been filling.
local function bagsLine(sum)
	if sum.bagFree == 0 then
		return "|cffff5555" .. L["Bags full"] .. "|r"
	end
	local bags = string.format(L["Bags: %d free"], sum.bagFree)
	if sum.fullIn then
		bags = bags .. string.format(L[" · full in ~%s"], Encode.duration(sum.fullIn))
	end
	return bags
end

-- The session in words, from its figures (ns.sessionSummary).
local function text()
	local sum = ns.sessionSummary()
	if not sum then
		return Session.automatic() and L["Loot something to start a session."] or L["Press Start on the HUD to start a session."]
	end
	local elapsed, r = sum.elapsed, sum.rates
	local lines = {
		string.format(sum.ended and L["Ended after %d:%02d"] or L["Farming %d:%02d"], math.floor(elapsed / 60), math.floor(elapsed % 60)),
		string.format(L["Coin: %s"], coins(sum.coin)),
		string.format(L["Items: %s"], coins(sum.value)) .. (sum.unpriced > 0 and string.format(L[" (+%d unpriced)"], sum.unpriced) or ""),
		"|cffffffff" .. string.format(L["Total: %s"], coins(r.total)) .. "|r",
	}
	if r.rated then
		table.insert(lines, "|cffffd100" .. string.format(L["Per hour: %s"], coins(r.goldPerHour)) .. "|r")
	else
		table.insert(lines, "|cff999999" .. L["Per hour: after a minute"] .. "|r")
	end
	local xp = xpLine(sum, Session.get(), Session.xpBar())
	if xp then
		table.insert(lines, xp)
	end
	table.insert(lines, bagsLine(sum))
	-- The most valuable items so far.
	for i = 1, math.min(TOP_ITEMS, #sum.ranked) do
		local item = sum.ranked[i]
		local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(item.id)) or string.format(L["item %d"], item.id)
		table.insert(lines, string.format("|cffaaaaaa" .. L["%dx %s: %s"] .. "|r", item.n, name, item.value > 0 and coins(item.value) or L["no price"]))
	end
	return table.concat(lines, "\n")
end

-- The session in words, for the tests.
ns.test.sessionText = text

-- "/gf session": the session in words, in the chat.
ns.commands.session = function()
	ns.say("\n" .. text())
end
