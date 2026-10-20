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

-- Item key of an item link or item string: "itemId", or "itemId:suffixId" for random-suffix
-- items. nil when the text is not an item.
function Encode.itemKey(link)
	local fields = link and string.match(link, "item:([%-%d:]+)")
	if not fields then
		return nil
	end
	local parts = {}
	for part in string.gmatch(fields .. ":", "([^:]*):") do
		parts[#parts + 1] = part
	end
	local id = tonumber(parts[1])
	if not id then
		return nil
	end
	local suffix = tonumber(parts[7] or "")
	if suffix and suffix ~= 0 then
		return id .. ":" .. suffix
	end
	return tostring(id)
end

-- Loot source of a unit or object GUID: "n<npcId>" or "o<objectId>"; nil for anything else.
-- Creature-0-<server>-<instance>-<zoneUID>-<npcId>-<spawnUID>, GameObject the same.
function Encode.source(guid)
	if not guid then
		return nil
	end
	local parts = {}
	for part in string.gmatch(guid, "[^%-]+") do
		parts[#parts + 1] = part
	end
	local prefix = (parts[1] == "Creature" or parts[1] == "Vehicle") and "n" or parts[1] == "GameObject" and "o" or nil
	local id = tonumber(parts[6] or "")
	if prefix and id then
		return prefix .. id
	end
	return nil
end

-- Splits an integer amount over weights (numbers ≥ 0) in proportion, remainder to the first
-- shares, so the parts always add up to the amount. Equal shares when every weight is 0.
function Encode.split(amount, weights)
	local total = 0
	for _, w in ipairs(weights) do
		total = total + w
	end
	local parts, given = {}, 0
	for i, w in ipairs(weights) do
		local share = total > 0 and w / total or 1 / #weights
		parts[i] = math.floor(amount * share)
		given = given + parts[i]
	end
	local i = 1
	while given < amount and #parts > 0 do
		parts[i] = parts[i] + 1
		given = given + 1
		i = i % #parts + 1
	end
	return parts
end

-- UTC day key of an epoch time, the bucket events are stored under.
function Encode.day(epoch)
	return date("!%Y-%m-%d", epoch)
end

return Encode
