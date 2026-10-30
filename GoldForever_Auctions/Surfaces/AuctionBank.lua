-- Gold Forever: the auction panel's Bank tab.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local searchEntry = ns.AuctionBooks.searchEntry
local money = ns.Money.auction

-- Bank (owner, 2026-10-24 and 25): what the bank and mailbox hold that the auction house pays for, most
-- worth first. A click chooses one and shows its listings in Blizzard's window, as on Sell; Take all, or
-- Take… an amount, marks it, and the next time the bank opens it moves to the bags (Inventory.lua).
local bankChosen -- the item chosen on the Bank tab
local function buildBank(page)
	local function wanted()
		return ns.fetchList() or {}
	end
	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3 },
		{ key = "count", title = "Held", width = 50, align = "RIGHT" },
		{ key = "place", title = "In", width = 40 },
		{ key = "worth", title = "Worth", width = 84, align = "RIGHT", text = function(r) return money(r.worth) end, sort = function(r) return r.worth end },
		{ key = "take", title = "Take", width = 44, align = "RIGHT", text = function(r) return r.take == true and "all" or r.take and tostring(r.take) or "" end,
			color = function() return Theme.color.accent end },
	}, {
		pageSize = 9,
		rowHeight = 24,
		empty = "Nothing in your bank or mail the auction house pays for.",
		itemId = function(r) return r.id end,
		isSelected = function(r) return bankChosen and r.id == bankChosen.id end,
		onRowClick = function(r)
			bankChosen = r
			searchEntry({ itemId = r.id }, true)
			page:Refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT")
	tbl:SetPoint("RIGHT", page, "RIGHT")
	page.table = tbl
	-- The chosen item and what to take of it.
	local detail = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	detail:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	detail:SetPoint("RIGHT", page, "RIGHT")
	detail:SetHeight(84)
	local name = UI.Text(detail, "", { size = "sm", medium = true })
	name:SetPoint("TOPLEFT", 12, -10)
	name:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
	local line = UI.Text(detail, "", { size = "xs", tone = "faint" })
	line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	local function mark(n)
		if bankChosen and bankChosen.place == "bank" then
			wanted()[bankChosen.id] = n
			page:Refresh()
		end
	end
	local all = UI.Button(detail, "Take all", function()
		mark(true)
	end, { width = 90, height = 26 })
	all:SetPoint("BOTTOMLEFT", 12, 10)
	-- Take…: a small window over the panel asks how many.
	local ask = UI.Panel(page, { color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	ask:SetSize(280, 96)
	ask:SetPoint("CENTER", detail, "CENTER")
	ask:SetFrameLevel(detail:GetFrameLevel() + 10)
	ask:EnableMouse(true)
	ask:Hide()
	local askText = UI.Text(ask, "", { size = "sm", wrap = true })
	askText:SetPoint("TOPLEFT", 12, -12)
	askText:SetPoint("RIGHT", ask, "RIGHT", -12, 0)
	local amount = UI.SearchBox(ask, "how many", nil)
	amount:SetPoint("BOTTOMLEFT", 12, 12)
	amount:SetWidth(90)
	local function takeAmount(text)
		local n = tonumber(string.match(text or "", "%d+") or "")
		amount:ClearFocus()
		ask:Hide()
		if n and n > 0 and bankChosen then
			mark(n >= bankChosen.count and true or n)
		end
	end
	local function takeTyped()
		takeAmount(amount:GetText())
	end
	amount:SetScript("OnEnterPressed", takeTyped)
	amount:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		ask:Hide()
	end)
	local okay = UI.Button(ask, "Take", takeTyped, { kind = "primary", width = 70, height = 26 })
	okay:SetPoint("LEFT", amount, "RIGHT", 8, 0)
	local cancel = UI.Button(ask, "Cancel", function()
		amount:ClearFocus()
		ask:Hide()
	end, { width = 70, height = 26 })
	cancel:SetPoint("LEFT", okay, "RIGHT", 6, 0)
	local some = UI.Button(detail, "Take...", function()
		if bankChosen and bankChosen.place == "bank" then
			askText:SetText(string.format("Take how many %s? %d in the bank.", bankChosen.name, bankChosen.count))
			amount:SetText("")
			ask:Show()
			amount:SetFocus()
		end
	end, { width = 80, height = 26 })
	some:SetPoint("LEFT", all, "RIGHT", 6, 0)
	local none = UI.Button(detail, "Don't take", function()
		mark(nil)
	end, { width = 100, height = 26 })
	none:SetPoint("LEFT", some, "RIGHT", 6, 0)
	local sum = UI.Text(page, "", { size = "xs", tone = "muted" })
	sum:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -8)
	sum:SetPoint("RIGHT", page, "RIGHT")
	page.take = { all = all, some = some, none = none, typed = function(n) takeAmount(tostring(n)) end, open = function() some:Click() end }
	function page:Refresh()
		local me = ns.me()
		local e = me and ns.Views.elsewhere(me, ns.Encode.parseItems, function(id)
			return (ns.Prices.value(id))
		end, ns.itemName) or { items = {} }
		local want, rows, n = wanted(), {}, 0
		for i, it in ipairs(e.items) do
			local take = it.place == "bank" and want[it.id] or nil
			rows[i] = { id = it.id, name = it.name, count = it.count, place = it.place, worth = it.worth, take = take }
			if take then
				n = n + 1
			end
			if bankChosen and bankChosen.id == it.id and bankChosen.place == it.place then
				bankChosen = rows[i]
			end
		end
		page.rows = rows
		tbl:SetRows(rows, true)
		local c = bankChosen
		name:SetText(c and c.name or Theme.escape(Theme.color.textFaint) .. "Choose an item.|r")
		line:SetText(c and (c.place == "mail" and string.format("%d in your mail: the mail helper takes it.", c.count)
			or string.format("%d in the bank · %s%s", c.count, money(c.worth), c.take == true and " · taking all" or c.take and (" · taking " .. c.take) or "")) or "")
		local can = c and c.place == "bank" or false
		for _, b in ipairs({ all, some, none }) do
			b:SetEnabled(can)
		end
		sum:SetText(n > 0 and string.format("%d chosen: they move into your bags the next time you open your bank.", n) or "Choose items to take from the bank: they move into your bags the next time you open it.")
	end
end

ns.AuctionBank = { key = "bank", label = "Bank", build = buildBank, refresh = function(page)
	page:Refresh()
end }
