-- The addon's text in the client's language (Locale.lua): the client's language when a file gives it,
-- English otherwise; every language's file has exactly English's texts, with the same placeholders; every
-- text a file shows through ns.L is in enUS.lua, and every one listed there is shown somewhere.

local LANGUAGES = { "frFR.lua" }

local function loaded(code)
	GetLocale = function() return code end
	local ns = {}
	for _, file in ipairs({ "Locale.lua", "enUS.lua", "frFR.lua" }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	GetLocale = nil
	return ns
end

local KEY = "Translated with AI: it may contain mistakes."
local en, fr = loaded("enUS"), loaded("frFR")
eq(en.L[KEY], KEY, "an English client shows the English text")
eq(fr.L[KEY], "Traduction faite par une IA : elle peut contenir des erreurs.", "a French client shows the French text")
eq(fr.L["a text no language lists"], "a text no language lists", "a text no file lists shows as it is")
eq(en.Locale.translated(), false, "English is not a translation")
eq(fr.Locale.translated(), true, "French is")

-- A language without a text shows it in English; a third language is one more file of this shape.
do
	local de = loaded("deDE")
	assert(load('local _, ns = ... ns.Locale.add("deDE", { ["Total"] = "Gesamt" })', "@deDE.lua"))("GoldForever", de)
	eq(de.L["Total"], "Gesamt", "a third language's text")
	eq(de.L[KEY], KEY, "a text the language lacks falls back to English")
	eq(de.Locale.translated(), true, "a third language is a translation")
end

-- Counts: English's singular is 1 alone, French's 0 and 1.
eq(en.plural(1, "%d craft", "%d crafts"), "1 craft", "English: 1 is singular")
eq(en.plural(0, "%d craft", "%d crafts"), "0 crafts", "English: 0 is plural")
eq(fr.plural(0, "%d fabrication", "%d fabrications"), "0 fabrication", "French: 0 is singular")
eq(fr.plural(2, "%d fabrication", "%d fabrications"), "2 fabrications", "French: 2 is plural")
eq(en.plural(3, "%d of %s", "%d of %s", "x"), "3 of x", "the rest is formatted after the count")

eq(fr.Locale.sourceOf(fr.L[KEY]), KEY, "a French text's English, for a name the save keeps")
eq(en.Locale.sourceOf("Total"), "Total", "an English text is its own")
eq(fr.upper("Règles de vente · à l'hôtel"), "RÈGLES DE VENTE · À L'HÔTEL", "capitals, accented letters too")

-- The placeholders a text formats, in their order (%s, %d, %.1f, …; %% is a literal).
local function placeholders(text)
	local out = {}
	for spec in string.gmatch((string.gsub(text, "%%%%", "")), "%%[%-%d%.]*[a-zA-Z]") do
		out[#out + 1] = spec
	end
	return table.concat(out, " ")
end
eq(placeholders("%d of %s: 100%% at %.1f"), "%d %s %.1f", "placeholders are read in order, %% left out")

local english = en.Locale.english
for _, file in ipairs(LANGUAGES) do
	local code = file:match("^(.-)%.lua$")
	local texts = en.Locale.languages[code]
	eq(type(texts), "table", file .. " adds " .. code)
	local missing, extra, wrong = {}, {}, {}
	for text in pairs(english) do
		if texts[text] == nil then missing[#missing + 1] = text end
	end
	for text, translated in pairs(texts) do
		if not english[text] then
			extra[#extra + 1] = text
		elseif placeholders(translated) ~= placeholders(text) then
			wrong[#wrong + 1] = text .. " -> " .. translated
		end
	end
	table.sort(missing) table.sort(extra) table.sort(wrong)
	eq(table.concat(missing, "\n"), "", file .. " lacks these texts")
	eq(table.concat(extra, "\n"), "", file .. " has texts enUS.lua does not")
	eq(table.concat(wrong, "\n"), "", file .. "'s placeholders differ from English's")
end

-- The texts the files show: every L["…"] literal, read as Lua reads it; one with an escaped quote in it
-- ends at its real end.
local function texts(source)
	local out = {}
	local at = 1
	while true do
		local s, e = string.find(source, '%f[%w_]L%["', at)
		if not s then break end
		local i = e + 1
		while string.sub(source, i, i) ~= '"' do
			i = i + (string.sub(source, i, i) == "\\" and 2 or 1)
		end
		out[#out + 1] = assert(load("return " .. string.sub(source, e, i)))()
		at = i + 1
	end
	return out
end
eq(table.concat(texts('x = L["a \\"b\\""] .. L["c"]'), "|"), 'a "b"|c', "a literal is read with its escapes")

local used, unlisted = {}, {}
for file, source in pairs(SOURCES) do
	if not file:find("^%a%a%u%u%.lua$") and file ~= "Locale.lua" then
		for _, text in ipairs(texts(source)) do
			used[text] = true
			if not english[text] then unlisted[#unlisted + 1] = file .. ": " .. text end
		end
	end
end
local unused = {}
for text in pairs(english) do
	if not used[text] then unused[#unused + 1] = text end
end
table.sort(unlisted) table.sort(unused)
eq(table.concat(unlisted, "\n"), "", "texts shown through ns.L that enUS.lua does not list")
eq(table.concat(unused, "\n"), "", "texts enUS.lua lists that no file shows")

-- The game's own text is read in the client's language: a client global string (ERR_AUCTION_SOLD_S) is
-- never backed by an English wording of the addon's, which would not match on a French client. The font
-- path and the number separator are no wording.
local NOT_WORDING = { STANDARD_TEXT_FONT = true, LARGE_NUMBER_SEPARATOR = true }
local fallbacks = {}
for file, source in pairs(SOURCES) do
	for name, text in string.gmatch(source, "%f[%w_]([%u][%u%d_]+) or \"([^\"]*)\"") do
		if not NOT_WORDING[name] and string.find(text, "%a") then
			fallbacks[#fallbacks + 1] = file .. ": " .. name .. " or \"" .. text .. "\""
		end
	end
end
table.sort(fallbacks)
eq(table.concat(fallbacks, "\n"), "", "client strings with an English fallback")

-- The locale files load before every file that shows text.
local toc = TOCS["GoldForever.toc"]
local first = toc:match("\n(Locales\\Locale%.lua)\nLocales\\enUS%.lua\nLocales\\frFR%.lua\n")
eq(first, "Locales\\Locale.lua", "the TOC loads Locale.lua, enUS.lua and frFR.lua together")
eq(toc:find("Locales\\Locale.lua", 1, true) < toc:find("Store\\Encode.lua", 1, true), true, "before the addon's own files")
return checks()
