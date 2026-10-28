-- Gold Forever: the compact row format of design 002. Pure Lua 5.1 with no game API, so it can
-- be tested outside the client.

local _, ns = ...
ns = ns or {}

local Encode = {}
ns.Encode = Encode

-- Rows per string. The client writes a "-- [n]" comment after every array entry; joining rows
-- into chunks keeps that overhead per chunk instead of per row.
Encode.ROWS_PER_CHUNK = 500

-- The most copper any price the addon takes from outside may be (a million gold).
Encode.MAX_COPPER = 10000000000

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

-- Whether a name names nothing: empty, "?", or the client's placeholder for a name it has not loaded yet
-- ("Unknown" in English; UNKNOWNOBJECT and UNKNOWN hold the client's own word for it). Such a name is
-- never written, so a later real one fills the row.
function Encode.noName(text)
	return text == nil or text == "" or text == "?" or text == "Unknown" or text == UNKNOWNOBJECT or text == UNKNOWN
end

-- Free text in a catalogue row: no commas (columns), semicolons (rows) or line breaks; nil for none.
function Encode.text(s)
	if not s or s == "" then
		return nil
	end
	return (Encode.name(s):gsub(";", "."):gsub("[\r\n]+", " "))
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

-- Market value of an item from one scan's listings ({ { unit, qty }, … }, any order): the average
-- unit price of the cheapest 15% of units, at least one. The web app's price engine does the same
-- (backend/Prices.kt), so the two agree.
function Encode.marketValue(listings)
	local sorted = {}
	local total = 0
	for i, l in ipairs(listings) do
		sorted[i] = l
		total = total + l.qty
	end
	if total == 0 then
		return nil
	end
	table.sort(sorted, function(a, b)
		return a.unit < b.unit
	end)
	local wanted = math.max(1, math.ceil(total * 0.15))
	local units, copper = 0, 0
	for _, l in ipairs(sorted) do
		local take = math.min(wanted - units, l.qty)
		units = units + take
		copper = copper + take * l.unit
		if units >= wanted then
			break
		end
	end
	return math.floor(copper / units)
end

-- The same market value from a flat list { unit1, qty1, unit2, qty2, … }: one table an item instead of one a
-- listing, for reading a whole scan (a retail scan has ~110,000 rows).
function Encode.marketValueFlat(flat)
	local n = #flat / 2
	local total = 0
	for k = 2, #flat, 2 do
		total = total + flat[k]
	end
	if total == 0 then
		return nil
	end
	local wanted = math.max(1, math.ceil(total * 0.15))
	if n == 1 then
		return flat[1]
	end
	local order
	if n <= 24 then
		-- Few listings (most items): sorted in place by unit, pairs moved together; no table, no closure.
		for i = 2, n do
			local u, q = flat[2 * i - 1], flat[2 * i]
			local j = i - 1
			while j >= 1 and flat[2 * j - 1] > u do
				flat[2 * j + 1], flat[2 * j + 2] = flat[2 * j - 1], flat[2 * j]
				j = j - 1
			end
			flat[2 * j + 1], flat[2 * j + 2] = u, q
		end
	else
		order = {}
		for k = 1, n do
			order[k] = k
		end
		table.sort(order, function(a, b)
			return flat[2 * a - 1] < flat[2 * b - 1]
		end)
	end
	local units, copper = 0, 0
	for i = 1, n do
		local k = order and order[i] or i
		local take = math.min(wanted - units, flat[2 * k])
		units = units + take
		copper = copper + take * flat[2 * k - 1]
		if units >= wanted then
			break
		end
	end
	return math.floor(copper / units)
end

-- The cheapest unit in a flat list.
function Encode.cheapestFlat(flat)
	local low
	for k = 1, #flat, 2 do
		if not low or flat[k] < low then
			low = flat[k]
		end
	end
	return low
end

-- A line for party chat: plain text (the game's "|" escapes out, so nothing coloured or linked), on one
-- line, within chat's 255 characters, marked as Gold Forever's.
function Encode.chatLine(text)
	local plain = string.gsub(string.gsub(tostring(text or ""), "|", ""), "[\r\n]+", " ")
	return string.sub("[Gold Forever] " .. plain, 1, 255)
end

-- Base64 (RFC 4648, with padding), for the GFL1/GFP1 strings players and the site share: the same bytes
-- as the site's btoa over UTF-8.
local B64 = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local B64_INDEX = {}
for i = 1, 64 do
	B64_INDEX[string.byte(B64, i)] = i - 1
end

function Encode.base64(text)
	local out = {}
	for i = 1, #text, 3 do
		local a, b, c = string.byte(text, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local d1, d2 = math.floor(n / 262144) % 64, math.floor(n / 4096) % 64
		local d3, d4 = math.floor(n / 64) % 64, n % 64
		out[#out + 1] = string.sub(B64, d1 + 1, d1 + 1) .. string.sub(B64, d2 + 1, d2 + 1)
			.. (b and string.sub(B64, d3 + 1, d3 + 1) or "=") .. (c and string.sub(B64, d4 + 1, d4 + 1) or "=")
	end
	return table.concat(out)
end

-- The text of a base64 string, or nil when it is not one (a character outside the alphabet, a bad length).
function Encode.unbase64(s)
	s = string.gsub(s, "%s", "")
	if #s % 4 ~= 0 then
		return nil
	end
	local out = {}
	for i = 1, #s, 4 do
		local c1, c2, c3, c4 = string.byte(s, i, i + 3)
		local v1, v2 = B64_INDEX[c1], B64_INDEX[c2]
		local v3, v4 = c3 == 61 and 0 or B64_INDEX[c3], c4 == 61 and 0 or B64_INDEX[c4]
		if not (v1 and v2 and v3 and v4) or (c3 == 61 and c4 ~= 61) or ((c3 == 61 or c4 == 61) and i + 3 < #s) then
			return nil
		end
		local n = v1 * 262144 + v2 * 4096 + v3 * 64 + v4
		out[#out + 1] = string.char(math.floor(n / 65536) % 256)
		if c3 ~= 61 then
			out[#out + 1] = string.char(math.floor(n / 256) % 256)
		end
		if c4 ~= 61 then
			out[#out + 1] = string.char(n % 256)
		end
	end
	return table.concat(out)
end

-- "1g 23s 4c", "23s 4c", "4c": copper as text, for where coin icons cannot go.
function Encode.money(copper)
	return ns.Money.format(copper, "plain")
end

-- XP gained between two readings: within a level, the difference; across a level-up, the rest of
-- the old level plus what the new one has so far.
function Encode.xpGained(before, beforeMax, now, levelledUp)
	if levelledUp then
		return math.max(0, beforeMax - before) + now
	end
	return math.max(0, now - before)
end

-- "1h 20m", "25m", "under a minute": a duration in seconds, rounded to minutes.
function Encode.duration(seconds)
	if seconds < 60 then
		return "under a minute"
	end
	local minutes = math.floor(seconds / 60 + 0.5)
	if minutes < 60 then
		return minutes .. "m"
	end
	return string.format("%dh %dm", math.floor(minutes / 60), minutes % 60)
end

-- The item ID of an item key ("2589", "10221:612"), or of an ID given as a number.
function Encode.itemId(key)
	return key and tonumber(string.match(tostring(key), "^(%d+)"))
end

-- The NPC ID of a loot source ("n7440"); nil for an object, an item or "?".
function Encode.npcOf(src)
	return src and tonumber(string.match(src, "^n(%d+)$"))
end

-- The NPC ID behind a unit or spawn GUID; nil for players, objects and anything else.
function Encode.npcId(guid)
	return Encode.npcOf(Encode.source(guid))
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

-- Declared columns ("t,char,map") as name -> position, so a row is read as its file declares it.
function Encode.columns(declared)
	local out, i = {}, 0
	for name in string.gmatch(declared or "", "[^,]+") do
		i = i + 1
		out[name] = i
	end
	return out
end

-- A Lua pattern from one of the client's own message formats ("You create: %sx%d."), with a capture
-- for each %s and %d, so a message reads the same in every language the client speaks.
function Encode.pattern(format)
	local escaped = string.gsub(format, "[%%%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
	return (string.gsub(string.gsub(escaped, "%%%%s", "(.+)"), "%%%%d", "(%%d+)"))
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
