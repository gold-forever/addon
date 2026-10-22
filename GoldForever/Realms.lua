-- Gold Forever: which realm a market belongs to. Retail trades gear per connected realm and
-- commodities per region (design 002, retail markets), so on retail a market's realm part is the
-- connected group's key: the alphabetically first normalized realm name of the group, the same from
-- every realm in it. WoW: Forever keeps the realm's own name.

local _, ns = ...

local Realms = {}
ns.Realms = Realms

-- Retail's interface numbers start at 110000; WoW: Forever's are 16xxx.
function Realms.isRetail(interface)
	return (interface or 0) >= 110000
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

function Realms.marketRealm(interface, realm, normalized, connected)
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
