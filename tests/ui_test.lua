-- UI.lua's layout: column widths, sorting, pages and money, which the in-game tables stand on.

local ns = {}
assert(load(SOURCES["Theme.lua"], "@Theme.lua"))("GoldForever", ns)
assert(load(SOURCES["UI.lua"], "@UI.lua"))("GoldForever", ns)
local L, T = ns.UI.layout, ns.Theme

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

-- Theme: colours as floats and as text escapes.
local r, g, b = T.rgb("#e0ac45")
eq(string.format("%.3f %.3f %.3f", r, g, b), "0.878 0.675 0.271", "accent as floats")
eq(T.escape("#E0AC45"), "|cffe0ac45", "accent as an escape")

-- Column widths: fixed as given, the rest shared by weight, never under the minimum.
local w = L.columnWidths({ { width = 70 }, { flex = 2 }, { flex = 1 }, { width = 100 } }, 470)
eq(w[1], 70, "fixed width")
eq(w[2], 200, "two shares of 300")
eq(w[3], 100, "one share of 300")
eq(w[4], 100, "fixed width at the end")
eq(L.columnWidths({ { width = 300 }, {} }, 200)[2], 40, "a squeezed column keeps its minimum")

-- Sorting: by key or a sort function, either way, unknown last, ties in order.
local rows = { { n = "b", v = 2 }, { n = "a", v = 3 }, { n = "c" }, { n = "d", v = 2 } }
local function names(list)
	local out = {}
	for i, row in ipairs(list) do
		out[i] = row.n
	end
	return table.concat(out)
end
eq(names(L.sortRows(rows, { key = "v" }, false)), "bdac", "ascending, ties kept, unknown last")
eq(names(L.sortRows(rows, { key = "v" }, true)), "abdc", "descending, unknown still last")
eq(names(L.sortRows(rows, { key = "x", sort = function(row) return row.n end }, true)), "dcba", "by a sort function")
eq(names(rows), "bacd", "the rows given are not reordered")

-- Pages: held inside the range.
local many = {}
for i = 1, 23 do
	many[i] = i
end
local p = L.page(many, 3, 10)
eq(#p.rows, 3, "the last page's rows")
eq(p.pages, 3, "pages")
eq(L.page(many, 9, 10).page, 3, "a page past the end is the last")
eq(L.page({}, 1, 10).pages, 1, "no rows is one empty page")

-- Money: coloured coins, the larger only when there are any.
local plain = function(text)
	return (string.gsub(string.gsub(text, "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end
eq(plain(L.money(45)), "45c", "copper alone")
eq(plain(L.money(1484)), "14s 84c", "silver and copper")
eq(plain(L.money(1014420)), "101g 44s 20c", "all three")
eq(plain(L.money(1014420, "gold")), "101g", "gold precision")
eq(plain(L.money(45, "gold")), "45c", "gold precision under a gold keeps the rest")
eq(plain(L.money(-250)), "-2s 50c", "a loss")

return checks
