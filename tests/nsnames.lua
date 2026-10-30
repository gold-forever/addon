-- The names a file reads and sets on the addon's shared table (`ns.name`), read from its source with the
-- comments and strings taken out. A file that calls a name no file sets fails silently in game (review
-- A-2: a rename left the craft queue empty, no error), so names_test.lua and the smoke run check them.
--   nsNames(source) -> reads, sets: name -> the first line it is on

-- Names that are nil until play sets them: what the last loot window or quest was, the last scan, and
-- the hub pages made when first shown. Every other name read is set once the files are loaded.
NS_OPTIONAL = {
	lootAt = true, lootSource = true, questAt = true, -- Loot.lua and Ledger.lua, at a loot or a quest
	repairAt = true, -- Trade.lua, at a repair
	scanVersion = true, lastScan = true, -- Market.lua, after a scan
	listsPage = true, rulesPage = true, -- the hub pages, when built
}

function nsNames(source)
	local reads, sets = {}, {}
	local n = 0
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		n = n + 1
		line = line:gsub("\\.", "__"):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
		-- " " first, so a name at the line's start has a character before it like the rest.
		for before, name, after in (" " .. line):gmatch("([^%w_.])ns%.([%a_][%w_]*)(%s*=?=?)") do
			local into = (after:match("=$") and not after:match("==$")) and sets or reads
			into[name] = into[name] or n
		end
		for name in line:gmatch("function%s+ns%.([%a_][%w_]*)") do
			sets[name] = sets[name] or n
		end
		-- ns.a, ns.b = …
		local list = line:match("^%s*(ns%.[%a_][%w_]*%s*,[%w_.,%s]+)=[^=]")
		if list then
			for name in list:gmatch("ns%.([%a_][%w_]*)") do
				sets[name] = sets[name] or n
			end
		end
	end
	return reads, sets
end
