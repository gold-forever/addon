-- Shopping.lua: the playground's shopping.test.ts cases, in Lua.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Shopping.lua"], "@Shopping.lua"))("GoldForever", ns)
local S, E = ns.Shopping, ns.Encode

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end
local function lv(unitPrice, quantity, own) return { unitPrice = unitPrice, quantity = quantity, own = own or 0 } end

-- Every function is there as soon as the file loads (one was once defined inside encode by mistake).
for _, name in ipairs({ "limit", "deal", "moved", "text", "encode", "decode", "parseAdd", "underPrice", "merge" }) do
	eq(type(S[name]), "function", "defined at load: " .. name)
end

-- entryLimit
eq(S.limit({ itemId = 1, maxUnit = 500 }, 900), 500, "its own price")
eq(S.limit({ itemId = 1 }, 900), 899, "a copper under market")
eq(S.limit({ itemId = 1 }, nil), nil, "no market, no limit")
-- A share of the market value, and how many to hold (owner's answer, 2026-10-24).
eq(S.limit({ itemId = 1, pct = 80 }, 1000), 800, "80% of market")
eq(S.parseGold("4.5"), 45000, "gold with a point")
eq(S.parseGold("4,5"), 45000, "or a comma")
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

-- Merging what the companion carries (decision 11): by id, the newer wins, the loser kept once.
local n = 0
local function newId() n = n + 1 return "new" .. n end
local mine = { { id = "a", edited = 100, name = "Mats" }, { id = "b", edited = 300, name = "Snipe" } }
local merged, changed = S.merge(mine, {
	{ id = "a", edited = 200, name = "Mats v2" }, -- newer from the site: replaces, the game's kept as a copy
	{ id = "b", edited = 250, name = "Snipe old" }, -- older from the site: the game's stays, the site's kept as a copy
	{ id = "c", edited = 50, name = "Herbs" }, -- new: added
}, newId)
local names = {}
for i, l in ipairs(merged) do names[i] = l.name end
eq(table.concat(names, "|"), "Mats v2|Snipe|Mats (older copy)|Snipe old (older copy)|Herbs", "replaced, kept, copied, added")
eq(changed, 3, "three changes")
local again, changedAgain = S.merge(merged, { { id = "b", edited = 250, name = "Snipe old" } }, newId)
eq(#again .. ":" .. changedAgain, "5:0", "a loser already kept is not kept twice")
local same, none = S.merge({ { id = "a", edited = 100, name = "x" } }, { { id = "a", edited = 100, name = "x" } }, newId)
eq(#same .. ":" .. none, "1:0", "the same edit: nothing")

return checks
