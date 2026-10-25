-- Gold Forever: the loot advisor. What to do with what is in the bags: sell it to a vendor, post it
-- on the auction house, or disenchant it, whichever brings the most, with the totals. Shown at a
-- vendor and with /gf bags. Prices and valuation are Pricing.lua's (ns.price).

local _, ns = ...

local LIST_LENGTH = 8 -- items shown per list; the rest are summed in one line

local frame, body

local function settings()
	return ns.settings("advisor", { shown = true })
end

-- Bag contents by item and whether it is bound (bound items cannot go to the auction house).
local function contents()
	local stacks = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.hasNoValue then
				local key = info.itemID .. (info.isBound and ":bound" or "")
				local s = stacks[key] or { id = info.itemID, bound = info.isBound, count = 0 }
				stacks[key] = s
				s.count = s.count + (info.stackCount or 1)
			end
		end
	end
	return stacks
end

-- Each stack's best use, by list (Views.adviseStacks).
local function advise()
	return ns.Views.adviseStacks(contents(), ns.price, ns.price.enchanting())
end

local HEADINGS = {
	{ "vendor", "|cffffd100Vendor these|r" },
	{ "post", "|cff56c98fPost these|r" },
	{ "disenchant", "|cffa335eeDisenchant these|r" },
}

local function text()
	local coins = ns.price.coins
	local lists, totals = advise()
	local lines = {}
	for _, h in ipairs(HEADINGS) do
		local use, heading = h[1], h[2]
		local list = lists[use]
		if #list > 0 then
			if #lines > 0 then
				table.insert(lines, " ")
			end
			table.insert(lines, heading .. " · " .. coins(totals[use]))
			for i = 1, math.min(LIST_LENGTH, #list) do
				local x = list[i]
				local line = string.format("%d× %s · %s", x.count, x.name, coins(x.value))
				if use == "post" and x.market then
					line = line .. "|cff999999 (post at " .. coins(x.market) .. " each)|r"
				end
				table.insert(lines, line)
			end
			if #list > LIST_LENGTH then
				local rest = 0
				for i = LIST_LENGTH + 1, #list do
					rest = rest + list[i].value
				end
				table.insert(lines, string.format("|cff999999and %d more · %s|r", #list - LIST_LENGTH, coins(rest)))
			end
		end
	end
	if #lines == 0 then
		return "Nothing in your bags is worth anything yet."
	end
	local total = totals.vendor + totals.post + totals.disenchant
	table.insert(lines, " ")
	table.insert(lines, "|cffffffffAll of it: " .. coins(total) .. "|r")
	return table.concat(lines, "\n")
end

-- Selling junk where the merchant window has no button of its own (Blizzard's retail one has; WoW:
-- Forever's client has the call, C_MerchantFrame.SellAllJunkItems, and no button): what Blizzard counts
-- as junk, sold by its own call, so it stays in the buyback tab. Returns how many and what they fetch.
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

local SELL_ARMED = 5 -- seconds the first press of Sell junk waits for the second
local sell, armedAt

local function refresh()
	if frame and frame:IsShown() then
		body:SetText(text())
		local n, value = nil, nil
		if MerchantFrame and MerchantFrame:IsShown() then
			n, value = junkSale()
		end
		if n and sell then
			local armed = armedAt and GetTime() - armedAt < SELL_ARMED
			sell.label:SetText(armed and string.format("Press again: sell %d for %s", n, ns.price.coins(value))
				or string.format("Sell junk: %d %s · %s", n, n == 1 and "item" or "items", ns.price.coins(value)))
			sell:Show()
		elseif sell then
			sell:Hide()
		end
		frame:SetHeight(body:GetStringHeight() + 40 + (n and 34 or 0))
	end
end

local function show()
	if not frame then
		frame, body = ns.makeWindow("GoldForeverAdvisor", "Gold Forever · your loot", settings(), { "LEFT", 60, 80 }, function()
			ns.say("/gf bags shows it again; it opens at vendors unless you hide it there with /gf bags.")
		end)
		frame:SetWidth(330)
		body:SetWidth(310)
		if ns.applyLook then
			ns.applyLook()
		end
		-- Two presses: the first says what it will sell, the second sells.
		sell = ns.UI.Button(frame, "Sell junk", function()
			ns.safely("sell junk", function()
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
			end)
		end, { width = 310, height = 26 })
		sell:SetPoint("BOTTOM", 0, 10)
		sell:Hide()
	end
	frame:Show()
	refresh()
end

ns.on("MERCHANT_SHOW", "advisor", function()
	if settings().shown then
		show()
	end
end)
ns.on("MERCHANT_CLOSED", "advisor", function()
	if frame then
		frame:Hide()
	end
end)
ns.on("BAG_UPDATE_DELAYED", "advisor", refresh)

-- /gf bags shows or hides it; hiding it at a vendor keeps it from opening at vendors.
ns.commands.bags = function()
	if frame and frame:IsShown() then
		frame:Hide()
		if MerchantFrame and MerchantFrame:IsShown() then
			settings().shown = false
			ns.say("the loot advisor no longer opens at vendors; /gf bags at one turns it back on.")
		end
	else
		if MerchantFrame and MerchantFrame:IsShown() then
			settings().shown = true
		end
		show()
	end
end

-- For the smoke test.
ns.Advisor = {
	sellButton = function()
		return sell
	end,
}
