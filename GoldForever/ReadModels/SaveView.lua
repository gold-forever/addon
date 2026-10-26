-- Gold Forever: what the windows read about the save itself: whether it is loaded, whether the install is
-- new, and the addon version that loaded it.

local _, ns = ...

local SaveView = {}
ns.SaveView = SaveView

-- Whether the save is loaded: nil until the addon has loaded.
function SaveView.loaded()
	return ns.db() ~= nil
end

-- Whether this install is new: nothing in the save from an earlier session.
function SaveView.isNew()
	return next(ns.db().characters or {}) == nil
end

-- The addon version that loaded the save; nil before the addon has loaded.
function SaveView.addon()
	local db = ns.db()
	return db and db.addon
end
