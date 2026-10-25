-- Gold Forever: the UI kit's pure layout (ns.UI.layout): the arithmetic the in-game tables, sliders,
-- rounded boxes and the hub's sidebar stand on, tested without the client. It makes ns.UI, which the
-- kit's other files fill: UIDraw, UIControls, UIData, and the hub's window, HubWindow.

local _, ns = ...

local UI = { layout = {} }
ns.UI = UI

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

-- The column a saved order names: by its key, so a column moved keeps the order (review B-42); an
-- order saved before by index alone, by that index. nil when the column is gone.
function UI.layout.sortColumn(columns, saved)
	if saved.key ~= nil then
		for i, c in ipairs(columns) do
			if c.key == saved.key then
				return i
			end
		end
		return nil
	end
	return columns[saved.column or 0] and saved.column or nil
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
-- Text without its colour codes, to show it in one tone (a greyed amount).
function UI.layout.plain(text)
	return (string.gsub(string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

-- A whole number in groups of three, with the client's separator ("3,000,000").
function UI.layout.group(n)
	return ns.Money.group(n)
end

function UI.layout.money(copper, precision)
	return ns.Money.format(copper, "colour", precision)
end

-- Money in a table cell: a faint dash for nothing, so rows of "0c" don't drown the amounts; gold and
-- silver unless told otherwise (manual test run 001: "17g 70s 0c" in Auction sales, "1,425g 0s 0c").
function UI.layout.amount(copper, precision)
	return ns.Money.format(copper, "cell", precision)
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

-- The Round texture's solid middle, a sliver wide enough to stretch without its edge showing.
local MID_LO, MID_HI = 0.49, 0.51

-- Texture coordinates for the nine parts of a rounded box cut from the Round texture (a circle): a
-- rounded corner takes its quarter of the circle, a corner named in `square` the solid middle.
function UI.layout.nineSlice(square)
	square = square or {}
	local function corner(name, l, r, t, b)
		if square[name] then
			return { MID_LO, MID_HI, MID_LO, MID_HI }
		end
		return { l, r, t, b }
	end
	return {
		TOPLEFT = corner("TOPLEFT", 0, 0.5, 0, 0.5),
		TOPRIGHT = corner("TOPRIGHT", 0.5, 1, 0, 0.5),
		BOTTOMLEFT = corner("BOTTOMLEFT", 0, 0.5, 0.5, 1),
		BOTTOMRIGHT = corner("BOTTOMRIGHT", 0.5, 1, 0.5, 1),
		TOP = { MID_LO, MID_HI, 0, 0.5 },
		BOTTOM = { MID_LO, MID_HI, 0.5, 1 },
		LEFT = { 0, 0.5, MID_LO, MID_HI },
		RIGHT = { 0.5, 1, MID_LO, MID_HI },
		CENTER = { MID_LO, MID_HI, MID_LO, MID_HI },
	}
end

-- Which end of a two-colour gradient each of a rounded box's nine slices takes: the slices along the
-- start edge the first colour, along the far edge the second, and the band between them the gradient
-- itself (SetGradient), so a gradient runs across the box unbroken.
function UI.layout.sliceGradient(orientation)
	if orientation == "VERTICAL" then
		return { TOPLEFT = "from", TOP = "from", TOPRIGHT = "from", LEFT = "span", CENTER = "span", RIGHT = "span",
			BOTTOMLEFT = "to", BOTTOM = "to", BOTTOMRIGHT = "to" }
	end
	return { TOPLEFT = "from", LEFT = "from", BOTTOMLEFT = "from", TOP = "span", CENTER = "span", BOTTOM = "span",
		TOPRIGHT = "to", RIGHT = "to", BOTTOMRIGHT = "to" }
end

-- A value a slider stands on: `value` held in min…max and rounded to the nearest step.
function UI.layout.step(value, min, max, step)
	step = step or 1
	local v = min + math.floor((value - min) / step + 0.5) * step
	return math.max(min, math.min(max, v))
end

-- The sidebar's rows for a search: each group's heading, then its pages whose label or title holds the
-- query (any case); a group with none left out. pages = { { key, label, title, group } } in order.
function UI.layout.navRows(pages, query)
	query = string.lower(query or "")
	local rows, group = {}, nil
	for _, p in ipairs(pages) do
		local hay = string.lower((p.label or "") .. " " .. (p.title or ""))
		local found, tab = query == "" or string.find(hay, query, 1, true), nil
		-- Else a tab's name: the page is found, opening on that tab.
		for _, t in ipairs(not found and p.tabs or {}) do
			if not tab and string.find(string.lower(t.label or ""), query, 1, true) then
				found, tab = true, t.key
			end
		end
		if found then
			if p.group and p.group ~= group then
				rows[#rows + 1] = { head = p.group }
			end
			group = p.group
			rows[#rows + 1] = { page = p, tab = tab }
		end
	end
	return rows
end

-- The addon's own footprint as the sidebar shows it: memory in kilobytes, CPU in milliseconds (or nil).
function UI.layout.footprint(kb, ms)
	local text = string.format("Memory %.1f MB", (kb or 0) / 1024)
	if ms then
		text = text .. string.format(" · CPU %.3f ms", ms)
	end
	return text
end
