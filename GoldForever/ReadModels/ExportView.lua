-- Gold Forever: what the export window reads from the save (design 005); what was sent is recorded by
-- the Store (Export.recordSent).

local _, ns = ...
local Export = ns.Export

local ExportView = {}
ns.ExportView = ExportView

-- Export.builder over the save: what is new since the last export, or with `all` everything again.
function ExportView.builder(all, now, deflate)
	local db = ns.db()
	return Export.builder(db, not all and db.exportedAt or nil, now, deflate)
end
