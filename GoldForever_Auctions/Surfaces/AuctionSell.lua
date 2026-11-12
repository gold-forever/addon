-- Gold Forever: the auction panel's Sell tab: the bag items the auction house takes, each priced by the
-- rule (Post.lua) or the sale plan against the cheapest listing by someone else, with the reason. A row
-- posts only from a live search of it (made when it is chosen); the last scan prices the list until then
-- (gf#368). One click, or Space while the panel shows, posts the chosen row and moves on. Posting is a hardware event (the click or the key); the result is
-- confirmed by its event before the next press is taken. Own auctions are left out of "cheapest", so the
-- player never undercuts themself.

local _, ns = ...
local L = ns.L
local Theme, UI, Post = ns.Theme, ns.UI, ns.Post
local ah = ns.ah
local Blizzard, Books = ns.AuctionBlizzard, ns.AuctionBooks
local settings, activeProfile = ns.auctionSettings, ns.activeProfile
local heldHere = ns.Holdings.heldHere
local bookKey, search, LISTED = Books.bookKey, Books.search, Books.LISTED
local await, busy, money = ah.await, ah.busy, ns.Money.auction
local Wide = ns.AuctionSellWide

local DURATIONS = { { value = 1, label = L["12 hours"] }, { value = 2, label = L["24 hours"] }, { value = 3, label = L["48 hours"] } }

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
						r = { key = key, id = info.itemID, link = info.hyperlink, name = name or C_Item.GetItemNameByID(info.itemID) or string.format(L["item %d"], info.itemID),
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

-- A sale plan's step as the Post tab's suggestion: posts in whole silver; "ask" posts the plan's price
-- after a second press; hold and skip post nothing.
local PLAN_REASONS = {
	undercut = L["Undercut (plan)"], fixed = L["Fixed price (plan)"], percentile = L["Percentile (plan)"], ["no-competition"] = L["No one else (plan)"],
	["market-moved"] = L["The market moved (plan)"], ["under-floor"] = L["Hold: under the plan's floor"], keeping = L["Keeping"], ["no-price"] = L["No price yet"],
	maximum = L["At the maximum (plan)"], ["under-vendor"] = L["Held: under the vendor price"],
}

-- Gear listed by the account's other characters counts as own too (gf#375): an item book's levels
-- marked again from its search's `owners`, and its cheapest other listing found again. A commodity's
-- book as it is: its results name no owners. Each book is read once (`marked`, by book).
local marked = setmetatable({}, { __mode = "k" })

local function ownersOf(itemKey)
	local owners = {}
	if not (C_AuctionHouse.GetNumItemSearchResults and C_AuctionHouse.GetItemSearchResultInfo) then
		return owners
	end
	for i = 1, math.min(C_AuctionHouse.GetNumItemSearchResults(itemKey) or 0, Books.LEVELS) do
		local res = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if res and res.auctionID and res.owners then
			owners[res.auctionID] = res.owners
		end
	end
	return owners
end

local function sellBook(itemID, commodity, itemKey)
	local book = (commodity or itemKey) and ah.live[bookKey(itemID, commodity, itemKey and itemKey.itemLevel)]
	if commodity or not (book and book.levels) then
		return book
	end
	if not marked[book] then
		local levels, alts = Post.withAlts(book.levels, ownersOf(itemKey), Post.accountNames())
		marked[book] = levels == book.levels and book
			or { cheapest = Books.honest(levels, itemID), levels = levels, alts = alts, commodity = false, at = book.at }
	end
	return marked[book]
end

-- limits: Post.limits for the item, or nil without a market value.
local function planned(r, rule, market, limits)
	-- Gear's book is known once the row was searched, at its own item level.
	local book = sellBook(r.id, r.commodity, r.itemKey)
	local step = ns.SalePlan.sell(rule, heldHere(r.id, r.count), book and book.levels or {}, market, nil, Post.silver,
		limits and { vendor = limits.vendor, maximum = limits.maximum })
	local unit = step.unitPrice or (step.choices and step.choices.plan)
	local label = PLAN_REASONS[step.reason] or step.reason
	if step.reason == "keeping" then
		label = string.format(L["Keeping %s"], tostring(rule.keep))
	end
	return {
		unit = unit and Post.silver(unit) or nil,
		reason = "plan", label = label, plan = step,
		floor = step.floor or 0, normal = unit or 0,
		ask = step.action == "ask" or nil,
		quantity = step.quantity,
		estimate = not book or nil,
	}
end

-- A row priced: market value, the cheapest other listing (live, else the last scan's for the list) and
-- the suggestion; one priced without a live search is an estimate, never posted. `s`: the settings,
-- read once for every row of a refresh.
local function price(r, s)
	s = s or settings()
	r.priced = true
	local value, valueFrom, trend, week = ns.price.valued(r.id)
	local market, from = ns.Prices.sellBase(value, valueFrom, week)
	r.market, r.marketFrom, r.trend, r.anyway = market, ns.price.sourceLabel(from), trend, nil
	r.typical = from == "typical price" and market or nil
	local l = ah.live[r.key]
	if l then
		local book = not r.commodity and sellBook(r.id, false, r.itemKey)
		r.cheapest, r.cheapestFrom = (book or l).cheapest, "live"
	else
		r.cheapest, r.cheapestFrom = ns.price.cheapest(r.id), "scan"
	end
	r.vendor = ns.price.vendor(r.id)
	-- The rule: an override for the item, or its category, over the default.
	local _, _, class = ns.price.itemInfo(r.id)
	local postRule, ruleFrom = Post.resolve(s.rule, s.overrides, r.id, class)
	local volatile, day = ns.price.today(r.id)
	local item = { vendor = r.vendor, cut = ns.price.cut, volatile = volatile, day = day }
	local days = postRule.supplyDays or Post.DEFAULT.supplyDays
	local sold, listed = ns.Prices.supply(r.id)
	r.postSize, r.supplyLine = ns.Prices.postSize(sold, r.count, days), ns.Prices.supplyLine(sold, listed, r.count, days)
	local plan = ns.SalePlan.ruleFor(activeProfile(s), r.id)
	if plan then
		r.suggestion = planned(r, plan, market, market and Post.limits(postRule, market, item))
	else
		r.suggestion, r.anyway = Post.advise(postRule, market, r.cheapest, item)
		if r.suggestion then
			r.suggestion.estimate = not l or nil
			r.suggestion.label = Post.label(r.suggestion, postRule, money, l ~= nil)
				.. (ruleFrom == "item" and L[" (item rule)"] or ruleFrom == "category" and L[" (category rule)"] or "")
		end
	end
	-- Holding more than the days of supply, the suggested post is that many days' worth.
	local sized = r.commodity and not plan and not s.quantities[r.key] and r.postSize and r.postSize < r.count
	r.sizeReason = sized and Post.supplyReason(days) or nil
	return r
end

-- The Cancel view (gf#369): the player's own auctions, each searched live (the Auctions tab's check), in
-- two lists with their reasons: undercut by more units than the tolerance, and those the rule would post
-- higher now that the cheaper listings sold. Cancel next, or Space while the view shows, cancels one a
-- press (CancelAuction is a hardware event, and costs the deposit); the items come back by mail.
local AHEADS = { 0, 3, 10 }
local HIGHER_BY = 10 -- percent: reposting costs a new deposit, so only a clear gain is offered

local function aheadTolerance()
	return settings().ahead or 3
end

-- Each owned auction against its item's live book, and what the rule would post it at now.
local function review(s)
	s = s or settings()
	for _, a in ipairs(ah.owned) do
		local key = bookKey(a.itemID, a.commodity, a.itemKey and a.itemKey.itemLevel)
		local book = sellBook(a.itemID, a.commodity, a.itemKey)
		a.levels, a.cheapest = book and book.levels, book and book.cheapest
		local r = book and price({ key = key, id = a.itemID, count = a.quantity, commodity = a.commodity, itemKey = a.itemKey }, s)
		a.repost = r and r.suggestion and r.suggestion.unit or nil
	end
	return Post.cancelReview(ah.owned, aheadTolerance(), HIGHER_BY)
end

-- The undercut first, then the higher.
local function nextToCancel(list)
	return list.undercut[1] or list.higher[1]
end

local function cancelView()
	return ah.panel and ah.panel.post and ah.panel.post.cancelView
end

local function cancelNext()
	local view = cancelView()
	if not view or busy() or ah.checking then
		return
	end
	local a = nextToCancel(review())
	if not a then
		view.note:SetText(L["Nothing to cancel."])
		return
	end
	C_AuctionHouse.CancelAuction(a.auctionID)
	await("cancel", "cancel:" .. a.auctionID, view.note)
	view.note:SetText(string.format(L["Cancelling %s..."], a.name))
end

-- The Auctions tab's check, which writes its progress on that tab's page: built first, hidden.
local function checkOwned()
	ah.panel.ensure("cancel")
	ns.AuctionCancel.startCheck()
end

local function showCancel(on)
	ah.sellView = on and "cancel" or nil
	local view = cancelView()
	if view then
		view:SetShown(on and true or false)
	end
	ah.refresh()
end

ns.on("AUCTION_CANCELED", "auction sell cancel", function()
	local view = cancelView()
	if view and view:IsShown() then
		view.note:SetText(Theme.escape(Theme.color.success) .. L["Cancelled: it comes back by mail."] .. "|r")
		ah.refresh()
	end
end)

-- Why an auction is in its list: units listed under it and the cheapest, or the price it would get now.
local function cancelReason(a)
	if a.up then
		return string.format(L["Cheaper ones sold: %s now (+%s%%)"], money(a.repost), tostring(a.up))
	end
	return string.format(L["%d ahead, cheapest %s"], a.ahead or 0, a.cheapest and money(a.cheapest) or "-")
end

-- Over the whole Sell page while it shows: Back, the tolerance and Check, the two lists, Cancel next.
local function buildCancelView(page)
	local v = UI.Panel(page, { color = Theme.color.bg })
	v:SetAllPoints(page)
	v:SetFrameLevel(page:GetFrameLevel() + 20)
	v:EnableMouse(true)
	v:Hide()
	local back = UI.Button(v, L["< Sell"], function()
		showCancel(false)
	end, { kind = "ghost", width = 80, height = 24 })
	back:SetPoint("TOPLEFT", 0, -2)
	local check = UI.Button(v, L["Check my auctions"], function()
		ns.safely("auction sell cancel", checkOwned)
	end, { width = 150, height = 28 })
	check:SetPoint("TOPRIGHT", 0, 0)
	local choices = {}
	for i, n in ipairs(AHEADS) do
		choices[i] = { value = n, label = ns.plural(n, L["%d item"], L["%d items"]) }
	end
	local aheadLabel = UI.Text(v, L["Undercut by more than"], { size = "sm", tone = "muted" })
	aheadLabel:SetPoint("TOPLEFT", 0, -45)
	local ahead = UI.Dropdown(v, choices, aheadTolerance(), function(n)
		settings().ahead = n
		ah.refresh()
	end)
	ahead:SetPoint("LEFT", aheadLabel, "RIGHT", 10, 0)
	ahead:SetWidth(100)
	local function list(heading, empty, tone)
		local head = UI.Text(v, heading, { size = "xs", medium = true, tone = "faint" })
		local tbl = UI.Table(v, {
			{ key = "name", title = L["Your auction"], flex = 2, color = function(r) return Theme.quality[r.quality] or Theme.color.text end,
				text = function(r) return r.quantity > 1 and (r.name .. Theme.escape(Theme.color.textFaint) .. " x" .. r.quantity .. "|r") or r.name end },
			{ key = "unit", title = L["Yours"], width = 74, align = "RIGHT", text = function(r) return money(r.unit) end },
			{ key = "why", title = L["Why"], flex = 3, text = cancelReason, color = function() return Theme.color[tone] end },
		}, { pageSize = 3, rowHeight = 22, empty = empty, itemId = function(r) return r.itemID end,
			onRowClick = function(r)
				Blizzard.browse(r.itemKey)
			end })
		tbl:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -4)
		tbl:SetPoint("RIGHT", v, "RIGHT")
		return head, tbl
	end
	local underHead, under = list(L["UNDERCUT"], L["Check your auctions to see which are undercut."], "warning")
	underHead:SetPoint("TOPLEFT", 0, -78)
	local higherHead, higher = list(L["REPOST HIGHER"], L["None would sell higher now."], "accent")
	higherHead:SetPoint("TOPLEFT", under, "BOTTOMLEFT", 0, -10)
	v.under, v.higher = under, higher
	local go = UI.Button(v, L["Cancel next"], function()
		ns.safely("auction sell cancel", cancelNext)
		ah.refresh()
	end, { kind = "primary", width = 200, height = 30 })
	go:SetPoint("TOPRIGHT", higher, "BOTTOMRIGHT", 0, -10)
	v.go = go
	v.note = UI.Text(v, L["Space cancels the next one while this view shows."], { size = "xs", tone = "faint", wrap = true })
	v.note:SetPoint("TOPLEFT", higher, "BOTTOMLEFT", 0, -12)
	v.note:SetPoint("RIGHT", go, "LEFT", -12, 0)
	function v:Refresh()
		ahead:Set(aheadTolerance())
		local found = review()
		under:SetRows(found.undercut, true)
		higher:SetRows(found.higher, true)
		local first = nextToCancel(found)
		if ah.checking == 0 then
			go:SetLabel(L["Reading..."])
		elseif ah.checking then
			go:SetLabel(string.format(L["Checking %d of %d..."], ah.checking, #ah.owned))
		elseif first then
			local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(first.auctionID)
			go:SetLabel(string.format(L["Cancel %s"], first.name) .. (cost and cost > 0 and (" (" .. money(cost) .. ")") or ""))
		else
			go:SetLabel(L["Cancel next"])
		end
		go:SetEnabled((first and not ah.checking and not busy()) and true or false)
	end
	return v
end

local lastArgs -- what the last post sent, for confirming it after the client's warning
local postedAt -- when the panel last sent a post (GetTime)
local WARNING_WINDOW = 2 -- seconds after the panel's own post in which the client's warning is for it

-- The duration an item posts for: the one last chosen for it, else the default.
local function durationOf(r)
	local s = settings()
	return r and s.durations[r.key] or s.duration
end

-- How many to post: of a commodity, the number chosen for it (at first the suggested size, or all without
-- one), never more than held; other items one at a time.
local function quantity(r)
	if not r.commodity then
		return 1
	end
	-- Post all: the whole holding, for this press only.
	if ah.allFor == r.key then
		return r.count
	end
	local picked = settings().quantities[r.key]
	-- A sale plan's quantity (what is over its keep) unless the player chose a number.
	local default = r.suggestion and r.suggestion.quantity or r.postSize or r.count
	return math.max(1, math.min(r.count, picked or default))
end

local function posting(r)
	await("post", r.key, ah.panel.post.note)
	ah.panel.post.note:SetText(L["Posting..."])
end

-- The unit price to post at, and whether it is forced: held under the floor, Post anyway posts at the
-- undercut price on a second press; nil when there is none yet.
local function unitToPost(r)
	local unit = r.suggestion.unit
	if unit or not r.anyway then
		return unit, false
	end
	if ah.armed ~= r.key .. ":anyway" then
		ah.armed = r.key .. ":anyway"
		-- Wide, the button itself asks for the second press (addon#91).
		local text = ah.panel.post.wide and Wide.underFloor(r) or string.format(L["%s is under your floor of %s. Press again to post anyway."],
			money(r.anyway), money(r.suggestion.floor))
		ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. text .. "|r")
		return nil
	end
	return r.anyway, true
end

-- The client warned about this post: the press confirms it, as its own window's button does. Only for
-- what was warned about: the price or quantity changed since, and the press posts afresh. True when
-- confirmed.
local function confirmWarned(r, unit)
	local args = ah.confirm and ah.confirm.key == r.key and ah.confirm.args
	if not (args and args[3] == quantity(r) and (r.commodity and args[4] or args[5] / quantity(r)) == unit) then
		return false
	end
	ah.confirm = nil
	-- The arguments as posted, a nil bid included (unpack stops at a hole without the count).
	if r.commodity and C_AuctionHouse.ConfirmPostCommodity then
		C_AuctionHouse.ConfirmPostCommodity(unpack(args, 1, args.n))
	elseif C_AuctionHouse.ConfirmPostItem then
		C_AuctionHouse.ConfirmPostItem(unpack(args, 1, args.n))
	end
	posting(r)
	return true
end

-- A price the panel warns about takes a second press; true while it waits for it.
local function waitsForSecondPress(r, unit, forced)
	local warning = not forced and (Post.check(unit, r.market, r.vendor, ns.price.cut)
		or (r.suggestion.ask and L["at the plan's fixed price though the market moved"]))
	if not warning or ah.armed == r.key then
		return false
	end
	ah.armed = r.key
	ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. string.format(L["Press again to post %s."], warning) .. "|r")
	return true
end

-- The client says at once whether the post needs confirming (a price far from the going one); then the
-- next press confirms it, as Blizzard's own sell window does, and no answer is waited for.
local function send(r, unit)
	local duration = durationOf(r)
	local loc = r.locations[1]
	local q = quantity(r)
	Blizzard.clearSell()
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
		ah.confirm = { key = r.key, args = lastArgs }
		ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. L["The auction house warns this price is far from the going one. Press again to post anyway."] .. "|r")
		return
	end
	posting(r)
end

-- Posts the chosen row: commodities all at once at the unit price, other items one location at a time.
local function post()
	-- In the Cancel view, Space cancels instead.
	if ah.sellView == "cancel" then
		cancelNext()
		return
	end
	local r = ah.chosen
	if not r or busy() or not r.suggestion then
		return
	end
	if r.suggestion.estimate then
		ah.panel.post.note:SetText(L["Searching the auction house for the live price..."])
		search(r, false)
		return
	end
	local unit, forced = unitToPost(r)
	if not unit or confirmWarned(r, unit) then
		return
	end
	ah.confirm = nil
	if waitsForSecondPress(r, unit, forced) then
		return
	end
	ah.armed = nil
	send(r, unit)
end

-- Post all: the chosen row's whole holding, past the days of supply.
local function postAll()
	if ah.chosen and ah.sellView ~= "cancel" then
		ah.allFor = ah.chosen.key
		post()
	end
end

local function posted()
	if not ah.waits.post then
		return -- not the panel's post (Blizzard's own Sell window)
	end
	local key = ah.waits.post.key
	ah.waits.post, ah.allFor = nil, nil
	ah.live[key] = nil
	-- The next row; the bags update a moment later and the list follows.
	local next
	for i, r in ipairs(ah.rows) do
		if r.key == key then
			next = ah.rows[i + 1] or ah.rows[i - 1]
		end
	end
	ah.chosen = next
	if ah.panel then
		ah.panel.post.note:SetText(Theme.escape(Theme.color.success) .. L["Posted."] .. "|r")
	end
	if next then
		-- Into Blizzard's Sell window too, as a click on it does.
		search(next, true)
	end
end
ns.on("AUCTION_HOUSE_AUCTION_CREATED", "auction panel", posted)
-- The client warns before some commodity posts (far under the going price): the next press confirms.
ns.on("AUCTION_HOUSE_POST_WARNING", "auction panel", function()
	-- The panel's: its post waiting for an answer, or one it was just warned about. Else it is a post
	-- from Blizzard's own Sell window, and its popup is the player's to answer.
	local fresh = ah.confirm and postedAt and GetTime() - postedAt <= WARNING_WINDOW
	if not (ah.waits.post or fresh) then
		return
	end
	if ah.waits.post and lastArgs then
		ah.confirm = { key = ah.waits.post.key, args = lastArgs }
	end
	Blizzard.closeWarning()
	ah.waits.post = nil
	if ah.panel and ah.panel.post.note then
		ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. L["The auction house warns this price is far from the going one. Press again to post anyway."] .. "|r")
	end
end)
-- A post the server refused: say so at once rather than after the wait.
ns.on("AUCTION_HOUSE_POST_ERROR", "auction panel", function()
	if ah.waits.post then
		ah.waits.post = nil
		if ah.panel and ah.panel.post.note then
			ah.panel.post.note:SetText(Theme.escape(Theme.color.danger) .. L["The auction house refused the post."] .. "|r")
		end
	end
end)

-- The tab's two layouts (addon#84): narrow, the list over the item's box; wide, the panel wider, the
-- list taller and wider, the box a column beside it. Wide takes only the room the screen has beside the
-- auction house; with too little for a list beside the box it stays narrow (`cramped`).
local PAD = 36 -- the page's inset in the panel, left and right
local GAP = 12 -- between the list and the box
local COLUMN = 416 -- the box beside the list: half the page at 880 (addon#91); with less room the list takes the cut
local WIDE = 880 -- the wide panel's width, room allowing
local MIN_LIST = 260 -- the narrowest list worth putting beside the box
local ROWS = { narrow = 5, wide = 13 }

local function layout(wide, room)
	local narrow = { wide = false, width = ah.WIDTH, rows = ROWS.narrow, list = ah.WIDTH - PAD, pad = PAD }
	if not wide then
		return narrow
	end
	local width = room and math.min(WIDE, math.floor(room)) or WIDE
	if width - PAD - GAP - COLUMN < MIN_LIST then
		narrow.cramped = true
		return narrow
	end
	return { wide = true, width = width, rows = ROWS.wide, list = width - PAD - GAP - COLUMN, column = COLUMN, gap = GAP, pad = PAD }
end

-- Previous / Next under the wide list (addon#86): only wide and with more than one page; `page` is the
-- table's, already within its pages.
local function pager(wide, count, page, size)
	local pages = math.ceil(count / size)
	if not wide or pages <= 1 then
		return { shown = false }
	end
	return { shown = true, text = page .. " / " .. pages, previous = page > 1, next = page < pages }
end

local DOCK = 6 -- the panel's gap to the auction house (AuctionPanel.lua)
local MARGIN = 8 -- kept free at the screen's edge

-- The room beside the auction house in the panel's units, or nil before the auction house is placed.
local function roomBeside(panel)
	local right = AuctionHouseFrame and AuctionHouseFrame:GetRight()
	local edge = UIParent:GetRight()
	if type(right) ~= "number" or type(edge) ~= "number" then
		return nil
	end
	local px = (edge * UIParent:GetEffectiveScale() - right * AuctionHouseFrame:GetEffectiveScale())
	return px / panel:GetEffectiveScale() - DOCK - MARGIN
end

-- The deposit the client takes for posting `q` of the row for duration `d`, where it says; else nil.
local function deposit(r, d, q)
	local AH = C_AuctionHouse
	if r.commodity then
		return AH.CalculateCommodityDeposit and AH.CalculateCommodityDeposit(r.id, d, q) or nil
	end
	return AH.CalculateItemDeposit and r.locations[1] and AH.CalculateItemDeposit(r.locations[1], d, q) or nil
end

-- The list's columns, narrow and wide: wide, the item's icon before its name and money in full (6g 98s
-- 99c), a held item's price "hold" (addon#91). A cell is its column's width less 16.
local COLUMNS = { narrow = { typical = 84, post = 92 }, wide = { typical = 100, post = 104 } }

local function buildPost(page)
	local wideNow = false
	local function cash(copper)
		return wideNow and ns.Money.format(copper, "colour") or money(copper)
	end
	local function itemName(r)
		local icon = wideNow and r.icon and ("|T" .. r.icon .. ":18:18|t ") or ""
		return icon .. r.name .. Theme.escape(Theme.color.textFaint) .. " x" .. r.count .. "|r"
	end
	local function postAt(r)
		local sug = r.suggestion
		if sug and sug.unit then
			return cash(sug.unit)
		end
		return wideNow and sug and (Theme.escape(Theme.color.textFaint) .. L["hold"] .. "|r") or "-"
	end
	local tbl = UI.Table(page, {
		{ key = "name", title = L["Item"], flex = 3, text = itemName, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		-- The typical price, what selling is priced against; the tooltip's "Market" is the day's value (addon#21).
		{ key = "typical", title = L["Typical"], width = COLUMNS.narrow.typical, align = "RIGHT", text = function(r) return r.typical and cash(r.typical) or "-" end, sort = function(r) return r.typical or 0 end },
		{ key = "post", title = L["Post at"], width = COLUMNS.narrow.post, align = "RIGHT", text = postAt, sort = function(r) return r.suggestion and r.suggestion.unit or 0 end },
	}, {
		pageSize = 5,
		rowHeight = 24,
		empty = L["Nothing in your bags the auction house takes."],
		itemId = function(r) return r.id end,
		isSelected = function(r) return ah.chosen and r.key == ah.chosen.key end,
		onRowClick = function(r)
			-- Another row disarms a pressed Post anyway; wide, its warning goes with it.
			if wideNow and ah.armed then
				page.note:SetText("")
			end
			ah.chosen, ah.armed, ah.confirm, ah.allFor = r, nil, nil, nil
			search(r, true)
			ah.refresh()
		end,
	})
	page.table = tbl

	local detail = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	page.detail = detail
	local name = UI.Text(detail, "", { size = "md", medium = true })
	name:SetPoint("TOPLEFT", 14, -12)
	name:SetPoint("RIGHT", detail, "RIGHT", -244, 0)
	-- The selling rules live in the hub: this opens them on a rule for the item in view.
	local function openRule()
		ns.openPage("rules")
		if ns.rulesPage and ah.chosen then
			ns.rulesPage.chooseScope("add-item")
		end
	end
	local ruleButton = UI.Button(detail, L["Rule >"], openRule, { width = 72, height = 24 })
	ruleButton:SetPoint("TOPRIGHT", -10, -8)
	page.ruleButton = ruleButton
	-- Wide or narrow, saved in the settings; the label offers the other.
	local function toggleLayout()
		local s = settings()
		s.sellWide = not s.sellWide
		page.applyLayout()
		ah.refresh()
	end
	local layoutButton = UI.Button(detail, L["Wide"], toggleLayout, { kind = "ghost", width = 64, height = 24 })
	layoutButton:SetPoint("RIGHT", ruleButton, "LEFT", -6, 0)
	page.layoutButton = layoutButton
	local function openCancel()
		showCancel(true)
	end
	local cancelButton = UI.Button(detail, L["Cancel >"], openCancel, { kind = "ghost", width = 72, height = 24 })
	cancelButton:SetPoint("RIGHT", layoutButton, "LEFT", -6, 0)
	local reason = UI.Text(detail, "", { size = "sm" })
	reason:SetPoint("TOPLEFT", name, "BOTTOMLEFT", 0, -8)
	reason:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
	local facts = UI.Text(detail, "", { size = "xs", tone = "muted", wrap = true })
	page.facts = facts
	facts:SetPoint("TOPLEFT", reason, "BOTTOMLEFT", 0, -6)
	facts:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
	-- The cheapest listings, the player's own marked, from the last search.
	local listHead = UI.Text(detail, L["LISTINGS"], { size = "xs", medium = true, tone = "faint" })
	listHead:SetPoint("TOPLEFT", facts, "BOTTOMLEFT", 0, -10)
	local listed = {}
	for i = 1, LISTED do
		local unit = UI.Text(detail, "", { size = "sm", align = "RIGHT" })
		unit:SetPoint("TOPLEFT", listHead, "BOTTOMLEFT", 0, -4 - (i - 1) * 15)
		unit:SetWidth(110)
		local qty = UI.Text(detail, "", { size = "xs", tone = "muted" })
		qty:SetPoint("LEFT", unit, "RIGHT", 12, 0)
		qty:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
		listed[i] = { unit = unit, qty = qty }
	end
	-- Chosen for the item in view and remembered for it; with no item chosen, the default.
	local duration = UI.Dropdown(detail, DURATIONS, settings().duration, function(v)
		if ah.chosen then
			settings().durations[ah.chosen.key] = v
		else
			settings().duration = v
		end
		ah.refresh()
	end)
	page.duration = duration
	-- How many of a commodity to post, remembered for it; hidden for gear (one at a time).
	local qtyLabel = UI.Text(detail, L["Post"], { size = "sm", tone = "muted" })
	local function chooseQuantity(v)
		if ah.chosen then
			settings().quantities[ah.chosen.key], ah.allFor = v, nil
			ah.refresh()
		end
	end
	local qty = UI.Slider(detail, 1, 2, 1, 1, chooseQuantity, function(v)
		return tostring(v)
	end)
	local function pressAll()
		ns.safely("auction post all", postAll)
		ah.refresh()
	end
	local allButton = UI.Button(detail, L["Post all"], pressAll, { kind = "ghost", width = 90, height = 24 })
	allButton:SetPoint("BOTTOMRIGHT", -14, 52)
	page.allButton = allButton
	qty:SetPoint("LEFT", qtyLabel, "RIGHT", 12, 0)
	qty:SetPoint("RIGHT", allButton, "LEFT", -10, 0)
	page.quantity = qty
	duration:SetWidth(110)
	local function press()
		ns.safely("auction post", post)
		ah.refresh()
	end
	local button = UI.Button(detail, L["Post"], press, { kind = "primary", width = 240, height = 30 })
	page.button = button
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })

	-- Wide, the box beside the list (addon#91); quantity and duration remembered for the item as narrow's.
	local box = Wide.build(page, {
		post = press, postAll = pressAll, rule = openRule, toggle = toggleLayout, cancel = openCancel,
		quantity = chooseQuantity,
		duration = function(v)
			if ah.chosen then
				settings().durations[ah.chosen.key] = v
			else
				settings().duration = v
			end
			ah.refresh()
		end,
	})
	box:Hide()
	page.box = box
	page.cancelView = buildCancelView(page)
	page.count = UI.Text(page, "", { size = "xs", tone = "faint" })

	-- Under the wide list at its right: Previous, the page of how many, Next; the wheel still pages.
	local paging = CreateFrame("Frame", nil, page)
	paging:SetSize(220, 24)
	local function turn(by)
		return function()
			tbl.page = tbl.page + by
			tbl:Refresh()
		end
	end
	paging.previous = UI.Button(paging, L["Previous"], turn(-1), { width = 80, height = 22 })
	paging.next = UI.Button(paging, L["Next"], turn(1), { width = 80, height = 22 })
	paging.text = UI.Text(paging, "", { size = "xs", tone = "muted", align = "CENTER" })
	paging.next:SetPoint("RIGHT")
	paging.text:SetPoint("RIGHT", paging.next, "LEFT", -6, 0)
	paging.text:SetWidth(48)
	paging.previous:SetPoint("RIGHT", paging.text, "LEFT", -6, 0)
	page.pager = paging
	local drawTable = tbl.Refresh
	-- Every redraw of the list (rows, a click, the wheel, a resize) sets the pager to the page shown.
	function tbl:Refresh()
		drawTable(self)
		local p = pager(wideNow, #self.all, self.page, self.size)
		paging:SetShown(p.shown)
		if p.shown then
			paging.text:SetText(p.text)
			paging.previous:SetEnabled(p.previous)
			paging.next:SetEnabled(p.next)
		end
	end

	-- Narrow: the list over the box, its controls in a row at the bottom. Wide: the box a column at the
	-- page's right, the list up to it, the controls stacked, the Post button the column's width.
	local function place(plan)
		local panel = page:GetParent()
		panel:SetWidth(plan.width)
		wideNow = plan.wide
		page.wide = plan.wide
		local widths = COLUMNS[plan.wide and "wide" or "narrow"]
		tbl.columns[2].width, tbl.columns[3].width = widths.typical, widths.post
		tbl.size = plan.rows
		tbl:ClearAllPoints()
		detail:ClearAllPoints()
		duration:ClearAllPoints()
		qtyLabel:ClearAllPoints()
		button:ClearAllPoints()
		box:ClearAllPoints()
		page.note:ClearAllPoints()
		tbl:SetPoint("TOPLEFT")
		detail:SetShown(not plan.wide)
		box:SetShown(plan.wide)
		page.count:SetShown(plan.wide)
		page.layoutButton = plan.wide and box.layoutButton or layoutButton
		if plan.wide then
			-- Two halves: the list, and the box the page's full height.
			box:SetPoint("TOPRIGHT", page, "TOPRIGHT")
			box:SetPoint("BOTTOMRIGHT", page, "BOTTOMRIGHT")
			box:SetWidth(plan.column)
			tbl:SetPoint("RIGHT", box, "LEFT", -plan.gap, 0)
			box.placeNote(page.note)
			page.count:ClearAllPoints()
			page.count:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
		else
			tbl:SetPoint("RIGHT", page, "RIGHT")
			detail:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
			detail:SetPoint("RIGHT", page, "RIGHT")
			detail:SetHeight(252)
			button:SetPoint("BOTTOMRIGHT", -14, 11)
			button:SetWidth(240)
			duration:SetPoint("BOTTOMLEFT", 14, 12)
			qtyLabel:SetPoint("BOTTOMLEFT", 14, 56)
			page.note:SetParent(page)
			page.note:SetPoint("TOPLEFT", detail, "BOTTOMLEFT", 0, -8)
			page.note:SetPoint("RIGHT", page, "RIGHT")
			page.note:SetWordWrap(true)
		end
		paging:ClearAllPoints()
		paging:SetPoint("TOPRIGHT", tbl, "BOTTOMRIGHT", 0, -6)
		tbl:Refresh()
	end
	-- The layout chosen, as far as the room beside the auction house allows: on showing, and on a toggle.
	function page.applyLayout()
		local wide = settings().sellWide
		local plan = layout(wide, wide and roomBeside(page:GetParent()) or nil)
		place(plan)
		layoutButton:SetLabel(wide and L["Narrow"] or L["Wide"])
		box.layoutButton:SetLabel(L["Narrow"])
		if plan.cramped then
			page.note:SetText(L["Too little room beside the auction house for the wide layout at this UI scale."])
		end
	end
	page.applyLayout()
	page:HookScript("OnShow", page.applyLayout)
	-- The other tabs keep the panel's own width.
	page:HookScript("OnHide", function()
		page:GetParent():SetWidth(ah.WIDTH)
	end)

	-- Wide: the box drawn from the chosen row, its book and what posting it would take.
	local function drawWide()
		local r = ah.chosen
		page.count:SetText(ns.plural(#ah.rows, L["%d item in your bags"], L["%d items in your bags"]))
		if not r then
			box:Draw({ note = page.note:GetText() })
			return
		end
		local live = ah.live[r.key]
		local book = sellBook(r.id, r.commodity, r.itemKey)
		local q, d = quantity(r), durationOf(r)
		box:Draw({
			r = r, quantity = q, duration = d, live = live, levels = live and book and book.levels or nil,
			armed = ah.armed == r.key .. ":anyway", busy = busy(), deposit = deposit(r, d, q), note = page.note:GetText(),
			all = r.commodity and q < r.count and r.suggestion and r.suggestion.unit and not r.suggestion.estimate and not busy() or false,
		})
	end

	function page:Refresh()
		page.cancelView:SetShown(ah.sellView == "cancel")
		if ah.sellView == "cancel" then
			page.cancelView:Refresh()
			return
		end
		local faint = Theme.escape(Theme.color.textFaint)
		if wideNow then
			drawWide()
			return
		end
		if not ah.chosen then
			name:SetText(faint .. L["Choose an item."] .. "|r")
			reason:SetText("")
			facts:SetText(L["Space posts the chosen item while this panel shows."])
			button:SetEnabled(false)
			allButton:Hide()
			return
		end
		local r = ah.chosen
		duration:Set(durationOf(r))
		local many = r.commodity and r.count > 1
		qtyLabel:SetShown(many)
		qty:SetShown(many)
		local sug = r.suggestion
		local live = sug and not sug.estimate
		allButton:SetShown(many and quantity(r) < r.count and live and sug.unit and true or false)
		allButton:SetEnabled(not busy())
		if many then
			qty:SetRange(1, r.count)
			qty:Set(quantity(r))
		end
		name:SetText(Theme.escape(Theme.quality[r.quality] or Theme.color.text) .. r.name .. "|r" .. faint .. "  x" .. quantity(r) .. (r.commodity and "" or L[" (one at a time)"]) .. "|r")
		local tone = not sug and Theme.color.textFaint or sug.reason == "hold" and Theme.color.warning or Theme.color.accent
		local hint = Post.trendHint(r.trend)
		reason:SetText(Theme.escape(tone) .. (sug and (sug.label or Post.REASONS[sug.reason]) or L["No price yet: scan first"]) .. "|r"
			.. (sug and sug.unit and ("  " .. money(sug.unit) .. faint .. L[" each"] .. "|r") or "")
			.. (hint and ("  " .. Theme.escape(r.trend > 0 and Theme.color.warning or Theme.color.textFaint) .. hint .. "|r") or "")
			.. (r.sizeReason and ("  " .. faint .. r.sizeReason .. "|r") or ""))
		local cheapest = r.cheapest and (money(r.cheapest) .. faint .. (r.cheapestFrom == "live" and L[" (live)"] or L[" (last scan, yours included)"]) .. "|r") or (faint .. L["none"] .. "|r")
		-- The market's trend on the week, when the pool carries one: green rising, red falling.
		local trend = ""
		if r.trend then
			local tone = r.trend >= 1 and Theme.color.success or r.trend <= -1 and Theme.color.danger or Theme.color.textFaint
			trend = Theme.escape(tone) .. (string.gsub(ns.Prices.trendText(r.trend), "^ · ", " ")) .. "|r"
		end
		-- The price Sell measures against, named for what it is: the typical price, or the market value and its source.
		local base = r.typical and string.format(L["typical %s"], money(r.typical))
			or (string.format(L["market %s"], r.market and money(r.market) or "-") .. (r.marketFrom and (faint .. " (" .. r.marketFrom .. ")|r") or ""))
		facts:SetText(string.format(L["Cheapest other %s · %s%s · floor %s · maximum %s"], cheapest, base, trend,
			sug and money(sug.floor) or "-", sug and sug.maximum and money(sug.maximum) or "-") .. (r.supplyLine and ("\n" .. r.supplyLine) or "")
			.. (Wide.altsNote(r) and ("\n" .. Wide.altsNote(r)) or ""))
		local l = ah.live[r.key]
		local alts = not r.commodity and l and (sellBook(r.id, false, r.itemKey) or {}).alts or {}
		for i, line in ipairs(listed) do
			local x = l and l.list and l.list[i]
			line.unit:SetText(x and money(x.unit) or (i == 1 and (faint .. (l and L["none listed"] or L["searching..."]) .. "|r") or ""))
			line.qty:SetText(x and ("x" .. x.qty .. ((x.own or alts[x.auctionID]) and (Theme.escape(Theme.color.accent) .. "  " .. L["yours"] .. "|r") or "")) or "")
		end
		listHead:SetText(l and l.total and l.total > LISTED and string.format(L["LISTINGS · CHEAPEST %d OF %d"], LISTED, l.total) or L["LISTINGS"])
		local can = live and (sug.unit or r.anyway) and not busy()
		if can then
			button:SetLabel(sug.unit and string.format(L["Post %d x %s"], quantity(r), money(sug.unit)) or string.format(L["Post anyway: %s"], string.format("%d x %s", quantity(r), money(r.anyway))))
		elseif sug and sug.estimate then
			button:SetLabel(L["Searching..."])
		else
			button:SetLabel(sug and sug.reason == "hold" and L["Under your floor"] or L["Post"])
		end
		button:SetEnabled(can and true or false)
	end
end


-- The rows priced again, the chosen one found among them, and the tab drawn.
local function refresh(page)
	local s = settings()
	for _, r in ipairs(ah.rows) do
		price(r, s)
	end
	if ah.chosen then
		for _, r in ipairs(ah.rows) do
			if r.key == ah.chosen.key then
				ah.chosen = r
			end
		end
	end
	page.table:SetRows(ah.rows, true) -- a click or the auction house's results keep the page (addon#76)
	page:Refresh()
end

-- The bags read again: the chosen row kept if it is still there, else the first.
local function reread()
	ah.rows = sellable()
	local still
	for _, r in ipairs(ah.rows) do
		if ah.chosen and r.key == ah.chosen.key then
			still = r
		end
	end
	ah.chosen = still or ah.rows[1]
	ah.refresh()
end

-- While the panel shows, a bag item's tooltip says what Post would ask for it (owner's answer,
-- 2026-10-24): the same price and reason as the Post tab, rule, override or profile.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function postTooltip(tooltip, data)
		if tooltip ~= GameTooltip or not data or not data.id or not ah.panel or not ah.panel:IsShown() then
			return
		end
		for _, r in ipairs(ah.rows) do
			if r.id == data.id then
				-- As the Sell tab last priced it; priced here only if it never was.
				if not r.priced then
					price(r)
				end
				local sug = r.suggestion
				if sug and sug.unit then
					tooltip:AddLine(ns.tipPrefix(tooltip) .. string.format(L["Post at %s · %s"], money(sug.unit), sug.label or Post.REASONS[sug.reason] or ""), 1, 1, 1)
				elseif sug then
					tooltip:AddLine(ns.tipPrefix(tooltip) .. (sug.label or Post.REASONS[sug.reason] or L["Hold"]), 0.6, 0.6, 0.6)
				end
				return
			end
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("auction tooltip", postTooltip, tooltip, data)
	end)
end

ns.AuctionSell = { key = "post", label = L["Sell"], build = buildPost, refresh = refresh, post = post, postAll = postAll, reread = reread, layout = layout, pager = pager,
	showCancel = showCancel, checkOwned = checkOwned, review = review, cancelNext = cancelNext }
