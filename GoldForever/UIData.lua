-- Gold Forever: the UI kit's data display: headline numbers, bars, sparklines, an empty state and the
-- table of rows that sorts and pages.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local solid, surface, radius = UI.solid, UI.surface, UI.radius


-- Data display --------------------------------------------------------------------------------------------

-- A headline number: a small caps label, the value, a hint under it.
function UI.StatCard(parent, label, value, hint)
	local f = UI.Panel(parent, { color = Theme.color.surfaceRaised })
	f:SetHeight(76)
	f.label = UI.Text(f, string.upper(label), { size = "xs", medium = true, tone = "muted" })
	f.label:SetPoint("TOPLEFT", 14, -12)
	f.value = UI.Text(f, value, { size = "xl", medium = true })
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
		local decor = Theme.skin.decor
		for i, s in ipairs(newSegments) do
			local t = self.fills[i] or solid(self, "ARTWORK", s.color)
			self.fills[i] = t
			-- The look's own fill for an accent segment; others keep their colour (XP, rested, a share).
			if decor and decor.bar and s.color == Theme.color.accent then
				UI.gradient(t, "HORIZONTAL", decor.bar)
			else
				t:SetVertexColor(Theme.rgb(s.color))
			end
			local w = newMax > 0 and math.min(width - x, width * s.value / newMax) or 0
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", x, 0)
			t:SetPoint("BOTTOMLEFT", x, 0)
			t:SetWidth(math.max(0.001, w))
			t:SetShown(w > 0)
			x = x + w
		end
		-- A spark where the fill ends: the Spark texture, added.
		if decor and decor.spark then
			self.spark = self.spark or self:CreateTexture(nil, "OVERLAY")
			self.spark:SetTexture(Theme.media.spark)
			self.spark:SetBlendMode("ADD")
			self.spark:SetVertexColor(Theme.rgb(Theme.color.accentStrong))
			self.spark:SetSize(14, (self:GetHeight() or 8) + 8)
			self.spark:ClearAllPoints()
			self.spark:SetPoint("CENTER", self, "LEFT", x, 0)
			self.spark:SetShown(x > 0 and x < width)
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

-- What overflowTip gives, as tooltip lines: each column's title, its full text under it.
local function addParts(parts)
	for _, part in ipairs(parts or {}) do
		GameTooltip:AddLine(part.title, Theme.rgb(Theme.color.textMuted))
		for _, text in ipairs(part.lines) do
			GameTooltip:AddLine(text, 1, 1, 1, true)
		end
	end
end

-- An item's own tooltip at the right of `owner`, with `parts` (overflowTip's) under it.
function UI.itemTip(owner, id, parts)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if GameTooltip.SetItemByID then
		GameTooltip:SetItemByID(id)
	else
		GameTooltip:SetHyperlink("item:" .. id)
	end
	addParts(parts)
	GameTooltip:Show()
end

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
	-- Its height from the start: set only later, in its first size change, what is anchored below it
	-- (Remove, Edit lists, the Sell box, the craft queue's buttons) was now and then never placed and not
	-- drawn until the panel was shown again (manual test run 001).
	t:SetHeight(ROW + 2 + t.size * ROW + 24)
	local saved = opts.sort and UI.layout.sortColumn(columns, opts.sort)
	if saved then
		t.sortColumn, t.sortDescending = saved, opts.sort.descending
	end
	t.header = CreateFrame("Frame", nil, t)
	t.header:SetPoint("TOPLEFT", 1, -1)
	t.header:SetPoint("TOPRIGHT", -1, -1)
	t.header:SetHeight(ROW + 2)
	-- The header follows the table's rounded top; its bottom corners stay square against the rows.
	t.header.bg = surface(t.header, Theme.color.surfaceRaised, 1, nil, math.max(0, radius("card") - 1), { BOTTOMLEFT = true, BOTTOMRIGHT = true })
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
				opts.sort.column, opts.sort.key, opts.sort.descending = i, c.key, t.sortDescending
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
		-- Alternate rows shaded on the web; the classic look lights a row with the quest log's highlight.
		l.bg = solid(l, "BACKGROUND", Theme.color.surfaceHover, n % 2 == 0 and Theme.skin.radius and 0.45 or 0)
		l.bg:SetAllPoints()
		if Theme.skin.highlight then
			l.hover = l:CreateTexture(nil, "HIGHLIGHT")
			l.hover:SetTexture(Theme.skin.highlight)
			l.hover:SetBlendMode("ADD")
		else
			l.hover = solid(l, "HIGHLIGHT", Theme.color.accent, 0.08)
		end
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
			-- opts.itemId(row): the row's item, whose own tooltip shows, the cut cells under it (manual test
			-- run 001: hovering an item should show it).
			local id = opts.itemId and opts.itemId(self.row)
			if id and GameTooltip then
				UI.itemTip(self, id, tip)
				return
			end
			if #tip == 0 or not GameTooltip then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			addParts(tip)
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

	-- New rows from page 1, or with keepPage on the page shown (a refresh while reading, as a click on a
	-- row or a ticker does; past the end it is the last page).
	-- The rows in order, kept until the rows or the order change: a wheel tick or a resize only pages
	-- (review C-11). New rows are sorted again, even in the same table.
	local sorted = {}
	function t:SetRows(rows, keepPage)
		sorted.all = nil
		self.all = rows or {}
		if not keepPage then
			self.page = 1
		end
		self:Refresh()
	end

	function t:Refresh()
		local widths = UI.layout.columnWidths(self.columns, (self:GetWidth() or 400) - 2)
		-- The sorted column in the accent (game fonts may lack arrow glyphs); the footer says which way.
		for i, h in ipairs(self.heads) do
			cellPoints(h, i, widths)
			h.text:SetTextColor(Theme.rgb(self.sortColumn == i and Theme.color.accent or Theme.color.textMuted))
		end
		local rows = self.all
		if self.sortColumn then
			if sorted.all ~= self.all or sorted.column ~= self.sortColumn or sorted.descending ~= self.sortDescending then
				sorted.rows = UI.layout.sortRows(self.all, self.columns[self.sortColumn], self.sortDescending)
				sorted.all, sorted.column, sorted.descending = self.all, self.sortColumn, self.sortDescending
			end
			rows = sorted.rows
		end
		local shown = UI.layout.page(rows, self.page, self.size)
		self.page = shown.page
		for n = 1, math.max(#self.lines, #shown.rows) do
			local l = line(n)
			local row = shown.rows[n]
			l.row = row
			l:SetShown(row ~= nil)
			-- The chosen row (opts.isSelected) lit in the accent's soft shade.
			if row and opts.isSelected and opts.isSelected(row) then
				l.bg:SetVertexColor(Theme.rgb(Theme.color.accentSoft))
				l.bg:SetAlpha(1)
			else
				l.bg:SetVertexColor(Theme.rgb(Theme.color.surfaceHover))
				l.bg:SetAlpha(n % 2 == 0 and Theme.skin.radius and 0.45 or 0)
			end
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
