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

-- A retail scan's row for one item ("item,class,subclass,stack"), so the server can tell a commodity
-- from gear before the catalogue has loaded it (half a scan's items, on the first real one). instant
-- is GetItemInfoInstant, client data that needs no server query; stack is GetItemMaxStackSizeByID,
-- written only when it answers. Either may be missing.
function Realms.itemRow(id, instant, stack)
	local class, subclass
	if instant then
		local _, _, _, _, _, c, s = instant(id)
		class, subclass = c, s
	end
	local size
	if stack then
		local ok, value = pcall(stack, id)
		size = ok and value or nil
	end
	return ns.Encode.row(id, class, subclass, size)
end

-- The client's item functions, for itemRow.
function Realms.itemApis()
	local instant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
	return instant, C_Item and C_Item.GetItemMaxStackSizeByID
end

-- Market of the auction house or guild bank the player is at: region, realm (until the ruleset
-- is known, checklist #8) and side. On retail the realm is the connected group's key (Realms.marketRealm).
function ns.market(side)
	local realm = Realms.marketRealm(ns.db().client.interface, ns.me() and ns.me().realm,
		GetNormalizedRealmName and GetNormalizedRealmName(), Realms.connected())
	return (ns.db().client.region or "?") .. "-" .. (realm or "?") .. "-" .. side
end
