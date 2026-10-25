-- Scans.lua: a market's realm group, and the newest full scan of a market that prices are read from.

local ns = {}
assert(load(SOURCES["Scans.lua"], "@Scans.lua"))("GoldForever", ns)
local S = ns.Scans

eq(S.marketGroup("EU-Aszune-neutral"), "EU-Aszune", "the side goes")
eq(S.marketGroup("EU-Area 52-horde"), "EU-Area 52", "a realm with a space")
eq(S.marketGroup("US-Azjol-Nerub-alliance"), "US-Azjol-Nerub", "a realm with a dash keeps it")
eq(S.marketGroup("nodash"), "nodash", "no side: as it is")
eq(S.marketGroup(nil), nil, "no market")

local scans = {
	{ kind = "full", market = "EU-Aszune-alliance", t = 100 },
	{ kind = "full", market = "EU-Aszune-alliance", t = 300 },
	{ kind = "item", market = "EU-Aszune-alliance", t = 900 },
	{ kind = "full", market = "EU-Aszune-neutral", t = 500 },
	{ kind = "full", market = "EU-Other-alliance", t = 700 },
}
eq(S.latestFull(scans, "EU-Aszune-alliance").t, 300, "the newest full scan of the market, not a single item's")
eq(S.latestFull(scans, "EU-Aszune-alliance", false).t, 300, "on Forever the side is its own market")
eq(S.latestFull(scans, "EU-Aszune-alliance", true).t, 500, "on retail any side's scan of the group")
eq(S.latestFull(scans, "EU-Aszune-horde", true).t, 500, "a side with no scan of its own reads the group's")
eq(S.latestFull(scans, "EU-Aszune-horde"), nil, "on Forever, nothing for it")
eq(S.latestFull({}, "EU-Aszune-alliance", true), nil, "no scans")
eq(S.latestFull({ { kind = "full", market = "EU-Aszune-alliance", t = 5 }, { kind = "full", market = "EU-Aszune-alliance", t = 5 } }, "EU-Aszune-alliance").t, 5, "two at once: one of them")

return checks()
