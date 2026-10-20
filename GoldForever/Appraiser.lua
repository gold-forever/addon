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

-- Prices --------------------------------------------------------------------------------------------

local prices -- item ID -> market value, from the latest full scan of the character's market
local pricedFrom -- scans known when prices were built; a new scan rebuilds them

local function buildPrices()
	prices = {}
	local db, me = ns.db(), ns.me()
	pricedFrom = #db.scans
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
	local listings = {}
	for _, chunk in ipairs(latest.rows or {}) do
		for row in string.gmatch(chunk, "[^;]+") do
			local key, unit, qty = string.match(row, "^([^,]+),(%d+),(%d+)")
			local id = key and tonumber(string.match(key, "^(%d+)"))
			if id then
				listings[id] = listings[id] or {}
				table.insert(listings[id], { unit = tonumber(unit), qty = tonumber(qty) })
			end
		end
	end
	for id, l in pairs(listings) do
		prices[id] = Encode.marketValue(l)
	end
end

local function market(id)
	if not prices or pricedFrom ~= #ns.db().scans then
		buildPrices()
	end
	return prices[id]
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

local function coins(copper)
	if GetCoinTextureString then
		return GetCoinTextureString(math.floor(copper + 0.5))
	end
	return Encode.money(copper)
end

-- Session ---------------------------------------------------------------------------------------------

-- { start, last, coin, items = { [id] = count }, xp, killXp, kills, bagBase, bagBaseAt, bagFree }
local session

local function idle()
	return not session or GetTime() - session.last > IDLE_SECONDS
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

-- XP since the last reading, across level-ups; quest XP counts toward XP per hour, not per kill.
local xpSeen -- { cur, max, level }
local questAt

local function readXp()
	return { cur = UnitXP("player"), max = UnitXPMax("player"), level = UnitLevel("player") }
end

local function xpChanged()
	local now = readXp()
	local before = xpSeen
	xpSeen = now
	if not before or now.max == 0 then
		return
	end
	local gained = Encode.xpGained(before.cur, before.max, now.cur, now.level > before.level)
	if gained <= 0 then
		return
	end
	local s = current()
	s.xp = s.xp + gained
	if not (questAt and GetTime() - questAt < 3) then
		s.killXp = s.killXp + gained
		s.kills = s.kills + 1
	end
end

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

-- Window ----------------------------------------------------------------------------------------------

local frame, body

local function settings()
	local s = ns.db().settings
	s.appraiser = s.appraiser or { shown = true }
	return s.appraiser
end

local function text()
	if not session then
		return "Loot something to start a session."
	end
	local elapsed = GetTime() - session.start
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

local function refresh()
	if frame and frame:IsShown() then
		body:SetText(text())
		frame:SetHeight(body:GetStringHeight() + 40)
	end
end

local function build()
	frame = CreateFrame("Frame", "GoldForeverAppraiser", UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	frame:SetSize(260, 120)
	local point = settings().point
	if point then
		frame:SetPoint(point[1], UIParent, point[2], point[3], point[4])
	else
		frame:SetPoint("RIGHT", UIParent, "RIGHT", -60, 120)
	end
	if frame.SetBackdrop then
		frame:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		frame:SetBackdropColor(0, 0, 0, 0.85)
	end
	frame:SetClampedToScreen(true)
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rel, x, y = self:GetPoint()
		settings().point = { p, rel, x, y }
	end)

	local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	title:SetPoint("TOPLEFT", 10, -9)
	title:SetText("Gold Forever · loot")

	local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		settings().shown = false
		frame:Hide()
		print("|cffe0ac45Gold Forever|r: loot window hidden; /gf appraise shows it again.")
	end)

	body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	body:SetPoint("TOPLEFT", 10, -28)
	body:SetWidth(240)
	body:SetJustifyH("LEFT")
	body:SetSpacing(2)
end

local function show()
	if not frame then
		build()
	end
	frame:Show()
	refresh()
end

table.insert(ns.lootListeners, function(coin, taken)
	current()
	session.coin = session.coin + coin
	for key, n in pairs(taken) do
		local id = tonumber(string.match(tostring(key), "^(%d+)"))
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
	xpChanged()
	refresh()
end)
ns.on("QUEST_TURNED_IN", "appraiser", function()
	questAt = GetTime()
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
	if frame and frame:IsShown() then
		s.shown = false
		frame:Hide()
	else
		s.shown = true
		show()
	end
end

ns.commands.reset = function()
	session = nil
	refresh()
	print("|cffe0ac45Gold Forever|r: farming session reset.")
end

-- Mob tooltips: what the characters have looted from the NPC, from the loot rows in the file -------------

local mobs -- npc ID -> { loots, coin, items = { [id] = { dropped, units } } }; rebuilt after new loot
table.insert(ns.lootListeners, function()
	mobs = nil
end)

local function buildMobs()
	mobs = {}
	local db = ns.db()
	local columns = {}
	local i = 0
	for name in string.gmatch((db.fields and db.fields.loot) or "", "[^,]+") do
		i = i + 1
		columns[name] = i
	end
	if not (columns.src and columns.coin and columns.items) then
		return
	end
	for _, bucket in pairs(db.events) do
		for _, chunk in ipairs(bucket.loot or {}) do
			for row in string.gmatch(chunk, "[^;]+") do
				local values = { strsplit(",", row) }
				local id = tonumber(string.match(values[columns.src] or "", "^n(%d+)$"))
				if id then
					local m = mobs[id] or { loots = 0, coin = 0, items = {} }
					mobs[id] = m
					m.loots = m.loots + 1
					m.coin = m.coin + (tonumber(values[columns.coin]) or 0)
					for key, n in string.gmatch(values[columns.items] or "", "([^+*]+)%*(%d+)") do
						local item = tonumber(string.match(key, "^(%d+)"))
						if item then
							local d = m.items[item] or { dropped = 0, units = 0 }
							m.items[item] = d
							d.dropped = d.dropped + 1
							d.units = d.units + tonumber(n)
						end
					end
				end
			end
		end
	end
end

local function itemName(id)
	local row = ns.db().catalogue.items[id]
	return (row and string.match(row, "^([^,]+)")) or (C_Item and C_Item.GetItemInfo and C_Item.GetItemInfo(id)) or ("item " .. id)
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
	return string.format("looted %d× · ~%s a loot", m.loots, coins(value / m.loots)), #top > 0 and table.concat(top, " · ") or nil
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip, data)
		ns.safely("mob tooltip", function()
			if tooltip ~= GameTooltip or not data or not ns.db() then
				return
			end
			local guid = data.guid or (tooltip.GetUnit and select(2, tooltip:GetUnit()))
			local npc = tonumber(string.match(Encode.source(guid) or "", "^n(%d+)$"))
			if not npc then
				return
			end
			local summary, drops = mobLines(npc)
			if summary then
				tooltip:AddLine("|cffe0ac45Gold Forever|r " .. summary, 1, 1, 1)
				if drops then
					tooltip:AddLine(drops, 0.7, 0.7, 0.7, true)
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
			if not m and not v then
				return
			end
			local parts = {}
			if m then
				parts[#parts + 1] = "AH " .. coins(m) .. " (" .. coins(math.floor(m * (1 - CUT))) .. " after cut)"
			end
			if v then
				parts[#parts + 1] = "vendor " .. coins(v)
			end
			tooltip:AddLine("|cffe0ac45Gold Forever|r " .. table.concat(parts, " · "), 1, 1, 1)
		end)
	end)
end
