-- Gold Forever: what the hub's Ledger tabs show from the save: money in and out, the characters,
-- everything they hold, and the auction sales.

local _, ns = ...
local Encode, Views = ns.Encode, ns.Views

local LedgerView = {}
ns.LedgerView = LedgerView

-- The days the save keeps, which the Ledger's tabs cover.
LedgerView.DAYS = 14

-- This character's reference for whose = "me", nil (every character) for "all".
local function refOf(whose)
	local me = ns.me()
	return whose == "me" and me and me.ref or nil
end

-- The Money tab: Views.ledger over the save's days, with the net a day by Encode.day.
function LedgerView.money(whose, now)
	local db, ref, from = ns.db(), refOf(whose), now - LedgerView.DAYS * 86400
	return Views.ledger(Views.rows(db, "money", ref, from), Views.rows(db, "flight"), ref, from, Encode.day)
end

-- The Characters tab: Views.characters, `online` the GUID playing.
function LedgerView.characters(now, online)
	return Views.characters(ns.db().characters, now, online)
end

-- The characters to choose from: { { guid, name } }.
function LedgerView.characterNames()
	local out = {}
	for guid, c in pairs(ns.db().characters or {}) do
		out[#out + 1] = { guid = guid, name = c.name or "?" }
	end
	return out
end

-- The Inventory tab: Views.inventory over every character.
function LedgerView.inventory(worth, quality, name, filter, vendor)
	return Views.inventory(ns.db().characters, Encode.parseItems, worth, quality, name, filter, vendor)
end

-- The Auction sales tab: Views.sales over the save's days, and the characters' names by reference.
function LedgerView.sales(whose, now)
	local db, ref, from = ns.db(), refOf(whose), now - LedgerView.DAYS * 86400
	local names = {}
	for _, c in pairs(db.characters or {}) do
		if c.ref then
			names[tonumber(c.ref) or c.ref] = c.name
		end
	end
	return Views.sales(Views.rows(db, "sale", ref, from), ref, from), names
end
