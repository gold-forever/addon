-- Trade.lua: the game's Sell All Junk button (C_MerchantFrame.SellAllJunkItems) sells every junk stack in
-- one call, without UseContainerItem; each is a merchantTrade sell row, as selling one item is. A sale's
-- price is the coin it brought, else the vendor price of its link (retail scales an item's price by its
-- item level, which the link carries and the item ID does not).

-- As the client's: the hook runs after the original with the same arguments.
function hooksecurefunc(t, name, hook)
	local orig = t[name]
	t[name] = function(...)
		orig(...)
		hook(...)
	end
end

SCALED = "|Hitem:50000|h[Old Blade]|h"

-- Three junk stacks, a stack that is not junk, and junk without a vendor price.
local bags = {
	[0] = {
		[1] = { itemID = 3300, quality = 0, stackCount = 4, hyperlink = "|Hitem:3300::::::::30|h[Rabbit's Foot]|h" },
		[2] = { itemID = 2589, quality = 1, stackCount = 20, hyperlink = "|Hitem:2589::::::::30|h[Linen Cloth]|h" },
	},
	[1] = {
		[3] = { itemID = 4865, quality = 0, stackCount = 1, hyperlink = "|Hitem:4865::::::::30|h[Ruined Pelt]|h" },
		[4] = { itemID = 6150, quality = 0, stackCount = 1, hasNoValue = true, hyperlink = "|Hitem:6150::::::::30|h[A Frayed Knot]|h" },
	},
	[4] = {
		[1] = { itemID = 4867, quality = 0, stackCount = 3, hyperlink = "|Hitem:4867::::::::30|h[Broken Scorpid Leg]|h" },
	},
	-- An old raid's weapon: 109c at its base item level, 3g 30c at the level its link scales it to.
	[2] = {
		[1] = { itemID = 50000, quality = 4, stackCount = 1, hyperlink = SCALED },
		[2] = { itemID = 50001, quality = 4, stackCount = 1, hyperlink = "|Hitem:50001|h[Old Helm]|h" },
	},
}
local vendor = { [3300] = 13, [2589] = 10, [4865] = 5, [6150] = 0, [4867] = 21, [50000] = 109, [50001] = 80 }
local scaled = { [SCALED] = 33000, ["|Hitem:50001|h[Old Helm]|h"] = 25000 }
C_Container = {
	GetContainerNumSlots = function(bag)
		return bags[bag] and 16 or 0
	end,
	GetContainerItemInfo = function(bag, slot)
		return bags[bag] and bags[bag][slot]
	end,
	UseContainerItem = function() end,
}
C_Item = {
	GetItemInfo = function(item)
		local price = scaled[item] or vendor[tonumber(item) or tonumber(string.match(item, "item:(%d+)"))]
		return "x", nil, 0, 1, 1, "", "", 20, "", 1, price
	end,
}
local purse, timers = 0, {}
function GetMoney() return purse end
function GetTime() return 100 end
-- The coin a sale brings, a moment after the hook.
local function paid(handlers, copper)
	purse = purse + copper
	handlers.PLAYER_MONEY()
end
local function runTimers()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
end

local function load(withJunkButton)
	C_MerchantFrame = withJunkButton and { SellAllJunkItems = function() end } or nil
	local handlers, rows = {}, {}
	local ns = {
		on = function(event, _, fn)
			handlers[event] = fn
		end,
		safely = function(_, fn, ...)
			return fn(...)
		end,
		me = function()
			return { ref = 1 }
		end,
		now = function()
			return 1792517535
		end,
		position = function()
			return 1429
		end,
		record = function(stream, row)
			if stream == "merchantTrade" then
				rows[#rows + 1] = table.concat({ row.kind, row.item, row.qty, row.price }, ",")
			end
		end,
		catalogueItem = function() end,
		after = function(_, _, fn)
			timers[#timers + 1] = fn
		end,
	}
	assert(_G.load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
	assert(_G.load(SOURCES["Trade.lua"], "@Trade.lua"))("GoldForever", ns)
	return handlers, rows
end

do
	local handlers, rows = load(true)
	C_MerchantFrame.SellAllJunkItems()
	eq(#rows, 0, "away from a merchant, nothing")
	handlers.MERCHANT_SHOW()
	C_MerchantFrame.SellAllJunkItems()
	paid(handlers, 120)
	eq(table.concat(rows, ";"), "sell,3300,4,52;sell,4865,1,5;sell,4867,3,63", "three junk stacks, three sell rows at their links' prices: one rise cannot say whose coin it is")
end

do
	-- A client without the call (guarded): loads, and one item sold still records.
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	C_Container.UseContainerItem(0, 2)
	runTimers()
	eq(table.concat(rows, ";"), "sell,2589,20,200", "no junk button: one item sold as before")
end

do
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	C_Container.UseContainerItem(2, 1)
	eq(#rows, 0, "a sale waits for its coin")
	paid(handlers, 33012)
	eq(table.concat(rows, ";"), "sell,50000,1,33012", "a sale is the coin it brought")
end

do
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	C_Container.UseContainerItem(2, 1)
	runTimers()
	eq(table.concat(rows, ";"), "sell,50000,1,33000", "no coin seen: the link's price, not the item's base price")
end

do
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	C_Container.UseContainerItem(2, 1)
	C_Container.UseContainerItem(2, 2)
	paid(handlers, 33000)
	paid(handlers, 25000)
	runTimers()
	eq(table.concat(rows, ";"), "sell,50000,1,33000;sell,50001,1,25000",
		"two sales before the coin: each at its link's price")
end

do
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	C_Container.UseContainerItem(2, 1)
	paid(handlers, -500)
	paid(handlers, 33012)
	eq(table.concat(rows, ";"), "sell,50000,1,33012", "spending while the sale waits is not its coin")
end

do
	-- In repair mode the click mends the item; nothing is sold.
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	InRepairMode = function() return true end
	C_Container.UseContainerItem(2, 1)
	InRepairMode = nil
	runTimers()
	eq(#rows, 0, "a repair is not a sale")
end

return checks()
