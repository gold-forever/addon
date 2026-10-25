-- Gold Forever: the auction house panel (design 009, Auction house module, Phase 1), docked to the right
-- of the auction house, never replacing or moving Blizzard's frame. Three tabs:
--   Scan  the full scan made visible: asking, reading N of M, the cooldown, the last result.
--   Post  the bag items the auction house takes, each priced by the rule (Post.lua) against the cheapest
--         listing by someone else (a live search when the row is chosen, else the last scan), with the
--         reason; one click, or Space while the panel shows, posts the chosen row and moves on.
--   Rule  undercut, floor and normal price, and what to do under the floor.
-- Posting is a hardware event (the click or the key); the result is confirmed by its event before the
-- next press is taken. Own auctions are left out of "cheapest", so the player never undercuts themself.

local _, ns = ...
local Theme, UI, Post = ns.Theme, ns.UI, ns.Post

local W = 420
local DURATIONS = { { value = 1, label = "12 hours" }, { value = 2, label = "24 hours" }, { value = 3, label = "48 hours" } }
local CONFIRM_TIMEOUT = 5 -- seconds to wait for a post's answer before the next press is taken

local function settings()
	-- The saved table as it is, once there: no defaults made on every call (it is read per row).
	local s = ns.db().settings.auction or ns.settings("auction", { rule = {}, duration = 2 })
	s.durations = s.durations or {}
	s.quantities = s.quantities or {}
	for k, v in pairs(Post.DEFAULT) do
		if s.rule[k] == nil then
			s.rule[k] = v
		end
	end
	return s
end

local panel -- built the first time the auction house opens (or again after a look change)
local built -- Theme.key it was drawn under
local panels = {} -- Theme.key -> panel
local rows, chosen = {}, nil -- the Post tab's rows and the chosen one
local live = {} -- item key -> { cheapest, at }: the last live search's cheapest other listing

-- An item's book in `live`: a commodity's by its id; other items' by id and item level, as one gear item
-- at two item levels is two books with two prices.
local function bookKey(itemID, commodity, itemLevel)
	if commodity then
		return tostring(itemID)
	end
	return "item:" .. itemID .. ":" .. (itemLevel or 0)
end
local waits = {} -- an action sent, by kind ("post", "shop", "cancel"), waiting for its answer: { key, at }
local armed -- a post that needs a second press: the row's key
local confirm -- the client warned about a commodity or item price: the next press confirms { key, args }

-- An action sent (a post, a buy, a cancel): the panel waits for its answer before the next press, and
-- never longer than CONFIRM_TIMEOUT, so a failure the client reports nowhere the panel hears cannot
-- leave Post, Shop and Cancel disabled. Each kind waits apart, so one kind's answer never ends
-- another's wait. `note` is the tab's line for the timeout; `onTimeout` lets go of what the action held.
local function await(kind, key, note, onTimeout)
	local w = { key = key, at = GetTime() }
	waits[kind] = w
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if waits[kind] == w then
			waits[kind] = nil
			if onTimeout then
				onTimeout()
			end
			if note then
				note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the auction house; check it before trying again.|r")
			end
			if ns.auctionRefresh then
				ns.auctionRefresh()
			end
		end
	end)
end

-- Whether any action waits for its answer: a press of Post, Buy next or Cancel next waits for it.
local function busy()
	return waits.post or waits.shop or waits.cancel
end

-- Gold and silver: a price rounded to the gold read as wrong beside the auction house's own (8g for 8g 69s).
local money = function(c)
	return UI.layout.money(c, "silver")
end

-- Bags --------------------------------------------------------------------------------------------------

local function bags()
	local list = { 0, 1, 2, 3, 4 }
	if Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag then
		list[#list + 1] = Enum.BagIndex.ReagentBag
	end
	return list
end

-- The bag items the auction house would take, one row per item (gear by its own link, so item levels
-- stay apart): { key, id, name, quality, count, locations = { ItemLocation }, commodity }.
local function sellable()
	local byKey, out = {}, {}
	if not (C_AuctionHouse and C_AuctionHouse.IsSellItemValid and ItemLocation) then
		return out
	end
	for _, bag in ipairs(bags()) do
		for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info and info.itemID and not info.isBound then
				local loc = ItemLocation:CreateFromBagAndSlot(bag, slot)
				if C_Item.DoesItemExist(loc) and C_AuctionHouse.IsSellItemValid(loc, false) then
					local commodity = C_AuctionHouse.GetItemCommodityStatus
						and C_AuctionHouse.GetItemCommodityStatus(loc) == (Enum.ItemCommodityStatus and Enum.ItemCommodityStatus.Commodity or 2)
					local key = commodity and tostring(info.itemID) or (ns.Encode.itemKey(info.hyperlink) or tostring(info.itemID))
					local r = byKey[key]
					if not r then
						local quality, _, _, _, name = ns.price.itemInfo(info.itemID)
						r = { key = key, id = info.itemID, link = info.hyperlink, name = name or C_Item.GetItemNameByID(info.itemID) or ("item " .. info.itemID),
							quality = quality or info.quality or 1, count = 0, locations = {}, commodity = commodity, icon = info.iconFileID }
						byKey[key] = r
						out[#out + 1] = r
					end
					r.count = r.count + (info.stackCount or 1)
					r.locations[#r.locations + 1] = loc
				end
			end
		end
	end
	return out
end

-- A row priced: market value, the cheapest other listing (live or from the scan) and the suggestion.
-- The active sale profile (Rule tab), or nil.
local function activeProfile(s)
	s = s or settings()
	return s.profile and s.profiles and s.profiles[s.profile] or nil
end

-- The bank's and mailbox's item strings, parsed once each time they change (not once per row).
local bankParsed, mailParsed = {}, {}
local function parsedOnce(cache, text)
	if text ~= cache.text then
		cache.text, cache.items = text, ns.Encode.parseItems(text)
	end
	return cache.items
end

-- What this character holds of an item, bags and bank (decision 12: keep counts per character).
local function heldHere(id, inBags)
	local me = ns.me()
	local bank = me and me.bank and parsedOnce(bankParsed, me.bank.items)[id] or 0
	-- The mailbox as last read, and what was bought since (it goes to the mailbox on retail).
	local mail = me and me.mail and parsedOnce(mailParsed, me.mail.items)[id] or 0
	local boughtSince = ns.boughtSince and ns.boughtSince(id) or 0
	return (inBags or 0) + bank + mail + boughtSince
end

-- A sale plan's step as the Post tab's suggestion: posts in whole silver; "ask" posts the plan's price
-- after a second press; hold and skip post nothing.
local PLAN_REASONS = {
	undercut = "Undercut (plan)", fixed = "Fixed price (plan)", percentile = "Percentile (plan)", ["no-competition"] = "No one else (plan)",
	["market-moved"] = "The market moved (plan)", ["under-floor"] = "Hold: under the plan's floor", keeping = "Keeping", ["no-price"] = "No price yet",
}

local function planned(r, rule, market)
	-- Gear's book is known once the row was searched, at its own item level.
	local book = (r.commodity or r.itemKey) and live[bookKey(r.id, r.commodity, r.itemKey and r.itemKey.itemLevel)]
	local step = ns.SalePlan.sell(rule, heldHere(r.id, r.count), book and book.levels or {}, market, nil, Post.silver)
	local unit = step.unitPrice or (step.choices and step.choices.plan)
	local label = PLAN_REASONS[step.reason] or step.reason
	if step.reason == "keeping" then
		label = "Keeping " .. rule.keep
	end
	return {
		unit = unit and Post.silver(unit) or nil,
		reason = "plan", label = label, plan = step,
		floor = step.floor or 0, normal = unit or 0,
		ask = step.action == "ask" or nil,
		quantity = step.quantity,
	}
end

-- `s`: the settings, read once for every row of a refresh.
local function price(r, s)
	s = s or settings()
	r.priced = true
	local value, valueFrom, trend, week = ns.Prices.value(r.id)
	local market, from = ns.Prices.sellBase(value, valueFrom, week)
	r.market, r.marketFrom, r.trend, r.anyway = market, from, trend, nil
	local l = live[r.key]
	if l then
		r.cheapest, r.cheapestFrom = l.cheapest, "live"
	else
		r.cheapest, r.cheapestFrom = ns.price.cheapest(r.id), "scan"
	end
	r.vendor = ns.price.vendor(r.id)
	local rule = ns.SalePlan.ruleFor(activeProfile(s), r.id)
	if rule then
		r.suggestion = planned(r, rule, market)
	else
		-- The rule: an override for the item, or its category, over the default.
		local _, _, class = ns.price.itemInfo(r.id)
		local postRule, from = Post.resolve(s.rule, s.overrides, r.id, class)
		r.suggestion, r.anyway = Post.advise(postRule, market, r.cheapest)
		if r.suggestion and from ~= "default" then
			r.suggestion.label = (Post.REASONS[r.suggestion.reason] or "") .. (from == "item" and " (item rule)" or " (category rule)")
		end
	end
	return r
end

-- Live search ------------------------------------------------------------------------------------------------

-- Asks the server for the chosen row's listings, own ones apart, sorted by price.
-- Asks for the chosen row's listings. With `open`, the auction house's own window shows the item too, as
-- a click on it in Blizzard's browse list does (its buy view, with every price); its search is the one
-- whose results arrive here. Without it, or on a client without that method, a search of our own.
-- The panel's tabs and Blizzard's in step (manual test run 001): its Buy, Sell and Auctions modes are
-- our Buy, Sell and Auctions. `following` is set while the panel itself moves Blizzard's window (a tab
-- clicked here, an item shown), so that move does not switch the panel back.
local following = false
local function tabForMode(mode)
	local M = AuctionHouseFrameDisplayMode
	if not M or not mode then
		return nil
	end
	if mode == M.Buy or mode == M.ItemBuy or mode == M.CommoditiesBuy then
		return "shop"
	elseif mode == M.ItemSell or mode == M.CommoditiesSell then
		return "post"
	elseif mode == M.Auctions then
		return "cancel"
	end
end
local BLIZZARD_TAB = { shop = "BuyTab", post = "SellTab", cancel = "AuctionsTab" }

local function blizzardMode()
	local f = AuctionHouseFrame
	if not f then
		return nil
	end
	return f.GetDisplayMode and f:GetDisplayMode() or f.displayMode
end

-- Shows an item's listings in Blizzard's window; true when it did. Blizzard's SelectBrowseResult reads
-- the item key's info and fails when the client has not loaded it yet (manual test run 001: "attempt to
-- index local itemKeyInfo"): the client is asked for it, and the item is shown when it arrives.
local waitingKey
local function browse(itemKey)
	local f = AuctionHouseFrame
	if not (itemKey and f and f.SelectBrowseResult and f:IsShown()) then
		return false
	end
	if C_AuctionHouse.GetItemKeyInfo and not C_AuctionHouse.GetItemKeyInfo(itemKey) then
		waitingKey = itemKey
		return false
	end
	waitingKey = nil
	following = true
	-- A browse result as Blizzard's list hands it: it shows minPrice at once ("rawCopper" nil without it,
	-- manual test run 001), before its own search brings the listings; the market value stands in.
	local price = ns.Prices and ns.Prices.value and ns.Prices.value(itemKey.itemID)
	local ok = pcall(f.SelectBrowseResult, f, { itemKey = itemKey, minPrice = math.floor(price or 0), totalQuantity = 0 })
	if not ok then
		-- Else the item's name in Blizzard's search bar, searched there.
		local bar = f.SearchBar
		local name = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemKey.itemID)
		if bar and bar.SearchBox and bar.StartSearch and name then
			if f.SetDisplayMode and AuctionHouseFrameDisplayMode then
				pcall(f.SetDisplayMode, f, AuctionHouseFrameDisplayMode.Buy)
			end
			bar.SearchBox:SetText(name)
			ok = ns.safely("auction search bar", bar.StartSearch, bar)
		end
	end
	following = false
	return ok
end
ns.on("ITEM_KEY_ITEM_INFO_RECEIVED", "auction panel", function(itemID)
	if waitingKey and waitingKey.itemID == itemID then
		browse(waitingKey)
	end
end)

-- Empties Blizzard's own Sell window before the panel posts what it holds: its frame keeps the bag slot,
-- and once the item has gone it asks that empty slot for an item level and fails (manual test run 001:
-- "bad argument #1 to 'GetCurrentItemLevel'" after a post). Blizzard's Post button empties it itself.
local function clearBlizzardSell()
	local f = AuctionHouseFrame
	if not f then
		return
	end
	following = true
	for _, sell in ipairs({ f.ItemSellFrame, f.CommoditiesSellFrame }) do
		if sell and sell.SetItem and (sell.itemLocation or (sell.GetItem and sell:GetItem())) then
			pcall(sell.SetItem, sell, nil)
		end
	end
	following = false
end

-- Puts a bag item in Blizzard's own Sell window, as a click on it in the bags does there; true when it did.
local function sellItem(location)
	local f = AuctionHouseFrame
	if not (location and f and f.SetPostItem and f:IsShown()) then
		return false
	end
	following = true
	local ok = ns.safely("auction sell item", f.SetPostItem, f, location)
	following = false
	return ok
end

local function search(r, open)
	if not (r and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.GetItemKeyFromItem) then
		return
	end
	local key = C_AuctionHouse.GetItemKeyFromItem(r.locations[1])
	if not key then
		return
	end
	r.itemKey = key
	-- Chosen on Sell: into Blizzard's Sell window too (the search below still reads the listings for
	-- the panel); else its listings in Blizzard's Buy view.
	if open and not sellItem(r.locations[1]) and browse(key) then
		return
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

local LISTED = 4 -- the cheapest listings the panel shows
local LEVELS = 100 -- the cheapest levels of a book the Shop reads

local refresh, show
-- For the waits above, defined before the drawing.
ns.auctionRefresh = function()
	if refresh then
		refresh()
	end
end

-- The cheapest other listing in a book: one sneaky-price guard for Sell, Cancel and the sale plans.
local function honest(levels, itemID)
	return Post.honestCheapest(levels, ns.Prices and ns.Prices.value and (ns.Prices.value(itemID)) or nil)
end

-- Commodities: the cheapest unit left after the player's own.
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction panel", function(itemID)
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	local list, levels = {}, {}
	-- The book as the Shop reads it ({ unitPrice, quantity, own }), the cheapest LEVELS of it.
	for i = 1, math.min(n, LEVELS) do
		local res = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if res then
			if #list < LISTED then
				list[#list + 1] = { unit = res.unitPrice, qty = res.quantity or 0, own = (res.numOwnerItems or 0) > 0 }
			end
			levels[#levels + 1] = { unitPrice = res.unitPrice, quantity = res.quantity or 0, own = res.numOwnerItems or 0 }
		end
	end
	live[tostring(itemID)] = { cheapest = honest(levels, itemID), list = list, total = n, levels = levels, commodity = true, at = GetTime() }
	if refresh then
		refresh()
	end
end)

-- Gear and other items: the cheapest buyout a unit that is not the player's own.
ns.on("ITEM_SEARCH_RESULTS_UPDATED", "auction panel", function(itemKey)
	if not itemKey then
		return
	end
	local n = C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0
	local all = {}
	-- The cheapest LEVELS (the search is sorted by price), as for commodities: a popular item lists hundreds.
	for i = 1, math.min(n, LEVELS) do
		local res = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if res and res.buyoutAmount and res.buyoutAmount > 0 then
			local unit = math.floor(res.buyoutAmount / math.max(1, res.quantity or 1) + 0.5)
			all[#all + 1] = { unit = unit, qty = res.quantity or 1, own = res.containsOwnerItem and true or false,
				auctionID = res.auctionID, buyout = res.buyoutAmount }
		end
	end
	table.sort(all, function(a, b)
		return a.unit < b.unit
	end)
	local list = {}
	for i = 1, math.min(LISTED, #all) do
		list[i] = all[i]
	end
	-- For the Shop: every auction of the item, cheapest first, as levels and with what PlaceBid needs.
	local levels = {}
	for i, a in ipairs(all) do
		levels[i] = { unitPrice = a.unit, quantity = a.qty, own = a.own and a.qty or 0, auctionID = a.auctionID, buyout = a.buyout }
	end
	local cheapest = honest(levels, itemKey.itemID)
	for _, r in ipairs(rows) do
		if r.itemKey and r.itemKey.itemID == itemKey.itemID and r.itemKey.itemLevel == itemKey.itemLevel then
			live[r.key] = { cheapest = cheapest, list = list, total = n, at = GetTime() }
		end
	end
	live[bookKey(itemKey.itemID, false, itemKey.itemLevel)] = { cheapest = cheapest, levels = levels, commodity = false, at = GetTime() }
	if refresh then
		refresh()
	end
end)

-- Posting -----------------------------------------------------------------------------------------------------

local lastArgs -- what the last post sent, for confirming it after the client's warning
local postedAt -- when the panel last sent a post (GetTime)
local WARNING_WINDOW = 2 -- seconds after the panel's own post in which the client's warning is for it

-- The duration an item posts for: the one last chosen for it, else the default.
local function durationOf(r)
	local s = settings()
	return r and s.durations[r.key] or s.duration
end

-- How many to post: of a commodity, the number chosen for it (all at first), never more than held;
-- other items one at a time.
local function quantity(r)
	if not r.commodity then
		return 1
	end
	local chosen = settings().quantities[r.key]
	-- A sale plan's quantity (what is over its keep) unless the player chose a number.
	local default = r.suggestion and r.suggestion.quantity or r.count
	return math.max(1, math.min(r.count, chosen or default))
end

-- Posts the chosen row: commodities all at once at the unit price, other items one location at a time.
local function post()
	local r = chosen
	if not r or busy() or not r.suggestion then
		return
	end
	local unit, forced = r.suggestion.unit, false
	-- Held under the floor: Post anyway posts at the undercut price on a second press.
	if not unit and r.anyway then
		if armed ~= r.key .. ":anyway" then
			armed = r.key .. ":anyway"
			panel.post.note:SetText(Theme.escape(Theme.color.warning) .. string.format("%s is under your floor of %s. Press again to post anyway.",
				money(r.anyway), money(r.suggestion.floor)) .. "|r")
			return
		end
		unit, forced = r.anyway, true
	end
	if not unit then
		return
	end
	-- The client warned about this post: the press confirms it, as its own window's button does.
	-- Only for what was warned about: the price or quantity changed since, and the press posts afresh.
	local args = confirm and confirm.key == r.key and confirm.args
	if args and args[3] == quantity(r) and (r.commodity and args[4] or args[5] / quantity(r)) == unit then
		confirm = nil
		-- The arguments as posted, a nil bid included (unpack stops at a hole without the count).
		if r.commodity and C_AuctionHouse.ConfirmPostCommodity then
			C_AuctionHouse.ConfirmPostCommodity(unpack(args, 1, args.n))
		elseif C_AuctionHouse.ConfirmPostItem then
			C_AuctionHouse.ConfirmPostItem(unpack(args, 1, args.n))
		end
		await("post", r.key, panel.post.note)
		panel.post.note:SetText("Posting…")
		return
	end
	confirm = nil
	local warning = not forced and (Post.check(unit, r.market, r.vendor, ns.price.cut)
		or (r.suggestion.ask and "at the plan's fixed price though the market moved"))
	if warning and armed ~= r.key then
		armed = r.key
		panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "Press again to post " .. warning .. ".|r")
		return
	end
	armed = nil
	local duration = durationOf(r)
	local loc = r.locations[1]
	local q = quantity(r)
	clearBlizzardSell()
	-- The client says at once whether the post needs confirming (a price far from the going one); then
	-- the next press confirms it, as Blizzard's own sell window does, and no answer is waited for.
	local needs
	postedAt = GetTime()
	if r.commodity then
		lastArgs = { n = 4, loc, duration, q, unit }
		needs = C_AuctionHouse.PostCommodity(loc, duration, q, unit)
	else
		lastArgs = { n = 5, loc, duration, q, nil, unit * q }
		needs = C_AuctionHouse.PostItem(loc, duration, q, nil, unit * q)
	end
	if needs then
		confirm = { key = r.key, args = lastArgs }
		panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "The auction house warns this price is far from the going one. Press again to post anyway.|r")
		return
	end
	await("post", r.key, panel.post.note)
	panel.post.note:SetText("Posting…")
end

local function posted()
	if not waits.post then
		return -- not the panel's post (Blizzard's own Sell window)
	end
	local key = waits.post.key
	waits.post = nil
	live[key] = nil
	-- The next row; the bags update a moment later and the list follows.
	local next
	for i, r in ipairs(rows) do
		if r.key == key then
			next = rows[i + 1] or rows[i - 1]
		end
	end
	chosen = next
	if panel then
		panel.post.note:SetText(Theme.escape(Theme.color.success) .. "Posted.|r")
	end
	if next then
		-- Into Blizzard's Sell window too, as a click on it does.
		search(next, true)
	end
end
ns.on("AUCTION_HOUSE_AUCTION_CREATED", "auction panel", posted)
-- The client warns before some commodity posts (far under the going price): the next press confirms.
-- Blizzard's own window shows its warning too, and its Accept finds no post of its own to confirm:
-- for a post of the panel's, that popup is closed (the next frame, after Blizzard's handler opened it).
local function closeBlizzardWarning()
	C_Timer.After(0, function()
		if StaticPopup_Hide then
			StaticPopup_Hide("AUCTION_HOUSE_POST_WARNING")
		end
	end)
end
ns.on("AUCTION_HOUSE_POST_WARNING", "auction panel", function()
	-- The panel's: its post waiting for an answer, or one it was just warned about. Else it is a post
	-- from Blizzard's own Sell window, and its popup is the player's to answer.
	local fresh = confirm and postedAt and GetTime() - postedAt <= WARNING_WINDOW
	if not (waits.post or fresh) then
		return
	end
	if waits.post and lastArgs then
		confirm = { key = waits.post.key, args = lastArgs }
	end
	closeBlizzardWarning()
	waits.post = nil
	if panel and panel.post.note then
		panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "The auction house warns this price is far from the going one. Press again to post anyway.|r")
	end
end)
-- A post the server refused: say so at once rather than after the wait.
ns.on("AUCTION_HOUSE_POST_ERROR", "auction panel", function()
	if waits.post then
		waits.post = nil
		if panel and panel.post.note then
			panel.post.note:SetText(Theme.escape(Theme.color.danger) .. "The auction house refused the post.|r")
		end
	end
end)

-- Drawing ----------------------------------------------------------------------------------------------------

local function buildScan(page)
	local status = UI.Text(page, "", { size = "lg", medium = true })
	status:SetPoint("TOPLEFT", 0, 0)
	local bar = UI.Bar(page, 1, {}, 8)
	bar:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -10)
	bar:SetPoint("RIGHT", page, "RIGHT")
	local line = UI.Text(page, "", { size = "sm", tone = "muted" })
	line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
	local button = UI.Button(page, "Scan now", function()
		ns.startScan()
	end, { kind = "primary", width = 140, height = 30 })
	button:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -14)
	-- Off at first: a scan starts when the player asks (manual test run 001).
	local scanSettings = ns.settings("scan", { auto = false })
	local auto = UI.Switch(page, scanSettings.auto, function(on)
		scanSettings.auto = on
	end)
	auto:SetPoint("LEFT", button, "RIGHT", 16, 0)
	local autoLabel = UI.Text(page, "Scan when I open the auction house", { size = "sm", tone = "muted" })
	autoLabel:SetPoint("LEFT", auto, "RIGHT", 8, 0)
	local cards = {}
	for i, label in ipairs({ "Listings", "Prices", "Took", "Scanned" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth((W - 40 - 12) / 2)
		if i == 1 then
			c:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -20)
		elseif i % 2 == 0 then
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		else
			c:SetPoint("TOPLEFT", cards[i - 2], "BOTTOMLEFT", 0, -12)
		end
		cards[i] = c
	end
	local note = UI.Text(page, "One full scan every 15 minutes per account: the server's limit. Sellers are never stored.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", cards[3], "BOTTOMLEFT", 0, -16)
	note:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local st = ns.scanState()
		if st.phase == "asking" then
			status:SetText("Asking the server…")
			bar:Set(1, { { value = 0, color = Theme.color.accent } })
		elseif st.phase == "reading" then
			status:SetText(string.format("Reading %s of %s", BreakUpLargeNumbers and BreakUpLargeNumbers(st.done) or st.done, BreakUpLargeNumbers and BreakUpLargeNumbers(st.total) or st.total))
			bar:Set(math.max(1, st.total), { { value = st.done, color = Theme.color.accent } })
		else
			status:SetText(st.wait > 0 and "Scanned" or "Ready to scan")
			bar:Set(1, { { value = st.wait > 0 and 1 or 0, color = Theme.color.accent } })
		end
		line:SetText(st.wait > 0 and string.format("Next full scan in %d:%02d", math.floor(st.wait / 60), st.wait % 60) or "A full scan can start now.")
		if st.wait > 0 or st.phase ~= "idle" then
			button:Disable()
			button:SetAlpha(0.5)
		else
			button:Enable()
			button:SetAlpha(1)
		end
		local last = st.last
		if not last then
			-- After a /reload: the newest scan in the save.
			for _, s in ipairs(ns.db().scans or {}) do
				if s.kind == "full" and (not last or s.t > last.t) then
					last = { t = s.t, auctions = s.auctions, prices = nil }
				end
			end
		end
		cards[1]:Set(last and tostring(last.auctions or 0) or "—", "auctions read")
		cards[2]:Set(last and last.prices and tostring(last.prices) or "—", "item and price pairs")
		cards[3]:Set(last and last.seconds and (last.seconds .. " s") or "—", "asking and reading")
		cards[4]:Set(last and ns.Views.ago(last.t, ns.now()) or "never", last and (last.kind == "partial" and "cut short: not used" or last.kind == "throttled" and "the server said wait") or "")
	end
end

local function buildPost(page)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, text = function(r) return r.name .. Theme.escape(Theme.color.textFaint) .. " ×" .. r.count .. "|r" end,
			color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "market", title = "Market", width = 84, align = "RIGHT", text = function(r) return r.market and money(r.market) or "—" end, sort = function(r) return r.market or 0 end },
		{ key = "post", title = "Post at", width = 92, align = "RIGHT", text = function(r) return r.suggestion and r.suggestion.unit and money(r.suggestion.unit) or "—" end,
			sort = function(r) return r.suggestion and r.suggestion.unit or 0 end },
	}, {
		pageSize = 5,
		rowHeight = 24,
		empty = "Nothing in your bags the auction house takes.",
		itemId = function(r) return r.id end,
		isSelected = function(r) return chosen and r.key == chosen.key end,
		onRowClick = function(r)
			chosen, armed, confirm = r, nil, nil
			search(r, true)
			refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT")
	tbl:SetPoint("RIGHT", page, "RIGHT")
	page.table = tbl

	local detail = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	detail:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	detail:SetPoint("RIGHT", page, "RIGHT")
	detail:SetHeight(252)
	local name = UI.Text(detail, "", { size = "md", medium = true })
	name:SetPoint("TOPLEFT", 14, -12)
	name:SetPoint("RIGHT", detail, "RIGHT", -96, 0)
	-- The selling rules live in the hub: this opens them on a rule for the item in view.
	local ruleButton = UI.Button(detail, "Rule ›", function()
		ns.openPage("rules")
		if ns.rulesPage and chosen then
			ns.rulesPage.chooseScope("add-item")
		end
	end, { width = 72, height = 24 })
	ruleButton:SetPoint("TOPRIGHT", -10, -8)
	page.ruleButton = ruleButton
	local reason = UI.Text(detail, "", { size = "sm" })
	reason:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	reason:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
	local facts = UI.Text(detail, "", { size = "xs", tone = "muted", wrap = true })
	facts:SetPoint("TOPLEFT", reason, "BOTTOMLEFT", 0, -6)
	facts:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
	-- The cheapest listings, the player's own marked, from the last search.
	local listHead = UI.Text(detail, "LISTINGS", { size = "xs", medium = true, tone = "faint" })
	listHead:SetPoint("TOPLEFT", facts, "BOTTOMLEFT", 0, -10)
	local listed = {}
	for i = 1, LISTED do
		local unit = UI.Text(detail, "", { size = "sm", align = "RIGHT" })
		unit:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", 0, -4 - (i - 1) * 15)
		unit:SetWidth(110)
		local qty = UI.Text(detail, "", { size = "xs", tone = "muted" })
		qty:SetPoint("LEFT", unit, "RIGHT", 12, 0)
		qty:SetWidth(200)
		listed[i] = { unit = unit, qty = qty }
	end
	-- Chosen for the item in view and remembered for it; with no item chosen, the default.
	local duration = UI.Dropdown(detail, DURATIONS, settings().duration, function(v)
		if chosen then
			settings().durations[chosen.key] = v
		else
			settings().duration = v
		end
		refresh()
	end)
	page.duration = duration
	duration:SetPoint("BOTTOMLEFT", 14, 12)
	-- How many of a commodity to post, remembered for it; hidden for gear (one at a time).
	local qtyLabel = UI.Text(detail, "Post", { size = "sm", tone = "muted" })
	qtyLabel:SetPoint("BOTTOMLEFT", 14, 56)
	local qty = UI.Slider(detail, 1, 2, 1, 1, function(v)
		if chosen then
			settings().quantities[chosen.key] = v
			refresh()
		end
	end, function(v)
		return tostring(v)
	end)
	qty:SetPoint("LEFT", qtyLabel, "RIGHT", 12, 0)
	qty:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
	page.quantity = qty
	duration:SetWidth(110)
	local button = UI.Button(detail, "Post", function()
		ns.safely("auction post", post)
		refresh()
	end, { kind = "primary", width = 240, height = 30 })
	button:SetPoint("BOTTOMRIGHT", -14, 11)
	page.button = button
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -8)
	page.note:SetPoint("RIGHT", page, "RIGHT")

	function page:Refresh()
		local faint = Theme.escape(Theme.color.textFaint)
		if not chosen then
			name:SetText(faint .. "Choose an item.|r")
			reason:SetText("")
			facts:SetText("Space posts the chosen item while this panel shows.")
			button:Disable()
			button:SetAlpha(0.5)
			return
		end
		local r = chosen
		duration:Set(durationOf(r))
		local many = r.commodity and r.count > 1
		qtyLabel:SetShown(many)
		qty:SetShown(many)
		if many then
			qty:SetRange(1, r.count)
			qty:Set(quantity(r))
		end
		local sug = r.suggestion
		name:SetText(Theme.escape(Theme.quality[r.quality] or Theme.color.text) .. r.name .. "|r" .. faint .. "  ×" .. quantity(r) .. (r.commodity and "" or " (one at a time)") .. "|r")
		local tone = not sug and Theme.color.textFaint or sug.reason == "hold" and Theme.color.warning or Theme.color.accent
		local hint = Post.trendHint(r.trend)
		reason:SetText(Theme.escape(tone) .. (sug and (sug.label or Post.REASONS[sug.reason]) or "No price yet: scan first") .. "|r"
			.. (sug and sug.unit and ("  " .. money(sug.unit) .. faint .. " each|r") or "")
			.. (hint and ("  " .. Theme.escape(r.trend > 0 and Theme.color.warning or Theme.color.textFaint) .. hint .. "|r") or ""))
		local cheapest = r.cheapest and (money(r.cheapest) .. faint .. (r.cheapestFrom == "live" and " (live)" or " (last scan, yours included)") .. "|r") or (faint .. "none|r")
		-- The market's trend on the week, when the pool carries one: green rising, red falling.
		local trend = ""
		if r.trend then
			local tone = r.trend >= 1 and Theme.color.success or r.trend <= -1 and Theme.color.danger or Theme.color.textFaint
			trend = Theme.escape(tone) .. (string.gsub(ns.Prices.trendText(r.trend), "^ · ", " ")) .. "|r"
		end
		facts:SetText(string.format("Cheapest other %s · market %s%s%s · floor %s · normal %s", cheapest,
			r.market and money(r.market) or "—", r.marketFrom and (faint .. " (" .. r.marketFrom .. ")|r") or "", trend,
			sug and money(sug.floor) or "—", sug and money(sug.normal) or "—"))
		local l = live[r.key]
		for i, line in ipairs(listed) do
			local x = l and l.list and l.list[i]
			line.unit:SetText(x and money(x.unit) or (i == 1 and (faint .. (l and "none listed" or "searching…") .. "|r") or ""))
			line.qty:SetText(x and ("×" .. x.qty .. (x.own and (Theme.escape(Theme.color.accent) .. "  yours|r") or "")) or "")
		end
		listHead:SetText(l and l.total and l.total > LISTED and string.format("LISTINGS · CHEAPEST %d OF %d", LISTED, l.total) or "LISTINGS")
		local can = sug and (sug.unit or r.anyway) and not busy()
		if can then
			local label = sug.unit and ("Post " .. quantity(r) .. " × " .. money(sug.unit)) or ("Post anyway: " .. quantity(r) .. " × " .. money(r.anyway))
			button.label:SetText(Theme.skin.titleCaps and string.upper(label) or label)
			button:Enable()
			button:SetAlpha(1)
		else
			button.label:SetText(sug and sug.reason == "hold" and "Under your floor" or "Post")
			button:Disable()
			button:SetAlpha(0.5)
		end
	end
end

-- Shop --------------------------------------------------------------------------------------------------------

-- Shopping lists (design 009, Shop): items with the most to pay a unit, or "under market". Choosing an
-- entry searches it; Buy next buys what its deal covers: a commodity in the client's two steps (a quote,
-- then a second press confirms it; a quote 10% dearer than the deal asks again), an item one auction a
-- press. Lists travel as GFL1 strings. Buying only ever happens on a press.
local shopChosen -- the entry in view: { itemId, maxUnit }
local buying -- { id, n }: the purchase sent, recorded when it succeeds
local overArmed -- the item whose dearer units (past a lowest entry's share) Buy next named; the next press buys
local purchase -- a commodity purchase in progress: { itemId, quantity, expected, quoted, moved }

-- An id for a list or profile made here, and its edited time stamped (design 009, decision 11).
local function newId()
	return string.format("g%x%06x", ns.now(), math.random(0, 0xffffff))
end
local function stamp(item)
	item.id = item.id or newId()
	item.edited = ns.now()
	return item
end

-- The player's lists (saved), and with them, while a sale profile with buy rules is active, the
-- profile's buy list after them (not saved: it is the profile's; "up to" counts what this character holds).
local function lists()
	local s = settings()
	if not s.lists or #s.lists == 0 then
		s.lists = { stamp({ name = "My list", entries = {} }) }
	end
	local shown = {}
	for i, l in ipairs(s.lists) do
		shown[i] = l
	end
	local p = s.profile and s.profiles and s.profiles[s.profile]
	-- The craft queue's missing reagents, at under market value (Crafting page and strip).
	local needs = ns.queueNeeds and ns.queueNeeds() or {}
	if next(needs) then
		local entries = {}
		-- Its prices are kept by item (it is made anew from the queue): s.queuePrices[id] = { maxUnit | pct }.
		local prices = s.queuePrices or {}
		for id, n in pairs(needs) do
			-- A reagent held already (bags and bank) is not to buy: off the list (manual test run 001).
			local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or 0
			-- A vendor's reagent is bought at the vendor (CraftQueue.lua), not here.
			if heldHere(id, inBags) < n and not ns.price.vendorBuy(id) then
				local p = prices[id] or {}
				entries[#entries + 1] = { itemId = id, upTo = n, maxUnit = p.maxUnit, pct = p.pct, lowest = p.lowest }
			end
		end
		table.sort(entries, function(a, b)
			return a.itemId < b.itemId
		end)
		if #entries > 0 then
			shown[#shown + 1] = { name = "Craft queue", entries = entries, profile = true, queue = true }
		end
	end
	if p and #p.buy > 0 then
		local entries = {}
		for i, r in ipairs(p.buy) do
			entries[i] = { itemId = r.itemID, maxUnit = r.maxUnit, upTo = r.upTo }
		end
		shown[#shown + 1] = { name = "Profile: " .. p.name, entries = entries, profile = true }
	end
	s.list = math.max(1, math.min(s.list or 1, #shown))
	return s.lists, shown[s.list], shown
end

-- The deal for an entry from its live book, or nil before a search came back.
local function shopDeal(e)
	-- A list entry is an item id: searched with its plain item key (searchEntry), item level 0.
	local l = live[tostring(e.itemId)] or live[bookKey(e.itemId, false, 0)]
	if not l or not l.levels then
		return nil, l
	end
	if e.lowest and e.upTo then
		-- What the player needs: the cheapest first, and past its share of market, asked first.
		local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(e.itemId)) or 0
		return ns.Shopping.lowestDeal(e, heldHere(e.itemId, inBags), l.levels, ns.Prices.value(e.itemId)), l
	end
	if e.upTo then
		-- A profile's buy rule: up to its target, counting what this character holds (decision 12).
		local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(e.itemId)) or 0
		local limit = ns.Shopping.limit(e, ns.Prices.value(e.itemId))
		if not limit then
			return nil, l
		end
		local step = ns.SalePlan.buy({ itemID = e.itemId, upTo = e.upTo, maxUnit = limit }, heldHere(e.itemId, inBags), l.levels)
		if step.quantity == 0 then
			return nil, l
		end
		return { itemId = e.itemId, quantity = step.quantity, total = step.total, topUnit = step.topUnit, limit = limit }, l
	end
	return ns.Shopping.deal(e, l.levels, ns.Prices.value(e.itemId)), l
end

-- After a full scan: one chat line naming the list items now listed at or under their price.
function ns.announceDeals()
	if settings().dealsAlert == false then
		return
	end
	local _, _, shown = lists()
	local under = ns.Shopping.underPrice(shown, ns.price.cheapest, function(id)
		return ns.Prices.value(id)
	end)
	if #under == 0 then
		return
	end
	local names = {}
	for i = 1, math.min(3, #under) do
		local _, _, _, _, name = ns.price.itemInfo(under[i])
		names[i] = name or ("item " .. under[i])
	end
	ns.say(string.format("%d %s on your lists %s at or under your price: %s%s. Open the Buy tab.", #under, #under == 1 and "item" or "items",
		#under == 1 and "is" or "are", table.concat(names, ", "), #under > 3 and ", …" or ""))
end

-- `open`: chosen by the player, so Blizzard's window shows its listings too (manual test run 001); the
-- panel's own search still reads the book for the deal.
local function searchEntry(e, open)
	if not (e and C_AuctionHouse.MakeItemKey and C_AuctionHouse.SendSearchQuery) then
		return
	end
	local key = C_AuctionHouse.MakeItemKey(e.itemId)
	if open then
		browse(key)
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

-- A purchase with no answer is let go: a later purchase in Blizzard's own window is not recorded as it.
local function letGo()
	buying, purchase = nil, nil
end

-- One press of Buy next.
local function buyNext()
	local e = shopChosen
	if not e or busy() then
		return
	end
	local deal, book = shopDeal(e)
	local note = panel.shop.note
	if purchase and purchase.itemId == e.itemId and purchase.quoted then
		-- The second press: confirm the quote the client gave (as its own Buy button does).
		local p = purchase
		purchase = nil
		C_AuctionHouse.ConfirmCommoditiesPurchase(p.itemId, p.quantity)
		buying = { id = p.itemId, n = p.quantity }
		await("shop", "shop:" .. p.itemId, note, letGo)
		note:SetText("Buying…")
		return
	end
	if not deal then
		note:SetText(book and "Nothing at or under your price now." or "Searching…")
		searchEntry(e)
		return
	end
	-- Over a lowest entry's share of market: said first, bought on the next press.
	if deal.over and overArmed ~= e.itemId then
		overArmed = e.itemId
		local market = ns.Prices.value(e.itemId)
		note:SetText(Theme.escape(Theme.color.warning) .. string.format("Over your %d%% of market: %d for %s (up to %s each%s). Press again to buy, or choose something else.",
			deal.share or 0, deal.quantity, money(deal.total), money(deal.topUnit), market and (", market " .. money(market)) or "") .. "|r")
		return
	end
	overArmed = nil
	if book.commodity then
		purchase = { itemId = e.itemId, quantity = deal.quantity, expected = deal.total }
		C_AuctionHouse.StartCommoditiesPurchase(e.itemId, deal.quantity)
		note:SetText("Asking the auction house for a price…")
	else
		-- The cheapest auction by someone else at or under the limit: one a press.
		for _, a in ipairs(book.levels) do
			if a.own == 0 and a.unitPrice <= deal.limit and a.auctionID then
				C_AuctionHouse.PlaceBid(a.auctionID, a.buyout)
				buying = { id = e.itemId, n = a.quantity or 1 }
				await("shop", "shop:" .. e.itemId, note, letGo)
				note:SetText("Buying one for " .. money(a.buyout) .. "…")
				return
			end
		end
		note:SetText("Nothing at or under your price now.")
	end
end

ns.on("COMMODITY_PRICE_UPDATED", "auction shop", function(unit, total)
	if not purchase or not panel or not panel.shop.note then
		return
	end
	purchase.quoted = total
	purchase.moved = ns.Shopping.moved(purchase.expected, total)
	local text = string.format("%d for %s", purchase.quantity, money(total))
	panel.shop.note:SetText(purchase.moved and (Theme.escape(Theme.color.warning) .. "The price moved: " .. text .. " (the deal was " .. money(purchase.expected) .. "). Press again to buy anyway.|r")
		or ("Press again to buy " .. text .. "."))
	refresh()
end)
-- What was bought since the mailbox was last read, for the craft queue: retail sends a purchase to the
-- mailbox, so the bags do not show it (manual test run 001: a reagent bought stayed on the Craft queue
-- list). settings().bought = { { id, n, t } }; dropped once the mailbox has been read after it.
local function recordBought(b)
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

local function bought(ok, why)
	if not panel or not panel.shop.note then
		return -- a purchase from Blizzard's own window, the Shop not drawn
	end
	if ok and buying then
		recordBought(buying)
	end
	buying = nil
	waits.shop, purchase = nil, nil
	panel.shop.note:SetText(ok and (Theme.escape(Theme.color.success) .. "Bought.|r") or (Theme.escape(Theme.color.danger) .. (why or "The purchase failed.") .. "|r"))
	if shopChosen then
		live[tostring(shopChosen.itemId)], live[bookKey(shopChosen.itemId, false, 0)] = nil, nil
		searchEntry(shopChosen)
	end
	refresh()
end
ns.on("COMMODITY_PURCHASE_SUCCEEDED", "auction shop", function()
	bought(true)
end)
ns.on("COMMODITY_PURCHASE_FAILED", "auction shop", function()
	bought(false, "The purchase failed: the price or the stock changed.")
end)
ns.on("COMMODITY_PRICE_UNAVAILABLE", "auction shop", function()
	bought(false, "No price: the stock changed. Search again.")
end)
ns.on("AUCTION_HOUSE_PURCHASE_COMPLETED", "auction shop", function()
	bought(true)
end)

-- Buying only (owner's answers, 2026-10-24): the list and Buy next, the list's items with their deals,
-- and Edit lists, which opens the hub's Shopping lists page where lists and their items are made,
-- named, priced and shared.
local function buildShop(page)
	local s = settings()
	local function names()
		local out = {}
		for i, l in ipairs(select(3, lists())) do
			out[i] = { value = i, label = l.name }
		end
		return out
	end
	local buy = UI.Button(page, "Buy next", function()
		ns.safely("auction shop", buyNext)
	end, { kind = "primary", width = 200, height = 28 })
	buy:SetPoint("TOPRIGHT", 0, 0)
	page.buy = buy
	local listPick
	local function rebuildPick()
		if listPick then
			listPick:SetOptions(names())
			listPick:Set(s.list or 1)
			return
		end
		listPick = UI.Dropdown(page, names(), s.list or 1, function(v)
			s.list = v
			shopChosen = nil
			refresh()
		end)
		listPick:SetPoint("TOPLEFT")
		listPick:SetPoint("RIGHT", buy, "LEFT", -10, 0)
	end
	rebuildPick()
	page.rebuildPick = rebuildPick

	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "max", title = "Up to", width = 100, align = "RIGHT", text = function(r)
			local price = r.maxUnit and money(r.maxUnit) or r.pct and (r.pct .. "%") or r.lowest and "lowest" or "market"
			return (r.upTo and (r.upTo .. " at ") or "") .. price
		end },
		{ key = "deal", title = "Deal", width = 120, align = "RIGHT", text = function(r)
			if r.deal and r.deal.over then
				return Theme.escape(Theme.color.warning) .. "over: " .. r.deal.quantity .. " for " .. money(r.deal.total) .. "|r"
			end
			return r.deal and (r.deal.quantity .. " for " .. money(r.deal.total)) or (r.searched and "—" or "")
		end },
	}, {
		pageSize = 9,
		rowHeight = 24,
		empty = "Nothing on this list yet: Edit lists adds items.",
		itemId = function(r) return r.itemId end,
		isSelected = function(r) return shopChosen and r.itemId == shopChosen.itemId end,
		onRowClick = function(r)
			shopChosen, purchase = r.entry, nil
			searchEntry(r.entry, true)
			refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT", 0, -38)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	page.table = tbl
	local editLists = UI.Button(page, "Edit lists ›", function()
		ns.openPage("lists")
	end, { width = 110, height = 26 })
	editLists:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	page.editLists = editLists
	-- Anchored to the table, not the button: with the note hung on the button at its left, that button's
	-- text was never placed now and then (manual test run 001, /gf uidebug: Remove, then Edit lists).
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -46)
	page.note:SetPoint("RIGHT", page, "RIGHT")

	function page:Refresh()
		rebuildPick() -- names and the chosen list as the Shopping lists page left them
		local _, list = lists()
		-- An item no longer on the list in view (the queue cleared, the list changed) is let go.
		local still = false
		for _, e in ipairs(list.entries) do
			if shopChosen and e.itemId == shopChosen.itemId then
				still = true
			end
		end
		if shopChosen and not still then
			shopChosen, purchase, overArmed = nil, nil, nil
		end
		local shown = {}
		for i, e in ipairs(list.entries) do
			local quality, _, _, _, name = ns.price.itemInfo(e.itemId)
			local deal, book = shopDeal(e)
			shown[i] = { entry = e, itemId = e.itemId, maxUnit = e.maxUnit, pct = e.pct, lowest = e.lowest, upTo = e.upTo, name = name or ("item " .. e.itemId), quality = quality or 1, deal = deal, searched = book ~= nil }
		end
		tbl:SetRows(shown)
		local deal = shopChosen and shopDeal(shopChosen)
		local label = purchase and purchase.quoted and ("Confirm: " .. purchase.quantity .. " for " .. money(purchase.quoted))
			or (deal and ("Buy " .. deal.quantity .. " for " .. money(deal.total))) or "Buy next"
		buy.label:SetText(Theme.skin.titleCaps and string.upper(label) or label)
		local can = shopChosen and not busy()
		if can then
			buy:Enable()
			buy:SetAlpha(1)
		else
			buy:Disable()
			buy:SetAlpha(0.5)
		end
	end
end

-- Cancel undercut ----------------------------------------------------------------------------------------------

-- The player's own auctions (design 009, Cancel undercut; owner: build it now, 5% by default): each
-- searched in turn against other players' listings (a few sneaky cheap units passed over); those
-- undercut by more than the tolerance are listed, and Cancel next cancels the most undercut one a press
-- (CancelAuction is a hardware event, and costs the deposit). The items come back by mail.
local TOLERANCES = { { value = 1, label = "1%" }, { value = 5, label = "5%" }, { value = 10, label = "10%" } }
local owned = {} -- { auctionID, itemID, key, name, quality, quantity, unit, commodity, cheapest, under }
local checking -- the index of the auction being searched, while a check runs (0: reading the auctions)
local checkRun -- the check running, so a timer of an earlier one leaves it be

local function tolerance()
	return settings().tolerance or 5
end

-- The cheapest other listing for an owned auction, from the last search of its item.
local function cheapestFor(a)
	local book = live[bookKey(a.itemID, a.commodity, a.itemKey and a.itemKey.itemLevel)]
	return book and book.cheapest or nil, book ~= nil
end

local function readOwned()
	owned = {}
	local n = C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetNumOwnedAuctions() or 0
	for i = 1, n do
		local info = C_AuctionHouse.GetOwnedAuctionInfo(i)
		-- Active ones only (status 0); sold ones wait in the list for their mail.
		if info and info.itemKey and (info.status or 0) == 0 and info.buyoutAmount and info.buyoutAmount > 0 then
			local keyInfo = C_AuctionHouse.GetItemKeyInfo and C_AuctionHouse.GetItemKeyInfo(info.itemKey)
			local commodity = keyInfo and keyInfo.isCommodity or false
			local qty = info.quantity or 1
			-- ASSUMED: a commodity's buyoutAmount is its unit price, an item's the whole auction's.
			local unit = commodity and info.buyoutAmount or math.floor(info.buyoutAmount / math.max(1, qty) + 0.5)
			local quality, _, _, _, name = ns.price.itemInfo(info.itemKey.itemID)
			owned[#owned + 1] = { auctionID = info.auctionID, itemID = info.itemKey.itemID, itemKey = info.itemKey, quantity = qty,
				unit = unit, commodity = commodity, name = (keyInfo and keyInfo.itemName) or name or ("item " .. info.itemKey.itemID), quality = quality or 1 }
		end
	end
end

-- Searches the next owned auction's item; the results event moves the check on.
local function checkNext()
	checking = (checking or 0) + 1
	local a = owned[checking]
	if not a then
		checking = nil
		refresh()
		return
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(a.itemKey, sorts, true)
	-- A search the server never answers (throttled) does not stall the check: on to the next.
	local at = checking
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if checking == at and not a.answered then
			a.answered = true
			ns.safely("auction cancel", checkNext)
		end
	end)
	refresh()
end

local function startCheck()
	if C_AuctionHouse.QueryOwnedAuctions then
		C_AuctionHouse.QueryOwnedAuctions({ { sortOrder = 0, reverseSort = false } })
	end
	checking = 0
	panel.cancel.note:SetText("Reading your auctions…")
	-- The list never coming (throttled, the auction house closing) does not leave the check running.
	local run = {}
	checkRun = run
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if checking == 0 and checkRun == run then
			checking = nil
			if panel and panel.cancel.note then
				panel.cancel.note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the auction house; check again in a moment.|r")
			end
			refresh()
		end
	end)
end

ns.on("OWNED_AUCTIONS_UPDATED", "auction cancel", function()
	if checking == 0 then
		readOwned()
		checkNext()
	end
end)
-- A search answered moves the check to the next auction (both kinds of results).
-- Only the answer for the auction being checked moves it on, once (other searches, the panel's or
-- Blizzard's, and repeated events for the same item do not); 0.7 s apart keeps the check under the
-- search limit of 100 a minute.
local CHECK_GAP = 0.7
local function searched(what)
	local a = checking and checking > 0 and owned[checking]
	if not a or a.answered then
		return
	end
	local id = type(what) == "table" and what.itemID or what
	if id ~= a.itemID then
		return
	end
	-- Gear: the answer for its own item level (two auctions of one item may be checked in turn).
	if type(what) == "table" and what.itemLevel and a.itemKey and a.itemKey.itemLevel and what.itemLevel ~= a.itemKey.itemLevel then
		return
	end
	a.answered = true
	C_Timer.After(CHECK_GAP, function()
		ns.safely("auction cancel", checkNext)
	end)
end
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction cancel", searched)
ns.on("ITEM_SEARCH_RESULTS_UPDATED", "auction cancel", searched)

-- The owned auctions undercut past the tolerance, most undercut first.
local function undercut()
	for _, a in ipairs(owned) do
		a.cheapest = cheapestFor(a)
	end
	return Post.undercutList(owned, tolerance())
end

local function cancelNext()
	if busy() then
		return
	end
	local a = undercut()[1]
	if not a then
		panel.cancel.note:SetText("Nothing undercut past " .. tolerance() .. "%.")
		return
	end
	C_AuctionHouse.CancelAuction(a.auctionID)
	await("cancel", "cancel:" .. a.auctionID, panel.cancel.note)
	panel.cancel.note:SetText("Cancelling " .. a.name .. "…")
end

ns.on("AUCTION_CANCELED", "auction cancel", function(auctionID)
	if waits.cancel and waits.cancel.key == "cancel:" .. tostring(auctionID) then
		waits.cancel = nil
	end
	for i, a in ipairs(owned) do
		if a.auctionID == auctionID then
			table.remove(owned, i)
			break
		end
	end
	if panel and panel.cancel.note then
		panel.cancel.note:SetText(Theme.escape(Theme.color.success) .. "Cancelled: it comes back by mail.|r")
		refresh()
	end
end)

local function buildCancel(page)
	local tol = UI.Dropdown(page, TOLERANCES, tolerance(), function(v)
		settings().tolerance = v
		refresh()
	end)
	-- The label, then the dropdown just after it, leaving room before Check my auctions at the right in
	-- the panel's 384 pixels (manual test run 001: they touched).
	local tolLabel = UI.Text(page, "Undercut past", { size = "sm", tone = "muted" })
	tolLabel:SetPoint("TOPLEFT", 0, -7)
	tol:SetPoint("LEFT", tolLabel, "RIGHT", 10, 0)
	tol:SetWidth(84)
	local check = UI.Button(page, "Check my auctions", function()
		ns.safely("auction cancel", startCheck)
	end, { width = 150, height = 28 })
	check:SetPoint("TOPRIGHT", 0, 0)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Your auction", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end,
			text = function(r) return r.quantity > 1 and (r.name .. Theme.escape(Theme.color.textFaint) .. " ×" .. r.quantity .. "|r") or r.name end },
		{ key = "unit", title = "Yours", width = 74, align = "RIGHT", text = function(r) return money(r.unit) end },
		{ key = "cheapest", title = "Cheapest", width = 74, align = "RIGHT", text = function(r) return r.cheapest and money(r.cheapest) or (r.searched and "—" or "") end },
		{ key = "under", title = "Under", width = 56, align = "RIGHT", text = function(r) return r.under and r.under > 0 and (r.under .. "%") or "" end,
			color = function(r) return r.under and r.under > tolerance() and Theme.color.warning or Theme.color.textMuted end, sort = function(r) return r.under or 0 end },
	}, { pageSize = 9, rowHeight = 24, empty = "Check your auctions to see which are undercut.", itemId = function(r) return r.itemID end,
		-- A click shows the item's listings in Blizzard's window (manual test run 001).
		onRowClick = function(r)
			browse(r.itemKey)
		end })
	tbl:SetPoint("TOPLEFT", 0, -40)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local go = UI.Button(page, "Cancel next", function()
		ns.safely("auction cancel", cancelNext)
		refresh()
	end, { kind = "primary", width = 200, height = 30 })
	go:SetPoint("TOPRIGHT", tbl, "BOTTOMRIGHT", 0, -10)
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -16)
	page.note:SetPoint("RIGHT", go, "LEFT", -12, 0)
	function page:Refresh()
		local list = undercut()
		for _, a in ipairs(owned) do
			a.searched = select(2, cheapestFor(a))
		end
		tbl:SetRows(owned)
		local first = list[1]
		if checking == 0 then
			go.label:SetText("Reading…")
		elseif checking then
			go.label:SetText(string.format("Checking %d of %d…", checking, #owned))
		elseif first then
			local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(first.auctionID)
			go.label:SetText("Cancel " .. first.name .. (cost and cost > 0 and (" (" .. money(cost) .. ")") or ""))
		else
			go.label:SetText("Cancel next")
		end
		local can = first and not checking and not busy()
		if can then
			go:Enable()
			go:SetAlpha(1)
		else
			go:Disable()
			go:SetAlpha(0.5)
		end
		if not checking and page.note:GetText() == "Reading your auctions…" then
			page.note:SetText(#owned == 0 and "You have no auctions up."
				or string.format("%d of your %d auctions are undercut past %d%%.", #list, #owned, tolerance()))
		end
	end
end

-- The selling rules, a page of the hub (manual test run 001: too much for the panel, and hard to read):
-- the rule's controls at the left, each saying what it does; at the right what the rule does to an item
-- worth 10g, and the sale profile.
local function buildRule(page)
	local s = settings()
	s.overrides = s.overrides or { items = {}, classes = {} }
	s.overrides.items = s.overrides.items or {}
	s.overrides.classes = s.overrides.classes or {}
	local LEFT, LABEL = 400, 130 -- the controls' column, and where a control starts in it
	local RIGHT = LEFT + 28 -- the column at the right starts here
	-- Which rule the controls below edit: the default, or an override (only the fields it changes).
	local scope = "default"
	local function className(class)
		local name = C_Item and C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(class) or (GetItemClassInfo and GetItemClassInfo(class))
		return name or ("category " .. class)
	end
	local function target()
		local kind, id = string.match(scope, "^(%a+):(%d+)$")
		if kind == "item" then
			return s.overrides.items[tonumber(id)]
		elseif kind == "class" then
			return s.overrides.classes[tonumber(id)]
		end
		return s.rule
	end
	-- The values the controls show: the default's with the override's over them.
	local function shown()
		local t, out = target(), {}
		for k, v in pairs(s.rule) do
			out[k] = v
		end
		if t ~= s.rule then
			for k, v in pairs(t or {}) do
				out[k] = v
			end
		end
		return out
	end

	-- What the rule does, at the right.
	local exampleCard = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	exampleCard:SetPoint("TOPLEFT", RIGHT, 0)
	exampleCard:SetPoint("RIGHT", page, "RIGHT")
	exampleCard:SetHeight(196)
	local exampleHead = UI.Text(exampleCard, "WHAT IT DOES TO AN ITEM WORTH 10G", { size = "xs", medium = true, tone = "faint" })
	exampleHead:SetPoint("TOPLEFT", 14, -12)
	local exampleText = UI.Text(exampleCard, "", { size = "xs", wrap = true })
	exampleText:SetPoint("TOPLEFT", exampleHead, "BOTTOMLEFT", 0, -10)
	exampleText:SetPoint("RIGHT", exampleCard, "RIGHT", -14, 0)
	local function showExamples()
		local lines = Post.examples(shown(), money)
		for i, l in ipairs(lines) do
			lines[i] = Theme.escape(Theme.color.accent) .. "•|r " .. l
		end
		exampleText:SetText(table.concat(lines, "\n\n"))
	end

	local function set(field, v)
		local t = target()
		if t then
			t[field] = v
		end
		showExamples()
	end
	-- A row: its name, the control, and a line under them saying what it does.
	local function row(y, label, control, says)
		local l = UI.Text(page, label, { size = "sm" })
		l:SetPoint("TOPLEFT", 0, y)
		control:SetPoint("TOPLEFT", LABEL, y + 6)
		control:SetPoint("RIGHT", page, "LEFT", LEFT, 0)
		local line = UI.Text(page, says, { size = "xs", tone = "faint", wrap = true })
		line:SetPoint("TOPLEFT", 0, y - 32)
		line:SetWidth(LEFT)
		return control
	end
	local undercuts = {}
	for _, u in ipairs(Post.UNDERCUTS) do
		undercuts[#undercuts + 1] = { value = u.value, label = u.label }
	end
	local v = shown()
	local controls = {
		undercut = row(-84, "Undercut by", UI.Dropdown(page, undercuts, v.undercut, function(x) set("undercut", x) end),
			"How far under the cheapest other seller you post."),
		floor = row(-156, "Never under", UI.Slider(page, 50, 100, 5, v.floor, function(x) set("floor", x) end, function(x) return x .. "%" end),
			"Your floor, as a share of the market value: nothing posts below it."),
		normal = row(-228, "Normal price", UI.Slider(page, 100, 200, 5, v.normal, function(x) set("normal", x) end, function(x) return x .. "%" end),
			"What you ask when no one else sells it, or everyone asks more than this."),
		belowFloor = row(-300, "Under the floor", UI.Dropdown(page, { { value = "hold", label = "Hold it" }, { value = "floor", label = "Post at the floor" } }, v.belowFloor, function(x) set("belowFloor", x) end),
			"When undercutting would go under your floor: keep the item, or post at the floor anyway."),
	}
	local scopePick, removeButton
	local function pickOptions()
		local out = { { value = "default", label = "Every item" } }
		for id in pairs(s.overrides.items) do
			local _, _, _, _, name = ns.price.itemInfo(id)
			out[#out + 1] = { value = "item:" .. id, label = "Item: " .. (name or id) }
		end
		for class in pairs(s.overrides.classes) do
			out[#out + 1] = { value = "class:" .. class, label = "Category: " .. className(class) }
		end
		out[#out + 1] = { value = "add-item", label = "+ The item chosen in Sell" }
		out[#out + 1] = { value = "add-class", label = "+ Its category" }
		return out
	end
	local rebuildPick
	local function choose(value)
		if value == "add-item" or value == "add-class" then
			if not chosen then
				value = "default"
			elseif value == "add-item" then
				s.overrides.items[chosen.id] = s.overrides.items[chosen.id] or {}
				value = "item:" .. chosen.id
			else
				local _, _, class = ns.price.itemInfo(chosen.id)
				if class then
					s.overrides.classes[class] = s.overrides.classes[class] or {}
					value = "class:" .. class
				else
					value = "default"
				end
			end
		end
		scope = value
		local now = shown()
		for field, c in pairs(controls) do
			c:Set(now[field])
		end
		removeButton:SetShown(scope ~= "default")
		rebuildPick()
		showExamples()
	end
	rebuildPick = function()
		if scopePick then
			scopePick:SetOptions(pickOptions())
			scopePick:Set(scope)
			return
		end
		scopePick = UI.Dropdown(page, pickOptions(), scope, choose)
		scopePick:SetPoint("TOPLEFT", LABEL, 6)
		scopePick:SetPoint("RIGHT", page, "LEFT", LEFT - 94, 0)
	end
	local pickLabel = UI.Text(page, "Rule for", { size = "sm" })
	pickLabel:SetPoint("TOPLEFT", 0, 0)
	removeButton = UI.Button(page, "Remove", function()
		local kind, id = string.match(scope, "^(%a+):(%d+)$")
		if kind == "item" then
			s.overrides.items[tonumber(id)] = nil
		elseif kind == "class" then
			s.overrides.classes[tonumber(id)] = nil
		end
		choose("default")
	end, { kind = "ghost", width = 86, height = 28 })
	removeButton:SetPoint("TOPRIGHT", page, "TOPLEFT", LEFT, 6)
	removeButton:Hide()
	rebuildPick()
	page.chooseScope = choose
	page.setField = set
	local scopeLine = UI.Text(page, "A rule for one item or a category changes only what you set for it; the rest comes from Every item.", { size = "xs", tone = "faint", wrap = true })
	scopeLine:SetPoint("TOPLEFT", 0, -34)
	scopeLine:SetWidth(LEFT)
	local note = UI.Text(page, "The market value is everyone's price from the companion, else your own last scan. Prices are whole silver.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", 0, -376)
	note:SetWidth(LEFT)

	-- Sale profiles (GFP1 strings from the site or other players): one active at a time.
	s.profiles = s.profiles or {}
	local head = UI.Text(page, "SALE PROFILE", { size = "xs", medium = true, tone = "faint" })
	head:SetPoint("TOPLEFT", exampleCard, "BOTTOMLEFT", 0, -18)
	local pick
	local summary = UI.Text(page, "", { size = "xs", tone = "muted", wrap = true })
	local function options()
		local out = { { value = 0, label = "None: the rules" } }
		for i, p in ipairs(s.profiles) do
			out[#out + 1] = { value = i, label = p.name }
		end
		return out
	end
	local function describe()
		local p = activeProfile()
		summary:SetText(p and string.format("%s by %s: %d items to sell, %d to buy. The items it names follow it instead of the rules.", p.name, p.author ~= "" and p.author or "?", #p.sell, #p.buy)
			or "A profile from gold-forever.app/me/lists prices the items it names; the rules price the rest.")
	end
	local function rebuild()
		if pick then
			pick:SetOptions(options())
			pick:Set(s.profile or 0)
			describe()
			return
		end
		pick = UI.Dropdown(page, options(), s.profile or 0, function(v)
			s.profile = v ~= 0 and v or nil
			describe()
		end)
		pick:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
		pick:SetPoint("RIGHT", page, "RIGHT")
		summary:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -8)
		summary:SetPoint("RIGHT", page, "RIGHT")
		describe()
	end
	rebuild()
	local field = UI.SearchBox(page, "Paste a GFP1 string", nil)
	field:SetMaxLetters(0) -- a profile string runs to 16 KB (SalePlan.decode bounds it)
	field:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -48)
	field:SetPoint("RIGHT", page, "RIGHT", -152, 0)
	local message = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	message:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -6)
	message:SetPoint("RIGHT", page, "RIGHT")
	local function doImport(text)
		local p, err = ns.SalePlan.decode(text or field:GetText())
		if not p then
			message:SetText(Theme.escape(Theme.color.danger) .. err .. "|r")
			return
		end
		-- Decision 11: each profile has an id and an edited time, so a later sync keeps the newest.
		stamp(p)
		s.profiles[#s.profiles + 1] = p
		s.profile = #s.profiles
		field:SetText("")
		rebuild()
		message:SetText("Imported and in use.")
	end
	local import = UI.Button(page, "Import", function()
		doImport()
	end, { width = 72, height = 28 })
	import:SetPoint("LEFT", field, "RIGHT", 6, 0)
	local export = UI.Button(page, "Export", function()
		local p = activeProfile()
		if p then
			field:SetText(ns.SalePlan.encode(p))
			field:SetFocus()
			field:HighlightText()
			message:SetText("Copy it with Ctrl+C.")
		end
	end, { width = 72, height = 28 })
	export:SetPoint("LEFT", import, "RIGHT", 4, 0)
	page.importProfile = doImport
	showExamples()
	-- The newest drawn (the window in the look in use), for the Sell tab's Rule button and the tests.
	ns.rulesPage = page
	function page:Refresh()
		choose(scope) -- an override added or removed from the Sell tab shows
	end
end
ns.buildSellingRules = buildRule

-- Shopping lists, a page of the hub (owner's answers, 2026-10-24, manual test run 001: the Buy tab had
-- no way to rename or delete a list or to price an item, and adding needed a click in a field first).
-- Lists at the left (new, rename, delete, import, export); the chosen list's items at the right, added by
-- dropping an item on the slot or shift-clicking it anywhere while the page shows; the chosen item's most
-- per unit (under market, a fixed price or a share of the market value) and how many to hold. The craft
-- queue's list is here too: its items follow the queue, their prices are set here.
local function itemNameOf(id)
	local _, _, _, _, name = ns.price.itemInfo(id)
	return name or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
end
local PRICE_MODES = { { value = "market", label = "Under market" }, { value = "fixed", label = "Fixed price" }, { value = "pct", label = "% of market" },
	{ value = "lowest", label = "Lowest, ask over %" } }

local function buildLists(page)
	local s = settings()
	local LEFT = 220
	local chosenItem -- the itemId chosen on the right

	-- Left: the lists.
	local head = UI.Text(page, "LISTS", { size = "xs", medium = true, tone = "faint" })
	head:SetPoint("TOPLEFT")
	local listTable = UI.Table(page, {
		{ key = "name", title = "List", flex = 1, color = function(r) return r.generated and Theme.color.textMuted or Theme.color.text end },
		{ key = "n", title = "Items", width = 44, align = "RIGHT" },
	}, {
		pageSize = 8,
		rowHeight = 24,
		isSelected = function(r) return r.index == s.list end,
		onRowClick = function(r)
			s.list, chosenItem = r.index, nil
			page:Refresh()
		end,
	})
	listTable:SetPoint("TOPLEFT", 0, -18)
	listTable:SetWidth(LEFT)
	local name = UI.SearchBox(page, "Rename the list", nil)
	name:SetPoint("TOPLEFT", listTable, "BOTTOMLEFT", 0, -10)
	name:SetWidth(LEFT)
	local function own()
		local mine, list = lists()
		for i, l in ipairs(mine) do
			if l == list then
				return list, i, mine
			end
		end
		return nil, nil, mine
	end
	local function renameTo(text)
		local list = own()
		text = string.match((string.gsub(text or "", "|", "")), "^%s*(.-)%s*$")
		if list and text ~= "" then
			list.name = string.sub(text, 1, 40)
			stamp(list)
		end
		page:Refresh()
	end
	name:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		renameTo(self:GetText())
	end)
	local newList = UI.Button(page, "New", function()
		local mine = lists()
		mine[#mine + 1] = stamp({ name = "List " .. (#mine + 1), entries = {} })
		s.list, chosenItem = #mine, nil
		page:Refresh()
		name:SetFocus()
		name:HighlightText()
	end, { width = 70, height = 26 })
	newList:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	local delete = UI.Button(page, "Delete", function(self)
		local list, i, mine = own()
		if not list then
			return
		end
		-- A second press deletes (a list can hold many items).
		if self.armed ~= list then
			self.armed = list
			page.note:SetText(Theme.escape(Theme.color.warning) .. "Press Delete again to delete \"" .. list.name .. "\".|r")
			return
		end
		self.armed = nil
		-- Remembered, so the site's copy of it does not bring it back (it is not deleted there).
		if list.id then
			s.removedShared = s.removedShared or {}
			s.removedShared[list.id] = ns.now()
		end
		table.remove(mine, i)
		s.list, chosenItem = math.max(1, i - 1), nil
		page.note:SetText("Deleted.")
		page:Refresh()
	end, { width = 70, height = 26 })
	delete:SetPoint("LEFT", newList, "RIGHT", 5, 0)
	local exportButton, importButton

	-- Right: the chosen list's items.
	local X = LEFT + 24
	local title = UI.Text(page, "", { size = "lg", medium = true })
	title:SetPoint("TOPLEFT", X, 0)
	title:SetPoint("RIGHT", page, "RIGHT", -240, 0)
	local crafting = UI.Button(page, "Open Crafting ›", function()
		ns.openPage("crafting")
	end, { width = 120, height = 24 })
	crafting:SetPoint("TOPRIGHT", 0, 2)
	local queueWindow = UI.Button(page, "Queue window", function()
		if ns.openCraftQueue then
			ns.openCraftQueue()
		end
	end, { width = 110, height = 24 })
	queueWindow:SetPoint("RIGHT", crafting, "LEFT", -6, 0)
	-- The slot: drop an item on it (or click it holding one), or shift-click an item anywhere.
	local slot = CreateFrame("Button", nil, page)
	slot:SetSize(36, 36)
	slot:SetPoint("TOPLEFT", X, -26)
	UI.surface(slot, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, Theme.skin.radius and 6 or 0)
	local plus = UI.Text(slot, "+", { size = "xl", tone = "faint", align = "CENTER" })
	plus:SetPoint("CENTER", 0, 1)
	local slotLine = UI.Text(page, "Drop an item here, or shift-click one anywhere, to add it.", { size = "xs", tone = "faint", wrap = true })
	slotLine:SetPoint("LEFT", slot, "RIGHT", 10, 0)
	slotLine:SetPoint("RIGHT", page, "RIGHT")
	local items = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "price", title = "At most", width = 110, align = "RIGHT" },
		{ key = "many", title = "How many", width = 80, align = "RIGHT" },
	}, {
		pageSize = 6,
		rowHeight = 24,
		empty = "No items yet.",
		itemId = function(r) return r.itemId end,
		isSelected = function(r) return r.itemId == chosenItem end,
		onRowClick = function(r)
			chosenItem = r.itemId
			page:Refresh()
		end,
	})
	items:SetPoint("TOPLEFT", X, -72)
	items:SetPoint("RIGHT", page, "RIGHT")

	-- The chosen item's settings.
	local edit = CreateFrame("Frame", nil, page)
	edit:SetPoint("TOPLEFT", items, "BOTTOMLEFT", 0, -10)
	edit:SetPoint("RIGHT", page, "RIGHT")
	edit:SetHeight(64)
	local editName = UI.Text(edit, "", { size = "sm", medium = true })
	editName:SetPoint("TOPLEFT")
	local setPrice, amount
	-- A kind chosen without its number yet (Fixed price, % of market): shown, the box waiting for it.
	local pending
	local mode = UI.Dropdown(edit, PRICE_MODES, "market", function(v)
		if v == "market" then
			pending = nil
			setPrice(v, "")
		else
			pending = { id = chosenItem, kind = v }
			page:Refresh()
			amount:SetText("")
			amount:SetFocus()
		end
	end)
	mode:SetPoint("TOPLEFT", 0, -20)
	mode:SetWidth(130)
	amount = UI.SearchBox(edit, "", nil)
	amount:SetPoint("LEFT", mode, "RIGHT", 8, 0)
	amount:SetWidth(90)
	local manyLabel = UI.Text(edit, "How many", { size = "sm", tone = "muted" })
	manyLabel:SetPoint("LEFT", amount, "RIGHT", 14, 0)
	local many = UI.SearchBox(edit, "any", nil)
	many:SetPoint("LEFT", manyLabel, "RIGHT", 8, 0)
	many:SetWidth(60)
	local removeItem = UI.Button(edit, "Remove", function()
		local list = own()
		if not list then
			return
		end
		for i, e in ipairs(list.entries) do
			if e.itemId == chosenItem then
				table.remove(list.entries, i)
				stamp(list)
				break
			end
		end
		chosenItem = nil
		page:Refresh()
	end, { width = 80, height = 26 })
	removeItem:SetPoint("TOPRIGHT", 0, -20)

	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", edit, "BOTTOMLEFT", 0, -6)
	page.note:SetPoint("RIGHT", page, "RIGHT")

	-- Import and export, under the lists: one field, the GFL1 string in or out.
	local field = UI.SearchBox(page, "Paste a GFL1 string", nil)
	field:SetMaxLetters(0)
	field:SetPoint("TOPLEFT", newList, "BOTTOMLEFT", 0, -14)
	field:SetWidth(LEFT)
	importButton = UI.Button(page, "Import", function()
		local got, err = ns.Shopping.decode(field:GetText())
		if not got then
			page.note:SetText(Theme.escape(Theme.color.danger) .. err .. "|r")
			return
		end
		local mine = lists()
		for _, l in ipairs(got) do
			mine[#mine + 1] = stamp(l)
		end
		s.list, chosenItem = #mine, nil
		field:SetText("")
		field:ClearFocus()
		page.note:SetText(string.format("Imported %d %s.", #got, #got == 1 and "list" or "lists"))
		page:Refresh()
	end, { width = 70, height = 26 })
	importButton:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -8)
	exportButton = UI.Button(page, "Export", function()
		local _, list = lists()
		field:SetText(ns.Shopping.encode({ { name = list.name, entries = list.entries } }))
		field:SetFocus()
		field:HighlightText()
		page.note:SetText("Copy it with Ctrl+C; anyone with Gold Forever can import it, or keep it at gold-forever.app/me/lists.")
	end, { width = 70, height = 26 })
	exportButton:SetPoint("LEFT", importButton, "RIGHT", 5, 0)

	-- The chosen entry, and where its price is kept (the craft queue's by item, others on the entry).
	local function chosenEntry()
		local _, list = lists()
		for _, e in ipairs(list.entries) do
			if e.itemId == chosenItem then
				return e, list
			end
		end
		return nil, list
	end
	local function priceTarget(e, list)
		if list.queue then
			s.queuePrices = s.queuePrices or {}
			s.queuePrices[e.itemId] = s.queuePrices[e.itemId] or {}
			return s.queuePrices[e.itemId]
		end
		return not list.profile and e or nil
	end
	function setPrice(kind, text)
		local e, list = chosenEntry()
		local t = e and priceTarget(e, list)
		if not t then
			return
		end
		local maxUnit, share
		if kind == "fixed" then
			maxUnit = ns.Shopping.parseGold(text)
		elseif kind == "pct" or kind == "lowest" then
			local n = tonumber(string.match(text or "", "%d+") or "")
			share = n and n > 0 and math.min(n, 1000) or nil
		end
		if kind ~= "market" and not maxUnit and not share then
			page.note:SetText(Theme.escape(Theme.color.warning) .. (kind == "fixed" and "Type a price in gold, as 4.5 or 4g 50s, then Enter."
				or kind == "lowest" and "Type the share of the market value to ask over, as 120, then Enter." or "Type a share of the market value, as 80, then Enter.") .. "|r")
			return
		end
		t.maxUnit, t.pct, t.lowest = maxUnit, kind == "pct" and share or nil, kind == "lowest" and share or nil
		if kind == "lowest" and not e.upTo and not list.queue then
			page.note:SetText("Set How many too: Lowest buys until you hold that many, asking over your share.")
		end
		if not list.queue then
			stamp(list)
		end
		page:Refresh()
	end
	amount:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		local kind = pending and pending.id == chosenItem and pending.kind or mode.value or "market"
		pending = nil
		setPrice(kind, self:GetText())
	end)
	local function setMany(text)
		local e, list = chosenEntry()
		if e and not list.profile then
			local n = tonumber(string.match(text or "", "%d+") or "")
			e.upTo = n and n > 0 and math.min(n, 1000000) or nil
			stamp(list)
		end
		page:Refresh()
	end
	many:SetScript("OnEnterPressed", function(self)
		self:ClearFocus()
		setMany(self:GetText())
	end)

	-- Adds an item to the chosen list (one of the player's own).
	local function add(id)
		local list = own()
		if not id then
			return
		end
		if not list then
			page.note:SetText("This list follows the craft queue or the profile; choose one of yours to add to.")
			return
		end
		for _, e in ipairs(list.entries) do
			if e.itemId == id then
				chosenItem = id
				page:Refresh()
				return
			end
		end
		list.entries[#list.entries + 1] = { itemId = id }
		stamp(list)
		chosenItem = id
		page.note:SetText("Added " .. itemNameOf(id) .. ": set the most you pay below.")
		page:Refresh()
	end
	page.addItem = add
	local function dropped()
		local kind, id = GetCursorInfo()
		if kind == "item" and id then
			ClearCursor()
			add(id)
		end
	end
	slot:SetScript("OnReceiveDrag", dropped)
	slot:SetScript("OnClick", dropped)

	function page:Refresh()
		-- The auction panel's Buy tab shows the same lists: it follows at once.
		if refresh then
			refresh()
		end
		local _, list, shown = lists()
		local rows = {}
		for i, l in ipairs(shown) do
			rows[i] = { index = i, name = l.name, n = #l.entries, generated = l.profile }
		end
		listTable:SetRows(rows, true)
		local mine = own()
		name:SetText(mine and mine.name or "")
		name:SetShown(mine ~= nil)
		delete:SetShown(mine ~= nil)
		exportButton:SetShown(mine ~= nil)
		title:SetText(list.name)
		crafting:SetShown(list.queue == true)
		queueWindow:SetShown(list.queue == true)
		slot:SetShown(mine ~= nil)
		slotLine:SetText(mine and "Drop an item here, or shift-click one anywhere, to add it."
			or list.queue and "Its items are what the queued crafts still need; set what you pay for each."
			or "This list follows the sale profile; change it there.")
		slotLine:ClearAllPoints()
		if mine then
			slotLine:SetPoint("LEFT", slot, "RIGHT", 10, 0)
		else
			slotLine:SetPoint("TOPLEFT", X, -32)
		end
		slotLine:SetPoint("RIGHT", page, "RIGHT")
		local entries = {}
		for i, e in ipairs(list.entries) do
			local quality = ns.price.itemInfo(e.itemId)
			entries[i] = { itemId = e.itemId, name = itemNameOf(e.itemId), quality = quality or 1,
				price = e.maxUnit and money(e.maxUnit) or e.pct and (e.pct .. "% of market") or e.lowest and ("lowest, ask over " .. e.lowest .. "%") or "under market",
				many = e.upTo and tostring(e.upTo) or "any" }
		end
		items:SetRows(entries, true)
		local e = chosenEntry()
		edit:SetShown(e ~= nil)
		if e then
			local editable = not list.profile or list.queue
			editName:SetText(itemNameOf(e.itemId))
			local kind = pending and pending.id == e.itemId and pending.kind or e.maxUnit and "fixed" or e.pct and "pct" or e.lowest and "lowest" or "market"
			mode:Set(kind)
			amount:SetShown(kind ~= "market")
			amount:SetText(e.maxUnit and (string.gsub(string.format("%.2f", e.maxUnit / 10000), "%.?0+$", "")) or (e.pct or e.lowest) and tostring(e.pct or e.lowest) or "")
			amount.hint:SetText(kind == "fixed" and "gold" or "%")
			many:SetText(e.upTo and tostring(e.upTo) or "")
			-- The craft queue's numbers come from the queue.
			many:SetShown(not list.profile)
			manyLabel:SetShown(not list.profile)
			removeItem:SetShown(not list.profile)
			mode:SetAlpha(editable and 1 or 0.5)
			mode:EnableMouse(editable)
		end
	end
	-- For the smoke test: its controls.
	page.controls = { new = newList, delete = delete, name = name, import = importButton, export = exportButton, field = field,
		remove = removeItem, setPrice = function(kind, text) setPrice(kind, text) end, setMany = setMany, rename = renameTo }
	ns.listsPage = page
end
ns.buildShoppingLists = buildLists

-- Bank (owner, 2026-10-24 and 25): what the bank and mailbox hold that the auction house pays for, most
-- worth first. A click chooses one and shows its listings in Blizzard's window, as on Sell; Take all, or
-- Take… an amount, marks it, and the next time the bank opens it moves to the bags (Inventory.lua).
local bankChosen -- the item chosen on the Bank tab
local function buildBank(page)
	local function wanted()
		return ns.fetchList and ns.fetchList() or {}
	end
	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3 },
		{ key = "count", title = "Held", width = 50, align = "RIGHT" },
		{ key = "place", title = "In", width = 40 },
		{ key = "worth", title = "Worth", width = 84, align = "RIGHT", text = function(r) return money(r.worth) end, sort = function(r) return r.worth end },
		{ key = "take", title = "Take", width = 44, align = "RIGHT", text = function(r) return r.take == true and "all" or r.take and tostring(r.take) or "" end,
			color = function() return Theme.color.accent end },
	}, {
		pageSize = 9,
		rowHeight = 24,
		empty = "Nothing in your bank or mail the auction house pays for.",
		itemId = function(r) return r.id end,
		isSelected = function(r) return bankChosen and r.id == bankChosen.id end,
		onRowClick = function(r)
			bankChosen = r
			searchEntry({ itemId = r.id }, true)
			page:Refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT")
	tbl:SetPoint("RIGHT", page, "RIGHT")
	page.table = tbl
	-- The chosen item and what to take of it.
	local detail = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	detail:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	detail:SetPoint("RIGHT", page, "RIGHT")
	detail:SetHeight(84)
	local name = UI.Text(detail, "", { size = "sm", medium = true })
	name:SetPoint("TOPLEFT", 12, -10)
	name:SetPoint("RIGHT", detail, "RIGHT", -12, 0)
	local line = UI.Text(detail, "", { size = "xs", tone = "faint" })
	line:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -4)
	local function mark(n)
		if bankChosen and bankChosen.place == "bank" then
			wanted()[bankChosen.id] = n
			page:Refresh()
		end
	end
	local all = UI.Button(detail, "Take all", function()
		mark(true)
	end, { width = 90, height = 26 })
	all:SetPoint("BOTTOMLEFT", 12, 10)
	-- Take…: a small window over the panel asks how many.
	local ask = UI.Panel(page, { color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	ask:SetSize(280, 96)
	ask:SetPoint("CENTER", detail, "CENTER")
	ask:SetFrameLevel(detail:GetFrameLevel() + 10)
	ask:EnableMouse(true)
	ask:Hide()
	local askText = UI.Text(ask, "", { size = "sm", wrap = true })
	askText:SetPoint("TOPLEFT", 12, -12)
	askText:SetPoint("RIGHT", ask, "RIGHT", -12, 0)
	local amount = UI.SearchBox(ask, "how many", nil)
	amount:SetPoint("BOTTOMLEFT", 12, 12)
	amount:SetWidth(90)
	local function takeAmount(text)
		local n = tonumber(string.match(text or "", "%d+") or "")
		amount:ClearFocus()
		ask:Hide()
		if n and n > 0 and bankChosen then
			mark(n >= bankChosen.count and true or n)
		end
	end
	local function takeTyped()
		takeAmount(amount:GetText())
	end
	amount:SetScript("OnEnterPressed", takeTyped)
	amount:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
		ask:Hide()
	end)
	local okay = UI.Button(ask, "Take", takeTyped, { kind = "primary", width = 70, height = 26 })
	okay:SetPoint("LEFT", amount, "RIGHT", 8, 0)
	local cancel = UI.Button(ask, "Cancel", function()
		amount:ClearFocus()
		ask:Hide()
	end, { width = 70, height = 26 })
	cancel:SetPoint("LEFT", okay, "RIGHT", 6, 0)
	local some = UI.Button(detail, "Take…", function()
		if bankChosen and bankChosen.place == "bank" then
			askText:SetText(string.format("Take how many %s? %d in the bank.", bankChosen.name, bankChosen.count))
			amount:SetText("")
			ask:Show()
			amount:SetFocus()
		end
	end, { width = 80, height = 26 })
	some:SetPoint("LEFT", all, "RIGHT", 6, 0)
	local none = UI.Button(detail, "Don't take", function()
		mark(nil)
	end, { width = 100, height = 26 })
	none:SetPoint("LEFT", some, "RIGHT", 6, 0)
	local sum = UI.Text(page, "", { size = "xs", tone = "muted" })
	sum:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -8)
	sum:SetPoint("RIGHT", page, "RIGHT")
	page.take = { all = all, some = some, none = none, typed = function(n) takeAmount(tostring(n)) end, open = function() some:Click() end }
	function page:Refresh()
		local me = ns.me()
		local e = me and ns.Views.elsewhere(me, ns.Encode.parseItems, function(id)
			return (ns.Prices.value(id))
		end, function(id)
			local _, _, _, _, n = ns.price.itemInfo(id)
			return n or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
		end) or { items = {} }
		local want, rows, n = wanted(), {}, 0
		for i, it in ipairs(e.items) do
			local take = it.place == "bank" and want[it.id] or nil
			rows[i] = { id = it.id, name = it.name, count = it.count, place = it.place, worth = it.worth, take = take }
			if take then
				n = n + 1
			end
			if bankChosen and bankChosen.id == it.id and bankChosen.place == it.place then
				bankChosen = rows[i]
			end
		end
		page.rows = rows
		tbl:SetRows(rows, true)
		local c = bankChosen
		name:SetText(c and c.name or Theme.escape(Theme.color.textFaint) .. "Choose an item.|r")
		line:SetText(c and (c.place == "mail" and string.format("%d in your mail: the mail helper takes it.", c.count)
			or string.format("%d in the bank · %s%s", c.count, money(c.worth), c.take == true and " · taking all" or c.take and (" · taking " .. c.take) or "")) or "")
		local can = c and c.place == "bank"
		for _, b in ipairs({ all, some, none }) do
			if can then
				b:Enable()
				b:SetAlpha(1)
			else
				b:Disable()
				b:SetAlpha(0.5)
			end
		end
		sum:SetText(n > 0 and string.format("%d chosen: they move into your bags the next time you open your bank.", n) or "Choose items to take from the bank: they move into your bags the next time you open it.")
	end
end

-- Space posts only while the Post tab shows: an override binding on a named button, set and cleared as
-- the tab and the panel change (never in combat, when bindings cannot change). Elsewhere it jumps.
local function bindSpace(p)
	if (InCombatLockdown and InCombatLockdown()) or not SetOverrideBindingClick then
		return
	end
	local want = p:IsShown() and p.tab == "post"
	if want and not p.spaceBound then
		SetOverrideBindingClick(p, true, "SPACE", "GoldForeverPostKey")
	elseif not want and p.spaceBound then
		ClearOverrideBindings(p)
	end
	p.spaceBound = want
end

local function build()
	if ns.applyLook then
		ns.applyLook()
	end
	local old = panel
	-- One panel per look and accent, reused when the look comes back (frames are never freed).
	if panels[Theme.key] then
		if old and old ~= panels[Theme.key] then
			old:Hide()
		end
		panel, built = panels[Theme.key], Theme.key
		return
	end
	local p = UI.Panel(UIParent, { window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	p:SetWidth(W)
	p:SetFrameStrata("HIGH")
	p:Hide()
	if old then
		old:Hide()
	end
	local mark = UI.Icon(p, "coins", 18, "accent")
	mark:SetPoint("TOPLEFT", 16, -16)
	local title = UI.Text(p, Theme.skin.titleCaps and "GOLD FOREVER" or "Gold Forever", { size = "lg", medium = true })
	title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
	-- What the bank and mailbox hold that the auction house pays for: fetch it first. A hover lists it.
	local away = CreateFrame("Button", nil, p)
	away:SetPoint("TOPRIGHT", -16, -16)
	away:SetSize(220, 18)
	away.text = UI.Text(away, "", { size = "xs", tone = "muted", align = "RIGHT" })
	away.text:SetAllPoints()
	-- Short (manual test run 001: the list of 52 was big and hard to read): what it is, and the click.
	away:SetScript("OnEnter", function(self)
		local e = self.list
		if not e or e.count == 0 then
			return
		end
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine(string.format("%d items in your bank and mail sell for %s.", e.count, money(e.total)), 1, 1, 1, true)
		GameTooltip:AddLine("Click to choose what to take from the bank.", 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	away:SetScript("OnClick", function()
		if panel and panel.select then
			panel.select("bank")
		end
	end)
	away:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	p.away = away
	local pages = {}
	-- Named as Blizzard's tabs are (manual test run 001); the keys stay as the save knows them.
	local tabs = UI.TabBar(p, { { key = "scan", label = "Scan" }, { key = "shop", label = "Buy" }, { key = "post", label = "Sell" }, { key = "cancel", label = "Auctions" }, { key = "bank", label = "Bank" } }, function(key)
		p.select(key)
	end, { variant = "underline" })
	-- A tab chosen here moves Blizzard's window to its own (fromBlizzard: it came from there).
	function p.select(key, fromBlizzard)
		p.ensure(key)
		tabs:Select(key)
		for k, f in pairs(pages) do
			f:SetShown(k == key)
		end
		p.tab = key
		bindSpace(p)
		local b = not fromBlizzard and AuctionHouseFrame and AuctionHouseFrame[BLIZZARD_TAB[key] or ""]
		if b and b.Click and b:IsShown() and tabForMode(blizzardMode()) ~= key then
			following = true
			ns.safely("auction tab", b.Click, b)
			following = false
		end
		refresh()
	end
	tabs:SetPoint("TOPLEFT", 16, -42)
	tabs:SetPoint("TOPRIGHT", -16, -42)
	for _, key in ipairs({ "scan", "post", "shop", "cancel", "bank" }) do
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -16)
		f:SetPoint("BOTTOMRIGHT", -20, 16)
		f:Hide()
		pages[key] = f
	end
	-- Each tab is drawn the first time it is chosen: opening the auction house draws Scan only.
	local builders = { scan = buildScan, post = buildPost, shop = buildShop, cancel = buildCancel, bank = buildBank }
	function p.ensure(key)
		local f = pages[key]
		if f and not f.built then
			f.built = true
			builders[key](f)
			-- Its widgets placed for certain: the panel anchored anew a frame later (see show).
			C_Timer.After(0, function()
				if ns.auctionAnchor then
					ns.auctionAnchor()
				end
			end)
		end
	end
	p.ensure("scan")
	p.scan, p.post, p.shop, p.cancel, p.bank, p.tabs, p.pages = pages.scan, pages.post, pages.shop, pages.cancel, pages.bank, tabs, pages
	p:SetScript("OnShow", bindSpace)
	p:SetScript("OnHide", bindSpace)
	panel = p
	built = Theme.key
	panels[built] = p
	tabs:Select("scan")
	pages.scan:Show()
	p.tab = "scan"
end

-- The title row's bank-and-mail line, worked out again only when the bank, the mail or the prices change.
local awayStamp = {}
local function drawAway()
	local me, away = ns.me(), panel and panel.away
	if not me or not away then
		return
	end
	local file = GoldForever_Prices
	local bankT, mailT = me.bank and me.bank.t, me.mail and me.mail.t
	local fileAt = type(file) == "table" and file.at or nil
	if away.list and awayStamp.bank == bankT and awayStamp.mail == mailT and awayStamp.scan == ns.scanVersion and awayStamp.file == fileAt then
		return
	end
	awayStamp.bank, awayStamp.mail, awayStamp.scan, awayStamp.file = bankT, mailT, ns.scanVersion, fileAt
	away.list = ns.Views.elsewhere(me, ns.Encode.parseItems, function(id)
		return (ns.Prices.value(id))
	end, function(id)
		local _, _, _, _, name = ns.price.itemInfo(id)
		return name or (C_Item.GetItemNameByID and C_Item.GetItemNameByID(id)) or ("item " .. id)
	end)
	local e = away.list
	away.text:SetText(e.count > 0 and string.format("Bank & mail: %d %s · %s", e.count, e.count == 1 and "item" or "items", money(e.total)) or "")
end

refresh = function()
	if not panel or not panel:IsShown() then
		return
	end
	ns.safely("auction panel away", drawAway)
	if built ~= Theme.key then
		local tab = panel.tab
		panel:Hide()
		build()
		panel.ensure(tab)
		panel.tabs:Select(tab)
		for k, f in pairs(panel.pages) do
			f:SetShown(k == tab)
		end
		panel.tab = tab
		show(true)
		return
	end
	if panel.tab == "scan" then
		panel.scan:Refresh()
	elseif panel.tab == "post" then
		local s = settings()
		for _, r in ipairs(rows) do
			price(r, s)
		end
		if chosen then
			for _, r in ipairs(rows) do
				if r.key == chosen.key then
					chosen = r
				end
			end
		end
		panel.post.table:SetRows(rows)
		panel.post:Refresh()
	elseif panel.tab == "shop" then
		panel.shop:Refresh()
	elseif panel.tab == "cancel" then
		panel.cancel:Refresh()
	elseif panel.tab == "bank" then
		panel.bank:Refresh()
	end
end

local function reread()
	rows = sellable()
	local still
	for _, r in ipairs(rows) do
		if chosen and r.key == chosen.key then
			still = r
		end
	end
	chosen = still or rows[1]
	refresh()
end

local ticker
local hooked = false
-- Beside the auction house, its height.
local function anchor()
	if panel and AuctionHouseFrame then
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
		panel:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 6, 0)
	end
end
-- A frame after opening, or after a tab is first drawn: anchored anew, then hidden and shown, which is
-- what closing and opening the auction house did that put every widget and text in place (manual test
-- run 001, /gf uidebug: a button's own text at nil,nil, unseen, on the first opening).
local function settle()
	anchor()
	if panel and panel:IsShown() then
		panel:Hide()
		panel:Show()
	end
end
ns.auctionAnchor = settle
-- `redrawn`: the same visit in a new look, on the tab it had; else a new visit, on Blizzard's tab.
show = function(redrawn)
	if not AuctionHouseFrame then
		return
	end
	if not panel then
		build()
	end
	-- Blizzard's tab chosen there switches the panel to its own.
	if not hooked and AuctionHouseFrame.SetDisplayMode and hooksecurefunc then
		hooked = true
		hooksecurefunc(AuctionHouseFrame, "SetDisplayMode", function(_, mode)
			local key = not following and tabForMode(mode)
			if key and panel and panel:IsShown() and panel.tab ~= key then
				ns.safely("auction tab", panel.select, key, true)
			end
		end)
	end
	anchor()
	panel:Show()
	-- Again a frame later: built in the frame the auction house opens, some of its widgets were never
	-- placed (manual test run 001, /gf uidebug: Sell's Rule ›, quantity and Post with no rect, Remove's
	-- text unseen) until the panel was anchored anew, as closing and opening did.
	C_Timer.After(0, settle)
	-- A new visit opens on Scan while a full scan may start, to prod the player into one (owner's answer,
	-- 2026-10-24); else on Blizzard's tab.
	if redrawn ~= true then
		local st = ns.scanState and ns.scanState()
		local key = st and st.wait == 0 and st.phase == "idle" and "scan" or tabForMode(blizzardMode())
		if key and key ~= panel.tab then
			panel.select(key, true)
		end
	end
	reread()
	if chosen then
		search(chosen)
	end
	-- The scan's progress and cooldown, once a second while the panel shows.
	if not ticker then
		ticker = C_Timer.NewTicker(1, function()
			if panel and panel:IsShown() and panel.tab == "scan" then
				ns.safely("auction panel", refresh)
			end
		end)
	end
end

-- A buy or cancel the auction house refused (gone, not enough money): Blizzard says why on screen;
-- the panel takes the next press. Other game errors (mana, cooldowns) are not the action's answer and
-- leave the wait to its timeout.
ns.on("AUCTION_HOUSE_SHOW_ERROR", "auction panel", function()
	local kind = waits.shop and "shop" or waits.cancel and "cancel" or waits.post and "post"
	if kind and panel then
		local note = panel[kind].note
		waits[kind], purchase = nil, nil
		if kind == "shop" then
			buying = nil
		end
		if note then
			note:SetText(Theme.escape(Theme.color.danger) .. "The auction house refused it.|r")
		end
		if ns.auctionRefresh then
			ns.auctionRefresh()
		end
	end
end)

local function hide()
	if panel then
		panel:Hide()
	end
	if ticker and ticker.Cancel then
		ticker:Cancel()
	end
	ticker = nil
	-- Nothing in flight outlives the auction house: a warned post, a quoted or sent purchase, a check.
	live, waits, armed, confirm, purchase, checking = {}, {}, nil, nil, nil, nil
	buying, overArmed = nil, nil
end

-- A panel hidden in combat could not clear its binding then: set it right when the fight ends.
ns.on("PLAYER_REGEN_ENABLED", "auction panel", function()
	if panel then
		bindSpace(panel)
	end
end)

-- The named button the Space binding clicks (SetOverrideBindingClick takes a global name): a key press
-- is a hardware event, as a click is.
local key = CreateFrame("Button", "GoldForeverPostKey", UIParent)
key:Hide()
key:SetScript("OnClick", function()
	if panel and panel:IsShown() and panel.tab == "post" then
		ns.safely("auction post", post)
		refresh()
	end
end)

ns.on("AUCTION_HOUSE_SHOW", "auction panel", function()
	-- Ask the client whether its auction house takes copper (Forever's source leaves it to the client).
	Post.copper = C_AuctionHouse and C_AuctionHouse.SupportsCopperValues and C_AuctionHouse.SupportsCopperValues() or false
	if settings().hidden then
		return
	end
	show()
end)
ns.on("AUCTION_HOUSE_CLOSED", "auction panel", hide)
ns.onLook("auction panel", function()
	if refresh then
		refresh() -- a panel that shows is drawn again in the look now set
	end
end)
ns.on("BAG_UPDATE_DELAYED", "auction panel", function()
	if panel and panel:IsShown() then
		reread()
	end
end)

-- Alt-click on a bag item while the panel shows chooses it in Post (owner's answer, 2026-10-24): the
-- game's own modified-click handler is hooked (HandleModifiedItemClick, after it ran; nothing replaced),
-- and the item found by its bag slot, or by its link where the client passes none.
local function bagSlot(loc)
	if type(loc) ~= "table" then
		return nil
	end
	if loc.GetBagAndSlot then
		return loc:GetBagAndSlot()
	end
	return loc.bag, loc.slot
end

local function chooseFromBag(link, loc, itemID)
	if not panel or not panel:IsShown() then
		return
	end
	reread()
	local bag, slot = bagSlot(loc)
	local key = link and ns.Encode.itemKey(link)
	local id = itemID or (link and ns.Encode.itemId(key))
	local found
	for _, r in ipairs(rows) do
		for _, l in ipairs(r.locations) do
			local b, sl = bagSlot(l)
			if bag and b == bag and sl == slot then
				found = r
			end
		end
		if not found and not bag and (r.key == key or ((r.commodity or itemID) and r.id == id)) then
			found = r
		end
	end
	if not found then
		return
	end
	panel.select("post", true)
	chosen, armed, confirm = found, nil, nil
	search(found, true)
	refresh()
end

-- Shift-click on any item while Shopping lists shows adds it to the chosen list.
local function addToList(link)
	local id = type(link) == "string" and tonumber(string.match(link, "item:(%d+)"))
	if id and ns.listsPage and ns.listsPage:IsVisible() then
		ns.safely("lists add", ns.listsPage.addItem, id)
	end
end
if hooksecurefunc and HandleModifiedItemClick then
	hooksecurefunc("HandleModifiedItemClick", function(link, loc)
		if IsAltKeyDown and IsAltKeyDown() then
			ns.safely("auction alt-click", chooseFromBag, link, loc)
		elseif IsShiftKeyDown and IsShiftKeyDown() then
			addToList(link)
		end
	end)
end
-- The auction house's own item buttons and chat links send a shift-click's link straight to the chat
-- link function, not through HandleModifiedItemClick (manual test run 001: shift-click in the auction
-- house added nothing): hooked too. An item added twice is only chosen again.
if hooksecurefunc and ChatFrameUtil and ChatFrameUtil.InsertLink then
	hooksecurefunc(ChatFrameUtil, "InsertLink", addToList)
elseif hooksecurefunc and ChatEdit_InsertLink then
	hooksecurefunc("ChatEdit_InsertLink", addToList)
end
ns.AuctionPanelAltClick = chooseFromBag
-- From the hub's Inventory: an item chosen in Post while the auction house is open.
function ns.auctionChoose(itemID)
	ns.safely("auction choose", chooseFromBag, nil, nil, itemID)
end

-- While the panel shows, a bag item's tooltip says what Post would ask for it (owner's answer,
-- 2026-10-24): the same price and reason as the Post tab, rule, override or profile.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function postTooltip(tooltip, data)
		if tooltip ~= GameTooltip or not data or not data.id or not panel or not panel:IsShown() then
			return
		end
		for _, r in ipairs(rows) do
			if r.id == data.id then
				-- As the Sell tab last priced it; priced here only if it never was.
				if not r.priced then
					price(r)
				end
				local sug = r.suggestion
				if sug and sug.unit then
					tooltip:AddLine(string.format("%sPost at %s · %s", ns.tipPrefix(tooltip), money(sug.unit), sug.label or Post.REASONS[sug.reason] or ""), 1, 1, 1)
				elseif sug then
					tooltip:AddLine(ns.tipPrefix(tooltip) .. (sug.label or Post.REASONS[sug.reason] or "Hold"), 0.6, 0.6, 0.6)
				end
				return
			end
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("auction tooltip", postTooltip, tooltip, data)
	end)
end

-- "/gf uidebug": what the client says of the widgets seen without their text (manual test run 001: Buy's
-- Remove, Sell's Rule › and quantity box, now and then right after opening), and every shown frame that
-- overlaps one and is drawn over it, in a box to copy.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function num(x)
	return type(x) == "number" and string.format("%.1f", x) or tostring(x)
end
local function call(obj, method)
	return obj and obj[method] and num(obj[method](obj)) or "-"
end
local function frameName(f)
	return (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or tostring(f)
end
-- Whether `a` is `b` or inside it.
local function within(a, b)
	while a do
		if a == b then
			return true
		end
		a = a.GetParent and a:GetParent()
	end
	return false
end
local function covering(w, out)
	if not (EnumerateFrames and w.GetRect) then
		return
	end
	local l, b, wd, ht = w:GetRect()
	if not l then
		out[#out + 1] = "    (no rect)"
		return
	end
	local strata, level = STRATA[w:GetFrameStrata()] or 0, w:GetFrameLevel() or 0
	local found, f = 0, EnumerateFrames()
	-- One frame looked at; a forbidden one (the client's own, closed to addons) errors and is skipped.
	local function look(f)
		if f == w or not f:IsVisible() or within(w, f) or within(f, w) then
			return
		end
		local fl, fb, fw, fh = f:GetRect()
		if fl and fl < l + wd and fl + fw > l and fb < b + ht and fb + fh > b then
			local fs, flv = STRATA[f:GetFrameStrata()] or 0, f:GetFrameLevel() or 0
			if fs > strata or (fs == strata and flv >= level) then
				found = found + 1
				out[#out + 1] = string.format("    over it: %s %s/%d at %.0f,%.0f %.0fx%.0f alpha %.2f", frameName(f), f:GetFrameStrata(), flv, fl, fb, fw, fh, f:GetEffectiveAlpha() or -1)
			end
		end
	end
	while f and found < 15 do
		pcall(look, f)
		f = EnumerateFrames(f)
	end
	if found == 0 then
		out[#out + 1] = "    nothing shown over it"
	end
end
local function describe(label, w, out)
	if not w then
		out[#out + 1] = "  " .. label .. ": not made"
		return
	end
	local fs = w.label or (w.GetFontString and w:GetFontString())
	local font, size
	if fs and fs.GetFont then
		font, size = fs:GetFont()
	elseif w.GetFont then
		font, size = w:GetFont()
	end
	out[#out + 1] = "  " .. label .. ": shown " .. call(w, "IsShown") .. " visible " .. call(w, "IsVisible") .. " alpha " .. call(w, "GetAlpha")
		.. "/" .. call(w, "GetEffectiveAlpha") .. " size " .. call(w, "GetWidth") .. "x" .. call(w, "GetHeight") .. " at " .. call(w, "GetLeft") .. "," .. call(w, "GetBottom")
		.. " strata " .. call(w, "GetFrameStrata") .. " level " .. call(w, "GetFrameLevel")
		.. " text [" .. call(w, "GetText") .. "] fs [" .. call(fs, "GetText") .. "] fs shown " .. call(fs, "IsShown") .. " fs alpha " .. call(fs, "GetAlpha")
		.. " fs width " .. call(fs, "GetStringWidth") .. " fs at " .. call(fs, "GetLeft") .. "," .. call(fs, "GetBottom")
		.. " font " .. tostring(font) .. " " .. num(size)
	covering(w, out)
end
ns.commands.uidebug = function()
	local out, n = {}, 0
	out[#out + 1] = string.format("Gold Forever %s, %s, interface %s", tostring(ns.db() and ns.db().addon), date and date("%Y-%m-%d %H:%M:%S") or "", tostring(select(4, GetBuildInfo())))
	for key, p in pairs(panels) do
		n = n + 1
		out[#out + 1] = string.format("panel %s: shown %s, tab %s, the one in use %s, strata %s level %s", key, tostring(p:IsShown()), tostring(p.tab), tostring(p == panel), tostring(p:GetFrameStrata()), tostring(p:GetFrameLevel()))
	end
	out[#out + 1] = string.format("  %d panels; Theme.key %s; built %s", n, tostring(Theme.key), tostring(built))
	if panel then
		describe("Buy Edit lists", panel.shop and panel.shop.editLists, out)
		describe("Sell Rule", panel.post and panel.post.ruleButton, out)
		describe("Sell quantity box", panel.post and panel.post.quantity and panel.post.quantity.readout, out)
		describe("Sell Post button", panel.post and panel.post.button, out)
	end
	local text = table.concat(out, "\n")
	if ns.showCopy then
		ns.showCopy("Gold Forever: widget report", text)
	else
		print(text)
	end
end

-- "/gf ah" shows or hides the panel at the auction house, and remembers.
ns.commands.ah = function()
	local s = settings()
	if panel and panel:IsShown() then
		s.hidden = true
		hide()
		ns.say("the auction panel no longer opens at the auction house; /gf ah there brings it back.")
	else
		s.hidden = false
		-- Shown only at the auction house: away from it, it opens there next time.
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			show()
		else
			ns.say("the auction panel opens at the auction house again.")
		end
	end
end

-- For the smoke test: pick a tab, post the chosen row, and read the rows.
ns.AuctionPanel = {
	panel = function()
		return panel
	end,
	tab = function(key)
		if panel then
			panel.select(key)
		end
	end,
	bound = function()
		return panel and panel.spaceBound
	end,
	post = function()
		if panel then
			post()
		end
	end,
	state = function()
		return rows, chosen, busy()
	end,
	duration = function(v)
		if panel and panel.post.duration then
			settings().durations[chosen.key] = v
		end
	end,
	quantity = function(v)
		settings().quantities[chosen.key] = v
	end,
	shopChoose = function(e)
		shopChosen, purchase = e, nil
		searchEntry(e, true)
		refresh()
	end,
	shopBuy = function()
		buyNext()
	end,
	shopNote = function()
		return panel and panel.shop.note.text
	end,
	cancelCheck = function()
		startCheck()
	end,
	cancelNext = function()
		cancelNext()
	end,
	owned = function()
		return owned, checking
	end,
	importProfile = function(text)
		ns.openPage("rules")
		ns.rulesPage.importProfile(text)
	end,
	ruleScope = function(value)
		ns.openPage("rules")
		ns.rulesPage.chooseScope(value)
	end,
	ruleSet = function(field, value)
		ns.rulesPage.setField(field, value)
	end,
	suggestion = function()
		return chosen and chosen.suggestion
	end,
}

-- Lists and profiles the companion carries from the site (Data.lua's `shared`), merged in at login:
-- by id, the newer edit wins and the other is dropped (Shopping.merge; no copies since 2026-10-24). A file
-- already merged is not merged again.
-- A copy the site kept: marked so by the server, or named so by an earlier merge. In the save, only a list
-- or profile with no id is taken for one by its name: one the player made (stamped with an id) keeps any
-- name. What the site sends is judged by its name too (left out, never deleted).
local function copyMark(x, name)
	if type(x.copyOf) == "string" then
		return x.copyOf
	end
	return not x.id and type(name) == "string" and string.find(name, " %(older copy%)$") and "named" or nil
end

local function mergeShared()
	local shared = type(GoldForever_Prices) == "table" and type(GoldForever_Prices.shared) == "table" and GoldForever_Prices.shared or nil
	local s = settings()
	-- The list and profile in use are kept by index: found again once the drop and the merge are done.
	local before = #(s.lists or {})
	local listWas = s.list and (s.lists or {})[s.list]
	local generated = s.list and s.list > before and s.list - before or nil
	local profileWas = s.profile and (s.profiles or {})[s.profile]
	local function restore()
		if profileWas then
			s.profile = ns.Shopping.refind(s.profiles, profileWas)
		end
		if listWas then
			s.list = ns.Shopping.refind(s.lists, listWas) or 1
		elseif generated then
			s.list = #(s.lists or {}) + generated
		end
	end
	-- The "(older copy)" lists and profiles earlier merges kept (owner, 2026-10-24: they piled up),
	-- marked or only named so.
	for _, items in ipairs({ s.lists or {}, s.profiles or {} }) do
		for _, x in ipairs(items) do
			x.copyOf = x.copyOf or copyMark({ id = x.id }, x.name)
		end
	end
	local n = ns.Shopping.dropCopies(s.lists or {}) + ns.Shopping.dropCopies(s.profiles or {})
	if n > 0 then
		ns.say(string.format("removed %d \"older copy\" %s the site sync had made.", n, n == 1 and "list" or "lists"))
	end
	if not shared or shared.at == s.sharedAt then
		restore()
		return
	end
	local lists, profiles = {}, {}
	for _, x in ipairs(type(shared.lists) == "table" and shared.lists or {}) do
		local got = type(x) == "table" and type(x.string) == "string" and ns.Shopping.decode(x.string)
		if got and got[1] and type(x.id) == "string" then
			got[1].id, got[1].edited = x.id, tonumber(x.edited) or 0
			got[1].copyOf = copyMark({ copyOf = x.copyOf }, got[1].name)
			lists[#lists + 1] = got[1]
		end
	end
	for _, x in ipairs(type(shared.profiles) == "table" and shared.profiles or {}) do
		local p = type(x) == "table" and type(x.string) == "string" and ns.SalePlan.decode(x.string)
		if p and type(x.id) == "string" then
			p.id, p.edited = x.id, tonumber(x.edited) or 0
			p.copyOf = copyMark({ copyOf = x.copyOf }, p.name)
			profiles[#profiles + 1] = p
		end
	end
	local a, b
	s.removedShared = s.removedShared or {}
	s.lists, a = ns.Shopping.merge(s.lists or {}, lists, s.removedShared)
	s.profiles, b = ns.Shopping.merge(s.profiles or {}, profiles, s.removedShared)
	s.sharedAt = shared.at
	restore()
	if a + b > 0 then
		ns.say(string.format("lists and profiles from the site: %d %s.", a + b, a + b == 1 and "change" or "changes"))
	end
end
ns.on("PLAYER_LOGIN", "shared lists", function()
	mergeShared()
end)
ns.mergeShared = mergeShared
