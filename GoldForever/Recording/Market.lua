-- Gold Forever: auction house scans and vendor prices (design 002, Stream: auction scans; State:
-- catalogue vendor).
--
-- A scan replicates the whole auction house, at most once per 15 minutes per account, and stores
-- one row per (item key, unit price). Owner and bidder fields are never read.

local _, ns = ...
local Encode = ns.Encode

local COOLDOWN = 15 * 60
local BATCH = 500 -- auctions read a frame where the client has no profiling timer (ns.frameSpent)
local KEEP_RECENT = 2 -- the newest full scans kept per market (design 002)
local KEEP_MAX = 10 -- with one more a day before them, up to this many: a week or so of history
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

-- Whether the player is in a zone with a neutral auction house (Booty Bay, Gadgetzan, Everlook), for the
-- tooltip's neutral line (design 009 decision 9). Read on zone changes, not per tooltip.
local neutralHere = false
local function readNeutral()
	local map = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
	local found = false
	while map do
		if NEUTRAL_MAPS[map] then
			found = true
			break
		end
		local info = C_Map.GetMapInfo(map)
		map = info and info.parentMapID ~= 0 and info.parentMapID or nil
	end
	neutralHere = found
end
ns.on("ZONE_CHANGED_NEW_AREA", "neutral zone", readNeutral)
function ns.atNeutralZone()
	return neutralHere
end

-- Keeps, per market, the newest KEEP_RECENT full scans and the newest of each earlier UTC day, up to
-- KEEP_MAX; throttled markers from the last day. The web app keeps every scan it was sent, so the
-- file needs only enough for the in-game prices and for a save that misses an upload or two.
-- A full scan is about 90 KB on the beta: ten a market for three markets made a save of 2.7 MB, of
-- which these rules keep about a third.
local function prune()
	-- Retail: one auction house per connected realm group whichever side's auctioneer opened it, and a
	-- full scan of ~300,000 auctions is ~2 MB of the save: only the newest per group is kept, so the save
	-- stays under the server's upload limit (10 MiB). The server keeps every scan it was sent.
	local retail = ns.Realms.isRetail(ns.db().client and ns.db().client.interface)
	local keepRecent, keepMax = retail and 1 or KEEP_RECENT, retail and 1 or KEEP_MAX
	local function group(market)
		return retail and ns.Scans.marketGroup(market) or market
	end
	local scans = {}
	for i, s in ipairs(ns.db().scans) do
		scans[i] = s
	end
	table.sort(scans, function(a, b)
		return (a.t or 0) < (b.t or 0)
	end)
	local full, days, kept = {}, {}, {}
	for i = #scans, 1, -1 do
		local s = scans[i]
		if s.kind == "full" then
			local g = group(s.market)
			local n = full[g] or 0
			local day = g .. "@" .. Encode.day(s.t or 0)
			if n < keepRecent or (n < keepMax and not days[day]) then
				full[g] = n + 1
				days[day] = true
				table.insert(kept, 1, s)
			end
		elseif ns.now() - (s.t or 0) < 86400 then
			table.insert(kept, 1, s)
		end
	end
	ns.db().scans = kept
end

-- A file saved by an older version with more scans shrinks at the next login, not the next scan.
ns.module("Market", {
	requires = { "Store" },
	enable = function()
		ns.safely("scans", prune)
	end,
	-- Whether the zone is neutral changes with the zone.
	world = function()
		readNeutral()
	end,
})

-- Rows written per frame when a scan is saved: like reading, spread so no frame stalls (design 009,
-- Performance budget). A retail scan has ~110,000 rows; written at once they took a frame of their own.
local ENCODE = 2000

-- A scan read only in part (the auction house closed while it read: the client stops giving the listings,
-- though the count stays) is no market: manual test run 001, leaving mid-read stored a few odd listings as
-- a full scan, and the shared price of Leafy Appendage became 145g against 7.92g on the auction house.
local COMPLETE = 0.9 -- the share of the listings a full scan must have read
ns.Market = ns.Market or {}
local Market = ns.Market
function Market.partial(n, read, cutShort)
	return n > 0 and (cutShort or (read or 0) < n * COMPLETE) or false
end

local function finish(s, buckets, n)
	local partial = Market.partial(n, s.read, s.cutShort)
	if partial then
		buckets = {} -- none of it is kept: a part is not the market
	end
	-- Rows in no particular order: nothing reads them by position, and sorting ~110,000 keys took a frame.
	local keys = {}
	for key in pairs(buckets) do
		keys[#keys + 1] = key
	end
	local rows, i = {}, 0
	local function store()
		local record = {
			t = s.t,
			market = s.market,
			-- A partial scan is stored as "throttled" (the server reads no rows of one), marked partial.
			kind = (n > 0 and not partial) and "full" or "throttled",
			partial = partial or nil,
			bands = 0,
			auctions = n,
			map = s.map,
			zone = s.zone,
			npc = s.npc,
			npcFaction = s.npcFaction,
			rows = Encode.chunks(rows),
		}
		-- Retail's distinct items (sorted and joined, a frame's work of its own on a full scan) go into the
		-- record the next frame; the save is written at logout, long after.
		if s.items then
			ns.after(0, "scan", function()
				local ids = {}
				for id in pairs(s.items) do
					ids[#ids + 1] = id
				end
				table.sort(ids)
				local items = {}
				for k, id in ipairs(ids) do
					items[k] = s.items[id]
				end
				record.items = Encode.chunks(items)
			end)
		end
		local scans = ns.db().scans
		scans[#scans + 1] = record
		prune()
		-- Prices built from the scans (Pricing.lua) are stale now; the count of scans may not change.
		ns.scanVersion = (ns.scanVersion or 0) + 1
		ns.lastScan = { t = s.t, kind = partial and "partial" or record.kind, auctions = n, prices = #keys, seconds = ns.now() - s.t, market = s.market }
		-- The new prices are read (over frames for a big scan); the deals line follows when they are in. A
		-- partial scan gives no prices and no deals line.
		if n > 0 and not partial then
			ns.emit("scanSaved")
		end
		if partial then
			ns.say(string.format("scan cut short: %d of %d listings read, so it is not used for prices. Stay at the auction house until reading ends.", s.read or 0, n))
		else
			ns.say(string.format("scanned %d auctions into %d prices (%s).", n, #keys, s.market))
		end
		scan = nil
	end
	local function encode()
		local started, done = ns.frameStart(), 0
		local stop = #keys
		for k = i + 1, #keys do
			local b = buckets[keys[k]]
			rows[k] = Encode.row(b.item, b.unit, b.qty, b.auctions, b.left)
			done = done + 1
			if ns.frameSpent(started, done, ENCODE) then
				stop = k
				break
			end
		end
		i = stop
		if i < #keys then
			ns.after(0, "scan", encode)
		else
			store()
		end
	end
	encode()
end

local READ_MS = 6 -- a full scan's reading, per frame

local function read()
	local s = scan
	if not s or s.reading then
		return
	end
	s.reading = true
	local n = C_AuctionHouse.GetNumReplicateItems()
	s.total = n
	local buckets, i = {}, 0
	-- On retail, each distinct item's class and stack size, read now: the catalogue loads in the
	-- background and a /reload can come first.
	local instant, stack = ns.Realms.itemApis()
	local timeLeft = C_AuctionHouse.GetReplicateItemTimeLeft
	if ns.Realms.isRetail(ns.db().client and ns.db().client.interface) then
		s.items = {}
	end
	local function batch()
		local started, done = ns.frameStart(), 0
		local stop = n
		for index = i, n - 1 do
			local _, _, count, _, _, _, _, _, _, buyout, _, _, _, _, _, _, itemID =
				C_AuctionHouse.GetReplicateItemInfo(index)
			-- Read: a listing with its count. Once the auction house is closed the client still gives the item
			-- but not that (manual test run 001: "322407 of 322407 read" on a cut scan). A bid-only listing is
			-- read too, though it has no buyout to price.
			if itemID and count and count > 0 then
				s.read = (s.read or 0) + 1
				if buyout and buyout > 0 then
					local key = Encode.itemKey(C_AuctionHouse.GetReplicateItemLink(index)) or tostring(itemID)
					local unit = math.floor(buyout / count + 0.5)
					local left = timeLeft and Encode.band(timeLeft(index))
					local bucket = key .. "|" .. unit .. "|" .. tostring(left)
					local b = buckets[bucket]
					if not b then
						b = { item = key, unit = unit, qty = 0, auctions = 0, left = left }
						buckets[bucket] = b
						ns.catalogueItem(key)
					end
					b.qty = b.qty + count
					b.auctions = b.auctions + 1
				end
				if s.items and not s.items[itemID] then
					s.items[itemID] = ns.Realms.itemRow(itemID, instant, stack)
				end
			end
			done = done + 1
			-- 6 ms a frame (owner, 2026-10-24: 60-70 fps reading at 3 ms, 50 is fine), about half the wait.
			if ns.frameSpent(started, done, BATCH, READ_MS) then
				stop = index + 1
				break
			end
		end
		i = stop
		s.done = i
		if i < n then
			ns.after(0, "scan", batch)
		else
			finish(s, buckets, n)
		end
	end
	batch()
end

-- A scan still in hand after this long failed partway (an error in reading or saving it ends the step,
-- not the scan); a real one is read and saved within two minutes, so the next may start.
local ABANDONED = 600

local function start(manual)
	local db = ns.db()
	if scan and ns.now() - scan.t < ABANDONED then
		return
	end
	scan = nil
	local wait = (db.lastReplicate or 0) + COOLDOWN - ns.now()
	if wait > 0 then
		if manual then
			ns.say(string.format("next scan possible in %d:%02d.", math.floor(wait / 60), wait % 60))
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
		npc = Encode.source(ns.readable(UnitGUID("npc"))),
		npcFaction = UnitExists("npc") and (UnitFactionGroup("npc") or "none") or nil,
	}
	ns.say("scanning the auction house…")
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

-- A scan starts by itself at the auction house only when the player switched that on (the Scan tab).
local function auctionOpened()
	if auctionOpen then
		return
	end
	auctionOpen = true
	if not ns.settings("scan").auto then
		return
	end
	ns.after(1, "scan", function()
		-- Closed again within the second: no scan, and the cooldown is not spent.
		if auctionOpen then
			start()
		end
	end)
end
local function auctionClosed()
	auctionOpen = false
	-- Closed while reading: the rest of the listings never come; the scan is partial.
	if scan and scan.reading then
		scan.cutShort = true
	end
end
ns.on("AUCTION_HOUSE_SHOW", "scan", auctionOpened)
ns.on("AUCTION_HOUSE_CLOSED", "scan", auctionClosed)
-- Read a moment after the list arrives so more item links have loaded.
ns.on("REPLICATE_ITEM_LIST_UPDATE", "scan", function()
	ns.after(1, "scan", read)
end)

-- Where the scan stands, for the auction panel: "asking" (the server has not answered), "reading"
-- (done of total), or "idle"; the seconds until the next full scan may start (0 when it may now).
function ns.scanState()
	local wait = math.max(0, ((ns.db() and ns.db().lastReplicate) or 0) + COOLDOWN - ns.now())
	if scan then
		return { phase = scan.reading and "reading" or "asking", done = scan.done or 0, total = scan.total or 0, wait = wait }
	end
	return { phase = "idle", wait = wait, last = ns.lastScan }
end

-- A scan the player asked for (the panel's button, /gf scan).
function ns.startScan()
	start(true)
end

ns.commands.scan = function()
	if not auctionOpen then
		ns.say("open the auction house first.")
		return
	end
	start(true)
end

-- Vendors ----------------------------------------------------------------------------------------

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
	local npc = Encode.npcId(ns.readable(UnitGUID("npc")))
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
