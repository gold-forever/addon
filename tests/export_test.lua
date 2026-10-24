-- Export.lua: the in-game export string of design 005 (GF1: base64 of deflated Lua table text).

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Export.lua"], "@Export.lua"))("GoldForever", ns)
local X = ns.Export

-- The Lua text the site's parser reads, keys in a stable order so the same data gives the same text.
eq(X.serialize({ b = 2, a = "x\"y\n", [3] = true, [1] = 1.5 }), '{[1]=1.5,[3]=true,["a"]="x\\"y\\n",["b"]=2}', "a table, sorted keys")
eq(X.serialize({ list = { "a", "b" } }), '{["list"]={[1]="a",[2]="b"}}', "nested arrays")
eq(X.serialize({ n = -12 }), '{["n"]=-12}', "a negative integer")

-- What goes in: every character, the event days from the last export's day on, and the scans
-- newer than it. Older days and scans were in the last export.
local day = function(t) return ns.Encode.day(t) end
local db = {
	schema = 1, addon = "0.12.0", fields = { loot = "t" }, client = { build = "1.60" },
	characters = { c1 = { name = "Testchar" } },
	events = { [day(1000000)] = { loot = { "a" } }, [day(1000000 + 3 * 86400)] = { loot = { "b" } } },
	scans = { { t = 1000000 + 100, market = "m" }, { t = 1000000 + 3 * 86400, market = "m" } },
	guildBanks = {}, catalogue = { items = { [2589] = "Linen" } },
	settings = { share = false }, errors = { boom = "x" },
}
db.catalogue.items[2592] = "Wool"
db.exportSent = { items = { [2589] = true } }
local picked = X.select(db, 1000000 + 86400, 1000000 + 4 * 86400)
eq(picked.catalogue.items[2589], nil, "a catalogue entry sent before stays out")
eq(picked.catalogue.items[2592], "Wool", "a new catalogue entry goes in")
X.markSent(db, picked)
eq(db.exportSent.items[2592], true, "and is remembered as sent")
eq(X.select(db, nil, 1).catalogue.items[2589], "Linen", "the first export, or export all, holds the whole catalogue")
eq(picked.characters.c1.name, "Testchar", "characters, always")
eq(picked.events[day(1000000)], nil, "an event day before the last export's")
eq(picked.events[day(1000000 + 3 * 86400)].loot[1], "b", "an event day after it")
eq(#picked.scans, 1, "only the newer scan")
eq(picked.export.since, 1000000 + 86400, "says what it is new since")
eq(picked.errors, nil, "the addon's own errors stay in the game")
eq(picked.settings, nil, "and its settings")
eq(X.select(db, nil, 1).events[day(1000000)].loot[1], "a", "the first export holds every day")
db.scans = {
	{ t = 10, market = "a", kind = "full" }, { t = 30, market = "a", kind = "full" },
	{ t = 20, market = "b", kind = "full" }, { t = 40, market = "a", kind = "throttled" },
}
local firstScans = X.select(db, nil, 50).scans
eq(#firstScans, 2, "the first export holds each market's newest full scan")
eq(firstScans[1].t + firstScans[2].t, 50, "those are a's at 30 and b's at 20")

-- Standard base64, which the site decodes with the JDK.
eq(X.base64(""), "", "empty")
eq(X.base64("f"), "Zg==", "one byte")
eq(X.base64("fo"), "Zm8=", "two bytes")
eq(X.base64("foo"), "Zm9v", "three bytes")
eq(X.base64("\0\255\128"), "AP+A", "binary")

return checks()
