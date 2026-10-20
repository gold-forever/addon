-- Gold Forever: a loot appraiser. While farming, a small window adds up what the loot is worth, in
-- coin and items, and the gold per hour; every item's tooltip gets its value. Prices come from the
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

local session -- { start, last, coin, items = { [id] = count } }

local function idle()
	return not session or GetTime() - session.last > IDLE_SECONDS
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
	if elapsed >= MIN_RATE_SECONDS then
		table.insert(lines, "|cffffd100Per hour: " .. coins(total * 3600 / elapsed) .. "|r")
	else
		table.insert(lines, "|cff999999Per hour: after a minute|r")
	end
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
	local now = GetTime()
	if idle() then
		session = { start = now, last = now, coin = 0, items = {} }
	end
	session.last = now
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
