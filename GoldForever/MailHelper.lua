-- Gold Forever: the auction mail helper (owner's answer, 2026-10-24): beside the mailbox, one press
-- opens all the auction house's mail, sold gold, bought, expired, cancelled and outbid items, one mail
-- after the other as fast as the server takes them (manual test run 001: ten a press, at least 0.3 s
-- apart, was slow next to other mail tools), stopping when the bags are full. A player's letter,
-- and any mail asking for cash on delivery, is never touched.

local _, ns = ...
ns = ns or {}

local Mail = {}
ns.Mail = Mail

Mail.BATCH = 500 -- mails a press: all of them (a guard against a loop, not a limit)
-- Seconds between the inbox's update after a take and the next take, and between checks while the
-- server is busy. 0.05 on the take's own answer was too soon (manual test run 001: three mails, then the
-- mailbox refused the next and the press ended): the inbox must have dropped the mail first.
local GAP = 0.15
local RETRIES = 3 -- a refused take is tried again, a second apart, this many times
local WAIT = 0.5 -- seconds to wait for an answer the client never sends

-- The auction house's subjects as the client words them ("Auction successful: %s"), English fallbacks
-- for the tests; as Lua patterns that match the whole subject.
function Mail.patterns(formats)
	formats = formats or {
		AUCTION_SOLD_MAIL_SUBJECT or "Auction successful: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT or "Auction expired: %s",
		AUCTION_REMOVED_MAIL_SUBJECT or "Auction canceled: %s",
		AUCTION_WON_MAIL_SUBJECT or "Auction won: %s",
		AUCTION_OUTBID_MAIL_SUBJECT or "Outbid on %s",
	}
	local out = {}
	for _, f in ipairs(formats) do
		-- Escape the pattern's magic characters, then let %s stand for anything.
		local escaped = string.gsub(f, "([%(%)%.%+%-%*%?%[%]%^%$%%])", "%%%1")
		out[#out + 1] = "^" .. string.gsub(escaped, "%%%%s", ".+") .. "$"
	end
	return out
end

function Mail.isAuction(subject, patterns)
	if type(subject) ~= "string" then
		return false
	end
	for _, p in ipairs(patterns) do
		if string.find(subject, p) then
			return true
		end
	end
	return false
end

-- The next auction mail to open from the inbox's headers ({ subject, money, cod, items, canReply }), in
-- order: one with something to take, no cash on delivery, and items only while the bags have room for
-- them. A letter that can be answered is a player's, whatever its subject says: never opened.
-- Returns its index, or nil and why ("none" or "bags").
function Mail.next(headers, freeSlots, patterns)
	local blocked = false
	for i, h in ipairs(headers) do
		if Mail.isAuction(h.subject, patterns) and not h.canReply and (h.cod or 0) == 0 and ((h.money or 0) > 0 or (h.items or 0) > 0) then
			if (h.items or 0) == 0 or (h.items or 0) <= freeSlots then
				return i
			end
			blocked = true
		end
	end
	return nil, blocked and "bags" or "none"
end

if not CreateFrame then
	return -- the tests load the rules above alone
end

local Theme, UI = ns.Theme, ns.UI
local patterns
local panel, built
local panels = {} -- Theme.key -> panel
local run -- a batch in progress: { left, waiting, failed, next }

local function settings()
	return ns.settings("mail", { helper = true })
end

local function headers()
	local out = {}
	for i = 1, (GetInboxNumItems and GetInboxNumItems() or 0) do
		local _, _, _, subject, money, cod, _, items, _, _, _, canReply = GetInboxHeaderInfo(i)
		out[i] = { subject = subject, money = money or 0, cod = cod or 0, items = items or 0, canReply = canReply }
	end
	return out
end

local function freeSlots()
	local free = 0
	for bag = 0, NUM_BAG_SLOTS or 4 do
		local n, kind = C_Container.GetContainerNumFreeSlots(bag)
		if (kind or 0) == 0 then
			free = free + (n or 0)
		end
	end
	return free
end

-- How much auction mail waits: mails, gold, items.
local function waiting()
	local n, gold, items = 0, 0, 0
	for _, h in ipairs(headers()) do
		if Mail.isAuction(h.subject, patterns) and not h.canReply and h.cod == 0 then
			n, gold, items = n + 1, gold + h.money, items + h.items
		end
	end
	return n, gold, items
end

local function refresh()
	if not panel or not panel:IsShown() then
		return
	end
	local n, gold, items = waiting()
	panel.count:SetText(n > 0 and string.format("%d auction %s: %s, %d %s", n, n == 1 and "mail" or "mails", UI.layout.money(gold, "gold"), items, items == 1 and "item" or "items")
		or "No auction mail.")
	local can = n > 0 and not run
	if can then
		panel.open:Enable()
		panel.open:SetAlpha(1)
	else
		panel.open:Disable()
		panel.open:SetAlpha(0.5)
	end
end

-- The batch's next step after `seconds`. Each call replaces the one still waiting, so one take runs at a
-- time: a take's own timeout cannot start a take beside the next (review B-3).
local step
local function later(seconds)
	local mine, token = run, {}
	run.next = token
	C_Timer.After(seconds, function()
		if run == mine and mine.next == token then
			mine.next = nil
			ns.safely("mail helper", step)
		end
	end)
end

-- One step of a batch: the next auction mail opened, then the next once the inbox has changed.
function step()
	if not run then
		return
	end
	local index, why = Mail.next(headers(), freeSlots(), patterns)
	if not index or run.left <= 0 then
		-- The client shows 50 mails at a time; the rest arrive when the mailbox refreshes.
		local shown, total = GetInboxNumItems()
		local more = total and shown and total > shown and (total - shown) or 0
		panel.note:SetText(why == "bags" and "Your bags are full: make room and press again."
			or more > 0 and string.format("All shown auction mail opened. %d more %s arrive when the mailbox refreshes (within a minute): press again then.", more, more == 1 and "mail" or "mails")
			or "All auction mail opened.")
		run = nil
		refresh()
		return
	end
	-- One mail at a time, as Blizzard's Open All does: not while the server still works on the last.
	if C_Mail and C_Mail.IsCommandPending and C_Mail.IsCommandPending() then
		later(GAP)
		return
	end
	run.left = run.left - 1
	run.waiting = true
	if AutoLootMailItem then
		AutoLootMailItem(index)
	else
		TakeInboxMoney(index)
		-- Attachment slots can have gaps: every slot, from the last.
		for a = ATTACHMENTS_MAX_RECEIVE or 16, 1, -1 do
			if not HasInboxItem or HasInboxItem(index, a) then
				TakeInboxItem(index, a)
			end
		end
	end
	-- Next when the take succeeds or the inbox changes, or after a moment if neither says.
	if run and run.waiting then
		later(WAIT)
	end
end

-- The server refused a take (a full bag, a busy inbox): tried again, then the batch stops and says so.
ns.on("MAIL_FAILED", "mail helper", function()
	if not run or not run.waiting then
		return
	end
	run.waiting = false
	run.failed = (run.failed or 0) + 1
	if run.failed > RETRIES then
		run = nil
		if panel then
			panel.note:SetText("The mailbox refused it again; press again in a moment.")
		end
		refresh()
		return
	end
	-- Busy: the same mail again after a second.
	run.left = run.left + 1
	later(1)
end)

local function answered()
	if run and run.waiting then
		run.waiting, run.failed = false, 0
		later(GAP)
	end
end
ns.on("MAIL_INBOX_UPDATE", "mail helper", function()
	answered()
	refresh()
end)

local function press()
	if run then
		return
	end
	run = { left = Mail.BATCH }
	panel.note:SetText("Opening…")
	step()
	refresh()
end

local function build()
	if ns.applyLook then
		ns.applyLook()
	end
	patterns = patterns or Mail.patterns()
	-- One panel per look and accent, reused when the look comes back (frames are never freed).
	if panels[ns.Theme.key] then
		if panel and panel ~= panels[ns.Theme.key] then
			panel:Hide()
		end
		panel, built = panels[ns.Theme.key], ns.Theme.key
		return
	end
	local p = UI.Panel(UIParent, { window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	p:SetSize(260, 150)
	p:SetFrameStrata("HIGH")
	p:Hide()
	local mark = UI.Icon(p, "coins", 16, "accent")
	mark:SetPoint("TOPLEFT", 14, -14)
	local title = UI.Text(p, Theme.skin.titleCaps and "GOLD FOREVER" or "Gold Forever", { size = "sm", medium = true, tone = "muted" })
	title:SetPoint("LEFT", mark, "RIGHT", 6, 0)
	p.count = UI.Text(p, "", { size = "sm", wrap = true })
	p.count:SetPoint("TOPLEFT", 14, -40)
	p.count:SetWidth(232)
	p.open = UI.Button(p, "Open all auction mail", function()
		ns.safely("mail helper", press)
	end, { kind = "primary", width = 232, height = 30 })
	p.open:SetPoint("TOPLEFT", 14, -78)
	p.note = UI.Text(p, "Gold and items from sold, bought, expired and cancelled auctions; never a player's letter.", { size = "xs", tone = "faint", wrap = true })
	p.note:SetPoint("TOPLEFT", p.open, "BOTTOMLEFT", 0, -8)
	p.note:SetWidth(232)
	panel = p
	built = ns.Theme.key
	panels[built] = p
end

local function close()
	run = nil
	if panel then
		panel:Hide()
	end
end

-- The client's mailbox opens and closes through its interaction manager, and MAIL_CLOSED does not come
-- every time the inbox goes (its close button, Escape, walking away): the panel goes with MailFrame.
local hooked = false
ns.on("MAIL_SHOW", "mail helper", function()
	if settings().helper == false or not MailFrame then
		return
	end
	if not hooked and MailFrame.HookScript then
		hooked = true
		MailFrame:HookScript("OnHide", function()
			ns.safely("mail helper", close)
		end)
	end
	if not panel or built ~= ns.Theme.key then
		build()
	end
	panel:ClearAllPoints()
	panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
	panel:Show()
	refresh()
end)
ns.on("MAIL_CLOSED", "mail helper", close)
-- A panel that shows is drawn again in the look now set.
ns.onLook("mail helper", function()
	if panel and panel:IsShown() and built ~= ns.Theme.key then
		panel:Hide()
		build()
		panel:ClearAllPoints()
		panel:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
		panel:Show()
		refresh()
	end
end)

-- For the smoke test.
Mail.press = function()
	press()
end
Mail.panel = function()
	return panel
end
