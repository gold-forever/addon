-- Gold Forever: what the in-game pages show, worked out from the saved file: a stream's rows, characters
-- and rested XP, levelling, and how times and numbers read. Pure Lua 5.1 with no game API, so it can be
-- tested outside the client; the same rules as the web app's (rested.ts, levelling). The rest of ns.Views,
-- by what it is about: ViewsMoney.lua, ViewsSession.lua and ViewsItems.lua.

local _, ns = ...
ns = ns or {}

local Views = {}
ns.Views = Views

-- Classic Era's rested rules, as the web app has them (not yet verified on Forever): 5% of a level
-- every 8 hours at an inn, a quarter of that elsewhere, at most 1.5 levels.
Views.RESTED_GAIN_PER_8H = 0.05
Views.RESTED_OUTSIDE_FACTOR = 0.25
Views.RESTED_CAP_LEVELS = 1.5

-- Gaps between XP gains longer than this are time away, not play.
Views.PLAY_GAP = 600

-- "a,,b" -> { "a", "", "b" }: empty columns kept.
local function split(row)
	local out = {}
	for value in string.gmatch(row .. ",", "([^,]*),") do
		out[#out + 1] = value
	end
	return out
end

-- A stream's rows across every saved day, each as { column = value } by the declared columns, in
-- time order. Numbers stay strings; the callers convert what they use. With `char` only that
-- character's rows, and with `from` only rows from then on: the others are passed over before they
-- are split (every stream starts "t,char"), which on two weeks of rows is most of the work.
function Views.rows(db, stream, char, from)
	local names = {}
	for name in string.gmatch(db.fields and db.fields[stream] or "", "[^,]+") do
		names[#names + 1] = name
	end
	local out = {}
	for _, bucket in pairs(db.events or {}) do
		for _, chunk in ipairs(bucket[stream] or {}) do
			for row in string.gmatch(chunk, "[^;]+") do
				if char or from then
					local t, c = string.match(row, "^(%d*),(%d*)")
					if (char and tonumber(c) ~= char) or (from and (tonumber(t) or 0) < from) then
						row = nil
					end
				end
				if row then
					local values, r = split(row), {}
					for i, name in ipairs(names) do
						r[name] = values[i] ~= "" and values[i] or nil
					end
					r.t = tonumber(r.t) or 0
					r.char = tonumber(r.char)
					out[#out + 1] = r
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

-- Rested XP now for a character saved with xp = { cur, max, rested, resting, t }: as read when it is
-- the one online, else grown since its save by the rules above. Returns rested, cap.
function Views.rested(xp, now, online)
	if not xp or not xp.max or xp.max <= 0 then
		return 0, 0
	end
	local cap = xp.max * Views.RESTED_CAP_LEVELS
	local rested = math.min(xp.rested or 0, cap)
	if online then
		return rested, cap
	end
	local factor = xp.resting and 1 or Views.RESTED_OUTSIDE_FACTOR
	local perSecond = xp.max * Views.RESTED_GAIN_PER_8H * factor / (8 * 3600)
	return math.min(cap, rested + perSecond * math.max(0, now - (xp.t or now))), cap
end

-- Every character as a row (`display` is its name with its surname, and its realm when that is not
-- enough to tell it apart), and the one to play next: the most rested XP waiting in levels, among
-- those not online and not at the cap. db.characters is keyed by GUID; `online` is the one playing.
function Views.characters(characters, now, online)
	local rows, best = {}, nil
	for guid, c in pairs(characters or {}) do
		local isOnline = guid == online
		local rested = Views.rested(c.xp, now, isOnline)
		local row = {
			guid = guid,
			name = c.name or "?",
			class = c.class,
			faction = c.faction,
			level = c.level or 0,
			money = c.money or 0,
			progress = c.xp and c.xp.max and c.xp.max > 0 and c.xp.cur / c.xp.max or nil,
			restedLevels = c.xp and c.xp.max and c.xp.max > 0 and rested / c.xp.max or nil,
			seen = isOnline and now or c.seen,
			online = isOnline,
		}
		row.display = c.surname and c.surname ~= "" and (row.name .. " " .. c.surname) or row.name
		row.realm = c.realm
		rows[#rows + 1] = row
		if row.restedLevels and not isOnline and (not best or row.restedLevels > best.restedLevels) then
			best = row
		end
	end
	-- Names still shared (no surname, another realm) get the realm after them.
	local seen = {}
	for _, r in ipairs(rows) do
		seen[r.display] = (seen[r.display] or 0) + 1
	end
	for _, r in ipairs(rows) do
		if seen[r.display] > 1 and r.realm then
			r.display = r.display .. " · " .. r.realm
		end
	end
	return rows, best
end

-- One character's levelling from its level and XP rows:
-- { levels = { { level, seconds, reached, money } }, sources = { [kind] = xp }, xp, rested,
--   playSeconds, perHour }. A level's time is from /played: each row knows when its level started
-- (played - levelPlayed), so a level lasted from its start to the next one's.
function Views.levelling(levelRows, xpRows, ref)
	local starts, reached = {}, {}
	for _, r in ipairs(levelRows or {}) do
		if r.char == ref then
			local level, played, levelPlayed = tonumber(r.level), tonumber(r.played), tonumber(r.levelPlayed)
			if level and played and levelPlayed then
				starts[level] = starts[level] or (played - levelPlayed)
			end
			if level and r.kind == "up" then
				reached[level] = { t = r.t, money = tonumber(r.money) }
			end
		end
	end
	local out = { levels = {}, sources = {}, xp = 0, rested = 0, playSeconds = 0 }
	for level, start in pairs(starts) do
		local nextStart = starts[level + 1]
		local seconds = nextStart and nextStart >= start and (nextStart - start) or nil
		if seconds or reached[level] then
			out.levels[#out.levels + 1] = {
				level = level,
				seconds = seconds,
				reached = reached[level] and reached[level].t,
				money = reached[level] and reached[level].money,
			}
		end
	end
	for level, r in pairs(reached) do
		if not starts[level] then
			out.levels[#out.levels + 1] = { level = level, reached = r.t, money = r.money }
		end
	end
	table.sort(out.levels, function(a, b)
		return a.level > b.level
	end)

	local last
	for _, r in ipairs(xpRows or {}) do
		local xp = tonumber(r.xp)
		if r.char == ref and xp and xp > 0 then
			local kind = r.kind or "other"
			out.sources[kind] = (out.sources[kind] or 0) + xp
			out.xp = out.xp + xp
			out.rested = out.rested + (tonumber(r.rested) or 0)
			if last and r.t - last <= Views.PLAY_GAP then
				out.playSeconds = out.playSeconds + (r.t - last)
			end
			last = r.t
		end
	end
	out.perHour = out.playSeconds >= 300 and out.xp / out.playSeconds * 3600 or nil
	return out
end

-- "2d 4h", "3h 12m", "45m", "under a minute".
function Views.duration(seconds)
	if not seconds then
		return "-"
	end
	seconds = math.floor(seconds)
	local d, h, m = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60
	if d > 0 then
		return h > 0 and string.format("%dd %dh", d, h) or string.format("%dd", d)
	elseif h > 0 then
		return m > 0 and string.format("%dh %dm", h, m) or string.format("%dh", h)
	elseif m > 0 then
		return string.format("%dm", m)
	end
	return "under a minute"
end

-- "now", "12m ago", "3h ago", "2d ago".
function Views.ago(t, now)
	if not t then
		return "-"
	end
	local s = now - t
	if s < 60 then
		return "now"
	end
	return Views.duration(s < 3600 and s or s < 86400 and math.floor(s / 3600) * 3600 or math.floor(s / 86400) * 86400) .. " ago"
end

-- "12.3k" for the HUD: thousands with one decimal, millions likewise, smaller numbers whole.
function Views.short(n)
	n = n or 0
	if n >= 1e6 then
		return string.format("%.1fm", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fk", n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end

-- The start of the server's UTC day that `t` falls in, as the saved days are bucketed.
function Views.dayStart(t)
	return t - t % 86400
end

-- A gold goal on Home: gold now (copper, all characters) against goal = { gold (copper), by (Unix time) }.
-- Returns { pct (0–100), left (copper still to make), daysLeft, perDay (copper a day to make it, nil once
-- reached or past), reached, late }.
function Views.goal(now, total, goal)
	local pct = goal.gold > 0 and math.min(100, math.floor(total / goal.gold * 100)) or 100
	local left = math.max(0, goal.gold - total)
	local daysLeft = math.max(0, math.ceil((goal.by - now) / 86400))
	local reached = left == 0
	local late = not reached and now >= goal.by
	return { pct = pct, left = left, daysLeft = daysLeft, reached = reached, late = late,
		perDay = (not reached and not late) and math.ceil(left / math.max(1, daysLeft)) or nil }
end

-- n lines in room rows: all of them when they fit, else room - 1 and a last row for the rest. Returns how
-- many show and how many are left for "+N more".
function Views.fit(n, room)
	if n <= room then
		return n, 0
	end
	return room - 1, n - room + 1
end

-- How many character rows (Views.characters) are at the level cap: by level, not by the XP missing, which
-- a character not yet read has missing too.
function Views.capped(rows, maxLevel)
	local n = 0
	for _, r in ipairs(rows) do
		if (r.level or 0) >= maxLevel then
			n = n + 1
		end
	end
	return n
end
