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
		if value == math.floor(value) and math.abs(value) < 2 ^ 53 then
			return string.format("%d", value)
		end
		return string.format("%.17g", value)
	elseif kind == "boolean" then
		return value and "true" or "false"
	end
	return "nil"
end

-- A value as a Lua literal. Tables in the save hold strings, numbers, booleans and tables only.
function Export.serialize(value)
	if type(value) ~= "table" then
		return literal(value)
	end
	local keys = {}
	for k in pairs(value) do
		keys[#keys + 1] = k
	end
	table.sort(keys, keyOrder)
	local out = {}
	for i, k in ipairs(keys) do
		out[i] = "[" .. literal(k) .. "]=" .. Export.serialize(value[k])
	end
	return "{" .. table.concat(out, ",") .. "}"
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

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

-- Standard base64 with padding. Built with arithmetic only: Lua 5.1 has no bit operators.
function Export.base64(bytes)
	local out = {}
	for i = 1, #bytes, 3 do
		local a, b, c = string.byte(bytes, i, i + 2)
		local n = a * 65536 + (b or 0) * 256 + (c or 0)
		local c1 = math.floor(n / 262144) % 64
		local c2 = math.floor(n / 4096) % 64
		local c3 = math.floor(n / 64) % 64
		local c4 = n % 64
		out[#out + 1] = ALPHABET:sub(c1 + 1, c1 + 1) .. ALPHABET:sub(c2 + 1, c2 + 1)
			.. (b and ALPHABET:sub(c3 + 1, c3 + 1) or "=") .. (c and ALPHABET:sub(c4 + 1, c4 + 1) or "=")
	end
	return table.concat(out)
end

-- The whole string, and what it holds: [deflate] is LibDeflate's CompressDeflate, passed in so this
-- file stays pure.
function Export.build(db, since, now, deflate)
	local picked = Export.select(db, since, now)
	return Export.PREFIX .. Export.base64(deflate(Export.serialize(picked))), picked
end

return Export
