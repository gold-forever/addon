-- Gold Forever: with no free bag slot, the stack worth least in the bags carries a small copper coin in its
-- slot's corner and one tooltip line, "Cheapest in your bags: 3c", so a farming player knows what to drop
-- (addon#96). Blizzard's own bag frames only; nothing is moved or deleted: that stays the player's.

local _, ns = ...

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

local function isQuest(bag, slot, id)
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
						bound = info.isBound, quest = isQuest(bag, slot, info.itemID) }
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

-- The shown item button of bag:slot, or nil.
local function buttonOf(bag, slot)
	for _, f in ipairs(bagFrames()) do
		local frame = f.frame
		if frame:IsShown() then
			local buttons = {}
			if frame.EnumerateValidItems then
				for _, b in frame:EnumerateValidItems() do
					buttons[#buttons + 1] = b
				end
			elseif f.name then
				for j = 1, frame.size or MAX_CONTAINER_ITEMS or 36 do
					buttons[#buttons + 1] = _G[f.name .. "Item" .. j]
				end
			end
			for _, b in ipairs(buttons) do
				local bagOf = b.GetBagID and b:GetBagID() or frame:GetID()
				if bagOf == bag and b:GetID() == slot then
					return b
				end
			end
		end
	end
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
	for _, f in ipairs(bagFrames()) do
		if not hooked[f.frame] then
			hooked[f.frame] = true
			f.frame:HookScript("OnShow", soon)
		end
	end
end

function refresh()
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
		if tooltip ~= GameTooltip or not marked or not data or data.id ~= marked.id or tooltip:GetOwner() ~= marked.button then
			return
		end
		tooltip:AddLine(ns.tipPrefix(tooltip) .. "Cheapest in your bags: " .. ns.price.coins(marked.total), 1, 1, 1)
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("bag mark tooltip", markTooltip, tooltip, data)
	end)
end
