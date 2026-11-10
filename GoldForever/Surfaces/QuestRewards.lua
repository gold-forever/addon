-- Gold Forever: at a quest's reward choice, the reward worth the most to sell carries a gold coin in its
-- button's corner, and its tooltip a line "Best to sell: 1g 20s" (addon#95). A reward's value is one unit's
-- worth (Pricing.lua: the better of the auction price after the cut and the vendor's) times its count.
-- Unpriced rewards are not marked; the line counts them. Nothing is recorded.

local _, ns = ...
local L = ns.L
local QuestRewards = {}
ns.QuestRewards = QuestRewards

local COIN = "Interface\\MoneyFrame\\UI-GoldIcon"
local COIN_SIZE = 14

-- The n rewards' values in order (nil: unpriced) → { marked = { [i] = true }, value, unpriced }. Each reward
-- worth the most is marked, a tie as well; one reward is no choice, and one worth nothing is not marked.
function QuestRewards.best(values, n)
	local pick = { marked = {}, unpriced = 0 }
	for i = 1, n do
		local v = values[i]
		if not v then
			pick.unpriced = pick.unpriced + 1
		elseif v > 0 and (not pick.value or v > pick.value) then
			pick.value, pick.marked = v, { [i] = true }
		elseif v > 0 and v == pick.value then
			pick.marked[i] = true
		end
	end
	if n < 2 then
		pick.marked, pick.value = {}, nil
	end
	return pick
end

function QuestRewards.value(id, count)
	local worth = id and ns.price.worth(id)
	return worth and worth * (tonumber(count) or 1) or nil
end

function QuestRewards.line(pick)
	local text = string.format(L["Best to sell: %s"], ns.Money.auction(pick.value))
	if pick.unpriced > 0 then
		return text .. ns.plural(pick.unpriced, L[" (%d reward unpriced)"], L[" (%d rewards unpriced)"])
	end
	return text
end

-- The quest frame ------------------------------------------------------------------------------------------

local marks = {} -- button -> its coin texture
local shownLine -- the tooltip line of the rewards marked now

local function choiceButton(i)
	local frame = QuestInfoRewardsFrame
	for _, b in ipairs(frame and frame.RewardButtons or {}) do
		if b.type == "choice" and b.GetID and b:GetID() == i then
			return b
		end
	end
	return _G["QuestInfoRewardsFrameQuestInfoItem" .. i]
end

local function marked(button)
	return shownLine and button and marks[button] and marks[button]:IsShown() and ns.tipLine("bestReward")
end

-- The line is added as the reward's tooltip is drawn, so a redraw (Shift, Tooltips.lua) keeps it; on a
-- client whose quest tooltip is not drawn from tooltip data, the button's OnEnter adds it instead.
local drawn -- the button whose tooltip the post call gave the line
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	local function rewardTooltip(tooltip)
		local owner = tooltip == GameTooltip and tooltip.GetOwner and tooltip:GetOwner()
		if marked(owner) then
			tooltip:AddLine(ns.tipPrefix(tooltip) .. shownLine, 1, 0.82, 0)
			drawn = owner
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip)
		ns.safely("quest reward tooltip", rewardTooltip, tooltip)
	end)
end

local function onEnter(button)
	if drawn == button then
		drawn = nil
		return
	end
	if marked(button) and GameTooltip then
		GameTooltip:AddLine(ns.tipPrefix(GameTooltip) .. shownLine, 1, 0.82, 0)
		GameTooltip:Show()
	end
end

local function coin(button)
	local mark = marks[button]
	if not mark then
		local name = button.GetName and button:GetName()
		local icon = button.Icon or (type(name) == "string" and _G[name .. "IconTexture"]) or button
		mark = button:CreateTexture(nil, "OVERLAY")
		mark:SetTexture(COIN)
		mark:SetSize(COIN_SIZE, COIN_SIZE)
		mark:SetPoint("TOPLEFT", icon, "TOPLEFT", -4, 4)
		marks[button] = mark
		button:HookScript("OnEnter", onEnter)
	end
	return mark
end

local function clear()
	shownLine = nil
	for _, mark in pairs(marks) do
		mark:Hide()
	end
end

local function rewardValue(i)
	local _, _, count, _, _, id = GetQuestItemInfo("choice", i)
	return QuestRewards.value(id or ns.Encode.itemId(ns.Encode.itemKey(GetQuestItemLink("choice", i))), count)
end

local function mark()
	clear()
	if ns.settings("prices").bestReward == false or not GetNumQuestChoices then
		return
	end
	local values = {}
	local n = GetNumQuestChoices()
	for i = 1, n do
		values[i] = rewardValue(i)
	end
	local pick = QuestRewards.best(values, n)
	if not pick.value then
		return
	end
	shownLine = QuestRewards.line(pick)
	for i in pairs(pick.marked) do
		local button = choiceButton(i)
		if button then
			coin(button):Show()
		end
	end
end

-- The client fills the reward buttons on the same event: marked once it has.
ns.on("QUEST_COMPLETE", "quest rewards", function()
	C_Timer.After(0, function()
		ns.safely("quest rewards", mark)
	end)
end)
for _, event in ipairs({ "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_GREETING", "QUEST_FINISHED" }) do
	ns.on(event, "quest rewards", clear)
end
