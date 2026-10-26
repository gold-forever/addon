-- Gold Forever: what is sold to and bought from vendors (data gap D4, docs/research/
-- 2026-10-23-data-opportunities.md in the web repository). One `merchantTrade` row per trade at an
-- open merchant:
--   sell     an item from the bags, as the client sells it on a right-click and as sell-junk addons do
--            (C_Container.UseContainerItem): the item's vendor price times the stack
--   buy      BuyMerchantItem: the merchant's price for the quantity; empty for items paid in currency
--            or other items
--   buyback  BuybackItem: the buyback price
-- Price is the total in copper. The money stream already has the merchant's coin; this says what for.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.merchantTrade = "t,char,kind,item,qty,price,map"

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
	ns.append("merchantTrade", Encode.row(ns.now(), me.ref, kind, key, qty, price, map))
	ns.catalogueItem(key)
end

-- Selling: the hook runs right after the call, while the item still sits in its slot, locked until the
-- server answers. An item without a vendor price is not sold, so nothing is written.
local function sold(bag, slot)
	if not atMerchant or not C_Container.GetContainerItemInfo then
		return
	end
	local info = C_Container.GetContainerItemInfo(bag, slot)
	if not info or info.hasNoValue then
		return
	end
	local link = info.hyperlink
	local id = info.itemID or (link and Encode.itemId(Encode.itemKey(link)))
	local sellPrice = id and select(11, C_Item.GetItemInfo(id))
	if not sellPrice or sellPrice <= 0 then
		return
	end
	local count = info.stackCount or 1
	record("sell", Encode.itemKey(link) or tostring(id), count, sellPrice * count)
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
