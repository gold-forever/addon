-- Gold Forever: the auction panel's side of Blizzard's own auction house window: its modes as the
-- panel's tabs, an item shown in it or put in its Sell window, and its post warning closed.

local _, ns = ...

local Blizzard = {}
ns.AuctionBlizzard = Blizzard

-- The panel's tabs and Blizzard's in step (manual test run 001): its Buy, Sell and Auctions modes are
-- our Buy, Sell and Auctions. `following` is set while the panel itself moves Blizzard's window (a tab
-- clicked here, an item shown), so that move does not switch the panel back.
local following = false
function Blizzard.tabForMode(mode)
	local M = AuctionHouseFrameDisplayMode
	if not M or not mode then
		return nil
	end
	if mode == M.Buy or mode == M.ItemBuy or mode == M.CommoditiesBuy then
		return "shop"
	elseif mode == M.ItemSell or mode == M.CommoditiesSell then
		return "post"
	elseif mode == M.Auctions then
		return "cancel"
	end
end

function Blizzard.mode()
	local f = AuctionHouseFrame
	if not f then
		return nil
	end
	return f.GetDisplayMode and f:GetDisplayMode() or f.displayMode
end

-- Shows an item's listings in Blizzard's window; true when it did. Blizzard's SelectBrowseResult reads
-- the item key's info and fails when the client has not loaded it yet (manual test run 001: "attempt to
-- index local itemKeyInfo"): the client is asked for it, and the item is shown when it arrives.
local waitingKey
function Blizzard.browse(itemKey)
	local f = AuctionHouseFrame
	if not (itemKey and f and f.SelectBrowseResult and f:IsShown()) then
		return false
	end
	if C_AuctionHouse.GetItemKeyInfo and not C_AuctionHouse.GetItemKeyInfo(itemKey) then
		waitingKey = itemKey
		return false
	end
	waitingKey = nil
	following = true
	-- A browse result as Blizzard's list hands it: it shows minPrice at once ("rawCopper" nil without it,
	-- manual test run 001), before its own search brings the listings; the market value stands in.
	local price = ns.Prices.value(itemKey.itemID)
	local ok = pcall(f.SelectBrowseResult, f, { itemKey = itemKey, minPrice = math.floor(price or 0), totalQuantity = 0 })
	if not ok then
		-- Else the item's name in Blizzard's search bar, searched there.
		local bar = f.SearchBar
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemKey.itemID)
		if bar and bar.SearchBox and bar.StartSearch and name then
			if f.SetDisplayMode and AuctionHouseFrameDisplayMode then
				pcall(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Buy)
			end
			bar.SearchBox:SetText(name)
			ok = ns.safely("auction search bar", bar.StartSearch, bar)
		end
	end
	following = false
	return ok
end
ns.on("ITEM_KEY_ITEM_INFO_RECEIVED", "auction panel", function(itemID)
	if waitingKey and waitingKey.itemID == itemID then
		Blizzard.browse(waitingKey)
	end
end)

-- Empties Blizzard's own Sell window before the panel posts what it holds: its frame keeps the bag slot,
-- and once the item has gone it asks that empty slot for an item level and fails (manual test run 001:
-- "bad argument #1 to 'GetCurrentItemLevel'" after a post). Blizzard's Post button empties it itself.
function Blizzard.clearSell()
	local f = AuctionHouseFrame
	if not f then
		return
	end
	following = true
	for _, sell in ipairs({ f.ItemSellFrame, f.CommoditiesSellFrame }) do
		if sell and sell.SetItem and (sell.itemLocation or (sell.GetItem and sell:GetItem())) then
			pcall(sell.SetItem, sell, nil)
		end
	end
	following = false
end

-- Puts a bag item in Blizzard's own Sell window, as a click on it in the bags does there; true when it did.
function Blizzard.sellItem(location)
	local f = AuctionHouseFrame
	if not (location and f and f.SetPostItem and f:IsShown()) then
		return false
	end
	following = true
	local ok = ns.safely("auction sell item", f.SetPostItem, f, location)
	following = false
	return ok
end

-- Blizzard's own window shows its warning too, and its Accept finds no post of its own to confirm:
-- for a post of the panel's, that popup is closed (the next frame, after Blizzard's handler opened it).
function Blizzard.closeWarning()
	C_Timer.After(0, function()
		if StaticPopup_Hide then
			StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING")
		end
	end)
end

local BLIZZARD_TAB = { shop = "BuyTab", post = "SellTab", cancel = "AuctionsTab" }
-- A tab chosen in the panel moves Blizzard's window to its own.
function Blizzard.showTab(key)
	local b = AuctionHouseFrame and AuctionHouseFrame[BLIZZARD_TAB[key] or ""]
	if b and b.Click and b:IsShown() and Blizzard.tabForMode(Blizzard.mode()) ~= key then
		following = true
		ns.safely("auction tab", b.Click, b)
		following = false
	end
end

-- Blizzard's tab chosen there: onTab(key) with the panel's own, unless the panel moved it itself.
local hooked = false
function Blizzard.followTabs(onTab)
	if not hooked and AuctionHouseFrame.SetDisplayMode and hooksecurefunc then
		hooked = true
		hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
			local key = not following and Blizzard.tabForMode(mode)
			if key then
				onTab(key)
			end
		end)
	end
end
