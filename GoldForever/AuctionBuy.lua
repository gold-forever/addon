-- Gold Forever: the auction panel's Buy tab.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local ah = ns.ah
local Books = ns.AuctionBooks
local settings = ns.auctionSettings
local heldHere = ns.Holdings.heldHere
local lists = ns.Lists.lists
local bookKey, searchEntry = Books.bookKey, Books.searchEntry
local await, busy, money = ah.await, ah.busy, ns.Money.auction

-- Shopping lists (design 009, Shop): items with the most to pay a unit, or "under market". Choosing an
-- entry searches it; Buy next buys what its deal covers: a commodity in the client's two steps (a quote,
-- then a second press confirms it; a quote 10% dearer than the deal asks again), an item one auction a
-- press. Lists travel as GFL1 strings. Buying only ever happens on a press.

-- The deal for an entry from its live book, or nil before a search came back.
local function shopDeal(e)
	-- A list entry is an item id: searched with its plain item key (searchEntry), item level 0.
	local l = ah.live[tostring(e.itemId)] or ah.live[bookKey(e.itemId, false, 0)]
	if not l or not l.levels then
		return nil, l
	end
	-- Held counts only for an entry with How many.
	local held = 0
	if e.upTo then
		local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(e.itemId)) or 0
		held = heldHere(e.itemId, inBags)
	end
	return ns.Shopping.entryDeal(e, l.levels, held, ns.Prices.value(e.itemId)), l
end

-- A purchase with no answer is let go: a later purchase in Blizzard's own window is not recorded as it.
local function letGo()
	ah.buying, ah.purchase = nil, nil
end

-- One press of Buy next.
local function buyNext()
	local e = ah.shopChosen
	if not e or busy() then
		return
	end
	local deal, book = shopDeal(e)
	local note = ah.panel.shop.note
	if ah.purchase and ah.purchase.itemId == e.itemId and ah.purchase.quoted then
		-- The second press: confirm the quote the client gave (as its own Buy button does).
		local p = ah.purchase
		ah.purchase = nil
		C_AuctionHouse.ConfirmCommoditiesPurchase(p.itemId, p.quantity)
		ah.buying = { id = p.itemId, n = p.quantity }
		await("shop", "shop:" .. p.itemId, note, letGo)
		note:SetText("Buying…")
		return
	end
	if not deal then
		note:SetText(book and "Nothing at or under your price now." or "Searching…")
		searchEntry(e)
		return
	end
	-- Over a lowest entry's share of market: said first, bought on the next press.
	if deal.over and ah.overArmed ~= e.itemId then
		ah.overArmed = e.itemId
		local market = ns.Prices.value(e.itemId)
		note:SetText(Theme.escape(Theme.color.warning) .. string.format("Over your %d%% of market: %d for %s (up to %s each%s). Press again to buy, or choose something else.",
			deal.share or 0, deal.quantity, money(deal.total), money(deal.topUnit), market and (", market " .. money(market)) or "") .. "|r")
		return
	end
	ah.overArmed = nil
	if book.commodity then
		ah.purchase = { itemId = e.itemId, quantity = deal.quantity, expected = deal.total }
		C_AuctionHouse.StartCommoditiesPurchase(e.itemId, deal.quantity)
		note:SetText("Asking the auction house for a price…")
	else
		-- The cheapest auction by someone else at or under the limit: one a press.
		for _, a in ipairs(book.levels) do
			if a.own == 0 and a.unitPrice <= deal.limit and a.auctionID then
				C_AuctionHouse.PlaceBid(a.auctionID, a.buyout)
				ah.buying = { id = e.itemId, n = a.quantity or 1 }
				await("shop", "shop:" .. e.itemId, note, letGo)
				note:SetText("Buying one for " .. money(a.buyout) .. "…")
				return
			end
		end
		note:SetText("Nothing at or under your price now.")
	end
end

ns.on("COMMODITY_PRICE_UPDATED", "auction shop", function(unit, total)
	if not ah.purchase or not ah.panel or not ah.panel.shop.note then
		return
	end
	ah.purchase.quoted = total
	ah.purchase.moved = ns.Shopping.moved(ah.purchase.expected, total)
	local text = string.format("%d for %s", ah.purchase.quantity, money(total))
	ah.panel.shop.note:SetText(ah.purchase.moved and (Theme.escape(Theme.color.warning) .. "The price moved: " .. text .. " (the deal was " .. money(ah.purchase.expected) .. "). Press again to buy anyway.|r")
		or ("Press again to buy " .. text .. "."))
	ah.refresh()
end)

local function bought(ok, why)
	if not ah.panel or not ah.panel.shop.note then
		return -- a purchase from Blizzard's own window, the Shop not drawn
	end
	if ok and ah.buying then
		ns.Holdings.recordBought(ah.buying)
	end
	ah.buying = nil
	ah.waits.shop, ah.purchase = nil, nil
	ah.panel.shop.note:SetText(ok and (Theme.escape(Theme.color.success) .. "Bought.|r") or (Theme.escape(Theme.color.danger) .. (why or "The purchase failed.") .. "|r"))
	if ah.shopChosen then
		ah.live[tostring(ah.shopChosen.itemId)], ah.live[bookKey(ah.shopChosen.itemId, false, 0)] = nil, nil
		searchEntry(ah.shopChosen)
	end
	ah.refresh()
end
ns.on("COMMODITY_PURCHASE_SUCCEEDED", "auction shop", function()
	bought(true)
end)
ns.on("COMMODITY_PURCHASE_FAILED", "auction shop", function()
	bought(false, "The purchase failed: the price or the stock changed.")
end)
ns.on("COMMODITY_PRICE_UNAVAILABLE", "auction shop", function()
	bought(false, "No price: the stock changed. Search again.")
end)
ns.on("AUCTION_HOUSE_PURCHASE_COMPLETED", "auction shop", function()
	bought(true)
end)

-- Buying only (owner's answers, 2026-10-24): the list and Buy next, the list's items with their deals,
-- and Edit lists, which opens the hub's Shopping lists page where lists and their items are made,
-- named, priced and shared.
local function buildShop(page)
	local s = settings()
	local function names()
		local out = {}
		for i, l in ipairs(select(3, lists())) do
			out[i] = { value = i, label = l.name }
		end
		return out
	end
	local buy = UI.Button(page, "Buy next", function()
		ns.safely("auction shop", buyNext)
	end, { kind = "primary", width = 200, height = 28 })
	buy:SetPoint("TOPRIGHT", 0, 0)
	page.buy = buy
	local listPick
	local function rebuildPick()
		if listPick then
			listPick:SetOptions(names())
			listPick:Set(s.list or 1)
			return
		end
		listPick = UI.Dropdown(page, names(), s.list or 1, function(v)
			s.list = v
			ah.shopChosen = nil
			ah.refresh()
		end)
		listPick:SetPoint("TOPLEFT")
		listPick:SetPoint("RIGHT", buy, "LEFT", -10, 0)
		page.listPick = listPick
	end
	rebuildPick()
	page.rebuildPick = rebuildPick

	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "max", title = "Up to", width = 100, align = "RIGHT", text = function(r)
			local price = r.maxUnit and money(r.maxUnit) or r.pct and (r.pct .. "%") or r.lowest and "lowest" or "market"
			return (r.upTo and (r.upTo .. " at ") or "") .. price
		end },
		{ key = "deal", title = "Deal", width = 120, align = "RIGHT", text = function(r)
			if r.deal and r.deal.over then
				return Theme.escape(Theme.color.warning) .. "over: " .. r.deal.quantity .. " for " .. money(r.deal.total) .. "|r"
			end
			return r.deal and (r.deal.quantity .. " for " .. money(r.deal.total)) or (r.searched and "—" or "")
		end },
	}, {
		pageSize = 9,
		rowHeight = 24,
		empty = "Nothing on this list yet: Edit lists adds items.",
		itemId = function(r) return r.itemId end,
		isSelected = function(r) return ah.shopChosen and r.itemId == ah.shopChosen.itemId end,
		onRowClick = function(r)
			ah.shopChosen, ah.purchase = r.entry, nil
			searchEntry(r.entry, true)
			ah.refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT", 0, -38)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	page.table = tbl
	local editLists = UI.Button(page, "Edit lists ›", function()
		ns.openPage("lists")
	end, { width = 110, height = 26 })
	editLists:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	page.editLists = editLists
	-- Anchored to the table, not the button: with the note hung on the button at its left, that button's
	-- text was never placed now and then (manual test run 001, /gf uidebug: Remove, then Edit lists).
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -46)
	page.note:SetPoint("RIGHT", page, "RIGHT")

	function page:Refresh()
		rebuildPick() -- names and the chosen list as the Shopping lists page left them
		local _, list = lists()
		-- An item no longer on the list in view (the queue cleared, the list changed) is let go.
		local still = false
		for _, e in ipairs(list.entries) do
			if ah.shopChosen and e.itemId == ah.shopChosen.itemId then
				still = true
			end
		end
		if ah.shopChosen and not still then
			ah.shopChosen, ah.purchase, ah.overArmed = nil, nil, nil
		end
		local shown = {}
		for i, e in ipairs(list.entries) do
			local quality, _, _, _, name = ns.price.itemInfo(e.itemId)
			local deal, book = shopDeal(e)
			shown[i] = { entry = e, itemId = e.itemId, maxUnit = e.maxUnit, pct = e.pct, lowest = e.lowest, upTo = e.upTo, name = name or ("item " .. e.itemId), quality = quality or 1, deal = deal, searched = book ~= nil }
		end
		tbl:SetRows(shown)
		local deal = ah.shopChosen and shopDeal(ah.shopChosen)
		local label = ah.purchase and ah.purchase.quoted and ("Confirm: " .. ah.purchase.quantity .. " for " .. money(ah.purchase.quoted))
			or (deal and ("Buy " .. deal.quantity .. " for " .. money(deal.total))) or "Buy next"
		buy:SetLabel(label)
		buy:SetEnabled((ah.shopChosen and not busy()) and true or false)
	end
end

ns.AuctionBuy = { key = "shop", label = "Buy", build = buildShop, refresh = function(page)
	page:Refresh()
end, buyNext = buyNext }
