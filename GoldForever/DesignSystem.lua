-- Gold Forever: the in-game window (/gf ui): web pages brought into the game from the saved file
-- (characters and who to play next, levelling, the ledger, mobs by what a loot is worth, everything
-- the characters hold), and a page showing every UI kit component with example data, as the web
-- app's Design system page does.

local _, ns = ...
local Theme, UI, Encode, Views = ns.Theme, ns.UI, ns.Encode, ns.Views

local function settings()
	return ns.settings("window", {})
end

-- A page's table order, saved with the window: the column and direction last picked, at first the given
-- column, highest first.
local function sortOf(page, column)
	local s = settings()
	s.sort = s.sort or {}
	s.sort[page] = s.sort[page] or { column = column, descending = true }
	return s.sort[page]
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

-- Shared by the pages ------------------------------------------------------------------------------------

-- 12345 -> "12,345".
local function count(n)
	local s = tostring(math.floor((n or 0) + 0.5))
	local out = string.gsub(string.reverse(s), "(%d%d%d)", "%1,")
	return (string.gsub(string.reverse(out), "^(%-?),", "%1"))
end

local function classColor(class)
	return Theme.class[class or ""] or Theme.color.text
end

-- Where a page's own content starts: the window's header shows its title and the line under it
-- (PAGES), so this is an empty strip along the page's top edge to place what follows.
local function header(page)
	local top = CreateFrame("Frame", nil, page)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(1)
	return top
end

-- Home ------------------------------------------------------------------------------------------------------

-- The next moves, from the save and the prices: scan, sell what the bags hold, the best craft; today's
-- money by where it came from; and the bag items worth most.
local function buildHome(page)
	local W = (page:GetWidth() and page:GetWidth() > 0) and page:GetWidth() or 708
	local GAP = 16
	local cardW = math.floor((W - GAP * 2) / 3)
	local actions = {}
	for i, a in ipairs({ { icon = "search", go = nil }, { icon = "package", go = "inventory" }, { icon = "flask-conical", go = "crafting" } }) do
		local card = CreateFrame("Button", nil, page)
		card:SetSize(cardW, 72)
		card:SetPoint("TOPLEFT", (i - 1) * (cardW + GAP), 0)
		local _, rim = UI.surface(card, Theme.color.surfaceRaised, 1, Theme.color.border, Theme.skin.radius and Theme.skin.radius.card or 0)
		local box = CreateFrame("Frame", nil, card)
		box:SetSize(38, 38)
		box:SetPoint("LEFT", 14, 0)
		UI.surface(box, Theme.color.accentSoft, 1, nil, Theme.skin.radius and 6 or 0)
		local icon = UI.Icon(box, a.icon, 20, "accent")
		icon:SetPoint("CENTER")
		card.title = UI.Text(card, "", { size = "sm", medium = true })
		card.title:SetPoint("TOPLEFT", 64, -18)
		card.title:SetWidth(cardW - 76)
		card.line = UI.Text(card, "", { size = "xs", tone = "faint" })
		card.line:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -5)
		card.line:SetWidth(cardW - 76)
		-- A card that opens a page says so: "Open ›" in its corner, and its edge lights up under the pointer
		-- (manual test run 001: hard to know it can be clicked).
		if a.go then
			local open = UI.Text(card, "Open ›", { size = "xs", tone = "faint" })
			open:SetPoint("TOPRIGHT", -10, -8)
			card:SetScript("OnClick", function()
				ns.openPage(a.go)
			end)
			card:SetScript("OnEnter", function()
				if rim then
					rim:SetColor(Theme.color.accent)
				end
				open:SetTextColor(Theme.rgb(Theme.color.accent))
			end)
			card:SetScript("OnLeave", function()
				if rim then
					rim:SetColor(Theme.color.border)
				end
				open:SetTextColor(Theme.rgb(Theme.color.textFaint))
			end)
		end
		actions[i] = card
	end

	local half = math.floor((W - GAP) / 2)
	local function column(x, title, rows, rowH)
		local label = UI.Text(page, title, { size = "xs", medium = true, tone = "faint" })
		label:SetPoint("TOPLEFT", x, -140)
		local card = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
		card:SetPoint("TOPLEFT", x, -158)
		card:SetSize(half, rows * rowH + 16)
		card.rows = {}
		for i = 1, rows do
			local r = CreateFrame("Frame", nil, card)
			r:SetHeight(rowH)
			r:SetPoint("TOPLEFT", 8, -8 - (i - 1) * rowH)
			r:SetPoint("RIGHT", card, "RIGHT", -8, 0)
			card.rows[i] = r
		end
		card.empty = UI.Text(card, "", { size = "sm", tone = "faint", wrap = true })
		card.empty:SetPoint("TOPLEFT", 16, -16)
		card.empty:SetPoint("RIGHT", card, "RIGHT", -16, 0)
		return card, label
	end

	-- A gold goal (owner's answer, 2026-10-24): gold across all characters against an amount and a date.
	local goalStrip = CreateFrame("Frame", nil, page)
	goalStrip:SetPoint("TOPLEFT", 0, -86)
	goalStrip:SetPoint("RIGHT", page, "RIGHT")
	goalStrip:SetHeight(42)
	local goalText = UI.Text(goalStrip, "", { size = "sm" })
	goalText:SetPoint("TOPLEFT")
	local goalBar = UI.Bar(goalStrip, 100, {}, 6)
	goalBar:SetPoint("TOPLEFT", goalText, "BOTTOMLEFT", 0, -8)
	goalBar:SetPoint("RIGHT", goalStrip, "RIGHT", -310, 0)
	-- The field groups the digits as they are typed ("3,000,000"); Set reads the digits alone.
	local goalGold
	goalGold = UI.SearchBox(goalStrip, "Goal in gold", function(text)
		local digits = string.gsub(text, "%D", "")
		local grouped = digits ~= "" and UI.layout.group(tonumber(digits)) or ""
		if grouped ~= text then
			goalGold:SetText(grouped)
			goalGold:SetCursorPosition(#grouped)
		end
	end)
	-- As tall as the dropdown and the button beside it, in every look (it was shorter in some).
	goalGold:SetHeight(28)
	goalGold:SetPoint("TOPRIGHT", -196, 2)
	goalGold:SetWidth(100)
	local DAYS = { { value = 7, label = "in 7 days" }, { value = 14, label = "in 14 days" }, { value = 30, label = "in 30 days" }, { value = 60, label = "in 60 days" } }
	local goalDays = UI.Dropdown(goalStrip, DAYS, 30, nil)
	goalDays:SetPoint("TOPRIGHT", -84, 2)
	goalDays:SetWidth(106)
	local goalSet = UI.Button(goalStrip, "Set", function()
		local gold = tonumber((string.gsub(goalGold:GetText() or "", "%D", "")))
		local s = settings()
		if gold and gold > 0 then
			s.goal = { gold = math.floor(gold * 10000), by = ns.now() + (goalDays.value or 30) * 86400 }
		else
			s.goal = nil -- an empty field clears it
		end
		goalGold:SetText("")
		goalGold:ClearFocus()
		page:Refresh()
	end, { kind = "ghost", width = 76, height = 28 })
	goalSet:SetPoint("TOPRIGHT", 0, 2)
	page.setGoal = function(gold, days)
		settings().goal = gold and { gold = gold, by = ns.now() + days * 86400 } or nil
	end

	local today, todayLabel = column(0, "TODAY", 7, 36)
	for _, r in ipairs(today.rows) do
		r.icon = UI.Icon(r, "trending-up", 15, "muted")
		r.icon:SetPoint("LEFT", 8, 0)
		r.label = UI.Text(r, "", { size = "sm" })
		r.label:SetPoint("LEFT", 34, 0)
		r.value = UI.Text(r, "", { size = "sm", align = "RIGHT" })
		r.value:SetPoint("RIGHT", -8, 0)
		r.value:SetWidth(150)
	end
	local sell = column(half + GAP, "WORTH SELLING NOW", 5, 50)
	for _, r in ipairs(sell.rows) do
		r.icon = r:CreateTexture(nil, "ARTWORK")
		r.icon:SetSize(28, 28)
		r.icon:SetPoint("LEFT", 6, 0)
		r.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		r.name = UI.Text(r, "", { size = "sm" })
		r.name:SetPoint("TOPLEFT", 44, -9)
		r.name:SetWidth(half - 190)
		r.hint = UI.Text(r, "", { size = "xs", tone = "faint" })
		r.hint:SetPoint("TOPLEFT", r.name, "BOTTOMLEFT", 0, -4)
		r.value = UI.Text(r, "", { size = "md", align = "RIGHT" })
		r.value:SetPoint("RIGHT", -8, 0)
		r.value:SetWidth(120)
		-- The item's own tooltip on hover.
		r:EnableMouse(true)
		r:SetScript("OnEnter", function(self)
			if self.itemId and GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if GameTooltip.SetItemByID then
					GameTooltip:SetItemByID(self.itemId)
				else
					GameTooltip:SetHyperlink("item:" .. self.itemId)
				end
				GameTooltip:Show()
			end
		end)
		r:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
	end

	-- Kept current while it shows: money as it moves, the bags as they are read (manual test run 001: Home
	-- stayed as it was after a fight). A moment's wait gathers a burst of changes into one refresh.
	local soon = ns.throttle("ui home", 2, function()
		if page:IsVisible() then
			page:Refresh()
		end
	end)
	ns.on("PLAYER_MONEY", "ui home", soon)
	ns.onBagsRead(soon)

	function page:Refresh()
		local db, me, now = ns.db(), ns.me(), ns.now()
		local faint = Theme.escape(Theme.color.textFaint)
		-- Scan: the cooldown, or how long ago the last one was.
		local st = ns.scanState and ns.scanState() or { wait = 0 }
		local last
		for _, s in ipairs(db.scans or {}) do
			if s.kind == "full" and (not last or s.t > last) then
				last = s.t
			end
		end
		actions[1].title:SetText("Scan the auction house")
		actions[1].line:SetText(st.wait > 0 and string.format("Next full scan in %d:%02d", math.floor(st.wait / 60), st.wait % 60)
			or (last and ("Last scan " .. Views.ago(last, now) .. ": scan again") or "No scan yet: open the auction house"))
		-- The bags: what they would sell for.
		local held = me and Encode.parseItems(me.bags and me.bags.items) or {}
		local list, total, unpriced = Views.worthList(held, function(id)
			if ns.price then
				return ns.price.worth(id)
			end
		end)
		actions[2].title:SetText("Sell your bags")
		actions[2].line:SetText(#list > 0 and string.format("%d items, about %s", #list, UI.layout.money(total, "gold")) or "Nothing priced in your bags")
		-- The best craft at the latest prices.
		local crafts = ns.profitableCrafts and ns.profitableCrafts() or {}
		local best = crafts[1]
		actions[3].title:SetText(best and ("Craft " .. itemName(best.recipe.output)) or "Craft for profit")
		actions[3].line:SetText(best and (UI.layout.money(best.profit, "gold") .. " profit a craft") or "No priced recipe makes a profit yet")

		-- The goal.
		local total = 0
		for _, c in pairs(db.characters or {}) do
			total = total + (c.money or 0)
		end
		local goal = settings().goal
		if goal then
			local g = Views.goal(now, total, goal)
			goalText:SetText(string.format("Goal %s: %s now, %d%%%s", UI.layout.money(goal.gold, "gold"), UI.layout.money(total, "gold"), g.pct,
				g.reached and Theme.escape(Theme.color.success) .. " · reached|r" or g.late and (faint .. " · the date has passed|r")
				or (faint .. string.format(" · %s a day for %d more %s", "|r" .. UI.layout.money(g.perDay, "gold") .. faint, g.daysLeft, g.daysLeft == 1 and "day" or "days") .. "|r")))
			goalBar:Set(100, { { value = g.pct, color = g.reached and Theme.color.success or Theme.color.accent } })
			goalBar:Show()
		else
			goalText:SetText(faint .. "A gold goal: an amount and a date, and Home shows how far there is to go. " .. "|r" .. UI.layout.money(total, "gold") .. faint .. " across your characters now.|r")
			goalBar:Hide()
		end

		-- Today's money for this character, by where it came from.
		local ledger = me and Views.ledger(Views.rows(db, "money", me.ref, Views.dayStart(now)), Views.rows(db, "flight"), me.ref, Views.dayStart(now)) or { categories = {}, net = 0 }
		table.sort(ledger.categories, function(a, b)
			return math.abs(a.net) > math.abs(b.net)
		end)
		todayLabel:SetText(#ledger.categories > 0 and ("TODAY · NET " .. string.upper(UI.layout.money(ledger.net, "gold"))) or "TODAY")
		for i, r in ipairs(today.rows) do
			local c = ledger.categories[i]
			r:SetShown(c ~= nil)
			if c then
				r.icon:SetTexture(Theme.icon(c.net >= 0 and "trending-up" or "coins"))
				r.icon:SetTone(c.net >= 0 and Theme.color.success or "faint")
				r.label:SetText(c.label or c.key)
				r.value:SetText(c.net >= 0 and UI.layout.money(c.net, "gold") or (Theme.escape(Theme.color.danger) .. "-|r" .. UI.layout.money(-c.net, "gold")))
			end
		end
		today.empty:SetText(#ledger.categories == 0 and "No money has moved today on this character." or "")

		-- The bag items worth most.
		for i, r in ipairs(sell.rows) do
			local it = list[i]
			r:SetShown(it ~= nil)
			r.itemId = it and it.id
			if it then
				local quality = itemQuality(it.id)
				local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id) or (GetItemIcon and GetItemIcon(it.id))
				r.icon:SetTexture(icon or 134400)
				r.name:SetText(Theme.escape(Theme.quality[quality] or Theme.color.text) .. itemName(it.id) .. "|r" .. faint .. " ×" .. it.count .. "|r")
				r.hint:SetText(it.where == "vendor" and "to a vendor" or "at the auction house, after its cut")
				r.value:SetText(UI.layout.money(it.value, "gold"))
			end
		end
		sell.empty:SetText(#list == 0 and ("Nothing priced in your bags" .. (unpriced > 0 and string.format(" (%d unpriced)", unpriced) or "") .. ". Scan the auction house for prices.") or "")
	end
end

-- Companion ---------------------------------------------------------------------------------------------------

-- What the addon can know of the companion without the internet (design 009): whether its file loaded,
-- when it was written, its markets and items, this character's Discord dings, and what is missing.
local function buildCompanion(page)
	local status = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	status:SetPoint("TOPLEFT")
	status:SetPoint("RIGHT", page, "RIGHT")
	status:SetHeight(76)
	local icon = UI.Icon(status, "coins", 22, "accent")
	icon:SetPoint("LEFT", 20, 0)
	local head = UI.Text(status, "", { size = "md", medium = true })
	head:SetPoint("TOPLEFT", 58, -18)
	head:SetPoint("RIGHT", status, "RIGHT", -16, 0)
	local line = UI.Text(status, "", { size = "xs", tone = "faint", wrap = true })
	line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
	line:SetPoint("RIGHT", status, "RIGHT", -16, 0)

	local cards = {}
	for i, label in ipairs({ "Prices written", "Markets", "This character's market", "Discord dings" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(math.floor(((page:GetWidth() and page:GetWidth() > 0 and page:GetWidth() or 708) - 36) / 4))
		if i == 1 then
			c:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -12)
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	local tbl = UI.Table(page, {
		{ key = "key", title = "Market", flex = 3 },
		{ key = "items", title = "Items", width = 90, align = "RIGHT" },
		{ key = "mine", title = "", width = 140, align = "RIGHT", text = function(r) return r.mine and "this character's" or "" end,
			color = function() return Theme.color.accent end },
	}, { pageSize = 6, empty = "No markets in the file." })
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local note = UI.Text(page, "The companion uploads your save whenever the game writes it (at /reload or logout) and brings everyone's prices into the game every hour. It needs nothing from you in game.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	note:SetPoint("RIGHT", page, "RIGHT")

	function page:Refresh()
		local st = ns.Prices.status(GoldForever_Prices, ns.Prices.mine(), ns.now())
		local warn = Theme.escape(Theme.color.warning)
		if st.state == "ok" then
			head:SetText("Connected: the companion's prices are loaded")
			icon:SetTone("accent")
			line:SetText(#st.missing > 0 and (warn .. "No prices yet for " .. table.concat(st.missing, ", ") .. ": the pool fills as players scan there.|r")
				or "Everyone's prices show in your tooltips and the auction panel.")
		elseif st.state == "missing" then
			head:SetText(warn .. "No companion data in the game|r")
			icon:SetTone(Theme.color.warning)
			line:SetText("The companion app writes the GoldForever_Data addon; start it, then restart the game. Get it at gold-forever.app/companion.")
		elseif st.state == "version" then
			head:SetText(warn .. "The companion's file is a newer version|r")
			icon:SetTone(Theme.color.warning)
			line:SetText("Update the addon to read it.")
		else
			head:SetText(warn .. "The companion's file cannot be read|r")
			icon:SetTone(Theme.color.warning)
			line:SetText("The companion writes it again at its next update.")
		end
		local mine
		for _, m in ipairs(st.markets) do
			if m.mine and not mine then
				mine = m
			end
		end
		cards[1]:Set(st.age or "—", st.state == "ok" and "the prices file" or "")
		cards[2]:Set(tostring(#st.markets), "in the file")
		cards[3]:Set(mine and tostring(mine.items) or "—", mine and "items priced" or "none yet")
		local d = ns.Dings and ns.Dings.current()
		cards[4]:Set(d and (d.on and "On" or "Off") or "—", d and (d.webhook == false and "no webhook on the site" or d.pending and "waiting for the upload" or d.companion and "this character" or "needs the companion") or "")
		tbl:SetRows(st.markets)
	end
end

-- Rares ------------------------------------------------------------------------------------------------------

local function mapName(id)
	local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
	return info and info.name or (id and ("map " .. id)) or "?"
end

-- Every rare the characters have seen (Rares.lua's log): how often, when and where last, how it was
-- seen, and what a loot of it has been worth.
local function buildRares(page)
	local note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT")
	note:SetPoint("RIGHT", page, "RIGHT")
	local tbl = UI.Table(page, {
		{ key = "name", title = "Rare", flex = 2 },
		{ key = "seen", title = "Seen", width = 50, align = "RIGHT" },
		{ key = "last", title = "Last", width = 80, align = "RIGHT", text = function(r) return Views.ago(r.last, ns.now()) end },
		{ key = "where", title = "Where", flex = 2, color = function() return Theme.color.textMuted end },
		{ key = "how", title = "How", width = 80, color = function() return Theme.color.textFaint end },
		{ key = "value", title = "A loot", width = 90, align = "RIGHT", text = function(r) return r.value and UI.layout.amount(r.value) or "—" end,
			sort = function(r) return r.value or -1 end },
	}, { pageSize = 14, empty = "No rare seen yet: they are logged when a nameplate, the target or the minimap shows one.", sort = sortOf("rares", 3) })
	tbl:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local retail = ns.Realms.isRetail(select(4, GetBuildInfo()))
		-- On retail nothing is recorded (its cities are full of markers taken for rares), and what a retail save
		-- holds from before that was switched off is those false rares (manual test run 001: "NPC …" from
		-- Silvermoon): none listed.
		note:SetText(retail and "Rares are recorded on WoW: Forever only: retail's cities are full of map markers that are not rares."
			or "Logged from nameplates, your target and the minimap. Settings → Modules switches the alerts.")
		local names = ns.db().catalogue.npcs
		local mobs, worth = ns.mobStats(function()
			if page:IsShown() then
				page:Refresh()
			end
		end)
		local rows = {}
		for _, r in ipairs(retail and {} or Views.rares(Views.rows(ns.db(), "rare"))) do
			local m = mobs and mobs[r.npc]
			local value
			if m and m.loots > 0 then
				value = m.coin
				for item, d in pairs(m.items) do
					value = value + (worth(item) or 0) * d.units
				end
				value = value / m.loots
			end
			rows[#rows + 1] = {
				name = (names[r.npc] and string.match(names[r.npc], "^([^,]+)")) or ("NPC " .. r.npc),
				seen = r.seen,
				last = r.last,
				where = mapName(r.map) .. ((r.x and r.y) and string.format("  %.1f, %.1f", r.x / 10, r.y / 10) or ""),
				how = r.how or "",
				value = value,
			}
		end
		tbl:SetRows(rows)
	end
end

-- The days the save keeps, which the Ledger's tabs cover.
local LEDGER_DAYS = 14

-- Auction sales ----------------------------------------------------------------------------------------------

-- What sold on the auction house, from the "sold" mail the addon reads: for this character or all,
-- with the cut and what it brought, over the two weeks the save keeps.
local function buildSales(page)
	local whose = settings().ledger or "me"
	local tabs = UI.TabBar(page, { { key = "me", label = "This character" }, { key = "all", label = "All characters" } }, function(key)
		whose = key
		settings().ledger = key
		page:Refresh()
	end)
	tabs:SetPoint("TOPLEFT")
	tabs:Select(whose)
	local cards = {}
	for i, label in ipairs({ "Sold", "Sold for", "After the cut" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(200)
		if i == 1 then
			c:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -12)
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	local names = {}
	local tbl = UI.Table(page, {
		{ key = "item", title = "Item", flex = 3, text = function(r) return r.qty > 1 and (r.item .. Theme.escape(Theme.color.textFaint) .. " ×" .. r.qty .. "|r") or r.item end },
		{ key = "char", title = "Character", flex = 2, text = function(r) return names[r.char] or "?" end, color = function() return Theme.color.textMuted end },
		{ key = "price", title = "Sold for", width = 90, align = "RIGHT", text = function(r) return UI.layout.amount(r.price) end },
		{ key = "net", title = "After cut", width = 90, align = "RIGHT", text = function(r) return UI.layout.amount(r.net) end },
		{ key = "t", title = "When", width = 70, align = "RIGHT", text = function(r) return Views.ago(r.t, ns.now()) end, color = function() return Theme.color.textFaint end },
	}, { pageSize = 8, empty = "No sale yet: they are read from the auction house's mail when you open it.", sort = sortOf("sales", 5) })
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local db, me, now = ns.db(), ns.me(), ns.now()
		for _, c in pairs(db.characters or {}) do
			if c.ref then
				names[tonumber(c.ref) or c.ref] = c.name
			end
		end
		local ref = whose == "me" and me and me.ref or nil
		local sales = Views.sales(Views.rows(db, "sale", ref, now - LEDGER_DAYS * 86400), ref, now - LEDGER_DAYS * 86400)
		cards[1]:Set(tostring(sales.count), sales.count == 1 and "sale" or "sales")
		cards[2]:Set(UI.layout.money(sales.gross, "gold"), "last " .. LEDGER_DAYS .. " days")
		cards[3]:Set(UI.layout.money(sales.net, "gold"), UI.layout.money(sales.cut, "gold") .. " to the auction house")
		tbl:SetRows(sales.list)
	end
end

-- Crafting -----------------------------------------------------------------------------------------------------

-- Every recipe the characters know that makes an item (design 009, Crafting module), by profit: what the
-- reagents cost (the cheaper of auction house and vendor), what it sells for after the cut, profit and
-- margin in bands; the chosen one's reagents below. "I have these" counts what you hold at no cost.
local BAND_COLOR = { loss = "danger", thin = "textFaint", fair = "text", good = "success" }

local function buildCrafting(page)
	local held = settings().craftHeld or false
	local chosen
	-- The switch beside its words (manual test run 001: far apart, and "I have these" was unclear).
	local sw = UI.Switch(page, held, function(on)
		held = on
		settings().craftHeld = on
		page:Refresh()
	end)
	sw:SetPoint("TOPLEFT", 0, -2)
	local switchLabel = UI.Text(page, "Use my own ingredients when I have them (they cost nothing)", { size = "sm", tone = "muted" })
	switchLabel:SetPoint("LEFT", sw, "RIGHT", 8, 0)
	-- One profession at a time, or all (owner, 2026-10-24: "only leatherworking").
	local profession = settings().craftProf
	local profPick = UI.Dropdown(page, { { value = "all", label = "All professions" } }, profession or "all", function(v)
		profession = v ~= "all" and v or nil
		settings().craftProf = profession
		chosen = nil
		page:Refresh()
	end)
	profPick:SetPoint("TOPRIGHT", 0, 2)
	profPick:SetWidth(180)
	local money = function(c)
		return c and UI.layout.amount(c) or (Theme.escape(Theme.color.textFaint) .. "unknown|r")
	end
	local tbl = UI.Table(page, {
		{ key = "name", title = "Recipe", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end,
			text = function(r) return r.name .. (r.gear and (Theme.escape(Theme.color.textFaint) .. "  any quality|r") or "") end },
		{ key = "cost", title = "Cost", width = 84, align = "RIGHT", text = function(r) return money(r.cost) end, sort = function(r) return r.cost or -1 end },
		{ key = "revenue", title = "Sells for", width = 84, align = "RIGHT", text = function(r) return money(r.revenue) end, sort = function(r) return r.revenue or -1 end },
		-- Gear: shown in grey and sorted last, its price being one for every quality.
		{ key = "profit", title = "Profit", width = 84, align = "RIGHT", text = function(r) return r.gear and (Theme.escape(Theme.color.textFaint) .. UI.layout.plain(money(r.profit)) .. "|r") or money(r.profit) end,
			sort = function(r) return (not r.gear and r.profit) or -math.huge end },
		{ key = "margin", title = "Margin", width = 64, align = "RIGHT", text = function(r) return r.margin and (r.margin .. "%") or "—" end,
			color = function(r) return r.gear and Theme.color.textFaint or Theme.color[BAND_COLOR[ns.Crafting.band(r.margin)] or "textFaint"] end,
			sort = function(r) return (not r.gear and r.margin) or -math.huge end },
	}, {
		pageSize = 8,
		empty = "No priced recipe yet: open your professions once, and scan the auction house.",
		itemId = function(r) return r.q and r.q.recipe and r.q.recipe.output end,
		sort = sortOf("crafting", 4),
		isSelected = function(r) return chosen and r.id == chosen end,
		onRowClick = function(r)
			chosen = r.id
			page:Refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT", 0, -30)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local detail = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	detail:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	detail:SetPoint("RIGHT", page, "RIGHT")
	detail:SetHeight(140)
	local head = UI.Text(detail, "", { size = "sm", medium = true })
	head:SetPoint("TOPLEFT", 14, -10)
	-- The craft queue: this recipe added, and the queue's size; the Shop buys what it still needs.
	local queued = UI.Text(detail, "", { size = "xs", tone = "faint" })
	queued:SetPoint("BOTTOMLEFT", 14, 12)
	local clear = UI.Button(detail, "Clear queue", function()
		ns.queueClear()
		page:Refresh()
	end, { kind = "ghost", width = 100, height = 22 })
	clear:SetPoint("BOTTOMRIGHT", -14, 8)
	-- The craft queue window: where to get each reagent (CraftQueue.lua).
	local queueWindow = UI.Button(detail, "Queue window", function()
		if ns.openCraftQueue then
			ns.openCraftQueue()
		end
	end, { width = 110, height = 22 })
	queueWindow:SetPoint("RIGHT", clear, "LEFT", -6, 0)
	for i, n in ipairs({ 5, 1 }) do
		local b = UI.Button(detail, "Queue " .. n, function()
			if chosen then
				ns.queueAdd(chosen, n)
				page:Refresh()
			end
		end, { width = 74, height = 22 })
		b:SetPoint("TOPRIGHT", -14 - (i - 1) * 80, -8)
	end
	local lines = {}
	for i = 1, 4 do
		local l = UI.Text(detail, "", { size = "xs" })
		l:SetPoint("TOPLEFT", 14, -30 - (i - 1) * 18)
		l:SetWidth(360)
		local v = UI.Text(detail, "", { size = "xs", align = "RIGHT", tone = "muted" })
		v:SetPoint("TOPRIGHT", -14, -30 - (i - 1) * 18)
		v:SetWidth(260)
		-- The reagent's own tooltip on hover (manual test run 001).
		local hover = CreateFrame("Button", nil, detail)
		hover:SetPoint("TOPLEFT", l, "TOPLEFT")
		hover:SetPoint("BOTTOMRIGHT", v, "BOTTOMRIGHT")
		hover:SetScript("OnEnter", function(self)
			if self.itemId and GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if GameTooltip.SetItemByID then
					GameTooltip:SetItemByID(self.itemId)
				else
					GameTooltip:SetHyperlink("item:" .. self.itemId)
				end
				GameTooltip:Show()
			end
		end)
		hover:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		lines[i] = { name = l, value = v, hover = hover }
	end
	function page:Refresh()
		local rows, profs, seenProf = {}, { { value = "all", label = "All professions" } }, {}
		local quotes = ns.allCraftQuotes and ns.allCraftQuotes() or {}
		for _, q in ipairs(quotes) do
			if q.prof and not seenProf[q.prof] then
				seenProf[q.prof] = true
				profs[#profs + 1] = { value = q.prof, label = q.prof }
			end
		end
		table.sort(profs, function(a, b)
			if a.value == "all" or b.value == "all" then
				return a.value == "all" and b.value ~= "all"
			end
			return a.label < b.label
		end)
		if profession and not seenProf[profession] then
			profession = nil -- this character has no such profession
		end
		profPick:SetOptions(profs)
		profPick:Set(profession or "all")
		for _, q in ipairs(quotes) do
			local r = q.recipe
			if not profession or q.prof == profession then
				local profit = held and ns.Crafting.profitHeld(q) or q.profit
				local cost = held and q.cash or q.spend
				rows[#rows + 1] = {
					id = r.id, q = q, name = (r.yield ~= 1 and (r.yield .. "× ") or "") .. itemName(r.output), quality = itemQuality(r.output),
					cost = cost, revenue = q.revenue, profit = profit, gear = q.gear,
					margin = profit and cost and cost > 0 and math.floor(profit / cost * 100 + 0.5) or nil,
				}
			end
		end
		tbl:SetRows(rows, true) -- a click or the ticker keeps the page
		local sel
		for _, r in ipairs(rows) do
			if r.id == chosen then
				sel = r
			end
		end
		sel = sel or rows[1]
		if not sel then
			head:SetText("")
			for _, l in ipairs(lines) do
				l.hover.itemId = nil
				l.name:SetText("")
				l.value:SetText("")
			end
			return
		end
		chosen = sel.id
		head:SetText(sel.name .. Theme.escape(Theme.color.textFaint) .. "  · reagents|r")
		local crafts = 0
		for _, q in ipairs(ns.queueList()) do
			crafts = crafts + q.count
		end
		queued:SetText(crafts > 0 and string.format("In the queue: %d %s. The Buy tab's \"Craft queue\" list buys what is missing.", crafts, crafts == 1 and "craft" or "crafts") or "The queue is empty.")
		for i, l in ipairs(lines) do
			local x = sel.q.lines[i]
			l.hover.itemId = x and x.id
			if x then
				l.name:SetText(x.needed .. "× " .. itemName(x.id) .. (x.owned > 0 and (Theme.escape(Theme.color.textFaint) .. "  (" .. x.owned .. " held)|r") or ""))
				l.value:SetText(x.unit and (UI.layout.amount(x.unit) .. " each, " .. (x.from == "vendor" and "vendor" or "AH")) or "no price")
			else
				l.name:SetText(i == 1 and "No reagents" or "")
				l.value:SetText("")
			end
		end
	end
end

-- This session --------------------------------------------------------------------------------------------------

-- The session as the HUD has it, at full size (design 009, Session module: the rates, the session's
-- loot, the big-drop threshold): refreshed once a second only while the tab shows.
local function buildSessionNow(page)
	local cards = {}
	for i, label in ipairs({ "Time", "Gold an hour", "XP an hour", "Kills an hour" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(160)
		if i == 1 then
			c:SetPoint("TOPLEFT")
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	local lines = {}
	for i, label in ipairs({ "Coin", "Loot, at what it sells for", "XP", "Kills", "Bags" }) do
		local l = UI.Text(page, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -14 - (i - 1) * 20)
		local v = UI.Text(page, "", { size = "sm" })
		v:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 200, -14 - (i - 1) * 20)
		v:SetPoint("RIGHT", page, "RIGHT")
		lines[i] = v
	end
	local tbl = UI.Table(page, {
		{ key = "name", title = "Loot", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "n", title = "Count", width = 60, align = "RIGHT" },
		{ key = "value", title = "Worth", width = 100, align = "RIGHT", text = function(r) return r.value > 0 and UI.layout.amount(r.value) or "—" end },
	}, { pageSize = 5, empty = "Nothing looted this session." })
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -124)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -8)
	note:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local sum = ns.sessionSummary and ns.sessionSummary()
		local faint = Theme.escape(Theme.color.textFaint)
		if not sum then
			for _, c in ipairs(cards) do
				c:Set("—", "")
			end
			for _, l in ipairs(lines) do
				l:SetText("")
			end
			tbl:SetRows({})
			note:SetText("Loot or kill something to start a session. A break of 15 minutes ends it.")
			return
		end
		local r = sum.rates
		cards[1]:Set(Views.duration(math.max(60, sum.elapsed)), sum.ended and "ended" or "running")
		cards[2]:Set(r.rated and UI.layout.money(r.goldPerHour, "gold") or "—", r.rated and "" or "after a minute")
		cards[3]:Set(r.rated and Views.short(r.xpPerHour) or "—", r.dingIn and ("ding in " .. Views.duration(r.dingIn)) or "")
		cards[4]:Set(r.rated and Views.short(r.killsPerHour) or "—", "no combat log")
		lines[1]:SetText(UI.layout.money(sum.coin))
		lines[2]:SetText(UI.layout.money(sum.value) .. (sum.unpriced > 0 and (faint .. string.format("  +%d unpriced", sum.unpriced) .. "|r") or ""))
		lines[3]:SetText(Views.short(sum.xp) .. (r.killsToLevel and (faint .. string.format("  · ~%d kills to level %d", r.killsToLevel, sum.nextLevel or 0) .. "|r") or ""))
		lines[4]:SetText(tostring(sum.kills))
		lines[5]:SetText(sum.bagFree == 0 and "full" or (sum.bagFree .. " free" .. (sum.fullIn and (faint .. "  · full in ~" .. Views.duration(sum.fullIn) .. "|r") or "")))
		local rows = {}
		for i, it in ipairs(sum.ranked) do
			local quality, name = ns.sessionItem(it.id)
			rows[i] = { name = name or ("item " .. it.id), quality = quality or 1, n = it.n, value = it.value }
		end
		tbl:SetRows(rows, true) -- a click or the ticker keeps the page
		note:SetText("A big drop (" .. UI.layout.money(sum.bigDrop, "gold") .. " or more, or rare and better) gets a message and a sound; change it in Settings → General.")
	end
	-- Once a second while shown, and no ticker otherwise.
	local ticker
	local function start(self)
		if C_Timer and C_Timer.NewTicker and not ticker then
			ticker = C_Timer.NewTicker(1, function()
				ns.safely("ui session", self.Refresh, self)
			end)
		end
	end
	page:SetScript("OnShow", start)
	-- A new frame is shown already, so OnShow does not come for the first opening.
	if page:IsShown() then
		start(page)
	end
	page:SetScript("OnHide", function()
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
	end)
end

-- Guide -------------------------------------------------------------------------------------------------------

-- How to use Gold Forever, for players at launch (owner's answer, 2026-10-24): short sections, the keys
-- and the commands. Every command named here exists (the tests check GUIDE_COMMANDS).
local GUIDE = {
	{ "Getting started", "Gold Forever records your characters, money, loot and auction scans for your pages on gold-forever.app, and brings everyone's prices into the game. Install the free companion app (gold-forever.app/companion): it uploads your save when the game writes it and brings prices in every hour. /gf opens this window; the minimap coin does too (right-click switches the look)." },
	{ "At the auction house", "A panel opens beside the auction house. Its tabs follow Blizzard's. Scan runs a full scan when you press Scan now (one every 15 minutes; switch on \"Scan when I open the auction house\" to have it start by itself). Sell lists what your bags can sell, priced by your selling rules against the cheapest listing by someone else; alt-click an item in your bags to choose it, then click Post or press Space. A price far under the market or a vendor's asks for a second press. Your bag items' tooltips say what Sell would ask; the panel's top line says what your bank and mail hold worth posting." },
	{ "Buy and Auctions", "Buy buys from a shopping list: choose a list, click an item to see its listings, and Buy next asks the auction house for a price; a second press buys. Lists are made on the Shopping lists page (Edit lists ›): drop an item on its slot or shift-click it anywhere, then set the most you pay (under market, a fixed price or a share of the market value) and how many you want. Auctions checks your auctions and cancels the most undercut one a press (the item comes back by mail); click one to see its listings." },
	{ "Selling rules and profiles", "The Selling rules page sets how you undercut, the floor and the normal price, and shows what that does to an item worth 10g; \"Rule for\" adds a rule for one item or a whole category (Rule › on the Sell tab opens it for the item in view). A sale profile (a GFP1 string, made at gold-forever.app/me/lists or shared by others) prices the items it names: keep so many, undercut, a fixed price or a point in the supply." },
	{ "Crafting", "The Crafting page lists your recipes by profit; \"I have these\" counts what you hold at no cost. Queue crafts there or on the strip beside the profession window, and the Buy tab's \"Craft queue\" list buys only what is missing." },
	{ "While you play", "The session HUD shows gold, XP and kills an hour; click it for the session. Big drops and rares get a message. The mail helper beside the mailbox opens auction mail a batch a press. Settings → Modules switches any part off; what the save records stays the same." },
	{ "Discord", "Add a Discord webhook at gold-forever.app/settings, then switch \"Announce dings\" on in Settings → Discord for the character you play: each level-up posts a picture and a public page." },
}
local GUIDE_COMMANDS = {
	{ "/gf", "this window (and /gf help: every command)" }, { "/gf hud", "the session HUD" }, { "/gf ah", "the auction panel" },
	{ "/gf look arcane", "a look (web, classic, arcane)" }, { "/gf accent #2fd1a8", "an accent colour" }, { "/gf dings on", "Discord dings" },
	{ "/gf scan", "a full scan at the auction house" }, { "/gf welcome", "the first-run card" }, { "/gf prices", "the prices file" },
}
ns.GUIDE_COMMANDS = GUIDE_COMMANDS

local function buildGuide(page)
	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetAllPoints()
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(680, 900)
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
	for _, section in ipairs(GUIDE) do
		local h = UI.Text(body, Theme.skin.titleCaps and string.upper(section[1]) or section[1], { size = "md", medium = true, tone = "accent" })
		h:SetPoint("TOPLEFT", 0, y)
		local t = UI.Text(body, section[2], { size = "sm", tone = "muted", wrap = true })
		t:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
		t:SetWidth(660)
		y = y - 26 - math.max(36, (t:GetStringHeight() or 36)) - 14
	end
	local h = UI.Text(body, Theme.skin.titleCaps and "COMMANDS" or "Commands", { size = "md", medium = true, tone = "accent" })
	h:SetPoint("TOPLEFT", 0, y)
	y = y - 24
	for _, c in ipairs(GUIDE_COMMANDS) do
		local k = UI.Text(body, c[1], { size = "sm" })
		k:SetPoint("TOPLEFT", 0, y)
		local v = UI.Text(body, c[2], { size = "sm", tone = "muted" })
		v:SetPoint("TOPLEFT", 200, y)
		y = y - 20
	end
	body:SetHeight(-y + 20)
end

-- Characters ----------------------------------------------------------------------------------------------

local function buildCharacters(page)
	local lede = header(page)
	local gold = UI.StatCard(page, "Gold, all characters", "", "")
	gold:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	gold:SetWidth(200)
	local nextUp = UI.StatCard(page, "Play next", "", "")
	nextUp:SetPoint("LEFT", gold, "RIGHT", 12, 0)
	nextUp:SetWidth(220)
	local capped = UI.StatCard(page, "Characters", "", "")
	capped:SetPoint("LEFT", nextUp, "RIGHT", 12, 0)
	capped:SetWidth(200)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Character", flex = 2, text = function(r) return r.online and (r.display .. "  " .. Theme.escape(Theme.color.success) .. "online|r") or r.display end,
			color = function(r) return classColor(r.class) end },
		{ key = "level", title = "Level", width = 56, align = "RIGHT" },
		{ key = "progress", title = "Into level", width = 80, align = "RIGHT", text = function(r) return r.progress and string.format("%d%%", math.floor(r.progress * 100)) or "—" end,
			sort = function(r) return r.level + (r.progress or 0) end },
		{ key = "restedLevels", title = "Rested", width = 90, align = "RIGHT",
			text = function(r) return r.restedLevels and (r.restedLevels >= Views.RESTED_CAP_LEVELS - 0.005 and "full" or string.format("%.2f levels", r.restedLevels)) or "—" end,
			color = function(r) return r.restedLevels and r.restedLevels >= 0.005 and Theme.color.rested or Theme.color.textFaint end },
		{ key = "money", title = "Gold", width = 110, align = "RIGHT", text = function(r) return UI.layout.amount(r.money, "gold") end },
		{ key = "seen", title = "Seen", width = 80, align = "RIGHT", text = function(r) return r.online and "now" or Views.ago(r.seen, ns.now()) end,
			color = function() return Theme.color.textMuted end },
	}, { pageSize = 10, empty = "No characters yet.", sort = sortOf("characters", 4) })
	tbl:SetPoint("TOPLEFT", gold, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local rows, best = Views.characters(ns.db().characters, ns.now(), UnitGUID and UnitGUID("player"))
		local money, top = 0, 0
		for _, r in ipairs(rows) do
			money = money + r.money
			top = top + (r.progress and 0 or 1)
		end
		gold:Set(UI.layout.money(money, "gold"), #rows .. (#rows == 1 and " character" or " characters"))
		if best then
			nextUp:Set(Theme.escape(classColor(best.class)) .. best.display .. "|r", string.format("%.2f levels of rested XP waiting", best.restedLevels))
		else
			nextUp:Set("—", "no one else with rested XP")
		end
		capped:Set(tostring(#rows), top > 0 and (top .. " at the level cap") or "none at the level cap yet")
		tbl:SetRows(rows)
	end
end

-- Levelling -----------------------------------------------------------------------------------------------

local SOURCES = {
	{ key = "kill", label = "Kills", color = Theme.color.chart1 },
	{ key = "quest", label = "Quests", color = Theme.color.chart2 },
	{ key = "boss", label = "Bosses", color = Theme.color.xp },
	{ key = "explore", label = "Exploring", color = Theme.color.success },
	{ key = "other", label = "Other", color = Theme.color.chartMuted },
}

local function buildLevelling(page)
	local lede = header(page)
	local progress = UI.Text(page, "", { size = "sm", tone = "muted" })
	progress:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	local bar = UI.Bar(page, 1, {})
	bar:SetPoint("TOPLEFT", progress, "BOTTOMLEFT", 0, -6)
	bar:SetPoint("RIGHT", page, "RIGHT")
	local pace = UI.StatCard(page, "XP an hour", "", "")
	pace:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
	pace:SetWidth(200)
	local ding = UI.StatCard(page, "Next level", "", "")
	ding:SetPoint("LEFT", pace, "RIGHT", 12, 0)
	ding:SetWidth(200)
	local rested = UI.StatCard(page, "Rested", "", "")
	rested:SetPoint("LEFT", ding, "RIGHT", 12, 0)
	rested:SetWidth(200)
	local mixLabel = UI.Text(page, "", { size = "sm", tone = "muted" })
	mixLabel:SetPoint("TOPLEFT", pace, "BOTTOMLEFT", 0, -12)
	local mix = UI.Bar(page, 1, {}, 6)
	mix:SetPoint("TOPLEFT", mixLabel, "BOTTOMLEFT", 0, -6)
	mix:SetPoint("RIGHT", page, "RIGHT")
	local tbl = UI.Table(page, {
		{ key = "level", title = "Level", width = 60, align = "RIGHT" },
		{ key = "seconds", title = "Time on it", flex = 1, align = "RIGHT", text = function(r) return r.seconds and Views.duration(r.seconds) or Theme.escape(Theme.color.textFaint) .. "—|r" end },
		{ key = "money", title = "Gold when reached", flex = 1, align = "RIGHT", text = function(r) return r.money and UI.layout.amount(r.money) or Theme.escape(Theme.color.textFaint) .. "—|r" end },
		{ key = "reached", title = "Reached", flex = 1, align = "RIGHT", text = function(r) return r.reached and Views.ago(r.reached, ns.now()) or Theme.escape(Theme.color.textFaint) .. "—|r" end,
			color = function() return Theme.color.textMuted end },
	}, { pageSize = 6, empty = "No level-ups recorded yet.", sort = sortOf("levelling", 1) })
	tbl:SetPoint("TOPLEFT", mix, "BOTTOMLEFT", 0, -16)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local me, db = ns.me(), ns.db()
		if not me then
			return
		end
		page:SetTitle(string.format("Levelling · %s%s|r, level %d", Theme.escape(classColor(me.class)), me.name or "?", me.level or 0))
		local lv = Views.levelling(Views.rows(db, "level", me.ref), Views.rows(db, "xp", me.ref), me.ref)
		local xp = me.xp
		if xp and xp.max and xp.max > 0 then
			local have = math.min(xp.rested or 0, xp.max * Views.RESTED_CAP_LEVELS)
			progress:SetText(string.format("%s / %s XP · %d%% · %s rested", count(xp.cur), count(xp.max), math.floor(xp.cur / xp.max * 100), count(have)))
			bar:Set(xp.max, { { value = xp.cur, color = Theme.color.xp }, { value = math.min(have, xp.max - xp.cur), color = Theme.color.rested } })
			local left = xp.max - xp.cur
			ding:Set(lv.perHour and ("in " .. Views.duration(left / lv.perHour * 3600)) or "—", count(left) .. " XP to go" .. (lv.perHour and " at your pace" or ""))
			rested:Set(string.format("%.2f levels", have / xp.max), have > 0 and "kills give double XP until it is used" or "rest in an inn or a city to build it")
		else
			progress:SetText("At the level cap: nothing left to level.")
			bar:Set(1, { { value = 1, color = Theme.color.xp } })
			ding:Set("—", "at the level cap")
			rested:Set("—", "at the level cap")
		end
		pace:Set(lv.perHour and count(lv.perHour) or "—", lv.perHour and Views.duration(lv.playSeconds) .. " of play counted" or "not enough play recorded yet")
		local segments, legend = {}, {}
		for _, s in ipairs(SOURCES) do
			local n = lv.sources[s.key] or 0
			if s.key == "other" then
				for kind, v in pairs(lv.sources) do
					if kind ~= "kill" and kind ~= "quest" and kind ~= "boss" and kind ~= "explore" and kind ~= "other" then
						n = n + v
					end
				end
			end
			if n > 0 then
				segments[#segments + 1] = { value = n, color = s.color }
				legend[#legend + 1] = string.format("%s%s|r %d%%", Theme.escape(s.color), s.label, math.floor(n / lv.xp * 100 + 0.5))
			end
		end
		mixLabel:SetText(lv.xp > 0 and ("XP by source: " .. table.concat(legend, " · ")) or "XP by source: none recorded yet")
		mix:Set(math.max(1, lv.xp), segments)
		tbl:SetRows(lv.levels)
	end
end

-- Ledger ----------------------------------------------------------------------------------------------------

local function buildLedger(page)
	local whose = settings().ledger or "me"
	local tabs = UI.TabBar(page, { { key = "me", label = "This character" }, { key = "all", label = "All characters" } }, function(key)
		whose = key
		settings().ledger = key
		page:Refresh()
	end)
	tabs:SetPoint("TOPLEFT")
	tabs:Select(whose)
	local lede = tabs
	local gained = UI.StatCard(page, "Money in", "", "")
	gained:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	gained:SetWidth(150)
	local spent = UI.StatCard(page, "Money out", "", "")
	spent:SetPoint("LEFT", gained, "RIGHT", 12, 0)
	spent:SetWidth(150)
	local net = UI.StatCard(page, "Net", "", "")
	net:SetPoint("LEFT", spent, "RIGHT", 12, 0)
	net:SetWidth(150)
	local trend = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	trend:SetPoint("TOPLEFT", net, "TOPRIGHT", 12, 0)
	trend:SetPoint("RIGHT", page, "RIGHT")
	trend:SetHeight(72)
	local trendLabel = UI.Text(trend, "NET A DAY", { size = "xs", tone = "muted" })
	trendLabel:SetPoint("TOPLEFT", 12, -10)
	local spark = UI.Sparkline(trend, {}, Theme.color.accent)
	spark:SetPoint("TOPLEFT", trendLabel, "BOTTOMLEFT", 0, -8)
	spark:SetPoint("BOTTOMRIGHT", -12, 10)
	local tbl = UI.Table(page, {
		{ key = "label", title = "Source", flex = 2 },
		{ key = "n", title = "Times", width = 60, align = "RIGHT" },
		{ key = "gained", title = "In", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.gained) end },
		{ key = "spent", title = "Out", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.spent) end },
		{ key = "net", title = "Net", width = 110, align = "RIGHT", text = function(r) return UI.layout.amount(r.net) end },
	}, { pageSize = 8, empty = "No money has moved yet.", sort = sortOf("ledger", 5) })
	tbl:SetPoint("TOPLEFT", gained, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local db, me, now = ns.db(), ns.me(), ns.now()
		local ref = whose == "me" and me and me.ref or nil
		local from = now - LEDGER_DAYS * 86400
		local ledger = Views.ledger(Views.rows(db, "money", ref, from), Views.rows(db, "flight"), ref, from, Encode.day)
		gained:Set(UI.layout.money(ledger.gained, "gold"), "last " .. LEDGER_DAYS .. " days")
		spent:Set(UI.layout.money(ledger.spent, "gold"), "last " .. LEDGER_DAYS .. " days")
		net:Set(UI.layout.money(ledger.net, "gold"), ledger.net >= 0 and "ahead" or "behind")
		local days = {}
		for i = LEDGER_DAYS - 1, 0, -1 do
			days[#days + 1] = ledger.days[Encode.day(now - i * 86400)] or 0
		end
		spark:Set(days)
		tbl:SetRows(ledger.categories)
	end
end

-- Mobs ---------------------------------------------------------------------------------------------------

local function buildMobs(page)
	local lede = header(page)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Mob", flex = 2 },
		{ key = "loots", title = "Looted", width = 70, align = "RIGHT" },
		{ key = "coin", title = "Coin a loot", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.coin) end, sort = function(r) return r.coin end },
		{ key = "value", title = "A loot", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.value) end, sort = function(r) return r.value end },
	}, { pageSize = 13, empty = "No loot recorded yet.", sort = sortOf("mobs", 4) })
	tbl:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local mobs, worth = ns.mobStats(function()
			if page:IsShown() then
				page:Refresh()
			end
		end)
		if not mobs then
			tbl:SetRows({})
			tbl.footer:SetText("Counting the loot…")
			return
		end
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
	-- Filters: whose, where, how good, and a search; the totals follow them (Views.inventory).
	local filter = { query = "" }
	local QUALITY = { { value = 0, label = "Any quality" }, { value = 1, label = "White and better" }, { value = 2, label = "Green and better" }, { value = 3, label = "Blue and better" } }
	local PLACE = { { value = "all", label = "Bags, bank, mail" }, { value = "bags", label = "Bags" }, { value = "bank", label = "Bank" }, { value = "mail", label = "Mail" },
		{ value = "gear", label = "Equipped" } }
	local function chars()
		local out = { { value = "all", label = "All characters" } }
		for guid, c in pairs(ns.db().characters or {}) do
			out[#out + 1] = { value = guid, label = c.name or "?" }
		end
		return out
	end
	local refresh = function()
		if page.Refresh then
			page:Refresh()
		end
	end
	local who = UI.Dropdown(page, chars(), "all", function(v)
		filter.char = v ~= "all" and v or nil
		refresh()
	end)
	who:SetPoint("TOPLEFT")
	who:SetWidth(150)
	local where = UI.Dropdown(page, PLACE, "all", function(v)
		filter.place = v ~= "all" and v or nil
		refresh()
	end)
	where:SetPoint("LEFT", who, "RIGHT", 8, 0)
	where:SetWidth(140)
	local quality = UI.Dropdown(page, QUALITY, 0, function(v)
		filter.quality = v > 0 and v or nil
		refresh()
	end)
	quality:SetPoint("LEFT", where, "RIGHT", 8, 0)
	quality:SetWidth(150)
	local search = UI.SearchBox(page, "Search items…", function(text)
		filter.query = string.lower(text)
		refresh()
	end)
	search:SetPoint("TOPRIGHT")
	search:SetPoint("LEFT", quality, "RIGHT", 8, 0)
	-- Four cards across the page; the fourth holds the soulbound switch (manual test run 001: the switch
	-- beside the cards looked out of place).
	local W = (page:GetWidth() and page:GetWidth() > 0) and page:GetWidth() or 708
	local cardW = math.floor((W - 36) / 4)
	local cards = {}
	for i, label in ipairs({ "Worth", "Items", "Units", "Soulbound" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(cardW)
		if i == 1 then
			c:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -12)
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	-- Leave out: soulbound units hidden (they count at a vendor's price otherwise).
	local tradeable = UI.Switch(cards[4], false, function(on)
		filter.tradeable = on or nil
		refresh()
	end)
	tradeable:SetPoint("TOPLEFT", cards[4].label, "BOTTOMLEFT", 0, -10)
	local tradeableLabel = UI.Text(cards[4], "Leave out", { size = "sm", tone = "muted" })
	tradeableLabel:SetPoint("LEFT", tradeable, "RIGHT", 8, 0)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 2, color = function(r) return Theme.quality[r.quality] or Theme.color.text end,
			text = function(r)
				return r.name .. (r.bound > 0 and (Theme.escape(Theme.color.textFaint) .. (r.bound == r.held and "  bound" or ("  " .. r.bound .. " bound")) .. "|r") or "")
			end },
		{ key = "held", title = "Held", width = 60, align = "RIGHT" },
		{ key = "where", title = "Where", flex = 2, color = function() return Theme.color.textMuted end, tooltip = function(r) return r.holders end },
		{ key = "value", title = "Worth", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.value, "silver") end, sort = function(r) return r.value end },
	}, {
		pageSize = 9,
		empty = "Nothing matches.",
		sort = sortOf("inventory", 4),
		itemId = function(r) return r.id end,
		-- At the auction house, a click chooses the item in Post.
		onRowClick = function(r)
			if ns.auctionChoose then
				ns.auctionChoose(r.id)
			end
		end,
	})
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local rows, totals = Views.inventory(ns.db().characters, Encode.parseItems, function(id)
			if ns.price then
				return ns.price.worth(id)
			end
		end, itemQuality, itemName, filter, function(id)
			return ns.price and ns.price.vendor(id)
		end)
		cards[1]:Set(UI.layout.money(totals.worth, "gold"), filter.place == "gear" and "equipped: not counted" or "bound at vendor price")
		cards[4]:Set("", "") -- the switch stands where a value would
		cards[2]:Set(tostring(totals.items), "different items")
		cards[3]:Set(tostring(totals.units), "in all")
		tbl:SetRows(rows)
	end
	page.setFilter = function(f)
		filter = f
		page:Refresh()
	end
end

-- Settings ------------------------------------------------------------------------------------------------

local isRetail = ns.Realms and ns.Realms.isRetail and ns.Realms.isRetail(select(4, GetBuildInfo()))

-- A card of settings in two columns: a small-caps title over it, each row its label on the left of its
-- half and its control on the right. rows = { { side = 0|1, label, make = function(parent) -> control,
-- full = true for a control as wide as the half's right part } }. Returns the card.
local function settingsCard(page, title, y, rows)
	local label = UI.Text(page, string.upper(title), { size = "xs", medium = true, tone = "faint" })
	label:SetPoint("TOPLEFT", 0, y)
	local count = 0
	for _, r in ipairs(rows) do
		count = math.max(count, (r.row or 0) + 1)
	end
	local card = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	card:SetPoint("TOPLEFT", 0, y - 18)
	card:SetPoint("RIGHT", page, "RIGHT")
	card:SetHeight(count * 50 + 8)
	local split = UI.solid(card, "BORDER", Theme.color.border)
	split:SetPoint("TOP", 0, -10)
	split:SetSize(UI.pixel(), count * 50 - 12)
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

local function buildSettings(page)
	local window = settings()
	local tabs = UI.TabBar(page, { { key = "general", label = "General" }, { key = "modules", label = "Modules" }, { key = "discord", label = "Discord" }, { key = "looks", label = "Looks" } }, function(key)
		page.ensure(key)
		page.general:SetShown(key == "general")
		page.modules:SetShown(key == "modules")
		page.discord:SetShown(key == "discord")
		page.looks:SetShown(key == "looks")
		if key == "discord" then
			page.discord:Refresh()
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
	page.discord = CreateFrame("Frame", nil, page)
	page.discord:SetAllPoints(page.general)
	page.modules = CreateFrame("Frame", nil, page)
	page.modules:SetAllPoints(page.general)
	page.modules:Hide()
	page.discord:Hide()

	local appraiser = ns.settings("appraiser", { shown = true })
	local advisor = ns.settings("advisor", { shown = true })
	local rares = ns.settings("rares", { announce = true, mark = true })
	local minimap = ns.settings("minimap", { angle = 225, hidden = false })
	-- Each tab drawn the first time it is chosen (General when the page opens).
	local fills = {}
	fills.general = function()
		-- General: only settings the addon has, each changed at once.
		local g = page.general
		local lookOptions = {}
		for _, name in ipairs(Theme.order) do
			lookOptions[#lookOptions + 1] = { value = name, label = Theme.skins[name].label }
		end
		settingsCard(g, "Display", 0, {
			{ side = 0, row = 0, label = "Look", full = true, make = function(cell)
				return UI.Dropdown(cell, lookOptions, Theme.skin.name, function(v)
					ns.commands.look(v)
				end)
			end },
			{ side = 0, row = 1, label = "Accent colour", make = function(cell)
				local row = CreateFrame("Frame", nil, cell)
				row:SetSize(#Theme.accents * 30 - 6, 24)
				for k, a in ipairs(Theme.accents) do
					local sw = UI.Swatch(row, a.hex, function()
						ns.commands.accent(window.accent == a.hex and "" or a.hex)
					end)
					sw:SetPoint("LEFT", (k - 1) * 30, 0)
					sw:SetOn(window.accent == a.hex)
				end
				return row
			end },
			{ side = 1, row = 0, label = "Minimap button", make = function(cell)
				return UI.Switch(cell, not minimap.hidden, function(on)
					minimap.hidden = not on
					if ns.refreshMinimap then
						ns.refreshMinimap()
					end
				end)
			end },
			{ side = 1, row = 1, label = "Window size", full = true, make = function(cell)
				return UI.Slider(cell, 70, 130, 5, math.floor((window.scale or 1) * 100 + 0.5), function(v)
					window.scale = v / 100
					page:GetParent():GetParent():SetScale(window.scale)
				end, function(v)
					return v .. "%"
				end, { onRelease = true })
			end },
		})
		settingsCard(g, "Alerts", -146, {
			{ side = 0, row = 0, label = "Hide the HUD in combat", make = function(cell)
				return UI.Switch(cell, appraiser.hideInCombat, function(on)
					appraiser.hideInCombat = on
				end)
			end },
			{ side = 0, row = 1, label = "Mark rares with a skull", make = function(cell)
				local sw = UI.Switch(cell, rares.mark, function(on)
					rares.mark = on
				end)
				if isRetail then
					sw:Disable()
					sw:SetAlpha(0.5)
				end
				return sw
			end },
			{ side = 1, row = 1, label = "Tell my party about rares", make = function(cell)
			local sw = UI.Switch(cell, rares.party == true, function(on)
				rares.party = on
			end)
			if isRetail then
				sw:Disable()
				sw:SetAlpha(0.5)
			end
			return sw
		end },
		{ side = 1, row = 0, label = "Big drop alert", full = true, make = function(cell)
				return UI.Slider(cell, 0, 50, 1, math.floor((appraiser.bigDrop or ns.BIG_DROP or 10000) / 10000), function(v)
					appraiser.bigDrop = v * 10000
				end, function(v)
					return v == 0 and "rares" or (v .. "g")
				end)
			end },
		})
	end
	fills.modules = function()
		-- Modules: each part of the addon a player sees, on or off at once, no reload. The recorder is not
		-- one: what the save records stays the same whatever is switched off.
		local m = page.modules
		local auction = ns.settings("auction", { rule = {}, duration = 2 })
		local prices = ns.settings("prices", { tooltip = true })
		local crafting = ns.settings("crafting", { strip = true })
		local MODULES = {
			{ icon = "timer", name = "Session HUD", blurb = "Gold, XP and kills an hour while you farm or level, and the session's loot.",
				on = function() return appraiser.shown end,
				set = function(on)
					if ns.setHud then
						ns.setHud(on)
					else
						appraiser.shown = on
					end
				end },
			{ icon = "gavel", name = "Auction house panel", blurb = "Scan, buy, sell and your auctions, beside the auction house.",
				on = function() return not auction.hidden end,
				set = function(on) auction.hidden = not on end },
			{ icon = "tag", name = "Prices in tooltips", blurb = "Everyone's price, or your own scan's, under every item.",
				on = function() return prices.tooltip ~= false end,
				set = function(on) prices.tooltip = on end },
			{ icon = "users", name = "Held counts in tooltips", blurb = "How many each of your characters holds, in bags, bank and mail.",
				on = function() return prices.held ~= false end,
				set = function(on) prices.held = on end },
			{ icon = "backpack", name = "Bag advice at vendors", blurb = "What to sell, keep or post when a vendor opens.",
				on = function() return advisor.shown end,
				set = function(on) advisor.shown = on end },
			{ icon = "search", name = "Deals after a scan", blurb = "One chat line naming the list items listed at or under your price.",
			on = function() return ns.settings("auction", { rule = {}, duration = 2 }).dealsAlert ~= false end,
			set = function(on) ns.settings("auction", { rule = {}, duration = 2 }).dealsAlert = on end },
		{ icon = "package", name = "Mail helper", blurb = "Beside the mailbox: open all the auction house's mail in one press.",
			on = function() return ns.settings("mail", { helper = true }).helper ~= false end,
			set = function(on) ns.settings("mail", { helper = true }).helper = on end },
		{ icon = "flask-conical", name = "Crafting strip", blurb = "Beside the profession window: a recipe's cost, sale, profit and what to buy.",
				on = function() return crafting.strip ~= false end,
				set = function(on) crafting.strip = on end },
			{ icon = "skull", name = "Rare alerts", blurb = isRetail and "Off on retail: its cities are full of markers the alert took for rares." or "A message and a sound when a rare is near.",
				on = function() return rares.announce end,
				set = function(on) rares.announce = on end, disabled = isRetail },
		}
		local list = UI.Panel(m, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
		list:SetPoint("TOPLEFT")
		list:SetPoint("RIGHT", m, "RIGHT")
		-- 38 a row: nine modules and the note fit the page (manual test run 001: at 52 the list ran past it).
		local ROW = 38
		list:SetHeight(#MODULES * ROW + 8)
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
			local sw = UI.Switch(row, mod.on(), function(on)
				mod.set(on)
				icon:SetTone(on and "accent" or "faint")
				name:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
			end)
			sw:SetPoint("RIGHT", -20, 0)
			if mod.disabled then
				sw:Disable()
				sw:SetAlpha(0.5)
			end
		end
		local note = UI.Text(m, "The save records the same whatever is off: the site and the shared prices still get it.", { size = "xs", tone = "faint", wrap = true })
		note:SetPoint("TOPLEFT", list, "BOTTOMLEFT", 0, -8)
		note:SetPoint("RIGHT", m, "RIGHT")
	end
	fills.discord = function()
		-- Discord: dings for the character online. The webhook is added on the site; the switch needs the
		-- companion, which carries the choice there and brings the site's side back.
		local d = page.discord
		local who = (ns.me() and ns.me().name) or (UnitName and UnitName("player")) or "this character"
		local card = UI.Panel(d, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
		card:SetPoint("TOPLEFT")
		card:SetPoint("RIGHT", d, "RIGHT")
		card:SetHeight(76)
		local icon = UI.Icon(card, "trending-up", 20, "accent")
		icon:SetPoint("TOPLEFT", 20, -18)
		local label = UI.Text(card, "Announce dings on Discord for " .. who, { size = "md", medium = true })
		label:SetPoint("TOPLEFT", 54, -18)
		local hint = UI.Text(card, "", { size = "xs", tone = "faint", wrap = true })
		hint:SetPoint("TOPLEFT", label, "BOTTOMLEFT", 0, -6)
		hint:SetPoint("RIGHT", card, "RIGHT", -90, 0)
		local switch
		switch = UI.Switch(card, false, function(on)
			ns.Dings.set(on)
			d:Refresh()
		end)
		switch:SetPoint("RIGHT", -20, 0)
		local about = UI.Text(d, "A ding posts a picture and a link to a public page with this character's name, realm, class, the level's time, zones, kills, gold and route. The webhook, and which other characters post, are set at gold-forever.app/settings.", { size = "xs", tone = "faint", wrap = true })
		about:SetPoint("TOPLEFT", card, "BOTTOMLEFT", 0, -14)
		about:SetPoint("RIGHT", d, "RIGHT")
		function d:Refresh()
			local state = ns.Dings.current()
			switch:Set(state.on)
			local can = ns.Dings.changeable(state)
			if can then
				switch:Enable()
			else
				switch:Disable()
			end
			switch:SetAlpha(can and 1 or 0.5)
			hint:SetText(ns.Dings.hint(state))
		end
		d:Refresh()
	end
	fills.looks = function()
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
	function page.ensure(key)
		local f = page[key]
		if f and not f.built then
			f.built = true
			fills[key]()
		end
	end
	page.ensure("general")
end

-- The window ----------------------------------------------------------------------------------------------

-- One window per look and accent, built the first time it opens: frames cannot be restyled in place,
-- and switching should not need a /reload. All share the saved position, page, scale and sorts.
local windows = {}

-- A page of tabs (design 009 decision 2, settled: the old pages folded into fewer rows, each a tab):
-- underline tabs at the top, each tab's page built the first time it is shown, the tab kept per page.
local function tabbed(key, tabs)
	return function(page)
		local store = settings()
		store.tabs = store.tabs or {}
		local bar = UI.TabBar(page, tabs, function(k)
			page:SelectTab(k)
		end, { variant = "underline" })
		bar:SetPoint("TOPLEFT")
		bar:SetPoint("TOPRIGHT")
		local subs = {}
		function page:SelectTab(k)
			local def
			for _, t in ipairs(tabs) do
				if t.key == k then
					def = t
				end
			end
			def = def or tabs[1]
			for _, f in pairs(subs) do
				f:Hide()
			end
			local sub = subs[def.key]
			if not sub then
				sub = CreateFrame("Frame", nil, page)
				sub:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -14)
				sub:SetPoint("BOTTOMRIGHT")
				-- A tab can name the page more closely (whose levelling it shows), as a page can.
				function sub.SetTitle(_, text)
					if page.SetTitle then
						page:SetTitle(text)
					end
				end
				ns.safely("ui " .. def.key, def.build, sub)
				subs[def.key] = sub
			end
			sub:Show()
			if page.SetTitle and page.title then
				page:SetTitle(page.title) -- a tab that names the page more closely sets it again on refresh
			end
			bar:Select(def.key)
			store.tabs[key] = def.key
			self.tab = def.key
			if sub.Refresh then
				ns.safely("ui " .. def.key, sub.Refresh, sub)
			end
		end
		function page:Refresh()
			self:SelectTab(self.tab or store.tabs[key])
		end
		-- The window refreshes a page right after building it, which shows this tab.
		page.tab = store.tabs[key] or tabs[1].key
	end
end

-- The tabbed pages' tabs; the sidebar's search finds a page by a tab's name too.
local LEDGER_TABS = {
	{ key = "money", label = "Money", build = buildLedger },
	{ key = "characters", label = "Characters", build = buildCharacters },
	{ key = "inventory", label = "Inventory", build = buildInventory },
	{ key = "sales", label = "Auction sales", build = buildSales },
}
local SESSION_TABS = {
	{ key = "now", label = "This session", build = buildSessionNow },
	{ key = "levelling", label = "Levelling", build = buildLevelling },
	{ key = "mobs", label = "Mobs", build = buildMobs },
}
local PAGES = {
	{ key = "home", label = "Home", icon = "coins", group = "Overview", build = buildHome, title = "Home",
		lede = "Your next moves, from everyone's prices and your own bags." },
	{ key = "ledger", label = "Ledger", icon = "book-open", group = "Overview", title = "Ledger",
		lede = "Where your money went and came from, your characters, and everything they hold.",
		tabs = LEDGER_TABS, build = tabbed("ledger", LEDGER_TABS) },
	{ key = "crafting", label = "Crafting", icon = "flask-conical", group = "Trading", build = buildCrafting, title = "Crafting",
		lede = "Your recipes by profit: reagents at the cheaper of auction house and vendor, the item at its price after the cut." },
	{ key = "lists", label = "Shopping lists", icon = "backpack", group = "Trading", title = "Shopping lists",
		lede = "What the auction panel's Buy tab buys: your lists, their items, the most you pay and how many.",
		build = function(page)
			ns.buildShoppingLists(page)
		end },
	{ key = "rules", label = "Selling rules", icon = "tag", group = "Trading", title = "Selling rules",
		lede = "How the auction panel's Sell tab prices your items: by these rules, or a sale profile.",
		build = function(page)
			ns.buildSellingRules(page)
		end },
	{ key = "session", label = "Session", icon = "timer", group = "Play", title = "Session",
		lede = "Levelling at this character's pace, and every mob by what a loot of it is worth. The HUD shows the session live.",
		tabs = SESSION_TABS, build = tabbed("session", SESSION_TABS) },
	{ key = "rares", label = "Rares", icon = "skull", group = "Play", build = buildRares, title = "Rares",
		lede = "Every rare your characters have seen, where and when last, and what a loot of one has been worth." },
	{ key = "companion", label = "Companion", icon = "rotate-ccw", group = "Addon", build = buildCompanion, title = "Companion",
		lede = "Everyone's prices in the game, and your save on the site: what the companion app has brought in." },
	{ key = "settings", label = "Settings", icon = "settings", group = "Addon", build = buildSettings, title = "Settings",
		lede = "How Gold Forever looks and behaves. Changes apply at once." },
	{ key = "guide", label = "Guide", icon = "circle-help", group = "Addon", build = buildGuide, title = "Guide",
		lede = "How to use Gold Forever: the auction house panel, crafting, the session, Discord, and the commands." },
	{ key = "design", label = "Design system", icon = "palette", group = "Addon", build = buildDesign, title = "Design system",
		lede = "Every part of the window kit with example data, in the look in use." },
}

-- The pages that became tabs, by their old keys: /gf ui levelling, a saved page, a card's link.
local FOLDED = {
	characters = { "ledger", "characters" }, inventory = { "ledger", "inventory" }, money = { "ledger", "money" },
	sales = { "ledger", "sales" },
	levelling = { "session", "levelling" }, mobs = { "session", "mobs" }, now = { "session", "now" },
}

-- Opens a page, or the page and tab an old key names.
local function openIn(window, key)
	local f = FOLDED[key]
	if f then
		settings().tabs = settings().tabs or {}
		settings().tabs[f[1]] = f[2]
		-- The page shows this tab as it opens, rather than refreshing the last one first.
		local page = window.pages[f[1]]
		if page then
			page.tab = f[2]
		end
		window:SelectPage(f[1])
		page = window.pages[f[1]]
		if page and page.SelectTab and page.tab ~= f[2] then
			page:SelectTab(f[2])
		end
	else
		window:SelectPage(key)
	end
end
ns.openPage = function(key)
	if ns.commands.ui then
		ns.commands.ui(key)
	end
end

local function look()
	local name = settings().look
	return Theme.skins[name] and name or "web"
end

-- The accent panels draw in this session. Each new colour draws every window and panel anew (frames are
-- never freed), so a session draws in at most MAX_ACCENTS of them; one more is saved and shows after a
-- /reload. Enough for every swatch in Settings and the look's own (manual test run 001: the fourth
-- swatch clicked waited for a reload); only typed /gf accent colours past those wait.
local MAX_ACCENTS = #Theme.accents + 1
local drawnAccents, drawnCount, sessionAccent, accentRead = {}, 0, nil, false
local function accent()
	if not accentRead then
		accentRead = true
		sessionAccent = settings().accent
		drawnAccents[sessionAccent or "none"], drawnCount = true, 1
	end
	return sessionAccent
end

-- The look and accent the player set, for panels outside the window (the session HUD) to draw in.
function ns.applyLook()
	Theme.apply(look(), accent())
end

local function windowFor(name)
	-- A page saved before the pages were folded opens as its tab.
	local folded = FOLDED[settings().page or ""]
	if folded then
		settings().tabs = settings().tabs or {}
		settings().tabs[folded[1]] = folded[2]
		settings().page = folded[1]
	end
	local hex = accent()
	Theme.apply(name, hex)
	local key = name .. (hex and string.gsub(hex, "#", "_") or "")
	if not windows[key] then
		windows[key] = UI.Window(key == "web" and "GoldForeverWindow" or "GoldForeverWindow_" .. key, "Gold Forever", PAGES, settings(), {
			version = ns.VERSION,
			look = Theme.skins[name].label,
		})
	end
	return windows[key]
end

local function shown()
	for _, w in pairs(windows) do
		if w:IsShown() then
			return w
		end
	end
end

-- For the smoke test: the window open now.
ns.hubWindow = function()
	return shown()
end

ns.commands.ui = function(page)
	local open = shown()
	if open and (page == nil or page == "") then
		open:Hide()
		return
	end
	local window = windowFor(look())
	window:Restore()
	window:Show()
	-- In front every time, an open window too (manual test run 001: Rule › left it under the panel).
	window:Raise()
	if page and page ~= "" then
		openIn(window, page)
	end
end

-- An open window rebuilt in the look and accent now set, on the same page.
local function reopen()
	local open = shown()
	if open then
		open:Hide()
		local window = windowFor(look())
		window:Restore()
		window:Show()
		window:SelectPage(settings().page or PAGES[1].key)
	else
		Theme.apply(look(), accent())
	end
	if ns.lookChanged then
		ns.lookChanged()
	end
end

-- "/gf look web", "/gf look classic" or "/gf look arcane": the window's look, kept in the settings. An
-- open window switches in place, on the same page.
ns.commands.look = function(name)
	name = string.lower(name or "")
	if not Theme.skins[name] then
		print(string.format("Gold Forever: the look is %s. /gf look %s", Theme.skins[look()].label, table.concat(Theme.order, " · /gf look ")))
		return
	end
	settings().look = name
	reopen()
end

-- "/gf accent #2fd1a8" puts an accent colour over the look; "/gf accent" goes back to the look's own.
ns.commands.accent = function(hex)
	hex = string.lower(hex or "")
	if hex ~= "" and not string.match(hex, "^#%x%x%x%x%x%x$") then
		print("Gold Forever: /gf accent #rrggbb, or /gf accent alone for the look's own colour.")
		return
	end
	local chosen = hex ~= "" and hex or nil
	settings().accent = chosen
	accent()
	if not drawnAccents[chosen or "none"] then
		if drawnCount >= MAX_ACCENTS then
			ns.say("accent saved; it shows after /reload (each new colour draws every panel again, which stays until a reload).")
			return
		end
		drawnAccents[chosen or "none"], drawnCount = true, drawnCount + 1
	end
	sessionAccent = chosen
	reopen()
end
