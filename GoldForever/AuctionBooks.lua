-- Gold Forever: the auction house's books as the panel last searched them (`ns.ah.live`): the searches
-- the panel sends and the results that fill the books, for Sell, Buy, Auctions and the sale plans.

local _, ns = ...
local Post = ns.Post
local ah = ns.ah
local Blizzard = ns.AuctionBlizzard

local Books = {}
ns.AuctionBooks = Books

-- An item's book in `live`: a commodity's by its id; other items' by id and item level, as one gear item
-- at two item levels is two books with two prices.
function Books.bookKey(itemID, commodity, itemLevel)
	if commodity then
		return tostring(itemID)
	end
	return "item:" .. itemID .. ":" .. (itemLevel or 0)
end

Books.LISTED = 4 -- the cheapest listings the panel shows
Books.LEVELS = 100 -- the cheapest levels of a book the Shop reads

-- The cheapest other listing in a book: one sneaky-price guard for Sell, Cancel and the sale plans.
function Books.honest(levels, itemID)
	return Post.honestCheapest(levels, (ns.Prices.value(itemID)))
end

-- Asks the server for the chosen row's listings, own ones apart, sorted by price.
-- Asks for the chosen row's listings. With `open`, the auction house's own window shows the item too, as
-- a click on it in Blizzard's browse list does (its buy view, with every price); its search is the one
-- whose results arrive here. Without it, or on a client without that method, a search of our own.
function Books.search(r, open)
	if not (r and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.GetItemKeyFromItem) then
		return
	end
	local key = C_AuctionHouse.GetItemKeyFromItem(r.locations[1])
	if not key then
		return
	end
	r.itemKey = key
	-- Chosen on Sell: into Blizzard's Sell window too (the search below still reads the listings for
	-- the panel); else its listings in Blizzard's Buy view.
	if open and not Blizzard.sellItem(r.locations[1]) and Blizzard.browse(key) then
		return
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

-- `open`: chosen by the player, so Blizzard's window shows its listings too (manual test run 001); the
-- panel's own search still reads the book for the deal.
function Books.searchEntry(e, open)
	if not (e and C_AuctionHouse.MakeItemKey and C_AuctionHouse.SendSearchQuery) then
		return
	end
	local key = C_AuctionHouse.MakeItemKey(e.itemId)
	if open then
		Blizzard.browse(key)
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

-- Commodities: the cheapest unit left after the player's own.
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction panel", function(itemID)
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	local list, levels = {}, {}
	-- The book as the Shop reads it ({ unitPrice, quantity, own }), the cheapest LEVELS of it.
	for i = 1, math.min(n, Books.LEVELS) do
		local res = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if res then
			if #list < Books.LISTED then
				list[#list + 1] = { unit = res.unitPrice, qty = res.quantity or 0, own = (res.numOwnerItems or 0) > 0 }
			end
			levels[#levels + 1] = { unitPrice = res.unitPrice, quantity = res.quantity or 0, own = res.numOwnerItems or 0 }
		end
	end
	ah.live[tostring(itemID)] = { cheapest = Books.honest(levels, itemID), list = list, total = n, levels = levels, commodity = true, at = GetTime() }
	ns.auctionRefresh()
end)

-- Gear and other items: the cheapest buyout a unit that is not the player's own.
ns.on("ITEM_SEARCH_RESULTS_UPDATED", "auction panel", function(itemKey)
	if not itemKey then
		return
	end
	local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
	local all = {}
	-- The cheapest LEVELS (the search is sorted by price), as for commodities: a popular item lists hundreds.
	for i = 1, math.min(n, Books.LEVELS) do
		local res = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if res and res.buyoutAmount and res.buyoutAmount > 0 then
			local unit = math.floor(res.buyoutAmount / math.max(1, res.quantity or 1) + 0.5)
			all[#all + 1] = { unit = unit, qty = res.quantity or 1, own = res.containsOwnerItem and true or false,
				auctionID = res.auctionID, buyout = res.buyoutAmount }
		end
	end
	table.sort(all, function(a, b)
		return a.unit < b.unit
	end)
	local list = {}
	for i = 1, math.min(Books.LISTED, #all) do
		list[i] = all[i]
	end
	-- For the Shop: every auction of the item, cheapest first, as levels and with what PlaceBid needs.
	local levels = {}
	for i, a in ipairs(all) do
		levels[i] = { unitPrice = a.unit, quantity = a.qty, own = a.own and a.qty or 0, auctionID = a.auctionID, buyout = a.buyout }
	end
	local cheapest = Books.honest(levels, itemKey.itemID)
	for _, r in ipairs(ah.rows) do
		if r.itemKey and r.itemKey.itemID == itemKey.itemID and r.itemKey.itemLevel == itemKey.itemLevel then
			ah.live[r.key] = { cheapest = cheapest, list = list, total = n, at = GetTime() }
		end
	end
	ah.live[Books.bookKey(itemKey.itemID, false, itemKey.itemLevel)] = { cheapest = cheapest, levels = levels, commodity = false, at = GetTime() }
	ns.auctionRefresh()
end)
