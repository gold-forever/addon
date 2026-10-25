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
local CONFIRM_TIMEOUT = ns.ah.CONFIRM_TIMEOUT

local settings = ns.auctionSettings
local ah = ns.ah
local Blizzard = ns.AuctionBlizzard
local Books = ns.AuctionBooks
local bookKey, search, searchEntry, LISTED = Books.bookKey, Books.search, Books.searchEntry, Books.LISTED

local await, busy = ah.await, ah.busy
local money = ah.money

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
local activeProfile = ns.activeProfile

local heldHere = ns.Holdings.heldHere
local lists, stamp = ns.Lists.lists, ns.Lists.stamp

-- A sale plan's step as the Post tab's suggestion: posts in whole silver; "ask" posts the plan's price
-- after a second press; hold and skip post nothing.
local PLAN_REASONS = {
	undercut = "Undercut (plan)", fixed = "Fixed price (plan)", percentile = "Percentile (plan)", ["no-competition"] = "No one else (plan)",
	["market-moved"] = "The market moved (plan)", ["under-floor"] = "Hold: under the plan's floor", keeping = "Keeping", ["no-price"] = "No price yet",
}

local function planned(r, rule, market)
	-- Gear's book is known once the row was searched, at its own item level.
	local book = (r.commodity or r.itemKey) and ah.live[bookKey(r.id, r.commodity, r.itemKey and r.itemKey.itemLevel)]
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
	local l = ah.live[r.key]
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

local refresh, show

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
	local picked = settings().quantities[r.key]
	-- A sale plan's quantity (what is over its keep) unless the player chose a number.
	local default = r.suggestion and r.suggestion.quantity or r.count
	return math.max(1, math.min(r.count, picked or default))
end

-- Posts the chosen row: commodities all at once at the unit price, other items one location at a time.
local function post()
	local r = ah.chosen
	if not r or busy() or not r.suggestion then
		return
	end
	local unit, forced = r.suggestion.unit, false
	-- Held under the floor: Post anyway posts at the undercut price on a second press.
	if not unit and r.anyway then
		if ah.armed ~= r.key .. ":anyway" then
			ah.armed = r.key .. ":anyway"
			ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. string.format("%s is under your floor of %s. Press again to post anyway.",
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
	local args = ah.confirm and ah.confirm.key == r.key and ah.confirm.args
	if args and args[3] == quantity(r) and (r.commodity and args[4] or args[5] / quantity(r)) == unit then
		ah.confirm = nil
		-- The arguments as posted, a nil bid included (unpack stops at a hole without the count).
		if r.commodity and C_AuctionHouse.ConfirmPostCommodity then
			C_AuctionHouse.ConfirmPostCommodity(unpack(args, 1, args.n))
		elseif C_AuctionHouse.ConfirmPostItem then
			C_AuctionHouse.ConfirmPostItem(unpack(args, 1, args.n))
		end
		await("post", r.key, ah.panel.post.note)
		ah.panel.post.note:SetText("Posting…")
		return
	end
	ah.confirm = nil
	local warning = not forced and (Post.check(unit, r.market, r.vendor, ns.price.cut)
		or (r.suggestion.ask and "at the plan's fixed price though the market moved"))
	if warning and ah.armed ~= r.key then
		ah.armed = r.key
		ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "Press again to post " .. warning .. ".|r")
		return
	end
	ah.armed = nil
	local duration = durationOf(r)
	local loc = r.locations[1]
	local q = quantity(r)
	Blizzard.clearSell()
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
		ah.confirm = { key = r.key, args = lastArgs }
		ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "The auction house warns this price is far from the going one. Press again to post anyway.|r")
		return
	end
	await("post", r.key, ah.panel.post.note)
	ah.panel.post.note:SetText("Posting…")
end

local function posted()
	if not ah.waits.post then
		return -- not the panel's post (Blizzard's own Sell window)
	end
	local key = ah.waits.post.key
	ah.waits.post = nil
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
		ah.panel.post.note:SetText(Theme.escape(Theme.color.success) .. "Posted.|r")
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
		ah.panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "The auction house warns this price is far from the going one. Press again to post anyway.|r")
	end
end)
-- A post the server refused: say so at once rather than after the wait.
ns.on("AUCTION_HOUSE_POST_ERROR", "auction panel", function()
	if ah.waits.post then
		ah.waits.post = nil
		if ah.panel and ah.panel.post.note then
			ah.panel.post.note:SetText(Theme.escape(Theme.color.danger) .. "The auction house refused the post.|r")
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
		isSelected = function(r) return ah.chosen and r.key == ah.chosen.key end,
		onRowClick = function(r)
			ah.chosen, ah.armed, ah.confirm = r, nil, nil
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
		if ns.rulesPage and ah.chosen then
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
		if ah.chosen then
			settings().durations[ah.chosen.key] = v
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
		if ah.chosen then
			settings().quantities[ah.chosen.key] = v
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
		if not ah.chosen then
			name:SetText(faint .. "Choose an item.|r")
			reason:SetText("")
			facts:SetText("Space posts the chosen item while this panel shows.")
			button:Disable()
			button:SetAlpha(0.5)
			return
		end
		local r = ah.chosen
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
		local l = ah.live[r.key]
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

-- The deal for an entry from its live book, or nil before a search came back.
local function shopDeal(e)
	-- A list entry is an item id: searched with its plain item key (searchEntry), item level 0.
	local l = ah.live[tostring(e.itemId)] or ah.live[bookKey(e.itemId, false, 0)]
	if not l or not l.levels then
		return nil, l
	end
	-- Held counts only for an entry with How many.
	local held = 0
	if e.upTo then
		local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(e.itemId)) or 0
		held = heldHere(e.itemId, inBags)
	end
	return ns.Shopping.entryDeal(e, l.levels, held, ns.Prices.value(e.itemId)), l
end

-- A purchase with no answer is let go: a later purchase in Blizzard's own window is not recorded as it.
local function letGo()
	ah.buying, ah.purchase = nil, nil
end

-- One press of Buy next.
local function buyNext()
	local e = ah.shopChosen
	if not e or busy() then
		return
	end
	local deal, book = shopDeal(e)
	local note = ah.panel.shop.note
	if ah.purchase and ah.purchase.itemId == e.itemId and ah.purchase.quoted then
		-- The second press: confirm the quote the client gave (as its own Buy button does).
		local p = ah.purchase
		ah.purchase = nil
		C_AuctionHouse.ConfirmCommoditiesPurchase(p.itemId, p.quantity)
		ah.buying = { id = p.itemId, n = p.quantity }
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
	if deal.over and ah.overArmed ~= e.itemId then
		ah.overArmed = e.itemId
		local market = ns.Prices.value(e.itemId)
		note:SetText(Theme.escape(Theme.color.warning) .. string.format("Over your %d%% of market: %d for %s (up to %s each%s). Press again to buy, or choose something else.",
			deal.share or 0, deal.quantity, money(deal.total), money(deal.topUnit), market and (", market " .. money(market)) or "") .. "|r")
		return
	end
	ah.overArmed = nil
	if book.commodity then
		ah.purchase = { itemId = e.itemId, quantity = deal.quantity, expected = deal.total }
		C_AuctionHouse.StartCommoditiesPurchase(e.itemId, deal.quantity)
		note:SetText("Asking the auction house for a price…")
	else
		-- The cheapest auction by someone else at or under the limit: one a press.
		for _, a in ipairs(book.levels) do
			if a.own == 0 and a.unitPrice <= deal.limit and a.auctionID then
				C_AuctionHouse.PlaceBid(a.auctionID, a.buyout)
				ah.buying = { id = e.itemId, n = a.quantity or 1 }
				await("shop", "shop:" .. e.itemId, note, letGo)
				note:SetText("Buying one for " .. money(a.buyout) .. "…")
				return
			end
		end
		note:SetText("Nothing at or under your price now.")
	end
end

ns.on("COMMODITY_PRICE_UPDATED", "auction shop", function(unit, total)
	if not ah.purchase or not ah.panel or not ah.panel.shop.note then
		return
	end
	ah.purchase.quoted = total
	ah.purchase.moved = ns.Shopping.moved(ah.purchase.expected, total)
	local text = string.format("%d for %s", ah.purchase.quantity, money(total))
	ah.panel.shop.note:SetText(ah.purchase.moved and (Theme.escape(Theme.color.warning) .. "The price moved: " .. text .. " (the deal was " .. money(ah.purchase.expected) .. "). Press again to buy anyway.|r")
		or ("Press again to buy " .. text .. "."))
	refresh()
end)

local function bought(ok, why)
	if not ah.panel or not ah.panel.shop.note then
		return -- a purchase from Blizzard's own window, the Shop not drawn
	end
	if ok and ah.buying then
		ns.Holdings.recordBought(ah.buying)
	end
	ah.buying = nil
	ah.waits.shop, ah.purchase = nil, nil
	ah.panel.shop.note:SetText(ok and (Theme.escape(Theme.color.success) .. "Bought.|r") or (Theme.escape(Theme.color.danger) .. (why or "The purchase failed.") .. "|r"))
	if ah.shopChosen then
		ah.live[tostring(ah.shopChosen.itemId)], ah.live[bookKey(ah.shopChosen.itemId, false, 0)] = nil, nil
		searchEntry(ah.shopChosen)
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
			ah.shopChosen = nil
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
		isSelected = function(r) return ah.shopChosen and r.itemId == ah.shopChosen.itemId end,
		onRowClick = function(r)
			ah.shopChosen, ah.purchase = r.entry, nil
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
			if ah.shopChosen and e.itemId == ah.shopChosen.itemId then
				still = true
			end
		end
		if ah.shopChosen and not still then
			ah.shopChosen, ah.purchase, ah.overArmed = nil, nil, nil
		end
		local shown = {}
		for i, e in ipairs(list.entries) do
			local quality, _, _, _, name = ns.price.itemInfo(e.itemId)
			local deal, book = shopDeal(e)
			shown[i] = { entry = e, itemId = e.itemId, maxUnit = e.maxUnit, pct = e.pct, lowest = e.lowest, upTo = e.upTo, name = name or ("item " .. e.itemId), quality = quality or 1, deal = deal, searched = book ~= nil }
		end
		tbl:SetRows(shown)
		local deal = ah.shopChosen and shopDeal(ah.shopChosen)
		local label = ah.purchase and ah.purchase.quoted and ("Confirm: " .. ah.purchase.quantity .. " for " .. money(ah.purchase.quoted))
			or (deal and ("Buy " .. deal.quantity .. " for " .. money(deal.total))) or "Buy next"
		buy.label:SetText(Theme.skin.titleCaps and string.upper(label) or label)
		local can = ah.shopChosen and not busy()
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
local checkRun -- the check running, so a timer of an earlier one leaves it be

local function tolerance()
	return settings().tolerance or 5
end

-- The cheapest other listing for an owned auction, from the last search of its item.
local function cheapestFor(a)
	local book = ah.live[bookKey(a.itemID, a.commodity, a.itemKey and a.itemKey.itemLevel)]
	return book and book.cheapest or nil, book ~= nil
end

local function readOwned()
	local n = C_AuctionHouse.GetNumOwnedAuctions and C_AuctionHouse.GetNumOwnedAuctions() or 0
	ah.owned = Post.readOwned(n, C_AuctionHouse.GetOwnedAuctionInfo, C_AuctionHouse.GetItemKeyInfo, ns.price.itemInfo)
end

-- Searches the next owned auction's item; the results event moves the check on.
local function checkNext()
	ah.checking = (ah.checking or 0) + 1
	local a = ah.owned[ah.checking]
	if not a then
		ah.checking = nil
		refresh()
		return
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(a.itemKey, sorts, true)
	-- A search the server never answers (throttled) does not stall the check: on to the next.
	local at = ah.checking
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if ah.checking == at and not a.answered then
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
	ah.checking = 0
	ah.panel.cancel.note:SetText("Reading your auctions…")
	-- The list never coming (throttled, the auction house closing) does not leave the check running.
	local run = {}
	checkRun = run
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if ah.checking == 0 and checkRun == run then
			ah.checking = nil
			if ah.panel and ah.panel.cancel.note then
				ah.panel.cancel.note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the auction house; check again in a moment.|r")
			end
			refresh()
		end
	end)
end

ns.on("OWNED_AUCTIONS_UPDATED", "auction cancel", function()
	if ah.checking == 0 then
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
	local a = ah.checking and ah.checking > 0 and ah.owned[ah.checking]
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
	for _, a in ipairs(ah.owned) do
		a.cheapest = cheapestFor(a)
	end
	return Post.undercutList(ah.owned, tolerance())
end

local function cancelNext()
	if busy() then
		return
	end
	local a = undercut()[1]
	if not a then
		ah.panel.cancel.note:SetText("Nothing undercut past " .. tolerance() .. "%.")
		return
	end
	C_AuctionHouse.CancelAuction(a.auctionID)
	await("cancel", "cancel:" .. a.auctionID, ah.panel.cancel.note)
	ah.panel.cancel.note:SetText("Cancelling " .. a.name .. "…")
end

ns.on("AUCTION_CANCELED", "auction cancel", function(auctionID)
	if ah.waits.cancel and ah.waits.cancel.key == "cancel:" .. tostring(auctionID) then
		ah.waits.cancel = nil
	end
	for i, a in ipairs(ah.owned) do
		if a.auctionID == auctionID then
			table.remove(ah.owned, i)
			break
		end
	end
	if ah.panel and ah.panel.cancel.note then
		ah.panel.cancel.note:SetText(Theme.escape(Theme.color.success) .. "Cancelled: it comes back by mail.|r")
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
			Blizzard.browse(r.itemKey)
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
		for _, a in ipairs(ah.owned) do
			a.searched = select(2, cheapestFor(a))
		end
		tbl:SetRows(ah.owned)
		local first = list[1]
		if ah.checking == 0 then
			go.label:SetText("Reading…")
		elseif ah.checking then
			go.label:SetText(string.format("Checking %d of %d…", ah.checking, #ah.owned))
		elseif first then
			local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(first.auctionID)
			go.label:SetText("Cancel " .. first.name .. (cost and cost > 0 and (" (" .. money(cost) .. ")") or ""))
		else
			go.label:SetText("Cancel next")
		end
		local can = first and not ah.checking and not busy()
		if can then
			go:Enable()
			go:SetAlpha(1)
		else
			go:Disable()
			go:SetAlpha(0.5)
		end
		if not ah.checking and page.note:GetText() == "Reading your auctions…" then
			page.note:SetText(#ah.owned == 0 and "You have no auctions up."
				or string.format("%d of your %d auctions are undercut past %d%%.", #list, #ah.owned, tolerance()))
		end
	end
end

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
	local old = ah.panel
	-- One panel per look and accent, reused when the look comes back (frames are never freed).
	if ah.panels[Theme.key] then
		if old and old ~= ah.panels[Theme.key] then
			old:Hide()
		end
		ah.panel, ah.built = ah.panels[Theme.key], Theme.key
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
		if ah.panel and ah.panel.select then
			ah.panel.select("bank")
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
		if not fromBlizzard then
			Blizzard.showTab(key)
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
	ah.panel = p
	ah.built = Theme.key
	ah.panels[ah.built] = p
	tabs:Select("scan")
	pages.scan:Show()
	p.tab = "scan"
end

-- The title row's bank-and-mail line, worked out again only when the bank, the mail or the prices change.
local awayStamp = {}
local function drawAway()
	local me, away = ns.me(), ah.panel and ah.panel.away
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
	if not ah.panel or not ah.panel:IsShown() then
		return
	end
	ns.safely("auction panel away", drawAway)
	if ah.built ~= Theme.key then
		local tab = ah.panel.tab
		ah.panel:Hide()
		build()
		ah.panel.ensure(tab)
		ah.panel.tabs:Select(tab)
		for k, f in pairs(ah.panel.pages) do
			f:SetShown(k == tab)
		end
		ah.panel.tab = tab
		show(true)
		return
	end
	if ah.panel.tab == "scan" then
		ah.panel.scan:Refresh()
	elseif ah.panel.tab == "post" then
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
		ah.panel.post.table:SetRows(ah.rows)
		ah.panel.post:Refresh()
	elseif ah.panel.tab == "shop" then
		ah.panel.shop:Refresh()
	elseif ah.panel.tab == "cancel" then
		ah.panel.cancel:Refresh()
	elseif ah.panel.tab == "bank" then
		ah.panel.bank:Refresh()
	end
end
ah.refresh = refresh

local function reread()
	ah.rows = sellable()
	local still
	for _, r in ipairs(ah.rows) do
		if ah.chosen and r.key == ah.chosen.key then
			still = r
		end
	end
	ah.chosen = still or ah.rows[1]
	refresh()
end

local ticker
-- Beside the auction house, its height.
local function anchor()
	if ah.panel and AuctionHouseFrame then
		ah.panel:ClearAllPoints()
		ah.panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
		ah.panel:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 6, 0)
	end
end
-- A frame after opening, or after a tab is first drawn: anchored anew, then hidden and shown, which is
-- what closing and opening the auction house did that put every widget and text in place (manual test
-- run 001, /gf uidebug: a button's own text at nil,nil, unseen, on the first opening).
local function settle()
	anchor()
	if ah.panel and ah.panel:IsShown() then
		ah.panel:Hide()
		ah.panel:Show()
	end
end
ns.auctionAnchor = settle
-- `redrawn`: the same visit in a new look, on the tab it had; else a new visit, on Blizzard's tab.
show = function(redrawn)
	if not AuctionHouseFrame then
		return
	end
	if not ah.panel then
		build()
	end
	-- Blizzard's tab chosen there switches the panel to its own.
	Blizzard.followTabs(function(key)
		if ah.panel and ah.panel:IsShown() and ah.panel.tab ~= key then
			ns.safely("auction tab", ah.panel.select, key, true)
		end
	end)
	anchor()
	ah.panel:Show()
	-- Again a frame later: built in the frame the auction house opens, some of its widgets were never
	-- placed (manual test run 001, /gf uidebug: Sell's Rule ›, quantity and Post with no rect, Remove's
	-- text unseen) until the panel was anchored anew, as closing and opening did.
	C_Timer.After(0, settle)
	-- A new visit opens on Scan while a full scan may start, to prod the player into one (owner's answer,
	-- 2026-10-24); else on Blizzard's tab.
	if redrawn ~= true then
		local st = ns.scanState and ns.scanState()
		local key = st and st.wait == 0 and st.phase == "idle" and "scan" or Blizzard.tabForMode(Blizzard.mode())
		if key and key ~= ah.panel.tab then
			ah.panel.select(key, true)
		end
	end
	reread()
	if ah.chosen then
		search(ah.chosen)
	end
	-- The scan's progress and cooldown, once a second while the panel shows.
	if not ticker then
		ticker = C_Timer.NewTicker(1, function()
			if ah.panel and ah.panel:IsShown() and ah.panel.tab == "scan" then
				ns.safely("auction panel", refresh)
			end
		end)
	end
end

-- A buy or cancel the auction house refused (gone, not enough money): Blizzard says why on screen;
-- the panel takes the next press. Other game errors (mana, cooldowns) are not the action's answer and
-- leave the wait to its timeout.
ns.on("AUCTION_HOUSE_SHOW_ERROR", "auction panel", function()
	local kind = ah.waits.shop and "shop" or ah.waits.cancel and "cancel" or ah.waits.post and "post"
	if kind and ah.panel then
		local note = ah.panel[kind].note
		ah.waits[kind], ah.purchase = nil, nil
		if kind == "shop" then
			ah.buying = nil
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
	if ah.panel then
		ah.panel:Hide()
	end
	if ticker and ticker.Cancel then
		ticker:Cancel()
	end
	ticker = nil
	-- Nothing in flight outlives the auction house: a warned post, a quoted or sent purchase, a check.
	ah.live, ah.waits, ah.armed, ah.confirm, ah.purchase, ah.checking = {}, {}, nil, nil, nil, nil
	ah.buying, ah.overArmed = nil, nil
end

-- A panel hidden in combat could not clear its binding then: set it right when the fight ends.
ns.on("PLAYER_REGEN_ENABLED", "auction panel", function()
	if ah.panel then
		bindSpace(ah.panel)
	end
end)

-- The named button the Space binding clicks (SetOverrideBindingClick takes a global name): a key press
-- is a hardware event, as a click is.
local key = CreateFrame("Button", "GoldForeverPostKey", UIParent)
key:Hide()
key:SetScript("OnClick", function()
	if ah.panel and ah.panel:IsShown() and ah.panel.tab == "post" then
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
	if ah.panel and ah.panel:IsShown() then
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
	if not ah.panel or not ah.panel:IsShown() then
		return
	end
	reread()
	local bag, slot = bagSlot(loc)
	local key = link and ns.Encode.itemKey(link)
	local id = itemID or (link and ns.Encode.itemId(key))
	local found
	for _, r in ipairs(ah.rows) do
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
	ah.panel.select("post", true)
	ah.chosen, ah.armed, ah.confirm = found, nil, nil
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

-- "/gf ah" shows or hides the panel at the auction house, and remembers.
ns.commands.ah = function()
	local s = settings()
	if ah.panel and ah.panel:IsShown() then
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
		return ah.panel
	end,
	tab = function(key)
		if ah.panel then
			ah.panel.select(key)
		end
	end,
	bound = function()
		return ah.panel and ah.panel.spaceBound
	end,
	post = function()
		if ah.panel then
			post()
		end
	end,
	state = function()
		return ah.rows, ah.chosen, busy()
	end,
	duration = function(v)
		if ah.panel and ah.panel.post.duration then
			settings().durations[ah.chosen.key] = v
		end
	end,
	quantity = function(v)
		settings().quantities[ah.chosen.key] = v
	end,
	shopChoose = function(e)
		ah.shopChosen, ah.purchase = e, nil
		searchEntry(e, true)
		refresh()
	end,
	shopBuy = function()
		buyNext()
	end,
	shopNote = function()
		return ah.panel and ah.panel.shop.note.text
	end,
	cancelCheck = function()
		startCheck()
	end,
	cancelNext = function()
		cancelNext()
	end,
	owned = function()
		return ah.owned, ah.checking
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
		return ah.chosen and ah.chosen.suggestion
	end,
}
