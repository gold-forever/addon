-- MailHelper.lua: which mail is the auction house's, and which to open next.

local ns = {}
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

return checks()
