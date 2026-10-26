-- Gold Forever: what the windows read about the save itself.

local _, ns = ...

local SaveView = {}
ns.SaveView = SaveView

-- Whether this install is new: nothing in the save from an earlier session.
function SaveView.isNew()
	return next(ns.db().characters or {}) == nil
end
