-- Gold Forever: what an item is worth (ns.price), for the HUD, the tooltips, the loot advisor, the
-- crafting and the auction panel. Prices come from the shared pool (Prices.lua) when the companion
-- wrote one, else from the latest full scan of the character's own auction house in the saved file,
-- valued as the web app does: the better of the market value after the auction cut and the vendor price.

local _, ns = ...
local Encode = ns.Encode

local CUT = 0.05 -- a faction auction house's cut; the character sells on its own

local prices -- item ID -> market value, from the latest full scan of the character's market
local cheapestPrices -- item ID -> the cheapest unit listed in that scan
local pricedFrom -- ns.scanVersion when prices were built; a new scan (Market.lua) rebuilds them
local pricedAt -- when that scan was taken

-- A scan this size or smaller is read into prices at once; a bigger one over several frames, the prices
-- before it staying in use until it is done (design 009, Performance budget: a retail scan's ~110,000
-- rows took ~100 ms to read in one go, a hitch at the first tooltip after a scan or a login).
local SYNC_CHUNKS = 10 -- of Encode.ROWS_PER_CHUNK (500) rows: 5,000 rows
-- Without a profiling timer, this much a frame; with one, the frame budget (ns.frameSpent).
local CHUNKS_PER_FRAME = 2
local ITEMS_PER_FRAME = 500
local building -- the scan version a build in progress is for

-- A market without its side ("EU-Aszune-neutral" → "EU-Aszune"): on retail one auction house serves a
-- connected realm group, whichever side's auctioneer opened it (Market.lua keeps scans the same way).
local function group(market)
	return string.match(market or "", "^(.*)%-[^-]+$") or market
end

-- The newest full scan of the character's market, or nil: on retail any side's scan of the realm group
-- (a Horde character scanning at the Bazaar's neutral auctioneer read no prices of its own before).
local function latestScan()
	local db, me = ns.db(), ns.me()
	if not me then
		return nil
	end
	local market = ns.market(string.lower(me.faction or "?"))
	local retail = ns.Realms.isRetail(db.client and db.client.interface)
	local mine = retail and group(market)
	local latest
	for _, scan in ipairs(db.scans) do
		if scan.kind == "full" and (scan.market == market or (mine and group(scan.market) == mine)) and (not latest or scan.t > latest.t) then
			latest = scan
		end
	end
	return latest
end

-- Reads one chunk of rows into listings: item ID -> { unit1, qty1, unit2, qty2, … }, a flat list an item
-- (one table an item, not one a row) and no string a row: the pattern reads the columns in place.
local function readChunk(chunk, listings)
	for key, unit, qty in string.gmatch(chunk, "([^,;]+),(%d+),(%d+)[^;]*") do
		local id = Encode.itemId(key)
		if id then
			local l = listings[id]
			if not l then
				l = {}
				listings[id] = l
			end
			l[#l + 1] = tonumber(unit)
			l[#l + 1] = tonumber(qty)
		end
	end
end

-- One item's market value and cheapest unit into the tables given.
local function priceItem(id, l, into, low)
	into[id] = Encode.marketValueFlat(l)
	low[id] = Encode.cheapestFlat(l)
end

-- After a scan's prices are in: the deals line, once (AuctionPanel.lua says it).
local function pricesReady()
	if ns.dealsPending and ns.announceDeals then
		ns.dealsPending = nil
		C_Timer.After(0, function()
			ns.safely("deals", ns.announceDeals)
		end)
	end
end

local function buildPrices()
	local version = ns.scanVersion or 0
	local latest = latestScan()
	local chunks = latest and latest.rows or {}
	if #chunks <= SYNC_CHUNKS then
		local listings, newPrices, newLow = {}, {}, {}
		for _, chunk in ipairs(chunks) do
			readChunk(chunk, listings)
		end
		for id, l in pairs(listings) do
			priceItem(id, l, newPrices, newLow)
		end
		prices, cheapestPrices, pricedFrom, pricedAt = newPrices, newLow, version, latest and latest.t
		pricesReady()
		return
	end
	if building == version then
		return
	end
	building = version
	prices, cheapestPrices = prices or {}, cheapestPrices or {}
	local listings, newPrices, newLow, i = {}, {}, {}, 0
	local ids, j
	local rows = Encode.ROWS_PER_CHUNK
	-- One frame's share; true when the build is done.
	local function share()
		local started, done = ns.frameStart(), 0
		if i < #chunks then
			-- Counted in rows, so the budget is looked at after every chunk.
			while i < #chunks do
				i = i + 1
				readChunk(chunks[i], listings)
				done = done + rows
				if ns.frameSpent(started, done, CHUNKS_PER_FRAME * rows) then
					break
				end
			end
			return false
		end
		if not ids then
			ids, j = {}, 0
			for id in pairs(listings) do
				ids[#ids + 1] = id
			end
		end
		while j < #ids do
			j = j + 1
			priceItem(ids[j], listings[ids[j]], newPrices, newLow)
			done = done + 1
			if ns.frameSpent(started, done, ITEMS_PER_FRAME) then
				break
			end
		end
		if j < #ids then
			return false
		end
		prices, cheapestPrices, pricedFrom, pricedAt = newPrices, newLow, version, latest.t
		building = nil
		pricesReady()
		return true
	end
	local function step()
		if building ~= version then
			return -- a newer scan started its own build
		end
		-- A share that fails ends this build, so the next price asked starts a new one: left marked as
		-- building, the prices would stay those of the scan before for the rest of the session.
		local ok, finished = pcall(share)
		if not ok then
			building = nil
			error(finished, 0)
		end
		if not finished then
			ns.after(0, "prices", step)
		end
	end
	step()
end

-- The own scan's market value: the cheapest 15% of the units listed, so an item with one listing is
-- worth what that one asks.
local function ownMarket(id)
	if not prices or pricedFrom ~= (ns.scanVersion or 0) then
		buildPrices()
	end
	return prices[id]
end

-- An item's market value: the shared pool's (many players' scans, outliers dropped, a jump held until a
-- later scan confirms it), else the own scan's (manual test run 001: Poached Nettlefish "sold for"
-- 47,499g on the Crafting page from a single listing in the own scan).
local function market(id)
	if ns.Prices and ns.Prices.value then
		return (ns.Prices.value(id))
	end
	return ownMarket(id)
end

local function cheapest(id)
	ownMarket(id) -- builds the prices when needed
	return cheapestPrices[id]
end

-- What buying one costs at the auction house: the pool's minimum when the prices file has it, picked as
-- the market value is, else the own scan's cheapest (Prices.lua).
local function buy(id)
	if ns.Prices and ns.Prices.cheapest then
		return ns.Prices.cheapest(id)
	end
	return cheapest(id)
end

-- The own scan's market value, cheapest unit and time, for the pool's fallback (Prices.lua).
function ns.ownPrice(id)
	local value = ownMarket(id)
	if value then
		return value, cheapestPrices[id], pricedAt
	end
end

-- What a vendor asks for one, when it sells it without limit: catalogue.vendor is the price of one
-- purchase of qty units (fields.vendor = buy,limited,t,qty).
local function vendorBuy(id)
	local row = ns.db().catalogue.vendor[id]
	if not row then
		return nil
	end
	local buy, limited, _, qty = strsplit(",", row)
	if limited == "1" or not tonumber(buy) then
		return nil
	end
	return tonumber(buy) / math.max(1, tonumber(qty) or 1)
end

-- An item's catalogue row read once a session: { name, quality, ilvl, class, sell }. Tooltips ask for
-- the same items over and over, and splitting the whole row each time made garbage on every hover.
-- At most ROWS_KEPT items are kept (a page listing thousands would hold them all); past that it starts over.
local ROWS_KEPT = 2000
local rowsRead, rowsKept = {}, 0
local function catalogueInfo(id)
	local info = rowsRead[id]
	if info then
		return info
	end
	local row = ns.db().catalogue.items[id]
	if not row then
		return nil -- not catalogued yet: asked again next time
	end
	local name, quality, ilvl, class, _, _, sell = strsplit(",", row)
	info = { name = name, quality = tonumber(quality), ilvl = tonumber(ilvl), class = tonumber(class), sell = tonumber(sell) }
	if rowsKept >= ROWS_KEPT then
		rowsRead, rowsKept = {}, 0
	end
	rowsRead[id] = info
	rowsKept = rowsKept + 1
	return info
end

-- What a vendor pays, from the catalogue (`sell` is its 7th column), else from the client.
local function vendor(id)
	local info = catalogueInfo(id)
	local sell = info and info.sell
	if not sell and C_Item and C_Item.GetItemInfo then
		sell = (select(11, C_Item.GetItemInfo(id)))
	end
	return sell and sell > 0 and sell or nil
end

-- One unit's worth: the better of selling it on the auction house (after the cut) and to a vendor, and
-- which ("auction" or "vendor").
local function worth(id)
	local m = market(id)
	local net = m and math.floor(m * (1 - CUT))
	local v = vendor(id)
	if net and (not v or net >= v) then
		return net, "auction"
	end
	if v then
		return v, "vendor"
	end
end

-- Quality (0 poor … 4 epic), item level, class and vendor price, from the catalogue, else the client.
local function itemInfo(id)
	local info = catalogueInfo(id)
	if info then
		return info.quality, info.ilvl, info.class, info.sell, info.name
	end
	if C_Item and C_Item.GetItemInfo then
		local name, _, quality, ilvl, _, _, _, _, _, _, sell, class = C_Item.GetItemInfo(id)
		return quality, ilvl, class, sell, name
	end
end

local function enchanting()
	local me = ns.me()
	local p = me and me.prof and me.prof[333]
	return p and p.skill or 0
end

-- What disenchanting one is worth, and the skill it needs; nil when it cannot be disenchanted. The table
-- is the classic one (Disenchant.lua): on retail it would value greens in Illusion Dust, so none there.
local function disenchantWorth(id)
	local client = ns.db().client
	if ns.Realms.isRetail(client and client.interface) then
		return nil
	end
	local quality, ilvl, class = itemInfo(id)
	local de = quality and ns.Disenchant.of(quality, ilvl, class)
	if not de then
		return nil
	end
	return ns.Disenchant.value(de.outcomes, worth), de.skill
end

-- Money with the game's coin icons, as its own Sell Price line; from a gold up, gold and silver only.
local function coins(copper)
	return ns.Money.format(copper, "icons")
end

-- For the loot advisor (Advisor.lua): the same prices and valuation as here.
ns.price = {
	market = market, own = ownMarket, cheapest = cheapest, buy = buy, vendor = vendor, vendorBuy = vendorBuy, worth = worth, itemInfo = itemInfo,
	disenchant = disenchantWorth, enchanting = enchanting, coins = coins, cut = CUT,
}
