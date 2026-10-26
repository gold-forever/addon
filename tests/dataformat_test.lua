-- DataFormat.lua against the companion's internal/addondata/format.go on its main branch: the same version,
-- addon, global, fields and tables. When format.go changes, this and DataFormat.lua change with it.
local ns = {}
assert(load(SOURCES["DataFormat.lua"], "@DataFormat.lua"))("GoldForever", ns)
local D = ns.DataFormat

eq(D.VERSION, 1, "formatVersion")
eq(D.ADDON, "GoldForever_Data", "addonName")
eq(D.GLOBAL, "GoldForever_Prices", "dataGlobal")

-- format.go's field constants, fieldVersion to fieldMarkets.
local GO = { version = "v", at = "at", shared = "shared", lists = "lists", profiles = "profiles", id = "id",
	edited = "edited", string = "string", dings = "dings", webhook = "webhook", characters = "characters", markets = "markets" }
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
	prices = "at dings markets shared v",
	shared = "at lists profiles",
	entry = "edited id string",
	dings = "at characters webhook",
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
return checks()
