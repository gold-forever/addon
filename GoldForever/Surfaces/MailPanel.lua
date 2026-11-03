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

-- Where the panel may sit, first that fits: under the inbox, to its left, then beside or under the open
-- mail; never on the inbox or the open mail (the client puts it right of the inbox, an addon anywhere).
local GAP = 6
local SPOTS = {
	{ "TOPLEFT", "MailFrame", "BOTTOMLEFT", 0, -GAP },
	{ "TOPRIGHT", "MailFrame", "TOPLEFT", -GAP, 0 },
	{ "TOPLEFT", "OpenMailFrame", "TOPRIGHT", GAP, 0 },
	{ "TOPLEFT", "OpenMailFrame", "BOTTOMLEFT", 0, -GAP },
}

-- A placed frame's box in screen pixels, or nil.
local function box(f)
	local left, bottom = f and f:GetLeft(), f and f:GetBottom()
	if not left or not bottom then
		return nil
	end
	local s = f:GetEffectiveScale()
	return { l = left * s, b = bottom * s, r = f:GetRight() * s, t = f:GetTop() * s }
end

local function meets(a, b)
	return a.l < b.r and b.l < a.r and a.b < b.t and b.b < a.t
end

-- The panel's box at `spot` beside `to`, the box of the frame it is anchored to.
local function boxAt(p, spot, to)
	local s = p:GetEffectiveScale()
	local w, h = p:GetWidth() * s, p:GetHeight() * s
	local x = (spot[3]:find("LEFT") and to.l or to.r) + spot[4] * s
	local y = (spot[3]:find("TOP") and to.t or to.b) + spot[5] * s
	local l = spot[1]:find("LEFT") and x or x - w
	return { l = l, r = l + w, t = y, b = y - h }
end

local function onScreen(a)
	local screen = box(UIParent)
	return not screen or (a.l >= screen.l and a.r <= screen.r and a.b >= screen.b and a.t <= screen.t)
end

local function covers(a)
	for _, name in ipairs({ "MailFrame", "OpenMailFrame" }) do
		local other = box(_G[name])
		if other and meets(a, other) then
			return true
		end
	end
	return false
end

-- The first spot on screen clear of both frames, else the first clear of them, else under the inbox.
local function spot(p)
	local clear
	for _, at in ipairs(SPOTS) do
		local to = box(_G[at[2]])
		local a = to and boxAt(p, at, to)
		local free = a and not covers(a)
		if free and onScreen(a) then
			return at
		end
		clear = clear or (free and at)
	end
	return clear or SPOTS[1]
end

local function dock(p)
	local at = spot(p)
	p:ClearAllPoints()
	p:SetPoint(at[1], _G[at[2]], at[3], at[4], at[5])
end
panels = UI.perLook(build, dock)

-- The open mail shown, hidden or moved (by the client or a mail addon): the panel placed again, at once
-- and once the frame has settled.
local function redock()
	local panel = panels.frame
	if panel and panel:IsShown() then
		dock(panel)
	end
end
local function redockSoon()
	ns.safely("mail helper", redock)
	C_Timer.After(0, function()
		ns.safely("mail helper", redock)
	end)
end
local watched = {}
local function watch(frame)
	if not frame or watched[frame] or not frame.HookScript then
		return
	end
	watched[frame] = true
	frame:HookScript("OnShow", redockSoon)
	frame:HookScript("OnHide", redockSoon)
	hooksecurefunc(frame, "SetPoint", redockSoon)
end

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
	watch(MailFrame)
	watch(OpenMailFrame)
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
