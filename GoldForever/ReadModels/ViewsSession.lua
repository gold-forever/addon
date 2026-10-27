-- Gold Forever: what farming shows (ns.Views): the session HUD's rates, a mob's loot worth and the rares
-- seen. Pure Lua 5.1, as Views.lua.

local _, ns = ...
local Views = ns.Views

-- The session HUD's numbers (design 009, Session module) from a session { coin, xp, killXp, kills } that
-- has run `elapsed` seconds, its loot worth `value`, and `toLevel` XP to the next level (0 or less at the
-- cap). No rate in the first minute: one lucky drop is not a rate. dingIn is seconds at this XP pace;
-- killsToLevel at this session's XP a kill.
Views.SESSION_MIN_RATE = 60

function Views.sessionRates(s, elapsed, value, toLevel)
	local total = (s.coin or 0) + (value or 0)
	local r = { total = total, rated = elapsed >= Views.SESSION_MIN_RATE }
	if r.rated then
		r.goldPerHour = total * 3600 / elapsed
		r.xpPerHour = (s.xp or 0) * 3600 / elapsed
		r.killsPerHour = (s.kills or 0) * 3600 / elapsed
		if r.xpPerHour > 0 and toLevel and toLevel > 0 then
			r.dingIn = toLevel / r.xpPerHour * 3600
		end
	end
	-- XP a kill from the kills that gave XP (grey mobs give none and count only as kills).
	local xpKills = s.xpKills or s.kills or 0
	if xpKills > 0 and (s.killXp or 0) > 0 and toLevel and toLevel > 0 then
		r.killsToLevel = math.ceil(toLevel / (s.killXp / xpKills))
	end
	return r
end

-- What one loot of an NPC is worth, from its counts ({ loots, coin, items = { [id] = { dropped, units } } },
-- ns.mobStats): its coin and every unit at `worth(id)`, an item without a price as nothing; nil for an
-- NPC never looted.
function Views.mobValue(m, worth)
	if not m or m.loots <= 0 then
		return nil
	end
	local value = m.coin
	for id, d in pairs(m.items) do
		value = value + (worth(id) or 0) * d.units
	end
	return value / m.loots
end

-- The rares seen, one row each from the rare stream's rows ({ t, npc, map, x, y, how }): how often, the
-- last sighting's time, place and how it was seen; the latest first.
function Views.rares(rows)
	local by, out = {}, {}
	for _, r in ipairs(rows or {}) do
		local npc = tonumber(r.npc)
		if npc then
			local e = by[npc]
			if not e then
				e = { npc = npc, seen = 0, last = 0 }
				by[npc] = e
				out[#out + 1] = e
			end
			e.seen = e.seen + 1
			if r.t >= e.last then
				e.last, e.map, e.x, e.y, e.how = r.t, tonumber(r.map), tonumber(r.x), tonumber(r.y), r.how
			end
		end
	end
	table.sort(out, function(a, b)
		return a.last > b.last
	end)
	return out
end
