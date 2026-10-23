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
	if market then
		r.suggestion = Post.suggest(settings().rule, market, r.cheapest)
	elseif r.cheapest then
		-- No market value: the cheapest other listing stands in for it.
		r.suggestion = Post.suggest(settings().rule, r.cheapest, r.cheapest)
	else
		r.suggestion = nil
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

local LISTED = 5 -- the cheapest listings the panel shows

local refresh, show

-- Commodities: the cheapest unit left after the player's own.
ns.on("COMMODITY_SEARCH_RESULTS_UPDATED", "auction panel", function(itemID)
	local n = C_AuctionHouse.GetNumCommoditySearchResults(itemID) or 0
	local cheapest, list = nil, {}
	for i = 1, n do
		local res = C_AuctionHouse.GetCommoditySearchResultInfo(itemID, i)
		if res then
			if not cheapest and (res.quantity or 0) - (res.numOwnerItems or 0) > 0 then
				cheapest = res.unitPrice
			end
			if #list < LISTED then
				list[#list + 1] = { unit = res.unitPrice, qty = res.quantity or 0, own = (res.numOwnerItems or 0) > 0 }
			end
		end
		if cheapest and #list >= LISTED then
			break
		end
	end
	live[tostring(itemID)] = { cheapest = cheapest, list = list, total = n, at = GetTime() }
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
			all[#all + 1] = { unit = unit, qty = res.quantity or 1, own = res.containsOwnerItem and true or false }
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

local function quantity(r)
	return r.commodity and r.count or 1
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
	if panel then
		panel.post.note:SetText(Theme.escape(Theme.color.warning) .. "The auction house warns this price is far from the going one. Press again to post anyway.|r")
	end
end)
ns.on("UI_ERROR_MESSAGE", "auction panel", function(_, message)
	if waiting and panel then
		waiting = nil
		panel.post.note:SetText(Theme.escape(Theme.color.danger) .. tostring(message or "The post failed.") .. "|r")
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
		pageSize = 6,
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
	detail:SetHeight(214)
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
		local sug = r.suggestion
		name:SetText(Theme.escape(Theme.quality[r.quality] or Theme.color.text) .. r.name .. "|r" .. faint .. "  ×" .. quantity(r) .. (r.commodity and "" or " (one at a time)") .. "|r")
		local tone = not sug and Theme.color.textFaint or sug.reason == "hold" and Theme.color.warning or Theme.color.accent
		reason:SetText(Theme.escape(tone) .. (sug and Post.REASONS[sug.reason] or "No price yet: scan first") .. "|r"
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

local function buildRule(page)
	local s = settings()
	local function row(y, label, control)
		local l = UI.Text(page, label, { size = "sm" })
		l:SetPoint("TOPLEFT", 0, y)
		control:SetPoint("TOPLEFT", 160, y + 6)
		control:SetPoint("RIGHT", page, "RIGHT")
	end
	local undercuts = {}
	for _, u in ipairs(Post.UNDERCUTS) do
		undercuts[#undercuts + 1] = { value = u.value, label = u.label }
	end
	row(0, "Undercut by", UI.Dropdown(page, undercuts, s.rule.undercut, function(v)
		s.rule.undercut = v
	end))
	row(-50, "Never under", UI.Slider(page, 50, 100, 5, s.rule.floor, function(v)
		s.rule.floor = v
	end, function(v) return v .. "%" end))
	row(-100, "Normal price", UI.Slider(page, 100, 200, 5, s.rule.normal, function(v)
		s.rule.normal = v
	end, function(v) return v .. "%" end))
	row(-150, "Under the floor", UI.Dropdown(page, { { value = "hold", label = "Hold" }, { value = "floor", label = "Post at the floor" } }, s.rule.belowFloor, function(v)
		s.rule.belowFloor = v
	end))
	local note = UI.Text(page, "Floor and normal price are shares of the market value: the pool's from the companion, else your own last scan. Prices are whole silver.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", 0, -200)
	note:SetPoint("RIGHT", page, "RIGHT")
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
	local tabs = UI.TabBar(p, { { key = "scan", label = "Scan" }, { key = "post", label = "Post" }, { key = "rule", label = "Rule" } }, function(key)
		for k, f in pairs(pages) do
			f:SetShown(k == key)
		end
		p.tab = key
		refresh()
	end, { variant = "underline" })
	tabs:SetPoint("TOPLEFT", 16, -42)
	tabs:SetPoint("TOPRIGHT", -16, -42)
	for _, key in ipairs({ "scan", "post", "rule" }) do
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -16)
		f:SetPoint("BOTTOMRIGHT", -20, 16)
		f:Hide()
		pages[key] = f
	end
	buildScan(pages.scan)
	buildPost(pages.post)
	buildRule(pages.rule)
	p.scan, p.post, p.tabs, p.pages = pages.scan, pages.post, tabs, pages
	-- Space posts while the panel shows: an override binding on a named button, never in combat.
	p:SetScript("OnShow", function(self)
		if not InCombatLockdown() and SetOverrideBindingClick then
			SetOverrideBindingClick(self, true, "SPACE", "GoldForeverPostKey")
		end
	end)
	p:SetScript("OnHide", function(self)
		if not InCombatLockdown() and ClearOverrideBindings then
			ClearOverrideBindings(self)
		end
	end)
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
			panel.tabs:Select(key)
			for k, f in pairs(panel.pages) do
				f:SetShown(k == key)
			end
			panel.tab = key
			refresh()
		end
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
}
