-- The kernel holds the namespace, events, messages, the module lifecycle and helpers; the saved table is the
-- Store's (Store/). No Kernel/ file reaches into the save: not GoldForeverDB, ns.db() or this character's
-- entry ns.me(). What the kernel needs from the save the Store hands it.

-- The kernel and the Store on a stand-in client: enough to load them and run their ADDON_LOADED.
local handler
local time = 100
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetTime() return time end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
function print() end
SlashCmdList = {}
local ns = {}
for _, file in ipairs({ "Encode.lua", "Realms.lua", "Modules.lua", "Errors.lua", "Events.lua", "Chat.lua", "Commands.lua", "Save.lua", "Characters.lua", "Core.lua", "Schema.lua", "Migrations.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end

-- A call the client stops for running too long never returns (here: one that yields and is never resumed);
-- the next call, in a later frame, counts it in the save for /gf check.
local function stopsMidway(name)
	coroutine.wrap(function()
		ns.safely(name, coroutine.yield)
	end)()
end
stopsMidway("before the save")
time = 101
ns.safely("next", function() end)
handler(nil, "ADDON_LOADED", "GoldForever")
eq(GoldForeverDB.stopped, nil, "a call stopped before the save is loaded is not counted")
stopsMidway("long")
time = 102
ns.safely("next", function() end)
eq(GoldForeverDB.stopped and GoldForeverDB.stopped.long and GoldForeverDB.stopped.long.n, 1, "a stopped call is counted under its name")
stopsMidway("long")
time = 103
ns.safely("next", function() end)
eq(GoldForeverDB.stopped.long.n, 2, "and again each time")
eq(GoldForeverDB.stopped.next, nil, "a call that returns is not")

-- A listener added while its event is dispatched (an addon loaded on demand at AUCTION_HOUSE_SHOW
-- subscribing to it) first hears the next one, so what the event started is not done twice.
local heard = {}
ns.on("GF_TEST_EVENT", "first", function()
	heard[#heard + 1] = "first"
	if #heard == 1 then
		ns.on("GF_TEST_EVENT", "added", function()
			heard[#heard + 1] = "added"
		end)
	end
end)
handler(nil, "GF_TEST_EVENT")
eq(table.concat(heard, ", "), "first", "a listener added during its event does not hear that one")
handler(nil, "GF_TEST_EVENT")
eq(table.concat(heard, ", "), "first, first, added", "it hears the next")

local function savedFields(source)
	local reads = nsNames(source)
	local found = {}
	for _, name in ipairs({ "db", "me" }) do
		if reads[name] then
			found[#found + 1] = "ns." .. name .. " at line " .. reads[name]
		end
	end
	local n = 0
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		n = n + 1
		if line:gsub('"[^"]*"', '""'):gsub("%-%-.*$", ""):find("GoldForeverDB", 1, true) then
			found[#found + 1] = "GoldForeverDB at line " .. n
			break
		end
	end
	return found
end

local kernel = 0
for file, source in pairs(SOURCES) do
	if PATHS[file]:find("^Kernel\\") then
		kernel = kernel + 1
		eq(table.concat(savedFields(source), ", "), "", file .. " indexes no saved-table field")
	end
end
eq(kernel > 0, true, "the Kernel/ files are read")

-- The scan sees each way into the save, and not one in a comment or a string.
eq(table.concat(savedFields("local c = ns.db().client"), ", "), "ns.db at line 1", "ns.db() read")
eq(table.concat(savedFields("\nlocal realm = ns.me() and ns.me().realm"), ", "), "ns.me at line 2", "ns.me() read")
eq(table.concat(savedFields("GoldForeverDB.errors = {}"), ", "), "GoldForeverDB at line 1", "the saved table by its global")
eq(table.concat(savedFields('-- ns.db().errors and GoldForeverDB\nprint("ns.db() GoldForeverDB")'), ", "), "", "comments and strings are neither")
-- /gf check: the popup gets the text of its chat lines, without the chat's colours and coin icons, so a
-- copy pastes as plain text.
do
	local said, popup = {}, nil
	function print(line) said[#said + 1] = line end
	ns.listen("checked", "test", function(text) popup = text end)
	ns.commands.check()
	function print() end
	local lines = {}
	for line in (popup or ""):gmatch("[^\n]+") do
		lines[#lines + 1] = line
	end
	eq(#lines, #said, "the popup has a line for each chat line")
	eq(lines[1], "Gold Forever " .. ns.VERSION .. " · schema " .. ns.SCHEMA .. " · " .. GoldForeverDB.client.build, "its first line, plain")
	eq((popup or "|"):find("|", 1, true), nil, "no colour or icon escapes")
	eq((popup or ""):find("long stopped by the client for running too long", 1, true) ~= nil, true, "the stopped call, plain")
end
eq(ns.plainText("|cffe0ac45Gold Forever|r: 1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 23|TInterface\\MoneyFrame\\UI-SilverIcon:0:0:2:0|t"),
	"Gold Forever: 1g 23s", "coin icons read as g, s and c")
eq(ns.plainText("5|A:coin-copper:0:0|a"), "5c", "coin atlases too")
return checks()
