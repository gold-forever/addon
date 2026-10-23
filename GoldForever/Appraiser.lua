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

local function buildPrices()
	prices = {}
	cheapestPrices = {}
	local db, me = ns.db(), ns.me()
	pricedFrom = ns.scanVersion or 0
	pricedAt = nil
	if not me then
		return
	end
	local market = ns.market(string.lower(me.faction or "?"))
	local latest
	for _, scan in ipairs(db.scans) do
		if scan.kind == "full" and scan.market == market and (not latest or scan.t > latest.t) then
			latest = scan
		end
	end
	if not latest then
		return
	end
	pricedAt = latest.t
	local listings = {}
	for _, chunk in ipairs(latest.rows or {}) do
		for row in string.gmatch(chunk, "[^;]+") do
			local key, unit, qty = string.match(row, "^([^,]+),(%d+),(%d+)")
			local id = Encode.itemId(key)
			if id then
				listings[id] = listings[id] or {}
				table.insert(listings[id], { unit = tonumber(unit), qty = tonumber(qty) })
			end
		end
	end
	for id, l in pairs(listings) do
		prices[id] = Encode.marketValue(l)
		local low
		for _, x in ipairs(l) do
			low = low and math.min(low, x.unit) or x.unit
		end
		cheapestPrices[id] = low
	end
end

local function market(id)
	if not prices or pricedFrom ~= (ns.scanVersion or 0) then
		buildPrices()
	end
	return prices[id]
end

local function cheapest(id)
	market(id) -- builds the prices when needed
	return cheapestPrices[id]
end

-- The own scan's market value, cheapest unit and time, for the pool's fallback (Prices.lua).
function ns.ownPrice(id)
	local value = market(id)
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

-- What a vendor pays, from the catalogue (`sell` is its 7th column), else from the client.
local function vendor(id)
	local row = ns.db().catalogue.items[id]
	local sell = row and tonumber((select(7, strsplit(",", row))))
	if not sell and C_Item and C_Item.GetItemInfo then
		sell = (select(11, C_Item.GetItemInfo(id)))
	end
	return sell and sell > 0 and sell or nil
end

-- One unit's worth: the better of selling it on the auction house (after the cut) and to a vendor.
local function worth(id)
	local m = market(id)
	local net = m and math.floor(m * (1 - CUT))
	local v = vendor(id)
	if net and v then
		return math.max(net, v)
	end
	return net or v
end

-- Quality (0 poor … 4 epic), item level, class and vendor price, from the catalogue, else the client.
local function itemInfo(id)
	local row = ns.db().catalogue.items[id]
	if row then
		local name, quality, ilvl, class, _, _, sell = strsplit(",", row)
		return tonumber(quality), tonumber(ilvl), tonumber(class), tonumber(sell), name
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
	local tooltip = catalogue.tooltips[id]
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

local function coins(copper)
	if GetCoinTextureString then
		return GetCoinTextureString(math.floor(copper + 0.5))
	end
	return Encode.money(copper)
end

-- For the loot advisor (Advisor.lua): the same prices and valuation as here.
ns.price = {
	market = market, cheapest = cheapest, vendor = vendor, vendorBuy = vendorBuy, worth = worth, itemInfo = itemInfo,
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
			xp = 0, killXp = 0, kills = 0,
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

table.insert(ns.xpListeners, function(gained, kind)
	local s = current()
	s.xp = s.xp + gained
	if kind == "kill" or kind == "boss" then
		s.killXp = s.killXp + gained
		s.kills = s.kills + 1
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
		if session.kills > 0 then
			line = line .. string.format(" (~%s kills)", number(math.ceil((xpSeen.max - xpSeen.cur) / (session.killXp / session.kills))))
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

-- The session in words, for /gf session and the tests.
ns.sessionText = text

local build

-- The seconds the session has run: an ended one stops its clock at its last loot (or at Stop).
local function elapsed()
	return (idle() and session.last or GetTime()) - session.start
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
	local secs = elapsed()
	local value, unpriced = itemsValue()
	local toLevel = xpSeen and xpSeen.max > 0 and (xpSeen.max - xpSeen.cur) or 0
	local r = Views.sessionRates(session, secs, value, toLevel)
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
	d.values[4]:SetText(Views.short(session.xp) .. (r.killsToLevel and (faint .. string.format("  · ~%d kills to level %d", r.killsToLevel, (xpSeen.level or 0) + 1) .. "|r") or ""))
	d.values[5]:SetText(session.kills .. faint .. "  counted from XP and corpses, never the combat log|r")
	local used = session.bagBase - session.bagFree
	local filling = GetTime() - session.bagBaseAt
	local bags = session.bagFree == 0 and (Theme.escape(Theme.color.danger) .. "full|r") or (session.bagFree .. " free")
	if session.bagFree > 0 and used >= 1 and filling >= 120 then
		bags = bags .. faint .. "  · full in ~" .. Views.duration(session.bagFree / (used / filling)) .. "|r"
	end
	d.values[6]:SetText(bags)
	-- The most valuable loot so far.
	local ranked = {}
	for id, n in pairs(session.items) do
		ranked[#ranked + 1] = { id = id, n = n, value = (worth(id) or 0) * n }
	end
	table.sort(ranked, function(a, b)
		return a.value > b.value
	end)
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

table.insert(ns.lootListeners, function(coin, taken)
	current()
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
ns.on("PLAYER_XP_UPDATE", "appraiser", function()
	xpSeen = readXp()
	refresh()
end)
ns.on("BAG_UPDATE_DELAYED", "appraiser", function()
	bagsChanged()
	refresh()
end)

-- The clock and the item names (they load a moment after the loot) keep the text current.
ns.on("PLAYER_LOGIN", "appraiser", function()
	C_Timer.NewTicker(1, function()
		ns.safely("appraiser", refresh)
	end)
end)

ns.commands.appraise = function()
	local s = settings()
	if hud and hud:IsShown() then
		s.shown = false
		hud:Hide()
		ns.say("session HUD hidden; /gf hud shows it again.")
	else
		s.shown = true
		show()
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
table.insert(ns.lootListeners, function(_, _, rows)
	if not mobs then
		return -- not built yet: the first tooltip reads everything, this loot included
	end
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
end)

local function buildMobs()
	mobs = {}
	local db = ns.db()
	local columns = Encode.columns(db.fields and db.fields.loot)
	if not (columns.src and columns.coin and columns.items) then
		return
	end
	for _, bucket in pairs(db.events) do
		for _, chunk in ipairs(bucket.loot or {}) do
			for row in string.gmatch(chunk, "[^;]+") do
				local values = { strsplit(",", row) }
				local id = Encode.npcOf(values[columns.src])
				if id then
					countLoot(id, tonumber(values[columns.coin]) or 0, Encode.parseItems(values[columns.items]))
				end
			end
		end
	end
end

local function itemName(id)
	local row = ns.db().catalogue.items[id]
	return (row and string.match(row, "^([^,]+)")) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or ("item " .. id)
end

-- Every NPC looted, for the in-game pages: { [npc] = { loots, coin, items = { [id] = { dropped, units } } } }
-- and what one unit of an item is worth.
function ns.mobStats()
	if not mobs then
		buildMobs()
	end
	return mobs, worth
end

-- "looted 40× · ~7c a loot" and the three likeliest drops, for an NPC looted before.
local function mobLines(npc)
	if not mobs then
		buildMobs()
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
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		ns.safely("mob tooltip", function()
			if tooltip ~= GameTooltip or not data or not ns.db() then
				return
			end
			local guid = data.guid or (tooltip.GetUnit and select(2, tooltip:GetUnit()))
			local npc = Encode.npcId(guid)
			if not npc then
				return
			end
			local summary, drops, starters = mobLines(npc)
			if summary then
				tooltip:AddLine(ns.PREFIX .. " " .. summary, 1, 1, 1)
				if drops then
					tooltip:AddLine(drops, 0.7, 0.7, 0.7, true)
				end
				if starters then
					tooltip:AddLine(starters, 1, 0.82, 0, true)
				end
			end
		end)
	end)
end

-- Tooltips ----------------------------------------------------------------------------------------------

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("appraiser tooltip", function()
			if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not data.id or not ns.db() then
				return
			end
			local m, v = market(data.id), vendor(data.id)
			if not m and not v and not disenchantWorth(data.id) then
				return
			end
			local parts = {}
			if m then
				parts[#parts + 1] = "AH " .. coins(m) .. " (" .. coins(math.floor(m * (1 - CUT))) .. " after cut)"
			end
			if v then
				parts[#parts + 1] = "vendor " .. coins(v)
			end
			if #parts > 0 then
				tooltip:AddLine(ns.PREFIX .. " " .. table.concat(parts, " · "), 1, 1, 1)
			end
			local de, skill = disenchantWorth(data.id)
			if de and de > 0 then
				local sale = worth(data.id) or 0
				local verdict = de > sale and " · |cff56c98fbetter than selling|r" or ""
				local short = enchanting() < skill and string.format(" |cff999999(needs Enchanting %d)|r", skill) or ""
				tooltip:AddLine("Disenchant ≈ " .. coins(de) .. verdict .. short, 1, 1, 1)
			end
		end)
	end)
end
