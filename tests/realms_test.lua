-- Realms.lua: on retail, gear trades per connected realm (design 002, retail markets), so a market's
-- realm part is the connected group's key: the alphabetically first normalized realm name of the group.

local ns = {}
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

return checks()
