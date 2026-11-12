-- The HUD's levelling pace (gf#379): XP an hour over the last 15 minutes of play, the time to the next
-- level at that pace, the rested XP left, and the line hidden at the level cap.

local ns = {}
for _, file in ipairs({ "Views.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["HudPace.lua"], "@HudPace.lua"))("GoldForever", ns)
local Pace = ns.HudPace

-- XP gains `every` seconds apart from `from` to `to`, played (not AFK).
local function farm(p, from, to, every, xp)
	for t = from, to, every do
		Pace.gain(p, t, false, xp)
	end
end

-- The rate: nothing until 2 minutes of play, then XP an hour over what was played.
local p = Pace.new(0)
Pace.gain(p, 60, false, 500)
eq(Pace.rate(p, 100, false), nil, "under 2 minutes of play: no rate")
eq(Pace.rate(p, 120, false), 15000, "500 XP in 2 minutes: 15k an hour")

-- The window: the last 15 minutes of play only.
p = Pace.new(0)
farm(p, 60, 1800, 60, 100) -- 100 XP a minute for half an hour
Pace.gain(p, 1800, false, 0)
eq(Pace.rate(p, 1800, false), 6000, "100 XP a minute: 6k an hour")
p = Pace.new(0)
farm(p, 60, 900, 60, 1000) -- a fast first 15 minutes
farm(p, 960, 1800, 60, 100) -- a slow next 15
eq(Pace.rate(p, 1800, false), 6000, "the fast start has left the window")

-- A gap: time AFK is not play, so a break does not drag the rate down.
p = Pace.new(0)
farm(p, 60, 600, 60, 100) -- 10 minutes, 1000 XP
Pace.tick(p, 600, true) -- AFK at 10 minutes
Pace.tick(p, 4200, false) -- back an hour later
eq(Pace.rate(p, 4200, false), 6000, "an hour AFK is not counted")
Pace.gain(p, 4260, false, 100)
eq(Pace.rate(p, 4260, false), 6000, "and play goes on from where it stopped")

-- A level-up mid-window: the gains are XP earned, whichever level they fell in.
p = Pace.new(0)
farm(p, 60, 600, 60, 100)
local ding = Pace.status(p, 600, false, { level = 27, cur = 100, max = 2000, rested = 0 })
eq(ding.rate, 6000, "the gains before the level-up still count")
eq(ding.eta, 1900 / 6000 * 3600, "the time to the next level: what is left at this pace")

-- Rested: as a share of the level.
local st = Pace.status(p, 600, false, { level = 27, cur = 100, max = 2000, rested = 240 })
eq(st.rested, 12, "240 rested of a 2000 XP level: 12%")
eq(Pace.status(p, 600, false, { level = 27, cur = 100, max = 2000, rested = 4000 }).rested, 200, "up to 1.5 levels and over")

-- The cap: no line.
eq(Pace.status(p, 600, false, { level = 60, cur = 0, max = 217000, rested = 0, atCap = true }), nil, "at the level cap: hidden, whatever the bar says")
eq(Pace.status(p, 600, false, { level = 27, cur = 0, max = 0, rested = 0 }), nil, "no XP bar: hidden")

-- The line: "Level 28 in ~19m · 6.0k XP/h · rested 12%", a dash for what is not known yet (the game's
-- fonts have no arrow or long dash).
eq(Pace.line(st, ns.Views), "Level 28 in ~19m · 6.0k XP/h · rested 12%", "the line")
local early = Pace.status(Pace.new(0), 30, false, { level = 27, cur = 100, max = 2000, rested = 240 })
eq(early.rate, nil, "warming up")
eq(Pace.line(early, ns.Views), "Level 28 in - · - XP/h · rested 12%", "dashes until 2 minutes of data")

-- The mode: Off, With Shift (while Shift is held) or Always (the default).
eq(Pace.shown(nil, false), true, "Always by default")
eq(Pace.shown("off", true), false, "Off")
eq(Pace.shown("shift", false), false, "With Shift: not without it")
eq(Pace.shown("shift", true), true, "With Shift: while it is held")

return checks()
