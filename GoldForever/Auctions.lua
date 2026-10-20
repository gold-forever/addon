-- Gold Forever: the character's own auctions (design 002 reserves them as an additive section).
-- Every auction posted (`post` rows), and every sale from the auction house's "successful" mail
-- (`sale` rows). Nothing about other players: the buyer named in the mail is never kept.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.post = "t,char,item,qty,unit,duration,commodity"
ns.FIELDS.sale = "t,char,item,qty,price,deposit,cut"

local DEDUPE_SECONDS = 5 -- a post and its confirmation are one auction

local lastPost -- { key, at }

local function post(location, duration, quantity, unit, commodity)
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
	if lastPost and lastPost.key == signature and GetTime() - lastPost.at < DEDUPE_SECONDS then
		return -- the confirmation of the post just recorded
	end
	lastPost = { key = signature, at = GetTime() }
	ns.append("post", Encode.row(ns.now(), me.ref, key, quantity or 1, unit, duration, commodity))
	ns.catalogueItem(key)
end

if C_AuctionHouse then
	-- PostItem(location, duration, quantity, bid, buyout): the unit price is the buyout per item.
	local function item(location, duration, quantity, _, buyout)
		ns.safely("post", post, location, duration, quantity,
			buyout and math.floor(buyout / math.max(1, quantity or 1) + 0.5) or nil, nil)
	end
	-- PostCommodity(location, duration, quantity, unitPrice).
	local function commodity(location, duration, quantity, unitPrice)
		ns.safely("post", post, location, duration, quantity, unitPrice, true)
	end
	for name, hook in pairs({ PostItem = item, ConfirmPostItem = item, PostCommodity = commodity, ConfirmPostCommodity = commodity }) do
		if C_AuctionHouse[name] then
			hooksecurefunc(C_AuctionHouse, name, hook)
		end
	end
end

-- Sales: the "successful" mail's invoice says what sold and for how much. A mail is recorded once,
-- by a key from its content and days left (stable while it sits in the inbox).
local function readInbox()
	local me = ns.me()
	if not me or not GetInboxNumItems or not GetInboxInvoiceInfo then
		return
	end
	local db = ns.db()
	db.salesSeen = db.salesSeen or {}
	for i = 1, GetInboxNumItems() do
		-- invoiceType, itemName, playerName (the buyer: not kept), bid, buyout, deposit, consignment, …, count
		local invoice, itemName, _, bid, buyout, deposit, cut, _, _, _, count = GetInboxInvoiceInfo(i)
		if invoice == "seller" and itemName then
			local daysLeft = select(7, GetInboxHeaderInfo(i))
			local key = table.concat({ me.ref, itemName, buyout or bid or 0, deposit or 0, count or 1, string.format("%.3f", daysLeft or 0) }, "|")
			if not db.salesSeen[key] then
				db.salesSeen[key] = ns.now()
				-- No free text in a stream: commas and semicolons out of the item name.
				local name = (Encode.name(itemName):gsub(";", "."))
				ns.append("sale", Encode.row(ns.now(), me.ref, name, count or 1, buyout or bid, deposit, cut))
			end
		end
	end
	-- Mails live 30 days; older keys can go.
	for key, t in pairs(db.salesSeen) do
		if ns.now() - t > 31 * 86400 then
			db.salesSeen[key] = nil
		end
	end
end

ns.on("MAIL_INBOX_UPDATE", "sales", ns.throttle("sales", 1, readInbox))
