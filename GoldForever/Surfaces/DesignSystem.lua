-- Gold Forever: the hub's Design system page: every UI kit component with example data, as the web
-- app's Design system page does.

local _, ns = ...
local L = ns.L
local Theme, UI = ns.Theme, ns.UI
local Kit = ns.HubKit
local heading = Kit.heading

local function buildDesign(page)
	local body = Kit.scrollBody(page, 640, 1240)
	local y = 0

	y = heading(body, L["Colours"], y)
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
		local t = UI.Text(body, ({ L["Poor"], L["Common"], L["Uncommon"], L["Rare"], L["Epic"], L["Legendary"] })[q + 1], { tone = Theme.quality[q] })
		t:SetPoint("TOPLEFT", q * 90, y)
	end
	y = y - 30

	y = heading(body, L["Text"], y)
	local sizes = { { "xxl", L["A page title"] }, { "xl", L["A stat's value"] }, { "lg", L["A section"] }, { "md", L["Body text, the default"] }, { "sm", L["Table cells"] }, { "xs", L["LABELS AND HINTS"] } }
	for _, s in ipairs(sizes) do
		local t = UI.Text(body, s[2], { size = s[1] })
		t:SetPoint("TOPLEFT", 0, y)
		local tag = UI.Text(body, s[1] .. " · " .. Theme.text[s[1]] .. " pt", { size = "xs", tone = "faint" })
		tag:SetPoint("LEFT", t, "RIGHT", 12, 0)
		y = y - (Theme.text[s[1]] + 10)
	end
	local tones = UI.Text(body, string.format(L["Text in three tones: %smuted|r, %sfaint|r, %saccent|r."], Theme.escape(Theme.color.textMuted), Theme.escape(Theme.color.textFaint), Theme.escape(Theme.color.accent)))
	tones:SetPoint("TOPLEFT", 0, y)
	y = y - 34

	y = heading(body, L["Buttons, badges, tabs, search"], y)
	local primary = UI.Button(body, L["Scan the auction house"], nil, { kind = "primary" })
	primary:SetPoint("TOPLEFT", 0, y)
	local default = UI.Button(body, L["Open the bags"])
	default:SetPoint("LEFT", primary, "RIGHT", 8, 0)
	local ghost = UI.Button(body, L["Hide"], nil, { kind = "ghost" })
	ghost:SetPoint("LEFT", default, "RIGHT", 8, 0)
	local x = 0
	for _, b in ipairs({ { L["sold"], Theme.color.success }, { L["learn · 1s"], Theme.color.warning }, { L["rare"], Theme.color.info }, { L["expired"], Theme.color.danger } }) do
		local badge = UI.Badge(body, b[1], b[2])
		badge:SetPoint("TOPLEFT", 380 + x, y - 4)
		x = x + badge:GetWidth() + 6
	end
	y = y - 40
	local tabs = UI.TabBar(body, { { key = "learned", label = L["Learned"] }, { key = "unlearned", label = L["Unlearned"] }, { key = "skillup", label = L["Skill up"] } })
	tabs:SetPoint("TOPLEFT", 0, y)
	tabs:SetWidth(320)
	local search = UI.SearchBox(body, L["Search items..."])
	search:SetPoint("TOPLEFT", 340, y - 2)
	search:SetWidth(240)
	y = y - 48

	y = heading(body, L["Stat cards and money"], y)
	local cards = {
		{ L["Gold, all characters"], UI.layout.money(1014420, "gold"), L["5 characters"] },
		{ L["Worth"], UI.layout.money(27098), L["at the better of auction and vendor"] },
		{ L["Play next"], "Jemmou Firereaver", L["0.3 levels of rested XP waiting"] },
	}
	for i, c in ipairs(cards) do
		local card = UI.StatCard(body, c[1], c[2], c[3])
		card:SetSize(200, 72)
		card:SetPoint("TOPLEFT", (i - 1) * 212, y)
	end
	y = y - 84
	local money = UI.Text(body, string.format(L["Money: %s · %s · %s · %s · as gold: %s"], UI.layout.money(0), UI.layout.money(45), UI.layout.money(1484), UI.layout.money(1014420), UI.layout.money(1014420, "gold")))
	money:SetPoint("TOPLEFT", 0, y)
	y = y - 34

	y = heading(body, L["Bars and a sparkline"], y)
	local xpLabel = UI.Text(body, L["Level progress and rested"], { size = "sm", tone = "muted" })
	xpLabel:SetPoint("TOPLEFT", 0, y)
	local xp = UI.Bar(body, 100, { { value = 67, color = Theme.color.xp }, { value = 18, color = Theme.color.rested } })
	xp:SetPoint("TOPLEFT", 0, y - 18)
	xp:SetWidth(300)
	local mixLabel = UI.Text(body, L["XP by source: quests, kills, dungeons"], { size = "sm", tone = "muted" })
	mixLabel:SetPoint("TOPLEFT", 0, y - 36)
	local mix = UI.Bar(body, 100, { { value = 52, color = Theme.color.chart1 }, { value = 38, color = Theme.color.chart2 }, { value = 10, color = Theme.color.xp } }, 6)
	mix:SetPoint("TOPLEFT", 0, y - 54)
	mix:SetWidth(300)
	local spark = UI.Sparkline(body, { 10, 14, 9, 22, 30, 26, 41, 38, 52, 47 })
	spark:SetPoint("TOPLEFT", 340, y - 4)
	spark:SetSize(240, 56)
	y = y - 80

	y = heading(body, L["Table"], y)
	local example = UI.Table(body, {
		{ key = "mob", title = L["Mob"], flex = 2 },
		{ key = "loots", title = L["Looted"], width = 70, align = "RIGHT" },
		{ key = "value", title = L["A loot"], width = 90, align = "RIGHT", text = function(r) return UI.layout.money(r.value) end, sort = function(r) return r.value end },
		{ key = "gph", title = L["Gold / hour"], width = 100, align = "RIGHT", text = function(r) return UI.layout.money(r.gph, "gold") end, sort = function(r) return r.gph end },
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

	y = heading(body, L["Empty state"], y)
	local empty = UI.EmptyState(body, L["Nothing held yet"], L["Upload a save: bags, bank and mail are read as the addon sees them."])
	empty:SetPoint("TOPLEFT", 0, y)
	empty:SetPoint("RIGHT", body, "RIGHT")
	body:SetHeight(-y + 100)
end

ns.hubPages.design = buildDesign
