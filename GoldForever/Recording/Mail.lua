-- Gold Forever: mail you send to your own characters (the mail stream), so items and gold moved to an
-- alt are known while they travel, and its gold is a transfer in the ledger on both sides (Ledger.lua).
-- Mail to or from anyone else records nothing about them: a recipient or sender is only ever compared
-- with your own characters, never written.

local _, ns = ...
local Encode = ns.Encode

-- A name or realm as a mail address compares: any case, without spaces or dashes.
local function same(a, b)
	local function plain(s)
		return string.lower((string.gsub(s or "", "[%s%-]", "")))
	end
	return plain(a) == plain(b)
end

-- Your characters on your other WoW accounts, as the companion's data file lists them (DataFormat.lua);
-- empty without the file or the list.
local function listed()
	local F = ns.DataFormat.field
	local data = _G[ns.DataFormat.GLOBAL]
	local list = type(data) == "table" and data[F.characters]
	return type(list) == "table" and list or {}
end

-- Your other character on this realm a mail address names ("Name" or "Name-Realm"), as the mail stream's
-- to: its ref when this save knows it, else "Name-Realm" as the companion's list spells it; nil for anyone else.
local function ownCharacter(address)
	local me = ns.me()
	local name, realm = string.match(type(address) == "string" and address or "", "^([^%-]+)%-?(.*)$")
	if not me or not name or (realm ~= "" and not same(realm, me.realm)) or same(name, me.name) then
		return nil
	end
	for _, c in pairs(ns.db().characters) do
		if c ~= me and c.ref and same(c.name, name) and same(c.realm, me.realm) then
			return c.ref
		end
	end
	local F = ns.DataFormat.field
	for _, c in ipairs(listed()) do
		local cName, cRealm = type(c) == "table" and c[F.name], type(c) == "table" and c[F.realm]
		if type(cName) == "string" and type(cRealm) == "string" and same(cName, name) and same(cRealm, me.realm) then
			return Encode.text(cName .. "-" .. cRealm)
		end
	end
end

-- Sending ------------------------------------------------------------------------------------------

local sending -- the mail to your own character the server has not answered yet: { to, items, money, cod }

local function attachments()
	local counts = {}
	for i = 1, ATTACHMENTS_MAX_SEND or 12 do
		local key = Encode.itemKey(GetSendMailItemLink(i))
		if key then
			local count = select(4, GetSendMailItem(i))
			counts[key] = (counts[key] or 0) + (count or 1)
			ns.catalogueItem(key)
		end
	end
	return next(counts) and Encode.items(counts) or nil
end

local function positive(n)
	return (n or 0) > 0 and n or nil
end

-- Read as SendMail is called: the send frame still holds the mail until the server answers.
local function send(recipient)
	sending = nil
	local to = ownCharacter(recipient)
	if not to then
		return
	end
	sending = { to = to, items = attachments(), money = positive(GetSendMailMoney()), cod = positive(GetSendMailCOD()) }
	if sending.money then
		ns.expectTransfer(-sending.money)
	end
end

if SendMail and GetSendMailItemLink then
	hooksecurefunc("SendMail", function(recipient)
		ns.safely("mail", send, recipient)
	end)
end

ns.on("MAIL_SEND_SUCCESS", "mail", function()
	local me = ns.me()
	if sending and me then
		ns.record("mail", { t = ns.now(), char = me.ref, to = sending.to, items = sending.items, money = sending.money, cod = sending.cod })
	end
	sending = nil
end)

ns.on("MAIL_FAILED", "mail", function()
	if sending and sending.money then
		ns.forgetTransfer(-sending.money)
	end
	sending = nil
end)

-- Receiving ----------------------------------------------------------------------------------------

-- Gold taken from a mail your own character sent: the ledger's next rise of that much is a transfer.
local function take(index)
	local _, _, sender, _, money = GetInboxHeaderInfo(index)
	if positive(money) and ownCharacter(sender) then
		ns.expectTransfer(money)
	end
end

for _, name in ipairs({ "TakeInboxMoney", "AutoLootMailItem" }) do
	if _G[name] and GetInboxHeaderInfo then
		hooksecurefunc(name, function(index)
			ns.safely("mail", take, index)
		end)
	end
end
