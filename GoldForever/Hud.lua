-- Gold Forever: the session HUD. A line of rates to drag anywhere, gold, XP and kills an hour with the
-- time to the next level; a click opens the session under it (Session.lua keeps the session).

local _, ns = ...
local Session = ns.Session
local itemInfo = ns.price.itemInfo

local hud -- the one-line HUD; hud.details is the session panel under it
local huds = {} -- Theme.key -> HUD
local hudThemeKey -- the Theme.key the HUD was drawn under

local function settings()
	return ns.settings("appraiser", { shown = true })
end

local build
local startTicker -- set below; the HUD's OnShow starts it

local function refresh()
	if not hud or not hud:IsShown() then
		return
	end
	local Theme, UI, Views = ns.Theme, ns.UI, ns.Views
	if hudThemeKey ~= Theme.key then
		local open = hud.details:IsShown()
		hud:Hide()
		build()
		hud:Show()
		hud.details:SetShown(open)
	end
	local faint = Theme.escape(Theme.color.textFaint)
	local session = Session.get()
	if not session then
		hud.time:SetText("")
		hud.gold:SetText(faint .. "Loot or kill something to start a session.|r")
		hud.xp:SetText("")
		hud.kills:SetText("")
		hud.ding:SetText("")
		hud.details:Hide()
		return
	end
	local sum = ns.sessionSummary()
	local secs, value, unpriced, r = sum.elapsed, sum.value, sum.unpriced, sum.rates
	local dash = faint .. "—|r"
	hud.time:SetText((Session.idle() and "ended " or "") .. Views.duration(math.max(60, secs)))
	hud.gold:SetText((r.rated and UI.layout.money(r.goldPerHour, "gold") or dash) .. faint .. " /h|r")
	hud.xp:SetText((r.rated and Views.short(r.xpPerHour) or dash) .. faint .. " XP/h|r")
	hud.kills:SetText((r.rated and Views.short(r.killsPerHour) or dash) .. faint .. " kills/h|r")
	hud.ding:SetText(not r.rated and "warming up…" or r.dingIn and ("ding in " .. Theme.escape(Theme.color.text) .. Views.duration(r.dingIn) .. "|r") or "")

	local d = hud.details
	if not d:IsShown() then
		return
	end
	d.values[1]:SetText(UI.layout.money(session.coin))
	d.values[2]:SetText(UI.layout.money(value) .. (unpriced > 0 and (faint .. string.format("  +%d unpriced", unpriced) .. "|r") or ""))
	d.values[3]:SetText(UI.layout.money(r.total) .. (r.rated and (faint .. "  · " .. "|r" .. UI.layout.money(r.goldPerHour, "gold") .. faint .. " an hour|r") or ""))
	d.values[4]:SetText(Views.short(sum.xp) .. (r.killsToLevel and (faint .. string.format("  · ~%d kills to level %d", r.killsToLevel, sum.nextLevel or 0) .. "|r") or ""))
	d.values[5]:SetText(sum.kills .. faint .. "  from kill XP and corpses, never the combat log|r")
	local bags = sum.bagFree == 0 and (Theme.escape(Theme.color.danger) .. "full|r") or (sum.bagFree .. " free")
	if sum.fullIn then
		bags = bags .. faint .. "  · full in ~" .. Views.duration(sum.fullIn) .. "|r"
	end
	d.values[6]:SetText(bags)
	-- The most valuable loot so far.
	local ranked = sum.ranked
	for i, row in ipairs(d.items) do
		local it = ranked[i]
		row:SetShown(it ~= nil)
		if it then
			local quality, _, _, _, name = itemInfo(it.id)
			local icon = C_Item and C_Item.GetItemIconByID and C_Item.GetItemIconByID(it.id) or (GetItemIcon and GetItemIcon(it.id))
			row.icon:SetTexture(icon or 134400) -- the question mark
			row.name:SetText(Theme.escape(Theme.quality[quality or 1] or Theme.color.text) .. (name or ("item " .. it.id)) .. "|r" .. faint .. " ×" .. it.n .. "|r")
			row.value:SetText(it.value > 0 and UI.layout.money(it.value, "gold") or (faint .. "no price|r"))
		end
	end
	d.empty:SetShown(#ranked == 0)
end

-- A small movable window with a title, a close button and a text body; its position is kept in
-- [store]. Shared with the loot advisor.
function ns.makeWindow(name, title, store, point, onClose)
	local f = CreateFrame("Frame", name, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
	f:SetSize(260, 120)
	if store.point then
		f:SetPoint(store.point[1], UIParent, store.point[2], store.point[3], store.point[4])
	else
		f:SetPoint(point[1], UIParent, point[1], point[2], point[3])
	end
	if f.SetBackdrop then
		f:SetBackdrop({
			bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			edgeSize = 12,
			insets = { left = 3, right = 3, top = 3, bottom = 3 },
		})
		f:SetBackdropColor(0, 0, 0, 0.85)
	end
	f:SetClampedToScreen(true)
	f:SetMovable(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rel, x, y = self:GetPoint()
		store.point = { p, rel, x, y }
	end)

	local heading = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
	heading:SetPoint("TOPLEFT", 10, -9)
	heading:SetText(title)

	local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
	close:SetPoint("TOPRIGHT", 2, 2)
	close:SetScript("OnClick", function()
		f:Hide()
		if onClose then
			onClose()
		end
	end)

	local text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
	text:SetPoint("TOPLEFT", 10, -28)
	text:SetWidth(240)
	text:SetJustifyH("LEFT")
	text:SetSpacing(2)
	return f, text
end

local W, H = 540, 34
local ROWS = { "Coin", "Loot, at what it sells for", "Total", "XP", "Kills", "Bags" }
local TOP_LOOT = 5

-- Draws the HUD in the look and accent the player set: a line of rates to drag anywhere; a click opens
-- the session under it. Drawn again when the look changes (refresh notices).
build = function()
	local Theme, UI = ns.Theme, ns.UI
	if ns.applyLook then
		ns.applyLook()
	end
	local s = settings()
	local old = hud
	-- One HUD per look and accent, reused when the look comes back (frames are never freed), placed
	-- where the player last left either.
	local cached = huds[Theme.key]
	if cached then
		if old and old ~= cached then
			old:Hide()
		end
		hud, hudThemeKey = cached, Theme.key
		hud:ClearAllPoints()
		if s.point then
			hud:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
		else
			hud:SetPoint("TOP", UIParent, "TOP", 0, -110)
		end
		return
	end
	hud = UI.Panel(UIParent, { color = Theme.color.surface, alpha = 0.94, borderColor = Theme.color.borderStrong })
	hud:SetSize(W, H)
	hud:SetFrameStrata("MEDIUM")
	hud:SetClampedToScreen(true)
	hud:SetMovable(true)
	if s.point then
		hud:SetPoint(s.point[1], UIParent, s.point[2], s.point[3], s.point[4])
	else
		hud:SetPoint("TOP", UIParent, "TOP", 0, -110)
	end
	hud:Hide()
	if old then
		old:Hide()
	end
	local web = Theme.skin.radius ~= nil
	-- The whole line is one button: click for the session, drag to move.
	local hit = CreateFrame("Button", nil, hud)
	hit:SetAllPoints()
	hit:RegisterForDrag("LeftButton")
	hit:SetScript("OnDragStart", function()
		hud:StartMoving()
	end)
	hit:SetScript("OnDragStop", function()
		hud:StopMovingOrSizing()
		local p, _, rel, x, y = hud:GetPoint()
		s.point = { p, rel, x, y }
	end)
	hit:SetScript("OnClick", function()
		if Session.get() then
			hud.details:SetShown(not hud.details:IsShown())
			refresh()
		end
	end)
	local mark = UI.solid(hit, "ARTWORK", Theme.color.accent)
	mark:SetSize(8, 8)
	mark:SetPoint("LEFT", 12, 0)
	if Theme.skin.decor and Theme.skin.decor.mark == "rune" then
		mark:SetTexture(Theme.media.rune)
		mark:SetBlendMode("ADD")
		mark:SetSize(16, 16)
		mark:SetPoint("LEFT", 8, 0)
	end
	local function field(x, width, size, tone, align)
		local t = UI.Text(hit, "", { size = size, tone = tone, medium = size == "md" and web, align = align })
		t:SetPoint("LEFT", x, 0)
		t:SetWidth(width)
		return t
	end
	hud.time = field(28, 64, "sm", "muted")
	hud.gold = field(94, 140, "md")
	hud.xp = field(236, 110, "md")
	hud.kills = field(348, 92, "md")
	hud.ding = UI.Text(hit, "", { size = "sm", tone = "muted", align = "RIGHT" })
	hud.ding:SetPoint("RIGHT", -12, 0)
	hud.ding:SetWidth(110)

	-- The session, under the line.
	local d = UI.Panel(hud, { color = Theme.color.surface, alpha = 0.96, borderColor = Theme.color.borderStrong })
	d:SetPoint("TOPLEFT", hud, "BOTTOMLEFT", 0, -6)
	d:SetWidth(W)
	d:SetHeight(48 + #ROWS * 20 + 26 + TOP_LOOT * 28 + 48)
	d:EnableMouse(true)
	d:Hide()
	local head = UI.Text(d, Theme.skin.titleCaps and "THIS SESSION" or "This session", { size = "lg", medium = true })
	head:SetPoint("TOPLEFT", 16, -14)
	d.values = {}
	for i, label in ipairs(ROWS) do
		local l = UI.Text(d, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", 16, -24 - i * 20)
		local v = UI.Text(d, "", { size = "sm" })
		v:SetPoint("TOPLEFT", 190, -24 - i * 20)
		v:SetWidth(W - 206)
		d.values[i] = v
	end
	local y = -24 - #ROWS * 20 - 34
	local lootHead = UI.Text(d, "LOOT", { size = "xs", medium = true, tone = "faint" })
	lootHead:SetPoint("TOPLEFT", 16, y)
	d.items = {}
	for i = 1, TOP_LOOT do
		local row = CreateFrame("Frame", nil, d)
		row:SetHeight(28)
		row:SetPoint("TOPLEFT", 12, y - 16 - (i - 1) * 28)
		row:SetPoint("RIGHT", d, "RIGHT", -12, 0)
		row.icon = row:CreateTexture(nil, "ARTWORK")
		row.icon:SetSize(22, 22)
		row.icon:SetPoint("LEFT", 4, 0)
		row.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
		row.name = UI.Text(row, "", { size = "sm" })
		row.name:SetPoint("LEFT", 34, 0)
		row.name:SetWidth(330)
		row.value = UI.Text(row, "", { size = "sm", align = "RIGHT" })
		row.value:SetPoint("RIGHT", -4, 0)
		row.value:SetWidth(140)
		d.items[i] = row
	end
	d.empty = UI.Text(d, "Nothing looted yet.", { size = "sm", tone = "faint" })
	d.empty:SetPoint("TOPLEFT", 16, y - 22)
	local stop = UI.Button(d, "Stop", function()
		Session.stop()
		refresh()
	end, { kind = "ghost", width = 80, height = 26 })
	stop:SetPoint("BOTTOMLEFT", 12, 12)
	local reset = UI.Button(d, "New session", function()
		ns.commands.reset()
	end, { kind = "ghost", width = 120, height = 26 })
	reset:SetPoint("LEFT", stop, "RIGHT", 8, 0)
	local hide = UI.Button(d, "Hide the HUD", function()
		ns.commands.appraise()
	end, { width = 130, height = 26 })
	hide:SetPoint("BOTTOMRIGHT", -12, 12)
	hud.details = d
	hudThemeKey = Theme.key
	-- The clock runs whenever the HUD shows, however it came back (after combat, a loading screen, a new
	-- look): manual test run 001, the HUD stood still at "1m · warming up…" in a delve until a /reload.
	hud:HookScript("OnShow", function()
		if startTicker then
			startTicker()
		end
	end)
	huds[hudThemeKey] = hud
end

-- Whether the HUD stays out of the way now: in combat, when the player asked for that.
local function tucked()
	return settings().hideInCombat and InCombatLockdown and InCombatLockdown()
end

local function show()
	if not hud then
		build()
	end
	if tucked() then
		return
	end
	hud:Show()
	refresh()
	startTicker()
end

ns.on("PLAYER_REGEN_DISABLED", "appraiser", function()
	if hud and settings().hideInCombat then
		hud:Hide()
	end
end)
ns.on("PLAYER_REGEN_ENABLED", "appraiser", function()
	if hud and settings().shown and settings().hideInCombat and Session.get() then
		hud:Show()
		refresh()
		startTicker()
	end
end)

ns.onLook("appraiser", function()
	refresh() -- a HUD that shows is drawn again in the look now set
end)

-- The clock and the item names (they load a moment after the loot) keep the text current: once a second
-- while the HUD shows, and no ticker at all while it is hidden (design 009, Performance budget).
local ticker
local function tick()
	if not hud or not hud:IsShown() then
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
		return
	end
	ns.safely("appraiser", refresh)
end
startTicker = function()
	if not ticker then
		ticker = C_Timer.NewTicker(1, tick)
	end
end

-- The HUD on or off as the player's choice (Settings → Modules): the saved switch, not whether the
-- frame shows now (it is not built before the first loot, and tucked away in combat when so set).
function ns.setHud(on)
	settings().shown = on
	if on then
		show()
	elseif hud then
		hud:Hide()
	end
end

ns.commands.appraise = function()
	-- Shown, or on but tucked away in combat: off. Hidden, or not built before the first loot: on.
	if hud and (hud:IsShown() or (settings().shown and tucked())) then
		ns.setHud(false)
		ns.say("session HUD hidden; /gf hud shows it again.")
	else
		ns.setHud(true)
	end
end

ns.commands.hud = ns.commands.appraise

Session.watch(function(how)
	if how == "loot" or how == "restored" then
		if settings().shown then
			show()
		end
		if how == "restored" then
			return
		end
	end
	refresh()
end)
