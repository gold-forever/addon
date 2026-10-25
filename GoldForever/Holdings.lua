-- Gold Forever: what this character holds of an item, bags, bank and mailbox, and the purchases made
-- since the mailbox was last read.

local _, ns = ...
local settings = ns.auctionSettings

local Holdings = {}
ns.Holdings = Holdings

-- The bank's and mailbox's item strings, parsed once each time they change (not once per row).
local bankParsed, mailParsed = {}, {}
local function parsedOnce(cache, text)
	if text ~= cache.text then
		cache.text, cache.items = text, ns.Encode.parseItems(text)
	end
	return cache.items
end

-- What this character holds of an item, bags and bank (decision 12: keep counts per character).
function Holdings.heldHere(id, inBags)
	local me = ns.me()
	local bank = me and me.bank and parsedOnce(bankParsed, me.bank.items)[id] or 0
	-- The mailbox as last read, and what was bought since (it goes to the mailbox on retail).
	local mail = me and me.mail and parsedOnce(mailParsed, me.mail.items)[id] or 0
	local boughtSince = ns.boughtSince and ns.boughtSince(id) or 0
	return (inBags or 0) + bank + mail + boughtSince
end

-- What was bought since the mailbox was last read, for the craft queue: retail sends a purchase to the
-- mailbox, so the bags do not show it (manual test run 001: a reagent bought stayed on the Craft queue
-- list). settings().bought = { { id, n, t } }; dropped once the mailbox has been read after it.
function Holdings.recordBought(b)
	local s = settings()
	s.bought = s.bought or {}
	s.bought[#s.bought + 1] = { id = b.id, n = b.n, t = ns.now() }
end
-- Units of an item bought and not in the mailbox as read yet. A read: the save changes only when the
-- mailbox is read (below).
function ns.boughtSince(id)
	local me = ns.me()
	local mailAt = me and me.mail and me.mail.t or 0
	local n = 0
	for _, b in ipairs(settings().bought or {}) do
		if b.t > mailAt and b.id == id then
			n = n + b.n
		end
	end
	return n
end
-- Purchases from before the mailbox was last read are in it (or the bags) by now: dropped from the save,
-- once the mailbox has been read (Inventory.lua reads it on the same event, at the same pace).
ns.on("MAIL_INBOX_UPDATE", "bought", ns.throttle("bought", 2, function()
	local me = ns.me()
	local list = settings().bought
	local mailAt = me and me.mail and me.mail.t
	if not (list and mailAt) then
		return
	end
	for i = #list, 1, -1 do
		if list[i].t <= mailAt then
			table.remove(list, i)
		end
	end
end))
