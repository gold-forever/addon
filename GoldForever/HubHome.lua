-- Gold Forever: the hub's Home page: the next moves, a gold goal, today's money and the bag items
-- worth most.

local _, ns = ...
local Theme, UI, Encode, Views = ns.Theme, ns.UI, ns.Encode, ns.Views
local Kit = ns.HubKit
local settings, itemName, itemQuality = Kit.settings, Kit.itemName, Kit.itemQuality

-- Every window's Home, kept current while it shows: money as it moves, the bags as they are read (manual
-- test run 001: Home stayed as it was after a fight). A moment's wait gathers a burst of changes into one
-- refresh. Listened for once here, not once a window.
local homes = {}
local homeSoon = ns.throttle("ui home", 2, function()
	for _, page in ipairs(homes) do
		if page:IsVisible() then
			ns.safely("ui home", page.Refresh, page)
		end
	end
end)
ns.on("PLAYER_MONEY", "ui home", homeSoon)
ns.onBagsRead(homeSoon)

-- The next moves, from the save and the prices: scan, sell what the bags hold, the best craft; today's
-- money by where it came from; and the bag items worth most.
local function buildHome(page)
	local W = Kit.pageWidth(page)
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
		Kit.itemTooltip(r)
	end

	homes[#homes + 1] = page

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
		local list, total, unpriced = Views.bagWorth(me and me.bags, Encode.parseItems, function(id)
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
		local gold = 0
		for _, c in pairs(db.characters or {}) do
			gold = gold + (c.money or 0)
		end
		local goal = settings().goal
		if goal then
			local g = Views.goal(now, gold, goal)
			goalText:SetText(string.format("Goal %s: %s now, %d%%%s", UI.layout.money(goal.gold, "gold"), UI.layout.money(gold, "gold"), g.pct,
				g.reached and Theme.escape(Theme.color.success) .. " · reached|r" or g.late and (faint .. " · the date has passed|r")
				or (faint .. string.format(" · %s a day for %d more %s", "|r" .. UI.layout.money(g.perDay, "gold") .. faint, g.daysLeft, g.daysLeft == 1 and "day" or "days") .. "|r")))
			goalBar:Set(100, { { value = g.pct, color = g.reached and Theme.color.success or Theme.color.accent } })
			goalBar:Show()
		else
			goalText:SetText(faint .. "A gold goal: an amount and a date, and Home shows how far there is to go. " .. "|r" .. UI.layout.money(gold, "gold") .. faint .. " across your characters now.|r")
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

ns.hubPages.home = buildHome
