-- Trade.lua: the game's Sell All Junk button (C_MerchantFrame.SellAllJunkItems) sells every junk stack in
-- one call, without UseContainerItem; each is a merchantTrade sell row, as selling one item is.

-- As the client's: the hook runs after the original with the same arguments.
function hooksecurefunc(t, name, hook)
	local orig = t[name]
	t[name] = function(...)
		orig(...)
		hook(...)
	end
end

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
}
local vendor = { [3300] = 13, [2589] = 10, [4865] = 5, [6150] = 0, [4867] = 21 }
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
	GetItemInfo = function(id)
		return "x", nil, 0, 1, 1, "", "", 20, "", 1, vendor[id]
	end,
}

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
	eq(table.concat(rows, ";"), "sell,3300,4,52;sell,4865,1,5;sell,4867,3,63", "three junk stacks, three sell rows")
end

do
	-- A client without the call (guarded): loads, and one item sold still records.
	local handlers, rows = load(false)
	handlers.MERCHANT_SHOW()
	C_Container.UseContainerItem(0, 2)
	eq(table.concat(rows, ";"), "sell,2589,20,200", "no junk button: one item sold as before")
end

return checks()
