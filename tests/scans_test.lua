-- Scans.lua: a market's realm group, and the newest full scan of a market that prices are read from.

local ns = { module = function() end, commands = {} }
assert(load(SOURCES["Scans.lua"], "@Scans.lua"))("GoldForever", ns)
assert(load(SOURCES["Diagnostics.lua"], "@Diagnostics.lua"))("GoldForever", ns) -- the save's size, as /gf check reads it
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

-- The size guard (gf#404): the owner's save of 9.9 MiB with 11 scans, the rest of it 3 MiB, ends under 8 MiB.
local MIB = 1048576
local function scan(market, t, kib)
	local rows = {}
	for i = 1, kib do
		rows[i] = string.rep("1", 1024)
	end
	return { kind = "full", market = market, t = t, rows = rows }
end
local markets = { "EU-Aszune-alliance", "EU-Aszune-horde", "EU-Aszune-neutral" }
local db = { catalogue = { text = string.rep("x", 3 * MIB) }, scans = {} }
for i = 1, 11 do
	db.scans[i] = scan(markets[i % 3 + 1], 1000 + i * 100, 630)
end
db.scans[12] = { kind = "throttled", market = "EU-Aszune-horde", t = 50 }
eq(string.format("%.1f", ns.saveSize(db) / MIB), "9.9", "the owner's save")
local dropped = S.keepUnder(db, 8 * MIB)
eq(ns.saveSize(db) < 8 * MIB, true, "under 8 MiB after: " .. ns.saveSize(db) / MIB)
eq(dropped, 5, "the oldest scans go, the marker of t=50 first, until it is under")
local ts = {}
for i, s in ipairs(db.scans) do
	ts[i] = s.t
end
eq(table.concat(ts, ","), "1500,1600,1700,1800,1900,2000,2100", "the newest kept, in their order")
eq(S.keepUnder(db, 8 * MIB), 0, "a save under it: nothing dropped")

-- A market's older scans and markers go before any market's newest full scan.
local big = { scans = { scan("EU-A-horde", 300, 1024), scan("EU-A-horde", 200, 1024), scan("EU-B-horde", 100, 1024),
	{ kind = "throttled", market = "EU-B-horde", t = 900 } } }
eq(S.keepUnder(big, 2.5 * MIB), 1, "the older scan of a market goes first, though EU-B's is older")
eq(big.scans[1].t .. "," .. big.scans[2].t, "300,100", "the newest full scan of each market")
eq(S.keepUnder(big, 1.5 * MIB), 2, "then the marker, then the oldest market's newest")
eq(#big.scans == 1 and big.scans[1].t, 300, "the newest full scan of all")

-- The owner's save of 2026-11-15 (gf#404): 10.0 MiB, 11 scans in three Forever markets, full and cut
-- short (stored as throttled, marked partial), the rest of it 3 MiB.
local function owner()
	local plan = { { "EU-normal-horde", "full" }, { "EU-pvp-horde", "full" }, { "EU-normal-neutral", "full" },
		{ "EU-normal-horde", "partial" }, { "EU-normal-horde", "full" }, { "EU-pvp-horde", "partial" },
		{ "EU-normal-neutral", "full" }, { "EU-normal-horde", "full" }, { "EU-pvp-horde", "full" },
		{ "EU-normal-horde", "partial" }, { "EU-normal-horde", "full" } }
	local save = { catalogue = { text = string.rep("x", 3 * MIB) }, scans = {} }
	for i, p in ipairs(plan) do
		local s = scan(p[1], 1000 + i * 100, 640)
		s.kind, s.partial = p[2] == "full" and "full" or "throttled", p[2] == "partial" or nil
		save.scans[i] = s
	end
	return save
end
local own = owner()
eq(string.format("%.1f", ns.saveSize(own) / MIB), "10.0", "the owner's save")
eq(S.keepUnder(own, 8 * MIB), 4, "the four oldest go, cut short or not")
eq(ns.saveSize(own) < 8 * MIB, true, "under 8 MiB after: " .. ns.saveSize(own) / MIB)
eq(#own.scans, 7, "seven scans left")

-- The newest of each market alone over the budget: the oldest of them go too, the newest scan stays.
own = owner()
eq(S.keepUnder(own, 4 * MIB), 10, "all but one")
eq(#own.scans == 1 and own.scans[1].t, 2100, "the newest full scan stays, though the save is still over")
own = owner()
eq(S.keepUnder(own, 4.5 * MIB), 9, "down to two")
eq(own.scans[1].t .. "," .. own.scans[2].t, "1900,2100", "the newest of two markets: the oldest market's newest went")
local markers = { scans = { scan("EU-A-horde", 100, 1024), { kind = "throttled", market = "EU-A-horde", t = 900, rows = { string.rep("1", 1024) } } } }
eq(S.keepUnder(markers, 1), 1, "a newer marker is not the scan kept")
eq(markers.scans[1].t, 100, "the newest full scan is")

return checks()
