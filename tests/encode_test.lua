-- Encode.lua: the compact row format of design 002.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
local E = ns.Encode

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

-- Free text for a catalogue row: commas become the look-alike, semicolons full stops, line breaks a space.
eq(E.text("Gold, more; less\r\nmore"), "Gold\226\128\154 more. less more", "free text in a row")
eq(E.text(""), nil, "no text")
eq(E.text(nil), nil, "nil text")

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

-- Item keys: the item ID, plus the suffix (7th field after the ID) only when it is set.
eq(E.itemKey("|cff1eff00|Hitem:14047::::::::30:::::::::|h[Runecloth]|h|r"), "14047", "plain item link")
eq(E.itemKey("|cff1eff00|Hitem:10221::::::612:0:30:::::::::|h[Gloves of the Bear]|h|r"), "10221:612", "random suffix")
eq(E.itemKey("item:10221:0:0:0:0:0:-19:0"), "10221:-19", "negative suffix kept raw")
eq(E.itemKey("item:2589:0:0:0:0:0:0:0"), "2589", "zero suffix is none")
eq(E.itemKey("|Hcurrency:1220|h[Resources]|h"), nil, "not an item")
eq(E.itemKey(nil), nil, "no link")

-- Loot sources from GUIDs.
eq(E.source("Creature-0-4620-0-12-7440-0000ABCDEF"), "n7440", "npc")
eq(E.source("Vehicle-0-4620-0-12-1234-0000ABCDEF"), "n1234", "vehicle is an npc")
eq(E.source("GameObject-0-4620-0-12-176583-0000ABCDEF"), "o176583", "object")
eq(E.source("Item-4620-0-4000000012345678"), nil, "items need the opened item's ID")
eq(E.source("Player-4620-006C0FC1"), nil, "players are never a source")
eq(E.source(nil), nil, "no guid")

-- Splits add up to the amount.
local parts = E.split(10, { 1, 1, 1 })
eq(parts[1] + parts[2] + parts[3], 10, "even split adds up")
eq(parts[1], 4, "remainder to the first share")
parts = E.split(100, { 30, 70 })
eq(parts[1] .. "/" .. parts[2], "30/70", "proportional split")
parts = E.split(5, { 0, 0 })
eq(parts[1] .. "/" .. parts[2], "3/2", "zero weights split evenly")

-- Market value: the cheapest 15% of units, averaged; the same as the web app's.
eq(E.marketValue({ { unit = 500, qty = 70 }, { unit = 100, qty = 10 }, { unit = 110, qty = 20 } }), math.floor((10 * 100 + 5 * 110) / 15), "cheapest 15% of 100 units")
eq(E.marketValue({ { unit = 9000, qty = 1 } }), 9000, "a single unit is its price")
eq(E.marketValue({}), nil, "no listings, no value")

-- Money as text.
eq(E.money(10925), "1g 9s 25c", "gold, silver and copper")
eq(E.money(2305), "23s 5c", "under a gold")
eq(E.money(37), "37c", "copper only")

-- XP gained, across a level-up too.
-- A whole stream at once: chunks of ROWS_PER_CHUNK rows, the same as appending row by row.
do
	local rows, appended = {}, {}
	for i = 1, E.ROWS_PER_CHUNK * 2 + 3 do
		rows[i] = tostring(i)
		E.append(appended, rows[i])
	end
	local chunks = E.chunks(rows)
	eq(#chunks, 3, "chunks for two full and a part")
	eq(table.concat(chunks, "|"), table.concat(appended, "|"), "chunks match appending")
	eq(#E.chunks({}), 0, "no rows, no chunks")
end

-- Keys, sources and lists, as several collectors read them.
eq(E.itemId("10221:612"), 10221, "item ID of a suffixed key")
eq(E.itemId(2589), 2589, "item ID of a number")
eq(E.itemId(nil), nil, "no key, no ID")
eq(E.npcOf("n7440"), 7440, "NPC of a source")
eq(E.npcOf("o1618"), nil, "an object is no NPC")
eq(E.npcId("Creature-0-4620-0-12-299-000A"), 299, "NPC of a GUID")
eq(E.npcId("Player-4620-006C0FC1"), nil, "a player is no NPC")
do
	local items = E.parseItems("2589*2+10221:612*1+2589*3")
	eq(items[2589], 5, "variants and repeats add up")
	eq(items[10221], 1, "a suffixed item by its ID")
	local columns = E.columns("t,char,map")
	eq(columns.map, 3, "a column by name")
	eq(next(E.columns(nil)), nil, "no declaration, no columns")
end

-- Patterns from the client's message formats, with captures.
do
	local link, n = string.match("You create: |cffffffff|Hitem:2996::::::::30|h[Bolt of Linen Cloth]|h|rx2.", E.pattern("You create: %sx%d."))
	eq(n, "2", "the count made")
	eq(E.itemId(E.itemKey(link)), 2996, "the item made")
	eq(string.match("Discovered Razor Hill: 55 experience gained", E.pattern("Discovered %s: %d experience gained")), "Razor Hill", "a discovery")
	eq(string.match("Discovered: Razor Hill", E.pattern("Discovered %s: %d experience gained")), nil, "no XP, no match")
	eq(string.match("Entdeckt: Klingenhügel (55 EP)", E.pattern("Entdeckt: %s (%d EP)")), "Klingenhügel", "parentheses escaped")
end

eq(E.xpGained(2570, 47400, 3010, false), 440, "within a level")
eq(E.xpGained(47000, 47400, 120, true), 520, "the rest of the old level plus the new one's")
eq(E.xpGained(3010, 47400, 2570, false), 0, "never negative")

-- Durations.
eq(E.duration(30), "under a minute", "seconds")
eq(E.duration(25 * 60), "25m", "minutes")
eq(E.duration(80 * 60), "1h 20m", "hours")

-- Day buckets are UTC.
eq(E.day(1792368000), "2026-10-19", "start of a UTC day")
eq(E.day(1792454399), "2026-10-19", "end of the same UTC day")

-- The flat market value agrees with the listing one, on many random scans.
math.randomseed(7)
for trial = 1, 200 do
	local list, flat = {}, {}
	for k = 1, math.random(1, 30) do
		local unit, qty = math.random(1, 50000), math.random(0, 200)
		list[k] = { unit = unit, qty = qty }
		flat[#flat + 1] = unit
		flat[#flat + 1] = qty
	end
	eq(E.marketValueFlat(flat), E.marketValue(list), "flat and listing market values agree, trial " .. trial)
	local low
	for _, l in ipairs(list) do low = (not low or l.unit < low) and l.unit or low end
	eq(E.cheapestFlat(flat), low, "the cheapest unit, trial " .. trial)
end
eq(E.marketValueFlat({}), nil, "no listings")

-- Base64, as the site's btoa: RFC 4648's vectors, round trips, and refusals.
for _, v in ipairs({ { "", "" }, { "f", "Zg==" }, { "fo", "Zm8=" }, { "foo", "Zm9v" }, { "foob", "Zm9vYg==" }, { "fooba", "Zm9vYmE=" }, { "foobar", "Zm9vYmFy" } }) do
	eq(E.base64(v[1]), v[2], "base64 of " .. v[1])
	eq(E.unbase64(v[2]), v[1], "back from " .. v[2])
end
eq(E.unbase64("Zm9v YmFy\n"), "foobar", "white space ignored")
eq(E.unbase64("Zm9"), nil, "a bad length")
eq(E.unbase64("Zm9!"), nil, "a character outside the alphabet")
eq(E.unbase64("Zg==Zg=="), nil, "padding only at the end")
local utf = "Guldsm\195\184r \226\128\153 \208\147"
eq(E.unbase64(E.base64(utf)), utf, "UTF-8 bytes round trip")

-- Party chat lines: plain, one line, at most 255 characters.
eq(E.chatLine("Rare: |cffff0000Bad|r (30) near 52.3, 34.1"), "[Gold Forever] Rare: cffff0000Badr (30) near 52.3, 34.1", "escapes out")
eq(E.chatLine("a\nb"), "[Gold Forever] a b", "one line")
eq(#E.chatLine(string.rep("x", 400)), 255, "within chat's limit")

return checks()
