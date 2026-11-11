-- The shared glossary (gold-forever docs/i18n/glossary.md, run.js reads it as GLOSSARY) decides the game's and
-- the site's words: in every language it fills, a text whose English says a term (a whole word) says one of
-- that language's forms of it, any case, ' and ’ alike.

-- Texts that use a term's English word in another sense: the glossary's kill and vendor are nouns (a kill
-- counted, a merchant), these say the verbs.
local OTHER_SENSE = {
	["Loot or kill something to start a session."] = "kill",
	["Loot or kill something to start a session. A break of 15 minutes ends it."] = "kill",
	["A small mark on each bag and bank item: post, vendor or disenchant."] = "vendor",
	["On a bag or bank item: post, vendor, disenchant or keep, and why."] = "vendor",
}

local FILES = { frFR = "frFR.lua", deDE = "deDE.lua", esES = "esES.lua", esMX = "esES.lua", ptBR = "ptBR.lua",
	koKR = "koKR.lua", zhCN = "zhCN.lua", zhTW = "zhTW.lua", itIT = "itIT.lua", ruRU = "ruRU.lua" }

-- Every language's texts, as its own client builds them.
local function texts(code)
	GetLocale = function() return code end
	local ns = {}
	for _, file in ipairs({ "Locale.lua", "enUS.lua", FILES[code] }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	GetLocale = nil
	return ns.Locale.languages[code], ns.Locale.english, ns.upper
end

local function trim(s) return (string.gsub(s, "^%s*(.-)%s*$", "%1")) end
local function cells(line)
	local out = {}
	for cell in string.gmatch(string.sub(line, 2), "([^|]*)|") do out[#out + 1] = trim(cell) end
	return out
end
local function forms(cell)
	local out = {}
	for form in string.gmatch((string.gsub(cell, "%b()", "")) .. "/", "([^/]*)/") do
		if trim(form) ~= "" then out[#out + 1] = trim(form) end
	end
	return out
end

-- The table: its header names the client codes; each row is a term, its English forms first.
local codes, terms = nil, {}
for line in string.gmatch(GLOSSARY, "[^\n]+") do
	if string.find(line, "^| enUS |") then
		codes = cells(line)
	elseif codes and string.find(line, "^| ") then
		local row = cells(line)
		local term = { english = forms(row[1]) }
		for i = 2, #codes do term[codes[i]] = forms(row[i] or "") end
		terms[#terms + 1] = term
	end
end
eq(codes and codes[1], "enUS", "the glossary has its table, English first")
eq(#terms > 10, true, "the glossary lists its terms")

-- What a text says, for comparing: capitals (accented ones too), one apostrophe, no /gf command (a command
-- is typed as it is, in every language).
-- Cyrillic folded too (а-п \208\176-\191 to \208\144-\159, р-я \209\128-\143 to \208\160-\175, ё to Ё):
-- the client's ns.upper folds Latin-1's letters alone.
local function cyrillic(text)
	text = string.gsub(text, "\208([\176-\191])", function(c) return "\208" .. string.char(string.byte(c) - 32) end)
	return (string.gsub(text, "\209([\128-\143\145])", function(c)
		return c == "\145" and "\208\129" or "\208" .. string.char(string.byte(c) + 32)
	end))
end
local function said(text, upper)
	text = string.gsub(text, "/gf[%w%s|<>#%[%]]*", " ")
	return cyrillic(upper((string.gsub(text, "\226\128\153", "'"))))
end
eq(said("Сессия ёжика · сессии", function(t) return t end), "СЕССИЯ ЁЖИКА · СЕССИИ", "Cyrillic compared in any case")
local function escape(s) return (string.gsub(s, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")) end

local found = {}
for _, code in ipairs({ "frFR", "deDE", "esES", "esMX", "ptBR", "koKR", "zhCN", "zhTW", "itIT", "ruRU" }) do
	local translated, english, upper = texts(code)
	local wrong = {}
	for _, term in ipairs(terms) do
		local own = term[code] or {}
		if #own > 0 then
			for text in pairs(english) do
				local en = said(text, upper)
				local says = false
				for _, form in ipairs(term.english) do
					says = says or string.find(en, "%f[%w]" .. escape(upper(form)) .. "%f[%W]") ~= nil
				end
				if says and OTHER_SENSE[text] ~= term.english[1] then
					local there, ok = said(translated[text] or "", upper), false
					for _, form in ipairs(own) do
						ok = ok or string.find(there, said(form, upper), 1, true) ~= nil
					end
					if not ok then
						wrong[#wrong + 1] = term.english[1] .. " (" .. table.concat(own, " / ") .. "): " .. text .. " -> " .. tostring(translated[text])
					end
				end
			end
		end
	end
	table.sort(wrong)
	if #wrong > 0 then found[#found + 1] = code .. ", " .. #wrong .. " texts:\n  " .. table.concat(wrong, "\n  ") end
end
eq(table.concat(found, "\n"), "", "texts that say a term otherwise than the glossary")

return checks()
