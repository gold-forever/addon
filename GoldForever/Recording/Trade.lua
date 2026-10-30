-- Gold Forever: what is sold to and bought from vendors (data gap D4, docs/research/
-- 2026-10-23-data-opportunities.md in the web repository). One `merchantTrade` row per trade at an
-- open merchant:
--   sell     an item from the bags, as the client sells it on a right-click and as sell-junk addons do
--            (C_Container.UseContainerItem), or each junk stack the game's Sell All Junk sells
--            (C_MerchantFrame.SellAllJunkItems): the coin the sale brought, else the vendor price of the
--            item's link times the stack
--   buy      BuyMerchantItem: the merchant's price for the quantity; empty for items paid in currency
--            or other items
--   buyback  BuybackItem: the buyback price
-- Price is the total in copper. The money stream already has the merchant's coin; this says what for.
-- A repair at the merchant sets ns.repairAt, so the money it costs is tagged (Ledger.lua).

local _, ns = ...
local Encode = ns.Encode

local atMerchant = false

ns.on("MERCHANT_SHOW", "trade", function()
	atMerchant = true
end)
ns.on("MERCHANT_CLOSED", "trade", function()
	atMerchant = false
end)
-- Newer clients open vendors through the interaction manager.
local INTERACTION = Enum and Enum.PlayerInteractionType or {}
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "trade", function(kind)
	if kind ~= nil and kind == INTERACTION.Merchant then
		atMerchant = true
	end
end)
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "trade", function(kind)
	if kind ~= nil and kind == INTERACTION.Merchant then
		atMerchant = false
	end
end)

local function record(kind, key, qty, price)
	local me = ns.me()
	if not me or not key or key == "" then
		return
	end
	local map = ns.position()
	ns.record("merchantTrade", { t = ns.now(), char = me.ref, kind = kind, item = key, qty = qty, price = price, map = map })
	ns.catalogueItem(key)
end

-- What a sale brought: a sale waits a moment for the money it raises. Only a rise while one sale waits is
-- that sale's coin; with several waiting (Sell All Junk, quick clicks) each takes its link's price.
local COIN_SECONDS = 2
local waiting = {} -- sell rows not written yet
local money -- GetMoney() at the last sale or money change

local function flush()
	for _, w in ipairs(waiting) do
		ns.record("merchantTrade", w.row)
	end
	waiting = {}
end

ns.on("PLAYER_MONEY", "trade", function()
	local now = GetMoney()
	local rise = money and now - money or 0
	money = now
	if rise <= 0 or #waiting == 0 then
		return
	end
	if #waiting == 1 then
		waiting[1].row.price = rise
	end
	flush()
end)

local function wait(row)
	local w = { row = row }
	waiting[#waiting + 1] = w
	money = GetMoney()
	ns.after(COIN_SECONDS, "trade", function()
		for i, other in ipairs(waiting) do
			if other == w then
				table.remove(waiting, i)
				ns.record("merchantTrade", row)
				return
			end
		end
	end)
end

local function repairing()
	return InRepairMode and InRepairMode()
end

-- ns.repairAt: GetTime() of the last repair at a merchant, all at once or one item in repair mode, for the
-- money it costs (Ledger.lua).
local function repaired()
	if atMerchant then
		ns.repairAt = GetTime()
	end
end

-- Selling: the hook runs right after the call, while the item still sits in its slot, locked until the
-- server answers. An item without a vendor price is not sold, so nothing is written. The price is read
-- from the link, which carries the item level retail scales it by.
local function sell(info)
	if not info or info.hasNoValue then
		return
	end
	local link = info.hyperlink
	local id = info.itemID or (link and Encode.itemId(Encode.itemKey(link)))
	local sellPrice = (link and select(11, C_Item.GetItemInfo(link))) or (id and select(11, C_Item.GetItemInfo(id)))
	local me = ns.me()
	local key = Encode.itemKey(link) or (id and tostring(id))
	if not sellPrice or sellPrice <= 0 or not me or not key then
		return
	end
	local count = info.stackCount or 1
	wait({ t = ns.now(), char = me.ref, kind = "sell", item = key, qty = count, price = sellPrice * count, map = ns.position() })
	ns.catalogueItem(key)
end

local function sold(bag, slot)
	if not atMerchant or not C_Container.GetContainerItemInfo then
		return
	end
	if repairing() then
		return repaired()
	end
	sell(C_Container.GetContainerItemInfo(bag, slot))
end

-- Sell All Junk sells every poor-quality stack in the bags in one call, without UseContainerItem.
local function soldJunk()
	if not atMerchant or not C_Container.GetContainerItemInfo then
		return
	end
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.quality == 0 then
				sell(info)
			end
		end
	end
end

local function bought(index, quantity)
	if not atMerchant then
		return
	end
	local id = GetMerchantItemID and GetMerchantItemID(index)
	local link = GetMerchantItemLink and GetMerchantItemLink(index)
	local price, stack, extended
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if info then
			price, stack, extended = info.price, info.stackCount, info.hasExtendedCost
		end
	else
		local _
		_, _, price, stack, _, _, _, extended = GetMerchantItemInfo(index)
	end
	stack = (stack and stack > 0) and stack or 1
	local qty = quantity or stack
	-- The listed price is for a stack of `stack`; currency and item costs are not copper.
	local total = (price and price > 0 and not extended) and math.floor(price / stack * qty + 0.5) or nil
	record("buy", Encode.itemKey(link) or (id and tostring(id)), qty, total)
end

local function boughtBack(index)
	if not atMerchant or not GetBuybackItemInfo then
		return
	end
	local _, _, price, quantity = GetBuybackItemInfo(index)
	local link = GetBuybackItemLink and GetBuybackItemLink(index)
	record("buyback", Encode.itemKey(link), quantity or 1, price)
end

if C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
		ns.safely("trade", sold, bag, slot)
	end)
end
if C_MerchantFrame and C_MerchantFrame.SellAllJunkItems then
	hooksecurefunc(C_MerchantFrame, "SellAllJunkItems", function()
		ns.safely("trade", soldJunk)
	end)
end
local function picked()
	if repairing() then
		repaired()
	end
end

if RepairAllItems then
	hooksecurefunc("RepairAllItems", function()
		ns.safely("trade", repaired)
	end)
end
if PickupInventoryItem then
	hooksecurefunc("PickupInventoryItem", function()
		ns.safely("trade", picked)
	end)
end
if C_Container and C_Container.PickupContainerItem then
	hooksecurefunc(C_Container, "PickupContainerItem", function()
		ns.safely("trade", picked)
	end)
end
if BuyMerchantItem then
	hooksecurefunc("BuyMerchantItem", function(index, quantity)
		ns.safely("trade", bought, index, quantity)
	end)
end
if BuybackItem then
	hooksecurefunc("BuybackItem", function(index)
		ns.safely("trade", boughtBack, index)
	end)
end
