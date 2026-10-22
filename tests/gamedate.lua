-- The game's global date, for every test (run.js loads it into each test's Lua state).
-- The game has os.date as the global date. fengari lacks the "!" (UTC) prefix and formats in the
-- machine's local time, so a "!" format is worked out here from the epoch itself: the tests then hold
-- in every time zone, as the game's UTC day keys do.
local function utc(t)
	local days, secs = math.floor(t / 86400), t % 86400
	-- Days since 1970-01-01 to a civil date (Howard Hinnant's algorithm).
	local z = days + 719468
	local era = math.floor(z / 146097)
	local doe = z - era * 146097
	local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
	local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
	local mp = math.floor((5 * doy + 2) / 153)
	local d = doy - math.floor((153 * mp + 2) / 5) + 1
	local m = mp < 10 and mp + 3 or mp - 9
	local y = yoe + era * 400 + (m <= 2 and 1 or 0)
	return { Y = y, m = m, d = d, H = math.floor(secs / 3600), M = math.floor(secs % 3600 / 60), S = secs % 60 }
end

date = function(format, t)
	if format:sub(1, 1) ~= "!" then
		return os.date(format, t)
	end
	local f = utc(t or os.time())
	return (format:sub(2):gsub("%%(.)", function(c)
		if c == "Y" then
			return string.format("%04d", f.Y)
		elseif f[c] then
			return string.format("%02d", f[c])
		elseif c == "%" then
			return "%"
		end
		error("the test's UTC date does not know %" .. c, 2)
	end))
end
