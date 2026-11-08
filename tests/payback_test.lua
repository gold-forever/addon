-- A recipe item's tooltip says how many crafts pay back its price (gf#321): Tooltips.lua over the real
-- quote (Crafting.lua, CraftPlanner.lua) and the catalogue's recipe rows.

local postCalls, listeners = {}, {}
local PATTERN, LIMITED, DROPPED, NO_MARGIN, LOSING, EVEN, UNPRICED, UNKNOWN_RECIPE, ENCHANT, RANDOM, PLAIN, COMMA, TWIN, SINGLE, SOMETIMES = 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15
local names = {
	[PATTERN] = "Pattern: Bolt", [LIMITED] = "Plans: Limited Bolt", [DROPPED] = "Formula: Dropped Bolt",
	[NO_MARGIN] = "Schematic: Unsold", [LOSING] = "Recipe: Losing", [EVEN] = "Design: Even",
	[UNPRICED] = "Pattern: Bolt", [UNKNOWN_RECIPE] = "Pattern: Never Seen", [ENCHANT] = "Formula: Enchant", [RANDOM] = "Technique: Random",
	[PLAIN] = "Linen Cloth", [COMMA] = "Manual: Bandage, Heavy", [TWIN] = "Pattern: Twin", [SINGLE] = "Pattern: Single", [SOMETIMES] = "Pattern: Sometimes",
}
local OUT, UNSOLD, LOSS, EVEN_OUT, COMMA_OUT, TWIN_LOW, TWIN_HIGH, SINGLE_OUT, REAGENT = 101, 102, 103, 104, 105, 106, 107, 108, 200
local market = { [OUT] = 1000, [LOSS] = 10, [EVEN_OUT] = 100, [COMMA_OUT] = 1000, [TWIN_LOW] = 1000, [TWIN_HIGH] = 5000, [SINGLE_OUT] = 1000,
	[DROPPED] = 7000, [NO_MARGIN] = 500, [LOSING] = 500, [EVEN] = 500, [UNKNOWN_RECIPE] = 500, [ENCHANT] = 500, [RANDOM] = 500, [COMMA] = 7000, [TWIN] = 2500, [SINGLE] = 100, [SOMETIMES] = 100 }
local cheapest = { [REAGENT] = 130 }

function strsplit(sep, text)
	local out = {}
	for part in string.gmatch(text .. sep, "([^" .. sep .. "]*)" .. sep) do
		out[#out + 1] = part
	end
	return (table.unpack or unpack)(out)
end

local recipes = {
	[1] = "197," .. OUT .. ",1,1," .. REAGENT .. "*1,Bolt",
	[2] = "197," .. OUT .. ",1,1," .. REAGENT .. "*1,Limited Bolt",
	[3] = "197," .. OUT .. ",1,1," .. REAGENT .. "*1,Dropped Bolt",
	[4] = "197," .. UNSOLD .. ",1,1," .. REAGENT .. "*1,Unsold",
	[5] = "197," .. LOSS .. ",1,1," .. REAGENT .. "*1,Losing",
	[6] = "197," .. EVEN_OUT .. ",1,1,300*1,Even",
	[9] = "333,,,," .. REAGENT .. "*1,Enchant",
	[7] = "333,,,," .. REAGENT .. "*1,Sometimes",
	[17] = "197," .. OUT .. ",1,1," .. REAGENT .. "*1,Sometimes",
	[10] = "197," .. RANDOM + 500 .. ",1,1," .. REAGENT .. "*1,Random",
	[12] = "197," .. COMMA_OUT .. ",1,1," .. REAGENT .. "*1,Bandage\226\128\154 Heavy",
	[13] = "197," .. TWIN_HIGH .. ",1,1," .. REAGENT .. "*1,Twin",
	[14] = "197," .. TWIN_LOW .. ",1,1," .. REAGENT .. "*1,Twin",
	[15] = "197," .. SINGLE_OUT .. ",1,1," .. REAGENT .. "*1,Single",
}
cheapest[300] = 95 -- Even: 100c after the 5% cut, less 95c
market[RANDOM + 500] = nil -- a random result: a recipe-class output with no price

local db = {
	fields = { recipe = "skillLine,output,min,max,reagents,name", vendor = "buy,limited,t,qty", item = "name" },
	catalogue = { recipes = recipes, vendor = { [PATTERN] = "7000,,,1", [LIMITED] = "2100,1,,1" } },
}

local shiftDown, modes = false, { payback = "shift" }
IsShiftKeyDown = function() return shiftDown end
C_Item = { GetItemInfo = function(id) return names[id] end, IsEquippableItem = function() return false end, GetItemInfoInstant = function() end }
Enum = { TooltipDataType = { Item = 0, Unit = 6 } }
TooltipDataProcessor = { AddTooltipPostCall = function(kind, fn)
	if kind == Enum.TooltipDataType.Item then
		postCalls[#postCalls + 1] = fn
	end
end }

local ns = {
	price = {
		market = function(id) return market[id] end, buy = function(id) return cheapest[id] end, vendorBuy = function() return nil end,
		cut = 0.05, own = function() end, worth = function() end, disenchant = function() end, enchanting = function() return 0 end,
		valued = function() end, sourceLabel = function() end,
		itemInfo = function(id) if id == RANDOM + 500 then return nil, nil, 9 end end,
		coins = function(c) return c .. "c" end,
	},
	db = function() return db end, me = function() return { prof = {} } end,
	settings = function() return modes end,
	on = function() end, listen = function(event, _, fn) listeners[event] = fn end,
	safely = function(_, fn, ...) fn(...) end, tipPrefix = function() return "" end,
	Catalogue = { name = function() end, startsQuest = function() end }, SaveView = { loaded = function() return true end },
	HeldView = { line = function() end },
	Prices = { neutralMarkets = function() end, rows = function() end, mine = function() return {} end, supply = function() end, supplyLine = function() end },
	FIELDS = db.fields,
}
loadEncode(ns)
for _, file in ipairs({ "Crafting.lua", "Tooltips.lua", "CraftPlanner.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end

GameTooltip = {}
local function tip(id)
	local lines = {}
	GameTooltip.AddDoubleLine = function(_, left, right) lines[#lines + 1] = left .. " " .. right end
	GameTooltip.AddLine = function(_, text) lines[#lines + 1] = text end
	for _, fn in ipairs(postCalls) do
		fn(GameTooltip, { id = id })
	end
	return table.concat(lines, " / ")
end

eq(tip(PATTERN), "", "With Shift, Shift up: no line")
shiftDown = true
-- Bolt: 1000c after the cut is 950c, less 130c: 820c a craft; 7000c / 820c is 8.5, so 9 crafts.
eq(tip(PATTERN), "Pays back in 9 crafts at today's margin (820c a craft)", "the vendor's price over the margin, rounded up")
eq(tip(LIMITED), "Pays back in 3 crafts at today's margin (820c a craft)", "a limited-stock vendor still sells it")
eq(tip(DROPPED), "Pays back in 9 crafts at today's margin (820c a craft)", "no vendor: the market value")
eq(tip(SINGLE), "Pays back in 1 craft at today's margin (820c a craft)", "one craft, singular")
eq(tip(LOSING), "No profit at today's prices", "a negative margin")
eq(tip(EVEN), "No profit at today's prices", "a margin of zero, never a division")
eq(tip(NO_MARGIN), "", "unknown margin: the output has no price")
eq(tip(UNPRICED), "", "unknown price: no vendor, no market")
eq(tip(UNKNOWN_RECIPE), "", "a recipe the catalogue lacks")
eq(tip(ENCHANT), "", "a recipe that makes no item has no margin")
eq(tip(RANDOM), "", "a random result has no margin")
eq(tip(PLAIN), "", "not a recipe item")
eq(tip(COMMA), "Pays back in 9 crafts at today's margin (820c a craft)", "a name with a comma matches its encoded row")
-- Twin's two ranks: the lowest recipe ID answers (4750c - 130c), as the same names always pick the same.
eq(tip(TWIN), "Pays back in 1 craft at today's margin (4620c a craft)", "of two recipes by one name, the lowest ID")
eq(tip(SOMETIMES), "Pays back in 1 craft at today's margin (820c a craft)", "a lower ID of the name that makes no item is passed over")

modes.payback = "off"
eq(tip(PATTERN), "", "Off: no line")
modes.payback = "always"
shiftDown = false
eq(tip(PATTERN), "Pays back in 9 crafts at today's margin (820c a craft)", "Always: without Shift")

-- A recipe read after the first hover answers once the profession window has been read.
names[UNKNOWN_RECIPE] = "Pattern: Learned Later"
eq(tip(UNKNOWN_RECIPE), "", "not catalogued yet")
recipes[16] = "197," .. OUT .. ",1,1," .. REAGENT .. "*1,Learned Later"
listeners.recipesRead({})
eq(tip(UNKNOWN_RECIPE), "Pays back in 1 craft at today's margin (820c a craft)", "catalogued, after recipesRead")

-- The two rules on their own.
local C = ns.Crafting
eq(C.taughtName("Pattern: Bolt"), "Bolt", "a recipe item's name")
eq(C.taughtName("Tome: Bolt"), nil, "another prefix")
eq(C.taughtName("Linen Cloth"), nil, "no prefix")
local money = function(c) return c .. "c" end
eq(C.paybackLine(100, 0, money), "No profit at today's prices", "zero")
eq(C.paybackLine(nil, -5, money), nil, "unknown price, losing: nothing")
eq(C.paybackLine(0, 5, money), nil, "no price to pay back: nothing")
eq(C.paybackLine(100, nil, money), nil, "unknown margin")

TooltipDataProcessor, Enum, GameTooltip, IsShiftKeyDown, C_Item, strsplit = nil, nil, nil, nil, nil, nil
return checks()
