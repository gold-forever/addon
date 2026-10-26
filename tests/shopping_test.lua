-- Shopping.lua: the playground's shopping.test.ts cases, in Lua.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Shopping.lua"], "@Shopping.lua"))("GoldForever", ns)
local S, E = ns.Shopping, ns.Encode

local function lv(unitPrice, quantity, own) return { unitPrice = unitPrice, quantity = quantity, own = own or 0 } end

-- Every function is there as soon as the file loads (one was once defined inside encode by mistake).
for _, name in ipairs({ "limit", "take", "deal", "moved", "text", "encode", "decode", "parseAdd", "underPrice", "merge", "refind" }) do
	eq(type(S[name]), "function", "defined at load: " .. name)
end

-- take: other players' units from the book, cheapest first, under a cap and up to a need.
local function took(...) return table.concat({ tostring((select(1, ...))), tostring((select(2, ...))), tostring((select(3, ...))) }, ":") end
local book = { lv(300, 5), lv(100, 4, 1), lv(200, 10) }
eq(took(S.take(book, nil, nil)), "18:" .. (300 + 2000 + 1500) .. ":300", "every other unit, cheapest first")
eq(took(S.take(book, 200, nil)), "13:2300:200", "at or under the cap")
eq(took(S.take(book, nil, 5)), "5:" .. (300 + 400) .. ":200", "up to the need")
eq(took(S.take(book, 50, 5)), "0:0:nil", "nothing under the cap")
eq(took(S.take(book, nil, 0)), "0:0:nil", "nothing needed")

-- entryLimit
eq(S.limit({ itemId = 1, maxUnit = 500 }, 900), 500, "its own price")
eq(S.limit({ itemId = 1 }, 900), 899, "a copper under market")
eq(S.limit({ itemId = 1 }, nil), nil, "no market, no limit")
-- A share of the market value, and how many to hold (owner's answer, 2026-10-24).
eq(S.limit({ itemId = 1, pct = 80 }, 1000), 800, "80% of market")
eq(S.limit({ itemId = 1, lowest = 120 }, 1000), 1200, "lowest: bought without asking up to 120% of market")
eq(S.line({ itemId = 7, lowest = 120, upTo = 20 }), "item 7 lowest 120 upto 20", "lowest in the line")
-- Lowest: needing 20, holding 5, market 1000, check over 120%: the cheapest 15 within 1200 first...
local low = S.lowestDeal({ itemId = 7, lowest = 120, upTo = 20 }, 5, { lv(1300, 50), lv(900, 10), lv(1100, 3) }, 1000)
eq(low.quantity .. " " .. low.total .. " " .. tostring(low.over), "13 12300 nil", "within the share, cheapest first")
-- ...then, still needing some and only dearer ones left, those, marked over.
local over = S.lowestDeal({ itemId = 7, lowest = 120, upTo = 20 }, 7, { lv(1300, 50), lv(1500, 10) }, 1000)
eq(over.quantity .. " " .. over.total .. " " .. tostring(over.over) .. " " .. over.limit, "13 16900 true 1300", "over the share: asked first")
eq(S.lowestDeal({ itemId = 7, lowest = 120, upTo = 20 }, 20, { lv(900, 10) }, 1000), nil, "nothing needed")
eq(S.decode(S.encode({ { name = "Raid", entries = { { itemId = 7, lowest = 120, upTo = 20 } } } }))[1].entries[1].lowest, 120, "lowest read back")
eq((S.decode("GFL1:" .. E.base64("list a\nitem 1 lowest 0"))), nil, "lowest 0")
eq(S.parseGold("4.5"), 45000, "gold with a point")
eq(S.parseGold("4,5"), 45000, "or a comma")
eq(S.parseGold("4,50"), 45000, "a comma before two digits")
-- A thousands separator is not a decimal point (review B-37).
eq(S.parseGold("1,000"), 10000000, "a thousand gold")
eq(S.parseGold("1,000,5"), 10005000, "thousands, then a decimal comma")
eq(S.parseGold("1,000.5"), 10005000, "thousands, then a decimal point")
eq(S.parseGold("4g 50s"), 45000, "gold and silver")
eq(S.parseGold("45s"), 4500, "silver")
eq(S.parseGold("1g2s3c"), 10203, "all three")
eq(S.parseGold(""), nil, "nothing")
eq(S.parseGold("cheap"), nil, "not a price")
eq(S.parseGold("0"), nil, "zero")
eq(S.limit({ itemId = 1, pct = 80 }, nil), nil, "a share of no market is no limit")
eq(S.line({ itemId = 7, pct = 80, upTo = 20 }), "item 7 pct 80 upto 20", "pct and upto in the line")
eq(S.line({ itemId = 7, maxUnit = 500 }), "item 7 max 500", "an old entry's line as before")
eq(S.line({ itemId = 7, upTo = 3 }), "item 7 market upto 3", "under market, up to 3")
local ext = S.decode(S.encode({ { name = "Mats", entries = { { itemId = 7, pct = 80, upTo = 20 }, { itemId = 8, maxUnit = 450, upTo = 5 }, { itemId = 9 } } } }))
eq(ext[1].entries[1].pct .. " " .. ext[1].entries[1].upTo, "80 20", "pct and upto read back")
eq(ext[1].entries[2].maxUnit .. " " .. ext[1].entries[2].upTo, "450 5", "max and upto read back")
eq(ext[1].entries[3].pct == nil and ext[1].entries[3].upTo == nil, true, "market alone")

-- dealFor
local d = S.deal({ itemId = 1, maxUnit = 300 }, { lv(250, 20), lv(300, 10, 4), lv(420, 30) }, nil)
eq(d.quantity, 26, "other players' units at or under the limit")
eq(d.total, 250 * 20 + 300 * 6, "their cost")
eq(d.topUnit, 300, "the dearest unit reached")
eq(d.limit, 300, "the limit")
eq(S.deal({ itemId = 1, maxUnit = 100 }, { lv(250, 20) }, nil), nil, "nothing cheap enough")
eq(S.deal({ itemId = 1 }, { lv(250, 20) }, nil), nil, "under market with no market")

-- priceMoved
eq(S.moved(1000, 1100), false, "10% is fine")
eq(S.moved(1000, 1101), true, "more is not")
eq(S.moved(1000, 900), false, "cheaper is fine")

-- The list string
local lists = {
	{ name = "Alchemy mats", entries = { { itemId = 13463, maxUnit = 17000 }, { itemId = 8925 } } },
	{ name = "Snipe", entries = { { itemId = 14344 } } },
}
eq(S.text(lists), table.concat({ "list Alchemy mats", "item 13463 max 17000", "item 8925 market", "list Snipe", "item 14344 market" }, "\n"), "plain lines")
local back = S.decode(S.encode(lists))
eq(back and S.text(back), S.text(lists), "reads back")
-- The site's own string for the same lists (btoa of the lines), read as the addon would.
eq(S.text(S.decode("GFL1:" .. E.base64(S.text(lists)))), S.text(lists), "a string from the site")
local function wrap(t) return "GFL1:" .. E.base64(t) end
local _, err = S.decode("GFP1:abc")
eq(err and err:find("GFL1:", 1, true) ~= nil, true, "names the prefix")
_, err = S.decode(wrap("item 1 market"))
eq(err and err:find("Line 1", 1, true) ~= nil, true, "names the line")
eq((S.decode(wrap("list a\nitem 1 max 0"))), nil, "a zero price")
eq((S.decode(wrap("list a\nitem 1 cheap"))), nil, "an unknown word")
eq((S.decode(wrap("list a\nitem 1 pct 0"))), nil, "a zero share")
eq((S.decode(wrap("list a\nitem 1 pct 1001"))), nil, "a share over 1000%")
eq((S.decode(wrap("list a\nitem 1 market upto 0"))), nil, "up to none")
eq((S.decode(wrap("list a\nitem 1 upto 5"))), nil, "upto with no price word")
eq((S.decode("GFL1:@@@@")), nil, "damaged")
eq(#S.decode(wrap(string.rep("list a\n", 50))), 50, "fifty lists")
_, err = S.decode(wrap(string.rep("list a\n", 51)))
eq(err, "More than 50 lists", "a string cannot fill the save with lists")
eq(S.decode(wrap("list |cffff0000Free|r\nitem 1 market"))[1].name, "cffff0000Freer", "the game's escapes stripped")

-- A list for one character: "for <GUID>" after its list line (gold-forever/gold-forever#13); none, every character.
local GUID = "Player-1234-0ABC1234"
local scoped = S.decode(wrap("list Mine\nfor " .. GUID .. "\nitem 1 market\nlist Everyone\nitem 2 market"))
eq(scoped[1].character, GUID, "the list is for that character")
eq(scoped[1].entries[1].itemId, 1, "its items read as before")
eq(scoped[2].character, nil, "a list without a for line: every character")
eq(S.text({ { name = "Mine", character = GUID, entries = { { itemId = 1 } } } }), "list Mine\nfor " .. GUID .. "\nitem 1 market", "the for line straight after the list line")
eq(S.decode(S.encode(scoped))[1].character, GUID, "the scope reads back")
eq((S.decode(wrap("for " .. GUID .. "\nlist a"))), nil, "a for line before any list")
eq((S.decode(wrap("list a\nfor " .. GUID .. "\nfor " .. GUID))), nil, "two for lines")
eq((S.decode(wrap("list a\nfor Bob"))), nil, "not a character's GUID")
eq((S.decode(wrap("list a\nfor Player-1234-0ABC123"))), nil, "seven hex digits")
eq((S.decode(wrap("list a\nfor Player-123456-0ABC1234"))), nil, "a six-digit server id")
-- One rule for a "for" line's character, lists' and profiles' alike.
eq(S.forLine("for " .. GUID), GUID, "a for line names its character")
eq(S.forLine("for Bob"), nil, "not a character's GUID")
eq(S.forLine("for Player-1234-0abc1234"), nil, "lower-case hex")
eq(S.forLine("for Player-1234-0ABC1234 x"), nil, "a word after the GUID")
-- A line it does not know is skipped, the rest read: a later format change cannot break a list again.
local later = S.decode(wrap("list a\nnote raid on thursday\nitem 1 market\ncolour blue\nlist b\nitem 2 max 5"))
eq(later and #later .. " " .. #later[1].entries .. " " .. later[2].entries[1].maxUnit, "2 1 5", "unknown lines skipped")
eq(#S.decode(wrap("version 2\nlist a")), 1, "an unknown line before any list")

-- Which lists show for the logged-in character: its own and every character's.
eq(S.forCharacter({ name = "a" }, GUID), true, "no scope: every character")
eq(S.forCharacter({ name = "a", character = GUID }, GUID), true, "this character's")
eq(S.forCharacter({ name = "a", character = "Player-1234-0ABC9999" }, GUID), false, "another character's")
eq(S.forCharacter({ name = "a", character = GUID }, nil), false, "no GUID known: only every character's")

-- The Shop's field: a link or an ID, then a price in gold or none.
local link = "|cffffffff|Hitem:2589::::::::30:::::|h[Linen Cloth]|h|r"
local id, max = S.parseAdd(link .. " 1.5")
eq(id, 2589, "the link's item")
eq(max, 15000, "1.5 gold")
id, max = S.parseAdd(link .. " ")
eq(id .. tostring(max), "2589nil", "no price: under market")
id, max = S.parseAdd("2589 0.25g")
eq(id .. "/" .. max, "2589/2500", "an ID typed, a price with g")
eq(S.parseAdd("Linen"), nil, "no item")
id, max = S.parseAdd(link .. " cheap")
eq(id .. tostring(max), "2589nil", "a price not understood is none")

-- After a scan: the items listed at or under their price, each once.
local scan = { [1] = 900, [2] = 2000, [3] = 500 }
local market = { [3] = 600 }
local under = S.underPrice({
	{ entries = { { itemId = 1, maxUnit = 1000 }, { itemId = 2, maxUnit = 1500 }, { itemId = 3 } } },
	{ entries = { { itemId = 1, maxUnit = 950 }, { itemId = 4, maxUnit = 99 } } },
}, function(id) return scan[id] end, function(id) return market[id] end)
eq(table.concat(under, ","), "1,3", "under the max, under market; once each; unlisted items left out")

-- Merging what the companion carries: by id, the newer wins, the other dropped; no copies (owner, 2026-10-24).
local mine = { { id = "a", edited = 100, name = "Mats" }, { id = "b", edited = 300, name = "Snipe" } }
local merged, changed = S.merge(mine, {
	{ id = "a", edited = 200, name = "Mats v2" }, -- newer from the site: replaces
	{ id = "b", edited = 250, name = "Snipe old" }, -- older from the site: the game's stays
	{ id = "c", edited = 50, name = "Herbs" }, -- new: added
})
local names = {}
for i, l in ipairs(merged) do names[i] = l.name end
eq(table.concat(names, "|"), "Mats v2|Snipe|Herbs", "replaced, kept, added; no copies")
eq(changed, 2, "two changes")
local again, changedAgain = S.merge(merged, { { id = "b", edited = 250, name = "Snipe old" } })
eq(#again .. ":" .. changedAgain, "3:0", "the site's stale version again: nothing")
-- A list deleted in the game stays deleted, unless edited on the site after; a site copy is never taken.
local kept = S.merge({}, { { id = "d", edited = 100, name = "Deleted" }, { id = "e", edited = 500, name = "Edited after" },
	{ id = "f", edited = 100, name = "Old (older copy)", copyOf = "a" } }, { d = 200, e = 200 })
eq(#kept .. kept[1].name, "1Edited after", "deleted stays deleted; edited after comes back; no copies")
-- The copies earlier merges kept are taken out.
local withCopies = { { id = "a", name = "Mats" }, { id = "x", name = "Mats (older copy)", copyOf = "a" }, { id = "y", name = "Mine" } }
eq(S.dropCopies(withCopies), 1, "one copy dropped")
eq(#withCopies .. withCopies[2].name, "2Mine", "the player's own lists stay")

-- The entry in use found again after copies are dropped (review B-11): profiles [A copy, B, C] with B in
-- use (2); after the drop B is at 1, not C at 2.
do
	local A, B, C = { id = "a" }, { id = "b" }, { id = "c" }
	local items = { { id = "x", copyOf = "a" }, B, C, A }
	local was = items[2]
	S.dropCopies(items)
	eq(S.refind(items, was), 1, "the same profile, at its new place")
	local newer = { id = "b", edited = 9 }
	eq(S.refind({ A, newer, C }, B), 2, "replaced by a newer copy: found by its id")
	eq(S.refind({ A, C }, { id = "y", copyOf = "c" }), 2, "a dropped copy: the one it was copied from")
	eq(S.refind({ A, C }, B), nil, "gone")
	eq(S.refind({ A }, nil), nil, "nothing in use")
end

-- The Buy tab's deal for an entry (review C-14): lowest, How many, or neither.
do
	local book = { lv(250, 20), lv(300, 10, 4), lv(420, 30) }
	local d = S.entryDeal({ itemId = 1, maxUnit = 300 }, book, 99, nil)
	eq(d.quantity .. " " .. d.total .. " " .. d.topUnit, "26 6800 300", "no How many: every unit at or under the price, held not counted")
	d = S.entryDeal({ itemId = 1, maxUnit = 300, upTo = 30 }, book, 10, nil)
	eq(d.quantity .. " " .. d.total .. " " .. d.topUnit .. " " .. d.limit, "20 5000 250 300", "How many 30 holding 10: 20 more, cheapest first")
	eq(S.entryDeal({ itemId = 1, maxUnit = 300, upTo = 30 }, book, 30, nil), nil, "holding enough: nothing")
	eq(S.entryDeal({ itemId = 1, upTo = 30 }, book, 0, nil), nil, "under market with no market: nothing")
	eq(S.entryDeal({ itemId = 1, maxUnit = 100, upTo = 30 }, book, 0, nil), nil, "nothing cheap enough")
	local low = S.entryDeal({ itemId = 7, lowest = 120, upTo = 20 }, { lv(1300, 50), lv(1500, 10) }, 7, 1000)
	eq(low.quantity .. " " .. tostring(low.over), "13 true", "lowest with How many: as lowestDeal")
	eq(S.entryDeal({ itemId = 7, lowest = 120 }, { lv(900, 10) }, 0, 1000).quantity, 10, "lowest without How many: a plain deal at its share")
end

return checks()
