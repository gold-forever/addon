-- Gold Forever: the in-game window (/gf ui). Its first page shows every UI kit component with
-- example data, as the web app's Design system page does; the others are web pages brought into
-- the game from the saved file: mobs by what a loot is worth, and everything the characters hold.

local _, ns = ...
local Theme, UI, Encode = ns.Theme, ns.UI, ns.Encode

local function settings()
	return ns.settings("window", {})
end

-- A section heading with a line under it; returns where the next thing goes.
local function heading(page, text, y)
	local h = UI.Text(page, text, { size = "lg" })
	h:SetPoint("TOPLEFT", 0, y)
	local rule = UI.solid(page, "BORDER", Theme.color.border)
	rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
	rule:SetPoint("RIGHT", page, "RIGHT")
	rule:SetHeight(UI.pixel())
	return y - 30
end

local function itemName(id)
	local row = ns.db().catalogue.items[id]
	return (row and string.match(row, "^([^,]+)")) or ("Item " .. id)
end

local function itemQuality(id)
	local row = ns.db().catalogue.items[id]
	return tonumber(row and select(2, strsplit(",", row))) or 1
end

-- Design system ----------------------------------------------------------------------------------------

local function buildDesign(page)
	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetAllPoints()
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(640, 1240)
	scroll:SetScrollChild(body)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, body:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 48)))
	end)
	page:SetScript("OnSizeChanged", function(_, w)
		body:SetWidth(w)
	end)
	local y = 0

	y = heading(body, "Colours", y)
	local swatches = {
		{ "surface", Theme.color.surface }, { "raised", Theme.color.surfaceRaised }, { "border", Theme.color.borderStrong },
		{ "accent", Theme.color.accent }, { "success", Theme.color.success }, { "warning", Theme.color.warning },
		{ "danger", Theme.color.danger }, { "info", Theme.color.info }, { "xp", Theme.color.xp }, { "rested", Theme.color.rested },
	}
	for i, s in ipairs(swatches) do
		local sw = UI.Panel(body, { color = s[2], borderColor = Theme.color.borderStrong })
		sw:SetSize(52, 32)
		sw:SetPoint("TOPLEFT", (i - 1) * 60, y)
		local label = UI.Text(body, s[1], { size = "xs", tone = "muted" })
		label:SetPoint("TOP", sw, "BOTTOM", 0, -4)
	end
	y = y - 64
	for q = 0, 5 do
		local t = UI.Text(body, ({ "Poor", "Common", "Uncommon", "Rare", "Epic", "Legendary" })[q + 1], { tone = Theme.quality[q] })
		t:SetPoint("TOPLEFT", q * 90, y)
	end
	y = y - 30

	y = heading(body, "Text", y)
	local sizes = { { "xxl", "A page title" }, { "xl", "A stat's value" }, { "lg", "A section" }, { "md", "Body text, the default" }, { "sm", "Table cells" }, { "xs", "LABELS AND HINTS" } }
	for _, s in ipairs(sizes) do
		local t = UI.Text(body, s[2], { size = s[1] })
		t:SetPoint("TOPLEFT", 0, y)
		local tag = UI.Text(body, s[1] .. " · " .. Theme.text[s[1]] .. " pt", { size = "xs", tone = "faint" })
		tag:SetPoint("LEFT", t, "RIGHT", 12, 0)
		y = y - (Theme.text[s[1]] + 10)
	end
	local tones = UI.Text(body, "Text in three tones: " .. Theme.escape(Theme.color.textMuted) .. "muted|r, " .. Theme.escape(Theme.color.textFaint) .. "faint|r, " .. Theme.escape(Theme.color.accent) .. "accent|r.")
	tones:SetPoint("TOPLEFT", 0, y)
	y = y - 34

	y = heading(body, "Buttons, badges, tabs, search", y)
	local primary = UI.Button(body, "Scan the auction house", nil, { kind = "primary" })
	primary:SetPoint("TOPLEFT", 0, y)
	local default = UI.Button(body, "Open the bags")
	default:SetPoint("LEFT", primary, "RIGHT", 8, 0)
	local ghost = UI.Button(body, "Hide", nil, { kind = "ghost" })
	ghost:SetPoint("LEFT", default, "RIGHT", 8, 0)
	local x = 0
	for _, b in ipairs({ { "sold", Theme.color.success }, { "learn · 1s", Theme.color.warning }, { "rare", Theme.color.info }, { "expired", Theme.color.danger } }) do
		local badge = UI.Badge(body, b[1], b[2])
		badge:SetPoint("TOPLEFT", 380 + x, y - 4)
		x = x + badge:GetWidth() + 6
	end
	y = y - 40
	local tabs = UI.TabBar(body, { { key = "learned", label = "Learned" }, { key = "unlearned", label = "Unlearned" }, { key = "skillup", label = "Skill up" } })
	tabs:SetPoint("TOPLEFT", 0, y)
	tabs:SetWidth(320)
	local search = UI.SearchBox(body, "Search items…")
	search:SetPoint("TOPLEFT", 340, y - 2)
	search:SetWidth(240)
	y = y - 48

	y = heading(body, "Stat cards and money", y)
	local cards = {
		{ "Gold, all characters", UI.layout.money(1014420, "gold"), "5 characters" },
		{ "Worth", UI.layout.money(27098), "at the better of auction and vendor" },
		{ "Play next", "Jemmou Firereaver", "0.3 levels of rested XP waiting" },
	}
	for i, c in ipairs(cards) do
		local card = UI.StatCard(body, c[1], c[2], c[3])
		card:SetSize(200, 72)
		card:SetPoint("TOPLEFT", (i - 1) * 212, y)
	end
	y = y - 84
	local money = UI.Text(body, "Money: " .. UI.layout.money(0) .. " · " .. UI.layout.money(45) .. " · " .. UI.layout.money(1484) .. " · " .. UI.layout.money(1014420) .. " · as gold: " .. UI.layout.money(1014420, "gold"))
	money:SetPoint("TOPLEFT", 0, y)
	y = y - 34

	y = heading(body, "Bars and a sparkline", y)
	local xpLabel = UI.Text(body, "Level progress and rested", { size = "sm", tone = "muted" })
	xpLabel:SetPoint("TOPLEFT", 0, y)
	local xp = UI.Bar(body, 100, { { value = 67, color = Theme.color.xp }, { value = 18, color = Theme.color.rested } })
	xp:SetPoint("TOPLEFT", 0, y - 18)
	xp:SetWidth(300)
	local mixLabel = UI.Text(body, "XP by source: quests, kills, dungeons", { size = "sm", tone = "muted" })
	mixLabel:SetPoint("TOPLEFT", 0, y - 36)
	local mix = UI.Bar(body, 100, { { value = 52, color = Theme.color.chart1 }, { value = 38, color = Theme.color.chart2 }, { value = 10, color = Theme.color.xp } }, 6)
	mix:SetPoint("TOPLEFT", 0, y - 54)
	mix:SetWidth(300)
	local spark = UI.Sparkline(body, { 10, 14, 9, 22, 30, 26, 41, 38, 52, 47 })
	spark:SetPoint("TOPLEFT", 340, y - 4)
	spark:SetSize(240, 56)
	y = y - 80

	y = heading(body, "Table", y)
	local example = UI.Table(body, {
		{ key = "mob", title = "Mob", flex = 2 },
		{ key = "loots", title = "Looted", width = 70, align = "RIGHT" },
		{ key = "value", title = "A loot", width = 90, align = "RIGHT", text = function(r) return UI.layout.money(r.value) end, sort = function(r) return r.value end },
		{ key = "gph", title = "Gold / hour", width = 100, align = "RIGHT", text = function(r) return UI.layout.money(r.gph, "gold") end, sort = function(r) return r.gph end },
	}, { pageSize = 5 })
	example:SetPoint("TOPLEFT", 0, y)
	example:SetPoint("RIGHT", body, "RIGHT")
	example:SetRows({
		{ mob = "Scrawny Ursera", loots = 40, value = 122, gph = 43432 },
		{ mob = "Vile Familiar", loots = 18, value = 226, gph = 27798 },
		{ mob = "Skeletal Mage", loots = 31, value = 412, gph = 77044 },
		{ mob = "Mottled Boar", loots = 12, value = 58, gph = 10846 },
		{ mob = "Gray Forest Wolf", loots = 4, value = 238, gph = 44506 },
		{ mob = "Prowler", loots = 3, value = 191, gph = 35717 },
	})
	y = y - example:GetHeight() - 12

	y = heading(body, "Empty state", y)
	local empty = UI.EmptyState(body, "Nothing held yet", "Upload a save: bags, bank and mail are read as the addon sees them.")
	empty:SetPoint("TOPLEFT", 0, y)
	empty:SetPoint("RIGHT", body, "RIGHT")
	body:SetHeight(-y + 100)
end

-- Mobs ---------------------------------------------------------------------------------------------------

local function buildMobs(page)
	local title = UI.Text(page, "Mobs, by what a loot is worth", { size = "xl" })
	title:SetPoint("TOPLEFT")
	local lede = UI.Text(page, "Every mob your characters have looted: how often, and what a loot brought in coin and items, priced as on the web.", { size = "sm", tone = "muted", wrap = true })
	lede:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
	lede:SetPoint("RIGHT", page, "RIGHT")
	local tbl = UI.Table(page, {
		{ key = "name", title = "Mob", flex = 2 },
		{ key = "loots", title = "Looted", width = 70, align = "RIGHT" },
		{ key = "coin", title = "Coin a loot", width = 100, align = "RIGHT", text = function(r) return UI.layout.money(r.coin) end, sort = function(r) return r.coin end },
		{ key = "value", title = "A loot", width = 100, align = "RIGHT", text = function(r) return UI.layout.money(r.value) end, sort = function(r) return r.value end },
	}, { pageSize = 16, empty = "No loot recorded yet." })
	tbl:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	tbl.sortColumn, tbl.sortDescending = 4, true
	function page:Refresh()
		local mobs, worth = ns.mobStats()
		local names = ns.db().catalogue.npcs
		local rows = {}
		for id, m in pairs(mobs or {}) do
			local value = m.coin
			for item, d in pairs(m.items) do
				value = value + (worth(item) or 0) * d.units
			end
			rows[#rows + 1] = {
				name = (names[id] and string.match(names[id], "^([^,]+)")) or ("NPC " .. id),
				loots = m.loots,
				coin = m.coin / m.loots,
				value = value / m.loots,
			}
		end
		tbl:SetRows(rows)
	end
end

-- Inventory ---------------------------------------------------------------------------------------------

local function buildInventory(page)
	local title = UI.Text(page, "Inventory", { size = "xl" })
	title:SetPoint("TOPLEFT")
	local query = ""
	local tbl
	local search = UI.SearchBox(page, "Search items…", function(text)
		query = string.lower(text)
		if page.Refresh then
			page:Refresh()
		end
	end)
	search:SetPoint("TOPRIGHT")
	search:SetWidth(220)
	local total = UI.StatCard(page, "Worth", "", "")
	total:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -12)
	total:SetWidth(220)
	local count = UI.StatCard(page, "Items held", "", "")
	count:SetPoint("LEFT", total, "RIGHT", 12, 0)
	count:SetWidth(220)
	tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 2, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "held", title = "Held", width = 60, align = "RIGHT" },
		{ key = "where", title = "Where", flex = 2, color = function() return Theme.color.textMuted end },
		{ key = "value", title = "Worth", width = 100, align = "RIGHT", text = function(r) return r.value > 0 and UI.layout.money(r.value) or "—" end, sort = function(r) return r.value end },
	}, { pageSize = 13, empty = "Nothing matches." })
	tbl:SetPoint("TOPLEFT", total, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	tbl.sortColumn, tbl.sortDescending = 4, true
	function page:Refresh()
		local byItem = {}
		for _, c in pairs(ns.db().characters) do
			for _, place in ipairs({ "bags", "bank", "mail" }) do
				for id, n in pairs(Encode.parseItems(c[place] and c[place].items)) do
					local it = byItem[id] or { held = 0, where = {} }
					byItem[id] = it
					it.held = it.held + n
					it.where[#it.where + 1] = string.format("%s %d (%s)", c.name or "?", n, place)
				end
			end
		end
		local rows, worth, units = {}, 0, 0
		for id, it in pairs(byItem) do
			local name = itemName(id)
			if query == "" or string.find(string.lower(name), query, 1, true) then
				local unit = ns.price and ns.price.worth(id) or 0
				rows[#rows + 1] = { name = name, quality = itemQuality(id), held = it.held, where = table.concat(it.where, ", "), value = (unit or 0) * it.held }
				worth = worth + (unit or 0) * it.held
				units = units + it.held
			end
		end
		total:Set(UI.layout.money(worth, "gold"), "at the better of auction and vendor")
		count:Set(tostring(#rows), units .. " units")
		tbl:SetRows(rows)
	end
end

-- The window ----------------------------------------------------------------------------------------------

local window

ns.commands.ui = function(page)
	if window and window:IsShown() and (page == nil or page == "") then
		window:Hide()
		return
	end
	if not window then
		window = UI.Window("GoldForeverWindow", "Gold Forever", {
			{ key = "design", label = "Design system", build = buildDesign },
			{ key = "mobs", label = "Mobs", build = buildMobs },
			{ key = "inventory", label = "Inventory", build = buildInventory },
		}, settings())
	end
	window:Show()
	if page and page ~= "" then
		window:SelectPage(page)
	end
end
