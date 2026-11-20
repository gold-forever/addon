-- Gold Forever: the auction mail helper's panel beside the mailbox: one press starts MailHelper.lua's
-- batch, which opens the auction house's mail and says what the panel's note shows.

local _, ns = ...
local L = ns.L
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
	panel.count:SetText(n > 0 and string.format(L["%s: %s, %s"], ns.plural(n, L["%d auction mail"], L["%d auction mails"]),
		UI.layout.money(gold, "gold"), ns.plural(items, L["%d item"], L["%d items"])) or L["No auction mail."])
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
	p.open = UI.Button(p, L["Open all auction mail"], function()
		ns.safely("mail helper", Mail.press)
	end, { kind = "primary", width = 232, height = 30 })
	p.open:SetPoint("TOPLEFT", 14, -78)
	p.note = UI.Text(p, L["Gold and items from sold, bought, expired and cancelled auctions; never a player's letter."], { size = "xs", tone = "faint", wrap = true })
	p.note:SetPoint("TOPLEFT", p.open, "BOTTOMLEFT", 0, -8)
	p.note:SetWidth(232)
	return p
end

-- Where the panel may sit, first that fits: right of the inbox, tops aligned (owner, 2026-11-20), and
-- right of the open mail while one shows there; then under the inbox, to its left, under the open mail.
-- Never on the inbox or the open mail.
local GAP = 6
local SPOTS = {
	{ "TOPLEFT", "MailFrame", "TOPRIGHT", GAP, 0 },
	{ "TOPLEFT", "OpenMailFrame", "TOPRIGHT", GAP, 0 },
	{ "TOPLEFT", "MailFrame", "BOTTOMLEFT", 0, -GAP },
	{ "TOPRIGHT", "MailFrame", "TOPLEFT", -GAP, 0 },
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

-- A shown frame's box with its tabs (a hidden one is neither in the way nor a place): the inbox's Inbox and Send Mail tabs hang below it, and the panel stays
-- clear of them (owner, 2026-11-20: it covered them).
local function reach(name)
	local f = _G[name]
	local b = f and (not f.IsShown or f:IsShown()) and box(f)
	if not b then
		return nil
	end
	for i = 1, 4 do
		local tab = _G[name .. "Tab" .. i]
		local t = tab and tab.IsShown and tab:IsShown() and box(tab)
		if t then
			b.l, b.b, b.r, b.t = math.min(b.l, t.l), math.min(b.b, t.b), math.max(b.r, t.r), math.max(b.t, t.t)
		end
	end
	return b
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
		local other = reach(name)
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
		local to = reach(at[2])
		local a = to and boxAt(p, at, to)
		local free = a and not covers(a)
		if free and onScreen(a) then
			return at
		end
		clear = clear or (free and at)
	end
	return clear or SPOTS[1]
end

-- Anchored to the frame itself, moved by what its tabs add on that side.
local function dock(p)
	local at = spot(p)
	local frame = _G[at[2]]
	local own, to = box(frame), reach(at[2])
	local dx, dy = 0, 0
	if own and to then
		local s = p:GetEffectiveScale()
		dx = ((at[3]:find("LEFT") and to.l - own.l) or to.r - own.r) / s
		dy = ((at[3]:find("TOP") and to.t - own.t) or to.b - own.b) / s
	end
	p:ClearAllPoints()
	p:SetPoint(at[1], frame, at[3], at[4] + dx, at[5] + dy)
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

-- A button on the mailbox that hides and shows the panel, kept as Settings > Modules > Mail helper keeps
-- it (the same switch): in its title bar, left of its close button. One per look, as the panel.
local toggles = {}
local function label(b)
	b:SetLabel(settings().helper == false and L["Show Gold Forever"] or L["Hide Gold Forever"])
	b:SetWidth(math.max(60, (b.label:GetStringWidth() or 40) + 24))
end

local show
local function buildToggle(frame)
	local b = UI.Button(frame, L["Hide Gold Forever"], function()
		local on = settings().helper == false
		settings().helper = on
		if on then
			show()
		else
			close()
		end
		label(toggles[ns.Theme.key] or b)
	end, { kind = "ghost", height = 18 })
	local x = _G.MailFrameCloseButton or frame.CloseButton
	if x then
		b:SetPoint("RIGHT", x, "LEFT", -2, 0)
	else
		b:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -28, -2)
	end
	b:HookScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
		GameTooltip:AddLine("Gold Forever", 1, 1, 1)
		GameTooltip:AddLine(L["Shows or hides Gold Forever's mail panel beside the mailbox."], 0.7, 0.7, 0.7, true)
		GameTooltip:Show()
	end)
	b:HookScript("OnLeave", function()
		GameTooltip:Hide()
	end)
	b.home = frame
	return b
end

-- The button in the look now set, on the mailbox; another look's hidden.
local function placeToggle()
	local frame = MailFrame
	if not frame then
		return
	end
	local b = toggles[ns.Theme.key]
	if not b or b.home ~= frame then
		b = buildToggle(frame)
		toggles[ns.Theme.key] = b
	end
	for _, other in pairs(toggles) do
		other:SetShown(other == b)
	end
	label(b)
end

show = function()
	local panel = panels.frame
	if not panel or panels.key ~= ns.Theme.key then
		panel = panels:get()
	end
	watch(MailFrame)
	watch(OpenMailFrame)
	dock(panel)
	panel:Show()
	refresh()
end

-- The client's mailbox opens and closes through its interaction manager, and MAIL_CLOSED does not come
-- every time the inbox goes (its close button, Escape, walking away): the panel goes with MailFrame.
local hooked = false
ns.on("MAIL_SHOW", "mail helper", function()
	if not MailFrame then
		return
	end
	if not hooked and MailFrame.HookScript then
		hooked = true
		MailFrame:HookScript("OnHide", function()
			ns.safely("mail helper", close)
		end)
	end
	ns.safely("mail helper toggle", placeToggle)
	if settings().helper == false then
		return
	end
	show()
end)
ns.on("MAIL_CLOSED", "mail helper", close)
-- A panel that shows is drawn again in the look now set.
panels:onLook("mail helper", function(redrawn)
	if MailFrame and MailFrame:IsShown() then
		placeToggle()
	end
	if redrawn then
		refresh()
	end
end)

-- For the smoke test.
Mail.panel = function()
	return panels.frame
end
Mail.toggle = function()
	return toggles[ns.Theme.key]
end
