-- Gold Forever: the text the addon shows, in the client's language (GetLocale()). English is the source:
-- each file writes L["English text"], enUS.lua lists every such text, and a language's file (frFR.lua)
-- gives its own for each. A text a language lacks shows in English. Another language is one more file
-- like frFR.lua, listed in the TOCs after enUS.lua; a client whose language differs from another's in a few
-- words (esMX from esES) is a variant in that language's file. A language's file returns at once on another
-- client, so only English and the client's language are ever built. The save is never translated: only what is shown.

local _, ns = ...

local Locale = {}
ns.Locale = Locale

Locale.code = GetLocale and GetLocale() or "enUS"
Locale.english = {} -- text -> true, every text the addon shows (enUS.lua)
Locale.languages = {} -- code -> { text -> translation }, the client's language once built, for the tests
local sources = {} -- a translation shown -> its English text

-- How a language picks between a count's singular and plural: English's one is 1 alone, French's and
-- Brazilian Portuguese's 0 and 1.
local function zeroOrOne(n) return n >= 0 and n < 2 end
local SINGULAR = {
	frFR = zeroOrOne,
	ptBR = zeroOrOne,
}
local function singular(n)
	return (SINGULAR[Locale.code] or function(m) return m == 1 end)(n)
end

-- ns.L[text]: the text in the client's language, else in English; a text no file lists shows as it is.
local L = setmetatable({}, { __index = function(_, text) return text end })
ns.L = L

-- enUS.lua: the source texts.
function Locale.source(texts)
	for _, text in ipairs(texts) do
		Locale.english[text] = true
	end
end

-- A language's file: its translations, used when the client is in that language.
function Locale.add(code, texts)
	Locale.languages[code] = texts
	if code == Locale.code then
		for text, translated in pairs(texts) do
			rawset(L, text, translated)
			sources[translated] = text
		end
	end
end

-- A client's language that is another's but for a few words (esMX, esES's): every text of the base, with
-- those overridden, built on that client alone. It follows the base's Locale.add, and lets the base go.
function Locale.variant(code, base, overrides)
	if code ~= Locale.code then
		return
	end
	local texts = {}
	for text, translated in pairs(Locale.languages[base]) do
		texts[text] = translated
	end
	Locale.languages[base] = nil
	for text, translated in pairs(overrides) do
		texts[text] = translated
	end
	Locale.add(code, texts)
end

-- The English text of one shown in the client's language, for names the save keeps (an error's).
function Locale.sourceOf(shown)
	return sources[shown] or shown
end

-- Whether the client shows the addon in a language other than its source (the AI-translation notice).
function Locale.translated()
	return Locale.languages[Locale.code] ~= nil
end

-- One of two texts by a count, formatted with the count and the rest: ns.plural(n, L["%d craft"], L["%d crafts"]).
function ns.plural(n, one, other, ...)
	return string.format(singular(n) and one or other, n, ...)
end

-- A text in capitals, accented letters too (string.upper leaves é as it is): à-þ are the capitals'
-- second byte plus 32 in UTF-8, ÷ is no letter.
function ns.upper(text)
	return (string.gsub(string.upper(text), "\195([\160-\190])", function(c)
		return c == "\183" and "\195\183" or "\195" .. string.char(string.byte(c) - 32)
	end))
end
