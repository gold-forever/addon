-- Gold Forever: what the auction panel's tabs share (ns.ah), and the waits for an action's answer.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI

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

-- Gold and silver: a price rounded to the gold read as wrong beside the auction house's own (8g for 8g 69s).
function ah.money(c)
	return UI.layout.money(c, "silver")
end

ah.WIDTH = 420 -- the panel's width
ah.CONFIRM_TIMEOUT = 5 -- seconds to wait for a post's answer before the next press is taken

-- For the waits below, and the files that refresh the panel.
ns.auctionRefresh = function()
	if ah.refresh then
		ah.refresh()
	end
end
-- The craft queue shows in the Buy tab as a list (CraftPlanner.lua).
ns.listen("queueChanged", "auction panel", ns.auctionRefresh)

-- An action sent (a post, a buy, a cancel): the panel waits for its answer before the next press, and
-- never longer than CONFIRM_TIMEOUT, so a failure the client reports nowhere the panel hears cannot
-- leave Post, Shop and Cancel disabled. Each kind waits apart, so one kind's answer never ends
-- another's wait. `note` is the tab's line for the timeout; `onTimeout` lets go of what the action held.
function ah.await(kind, key, note, onTimeout)
	local w = { key = key, at = GetTime() }
	ah.waits[kind] = w
	C_Timer.After(ah.CONFIRM_TIMEOUT, function()
		if ah.waits[kind] == w then
			ah.waits[kind] = nil
			if onTimeout then
				onTimeout()
			end
			if note then
				note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the auction house; check it before trying again.|r")
			end
			ns.auctionRefresh()
		end
	end)
end

-- Whether any action waits for its answer: a press of Post, Buy next or Cancel next waits for it.
function ah.busy()
	return ah.waits.post or ah.waits.shop or ah.waits.cancel
end
