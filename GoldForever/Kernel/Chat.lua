-- Gold Forever: the addon's lines in chat, mid-screen and in tooltips.

local _, ns = ...

ns.PREFIX = "|cffe0ac45Gold Forever|r"

-- "Gold Forever: …" in the chat frame.
function ns.say(text)
	print(ns.PREFIX .. ": " .. text)
end

-- A chat line as plain text, for a box the player copies from: no colours, coin icons as g, s and c, no
-- other icons.
local COINS = { gold = "g", silver = "s", copper = "c" }
function ns.plainText(text)
	text = string.gsub(string.gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", "")
	return (string.gsub(text, "|[TA]([^|]*)|[ta]", function(icon)
		icon = string.lower(icon)
		return COINS[string.match(icon, "(%a+)icon") or string.match(icon, "coin%-(%a+)")] or ""
	end))
end

-- A message mid-screen with the raid-warning sound, and in chat: big drops, quest starters, rares.
function ns.alert(text)
	if RaidNotice_AddMessage and RaidWarningFrame then
		RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo and ChatTypeInfo["RAID_WARNING"] or { r = 1, g = 0.82, b = 0 })
	end
	if PlaySound and SOUNDKIT and SOUNDKIT.RAID_WARNING then
		PlaySound(SOUNDKIT.RAID_WARNING)
	end
	print(ns.PREFIX .. " " .. text)
end

-- "Gold Forever " on the first of the addon's lines in a tooltip, nothing on the rest (manual test run
-- 001: three lines each with the name were hard to read). The mark goes when the tooltip is cleared.
local prefixed = setmetatable({}, { __mode = "k" })
local clearedHook = setmetatable({}, { __mode = "k" })
function ns.tipPrefix(tooltip)
	if prefixed[tooltip] then
		return ""
	end
	prefixed[tooltip] = true
	if not clearedHook[tooltip] and tooltip.HookScript then
		clearedHook[tooltip] = true
		tooltip:HookScript("OnTooltipCleared", function(self)
			prefixed[self] = nil
		end)
	end
	return ns.PREFIX .. " "
end
