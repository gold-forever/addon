-- Gold Forever: the HUD's levelling pace (gf#379), "Level 28 in ~41m · 38k XP/h · rested 12%". XP an hour
-- over the last 15 minutes of play, from every XP gain Levelling.lua tells of (kills, quests, discovery,
-- the rest); time AFK is not play. Kept in memory: a login or a /reload starts it again. Pure Lua 5.1.

local _, ns = ...
local L = ns.L

local Pace = {}
ns.HudPace = Pace

Pace.WINDOW = 15 * 60 -- seconds of play the rate covers
Pace.MIN_PLAY = 2 * 60 -- seconds of play before there is a rate

-- A pace started at `now` (GetTime): the play clock, whether the player was AFK when last seen, and the
-- gains, each { play, xp }, oldest first.
function Pace.new(now)
	return { play = 0, at = now, afk = false, gains = {} }
end

-- The play clock moved on to `now`: the time since it was last seen counts unless the player was AFK.
function Pace.tick(p, now, afk)
	if not p.afk then
		p.play = p.play + math.max(0, now - p.at)
	end
	p.at, p.afk = now, afk and true or false
	while p.gains[1] and p.gains[1].play <= p.play - Pace.WINDOW do
		table.remove(p.gains, 1)
	end
end

function Pace.gain(p, now, afk, xp)
	Pace.tick(p, now, afk)
	p.gains[#p.gains + 1] = { play = p.play, xp = xp }
end

-- XP an hour over the last 15 minutes of play (or all of it, when less), nil under 2 minutes.
function Pace.rate(p, now, afk)
	Pace.tick(p, now, afk)
	if p.play < Pace.MIN_PLAY then
		return nil
	end
	local xp = 0
	for _, g in ipairs(p.gains) do
		xp = xp + g.xp
	end
	return xp * 3600 / math.min(p.play, Pace.WINDOW)
end

-- What the line shows from the XP bar ({ level, cur, max, rested, atCap }): the rate, the seconds to the
-- next level at it, and the rested XP left in percent of the level; nil at the cap, where it is hidden.
function Pace.status(p, now, afk, bar)
	if bar.atCap or not bar.max or bar.max <= 0 then
		return nil
	end
	local rate = Pace.rate(p, now, afk)
	local left = bar.max - bar.cur
	return {
		level = bar.level,
		rate = rate,
		eta = rate and rate > 0 and left / rate * 3600 or nil,
		rested = math.floor((bar.rested or 0) * 100 / bar.max + 0.5),
	}
end

function Pace.line(st, Views)
	local dash = "-"
	local eta = st.eta and ("~" .. Views.duration(st.eta)) or dash
	local rate = st.rate and Views.short(st.rate) or dash
	return string.format(L["Level %d in %s"], st.level + 1, eta) .. " · " .. rate .. L[" XP/h"]
		.. " · " .. string.format(L["rested %d%%"], st.rested)
end

-- Whether the line shows in its mode ("off", "shift" or "always", as a tooltip line's), Shift held or not.
function Pace.shown(mode, shift)
	if mode == "off" then
		return false
	elseif mode == "shift" then
		return shift and true or false
	end
	return true
end
