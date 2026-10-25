-- Gold Forever: the export string a player pastes on the site (design 005), for players who do not
-- go looking for SavedVariables files. "GF1:" + base64(raw DEFLATE(Lua table text)): the same
-- schema as GoldForever.lua (design 002), so the site reads it with the parser it already has.
-- Pure Lua 5.1 here; the frame and the compression are wired in ExportFrame.lua.

local _, ns = ...
ns = ns or {}

local Export = {}
ns.Export = Export

Export.PREFIX = "GF1:"

-- Keys sort numbers first, then strings, so the same data always gives the same text.
local function keyOrder(a, b)
	local ta, tb = type(a), type(b)
	if ta ~= tb then
		return ta == "number"
	end
	return a < b
end

local function literal(value)
	local kind = type(value)
	if kind == "string" then
		return (string.format("%q", value):gsub("\\\n", "\\n"))
	elseif kind == "number" then
		-- %.0f, not %d: the client's %d stops at 2^31, under one character's 913k gold in copper.
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return string.format("%.0f", value)
		end
		return string.format("%.17g", value)
	elseif kind == "boolean" then
		return value and "true" or "false"
	end
	return "nil"
end

-- A value as Lua literal text, handed to emit(piece) a piece at a time. Tables in the save hold strings,
-- numbers, booleans and tables only.
local function write(value, emit)
	if type(value) ~= "table" then
		emit(literal(value))
		return
	end
	local keys = {}
	for k in pairs(value) do
		keys[#keys + 1] = k
	end
	table.sort(keys, keyOrder)
	emit("{")
	for i, k in ipairs(keys) do
		emit((i > 1 and ",[" or "[") .. literal(k) .. "]=")
		write(value[k], emit)
	end
	emit("}")
end

-- A value as a Lua literal.
function Export.serialize(value)
	local out = {}
	write(value, function(piece)
		out[#out + 1] = piece
	end)
	return table.concat(out)
end

-- The catalogue entries this player has not exported yet, section by section. The catalogue is the
-- same for every player and is most of a save, so each entry goes once. One never pasted reaches
-- the site in other players' exports, and `/gf export all` sends the whole catalogue again.
local function newCatalogue(catalogue, sent)
	local out = {}
	for section, entries in pairs(catalogue or {}) do
		local before = sent and sent[section] or {}
		local fresh = {}
		for key, entry in pairs(entries) do
			if not before[key] then
				fresh[key] = entry
			end
		end
		out[section] = fresh
	end
	return out
end

-- Each market's newest full scan: for a first export, as the older ones only add history.
local function newestFull(scans)
	local newest = {}
	for _, scan in ipairs(scans) do
		local best = newest[scan.market]
		if scan.kind == "full" and (not best or (scan.t or 0) > (best.t or 0)) then
			newest[scan.market] = scan
		end
	end
	local out = {}
	for _, scan in pairs(newest) do
		out[#out + 1] = scan
	end
	table.sort(out, function(a, b) return (a.t or 0) < (b.t or 0) end)
	return out
end

-- What an export holds: what the site needs that is new since [since], the last export's time (nil
-- for the first, or for "export all"). Characters always, as they are now; event days from the last
-- export's day on, since a day is filled across the export; scans newer than it; catalogue entries
-- not exported before. The site stores each record once, so overlaps cost nothing. The addon's own
-- errors and settings stay in the game.
function Export.select(db, since, now)
	local fromDay = since and ns.Encode.day(since) or nil
	local events = {}
	for day, streams in pairs(db.events or {}) do
		if not fromDay or day >= fromDay then
			events[day] = streams
		end
	end
	local scans = {}
	if since then
		for _, scan in ipairs(db.scans or {}) do
			if (scan.t or 0) > since then
				scans[#scans + 1] = scan
			end
		end
	else
		scans = newestFull(db.scans or {})
	end
	return {
		schema = db.schema,
		addon = db.addon,
		fields = db.fields,
		client = db.client,
		characters = db.characters,
		guildBanks = db.guildBanks,
		catalogue = since and newCatalogue(db.catalogue, db.exportSent) or db.catalogue,
		events = events,
		scans = scans,
		export = { t = now, since = since },
	}
end

-- Remembers the catalogue entries [picked] holds as sent.
function Export.markSent(db, picked)
	db.exportSent = db.exportSent or {}
	for section, entries in pairs(picked.catalogue or {}) do
		local sent = db.exportSent[section] or {}
		db.exportSent[section] = sent
		for key in pairs(entries) do
			sent[key] = true
		end
	end
end

-- Standard base64 with padding, which the site decodes with the JDK.
Export.base64 = ns.Encode.base64

-- The text is deflated in parts of PART bytes, each alone, as LibDeflate cannot stop and go on: one
-- part fits in a frame where the whole of a heavy save took 19 s (review B-1). The parts are joined
-- into the one raw DEFLATE stream the site inflates, so the string is the same format.
Export.PART = 16384
-- At level 3 a heavy save's parts deflate in about 2.6 s in all, 3.8 ms each (LuaJIT, interpreted),
-- to 32% of the text; level 9 gave 30% in three times as long.
Export.LEVEL = 3

-- A part's DEFLATE bytes made to go on into the next part. LibDeflate deflates a part under 64 KB as one
-- block, whose first bit says it is the last: cleared. LibDeflate pads the last byte with 1-bits: made 0,
-- and an empty stored block (zlib's sync flush) brings the stream to a byte boundary, where the next
-- part's own blocks begin. The stored block's three header bits fit in the padding when it has room,
-- else in one byte more. `padding` is the number of padding bits in the last byte.
function Export.joinable(bytes, padding)
	local first = string.byte(bytes, 1)
	bytes = string.char(first - first % 2) .. string.sub(bytes, 2)
	local last = string.byte(bytes, #bytes)
	bytes = string.sub(bytes, 1, #bytes - 1) .. string.char(last % 2 ^ (8 - padding))
	return bytes .. (padding < 3 and "\0" or "") .. "\0\0\255\255"
end

-- The export built a little at a time, within what the client lets a script run. The returned
-- step(spent) does one frame's share: spent(work) says, as frameSpent does, whether the frame's share is
-- used. Once it is all done, step returns the string and what it holds. deflate(part) is LibDeflate's
-- CompressDeflate (the bytes and the padding bits of the last byte), passed in so this file stays pure.
function Export.builder(db, since, now, deflate)
	local picked = Export.select(db, since, now)
	local spent, work = nil, 0
	-- A part deflated is a frame's worth on its own: spent is asked right after it.
	local function pause(heavy)
		work = heavy and (work - work % 25 + 25) or (work + 1)
		if spent(work) then
			work = 0
			spent = coroutine.yield()
		end
	end
	local out = { Export.PREFIX }
	local packed = "" -- deflated bytes not yet in base64, fewer than three
	local function pack(part, final)
		local bytes, padding = deflate(part)
		if not final then
			bytes = Export.joinable(bytes, padding)
		end
		pause(true)
		packed = packed .. bytes
		local whole = final and #packed or (#packed - #packed % 3)
		out[#out + 1] = Export.base64(string.sub(packed, 1, whole))
		packed = string.sub(packed, whole + 1)
		pause(true)
	end
	-- Text waiting to be deflated: always some of it is left for the last part.
	local text, size = {}, 0
	local function emit(piece)
		text[#text + 1] = piece
		size = size + #piece
		if size > Export.PART then
			local all, at = table.concat(text), 1
			while #all - at + 1 > Export.PART do
				pack(string.sub(all, at, at + Export.PART - 1))
				at = at + Export.PART
			end
			local rest = string.sub(all, at)
			text, size = { rest }, #rest
		end
		pause(false)
	end
	local job = coroutine.create(function(first)
		spent = first
		write(picked, emit)
		pack(table.concat(text), true)
	end)
	local result
	return function(frameSpent)
		if not result then
			local ok, err = coroutine.resume(job, frameSpent)
			if not ok then
				error(err, 0)
			end
			if coroutine.status(job) ~= "dead" then
				return nil
			end
			result = table.concat(out)
		end
		return result, picked
	end
end

-- The whole string at once, and what it holds.
function Export.build(db, since, now, deflate)
	local step = Export.builder(db, since, now, deflate)
	return step(function()
		return false
	end)
end

return Export
