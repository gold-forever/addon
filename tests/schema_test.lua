-- ns.record (Store/Schema.lua): a row by column name, written in the order the schema declares, to today's
-- bucket of its stream; a stream or column the schema does not have is recorded as an error, not raised.

-- Core.lua and Schema.lua on a stand-in client: enough to load them and run their ADDON_LOADED.
local handler
local said = {}
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
function print(text) said[#said + 1] = text end
unpack = table.unpack
SlashCmdList = {}
local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
assert(load(SOURCES["Core.lua"], "@Core.lua"))("GoldForever", ns)
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
ns.FIELDS.trial = "t,char,kind,price"
handler(nil, "ADDON_LOADED", "GoldForever")

local function today(stream)
	local bucket = GoldForeverDB.events[ns.Encode.day(GetServerTime())] or {}
	return table.concat(bucket[stream] or {}, ";")
end

ns.record("trial", { price = 250, kind = "sell", char = 1, t = 1761148800 })
eq(today("trial"), "1761148800,1,sell,250", "a row's values in the schema's column order")
ns.record("trial", { t = 1761148801, char = 1, kind = "buy" })
eq(today("trial"), "1761148800,1,sell,250;1761148801,1,buy,", "a column left out is empty, the row as long as its declaration")
ns.record("trial", { t = 1761148802, char = 1, kind = true, price = false })
eq(today("trial"), "1761148800,1,sell,250;1761148801,1,buy,;1761148802,1,1,", "true and false as Encode.row writes them")
eq(GoldForeverDB.errors.record, nil, "rows the schema declares record no error")

-- A row ns.append is given by hand comes out the same through ns.record.
ns.append("sys", ns.Encode.row(1761148800, 1, "login"))
ns.record("sys", { t = 1761148800, char = 1, kind = "login" })
eq(today("sys"), "1761148800,1,login;1761148800,1,login", "the same row as ns.append(Encode.row(...))")

local ok = pcall(ns.record, "nosuch", { t = 1 })
eq(ok, true, "an unknown stream is not raised")
eq(today("nosuch"), "", "an unknown stream writes nothing")
eq(GoldForeverDB.errors.record and GoldForeverDB.errors.record.msg, "no stream nosuch in the schema", "an unknown stream is recorded as an error")

ok = pcall(ns.record, "trial", { t = 1761148803, char = 1, kind = "sell", cost = 5 })
eq(ok, true, "a column the schema does not have is not raised")
eq(today("trial"), "1761148800,1,sell,250;1761148801,1,buy,;1761148802,1,1,", "a row with an unknown column writes nothing")
eq(GoldForeverDB.errors.record.msg, "trial has no column cost in the schema", "an unknown column is recorded as an error")
eq(GoldForeverDB.errors.record.n, 2, "each refused row counts")
eq(#said, 1, "the player is told once, as for any failing collector")

-- Rows reach the save through ns.record: these files still append their own (ns.append, Encode.append);
-- the list only shrinks. A file that switches leaves it, and a new one fails here.
local KNOWN = {
	"Auctions.lua",
	"Core.lua",
	"Ledger.lua",
	"Levelling.lua",
	"Loot.lua",
	"Professions.lua",
	"Rares.lua",
}

local function appendsItself(source)
	if nsNames(source).append then
		return true
	end
	for line in source:gmatch("[^\n]+") do
		if line:gsub("%-%-.*$", ""):find("Encode%.append%s*%(") then
			return true
		end
	end
	return false
end
local appending = {}
for file, source in pairs(SOURCES) do
	if not PATHS[file]:find("^Store\\") and appendsItself(source) then
		appending[#appending + 1] = file
	end
end
table.sort(appending)
eq(table.concat(appending, ", "), table.concat(KNOWN, ", "), "the files that append rows to the save themselves")

-- The scan sees either append called, and not one in a comment or ns.record.
eq(appendsItself('ns.append("loot", row)'), true, "ns.append called")
eq(appendsItself("Encode.append(bucket, row)"), true, "Encode.append called")
eq(appendsItself('ns.record("loot", row) -- not ns.append(…) nor Encode.append(…)'), false, "ns.record, and appends in a comment")
-- Every stream and its columns are declared in Store/Schema.lua: a file elsewhere that adds to ns.FIELDS
-- fails here.
local function declaresFields(source)
	for line in source:gmatch("[^\n]+") do
		local code = line:gsub("%-%-.*$", "")
		if code:find("ns%.FIELDS%.[%w_]+%s*=[^=]") or code:find("ns%.FIELDS%s*%b[]%s*=[^=]") or code:find("ns%.FIELDS%s*=[^=]") then
			return true
		end
	end
	return false
end
local declaring = {}
for file, source in pairs(SOURCES) do
	if not PATHS[file]:find("^Store\\") and declaresFields(source) then
		declaring[#declaring + 1] = file
	end
end
table.sort(declaring)
eq(table.concat(declaring, ", "), "", "the files outside Store/ that add to ns.FIELDS")

-- The scan sees a declaration, and not a read, a comparison or one in a comment.
eq(declaresFields('ns.FIELDS.loot = "t,char"'), true, "a column list declared")
eq(declaresFields('ns.FIELDS["loot"] = "t,char"'), true, "declared by a quoted key")
eq(declaresFields('local cols = Encode.columns(ns.FIELDS.item) if ns.FIELDS.x == y then end -- ns.FIELDS.z = "a"'), false,
	"a read, a comparison and a comment")
return checks()
