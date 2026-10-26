-- Gold Forever: the save's streams and their columns (design 002, schema v1), and ns.record, the one way
-- a collector appends a row to a stream.

local _, ns = ...
local Encode = ns.Encode

-- Column dictionary; each collector adds its own entries when its file loads.
ns.FIELDS = {
	sys = "t,char,kind",
}

-- A declaration's column names in order and by name, read once.
local layouts = {}
local function layout(declared)
	local known = layouts[declared]
	if not known then
		known = { names = {}, index = Encode.columns(declared) }
		for name, i in pairs(known.index) do
			known.names[i] = name
		end
		layouts[declared] = known
	end
	return known
end

-- Appends a row, its values by column name, to today's bucket of a stream; a column left out is empty.
-- A stream or column the schema does not have is recorded as an error (ns.fail) and nothing is written.
function ns.record(stream, row)
	local declared = ns.FIELDS[stream]
	if not declared then
		ns.fail("record", "no stream " .. tostring(stream) .. " in the schema")
		return
	end
	local columns = layout(declared)
	for name in pairs(row) do
		if not columns.index[name] then
			ns.fail("record", stream .. " has no column " .. tostring(name) .. " in the schema")
			return
		end
	end
	local values = {}
	for i, name in ipairs(columns.names) do
		values[i] = row[name]
	end
	ns.append(stream, Encode.row(unpack(values, 1, #columns.names)))
end
