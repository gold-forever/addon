-- Gold Forever: what the "Held" line in item tooltips reads from the save (owner's answer, 2026-10-24): how
-- many every character holds, from what the save has of their bags, bank and mail. The index is built
-- again only when one of those changed.

local _, ns = ...
local Encode, Views = ns.Encode, ns.Views

local HeldView = {}
ns.HeldView = HeldView

local held, heldStamp
local function stamp()
	local sum, n = 0, 0
	for _, c in pairs(ns.db().characters or {}) do
		n = n + 1
		for _, place in ipairs(Views.PLACES) do
			sum = sum + (c[place] and c[place].t or 0)
		end
	end
	return sum * 1000 + n
end

-- The "Held" line for item `id` (Views.heldText), nil when nobody holds it.
function HeldView.line(id)
	local now = stamp()
	if not held or heldStamp ~= now then
		held, heldStamp = Views.holdings(ns.db().characters, Encode.parseItems), now
	end
	return Views.heldText(held[id])
end
