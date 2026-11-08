-- Gold Forever: a small mark on each item in Blizzard's bag and bank frames saying what to do with it (post,
-- vendor, disenchant; nothing for keep) and the same word as one tooltip line. SalePlan.verdict is the rule.
-- Nothing is moved, sold or recorded; the cheapest-item coin (BagMark.lua) keeps its corner.

local _, ns = ...

local BagVerdict = {}
ns.BagVerdict = BagVerdict

local GEAR = { [2] = true, [4] = true } -- item classes: weapon, armor
local THROTTLE_SECONDS = 0.25
local ICON_SIZE = 12
local ICONS = {
	post = "Interface\\AddOns\\GoldForever\\Media\\Icons\\gavel",
	vendor = "Interface\\AddOns\\GoldForever\\Media\\Icons\\coins",
	disenchant = "Interface\\Icons\\INV_Enchant_Disenchant",
}
local textures = {} -- item button -> its mark, made the first time it is marked
local shown = {} -- item button -> its verdict, with the item's id

-- The tooltip words of a verdict.
function BagVerdict.line(v, coins)
	local why
	if v.word == "keep" then
		why = v.why
	elseif v.word == "disenchant" then
		why = "~" .. coins(v.disenchant) .. (v.sale and (", best sale " .. coins(v.sale)) or "")
	elseif v.word == "vendor" then
		why = "vendor " .. coins(v.sale)
	else
		why = "AH " .. coins(v.sale) .. " after the cut" .. (v.vendor and (", vendor " .. coins(v.vendor)) or "")
	end
	return "Verdict: " .. v.word .. " (" .. why .. ")"
end

-- What this character means to buy, item ID -> true: its shopping lists and an active profile's buy rules.
local function wanted()
	local s = ns.auctionSettings()
	local guid = UnitGUID and ns.readable(UnitGUID("player"))
	local out = {}
	for _, list in ipairs(s.lists or {}) do
		if ns.Shopping.forCharacter(list, guid) then
			for _, entry in ipairs(list.entries or {}) do
				out[entry.itemId] = true
			end
		end
	end
	local profile = ns.activeProfile(s)
	for _, rule in ipairs(profile and profile.buy or {}) do
		out[rule.itemID] = true
	end
	return out
end

local function verdictOf(s, info, listed, queue)
	local price, id = ns.price, info.itemID
	local worth, where = price.worth(id)
	local disenchant, skill = price.disenchant(id)
	return ns.SalePlan.verdict({ worth = worth, where = where, vendor = price.vendor(id), disenchant = disenchant, skill = skill,
		enchanting = price.enchanting(), quest = ns.BagMark.isQuest(s.bag, s.slot, id), listed = listed[id], queued = queue[id] ~= nil,
		bound = info.isBound, gear = GEAR[tonumber((select(3, price.itemInfo(id))))] })
end

local function place(button, word)
	local t = textures[button]
	if not t then
		t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetSize(ICON_SIZE, ICON_SIZE)
		t:SetPoint("TOPLEFT", 2, -2)
		textures[button] = t
	end
	t:SetTexture(ICONS[word])
	t:Show()
end

local function draw()
	for _, t in pairs(textures) do
		t:Hide()
	end
	shown = {}
	if ns.settings("prices").bagVerdict == false then
		return
	end
	local listed, queue = wanted(), ns.queueNeeds()
	for _, s in ipairs(ns.BagMark.shownButtons()) do
		local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
		if info and info.itemID then
			local v = verdictOf(s, info, listed, queue)
			v.id = info.itemID
			shown[s.button] = v
			if ICONS[v.word] and not ns.BagMark.isMarked(s.button) then
				place(s.button, v.word)
			end
		end
	end
end

local function drawOutOfCombat()
	ns.afterCombat("bag verdict", draw)
end

local throttled = ns.throttle("bag verdict", THROTTLE_SECONDS, drawOutOfCombat)
-- With no bag open and nothing left to clear there is nothing to draw, so no timer either.
local function soon()
	if next(shown) or #ns.BagMark.shownButtons() > 0 then
		throttled()
	end
end
BagVerdict.refresh = soon

ns.on("BAG_UPDATE", "bag verdict", soon)
ns.on("PLAYERBANKSLOTS_CHANGED", "bag verdict", soon)
ns.listen("bagMarkDrawn", "bag verdict", soon)
ns.listen("pricesReady", "bag verdict", soon)

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local function verdictTooltip(tooltip, data)
		local v = tooltip == GameTooltip and data and next(shown) and shown[tooltip:GetOwner()]
		if not v or v.id ~= data.id or not ns.tipLine("bagVerdict") then
			return
		end
		tooltip:AddLine(ns.tipPrefix(tooltip) .. BagVerdict.line(v, ns.price.coins), 1, 1, 1)
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("bag verdict tooltip", verdictTooltip, tooltip, data)
	end)
end
