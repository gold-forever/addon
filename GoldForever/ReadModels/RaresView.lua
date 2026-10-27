-- Gold Forever: what the hub's Rares page shows, from the save: every rare the characters have seen and
-- what a loot of it has been worth.

local _, ns = ...
local Views = ns.Views

local RaresView = {}
ns.RaresView = RaresView

-- Views.rares' rows, each with `value`: what a loot of the rare is worth from the mobs' loot counts
-- (ns.mobStats' mobs, at `worth`), nil while they are counted or for a rare never looted.
function RaresView.rows(mobs, worth)
	local rows = Views.rares(Views.rows(ns.db(), "rare"))
	for _, r in ipairs(rows) do
		r.value = Views.mobValue(mobs and mobs[r.npc], worth)
	end
	return rows
end
