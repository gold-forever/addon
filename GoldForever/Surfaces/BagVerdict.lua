-- Gold Forever: a small mark on each item in Blizzard's bag and bank frames saying what to do with it (post,
-- vendor, disenchant; nothing for keep); the tooltip's price block says the word (Tooltips.lua). SalePlan.verdict
-- is the rule.
-- Nothing is moved, sold or recorded; the cheapest-item coin (BagMark.lua) keeps its corner.

local _, ns = ...
local L = ns.L

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
local shown = {} -- item button -> its verdict, with the item's id and stack count

-- A verdict's word and a keep's reason (SalePlan.verdict) as the player reads them.
local WORDS = { keep = L["keep"], disenchant = L["disenchant"], vendor = L["vendor"], post = L["post"] }
local WHY = {
	["a quest item"] = L["a quest item"], ["on a shopping list"] = L["on a shopping list"],
	["in the craft queue"] = L["in the craft queue"], ["soulbound gear"] = L["soulbound gear"], ["no price"] = L["no price"],
}

-- A verdict's words for the tooltip's Suggestion line: the word and its reason.
function BagVerdict.line(v, coins)
	local why
	if v.word == "keep" then
		why = WHY[v.why] or v.why
	elseif v.word == "disenchant" then
		why = "~" .. coins(v.disenchant) .. (v.sale and string.format(L[", best sale %s"], coins(v.sale)) or "")
	elseif v.word == "vendor" then
		why = string.format(L["vendor %s"], coins(v.sale))
	else
		why = string.format(L["AH %s after the cut"], coins(v.sale)) .. (v.vendor and string.format(L[", vendor %s"], coins(v.vendor)) or "")
	end
	return string.format(L["%s (%s)"], WORDS[v.word] or v.word, why)
end

-- What this character means to buy, item ID -> true: its shopping lists and an active profile's buy rules.
function BagVerdict.wanted()
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
	local marking = ns.settings("prices").bagVerdict ~= false -- off: no marks, the tooltip's words stay
	local listed, queue = BagVerdict.wanted(), ns.queueNeeds()
	for _, s in ipairs(ns.BagMark.shownButtons()) do
		local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
		if info and info.itemID then
			local v = verdictOf(s, info, listed, queue)
			v.id, v.count = info.itemID, info.stackCount or 1
			shown[s.button] = v
			if marking and ICONS[v.word] and not ns.BagMark.isMarked(s.button) then
				place(s.button, v.word)
			end
		end
	end
end

-- For /gf bags: the first of these buttons with an item, its item and its verdict; nil when all are empty.
function BagVerdict.sample(buttons)
	for _, s in ipairs(buttons) do
		local info = C_Container.GetContainerItemInfo(s.bag, s.slot)
		if info and info.itemID then
			return s, info, verdictOf(s, info, BagVerdict.wanted(), ns.queueNeeds())
		end
	end
end

-- The verdict drawn for this item button, when it still holds item `id`; nil otherwise.
function BagVerdict.at(button, id)
	local v = next(shown) and shown[button]
	return v and v.id == id and v or nil
end

-- For /gf bags: how many verdict marks are showing.
function BagVerdict.marksShowing()
	local n = 0
	for _, t in pairs(textures) do
		if t:IsShown() then
			n = n + 1
		end
	end
	return n
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

-- /gf bags: why the marks do or don't show (gf#331).
local REPLACEMENT_BAG_ADDONS = { "Bagnon", "ArkInventory", "Baganator", "AdiBags" }

local function addonLoaded(name)
	if C_AddOns and C_AddOns.IsAddOnLoaded then
		return C_AddOns.IsAddOnLoaded(name)
	end
	return IsAddOnLoaded and IsAddOnLoaded(name)
end

-- Each section is one line; a read that fails costs only its own line.
local function section(label, read)
	local ok, text = pcall(read)
	print(string.format(L["  %s: %s"], label, ok and text or string.format(L["could not read (%s)"], tostring(text))))
end

local function frameLine(r)
	local parts = { string.format(L["%s: %s"], r.name, r.shown == nil and L["unknown"] or r.shown and L["shown"] or L["hidden"]), r.how }
	if r.err then
		parts[#parts + 1] = string.format(L["could not read (%s)"], r.err)
	elseif r.count then
		parts[#parts + 1] = ns.plural(r.count, L["%d button"], L["%d buttons"])
	end
	return table.concat(parts, ", ")
end

local function sampleLine()
	local s, info, verdict = BagVerdict.sample(ns.BagMark.shownButtons())
	if not s then
		return L["no item in a shown slot"]
	end
	return string.format(L["bag %s slot %s, %s, %s"], tostring(s.bag), tostring(s.slot), info.hyperlink or string.format(L["item %d"], info.itemID),
		BagVerdict.line(verdict, ns.price.coins))
end

local function errorWords(name)
	local e = ns.lastError(name)
	if not e then
		return string.format(L["%s none"], name)
	end
	return string.format(L["%s failed %dx, %d min ago: %s"], name, e.n, math.floor((GetServerTime() - e.t) / 60), e.msg)
end

local function switchWord(name)
	return ns.settings("prices")[name] == false and L["off"] or L["on"]
end

local function replacementAddons()
	local found = {}
	for _, name in ipairs(REPLACEMENT_BAG_ADDONS) do
		if addonLoaded(name) then
			found[#found + 1] = name
		end
	end
	return #found > 0 and table.concat(found, ", ") or L["none"]
end

ns.commands.bags = function()
	print(string.format(L["%s bags:"], ns.PREFIX))
	local open
	section(L["frames"], function()
		local lines, anyShown = {}, false
		for i, r in ipairs(ns.BagMark.frameReport()) do
			lines[i] = frameLine(r)
			anyShown = anyShown or r.shown == true
		end
		open = anyShown
		return #lines > 0 and table.concat(lines, " · ") or L["none exist"]
	end)
	if open == false then
		print(L["  open your bags first"])
	else
		section(L["item buttons"], function()
			return tostring(#ns.BagMark.shownButtons())
		end)
		section(L["sample"], sampleLine)
	end
	section(L["marks showing"], function()
		return string.format(L["%d verdict, %d coin"], BagVerdict.marksShowing(), ns.BagMark.coinShowing() and 1 or 0)
	end)
	section(L["switches"], function()
		return string.format(L["bag mark %s, bag verdict %s"], switchWord("bagMark"), switchWord("bagVerdict"))
	end)
	section(L["last error"], function()
		return errorWords("bag verdict") .. ", " .. errorWords("bag mark")
	end)
	section(L["replacement bag addon"], replacementAddons)
end
