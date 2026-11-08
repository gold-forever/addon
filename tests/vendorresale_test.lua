-- VendorResale.lua and ResaleSales.lua: a merchant item that fetches at least 20% more on the auction house after the 5% cut, and
-- has sales, is marked; one with no price, no sales, a thin margin or a cost other than gold is not.

local ns = { on = function() end, settings = function() return {} end, retail = false, Money = {} }
loadEncode(ns)
assert(load(SOURCES["Scans.lua"], "@Scans.lua"))("GoldForever", ns)
ns.Money.auction = function(copper) return copper .. "c" end
ns.me = function() return { faction = "Horde" } end
ns.market = function(side) return "R-" .. side end

local values, weeks, solds = {}, {}, {}
local saved = { scans = {} }
ns.price = { cut = 0.05, market = function(id) return values[id] end }
ns.Prices = { value = function(id) return values[id], "pool", nil, weeks[id] end,
	supply = function(id) return solds[id] end, perDay = function(sold) return string.format("%d", sold / 7) end }
ns.db = function() return saved end
assert(load(SOURCES["ResaleSales.lua"], "@ResaleSales.lua"))("GoldForever", ns)
assert(load(SOURCES["VendorResale.lua"], "@VendorResale.lua"))("GoldForever", ns)
local V = ns.VendorResale
local hasSales = ns.ResaleSales.hasSales

local function full(market, rows, kind) return { kind = kind or "full", market = market, t = 1, rows = rows } end
local function sold(id, price, stack, more)
	local item = { id = id, price = price, stack = stack or 1, available = -1 }
	for k, v in pairs(more or {}) do item[k] = v end
	return item
end

-- The margin: market value × 0.95 against 1.2 × the vendor's price of one, on the boundary too.
values[1], weeks[1] = 1200, 1100
local offer = V.offer(sold(1, 950))
eq(offer and offer.gain, 190, "exactly 20% over: an offer, the gain after the cut")
eq(V.offer(sold(1, 951)), nil, "just under 20%: nothing")

-- The vendor's stack is counted: 5 for 4750 is 950 each.
offer = V.offer(sold(1, 4750, 5))
eq(offer and offer.value, 1200, "a stack priced per unit: the market value of one")
eq(offer and offer.gain, 190, "and the gain on one")
eq(V.offer(sold(1, 4755, 5)), nil, "a stack just under the margin: nothing")

-- No price; costs other than gold.
eq(V.offer(sold(2, 100)), nil, "no market value: nothing")
eq(V.offer(sold(1, 100, 1, { extended = true })), nil, "gold and tokens: nothing")
eq(V.offer(sold(1, 0, 1, { extended = true })), nil, "tokens only: nothing")
eq(V.offer(sold(1, 0)), nil, "no gold price: nothing")
eq(V.offer(sold(nil, 100)), nil, "no item id: nothing")

-- Sales: a typical price, or the item in two of the character's own full scans.
values[3] = 5000
eq(hasSales(3), false, "no typical price, no scans: no sales")
eq(V.offer(sold(3, 100)), nil, "no sales: nothing")
weeks[3] = 4900
eq(hasSales(3), true, "a typical price is sales")
weeks[3] = nil
saved.scans = { full("R-horde", { "3,50,1,1,2;4,60,1,1,2" }) }
eq(hasSales(3), false, "one scan is not enough")
ns.scanVersion = 1
saved.scans[2] = full("R-horde", { "9,1,1,1,1", "7,1,1,1,1;3:612,50,1,1,2" })
eq(hasSales(3), true, "two full scans, a random-suffix key and a later chunk too")

ns.scanVersion = 2
saved.scans = { full("R-horde", { "33,1,1,1,1;13,1,1,1,1" }), full("R-horde", { "3,1,1,1,1" }) }
eq(hasSales(3), false, "another item's id containing the digits does not count")
ns.scanVersion = 3
saved.scans = { full("R-horde", { "3,1,1,1,1" }), full("R-alliance", { "3,1,1,1,1" }), full("R-horde", { "3,1,1,1,1" }, "partial") }
eq(hasSales(3), false, "another market's scan and a partial scan do not count")
ns.scanVersion = 4
ns.retail = true
saved.scans = { full("R-horde", { "3,1,1,1,1" }), full("R-neutral", { "3,1,1,1,1" }) }
eq(hasSales(3), true, "retail: any side's scan of the realm group counts")
ns.retail = false

-- The answer is kept until a new scan, so a long scan list is read once.
ns.scanVersion = 5
saved.scans = {}
eq(hasSales(3), false, "read for this scan")
saved.scans = { full("R-horde", { "3,1,1,1,1" }), full("R-horde", { "3,1,1,1,1" }) }
eq(hasSales(3), false, "kept until a new scan")
ns.scanVersion = 6
eq(hasSales(3), true, "a new scan: read again")

-- The prices file says what sold (gf#316): that decides, over the typical price and the scans.
ns.scanVersion = 8
values[4], weeks[4], solds[4] = 5000, 4900, 0
eq(hasSales(4), false, "sold 0: no sales, a typical price or not")
eq(V.offer(sold(4, 100)), nil, "sold 0: nothing")
weeks[4], solds[4] = nil, 21
eq(hasSales(4), true, "sold > 0: sales, without a typical price")
eq(V.offer(sold(4, 100)).rate, "3", "and the offer says how many a day")
solds[4] = nil
eq(hasSales(4), false, "no sold, no typical price, no scans: today's gate")
weeks[4] = 4900
eq(hasSales(4), true, "no sold, a typical price: today's gate")
eq(V.offer(sold(4, 100)).rate, nil, "no sold: no rate")

-- Before a character is known: no sales, no error.
ns.me = function() return nil end
ns.scanVersion = 7
eq(hasSales(3), false, "no character: no sales")
ns.me = function() return { faction = "Horde" } end

-- The line and the limited flag.
eq(V.line({ value = 49800, gain = 38310 }), "Resell: 49800c on the AH · +38310c after the cut", "the line")
eq(V.line({ value = 49800, gain = 38310, limited = true }), "Resell: 49800c on the AH · +38310c after the cut (limited)", "limited")
eq(V.line({ value = 49800, gain = 38310, rate = "3" }), "Resell: 49800c on the AH (3 a day) · +38310c after the cut", "with its sales a day")
eq(V.offer(sold(1, 950, 1, { available = 3 })).limited, true, "stock left: limited")
eq(V.offer(sold(1, 950, 1, { available = 0 })).limited, true, "sold out for now: limited")
eq(V.offer(sold(1, 950)).limited, false, "-1: unlimited")
eq(V.offer(sold(1, 950, 1, { available = false })).limited, false, "stock unknown: not called limited")

return checks()
