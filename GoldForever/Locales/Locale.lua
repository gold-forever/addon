-- Gold Forever: the text the addon shows, in the client's language (GetLocale()). English is the source:
-- each file writes L["English text"], enUS.lua lists every such text, and a language's file (frFR.lua)
-- gives its own for each. A text a language lacks shows in English. Another language is one more file
-- like frFR.lua, listed in the TOCs after enUS.lua. The save is never translated: only what is shown.

local _, ns = ...

local Locale = {}
ns.Locale = Locale

Locale.code = GetLocale and GetLocale() or "enUS"
Locale.english = {} -- text -> true, every text the addon shows (enUS.lua)
Locale.languages = {} -- code -> { text -> translation }, every language's file, for the tests

-- How a language picks between a count's singular and plural: English's one is 1 alone, French's 0 and 1.
local SINGULAR = {
	frFR = function(n) return n >= 0 and n < 2 end,
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
		end
	end
end

-- Whether the client shows the addon in a language other than its source (the AI-translation notice).
function Locale.translated()
	return Locale.languages[Locale.code] ~= nil
end

-- One of two texts by a count, formatted with the count and the rest: ns.plural(n, L["%d craft"], L["%d crafts"]).
function ns.plural(n, one, other, ...)
	return string.format(singular(n) and one or other, n, ...)
end
