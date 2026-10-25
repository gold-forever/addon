-- Gold Forever: the hub's Shopping lists page: the lists Buy shows, made, named, priced and shared.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local settings = ns.auctionSettings
local lists, stamp = ns.Lists.lists, ns.Lists.stamp
local money = ns.Money.auction

-- Shopping lists, a page of the hub (owner's answers, 2026-10-24, manual test run 001: the Buy tab had
-- no way to rename or delete a list or to price an item, and adding needed a click in a field first).
-- Lists at the left (new, rename, delete, import, export); the chosen list's items at the right, added by
-- dropping an item on the slot or shift-clicking it anywhere while the page shows; the chosen item's most
-- per unit (under market, a fixed price or a share of the market value) and how many to hold. The craft
-- queue's list is here too: its items follow the queue, their prices are set here.
local PRICE_MODES = { { value = "market", label = "Under market" }, { value = "fixed", label = "Fixed price" }, { value = "pct", label = "% of market" },
	{ value = "lowest", label = "Lowest, ask over %" } }

local function buildLists(page)
	local s = settings()
	local LEFT = 220
	local chosenItem -- the itemId chosen on the right

	-- Left: the lists.
	local head = UI.Text(page, "LISTS", { size = "xs", medium = true, tone = "faint" })
	head:SetPoint("TOPLEFT")
	local listTable = UI.Table(page, {
		{ key = "name", title = "List", flex = 1, color = function(r) return r.generated and Theme.color.textMuted or Theme.color.text end },
		{ key = "n", title = "Items", width = 44, align = "RIGHT" },
	}, {
		pageSize = 8,
		rowHeight = 24,
		isSelected = function(r) return r.index == s.list end,
		onRowClick = function(r)
			s.list, chosenItem = r.index, nil
			page:Refresh()
		end,
	})
	listTable:SetPoint("TOPLEFT", 0, -18)
	listTable:SetWidth(LEFT)
	local name = UI.SearchBox(page, "Rename the list", nil)
	name:SetPoint("TOPLEFT", listTable, "BOTTOMLEFT", 0, -10)
	name:SetWidth(LEFT)
	local function own()
		local mine, list = lists()
		for i, l in ipairs(mine) do
			if l == list then
				return list, i, mine
			end
		end
		return nil, nil, mine
	end
	local function renameTo(text)
		local list = own()
		text = string.match((string.gsub(text or "", "|", "")), "^%s*(.-)%s*$")
		if list and text ~= "" then
			list.name = string.sub(text, 1, 40)
			stamp(list)
		end
		page:Refresh()
	end
	name:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		renameTo(self:GetText())
	end)
	local newList = UI.Button(page, "New", function()
		local mine = lists()
		mine[#mine + 1] = stamp({ name = "List " .. (#mine + 1), entries = {} })
		s.list, chosenItem = #mine, nil
		page:Refresh()
		name:SetFocus()
		name:HighlightText()
	end, { width = 70, height = 26 })
	newList:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	local delete = UI.Button(page, "Delete", function(self)
		local list, i, mine = own()
		if not list then
			return
		end
		-- A second press deletes (a list can hold many items).
		if self.armed ~= list then
			self.armed = list
			page.note:SetText(Theme.escape(Theme.color.warning) .. "Press Delete again to delete \"" .. list.name .. "\".|r")
			return
		end
		self.armed = nil
		-- Remembered, so the site's copy of it does not bring it back (it is not deleted there).
		if list.id then
			s.removedShared = s.removedShared or {}
			s.removedShared[list.id] = ns.now()
		end
		table.remove(mine, i)
		s.list, chosenItem = math.max(1, i - 1), nil
		page.note:SetText("Deleted.")
		page:Refresh()
	end, { width = 70, height = 26 })
	delete:SetPoint("LEFT", newList, "RIGHT", 5, 0)
	local exportButton, importButton

	-- Right: the chosen list's items.
	local X = LEFT + 24
	local title = UI.Text(page, "", { size = "lg", medium = true })
	title:SetPoint("TOPLEFT", X, 0)
	title:SetPoint("RIGHT", page, "RIGHT", -240, 0)
	local crafting = UI.Button(page, "Open Crafting ›", function()
		ns.openPage("crafting")
	end, { width = 120, height = 24 })
	crafting:SetPoint("TOPRIGHT", 0, 2)
	local queueWindow = UI.Button(page, "Queue window", function()
		ns.openCraftQueue()
	end, { width = 110, height = 24 })
	queueWindow:SetPoint("RIGHT", crafting, "LEFT", -6, 0)
	-- The slot: drop an item on it (or click it holding one), or shift-click an item anywhere.
	local slot = CreateFrame("Button", nil, page)
	slot:SetSize(36, 36)
	slot:SetPoint("TOPLEFT", X, -26)
	UI.surface(slot, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, Theme.skin.radius and 6 or 0)
	local plus = UI.Text(slot, "+", { size = "xl", tone = "faint", align = "CENTER" })
	plus:SetPoint("CENTER", 0, 1)
	local slotLine = UI.Text(page, "Drop an item here, or shift-click one anywhere, to add it.", { size = "xs", tone = "faint", wrap = true })
	slotLine:SetPoint("LEFT", slot, "RIGHT", 10, 0)
	slotLine:SetPoint("RIGHT", page, "RIGHT")
	local items = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "price", title = "At most", width = 110, align = "RIGHT" },
		{ key = "many", title = "How many", width = 80, align = "RIGHT" },
	}, {
		pageSize = 6,
		rowHeight = 24,
		empty = "No items yet.",
		itemId = function(r) return r.itemId end,
		isSelected = function(r) return r.itemId == chosenItem end,
		onRowClick = function(r)
			chosenItem = r.itemId
			page:Refresh()
		end,
	})
	items:SetPoint("TOPLEFT", X, -72)
	items:SetPoint("RIGHT", page, "RIGHT")

	-- The chosen item's settings.
	local edit = CreateFrame("Frame", nil, page)
	edit:SetPoint("TOPLEFT", items, "BOTTOMLEFT", 0, -10)
	edit:SetPoint("RIGHT", page, "RIGHT")
	edit:SetHeight(64)
	local editName = UI.Text(edit, "", { size = "sm", medium = true })
	editName:SetPoint("TOPLEFT")
	local setPrice, amount
	-- A kind chosen without its number yet (Fixed price, % of market): shown, the box waiting for it.
	local pending
	local mode = UI.Dropdown(edit, PRICE_MODES, "market", function(v)
		if v == "market" then
			pending = nil
			setPrice(v, "")
		else
			pending = { id = chosenItem, kind = v }
			page:Refresh()
			amount:SetText("")
			amount:SetFocus()
		end
	end)
	mode:SetPoint("TOPLEFT", 0, -20)
	mode:SetWidth(130)
	amount = UI.SearchBox(edit, "", nil)
	amount:SetPoint("LEFT", mode, "RIGHT", 8, 0)
	amount:SetWidth(90)
	local manyLabel = UI.Text(edit, "How many", { size = "sm", tone = "muted" })
	manyLabel:SetPoint("LEFT", amount, "RIGHT", 14, 0)
	local many = UI.SearchBox(edit, "any", nil)
	many:SetPoint("LEFT", manyLabel, "RIGHT", 8, 0)
	many:SetWidth(60)
	local removeItem = UI.Button(edit, "Remove", function()
		local list = own()
		if not list then
			return
		end
		for i, e in ipairs(list.entries) do
			if e.itemId == chosenItem then
				table.remove(list.entries, i)
				stamp(list)
				break
			end
		end
		chosenItem = nil
		page:Refresh()
	end, { width = 80, height = 26 })
	removeItem:SetPoint("TOPRIGHT", 0, -20)

	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -6)
	page.note:SetPoint("RIGHT", page, "RIGHT")

	-- Import and export, under the lists: one field, the GFL1 string in or out.
	local field = UI.SearchBox(page, "Paste a GFL1 string", nil)
	field:SetMaxLetters(0)
	field:SetPoint("TOPLEFT", newList, "BOTTOMLEFT", 0, -14)
	field:SetWidth(LEFT)
	importButton = UI.Button(page, "Import", function()
		local got, err = ns.Shopping.decode(field:GetText())
		if not got then
			page.note:SetText(Theme.escape(Theme.color.danger) .. err .. "|r")
			return
		end
		local mine = lists()
		for _, l in ipairs(got) do
			mine[#mine + 1] = stamp(l)
		end
		s.list, chosenItem = #mine, nil
		field:SetText("")
		field:ClearFocus()
		page.note:SetText(string.format("Imported %d %s.", #got, #got == 1 and "list" or "lists"))
		page:Refresh()
	end, { width = 70, height = 26 })
	importButton:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -8)
	exportButton = UI.Button(page, "Export", function()
		local _, list = lists()
		field:SetText(ns.Shopping.encode({ { name = list.name, entries = list.entries } }))
		field:SetFocus()
		field:HighlightText()
		page.note:SetText("Copy it with Ctrl+C; anyone with Gold Forever can import it, or keep it at gold-forever.app/me/lists.")
	end, { width = 70, height = 26 })
	exportButton:SetPoint("LEFT", importButton, "RIGHT", 5, 0)

	-- The chosen entry, and where its price is kept (the craft queue's by item, others on the entry).
	local function chosenEntry()
		local _, list = lists()
		for _, e in ipairs(list.entries) do
			if e.itemId == chosenItem then
				return e, list
			end
		end
		return nil, list
	end
	local function priceTarget(e, list)
		if list.queue then
			s.queuePrices = s.queuePrices or {}
			s.queuePrices[e.itemId] = s.queuePrices[e.itemId] or {}
			return s.queuePrices[e.itemId]
		end
		return not list.profile and e or nil
	end
	function setPrice(kind, text)
		local e, list = chosenEntry()
		local t = e and priceTarget(e, list)
		if not t then
			return
		end
		local maxUnit, share
		if kind == "fixed" then
			maxUnit = ns.Shopping.parseGold(text)
		elseif kind == "pct" or kind == "lowest" then
			local n = tonumber(string.match(text or "", "%d+") or "")
			share = n and n > 0 and math.min(n, 1000) or nil
		end
		if kind ~= "market" and not maxUnit and not share then
			page.note:SetText(Theme.escape(Theme.color.warning) .. (kind == "fixed" and "Type a price in gold, as 4.5 or 4g 50s, then Enter."
				or kind == "lowest" and "Type the share of the market value to ask over, as 120, then Enter." or "Type a share of the market value, as 80, then Enter.") .. "|r")
			return
		end
		t.maxUnit, t.pct, t.lowest = maxUnit, kind == "pct" and share or nil, kind == "lowest" and share or nil
		if kind == "lowest" and not e.upTo and not list.queue then
			page.note:SetText("Set How many too: Lowest buys until you hold that many, asking over your share.")
		end
		if not list.queue then
			stamp(list)
		end
		page:Refresh()
	end
	amount:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local kind = pending and pending.id == chosenItem and pending.kind or mode.value or "market"
		pending = nil
		setPrice(kind, self:GetText())
	end)
	local function setMany(text)
		local e, list = chosenEntry()
		if e and not list.profile then
			local n = tonumber(string.match(text or "", "%d+") or "")
			e.upTo = n and n > 0 and math.min(n, 1000000) or nil
			stamp(list)
		end
		page:Refresh()
	end
	many:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		setMany(self:GetText())
	end)

	-- Adds an item to the chosen list (one of the player's own).
	local function add(id)
		local list = own()
		if not id then
			return
		end
		if not list then
			page.note:SetText("This list follows the craft queue or the profile; choose one of yours to add to.")
			return
		end
		for _, e in ipairs(list.entries) do
			if e.itemId == id then
				chosenItem = id
				page:Refresh()
				return
			end
		end
		list.entries[#list.entries + 1] = { itemId = id }
		stamp(list)
		chosenItem = id
		page.note:SetText("Added " .. ns.itemName(id) .. ": set the most you pay below.")
		page:Refresh()
	end
	page.addItem = add
	local function dropped()
		local kind, id = GetCursorInfo()
		if kind == "item" and id then
			ClearCursor()
			add(id)
		end
	end
	slot:SetScript("OnReceiveDrag", dropped)
	slot:SetScript("OnClick", dropped)

	function page:Refresh()
		-- The auction panel's Buy tab shows the same lists: it follows at once.
		ns.auctionRefresh()
		local _, list, shown = lists()
		local rows = {}
		for i, l in ipairs(shown) do
			rows[i] = { index = i, name = l.name, n = #l.entries, generated = l.profile }
		end
		listTable:SetRows(rows, true)
		local mine = own()
		name:SetText(mine and mine.name or "")
		name:SetShown(mine ~= nil)
		delete:SetShown(mine ~= nil)
		exportButton:SetShown(mine ~= nil)
		title:SetText(list.name)
		crafting:SetShown(list.queue == true)
		queueWindow:SetShown(list.queue == true)
		slot:SetShown(mine ~= nil)
		slotLine:SetText(mine and "Drop an item here, or shift-click one anywhere, to add it."
			or list.queue and "Its items are what the queued crafts still need; set what you pay for each."
			or "This list follows the sale profile; change it there.")
		slotLine:ClearAllPoints()
		if mine then
			slotLine:SetPoint("LEFT", slot, "RIGHT", 10, 0)
		else
			slotLine:SetPoint("TOPLEFT", X, -32)
		end
		slotLine:SetPoint("RIGHT", page, "RIGHT")
		local entries = {}
		for i, e in ipairs(list.entries) do
			local quality = ns.price.itemInfo(e.itemId)
			entries[i] = { itemId = e.itemId, name = ns.itemName(e.itemId), quality = quality or 1,
				price = e.maxUnit and money(e.maxUnit) or e.pct and (e.pct .. "% of market") or e.lowest and ("lowest, ask over " .. e.lowest .. "%") or "under market",
				many = e.upTo and tostring(e.upTo) or "any" }
		end
		items:SetRows(entries, true)
		local e = chosenEntry()
		edit:SetShown(e ~= nil)
		if e then
			local editable = not list.profile or list.queue
			editName:SetText(ns.itemName(e.itemId))
			local kind = pending and pending.id == e.itemId and pending.kind or e.maxUnit and "fixed" or e.pct and "pct" or e.lowest and "lowest" or "market"
			mode:Set(kind)
			amount:SetShown(kind ~= "market")
			amount:SetText(e.maxUnit and (string.gsub(string.format("%.2f", e.maxUnit / 10000), "%.?0+$", "")) or (e.pct or e.lowest) and tostring(e.pct or e.lowest) or "")
			amount.hint:SetText(kind == "fixed" and "gold" or "%")
			many:SetText(e.upTo and tostring(e.upTo) or "")
			-- The craft queue's numbers come from the queue.
			many:SetShown(not list.profile)
			manyLabel:SetShown(not list.profile)
			removeItem:SetShown(not list.profile)
			mode:SetAlpha(editable and 1 or 0.5)
			mode:EnableMouse(editable)
		end
	end
	-- For the smoke test: its controls.
	page.controls = { new = newList, delete = delete, name = name, import = importButton, export = exportButton, field = field,
		remove = removeItem, setPrice = function(kind, text) setPrice(kind, text) end, setMany = setMany, rename = renameTo }
	ns.listsPage = page
end
ns.buildShoppingLists = buildLists
