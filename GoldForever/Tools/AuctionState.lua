-- Gold Forever: what the auction panel's tabs share (ns.ah), apart from the panel: the hub's pages and
-- /gf uidebug read it too.

local _, ns = ...

-- The panel's state, one table the tabs reach: the panel built for the look in use (`panel`, `panels` by
-- Theme.key, `built` the key it was drawn under); Sell's `rows` and `chosen` row; `live`, item key ->
-- { cheapest, at }: the last live search's cheapest other listing (AuctionBooks.lua); `waits`, an action
-- sent, by kind ("post", "shop", "cancel"), waiting for its answer: { key, at }; Sell's `armed` (a post
-- that needs a second press: the row's key) and `confirm` (the client warned about a commodity or item
-- price: the next press confirms { key, args }); Buy's `shopChosen` (the entry in view: { itemId,
-- maxUnit }), `buying` ({ id, n }: the purchase sent, recorded when it succeeds), `overArmed` (the item
-- whose dearer units, past a lowest entry's share, Buy next named; the next press buys) and `purchase`
-- (a commodity purchase in progress: { itemId, quantity, expected, quoted, moved }); Auctions' `owned`
-- ({ auctionID, itemID, key, name, quality, quantity, unit, commodity, cheapest, under }) and `checking`
-- (the index of the auction being searched, while a check runs; 0: reading the auctions). `refresh`
-- draws the tab in view again (AuctionPanel.lua sets it).
local ah = { panels = {}, rows = {}, live = {}, waits = {}, owned = {} }
ns.ah = ah

-- For the waits (AuctionWaits.lua), and the files that refresh the panel.
ns.auctionRefresh = function()
	if ah.refresh then
		ah.refresh()
	end
end
-- The craft queue shows in the Buy tab as a list (CraftPlanner.lua).
ns.listen("queueChanged", "auction panel", ns.auctionRefresh)
