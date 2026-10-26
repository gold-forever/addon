-- The windows read the save only through what the rest of the addon works out from it (ReadModels/): a
-- window that indexes ns.db breaks when the way data is recorded changes. No Surfaces/ file does; a new
-- one fails here.

local KNOWN = {}

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
