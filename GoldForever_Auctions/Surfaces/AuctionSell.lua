-- Gold Forever: the auction panel's Sell tab: the bag items the auction house takes, each priced by the
-- rule (Post.lua) or the sale plan against the cheapest listing by someone else (a live search when the
-- row is chosen, else the last scan), with the reason; one click, or Space while the panel shows, posts
-- the chosen row and moves on. Posting is a hardware event (the click or the key); the result is
-- confirmed by its event before the next press is taken. Own auctions are left out of "cheapest", so the
-- player never undercuts themself.

local _, ns = ...
local Theme, UI, Post = ns.Theme, ns.UI, ns.Post
local ah = ns.ah
local Blizzard, Books = ns.AuctionBlizzard, ns.AuctionBooks
local settings, activeProfile = ns.auctionSettings, ns.activeProfile
local heldHere = ns.Holdings.heldHere
local bookKey, search, LISTED = Books.bookKey, Books.search, Books.LISTED
local await, busy, money = ah.await, ah.busy, ns.Money.auction

local DURATIONS = { { value = 1, label = "12 hours" }, { value = 2, label = "24 hours" }, { value = 3, label = "48 hours" } }

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

-- A row priced: market value, the cheapest other listing (live or from the scan) and the suggestion.
-- `s`: the settings, read once for every row of a refresh.
local function price(r, s)
	s = s or settings()
	r.priced = true
	local value, valueFrom, trend, week = ns.Prices.value(r.id)
	local market, from = ns.Prices.sellBase(value, valueFrom, week)
	r.market, r.marketFrom, r.trend, r.anyway = market, from, trend, nil
	r.typical = from == "typical price" and market or nil
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
		ah.panel.post.note:SetText("Posting...")
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
	ah.panel.post.note:SetText("Posting...")
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

local function buildPost(page)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, text = function(r) return r.name .. Theme.escape(Theme.color.textFaint) .. " x" .. r.count .. "|r" end,
			color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		-- The typical price, what selling is priced against; the tooltip's "Market" is the day's value (addon#21).
		{ key = "typical", title = "Typical", width = 84, align = "RIGHT", text = function(r) return r.typical and money(r.typical) or "-" end, sort = function(r) return r.typical or 0 end },
		{ key = "post", title = "Post at", width = 92, align = "RIGHT", text = function(r) return r.suggestion and r.suggestion.unit and money(r.suggestion.unit) or "-" end,
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
			ah.refresh()
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
	local ruleButton = UI.Button(detail, "Rule >", function()
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
	page.facts = facts
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
		ah.refresh()
	end)
	page.duration = duration
	duration:SetPoint("BOTTOMLEFT", 14, 12)
	-- How many of a commodity to post, remembered for it; hidden for gear (one at a time).
	local qtyLabel = UI.Text(detail, "Post", { size = "sm", tone = "muted" })
	qtyLabel:SetPoint("BOTTOMLEFT", 14, 56)
	local qty = UI.Slider(detail, 1, 2, 1, 1, function(v)
		if ah.chosen then
			settings().quantities[ah.chosen.key] = v
			ah.refresh()
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
		ah.refresh()
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
			button:SetEnabled(false)
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
		name:SetText(Theme.escape(Theme.quality[r.quality] or Theme.color.text) .. r.name .. "|r" .. faint .. "  x" .. quantity(r) .. (r.commodity and "" or " (one at a time)") .. "|r")
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
		-- The price Sell measures against, named for what it is: the typical price, or the market value and its source.
		local base = r.typical and ("typical " .. money(r.typical))
			or ("market " .. (r.market and money(r.market) or "-") .. (r.marketFrom and (faint .. " (" .. r.marketFrom .. ")|r") or ""))
		facts:SetText(string.format("Cheapest other %s · %s%s · floor %s · normal %s", cheapest, base, trend,
			sug and money(sug.floor) or "-", sug and money(sug.normal) or "-"))
		local l = ah.live[r.key]
		for i, line in ipairs(listed) do
			local x = l and l.list and l.list[i]
			line.unit:SetText(x and money(x.unit) or (i == 1 and (faint .. (l and "none listed" or "searching...") .. "|r") or ""))
			line.qty:SetText(x and ("x" .. x.qty .. (x.own and (Theme.escape(Theme.color.accent) .. "  yours|r") or "")) or "")
		end
		listHead:SetText(l and l.total and l.total > LISTED and string.format("LISTINGS · CHEAPEST %d OF %d", LISTED, l.total) or "LISTINGS")
		local can = sug and (sug.unit or r.anyway) and not busy()
		if can then
			button:SetLabel(sug.unit and ("Post " .. quantity(r) .. " x " .. money(sug.unit)) or ("Post anyway: " .. quantity(r) .. " x " .. money(r.anyway)))
		else
			button:SetLabel(sug and sug.reason == "hold" and "Under your floor" or "Post")
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
	page.table:SetRows(ah.rows)
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

ns.AuctionSell = { key = "post", label = "Sell", build = buildPost, refresh = refresh, post = post, reread = reread }
