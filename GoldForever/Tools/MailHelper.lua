-- Gold Forever: the auction mail helper (owner's answer, 2026-10-24): beside the mailbox, one press
-- opens all the auction house's mail, sold gold, bought, expired, cancelled and outbid items, one mail
-- after the other as fast as the server takes them (manual test run 001: ten a press, at least 0.3 s
-- apart, was slow next to other mail tools), stopping when the bags are full. A player's letter,
-- and any mail asking for cash on delivery, is never touched. These are its rules and the batch that
-- opens the mail; the batch says what the panel beside the mailbox (MailPanel.lua) shows with the
-- "mailBatch" message.

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

-- Seconds between the inbox's update after a take and the next take, and between checks while the
-- server is busy. 0.05 on the take's own answer was too soon (manual test run 001: three mails, then the
-- mailbox refused the next and the press ended): the inbox must have dropped the mail first.
local GAP = 0.15
local RETRIES = 3 -- a refused take is tried again, a second apart, this many times
local WAIT = 0.5 -- seconds to wait for an answer the client never sends

local patterns
local run -- a batch in progress: { left, waiting, failed, next }

local function auctionPatterns()
	patterns = patterns or Mail.patterns()
	return patterns
end

local function headers()
	local out = {}
	for i = 1, (GetInboxNumItems and GetInboxNumItems() or 0) do
		local _, _, _, subject, money, cod, _, items, _, _, _, canReply = GetInboxHeaderInfo(i)
		out[i] = { subject = subject, money = money or 0, cod = cod or 0, items = items or 0, canReply = canReply }
	end
	return out
end

local function freeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, kind = C_Container.GetContainerNumFreeSlots(bag)
		if (kind or 0) == 0 then
			free = free + (n or 0)
		end
	end
	return free
end

-- How much auction mail waits: mails, gold, items.
function Mail.waiting()
	local n, gold, items = 0, 0, 0
	for _, h in ipairs(headers()) do
		if Mail.isAuction(h.subject, auctionPatterns()) and not h.canReply and h.cod == 0 then
			n, gold, items = n + 1, gold + h.money, items + h.items
		end
	end
	return n, gold, items
end

function Mail.running()
	return run ~= nil
end

-- The batch ended, with what the panel says.
local function finish(note)
	run = nil
	ns.emit("mailBatch", note)
end

-- The batch's next step after `seconds`. Each call replaces the one still waiting, so one take runs at a
-- time: a take's own timeout cannot start a take beside the next (review B-3).
local step
local function later(seconds)
	local mine, token = run, {}
	run.next = token
	C_Timer.After(seconds, function()
		if run == mine and mine.next == token then
			mine.next = nil
			ns.safely("mail helper", step)
		end
	end)
end

-- One step of a batch: the next auction mail opened, then the next once the inbox has changed.
function step()
	if not run then
		return
	end
	local index, why = Mail.next(headers(), freeSlots(), auctionPatterns())
	if not index or run.left <= 0 then
		-- The client shows 50 mails at a time; the rest arrive when the mailbox refreshes.
		local shown, total = GetInboxNumItems()
		local more = total and shown and total > shown and (total - shown) or 0
		finish(why == "bags" and "Your bags are full: make room and press again."
			or more > 0 and string.format("All shown auction mail opened. %d more %s arrive when the mailbox refreshes (within a minute): press again then.", more, more == 1 and "mail" or "mails")
			or "All auction mail opened.")
		return
	end
	-- One mail at a time, as Blizzard's Open All does: not while the server still works on the last.
	if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
		later(GAP)
		return
	end
	run.left = run.left - 1
	run.waiting = true
	if AutoLootMailItem then
		AutoLootMailItem(index)
	else
		TakeInboxMoney(index)
		-- Attachment slots can have gaps: every slot, from the last.
		for a = ATTACHMENTS_MAX_RECEIVE or 16, 1, -1 do
			if not HasInboxItem or HasInboxItem(index, a) then
				TakeInboxItem(index, a)
			end
		end
	end
	-- Next when the take succeeds or the inbox changes, or after a moment if neither says.
	if run and run.waiting then
		later(WAIT)
	end
end

-- The server refused a take (a full bag, a busy inbox): tried again, then the batch stops and says so.
ns.on("MAIL_FAILED", "mail helper", function()
	if not run or not run.waiting then
		return
	end
	run.waiting = false
	run.failed = (run.failed or 0) + 1
	if run.failed > RETRIES then
		finish("The mailbox refused it again; press again in a moment.")
		return
	end
	-- Busy: the same mail again after a second.
	run.left = run.left + 1
	later(1)
end)

ns.on("MAIL_INBOX_UPDATE", "mail helper", function()
	if run and run.waiting then
		run.waiting, run.failed = false, 0
		later(GAP)
	end
end)

function Mail.press()
	if run then
		return
	end
	run = { left = Mail.BATCH }
	ns.emit("mailBatch", "Opening...")
	step()
end

-- The mailbox closed: the batch stops where it is.
function Mail.stop()
	run = nil
end
