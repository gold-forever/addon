-- Gold Forever: the loot advisor. What to do with what is in the bags: sell it to a vendor, post it
-- on the auction house, or disenchant it, whichever brings the most, with the totals. Shown at a
-- vendor and with /gf bags. Prices and valuation are the appraiser's (ns.price).

local _, ns = ...

local LIST_LENGTH = 8 -- items shown per list; the rest are summed in one line

local frame, body

local function settings()
	local s = ns.db().settings
	s.advisor = s.advisor or { shown = true }
	return s.advisor
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

-- Each stack's best use: { use = "vendor" | "post" | "disenchant", value, unit, … }.
local function advise()
	local p = ns.price
	local lists = { vendor = {}, post = {}, disenchant = {} }
	local totals = { vendor = 0, post = 0, disenchant = 0 }
	for _, s in pairs(contents()) do
		local options = {}
		local vendor = p.vendor(s.id)
		if vendor then
			options.vendor = vendor * s.count
		end
		local market = not s.bound and p.market(s.id)
		if market then
			options.post = math.floor(market * (1 - p.cut)) * s.count
		end
		local de, skill = p.disenchant(s.id)
		if de and de > 0 and p.enchanting() >= skill then
			options.disenchant = de * s.count
		end
		local best, value
		for use, v in pairs(options) do
			if not value or v > value then
				best, value = use, v
			end
		end
		if best and value > 0 then
			local _, _, _, _, name = p.itemInfo(s.id)
			table.insert(lists[best], { id = s.id, name = name or ("item " .. s.id), count = s.count, value = value, market = market })
			totals[best] = totals[best] + value
		end
	end
	for _, list in pairs(lists) do
		table.sort(list, function(a, b)
			return a.value > b.value
		end)
	end
	return lists, totals
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

local function refresh()
	if frame and frame:IsShown() then
		body:SetText(text())
		frame:SetHeight(body:GetStringHeight() + 40)
	end
end

local function show()
	if not frame then
		frame, body = ns.makeWindow("GoldForeverAdvisor", "Gold Forever · your loot", settings(), { "LEFT", 60, 80 }, function()
			print("|cffe0ac45Gold Forever|r: /gf bags shows it again; it opens at vendors unless you hide it there with /gf bags.")
		end)
		frame:SetWidth(330)
		body:SetWidth(310)
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
			print("|cffe0ac45Gold Forever|r: the loot advisor no longer opens at vendors; /gf bags at one turns it back on.")
		end
	else
		if MerchantFrame and MerchantFrame:IsShown() then
			settings().shown = true
		end
		show()
	end
end
