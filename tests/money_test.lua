-- Money as the addon writes it (Money.lua): plain text (Encode.money, the chat), the game's coin colours
-- (UI.layout.money and .amount, the windows) and the coin icons (ns.price.coins, tooltips). Each pinned
-- as it reads, character for character.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Money.lua"], "@Money.lua"))("GoldForever", ns)
assert(load(SOURCES["Theme.lua"], "@Theme.lua"))("GoldForever", ns)
assert(load(SOURCES["UILayout.lua"], "@UILayout.lua"))("GoldForever", ns)
local E, L = ns.Encode, ns.UI.layout

-- Plain: every unit from the largest there is, no grouping.
eq(E.money(0), "0c", "plain nothing")
eq(E.money(37), "37c", "plain copper only")
eq(E.money(2305), "23s 5c", "plain under a gold")
eq(E.money(10925), "1g 9s 25c", "plain gold, silver and copper")
eq(E.money(10000), "1g 0s 0c", "plain a gold keeps its zeros")
eq(E.money(30000000000), "3000000g 0s 0c", "plain gold not grouped")
eq(E.money(36.5), "37c", "plain half a copper rounds up")
eq(E.money(36.4), "36c", "plain under half rounds down")
eq(E.money(-150), "-1s 50c", "plain a loss with its minus sign")
eq(E.money(-150000), "-15g 0s 0c", "plain a loss of whole gold")
eq(E.money(-37), "-37c", "plain a loss of copper")

-- Coloured: the game's coin colours, the larger units only when there are any.
local G, S, C = "|cfff2c94c", "|cffc9ced6", "|cffc97b3e"
eq(L.money(0), C .. "0c|r", "coloured nothing")
eq(L.money(nil), C .. "0c|r", "coloured no amount")
eq(L.money(45), C .. "45c|r", "coloured copper only")
eq(L.money(1484), S .. "14s|r " .. C .. "84c|r", "coloured silver and copper")
eq(L.money(10000), G .. "1g|r " .. S .. "0s|r " .. C .. "0c|r", "coloured a gold keeps its zeros")
eq(L.money(1014420), G .. "101g|r " .. S .. "44s|r " .. C .. "20c|r", "coloured all three")
eq(L.money(-250), "-" .. S .. "2s|r " .. C .. "50c|r", "coloured a loss")
eq(L.money(-0.4), C .. "0c|r", "coloured under half a copper lost is nothing")
eq(L.money(30000000000, "gold"), G .. "3,000,000g|r", "coloured gold grouped")
eq(L.money(1014420, "gold"), G .. "101g|r", "coloured gold precision")
eq(L.money(1014999.6, "gold"), G .. "101g|r", "coloured gold precision drops, not rounds, the rest")
eq(L.money(45, "gold"), C .. "45c|r", "coloured gold precision under a gold")
eq(L.money(86900, "silver"), G .. "8g|r " .. S .. "69s|r", "coloured silver precision")
eq(L.money(80000, "silver"), G .. "8g|r", "coloured silver precision, no 0s")
eq(L.money(6950, "silver"), S .. "69s|r " .. C .. "50c|r", "coloured silver precision under a gold")
eq(L.money(700, "silver"), S .. "7s|r", "coloured silver precision, no 0c")
eq(L.money(0, "silver"), C .. "0c|r", "coloured silver precision, nothing")
eq(L.money(-86900, "silver"), "-" .. G .. "8g|r " .. S .. "69s|r", "coloured silver precision, a loss")

-- In a table cell: a faint dash for nothing, else gold and silver.
local DASH = "|cff6c7690—|r"
eq(L.amount(0), DASH, "cell nothing")
eq(L.amount(nil), DASH, "cell no amount")
eq(L.amount(0.4), DASH, "cell under half a copper")
eq(L.amount(-0.4), DASH, "cell under half a copper lost")
eq(L.amount(1484), S .. "14s|r " .. C .. "84c|r", "cell silver and copper")
eq(L.amount(177000), G .. "17g|r " .. S .. "70s|r", "cell gold and silver")
eq(L.amount(177050, "gold"), G .. "17g|r", "cell gold precision")
eq(L.amount(-250), "-" .. S .. "2s|r " .. C .. "50c|r", "cell a loss")

-- Icons: the client's coin string, from a gold up to the silver; plain text without the client's function.
local asked = {}
GetCoinTextureString = function(copper)
	asked[#asked + 1] = copper
	return "<" .. copper .. ">"
end
local withIcons = { Encode = ns.Encode }
assert(load(SOURCES["Money.lua"], "@Money.lua"))("GoldForever", withIcons)
assert(load(SOURCES["Pricing.lua"], "@Pricing.lua"))("GoldForever", withIcons)
local coins = withIcons.price.coins
eq(coins(0), "<0>", "icons nothing")
eq(coins(37), "<37>", "icons copper only")
eq(coins(1234.4), "<1234>", "icons rounded to a copper")
eq(coins(9999.6), "<10000>", "icons rounded up to a gold")
eq(coins(123456), "<123400>", "icons from a gold, no copper")
eq(coins(-150), "<-150>", "icons a loss, as the client is handed it")
eq(#asked, 6, "the client asked each time")
GetCoinTextureString = nil
local noIcons = { Encode = ns.Encode }
assert(load(SOURCES["Money.lua"], "@Money.lua"))("GoldForever", noIcons)
assert(load(SOURCES["Pricing.lua"], "@Pricing.lua"))("GoldForever", noIcons)
eq(noIcons.price.coins(123456), "12g 34s 0c", "no icons: plain, copper dropped from a gold")
eq(noIcons.price.coins(37), "37c", "no icons: copper only")

-- The one formatter behind them all, by mode.
local M = ns.Money
eq(M.format(10925), "1g 9s 25c", "plain by default")
eq(M.format(10925, "plain"), E.money(10925), "plain is Encode.money")
eq(M.format(86900, "colour", "silver"), L.money(86900, "silver"), "colour is UI.layout.money")
eq(M.format(0, "cell"), L.amount(0), "cell is UI.layout.amount")
eq(M.auction(86969), L.money(86969, "silver"), "the auction panel's is gold and silver")
eq(M.auction(86969), G .. "8g|r " .. S .. "69s|r", "8g 69s, not 8g")
eq(withIcons.Money.format(123456, "icons"), "<123400>", "icons is ns.price.coins")
eq(M.format(123456, "icons"), "12g 34s 0c", "icons without the client's function, plain")
eq(M.group(-1234567), "-1,234,567", "grouped, a loss")
eq(L.group(1234), "1,234", "UI.layout.group is Money.group")

return checks()
