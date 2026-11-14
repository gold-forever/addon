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
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H,", "a Horde visitor records side H")
faction = "Alliance"
visit()
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,A,", "an Alliance visitor records side A")
faction = "Neutral"
visit()
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,,", "a neutral visitor records no side")

-- Schema 13 (gf#393): the vendor row ends with the visitor's standing with the vendor (UnitReaction, 1 Hated …
-- 8 Exalted), the price having been seen at it; the merchant row with the wares whose tooltip says
-- "Requires <faction> - <standing>", each item:standing:faction.
ITEM_REQ_REPUTATION = "Requires %s - %s"
for i, label in ipairs({ "Hated", "Hostile", "Unfriendly", "Neutral", "Friendly", "Honored", "Revered", "Exalted" }) do
	_G["FACTION_STANDING_LABEL" .. i] = label
end
FACTION_STANDING_LABEL7_FEMALE = "Reverée"
save.catalogue.factions = { [76] = "Orgrimmar" }
local reaction = 6
function UnitReaction(unit, other)
	if unit == "npc" and other == "player" then
		return reaction
	end
end
local tooltips = { [2] = { "Recipe: Thing", "Requires Orgrimmar - Honored", "Requires Level 20" } }
C_TooltipInfo = {
	GetMerchantItem = function(i)
		local lines = {}
		for n, text in ipairs(tooltips[i] or {}) do
			lines[n] = { leftText = text }
		end
		return { lines = lines }
	end,
}
faction = "Horde"
visit()
eq(save.catalogue.vendor[2589], "50,,1792517535,1,6", "the vendor price ends with the visitor's standing, Honored")
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H,238560:6:76", "the ware that needs Honored with Orgrimmar")

tooltips[2] = { "Recipe: Thing", "Requires Darkspear Trolls - Reverée" }
tooltips[1] = { "Linen Cloth", "Requires Orgrimmar - Exalted" }
visit()
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H,2589:8:76+238560:7:", "a faction not catalogued: no ID; a feminine label reads too")

tooltips = {}
for _, odd in ipairs({ 0, 9, 5.5, "6" }) do
	reaction = odd
	visit()
	eq(save.catalogue.vendor[2589], "50,,1792517535,1,", "a reaction that is no standing is none: " .. tostring(odd))
end
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H,", "no ware needs a standing: requires empty")

-- Forever's client: no C_TooltipInfo; the addon's own hidden tooltip reads the ware.
C_TooltipInfo = nil
local tipLines = {}
local tip = {
	SetOwner = function() end,
	ClearLines = function() end,
	SetMerchantItem = function(_, i)
		tipLines = ({ [2] = { "Recipe: Thing", "Requires Orgrimmar - Revered" } })[i] or {}
	end,
	NumLines = function() return #tipLines end,
}
function CreateFrame(kind, name)
	assert(kind == "GameTooltip", "a tooltip")
	for n = 1, 5 do
		_G[name .. "TextLeft" .. n] = { GetText = function() return tipLines[n] end }
	end
	return tip
end
reaction = 5
visit()
eq(save.catalogue.vendor[2589], "50,,1792517535,1,5", "Forever: Friendly")
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H,238560:7:76", "Forever: the hidden tooltip's requirement")

-- A client where the calls are missing or raise: the rows as before, their new columns empty, no error.
UnitReaction = nil
tip.SetMerchantItem = function() error("no merchant item") end
visit()
eq(save.catalogue.vendor[2589], "50,,1792517535,1,", "no UnitReaction: no standing")
eq(save.catalogue.merchants[12345], "2393,0.5,0.5,2589+238560,H,", "a tooltip that raises: no requirement")

return checks()
