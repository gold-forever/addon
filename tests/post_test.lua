-- Post.lua: the price to post at, the playground's suggestPost rule in whole silver.

local ns = {}
loadEncode(ns)
assert(load(SOURCES["Post.lua"], "@Post.lua"))("GoldForever", ns)
assert(load(SOURCES["SalePlan.lua"], "@SalePlan.lua"))("GoldForever", ns)
local P = ns.Post

local rule = P.DEFAULT
-- Market value 1g: floor 80s, normal 1g 20s.
local s = P.suggest(rule, 10000, nil)
eq(s.reason, "alone", "nobody else")
eq(s.unit, 12000, "the normal price")
eq(s.floor, 8000, "floor at 80%")

s = P.suggest(rule, 10000, 9550)
eq(s.reason, "undercut", "undercut")
eq(s.unit, 9400, "a silver under 95s 50c, in whole silver")

-- A rising market (gf#368): the cheapest well over 120% of the market is still undercut.
s = P.suggest(rule, 10000, 15000)
eq(s.reason .. s.unit, "undercut14900", "a rising market: a silver under the cheapest, over 1.2x")
s = P.suggest(rule, 10000, 30000)
eq(s.reason .. s.unit, "undercut29900", "up to 3x the market: still undercut")

s = P.suggest(rule, 10000, 7000)
eq(s.reason, "hold", "the cheapest is under the floor")
eq(s.unit, nil, "nothing to post")

s = P.suggest({ undercut = "1s", floor = 80, normal = 120, belowFloor = "floor" }, 10000, 7000)
eq(s.reason, "floor", "post at the floor instead")
eq(s.unit, 8000, "at the floor")

s = P.suggest({ undercut = "5%", floor = 80, normal = 120 }, 10000, 10000)
eq(s.unit, 9500, "five percent under")

s = P.suggest(rule, 10000, 8050)
eq(s.reason, "hold", "a silver under would round below the floor")

-- Cheap items: never under a silver.
eq(P.silver(37), 100, "at least a silver")
eq(P.suggest(rule, 50, nil).unit, 100, "a copper item posts at a silver")

-- Sanity checks ask for a second press.
eq(P.check(100, 10000, 50, 0.05), "more than half under the market value", "far under market")
eq(P.check(100, nil, 200, 0.05), "under what a vendor pays", "under vendor after the cut")
eq(P.check(9400, 10000, 200, 0.05), nil, "a normal post")

-- Cancel undercut: how far under, as the playground's undercutPct.
eq(P.undercutPct(2100, 1900), 9.5, "9.5% under")
eq(P.undercutPct(2100, 2100), 0, "level")
eq(P.undercutPct(2100, 2500), 0, "dearer")
eq(P.undercutPct(2100, nil), 0, "nobody")
-- The sneaky-price guard, the sale plans' own (SalePlan.clean): up to two cheap units far under the next
-- price are passed over; more, or close, count.
local function lv(u, q, own) return { unitPrice = u, quantity = q, own = own or 0 } end
eq(P.honestCheapest({ lv(1000, 1), lv(2000, 20) }), 2000, "a single cheap unit far under is a sneaky price")
eq(P.honestCheapest({ lv(1000, 2), lv(2000, 20) }), 2000, "two units are too")
eq(P.honestCheapest({ lv(1000, 3), lv(2000, 20) }), 1000, "three units count")
eq(P.honestCheapest({ lv(1900, 1), lv(2000, 20) }), 1900, "one unit close to the next counts")
eq(P.honestCheapest({ lv(1500, 5, 5), lv(2000, 20) }), 2000, "the player's own units are left out")
eq(P.honestCheapest({}), nil, "an empty book")
-- Two definitions once disagreed here (review B-12): 100 by one, 1000 by the other.
eq(P.honestCheapest({ lv(100, 1), lv(110, 1), lv(1000, 50) }), 1000, "two cheap single units under a real price")
local kept = ns.SalePlan.clean({ lv(100, 1), lv(110, 1), lv(1000, 50) })
eq(kept[1].unitPrice, 1000, "the sale plan's guard agrees")
eq(P.honestCheapest({ lv(500, 1) }, 2000), nil, "a few units far under the market: none to react to")
eq(P.honestCheapest({ lv(500, 1) }), 500, "no market: kept")

-- What Sell suggests (Post.advise): the rule's suggestion; held under the floor, what undercutting would
-- ask anyway; with no market value, the cheapest stands in for it; with neither, nothing.
local sug, anyway = P.advise(rule, 10000, 9550)
eq(sug.reason .. sug.unit .. ":" .. tostring(anyway), "undercut9400:nil", "undercut, nothing held")
sug, anyway = P.advise(rule, 10000, 7000)
eq(sug.reason .. ":" .. anyway, "hold:6900", "held under the floor, a silver under 70s anyway")
sug, anyway = P.advise(rule, nil, 5000)
eq(sug.reason .. sug.unit, "undercut4900", "no market value: the cheapest stands in")
eq(P.advise(rule, nil, nil), nil, "neither: no suggestion")
eq(P.advise(rule, 10000, nil).reason, "alone", "nobody else")

-- Cancel undercut's list: past the tolerance, most undercut first.
local list = P.undercutList({ { id = 1, unit = 2100, cheapest = 1900 }, { id = 2, unit = 1000, cheapest = 990 }, { id = 3, unit = 1000, cheapest = 800 }, { id = 4, unit = 500 } }, 5)
eq(#list .. ":" .. list[1].id .. list[2].id, "2:31", "the 20% then the 9.5%; 1% and none left out")
eq(list[1].under, 20, "its under set")

-- Items ahead (gf#369): other players' units listed under the auction's price, own units left out.
local book = { { unitPrice = 900, quantity = 5, own = 2 }, { unitPrice = 950, quantity = 1, own = 0 }, { unitPrice = 1000, quantity = 10, own = 10 }, { unitPrice = 1100, quantity = 4, own = 0 } }
eq(P.ahead(1000, book), 4, "3 others at 90s and 1 at 95s; ours and the dearer ones not")
eq(P.ahead(900, book), 0, "none under the cheapest")
eq(P.ahead(1000, nil), 0, "no book: none")

-- The Cancel view's two lists (gf#369): undercut by more than `ahead` items, most ahead first; and
-- those the rule would post more than `tolerance` percent higher now, most gained first. Unsearched
-- ones (no levels) are in neither.
local review = P.cancelReview({
	{ id = 1, unit = 1000, levels = book }, -- 4 ahead
	{ id = 2, unit = 1000, levels = { { unitPrice = 990, quantity = 3, own = 0 } } }, -- 3 ahead: within
	{ id = 3, unit = 1000, levels = { { unitPrice = 800, quantity = 20, own = 0 } } }, -- 20 ahead
	{ id = 4, unit = 1000, levels = {}, repost = 1500 }, -- alone now: 50% higher
	{ id = 5, unit = 1000, levels = {}, repost = 1040 }, -- 4% higher: within
	{ id = 6, unit = 1000, levels = {}, repost = 1200 }, -- 20% higher
	{ id = 7, unit = 1000, repost = 2000 }, -- not searched
}, 3, 5)
local function ids(l) local t = {} for _, a in ipairs(l) do t[#t + 1] = a.id end return table.concat(t, ",") end
eq(ids(review.undercut), "3,1", "past 3 ahead, most ahead first")
eq(review.undercut[1].ahead, 20, "its ahead set")
eq(ids(review.higher), "4,6", "past 5% higher, most gained first")
eq(review.higher[1].up, 50, "its up set, in percent")
local twice = P.cancelReview({ { id = 8, unit = 1000, levels = { { unitPrice = 900, quantity = 9, own = 0 } }, repost = 5000 } }, 3, 5)
eq(ids(twice.undercut) .. "|" .. ids(twice.higher), "8|", "undercut wins over higher")
eq(#P.cancelReview({ { id = 9, unit = 1000, levels = {}, repost = nil } }, 3, 5).higher, 0, "held now: not higher")

-- Overrides: an item's over its category's over the default; only the fields an override holds change.
local base = { undercut = "1s", floor = 80, normal = 120, belowFloor = "hold" }
local overrides = { items = { [2589] = { floor = 50 } }, classes = { [7] = { undercut = "5%", normal = 150 } } }
local r, from = P.resolve(base, overrides, 2589, 7)
eq(from .. r.floor .. r.undercut .. r.normal, "item501s120", "the item's override, the rest the default's")
r, from = P.resolve(base, overrides, 2592, 7)
eq(from .. r.undercut .. r.normal .. r.floor, "category5%15080", "the category's")
r, from = P.resolve(base, overrides, 1, 2)
eq(from, "default", "no override")
eq(r, base, "the default itself")
eq(P.resolve(base, nil, 1, nil), base, "no overrides at all")

-- A client whose auction house takes copper: copper prices, a copper undercut.
P.copper = true
eq(P.silver(9437), 9437, "copper kept")
eq(P.suggest({ undercut = "1c", floor = 80, normal = 120 }, 10000, 9550).unit, 9549, "a copper under")
-- Alone in copper mode: the normal price to the copper, not 50 copper over it (review B-13).
s = P.suggest(rule, 10000, nil)
eq(s.reason .. " " .. s.unit, "alone 12000", "copper mode, nobody else: 120% of the market exactly")
eq(P.suggest(rule, 10041, nil).unit, 12049, "copper mode: down to the copper")
P.copper = false
eq(P.suggest(rule, 10041, nil).unit, 12000, "silver mode: to the nearest silver")
eq(P.suggest({ undercut = "1c", floor = 80, normal = 120 }, 10000, 9550).unit, 9500, "whole silver otherwise")

-- The default undercut is the auction house's smallest step (owner's screenshot, 2026-11-12: Sweet Nectar
-- at 1s 50c, "Post anyway" offered 50c, a whole silver off).
eq(P.DEFAULT.undercut, "step", "the default undercut is the step")
P.copper = true
local loose = { undercut = "step", floor = 1, normal = 120 }
eq(P.suggest(loose, 214, 150).unit, 149, "copper auction house: 1 copper under 1s 50c")
eq(P.suggest({ undercut = "1s", floor = 1, normal = 120 }, 214, 150).unit, 143, "1 silver is capped at 5% of the cheapest: 7c off 1s 50c, not 50c")
eq(P.suggest({ undercut = "1s", floor = 1, normal = 120 }, 100000, 90000).unit, 89900, "1 silver off a price it is under 5% of: a whole silver")
P.copper = false
eq(P.suggest(loose, 30000, 25000).unit, 24900, "silver auction house: 1 silver under")
eq(P.suggest({ undercut = "nonsense", floor = 1, normal = 120 }, 30000, 25000).unit, 24900, "an unknown undercut is the step")

-- The trend's advice: rising at 10% over the typical price (the 7-day median), falling at 10% under, else none.
eq(P.trendHint(12), "rising: maybe wait", "well over the typical price")
eq(P.trendHint(10), "rising: maybe wait", "at the threshold")
eq(P.trendHint(-15), "falling", "well under")
eq(P.trendHint(9), nil, "near the typical price: no advice")
eq(P.trendHint(nil), nil, "no trend known")

-- What a rule does, in sentences for an item worth 10g (manual test run 001: the rule was hard to read).
local ex = P.examples(P.DEFAULT, function(c) return c .. "c" end)
eq(#ex, 4, "four situations")
eq(ex[1], "Someone lists it at 95000c: you post at 94900c (undercut)", "a little under the market")
eq(ex[2], "No one else lists it: you post at 120000c (no one else)", "alone")
eq(ex[3], "The cheapest is 50000c: you hold it, as it is under your floor", "under the floor, held")
eq(ex[4], "The cheapest is 400000c: you post at 300000c (at the maximum)", "far over: the maximum")
local atFloor = P.examples({ undercut = "1s", floor = 80, normal = 120, belowFloor = "floor" }, function(c) return c .. "c" end)
eq(atFloor[3], "The cheapest is 50000c: you post at 80000c (at floor)", "or posted at the floor")

-- gf#368: the maximum against outliers, the vendor floor, the day price when alone, the reasons.
do
	-- An outlier over 3x the market: posted at the maximum, never over it.
	local o = P.suggest(rule, 10000, 40000)
	eq(o.reason .. o.unit .. ":" .. o.times, "maximum30000:3", "an outlier over 3x: at the maximum, 3x")
	-- Highly volatile: 5x.
	o = P.suggest(rule, 10000, 40000, { volatile = true })
	eq(o.reason .. o.unit, "undercut39900", "volatile: 4x is under its 5x maximum, undercut")
	o = P.suggest(rule, 10000, 60000, { volatile = true })
	eq(o.reason .. o.unit .. ":" .. o.times, "maximum50000:5", "volatile: at the maximum, 5x")
	-- The maximums are the rule's, changeable.
	o = P.suggest({ undercut = "1s", floor = 80, normal = 120, maximum = 2, volatileMaximum = 4 }, 10000, 40000)
	eq(o.reason .. o.unit, "maximum20000", "a maximum of 2x")
	-- The floor: the higher of 80% of the market and the vendor price after the cut (9000 / 0.95, up to the silver).
	o = P.suggest(rule, 10000, 9550, { vendor = 9000, cut = 0.05 })
	eq(o.reason .. ":" .. o.floor .. ":" .. o.floorBy, "hold:9500:vendor", "under the vendor price after the cut: held")
	o = P.suggest(rule, 10000, 9550, { vendor = 5000, cut = 0.05 })
	eq(o.reason .. o.unit .. ":" .. o.floor .. ":" .. o.floorBy, "undercut9400:8000:market", "a low vendor price: the market's floor")
	o = P.suggest({ undercut = "1s", floor = 80, normal = 120, belowFloor = "floor" }, 10000, 9550, { vendor = 9000, cut = 0.05 })
	eq(o.reason .. o.unit, "floor9500", "post at the floor: the vendor floor")
	-- Post anyway under the vendor floor: what undercutting would ask.
	local held, anyway = P.advise(rule, 10000, 9550, { vendor = 9000, cut = 0.05 })
	eq(held.reason .. ":" .. tostring(anyway), "hold:9400", "held under the vendor price, Post anyway at the undercut")
	-- Alone: the higher of 120% and today's price, at most the maximum.
	o = P.suggest(rule, 10000, nil, { day = 15000 })
	eq(o.reason .. o.unit .. ":" .. tostring(o.day), "alone15000:true", "alone with a day price over 120%: today's price")
	o = P.suggest(rule, 10000, nil, { day = 11000 })
	eq(o.reason .. o.unit .. ":" .. tostring(o.day), "alone12000:false", "a day price under 120%: 120%")
	o = P.suggest(rule, 10000, nil, { day = 90000 })
	eq(o.reason .. o.unit, "alone30000", "a day price over the maximum: the maximum")
	o = P.suggest(rule, 10000, nil, { vendor = 20000, cut = 0.05 })
	eq(o.unit, 21100, "alone, the vendor floor over 120%: the floor")

	-- The reasons, as Sell names them.
	local function m(c) return c .. "c" end
	eq(P.label(P.suggest(rule, 10000, 9550), rule, m, true), "Undercut 100c (live)", "undercut, live")
	eq(P.label(P.suggest(rule, 10000, 9550), rule, m, false), "Undercut 100c (last scan)", "undercut, from the scan for the list")
	eq(P.label(P.suggest({ undercut = "5%" }, 10000, 9550), { undercut = "5%" }, m, true), "Undercut 5% (live)", "a share")
	eq(P.label(P.suggest(rule, 10000, 40000), rule, m, true), "At the maximum, 3x market", "the maximum")
	eq(P.label(P.suggest(rule, 10000, 60000, { volatile = true }), rule, m, true), "At the maximum, 5x market", "the volatile maximum")
	eq(P.label(P.suggest(rule, 10000, 9550, { vendor = 9000, cut = 0.05 }), rule, m, true), "Held: under the vendor price", "held by the vendor price")
	eq(P.label(P.suggest(rule, 10000, 7000), rule, m, true), "Held: under your floor", "held by the floor")
	eq(P.label(P.suggest(rule, 10000, nil, { day = 15000 }), rule, m, true), "Alone: today's price", "alone at the day price")
	eq(P.label(P.suggest(rule, 10000, nil), rule, m, true), "Alone: 120% of market", "alone at 120%")
	eq(P.label(nil, rule, m, true), nil, "no suggestion: no label")
	eq(P.DEFAULT.maximum .. P.DEFAULT.volatileMaximum .. P.DEFAULT.supplyDays, "352", "the defaults: 3x, 5x, 2 days")
	-- The day count of the post size, worded for any number.
	eq(P.supplyReason(2), "2 days of supply", "two days")
	eq(P.supplyReason(1), "1 day of supply", "one day")
end

-- The player's own auctions as the Auctions tab reads them (review C-14).
do
	local infos = {
		{ auctionID = 1, itemKey = { itemID = 2589 }, status = 0, buyoutAmount = 120, quantity = 20 },
		{ auctionID = 2, itemKey = { itemID = 14047, itemLevel = 30 }, status = 0, buyoutAmount = 9001, quantity = 2 },
		{ auctionID = 3, itemKey = { itemID = 2589 }, status = 1, buyoutAmount = 120, quantity = 5 },
		{ auctionID = 4, itemKey = { itemID = 2592 }, status = 0, buyoutAmount = 0 },
		nil,
		{ auctionID = 6, itemKey = { itemID = 4306 }, buyoutAmount = 700 },
	}
	local keys = { [2589] = { isCommodity = true, itemName = "Linen Cloth" }, [14047] = { isCommodity = false } }
	local names = { [14047] = { 3, "Runecloth" } }
	local owned = P.readOwned(6, function(i) return infos[i] end, function(k) return keys[k.itemID] end, function(id)
		local x = names[id]
		if x then
			return x[1], nil, nil, nil, x[2]
		end
	end)
	eq(#owned, 3, "active ones with a buyout: sold, no buyout and missing left out")
	eq(owned[1].unit .. " " .. tostring(owned[1].commodity) .. " " .. owned[1].name .. " " .. owned[1].quality, "120 true Linen Cloth 1", "a commodity: its buyout is the unit price")
	eq(owned[2].unit .. " " .. owned[2].quantity .. " " .. owned[2].name .. " " .. owned[2].quality .. " " .. owned[2].itemKey.itemLevel, "9001 2 Runecloth 3 30", "an item: its buyout is per unit too, not divided by the quantity")
	eq(owned[3].name .. " " .. owned[3].quantity .. " " .. tostring(owned[3].commodity), "item 4306 1 false", "no names and no key info: by its id, one, not a commodity")
	eq(#P.readOwned(0, nil, nil, nil), 0, "no auctions")
	eq(P.readOwned(1, function() return infos[1] end, nil, function() end)[1].commodity, false, "a client without key info: not a commodity")
end

-- The account's characters as an auction's owners name them (gf#375): bare on the player's realm,
-- "Name-Realm" (spaces and hyphens dropped) on any realm of the region.
do
	local chars = {
		a = { name = "Main", realm = "Argent Dawn", region = "EU" },
		b = { name = "Alt", realm = "Argent Dawn", region = "EU" },
		c = { name = "Far", realm = "Azjol-Nerub", region = "EU" },
		d = { name = "Yank", realm = "Argent Dawn", region = "US" },
		e = { realm = "Argent Dawn", region = "EU" },
	}
	local names = P.ownerNames(chars, "Argent Dawn", "EU")
	eq(tostring(names.Alt) .. tostring(names["Alt-ArgentDawn"]) .. tostring(names["Far-AzjolNerub"]), "truetruetrue", "same realm bare and suffixed, another realm suffixed")
	eq(tostring(names.Far) .. tostring(names.Yank) .. tostring(names["Yank-ArgentDawn"]), "nilnilnil", "another realm never bare; another region never")
	eq(next(P.ownerNames(nil, "Argent Dawn", "EU")), nil, "no characters: no names")
end

-- Gear levels with the account's alts' auctions counted as own (gf#375): an auction is the account's
-- when every owner it names is one of its characters.
do
	local levels = {
		{ unitPrice = 100, quantity = 1, own = 0, auctionID = 1 },
		{ unitPrice = 110, quantity = 2, own = 0, auctionID = 2 },
		{ unitPrice = 120, quantity = 1, own = 0, auctionID = 3 },
		{ unitPrice = 130, quantity = 1, own = 1, auctionID = 4 },
		{ unitPrice = 140, quantity = 1, own = 0 },
	}
	local owners = { [1] = { "Alt" }, [2] = { "Alt", "Stranger" }, [3] = {}, [4] = { "Main" } }
	local names = { Alt = true, Main = true }
	local marked, alts = P.withAlts(levels, owners, names)
	eq(marked[1].own .. marked[2].own .. marked[3].own .. marked[4].own .. marked[5].own, "10010", "an alt's alone: own; with a stranger, none named or no id: not")
	eq(tostring(alts[1]) .. tostring(alts[2]) .. tostring(alts[4]), "truenilnil", "the alts' auctions by id, the player's own not among them")
	eq(levels[1].own, 0, "the book itself is left as it was")
	eq(marked[2].auctionID, 2, "the other fields kept")
	local same = P.withAlts(levels, { [2] = { "Stranger" } }, names)
	eq(same == levels, true, "no alt among them: the same levels")
	eq(P.withAlts(nil, owners, names), nil, "no levels: none")
end

return checks()
