-- The windows read the save only through what the rest of the addon works out from it: a window that
-- indexes ns.db breaks when the way data is recorded changes. These Surfaces/ files still do; the list
-- only shrinks. A file that stops reading ns.db leaves it, and a new one fails here.

local KNOWN = {
	"CraftQueue.lua",
	"ExportFrame.lua",
	"UiDebug.lua",
}

local reading = {}
for file, source in pairs(SOURCES) do
	if PATHS[file]:find("^Surfaces\\") and nsNames(source).db then
		reading[#reading + 1] = file
	end
end
table.sort(reading)
eq(table.concat(reading, ", "), table.concat(KNOWN, ", "), "the Surfaces/ files that index ns.db")

-- The scan sees ns.db read, and not ns.dbVersion, a string or a comment.
eq(nsNames("local rows = ns.db.loot").db ~= nil, true, "ns.db read")
eq(nsNames('local v = ns.dbVersion print("ns.db") -- ns.db').db, nil, "ns.db not read")
return checks()
