-- Gold Forever: the auction mail helper (owner's answer, 2026-10-24): beside the mailbox, one press
-- opens all the auction house's mail, sold gold, bought, expired, cancelled and outbid items, one mail
-- after the other as fast as the server takes them (manual test run 001: ten a press, at least 0.3 s
-- apart, was slow next to other mail tools), stopping when the bags are full. A player's letter,
-- and any mail asking for cash on delivery, is never touched. These are its rules; the panel beside the
-- mailbox is MailPanel.lua.

local _, ns = ...
ns = ns or {}

local Mail = {}
ns.Mail = Mail

Mail.BATCH = 500 -- mails a press: all of them (a guard against a loop, not a limit)

-- The auction house's subjects as the client words them ("Auction successful: %s"), English fallbacks
-- for the tests; as Lua patterns that match the whole subject.
function Mail.patterns(formats)
	formats = formats or {
		AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s",
		AUCTION_REMOVED_MAIL_SUBJECT or "Auction canceled: %s",
		AUCTION_WON_MAIL_SUBJECT or "Auction won: %s",
		AUCTION_OUTBID_MAIL_SUBJECT or "Outbid on %s",
	}
	local out = {}
	for _, f in ipairs(formats) do
		-- Escape the pattern's magic characters, then let %s stand for anything.
		local escaped = string.gsub(f, "([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
		out[#out + 1] = "^" .. string.gsub(escaped, "%%%%s", ".+") .. "$"
	end
	return out
end

function Mail.isAuction(subject, patterns)
	if type(subject) ~= "string" then
		return false
	end
	for _, p in ipairs(patterns) do
		if string.find(subject, p) then
			return true
		end
	end
	return false
end

-- The next auction mail to open from the inbox's headers ({ subject, money, cod, items, canReply }), in
-- order: one with something to take, no cash on delivery, and items only while the bags have room for
-- them. A letter that can be answered is a player's, whatever its subject says: never opened.
-- Returns its index, or nil and why ("none" or "bags").
function Mail.next(headers, freeSlots, patterns)
	local blocked = false
	for i, h in ipairs(headers) do
		if Mail.isAuction(h.subject, patterns) and not h.canReply and (h.cod or 0) == 0 and ((h.money or 0) > 0 or (h.items or 0) > 0) then
			if (h.items or 0) == 0 or (h.items or 0) <= freeSlots then
				return i
			end
			blocked = true
		end
	end
	return nil, blocked and "bags" or "none"
end
