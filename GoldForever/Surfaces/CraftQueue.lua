-- Gold Forever: the craft queue window (owner's answers, 2026-10-25): the crafts queued and, for each
-- reagent, what the bags hold, what to pick up from the bank, what the guild bank and the other
-- characters hold, and what is left to buy (the Buy tab's Craft queue list buys it). It opens by itself
-- while the queue has crafts, closes with its X (until a craft is queued again), and opens from the
-- Crafting page or the Craft queue list. Take from bank marks the reagents for the next bank visit.

local _, ns = ...
local Theme, UI, Views, Encode, CraftQueueView = ns.Theme, ns.UI, ns.Views, ns.Encode, ns.CraftQueueView

local CraftQueue = {}
ns.CraftQueue = CraftQueue

local W = 600
local toldReady -- "ready to craft" said for this queue: once, until a craft is queued again

local function settings()
	return ns.settings("craftQueue")
end

-- Every row of the plan for the queue now (Views.queuePlan).
function CraftQueue.plan()
	local needs = ns.queueNeeds()
	local me = ns.me()
	local mine = { bags = {}, bank = {}, mail = {} }
	local bank = me and me.bank and Encode.parseItems(me.bank.items) or {}
	local mail = me and me.mail and Encode.parseItems(me.mail.items) or {}
	for id in pairs(needs) do
		mine.bags[id] = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or 0
		mine.bank[id] = bank[id]
		mine.mail[id] = (mail[id] or 0) + ns.boughtSince(id)
	end
	local guild = GetGuildInfo and GetGuildInfo("player")
	local plan = Views.queuePlan(needs, mine, CraftQueueView.guildCounts(me, guild), CraftQueueView.others(needs, me))
	-- A reagent a vendor sells without limit (seen at a merchant) is bought there, not at the auction house.
	for _, r in ipairs(plan) do
		r.vendor = ns.price.vendorBuy(r.id) ~= nil
	end
	return plan
end

local function build()
	-- Closed with its X, it stays closed until a craft is queued again.
	local f = UI.Dialog({ window = true, width = W, height = 340, strata = "MEDIUM", movable = true, store = settings, at = { "LEFT", 40, 60 },
		icon = "flask-conical", title = "Craft queue", titleSize = "md", close = function()
			settings().closed = true
		end })
	f.crafts = UI.Text(f, "", { size = "xs", tone = "muted", wrap = true })
	f.crafts:SetPoint("TOPLEFT", 14, -38)
	f.crafts:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.table = UI.Table(f, {
		-- Columns wide enough for their titles in every look (manual test run 001: "Ne…", "Ha…", "Ba…").
		{ key = "name", title = "Reagent", flex = 3 },
		{ key = "need", title = "Need", width = 56, align = "RIGHT" },
		{ key = "bags", title = "Bags", width = 56, align = "RIGHT" },
		{ key = "bank", title = "Bank", width = 56, align = "RIGHT", text = function(r) return r.bank > 0 and tostring(r.bank) or "" end },
		{ key = "where", title = "Elsewhere", flex = 2, color = function() return Theme.color.textMuted end },
		{ key = "buy", title = "Buy", width = 80, align = "RIGHT", text = function(r) return r.buy > 0 and (r.buy .. (r.vendor and " vendor" or "")) or "—" end,
			color = function(r) return r.buy > 0 and Theme.color.accent or Theme.color.textFaint end },
	}, { pageSize = 7, rowHeight = 22, empty = "Nothing queued.", itemId = function(r) return r.id end })
	f.table:SetPoint("TOPLEFT", 14, -64)
	f.table:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f.take = UI.Button(f, "Take from bank", function()
		local want = ns.fetchList()
		if not want then
			return
		end
		local n = 0
		for _, r in ipairs(CraftQueue.plan()) do
			if r.bank > 0 then
				want[r.id] = r.bank
				n = n + 1
			end
		end
		f.note:SetText(n > 0 and string.format("%d %s marked: they move into your bags the next time you open your bank.", n, n == 1 and "reagent" or "reagents")
			or "Nothing to take from the bank.")
	end, { width = 130, height = 26 })
	f.take:SetPoint("TOPLEFT", f.table, "BOTTOMLEFT", 0, -10)
	f.clear = UI.Button(f, "Clear queue", function()
		ns.queueClear()
	end, { width = 110, height = 26 })
	f.clear:SetPoint("LEFT", f.take, "RIGHT", 6, 0)
	f.note = UI.Text(f, "", { size = "xs", tone = "faint", wrap = true })
	f.note:SetPoint("TOPLEFT", f.take, "BOTTOMLEFT", 0, -8)
	f.note:SetPoint("RIGHT", f, "RIGHT", -14, 0)
	f:Hide()
	return f
end

-- Where the player left it, else at the left of the screen.
local function dock(f)
	f:Restore()
end

-- One window per look and accent.
local frames = UI.perLook(build, dock)

function CraftQueue.refresh()
	if not frames.frame or not frames.frame:IsShown() then
		return
	end
	frames:redraw()
	local frame = frames.frame
	local queue = ns.queueList()
	local crafts = {}
	for _, q in ipairs(queue) do
		local r = ns.recipeOf(q.recipe)
		crafts[#crafts + 1] = q.count .. "× " .. (r and ns.itemName(r.output) or ("recipe " .. q.recipe))
	end
	frame.crafts:SetText(#crafts > 0 and table.concat(crafts, ", ") or "Nothing queued: queue crafts on the Crafting page or the crafting strip.")
	local rows, buy, vendors, ready = {}, 0, 0, true
	local plan = CraftQueue.plan()
	for _, r in ipairs(plan) do
		local where = {}
		if r.mail > 0 then
			where[#where + 1] = "mailbox " .. r.mail
		end
		if r.guild > 0 then
			where[#where + 1] = "guild bank " .. r.guild
		end
		for _, o in ipairs(r.others) do
			where[#where + 1] = o.name .. " " .. o.n
		end
		-- A reagent all in the bags is done: not listed (owner, 2026-10-25).
		if r.bags < r.need then
			rows[#rows + 1] = { id = r.id, name = ns.itemName(r.id), need = r.need, bags = r.bags, bank = r.bank, where = table.concat(where, ", "), buy = r.buy, vendor = r.vendor }
		end
		if r.buy > 0 and not r.vendor then
			buy = buy + 1
		elseif r.buy > 0 then
			vendors = vendors + 1
		end
		if r.bags < r.need then
			ready = false
		end
	end
	-- Everything in the bags: nothing to fetch or buy, so the window goes (it comes back with the next
	-- craft queued, or from its buttons).
	if ready and #plan > 0 then
		frame:Hide()
		if not toldReady then
			toldReady = true
			ns.say("everything the craft queue needs is in your bags: ready to craft.")
		end
		return
	end
	frame.table:SetRows(rows, true)
	local parts = {}
	if buy > 0 then
		parts[#parts + 1] = string.format("%d to buy at the auction house (Buy tab, list \"Craft queue\")", buy)
	end
	if vendors > 0 then
		parts[#parts + 1] = string.format("%d from a vendor (bought when you open one that sells it)", vendors)
	end
	frame.note:SetText(#parts > 0 and (table.concat(parts, "; ") .. ".") or "Nothing left to buy.")
end

function CraftQueue.show()
	local frame = frames.frame
	if not frame or frames.key ~= Theme.key then
		frame = frames:get()
	end
	dock(frame)
	frame:Show()
	CraftQueue.refresh()
end

-- For the smoke test.
function CraftQueue.window()
	return frames.frame
end

-- From the Crafting page and the Craft queue list: open it again.
function ns.openCraftQueue()
	settings().closed = false
	CraftQueue.show()
end

-- The queue changed (CraftPlanner.lua): a craft added opens it (even after the X); a craft made only redraws it
-- where it shows, so the X sticks (review B-25); an empty queue closes it.
local function queueChanged(how)
	local queue = ns.queueList()
	if how == "added" or #queue == 0 then
		toldReady = nil
	end
	local frame = frames.frame
	if #queue == 0 then
		if frame then
			frame:Hide()
		end
		return
	end
	if how == "added" then
		settings().closed = false
	end
	if frame and frame:IsShown() then
		CraftQueue.refresh()
	elseif how == "added" then
		CraftQueue.show()
	end
end
ns.listen("queueChanged", "craft queue", queueChanged)

-- At a merchant: the queue's vendor reagents it sells, bought (owner, 2026-10-25: "be bought when talking
-- to a vendor that has the item"), as many as are still to buy and the money allows, in stacks the
-- merchant sells. A chat line says what was bought.
local function buyFromMerchant()
	if ns.inCombat() then
		return
	end
	local need = {}
	for _, r in ipairs(CraftQueue.plan()) do
		if r.buy > 0 then
			need[r.id] = r.buy
		end
	end
	if not next(need) then
		return
	end
	local bought, spent, money = {}, 0, GetMoney()
	for i = 1, (GetMerchantNumItems and GetMerchantNumItems() or 0) do
		local id = GetMerchantItemID and GetMerchantItemID(i)
		local n = id and need[id]
		if n then
			local price, per, extended
			if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
				local info = C_MerchantFrame.GetItemInfo(i)
				if info then
					price, per, extended = info.price, info.stackCount, info.hasExtendedCost
				end
			else
				local _
				_, _, price, per, _, _, _, extended = GetMerchantItemInfo(i)
			end
			per = math.max(1, per or 1)
			if price and price > 0 and not extended then
				local unit = price / per
				-- What the money allows, then in the merchant's largest stack a purchase.
				n = math.min(n, math.floor(money / unit))
				local most = GetMerchantItemMaxStack and GetMerchantItemMaxStack(i) or n
				local left = n
				while left > 0 do
					local take = math.min(left, math.max(1, most))
					BuyMerchantItem(i, take)
					left = left - take
				end
				if n > 0 then
					bought[#bought + 1] = n .. "× " .. ns.itemName(id)
					spent, money = spent + n * unit, money - n * unit
				end
			end
		end
	end
	if #bought > 0 then
		ns.say("bought for the craft queue: " .. table.concat(bought, ", ") .. " (" .. ns.price.coins(spent) .. ").")
	end
end
ns.on("MERCHANT_SHOW", "craft queue", function()
	ns.after(0.6, "craft queue", buyFromMerchant)
end)

-- At login, while there are crafts queued and it was not closed.
ns.on("PLAYER_ENTERING_WORLD", "craft queue", function(isInitialLogin, isReloadingUi)
	if isInitialLogin or isReloadingUi then
		ns.after(3, "craft queue", function()
			local queue = ns.queueList()
			if #queue > 0 and not settings().closed then
				CraftQueue.show()
			end
		end)
	end
end)

-- What it shows follows the bags, the bank, the mail and the guild bank, once a second at most.
local soon = ns.throttle("craft queue", 1, CraftQueue.refresh)
for _, event in ipairs({ "BAG_UPDATE_DELAYED", "MAIL_INBOX_UPDATE", "BANKFRAME_CLOSED", "PLAYERBANKSLOTS_CHANGED", "GUILDBANKBAGSLOTS_CHANGED" }) do
	ns.on(event, "craft queue", function()
		if frames.frame and frames.frame:IsShown() then
			soon()
		end
	end)
end
ns.onBagsRead(function()
	if frames.frame and frames.frame:IsShown() then
		soon()
	end
end)
frames:onLook("craft queue", CraftQueue.refresh)
