-- API.lua: what other addons read through GoldForeverAPI: numbers and strings only, the real pricing
-- behind it, nil for whatever is unknown, and nothing a caller can change.

local ns = {}
loadEncode(ns)
for _, file in ipairs({ "Money.lua", "Realms.lua", "Scans.lua", "Schema.lua", "Views.lua", "ViewsMoney.lua", "ViewsSession.lua", "ViewsItems.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
ns.commands = {}
ns.on = function() end
ns.listen = function() end
ns.module = function() end

local NOW = 1761148800
function GetServerTime() return NOW end
function strsplit(sep, text)
	local out = {}
	for part in string.gmatch(text .. sep, "([^" .. sep .. "]*)" .. sep) do
		out[#out + 1] = part
	end
	return (unpack or table.unpack)(out)
end

local MARKET = "EU-Beta PvE-alliance"
local POOL = "forever-EU-normal-alliance"
local db = {
	client = { interface = 16001, region = "EU" },
	scans = { { kind = "full", market = MARKET, t = NOW - 3600, rows = { "2590,100,5;2591,5000,1" } } },
	catalogue = { items = {}, vendor = {} },
}
local me = { faction = "Alliance", realm = "Beta PvE", prof = {} }
ns.db = function() return db end
ns.me = function() return me end
ns.market = function() return MARKET end

for _, file in ipairs({ "Pricing.lua", "DataFormat.lua", "Prices.lua", "PricesMarkets.lua", "Disenchant.lua", "API.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end

GoldForever_Prices = { v = 1, at = NOW, markets = { [POOL] = {
	[2589] = { 1234, 1100, 3, NOW - 7200 },
	[2591] = { 1000, 900, 4, NOW - 7200 },
	[11137] = { 1000, 900, 2, NOW - 60 },
} } }

local API = GoldForeverAPI
local function item(columns)
	local index, row = ns.Encode.columns(ns.FIELDS.item), {}
	for i = 1, 11 do row[i] = "" end
	for name, value in pairs(columns) do row[index[name]] = value end
	return table.concat(row, ",")
end
db.catalogue.items[5001] = item({ name = "Violet Sash", quality = 2, ilvl = 36, class = 4, sell = 75 })
db.catalogue.items[5002] = item({ name = "Worth nothing", quality = 1, ilvl = 5, class = 4, sell = 0 })
-- Disenchants into materials nobody has priced: a level 10 green's strange dust is absent from the fixture.
db.catalogue.items[5003] = item({ name = "Unpriced green", quality = 2, ilvl = 10, class = 4, sell = 0 })

eq(API.version, 1, "the API's version starts at 1")

local function price(id)
	local value, source, age, players = API.GetPrice(id)
	return table.concat({ tostring(value), tostring(source), tostring(age), tostring(players) }, " ")
end
eq(price(2589), "1234 pool 7200 3", "the pool's value, its source, its age and its players")
eq(price(2590), "100 scan 3600 1", "no pool price: the player's own scan, one player behind it")
eq(price(2591), "5000 scan 3600 1", "the own scan overrules a pool price it is newer than and far from")
eq(price(424242), "nil nil nil nil", "an item nobody priced is nil")
eq(price("2589"), "nil nil nil nil", "an id that is no number is nil")
eq(price(nil), "nil nil nil nil", "no id is nil")

-- A pool entry scanned a moment "later" than this client's clock is no negative age.
GoldForever_Prices.markets[POOL][2592] = { 700, 600, 2, NOW + 30 }
eq(price(2592), "700 pool 0 2", "a clock behind the scan's: age 0")

local file = GoldForever_Prices
GoldForever_Prices = { v = 99, markets = file.markets }
eq(price(2589), "nil nil nil nil", "a prices file of another version gives no pool price")
eq(price(2590), "100 scan 3600 1", "and the own scan still answers")
GoldForever_Prices = file

eq(API.GetVendorPrice(5001), 75, "what a vendor pays for one")
eq(API.GetVendorPrice(5002), nil, "nothing a vendor pays is nil")
eq(API.GetVendorPrice(424242), nil, "an unknown item has no vendor price")
eq(API.GetVendorPrice("5001"), nil, "an id that is no number has no vendor price")
-- The client's lookup also takes a name or a link: the API answers for item IDs only.
C_Item = { GetItemInfo = function(item)
	return nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, item == "Violet Sash" and 75 or nil
end }
eq(API.GetVendorPrice("Violet Sash"), nil, "an item's name is no item ID")
C_Item = nil

local dust = ns.Disenchant.of(2, 36, 4).outcomes[1]
eq(dust.id, 11137, "the sash's first outcome is the priced dust")
eq(API.GetDisenchantValue(5001), math.floor(dust.chance * (dust.min + dust.max) / 2 * 950 + 0.5), "the expected worth of its materials")
eq(select("#", API.GetDisenchantValue(5001)), 1, "the value alone, not the skill")
eq(API.GetDisenchantValue(5003), nil, "materials nobody priced are no value, not a value of 0")
eq(API.GetDisenchantValue(5002), nil, "what cannot be disenchanted is nil")
eq(API.GetDisenchantValue(424242), nil, "an unknown item has no disenchant value")
ns.retail = true
eq(API.GetDisenchantValue(5001), nil, "none on retail: the table is the classic one")
ns.retail = nil

-- Before the character is known (another addon's load, say) every call answers nil and raises nothing.
local playing, saved = me, db
me, db = nil, nil
eq(price(2589), "nil nil nil nil", "before login: no price")
eq(API.GetVendorPrice(5001), nil, "before login: no vendor price")
eq(API.GetDisenchantValue(5001), nil, "before login: no disenchant value")
me, db = playing, saved

-- What a caller gets holds no table of the addon's, and the API itself cannot be changed.
for _, call in ipairs({ { API.GetPrice(2589) }, { API.GetPrice(2590) }, { API.GetVendorPrice(5001) }, { API.GetDisenchantValue(5001) } }) do
	for _, value in pairs(call) do
		eq(type(value) == "table", false, "a call returns no table")
	end
end
local original = API.GetPrice
eq(pcall(function() API.GetPrice = function() return 1 end end), false, "GetPrice cannot be replaced")
eq(pcall(function() API.version = 2 end), false, "the version cannot be changed")
eq(pcall(function() API.Extra = 1 end), false, "nothing can be added")
eq(API.GetPrice, original, "GetPrice is the same after those tries")
eq(API.version, 1, "the version is the same after those tries")
eq(type(getmetatable(API)) == "table", false, "its metatable is not handed out")

-- A read changes nothing in the save or the prices file.
local function dump(value, seen)
	if type(value) ~= "table" then
		return tostring(value)
	end
	local keys, out = {}, {}
	for key in pairs(value) do keys[#keys + 1] = key end
	table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
	for i, key in ipairs(keys) do out[i] = tostring(key) .. "=" .. dump(value[key]) end
	return "{" .. table.concat(out, ",") .. "}"
end
local before = dump(db) .. dump(GoldForever_Prices)
API.GetPrice(2589) API.GetPrice(2590) API.GetVendorPrice(5001) API.GetDisenchantValue(5001)
eq(dump(db) .. dump(GoldForever_Prices), before, "reading leaves the save and the prices file as they were")

return checks()
