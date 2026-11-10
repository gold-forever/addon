-- Gold Forever: the crafting strip (design 009, Crafting module, Phase 1; the playground's Crafting strip
-- idea). Docked beside the profession window, never inside it: for the recipe selected there, what its
-- reagents cost (each at the cheaper of the auction house and a vendor; unknown stays unknown), what the
-- item sells for after the auction house's cut, the profit and the margin, and what is still to buy.
-- Crafting itself stays the profession window's own button.
--
-- The selected recipe comes from the profession window's own event (EventRegistry,
-- ProfessionsRecipeListMixin.Event.OnRecipeSelected) where the client has it, else from the schematic
-- form it shows. ASSUMED for Forever: its profession window is ProfessionsFrame as on retail.

local _, ns = ...
local L = ns.L
local Theme, UI = ns.Theme, ns.UI

local W, LINES = 280, 6
-- The To buy lines: a name beside its price, or across the strip without one; each wraps (addon#65).
local NAME_W, FULL_W, LINE_GAP = W - 110, W - 28, 4
local TOP_OF_LINES = 80 + 4 * 20 + 26

local function settings()
	return ns.settings("crafting")
end

local recipeID

local function host()
	return ProfessionsFrame or TradeSkillFrame
end

local function build()
	local f = UI.Dialog({ window = true, width = W, height = 120 + 4 * 20 + LINES * 18 + 30, strata = "HIGH", icon = "flask-conical", title = "Gold Forever",
		titleTone = "muted" })
	f:Hide()
	f.title = UI.Text(f, "", { size = "md", medium = true, wrap = true })
	f.title:SetPoint("TOPLEFT", 14, -40)
	f.title:SetWidth(W - 28)
	f.rows = {}
	for i, label in ipairs({ L["Reagents"], L["Sells for"], L["Profit"], L["Margin"] }) do
		local l = UI.Text(f, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", 14, -80 - (i - 1) * 20)
		local v = UI.Text(f, "", { size = "sm", align = "RIGHT", medium = i == 3 })
		v:SetPoint("TOPRIGHT", -14, -80 - (i - 1) * 20)
		v:SetWidth(W - 120)
		f.rows[i] = v
	end
	local lh = UI.Text(f, L["TO BUY"], { size = "xs", medium = true, tone = "faint" })
	lh:SetPoint("TOPLEFT", 14, -80 - 4 * 20 - 10)
	f.lines = {}
	for i = 1, LINES do
		local l = UI.Text(f, "", { size = "xs", wrap = true })
		if i == 1 then
			l:SetPoint("TOPLEFT", 14, -TOP_OF_LINES)
		else
			l:SetPoint("TOPLEFT", f.lines[i - 1].name, "BOTTOMLEFT", 0, -LINE_GAP)
		end
		l:SetWidth(NAME_W)
		local v = UI.Text(f, "", { size = "xs", align = "RIGHT", tone = "muted" })
		v:SetPoint("TOP", l, "TOP")
		v:SetPoint("RIGHT", f, "RIGHT", -14, 0)
		v:SetWidth(96)
		f.lines[i] = { name = l, value = v }
	end
	-- Queue one of the recipe in view; the Shop's "Craft queue" list buys what the queue needs.
	f.queue = UI.Button(f, L["Queue 1"], function()
		if recipeID and ns.queueAdd then
			ns.queueAdd(recipeID, 1)
			f.note:SetText(L["Queued. The Buy tab's \"Craft queue\" list buys what is missing."])
		end
	end, { kind = "ghost", width = 70, height = 22 })
	f.queue:SetPoint("TOPRIGHT", -12, -12)
	f.note = UI.Text(f, "", { size = "xs", tone = "faint", wrap = true })
	f.note:SetPoint("BOTTOMLEFT", 14, 12)
	f.note:SetWidth(W - 28)
	return f
end

-- The space between the profession window's right edge and the strip: Blizzard's buttons stick out past
-- that edge, and a narrower gap covered them (addon#93). Which frame they are is not known here, so the
-- gap is fixed; the owner checks it in game.
local GAP = 46

-- Beside the profession window.
local function dock(f)
	f:ClearAllPoints()
	f:SetPoint("TOPLEFT", host(), "TOPRIGHT", GAP, 0)
end

-- One To buy line: its name, and its price if it has one (else the name takes the strip's width).
local function setLine(l, name, value)
	l.name:SetWidth(value ~= "" and NAME_W or FULL_W)
	l.name:SetText(name)
	l.value:SetText(value)
end

-- The strip as tall as its wrapped lines and note.
local function fit(strip)
	local h = TOP_OF_LINES
	for _, l in ipairs(strip.lines) do
		if l.name:GetText() ~= "" then
			h = h + (l.name:GetStringHeight() or 0) + LINE_GAP
		end
	end
	strip:SetHeight(h + 12 + (strip.note:GetStringHeight() or 0) + 12)
end

-- A reagent's name; a slot of the player's choice as "any of", the cheapest choice first.
local function reagentName(line)
	if not line.options then
		return ns.itemName(line.id)
	end
	local names = { ns.itemName(line.id) }
	for _, id in ipairs(line.options) do
		if id ~= line.id then
			names[#names + 1] = ns.itemName(id)
		end
	end
	return string.format(L["any of: %s"], table.concat(names, ", "))
end

-- One strip per look and accent.
local strips = UI.perLook(build, dock)

-- Sells for, Profit and Margin. A random result (or one that can fail) has none of them, and says so.
local function saleRows(strip, q, gear, money, faint, dash)
	if q.random then
		strip.rows[2]:SetText(faint .. L["random, can fail"] .. "|r")
		strip.rows[3]:SetText("")
		strip.rows[4]:SetText("")
		return
	end
	strip.rows[2]:SetText(q.revenue and (money(q.revenue) .. faint .. (gear and L[" any quality"] or L[" after the cut"]) .. "|r") or dash)
	if q.profit and gear then
		-- One price for every quality and item level: grey, not to be trusted.
		strip.rows[3]:SetText(faint .. (q.profit >= 0 and "+" or "-") .. UI.layout.plain(money(math.abs(q.profit))) .. "|r")
	elseif q.profit then
		strip.rows[3]:SetText(q.profit >= 0 and (Theme.escape(Theme.color.success) .. "+|r" .. money(q.profit)) or (Theme.escape(Theme.color.danger) .. "-|r" .. money(-q.profit)))
	else
		strip.rows[3]:SetText(dash)
	end
	local margin = ns.Crafting.margin(q)
	strip.rows[4]:SetText(margin and ((gear and faint or "") .. margin .. "%" .. (gear and "|r" or "")) or dash)
end

local function refresh()
	if not strips.frame or not strips.frame:IsShown() then
		return
	end
	strips:redraw()
	local strip = strips.frame
	local money = function(c)
		return UI.layout.money(c, "gold")
	end
	local faint = Theme.escape(Theme.color.textFaint)
	local dash = faint .. L["unknown"] .. "|r"
	local q = recipeID and ns.quoteRecipe(recipeID)
	if not q then
		strip.title:SetText(faint .. (recipeID and L["This recipe makes no item, or the addon has not read it yet."] or L["Choose a recipe."]) .. "|r")
		for _, v in ipairs(strip.rows) do
			v:SetText("")
		end
		for _, l in ipairs(strip.lines) do
			setLine(l, "", "")
		end
		strip.note:SetText("")
		fit(strip)
		return
	end
	local r = q.recipe
	local quality = ns.price.itemInfo(r.output) or 1
	-- A random result's count is what the client gives as its reagents', not what it makes (addon#65).
	local count = not q.random and r.yield ~= 1 and (r.yield .. "x ") or ""
	strip.title:SetText(Theme.escape(Theme.quality[quality] or Theme.color.text) .. count .. ns.itemName(r.output) .. "|r")
	strip.rows[1]:SetText(q.spend and money(q.spend) or dash)
	local gear = not q.random and ns.isGear(r.output)
	saleRows(strip, q, gear, money, faint, dash)
	local toBuy = {}
	for _, line in ipairs(q.lines) do
		if line.toBuy > 0 then
			toBuy[#toBuy + 1] = line
		end
	end
	-- More than the lines hold: the last says how many more, not cut off silently.
	local shown = #toBuy > LINES and LINES - 1 or #toBuy
	for i = 1, shown do
		local line = toBuy[i]
		setLine(strip.lines[i], line.toBuy .. "x " .. reagentName(line),
			line.unit and (money(line.unit) .. faint .. (line.from == "vendor" and L[" vendor"] or L[" AH"]) .. "|r") or dash)
	end
	if shown < #toBuy then
		shown = shown + 1
		setLine(strip.lines[shown], faint .. string.format(L["+%d more"], #toBuy - shown + 1) .. "|r", "")
	end
	for i = shown + 1, LINES do
		setLine(strip.lines[i], i == 1 and (faint .. L["Nothing: your bags and bank hold it all."] .. "|r") or "", "")
	end
	strip.note:SetText(q.random and L["Its result is random, and it can fail: no sale price or profit to show."]
		or gear and L["Gear has one price for every quality and item level: check the auction house for the quality you craft."]
		or L["Reagents at the cheaper of the auction house and a vendor; what you hold counts at the lower of buying and selling it."])
	fit(strip)
end

-- The recipe the profession window shows now, read from its schematic form where it has one.
local function shownRecipe()
	local page = ProfessionsFrame and ProfessionsFrame.CraftingPage
	local form = type(page) == "table" and page.SchematicForm
	local info = type(form) == "table" and type(form.GetRecipeInfo) == "function" and form:GetRecipeInfo()
	return type(info) == "table" and info.recipeID or nil
end

local function show()
	if settings().strip == false or not host() then
		return
	end
	local strip = strips.frame or strips:get()
	dock(strip)
	strip:Show()
	-- The recipe this window shows first: one kept from the last window would name another profession's
	-- (review B-27).
	recipeID = shownRecipe() or recipeID
	refresh()
end

local function hide()
	recipeID = nil
	if strips.frame then
		strips.frame:Hide()
	end
end

ns.on("TRADE_SKILL_SHOW", "crafting strip", function()
	C_Timer.After(0, function()
		ns.safely("crafting strip", show)
	end)
end)
ns.on("TRADE_SKILL_CLOSE", "crafting strip", hide)
strips:onLook("crafting strip", refresh)
ns.on("BAG_UPDATE_DELAYED", "crafting strip", refresh)

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, info)
		recipeID = info and info.recipeID or recipeID
		ns.safely("crafting strip", refresh)
	end, ns)
end

-- For the smoke test: choose a recipe as the profession window would, or open as with the window.
ns.CraftingStrip = {
	select = function(id)
		recipeID = id
		refresh()
	end,
	open = function()
		show()
	end,
	-- The strip itself, to read where it docks.
	frame = function()
		return strips.frame
	end,
	shown = function()
		local strip = strips.frame
		return strip and strip:IsShown() and strip.title:GetText()
	end,
	line = function(i)
		return strips.frame.lines[i].name:GetText()
	end,
	row = function(i)
		return strips.frame.rows[i]:GetText()
	end,
}
