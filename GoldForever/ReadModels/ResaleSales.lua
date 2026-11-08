-- Gold Forever: whether an item sells, for the merchant's resale mark (VendorResale.lua, gf#317). The one gate
-- to change when the prices file carries real sales (gf#316).

local _, ns = ...
local ResaleSales = {}
ns.ResaleSales = ResaleSales

local MIN_SCANS = 2

-- Whether the scan's rows ("key,unit,…" joined by ";") hold the item; a key may carry a suffix ("2589:612").
local function listed(scan, id)
	local plain = ";" .. id .. ","
	local suffixed = ";" .. id .. ":"
	for _, chunk in ipairs(scan.rows or {}) do
		if string.find(chunk, plain, 1, true) or string.find(chunk, suffixed, 1, true)
			or ns.Encode.itemId(string.match(chunk, "^[^,]+")) == id then
			return true
		end
	end
	return false
end

local function inMyMarket(scan, market)
	if scan.market == market then
		return true
	end
	return ns.retail and ns.Scans.marketGroup(scan.market) == ns.Scans.marketGroup(market)
end

local function ownScansHold(id)
	local me = ns.me()
	if not me then
		return false
	end
	local market, found = ns.market(string.lower(me.faction or "?")), 0
	for _, scan in ipairs(ns.db().scans) do
		if scan.kind == "full" and inMyMarket(scan, market) and listed(scan, id) then
			found = found + 1
			if found >= MIN_SCANS then
				return true
			end
		end
	end
	return false
end

-- Scans are long and a merchant's list is redrawn often: each item's answer is kept until the next scan.
local held, heldFor = {}, nil
local function seenInOwnScans(id)
	if heldFor ~= ns.scanVersion then
		held, heldFor = {}, ns.scanVersion
	end
	if held[id] == nil then
		held[id] = ownScansHold(id)
	end
	return held[id]
end

-- Whether the item has sales. The client knows none, so a value that has lasted stands in for them: the
-- pool's typical price (3 days or more), or the item in at least two of the character's own full scans.
function ResaleSales.hasSales(id)
	local _, _, _, week = ns.Prices.value(id)
	return week ~= nil or seenInOwnScans(id)
end
