-- Gold Forever: the error path. A collector that fails records its error (ns.fail) and leaves the others
-- running: ns.safely runs a call that way, and ns.after and ns.throttle run later ones through it.

local _, ns = ...

local errors = {} -- collector -> { n, msg, t, stack }; becomes the save's once it is loaded
local told = {} -- collectors already reported in chat this session

-- `stack`, where known, is where the error came from, trimmed so the file stays small.
local STACK_CHARS = 800
function ns.fail(name, err, stack)
	local e = errors[name] or { n = 0 }
	errors[name] = e
	e.n = e.n + 1
	e.msg = tostring(err)
	e.stack = type(stack) == "string" and string.sub(stack, 1, STACK_CHARS) or nil
	e.t = GetServerTime()
	if not told[name] then
		told[name] = true
		ns.say(name .. " failed: " .. tostring(err))
	end
end

-- The outermost call in flight and the frame it began in. The client stops a script that runs too long
-- without an error the addon can catch ("has exceeded its execution time limit", no stack): that call
-- never returns, so the next one, in a later frame, finds it still marked and counts it in
-- the save (manual test run 001: 112 of them in a delve, no name). /gf check lists them.
local running, runningAt, depth = nil, nil, 0
local countStopped -- the Store's count of a stopped call, once the save is loaded
local function stoppedBefore(now)
	if depth > 0 and runningAt ~= now then
		if countStopped then
			countStopped(running)
		end
		depth = 0
	end
end

-- The stack of the last error, read in the error handler while it still exists. The client's debugstack
-- leaves out the handler itself; debug.traceback elsewhere.
local lastStack
local function withStack(err)
	if debugstack then
		lastStack = debugstack(2, 12, 0)
	elseif debug and debug.traceback then
		lastStack = debug.traceback("", 2)
	end
	return err
end
-- The client's xpcall passes arguments on to the call; a plain Lua 5.1's does not, and a call with
-- some goes through a closure there.
local passesArgs = select(2, xpcall(function(a)
	return a
end, withStack, true)) == true

-- Runs fn(...) and records an error, with its stack, instead of raising it.
function ns.safely(name, fn, ...)
	local now = GetTime and GetTime() or 0
	stoppedBefore(now)
	if depth == 0 then
		running, runningAt = name, now
	end
	depth = depth + 1
	local ok, err
	if passesArgs or select("#", ...) == 0 then
		ok, err = xpcall(fn, withStack, ...)
	else
		local args, n = { ... }, select("#", ...)
		ok, err = xpcall(function()
			return fn(unpack(args, 1, n))
		end, withStack)
	end
	depth = depth - 1
	if not ok then
		local stack = lastStack
		lastStack = nil
		ns.fail(name, err, stack)
	end
	return ok
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

-- From the save's loading on (Store/Save.lua), errors are recorded in it, those from before with them, and
-- each stopped call is counted by `stopped(name)`.
function ns.recordErrorsIn(saved, stopped)
	for name, e in pairs(errors) do
		saved[name] = e
	end
	errors = saved
	countStopped = stopped
end

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
