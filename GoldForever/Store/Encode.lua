-- Gold Forever: the compact row format of design 002, and the facade ns.Encode, which the files beside it
-- fill in the TOC's order: ids (EncodeIds.lua), text (EncodeText.lua) and amounts (EncodeAmounts.lua).
-- Pure Lua 5.1 with no game API, so it can be tested outside the client.

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

-- A retail scan's row for one item ("item,class,subclass,stack"), so the server can tell a commodity
-- from gear before the catalogue has loaded it (half a scan's items, on the first real one). instant
-- is GetItemInfoInstant, client data that needs no server query; stack is GetItemMaxStackSizeByID,
-- written only when it answers. Either may be missing.
function Encode.itemRow(id, instant, stack)
	local class, subclass
	if instant then
		local _, _, _, _, _, c, s = instant(id)
		class, subclass = c, s
	end
	local size
	if stack then
		local ok, value = pcall(stack, id)
		size = ok and value or nil
	end
	return Encode.row(id, class, subclass, size)
end

-- Rows in each stream's last chunk, kept in memory so an append does not count them again: stream ->
-- { chunk, n }, trusted only while that chunk is still the stream's last.
local lastRows = setmetatable({}, { __mode = "k" })

-- Appends a row to a stream: an array of chunk strings, the last one filled first.
function Encode.append(stream, row)
	local last = #stream
	local chunk = stream[last]
	local known = lastRows[stream]
	local n = chunk and (known and known.chunk == chunk and known.n or Encode.count(chunk)) or 0
	if chunk and n < Encode.ROWS_PER_CHUNK then
		chunk, n = chunk .. ";" .. row, n + 1
		stream[last] = chunk
	else
		chunk, n = row, 1
		stream[last + 1] = chunk
	end
	if known then
		known.chunk, known.n = chunk, n
	else
		lastRows[stream] = { chunk = chunk, n = n }
	end
end

-- Rows as chunk strings in one pass, ROWS_PER_CHUNK to a chunk: for a stream written all at once
-- (a scan's 20,000 listings), where appending row by row would copy each chunk again and again.
function Encode.chunks(rows)
	local chunks = {}
	for i = 1, #rows, Encode.ROWS_PER_CHUNK do
		chunks[#chunks + 1] = table.concat(rows, ";", i, math.min(#rows, i + Encode.ROWS_PER_CHUNK - 1))
	end
	return chunks
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

-- An item list ("2589*2+10221:612*1") as item ID -> count; variants of one item add up.
function Encode.parseItems(text)
	local out = {}
	for key, n in string.gmatch(text or "", "([^+*]+)%*(%d+)") do
		local id = Encode.itemId(key)
		if id then
			out[id] = (out[id] or 0) + tonumber(n)
		end
	end
	return out
end

-- A 0–1 map coordinate as an integer 0–1000: in-game coordinates to one decimal.
function Encode.coord(v)
	if not v then
		return nil
	end
	return math.floor(v * 1000 + 0.5)
end

-- Declared columns ("t,char,map") as name -> position, so a row is read as its file declares it.
function Encode.columns(declared)
	local out, i = {}, 0
	for name in string.gmatch(declared or "", "[^,]+") do
		i = i + 1
		out[name] = i
	end
	return out
end

-- UTC day key of an epoch time, the bucket events are stored under.
function Encode.day(epoch)
	return date("!%Y-%m-%d", epoch)
end

-- A time-left band (Enum.AuctionHouseTimeLeftBand, 0–3) from GetReplicateItemTimeLeft's answer, which
-- is 1–4 (short … very long); nil for anything else.
function Encode.band(raw)
	if type(raw) == "number" and raw >= 1 and raw <= 4 and raw == math.floor(raw) then
		return raw - 1
	end
	return nil
end

return Encode
