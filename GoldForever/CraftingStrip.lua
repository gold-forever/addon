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
local Theme, UI = ns.Theme, ns.UI

local W, LINES = 280, 6

local function settings()
	return ns.settings("crafting", { strip = true })
end

local strip, built
local strips = {} -- Theme.key -> strip
local recipeID

local function host()
	return ProfessionsFrame or TradeSkillFrame
end

local function name(id)
	local _, _, _, _, n = ns.price.itemInfo(id)
	return n or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
end

local function build()
	if ns.applyLook then
		ns.applyLook()
	end
	local old = strip
	-- One strip per look and accent, reused (frames are never freed).
	local cached = strips[Theme.key]
	if cached then
		if old and old ~= cached then
			old:Hide()
		end
		strip, built = cached, Theme.key
		return
	end
	local f = UI.Panel(UIParent, { window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	f:SetWidth(W)
	f:SetHeight(120 + 4 * 20 + LINES * 18 + 30)
	f:SetFrameStrata("HIGH")
	f:Hide()
	if old then
		old:Hide()
	end
	local mark = UI.Icon(f, "flask-conical", 16, "accent")
	mark:SetPoint("TOPLEFT", 14, -14)
	local head = UI.Text(f, Theme.skin.titleCaps and "GOLD FOREVER" or "Gold Forever", { size = "sm", medium = true, tone = "muted" })
	head:SetPoint("LEFT", mark, "RIGHT", 6, 0)
	f.title = UI.Text(f, "", { size = "md", medium = true, wrap = true })
	f.title:SetPoint("TOPLEFT", 14, -40)
	f.title:SetWidth(W - 28)
	f.rows = {}
	for i, label in ipairs({ "Reagents", "Sells for", "Profit", "Margin" }) do
		local l = UI.Text(f, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", 14, -80 - (i - 1) * 20)
		local v = UI.Text(f, "", { size = "sm", align = "RIGHT", medium = i == 3 })
		v:SetPoint("TOPRIGHT", -14, -80 - (i - 1) * 20)
		v:SetWidth(W - 120)
		f.rows[i] = v
	end
	local lh = UI.Text(f, "TO BUY", { size = "xs", medium = true, tone = "faint" })
	lh:SetPoint("TOPLEFT", 14, -80 - 4 * 20 - 10)
	f.lines = {}
	for i = 1, LINES do
		local l = UI.Text(f, "", { size = "xs" })
		l:SetPoint("TOPLEFT", 14, -80 - 4 * 20 - 26 - (i - 1) * 18)
		l:SetWidth(W - 110)
		local v = UI.Text(f, "", { size = "xs", align = "RIGHT", tone = "muted" })
		v:SetPoint("TOPRIGHT", -14, -80 - 4 * 20 - 26 - (i - 1) * 18)
		v:SetWidth(96)
		f.lines[i] = { name = l, value = v }
	end
	-- Queue one of the recipe in view; the Shop's "Craft queue" list buys what the queue needs.
	f.queue = UI.Button(f, "Queue 1", function()
		if recipeID and ns.queueAdd then
			ns.queueAdd(recipeID, 1)
			f.note:SetText("Queued. The Shop's \"Craft queue\" list buys what is missing.")
		end
	end, { kind = "ghost", width = 70, height = 22 })
	f.queue:SetPoint("TOPRIGHT", -12, -12)
	f.note = UI.Text(f, "", { size = "xs", tone = "faint", wrap = true })
	f.note:SetPoint("BOTTOMLEFT", 14, 12)
	f.note:SetWidth(W - 28)
	strip = f
	built = Theme.key
	strips[built] = f
end

local function refresh()
	if not strip or not strip:IsShown() then
		return
	end
	if built ~= Theme.key then
		strip:Hide()
		build()
		strip:SetPoint("TOPLEFT", host(), "TOPRIGHT", 6, 0)
		strip:Show()
	end
	local money = function(c)
		return UI.layout.money(c, "gold")
	end
	local faint = Theme.escape(Theme.color.textFaint)
	local dash = faint .. "unknown|r"
	local q = recipeID and ns.quoteRecipe and ns.quoteRecipe(recipeID)
	if not q then
		strip.title:SetText(faint .. (recipeID and "This recipe makes no item, or the addon has not read it yet." or "Choose a recipe.") .. "|r")
		for _, v in ipairs(strip.rows) do
			v:SetText("")
		end
		for _, l in ipairs(strip.lines) do
			l.name:SetText("")
			l.value:SetText("")
		end
		strip.note:SetText("")
		return
	end
	local r = q.recipe
	local quality = ns.price.itemInfo(r.output) or 1
	strip.title:SetText(Theme.escape(Theme.quality[quality] or Theme.color.text) .. (r.yield ~= 1 and (r.yield .. "× ") or "") .. name(r.output) .. "|r")
	strip.rows[1]:SetText(q.cost and money(q.cost) or dash)
	strip.rows[2]:SetText(q.revenue and (money(q.revenue) .. faint .. " after the cut|r") or dash)
	if q.profit then
		strip.rows[3]:SetText(q.profit >= 0 and (Theme.escape(Theme.color.success) .. "+|r" .. money(q.profit)) or (Theme.escape(Theme.color.danger) .. "-|r" .. money(-q.profit)))
	else
		strip.rows[3]:SetText(dash)
	end
	local margin = ns.Crafting.margin(q)
	strip.rows[4]:SetText(margin and (margin .. "%") or dash)
	local shown = 0
	for _, line in ipairs(q.lines) do
		if line.toBuy > 0 and shown < LINES then
			shown = shown + 1
			local l = strip.lines[shown]
			l.name:SetText(line.toBuy .. "× " .. name(line.id))
			l.value:SetText(line.unit and (money(line.unit) .. faint .. (line.from == "vendor" and " vendor" or " AH") .. "|r") or dash)
		end
	end
	for i = shown + 1, LINES do
		strip.lines[i].name:SetText(i == 1 and (faint .. "Nothing: your bags and bank hold it all.|r") or "")
		strip.lines[i].value:SetText("")
	end
	strip.note:SetText("Reagents at the cheaper of the auction house (your last scan) and a vendor; what you hold counts at the lower of buying and selling it.")
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
	if not strip then
		build()
	end
	strip:ClearAllPoints()
	strip:SetPoint("TOPLEFT", host(), "TOPRIGHT", 6, 0)
	strip:Show()
	recipeID = recipeID or shownRecipe()
	refresh()
end

local function hide()
	if strip then
		strip:Hide()
	end
end

ns.on("TRADE_SKILL_SHOW", "crafting strip", function()
	C_Timer.After(0, function()
		ns.safely("crafting strip", show)
	end)
end)
ns.on("TRADE_SKILL_CLOSE", "crafting strip", hide)
ns.on("BAG_UPDATE_DELAYED", "crafting strip", refresh)

if EventRegistry and EventRegistry.RegisterCallback then
	EventRegistry:RegisterCallback("ProfessionsRecipeListMixin.Event.OnRecipeSelected", function(_, info)
		recipeID = info and info.recipeID or recipeID
		ns.safely("crafting strip", refresh)
	end, ns)
end

-- For the smoke test: choose a recipe as the profession window would.
ns.CraftingStrip = {
	select = function(id)
		recipeID = id
		refresh()
	end,
	shown = function()
		return strip and strip:IsShown() and strip.title.text
	end,
}
