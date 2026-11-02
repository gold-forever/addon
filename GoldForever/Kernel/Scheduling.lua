-- Gold Forever: work run later or spread over frames. ns.after and ns.throttle run a call later through
-- ns.safely (Errors.lua); ns.frameStart and ns.frameSpent share a frame's time between long jobs.

local _, ns = ...

function ns.after(seconds, name, fn)
	C_Timer.After(seconds, function()
		ns.safely(name, fn)
	end)
end

-- fn at most once per `seconds`; calls during the wait collapse into one run at its end.
function ns.throttle(name, seconds, fn)
	local waiting, last = false, -math.huge
	return function()
		if waiting then
			return
		end
		local wait = last + seconds - GetTime()
		if wait <= 0 then
			last = GetTime()
			ns.safely(name, fn)
		else
			waiting = true
			C_Timer.After(wait, function()
				waiting = false
				last = GetTime()
				ns.safely(name, fn)
			end)
		end
	end
end

-- Work spread over frames takes about FRAME_MS a frame: ns.frameStart() when a frame's share begins,
-- then ns.frameSpent(started, done, fallback[, ms]) every so often says whether to yield. Where the client
-- has no profiling timer, `fallback` units of work a frame instead. `ms` gives a larger share to work the
-- player waits on (a scan's reading).
local FRAME_MS = 3
function ns.frameStart()
	return debugprofilestop and debugprofilestop() or nil
end
function ns.frameSpent(started, done, fallback, ms)
	if started then
		return done % 25 == 0 and debugprofilestop() - started >= (ms or FRAME_MS)
	end
	return done >= fallback
end
