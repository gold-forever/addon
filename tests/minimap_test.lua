-- Minimap.lua's arithmetic: where the button sits for an angle, and the angle a drag leaves it at.

local ns = { on = function() end, commands = {}, settings = function(_, d) return d end }
assert(load(SOURCES["Theme.lua"], "@Theme.lua"))("GoldForever", ns)
assert(load(SOURCES["Minimap.lua"], "@Minimap.lua"))("GoldForever", ns)
local M = ns.Minimap

local x, y = M.offset(0, 80)
near(x, 80, "east is right")
near(y, 0, "east is level")
x, y = M.offset(90, 80)
near(x, 0, "north is centred")
near(y, 80, "north is up")
x, y = M.offset(225, 100)
near(x, -100 / math.sqrt(2), "the default sits bottom left")
near(y, -100 / math.sqrt(2), "below the centre")

near(M.angle(110, 10, 10, 10), 0, "a drag to the right")
near(M.angle(10, 110, 10, 10), 90, "a drag straight up")
near(M.angle(-90, 10, 10, 10), 180, "a drag to the left")
near(M.angle(10, -90, 10, 10), 270, "a drag straight down")
near(M.angle(0, 0, 10, 10), 225, "down and left")
near(M.angle(20, 0, 10, 10), 315, "down and right is not negative")
for _, a in ipairs({ 0, 33, 135, 225, 300 }) do
	local dx, dy = M.offset(a, 70)
	near(M.angle(10 + dx, 10 + dy, 10, 10), a, "an angle survives a round trip: " .. a)
end

-- A right-click steps on from the saved look, whichever look was drawn last.
do
	local asked
	ns.commands.look = function(name) asked = name end
	ns.currentLook = function() return "arcane" end
	ns.Theme.apply("web")
	M.switchLook()
	eq(asked, "web", "saved Arcane, drawn Web: on to Web, round the list")
	ns.currentLook = function() return "web" end
	M.switchLook()
	eq(asked, "classic", "saved Web: on to Classic")
end

return checks()
