-- The Sell tab's two layouts (addon#84): narrow, the list over the item's box as before; wide, the panel
-- wider, the list taller and wider, the item's box a column beside it, as far as the screen beside the
-- auction house has room.

-- AuctionSell.lua on the parts of the namespace it reads when loaded.
local ns = {
	Theme = {}, UI = {}, Post = {}, ah = { await = function() end, busy = function() end, WIDTH = 420 },
	AuctionBlizzard = {}, AuctionBooks = { LISTED = 4 }, Holdings = {}, Money = {},
	auctionSettings = function() end, activeProfile = function() end, on = function() end,
}
assert(load(SOURCES["AuctionSell.lua"], "@AuctionSell.lua"))("GoldForever_Auctions", ns)
local layout = ns.AuctionSell.layout

-- Narrow is today's: the panel's own width, five rows, no column.
local narrow = layout(false, 2000)
eq(narrow.wide, false, "narrow: not wide")
eq(narrow.width, 420, "narrow: the panel's own width")
eq(narrow.rows, 5, "narrow: five rows")
eq(narrow.column, nil, "narrow: the box under the list")
eq(layout(false, nil).width, 420, "narrow whatever the room")

-- Wide at the auction house's side (addon#91): the 844 page in two halves of 416, 12 apart.
local full = layout(true, 2000)
eq(full.width, 880, "wide: 880")
eq(full.width - full.pad, 844, "wide: the page 844")
eq(full.column, 416, "wide: the box half the page")
eq(full.list, 416, "wide: the list half the page")
eq(full.gap, 12, "wide: 12 between the halves")
eq(full.rows, 13, "wide: thirteen rows")

-- Wide with room: wider than narrow, more rows, the box a column, and the list wider than narrow's.
local wide = layout(true, 2000)
eq(wide.wide, true, "wide: wide")
eq(wide.width > 420, true, "wide: a wider panel")
eq(wide.rows > narrow.rows, true, "wide: a taller list")
eq(type(wide.column), "number", "wide: the box a column beside the list")
eq(wide.list > narrow.list, true, "wide: a wider list")
eq(wide.list + wide.column + wide.gap + wide.pad, wide.width, "wide: list, gap and column fill the panel")
eq(narrow.list + narrow.pad, narrow.width, "narrow: the list as wide as the page")

-- The panel never runs past the screen: as wide as the room, never more.
local room = wide.width - 100
local tight = layout(true, room)
eq(tight.wide, true, "a little less room: still wide")
eq(tight.width, room, "as wide as the room")
eq(tight.list, wide.list - 100, "the list takes the cut")
-- Too little room for a list beside the box: narrow, and the plan says why.
local none = layout(true, 500)
eq(layout(true, 36 + 12 + 416 + 260).wide, true, "room for the box and the narrowest list: wide")
eq(layout(true, 36 + 12 + 416 + 259).cramped, true, "a pixel less: narrow, said")
eq(none.wide, false, "no room: narrow")
eq(none.width, 420, "no room: the panel's own width")
eq(none.cramped, true, "no room: said")
eq(narrow.cramped, nil, "narrow by choice: nothing to say")
-- Room unknown (the auction house not placed yet): the full width.
eq(layout(true, nil).width, wide.width, "room unknown: the full width")
-- Previous / Next under the wide list (addon#86): only wide, only with more than one page, each off at its end.
local pager = ns.AuctionSell.pager
eq(pager(false, 40, 2, 5).shown, false, "narrow: no Previous / Next, whatever the pages")
eq(pager(true, 13, 1, 13).shown, false, "wide, one page: hidden")
eq(pager(true, 0, 1, 13).shown, false, "wide, no rows: hidden")
local first = pager(true, 40, 1, 13)
eq(first.shown, true, "wide, four pages: shown")
eq(first.text, "1 / 4", "the page, of how many")
eq(first.previous, false, "first page: Previous off")
eq(first.next, true, "first page: Next on")
local mid = pager(true, 40, 2, 13)
eq(mid.text, "2 / 4", "page two of four")
eq(mid.previous and mid.next, true, "between the ends: both on")
local last = pager(true, 40, 4, 13)
eq(last.previous, true, "last page: Previous on")
eq(last.next, false, "last page: Next off")
eq(pager(true, 14, 2, 13).text, "2 / 2", "a page of one row is a page")

-- The wide box (addon#91), AuctionSellWide.lua's pure parts: where things go, the listings, the texts.
local wns = {
	Theme = { escape = function() return "" end, color = {} }, UI = {},
	Money = { format = function(c) return c .. "c" end },
}
assert(load(SOURCES["AuctionSellWide.lua"], "@AuctionSellWide.lua"))("GoldForever_Auctions", wns)
local Wide = wns.AuctionSellWide

-- Geometry at the panel's real size: the box 416 x 436, content 388 wide.
local g = Wide.geometry(416, 436)
eq(g.inner, 388, "the box's content: 388 wide")
eq(g.name, 388 - 46 - 140, "the name clips beside Narrow and Rule")
eq(g.fact, 129, "three facts, a third each")
eq(g.slider, 152, "the slider from x 70 to the duration buttons' room")
eq(g.note, 278, "the note line beside the deposit")
eq(g.rows, 6, "six listing rows at 538")
eq(Wide.geometry(416, 436 + 40).rows, 8, "a taller box: more rows")
eq(Wide.geometry(416, 200).rows, 0, "no height left: none")

-- Gear: auctions of one price and stack size on one line, counted; the player's own apart and marked.
local lines, prices, units = Wide.lines({
	{ unitPrice = 500, quantity = 1, own = 0 }, { unitPrice = 500, quantity = 1, own = 0 },
	{ unitPrice = 500, quantity = 1, own = 1 }, { unitPrice = 500, quantity = 5, own = 0 },
	{ unitPrice = 700, quantity = 1, own = 0 },
}, false)
eq(#lines, 4, "gear: four lines")
eq(lines[1].stack .. "x" .. lines[1].count, "1x2", "two auctions of one at 500: one line, counted")
eq(lines[2].own and lines[2].count, 1, "the player's own apart from the same price and stack, marked")
eq(lines[3].stack .. "x" .. lines[3].count, "5x1", "a stack of five apart")
eq(lines[1].own, false, "others' not marked")
eq(prices, 2, "gear: two prices")
eq(units, 9, "gear: nine for sale")
-- Commodities: by price, the quantity summed.
lines, prices, units = Wide.lines({ { unitPrice = 3000, quantity = 5, own = 5 }, { unitPrice = 4250, quantity = 20, own = 0 } }, true)
eq(#lines, 2, "commodities: a line a price")
eq(lines[1].stack, nil, "commodities: no stack")
eq(lines[2].count, 20, "commodities: the quantity at the price")
eq(lines[1].own, true, "commodities: the own marked")
eq(units, 25, "commodities: 25 for sale")
eq(Wide.heading(9, 75), "LISTINGS · 9 PRICES · 75 FOR SALE", "the heading counts prices and units")
eq(Wide.heading(1, 1), "LISTINGS · 1 PRICE · 1 FOR SALE", "one price")
eq(select(1, Wide.lines(nil, true))[1], nil, "no book: no lines")

-- The why line: one sentence for each reason.
eq(Wide.why({ suggestion = { reason = "undercut", unit = 600 }, cheapest = 699 }), "99c under the cheapest other listing, above your floor.", "undercut")
eq(Wide.why({ suggestion = { reason = "alone" } }), "No one else lists it: your normal price.", "alone")
eq(Wide.why({ suggestion = { reason = "hold" }, anyway = 38999 }), "The cheapest other is under your floor: held. Anyway: 38999c.", "held, with Post anyway's price")
eq(Wide.why({}), "No price yet: scan first.", "no price")
-- gf#368: the maximum, the vendor floor, today's price, the post size.
eq(Wide.why({ suggestion = { reason = "maximum", times = 3 } }), "The others ask more than 3x the market: posted at the maximum.", "at the maximum")
eq(Wide.why({ suggestion = { reason = "hold", floorBy = "vendor" } }), "The cheapest other is under the vendor price after the cut: held.", "held by the vendor price")
eq(Wide.why({ suggestion = { reason = "alone", day = true } }), "No one else lists it: today's price.", "alone at today's price")
eq(Wide.why({ suggestion = { reason = "undercut", unit = 600 }, cheapest = 699, sizeReason = "2 days of supply" }), "99c under the cheapest other listing, above your floor. Posting 2 days of supply.", "the post size's reason")
eq(Wide.why({ suggestion = { reason = "undercut", unit = 600, estimate = true }, cheapest = 699 }), "Searching the auction house for the live price...", "from the scan: waits for the live search")

-- The badge: the reason in a word, in its tone.
local b = Wide.badge({ reason = "hold" })
eq(b.label .. " " .. b.tone, "Hold danger", "held: Hold")
b = Wide.badge({ reason = "undercut" })
eq(b.label .. " " .. b.tone, "Undercut accent", "undercut")
eq(Wide.badge({ reason = "plan", label = "Fixed price (plan)", unit = 5 }).label, "Fixed price (plan)", "a plan's step by its label")
eq(Wide.badge(nil), nil, "no price: no badge")
b = Wide.badge({ reason = "maximum" })
eq(b.label .. " " .. b.tone, "At the maximum info", "the maximum")

-- Post, and Post anyway under the floor: the plain button, a second press, its own words.
local post = Wide.button({ suggestion = { reason = "undercut", unit = 600 } }, 15, false)
eq(post.label, "Post 15 x 600c", "Post: quantity and price")
eq(post.kind .. " " .. tostring(post.enabled), "primary true", "Post: primary")
local held = { suggestion = { reason = "hold", floor = 43200 }, anyway = 38999 }
local first = Wide.button(held, 6, false)
eq(first.label, "Post anyway: 6 x 38999c", "held: Post anyway")
eq(first.kind .. " " .. tostring(first.enabled), "default true", "held: the plain button")
eq(Wide.button(held, 6, true).label, "Press again: post 6 x 38999c", "armed: press again")
eq(Wide.underFloor(held), "Under your floor of 43200c.", "armed: the note names the floor")
eq(Wide.button({ suggestion = { reason = "hold" } }, 1, false).enabled, false, "held with no one to undercut: off")
eq(Wide.button(nil, 1, false).enabled, false, "no price: off")
eq(Wide.button({ suggestion = { reason = "undercut", unit = 600 } }, 1, false, true).enabled, false, "busy: off")
eq(Wide.button({ suggestion = { reason = "undercut", unit = 600, estimate = true } }, 1, false).enabled, false, "from the scan: off until the live search")
eq(Wide.button({ suggestion = { reason = "undercut", unit = 600, estimate = true } }, 1, false).label, "Searching...", "from the scan: searching")
eq(Wide.button({ suggestion = { reason = "hold", estimate = true }, anyway = 5 }, 1, false).enabled, false, "Post anyway waits for the live search too")
eq(Wide.price({ suggestion = { reason = "hold" }, anyway = 1 }).held, true, "held: the price line reads Held")
eq(Wide.price({ suggestion = { reason = "undercut", unit = 600 } }).text, "600c", "the unit price")
return checks()
