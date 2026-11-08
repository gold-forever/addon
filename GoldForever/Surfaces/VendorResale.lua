-- Gold Forever: at a merchant, an item that fetches more on the auction house than the vendor asks carries a
-- small coin in the merchant's list and a tooltip line "Resell: 4g 98s on the AH · +3g 83s after the cut"
-- (gf#317): only with sales, only with the market value after the cut at least 20% over the vendor's price
-- of one, and only for gold. Nothing is recorded.

local _, ns = ...
local VendorResale = {}
ns.VendorResale = VendorResale

local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local COIN_SIZE = 14
local MARGIN_PERCENT = 120 -- the market value after the cut, as a percentage of the vendor's price
local PAGE_SLOTS = 12 -- past the 10 a merchant page shows today, so a longer page is still read

-- item: { id, price, stack, available (-1 unlimited), extended (costs more than gold) } → { value, gain,
-- limited }, or nil when it is no resale.
function VendorResale.offer(item)
	if not item.id or item.extended or not item.price or item.price <= 0 then
		return nil
	end
	local value = ns.price.market(item.id)
	if not value then
		return nil
	end
	local net = math.floor(value * (1 - ns.price.cut) + 0.5)
	local stack = math.max(1, item.stack or 1)
	if net * stack * 100 < item.price * MARGIN_PERCENT or not ns.ResaleSales.hasSales(item.id) then
		return nil
	end
	return { value = value, gain = net - item.price / stack, limited = (item.available or -1) >= 0 }
end

function VendorResale.line(offer)
	return "Resell: " .. ns.Money.auction(offer.value) .. " on the AH · +" .. ns.Money.auction(offer.gain) .. " after the cut"
		.. (offer.limited and " (limited)" or "")
end

-- The merchant's window ------------------------------------------------------------------------------------

local marks = {} -- button -> its coin texture
local lines = {} -- button -> its tooltip line, for the items marked now

local function marked(button)
	return button and lines[button] and ns.tipLine("vendorResale")
end

-- As QuestRewards.lua: the line is added as the item's tooltip is drawn, so a redraw on Shift keeps it; on a
-- client whose merchant tooltip is not drawn from tooltip data, the button's OnEnter adds it instead.
local drawn -- the button whose tooltip the post call gave the line
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local function merchantTooltip(tooltip)
		local owner = tooltip == GameTooltip and tooltip.GetOwner and tooltip:GetOwner()
		if marked(owner) then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. lines[owner], 1, 0.82, 0)
			drawn = owner
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
		ns.safely("vendor resale tooltip", merchantTooltip, tooltip)
	end)
end

local function onEnter(button)
	if drawn == button then
		drawn = nil
		return
	end
	if marked(button) and GameTooltip then
		GameTooltip:AddLine(ns.tipPrefix(GameTooltip) .. lines[button], 1, 0.82, 0)
		GameTooltip:Show()
	end
end

local function coin(button)
	local mark = marks[button]
	if not mark then
		mark = button:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(COIN)
		mark:SetSize(COIN_SIZE, COIN_SIZE)
		mark:SetPoint("TOPLEFT", button, "TOPLEFT", -4, 4)
		marks[button] = mark
		button:HookScript("OnEnter", onEnter)
	end
	return mark
end

local function clear()
	lines = {}
	for _, mark in pairs(marks) do
		mark:Hide()
	end
end

local function merchantItem(index)
	local item = { id = GetMerchantItemID(index) }
	if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
		local info = C_MerchantFrame.GetItemInfo(index)
		if not info then
			return item
		end
		item.price, item.stack, item.available, item.extended = info.price, info.stackCount, info.numAvailable, info.hasExtendedCost
	else
		local _
		_, _, item.price, item.stack, item.available, _, _, item.extended = GetMerchantItemInfo(index)
	end
	return item
end

local function mark()
	clear()
	if ns.settings("prices").vendorResale == false then
		return
	end
	for slot = 1, PAGE_SLOTS do
		local button = _G["MerchantItem" .. slot .. "ItemButton"]
		local offer = button and button:IsShown() and VendorResale.offer(merchantItem(button:GetID()))
		if offer then
			lines[button] = VendorResale.line(offer)
			coin(button):Show()
		end
	end
end

-- Blizzard redraws the list's buttons for a page turn, a purchase or the buyback tab; the coins follow it.
if hooksecurefunc and MerchantFrame_UpdateMerchantInfo then
	hooksecurefunc("MerchantFrame_UpdateMerchantInfo", function()
		ns.safely("vendor resale", mark)
	end)
end
if hooksecurefunc and MerchantFrame_UpdateBuybackInfo then
	hooksecurefunc("MerchantFrame_UpdateBuybackInfo", function()
		ns.safely("vendor resale", clear)
	end)
end
