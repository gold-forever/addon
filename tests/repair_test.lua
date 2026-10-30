-- Trade.lua and Ledger.lua: money spent on a repair at a merchant, all at once (RepairAllItems) or one item
-- at a time in repair mode, is tagged "repair" in its money row; other spending at the merchant is not.

-- As the client's: the hook runs after the original with the same arguments.
function hooksecurefunc(t, name, hook)
	if type(t) == "string" then
		t, name, hook = _G, t, name
	end
	local orig = t[name]
	t[name] = function(...)
		orig(...)
		hook(...)
	end
end

local clock, purse = 100, 100000
function GetTime() return clock end
function GetMoney() return purse end
function RepairAllItems() end
function PickupInventoryItem() end
function BuyMerchantItem() end
function GetMerchantItemInfo() return "Water", 0, 25, 5, -1, true, true, false end
function GetMerchantItemLink() return "|Hitem:159::::::::30|h[Water]|h" end
local repairMode = false
function InRepairMode() return repairMode end
C_Container = {
	GetContainerItemInfo = function()
		return { itemID = 2589, stackCount = 1, hyperlink = "|Hitem:2589::::::::30|h[Linen Cloth]|h" }
	end,
	UseContainerItem = function() end,
	PickupContainerItem = function() end,
}
C_Item = { GetItemInfo = function() return "x", nil, 0, 1, 1, "", "", 20, "", 1, 10 end }

local handlers, rows = {}, {}
local ns = {
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	after = function() end,
	module = function() end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	me = function() return { ref = 1 } end,
	now = function() return 1792517535 end,
	position = function() return 1429 end,
	tornDown = function() return false end,
	catalogueItem = function() end,
	record = function(stream, row)
		if stream == "money" then
			rows[#rows + 1] = row.delta .. "," .. row.ctx
		end
	end,
}
local function fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(...)
	end
end
local function spend(copper)
	purse = purse - copper
	fire("PLAYER_MONEY")
end
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Ledger.lua"], "@Ledger.lua"))("GoldForever", ns)
assert(load(SOURCES["Trade.lua"], "@Trade.lua"))("GoldForever", ns)

fire("PLAYER_MONEY") -- the purse the changes are measured from
fire("MERCHANT_SHOW")

RepairAllItems()
spend(100000 - 90000)
eq(rows[#rows], "-10000,merchant+repair", "repair all: the cost is a repair")

clock = clock + 1
BuyMerchantItem(1, 5)
spend(25)
eq(rows[#rows], "-25,merchant", "a purchase after the repair is not one")

repairMode = true
clock = clock + 0.5 -- a click a moment after the last
PickupInventoryItem(16)
spend(300)
eq(rows[#rows], "-300,merchant+repair", "one equipped item mended")

clock = clock + 0.5
C_Container.PickupContainerItem(0, 1)
spend(120)
eq(rows[#rows], "-120,merchant+repair", "one item in the bags mended")

clock = clock + 0.5
C_Container.UseContainerItem(0, 2)
spend(80)
eq(rows[#rows], "-80,merchant+repair", "one item in the bags mended by a right-click")
repairMode = false

clock = clock + 0.5
PickupInventoryItem(16)
spend(5)
eq(rows[#rows], "-5,merchant", "out of repair mode, picking an item up repairs nothing")

clock = clock + 0.5
RepairAllItems()
spend(-50)
eq(rows[#rows], "50,merchant", "money coming in after a repair is not its cost")
spend(30)
eq(rows[#rows], "-30,merchant+repair", "the repair's cost, after it")

clock = clock + 0.5
RepairAllItems()
clock = clock + 10
spend(40)
eq(rows[#rows], "-40,merchant", "a repair long gone does not tag later spending")

return checks()
