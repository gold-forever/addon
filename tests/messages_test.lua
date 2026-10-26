-- Messages between modules, not calls into each other's tables: a file tells the layers above it what
-- happened with ns.emit, and those that care ns.listen (Kernel/Events.lua). A file never reads a name on
-- ns that only a layer above its own sets, never sets a name another file sets, and keeps no listeners of
-- its own; every message listened to is one a file emits.

-- The layers, lowest first: a file reads what its own layer and those below it set.
local LAYERS = { "Kernel", "Store", "Recording", "ReadModels", "Tools", "UIKit", "Surfaces" }
local rank = {}
for i, layer in ipairs(LAYERS) do
	rank[layer] = i
end
local function layerOf(file)
	return rank[PATHS[file]:match("^([^\\]+)\\")]
end
local layers = 0
for file in pairs(SOURCES) do
	eq(layerOf(file) ~= nil, true, file .. " is in a layer folder")
	layers = layers + 1
end
eq(layers > 0, true, "the addon's files are read")

-- The lowest layer that sets each name.
local lowest = {}
for file, source in pairs(SOURCES) do
	for name in pairs(select(2, nsNames(source))) do
		lowest[name] = math.min(lowest[name] or math.huge, layerOf(file))
	end
end

-- These files still read a name only a layer above sets, each with why it stays; the list only shrinks
-- (addon#40). None is a call a message would replace: each is a query of a helper that sits above its reader.
local KNOWN = {
	["Commands.lua ns.stopped"] = "the Store's switch that stops the addon for a session; the kernel asks it before a command",
	["Events.lua ns.stopped"] = "the Store's switch that stops the addon for a session; the kernel asks it before each handler",
	["Modules.lua ns.stopped"] = "the Store's switch that stops the addon for a session; the kernel asks it before each module",
	["Money.lua ns.Theme"] = "the UI kit's money colours, for the coloured money text",
	["Realms.lua ns.Encode"] = "the Store's row encoding, for the item rows of Realms.itemRow",
	["Advisor.lua ns.makeWindow"] = "the loot advisor's window, which sits with its read model",
	["Advisor.lua ns.applyLook"] = "the loot advisor's window, which sits with its read model",
	["Advisor.lua ns.UI"] = "the loot advisor's window, which sits with its read model",
	["Dings.lua ns.DataFormat"] = "the data file's contract (rule 8): the dings switch reads the companion's side from it",
	["Inventory.lua ns.Views"] = "the read models' list of places items are held, for the Held tooltip index",
	["Market.lua ns.Scans"] = "the read model's market groups, for which scans the save keeps on retail",
	["MobStats.lua ns.price"] = "the read model's prices, to value what each NPC dropped",
	["Session.lua ns.Views"] = "the read model's kill credit, for the session's kills",
	["Session.lua ns.price"] = "the read model's prices, to value the session's loot",
	["MailHelper.lua ns.Theme"] = "the mail helper's panel, which sits with its tool",
	["MailHelper.lua ns.UI"] = "the mail helper's panel, which sits with its tool",
	["AuctionWaits.lua ns.Theme"] = "the auction panel's sizes, which sit with its waits",
}
local known = {}
for entry, why in pairs(KNOWN) do
	known[#known + 1] = entry
	eq(why ~= "", true, entry .. " says why it stays")
end
table.sort(known)

local function readsUp(file, source)
	local found = {}
	local reads, sets = nsNames(source)
	for name in pairs(reads) do
		if not sets[name] and lowest[name] and lowest[name] > layerOf(file) then
			found[#found + 1] = file .. " ns." .. name
		end
	end
	return found
end
local up = {}
for file, source in pairs(SOURCES) do
	for _, entry in ipairs(readsUp(file, source)) do
		up[#up + 1] = entry
	end
end
table.sort(up)
eq(table.concat(up, ", "), table.concat(known, ", "), "the files that read a name only a layer above sets")

-- Each name on ns is set by one file: a second that sets it again replaces the first's.
local setBy = {}
for file, source in pairs(SOURCES) do
	for name in pairs(select(2, nsNames(source))) do
		setBy[name] = setBy[name] or {}
		table.insert(setBy[name], file)
	end
end
local twice = {}
for name, files in pairs(setBy) do
	if #files > 1 then
		table.sort(files)
		twice[#twice + 1] = "ns." .. name .. " (" .. table.concat(files, ", ") .. ")"
	end
end
table.sort(twice)
eq(table.concat(twice, ", "), "", "the names more than one file sets")

-- No file keeps its own listeners (ns.onSomething(fn)): ns.listen is the one way to hear a message.
local function ownListeners(source)
	local found = {}
	for name in pairs(select(2, nsNames(source))) do
		if name:find("^on%u") then
			found[#found + 1] = "ns." .. name
		end
	end
	table.sort(found)
	return table.concat(found, ", ")
end
for file, source in pairs(SOURCES) do
	eq(ownListeners(source), "", file .. " keeps no listeners of its own")
end

-- Every message listened to is emitted by a file: one renamed on one side only is never heard, silently.
local function messages(source, verb)
	local found = {}
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		for name in line:gsub("%-%-.*$", ""):gmatch("ns%." .. verb .. "%(%s*\"([^\"]+)\"") do
			found[name] = true
		end
	end
	return found
end
local emitted, listened = {}, {}
for _, source in pairs(SOURCES) do
	for name in pairs(messages(source, "emit")) do
		emitted[name] = true
	end
	for name in pairs(messages(source, "listen")) do
		listened[name] = true
	end
end
local heard = 0
for name in pairs(listened) do
	eq(emitted[name], true, "the message \"" .. name .. "\" is emitted by a file")
	heard = heard + 1
end
eq(heard > 0, true, "the messages listened to are read")

-- The scans see what they look for, and not a comment or a string.
local reads = readsUp("Loot.lua", 'local x = ns.openPage("home") -- ns.UI\nlocal s = "ns.Theme"')
eq(table.concat(reads, ", "), "Loot.lua ns.openPage", "a collector reading a hub function")
eq(ownListeners("function ns.onBagsRead(fn) end\nns.on(\"BAG_UPDATE\", \"x\", f) -- ns.onX = f"), "ns.onBagsRead", "a list of its own")
local said = messages('ns.emit("bagsRead") ns.emit( "lookChanged", x) -- ns.emit("old")', "emit")
eq(said.bagsRead and said.lookChanged and not said.old, true, "messages emitted, and not one in a comment")
return checks()
