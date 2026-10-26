-- Gold Forever: the first-run card (design 009, Phase 2; the playground's First run idea). Once per new
-- install, never in combat (it waits for the fight to end): what Gold Forever records and shares, which
-- parts to start with (three presets over Settings → Modules), the look and accent colour, and the
-- companion app. Skippable;
-- "/gf welcome" shows it again. An install that already has characters in its save never sees it.

local _, ns = ...
ns = ns or {}

local FirstRun = {}
ns.FirstRun = FirstRun

-- The presets: which module switches each turns on (the rest off). Rare alerts stay as they are.
FirstRun.PRESETS = {
	{ id = "prices", label = "Prices only", blurb = "Everyone's prices in your tooltips; nothing else on screen.",
		on = { tooltip = true } },
	{ id = "trader", label = "Trader", blurb = "Prices, the auction house panel and the crafting strip.",
		on = { tooltip = true, auction = true, strip = true } },
	{ id = "everything", label = "Everything", blurb = "All of it, the session HUD and bag advice too. Switch any off later.",
		on = { tooltip = true, auction = true, strip = true, hud = true, advice = true } },
}

-- Applies a preset to the settings tables (each as ns.settings would return it). Pure: no game API.
function FirstRun.apply(id, s)
	local preset
	for _, p in ipairs(FirstRun.PRESETS) do
		if p.id == id then
			preset = p
		end
	end
	if not preset then
		return false
	end
	local on = preset.on
	s.prices.tooltip = on.tooltip == true
	s.auction.hidden = not on.auction
	s.crafting.strip = on.strip == true
	s.appraiser.shown = on.hud == true
	s.advisor.shown = on.advice == true
	return true
end

if not CreateFrame then
	return -- the tests load the rules above alone
end

local Theme, UI = ns.Theme, ns.UI

local function settingsTables()
	return {
		prices = ns.settings("prices"),
		auction = ns.settings("auction"),
		crafting = ns.settings("crafting"),
		appraiser = ns.settings("appraiser"),
		advisor = ns.settings("advisor"),
	}
end

local card, open
local STEPS = { "What it records", "Where to start", "Look and colour", "The companion" }
-- The preset picked, kept across the cards of each look (a new look draws the card anew).
local chosen = "trader"

local function build()
	ns.applyLook()
	local W, H = 560, 360
	local f = UI.Panel(UIParent, { window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	f:SetSize(W, H)
	f:SetPoint("CENTER", 0, 40)
	f:SetFrameStrata("DIALOG")
	f:EnableMouse(true)
	local title = UI.Text(f, Theme.skin.titleCaps and "WELCOME TO GOLD FOREVER" or "Welcome to Gold Forever", { size = "xl", medium = true })
	title:SetPoint("TOPLEFT", 24, -22)
	local steps = UI.Text(f, "", { size = "xs", tone = "faint" })
	steps:SetPoint("TOPLEFT", 24, -54)
	local rule = UI.solid(f, "BORDER", Theme.color.border)
	rule:SetPoint("TOPLEFT", 0, -76)
	rule:SetPoint("TOPRIGHT", 0, -76)
	rule:SetHeight(UI.pixel())

	local pages = {}
	-- 1: what it records and shares, in the site's words.
	local p1 = CreateFrame("Frame", nil, f)
	p1:SetPoint("TOPLEFT", 24, -92)
	p1:SetPoint("BOTTOMRIGHT", -24, 60)
	for i, t in ipairs({
		{ "Your characters", "level, gold, professions and where they are, for your own pages on the site" },
		{ "Your money and loot", "every coin in and out, and what you looted and sold" },
		{ "Auction scans", "prices when you open the auction house, never who sells" },
	}) do
		local l = UI.Text(p1, Theme.escape(Theme.color.accent) .. "•|r  " .. t[1] .. "\n" .. Theme.escape(Theme.color.textMuted) .. t[2] .. "|r", { size = "sm", wrap = true })
		l:SetPoint("TOPLEFT", 0, -(i - 1) * 44)
		l:SetPoint("RIGHT", p1, "RIGHT")
	end
	local shared = UI.Text(p1, "Every upload adds its auction scans, item details and loot counts to the shared prices, never your name. Your characters, gold and ledger stay private.", { size = "xs", tone = "faint", wrap = true })
	shared:SetPoint("TOPLEFT", 0, -140)
	shared:SetPoint("RIGHT", p1, "RIGHT")
	pages[1] = p1

	-- 2: a preset.
	local p2 = CreateFrame("Frame", nil, f)
	p2:SetAllPoints(p1)
	p2.rows = {}
	for i, preset in ipairs(FirstRun.PRESETS) do
		local row = CreateFrame("Button", nil, p2)
		row:SetHeight(58)
		row:SetPoint("TOPLEFT", 0, -(i - 1) * 64)
		row:SetPoint("RIGHT", p2, "RIGHT")
		row.bg, row.rim = UI.surface(row, Theme.color.surfaceRaised, 1, Theme.color.border, Theme.skin.radius and Theme.skin.radius.card or 0)
		row.label = UI.Text(row, preset.label, { size = "md", medium = true })
		row.label:SetPoint("TOPLEFT", 16, -11)
		row.blurb = UI.Text(row, preset.blurb, { size = "xs", tone = "faint" })
		row.blurb:SetPoint("TOPLEFT", row.label, "BOTTOMLEFT", 0, -5)
		row:SetScript("OnClick", function()
			chosen = preset.id
			p2:Paint()
		end)
		row.id = preset.id
		p2.rows[i] = row
	end
	function p2:Paint()
		for _, row in ipairs(self.rows) do
			local on = row.id == chosen
			row.rim:SetColor(on and Theme.color.accent or Theme.color.border)
			row.label:SetTextColor(Theme.rgb(on and Theme.color.accent or Theme.color.text))
		end
	end
	p2:Paint()
	pages[2] = p2

	-- 3: the look and accent, as Settings → General sets them. Each is seen at once: the card is drawn
	-- again in it, on this step.
	local p3 = CreateFrame("Frame", nil, f)
	p3:SetAllPoints(p1)
	local function redraw(change)
		f:Hide()
		change()
		open(3)
	end
	local lookLabel = UI.Text(p3, "Look", { size = "xs", medium = true, tone = "faint" })
	lookLabel:SetPoint("TOPLEFT")
	local function pickLook(name)
		if name ~= Theme.skin.name then
			redraw(function()
				ns.commands.look(name)
			end)
		end
	end
	f.pickLook = pickLook
	for i, name in ipairs(Theme.order) do
		local b = UI.Button(p3, Theme.skins[name].label, function()
			pickLook(name)
		end, { kind = name == Theme.skin.name and "primary" or nil, width = 110, height = 28 })
		b:SetPoint("TOPLEFT", (i - 1) * 118, -18)
	end
	local accentLabel = UI.Text(p3, "Accent colour", { size = "xs", medium = true, tone = "faint" })
	accentLabel:SetPoint("TOPLEFT", 0, -68)
	local current = ns.settings("window").accent
	local own = UI.Button(p3, "The look's own", function()
		if current then
			redraw(function()
				ns.commands.accent("")
			end)
		end
	end, { kind = current == nil and "primary" or nil, width = 130, height = 28 })
	own:SetPoint("TOPLEFT", 0, -86)
	for k, a in ipairs(Theme.accents) do
		local sw = UI.Swatch(p3, a.hex, function()
			if current ~= a.hex then
				redraw(function()
					ns.commands.accent(a.hex)
				end)
			end
		end)
		sw:SetPoint("LEFT", own, "RIGHT", 12 + (k - 1) * 30, 0)
		sw:SetOn(current == a.hex)
	end
	local later = UI.Text(p3, "Settings → General changes both any time, and /gf look too.", { size = "xs", tone = "faint" })
	later:SetPoint("TOPLEFT", 0, -132)
	pages[3] = p3

	-- 4: the companion.
	local p4 = CreateFrame("Frame", nil, f)
	p4:SetAllPoints(p1)
	local why = UI.Text(p4, "The addon cannot reach the internet. The free companion app brings everyone's prices into the game every hour and uploads your save when the game writes it. Copy the address and open it in your browser:", { size = "sm", tone = "muted", wrap = true })
	why:SetPoint("TOPLEFT")
	why:SetPoint("RIGHT", p4, "RIGHT")
	local url = UI.SearchBox(p4, "", nil)
	url:SetPoint("TOPLEFT", 0, -74)
	url:SetWidth(320)
	url:SetText("gold-forever.app/companion")
	url:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	local copy = UI.Text(p4, "Ctrl+C copies it. Without the companion, prices come from your own scans.", { size = "xs", tone = "faint" })
	copy:SetPoint("TOPLEFT", url, "BOTTOMLEFT", 0, -10)
	-- Said plainly (manual test run 001): a player installs it on their own computer, so they may read it first.
	local source = UI.Text(p4, Theme.escape(Theme.color.accent) .. "Open source.|r The companion's code is free to read (MIT licence) at github.com/gold-forever/companion: everything it reads and sends is there.", { size = "xs", tone = "muted", wrap = true })
	source:SetPoint("TOPLEFT", copy, "BOTTOMLEFT", 0, -14)
	source:SetPoint("RIGHT", p4, "RIGHT")
	pages[4] = p4

	local step = 1
	local skip, back, nextButton
	local function show(n)
		step = n
		for i, p in ipairs(pages) do
			p:SetShown(i == n)
		end
		local parts = {}
		for i, s in ipairs(STEPS) do
			parts[i] = i == n and (Theme.escape(Theme.color.accent) .. i .. ". " .. s .. "|r") or (i .. ". " .. s)
		end
		steps:SetText(table.concat(parts, "  ·  "))
		back:SetShown(n > 1)
		nextButton:SetLabel(n == #STEPS and "Done" or "Next")
	end
	local function finish(skipped)
		local s = ns.settings("firstRun")
		s.done = true
		if not skipped then
			local tables = settingsTables()
			FirstRun.apply(chosen, tables)
			-- The HUD on screen goes with its switch, as Settings → Modules does it.
			ns.setHud(tables.appraiser.shown)
		end
		f:Hide()
		ns.say(skipped and "first-run card skipped; everything stays as it was. /gf welcome shows it again."
			or "started with the " .. chosen .. " preset. Settings → Modules changes it any time.")
	end
	skip = UI.Button(f, "Skip", function()
		finish(true)
	end, { kind = "ghost", width = 80, height = 28 })
	skip:SetPoint("BOTTOMLEFT", 20, 18)
	nextButton = UI.Button(f, "Next", function()
		if step == #STEPS then
			finish(false)
		else
			show(step + 1)
		end
	end, { kind = "primary", width = 96, height = 28 })
	nextButton:SetPoint("BOTTOMRIGHT", -20, 18)
	back = UI.Button(f, "Back", function()
		show(step - 1)
	end, { width = 96, height = 28 })
	back:SetPoint("RIGHT", nextButton, "LEFT", -8, 0)
	f.show = show
	f.finish = finish
	f.choose = function(id)
		chosen = id
		p2:Paint()
	end
	show(1)
	return f
end

-- One card per look and accent, built the first time it is needed (frames are never freed): every
-- loading screen asks for the card until it is done or skipped, and it is not built again for that.
local cards = {}
-- `step`: the step to show (a new look reopens it on that step), else the first.
function open(step)
	if InCombatLockdown and InCombatLockdown() then
		ns.settings("firstRun").waiting = true
		return
	end
	ns.applyLook()
	local key = ns.Theme.key
	if card and card ~= cards[key] then
		card:Hide()
	end
	if card and card == cards[key] and card:IsShown() then
		return -- still open since the last loading screen
	end
	card = cards[key] or build()
	cards[key] = card
	card.show(step or 1)
	card:Show()
end

-- At load: a save with no characters yet is a new install, and is due the card.
ns.listen("ready", "first run", function()
	local s = ns.settings("firstRun")
	if s.due == nil then
		s.due = ns.SaveView.isNew()
	end
end)
ns.on("PLAYER_ENTERING_WORLD", "first run", function()
	local s = ns.settings("firstRun")
	if s.due and not s.done then
		C_Timer.After(2, function()
			ns.safely("first run", open)
		end)
	end
end)
ns.on("PLAYER_REGEN_ENABLED", "first run", function()
	local s = ns.settings("firstRun")
	if s.waiting and not s.done then
		s.waiting = nil
		open()
	end
end)

-- "/gf welcome": the card again.
ns.commands.welcome = function()
	ns.settings("firstRun").done = nil
	open()
end

-- For the smoke test.
FirstRun.card = function()
	return card
end
