-- Gold Forever: what the hub's Home page shows from the save: the gold across the characters, today's
-- money for this one, and what its bags would sell for.

local _, ns = ...
local Encode, Views = ns.Encode, ns.Views

local HomeView = {}
ns.HomeView = HomeView

-- At `now`, with worth(id) a unit's price: { gold (copper, every character), today (Views.ledger of this
-- character's money since the day's start), bags = { list, total, unpriced } (Views.bagWorth) }.
function HomeView.home(now, worth)
	local db, me = ns.db(), ns.me()
	local gold = 0
	for _, c in pairs(db.characters or {}) do
		gold = gold + (c.money or 0)
	end
	local from = Views.dayStart(now)
	local today = me and Views.ledger(Views.rows(db, "money", me.ref, from), Views.rows(db, "flight"), me.ref, from) or { categories = {}, net = 0 }
	local list, total, unpriced = Views.bagWorth(me and me.bags, Encode.parseItems, worth)
	return { gold = gold, today = today, bags = { list = list, total = total, unpriced = unpriced } }
end
