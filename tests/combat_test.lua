-- The kernel's combat safety and frame budget (Combat.lua, Errors.lua): work that must not run in combat
-- waits for its end with ns.afterCombat, and repeated updates collapse with ns.throttle, so no module
-- keeps its own PLAYER_REGEN_ENABLED handling or timers for them.

-- Errors.lua, Events.lua and Combat.lua on a stand-in client: its events, its clock and its timers.
local handler
local time = 100
local timers = {}
function GetTime() return time end
function GetServerTime() return 1761148800 end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
C_Timer = {
	After = function(seconds, fn)
		timers[#timers + 1] = { at = time + seconds, fn = fn }
	end,
}
-- Time passes: the timers due by then run, in order.
local function wait(seconds)
	time = time + seconds
	local due = {}
	for i = #timers, 1, -1 do
		if timers[i].at <= time then
			table.insert(due, 1, table.remove(timers, i))
		end
	end
	for _, t in ipairs(due) do
		t.fn()
	end
end
local function fire(event, ...)
	handler(nil, event, ...)
end

local ns = { say = function() end, stopped = function() return false end }
for _, file in ipairs({ "Errors.lua", "Events.lua", "Combat.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end

-- Out of combat: at once.
local ran = {}
local function note(what)
	return function()
		ran[#ran + 1] = what
	end
end
eq(ns.inCombat(), false, "out of combat before any fight")
ns.afterCombat("test", note("now"))
eq(table.concat(ran, ", "), "now", "out of combat, the work runs at once")

-- In combat: once, when it ends, however often it was asked for; each piece of work in the order asked.
ran = {}
fire("PLAYER_REGEN_DISABLED")
eq(ns.inCombat(), true, "in combat from the fight's start")
local bind, show = note("bind"), note("show")
ns.afterCombat("test", bind)
ns.afterCombat("test", show)
ns.afterCombat("test", bind)
eq(table.concat(ran, ", "), "", "nothing runs in combat")
time = 130
fire("PLAYER_REGEN_ENABLED")
eq(ns.inCombat(), false, "out of combat once it ends")
eq(table.concat(ran, ", "), "bind, show", "each piece of work once after combat, in the order first asked")
eq(ns.combatEnded(), 130, "when the last fight ended")
ran = {}
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_REGEN_ENABLED")
eq(table.concat(ran, ", "), "", "work already run does not run again after the next fight")

-- Work asked for when the client already locks the UI (a reload in combat: no fight start seen) waits too.
InCombatLockdown = function() return true end
eq(ns.inCombat(), true, "in combat while the client locks the UI")
ns.afterCombat("test", note("after reload"))
eq(table.concat(ran, ", "), "", "waits while the UI is locked")
InCombatLockdown = function() return false end
fire("PLAYER_REGEN_ENABLED")
eq(table.concat(ran, ", "), "after reload", "runs when combat ends")
InCombatLockdown = nil

-- Work that fails records its error under its name, and the rest still runs.
ran = {}
local failed = {}
local fail = ns.fail
ns.fail = function(name)
	failed[#failed + 1] = name
end
fire("PLAYER_REGEN_DISABLED")
ns.afterCombat("broken", function() error("boom") end)
ns.afterCombat("test", note("after the error"))
fire("PLAYER_REGEN_ENABLED")
eq(table.concat(failed, ", "), "broken", "the failing work's error is recorded under its name")
eq(table.concat(ran, ", "), "after the error", "the work after it still runs")
ns.fail = fail

-- Work asked for while the end of combat runs the waiting work runs at once.
ran = {}
fire("PLAYER_REGEN_DISABLED")
ns.afterCombat("test", function()
	ns.afterCombat("test", note("asked at the end"))
end)
fire("PLAYER_REGEN_ENABLED")
eq(table.concat(ran, ", "), "asked at the end", "work asked for as combat ends runs at once")

-- Throttled: the first call at once, the calls during the wait as one run at its end, in or out of combat.
local runs = 0
local soon = ns.throttle("test", 2, function()
	runs = runs + 1
end)
soon()
eq(runs, 1, "the first call runs at once")
soon()
soon()
eq(runs, 1, "calls within the wait do not run at once")
wait(1)
soon()
eq(runs, 1, "nor later within it")
wait(1)
eq(runs, 2, "the calls within the wait run once at its end")
wait(5)
eq(runs, 2, "and only once")
soon()
eq(runs, 3, "a call after the wait runs at once")
fire("PLAYER_REGEN_DISABLED")
wait(5)
soon()
eq(runs, 4, "in combat too: throttling is not combat safety")
fire("PLAYER_REGEN_ENABLED")
return checks()
