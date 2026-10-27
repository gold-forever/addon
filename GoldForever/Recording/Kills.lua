-- Gold Forever: kills without the combat log (forbidden on Forever), for the farming session (Session.lua).
-- Pure Lua 5.1, so it is tested outside the client.

local _, ns = ...

local Kills = {}
ns.Kills = Kills

-- Kills in one fight without the combat log (design 009; the playground's killsInFight): when the fight
-- closes (combat over and a few seconds to loot), the larger of its kill-XP gains and the creature
-- corpses looted for the first time. A corpse looted again is no new kill; a grey mob gives no XP but its
-- corpse counts; a chest or herb (not a creature) never does. `seen` (guid -> true) is updated in place.
-- Kills to add for a closed fight (or a loot or kill XP outside any), across fights: a kill credited
-- by its XP whose corpse is looted later, after its fight closed or inside the next one, is not counted
-- again. `pending` holds the times of XP kills with no corpse yet; a fresh corpse first matches one of
-- those (from the last MATCH_SECONDS), then counts as a kill of its own. Returns the kills to add.
Kills.MATCH_SECONDS = 120
function Kills.credit(pending, xpKills, corpses, seen, now)
	for i = #pending, 1, -1 do
		if now - pending[i] > Kills.MATCH_SECONDS then
			table.remove(pending, i)
		end
	end
	local fresh = 0
	for _, guid in ipairs(corpses or {}) do
		if string.find(guid, "^Creature%-") and not seen[guid] then
			seen[guid] = true
			fresh = fresh + 1
		end
	end
	local matched = math.min(fresh, #pending)
	for _ = 1, matched do
		table.remove(pending, 1)
	end
	fresh = fresh - matched
	for _ = 1, (xpKills or 0) - fresh do
		pending[#pending + 1] = now
	end
	return math.max(xpKills or 0, fresh)
end
