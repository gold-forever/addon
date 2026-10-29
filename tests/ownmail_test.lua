-- Mail.lua and Ledger.lua: mail sent to one of your own characters is recorded (items, money, cash on
-- delivery) once the server takes it, and its gold is a transfer in the ledger on both sides. Mail to
-- anyone else records nothing, and no name is ever written.

-- As the client's: the hook runs after the original with the same arguments.
function hooksecurefunc(name, hook)
	local orig = _G[name]
	_G[name] = function(...)
		orig(...)
		hook(...)
	end
end

local clock, purse = 100, 0
function GetTime() return clock end
function GetMoney() return purse end

-- The send frame: its attachments, money and cash on delivery, cleared once the server takes the mail.
local attached, sendMoney, sendCod = {}, 0, 0
function GetSendMailItemLink(i) return attached[i] and attached[i].link end
function GetSendMailItem(i)
	local a = attached[i]
	if a then
		return "x", a.id, nil, a.count, 1
	end
end
function GetSendMailMoney() return sendMoney end
function GetSendMailCOD() return sendCod end
function SendMail() end

-- The inbox: sender and money of each mail.
local inbox = {}
function GetInboxHeaderInfo(i)
	local m = inbox[i]
	return nil, nil, m.sender, m.subject, m.money, 0, 20, 0, false, false, false, true
end
function TakeInboxMoney() end
function AutoLootMailItem() end

local me = { ref = 1, name = "Ann", realm = "Argent Dawn" }
local save = { characters = {
	["Player-1-a"] = me,
	["Player-1-b"] = { ref = 2, name = "Bankalt", realm = "Argent Dawn" },
	["Player-2-c"] = { ref = 3, name = "Faraway", realm = "Silvermoon" },
} }
local handlers, rows = {}, {}
local ns = {
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	after = function() end,
	module = function() end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	me = function() return me end,
	db = function() return save end,
	now = function() return 1792517535 end,
	tornDown = function() return false end,
	catalogueItem = function() end,
	record = function(stream, row)
		rows[#rows + 1] = { stream = stream, row = row }
	end,
}
local function fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(...)
	end
end
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Ledger.lua"], "@Ledger.lua"))("GoldForever", ns)
assert(load(SOURCES["Mail.lua"], "@Mail.lua"))("GoldForever", ns)

-- The rows of a stream written since the last look, as "column=value" in the given columns' order.
local function written(stream, columns)
	local out = {}
	for _, r in ipairs(rows) do
		if r.stream == stream then
			local parts = {}
			for _, c in ipairs(columns) do
				parts[#parts + 1] = c .. "=" .. tostring(r.row[c])
			end
			out[#out + 1] = table.concat(parts, " ")
		end
	end
	rows = {}
	return table.concat(out, "; ")
end
local MAIL = { "char", "to", "items", "money", "cod" }
local MONEY = { "delta", "ctx" }

local function spend(amount)
	purse = purse - amount
	fire("PLAYER_MONEY")
end

fire("MAIL_SHOW")
purse = 5000000
fire("PLAYER_MONEY") -- the purse the changes are measured from

-- Items and gold to your bank alt: recorded once the server takes it, its gold a transfer and the
-- postage spent at the mailbox.
attached = {
	{ link = "|Hitem:2589::::::::30|h[Linen Cloth]|h", id = 2589, count = 20 },
	[3] = { link = "|Hitem:2589::::::::30|h[Linen Cloth]|h", id = 2589, count = 7 },
	[4] = { link = "|Hitem:14047::::::::30|h[Runecloth]|h", id = 14047, count = 3 },
}
sendMoney = 1000000
SendMail("Bankalt", "stuff", "")
eq(written("mail", MAIL), "", "nothing before the server takes the mail")
spend(1000000 + 60)
eq(written("money", MONEY), "delta=-1000000 ctx=mail+transfer; delta=-60 ctx=mail", "the gold sent is a transfer, the postage is mail")
attached, sendMoney = {}, 0
fire("MAIL_SEND_SUCCESS")
eq(written("mail", MAIL), "char=1 to=2 items=14047*3+2589*27 money=1000000 cod=nil", "the mail to your bank alt, its items and gold")

-- The server's answer may come before the money moves.
sendMoney = 2500
SendMail("bankalt-ArgentDawn", "", "")
fire("MAIL_SEND_SUCCESS")
eq(written("mail", MAIL), "char=1 to=2 items=nil money=2500 cod=nil", "your character named with its realm, any case")
spend(2500 + 30)
eq(written("money", MONEY), "delta=-2500 ctx=mail+transfer; delta=-30 ctx=mail", "the transfer is tagged after the answer too")

-- Cash on delivery to your own character: recorded; no gold moves.
sendMoney, attached, sendCod = 0, { { link = "|Hitem:14047::::::::30|h[Runecloth]|h", id = 14047, count = 1 } }, 900
SendMail("Bankalt", "", "")
fire("MAIL_SEND_SUCCESS")
eq(written("mail", MAIL), "char=1 to=2 items=14047*1 money=nil cod=900", "cash on delivery recorded")
attached, sendCod = {}, 0

-- A send that fails records nothing, and its gold is no transfer.
sendMoney = 7000
SendMail("Bankalt", "", "")
fire("MAIL_FAILED")
eq(written("mail", MAIL), "", "a failed send records nothing")
spend(7000)
eq(written("money", MONEY), "delta=-7000 ctx=mail", "and leaves no transfer to tag the next change")

-- Mail to anyone else: nothing about them, and its gold is spent at the mailbox as before.
for _, recipient in ipairs({ "Stranger", "Faraway", "Bankalt-Silvermoon", "Ann" }) do
	sendMoney = 400
	attached = { { link = "|Hitem:2589::::::::30|h[Linen Cloth]|h", id = 2589, count = 1 } }
	SendMail(recipient, "", "")
	fire("MAIL_SEND_SUCCESS")
	eq(written("mail", MAIL), "", "nothing recorded for mail to " .. recipient)
	spend(430)
	eq(written("money", MONEY), "delta=-430 ctx=mail", "mail to " .. recipient .. " is no transfer")
end
sendMoney, attached = 0, {}

-- The receiving side: gold taken from your own character's mail is a transfer; another's is not.
inbox = {
	{ sender = "Bankalt", subject = "gold", money = 300000 },
	{ sender = "Stranger", subject = "gold", money = 5000 },
}
TakeInboxMoney(1)
spend(-300000)
eq(written("money", MONEY), "delta=300000 ctx=mail+transfer", "gold from your own character is a transfer")
AutoLootMailItem(2)
spend(-5000)
eq(written("money", MONEY), "delta=5000 ctx=mail", "gold from anyone else is mail")
AutoLootMailItem(1)
spend(-300000)
eq(written("money", MONEY), "delta=300000 ctx=mail+transfer", "taken with Open All too")

-- Gold sent waits for gold to leave: a rise meanwhile is not it.
sendMoney = 1000
SendMail("Bankalt", "", "")
fire("MAIL_SEND_SUCCESS")
written("mail", MAIL)
sendMoney = 0
AutoLootMailItem(2)
spend(-5000)
eq(written("money", MONEY), "delta=5000 ctx=mail", "a rise is not the gold sent")
spend(1030)
eq(written("money", MONEY), "delta=-1000 ctx=mail+transfer; delta=-30 ctx=mail", "the fall that follows is")

-- An expected transfer the money never matched is forgotten after a while.
TakeInboxMoney(1)
clock = clock + 60
spend(-300000)
eq(written("money", MONEY), "delta=300000 ctx=mail", "a transfer expected long ago tags nothing")

return checks()
