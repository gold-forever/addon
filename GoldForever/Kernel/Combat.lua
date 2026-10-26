-- Gold Forever: combat safety. What must not run in combat (a binding, a protected frame, a move of items)
-- asks ns.afterCombat, which runs it now or once when the fight ends; ns.inCombat says whether one is on.

local _, ns = ...

-- From the fight's start (PLAYER_REGEN_DISABLED, a moment before the client locks the UI) to its end; and
-- whenever the client locks the UI, as after a reload in combat, when no start was seen.
local fighting = false
local endedAt = -math.huge
local waiting = {} -- { { name, fn } } in the order first asked
local queued = {} -- fn -> true while it waits

function ns.inCombat()
	return fighting or (InCombatLockdown ~= nil and InCombatLockdown()) or false
end

-- GetTime() when the last fight ended.
function ns.combatEnded()
	return endedAt
end

-- fn now out of combat; in combat, once when it ends however often it was asked for.
function ns.afterCombat(name, fn)
	if not ns.inCombat() then
		ns.safely(name, fn)
		return
	end
	if not queued[fn] then
		queued[fn] = true
		waiting[#waiting + 1] = { name = name, fn = fn }
	end
end

ns.on("PLAYER_REGEN_DISABLED", "combat", function()
	fighting = true
end)
ns.on("PLAYER_REGEN_ENABLED", "combat", function()
	fighting = false
	endedAt = GetTime()
	local due = waiting
	waiting, queued = {}, {}
	for _, w in ipairs(due) do
		ns.safely(w.name, w.fn)
	end
end)
