-- Gold Forever: auction house scans and vendor prices (design 002, Stream: auction scans; State:
-- catalogue vendor).
--
-- A scan replicates the whole auction house, at most once per 15 minutes per account, and stores
-- one row per (item key, unit price). Owner and bidder fields are never read.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.scan = "item,unit,qty,auctions"
-- qty is appended to design 002's columns: buy is the price of one purchase of qty items.
ns.FIELDS.vendor = "buy,limited,t,qty"

local COOLDOWN = 15 * 60
local BATCH = 500 -- auctions read per frame
local KEEP = 10 -- full scans kept per market; design 002 keeps 2, raised for the last days
local NEUTRAL_MAPS = { [1434] = true, [1446] = true, [1452] = true } -- Stranglethorn, Tanaris, Winterspring

local scan -- the scan in progress

-- Side of the auction house: the auctioneer's own faction (goblins have none), else by map.
local function side()
	local faction = UnitExists("npc") and UnitFactionGroup("npc")
	if faction == "Alliance" or faction == "Horde" then
		return string.lower(faction)
	elseif UnitExists("npc") then
		return "neutral"
	end
	local map = C_Map.GetBestMapForUnit("player")
	while map do
		if NEUTRAL_MAPS[map] then
			return "neutral"
		end
		local info = C_Map.GetMapInfo(map)
		map = info and info.parentMapID ~= 0 and info.parentMapID or nil
	end
	local me = ns.me()
	return string.lower(me and me.faction or "?")
end

-- Keeps the newest KEEP full scans per market and throttled markers from the last day.
local function prune()
	local scans = ns.db().scans
	local full, kept = {}, {}
	for i = #scans, 1, -1 do
		local s = scans[i]
		if s.kind == "full" then
			full[s.market] = (full[s.market] or 0) + 1
			if full[s.market] <= KEEP then
				table.insert(kept, 1, s)
			end
		elseif ns.now() - (s.t or 0) < 86400 then
			table.insert(kept, 1, s)
		end
	end
	ns.db().scans = kept
end

local function finish(s, buckets, n)
	local record = {
		t = s.t,
		market = s.market,
		kind = n > 0 and "full" or "throttled",
		auctions = n,
		map = s.map,
		zone = s.zone,
		npc = s.npc,
		npcFaction = s.npcFaction,
		rows = {},
	}
	local keys = {}
	for key in pairs(buckets) do
		keys[#keys + 1] = key
	end
	table.sort(keys)
	local rows = {}
	for i, key in ipairs(keys) do
		local b = buckets[key]
		rows[i] = Encode.row(b.item, b.unit, b.qty, b.auctions)
	end
	record.rows = Encode.chunks(rows)
	local scans = ns.db().scans
	scans[#scans + 1] = record
	prune()
	-- Prices built from the scans (Appraiser.lua) are stale now; the count of scans may not change.
	ns.scanVersion = (ns.scanVersion or 0) + 1
	print(string.format("|cffe0ac45Gold Forever|r: scanned %d auctions into %d prices (%s).", n, #keys, s.market))
	scan = nil
end

local function read()
	local s = scan
	if not s or s.reading then
		return
	end
	s.reading = true
	local n = C_AuctionHouse.GetNumReplicateItems()
	local buckets, i = {}, 0
	local function batch()
		local stop = math.min(i + BATCH, n)
		for index = i, stop - 1 do
			local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
				C_AuctionHouse.GetReplicateItemInfo(index)
			if itemID and buyout and buyout > 0 and count and count > 0 then
				local key = Encode.itemKey(C_AuctionHouse.GetReplicateItemLink(index)) or tostring(itemID)
				local unit = math.floor(buyout / count + 0.5)
				local bucket = key .. "|" .. unit
				local b = buckets[bucket]
				if not b then
					b = { item = key, unit = unit, qty = 0, auctions = 0 }
					buckets[bucket] = b
					ns.catalogueItem(key)
				end
				b.qty = b.qty + count
				b.auctions = b.auctions + 1
			end
		end
		i = stop
		if i < n then
			ns.after(0, "scan", batch)
		else
			finish(s, buckets, n)
		end
	end
	batch()
end

local function start(manual)
	local db = ns.db()
	if scan then
		return
	end
	local wait = (db.lastReplicate or 0) + COOLDOWN - ns.now()
	if wait > 0 then
		if manual then
			print(string.format("|cffe0ac45Gold Forever|r: next scan possible in %d:%02d.", math.floor(wait / 60), wait % 60))
		end
		return
	end
	if not C_AuctionHouse or not C_AuctionHouse.ReplicateItems then
		return
	end
	db.lastReplicate = ns.now()
	scan = {
		t = ns.now(),
		market = ns.market(side()),
		map = C_Map.GetBestMapForUnit("player"),
		zone = GetSubZoneText(),
		npc = Encode.source(UnitGUID("npc")),
		npcFaction = UnitExists("npc") and (UnitFactionGroup("npc") or "none") or nil,
	}
	print("|cffe0ac45Gold Forever|r: scanning the auction house…")
	C_AuctionHouse.ReplicateItems()
	-- No update within a minute: the client is throttling; record that instead of waiting forever.
	local mine = scan
	ns.after(60, "scan", function()
		if scan == mine and not mine.reading then
			finish(mine, {}, 0)
		end
	end)
end

local auctionOpen = false

local function auctionOpened()
	if auctionOpen then
		return
	end
	auctionOpen = true
	ns.after(1, "scan", function()
		-- Closed again within the second: no scan, and the cooldown is not spent.
		if auctionOpen then
			start()
		end
	end)
end
local function auctionClosed()
	auctionOpen = false
end
ns.on("AUCTION_HOUSE_SHOW", "scan", auctionOpened)
ns.on("AUCTION_HOUSE_CLOSED", "scan", auctionClosed)
-- Read a moment after the list arrives so more item links have loaded.
ns.on("REPLICATE_ITEM_LIST_UPDATE", "scan", function()
	ns.after(1, "scan", read)
end)

ns.commands.scan = function()
	if not auctionOpen then
		print("|cffe0ac45Gold Forever|r: open the auction house first.")
		return
	end
	start(true)
end

-- Vendors ----------------------------------------------------------------------------------------

ns.FIELDS.merchant = "map,x,y,items"

local function readMerchant()
	local vendor = ns.db().catalogue.vendor
	local sold = {} -- every item this vendor sells, for "where to buy" (recipes in particular)
	for i = 1, GetMerchantNumItems() do
		local id = GetMerchantItemID(i)
		local price, quantity, available, extended
		if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
			local info = C_MerchantFrame.GetItemInfo(i)
			if info then
				price, quantity, available, extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
			end
		else
			local _
			_, _, price, quantity, available, _, _, extended = GetMerchantItemInfo(i)
		end
		if id then
			sold[#sold + 1] = id
		end
		if id and price and price > 0 and not extended then
			vendor[id] = Encode.row(price, available and available >= 0 or nil, ns.now(), quantity)
			ns.catalogueItem(id)
		end
	end
	local src = Encode.source(UnitGUID("npc"))
	local npc = src and tonumber(string.match(src, "^n(%d+)$"))
	if npc and #sold > 0 then
		local map, x, y = ns.position()
		ns.db().catalogue.merchants[npc] = Encode.row(map, x, y, table.concat(sold, "+"))
	end
end

local merchantSoon = ns.throttle("vendor", 1, readMerchant)
local function merchantOpened()
	ns.after(0.5, "vendor", readMerchant)
end
ns.on("MERCHANT_SHOW", "vendor", merchantOpened)
ns.on("MERCHANT_UPDATE", "vendor", merchantSoon)

-- Newer clients open the auction house and vendors through the interaction manager.
local INTERACTION = Enum and Enum.PlayerInteractionType or {}
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "scan", function(kind)
	if kind == INTERACTION.Auctioneer then
		auctionOpened()
	elseif kind == INTERACTION.Merchant then
		merchantOpened()
	end
end)
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "scan", function(kind)
	if kind == INTERACTION.Auctioneer then
		auctionClosed()
	end
end)
