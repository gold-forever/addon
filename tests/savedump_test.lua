-- savedump.lua, the text the smoke runs' saves are compared by with their golden copies (run.js).
local Dump = assert(load(SAVEDUMP, "@savedump.lua"))()

eq(Dump.save({ b = 1, a = { [2] = "x", [10] = true, z = "q" } }), 'a[2] = "x"\na[10] = true\na.z = "q"\nb = 1\n',
	"one line a value, keys sorted, numbers first and in number order")
eq(Dump.save({ catalogue = { names = {} }, odd = { ["two words"] = 1 } }), 'catalogue.names = {}\nodd["two words"] = 1\n',
	"an empty table is a line; a key that is no name is quoted")
eq(Dump.save({ note = "a\nb" }), 'note = "a\\nb"\n', "a line break in a value stays on its line")

-- Scan rows in any order and chunking come out the same.
local one = Dump.save({ scans = { { market = "m", rows = { "3,1;1,9", "2,5" } } } })
local other = Dump.save({ scans = { { market = "m", rows = { "2,5;3,1", "1,9" } } } })
eq(one, other, "a scan's rows compared as one sorted list")
eq(one, 'scans[1].market = "m"\nscans[1].rows: "1,9"\nscans[1].rows: "2,5"\nscans[1].rows: "3,1"\n', "one row a line")

local before = { addon = "1.0", gone = "x", catalogue = { tooltips = { [1] = "a", [2] = "b" }, items = { [7] = "i" } },
	scans = { { market = "m", t = 1, rows = { "1,1;2,2" } }, { market = "n", t = 2, rows = { "5,5" } } } }
local after = { addon = "1.1", catalogue = { tooltips = { [2] = "b" }, items = { [7] = "i", [8] = "j" } }, settings = { look = "web" },
	scans = { { market = "n", t = 2, rows = { "5,5" } }, { market = "m", t = 1, rows = { "2,2;3,3" } } } }
eq(Dump.changes(before, after), table.concat({
	"- addon gone",
	'+ addon = "1.1"',
	'+ catalogue.items[8] = "j"',
	"- catalogue.tooltips: [1]",
	"- scans order = m@1 n@2",
	"+ scans order = n@2 m@1",
	'- scans["m@1"].rows: "1,1"',
	'+ scans["m@1"].rows: "3,3"',
	'+ settings.look = "web"',
}, "\n") .. "\n", "what changed: values gone by key, values new and changed, scans matched by market and time")
eq(Dump.changes(before, { addon = "1.0", gone = "x" }), "- catalogue (3 lines)\n- scans (7 lines)\n", "a table gone, as its line count")
return checks()
