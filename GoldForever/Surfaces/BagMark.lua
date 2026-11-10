-- Gold Forever: with no free bag slot, the stack worth least in the bags carries a small copper coin in its
-- slot's corner and one tooltip line, "Cheapest in your bags: 3c", so a farming player knows what to drop
-- (addon#96). Blizzard's own bag frames only; nothing is moved or deleted: that stays the player's.

local _, ns = ...
local L = ns.L

local BagMark = {}
ns.BagMark = BagMark

local QUEST_CLASS = 12 -- an item's class ID for quest items
local ICON = "Interface\\MoneyFrame\\UI-CopperIcon"
local ICON_SIZE = 12
local marks = {} -- item button -> its coin texture, made the first time it is marked
local marked -- the button marked now, with its { stack, total }
local hooked = {} -- bag frames whose OnShow refreshes the mark

-- The stack to make room with: the least worth in all (a unit's worth(id) times the stack), never soulbound,
-- a quest item or one without a price; on equal totals, the first in bag order. Returns it and its total.
function BagMark.pick(stacks, worth)
	local best, least
	for _, s in ipairs(stacks) do
		local unit = not s.bound and not s.quest and worth(s.id)
		if unit and (not least or unit * s.count < least) then
			best, least = s, unit * s.count
		end
	end
	return best, least
end

function BagMark.isQuest(bag, slot, id)
	local info = C_Container.GetContainerItemQuestInfo and C_Container.GetContainerItemQuestInfo(bag, slot)
	if info and info.isQuestItem then
		return true
	end
	return tonumber((select(3, ns.price.itemInfo(id)))) == QUEST_CLASS
end

-- Every stack in the general bags (a profession bag's slot frees no room for loot), or nil when one has a
-- free slot.
local function fullBags()
	local stacks = {}
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local free, kind = C_Container.GetContainerNumFreeSlots(bag)
		if (kind or 0) == 0 then
			if (free or 0) > 0 then
				return nil
			end
			for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
				local info = C_Container.GetContainerItemInfo(bag, slot)
				if info and info.itemID then
					stacks[#stacks + 1] = { bag = bag, slot = slot, id = info.itemID, count = info.stackCount or 1,
						bound = info.isBound, quest = BagMark.isQuest(bag, slot, info.itemID) }
				end
			end
		end
	end
	return stacks
end

-- Blizzard's bag frames: one a bag (ContainerFrame1…), and retail's combined bags.
local function bagFrames()
	local list = {}
	for i = 1, NUM_CONTAINER_FRAMES or 13 do
		local name = "ContainerFrame" .. i
		list[#list + 1] = _G[name] and { frame = _G[name], name = name }
	end
	list[#list + 1] = ContainerFrameCombinedBags and { frame = ContainerFrameCombinedBags }
	return list
end

-- The bank's own frames: the classic slots (BankFrameItem1…) and retail's tabbed panel.
local function addBank(out)
	if BankPanel and BankPanel:IsShown() and BankPanel.EnumerateValidItems then
		for b in BankPanel:EnumerateValidItems() do
			out[#out + 1] = { button = b, bag = b:GetBankTabID(), slot = b:GetContainerSlotID() }
		end
	elseif BankFrame and BankFrame:IsShown() then
		for j = 1, NUM_BANKGENERIC_SLOTS or 28 do
			local b = _G["BankFrameItem" .. j]
			if b then
				out[#out + 1] = { button = b, bag = BANK_CONTAINER or -1, slot = b:GetID() }
			end
		end
	end
end

local function addFrameButtons(out, f)
	local frame = f.frame
	if frame.EnumerateValidItems then
		for _, b in frame:EnumerateValidItems() do
			out[#out + 1] = { button = b, bag = b.GetBagID and b:GetBagID() or frame:GetID(), slot = b:GetID() }
		end
	elseif f.name then
		for j = 1, frame.size or MAX_CONTAINER_ITEMS or 36 do
			local b = _G[f.name .. "Item" .. j]
			if b then
				out[#out + 1] = { button = b, bag = b.GetBagID and b:GetBagID() or frame:GetID(), slot = b:GetID() }
			end
		end
	end
end

-- Every item button showing now, in the bags and the bank: { button, bag, slot }.
function BagMark.shownButtons()
	local out = {}
	for _, f in ipairs(bagFrames()) do
		if f.frame:IsShown() then
			addFrameButtons(out, f)
		end
	end
	addBank(out)
	return out
end

-- For /gf bags, each bag frame: { name, shown, how, count, err }. One frame failing is reported, not raised.
function BagMark.frameReport()
	local out = {}
	for _, f in ipairs(bagFrames()) do
		local r = { name = f.name or "ContainerFrameCombinedBags" }
		out[#out + 1] = r
		local ok, err = pcall(function()
			r.how = f.frame.EnumerateValidItems and "EnumerateValidItems" or f.name and "named buttons" or "no button list"
			r.shown = f.frame:IsShown() and true or false
			if r.shown then
				local buttons = {}
				addFrameButtons(buttons, f)
				r.count = #buttons
			end
		end)
		r.err = not ok and tostring(err) or nil
	end
	return out
end

-- The shown item button of bag:slot, or nil.
local function buttonOf(bag, slot)
	for _, s in ipairs(BagMark.shownButtons()) do
		if s.bag == bag and s.slot == slot then
			return s.button
		end
	end
end

-- Whether the copper coin is on this button: its corner is the coin's, and a bag verdict gives way.
function BagMark.isMarked(button)
	return marked ~= nil and marked.button == button
end

function BagMark.coinShowing()
	return marked ~= nil
end

local function coin(button)
	if not marks[button] then
		local t = button:CreateTexture(nil, "OVERLAY", nil, 7)
		t:SetTexture(ICON)
		t:SetSize(ICON_SIZE, ICON_SIZE)
		t:SetPoint("TOPLEFT", 2, -2)
		marks[button] = t
	end
	return marks[button]
end

local refresh, soon
local function hookFrames()
	local frames = bagFrames()
	frames[#frames + 1] = BankFrame and { frame = BankFrame }
	for _, f in ipairs(frames) do
		if not hooked[f.frame] then
			hooked[f.frame] = true
			f.frame:HookScript("OnShow", soon)
		end
	end
end

local function mark()
	hookFrames()
	if marked then
		marks[marked.button]:Hide()
		marked = nil
	end
	if ns.settings("prices").bagMark == false then
		return
	end
	local stacks = fullBags()
	if not stacks then
		return
	end
	local s, total = BagMark.pick(stacks, ns.price.worth)
	local button = s and buttonOf(s.bag, s.slot)
	if button then
		coin(button):Show()
		marked = { button = button, id = s.id, total = total }
	end
end

function refresh()
	mark()
	ns.emit("bagMarkDrawn") -- the bag verdicts follow, so the coin keeps its corner
end

local waiting
function soon()
	if waiting then
		return
	end
	waiting = true
	C_Timer.After(0, function()
		waiting = false
		ns.safely("bag mark", refresh)
	end)
end
BagMark.refresh = soon

ns.on("BAG_UPDATE_DELAYED", "bag mark", soon)
ns.listen("pricesReady", "bag mark", soon)
if hooksecurefunc and ContainerFrame_Update then
	hooksecurefunc("ContainerFrame_Update", soon) -- a classic frame is given another bag as bags open
end

-- The marked slot's tooltip: one line with what the stack is worth in all.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local function markTooltip(tooltip, data)
		if tooltip ~= GameTooltip or not marked or not data or data.id ~= marked.id or tooltip:GetOwner() ~= marked.button
			or not ns.tipLine("bagMark") then
			return
		end
		tooltip:AddLine(ns.tipPrefix(tooltip) .. string.format(L["Cheapest in your bags: %s"], ns.price.coins(marked.total)), 1, 1, 1)
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("bag mark tooltip", markTooltip, tooltip, data)
	end)
end
