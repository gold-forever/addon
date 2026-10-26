-- Gold Forever: what the hub's Session tabs show from the save: the character levelling and how.

local _, ns = ...
local Views = ns.Views

local SessionView = {}
ns.SessionView = SessionView

-- The Levelling tab: this character ({ name, class, level, xp = { cur, max, rested } }, xp nil at the
-- level cap) and its levelling (Views.levelling); nil before the character is known.
function SessionView.levelling()
	local me, db = ns.me(), ns.db()
	if not me then
		return nil
	end
	local xp = me.xp and { cur = me.xp.cur, max = me.xp.max, rested = me.xp.rested }
	return {
		character = { name = me.name, class = me.class, level = me.level, xp = xp },
		levelling = Views.levelling(Views.rows(db, "level", me.ref), Views.rows(db, "xp", me.ref), me.ref),
	}
end
