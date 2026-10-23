-- Gold Forever: the character's own auctions (design 002 reserves them as an additive section).
-- Every auction posted (`post` rows), every sale from the auction house's "successful" mail (`sale`
-- rows), what the character bought (`ahBuy`) and how its other auctions ended (`auctionEnd`: expired,
-- from the "expired" mail, or cancelled; data gap D7). Nothing about other players: neither the buyer
-- named in a mail nor the seller of a purchase is kept.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.post = "t,char,item,qty,unit,duration,commodity"
ns.FIELDS.sale = "t,char,item,qty,price,deposit,cut"
-- price: the total paid in copper; commodity: 1 for a commodity, empty for an item.
ns.FIELDS.ahBuy = "t,char,item,qty,price,commodity"
-- unit: the price asked per unit, when known (a cancel knows it; an expiry mail does not).
ns.FIELDS.auctionEnd = "t,char,item,qty,unit,outcome"

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

-- Purchases: recorded when the server says the purchase went through, never on the press alone (a
-- purchase can fail: the price moved, the money ran short). A commodity's price is the server's quote.
local quote -- the last COMMODITY_PRICE_UPDATED: { unit, total }
local buying -- the purchase pressed and waiting for its answer

local function bought()
	local me, b = ns.me(), buying
	buying = nil
	if not me or not b or not b.key then
		return
	end
	ns.append("ahBuy", Encode.row(ns.now(), me.ref, b.key, b.qty, b.price, b.commodity))
	ns.catalogueItem(b.key)
end

-- Cancels: what the auction was, read from the character's own auctions as the cancel is pressed,
-- written when the server confirms it.
local cancelling = {} -- auctionID -> { key, qty, unit }

local function canceled(auctionID)
	local me, c = ns.me(), cancelling[auctionID]
	cancelling[auctionID] = nil
	if me and c and c.key then
		ns.append("auctionEnd", Encode.row(ns.now(), me.ref, c.key, c.qty, c.unit, "cancelled"))
	end
end

if C_AuctionHouse then
	ns.on("COMMODITY_PRICE_UPDATED", "ahBuy", function(unit, total)
		quote = { unit = unit, total = total }
	end)
	if C_AuctionHouse.ConfirmCommoditiesPurchase then
		hooksecurefunc(C_AuctionHouse, "ConfirmCommoditiesPurchase", function(itemID, quantity)
			buying = { key = itemID and tostring(itemID), qty = quantity, price = quote and quote.total, commodity = true }
		end)
	end
	-- An item auction is bought with PlaceBid at its buyout; a lower bid can still be outbid, so is not a purchase.
	if C_AuctionHouse.PlaceBid then
		hooksecurefunc(C_AuctionHouse, "PlaceBid", function(auctionID, bid)
			local info = C_AuctionHouse.GetAuctionInfoByID and C_AuctionHouse.GetAuctionInfoByID(auctionID)
			if info and info.buyoutAmount and bid and bid >= info.buyoutAmount then
				local key = Encode.itemKey(info.itemLink) or (info.itemKey and info.itemKey.itemID and tostring(info.itemKey.itemID))
				buying = { id = auctionID, key = key, qty = info.quantity or 1, price = bid }
			end
		end)
	end
	ns.on("COMMODITY_PURCHASE_SUCCEEDED", "ahBuy", function()
		if buying and buying.commodity then
			bought()
		end
	end)
	ns.on("AUCTION_HOUSE_PURCHASE_COMPLETED", "ahBuy", function(auctionID)
		if buying and buying.id == auctionID then
			bought()
		end
	end)
	ns.on("COMMODITY_PURCHASE_FAILED", "ahBuy", function()
		buying = nil
	end)

	if C_AuctionHouse.CancelAuction then
		hooksecurefunc(C_AuctionHouse, "CancelAuction", function(auctionID)
			for i = 1, (C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetNumOwnedAuctions() or 0) do
				local a = C_AuctionHouse.GetOwnedAuctionInfo(i)
				if a and a.auctionID == auctionID then
					local key = Encode.itemKey(a.itemLink) or (a.itemKey and a.itemKey.itemID and tostring(a.itemKey.itemID))
					cancelling[auctionID] = { key = key, qty = a.quantity, unit = a.buyoutAmount }
				end
			end
		end)
	end
	ns.on("AUCTION_CANCELED", "auctionEnd", function(auctionID)
		ns.safely("auctionEnd", canceled, auctionID)
	end)
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
			-- The client gives 0 here: an unknown count is left empty, for the web app to work out from the post.
			count = tonumber(count)
			count = count and count > 0 and count or nil
			local price = (bid and bid > 0) and bid or buyout
			local daysLeft = select(7, GetInboxHeaderInfo(i)) or 0
			local expiry = now + daysLeft * 86400
			local content = table.concat({ me.ref, itemName, price or 0, deposit or 0, count or "" }, "|")
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

-- Expiries: the auction house's "expired" mail brings the stack back. Its subject is the client's own
-- localized string (AUCTION_EXPIRED_MAIL_SUBJECT, "Auction expired: %s"), matched up to the item name; the
-- stack is the mail's first attachment. Known again, as a sale is, by its content and its expiry.
local function expiredPrefix()
	local format = AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s"
	return (string.match(format, "^(.-)%%s") or format):gsub("[:%s]+$", "")
end

local function readExpired()
	local me = ns.me()
	if not me or not GetInboxNumItems or not GetInboxHeaderInfo or not GetInboxItem then
		return
	end
	local db = ns.db()
	db.endsSeen = db.endsSeen or {} -- content -> { [expiry] = seen at }
	local prefix = expiredPrefix()
	local now = ns.now()
	local matched = {}
	for i = 1, GetInboxNumItems() do
		local _, _, _, subject, _, _, daysLeft = GetInboxHeaderInfo(i)
		if type(subject) == "string" and prefix ~= "" and string.sub(subject, 1, #prefix) == prefix then
			local _, itemID, _, count = GetInboxItem(i, 1)
			local key = Encode.itemKey(GetInboxItemLink and GetInboxItemLink(i, 1)) or (itemID and tostring(itemID))
			if key then
				local expiry = now + (daysLeft or 0) * 86400
				local content = table.concat({ me.ref, key, count or "" }, "|")
				local seen = db.endsSeen[content] or {}
				db.endsSeen[content] = seen
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
					ns.append("auctionEnd", Encode.row(now, me.ref, key, count, nil, "expired"))
					ns.catalogueItem(key)
				end
			end
		end
	end
	-- An expiry mail lives 30 days; a day after its expiry the key can go.
	for content, seen in pairs(db.endsSeen) do
		for at in pairs(seen) do
			if at < now - 86400 then
				seen[at] = nil
			end
		end
		if next(seen) == nil then
			db.endsSeen[content] = nil
		end
	end
end

ns.on("MAIL_INBOX_UPDATE", "auctionEnd", ns.throttle("auctionEnd", 1, readExpired))
