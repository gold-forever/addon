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
	local s = ns.settings("auction", { rule = {}, duration = 2 })
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
local rows, chosen = {}, nil -- the Post tab's rows and the chosen one
local live = {} -- item key -> { cheapest, at }: the last live search's cheapest other listing
local waiting -- a post sent, waiting for its answer: { key, at }
local armed -- a post that needs a second press: the row's key
local confirm -- the client warned about a commodity or item price: the next press confirms { key, args }

local money = function(c)
	return UI.layout.money(c, "gold")
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
local function activeProfile()
	local s = settings()
	return s.profile and s.profiles and s.profiles[s.profile] or nil
end

-- What this character holds of an item, bags and bank (decision 12: keep counts per character).
local function heldHere(id, bags)
	local me = ns.me()
	local bank = me and me.bank and ns.Encode.parseItems(me.bank.items)[id] or 0
	return (bags or 0) + bank
end

-- A sale plan's step as the Post tab's suggestion: posts in whole silver; "ask" posts the plan's price
-- after a second press; hold and skip post nothing.
local PLAN_REASONS = {
	undercut = "Undercut (plan)", fixed = "Fixed price (plan)", percentile = "Percentile (plan)", ["no-competition"] = "No one else (plan)",
	["market-moved"] = "The market moved (plan)", ["under-floor"] = "Hold: under the plan's floor", keeping = "Keeping", ["no-price"] = "No price yet",
}
Post.REASONS.plan = "Plan"

local function planned(r, rule, market)
	local book = live[r.commodity and tostring(r.id) or ("item:" .. r.id)]
	local step = ns.SalePlan.sell(rule, heldHere(r.id, r.count), book and book.levels or {}, market)
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

local function price(r)
	local market, from = ns.Prices.value(r.id)
	r.market, r.marketFrom = market, from
	local l = live[r.key]
	if l then
		r.cheapest, r.cheapestFrom = l.cheapest, "live"
	else
		r.cheapest, r.cheapestFrom = ns.price.cheapest(r.id), "scan"
	end
	r.vendor = ns.price.vendor(r.id)
	local rule = ns.SalePlan.ruleFor(activeProfile(), r.id)
	if rule then
		r.suggestion = planned(r, rule, market)
	else
		-- The rule: an override for the item, or its category, over the default.
		local _, _, class = ns.price.itemInfo(r.id)
		local postRule, from = Post.resolve(settings().rule, settings().overrides, r.id, class)
		if market then
			r.suggestion = Post.suggest(postRule, market, r.cheapest)
		elseif r.cheapest then
			-- No market value: the cheapest other listing stands in for it.
			r.suggestion = Post.suggest(postRule, r.cheapest, r.cheapest)
		else
			r.suggestion = nil
		end
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
local function search(r, open)
	if not (r and C_AuctionHouse.SendSearchQuery and C_AuctionHouse.GetItemKeyFromItem) then
		return
	end
	local key = C_AuctionHouse.GetItemKeyFromItem(r.locations[1])
	if not key then
		return
	end
	r.itemKey = key
	if open and AuctionHouseFrame and AuctionHouseFrame.SelectBrowseResult and AuctionHouseFrame:IsShown() then
		if ns.safely("auction browse", AuctionHouseFrame.SelectBrowseResult, AuctionHouseFrame, { itemKey = key }) then
			return
		end
	end
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

local LISTED = 4 -- the cheapest listings the panel shows
local LEVELS = 100 -- the cheapest levels of a book the Shop reads

local refresh, show

-- Commodities: the cheapest unit left after the player's own.
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction panel", function(itemID)
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	local cheapest, list, levels = nil, {}, {}
	-- The book as the Shop reads it ({ unitPrice, quantity, own }), the cheapest LEVELS of it.
	for i = 1, math.min(n, LEVELS) do
		local res = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if res then
			if not cheapest and (res.quantity or 0) - (res.numOwnerItems or 0) > 0 then
				cheapest = res.unitPrice
			end
			if #list < LISTED then
				list[#list + 1] = { unit = res.unitPrice, qty = res.quantity or 0, own = (res.numOwnerItems or 0) > 0 }
			end
			levels[#levels + 1] = { unitPrice = res.unitPrice, quantity = res.quantity or 0, own = res.numOwnerItems or 0 }
		end
	end
	live[tostring(itemID)] = { cheapest = cheapest, list = list, total = n, levels = levels, commodity = true, at = GetTime() }
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
	local cheapest, all = nil, {}
	for i = 1, n do
		local res = C_AuctionHouse.GetItemSearchResultInfo(itemKey, i)
		if res and res.buyoutAmount and res.buyoutAmount > 0 then
			local unit = math.floor(res.buyoutAmount / math.max(1, res.quantity or 1) + 0.5)
			all[#all + 1] = { unit = unit, qty = res.quantity or 1, own = res.containsOwnerItem and true or false,
				auctionID = res.auctionID, buyout = res.buyoutAmount }
			if not res.containsOwnerItem then
				cheapest = cheapest and math.min(cheapest, unit) or unit
			end
		end
	end
	table.sort(all, function(a, b)
		return a.unit < b.unit
	end)
	local list = {}
	for i = 1, math.min(LISTED, #all) do
		list[i] = all[i]
	end
	for _, r in ipairs(rows) do
		if r.itemKey and r.itemKey.itemID == itemKey.itemID and r.itemKey.itemLevel == itemKey.itemLevel then
			live[r.key] = { cheapest = cheapest, list = list, total = n, at = GetTime() }
		end
	end
	-- For the Shop: every auction of the item, cheapest first, as levels and with what PlaceBid needs.
	local levels = {}
	for i, a in ipairs(all) do
		levels[i] = { unitPrice = a.unit, quantity = a.qty, own = a.own and a.qty or 0, auctionID = a.auctionID, buyout = a.buyout }
	end
	live["item:" .. itemKey.itemID] = { cheapest = cheapest, levels = levels, commodity = false, at = GetTime() }
	if refresh then
		refresh()
	end
end)

-- Posting -----------------------------------------------------------------------------------------------------

local lastArgs -- what the last post sent, for confirming it after the client's warning

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
	if not r or waiting or not r.suggestion or not r.suggestion.unit then
		return
	end
	local unit = r.suggestion.unit
	-- The client warned about this post: the press confirms it, as its own window's button does.
	if confirm and confirm.key == r.key then
		local args = confirm.args
		confirm = nil
		if r.commodity and C_AuctionHouse.ConfirmPostCommodity then
			C_AuctionHouse.ConfirmPostCommodity(unpack(args))
		elseif C_AuctionHouse.ConfirmPostItem then
			C_AuctionHouse.ConfirmPostItem(unpack(args))
		end
		waiting = { key = r.key, at = GetTime() }
		return
	end
	local warning = Post.check(unit, r.market, r.vendor, ns.price.cut)
		or (r.suggestion.ask and "at the plan's fixed price though the market moved")
	if warning and armed ~= r.key then
		armed = r.key
		panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "Press again to post " .. warning .. ".|r")
		return
	end
	armed = nil
	local duration = durationOf(r)
	local loc = r.locations[1]
	local q = quantity(r)
	if r.commodity then
		C_AuctionHouse.PostCommodity(loc, duration, q, unit)
		lastArgs = { loc, duration, q, unit }
	else
		C_AuctionHouse.PostItem(loc, duration, q, nil, unit * q)
		lastArgs = { loc, duration, q, nil, unit * q }
	end
	waiting = { key = r.key, at = GetTime() }
	panel.post.note:SetText("Posting…")
	C_Timer.After(CONFIRM_TIMEOUT, function()
		if waiting and waiting.key == r.key then
			waiting = nil
			panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the server; check the auction house before posting again.|r")
		end
	end)
end

local function posted()
	if not waiting then
		return
	end
	local key = waiting.key
	waiting = nil
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
		search(next)
	end
end
ns.on("AUCTION_HOUSE_AUCTION_CREATED", "auction panel", posted)
-- The client warns before some commodity posts (far under the going price): the next press confirms.
ns.on("AUCTION_HOUSE_POST_WARNING", "auction panel", function()
	if waiting and lastArgs then
		confirm = { key = waiting.key, args = lastArgs }
	end
	waiting = nil
	if panel and panel.post.note then
		panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "The auction house warns this price is far from the going one. Press again to post anyway.|r")
	end
end)
ns.on("UI_ERROR_MESSAGE", "auction panel", function(_, message)
	if waiting and panel then
		local note = string.find(waiting.key, "^shop:") and panel.shop.note or string.find(waiting.key, "^cancel:") and panel.cancel.note or panel.post.note
		waiting = nil
		if not note then
			return
		end
		note:SetText(Theme.escape(Theme.color.danger) .. tostring(message or "The post failed.") .. "|r")
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
		cards[4]:Set(last and ns.Views.ago(last.t, ns.now()) or "never", last and last.kind == "throttled" and "the server said wait" or "")
	end
end

local function buildPost(page)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, text = function(r) return r.name .. Theme.escape(Theme.color.textFaint) .. " ×" .. r.count .. "|r" end,
			color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "market", title = "Market", width = 72, align = "RIGHT", text = function(r) return r.market and money(r.market) or "—" end, sort = function(r) return r.market or 0 end },
		{ key = "post", title = "Post at", width = 86, align = "RIGHT", text = function(r) return r.suggestion and r.suggestion.unit and money(r.suggestion.unit) or "—" end,
			sort = function(r) return r.suggestion and r.suggestion.unit or 0 end },
	}, {
		pageSize = 5,
		rowHeight = 24,
		empty = "Nothing in your bags the auction house takes.",
		isSelected = function(r) return chosen and r.key == chosen.key end,
		onRowClick = function(r)
			chosen, armed = r, nil
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
	name:SetPoint("RIGHT", detail, "RIGHT", -14, 0)
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
		reason:SetText(Theme.escape(tone) .. (sug and (sug.label or Post.REASONS[sug.reason]) or "No price yet: scan first") .. "|r"
			.. (sug and sug.unit and ("  " .. money(sug.unit) .. faint .. " each|r") or ""))
		local cheapest = r.cheapest and (money(r.cheapest) .. faint .. (r.cheapestFrom == "live" and " (live)" or " (last scan, yours included)") .. "|r") or (faint .. "none|r")
		facts:SetText(string.format("Cheapest other %s · market %s%s · floor %s · normal %s", cheapest,
			r.market and money(r.market) or "—", r.marketFrom and (faint .. " (" .. r.marketFrom .. ")|r") or "",
			sug and money(sug.floor) or "—", sug and money(sug.normal) or "—"))
		local l = live[r.key]
		for i, line in ipairs(listed) do
			local x = l and l.list and l.list[i]
			line.unit:SetText(x and money(x.unit) or (i == 1 and (faint .. (l and "none listed" or "searching…") .. "|r") or ""))
			line.qty:SetText(x and ("×" .. x.qty .. (x.own and (Theme.escape(Theme.color.accent) .. "  yours|r") or "")) or "")
		end
		listHead:SetText(l and l.total and l.total > LISTED and string.format("LISTINGS · CHEAPEST %d OF %d", LISTED, l.total) or "LISTINGS")
		local can = sug and sug.unit and not waiting
		if can then
			button.label:SetText((Theme.skin.titleCaps and "POST " or "Post ") .. quantity(r) .. " × " .. money(sug.unit))
			button:Enable()
			button:SetAlpha(1)
		else
			button.label:SetText(sug and sug.reason == "hold" and "Hold: under your floor" or "Post")
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
	local l = live[tostring(e.itemId)] or live["item:" .. e.itemId]
	if not l or not l.levels then
		return nil, l
	end
	if e.upTo then
		-- A profile's buy rule: up to its target, counting what this character holds (decision 12).
		local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(e.itemId)) or 0
		local step = ns.SalePlan.buy({ itemID = e.itemId, upTo = e.upTo, maxUnit = e.maxUnit }, heldHere(e.itemId, inBags), l.levels)
		if step.quantity == 0 then
			return nil, l
		end
		return { itemId = e.itemId, quantity = step.quantity, total = step.total, topUnit = step.topUnit, limit = e.maxUnit }, l
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
	ns.say(string.format("%d %s on your lists %s at or under your price: %s%s. Open the Shop.", #under, #under == 1 and "item" or "items",
		#under == 1 and "is" or "are", table.concat(names, ", "), #under > 3 and ", …" or ""))
end

local function searchEntry(e)
	if not (e and C_AuctionHouse.MakeItemKey and C_AuctionHouse.SendSearchQuery) then
		return
	end
	local key = C_AuctionHouse.MakeItemKey(e.itemId)
	local sorts = { { sortOrder = Enum.AuctionHouseSortOrder and Enum.AuctionHouseSortOrder.Price or 0, reverseSort = false } }
	C_AuctionHouse.SendSearchQuery(key, sorts, true)
end

-- One press of Buy next.
local function buyNext()
	local e = shopChosen
	if not e or waiting then
		return
	end
	local deal, book = shopDeal(e)
	local note = panel.shop.note
	if purchase and purchase.itemId == e.itemId and purchase.quoted then
		-- The second press: confirm the quote the client gave (as its own Buy button does).
		local p = purchase
		purchase = nil
		C_AuctionHouse.ConfirmCommoditiesPurchase(p.itemId, p.quantity)
		waiting = { key = "shop:" .. p.itemId, at = GetTime() }
		note:SetText("Buying…")
		return
	end
	if not deal then
		note:SetText(book and "Nothing at or under your price now." or "Searching…")
		searchEntry(e)
		return
	end
	if book.commodity then
		purchase = { itemId = e.itemId, quantity = deal.quantity, expected = deal.total }
		C_AuctionHouse.StartCommoditiesPurchase(e.itemId, deal.quantity)
		note:SetText("Asking the auction house for a price…")
	else
		-- The cheapest auction by someone else at or under the limit: one a press.
		for _, a in ipairs(book.levels) do
			if a.own == 0 and a.unitPrice <= deal.limit and a.auctionID then
				C_AuctionHouse.PlaceBid(a.auctionID, a.buyout)
				waiting = { key = "shop:" .. e.itemId, at = GetTime() }
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
local function bought(ok, why)
	if not panel or not panel.shop.note then
		return -- a purchase from Blizzard's own window, the Shop not drawn
	end
	waiting, purchase = nil, nil
	panel.shop.note:SetText(ok and (Theme.escape(Theme.color.success) .. "Bought.|r") or (Theme.escape(Theme.color.danger) .. (why or "The purchase failed.") .. "|r"))
	if shopChosen then
		live[tostring(shopChosen.itemId)], live["item:" .. shopChosen.itemId] = nil, nil
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

local function buildShop(page)
	local s = settings()
	local function names()
		local out = {}
		for i, l in ipairs(select(3, lists())) do
			out[i] = { value = i, label = l.name }
		end
		return out
	end
	local listPick
	local function rebuildPick()
		if listPick then
			listPick:Hide()
		end
		listPick = UI.Dropdown(page, names(), s.list or 1, function(v)
			s.list = v
			shopChosen = nil
			refresh()
		end)
		listPick:SetPoint("TOPLEFT")
		listPick:SetWidth(170)
	end
	rebuildPick()
	page.rebuildPick = rebuildPick
	local newList = UI.Button(page, "New", function()
		local all = lists()
		all[#all + 1] = stamp({ name = "List " .. (#all + 1), entries = {} })
		s.list = #all
		rebuildPick()
		refresh()
	end, { kind = "ghost", width = 54, height = 28 })
	newList:SetPoint("LEFT", page, "TOPLEFT", 178, -14)

	-- Import and export: one field, the GFL1 string in or out.
	local field = UI.SearchBox(page, "Paste a GFL1: string (make one at gold-forever.app/me/lists)", nil)
	field:SetPoint("TOPLEFT", 0, -36)
	field:SetPoint("RIGHT", page, "RIGHT", -150, 0)
	local import = UI.Button(page, "Import", function()
		local got, err = ns.Shopping.decode(field:GetText())
		if not got then
			page.note:SetText(Theme.escape(Theme.color.danger) .. err .. "|r")
			return
		end
		local all = lists()
		for _, l in ipairs(got) do
			all[#all + 1] = stamp(l)
		end
		s.list = #all
		field:SetText("")
		rebuildPick()
		page.note:SetText(string.format("Imported %d %s.", #got, #got == 1 and "list" or "lists"))
		refresh()
	end, { kind = "ghost", width = 70, height = 28 })
	import:SetPoint("LEFT", field, "RIGHT", 6, 0)
	local export = UI.Button(page, "Export", function()
		local _, list = lists()
		field:SetText(ns.Shopping.encode({ list }))
		field:SetFocus()
		field:HighlightText()
		page.note:SetText("Copy it with Ctrl+C; anyone with Gold Forever can import it.")
	end, { kind = "ghost", width = 70, height = 28 })
	export:SetPoint("LEFT", import, "RIGHT", 4, 0)

	-- Adding: shift-click an item into the field (or type its ID), then a price in gold, or none for
	-- "under market".
	local add = UI.SearchBox(page, "Shift-click an item, then a gold price (or none)", nil)
	add:SetPoint("TOPLEFT", 0, -72)
	add:SetPoint("RIGHT", page, "RIGHT", -82, 0)
	page.add = add
	local addButton = UI.Button(page, "Add", function()
		local id, maxUnit = ns.Shopping.parseAdd(add:GetText())
		if not id then
			page.note:SetText(Theme.escape(Theme.color.warning) .. "Shift-click an item into the field first.|r")
			return
		end
		local _, list = lists()
		if list.profile then
			page.note:SetText("The profile's buy list follows the profile: change it on the site and import it again.")
			return
		end
		list.entries[#list.entries + 1] = { itemId = id, maxUnit = maxUnit }
		stamp(list)
		add:SetText("")
		add:ClearFocus()
		refresh()
	end, { width = 76, height = 28 })
	addButton:SetPoint("LEFT", add, "RIGHT", 6, 0)

	local tbl = UI.Table(page, {
		{ key = "name", title = "Item", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "max", title = "Up to", width = 80, align = "RIGHT", text = function(r)
			return (r.upTo and (r.upTo .. " at ") or "") .. (r.maxUnit and money(r.maxUnit) or "market")
		end },
		{ key = "deal", title = "Deal", width = 110, align = "RIGHT", text = function(r)
			return r.deal and (r.deal.quantity .. " for " .. money(r.deal.total)) or (r.searched and "—" or "")
		end },
	}, {
		pageSize = 6,
		rowHeight = 24,
		empty = "No items yet: shift-click one into the field above.",
		isSelected = function(r) return shopChosen and r.itemId == shopChosen.itemId end,
		onRowClick = function(r)
			shopChosen, purchase = r.entry, nil
			searchEntry(r.entry)
			refresh()
		end,
	})
	tbl:SetPoint("TOPLEFT", add, "BOTTOMLEFT", 0, -10)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	page.table = tbl
	local buy = UI.Button(page, "Buy next", function()
		ns.safely("auction shop", buyNext)
	end, { kind = "primary", width = 200, height = 30 })
	buy:SetPoint("TOPRIGHT", tbl, "BOTTOMRIGHT", 0, -10)
	page.buy = buy
	local remove = UI.Button(page, "Remove", function()
		local _, list = lists()
		if list.profile then
			page.note:SetText("The profile's buy list follows the profile: change it on the site and import it again.")
			return
		end
		for i, e in ipairs(list.entries) do
			if shopChosen and e.itemId == shopChosen.itemId then
				table.remove(list.entries, i)
				stamp(list)
				shopChosen = nil
				break
			end
		end
		refresh()
	end, { kind = "ghost", width = 90, height = 30 })
	remove:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	page.note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	page.note:SetPoint("TOPLEFT", remove, "BOTTOMLEFT", 0, -10)
	page.note:SetPoint("RIGHT", page, "RIGHT")

	function page:Refresh()
		local _, list = lists()
		local shown = {}
		for i, e in ipairs(list.entries) do
			local quality, _, _, _, name = ns.price.itemInfo(e.itemId)
			local deal, book = shopDeal(e)
			shown[i] = { entry = e, itemId = e.itemId, maxUnit = e.maxUnit, upTo = e.upTo, name = name or ("item " .. e.itemId), quality = quality or 1, deal = deal, searched = book ~= nil }
		end
		tbl:SetRows(shown)
		local deal = shopChosen and shopDeal(shopChosen)
		local label = purchase and purchase.quoted and ("Confirm: " .. purchase.quantity .. " for " .. money(purchase.quoted))
			or (deal and ("Buy " .. deal.quantity .. " for " .. money(deal.total))) or "Buy next"
		buy.label:SetText(Theme.skin.titleCaps and string.upper(label) or label)
		local can = shopChosen and not waiting
		if can then
			buy:Enable()
			buy:SetAlpha(1)
		else
			buy:Disable()
			buy:SetAlpha(0.5)
		end
	end
end

-- Shift-clicking an item while the Shop's field has focus puts its link there, as in the chat box.
if hooksecurefunc and ChatEdit_InsertLink then
	hooksecurefunc("ChatEdit_InsertLink", function(link)
		if panel and panel.shop and panel.shop.add and panel.shop.add:HasFocus() and link then
			panel.shop.add:Insert(link .. " ")
		end
	end)
end

-- Cancel undercut ----------------------------------------------------------------------------------------------

-- The player's own auctions (design 009, Cancel undercut; owner: build it now, 5% by default): each
-- searched in turn against other players' listings (a sneaky single cheap unit passed over); those
-- undercut by more than the tolerance are listed, and Cancel next cancels the most undercut one a press
-- (CancelAuction is a hardware event, and costs the deposit). The items come back by mail.
local TOLERANCES = { { value = 1, label = "1 percent" }, { value = 5, label = "5 percent" }, { value = 10, label = "10 percent" } }
local owned = {} -- { auctionID, itemID, key, name, quality, quantity, unit, commodity, cheapest, under }
local checking -- the index of the auction being searched, while a check runs

local function tolerance()
	return settings().tolerance or 5
end

-- The cheapest other listing for an owned auction, from the last search of its item.
local function cheapestFor(a)
	local book = live[a.commodity and tostring(a.itemID) or ("item:" .. a.itemID)]
	return book and book.levels and Post.honestCheapest(book.levels) or nil, book ~= nil
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
	refresh()
end

local function startCheck()
	if C_AuctionHouse.QueryOwnedAuctions then
		C_AuctionHouse.QueryOwnedAuctions({ { sortOrder = 0, reverseSort = false } })
	end
	checking = 0
	panel.cancel.note:SetText("Reading your auctions…")
end

ns.on("OWNED_AUCTIONS_UPDATED", "auction cancel", function()
	if checking == 0 then
		readOwned()
		checkNext()
	end
end)
-- A search answered moves the check to the next auction (both kinds of results).
local function searched()
	if checking and checking > 0 then
		C_Timer.After(0.3, function()
			ns.safely("auction cancel", checkNext)
		end)
	end
end
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction cancel", searched)
ns.on("ITEM_SEARCH_RESULTS_UPDATED", "auction cancel", searched)

-- The owned auctions undercut past the tolerance, most undercut first.
local function undercut()
	local out = {}
	for _, a in ipairs(owned) do
		local other = cheapestFor(a)
		a.cheapest, a.under = other, Post.undercutPct(a.unit, other)
		if a.under > tolerance() then
			out[#out + 1] = a
		end
	end
	table.sort(out, function(x, y)
		return x.under > y.under
	end)
	return out
end

local function cancelNext()
	if waiting then
		return
	end
	local a = undercut()[1]
	if not a then
		panel.cancel.note:SetText("Nothing undercut past " .. tolerance() .. "%.")
		return
	end
	C_AuctionHouse.CancelAuction(a.auctionID)
	waiting = { key = "cancel:" .. a.auctionID, at = GetTime() }
	panel.cancel.note:SetText("Cancelling " .. a.name .. "…")
end

ns.on("AUCTION_CANCELED", "auction cancel", function(auctionID)
	if waiting and waiting.key == "cancel:" .. tostring(auctionID) then
		waiting = nil
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
	tol:SetPoint("TOPLEFT", 120, 0)
	tol:SetWidth(120)
	local tolLabel = UI.Text(page, "Undercut past", { size = "sm", tone = "muted" })
	tolLabel:SetPoint("RIGHT", tol, "LEFT", -10, 0)
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
	}, { pageSize = 9, rowHeight = 24, empty = "Check your auctions to see which are undercut." })
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
		if checking then
			go.label:SetText(string.format("Checking %d of %d…", math.max(1, checking), #owned))
		elseif first then
			local cost = C_AuctionHouse.GetCancelCost and C_AuctionHouse.GetCancelCost(first.auctionID)
			go.label:SetText("Cancel " .. first.name .. (cost and cost > 0 and (" (" .. money(cost) .. ")") or ""))
		else
			go.label:SetText("Cancel next")
		end
		local can = first and not checking and not waiting
		if can then
			go:Enable()
			go:SetAlpha(1)
		else
			go:Disable()
			go:SetAlpha(0.5)
		end
		if not checking and #owned > 0 and page.note:GetText() == "Reading your auctions…" then
			page.note:SetText(string.format("%d of your %d auctions are undercut past %d%%.", #list, #owned, tolerance()))
		end
	end
end

local function buildRule(page)
	local s = settings()
	s.overrides = s.overrides or { items = {}, classes = {} }
	s.overrides.items = s.overrides.items or {}
	s.overrides.classes = s.overrides.classes or {}
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
	local function set(field, v)
		local t = target()
		if t then
			t[field] = v
		end
	end
	local function row(y, label, control)
		local l = UI.Text(page, label, { size = "sm" })
		l:SetPoint("TOPLEFT", 0, y)
		control:SetPoint("TOPLEFT", 160, y + 6)
		control:SetPoint("RIGHT", page, "RIGHT")
		return control
	end
	local undercuts = {}
	for _, u in ipairs(Post.UNDERCUTS) do
		undercuts[#undercuts + 1] = { value = u.value, label = u.label }
	end
	local v = shown()
	local controls = {
		undercut = row(-40, "Undercut by", UI.Dropdown(page, undercuts, v.undercut, function(x) set("undercut", x) end)),
		floor = row(-90, "Never under", UI.Slider(page, 50, 100, 5, v.floor, function(x) set("floor", x) end, function(x) return x .. "%" end)),
		normal = row(-140, "Normal price", UI.Slider(page, 100, 200, 5, v.normal, function(x) set("normal", x) end, function(x) return x .. "%" end)),
		belowFloor = row(-190, "Under the floor", UI.Dropdown(page, { { value = "hold", label = "Hold" }, { value = "floor", label = "Post at the floor" } }, v.belowFloor, function(x) set("belowFloor", x) end)),
	}
	local scopePick, removeButton
	local function pickOptions()
		local out = { { value = "default", label = "Default: every item" } }
		for id in pairs(s.overrides.items) do
			local _, _, _, _, name = ns.price.itemInfo(id)
			out[#out + 1] = { value = "item:" .. id, label = "Item: " .. (name or id) }
		end
		for class in pairs(s.overrides.classes) do
			out[#out + 1] = { value = "class:" .. class, label = "Category: " .. className(class) }
		end
		out[#out + 1] = { value = "add-item", label = "+ The item chosen in Post" }
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
	end
	rebuildPick = function()
		if scopePick then
			scopePick:Hide()
		end
		scopePick = UI.Dropdown(page, pickOptions(), scope, choose)
		scopePick:SetPoint("TOPLEFT", 160, 6)
		scopePick:SetPoint("RIGHT", page, "RIGHT", -96, 0)
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
	removeButton:SetPoint("TOPRIGHT", 0, 6)
	removeButton:Hide()
	rebuildPick()
	page.chooseScope = choose
	page.setField = set
	local note = UI.Text(page, "Floor and normal price are shares of the market value: the pool's from the companion, else your own last scan. Prices are whole silver. An item in the sale profile follows the profile instead.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", 0, -230)
	note:SetPoint("RIGHT", page, "RIGHT")

	-- Sale profiles (GFP1 strings from the site or other players): one active at a time.
	s.profiles = s.profiles or {}
	local head = UI.Text(page, "SALE PROFILE", { size = "xs", medium = true, tone = "faint" })
	head:SetPoint("TOPLEFT", 0, -270)
	local pick
	local summary = UI.Text(page, "", { size = "xs", tone = "muted", wrap = true })
	local function options()
		local out = { { value = 0, label = "None: the rule above" } }
		for i, p in ipairs(s.profiles) do
			out[#out + 1] = { value = i, label = p.name }
		end
		return out
	end
	local function describe()
		local p = activeProfile()
		summary:SetText(p and string.format("%s by %s: %d items to sell, %d to buy.", p.name, p.author ~= "" and p.author or "?", #p.sell, #p.buy)
			or "No profile: every item follows the rule above.")
	end
	local function rebuild()
		if pick then
			pick:Hide()
		end
		pick = UI.Dropdown(page, options(), s.profile or 0, function(v)
			s.profile = v ~= 0 and v or nil
			describe()
		end)
		pick:SetPoint("TOPLEFT", 0, -288)
		pick:SetWidth(220)
		summary:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -8)
		summary:SetPoint("RIGHT", page, "RIGHT")
		describe()
	end
	rebuild()
	local field = UI.SearchBox(page, "Paste a GFP1: profile (make one at gold-forever.app/me/lists)", nil)
	field:SetPoint("TOPLEFT", 0, -340)
	field:SetPoint("RIGHT", page, "RIGHT", -150, 0)
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
	end, { kind = "ghost", width = 70, height = 28 })
	import:SetPoint("LEFT", field, "RIGHT", 6, 0)
	local export = UI.Button(page, "Export", function()
		local p = activeProfile()
		if p then
			field:SetText(ns.SalePlan.encode(p))
			field:SetFocus()
			field:HighlightText()
			message:SetText("Copy it with Ctrl+C.")
		end
	end, { kind = "ghost", width = 70, height = 28 })
	export:SetPoint("LEFT", import, "RIGHT", 4, 0)
	page.importProfile = doImport
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
	local pages = {}
	local tabs = UI.TabBar(p, { { key = "scan", label = "Scan" }, { key = "post", label = "Post" }, { key = "shop", label = "Shop" }, { key = "cancel", label = "Cancel" }, { key = "rule", label = "Rule" } }, function(key)
		p.ensure(key)
		for k, f in pairs(pages) do
			f:SetShown(k == key)
		end
		p.tab = key
		bindSpace(p)
		refresh()
	end, { variant = "underline" })
	tabs:SetPoint("TOPLEFT", 16, -42)
	tabs:SetPoint("TOPRIGHT", -16, -42)
	for _, key in ipairs({ "scan", "post", "shop", "cancel", "rule" }) do
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -16)
		f:SetPoint("BOTTOMRIGHT", -20, 16)
		f:Hide()
		pages[key] = f
	end
	-- Each tab is drawn the first time it is chosen: opening the auction house draws Scan only.
	local builders = { scan = buildScan, post = buildPost, shop = buildShop, cancel = buildCancel, rule = buildRule }
	function p.ensure(key)
		local f = pages[key]
		if f and not f.built then
			f.built = true
			builders[key](f)
		end
	end
	p.ensure("scan")
	p.scan, p.post, p.shop, p.cancel, p.tabs, p.pages = pages.scan, pages.post, pages.shop, pages.cancel, tabs, pages
	p:SetScript("OnShow", bindSpace)
	p:SetScript("OnHide", bindSpace)
	panel = p
	built = Theme.key
	tabs:Select("scan")
	pages.scan:Show()
	p.tab = "scan"
end

refresh = function()
	if not panel or not panel:IsShown() then
		return
	end
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
		show()
		return
	end
	if panel.tab == "scan" then
		panel.scan:Refresh()
	elseif panel.tab == "post" then
		for _, r in ipairs(rows) do
			price(r)
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
show = function()
	if not AuctionHouseFrame then
		return
	end
	if not panel then
		build()
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 6, 0)
	panel:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMRIGHT", 6, 0)
	panel:Show()
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

local function hide()
	if panel then
		panel:Hide()
	end
	if ticker and ticker.Cancel then
		ticker:Cancel()
	end
	ticker = nil
	live, waiting, armed = {}, nil, nil
end

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
	if settings().hidden then
		return
	end
	show()
end)
ns.on("AUCTION_HOUSE_CLOSED", "auction panel", hide)
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

local function chooseFromBag(link, loc)
	if not panel or not panel:IsShown() then
		return
	end
	reread()
	local bag, slot = bagSlot(loc)
	local key = link and ns.Encode.itemKey(link)
	local id = link and ns.Encode.itemId(key)
	local found
	for _, r in ipairs(rows) do
		for _, l in ipairs(r.locations) do
			local b, sl = bagSlot(l)
			if bag and b == bag and sl == slot then
				found = r
			end
		end
		if not found and not bag and (r.key == key or (r.commodity and r.id == id)) then
			found = r
		end
	end
	if not found then
		return
	end
	panel.ensure("post")
	panel.tabs:Select("post")
	for k, f in pairs(panel.pages) do
		f:SetShown(k == "post")
	end
	panel.tab = "post"
	bindSpace(panel)
	chosen, armed = found, nil
	search(found, true)
	refresh()
end

if hooksecurefunc and HandleModifiedItemClick then
	hooksecurefunc("HandleModifiedItemClick", function(link, loc)
		if IsAltKeyDown and IsAltKeyDown() then
			ns.safely("auction alt-click", chooseFromBag, link, loc)
		end
	end)
end
ns.AuctionPanelAltClick = chooseFromBag

-- While the panel shows, a bag item's tooltip says what Post would ask for it (owner's answer,
-- 2026-10-24): the same price and reason as the Post tab, rule, override or profile.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("auction tooltip", function()
			if tooltip ~= GameTooltip or not data or not data.id or not panel or not panel:IsShown() then
				return
			end
			for _, r in ipairs(rows) do
				if r.id == data.id then
					price(r)
					local sug = r.suggestion
					if sug and sug.unit then
						tooltip:AddLine(string.format("%s Post at %s · %s", ns.PREFIX, money(sug.unit), sug.label or Post.REASONS[sug.reason] or ""), 1, 1, 1)
					elseif sug then
						tooltip:AddLine(ns.PREFIX .. " " .. (sug.label or Post.REASONS[sug.reason] or "Hold"), 0.6, 0.6, 0.6)
					end
					return
				end
			end
		end)
	end)
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
		show()
	end
end

-- For the smoke test: pick a tab, post the chosen row, and read the rows.
ns.AuctionPanel = {
	tab = function(key)
		if panel then
			panel.ensure(key)
			panel.tabs:Select(key)
			for k, f in pairs(panel.pages) do
				f:SetShown(k == key)
			end
			panel.tab = key
			bindSpace(panel)
			refresh()
		end
	end,
	bound = function()
		return panel and panel.spaceBound
	end,
	post = function()
		post()
	end,
	state = function()
		return rows, chosen, waiting
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
		searchEntry(e)
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
		panel.pages.rule.importProfile(text)
	end,
	ruleScope = function(value)
		panel.ensure("rule")
		panel.pages.rule.chooseScope(value)
	end,
	ruleSet = function(field, value)
		panel.pages.rule.setField(field, value)
	end,
	suggestion = function()
		return chosen and chosen.suggestion
	end,
}

-- Lists and profiles the companion carries from the site (Data.lua's `shared`), merged in at login:
-- by id, the newer edit wins and the loser is kept once as an older copy (Shopping.merge). A file
-- already merged is not merged again.
local function mergeShared()
	local shared = type(GoldForever_Prices) == "table" and type(GoldForever_Prices.shared) == "table" and GoldForever_Prices.shared or nil
	local s = settings()
	if not shared or shared.at == s.sharedAt then
		return
	end
	local lists, profiles = {}, {}
	for _, x in ipairs(type(shared.lists) == "table" and shared.lists or {}) do
		local got = type(x) == "table" and type(x.string) == "string" and ns.Shopping.decode(x.string)
		if got and got[1] and type(x.id) == "string" then
			got[1].id, got[1].edited = x.id, tonumber(x.edited) or 0
			lists[#lists + 1] = got[1]
		end
	end
	for _, x in ipairs(type(shared.profiles) == "table" and shared.profiles or {}) do
		local p = type(x) == "table" and type(x.string) == "string" and ns.SalePlan.decode(x.string)
		if p and type(x.id) == "string" then
			p.id, p.edited = x.id, tonumber(x.edited) or 0
			profiles[#profiles + 1] = p
		end
	end
	local a, b
	s.lists, a = ns.Shopping.merge(s.lists or {}, lists, newId)
	s.profiles, b = ns.Shopping.merge(s.profiles or {}, profiles, newId)
	s.sharedAt = shared.at
	if a + b > 0 then
		ns.say(string.format("lists and profiles from the site: %d %s.", a + b, a + b == 1 and "change" or "changes"))
	end
end
ns.on("PLAYER_LOGIN", "shared lists", function()
	mergeShared()
end)
ns.mergeShared = mergeShared
