-- Prices.lua: the pool's prices the companion writes (GoldForever_Data, contract T01) become one
-- tooltip line for the player's market; anything absent or malformed gives no line and no error.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
assert(load(SOURCES["Prices.lua"], "@Prices.lua"))("GoldForever", ns)
ns.price = { coins = ns.Encode.money }
local P = ns.Prices

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

local MARKET = "EU-Classic Beta PvE 2-alliance"
local NOW = 1761148800
local function data(entry, market)
	return { v = 1, at = NOW, markets = { [market or MARKET] = { [2589] = entry } } }
end
local good = { 1234, 1100, 3, NOW - 3 * 3600 }

eq(P.line(data(good), MARKET, 2589, NOW), "Pool: 12s 34c · min 11s 0c · 3 players · 3h ago", "the item's line")
eq(P.line(data({ 1234, 1100, 1, NOW }), MARKET, 2589, NOW), "Pool: 12s 34c · min 11s 0c · 1 player · now", "one player")

eq(P.line(data({ 1234, 1100, 2.5, NOW }), MARKET, 2589, NOW), "Pool: 12s 34c · min 11s 0c · 2 players · now", "a fractional count is not an error")

-- Absent: no table, no market, no item.
eq(P.line(nil, MARKET, 2589, NOW), nil, "no data table")
eq(P.line(data(good, "EU-Other-alliance"), MARKET, 2589, NOW), nil, "another market only")
eq(P.line(data(good), MARKET, 2590, NOW), nil, "an item the pool has no price for")
eq(P.line(data(good), nil, 2589, NOW), nil, "no market known")

-- Malformed: every level type-checked.
eq(P.line("GoldForever_Prices", MARKET, 2589, NOW), nil, "the global is not a table")
eq(P.line(5, MARKET, 2589, NOW), nil, "the global a number")
eq(P.line({ v = 2, markets = { [MARKET] = { [2589] = good } } }, MARKET, 2589, NOW), nil, "a version this addon does not read")
eq(P.line({ v = 1, markets = "x" }, MARKET, 2589, NOW), nil, "markets not a table")
eq(P.line({ v = 1, markets = { [MARKET] = 7 } }, MARKET, 2589, NOW), nil, "a market not a table")
eq(P.line(data("1234,1100"), MARKET, 2589, NOW), nil, "an entry not a table")
eq(P.line(data(1234), MARKET, 2589, NOW), nil, "an entry a number")
eq(P.line(data({ "1234", 1100, 3, NOW }), MARKET, 2589, NOW), nil, "value a string")
eq(P.line(data({ 1234, nil, 3, NOW }), MARKET, 2589, NOW), nil, "no minimum buyout")
eq(P.line(data({ 1234, 1100, true, NOW }), MARKET, 2589, NOW), nil, "players not a number")
eq(P.line(data({ 1234, 1100, 3, {} }), MARKET, 2589, NOW), nil, "scan time not a number")
eq(P.line(data({ 0 / 0, 1100, 3, NOW }), MARKET, 2589, NOW), nil, "value NaN")
eq(P.line(data({ math.huge, 1100, 3, NOW }), MARKET, 2589, NOW), nil, "value infinite")
eq(P.line(data({ -5, 1100, 3, NOW }), MARKET, 2589, NOW), nil, "a negative value")

-- The server's market key (backend Markets.kt key() for Forever) from the addon's own market string.
local FOREVER, RETAIL = 16001, 120105
eq(P.poolMarket("110-Classic Beta PvE 2-alliance", FOREVER), "forever-BETA-normal-alliance", "beta's region, PvE is not pvp")
eq(P.poolMarket("US-Some Realm-horde", FOREVER), "forever-NA-normal-horde", "US is NA")
eq(P.poolMarket("na-Some Realm-horde", FOREVER), "forever-NA-normal-horde", "na upper-cased")
eq(P.poolMarket("eu-Some Realm-horde", FOREVER), "forever-EU-normal-horde", "eu upper-cased")
eq(P.poolMarket("KR-Some Realm-horde", FOREVER), "forever-KR-normal-horde", "KR stays")
eq(P.poolMarket("TW-Some Realm-horde", FOREVER), "forever-TW-normal-horde", "TW stays")
eq(P.poolMarket("CN-Some Realm-horde", FOREVER), "forever-CN-normal-horde", "CN stays")
eq(P.poolMarket("?-Some Realm-horde", FOREVER), "forever-BETA-normal-horde", "an unknown region is beta")
eq(P.poolMarket("EU-Grim PvP-Realm-horde", FOREVER), "forever-EU-pvp-horde", "a realm with '-' and the word PvP")
eq(P.poolMarket("EU-grim pvp-alliance", FOREVER), "forever-EU-pvp-alliance", "pvp in any case")
eq(P.poolMarket("EU-PvPland-alliance", FOREVER), "forever-EU-normal-alliance", "PvP only as a word")
eq(P.poolMarket("EU-Argent RP-alliance", FOREVER), "forever-EU-rp-alliance", "the word RP")
eq(P.poolMarket("EU-Argent rp-alliance", FOREVER), "forever-EU-normal-alliance", "RP is case-sensitive")
eq(P.poolMarket("EU-Sharp-alliance", FOREVER), "forever-EU-normal-alliance", "RP inside a word is not RP")
eq(P.poolMarket("EU-RPG Realm-alliance", FOREVER), "forever-EU-normal-alliance", "RP only as a word")
eq(P.poolMarket("EU-RP PvP-alliance", FOREVER), "forever-EU-pvp-alliance", "PvP before RP")
eq(P.poolMarket("EU-Some Realm-neutral", FOREVER), "forever-EU-normal-neutral", "the side kept")
eq(P.poolMarket("EU-Some Realm-alliance", RETAIL), nil, "retail is not the pool's yet")
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
local function mine(market) return P.line(several, P.poolMarket(market, FOREVER), 2589, NOW) end
eq(mine("EU-Some Realm-horde"), "Pool: 2s 0c · min 1s 90c · 4 players · now", "Horde in EU")
eq(mine("EU-Some Realm-alliance"), "Pool: 1s 0c · min 90c · 2 players · now", "Alliance in EU")
eq(mine("US-Grim PvP-horde"), "Pool: 3s 0c · min 2s 90c · 6 players · now", "Horde on an NA PvP realm")
eq(mine("US-Grim PvP-alliance"), nil, "Alliance in NA: not in the file")

return checks
