-- Gold Forever: on a group loot roll, one small line under the item's name on Blizzard's roll frame
-- (GroupLootFrame1–4) with its auction and vendor value, "AH 1g 20s · vendor 15s", times how many drop, so
-- Greed is an informed choice (addon#97). The auction value is the market price (Pricing.lua), as the
-- tooltip's; an unknown price reads "?". It only shows: the roll stays the player's. Nothing is recorded.

local _, ns = ...
local RollValue = {}
ns.RollValue = RollValue

local FRAMES = 4 -- the client's roll frames, GroupLootFrame1–4
local UNKNOWN = "?"

local function money(copper)
	return copper and ns.Money.auction(copper) or UNKNOWN
end

-- The line for the auction and vendor values in copper (nil: unknown); nil when both are unknown.
function RollValue.line(auction, vendor)
	if not auction and not vendor then
		return nil
	end
	return "AH " .. money(auction) .. " · vendor " .. money(vendor)
end

function RollValue.text(id, count)
	if not id then
		return nil
	end
	local n = tonumber(count) or 1
	local market, vendor = ns.price.market(id), ns.price.vendor(id)
	return RollValue.line(market and market * n, vendor and vendor * n)
end

-- The roll frames --------------------------------------------------------------------------------------------

local lines = {} -- roll frame -> its value line

local function valueLine(frame)
	local fs = lines[frame]
	if not fs then
		local name = frame.Name or _G[frame:GetName() .. "Name"]
		fs = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
		fs:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -1)
		fs:SetTextColor(0.8, 0.8, 0.8)
		lines[frame] = fs
	end
	return fs
end

local function rollText(rollID)
	local _, _, count = GetLootRollItemInfo(rollID)
	local link = GetLootRollItemLink(rollID)
	return RollValue.text(ns.Encode.itemId(ns.Encode.itemKey(link)), count)
end

local function show()
	local on = ns.settings("prices").rollValue ~= false
	for i = 1, FRAMES do
		local frame = _G["GroupLootFrame" .. i]
		local text = frame and on and frame.rollID and rollText(frame.rollID)
		if text then
			local fs = valueLine(frame)
			fs:SetText(text)
			fs:Show()
		elseif frame and lines[frame] then
			lines[frame]:Hide()
		end
	end
end

-- The client fills the roll frame on the same event: the line is set once it has.
ns.on("START_LOOT_ROLL", "roll value", function()
	C_Timer.After(0, function()
		ns.safely("roll value", show)
	end)
end)
