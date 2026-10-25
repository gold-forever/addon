-- Gold Forever: the hub's Crafting page: the recipes the characters know, by profit, and the craft
-- queue.

local _, ns = ...
local Theme, UI, Views = ns.Theme, ns.UI, ns.Views
local Kit = ns.HubKit
local settings, sortOf, itemName, itemQuality = Kit.settings, Kit.sortOf, Kit.itemName, Kit.itemQuality

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
		sort = sortOf("crafting", "profit"),
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
		Kit.itemTooltip(hover)
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
		-- More reagents than lines: the last line says how many more (the queue window lists them all).
		local fits, more = Views.fit(#sel.q.lines, #lines)
		for i, l in ipairs(lines) do
			local x = i <= fits and sel.q.lines[i] or nil
			l.hover.itemId = x and x.id
			if x then
				l.name:SetText(x.needed .. "× " .. itemName(x.id) .. (x.owned > 0 and (Theme.escape(Theme.color.textFaint) .. "  (" .. x.owned .. " held)|r") or ""))
				l.value:SetText(x.unit and (UI.layout.amount(x.unit) .. " each, " .. (x.from == "vendor" and "vendor" or "AH")) or "no price")
			elseif i == fits + 1 and more > 0 then
				l.name:SetText(Theme.escape(Theme.color.textFaint) .. "+" .. more .. " more " .. (more == 1 and "reagent" or "reagents") .. "|r")
				l.value:SetText("")
			else
				l.name:SetText(i == 1 and "No reagents" or "")
				l.value:SetText("")
			end
		end
	end
end

ns.hubPages.crafting = buildCrafting
