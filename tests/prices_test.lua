-- Prices.lua: the pool's prices the companion writes (GoldForever_Data, contract T01) become one
-- tooltip line for the player's market; anything absent or malformed gives no line and no error.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Money.lua"], "@Money.lua"))("GoldForever", ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
ns.commands = {}
ns.on = function() end
-- The real money formatter (ns.price.coins): without the client's coin icons, plain text.
assert(load(SOURCES["Pricing.lua"], "@Pricing.lua"))("GoldForever", ns)
assert(load(SOURCES["DataFormat.lua"], "@DataFormat.lua"))("GoldForever", ns)
assert(load(SOURCES["Prices.lua"], "@Prices.lua"))("GoldForever", ns)
local P = ns.Prices

local MARKET = "EU-Classic Beta PvE 2-alliance"
local NOW = 1761148800
local function data(entry, market)
	return { v = 1, at = NOW, markets = { [market or MARKET] = { [2589] = entry } } }
end
local good = { 1234, 1100, 3, NOW - 3 * 3600 }

eq(P.line(data(good), { MARKET }, 2589, NOW), "Market 12s 34c · min 11s 0c", "the item's line")
eq(P.line(data({ 1234, 1100, 1, NOW }), { MARKET }, 2589, NOW), "Market 12s 34c · min 11s 0c", "one player")

eq(P.line(data({ 1234, 1100, 2.5, NOW }), { MARKET }, 2589, NOW), "Market 12s 34c · min 11s 0c", "a fractional count is not an error")

-- The typical price (the median of the item's daily values over the 7 days before, a fifth field) and the
-- value against it, beside the value; nothing extra without it.
eq(P.line(data({ 1234, 1100, 1, NOW, 1100 }), { MARKET }, 2589, NOW), "Market 12s 34c · typical 11s 0c (+12%) · min 11s 0c", "up on the typical price")
eq(P.line(data({ 1000, 900, 1, NOW, 1250 }), { MARKET }, 2589, NOW), "Market 10s 0c · typical 12s 50c (-20%) · min 9s 0c", "down on it")
eq(P.line(data({ 1000, 900, 1, NOW, 1004 }), { MARKET }, 2589, NOW), "Market 10s 0c · typical 10s 4c (steady) · min 9s 0c", "within 1%")
eq(P.line(data({ 1000, 900, 1, NOW, "x" }), { MARKET }, 2589, NOW), "Market 10s 0c · min 9s 0c", "an unusable typical price shows nothing extra")
eq(P.line(data({ 1000, 900, 1, NOW, 1250 }, MARKET), { MARKET }, 2589, NOW, "Neutral AH"), "Neutral AH 10s 0c · typical 12s 50c (-20%) · min 9s 0c", "the neutral AH's line too")
-- The Sell tab's trend, named as the site names the price.
eq(P.trendText(8), " · +8% vs typical", "the Sell tab's trend")
eq(P.trendText(0), " · steady vs typical", "steady")
eq(P.trendText(nil), "", "no trend")
-- The own scan wins when it is newer and the pool is more than twice or under half of it.
eq(table.concat({ P.pick(480000, 100, 9900, 200) }, " "), "9900 scan", "the pool far over a newer own scan")
eq(table.concat({ P.pick(480000, 300, 9900, 200) }, " "), "480000 pool", "an older own scan does not")
eq(table.concat({ P.pick(12000, 100, 9900, 200) }, " "), "12000 pool", "within twice: the pool")
eq(table.concat({ P.pick(1000, 100, 9900, 200) }, " "), "9900 scan", "far under it too")
eq(table.concat({ P.pick(1000, 100, nil, nil) }, " "), "1000 pool", "no own scan")
-- Sell measures against the typical price where there is one.
eq(table.concat({ P.sellBase(128300, "pool", 90000) }, " "), "90000 typical price", "the typical price")
eq(table.concat({ P.sellBase(128300, "pool", nil) }, " "), "128300 pool", "else the value")
eq(P.line(data({ 1000, 900, 1, NOW, 0 }), { MARKET }, 2589, NOW), "Market 10s 0c · min 9s 0c", "nor a zero one")
eq(P.trend(nil, 1000), nil, "no value, no trend")

-- Absent: no table, no market, no item.
eq(P.line(nil, { MARKET }, 2589, NOW), nil, "no data table")
eq(P.line(data(good, "EU-Other-alliance"), { MARKET }, 2589, NOW), nil, "another market only")
eq(P.line(data(good), { MARKET }, 2590, NOW), nil, "an item the pool has no price for")
eq(P.line(data(good), nil, 2589, NOW), nil, "no market known")

-- Malformed: every level type-checked.
eq(P.line("GoldForever_Prices", { MARKET }, 2589, NOW), nil, "the global is not a table")
eq(P.line(5, { MARKET }, 2589, NOW), nil, "the global a number")
eq(P.line({ v = 2, markets = { [MARKET] = { [2589] = good } } }, { MARKET }, 2589, NOW), nil, "a version this addon does not read")
eq(P.line({ v = 1, markets = "x" }, { MARKET }, 2589, NOW), nil, "markets not a table")
eq(P.line({ v = 1, markets = { [MARKET] = 7 } }, { MARKET }, 2589, NOW), nil, "a market not a table")
eq(P.line(data("1234,1100"), { MARKET }, 2589, NOW), nil, "an entry not a table")
eq(P.line(data(1234), { MARKET }, 2589, NOW), nil, "an entry a number")
eq(P.line(data({ "1234", 1100, 3, NOW }), { MARKET }, 2589, NOW), nil, "value a string")
eq(P.line(data({ 1234, nil, 3, NOW }), { MARKET }, 2589, NOW), nil, "no minimum buyout")
eq(P.line(data({ 1234, 1100, true, NOW }), { MARKET }, 2589, NOW), nil, "players not a number")
eq(P.line(data({ 1234, 1100, 3, {} }), { MARKET }, 2589, NOW), nil, "scan time not a number")
eq(P.line(data({ 0 / 0, 1100, 3, NOW }), { MARKET }, 2589, NOW), nil, "value NaN")
eq(P.line(data({ math.huge, 1100, 3, NOW }), { MARKET }, 2589, NOW), nil, "value infinite")
eq(P.line(data({ 1e15, 1100, 3, NOW }), { MARKET }, 2589, NOW), nil, "a value above a million gold")
eq(P.line(data({ 1234, 1e11, 3, NOW }), { MARKET }, 2589, NOW), nil, "a min above a million gold")
eq(P.line(data({ ns.Encode.MAX_COPPER, 1100, 3, NOW }), { MARKET }, 2589, NOW) ~= nil, true, "a million gold itself is a price")
eq(P.line(data({ -5, 1100, 3, NOW }), { MARKET }, 2589, NOW), nil, "a negative value")

-- The server's market key (backend Markets.kt key() for Forever) from the addon's own market string.
local FOREVER, RETAIL = 16001, 120105
eq(P.poolMarket("110-Classic Beta PvE 2-alliance", FOREVER), "forever-BETA-normal-alliance", "beta's region, PvE is not pvp")
eq(P.poolMarket("US-Some PvE Realm-horde", FOREVER), "forever-NA-normal-horde", "US is NA")
eq(P.poolMarket("na-Some PvE Realm-horde", FOREVER), "forever-NA-normal-horde", "na upper-cased")
eq(P.poolMarket("eu-Some PvE Realm-horde", FOREVER), "forever-EU-normal-horde", "eu upper-cased")
eq(P.poolMarket("KR-Normal-horde", FOREVER), "forever-KR-normal-horde", "KR stays")
eq(P.poolMarket("TW-Normal-horde", FOREVER), "forever-TW-normal-horde", "TW stays")
eq(P.poolMarket("CN-Normal-horde", FOREVER), "forever-CN-normal-horde", "CN stays")
eq(P.poolMarket("?-Some PvE Realm-horde", FOREVER), "forever-UNKNOWN-normal-horde", "an unknown region is never the beta")
eq(P.poolMarket("3-Forever PvP-horde", FOREVER), "forever-EU-pvp-horde", "a region id")
eq(P.poolMarket("41-Azeroth-alliance", FOREVER, "EU"), "forever-EU-azeroth-alliance", "an unknown id, the portal says EU")
eq(P.poolMarket("41-Azeroth-alliance", FOREVER), "forever-X41-azeroth-alliance", "an unknown id with no portal")
eq(P.poolMarket("110-Classic Beta PvE 2-horde", FOREVER, "EU"), "forever-BETA-normal-horde", "110 is the beta over a live portal")
eq(P.poolMarket("EU-Grim PvP-Realm-horde", FOREVER), "forever-EU-pvp-horde", "a realm with '-' and the word PvP")
eq(P.poolMarket("EU-grim pvp-alliance", FOREVER), "forever-EU-pvp-alliance", "pvp in any case")
eq(P.poolMarket("EU-PvPland-alliance", FOREVER), "forever-EU-pvpland-alliance", "PvP only as a word: else the name is the market")
eq(P.poolMarket("EU-Argent RP-alliance", FOREVER), "forever-EU-rp-alliance", "the word RP")
eq(P.poolMarket("EU-Argent rp-alliance", FOREVER), "forever-EU-rp-alliance", "RP in any case")
eq(P.poolMarket("EU-RP PvP-alliance", FOREVER), "forever-EU-rppvp-alliance", "RP and PvP: RP-PvP")
eq(P.poolMarket("EU-Some PvE Realm-neutral", FOREVER), "forever-EU-normal-neutral", "the side kept")
-- Backend Markets (LaunchMarketsTest), the same cases.
eq(P.region("EU"), "EU", "EU")
eq(P.region("US"), "NA", "US")
eq(P.region("110"), "BETA", "the beta")
eq(P.region("110", "test"), "BETA", "the beta's portal")
eq(P.region("1"), "NA", "id 1")
eq(P.region("3"), "EU", "id 3")
eq(P.region("41", "EU"), "EU", "the portal")
eq(P.region("", "US"), "NA", "empty, portal US")
eq(P.region(nil, "us"), "NA", "no region, portal us")
eq(P.region("41"), "X41", "an unknown id")
eq(P.region("41", "test-2"), "X41", "an unknown portal")
eq(P.region("?"), "UNKNOWN", "a question mark")
eq(P.region(nil), "UNKNOWN", "nothing")
eq(P.ruleset("Classic Beta PvE 2"), "normal", "the beta's realm")
eq(P.ruleset("Forever Normal"), "normal", "Normal")
eq(P.ruleset("PvE"), "normal", "PvE")
eq(P.ruleset("Forever PvP"), "pvp", "PvP")
eq(P.ruleset("Argent Dawn RP"), "rp", "RP")
eq(P.ruleset("Forever Roleplay"), "rp", "Roleplay")
eq(P.ruleset("Role Play"), "rp", "Role Play")
eq(P.ruleset("Forever RP-PvP"), "rppvp", "RP-PvP")
eq(P.ruleset("RPPvP"), "rppvp", "RPPvP")
eq(P.ruleset("Forever RP PvP"), "rppvp", "RP PvP")
eq(P.ruleset("Forever Hardcore"), "hardcore", "Hardcore")
eq(P.ruleset(nil), "normal", "no realm")
eq(P.ruleset("Azeroth"), "azeroth", "a name of its own")
eq(P.ruleset("Shen'dralas"), "shendralas", "letters and digits only")
eq(P.ruleset("The Forever Mega-Realm of Europe and Beyond"), "theforevermegarealmofeuropeandbe", "at most 32")
-- Names beyond ASCII, read byte by byte: bytes from 0x80 as hex, so every key stays ASCII.
eq(P.ruleset("Гордунни"), "d093d0bed180d0b4d183d0bdd0bdd0b8", "Cyrillic as its bytes in hex")
eq(P.ruleset("Shen’dralas"), "shene28099dralas", "the typographic apostrophe stays in the word")
eq(P.ruleset("Éclat"), "c389clat", "an accented capital as its bytes")
eq(P.ruleset("Éclat RP-PvP"), "rppvp", "an accented RP-PvP realm")
eq(#P.ruleset("Пиратская Бухта Свежевателя Душ"), 32, "a long Cyrillic name cut to 32 characters")
-- The server's own table (backend LaunchMarketsTest.REALM_KEYS, docs/launch-runbook.md), pinned as is.
local REALM_KEYS = {
	{ "Гордунни", "d093d0bed180d0b4d183d0bdd0bdd0b8" },
	{ "Les Sentinelles", "lessentinelles" },
	{ "Zirkel des Cenarius", "zirkeldescenarius" },
	{ "Die Aldor", "diealdor" },
	{ "Shen’dralas", "shene28099dralas" },
	{ "Shen'dralas", "shendralas" },
	{ "Éclat", "c389clat" },
	{ "Ревущий фьорд Азерота", "d0a0d0b5d0b2d183d189d0b8d0b9d184" },
	{ "Confrérie du Thorium RP-PvP", "rppvp" },
	{ "Kul Tiras RP-PvP", "rppvp" },
	{ "Forever PvP", "pvp" },
	{ "Azeroth", "azeroth" },
	{ "", "unknown" },
	{ "’ – ’", "e28099e28093e28099" },
}
for _, k in ipairs(REALM_KEYS) do
	eq(P.ruleset(k[1]), k[2], "server table: " .. k[1])
end
eq(P.poolMarket("EU-Some Realm-alliance", RETAIL), nil, "poolMarket is Forever's key only")
eq(P.poolMarket("EU-Some Realm-alliance", nil), nil, "no interface known")
eq(P.poolMarket("EU-Some Realm-alliance", 15999), nil, "below Forever's range")
eq(P.poolMarket("EU-Some Realm-alliance", 17000), nil, "above Forever's range")
eq(P.poolMarket("EU-alliance", FOREVER), nil, "no realm")
eq(P.poolMarket("-Some Realm-alliance", FOREVER), nil, "an empty region")
eq(P.poolMarket("EU--alliance", FOREVER), nil, "an empty realm")
eq(P.poolMarket("EU-Some Realm-", FOREVER), nil, "an empty side")
eq(P.poolMarket(nil, FOREVER), nil, "no market")
eq(P.poolMarket(42, FOREVER), nil, "a market not a string")

-- One file holding both factions and two regions (contract T05): each character's key reads its own.
local several = { v = 1, at = NOW, markets = {
	["forever-EU-normal-alliance"] = { [2589] = { 100, 90, 2, NOW } },
	["forever-EU-normal-horde"] = { [2589] = { 200, 190, 4, NOW } },
	["forever-NA-pvp-horde"] = { [2589] = { 300, 290, 6, NOW } },
} }
local function mine(market) return P.line(several, P.markets(market, FOREVER), 2589, NOW) end
eq(mine("EU-Some PvE Realm-horde"), "Market 2s 0c · min 1s 90c", "Horde in EU")
eq(mine("EU-Some PvE Realm-alliance"), "Market 1s 0c · min 90c", "Alliance in EU")
eq(mine("US-Grim PvP-horde"), "Market 3s 0c · min 2s 90c", "Horde on an NA PvP realm")
eq(mine("US-Grim PvP-alliance"), nil, "Alliance in NA: not in the file")

-- The server's keys to read, in order: Forever its one market, retail the realm group's then the region's
-- commodities (contract T05; backend Markets.retail).
local function keys(market, interface) return table.concat(P.markets(market, interface) or {}, " ") end
eq(keys("EU-Some PvE Realm-horde", FOREVER), "forever-EU-normal-horde", "Forever: its one market")
eq(keys("EU-ArgentDawn-horde", RETAIL), "retail-EU-ArgentDawn retail-EU", "retail: the group, then the commodities")
eq(keys("US-Area52-alliance", RETAIL), "retail-NA-Area52 retail-NA", "retail: US is NA")
eq(keys("na-Area52-alliance", RETAIL), "retail-NA-Area52 retail-NA", "retail: na upper-cased")
eq(keys("KR-Azshara-horde", RETAIL), "retail-KR-Azshara retail-KR", "retail: KR stays")
eq(keys("TW-Realm-horde", RETAIL), "retail-TW-Realm retail-TW", "retail: TW stays")
eq(keys("CN-Realm-horde", RETAIL), "retail-CN-Realm retail-CN", "retail: CN stays")
eq(keys("110-Realm-horde", RETAIL), "retail-BETA-Realm retail-BETA", "retail: the beta's 110 is the beta")
eq(keys("EU-Argent Dawn-neutral", RETAIL), "retail-EU-ArgentDawn retail-EU", "retail: spaces removed (a pre-0.14 realm name)")
eq(keys("EU-Azjol-Nerub-horde", RETAIL), "retail-EU-AzjolNerub retail-EU", "retail: dashes removed")
eq(keys("EU-Mr. Realm-horde", RETAIL), "retail-EU-MrRealm retail-EU", "retail: dots removed")
eq(keys("EU-Kel'Thuzad-horde", RETAIL), "retail-EU-Kel'Thuzad retail-EU", "retail: apostrophes kept")
eq(keys("EU-Realm-Horde", RETAIL), "retail-EU-Realm retail-EU", "retail: the side in any case")
eq(keys("EU--horde", RETAIL), "retail-EU- retail-EU", "retail: an empty realm, as the server")
eq(keys("EU-Realm-?", RETAIL), "", "retail: not a side")
eq(keys("EU-horde", RETAIL), "", "retail: no realm part")
eq(keys("-Realm-horde", RETAIL), "", "retail: no region")
eq(keys(nil, RETAIL), "", "retail: no market")
eq(keys("EU-Realm-horde", nil), "", "no interface known")
eq(keys("EU-Realm-horde", 15999), "", "neither Forever nor retail")

-- Retail reads the realm group's price first, then the region's commodity price.
local retail = { v = 1, at = NOW, markets = {
	["retail-EU-ArgentDawn"] = { [1] = { 100, 90, 2, NOW } },
	["retail-EU"] = { [1] = { 500, 490, 9, NOW }, [2] = { 200, 190, 4, NOW } },
	["retail-NA-Area52"] = { [2] = { 300, 290, 6, NOW } },
} }
local group = P.markets("EU-ArgentDawn-horde", RETAIL)
eq(P.line(retail, group, 1, NOW), "Market 1s 0c · min 90c", "the group's price before the commodity's")
eq(P.line(retail, group, 2, NOW), "Market 2s 0c · min 1s 90c", "the region's commodity price")
eq(P.line(retail, group, 3, NOW), nil, "neither has the item")
eq(P.line(retail, P.markets("EU-ArgentDawn-horde", FOREVER), 1, NOW), nil, "Forever never reads retail's markets")
retail.markets["retail-EU-ArgentDawn"][1] = { "x" }
eq(P.line(retail, group, 1, NOW), "Market 5s 0c · min 4s 90c", "a malformed group entry falls through to the commodity's")

-- Stale: a price scanned more than three days ago is greyed (the second value).
local DAY = 86400
local function stale(scannedAt) return select(2, P.line(data({ 1234, 1100, 3, scannedAt }), { MARKET }, 2589, NOW)) end
eq(stale(NOW - 3 * DAY), false, "three days old is not stale yet")
eq(stale(NOW - 3 * DAY - 1), true, "older than three days is stale")
eq(stale(NOW), false, "a fresh price")
eq(P.line(data({ 1234, 1100, 3, NOW - 4 * DAY }), { MARKET }, 2589, NOW), "Market 12s 34c · min 11s 0c · scanned 4d ago", "a stale line keeps its words")

-- The player's own scans when the file lacks the item, labelled as theirs.
eq(P.ownLine(1234, 1100, NOW - 2 * 3600, NOW), "Your scan 12s 34c · min 11s 0c", "the player's own scan")
eq(P.ownLine(1234, nil, NOW, NOW), "Your scan 12s 34c", "no cheapest known")
eq(select(2, P.ownLine(1234, 1100, NOW - 4 * DAY, NOW)), true, "an old own scan is stale too")
eq(select(2, P.ownLine(1234, 1100, NOW, NOW)), false, "a fresh own scan")
eq(P.ownLine(nil, 1100, NOW, NOW), nil, "no own price")
eq(P.ownLine(1234, 1100, nil, NOW), nil, "no scan time")

-- Whether a readable prices file is loaded: the own-scan fallback is only for an item the file lacks.
eq(P.loaded(data(good)), true, "a file is loaded")
eq(P.loaded(nil), false, "no file")
eq(P.loaded({ v = 2, markets = {} }), false, "a version this addon does not read")
eq(P.loaded({ v = 1, markets = "x" }), false, "markets not a table")

-- /gf prices: the file's markets, item counts and age, or that no file is loaded.
local function summary(d, mine) return table.concat(P.summary(d, mine, NOW), "\n") end
eq(summary(nil, nil), "no prices file loaded. The companion app writes it into the GoldForever_Data addon.", "no file")
eq(summary("x", nil), "no prices file loaded. The companion app writes it into the GoldForever_Data addon.", "not a table")
eq(summary({ v = 2, at = NOW }, nil), "the prices file is version 2; this addon reads version 1. Update the addon.", "another version")
eq(summary({ v = 1, at = NOW - 2 * 3600, markets = {
	["forever-EU-normal-horde"] = { [1] = good, [2] = good },
	["forever-EU-normal-alliance"] = { [1] = good },
	["forever-NA-normal-horde"] = 7,
} }, { "forever-EU-normal-horde" }), table.concat({
	"prices file written 2h ago · 3 markets",
	"forever-EU-normal-alliance: 1 item",
	"forever-EU-normal-horde: 2 items · this character's",
	"forever-NA-normal-horde: 0 items",
}, "\n"), "markets sorted, counted, this character's marked")
eq(summary({ v = 1, markets = "x" }, nil), "the prices file cannot be read. The companion app writes it again on its next update.", "markets not a table")
eq(summary({ v = 1, markets = {} }, nil), "prices file of unknown age · 0 markets", "no time, no markets")
eq(summary({ v = 1, at = NOW - 4 * DAY, markets = {} }, nil), "prices file written 4d ago · 0 markets", "an old file")

-- The Companion page: the file's state, its age and markets, this character's first, and what it lacks.
eq(P.status(nil, nil, NOW).state, "missing", "no file")
eq(P.status({ v = 2 }, nil, NOW).state, "version", "another version")
eq(P.status({ v = 1, markets = "x" }, nil, NOW).state, "broken", "markets not a table")
local st = P.status({ v = 1, at = NOW - 2 * 3600, markets = {
	["forever-EU-normal-alliance"] = { [1] = good },
	["forever-EU-normal-horde"] = { [1] = good, [2] = good },
} }, { "forever-EU-normal-horde", "forever-EU-normal-neutral" }, NOW)
eq(st.state, "ok", "a file read")
eq(st.age, "2h ago", "its age")
eq(st.markets[1].key, "forever-EU-normal-horde", "this character's market first")
eq(st.markets[1].items, 2, "its items")
eq(st.markets[1].mine, true, "marked")
eq(st.markets[2].mine, false, "another market")
eq(#st.missing, 1, "a market of this character's the file lacks")
eq(st.missing[1], "forever-EU-normal-neutral", "named")

-- A line's label: "Pool" unless named (the neutral auction house's line).
eq((P.line({ v = 1, at = NOW, markets = { m = { [5] = good } } }, { "m" }, 5, NOW, "Neutral AH") or ""):sub(1, 11), "Neutral AH ", "a named line")

-- The stale-file warning at login: over a day old, at most once a day; nothing without a file.
eq(P.staleWarning(nil, NOW, nil), nil, "no file, no warning")
eq(P.staleWarning({ at = NOW - 3600 }, NOW, nil), nil, "a fresh file")
eq(P.staleWarning({ at = NOW - 2 * DAY - 5 }, NOW, nil), "everyone's prices are 2 days old: is the companion app running? gold-forever.app/companion", "two days")
eq(P.staleWarning({ at = NOW - DAY - 5 }, NOW, nil):find("1 day old", 1, true) ~= nil, true, "one day")
eq(P.staleWarning({ at = NOW - 2 * DAY }, NOW, NOW - 3600), nil, "warned an hour ago")

-- The hub's Export button shows unless the companion is at work: its file loaded and under a day old.
eq(P.connected({ v = 1, at = NOW - 3600, markets = { m = { [1] = good } } }, NOW), true, "a fresh file: connected")
eq(P.connected({ v = 1, at = NOW - DAY - 5, markets = { m = { [1] = good } } }, NOW), false, "a day old: not running")
eq(P.connected({ v = 1, markets = { m = { [1] = good } } }, NOW), false, "no time: not known to run")
eq(P.connected(nil, NOW), false, "no file")
eq(P.connected({ v = 2, at = NOW }, NOW), false, "a file this addon cannot read")

-- A file this addon was not written for (DataFormat.lua): an older version shows no prices either, and
-- says so; a field the addon does not know, and an item figure past the fifth, are ignored.
eq(P.line({ v = 0, at = NOW, markets = { [MARKET] = { [2589] = good } } }, { MARKET }, 2589, NOW), nil, "an older version")
eq(summary({ v = 0, at = NOW }, nil), "the prices file is version 0; this addon reads version 1. Update the addon.", "an older version, said")
local known = data({ 1234, 1100, 3, NOW - 3 * 3600, 1100 })
local more = data({ 1234, 1100, 3, NOW - 3 * 3600, 1100, 99 })
more.future = { anything = true }
more.markets[MARKET].future = "x"
eq(P.line(more, { MARKET }, 2589, NOW), P.line(known, { MARKET }, 2589, NOW), "an unknown field and a sixth figure change nothing")
eq(P.status(more, { MARKET }, NOW).state, "ok", "and the file is read")
return checks()
