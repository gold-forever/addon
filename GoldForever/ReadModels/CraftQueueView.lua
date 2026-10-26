-- Gold Forever: what the craft queue window reads from the save: the guild bank as last read, and what
-- the other characters hold of the reagents.

local _, ns = ...
local Encode, Views = ns.Encode, ns.Views

local CraftQueueView = {}
ns.CraftQueueView = CraftQueueView

-- The guild bank of character `me`'s guild `guild`, as last read: counts by item; empty without either.
function CraftQueueView.guildCounts(me, guild)
	local out = {}
	if not me or not guild then
		return out
	end
	local bank = ns.db().guildBanks[ns.market(string.lower(me.faction or "?")) .. ":" .. guild]
	for _, tab in pairs(bank and bank.tabs or {}) do
		for id, n in pairs(Encode.parseItems(tab.items)) do
			out[id] = (out[id] or 0) + n
		end
	end
	return out
end

-- What each other character holds of the items in `needs` (a set of item IDs): { [id] = { { name, total } } },
-- most first (Views.holdingsOf). `me` is left out itself, not by name: an alt of the same name on another
-- realm is another character.
function CraftQueueView.others(needs, me)
	local others = {}
	for id, e in pairs(Views.holdingsOf(ns.db().characters, Encode.parseItems, needs, me)) do
		local list = {}
		for _, h in ipairs(e.by) do
			list[#list + 1] = { name = h.name, total = h.total }
		end
		others[id] = list
	end
	return others
end
