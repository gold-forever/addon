-- Gold Forever: a Sell junk button under the merchant window, where it has no button of its own
-- (Blizzard's retail one has; WoW: Forever's client has the call, C_MerchantFrame.SellAllJunkItems, and
-- no button). What Blizzard counts as junk, sold by its own call, so it stays in the buyback tab.

local _, ns = ...
local UI = ns.UI

local SELL_ARMED = 5 -- seconds the first press waits for the second
local buttons, armedAt -- one button per look and accent (UI.perLook)

-- How many junk items the merchant would take and what they fetch; nil where our button has no place.
local function junkSale()
	local api = C_MerchantFrame
	if not (api and api.SellAllJunkItems and api.GetNumJunkItems) or MerchantSellAllJunkButton then
		return nil
	end
	if api.IsSellAllJunkEnabled and not api.IsSellAllJunkEnabled() then
		return nil
	end
	local n = api.GetNumJunkItems() or 0
	if n == 0 then
		return nil
	end
	local value = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and info.quality == 0 and not info.hasNoValue then
				value = value + (ns.price.vendor(info.itemID) or 0) * (info.stackCount or 1)
			end
		end
	end
	return n, value
end

local function refresh()
	local sell = buttons.frame
	if not sell then
		return
	end
	local n, value = nil, nil
	if MerchantFrame and MerchantFrame:IsShown() then
		n, value = junkSale()
	end
	if not n then
		sell:Hide()
		return
	end
	local armed = armedAt and GetTime() - armedAt < SELL_ARMED
	sell:SetLabel(armed and string.format("Press again: sell %d for %s", n, ns.price.coins(value))
		or string.format("Sell junk: %d %s · %s", n, n == 1 and "item" or "items", ns.price.coins(value)))
	sell:Show()
end

-- Two presses: the first says what it will sell, the second sells.
local function press()
	local n, value = junkSale()
	if not n then
		return
	end
	if armedAt and GetTime() - armedAt < SELL_ARMED then
		armedAt = nil
		C_MerchantFrame.SellAllJunkItems()
		ns.say(string.format("sold %d junk %s for %s; the buyback tab has them for now.", n, n == 1 and "item" or "items", ns.price.coins(value)))
	else
		armedAt = GetTime()
		C_Timer.After(SELL_ARMED, refresh)
	end
	refresh()
end

local function build()
	local sell = UI.Button(MerchantFrame, "Sell junk", function()
		ns.safely("sell junk", press)
	end, { width = 240, height = 26 })
	sell:Hide()
	return sell
end

-- Under the merchant window, clear of its own buttons.
local function dock(sell)
	sell:ClearAllPoints()
	sell:SetPoint("TOPLEFT", MerchantFrame, "BOTTOMLEFT", 0, -4)
end
buttons = UI.perLook(build, dock)

ns.on("MERCHANT_SHOW", "sell junk", function()
	if not MerchantFrame or not junkSale() then
		return
	end
	local sell = buttons.frame
	if not sell or buttons.key ~= ns.Theme.key then
		sell = buttons:get()
	end
	dock(sell)
	refresh()
end)
ns.on("MERCHANT_CLOSED", "sell junk", function()
	if buttons.frame then
		buttons.frame:Hide()
	end
end)
ns.on("BAG_UPDATE_DELAYED", "sell junk", refresh)
buttons:onLook("sell junk", function(redrawn)
	if redrawn then
		refresh()
	end
end)

-- For the smoke test.
ns.SellJunk = {
	button = function()
		return buttons.frame
	end,
}
