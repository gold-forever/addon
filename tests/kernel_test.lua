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
return checks()
