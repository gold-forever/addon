-- Prices.lua: the pool's prices the companion writes (GoldForever_Data, contract T01) become one
-- tooltip line for the player's market; anything absent or malformed gives no line and no error.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
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

return checks
