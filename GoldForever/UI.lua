-- Gold Forever: the in-game UI kit. The web app's components (frontend/src/design-system) in the
-- game's own frames, styled by Theme.lua: flat ink surfaces, 1-pixel borders, one gold accent,
-- text at three levels, everything on the pixel grid. Plain frames only (no secure templates), so
-- every window can open in combat; nothing here reads a value the client keeps secret.
--
-- Pure helpers (ns.UI.layout) carry the arithmetic, so it is tested without the client.

local _, ns = ...
local Theme = ns.Theme

local UI = { layout = {} }
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"
-- A condensed sans every client has; a bundled font can replace it in one place.
local FONT = "Fonts\\ARIALN.TTF"

-- Layout: pure ---------------------------------------------------------------------------------------

-- Column widths for a table `total` pixels wide: fixed `width`s as given, the rest shared by the
-- columns with `flex` (a weight, 1 when neither is set), at least `min` each.
function UI.layout.columnWidths(columns, total)
	local fixed, weight = 0, 0
	for _, c in ipairs(columns) do
		if c.width then
			fixed = fixed + c.width
		else
			weight = weight + (c.flex or 1)
		end
	end
	local spare = math.max(0, total - fixed)
	local widths = {}
	for i, c in ipairs(columns) do
		widths[i] = c.width or math.max(c.min or 40, math.floor(spare * (c.flex or 1) / math.max(weight, 1)))
	end
	return widths
end

-- Rows sorted by a column's `sort` value (or its key), descending when asked; ties keep their order.
function UI.layout.sortRows(rows, column, descending)
	local value = column.sort or function(row)
		return row[column.key]
	end
	local indexed = {}
	for i, row in ipairs(rows) do
		indexed[i] = { row = row, i = i, v = value(row) }
	end
	table.sort(indexed, function(a, b)
		if a.v == b.v or a.v == nil or b.v == nil then
			if (a.v == nil) ~= (b.v == nil) then
				return b.v == nil -- unknown last, either way
			end
			return a.i < b.i
		end
		if descending then
			return a.v > b.v
		end
		return a.v < b.v
	end)
	local out = {}
	for i, x in ipairs(indexed) do
		out[i] = x.row
	end
	return out
end

-- One page of rows: { rows, page, pages }, the page held inside 1…pages.
function UI.layout.page(rows, page, size)
	local pages = math.max(1, math.ceil(#rows / size))
	page = math.min(math.max(1, page or 1), pages)
	local out = {}
	for i = (page - 1) * size + 1, math.min(#rows, page * size) do
		out[#out + 1] = rows[i]
	end
	return { rows = out, page = page, pages = pages }
end

-- Coins as coloured text: "12g 4s 50c" with the game's coin colours, the larger units only when
-- there are any (and "gold" precision drops silver and copper above a gold).
function UI.layout.money(copper, precision)
	copper = math.floor((copper or 0) + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local function coin(n, unit, hex)
		return Theme.escape(hex) .. n .. unit .. "|r"
	end
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = coin(g, "g", Theme.color.gold)
	end
	if precision ~= "gold" or g == 0 then
		if s > 0 or g > 0 then
			parts[#parts + 1] = coin(s, "s", Theme.color.silver)
		end
		parts[#parts + 1] = coin(c, "c", Theme.color.copper)
	end
	return sign .. table.concat(parts, " ")
end

-- Money in a table cell: a faint dash for nothing, so rows of "0c" don't drown the amounts.
function UI.layout.amount(copper, precision)
	if math.floor(math.abs(copper or 0) + 0.5) == 0 then
		return Theme.escape(Theme.color.textFaint) .. "—|r"
	end
	return UI.layout.money(copper, precision)
end

-- What a row's tooltip shows for the cells too narrow for their text: each column's title and its
-- full text, or the lines its `tooltip(row)` gives (a list reads better than a clipped sentence).
function UI.layout.overflowTip(columns, row, clipped)
	local out = {}
	for i, c in ipairs(columns) do
		if clipped[i] then
			local lines = c.tooltip and c.tooltip(row) or { c.text and c.text(row) or tostring(row[c.key] or "") }
			out[#out + 1] = { title = c.title, lines = lines }
		end
	end
	return out
end

-- Pixels -------------------------------------------------------------------------------------------

-- One physical pixel in UI units: 1-pixel lines stay 1 pixel at any UI scale.
function UI.pixel()
	local _, height = GetPhysicalScreenSize and GetPhysicalScreenSize()
	local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if not height or height == 0 or not scale or scale == 0 then
		return 1
	end
	return 768 / height / scale
end

-- Drawing ------------------------------------------------------------------------------------------

local function solid(parent, layer, hex, alpha)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	local r, g, b = Theme.rgb(hex)
	t:SetVertexColor(r, g, b, alpha or 1)
	return t
end
UI.solid = solid

-- A 1-pixel border inside a frame's edges, in four textures.
function UI.border(frame, hex, alpha)
	local px = UI.pixel()
	local edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = solid(frame, "BORDER", hex or Theme.color.border, alpha)
		if side == "TOP" or side == "BOTTOM" then
			t:SetPoint(side .. "LEFT")
			t:SetPoint(side .. "RIGHT")
			t:SetHeight(px)
		else
			t:SetPoint("TOP" .. side)
			t:SetPoint("BOTTOM" .. side)
			t:SetWidth(px)
		end
		edges[side] = t
	end
	frame.edges = edges
	return edges
end

-- A flat panel: a surface colour with a border.
function UI.Panel(parent, opts)
	opts = opts or {}
	local f = CreateFrame("Frame", opts.name, parent)
	f.bg = solid(f, "BACKGROUND", opts.color or Theme.color.surface, opts.alpha)
	f.bg:SetAllPoints()
	if opts.border ~= false then
		UI.border(f, opts.borderColor)
	end
	return f
end

-- Text -----------------------------------------------------------------------------------------------

-- Text at a size from Theme.text and a tone: "text" (default), "muted", "faint", "accent", or a hex.
function UI.Text(parent, text, opts)
	opts = opts or {}
	local fs = parent:CreateFontString(nil, "OVERLAY")
	fs:SetFont(FONT, Theme.text[opts.size or "md"] or Theme.text.md, opts.outline and "OUTLINE" or "")
	fs:SetShadowOffset(1, -1)
	fs:SetShadowColor(0, 0, 0, 0.6)
	local tones = { text = Theme.color.text, muted = Theme.color.textMuted, faint = Theme.color.textFaint, accent = Theme.color.accent }
	fs:SetTextColor(Theme.rgb(tones[opts.tone or "text"] or opts.tone))
	fs:SetJustifyH(opts.align or "LEFT")
	fs:SetWordWrap(opts.wrap or false)
	if text then
		fs:SetText(text)
	end
	return fs
end

-- Controls ---------------------------------------------------------------------------------------------

-- A flat button: `primary` (gold, dark text), `ghost` (border only) or the default (raised surface).
-- Hover lifts it a little; the colours stay the theme's.
function UI.Button(parent, label, onClick, opts)
	opts = opts or {}
	local b = CreateFrame("Button", nil, parent)
	b:SetHeight(opts.height or 24)
	local kind = opts.kind or "default"
	local bgHex = kind == "primary" and Theme.color.accent or Theme.color.surfaceRaised
	b.bg = solid(b, "BACKGROUND", bgHex, kind == "ghost" and 0 or 1)
	b.bg:SetAllPoints()
	UI.border(b, kind == "primary" and Theme.color.accentStrong or Theme.color.borderStrong)
	b.label = UI.Text(b, label, { size = "sm", tone = kind == "primary" and Theme.color.accentContrast or "text", align = "CENTER" })
	b.label:SetPoint("CENTER")
	b:SetWidth(opts.width or math.max(60, (b.label:GetStringWidth() or 40) + 24))
	b:SetScript("OnEnter", function(self)
		self.bg:SetAlpha(kind == "ghost" and 0.15 or 0.85)
	end)
	b:SetScript("OnLeave", function(self)
		self.bg:SetAlpha(1)
		if kind == "ghost" then
			self.bg:SetAlpha(0)
		end
	end)
	if onClick then
		b:SetScript("OnClick", onClick)
	end
	return b
end

-- A small rounded-looking label: a tone's soft background and its colour as text.
function UI.Badge(parent, text, hex)
	local f = CreateFrame("Frame", nil, parent)
	f.bg = solid(f, "BACKGROUND", hex or Theme.color.accent, 0.18)
	f.bg:SetAllPoints()
	f.text = UI.Text(f, text, { size = "xs", tone = hex or Theme.color.accent, align = "CENTER" })
	f.text:SetPoint("CENTER")
	f:SetSize((f.text:GetStringWidth() or 30) + 12, 16)
	return f
end

-- A row of tabs with an accent underline on the chosen one; onSelect(key) when one is clicked.
function UI.TabBar(parent, tabs, onSelect)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(28)
	bar.line = solid(bar, "BORDER", Theme.color.border)
	bar.line:SetPoint("BOTTOMLEFT")
	bar.line:SetPoint("BOTTOMRIGHT")
	bar.line:SetHeight(UI.pixel())
	bar.buttons = {}
	local x = 0
	for i, tab in ipairs(tabs) do
		local b = CreateFrame("Button", nil, bar)
		b.key = tab.key
		b.label = UI.Text(b, tab.label, { size = "md", tone = "muted" })
		b.label:SetPoint("CENTER", 0, 1)
		local w = (b.label:GetStringWidth() or 50) + 20
		b:SetSize(w, 28)
		b:SetPoint("BOTTOMLEFT", x, 0)
		x = x + w
		b.underline = solid(b, "OVERLAY", Theme.color.accent)
		b.underline:SetPoint("BOTTOMLEFT")
		b.underline:SetPoint("BOTTOMRIGHT")
		b.underline:SetHeight(2)
		b:SetScript("OnClick", function()
			bar:Select(tab.key)
			if onSelect then
				onSelect(tab.key)
			end
		end)
		bar.buttons[i] = b
	end
	function bar:Select(key)
		for _, b in ipairs(self.buttons) do
			local on = b.key == key
			b.underline:SetShown(on)
			b.label:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
		end
		self.selected = key
	end
	if tabs[1] then
		bar:Select(tabs[1].key)
	end
	return bar
end

-- A search field with a placeholder; onChange(text) as it is typed.
function UI.SearchBox(parent, placeholder, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetHeight(24)
	box:SetFont(FONT, Theme.text.md, "")
	box:SetTextColor(Theme.rgb(Theme.color.text))
	box:SetTextInsets(8, 8, 0, 0)
	box.bg = solid(box, "BACKGROUND", Theme.color.surfaceSunken)
	box.bg:SetAllPoints()
	UI.border(box, Theme.color.borderStrong)
	box.hint = UI.Text(box, placeholder, { tone = "faint" })
	box.hint:SetPoint("LEFT", 8, 0)
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.hint:SetShown(text == "")
		if onChange then
			onChange(text)
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.edges.TOP:SetVertexColor(Theme.rgb(Theme.color.accent))
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self.edges.TOP:SetVertexColor(Theme.rgb(Theme.color.borderStrong))
	end)
	return box
end

-- Data display --------------------------------------------------------------------------------------------

-- A headline number: a small caps label, the value, a hint under it.
function UI.StatCard(parent, label, value, hint)
	local f = UI.Panel(parent, { color = Theme.color.surfaceRaised })
	f:SetHeight(72)
	f.label = UI.Text(f, string.upper(label), { size = "xs", tone = "muted" })
	f.label:SetPoint("TOPLEFT", 12, -10)
	f.value = UI.Text(f, value, { size = "xl" })
	f.value:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -6)
	f.hint = UI.Text(f, hint, { size = "xs", tone = "faint" })
	f.hint:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -4)
	function f:Set(newValue, newHint)
		self.value:SetText(newValue)
		self.hint:SetText(newHint or "")
	end
	return f
end

-- A bar of stacked segments ({ value, color }), out of `max`: XP, rested, a share of something.
function UI.Bar(parent, max, segments, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(height or 8)
	f.track = solid(f, "BACKGROUND", Theme.color.surfaceSunken)
	f.track:SetAllPoints()
	f.fills = {}
	function f:Set(newMax, newSegments)
		self.max, self.segments = newMax, newSegments
		for _, t in ipairs(self.fills) do
			t:Hide()
		end
		local width = self:GetWidth() or 0
		local x = 0
		for i, s in ipairs(newSegments) do
			local t = self.fills[i] or solid(self, "ARTWORK", s.color)
			self.fills[i] = t
			t:SetVertexColor(Theme.rgb(s.color))
			local w = newMax > 0 and math.min(width - x, width * s.value / newMax) or 0
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", x, 0)
			t:SetPoint("BOTTOMLEFT", x, 0)
			t:SetWidth(math.max(0.001, w))
			t:SetShown(w > 0)
			x = x + w
		end
	end
	f:SetScript("OnSizeChanged", function(self)
		self:Set(self.max or max, self.segments or segments)
	end)
	f.max, f.segments = max, segments
	return f
end

-- A sparkline: values as a line across the frame, lowest at the bottom.
function UI.Sparkline(parent, values, hex)
	local f = CreateFrame("Frame", nil, parent)
	f.lines = {}
	function f:Set(newValues)
		self.values = newValues
		for _, l in ipairs(self.lines) do
			l:Hide()
		end
		local w, h = self:GetWidth() or 0, self:GetHeight() or 0
		if #newValues < 2 or w == 0 then
			return
		end
		local lo, hi = math.huge, -math.huge
		for _, v in ipairs(newValues) do
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		local span = hi - lo
		local function y(v)
			return span == 0 and h / 2 or (v - lo) / span * h
		end
		for i = 2, #newValues do
			local l = self.lines[i - 1] or self:CreateLine(nil, "ARTWORK")
			self.lines[i - 1] = l
			l:SetColorTexture(Theme.rgb(hex or Theme.color.chart1))
			l:SetThickness(2)
			l:SetStartPoint("BOTTOMLEFT", (i - 2) / (#newValues - 1) * w, y(newValues[i - 1]))
			l:SetEndPoint("BOTTOMLEFT", (i - 1) / (#newValues - 1) * w, y(newValues[i]))
			l:Show()
		end
	end
	f:SetScript("OnSizeChanged", function(self)
		self:Set(self.values or values)
	end)
	f.values = values
	return f
end

-- When there is nothing to show: a title and a line saying what to do.
function UI.EmptyState(parent, title, body)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(80)
	f.title = UI.Text(f, title, { size = "lg", align = "CENTER" })
	f.title:SetPoint("TOP", 0, -16)
	f.body = UI.Text(f, body, { size = "sm", tone = "muted", align = "CENTER", wrap = true })
	f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
	f.body:SetWidth(360)
	return f
end

-- Table ----------------------------------------------------------------------------------------------------

-- Whether a cell's text is cut short: the client's own answer where it has one, else the text's
-- full width against the cell's.
local function clipped(cell)
	if cell.IsTruncated then
		local truncated = cell:IsTruncated()
		if type(truncated) == "boolean" then
			return truncated
		end
	end
	local full = cell.GetUnboundedStringWidth and cell:GetUnboundedStringWidth()
	if type(full) ~= "number" then
		full = cell:GetStringWidth()
	end
	local width = cell:GetWidth()
	return type(full) == "number" and type(width) == "number" and full > width + 1
end

-- A table of rows: columns { key, title, width | flex, align, text = function(row), color = function(row),
-- sort = function(row), tooltip = function(row) -> lines }. Headers sort (click again to reverse), rows
-- alternate and light up under the pointer, the wheel and the page arrows page; a cell cut short shows
-- in full in the row's tooltip. opts.sort = { column, descending } is the starting order and is kept
-- up to date, so a saved table remembers it. Row frames are made once per visible line and reused.
function UI.Table(parent, columns, opts)
	opts = opts or {}
	local ROW = opts.rowHeight or 22
	local t = UI.Panel(parent, { color = Theme.color.surface })
	t.columns, t.all, t.page, t.size = columns, {}, 1, opts.pageSize or 12
	if opts.sort and columns[opts.sort.column] then
		t.sortColumn, t.sortDescending = opts.sort.column, opts.sort.descending
	end
	t.header = CreateFrame("Frame", nil, t)
	t.header:SetPoint("TOPLEFT", 1, -1)
	t.header:SetPoint("TOPRIGHT", -1, -1)
	t.header:SetHeight(ROW + 2)
	t.header.bg = solid(t.header, "BACKGROUND", Theme.color.surfaceRaised)
	t.header.bg:SetAllPoints()
	t.heads, t.lines = {}, {}

	local function cellPoints(cell, i, widths)
		local x = 0
		for j = 1, i - 1 do
			x = x + widths[j]
		end
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", x + 8, 0)
		cell:SetWidth(math.max(1, widths[i] - 16))
	end

	for i, c in ipairs(columns) do
		local h = CreateFrame("Button", nil, t.header)
		h:SetHeight(ROW)
		h.text = UI.Text(h, string.upper(c.title), { size = "xs", tone = "muted", align = c.align or "LEFT" })
		h.text:SetAllPoints()
		h:SetScript("OnClick", function()
			t.sortDescending = t.sortColumn == i and not t.sortDescending or (t.sortColumn ~= i and c.align == "RIGHT")
			t.sortColumn = i
			if opts.sort then
				opts.sort.column, opts.sort.descending = i, t.sortDescending
			end
			t.page = 1
			t:Refresh()
		end)
		t.heads[i] = h
	end

	t.footer = UI.Text(t, "", { size = "xs", tone = "faint", align = "RIGHT" })
	t.footer:SetPoint("BOTTOMRIGHT", -10, 6)
	t:EnableMouseWheel(true)
	t:SetScript("OnMouseWheel", function(self, delta)
		self.page = self.page - delta
		self:Refresh()
	end)

	local function line(n)
		local l = t.lines[n]
		if l then
			return l
		end
		l = CreateFrame("Button", nil, t)
		l:SetHeight(ROW)
		l:SetPoint("TOPLEFT", t.header, "BOTTOMLEFT", 0, -(n - 1) * ROW)
		l:SetPoint("TOPRIGHT", t.header, "BOTTOMRIGHT", 0, -(n - 1) * ROW)
		l.bg = solid(l, "BACKGROUND", n % 2 == 0 and Theme.color.surfaceHover or Theme.color.surface, n % 2 == 0 and 0.45 or 0)
		l.bg:SetAllPoints()
		l.hover = solid(l, "HIGHLIGHT", Theme.color.accent, 0.08)
		l.hover:SetAllPoints()
		l.cells = {}
		for i, c in ipairs(columns) do
			l.cells[i] = UI.Text(l, "", { size = "sm", align = c.align or "LEFT" })
		end
		l:SetScript("OnClick", function(self)
			if opts.onRowClick and self.row then
				opts.onRowClick(self.row)
			end
		end)
		l:SetScript("OnEnter", function(self)
			if not self.row then
				return
			end
			if opts.onRowEnter then
				opts.onRowEnter(self, self.row)
				return
			end
			local cut = {}
			for i, cell in ipairs(self.cells) do
				cut[i] = clipped(cell)
			end
			local tip = UI.layout.overflowTip(columns, self.row, cut)
			if #tip == 0 or not GameTooltip then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			for _, part in ipairs(tip) do
				GameTooltip:AddLine(part.title, Theme.rgb(Theme.color.textMuted))
				for _, text in ipairs(part.lines) do
					GameTooltip:AddLine(text, 1, 1, 1, true)
				end
			end
			GameTooltip:Show()
		end)
		l:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		t.lines[n] = l
		return l
	end

	function t:SetRows(rows)
		self.all = rows or {}
		self.page = 1
		self:Refresh()
	end

	function t:Refresh()
		local widths = UI.layout.columnWidths(self.columns, (self:GetWidth() or 400) - 2)
		-- The sorted column in the accent (game fonts may lack arrow glyphs); the footer says which way.
		for i, h in ipairs(self.heads) do
			cellPoints(h, i, widths)
			h.text:SetTextColor(Theme.rgb(self.sortColumn == i and Theme.color.accent or Theme.color.textMuted))
		end
		local rows = self.sortColumn and UI.layout.sortRows(self.all, self.columns[self.sortColumn], self.sortDescending) or self.all
		local shown = UI.layout.page(rows, self.page, self.size)
		self.page = shown.page
		for n = 1, math.max(#self.lines, #shown.rows) do
			local l = line(n)
			local row = shown.rows[n]
			l.row = row
			l:SetShown(row ~= nil)
			if row then
				for i, c in ipairs(self.columns) do
					local cell = l.cells[i]
					cellPoints(cell, i, widths)
					cell:SetText(c.text and c.text(row) or tostring(row[c.key] or ""))
					cell:SetTextColor(Theme.rgb(c.color and c.color(row) or Theme.color.text))
				end
			end
		end
		local sorted = self.sortColumn and string.format(" · by %s, %s first", string.lower(self.columns[self.sortColumn].title),
			self.sortDescending and "highest" or "lowest") or ""
		self.footer:SetText(#rows == 0 and (opts.empty or "Nothing yet.") or
			((shown.pages > 1 and string.format("%d–%d of %d · page %d of %d (wheel to page)", (shown.page - 1) * self.size + 1,
				math.min(#rows, shown.page * self.size), #rows, shown.page, shown.pages) or string.format("%d rows", #rows)) .. sorted))
		self:SetHeight(ROW + 2 + self.size * ROW + 24)
	end

	t:SetScript("OnSizeChanged", function(self)
		self:Refresh()
	end)
	return t
end

-- Window ------------------------------------------------------------------------------------------------------

-- The main window: a title bar to drag it by, a close button, a sidebar of pages and a content
-- area; Escape closes it. pages = { { key, label, build = function(content) } }: a page is built the
-- first time it is shown. Its position is kept in `store`.
function UI.Window(name, title, pages, store, opts)
	opts = opts or {}
	local w = UI.Panel(UIParent, { name = name, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	w:SetSize(opts.width or 860, opts.height or 560)
	w:SetFrameStrata("HIGH")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	if store.point then
		w:SetPoint(store.point[1], UIParent, store.point[2], store.point[3], store.point[4])
	else
		w:SetPoint("CENTER")
	end
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end

	local bar = CreateFrame("Frame", nil, w)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(36)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		w:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		w:StopMovingOrSizing()
		local p, _, rel, x, y = w:GetPoint()
		store.point = { p, rel, x, y }
	end)
	bar.bg = solid(bar, "BACKGROUND", Theme.color.surface)
	bar.bg:SetAllPoints()
	local mark = solid(bar, "ARTWORK", Theme.color.accent)
	mark:SetSize(10, 10)
	mark:SetPoint("LEFT", 14, 0)
	w.title = UI.Text(bar, title, { size = "lg" })
	w.title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
	local close = UI.Button(bar, "×", function()
		w:Hide()
	end, { kind = "ghost", width = 28, height = 24 })
	close:SetPoint("RIGHT", -8, 0)

	local side = CreateFrame("Frame", nil, w)
	side:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
	side:SetPoint("BOTTOMLEFT", 1, 1)
	side:SetWidth(opts.sidebar or 170)
	side.bg = solid(side, "BACKGROUND", Theme.color.surface)
	side.bg:SetAllPoints()
	local divider = solid(side, "BORDER", Theme.color.border)
	divider:SetPoint("TOPRIGHT")
	divider:SetPoint("BOTTOMRIGHT")
	divider:SetWidth(UI.pixel())

	local content = CreateFrame("Frame", nil, w)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 16, -16)
	content:SetPoint("BOTTOMRIGHT", -16, 16)
	w.content = content

	w.pages, w.items = {}, {}
	function w:SelectPage(key)
		for _, p in pairs(self.pages) do
			p:Hide()
		end
		for _, item in ipairs(self.items) do
			local on = item.key == key
			item.bg:SetAlpha(on and 1 or 0)
			item.label:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
		end
		local page = self.pages[key]
		if not page then
			for _, p in ipairs(pages) do
				if p.key == key then
					page = CreateFrame("Frame", nil, content)
					page:SetAllPoints()
					ns.safely("ui " .. key, p.build, page)
					self.pages[key] = page
				end
			end
		end
		if page then
			page:Show()
			if page.Refresh then
				ns.safely("ui " .. key, page.Refresh, page)
			end
		end
		store.page = key
	end
	for i, p in ipairs(pages) do
		local item = CreateFrame("Button", nil, side)
		item.key = p.key
		item:SetHeight(28)
		item:SetPoint("TOPLEFT", 8, -8 - (i - 1) * 30)
		item:SetPoint("TOPRIGHT", -8, -8 - (i - 1) * 30)
		item.bg = solid(item, "BACKGROUND", Theme.color.accentSoft)
		item.bg:SetAllPoints()
		item.label = UI.Text(item, p.label, { size = "md", tone = "muted" })
		item.label:SetPoint("LEFT", 10, 0)
		item:SetScript("OnClick", function()
			w:SelectPage(p.key)
		end)
		w.items[i] = item
	end
	w:SelectPage(store.page or (pages[1] and pages[1].key))
	return w
end
