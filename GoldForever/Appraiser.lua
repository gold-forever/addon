-- Gold Forever: a loot appraiser. While farming, a small window adds up what the loot is worth, in
-- coin and items, the gold and XP per hour with the time to the next level, and when the bags will
-- be full; every item's tooltip gets its value, and every mob's what the characters have looted from
-- it. The session survives a /reload. Prices come from the
-- latest full scan of the character's own auction house in the saved file, valued as the web app
-- does: the better of the market value after the auction cut and the vendor price.

local _, ns = ...
local Encode = ns.Encode

local CUT = 0.05 -- a faction auction house's cut; the character sells on its own
local IDLE_SECONDS = 15 * 60 -- the web app's session split
local MIN_RATE_SECONDS = 60 -- no gold per hour for the first minute: one lucky drop is not a rate
local TOP_ITEMS = 4
local BIG_DROP = 10000 -- 1 gold: the default big-drop threshold
ns.BIG_DROP = BIG_DROP

-- Prices --------------------------------------------------------------------------------------------

local prices -- item ID -> market value, from the latest full scan of the character's market
local cheapestPrices -- item ID -> the cheapest unit listed in that scan
local pricedFrom -- ns.scanVersion when prices were built; a new scan (Market.lua) rebuilds them
local pricedAt -- when that scan was taken

-- A scan this size or smaller is read into prices at once; a bigger one over several frames, the prices
-- before it staying in use until it is done (design 009, Performance budget: a retail scan's ~110,000
-- rows took ~100 ms to read in one go, a hitch at the first tooltip after a scan or a login).
local SYNC_CHUNKS = 10 -- of Encode.ROWS_PER_CHUNK (500) rows: 5,000 rows
local CHUNKS_PER_FRAME = 2
local ITEMS_PER_FRAME = 500
local building -- the scan version a build in progress is for

-- A market without its side ("EU-Aszune-neutral" → "EU-Aszune"): on retail one auction house serves a
-- connected realm group, whichever side's auctioneer opened it (Market.lua keeps scans the same way).
local function group(market)
	return string.match(market or "", "^(.*)%-[^-]+$") or market
end

-- The newest full scan of the character's market, or nil: on retail any side's scan of the realm group
-- (a Horde character scanning at the Bazaar's neutral auctioneer read no prices of its own before).
local function latestScan()
	local db, me = ns.db(), ns.me()
	if not me then
		return nil
	end
	local market = ns.market(string.lower(me.faction or "?"))
	local retail = ns.Realms.isRetail(db.client and db.client.interface)
	local mine = retail and group(market)
	local latest
	for _, scan in ipairs(db.scans) do
		if scan.kind == "full" and (scan.market == market or (mine and group(scan.market) == mine)) and (not latest or scan.t > latest.t) then
			latest = scan
		end
	end
	return latest
end

-- Reads one chunk of rows into listings: item ID -> { unit1, qty1, unit2, qty2, … }, a flat list an item
-- (one table an item, not one a row) and no string a row: the pattern reads the columns in place.
local function readChunk(chunk, listings)
	for key, unit, qty in string.gmatch(chunk, "([^,;]+),(%d+),(%d+)[^;]*") do
		local id = Encode.itemId(key)
		if id then
			local l = listings[id]
			if not l then
				l = {}
				listings[id] = l
			end
			l[#l + 1] = tonumber(unit)
			l[#l + 1] = tonumber(qty)
		end
	end
end

-- One item's market value and cheapest unit into the tables given.
local function priceItem(id, l, into, low)
	into[id] = Encode.marketValueFlat(l)
	low[id] = Encode.cheapestFlat(l)
end

-- After a scan's prices are in: the deals line, once (AuctionPanel.lua says it).
local function pricesReady()
	if ns.dealsPending and ns.announceDeals then
		ns.dealsPending = nil
		C_Timer.After(0, function()
			ns.safely("deals", ns.announceDeals)
		end)
	end
end

local function buildPrices()
	local version = ns.scanVersion or 0
	local latest = latestScan()
	local chunks = latest and latest.rows or {}
	if #chunks <= SYNC_CHUNKS then
		local listings, newPrices, newLow = {}, {}, {}
		for _, chunk in ipairs(chunks) do
			readChunk(chunk, listings)
		end
		for id, l in pairs(listings) do
			priceItem(id, l, newPrices, newLow)
		end
		prices, cheapestPrices, pricedFrom, pricedAt = newPrices, newLow, version, latest and latest.t
		pricesReady()
		return
	end
	if building == version then
		return
	end
	building = version
	prices, cheapestPrices = prices or {}, cheapestPrices or {}
	local listings, newPrices, newLow, i = {}, {}, {}, 0
	local ids, j
	local function step()
		if building ~= version then
			return -- a newer scan started its own build
		end
		if i < #chunks then
			for k = i + 1, math.min(i + CHUNKS_PER_FRAME, #chunks) do
				readChunk(chunks[k], listings)
			end
			i = math.min(i + CHUNKS_PER_FRAME, #chunks)
		else
			if not ids then
				ids, j = {}, 0
				for id in pairs(listings) do
					ids[#ids + 1] = id
				end
			end
			for k = j + 1, math.min(j + ITEMS_PER_FRAME, #ids) do
				priceItem(ids[k], listings[ids[k]], newPrices, newLow)
			end
			j = math.min(j + ITEMS_PER_FRAME, #ids)
			if j >= #ids then
				prices, cheapestPrices, pricedFrom, pricedAt = newPrices, newLow, version, latest.t
				building = nil
				pricesReady()
				return
			end
		end
		ns.after(0, "prices", step)
	end
	step()
end

-- The own scan's market value: the cheapest 15% of the units listed, so an item with one listing is
-- worth what that one asks.
local function ownMarket(id)
	if not prices or pricedFrom ~= (ns.scanVersion or 0) then
		buildPrices()
	end
	return prices[id]
end

-- An item's market value: the shared pool's (many players' scans, outliers dropped, a jump held until a
-- later scan confirms it), else the own scan's (manual test run 001: Poached Nettlefish "sold for"
-- 47,499g on the Crafting page from a single listing in the own scan).
local function market(id)
	if ns.Prices and ns.Prices.value then
		return (ns.Prices.value(id))
	end
	return ownMarket(id)
end

local function cheapest(id)
	ownMarket(id) -- builds the prices when needed
	return cheapestPrices[id]
end

-- What buying one costs at the auction house: the pool's minimum when the prices file has it, picked as
-- the market value is, else the own scan's cheapest (Prices.lua).
local function buy(id)
	if ns.Prices and ns.Prices.cheapest then
		return ns.Prices.cheapest(id)
	end
	return cheapest(id)
end

-- The own scan's market value, cheapest unit and time, for the pool's fallback (Prices.lua).
function ns.ownPrice(id)
	local value = ownMarket(id)
	if value then
		return value, cheapestPrices[id], pricedAt
	end
end

-- What a vendor asks for one, when it sells it without limit: catalogue.vendor is the price of one
-- purchase of qty units (fields.vendor = buy,limited,t,qty).
local function vendorBuy(id)
	local row = ns.db().catalogue.vendor[id]
	if not row then
		return nil
	end
	local buy, limited, _, qty = strsplit(",", row)
	if limited == "1" or not tonumber(buy) then
		return nil
	end
	return tonumber(buy) / math.max(1, tonumber(qty) or 1)
end

-- An item's catalogue row read once a session: { name, quality, ilvl, class, sell }. Tooltips ask for
-- the same items over and over, and splitting the whole row each time made garbage on every hover.
-- At most ROWS_KEPT items are kept (a page listing thousands would hold them all); past that it starts over.
local ROWS_KEPT = 2000
local rowsRead, rowsKept = {}, 0
local function catalogueInfo(id)
	local info = rowsRead[id]
	if info then
		return info
	end
	local row = ns.db().catalogue.items[id]
	if not row then
		return nil -- not catalogued yet: asked again next time
	end
	local name, quality, ilvl, class, _, _, sell = strsplit(",", row)
	info = { name = name, quality = tonumber(quality), ilvl = tonumber(ilvl), class = tonumber(class), sell = tonumber(sell) }
	if rowsKept >= ROWS_KEPT then
		rowsRead, rowsKept = {}, 0
	end
	rowsRead[id] = info
	rowsKept = rowsKept + 1
	return info
end

-- What a vendor pays, from the catalogue (`sell` is its 7th column), else from the client.
local function vendor(id)
	local info = catalogueInfo(id)
	local sell = info and info.sell
	if not sell and C_Item and C_Item.GetItemInfo then
		sell = (select(11, C_Item.GetItemInfo(id)))
	end
	return sell and sell > 0 and sell or nil
end

-- One unit's worth: the better of selling it on the auction house (after the cut) and to a vendor, and
-- which ("auction" or "vendor").
local function worth(id)
	local m = market(id)
	local net = m and math.floor(m * (1 - CUT))
	local v = vendor(id)
	if net and (not v or net >= v) then
		return net, "auction"
	end
	if v then
		return v, "vendor"
	end
end

-- Quality (0 poor … 4 epic), item level, class and vendor price, from the catalogue, else the client.
local function itemInfo(id)
	local info = catalogueInfo(id)
	if info then
		return info.quality, info.ilvl, info.class, info.sell, info.name
	end
	if C_Item and C_Item.GetItemInfo then
		local name, _, quality, ilvl, _, _, _, _, _, _, sell, class = C_Item.GetItemInfo(id)
		return quality, ilvl, class, sell, name
	end
end

local function enchanting()
	local me = ns.me()
	local p = me and me.prof and me.prof[333]
	return p and p.skill or 0
end

-- What disenchanting one is worth, and the skill it needs; nil when it cannot be disenchanted.
local function disenchantWorth(id)
	local quality, ilvl, class = itemInfo(id)
	local de = quality and ns.Disenchant.of(quality, ilvl, class)
	if not de then
		return nil
	end
	return ns.Disenchant.value(de.outcomes, worth), de.skill
end

-- The quest an item starts: its ID when a loot window said so, true when only its tooltip does.
local function startsQuest(id)
	local catalogue = ns.db().catalogue
	local quest = catalogue.questStarters and catalogue.questStarters[id]
	if quest then
		return quest
	end
	local tooltip = catalogue.tooltips[id] or (ns.lean and ns.itemTooltipText(id))
	return tooltip and (string.find(tooltip, ITEM_STARTS_QUEST or "This Item Begins a Quest", 1, true) and true) or nil
end

-- Whether this character finished the quest; unknown (nil) without a quest ID.
local function questDone(quest)
	if type(quest) ~= "number" then
		return nil
	end
	local completed = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
	return completed and completed(quest) or false
end

-- Money with the game's coin icons, as its own Sell Price line; from a gold up, gold and silver only.
-- Retail has the function under C_CurrencyInfo (manual test run 001: the tooltips showed plain text).
local coinTexture = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString
local function coins(copper)
	copper = math.floor(copper + 0.5)
	if copper >= 10000 then
		copper = math.floor(copper / 100) * 100
	end
	if coinTexture then
		return coinTexture(copper)
	end
	return Encode.money(copper)
end

-- For the loot advisor (Advisor.lua): the same prices and valuation as here.
ns.price = {
	market = market, own = ownMarket, cheapest = cheapest, buy = buy, vendor = vendor, vendorBuy = vendorBuy, worth = worth, itemInfo = itemInfo,
	disenchant = disenchantWorth, enchanting = enchanting, coins = coins, cut = CUT,
}

-- Session ---------------------------------------------------------------------------------------------

-- { start, last, coin, items = { [id] = count }, xp, killXp, kills, bagBase, bagBaseAt, bagFree }
local session

local function idle()
	return not session or session.stopped or GetTime() - session.last > IDLE_SECONDS
end

-- Free slots in general-purpose bags (profession bags take only their own kind of item).
local function freeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, bagType = C_Container.GetContainerNumFreeSlots(bag)
		if (bagType or 0) == 0 then
			free = free + (n or 0)
		end
	end
	return free
end

-- The current session, started now when there is none or the last one went idle. A kill's XP comes
-- before its loot, so either starts one.
local function current()
	local now = GetTime()
	if idle() then
		local free = freeSlots()
		session = {
			start = now, last = now, coin = 0, items = {},
			xp = 0, killXp = 0, kills = 0, xpKills = 0,
			bagBase = free, bagBaseAt = now, bagFree = free,
		}
	end
	session.last = now
	return session
end

-- Bags: the fill rate from slots used since the baseline; selling or emptying bags (free slots go
-- up) starts a new baseline.
local function bagsChanged()
	if idle() then
		return
	end
	local free = freeSlots()
	if free > session.bagFree then
		session.bagBase, session.bagBaseAt = free, GetTime()
	end
	session.bagFree = free
end

-- XP: quest XP counts toward XP per hour, not per kill.
-- The XP bar now, for the time to the next level. The gains come from Levelling.lua, which tells
-- what earned each: only kills count toward "~N kills".
local xpSeen -- { cur, max, level }

local function readXp()
	return { cur = UnitXP("player"), max = UnitXPMax("player"), level = UnitLevel("player") }
end

-- Kills without the combat log (forbidden on Forever): a fight opens when combat starts and closes a
-- few seconds after it ends, once its loot is in; its kills are the larger of its kill-XP gains and the
-- creature corpses looted for the first time, so a grey mob counts too; a corpse looted after its
-- fight closed matches the kill XP already counted rather than counting again (Views.creditKills).
local FIGHT_GRACE = 8 -- seconds after combat for the kill XP (classified 3 s late) and the loot
local fight -- { xpKills, corpses = { guid } } while one is open
local corpsesSeen = {} -- corpse GUIDs already counted
local uncorpsed = {} -- times of kills credited by XP whose corpse is not looted yet (Views.creditKills)

local function closeFight()
	local f = fight
	fight = nil
	if f and session then
		session.kills = session.kills + ns.Views.creditKills(uncorpsed, f.xpKills, f.corpses, corpsesSeen, GetTime())
	end
end

ns.on("PLAYER_REGEN_DISABLED", "session fights", function()
	closeFight() -- a new pull before the last fight's loot was in
	fight = { xpKills = 0, corpses = {} }
end)
ns.on("PLAYER_REGEN_ENABLED", "session fights", function()
	local f = fight
	C_Timer.After(FIGHT_GRACE, function()
		if fight == f then
			ns.safely("session fights", closeFight)
		end
	end)
end)

table.insert(ns.xpListeners, function(gained, kind)
	local s = current()
	s.xp = s.xp + gained
	if kind == "kill" or kind == "boss" then
		s.killXp = s.killXp + gained
		s.xpKills = (s.xpKills or 0) + 1
		if fight then
			fight.xpKills = fight.xpKills + 1
		else
			-- a kill outside any fight (a pet's, a DoT's after combat)
			s.kills = s.kills + ns.Views.creditKills(uncorpsed, 1, nil, corpsesSeen, GetTime())
		end
	end
end)

local function number(n)
	n = math.floor(n + 0.5)
	return BreakUpLargeNumbers and BreakUpLargeNumbers(n) or tostring(n)
end

local function itemsValue()
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

-- The session HUD ------------------------------------------------------------------------------------------

local hud -- the one-line HUD; hud.details is the session panel under it
local huds = {} -- Theme.key -> HUD
local built -- the Theme.key the HUD was drawn under

local function settings()
	return ns.settings("appraiser", { shown = true })
end

local function text()
	if not session then
		return "Loot something to start a session."
	end
	-- An ended session stops its clock at its last loot (or at Stop).
	local elapsed = (idle() and session.last or GetTime()) - session.start
	local value, unpriced = itemsValue()
	local total = session.coin + value
	local lines = {
		string.format("%s%d:%02d", idle() and "Ended after " or "Farming ", math.floor(elapsed / 60), math.floor(elapsed % 60)),
		"Coin: " .. coins(session.coin),
		"Items: " .. coins(value) .. (unpriced > 0 and string.format(" (+%d unpriced)", unpriced) or ""),
		"|cffffffffTotal: " .. coins(total) .. "|r",
	}
	local rated = elapsed >= MIN_RATE_SECONDS
	if rated then
		table.insert(lines, "|cffffd100Per hour: " .. coins(total * 3600 / elapsed) .. "|r")
	else
		table.insert(lines, "|cff999999Per hour: after a minute|r")
	end
	-- XP, and when the next level comes at this pace (not at the level cap: no XP to gain).
	if session.xp > 0 and xpSeen and xpSeen.max > 0 then
		local line = "XP: " .. number(session.xp)
		if rated then
			local perHour = session.xp * 3600 / elapsed
			line = line .. " · " .. number(perHour) .. "/h · level " .. (xpSeen.level + 1) .. " in "
				.. Encode.duration((xpSeen.max - xpSeen.cur) / perHour * 3600)
		end
		if (session.xpKills or 0) > 0 and session.killXp > 0 then
			line = line .. string.format(" (~%s kills)", number(math.ceil((xpSeen.max - xpSeen.cur) / (session.killXp / session.xpKills))))
		end
		table.insert(lines, line)
	end
	-- Bags: free slots, and when they run out at the rate they have been filling.
	local used = session.bagBase - session.bagFree
	local filling = GetTime() - session.bagBaseAt
	local bags = "Bags: " .. session.bagFree .. " free"
	if session.bagFree == 0 then
		bags = "|cffff5555Bags full|r"
	elseif used >= 1 and filling >= 120 then
		bags = bags .. " · full in ~" .. Encode.duration(session.bagFree / (used / filling))
	end
	table.insert(lines, bags)
	-- The most valuable items so far.
	local ranked = {}
	for id, n in pairs(session.items) do
		ranked[#ranked + 1] = { id = id, n = n, value = (worth(id) or 0) * n }
	end
	table.sort(ranked, function(a, b)
		return a.value > b.value
	end)
	for i = 1, math.min(TOP_ITEMS, #ranked) do
		local r = ranked[i]
		local name = (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(r.id)) or ("item " .. r.id)
		table.insert(lines, string.format("|cffaaaaaa%d× %s: %s|r", r.n, name, r.value > 0 and coins(r.value) or "no price"))
	end
	return table.concat(lines, "\n")
end

-- The session in words, for /gf session and the tests; and its kills, for the tests.
ns.sessionText = text
ns.sessionKills = function()
	return session and session.kills
end

local build
local startTicker -- set below; the HUD's OnShow starts it

-- The seconds the session has run: an ended one stops its clock at its last loot (or at Stop).
local function elapsed()
	return (idle() and session.last or GetTime()) - session.start
end

-- The session in figures, for the HUD and the hub's Session page: nil before any session.
function ns.sessionSummary()
	if not session then
		return nil
	end
	local secs = elapsed()
	local value, unpriced = itemsValue()
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
		ended = idle(), elapsed = secs, coin = session.coin, value = value, unpriced = unpriced,
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

local function refresh()
	if not hud or not hud:IsShown() then
		return
	end
	local Theme, UI, Views = ns.Theme, ns.UI, ns.Views
	if built ~= Theme.key then
		local open = hud.details:IsShown()
		hud:Hide()
		build()
		hud:Show()
		hud.details:SetShown(open)
	end
	local faint = Theme.escape(Theme.color.textFaint)
	if not session then
		hud.time:SetText("")
		hud.gold:SetText(faint .. "Loot or kill something to start a session.|r")
		hud.xp:SetText("")
		hud.kills:SetText("")
		hud.ding:SetText("")
		hud.details:Hide()
		return
	end
	local sum = ns.sessionSummary()
	local secs, value, unpriced, r = sum.elapsed, sum.value, sum.unpriced, sum.rates
	local dash = faint .. "—|r"
	hud.time:SetText((idle() and "ended " or "") .. Views.duration(math.max(60, secs)))
	hud.gold:SetText((r.rated and UI.layout.money(r.goldPerHour, "gold") or dash) .. faint .. " /h|r")
	hud.xp:SetText((r.rated and Views.short(r.xpPerHour) or dash) .. faint .. " XP/h|r")
	hud.kills:SetText((r.rated and Views.short(r.killsPerHour) or dash) .. faint .. " kills/h|r")
	hud.ding:SetText(not r.rated and "warming up…" or r.dingIn and ("ding in " .. Theme.escape(Theme.color.text) .. Views.duration(r.dingIn) .. "|r") or "")

	local d = hud.details
	if not d:IsShown() then
		return
	end
	d.values[1]:SetText(UI.layout.money(session.coin))
	d.values[2]:SetText(UI.layout.money(value) .. (unpriced > 0 and (faint .. string.format("  +%d unpriced", unpriced) .. "|r") or ""))
	d.values[3]:SetText(UI.layout.money(r.total) .. (r.rated and (faint .. "  · " .. "|r" .. UI.layout.money(r.goldPerHour, "gold") .. faint .. " an hour|r") or ""))
	d.values[4]:SetText(Views.short(sum.xp) .. (r.killsToLevel and (faint .. string.format("  · ~%d kills to level %d", r.killsToLevel, sum.nextLevel or 0) .. "|r") or ""))
	d.values[5]:SetText(sum.kills .. faint .. "  from kill XP and corpses, never the combat log|r")
	local bags = sum.bagFree == 0 and (Theme.escape(Theme.color.danger) .. "full|r") or (sum.bagFree .. " free")
	if sum.fullIn then
		bags = bags .. faint .. "  · full in ~" .. Views.duration(sum.fullIn) .. "|r"
	end
	d.values[6]:SetText(bags)
	-- The most valuable loot so far.
	local ranked = sum.ranked
	for i, row in ipairs(d.items) do
		local it = ranked[i]
		row:SetShown(it ~= nil)
		if it then
			local quality, _, _, _, name = itemInfo(it.id)
			local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id) or (GetItemIcon and GetItemIcon(it.id))
			row.icon:SetTexture(icon or 134400) -- the question mark
			row.name:SetText(Theme.escape(Theme.quality[quality or 1] or Theme.color.text) .. (name or ("item " .. it.id)) .. "|r" .. faint .. " ×" .. it.n .. "|r")
			row.value:SetText(it.value > 0 and UI.layout.money(it.value, "gold") or (faint .. "no price|r"))
		end
	end
	d.empty:SetShown(#ranked == 0)
end

-- A small movable window with a title, a close button and a text body; its position is kept in
-- [store]. Shared with the loot advisor.
function ns.makeWindow(name, title, store, point, onClose)
	local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(260, 120)
	if store.point then
		f:SetPoint(store.point[1], UIParent, store.point[2], store.point[3], store.point[4])
	else
		f:SetPoint(point[1], UIParent, point[1], point[2], point[3])
	end
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0, 0, 0, 0.85)
	end
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rel, x, y = self:GetPoint()
		store.point = { p, rel, x, y }
	end)

	local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 10, -9)
	heading:SetText(title)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		f:Hide()
		if onClose then
			onClose()
		end
	end)

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", 10, -28)
	text:SetWidth(240)
	text:SetJustifyH("LEFT")
	text:SetSpacing(2)
	return f, text
end

local W, H = 540, 34
local ROWS = { "Coin", "Loot, at what it sells for", "Total", "XP", "Kills", "Bags" }
local TOP_LOOT = 5

-- Draws the HUD in the look and accent the player set: a line of rates to drag anywhere; a click opens
-- the session under it. Drawn again when the look changes (refresh notices).
build = function()
	local Theme, UI = ns.Theme, ns.UI
	if ns.applyLook then
		ns.applyLook()
	end
	local s = settings()
	local old = hud
	-- One HUD per look and accent, reused when the look comes back (frames are never freed), placed
	-- where the player last left either.
	local cached = huds[Theme.key]
	if cached then
		if old and old ~= cached then
			old:Hide()
		end
		hud, built = cached, Theme.key
		hud:ClearAllPoints()
		if s.point then
			hud:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
		else
			hud:SetPoint("TOP", UIParent, "TOP", 0, -110)
		end
		return
	end
	hud = UI.Panel(UIParent, { color = Theme.color.surface, alpha = 0.94, borderColor = Theme.color.borderStrong })
	hud:SetSize(W, H)
	hud:SetFrameStrata("MEDIUM")
	hud:SetClampedToScreen(true)
	hud:SetMovable(true)
	if s.point then
		hud:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
	else
		hud:SetPoint("TOP", UIParent, "TOP", 0, -110)
	end
	hud:Hide()
	if old then
		old:Hide()
	end
	local web = Theme.skin.radius ~= nil
	-- The whole line is one button: click for the session, drag to move.
	local hit = CreateFrame("Button", nil, hud)
	hit:SetAllPoints()
	hit:RegisterForDrag("LeftButton")
	hit:SetScript("OnDragStart", function()
		hud:StartMoving()
	end)
	hit:SetScript("OnDragStop", function()
		hud:StopMovingOrSizing()
		local p, _, rel, x, y = hud:GetPoint()
		s.point = { p, rel, x, y }
	end)
	hit:SetScript("OnClick", function()
		if session then
			hud.details:SetShown(not hud.details:IsShown())
			refresh()
		end
	end)
	local mark = UI.solid(hit, "ARTWORK", Theme.color.accent)
	mark:SetSize(8, 8)
	mark:SetPoint("LEFT", 12, 0)
	if Theme.skin.decor and Theme.skin.decor.mark == "rune" then
		mark:SetTexture(Theme.media.rune)
		mark:SetBlendMode("ADD")
		mark:SetSize(16, 16)
		mark:SetPoint("LEFT", 8, 0)
	end
	local function field(x, width, size, tone, align)
		local t = UI.Text(hit, "", { size = size, tone = tone, medium = size == "md" and web, align = align })
		t:SetPoint("LEFT", x, 0)
		t:SetWidth(width)
		return t
	end
	hud.time = field(28, 64, "sm", "muted")
	hud.gold = field(94, 140, "md")
	hud.xp = field(236, 110, "md")
	hud.kills = field(348, 92, "md")
	hud.ding = UI.Text(hit, "", { size = "sm", tone = "muted", align = "RIGHT" })
	hud.ding:SetPoint("RIGHT", -12, 0)
	hud.ding:SetWidth(110)

	-- The session, under the line.
	local d = UI.Panel(hud, { color = Theme.color.surface, alpha = 0.96, borderColor = Theme.color.borderStrong })
	d:SetPoint("TOPLEFT", hud, "BOTTOMLEFT", 0, -6)
	d:SetWidth(W)
	d:SetHeight(48 + #ROWS * 20 + 26 + TOP_LOOT * 28 + 48)
	d:EnableMouse(true)
	d:Hide()
	local head = UI.Text(d, Theme.skin.titleCaps and "THIS SESSION" or "This session", { size = "lg", medium = true })
	head:SetPoint("TOPLEFT", 16, -14)
	d.values = {}
	for i, label in ipairs(ROWS) do
		local l = UI.Text(d, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", 16, -24 - i * 20)
		local v = UI.Text(d, "", { size = "sm" })
		v:SetPoint("TOPLEFT", 190, -24 - i * 20)
		v:SetWidth(W - 206)
		d.values[i] = v
	end
	local y = -24 - #ROWS * 20 - 34
	local lootHead = UI.Text(d, "LOOT", { size = "xs", medium = true, tone = "faint" })
	lootHead:SetPoint("TOPLEFT", 16, y)
	d.items = {}
	for i = 1, TOP_LOOT do
		local row = CreateFrame("Frame", nil, d)
		row:SetHeight(28)
		row:SetPoint("TOPLEFT", 12, y - 16 - (i - 1) * 28)
		row:SetPoint("RIGHT", d, "RIGHT", -12, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.name = UI.Text(row, "", { size = "sm" })
		row.name:SetPoint("LEFT", 34, 0)
		row.name:SetWidth(330)
		row.value = UI.Text(row, "", { size = "sm", align = "RIGHT" })
		row.value:SetPoint("RIGHT", -4, 0)
		row.value:SetWidth(140)
		d.items[i] = row
	end
	d.empty = UI.Text(d, "Nothing looted yet.", { size = "sm", tone = "faint" })
	d.empty:SetPoint("TOPLEFT", 16, y - 22)
	local stop = UI.Button(d, "Stop", function()
		if session and not idle() then
			session.stopped = true
			session.last = GetTime()
		end
		refresh()
	end, { kind = "ghost", width = 80, height = 26 })
	stop:SetPoint("BOTTOMLEFT", 12, 12)
	local reset = UI.Button(d, "New session", function()
		ns.commands.reset()
	end, { kind = "ghost", width = 120, height = 26 })
	reset:SetPoint("LEFT", stop, "RIGHT", 8, 0)
	local hide = UI.Button(d, "Hide the HUD", function()
		ns.commands.appraise()
	end, { width = 130, height = 26 })
	hide:SetPoint("BOTTOMRIGHT", -12, 12)
	hud.details = d
	built = Theme.key
	-- The clock runs whenever the HUD shows, however it came back (after combat, a loading screen, a new
	-- look): manual test run 001, the HUD stood still at "1m · warming up…" in a delve until a /reload.
	hud:HookScript("OnShow", function()
		if startTicker then
			startTicker()
		end
	end)
	huds[built] = hud
end

-- Whether the HUD stays out of the way now: in combat, when the player asked for that.
local function tucked()
	return settings().hideInCombat and InCombatLockdown and InCombatLockdown()
end

local function show()
	if not hud then
		build()
	end
	if tucked() then
		return
	end
	hud:Show()
	refresh()
	startTicker()
end

ns.on("PLAYER_REGEN_DISABLED", "appraiser", function()
	if hud and settings().hideInCombat then
		hud:Hide()
	end
end)
ns.on("PLAYER_REGEN_ENABLED", "appraiser", function()
	if hud and settings().shown and settings().hideInCombat and session then
		hud:Show()
		refresh()
		startTicker()
	end
end)

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
			local quest = startsQuest(id)
			if quest and not questDone(quest) and not startersAlerted[id] then
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

table.insert(ns.lootListeners, function(coin, taken, rows)
	current()
	-- Creature corpses looted for the first time: in the open fight, or a fight of their own.
	local corpses = {}
	for _, row in ipairs(rows or {}) do
		if row.first and row.guid then
			corpses[#corpses + 1] = row.guid
		end
	end
	if fight then
		for _, guid in ipairs(corpses) do
			table.insert(fight.corpses, guid)
		end
	elseif #corpses > 0 then
		session.kills = session.kills + ns.Views.creditKills(uncorpsed, 0, corpses, corpsesSeen, GetTime())
	end
	ns.safely("big drop", bigDrops, taken)
	session.coin = session.coin + coin
	for key, n in pairs(taken) do
		local id = Encode.itemId(key)
		if id then
			session.items[id] = (session.items[id] or 0) + n
		end
	end
	if settings().shown then
		show()
	end
	refresh()
end)

-- A /reload (or a quick relog) keeps the session: it is saved when the file is written, and picked
-- up on load for the same character unless it went idle meanwhile. Times are kept as ages, since the
-- client's clock (GetTime) and the server's differ.
ns.on("PLAYER_LOGOUT", "appraiser", function()
	local db, me = ns.db(), ns.me()
	if not session or idle() or not me then
		db.appraiserSession = nil
		return
	end
	local now = GetTime()
	db.appraiserSession = {
		character = me.ref,
		savedAt = GetServerTime(),
		age = now - session.start,
		sinceLoot = now - session.last,
		sinceBagBase = now - session.bagBaseAt,
		coin = session.coin,
		items = session.items,
		xp = session.xp,
		killXp = session.killXp,
		kills = session.kills,
		xpKills = session.xpKills,
		bagBase = session.bagBase,
	}
end)

local function restore()
	local db, me = ns.db(), ns.me()
	local saved = db.appraiserSession
	db.appraiserSession = nil
	if not saved or not me or saved.character ~= me.ref then
		return
	end
	local gap = math.max(0, GetServerTime() - (saved.savedAt or 0))
	if saved.sinceLoot + gap > IDLE_SECONDS then
		return
	end
	local now = GetTime()
	session = {
		start = now - saved.age - gap,
		last = now - saved.sinceLoot - gap,
		coin = saved.coin or 0,
		items = saved.items or {},
		xp = saved.xp or 0,
		killXp = saved.killXp or 0,
		kills = saved.kills or 0,
		xpKills = saved.xpKills or saved.kills or 0,
		bagBase = saved.bagBase or freeSlots(),
		bagBaseAt = now - (saved.sinceBagBase or 0) - gap,
		bagFree = freeSlots(),
	}
	if settings().shown then
		show()
	end
end

ns.on("PLAYER_ENTERING_WORLD", "appraiser", function(isInitialLogin, isReloadingUi)
	xpSeen = readXp()
	if isInitialLogin or isReloadingUi then
		restore()
	end
end)
ns.onLook("appraiser", function()
	refresh() -- a HUD that shows is drawn again in the look now set
end)
ns.on("PLAYER_XP_UPDATE", "appraiser", function()
	xpSeen = readXp()
	refresh()
end)
ns.on("BAG_UPDATE_DELAYED", "appraiser", function()
	bagsChanged()
	refresh()
end)

-- The clock and the item names (they load a moment after the loot) keep the text current: once a second
-- while the HUD shows, and no ticker at all while it is hidden (design 009, Performance budget).
local ticker
local function tick()
	if not hud or not hud:IsShown() then
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
		return
	end
	ns.safely("appraiser", refresh)
end
startTicker = function()
	if not ticker then
		ticker = C_Timer.NewTicker(1, tick)
	end
end

-- The HUD on or off as the player's choice (Settings → Modules): the saved switch, not whether the
-- frame shows now (it is not built before the first loot, and tucked away in combat when so set).
function ns.setHud(on)
	settings().shown = on
	if on then
		show()
	elseif hud then
		hud:Hide()
	end
end

ns.commands.appraise = function()
	-- Shown, or on but tucked away in combat: off. Hidden, or not built before the first loot: on.
	if hud and (hud:IsShown() or (settings().shown and tucked())) then
		ns.setHud(false)
		ns.say("session HUD hidden; /gf hud shows it again.")
	else
		ns.setHud(true)
	end
end

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

ns.commands.hud = ns.commands.appraise

-- "/gf session": the session in words, in the chat.
ns.commands.session = function()
	ns.say("\n" .. text())
end

ns.commands.reset = function()
	session = nil
	refresh()
	ns.say("farming session reset.")
end

-- Mob tooltips: what the characters have looted from the NPC, from the loot rows in the file -------------

local mobs -- npc ID -> { loots, coin, items = { [id] = { dropped, units } } }; built once, then kept up per loot

-- One loot row counted in: by the full build and by every loot after it.
local function countLoot(npc, coin, items)
	local m = mobs[npc] or { loots = 0, coin = 0, items = {} }
	mobs[npc] = m
	m.loots = m.loots + 1
	m.coin = m.coin + coin
	for item, n in pairs(items) do
		local d = m.items[item] or { dropped = 0, units = 0 }
		m.items[item] = d
		d.dropped = d.dropped + 1
		d.units = d.units + n
	end
end

-- New loot updates the counts in place, rather than reading every loot row again at the next
-- tooltip (two weeks of rows, in the tooltip's own frame).
local countingRows -- loot rows that came while the counts were being built, counted in after them
local function countRows(rows)
	for _, row in ipairs(rows or {}) do
		local npc = Encode.npcOf(row.src)
		if npc then
			local items = {}
			for key, n in pairs(row.items) do
				local id = Encode.itemId(key)
				if id then
					items[id] = (items[id] or 0) + n
				end
			end
			countLoot(npc, row.coin or 0, items)
		end
	end
end
table.insert(ns.lootListeners, function(_, _, rows)
	if mobs then
		countRows(rows)
	elseif countingRows then
		countingRows[#countingRows + 1] = rows
	end -- not started: the build reads everything, this loot included
end)

-- The counts from every saved loot row. Two weeks of heavy farming is tens of thousands of rows, more
-- than one frame may spend on: CHUNKS_A_FRAME chunks (500 rows each) a frame, from a list of the chunks
-- taken at the start (rows written meanwhile come through the listener above). Until it is done the
-- counts are nil: no tooltip line, and the Mobs page says it is counting.
-- A frame's share (ns.frameSpent), else ROWS_A_FRAME rows: chunks of 500 rows were 6 ms each on two
-- weeks of loot, too much for one frame.
local ROWS_A_FRAME = 250
local built = {} -- what to call once the counts are in
local function buildMobs()
	if countingRows then
		return
	end
	local db = ns.db()
	local columns = Encode.columns(db.fields and db.fields.loot)
	if not (columns.src and columns.coin and columns.items) then
		mobs = {}
		return
	end
	local chunks = {}
	for _, bucket in pairs(db.events) do
		for _, chunk in ipairs(bucket.loot or {}) do
			chunks[#chunks + 1] = chunk
		end
	end
	countingRows = {}
	local counted, i, pos = {}, 1, 1 -- the chunk and the place in it the next row starts
	local step
	-- A step that fails (a malformed row) drops the half-built counts: the next tooltip or page builds
	-- them again, rather than showing part of them for the session.
	local function failed(err)
		mobs, countingRows, built = nil, nil, {}
		ns.fail("mob counts", err)
	end
	local function guarded()
		local ok, err = pcall(step)
		if not ok then
			failed(err)
		end
	end
	step = function()
		local saved = mobs
		mobs = counted
		local started, rows = ns.frameStart(), 0
		while chunks[i] do
			local chunk = chunks[i]
			local stop = string.find(chunk, ";", pos, true)
			local row = string.sub(chunk, pos, (stop or 0) - 1)
			if stop then
				pos = stop + 1
			else
				i, pos = i + 1, 1
			end
			if row ~= "" then
				local values = { strsplit(",", row) }
				local id = Encode.npcOf(values[columns.src])
				if id then
					countLoot(id, tonumber(values[columns.coin]) or 0, Encode.parseItems(values[columns.items]))
				end
			end
			rows = rows + 1
			if ns.frameSpent(started, rows, ROWS_A_FRAME) then
				break
			end
		end
		if chunks[i] then
			mobs = saved
			C_Timer.After(0, guarded)
			return
		end
		for _, rows in ipairs(countingRows) do
			countRows(rows)
		end
		countingRows = nil
		for _, fn in ipairs(built) do
			ns.safely("mob counts", fn)
		end
		built = {}
	end
	guarded()
end
ns.on("PLAYER_ENTERING_WORLD", "mob counts", function()
	if not mobs then
		ns.after(20, "mob counts", buildMobs)
	end
end)

local function itemName(id)
	local row = ns.db().catalogue.items[id]
	return (row and string.match(row, "^([^,]+)")) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or ("item " .. id)
end

-- Every NPC looted, for the in-game pages: { [npc] = { loots, coin, items = { [id] = { dropped, units } } } }
-- and what one unit of an item is worth; nil while the counts are built, and `whenBuilt` is called once
-- they are.
function ns.mobStats(whenBuilt)
	if not mobs then
		if whenBuilt then
			built[#built + 1] = whenBuilt
		end
		buildMobs()
	end
	return mobs, worth
end

-- "looted 40× · ~7c a loot" and the three likeliest drops, for an NPC looted before.
local function mobLines(npc)
	if not mobs then
		buildMobs()
		if not mobs then
			return nil
		end
	end
	local m = mobs[npc]
	if not m then
		return nil
	end
	local value = m.coin
	local drops = {}
	for id, d in pairs(m.items) do
		value = value + (worth(id) or 0) * d.units
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
		local quest = startsQuest(id)
		if quest then
			local done = questDone(quest)
			starters[#starters + 1] = string.format("%s (%d%% of loots)%s", itemName(id), math.floor(d.dropped / m.loots * 100 + 0.5),
				done == false and " · not done" or done and " · done" or "")
		end
	end
	return string.format("looted %d× · ~%s a loot", m.loots, coins(value / m.loots)), #top > 0 and table.concat(top, " · ") or nil,
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

-- Tooltips ----------------------------------------------------------------------------------------------

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
