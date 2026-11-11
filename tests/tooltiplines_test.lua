-- Tooltips.lua: each of the addon's tooltip lines is Off, shown with Shift, or Always (addon#98); Shift
-- pressed or let go refreshes the open tooltip when a line waits on it.

local saved = {}
local handlers = {}
local ns = {
	Crafting = {}, Encode = {}, Catalogue = {}, SaveView = { loaded = function() return true end }, price = {},
	settings = function(name) saved[name] = saved[name] or {} return saved[name] end,
	on = function(event, _, fn) handlers[event] = fn end,
	listen = function() end,
}
local shift = false
IsShiftKeyDown = function() return shift end
assert(load(SOURCES["Tooltips.lua"], "@Tooltips.lua"))("GoldForever", ns)

saved.tooltip = { held = "always", scan = "off", mob = "shift" }
eq(ns.tipLine("held"), true, "Always: shown")
eq(ns.tipLine("scan"), false, "Off: not shown")
eq(ns.tipLine("mob"), false, "with Shift, Shift up: not shown")
shift = true
eq(ns.tipLine("mob"), true, "with Shift, Shift held: shown")
eq(ns.tipLine("scan"), false, "Off stays off with Shift held")
shift = false

-- Every line has a name and a blurb for Settings, and its key once.
local keys = {}
for _, line in ipairs(ns.TOOLTIP_LINES) do
	eq(keys[line.key], nil, line.key .. " once")
	keys[line.key] = true
	eq(type(line.name) == "string" and type(line.blurb) == "string", true, line.key .. ": name and blurb")
end
eq(#ns.TOOLTIP_LINES, 13, "thirteen lines")
eq(ns.TOOLTIP_LINES[1].key .. " " .. ns.TOOLTIP_LINES[2].key .. " " .. ns.TOOLTIP_LINES[3].key .. " " .. ns.TOOLTIP_LINES[4].key .. " " .. ns.TOOLTIP_LINES[5].key,
	"vendor price minBuyout disenchant bagVerdict", "the price block's five lines first, in its order")

-- The price block (gf#360): Vendor, AH, AH (min), Disenchant, Suggestion; "total (each)" on a stack; a line
-- with no value left out; a line not shown is never asked for its value.
local rows = ns.TooltipBlock.rows
local function coins(c) return c .. "c" end
local asked = {}
local function values(v)
	local out = {}
	for _, key in ipairs({ "vendor", "price", "minBuyout", "disenchant", "bagVerdict" }) do
		out[key] = function(id, slot) asked[key] = true return v[key] end
	end
	return out
end
local function all() return true end
local function text(r)
	local out = {}
	for i, row in ipairs(r) do out[i] = row[1] .. " " .. row[2] end
	return table.concat(out, " / ")
end
local FULL = { vendor = 6, price = 20, minBuyout = 18, disenchant = 40, bagVerdict = "post (AH 19c after the cut)" }
eq(text(rows(2589, 1, values(FULL), all, coins)), "Vendor 6c / AH 20c / AH (min) 18c / Disenchant 40c / Suggestion post (AH 19c after the cut)", "one item: each line in order")
eq(text(rows(2589, 20, values(FULL), all, coins)), "Vendor 120c (6c) / AH 400c (20c) / AH (min) 360c (18c) / Disenchant 800c (40c) / Suggestion post (AH 19c after the cut)", "a stack of 20: total (each), the suggestion as it is")
eq(text(rows(2589, 3, values({ price = 20, vendor = 0 }), all, coins)), "AH 60c (20c)", "no value, or none worth a copper: left out")
eq(text(rows(2589, 1, values({}), all, coins)), "", "nothing known: no block")
asked = {}
saved.tooltip = { vendor = "always", price = "always", minBuyout = "shift", disenchant = "off", bagVerdict = "shift" }
eq(text(rows(2589, 1, values(FULL), ns.tipLine, coins)), "Vendor 6c / AH 20c", "Shift up: the Always lines alone")
eq(asked.minBuyout or asked.disenchant or asked.bagVerdict, nil, "a line not shown is not looked up")
shift = true
eq(text(rows(2589, 1, values(FULL), ns.tipLine, coins)), "Vendor 6c / AH 20c / AH (min) 18c / Suggestion post (AH 19c after the cut)", "Shift held: the Shift lines too, Off stays off")
shift = false

-- Shift pressed: the open tooltip is drawn again, only when a line is on Shift and only for Shift.
local refreshed = 0
GameTooltip = { IsShown = function() return true end, RefreshData = function() refreshed = refreshed + 1 end }
local changed = handlers.MODIFIER_STATE_CHANGED
changed("LSHIFT", 1)
eq(refreshed, 1, "Shift pressed with a line on Shift: refreshed")
changed("RSHIFT", 0)
eq(refreshed, 2, "Shift let go: refreshed again")
changed("LCTRL", 1)
eq(refreshed, 2, "another key: not refreshed")
saved.tooltip = { held = "always", mob = "off" }
changed("LSHIFT", 1)
eq(refreshed, 2, "no line on Shift: not refreshed")
saved.tooltip = { mob = "shift" }
GameTooltip.IsShown = function() return false end
changed("LSHIFT", 1)
eq(refreshed, 2, "no tooltip open: not refreshed")
GameTooltip = nil
changed("LSHIFT", 1)

return checks()
