-- The save as text that is the same every run, for the golden comparison (run.js): one line per value, its
-- path then the value, keys sorted with numbers first. A market scan's rows come out in whatever order the
-- scan read them, in chunks of whatever size its frames allowed: they are written as one sorted list.
-- A run on a given save (the big save) is compared by what it changed in it, which is far smaller.
local function keyOrder(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta == "number"
	end
	return a < b
end

local function sortedKeys(t)
	local keys = {}
	for k in pairs(t) do
		keys[#keys + 1] = k
	end
	table.sort(keys, keyOrder)
	return keys
end

local function valueText(v)
	if type(v) == "number" then
		return string.format("%.17g", v)
	elseif type(v) == "string" then
		return (string.format("%q", v):gsub("\\\n", "\\n"))
	end
	return tostring(v)
end

local function keyText(k)
	if type(k) == "string" and k:match("^[%a_][%w_]*$") then
		return "." .. k
	end
	return "[" .. valueText(k) .. "]"
end

local function scanRows(chunks)
	local rows = {}
	for _, chunk in ipairs(chunks) do
		for row in chunk:gmatch("[^;]+") do
			rows[#rows + 1] = row
		end
	end
	table.sort(rows)
	return rows
end

local dump
local function dumpRows(chunks, at, out)
	for _, row in ipairs(scanRows(chunks)) do
		out[#out + 1] = at .. ": " .. valueText(row)
	end
end

-- The path of a value under t[k]; the save's own keys are written without a leading dot.
local function under(path, k)
	return ((path .. keyText(k)):gsub("^%.", ""))
end

local function isRows(path, k)
	return k == "rows" and path:match("^scans%[[^%]]+%]$")
end

function dump(value, path, out)
	if type(value) ~= "table" then
		out[#out + 1] = path .. " = " .. valueText(value)
		return
	end
	local keys = sortedKeys(value)
	if #keys == 0 then
		out[#out + 1] = path .. " = {}"
	end
	for _, k in ipairs(keys) do
		if isRows(path, k) then
			dumpRows(value[k], under(path, k), out)
		else
			dump(value[k], under(path, k), out)
		end
	end
end

local function lines(value, path)
	local out = {}
	dump(value, path, out)
	return out
end

-- Values gone from a table, by key: tables as their line count, the others a few keys to a line (a run
-- may drop thousands, as catalogue tooltips).
local KEYS_A_LINE = 16
local function removed(t, keys, path, out)
	local scalars = {}
	local function flush()
		if #scalars > 0 then
			out[#out + 1] = "- " .. (path == "" and "" or path .. ": ") .. table.concat(scalars, " ")
			scalars = {}
		end
	end
	for _, k in ipairs(keys) do
		if type(t[k]) == "table" then
			flush()
			out[#out + 1] = "- " .. under(path, k) .. " (" .. #lines(t[k], under(path, k)) .. " lines)"
		else
			scalars[#scalars + 1] = (keyText(k):gsub("^%.", ""))
			if #scalars == KEYS_A_LINE then
				flush()
			end
		end
	end
	flush()
end

local function added(value, path, out)
	for _, line in ipairs(lines(value, path)) do
		out[#out + 1] = "+ " .. line
	end
end

-- A scan's rows before and after, as a multiset: each row removed or added, in sorted order.
local function rowChanges(before, after, at, out)
	local was, now = scanRows(before), scanRows(after)
	local i, j = 1, 1
	while i <= #was or j <= #now do
		if j > #now or (i <= #was and was[i] < now[j]) then
			out[#out + 1] = "- " .. at .. ": " .. valueText(was[i])
			i = i + 1
		elseif i > #was or now[j] < was[i] then
			out[#out + 1] = "+ " .. at .. ": " .. valueText(now[j])
			j = j + 1
		else
			i, j = i + 1, j + 1
		end
	end
end

local changes
-- Scans matched by market and time, not by place: a run that reorders them changes only their order.
local function scanChanges(before, after, out)
	local function byId(scans)
		local ids, order = {}, {}
		for i, scan in ipairs(scans) do
			local id = tostring(scan.market) .. "@" .. tostring(scan.t)
			ids[id], order[i] = scan, id
		end
		return ids, table.concat(order, " ")
	end
	local was, wasOrder = byId(before)
	local now, nowOrder = byId(after)
	if wasOrder ~= nowOrder then
		out[#out + 1] = "- scans order = " .. wasOrder
		out[#out + 1] = "+ scans order = " .. nowOrder
	end
	changes(was, now, "scans", out)
end

-- What changed from one save to another: "- path" for values gone (see removed), "+ path = value" for each
-- value new, both for a value changed.
function changes(before, after, path, out)
	local keys, seen = {}, {}
	for _, t in ipairs({ before, after }) do
		for k in pairs(t) do
			if not seen[k] then
				seen[k], keys[#keys + 1] = true, k
			end
		end
	end
	table.sort(keys, keyOrder)
	local gone = {}
	for _, k in ipairs(keys) do
		local was, now = before[k], after[k]
		if was ~= nil and now ~= was and not (type(was) == "table" and type(now) == "table") then
			gone[#gone + 1] = k
		end
	end
	removed(before, gone, path, out)
	for _, k in ipairs(keys) do
		local was, now, at = before[k], after[k], under(path, k)
		if type(was) == "table" and type(now) == "table" then
			if path == "" and k == "scans" then
				scanChanges(was, now, out)
			elseif isRows(path, k) then
				rowChanges(was, now, at, out)
			else
				changes(was, now, at, out)
			end
		elseif now ~= nil and now ~= was then
			added(now, at, out)
		end
	end
	return out
end

local function text(out)
	return table.concat(out, "\n") .. "\n"
end

local Dump = {}

function Dump.save(db)
	return text(lines(db or {}, ""))
end

function Dump.changes(before, after)
	return text(changes(before or {}, after or {}, "", {}))
end

return Dump
