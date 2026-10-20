-- Gold Forever: the compact row format of design 002. Pure Lua 5.1 with no game API, so it can
-- be tested outside the client.

local _, ns = ...
ns = ns or {}

local Encode = {}
ns.Encode = Encode

-- Rows per string. The client writes a "-- [n]" comment after every array entry; joining rows
-- into chunks keeps that overhead per chunk instead of per row.
Encode.ROWS_PER_CHUNK = 500

-- One row from values in declared column order. nil and false become empty, true becomes "1".
-- Trailing empty columns are kept so the row always matches its declaration.
function Encode.row(...)
	local n = select("#", ...)
	local out = {}
	for i = 1, n do
		local v = select(i, ...)
		if v == nil or v == false then
			out[i] = ""
		elseif v == true then
			out[i] = "1"
		else
			out[i] = tostring(v)
		end
	end
	return table.concat(out, ",")
end

-- Appends a row to a stream: an array of chunk strings, the last one filled first.
function Encode.append(stream, row)
	local last = #stream
	local chunk = stream[last]
	if chunk and Encode.count(chunk) < Encode.ROWS_PER_CHUNK then
		stream[last] = chunk .. ";" .. row
	else
		stream[last + 1] = row
	end
end

-- Number of rows in a chunk.
function Encode.count(chunk)
	local _, separators = string.gsub(chunk, ";", "")
	return separators + 1
end

-- "itemId*count+itemId*count" from { [itemKey] = count }, in a stable order.
function Encode.items(counts)
	local keys = {}
	for key in pairs(counts) do
		keys[#keys + 1] = key
	end
	table.sort(keys, function(a, b)
		return tostring(a) < tostring(b)
	end)
	local out = {}
	for i, key in ipairs(keys) do
		out[i] = key .. "*" .. counts[key]
	end
	return table.concat(out, "+")
end

-- A 0–1 map coordinate as an integer 0–1000: in-game coordinates to one decimal.
function Encode.coord(v)
	if not v then
		return nil
	end
	return math.floor(v * 1000 + 0.5)
end

-- Item names go in the catalogue as one column; commas become U+201A (design 002).
function Encode.name(text)
	return (string.gsub(text, ",", "\226\128\154"))
end

-- UTC day key of an epoch time, the bucket events are stored under.
function Encode.day(epoch)
	return date("!%Y-%m-%d", epoch)
end

return Encode
