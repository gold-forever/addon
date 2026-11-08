-- Gold Forever: the hub's Settings page: General, Modules, Tooltip and Looks.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local Kit = ns.HubKit
local settings, isRetail = Kit.settings, Kit.isRetail

-- A card of settings in two columns: a small-caps title over it, each row its label on the left of its
-- half and its control on the right. rows = { { side = 0|1, label, make = function(parent) -> control,
-- full = true for a control as wide as the half's right part } }. Returns the card.
local function settingsCard(page, title, y, rows)
	local label = UI.Text(page, string.upper(title), { size = "xs", medium = true, tone = "faint" })
	label:SetPoint("TOPLEFT", 0, y)
	local lines = 0
	for _, r in ipairs(rows) do
		lines = math.max(lines, (r.row or 0) + 1)
	end
	local card = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	card:SetPoint("TOPLEFT", 0, y - 18)
	card:SetPoint("RIGHT", page, "RIGHT")
	card:SetHeight(lines * 50 + 8)
	local split = UI.solid(card, "BORDER", Theme.color.border)
	split:SetPoint("TOP", 0, -10)
	split:SetSize(UI.pixel(), lines * 50 - 12)
	local half = CreateFrame("Frame", nil, card)
	half:SetPoint("TOPLEFT")
	half:SetPoint("BOTTOMRIGHT", card, "BOTTOM")
	for _, r in ipairs(rows) do
		local cell = CreateFrame("Frame", nil, card)
		cell:SetHeight(50)
		cell:SetPoint("TOPLEFT", card, "TOPLEFT", 0, -4 - (r.row or 0) * 50)
		cell:SetPoint("RIGHT", half, "RIGHT")
		if r.side == 1 then
			cell:ClearAllPoints()
			cell:SetHeight(50)
			cell:SetPoint("TOPLEFT", half, "TOPRIGHT", 0, -4 - (r.row or 0) * 50)
			cell:SetPoint("RIGHT", card, "RIGHT")
		end
		local text = UI.Text(cell, r.label, { size = "sm" })
		text:SetPoint("LEFT", 20, 0)
		local control = r.make(cell)
		if r.full then
			control:SetPoint("LEFT", cell, "CENTER", -6, 0)
			control:SetPoint("RIGHT", -20, 0)
		else
			control:SetPoint("RIGHT", -20, 0)
		end
		if r.hint then
			local hint = UI.Text(cell, r.hint, { size = "xs", tone = "faint" })
			hint:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 0, -3)
		end
	end
	return card
end

local function fillGeneral(page, prefs)
	local window, appraiser, rares, minimap = prefs.window, prefs.appraiser, prefs.rares, prefs.minimap
	-- General: only settings the addon has, each changed at once.
	local g = page.general
	local lookOptions = {}
	for _, name in ipairs(Theme.order) do
		lookOptions[#lookOptions + 1] = { value = name, label = Theme.skins[name].label }
	end
	-- The controls, each set again from the settings at every refresh (a command may have changed one).
	local c = {}
	local function bigDrop()
		return math.floor((appraiser.bigDrop or ns.BIG_DROP) / 10000)
	end
	settingsCard(g, "Display", 0, {
		{ side = 0, row = 0, label = "Look", full = true, make = function(cell)
			c.look = UI.Dropdown(cell, lookOptions, ns.currentLook(), function(v)
				ns.commands.look(v)
			end)
			return c.look
		end },
		{ side = 0, row = 1, label = "Accent colour", make = function(cell)
			local row = CreateFrame("Frame", nil, cell)
			row:SetSize(#Theme.accents * 30 - 6, 24)
			c.swatches = {}
			for k, a in ipairs(Theme.accents) do
				local sw = UI.Swatch(row, a.hex, function()
					ns.commands.accent(window.accent == a.hex and "" or a.hex)
				end)
				sw:SetPoint("LEFT", (k - 1) * 30, 0)
				sw:SetOn(window.accent == a.hex)
				c.swatches[k] = sw
			end
			return row
		end },
		{ side = 1, row = 0, label = "Minimap button", make = function(cell)
			c.minimap = UI.Switch(cell, not minimap.hidden, function(on)
				minimap.hidden = not on
				ns.refreshMinimap()
			end)
			return c.minimap
		end },
		{ side = 1, row = 1, label = "Window size", full = true, make = function(cell)
			c.scale = UI.Slider(cell, 70, 130, 5, math.floor((window.scale or 1) * 100 + 0.5), function(v)
				window.scale = v / 100
				local open = ns.hubWindow()
				if open then
					open:SetScale(window.scale)
				end
			end, function(v)
				return v .. "%"
			end, { onRelease = true })
			return c.scale
		end },
	})
	settingsCard(g, "Alerts", -146, {
		{ side = 0, row = 0, label = "Hide the HUD in combat", make = function(cell)
			c.hideInCombat = UI.Switch(cell, appraiser.hideInCombat, function(on)
				appraiser.hideInCombat = on
			end)
			return c.hideInCombat
		end },
		{ side = 0, row = 2, label = "Start and stop sessions by themselves", make = function(cell)
			c.autoSession = UI.Switch(cell, ns.Session.automatic(), function(on)
				ns.Session.setAutomatic(on)
			end)
			return c.autoSession
		end },
		{ side = 0, row = 1, label = "Offer a skull mark (/gf mark)", make = function(cell)
			c.mark = UI.Switch(cell, rares.mark, function(on)
				rares.mark = on
			end)
			if isRetail then
				c.mark:Disable()
				c.mark:SetAlpha(0.5)
			end
			return c.mark
		end },
		{ side = 1, row = 1, label = "Tell my party about rares", make = function(cell)
			c.party = UI.Switch(cell, rares.party == true, function(on)
				rares.party = on
			end)
			if isRetail then
				c.party:Disable()
				c.party:SetAlpha(0.5)
			end
			return c.party
		end },
		{ side = 1, row = 0, label = "Big drop alert", full = true, make = function(cell)
			c.bigDrop = UI.Slider(cell, 0, 50, 1, bigDrop(), function(v)
				appraiser.bigDrop = v * 10000
			end, function(v)
				return v == 0 and "rares" or (v .. "g")
			end)
			return c.bigDrop
		end },
	})
	function g:Refresh()
		c.look:Set(ns.currentLook())
		for k, a in ipairs(Theme.accents) do
			c.swatches[k]:SetOn(window.accent == a.hex)
		end
		c.minimap:Set(not minimap.hidden)
		c.scale:Set(math.floor((window.scale or 1) * 100 + 0.5))
		c.hideInCombat:Set(appraiser.hideInCombat)
		c.autoSession:Set(ns.Session.automatic())
		c.mark:Set(rares.mark)
		c.party:Set(rares.party == true)
		c.bigDrop:Set(bigDrop())
	end
end

local function fillModules(page, prefs)
	local appraiser, rares = prefs.appraiser, prefs.rares
	-- Modules: each part of the addon a player sees, on or off at once, no reload. The recorder is not
	-- one: what the save records stays the same whatever is switched off.
	local m = page.modules
	local auction = ns.settings("auction")
	local prices = ns.settings("prices")
	local crafting = ns.settings("crafting")
	local mail = ns.settings("mail")
	local MODULES = {
		{ icon = "timer", name = "Session HUD", blurb = "Gold, XP and kills an hour while you farm or level, and the session's loot.",
			on = function() return appraiser.shown end,
			set = function(on)
				ns.setHud(on)
			end },
		{ icon = "timer", name = "Session recap", blurb = "When a session ends, a small card with what it came to.",
			on = function() return appraiser.recap ~= false end,
			set = function(on) appraiser.recap = on end },
		{ icon = "gavel", name = "Auction house panel", blurb = "Scan, buy, sell and your auctions, beside the auction house.",
			on = function() return not auction.hidden end,
			set = function(on) auction.hidden = not on end },
		{ icon = "search", name = "Deals after a scan", blurb = "One chat line naming the list items listed at or under your price.",
			on = function() return auction.dealsAlert ~= false end,
			set = function(on) auction.dealsAlert = on end },
		{ icon = "coins", name = "Sale alert", blurb = "A coin sound and one chat line when one of your auctions sells.",
			on = function() return auction.soldAlert ~= false end,
			set = function(on) auction.soldAlert = on end },
		{ icon = "coins", name = "Best quest reward", blurb = "A gold coin on the quest reward worth the most to sell.",
			on = function() return prices.bestReward ~= false end,
			set = function(on) prices.bestReward = on end },
		{ icon = "coins", name = "Vendor resale", blurb = "At a merchant, a gold coin on items that sell for more on the auction house.",
			on = function() return prices.vendorResale ~= false end,
			set = function(on) prices.vendorResale = on end },
		{ icon = "backpack", name = "Cheapest in full bags", blurb = "With your bags full, a copper coin on the stack worth least, to make room.",
			on = function() return prices.bagMark ~= false end,
			set = function(on)
				prices.bagMark = on
				ns.BagMark.refresh()
			end },
		{ icon = "backpack", name = "Bag verdicts", blurb = "A small mark on each bag and bank item: post, vendor or disenchant.",
			on = function() return prices.bagVerdict ~= false end,
			set = function(on)
				prices.bagVerdict = on
				ns.BagVerdict.refresh()
			end },
		{ icon = "coins", name = "Loot roll value", blurb = "Under the item on a Need/Greed roll: its auction and vendor value.",
			on = function() return prices.rollValue ~= false end,
			set = function(on) prices.rollValue = on end },
		{ icon = "skull", name = "Best farm changed", blurb = "After new prices, one chat line when another mob is now your best loot.",
			on = function() return prices.bestFarm == true end,
			set = function(on) prices.bestFarm = on end },
		{ icon = "package", name = "Mail helper", blurb = "Beside the mailbox: open all the auction house's mail in one press.",
			on = function() return mail.helper ~= false end,
			set = function(on) mail.helper = on end },
		{ icon = "flask-conical", name = "Crafting strip", blurb = "Beside the profession window: a recipe's cost, sale, profit and what to buy.",
			on = function() return crafting.strip ~= false end,
			set = function(on) crafting.strip = on end },
		{ icon = "skull", name = "Rare alerts", blurb = isRetail and "Off on retail: its cities are full of markers the alert took for rares." or "A message and a sound when a rare is near.",
			on = function() return rares.announce end,
			set = function(on) rares.announce = on end, disabled = isRetail },
	}
	-- 38 a row (manual test run 001: at 52 the list ran past it). The page holds about ten rows and the note,
	-- so the list scrolls with the wheel, as the Guide does (Kit.scrollBody).
	local ROW = 38
	local NOTE = 40 -- the note under the list, wrapped to two lines, and its gap
	m.body = Kit.scrollBody(m, m:GetWidth(), #MODULES * ROW + 8 + NOTE)
	local list = UI.Panel(m.body, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	list:SetPoint("TOPLEFT")
	list:SetPoint("RIGHT", m.body, "RIGHT")
	list:SetHeight(#MODULES * ROW + 8)
	-- Each row painted from its setting: when drawn, and at every refresh (/gf hud may have changed one).
	m.rows = {}
	local function paint(row, on)
		row.icon:SetTone(on and "accent" or "faint")
		row.name:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
	end
	for i, mod in ipairs(MODULES) do
		local row = CreateFrame("Frame", nil, list)
		row:SetHeight(ROW)
		row:SetPoint("TOPLEFT", 0, -4 - (i - 1) * ROW)
		row:SetPoint("RIGHT", list, "RIGHT")
		if i > 1 then
			local rule = UI.solid(row, "BORDER", Theme.color.border)
			rule:SetPoint("TOPLEFT", 16, 0)
			rule:SetPoint("TOPRIGHT", -16, 0)
			rule:SetHeight(UI.pixel())
		end
		local icon = UI.Icon(row, mod.icon, 20, mod.on() and "accent" or "faint")
		icon:SetPoint("LEFT", 20, 0)
		local name = UI.Text(row, mod.name, { size = "sm", medium = true, tone = mod.on() and "text" or "muted" })
		name:SetPoint("TOPLEFT", 56, -5)
		local blurb = UI.Text(row, mod.blurb, { size = "xs", tone = "faint" })
		blurb:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
		blurb:SetPoint("RIGHT", row, "RIGHT", -80, 0)
		row.icon, row.name, row.mod = icon, name, mod
		row.switch = UI.Switch(row, mod.on(), function(on)
			mod.set(on)
			paint(row, on)
		end)
		row.switch:SetPoint("RIGHT", -20, 0)
		if mod.disabled then
			row.switch:Disable()
			row.switch:SetAlpha(0.5)
		end
		m.rows[i] = row
	end
	function m:Refresh()
		for _, row in ipairs(self.rows) do
			local on = row.mod.on() and true or false
			row.switch:Set(on)
			paint(row, on)
		end
	end
	local note = UI.Text(m.body, "The save records the same whatever is off: the site and the shared prices still get it.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
	note:SetPoint("RIGHT", m.body, "RIGHT")
end

-- Tooltip: each line the addon adds to a tooltip (Tooltips.lua) with a three-way picker, Off, With Shift or
-- Always, changed at once; a tooltip open with Shift held shows the Shift lines.
local MODES = { { key = "off", label = "Off" }, { key = "shift", label = "With Shift" }, { key = "always", label = "Always" } }
local function fillTooltip(page)
	local t = page.tooltip
	local modes = ns.settings("tooltip")
	local lines = ns.TOOLTIP_LINES
	local ROW = 44
	local NOTE = 40
	t.body = Kit.scrollBody(t, t:GetWidth(), #lines * ROW + 8 + NOTE)
	local list = UI.Panel(t.body, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	list:SetPoint("TOPLEFT")
	list:SetPoint("RIGHT", t.body, "RIGHT")
	list:SetHeight(#lines * ROW + 8)
	t.rows = {}
	for i, line in ipairs(lines) do
		local row = CreateFrame("Frame", nil, list)
		row:SetHeight(ROW)
		row:SetPoint("TOPLEFT", 0, -4 - (i - 1) * ROW)
		row:SetPoint("RIGHT", list, "RIGHT")
		if i > 1 then
			local rule = UI.solid(row, "BORDER", Theme.color.border)
			rule:SetPoint("TOPLEFT", 16, 0)
			rule:SetPoint("TOPRIGHT", -16, 0)
			rule:SetHeight(UI.pixel())
		end
		local name = UI.Text(row, line.name, { size = "sm", medium = true })
		name:SetPoint("TOPLEFT", 20, -7)
		local blurb = UI.Text(row, line.blurb, { size = "xs", tone = "faint" })
		blurb:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -2)
		row.picker = UI.TabBar(row, MODES, function(mode)
			modes[line.key] = mode
		end)
		row.picker:SetPoint("RIGHT", -20, 0)
		blurb:SetPoint("RIGHT", row.picker, "LEFT", -12, 0)
		row.picker:Select(modes[line.key])
		row.line = line
		t.rows[i] = row
	end
	function t:Refresh()
		for _, row in ipairs(self.rows) do
			row.picker:Select(modes[row.line.key])
		end
	end
	local note = UI.Text(t.body, "With Shift: the line shows while you hold Shift over the item or mob.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
	note:SetPoint("RIGHT", t.body, "RIGHT")
end

local function fillLooks(page)
	-- Looks: a card per look; a click switches every window to it, no reload.
	local l = page.looks
	for i, name in ipairs(Theme.order) do
		local skin = Theme.skins[name]
		local on = name == Theme.skin.name
		local card = CreateFrame("Button", nil, l)
		card:SetSize(212, 86)
		card:SetPoint("TOPLEFT", (i - 1) * 228, 0)
		UI.surface(card, Theme.color.surfaceRaised, 1, on and Theme.color.accent or Theme.color.border, Theme.skin.radius and Theme.skin.radius.card or 0)
		local icon = UI.Icon(card, on and "check" or "palette", 18, on and "accent" or "muted")
		icon:SetPoint("TOPLEFT", 16, -16)
		local label = UI.Text(card, skin.label, { size = "md", medium = true, tone = on and "accent" or "text" })
		label:SetPoint("LEFT", icon, "RIGHT", 10, 0)
		local line = UI.Text(card, on and "In use. Every window draws in it." or "Click to switch: no reload.", { size = "xs", tone = "faint", wrap = true })
		line:SetPoint("TOPLEFT", 16, -46)
		line:SetWidth(180)
		card:SetScript("OnClick", function()
			ns.commands.look(name)
		end)
	end
	local note = UI.Text(l, "The accent colour (General) goes over any look. Panels opened before a change keep their colours until /reload.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", 0, -106)
	note:SetPoint("RIGHT", l, "RIGHT")
end
-- Each tab drawn the first time it is chosen (General when the page opens).
local FILLS = { general = fillGeneral, modules = fillModules, tooltip = fillTooltip, looks = fillLooks }
local TABS = { { key = "general", label = "General" }, { key = "modules", label = "Modules" }, { key = "tooltip", label = "Tooltip" },
	{ key = "looks", label = "Looks" } }

local function buildSettings(page)
	local window = settings()
	local tabs = UI.TabBar(page, TABS, function(key)
		page.ensure(key)
		for _, tab in ipairs(TABS) do
			page[tab.key]:SetShown(key == tab.key)
		end
		if page[key].Refresh then
			page[key]:Refresh()
		end
	end, { variant = "underline" })
	tabs:SetPoint("TOPLEFT")
	tabs:SetPoint("TOPRIGHT")
	page.general = CreateFrame("Frame", nil, page)
	page.general:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -16)
	page.general:SetPoint("BOTTOMRIGHT")
	page.looks = CreateFrame("Frame", nil, page)
	page.looks:SetAllPoints(page.general)
	page.looks:Hide()
	page.modules = CreateFrame("Frame", nil, page)
	page.modules:SetAllPoints(page.general)
	page.modules:Hide()
	page.tooltip = CreateFrame("Frame", nil, page)
	page.tooltip:SetAllPoints(page.general)
	page.tooltip:Hide()

	local prefs = { window = window, appraiser = ns.settings("appraiser"), rares = ns.settings("rares"), minimap = ns.settings("minimap") }
	function page.ensure(key)
		local f = page[key]
		if f and not f.built then
			f.built = true
			FILLS[key](page, prefs)
		end
	end
	page.ensure("general")
	-- Opened again: every tab drawn shows the settings as they are now.
	function page:Refresh()
		for _, key in ipairs({ "general", "modules", "tooltip" }) do
			local f = self[key]
			if f.built and f.Refresh then
				f:Refresh()
			end
		end
	end
end

ns.hubPages.settings = buildSettings
