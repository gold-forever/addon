-- Gold Forever: the public API, GoldForeverAPI, for other addons to read prices. All amounts are copper
-- for one unit. Every call answers with numbers and strings, or nil for an item it knows nothing about
-- (or before the character has logged in), and only reads: it is safe in combat. The table itself cannot
-- be changed. Call it with a dot: GoldForeverAPI.GetPrice(itemID).
--
--   GoldForeverAPI.version
--   GoldForeverAPI.GetPrice(itemID)          -> value, source, age, players
--     value: the market value; source: "pool" (the shared prices from the companion app) or "scan" (this
--     player's own latest full scan); age: seconds since it was scanned; players: how many are behind it
--     (1 for "scan"; age may be nil there if the scan's time is unknown).
--   GoldForeverAPI.GetVendorPrice(itemID)    -> what a vendor pays for one
--   GoldForeverAPI.GetDisenchantValue(itemID) -> the expected worth of disenchanting one; nil where it
--     cannot be disenchanted, where none of its materials is priced, and on retail.
--
-- `version` changes when an addon using the API as it is would misread it: a call or a return removed,
-- renamed, reordered or given another meaning or type. A new call, or a new return after the last, does
-- not. Check it before relying on a call: if GoldForeverAPI and GoldForeverAPI.version == 1 then … end

local _, ns = ...

local VERSION = 1
local F, ITEM = ns.DataFormat.field, ns.DataFormat.item

local function known(id)
	return type(id) == "number" and ns.db() and ns.me()
end

-- The players and scan time of the pool's entry Prices.value picked: the first of the character's markets
-- whose entry carries that value, as Prices.lua reads them first to last.
local function poolEntry(id, value)
	local data = GoldForever_Prices
	local markets = data[F.markets]
	for _, key in ipairs(ns.Prices.mine()) do
		local items = markets[key]
		local e = type(items) == "table" and items[id]
		if type(e) == "table" and e[ITEM.value] == value and type(e[ITEM.players]) == "number" and type(e[ITEM.scannedAt]) == "number" then
			return e[ITEM.players], e[ITEM.scannedAt]
		end
	end
end

local function age(at)
	return at and math.max(0, GetServerTime() - at) or nil
end

local function getPrice(id)
	if not known(id) then
		return nil
	end
	local value, source = ns.Prices.value(id)
	if not value then
		return nil
	end
	if source == "pool" then
		local players, at = poolEntry(id, value)
		return value, source, age(at), players
	end
	local _, _, at = ns.ownPrice(id)
	return value, source, age(at), 1
end

local function getVendorPrice(id)
	if not known(id) then
		return nil
	end
	return ns.price.vendor(id)
end

local function getDisenchantValue(id)
	if not known(id) then
		return nil
	end
	local value = ns.price.disenchant(id)
	-- ns.price counts an unpriced material as nothing: all unpriced is no value, not a value of 0.
	return value and value > 0 and value or nil
end

local api = { version = VERSION, GetPrice = getPrice, GetVendorPrice = getVendorPrice, GetDisenchantValue = getDisenchantValue }

GoldForeverAPI = setmetatable({}, {
	__index = api,
	__newindex = function()
		error("GoldForeverAPI is read-only", 2)
	end,
	__metatable = false,
})
