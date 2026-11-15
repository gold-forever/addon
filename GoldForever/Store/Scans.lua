-- Gold Forever: the auction house scans in the saved file (Market.lua writes them), read the same way
-- everywhere. Pure Lua with no game API, so it is tested outside the client.

local _, ns = ...

local Scans = {}
ns.Scans = Scans

-- The most the save may take before the oldest scans go (gf#404): under the site's 10 MiB upload cap, with
-- room for a session's growth. And how many went at the save this session started from, for /gf check.
Scans.MOST = 8 * 1048576
Scans.dropped = 0

-- A market without its side ("EU-Aszune-neutral" → "EU-Aszune"): on retail one auction house serves a
-- connected realm group, whichever side's auctioneer opened it (Market.lua keeps scans the same way).
function Scans.marketGroup(market)
	return string.match(market or "", "^(.*)%-[^-]+$") or market
end

-- The newest full scan of the market, or nil: on retail any side's scan of the realm group (a Horde
-- character scanning at the Bazaar's neutral auctioneer read no prices of its own before).
function Scans.latestFull(scans, market, retail)
	local mine = retail and Scans.marketGroup(market)
	local latest
	for _, scan in ipairs(scans) do
		if scan.kind == "full" and (scan.market == market or (mine and Scans.marketGroup(scan.market) == mine)) and (not latest or scan.t > latest.t) then
			latest = scan
		end
	end
	return latest
end

-- The size guard (gf#404): drops the oldest scans until the save (ns.saveSize, as /gf check reads it) is
-- under `most` bytes, keeping each market's newest full scan. How many it dropped.
function Scans.keepUnder(db, most)
	local size, scans = ns.saveSize(db), db.scans
	if size < most then
		return 0
	end
	local newest = {}
	for _, s in ipairs(scans) do
		local kept = newest[s.market]
		if s.kind == "full" and (not kept or s.t > kept.t) then
			newest[s.market] = s
		end
	end
	local oldest = {}
	for i, s in ipairs(scans) do
		if newest[s.market] ~= s then
			oldest[#oldest + 1] = i
		end
	end
	table.sort(oldest, function(a, b)
		return (scans[a].t or 0) < (scans[b].t or 0)
	end)
	local dropped, n = {}, 0
	for _, i in ipairs(oldest) do
		if size < most then
			break
		end
		size = size - ns.scanSize(scans, i)
		dropped[scans[i]] = true
		n = n + 1
	end
	local kept = {}
	for _, s in ipairs(scans) do
		if not dropped[s] then
			kept[#kept + 1] = s
		end
	end
	db.scans = kept
	return n
end
