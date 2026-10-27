-- Gold Forever: the auction mail helper's panel beside the mailbox: one press starts MailHelper.lua's
-- batch, which opens the auction house's mail and says what the panel's note shows.

local _, ns = ...
local UI = ns.UI
local Mail = ns.Mail

local panels -- one panel per look and accent (UI.perLook)

local function settings()
	return ns.settings("mail")
end

local function refresh()
	local panel = panels.frame
	if not panel or not panel:IsShown() then
		return
	end
	local n, gold, items = Mail.waiting()
	panel.count:SetText(n > 0 and string.format("%d auction %s: %s, %d %s", n, n == 1 and "mail" or "mails", UI.layout.money(gold, "gold"), items, items == 1 and "item" or "items")
		or "No auction mail.")
	panel.open:SetEnabled(n > 0 and not Mail.running())
end

-- The batch (MailHelper.lua) says what the note shows.
ns.listen("mailBatch", "mail helper", function(note)
	if panels.frame then
		panels.frame.note:SetText(note)
	end
	refresh()
end)
ns.on("MAIL_INBOX_UPDATE", "mail helper", refresh)

local function build()
	local p = UI.Dialog({ window = true, width = 260, height = 150, strata = "HIGH", icon = "coins", title = "Gold Forever", titleTone = "muted" })
	p:Hide()
	p.count = UI.Text(p, "", { size = "sm", wrap = true })
	p.count:SetPoint("TOPLEFT", 14, -40)
	p.count:SetWidth(232)
	p.open = UI.Button(p, "Open all auction mail", function()
		ns.safely("mail helper", Mail.press)
	end, { kind = "primary", width = 232, height = 30 })
	p.open:SetPoint("TOPLEFT", 14, -78)
	p.note = UI.Text(p, "Gold and items from sold, bought, expired and cancelled auctions; never a player's letter.", { size = "xs", tone = "faint", wrap = true })
	p.note:SetPoint("TOPLEFT", p.open, "BOTTOMLEFT", 0, -8)
	p.note:SetWidth(232)
	return p
end

-- Beside the mailbox.
local function dock(p)
	p:ClearAllPoints()
	p:SetPoint("TOPLEFT", MailFrame, "TOPRIGHT", 6, 0)
end
panels = UI.perLook(build, dock)

local function close()
	Mail.stop()
	if panels.frame then
		panels.frame:Hide()
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
	local panel = panels.frame
	if not panel or panels.key ~= ns.Theme.key then
		panel = panels:get()
	end
	dock(panel)
	panel:Show()
	refresh()
end)
ns.on("MAIL_CLOSED", "mail helper", close)
-- A panel that shows is drawn again in the look now set.
panels:onLook("mail helper", function(redrawn)
	if redrawn then
		refresh()
	end
end)

-- For the smoke test.
Mail.panel = function()
	return panels.frame
end
