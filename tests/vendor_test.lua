-- Market.lua: a vendor's window catalogues every item it lists, whatever its cost, so an item sold for
-- currency or other items is named too; the vendor price is recorded only for an item sold for gold.

-- The vendor: Linen Cloth for 50 copper, and a recipe for currency (an extended cost, no gold).
local stock = {
	{ id = 2589, price = 50, quantity = 1, available = -1, extended = false },
	{ id = 238560, price = 0, quantity = 1, available = -1, extended = true },
}
function GetMerchantNumItems() return #stock end
function GetMerchantItemID(i) return stock[i].id end
function GetMerchantItemInfo(i)
	local s = stock[i]
	return "x", 0, s.price, s.quantity, s.available, true, true, s.extended
end
function UnitGUID() return "Creature-0-1-2-3-12345-0000000000" end
local faction = "Horde"
function UnitFactionGroup(unit) return unit == "player" and faction or nil end

local save = { catalogue = { vendor = {}, merchants = {} } }
local handlers, catalogued, later = {}, {}, {}
local ns = {
	on = function(event, _, fn) handlers[event] = fn end,
	after = function(_, _, fn) later[#later + 1] = fn end,
	throttle = function(_, _, fn) return fn end,
	module = function() end,
	commands = {},
	db = function() return save end,
	now = function() return 1792517535 end,
	readable = function(v) return v end,
	position = function() return 2393, 0.5, 0.5 end,
	catalogueItem = function(id) catalogued[#catalogued + 1] = id end,
}
loadEncode(ns)
assert(load(SOURCES["Market.lua"], "@Market.lua"))("GoldForever", ns)

local function visit()
	later = {}
	handlers.MERCHANT_SHOW()
	for _, fn in ipairs(later) do
		fn()
	end
end
visit()

table.sort(catalogued)
eq(table.concat(catalogued, " "), "2589 238560", "both items catalogued, the one sold for currency too")
eq(save.catalogue.vendor[2589] ~= nil, true, "the gold item has a vendor price")
eq(save.catalogue.vendor[238560], nil, "the currency item has none")
eq(save.catalogue.merchants[12345]:find("2589+238560", 1, true) ~= nil, true, "the vendor lists both")

-- The merchant row ends with the visitor's side (H, A, or empty for a neutral visitor), as a trainer's place.
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H", "a Horde visitor records side H")
faction = "Alliance"
visit()
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,A", "an Alliance visitor records side A")
faction = "Neutral"
visit()
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,", "a neutral visitor records no side")

return checks()
