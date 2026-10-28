-- DataFormat.lua against the companion's internal/addondata/format.go on its main branch: the same version,
-- addon, global, fields and tables. When format.go changes, this and DataFormat.lua change with it.
local ns = {}
assert(load(SOURCES["DataFormat.lua"], "@DataFormat.lua"))("GoldForever", ns)
local D = ns.DataFormat

eq(D.VERSION, 1, "formatVersion")
eq(D.ADDON, "GoldForever_Data", "addonName")
eq(D.GLOBAL, "GoldForever_Prices", "dataGlobal")

-- format.go's field constants, fieldVersion to fieldUnits.
local GO = { version = "v", at = "at", shared = "shared", lists = "lists", profiles = "profiles", id = "id",
	edited = "edited", string = "string", markets = "markets",
	units = "units" }
local function sorted(t, values)
	local out = {}
	for k, v in pairs(t) do
		out[#out + 1] = values and (k .. "=" .. v) or k
	end
	table.sort(out)
	return table.concat(out, " ")
end
eq(sorted(D.field, true), sorted(GO, true), "the fields")

-- Data.lua's tables, as format.go draws them, and an item's figures in their order.
local TABLES = {
	prices = "at markets shared v",
	shared = "at lists profiles",
	entry = "edited id string",
	item = "units",
}
eq(sorted(D.tables), sorted(TABLES), "the tables")
for name, fields in pairs(TABLES) do
	eq(sorted(D.tables[name]), fields, "the fields of " .. name)
end
eq(sorted(D.item, true), "minBuyout=2 players=3 scannedAt=4 value=1 week=5", "an item's figures by place")

-- Every field a table holds is a declared field, and every declared field is in a table.
local used = {}
for _, fields in pairs(D.tables) do
	for f in pairs(fields) do
		used[f] = true
	end
end
local declared = {}
for _, f in pairs(D.field) do
	declared[f] = true
end
eq(sorted(used), sorted(declared), "the tables use the declared fields, all of them")

-- DataFormat.lua is the one place the file's shape is named: its readers (the files that name the global
-- or read ns.DataFormat) index it by DataFormat's names, never the global directly or a field by a quoted
-- name; a new one fails here. A field read by dot through a local (data.markets) is not seen.
local FIELD = {}
for _, f in pairs(D.field) do
	FIELD[f] = true
end
local function literalReads(source)
	local found = {}
	local n = 0
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		n = n + 1
		local code = line:gsub("%-%-.*$", "")
		local hit = code:find(D.GLOBAL .. "%s*[%.:%[]")
		for name in code:gmatch('%[%s*"([%w_]+)"%s*%]') do
			hit = hit or FIELD[name]
		end
		if hit then
			found[#found + 1] = "line " .. n
		end
	end
	return table.concat(found, ", ")
end
local readers = 0
for file, source in pairs(SOURCES) do
	if file ~= "DataFormat.lua" and (source:find(D.GLOBAL, 1, true) or nsNames(source).DataFormat) then
		readers = readers + 1
		eq(literalReads(source), "", file .. " reads the data file by DataFormat's names")
	end
end
eq(readers >= 4, true, "the data file's readers are found")

-- The scan sees a literal read, and not one by DataFormat's names or in a comment.
eq(literalReads('local m = GoldForever_Prices.markets\nlocal s = file["shared"]\nlocal t = x["title"]'), "line 1, line 2",
	"the global indexed, a field by its quoted name, and not another quoted key")
eq(literalReads("local m = data[F.markets] -- data.markets"), "", "DataFormat's names, and a comment")
return checks()
