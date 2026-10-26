-- FirstRun.lua: the presets over Settings → Modules (who sees the card: saveview_test.lua).

local ns = {}
assert(load(SOURCES["FirstRun.lua"], "@FirstRun.lua"))("GoldForever", ns)
local F = ns.FirstRun

local function tables()
	return { prices = { tooltip = true }, auction = { hidden = false }, crafting = { strip = true }, shop = { shown = true },
		appraiser = { shown = true }, advisor = { shown = true } }
end

local s = tables()
eq(F.apply("prices", s), true, "a known preset")
eq(s.prices.tooltip, true, "prices only: the tooltip")
eq(s.auction.hidden, true, "no auction panel")
eq(s.crafting.strip, false, "no crafting strip")
eq(s.appraiser.shown, false, "no HUD")
eq(s.advisor.shown, false, "no bag advice")

s = tables()
F.apply("trader", s)
eq(s.auction.hidden, false, "trader: the auction panel")
eq(s.crafting.strip, true, "the crafting strip")
eq(s.appraiser.shown, false, "no HUD")

s = tables()
F.apply("everything", s)
eq(s.appraiser.shown and s.advisor.shown and s.crafting.strip and not s.auction.hidden and s.prices.tooltip, true, "everything on")

eq(F.apply("nonsense", tables()), false, "an unknown preset changes nothing")

return checks()
