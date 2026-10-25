-- Realms.lua: on retail, gear trades per connected realm (design 002, retail markets), so a market's
-- realm part is the connected group's key: the alphabetically first normalized realm name of the group.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
local R = ns.Realms

-- Retail is interface 110000 and up; WoW: Forever (16xxx) keeps its realm names.
eq(R.isRetail(120105), true, "retail 12.1.5")
eq(R.isRetail(110000), true, "retail's first 11.0 build")
eq(R.isRetail(16001), false, "WoW: Forever")
eq(R.isRetail(nil), false, "unknown")

-- The group's key is the same whichever realm of the group the player is on.
eq(R.connectedKey("Silvermoon", { "Silvermoon", "Ravencrest", "Kazzak" }), "Kazzak", "the first name")
eq(R.connectedKey("Kazzak", { "Ravencrest", "Silvermoon" }), "Kazzak", "the player's own realm counts")
eq(R.connectedKey("Ravencrest", {}), "Ravencrest", "a realm with no connections is its own group")
eq(R.connectedKey("Ravencrest", nil), "Ravencrest", "no list at all")
eq(R.connectedKey(nil, { "Silvermoon", "Kazzak" }), "Kazzak", "no own name, the list alone")
eq(R.connectedKey(nil, nil), nil, "nothing known")

-- The market's realm part: the connected key on retail, the realm's own name on WoW: Forever.
eq(R.marketRealm(120105, "Argent Dawn", "ArgentDawn", { "ArgentDawn", "AeriePeak" }), "AeriePeak", "retail: the group")
eq(R.marketRealm(16001, "Classic Beta PvE 2", "ClassicBetaPvE2", { "Other" }), "Classic Beta PvE 2", "Forever: unchanged")
eq(R.marketRealm(120105, "Argent Dawn", nil, nil), "Argent Dawn", "retail without the realm APIs: the name")

-- What a retail scan records per item, so the server can tell commodities (region-wide) from gear
-- (per connected realm) even for items the catalogue has not loaded yet: class and subclass are
-- client data (GetItemInfoInstant needs no server query), the stack size only when the client has it.
local instant = function(id)
	if id == 2589 then
		return 2589, "Tradeskill", "Cloth", "", 132889, 7, 5
	end
	if id == 19019 then
		return 19019, "Weapon", "Swords", "INVTYPE_WEAPONMAINHAND", 135349, 2, 7
	end
end
local stack = function(id)
	return id == 2589 and 1000 or nil
end
eq(R.itemRow(2589, instant, stack), "2589,7,5,1000", "a commodity: class, subclass and stack")
eq(R.itemRow(19019, instant, stack), "19019,2,7,", "gear with no stack known: the column stays empty")
eq(R.itemRow(424242, instant, stack), "424242,,,", "an item the client does not know")
eq(R.itemRow(2589, nil, nil), "2589,,,", "a client without the item APIs")
eq(R.itemRow(2589, instant, function()
	error("not loaded")
end), "2589,7,5,", "a stack call that fails is not fatal")

return checks()
