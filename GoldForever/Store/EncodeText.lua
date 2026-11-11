-- Gold Forever: text in the save and in what players share (ns.Encode): names and free text in rows, chat
-- lines, base64, money, durations and the client's message patterns. Pure Lua 5.1 with no game API.

local _, ns = ...
ns = ns or {}
local L = ns.L
local Encode = ns.Encode

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

-- "1h 20m", "25m", "under a minute": a duration in seconds, rounded to minutes.
function Encode.duration(seconds)
	if seconds < 60 then
		return L["under a minute"]
	end
	local minutes = math.floor(seconds / 60 + 0.5)
	if minutes < 60 then
		return string.format(L["%dm"], minutes)
	end
	return string.format(L["%dh %dm"], math.floor(minutes / 60), minutes % 60)
end

-- The placeholder at `i` in a message format: its argument's position where the format numbers it
-- ("%2$d", a language that reorders them), its kind (s or d), and where the rest starts.
local function placeholder(format, i)
	local at, kind, after = string.match(format, "^%%(%d+)%$([sd])()", i)
	if not kind then
		kind, after = string.match(format, "^%%([sd])()", i)
	end
	return tonumber(at), kind, after
end

-- The client's grammar markers, which the game resolves before it sends a message: each as a pattern on the
-- format and the forms it may become. Korean's |1X;Y; is the particle X or Y the word before it takes
-- (koKR LOOT_ITEM_CREATED_SELF "%s|1을;를; 만들었습니다."), French's "|2 " is "de " or "d'" before a name
-- (frFR ERR_AUCTION_SOLD_S), Russian's |4A:B:C; the plural form of the number before it (ruRU
-- COMBATLOG_XPGAIN_FIRSTPERSON). Source: Ketho/BlizzardInterfaceResources, branch forever,
-- Resources/GlobalStrings/<locale>.lua (commit d1ee5698).
local MARKERS = {
	{ "|1([^;|]*);([^;|]*);", function(a, b) return { a, b } end },
	{ "|2 ", function() return { "de ", "d'" } end },
	{ "|4([^;|]*);", function(forms)
		local out = {}
		for form in string.gmatch(forms .. ":", "([^:]*):") do out[#out + 1] = form end
		return out
	end },
}

-- Every form a format's message may take, its markers resolved each way: one, the format, without any.
local function resolved(format)
	for _, marker in ipairs(MARKERS) do
		local s, e, a, b = string.find(format, marker[1])
		if s then
			local out = {}
			for _, form in ipairs(marker[2](a, b)) do
				for _, rest in ipairs(resolved(string.sub(format, e + 1))) do
					out[#out + 1] = string.sub(format, 1, s - 1) .. form .. rest
				end
			end
			return out
		end
	end
	return { format }
end

-- One marker-free format as a pattern, and its placeholders' argument positions in the order they come.
local function compiled(format, whole)
	local parts, order = {}, {}
	local i = 1
	while i <= #format do
		local at, kind, after = placeholder(format, i)
		if kind then
			order[#order + 1] = at or #order + 1
			parts[#parts + 1] = kind == "s" and "(.+)" or "(%d+)"
			i = after
		else
			local c = string.sub(format, i, i)
			if string.sub(format, i, i + 1) == "%%" then
				i = i + 1 -- a literal %
			end
			parts[#parts + 1] = string.find(c, "^[%^%$%(%)%%%.%[%]%*%+%-%?]") and "%" .. c or c
			i = i + 1
		end
	end
	local pattern = table.concat(parts)
	return whole and "^" .. pattern .. "$" or pattern, order
end

-- A reader for one of the client's own message formats ("You create: %sx%d.", its global string in the
-- client's language): reader(text) gives the values of its %s and %d in the format's argument order, or
-- nil when the text is not that message. So a message reads the same in every language the client
-- speaks, a language that numbers its placeholders ("%2$d ... %1$s") or writes grammar markers included
-- (a message is read against each form the markers give). `whole`: the text is the message and nothing more.
local unpack = unpack or table.unpack
function Encode.matcher(format, whole)
	local patterns, order = {}, nil
	for _, form in ipairs(resolved(format)) do
		patterns[#patterns + 1], order = compiled(form, whole)
	end
	return function(text)
		for _, pattern in ipairs(patterns) do
			local found = { string.match(text, pattern) }
			if found[1] ~= nil then
				local out = {}
				for k, at in ipairs(order) do
					out[at] = found[k]
				end
				return unpack(out, 1, #order)
			end
		end
		return nil
	end
end
