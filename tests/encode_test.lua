-- Encode.lua: the compact row format of design 002.

-- The game has os.date as the global date; fengari lacks the "!" (UTC) prefix, so tests run
-- with TZ=UTC and the prefix is stripped.
date = function(format, t)
	if format:sub(1, 1) == "!" then
		format = format:sub(2)
	end
	return os.date(format, t)
end

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
local E = ns.Encode

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

-- Rows keep every declared column, empty included, so they match their declaration.
eq(E.row(1792407600, 1, 1452, 612, 384, "n7440", true, 2400, "14047*2"), "1792407600,1,1452,612,384,n7440,1,2400,14047*2", "full loot row")
eq(E.row(1792411000, 2, nil, nil, nil, "n10184", true, 52000, ""), "1792411000,2,,,,n10184,1,52000,", "instance loot keeps empty columns")
eq(E.row(1, false, nil), "1,,", "false and nil are empty")
eq(E.row(), "", "no columns")

-- Streams fill the last chunk up to ROWS_PER_CHUNK, then start a new one.
local stream = {}
for i = 1, E.ROWS_PER_CHUNK + 1 do
	E.append(stream, E.row(i, 1, "login"))
end
eq(#stream, 2, "a second chunk after ROWS_PER_CHUNK rows")
eq(E.count(stream[1]), E.ROWS_PER_CHUNK, "first chunk is full")
eq(stream[2], (E.ROWS_PER_CHUNK + 1) .. ",1,login", "second chunk holds the overflow")
local single = {}
E.append(single, "a")
E.append(single, "b")
eq(single[1], "a;b", "rows join with ;")

-- Item lists: stable order, suffix keys kept as given.
eq(E.items({ [14047] = 2, ["10221:612"] = 1, [2589] = 20 }), "10221:612*1+14047*2+2589*20", "items sorted as text")
eq(E.items({}), "", "no items")

-- Coordinates: 0–1 to 0–1000, rounded to in-game one-decimal precision.
eq(E.coord(0.6124), 612, "rounds down")
eq(E.coord(0.6125), 613, "rounds half up")
eq(E.coord(1), 1000, "upper edge")
eq(E.coord(nil), nil, "no position")

-- Names: commas would split a catalogue entry, so they become U+201A.
eq(E.name("Gloves, of the Bear"), "Gloves\226\128\154 of the Bear", "comma swapped")
eq(E.name("Black Lotus"), "Black Lotus", "plain name unchanged")

-- Day buckets are UTC.
eq(E.day(1792368000), "2026-10-19", "start of a UTC day")
eq(E.day(1792454399), "2026-10-19", "end of the same UTC day")

return checks
