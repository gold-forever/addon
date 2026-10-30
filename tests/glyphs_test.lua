-- Every string the addon can show is drawn by the game's fonts (Friz Quadrata, Arial Narrow, Morpheus,
-- Skurri) and the looks' own (Roboto, Exo 2): a character one of them lacks shows as an empty square
-- (the first-run card's "Settings → General", 2026-10-30). Every string literal in the addons' files and
-- their TOCs is read; plain ASCII passes, and the one character beyond it that the string may hold.

-- The middle dot, the separator in lines of facts: Latin-1, which every font the game draws its Western
-- locales in has.
local ALLOWED = { ["\194\183"] = true }

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

-- The first character in `text` the fonts may not draw, else nil.
local function undrawn(text)
	for ch in text:gmatch("[\192-\255][\128-\191]*") do
		if not ALLOWED[ch] then
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

local names = {}
for name in pairs(SOURCES) do
	names[#names + 1] = name
end
table.sort(names)
local bad = {}
for _, name in ipairs(names) do
	for _, lit in ipairs(literals(SOURCES[name])) do
		local ch = undrawn(lit[2])
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
