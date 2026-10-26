-- Gold Forever: what the export window reads from the save, and its mark of what was sent (design 005).

local _, ns = ...
local Export = ns.Export

local ExportView = {}
ns.ExportView = ExportView

-- Export.builder over the save: what is new since the last export, or with `all` everything again.
function ExportView.builder(all, now, deflate)
	local db = ns.db()
	return Export.builder(db, not all and db.exportedAt or nil, now, deflate)
end

-- What an export built at `now` held (`picked`, as Export.builder hands it) counts as sent: the next
-- export starts from it.
function ExportView.sent(picked, now)
	local db = ns.db()
	db.exportedAt = now
	Export.markSent(db, picked)
end
