-- Gold Forever: which realm a market belongs to. Retail trades gear per connected realm and
-- commodities per region (design 002, retail markets), so on retail a market's realm part is the
-- connected group's key: the alphabetically first normalized realm name of the group, the same from
-- every realm in it. WoW: Forever keeps the realm's own name; where the client names none (hotfix
-- 1.60.1), the game mode: one auction house serves a region's game mode and side.

local _, ns = ...

local Realms = {}
ns.Realms = Realms

-- Retail's interface numbers start at 110000; WoW: Forever's are 16xxx.
function Realms.isRetail(interface)
	return (interface or 0) >= 110000
end

-- WoW: Forever's interface numbers.
function Realms.isForever(interface)
	return type(interface) == "number" and interface >= 16000 and interface <= 16999
end

-- own: this realm's normalized name; list: the names it is connected to (normalized), which may or
-- may not include it.
function Realms.connectedKey(own, list)
	local key = own
	for _, name in ipairs(list or {}) do
		if not key or name < key then
			key = name
		end
	end
	return key
end

-- Forever's game modes (C_GameRules.GetCurrentGameModeRecordID) as the market's realm part, in a word
-- Prices.ruleset reads. A new mode is one line here.
local FOREVER_MODES = {
	[14] = "PvP",
	[15] = "PvE",
	[16] = "RP",
	[18] = "RP PvP",
}

-- mode: the game mode's record ID, used on Forever when the realm has no name.
function Realms.marketRealm(interface, realm, normalized, connected, mode)
	if Realms.isForever(interface) and realm == "" then
		return FOREVER_MODES[mode] or realm
	end
	if not Realms.isRetail(interface) then
		return realm
	end
	return Realms.connectedKey(normalized, connected) or realm
end

-- The client's answers, read when a market is named: C_AutoComplete since 12.0.5, the global before.
function Realms.connected()
	if C_AutoComplete and C_AutoComplete.GetAutoCompleteRealms then
		return C_AutoComplete.GetAutoCompleteRealms()
	end
	return GetAutoCompleteRealms and GetAutoCompleteRealms() or nil
end

function Realms.gameMode()
	local rules = C_GameRules
	if not (rules and rules.GetCurrentGameModeRecordID) then
		return nil
	end
	local ok, mode = pcall(rules.GetCurrentGameModeRecordID)
	return ok and mode or nil
end
