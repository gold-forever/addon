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
eq(none.wide, false, "no room: narrow")
eq(none.width, 420, "no room: the panel's own width")
eq(none.cramped, true, "no room: said")
eq(narrow.cramped, nil, "narrow by choice: nothing to say")
-- Room unknown (the auction house not placed yet): the full width.
eq(layout(true, nil).width, wide.width, "room unknown: the full width")
return checks()
