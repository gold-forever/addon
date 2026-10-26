-- Gold Forever: the auction house panel (design 009, Auction house module, Phase 1), docked to the right
-- of the auction house, never replacing or moving Blizzard's frame. The shell: the window per look, its
-- tabs (Scan, Buy, Sell, Auctions, Bank: one file each), shown and hidden with the auction house, the
-- Space binding for Sell, and /gf ah.

local _, ns = ...
local Theme, UI, Post = ns.Theme, ns.UI, ns.Post
local ah = ns.ah
local Blizzard = ns.AuctionBlizzard
local settings = ns.auctionSettings
local Sell, Buy, Cancel = ns.AuctionSell, ns.AuctionBuy, ns.AuctionCancel
local search, searchEntry = ns.AuctionBooks.search, ns.AuctionBooks.searchEntry
local busy, money = ah.busy, ns.Money.auction

-- The tabs in their order: { key, label, build(page), refresh(page) }. Named as Blizzard's tabs are
-- (manual test run 001); the keys stay as the save knows them.
local TABS = { ns.AuctionScanTab, Buy, Sell, Cancel, ns.AuctionBank }
local TAB = {}
for _, t in ipairs(TABS) do
	TAB[t.key] = t
end

local refresh, show

-- Space posts only while the Post tab shows: an override binding on a named button, set and cleared as
-- the tab and the panel change; in combat, when bindings cannot change, once the fight ends. Elsewhere it
-- jumps.
local bindSpace
local function rebind()
	if ah.panel then
		bindSpace(ah.panel)
	end
end
function bindSpace(p)
	if not SetOverrideBindingClick then
		return
	end
	if ns.inCombat() then
		ns.afterCombat("auction panel", rebind)
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
	local p = UI.Panel(UIParent, { window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	p:SetWidth(ah.WIDTH)
	p:SetFrameStrata("HIGH")
	p:Hide()
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
	local bar = {}
	for i, t in ipairs(TABS) do
		bar[i] = { key = t.key, label = t.label }
	end
	local tabs = UI.TabBar(p, bar, function(key)
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
	-- Each tab's page, also as p[key].
	for _, key in ipairs({ "scan", "post", "shop", "cancel", "bank" }) do
		local f = CreateFrame("Frame", nil, p)
		f:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -16)
		f:SetPoint("BOTTOMRIGHT", -20, 16)
		f:Hide()
		pages[key] = f
		p[key] = f
	end
	-- Each tab is drawn the first time it is chosen: opening the auction house draws Scan only.
	function p.ensure(key)
		local f = pages[key]
		if f and not f.built then
			f.built = true
			TAB[key].build(f)
			-- Its widgets placed for certain: the panel anchored anew a frame later (see show).
			C_Timer.After(0, function()
				ns.auctionAnchor()
			end)
		end
	end
	p.ensure("scan")
	p.tabs, p.pages = tabs, pages
	p:SetScript("OnShow", bindSpace)
	p:SetScript("OnHide", bindSpace)
	ah.panel = p
	ah.built = Theme.key
	tabs:Select("scan")
	pages.scan:Show()
	p.tab = "scan"
	return p
end

-- Drawn again in a new look: the same visit, on the tab it had.
local function dock(p, old)
	ah.panel, ah.built = p, Theme.key
	local tab = old.tab
	p.ensure(tab)
	p.tabs:Select(tab)
	for k, f in pairs(p.pages) do
		f:SetShown(k == tab)
	end
	p.tab = tab
	show(true)
end

-- One panel per look and accent; ah.panels holds them.
local panels = UI.perLook(build, dock)
panels.frames = ah.panels

-- The title row's bank-and-mail line, worked out again only when the bank, the mail or the prices change.
local awayStamp = {}
local function drawAway()
	local me, away = ns.me(), ah.panel and ah.panel.away
	if not me or not away then
		return
	end
	local file = GoldForever_Prices
	local bankT, mailT = me.bank and me.bank.t, me.mail and me.mail.t
	local fileAt = type(file) == "table" and file[ns.DataFormat.field.at] or nil
	if away.list and awayStamp.bank == bankT and awayStamp.mail == mailT and awayStamp.scan == ns.scanVersion and awayStamp.file == fileAt then
		return
	end
	awayStamp.bank, awayStamp.mail, awayStamp.scan, awayStamp.file = bankT, mailT, ns.scanVersion, fileAt
	away.list = ns.Views.elsewhere(me, ns.Encode.parseItems, function(id)
		return (ns.Prices.value(id))
	end, ns.itemName)
	local e = away.list
	away.text:SetText(e.count > 0 and string.format("Bank & mail: %d %s · %s", e.count, e.count == 1 and "item" or "items", money(e.total)) or "")
end

refresh = function()
	if not ah.panel or not ah.panel:IsShown() then
		return
	end
	ns.safely("auction panel away", drawAway)
	if panels:redraw() then
		return
	end
	local tab = TAB[ah.panel.tab]
	if tab then
		tab.refresh(ah.panel[tab.key])
	end
end
ah.refresh = refresh

local reread = Sell.reread

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
		ah.panel, ah.built = panels:get(), Theme.key
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
		local st = ns.scanState()
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
		ns.auctionRefresh()
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

-- The named button the Space binding clicks (SetOverrideBindingClick takes a global name): a key press
-- is a hardware event, as a click is.
local key = CreateFrame("Button", "GoldForeverPostKey", UIParent)
key:Hide()
key:SetScript("OnClick", function()
	if ah.panel and ah.panel:IsShown() and ah.panel.tab == "post" then
		ns.safely("auction post", Sell.post)
		refresh()
	end
end)

local function opened()
	-- Ask the client whether its auction house takes copper (Forever's source leaves it to the client).
	Post.copper = C_AuctionHouse and C_AuctionHouse.SupportsCopperValues and C_AuctionHouse.SupportsCopperValues() or false
	if settings().hidden then
		return
	end
	show()
end
ns.on("AUCTION_HOUSE_SHOW", "auction panel", opened)
-- Started after the auction house opened (loaded on demand there): it opens at once.
ns.module("AuctionPanel", {
	enable = function()
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			opened()
		end
	end,
})
ns.on("AUCTION_HOUSE_CLOSED", "auction panel", hide)
-- A panel that shows is drawn again in the look now set.
panels:onLook("auction panel", function(redrawn)
	if not redrawn then
		refresh()
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
ns.test.AuctionPanelAltClick = chooseFromBag
-- From the hub's Inventory: an item chosen in Post while the auction house is open.
function ns.auctionChoose(itemID)
	ns.safely("auction choose", chooseFromBag, nil, nil, itemID)
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
			Sell.post()
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
		Buy.buyNext()
	end,
	shopNote = function()
		return ah.panel and ah.panel.shop.note.text
	end,
	cancelCheck = function()
		Cancel.startCheck()
	end,
	cancelNext = function()
		Cancel.cancelNext()
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
