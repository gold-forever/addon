-- MailHelper.lua: which mail is the auction house's, which to open next, and the batch that opens them.

local ns = { on = function() end }
assert(load(SOURCES["MailHelper.lua"], "@MailHelper.lua"))("GoldForever", ns)
local M = ns.Mail

local P = M.patterns()
eq(M.isAuction("Auction successful: Wool Cloth", P), true, "sold")
eq(M.isAuction("Auction expired: Linen Cloth (20)", P), true, "expired, with a stack in brackets")
eq(M.isAuction("Auction canceled: Silk Cloth", P), true, "canceled, as the client spells it")
eq(M.isAuction("Auction won: Iron Ore", P), true, "won")
eq(M.isAuction("Outbid on Copper Bar", P), true, "outbid")
eq(M.isAuction("Re: Auction successful: lol", P), false, "a player's reply is not")
eq(M.isAuction("Hi there", P), false, "a letter is not")
eq(M.isAuction(nil, P), false, "no subject")
-- Another client's words, with pattern characters in them.
local de = M.patterns({ "Auktion erfolgreich (%s)" })
eq(M.isAuction("Auktion erfolgreich (Wollstoff)", de), true, "a translated subject, brackets literal")

local inbox = {
	{ subject = "Hello", money = 500, items = 0 },
	{ subject = "Auction expired: Linen Cloth", money = 0, items = 1 },
	{ subject = "Auction successful: Wool Cloth", money = 1900, items = 0 },
	{ subject = "Auction won: Ore", money = 0, items = 2, cod = 100 },
}
eq(M.next(inbox, 5, P), 2, "the first auction mail, not the letter")
eq(M.next(inbox, 0, P), 3, "bags full: the gold first")
local _, why = M.next({ inbox[1], inbox[2] }, 0, P)
eq(why, "bags", "only items left and no room")
_, why = M.next({ inbox[1], inbox[4] }, 5, P)
eq(why, "none", "cash on delivery is never opened")
-- A player's letter titled like the auction house's (it can be answered): never opened.
_, why = M.next({ { subject = "Auction successful: Gold", money = 100000, items = 0, canReply = true } }, 5, P)
eq(why, "none", "a player's letter with an auction subject is not auction mail")

-- The batch: one press takes the auction mail in turn, and tells the panel what to say with a message
-- ("mailBatch"), not by writing the panel's note.
local handlers, notes, timers = {}, {}, {}
local batch = {
	on = function(event, _, fn)
		handlers[event] = fn
	end,
	emit = function(event, note)
		if event == "mailBatch" then
			notes[#notes + 1] = note or ""
		end
	end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
}
-- The timers waiting now run; those they start wait for the next.
local function flush()
	local due = timers
	timers = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
local mails = {
	{ "Hello", 500, 0, true },
	{ "Auction expired: Linen Cloth", 0, 1 },
	{ "Auction successful: Wool Cloth", 1900, 0 },
}
local taken = {}
local keep = { C_Timer, C_Container, GetInboxNumItems, GetInboxHeaderInfo, AutoLootMailItem }
C_Timer = { After = function(_, fn) timers[#timers + 1] = fn end }
C_Container = { GetContainerNumFreeSlots = function() return 5, 0 end }
function GetInboxNumItems() return #mails, #mails end
function GetInboxHeaderInfo(i)
	local m = mails[i]
	return nil, nil, "Auction House", m[1], m[2], 0, 20, m[3], false, false, false, m[4] or false
end
function AutoLootMailItem(i)
	taken[#taken + 1] = table.remove(mails, i)[1]
end
assert(load(SOURCES["MailHelper.lua"], "@MailHelper.lua"))("GoldForever", batch)
local B = batch.Mail
eq(select(1, B.waiting()), 2, "two auction mails wait, the letter not counted")
B.press()
eq(B.running(), true, "a press runs a batch")
handlers.MAIL_INBOX_UPDATE()
flush()
handlers.MAIL_INBOX_UPDATE()
flush()
eq(table.concat(taken, " | "), "Auction expired: Linen Cloth | Auction successful: Wool Cloth", "the auction mails in turn, the letter stays")
eq(B.running(), false, "the batch ends when none is left")
eq(notes[1], "Opening…", "the batch says it opens")
eq(notes[#notes], "All auction mail opened.", "and says when it is done")
-- A take the server refuses each time: tried again three times, then the batch stops and says so.
mails[#mails + 1] = { "Auction successful: Stuck", 100, 0 }
local tries = 0
function AutoLootMailItem()
	tries = tries + 1
end
B.press()
for _ = 1, 4 do
	handlers.MAIL_FAILED()
	flush()
end
eq(tries, 4, "the first take and three more")
eq(B.running(), false, "then the batch stops")
eq(notes[#notes], "The mailbox refused it again; press again in a moment.", "and says so")
-- A batch stopped (the mailbox closed) takes nothing more.
B.press()
B.stop()
flush()
eq(B.running(), false, "stopped")
C_Timer, C_Container, GetInboxNumItems, GetInboxHeaderInfo, AutoLootMailItem = keep[1], keep[2], keep[3], keep[4], keep[5]

return checks()
