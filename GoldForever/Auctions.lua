-- Gold Forever: the character's own auctions (design 002 reserves them as an additive section).
-- Every auction posted (`post` rows), and every sale from the auction house's "successful" mail
-- (`sale` rows). Nothing about other players: the buyer named in the mail is never kept.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.post = "t,char,item,qty,unit,duration,commodity"
ns.FIELDS.sale = "t,char,item,qty,price,deposit,cut"

local DEDUPE_SECONDS = 5 -- a post and its confirmation are one auction

local lastPost -- { key, at }

-- A post, or with [confirming] the confirmation the client asks for after a warning (the same
-- auction, recorded once).
local function post(location, duration, quantity, unit, commodity, confirming)
	local me = ns.me()
	if not me or not location then
		return
	end
	local link = C_Item.GetItemLink and C_Item.GetItemLink(location)
	local key = Encode.itemKey(link) or tostring(C_Item.GetItemID(location) or "")
	if key == "" then
		return
	end
	local signature = table.concat({ key, quantity or 1, unit or 0 }, ":")
	if confirming and lastPost and lastPost.key == signature and GetTime() - lastPost.at < DEDUPE_SECONDS then
		return -- the confirmation of the post just recorded
	end
	lastPost = { key = signature, at = GetTime() }
	ns.append("post", Encode.row(ns.now(), me.ref, key, quantity or 1, unit, duration, commodity))
	ns.catalogueItem(key)
end

if C_AuctionHouse then
	-- PostItem(location, duration, quantity, bid, buyout): the unit price is the buyout per item.
	local function item(confirming)
		return function(location, duration, quantity, _, buyout)
			ns.safely("post", post, location, duration, quantity,
				buyout and math.floor(buyout / math.max(1, quantity or 1) + 0.5) or nil, nil, confirming)
		end
	end
	-- PostCommodity(location, duration, quantity, unitPrice).
	local function commodity(confirming)
		return function(location, duration, quantity, unitPrice)
			ns.safely("post", post, location, duration, quantity, unitPrice, true, confirming)
		end
	end
	local hooks = {
		PostItem = item(false), ConfirmPostItem = item(true),
		PostCommodity = commodity(false), ConfirmPostCommodity = commodity(true),
	}
	for name, hook in pairs(hooks) do
		if C_AuctionHouse[name] then
			hooksecurefunc(C_AuctionHouse, name, hook)
		end
	end
end

-- Sales: the "successful" mail's invoice says what sold and for how much. A mail is known by its
-- content and when it expires (now plus its days left, steady while it sits in the inbox), so a
-- mail seen again is not a second sale, and two alike mails are two.
local SAME_EXPIRY = 300 -- seconds: the days left are read at slightly different moments

local function readInbox()
	local me = ns.me()
	if not me or not GetInboxNumItems or not GetInboxInvoiceInfo then
		return
	end
	local db = ns.db()
	db.salesSeen = db.salesSeen or {} -- content -> { [expiry] = seen at }
	local now = ns.now()
	local matched = {} -- expiries matched in this read, so alike mails each match their own
	for i = 1, GetInboxNumItems() do
		-- invoiceType, itemName, playerName (the buyer: not kept), bid, buyout, deposit, consignment,
		-- moneyDelay, etherealTime, count, commerceAuction
		local invoice, itemName, _, bid, buyout, deposit, cut, _, _, count = GetInboxInvoiceInfo(i)
		if invoice == "seller" and itemName then
			count = tonumber(count) or 1
			local price = (bid and bid > 0) and bid or buyout
			local daysLeft = select(7, GetInboxHeaderInfo(i)) or 0
			local expiry = now + daysLeft * 86400
			local content = table.concat({ me.ref, itemName, price or 0, deposit or 0, count }, "|")
			local seen = db.salesSeen[content]
			if type(seen) ~= "table" then
				seen = {}
				db.salesSeen[content] = seen
			end
			local known
			for at in pairs(seen) do
				if math.abs(at - expiry) <= SAME_EXPIRY and not matched[content .. "@" .. at] then
					known = at
					break
				end
			end
			if known then
				matched[content .. "@" .. known] = true
			else
				seen[expiry] = now
				matched[content .. "@" .. expiry] = true
				-- No free text in a stream: commas and semicolons out of the item name.
				local name = (Encode.name(itemName):gsub(";", "."))
				ns.append("sale", Encode.row(now, me.ref, name, count, price, deposit, cut))
			end
		end
	end
	-- Mails live 30 days; expired ones can go, and so can the keys of the old format.
	for content, seen in pairs(db.salesSeen) do
		if type(seen) == "table" then
			for at in pairs(seen) do
				if at < now - 86400 then
					seen[at] = nil
				end
			end
		end
		if type(seen) ~= "table" or next(seen) == nil then
			db.salesSeen[content] = nil
		end
	end
end

ns.on("MAIL_INBOX_UPDATE", "sales", ns.throttle("sales", 1, readInbox))
