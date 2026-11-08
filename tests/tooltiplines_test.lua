-- Tooltips.lua: each of the addon's tooltip lines is Off, shown with Shift, or Always (addon#98); Shift
-- pressed or let go refreshes the open tooltip when a line waits on it.

local saved = {}
local handlers = {}
local ns = {
	Encode = {}, Catalogue = {}, SaveView = { loaded = function() return true end }, price = {},
	settings = function(name) saved[name] = saved[name] or {} return saved[name] end,
	on = function(event, _, fn) handlers[event] = fn end,
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
eq(#ns.TOOLTIP_LINES, 10, "ten lines")

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
