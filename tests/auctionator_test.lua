-- The last price source (gf#323): with no pool price and no own scan, ns.price asks Auctionator's public
-- API when it is loaded. The result is labelled, and anything wrong with Auctionator is simply no price.

local ns = {}
loadEncode(ns)
assert(load(SOURCES["Money.lua"], "@Money.lua"))("GoldForever", ns)
ns.commands = {}
ns.on = function() end
ns.listen = function() end
ns.module = function() end
assert(load(SOURCES["Pricing.lua"], "@Pricing.lua"))("GoldForever", ns)
assert(load(SOURCES["DataFormat.lua"], "@DataFormat.lua"))("GoldForever", ns)
assert(load(SOURCES["Prices.lua"], "@Prices.lua"))("GoldForever", ns)

local MARKET = "EU-Classic Beta PvE 2-alliance"
local NOW = 1761148800
local POOLED, SCANNED, ONLY_AUCTIONATOR = 2589, 2592, 4306
ns.me = function() return { faction = "Alliance", realm = "R" } end
ns.db = function() return { client = {}, catalogue = { items = {}, vendor = {} } } end
ns.market = function() return "m" end
ns.Prices.markets = function() return { MARKET } end
ns.ownPrice = function(id)
	if id == SCANNED then
		return 700, 650, NOW
	end
end
GoldForever_Prices = { v = 1, at = NOW, markets = { [MARKET] = { [POOLED] = { 1234, 1100, 3, NOW } } } }

local asked
local function standIn(fn)
	asked = {}
	Auctionator = { API = { v1 = { GetAuctionPriceByItemID = function(caller, id)
		asked[#asked + 1] = { caller = caller, id = id }
		return fn(id)
	end } } }
end
local price = ns.price

-- Used last.
standIn(function() return 5000 end)
local value, from = price.valued(POOLED)
eq(value, 1234, "the pool's price wins")
eq(from, "pool", "and says so")
value, from = price.valued(SCANNED)
eq(value, 700, "the own scan's comes before Auctionator")
eq(from, "scan", "and says so")
eq(#asked, 0, "Auctionator is not asked while another source has a price")

-- Labelled, and asked as its API wants.
value, from = price.valued(ONLY_AUCTIONATOR)
eq(value, 5000, "no other price: Auctionator's")
eq(from, "auctionator", "with the source auctionator")
eq(asked[1].caller, "GoldForever", "asked in the addon's name")
eq(asked[1].id, ONLY_AUCTIONATOR, "for the item")
eq(price.sourceLabel("auctionator"), "Auctionator", "shown as Auctionator")
eq(price.sourceLabel("pool"), "pool", "other sources keep their words")
eq(price.sourceLabel("typical price"), "typical price", "the typical price too")

-- Every reading of the market value has it.
eq(price.market(ONLY_AUCTIONATOR), 5000, "the market value")
eq(price.buy(ONLY_AUCTIONATOR), 5000, "what buying one costs")
local worth, where = price.worth(ONLY_AUCTIONATOR)
eq(worth, 4750, "the worth is after the auction cut")
eq(where, "auction", "and is an auction sale")
eq(price.buy(POOLED), 1100, "the pool's minimum still comes first")

-- Absent, erroring, or answering nonsense: no price, never a crash.
local function noPrice(label)
	local v, f = price.valued(ONLY_AUCTIONATOR)
	eq(v, nil, label .. ": no price")
	eq(f, nil, label .. ": no source")
	eq(price.market(ONLY_AUCTIONATOR), nil, label .. ": no market value")
	eq(price.buy(ONLY_AUCTIONATOR), nil, label .. ": nothing to buy at")
	eq(price.worth(ONLY_AUCTIONATOR), nil, label .. ": no worth")
end
Auctionator = nil
noPrice("not installed")
Auctionator = {}
noPrice("no public API")
Auctionator = { API = { v1 = {} } }
noPrice("no such function")
standIn(function() error("database not ready") end)
noPrice("an error")
eq(#asked > 0, true, "the erroring stand-in was asked")
standIn(function() return nil end)
noPrice("nil")
standIn(function() return "12" end)
noPrice("not a number")
standIn(function() return 0 end)
noPrice("zero")
standIn(function() return -1 end)
noPrice("negative")
standIn(function() return ns.Encode.MAX_COPPER + 1 end)
noPrice("absurd")

-- The tooltip: a row labelled Auctionator only for a price that came from it, under the "price" setting.
local postCalls = {}
Enum = { TooltipDataType = { Item = 1, Unit = 2 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
	if kind == Enum.TooltipDataType.Item then
		postCalls[#postCalls + 1] = fn
	end
end }
GetServerTime = function() return NOW end
local tipSettings = { price = "always" }
local tns = setmetatable({
	price = {
		own = function() end, worth = function() end, disenchant = function() end, enchanting = function() end,
		coins = function(c) return c .. "c" end,
		sourceLabel = price.sourceLabel,
		valued = function(id)
			if id == ONLY_AUCTIONATOR then
				return 5000, "auctionator"
			end
			return 1234, "pool"
		end,
	},
	settings = function() return tipSettings end,
	on = function() end,
	listen = function() end,
	me = function() return {} end,
	safely = function(_, fn, ...) fn(...) end,
	tipPrefix = function() return "" end,
	Crafting = {}, Encode = {}, Catalogue = {}, SaveView = { loaded = function() return true end },
	Prices = { neutralMarkets = function() end, rows = function() end, mine = function() return {} end, supply = function() end, supplyLine = function() end },
}, { __index = ns })
assert(load(SOURCES["Tooltips.lua"], "@Tooltips.lua"))("GoldForever", tns)
GameTooltip = {}
local function tipLines(id)
	local lines = {}
	GameTooltip.AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " " .. right end
	GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
	for _, fn in ipairs(postCalls) do
		fn(GameTooltip, { id = id })
	end
	return table.concat(lines, " / ")
end
eq(tipLines(ONLY_AUCTIONATOR), "Auctionator 5000c", "the tooltip's row")
eq(tipLines(POOLED), "", "a pool price adds no Auctionator row")
tipSettings.price = "off"
eq(tipLines(ONLY_AUCTIONATOR), "", "the row follows the price setting")

Auctionator, TooltipDataProcessor, Enum, GameTooltip, GetServerTime, GoldForever_Prices = nil, nil, nil, nil, nil, nil
return checks()
