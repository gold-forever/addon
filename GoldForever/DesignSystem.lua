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
	}, { pageSize = 12, empty = "No characters yet.", sort = sortOf("characters", 4) })
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
	}, { pageSize = 8, empty = "No level-ups recorded yet.", sort = sortOf("levelling", 1) })
	tbl:SetPoint("TOPLEFT", mix, "BOTTOMLEFT", 0, -16)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local me, db = ns.me(), ns.db()
		if not me then
			return
		end
		page:SetTitle(string.format("Levelling · %s%s|r, level %d", Theme.escape(classColor(me.class)), me.name or "?", me.level or 0))
		local lv = Views.levelling(Views.rows(db, "level"), Views.rows(db, "xp"), me.ref)
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

local LEDGER_DAYS = 14

local function buildLedger(page)
	local whose = settings().ledger or "me"
	local tabs = UI.TabBar(page, { { key = "me", label = "This character" }, { key = "all", label = "All characters" } }, function(key)
		whose = key
		settings().ledger = key
		page:Refresh()
	end, { variant = "underline" })
	tabs:SetPoint("TOPLEFT")
	tabs:SetPoint("TOPRIGHT")
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
	}, { pageSize = 9, empty = "No money has moved yet.", sort = sortOf("ledger", 5) })
	tbl:SetPoint("TOPLEFT", gained, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local db, me, now = ns.db(), ns.me(), ns.now()
		local ref = whose == "me" and me and me.ref or nil
		local from = now - LEDGER_DAYS * 86400
		local ledger = Views.ledger(Views.rows(db, "money"), Views.rows(db, "flight"), ref, from, Encode.day)
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
	}, { pageSize = 16, empty = "No loot recorded yet.", sort = sortOf("mobs", 4) })
	tbl:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
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
	local title = header(page)
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
		{ key = "where", title = "Where", flex = 2, color = function() return Theme.color.textMuted end, tooltip = function(r) return r.holders end },
		{ key = "value", title = "Worth", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.value) end, sort = function(r) return r.value end },
	}, { pageSize = 13, empty = "Nothing matches.", sort = sortOf("inventory", 4) })
	tbl:SetPoint("TOPLEFT", total, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
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
				rows[#rows + 1] = { name = name, quality = itemQuality(id), held = it.held, where = table.concat(it.where, ", "), holders = it.where, value = (unit or 0) * it.held }
				worth = worth + (unit or 0) * it.held
				units = units + it.held
			end
		end
		total:Set(UI.layout.money(worth, "gold"), "at the better of auction and vendor")
		count:Set(tostring(#rows), units .. " units")
		tbl:SetRows(rows)
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
	local tabs = UI.TabBar(page, { { key = "general", label = "General" }, { key = "discord", label = "Discord" }, { key = "looks", label = "Looks" } }, function(key)
		page.general:SetShown(key == "general")
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
	page.discord:Hide()

	-- General: only settings the addon has, each changed at once.
	local g = page.general
	local lookOptions = {}
	for _, name in ipairs(Theme.order) do
		lookOptions[#lookOptions + 1] = { value = name, label = Theme.skins[name].label }
	end
	local appraiser = ns.settings("appraiser", { shown = true })
	local advisor = ns.settings("advisor", { shown = true })
	local shop = ns.settings("shop", { shown = true })
	local rares = ns.settings("rares", { announce = true, mark = true })
	local minimap = ns.settings("minimap", { angle = 225, hidden = false })
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
			end)
		end },
	})
	settingsCard(g, "Panels and alerts", -146, {
		{ side = 0, row = 0, label = "Session HUD", make = function(cell)
			return UI.Switch(cell, appraiser.shown, function(on)
				if on ~= appraiser.shown and ns.commands.appraise then
					ns.commands.appraise()
				end
				appraiser.shown = on
			end)
		end },
		{ side = 0, row = 1, label = "Bag advice at vendors", make = function(cell)
			return UI.Switch(cell, advisor.shown, function(on)
				advisor.shown = on
			end)
		end },
		{ side = 0, row = 2, label = "Craft list at the auction house", make = function(cell)
			return UI.Switch(cell, shop.shown, function(on)
				shop.shown = on
			end)
		end },
		{ side = 0, row = 3, label = "Hide the HUD in combat", make = function(cell)
			return UI.Switch(cell, appraiser.hideInCombat, function(on)
				appraiser.hideInCombat = on
			end)
		end },
		{ side = 1, row = 0, label = "Big drop alert", full = true, make = function(cell)
			return UI.Slider(cell, 0, 50, 1, math.floor((appraiser.bigDrop or ns.BIG_DROP or 10000) / 10000), function(v)
				appraiser.bigDrop = v * 10000
			end, function(v)
				return v == 0 and "rares" or (v .. "g")
			end)
		end },
		{ side = 1, row = 1, label = isRetail and "Announce rares (off on retail)" or "Announce rares", make = function(cell)
			local sw = UI.Switch(cell, rares.announce, function(on)
				rares.announce = on
			end)
			if isRetail then
				sw:Disable()
				sw:SetAlpha(0.5)
			end
			return sw
		end },
		{ side = 1, row = 2, label = "Mark rares with a skull", make = function(cell)
			local sw = UI.Switch(cell, rares.mark, function(on)
				rares.mark = on
			end)
			if isRetail then
				sw:Disable()
				sw:SetAlpha(0.5)
			end
			return sw
		end },
	})

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

-- The window ----------------------------------------------------------------------------------------------

-- One window per look and accent, built the first time it opens: frames cannot be restyled in place,
-- and switching should not need a /reload. All share the saved position, page, scale and sorts.
local windows = {}

local PAGES = {
	{ key = "characters", label = "Characters", icon = "users", group = "Overview", build = buildCharacters, title = "Characters",
		lede = "Every character this save has seen. Rested XP grows while logged out, so it is worked out to now: the one with the most waiting is the one to play next." },
	{ key = "ledger", label = "Ledger", icon = "book-open", group = "Overview", build = buildLedger, title = "Ledger",
		lede = "Where money came from and went, by the window open when it moved, over the last two weeks the save keeps." },
	{ key = "inventory", label = "Inventory", icon = "package", group = "Overview", build = buildInventory, title = "Inventory",
		lede = "Everything your characters hold, in bags, bank and mail, at the better of auction and vendor." },
	{ key = "levelling", label = "Levelling", icon = "trending-up", group = "Play", build = buildLevelling, title = "Levelling",
		lede = "This character, from the last two weeks the save keeps. XP an hour counts the time between gains; a break over ten minutes is left out." },
	{ key = "mobs", label = "Mobs", icon = "skull", group = "Play", build = buildMobs, title = "Mobs, by what a loot is worth",
		lede = "Every mob your characters have looted: how often, and what a loot brought in coin and items, priced as on the web." },
	{ key = "settings", label = "Settings", icon = "settings", group = "Addon", build = buildSettings, title = "Settings",
		lede = "How Gold Forever looks and behaves. Changes apply at once." },
	{ key = "design", label = "Design system", icon = "palette", group = "Addon", build = buildDesign, title = "Design system",
		lede = "Every part of the window kit with example data, in the look in use." },
}

local function look()
	local name = settings().look
	return Theme.skins[name] and name or "web"
end

-- The look and accent the player set, for panels outside the window (the session HUD) to draw in.
function ns.applyLook()
	Theme.apply(look(), settings().accent)
end

local function windowFor(name)
	local accent = settings().accent
	Theme.apply(name, accent)
	local key = name .. (accent and string.gsub(accent, "#", "_") or "")
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

ns.commands.ui = function(page)
	local open = shown()
	if open and (page == nil or page == "") then
		open:Hide()
		return
	end
	local window = windowFor(look())
	window:Restore()
	window:Show()
	if page and page ~= "" then
		window:SelectPage(page)
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
		Theme.apply(look(), settings().accent)
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
	settings().accent = hex ~= "" and hex or nil
	reopen()
end
