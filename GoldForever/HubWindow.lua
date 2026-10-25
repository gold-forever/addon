-- Gold Forever: the hub's window (UI.Window): the sidebar of pages, the page header over the look's
-- art, the footer, and the addon's own footprint at the sidebar's foot. Hub.lua makes one per look.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local box, solid, surface, radius = UI.box, UI.solid, UI.surface, UI.radius

local WHITE = "Interface\\Buttons\\WHITE8X8"


-- What the client says about the addon's memory and recent CPU time, when it says anything.
-- `fresh`: measure memory anew. UpdateAddOnMemoryUsage walks every addon loaded, which a big set of
-- addons makes slow enough for the client to stop it (manual test run 001: "exceeded its execution time
-- limit", about every 10 s while the hub was open); so only when asked, the last figure kept between.
local lastKb
local function footprint(addon, fresh)
	local kb, ms
	if fresh and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		lastKb = GetAddOnMemoryUsage(addon)
	end
	kb = lastKb
	if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
		ms = C_AddOnProfiler.GetAddOnMetric(addon, Enum.AddOnProfilerMetric.RecentAverageTime)
	end
	return kb and UI.layout.footprint(kb, ms) or ""
end

local SIDE, HERO, FOOT, PAD = 236, 118, 56, 28

-- The main window, the hub (design 009, the playground's Hub v2): a sidebar with the brand, a search and
-- the pages in groups with an icon each, a large page title over the look's art, the page, and a footer
-- with Reload UI and Close; the addon's memory and CPU at the sidebar's foot. Drag it by any bare part;
-- Escape closes it. pages = { { key, label, icon, group, title, lede, build = function(content) } }: a
-- page is built the first time it is shown. Its position, page and scale are kept in `store`.
-- opts: width, height, version, look (the look's label for the footer), onReload.
function UI.Window(name, title, pages, store, opts)
	opts = opts or {}
	local skin = Theme.skin
	local web = skin.radius ~= nil
	local W, H = opts.width or 1000, opts.height or 660
	local w = UI.Panel(UIParent, { name = name, window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	w:SetSize(W, H)
	w:SetFrameStrata("HIGH")
	-- Over the auction panel and the other HIGH frames when it opens or is clicked (manual test run 001:
	-- Rule › opened it under the panel).
	w:SetToplevel(true)
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rel, x, y = self:GetPoint()
		store.point = { p, rel, x, y }
	end)
	-- Back to where the player left it, at the scale they set (the store is shared by every look's window).
	function w:Restore()
		self:SetScale(store.scale or 1)
		self:ClearAllPoints()
		if store.point then
			self:SetPoint(store.point[1], UIParent, store.point[2], store.point[3], store.point[4])
		else
			self:SetPoint("CENTER")
		end
	end
	w:Restore()
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end
	-- Inside the edge: the web's 1-pixel rim, or the dialog border's width.
	local inset = web and 1 or 5
	local decor = skin.decor

	-- The sidebar ----
	local side = CreateFrame("Frame", nil, w)
	side:SetPoint("TOPLEFT", inset, -inset)
	side:SetPoint("BOTTOMLEFT", inset, inset)
	side:SetWidth(SIDE - inset)
	if web then
		side.bg = surface(side, Theme.color.surface, decor and 0.55 or 1, nil, radius("window") - 1, { TOPRIGHT = true, BOTTOMRIGHT = true })
	else
		side.bg = solid(side, "BACKGROUND", "#000000", 0.3)
		side.bg:SetAllPoints()
	end
	local divider = solid(side, "BORDER", Theme.color.border)
	divider:SetPoint("TOPRIGHT")
	divider:SetPoint("BOTTOMRIGHT")
	divider:SetWidth(UI.pixel())

	local emblem = CreateFrame("Frame", nil, side)
	emblem:SetSize(44, 44)
	emblem:SetPoint("TOPLEFT", 20, -22)
	surface(emblem, Theme.color.accentSoft, 1, Theme.color.accent, radius("card"))
	local coin = UI.Icon(emblem, "coins", 24, "accent")
	coin:SetPoint("CENTER")
	if decor and decor.mark == "rune" then
		local glow = emblem:CreateTexture(nil, "ARTWORK", nil, -1)
		glow:SetTexture(Theme.media.glow)
		glow:SetBlendMode("ADD")
		glow:SetPoint("TOPLEFT", -10, 10)
		glow:SetPoint("BOTTOMRIGHT", 10, -10)
		local r, g, b = Theme.rgb(Theme.color.accent)
		glow:SetVertexColor(r, g, b, 0.35)
	end
	w.title = UI.Text(side, skin.titleCaps and string.upper(title) or title, { size = "xl", medium = true, tone = web and "text" or "accent" })
	w.title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 12, -2)
	local tagline = UI.Text(side, "FOR WOW: FOREVER", { size = "xs", tone = "faint" })
	tagline:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 1, -5)

	local nav = CreateFrame("Frame", nil, side)
	nav:SetPoint("TOPLEFT", 8, -130)
	nav:SetPoint("BOTTOMRIGHT", -8, FOOT + 8)
	local search = UI.SearchBox(side, "Search pages…", function(text)
		if w.Filter then
			w:Filter(text)
		end
	end)
	search:SetPoint("TOPLEFT", 18, -88)
	search:SetWidth(SIDE - 36)

	local foot = solid(side, "BORDER", Theme.color.border)
	foot:SetPoint("BOTTOMLEFT", 0, FOOT)
	foot:SetPoint("BOTTOMRIGHT", 0, FOOT)
	foot:SetHeight(UI.pixel())
	local version = UI.Text(side, opts.version and ("v" .. opts.version) or "", { size = "xs", tone = "faint" })
	version:SetPoint("BOTTOMLEFT", 20, 32)
	local perf = UI.Text(side, "", { size = "xs", tone = "faint" })
	perf:SetPoint("BOTTOMLEFT", 20, 14)
	-- Memory when the window opens and when the line is clicked; the CPU (cheap to ask) every ten
	-- seconds while the window shows, and never while it is closed.
	local ticker
	local function measure(fresh)
		perf:SetText(footprint(opts.addon or "GoldForever", fresh))
	end
	local perfButton = CreateFrame("Button", nil, side)
	perfButton:SetAllPoints(perf)
	perfButton:SetScript("OnClick", function()
		ns.safely("footprint", measure, true)
	end)
	local function started()
		ns.safely("footprint", measure, true)
		if C_Timer and C_Timer.NewTicker and not ticker then
			ticker = C_Timer.NewTicker(10, function()
				ns.safely("footprint", measure, false)
			end)
		end
	end
	-- Opened again: the page in view shows what changed while it was closed (manual test run 001).
	w:SetScript("OnShow", function()
		w:Raise()
		started()
		local page = w.pages and w.pages[store.page]
		if page and page.Refresh then
			ns.safely("ui " .. store.page, page.Refresh, page)
		end
	end)
	w:SetScript("OnHide", function()
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
	end)

	-- The page header over the look's art ----
	local hero = CreateFrame("Frame", nil, w)
	hero:SetPoint("TOPLEFT", SIDE, -inset)
	hero:SetPoint("TOPRIGHT", -inset, -inset)
	hero:SetHeight(HERO)
	UI.HeroArt(hero, W - SIDE - inset, HERO)
	-- The title and its line in a frame over the art's.
	local words = CreateFrame("Frame", nil, hero)
	words:SetAllPoints()
	words:SetFrameLevel(hero:GetFrameLevel() + 2)
	w.pageTitle = UI.Text(words, "", { size = "xxl", medium = true })
	w.pageTitle:SetPoint("TOPLEFT", PAD, -30)
	w.pageLede = UI.Text(words, "", { size = "sm", tone = "muted", wrap = true })
	w.pageLede:SetPoint("TOPLEFT", PAD, -72)
	w.pageLede:SetWidth(W - SIDE - 160)
	local rule = solid(w, "BORDER", Theme.color.border)
	rule:SetPoint("TOPLEFT", hero, "BOTTOMLEFT")
	rule:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT")
	rule:SetHeight(UI.pixel())
	if decor and decor.rule then
		UI.gradient(rule, "HORIZONTAL", decor.rule)
	end
	-- A light sweeping along the rule: the Spark texture, added, moved by a looping Translation, inside
	-- a strip that clips it to the header's width.
	if decor and decor.shimmer then
		local strip = CreateFrame("Frame", nil, w)
		strip:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, 1)
		strip:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, 1)
		strip:SetHeight(3)
		strip:SetClipsChildren(true)
		local inside = CreateFrame("Frame", nil, strip)
		inside:SetAllPoints()
		local light = inside:CreateTexture(nil, "OVERLAY")
		light:SetTexture(Theme.media.spark)
		light:SetBlendMode("ADD")
		light:SetSize(110, 3)
		light:SetPoint("RIGHT", strip, "LEFT", 0, 0)
		local sweep = light:CreateAnimationGroup()
		sweep:SetLooping("REPEAT")
		local move = sweep:CreateAnimation("Translation")
		move:SetOffset(W - SIDE + 110, 0)
		move:SetDuration(3.2)
		sweep:Play()
		w.shimmer = sweep
	end
	local close
	if skin.closeTemplate then
		close = CreateFrame("Button", nil, w, skin.closeTemplate)
		close:SetPoint("TOPRIGHT", hero, "TOPRIGHT", 2, 2)
	else
		close = UI.Button(w, "", nil, { kind = "ghost", width = 30, height = 30 })
		local x = UI.Icon(close, "x", 16, "muted")
		x:SetPoint("CENTER")
		close:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -14, -14)
	end
	close:SetFrameLevel(hero:GetFrameLevel() + 5)
	close:SetScript("OnClick", function()
		w:Hide()
	end)

	-- The page ----
	local content = CreateFrame("Frame", nil, w)
	content:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", PAD, -20)
	content:SetPoint("BOTTOMRIGHT", -PAD - inset, FOOT + 16)
	w.content = content

	-- The footer ----
	local footRule = solid(w, "BORDER", Theme.color.border)
	footRule:SetPoint("BOTTOMLEFT", SIDE, FOOT)
	footRule:SetPoint("BOTTOMRIGHT", -inset, FOOT)
	footRule:SetHeight(UI.pixel())
	local reload = UI.Button(w, "Reload UI", function()
		if opts.onReload then
			opts.onReload()
		elseif ReloadUI then
			ReloadUI()
		end
	end, { width = 130, height = 30 })
	reload:SetPoint("BOTTOMLEFT", SIDE + PAD, 13)
	local note = UI.Text(w, (opts.look and ("Look: " .. opts.look .. " · ") or "") .. "gold-forever.app", { size = "xs", tone = "faint", align = "CENTER" })
	note:SetPoint("BOTTOM", SIDE / 2, 22)
	local done = UI.Button(w, "Close", function()
		w:Hide()
	end, { kind = "primary", width = 130, height = 30 })
	done:SetPoint("BOTTOMRIGHT", -PAD - inset, 13)

	-- The sidebar's rows: a heading per group, a row per page; the search hides and restacks them.
	w.pages, w.items, w.heads = {}, {}, {}
	local byKey = {}
	for _, p in ipairs(pages) do
		byKey[p.key] = p
		local item = CreateFrame("Button", nil, nav)
		item.key = p.key
		item:SetHeight(32)
		if skin.highlight then
			local t = item:CreateTexture(nil, "BACKGROUND")
			t:SetTexture(skin.highlight)
			t:SetBlendMode("ADD")
			t:SetAllPoints()
			item.bg = box({ t })
		elseif decor and decor.selected then
			-- The accent fading to the right, with a bar at the left edge; shown and hidden together.
			item.bg = surface(item, Theme.color.accentSoft, 1, nil, radius("item"))
			item.bg:SetGradient("HORIZONTAL", decor.selected)
			local edge = item:CreateTexture(nil, "ARTWORK")
			edge:SetTexture(WHITE)
			edge:SetVertexColor(Theme.rgb(Theme.color.accent))
			edge:SetPoint("TOPLEFT")
			edge:SetPoint("BOTTOMLEFT")
			edge:SetWidth(2)
			item.bg.parts.edge = edge
		else
			item.bg = surface(item, Theme.color.accentSoft, 1, nil, radius("item"))
		end
		item.icon = UI.Icon(item, p.icon or "package", 17, "muted")
		item.icon:SetPoint("LEFT", 14, 0)
		item.label = UI.Text(item, p.label, { size = "md", medium = web, tone = "muted" })
		item.label:SetPoint("LEFT", 42, 0)
		item:SetScript("OnClick", function(self)
			w:SelectPage(p.key, self.tab)
		end)
		w.items[#w.items + 1] = item
		if p.group and not w.heads[p.group] then
			local head = CreateFrame("Frame", nil, nav)
			head:SetHeight(28)
			head.text = UI.Text(head, string.upper(p.group), { size = "xs", medium = true, tone = "accent" })
			head.text:SetPoint("BOTTOMLEFT", 12, 6)
			w.heads[p.group] = head
		end
	end
	local empty = UI.Text(nav, "No page matches.", { size = "sm", tone = "faint" })
	empty:SetPoint("TOPLEFT", 12, -8)
	function w:Filter(query)
		for _, item in ipairs(self.items) do
			item:Hide()
		end
		for _, head in pairs(self.heads) do
			head:Hide()
		end
		local y = 0
		local rows = UI.layout.navRows(pages, query)
		for _, row in ipairs(rows) do
			local f = row.head and self.heads[row.head]
			if row.page then
				for _, item in ipairs(self.items) do
					if item.key == row.page.key then
						f = item
						item.tab = row.tab
					end
				end
			end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", 0, -y)
			f:SetPoint("TOPRIGHT", 0, -y)
			f:Show()
			y = y + f:GetHeight()
		end
		empty:SetShown(#rows == 0)
	end

	-- `tab`: the tab to open on a tabbed page (a search that matched it), else the page's last.
	function w:SelectPage(key, tab)
		local def = byKey[key] or pages[1]
		if not def then
			return
		end
		key = def.key
		for _, p in pairs(self.pages) do
			p:Hide()
		end
		for _, item in ipairs(self.items) do
			local on = item.key == key
			item.bg:SetAlpha(on and 1 or 0)
			item.label:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
			item.icon:SetTone(on and "accent" or "muted")
		end
		self.pageTitle:SetText(def.title or def.label)
		self.pageLede:SetText(def.lede or "")
		local page = self.pages[key]
		if not page then
			page = CreateFrame("Frame", nil, content)
			page:SetAllPoints()
			-- A page can name itself more closely once it knows more (whose levelling it shows).
			function page.SetTitle(_, text)
				self.pageTitle:SetText(text)
			end
			page.title = def.title or def.label
			ns.safely("ui " .. key, def.build, page)
			self.pages[key] = page
		end
		page:Show()
		if tab and page.SelectTab then
			page.tab = tab
		end
		if page.Refresh then
			ns.safely("ui " .. key, page.Refresh, page)
		end
		store.page = key
	end
	w:Filter("")
	w:SelectPage(store.page or (pages[1] and pages[1].key))
	-- A new frame is shown already, so OnShow does not come for the first opening.
	if w:IsShown() then
		started()
	end
	return w
end
