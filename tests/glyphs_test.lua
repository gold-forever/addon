-- Every string the addon can show is drawn by the game's fonts (Friz Quadrata, Arial Narrow, Morpheus,
-- Skurri) and the looks' own (Roboto, Exo 2): a character one of them lacks shows as an empty square
-- (the first-run card's "Settings → General", 2026-10-30). Every string literal in the addons' files and
-- their TOCs is read; plain ASCII passes, and the one character beyond it that the string may hold.

-- The middle dot, the separator in lines of facts: Latin-1, which every font the game draws its Western
-- locales in has.
local ALLOWED = { ["\194\183"] = true }
-- French's letters and quotes (frFR.lua), Latin-1 as well: the French client's own text uses them. Not œ or
-- the curly apostrophe, which are beyond it: French text writes oe and '.
-- German's ß (deDE.lua) is Latin-1 too; its umlauts are among French's. Spanish's and Portuguese's letters
-- and Spanish's opening marks (esES.lua, ptBR.lua) as well.
for ch in string.gmatch("àâäçéèêëîïôöùûüÿÀÂÄÇÉÈÊËÎÏÔÖÙÛÜ«»ßáíóúñãõÁÍÓÚÑÃÕ¿¡", "[\192-\255][\128-\191]*") do
	ALLOWED[ch] = true
end

-- The string literals in a Lua source, comments left out: each as { line, text } (escapes kept as written).
local function literals(source)
	local out, i, line = {}, 1, 1
	local function longBracket(at)
		local eqs = source:match("^%[(=*)%[", at)
		return eqs and #eqs
	end
	local function skipLong(at, level)
		local close = "]" .. string.rep("=", level) .. "]"
		local _, stop = source:find(close, at, true)
		stop = stop or #source
		return stop + 1
	end
	while i <= #source do
		local c = source:sub(i, i)
		if c == "\n" then
			line = line + 1
			i = i + 1
		elseif source:sub(i, i + 1) == "--" then
			local level = longBracket(i + 2)
			local stop = level and skipLong(i + 2, level) or (source:find("\n", i, true) or #source + 1)
			local _, n = source:sub(i, stop - 1):gsub("\n", "")
			line, i = line + n, stop
		elseif c == "[" and longBracket(i) then
			local stop = skipLong(i, longBracket(i))
			local text = source:sub(i, stop - 1)
			out[#out + 1] = { line, text }
			local _, n = text:gsub("\n", "")
			line, i = line + n, stop
		elseif c == '"' or c == "'" then
			local j = i + 1
			while j <= #source and source:sub(j, j) ~= c and source:sub(j, j) ~= "\n" do
				j = j + (source:sub(j, j) == "\\" and 2 or 1)
			end
			out[#out + 1] = { line, source:sub(i + 1, j - 1) }
			i = j + 1
		else
			i = i + 1
		end
	end
	return out
end

-- On the Korean and Chinese clients every look draws in the client's own font (Theme.lua), which has Hangul,
-- Han, their punctuation and fullwidth forms: those files (koKR.lua, zhCN.lua, zhTW.lua) may hold them too.
local OWN_FONT = { ["koKR.lua"] = true, ["zhCN.lua"] = true, ["zhTW.lua"] = true }
local function codepoint(ch)
	local b1, b2, b3 = string.byte(ch, 1, 3)
	return #ch == 3 and ((b1 % 16) * 4096 + (b2 % 64) * 64 + b3 % 64) or nil
end
local function eastAsian(ch)
	local c = codepoint(ch)
	return c ~= nil and ((c >= 0xAC00 and c <= 0xD7A3) or (c >= 0x4E00 and c <= 0x9FFF)
		or (c >= 0x3000 and c <= 0x303F) or (c >= 0xFF01 and c <= 0xFF5E))
end

-- The first character in `text` the fonts may not draw, else nil; `own` for a file drawn in a Korean or
-- Chinese client's font.
local function undrawn(text, own)
	for ch in text:gmatch("[\192-\255][\128-\191]*") do
		if not ALLOWED[ch] and not (own and eastAsian(ch)) then
			return ch
		end
	end
end

-- The reader itself: strings found, comments skipped, lines counted.
local sample = 'local a = "x" -- "→"\n--[[ "→"\n]] local b = [[y\n→]]\nlocal c = \'z\\\'→\''
local found = literals(sample)
eq(#found, 3, "three literals, none from the comments")
eq(found[2][1], 3, "the long string's line")
eq(undrawn(found[3][2]), "→", "an escaped quote does not end the string")
eq(undrawn("Settings › General"), "›", "the first-run card's chevron")
eq(undrawn("a · b"), nil, "the middle dot passes")
eq(undrawn("la fenêtre « déjà »"), nil, "French's letters and quotes pass")
eq(undrawn("cœur"), "œ", "œ is beyond Latin-1")
eq(undrawn("Größe für Bären"), nil, "German's letters pass")
eq(undrawn("¿Añadir la misión? ¡Sí! · leilões, ação, Ú"), nil, "Spanish's and Portuguese's letters and marks pass")
eq(undrawn("경매장 · 拍卖行，拍賣場：（AI）「」"), "경", "Hangul and Han are beyond the bundled fonts")
eq(undrawn("경매장 · 拍卖行，拍賣場：（AI）「」", true), nil, "a Korean or Chinese client's own font draws them")
eq(undrawn("경매장 → 拍卖行", true), "→", "but not an arrow")

local names = {}
for name in pairs(SOURCES) do
	names[#names + 1] = name
end
table.sort(names)
local bad = {}
for _, name in ipairs(names) do
	for _, lit in ipairs(literals(SOURCES[name])) do
		local ch = undrawn(lit[2], OWN_FONT[name])
		if ch then
			bad[#bad + 1] = string.format("%s:%d %s in \"%s\"", name, lit[1], ch, lit[2])
		end
	end
end
for name, toc in pairs(TOCS) do
	local ch = undrawn(toc)
	if ch then
		bad[#bad + 1] = name .. " " .. ch
	end
end
eq(table.concat(bad, "\n"), "", #bad .. " strings with a character the fonts may not draw")

return checks()
