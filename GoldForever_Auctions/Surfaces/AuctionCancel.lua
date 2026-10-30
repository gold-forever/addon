-- Gold Forever: the auction panel's Auctions tab: the player's own auctions, and cancelling the undercut.

local _, ns = ...
local Theme, UI, Post = ns.Theme, ns.UI, ns.Post
local ah = ns.ah
local Blizzard = ns.AuctionBlizzard
local settings = ns.auctionSettings
local bookKey = ns.AuctionBooks.bookKey
local await, busy, money = ah.await, ah.busy, ns.Money.auction
local CONFIRM_TIMEOUT = ah.CONFIRM_TIMEOUT

-- The player's own auctions (design 009, Cancel undercut; owner: build it now, 5% by default): each
-- searched in turn against other players' listings (a few sneaky cheap units passed over); those
-- undercut by more than the tolerance are listed, and Cancel next cancels the most undercut one a press
-- (CancelAuction is a hardware event, and costs the deposit). The items come back by mail.
local TOLERANCES = { { value = 1, label = "1%" }, { value = 5, label = "5%" }, { value = 10, label = "10%" } }
local checkRun -- the check running, so a timer of an earlier one leaves it be

local function tolerance()
	return settings().tolerance or 5
end

-- The cheapest other listing for an owned auction, from the last search of its item.
local function cheapestFor(a)
	local book = ah.live[bookKey(a.itemID, a.commodity, a.itemKey and a.itemKey.itemLevel)]
	return book and book.cheapest or nil, book ~= nil
end

local function readOwned()
	local n = C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetNumOwnedAuctions() or 0
	ah.owned = Post.readOwned(n, C_AuctionHouse.GetOwnedAuctionInfo, C_AuctionHouse.GetItemKeyInfo, ns.price.itemInfo)
end

-- Searches the next owned auction's item; the results event moves the check on.
local function checkNext()
	ah.checking = (ah.checking or 0) + 1
	local a = ah.owned[ah.checking]
	if not a then
		ah.checking = nil
		ah.refresh()
		return
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(a.itemKey, sorts, true)
	-- A search the server never answers (throttled) does not stall the check: on to the next.
	local at = ah.checking
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if ah.checking == at and not a.answered then
			a.answered = true
			ns.safely("auction cancel", checkNext)
		end
	end)
	ah.refresh()
end

local function startCheck()
	if C_AuctionHouse.QueryOwnedAuctions then
		C_AuctionHouse.QueryOwnedAuctions({ { sortOrder = 0, reverseSort = false } })
	end
	ah.checking = 0
	ah.panel.cancel.note:SetText("Reading your auctions...")
	-- The list never coming (throttled, the auction house closing) does not leave the check running.
	local run = {}
	checkRun = run
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if ah.checking == 0 and checkRun == run then
			ah.checking = nil
			if ah.panel and ah.panel.cancel.note then
				ah.panel.cancel.note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the auction house; check again in a moment.|r")
			end
			ah.refresh()
		end
	end)
end

ns.on("OWNED_AUCTIONS_UPDATED", "auction cancel", function()
	if ah.checking == 0 then
		readOwned()
		checkNext()
	end
end)
-- A search answered moves the check to the next auction (both kinds of results).
-- Only the answer for the auction being checked moves it on, once (other searches, the panel's or
-- Blizzard's, and repeated events for the same item do not); 0.7 s apart keeps the check under the
-- search limit of 100 a minute.
local CHECK_GAP = 0.7
local function searched(what)
	local a = ah.checking and ah.checking > 0 and ah.owned[ah.checking]
	if not a or a.answered then
		return
	end
	local id = type(what) == "table" and what.itemID or what
	if id ~= a.itemID then
		return
	end
	-- Gear: the answer for its own item level (two auctions of one item may be checked in turn).
	if type(what) == "table" and what.itemLevel and a.itemKey and a.itemKey.itemLevel and what.itemLevel ~= a.itemKey.itemLevel then
		return
	end
	a.answered = true
	C_Timer.After(CHECK_GAP, function()
		ns.safely("auction cancel", checkNext)
	end)
end
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction cancel", searched)
ns.on("ITEM_SEARCH_RESULTS_UPDATED", "auction cancel", searched)

-- The owned auctions undercut past the tolerance, most undercut first.
local function undercut()
	for _, a in ipairs(ah.owned) do
		a.cheapest = cheapestFor(a)
	end
	return Post.undercutList(ah.owned, tolerance())
end

local function cancelNext()
	if busy() then
		return
	end
	local a = undercut()[1]
	if not a then
		ah.panel.cancel.note:SetText("Nothing undercut past " .. tolerance() .. "%.")
		return
	end
	C_AuctionHouse.CancelAuction(a.auctionID)
	await("cancel", "cancel:" .. a.auctionID, ah.panel.cancel.note)
	ah.panel.cancel.note:SetText("Cancelling " .. a.name .. "...")
end

ns.on("AUCTION_CANCELED", "auction cancel", function(auctionID)
	if ah.waits.cancel and ah.waits.cancel.key == "cancel:" .. tostring(auctionID) then
		ah.waits.cancel = nil
	end
	for i, a in ipairs(ah.owned) do
		if a.auctionID == auctionID then
			table.remove(ah.owned, i)
			break
		end
	end
	if ah.panel and ah.panel.cancel.note then
		ah.panel.cancel.note:SetText(Theme.escape(Theme.color.success) .. "Cancelled: it comes back by mail.|r")
		ah.refresh()
	end
end)

local function buildCancel(page)
	local tol = UI.Dropdown(page, TOLERANCES, tolerance(), function(v)
		settings().tolerance = v
		ah.refresh()
	end)
	-- The label, then the dropdown just after it, leaving room before Check my auctions at the right in
	-- the panel's 384 pixels (manual test run 001: they touched).
	local tolLabel = UI.Text(page, "Undercut past", { size = "sm", tone = "muted" })
	tolLabel:SetPoint("TOPLEFT", 0, -7)
	tol:SetPoint("LEFT", tolLabel, "RIGHT", 10, 0)
	tol:SetWidth(84)
	local check = UI.Button(page, "Check my auctions", function()
		ns.safely("auction cancel", startCheck)
	end, { width = 150, height = 28 })
	check:SetPoint("TOPRIGHT", 0, 0)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Your auction", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end,
			text = function(r) return r.quantity > 1 and (r.name .. Theme.escape(Theme.color.textFaint) .. " x" .. r.quantity .. "|r") or r.name end },
		{ key = "unit", title = "Yours", width = 74, align = "RIGHT", text = function(r) return money(r.unit) end },
		{ key = "cheapest", title = "Cheapest", width = 74, align = "RIGHT", text = function(r) return r.cheapest and money(r.cheapest) or (r.searched and "-" or "") end },
		{ key = "under", title = "Under", width = 56, align = "RIGHT", text = function(r) return r.under and r.under > 0 and (r.under .. "%") or "" end,
			color = function(r) return r.under and r.under > tolerance() and Theme.color.warning or Theme.color.textMuted end, sort = function(r) return r.under or 0 end },
	}, { pageSize = 9, rowHeight = 24, empty = "Check your auctions to see which are undercut.", itemId = function(r) return r.itemID end,
		-- A click shows the item's listings in Blizzard's window (manual test run 001).
		onRowClick = function(r)
			Blizzard.browse(r.itemKey)
		end })
	tbl:SetPoint("TOPLEFT", 0, -40)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local go = UI.Button(page, "Cancel next", function()
		ns.safely("auction cancel", cancelNext)
		ah.refresh()
	end, { kind = "primary", width = 200, height = 30 })
	go:SetPoint("TOPRIGHT", tbl, "BOTTOMRIGHT", 0, -10)
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -16)
	page.note:SetPoint("RIGHT", go, "LEFT", -12, 0)
	function page:Refresh()
		local list = undercut()
		for _, a in ipairs(ah.owned) do
			a.searched = select(2, cheapestFor(a))
		end
		tbl:SetRows(ah.owned)
		local first = list[1]
		if ah.checking == 0 then
			go:SetLabel("Reading...")
		elseif ah.checking then
			go:SetLabel(string.format("Checking %d of %d...", ah.checking, #ah.owned))
		elseif first then
			local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(first.auctionID)
			go:SetLabel("Cancel " .. first.name .. (cost and cost > 0 and (" (" .. money(cost) .. ")") or ""))
		else
			go:SetLabel("Cancel next")
		end
		go:SetEnabled((first and not ah.checking and not busy()) and true or false)
		if not ah.checking and page.note:GetText() == "Reading your auctions..." then
			page.note:SetText(#ah.owned == 0 and "You have no auctions up."
				or string.format("%d of your %d auctions are undercut past %d%%.", #list, #ah.owned, tolerance()))
		end
	end
end

ns.AuctionCancel = { key = "cancel", label = "Auctions", build = buildCancel, refresh = function(page)
	page:Refresh()
end, startCheck = startCheck, cancelNext = cancelNext }
