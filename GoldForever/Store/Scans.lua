-- Gold Forever: the auction house scans in the saved file (Market.lua writes them), read the same way
-- everywhere. Pure Lua with no game API, so it is tested outside the client.

local _, ns = ...

local Scans = {}
ns.Scans = Scans

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
