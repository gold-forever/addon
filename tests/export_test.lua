-- Export.lua: the in-game export string of design 005 (GF1: base64 of deflated Lua table text).

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Export.lua"], "@Export.lua"))("GoldForever", ns)
local X = ns.Export

-- The Lua text the site's parser reads, keys in a stable order so the same data gives the same text.
eq(X.serialize({ b = 2, a = "x\"y\n", [3] = true, [1] = 1.5 }), '{[1]=1.5,[3]=true,["a"]="x\\"y\\n",["b"]=2}', "a table, sorted keys")
eq(X.serialize({ list = { "a", "b" } }), '{["list"]={[1]="a",[2]="b"}}', "nested arrays")
eq(X.serialize({ n = -12 }), '{["n"]=-12}', "a negative integer")
-- The client's string.format("%d") stops at 2^31 ("integer overflow attempting to store"); copper does not.
do
	local format = string.format
	string.format = function(spec, value, ...)
		if spec == "%d" and math.abs(value) >= 2 ^ 31 then
			error("integer overflow attempting to store " .. tostring(value))
		end
		return format(spec, value, ...)
	end
	local ok, text = pcall(X.serialize, { money = 9132822274, debt = -9132822274 })
	string.format = format
	eq(text, '{["debt"]=-9132822274,["money"]=9132822274}', "copper past 2^31")
end

-- What goes in: every character, the event days from the last export's day on, and the scans
-- newer than it. Older days and scans were in the last export.
local day = function(t) return ns.Encode.day(t) end
local db = {
	schema = 1, addon = "0.12.0", fields = { loot = "t" }, client = { build = "1.60" },
	characters = { c1 = { name = "Testchar" } },
	events = { [day(1000000)] = { loot = { "a" } }, [day(1000000 + 3 * 86400)] = { loot = { "b" } } },
	scans = { { t = 1000000 + 100, market = "m" }, { t = 1000000 + 3 * 86400, market = "m" } },
	guildBanks = {}, catalogue = { items = { [2589] = "Linen" } },
	settings = { share = false }, errors = { boom = "x" },
}
db.catalogue.items[2592] = "Wool"
db.exportSent = { items = { [2589] = true } }
local picked = X.select(db, 1000000 + 86400, 1000000 + 4 * 86400)
eq(picked.catalogue.items[2589], nil, "a catalogue entry sent before stays out")
eq(picked.catalogue.items[2592], "Wool", "a new catalogue entry goes in")
X.markSent(db, picked)
eq(db.exportSent.items[2592], true, "and is remembered as sent")
eq(X.select(db, nil, 1).catalogue.items[2589], "Linen", "the first export, or export all, holds the whole catalogue")
-- Recorded as sent in the save: the time the next export starts from, and what it held.
local sentBefore = db.exportSent
ns.db = function() return db end
db.exportSent = nil
X.recordSent(picked, 1000000 + 4 * 86400)
eq(db.exportedAt, 1000000 + 4 * 86400, "recorded as sent: the next export starts from it")
eq(db.exportSent.items[2592], true, "and what it held is remembered as sent")
ns.db, db.exportedAt, db.exportSent = nil, nil, sentBefore
eq(picked.characters.c1.name, "Testchar", "characters, always")
eq(picked.events[day(1000000)], nil, "an event day before the last export's")
eq(picked.events[day(1000000 + 3 * 86400)].loot[1], "b", "an event day after it")
eq(#picked.scans, 1, "only the newer scan")
eq(picked.export.since, 1000000 + 86400, "says what it is new since")
eq(picked.errors, nil, "the addon's own errors stay in the game")
eq(picked.settings, nil, "and its settings")
eq(X.select(db, nil, 1).events[day(1000000)].loot[1], "a", "the first export holds every day")
db.scans = {
	{ t = 10, market = "a", kind = "full" }, { t = 30, market = "a", kind = "full" },
	{ t = 20, market = "b", kind = "full" }, { t = 40, market = "a", kind = "throttled" },
}
local firstScans = X.select(db, nil, 50).scans
eq(#firstScans, 2, "the first export holds each market's newest full scan")
eq(firstScans[1].t + firstScans[2].t, 50, "those are a's at 30 and b's at 20")

-- Standard base64, which the site decodes with the JDK.
eq(X.base64(""), "", "empty")
eq(X.base64("f"), "Zg==", "one byte")
eq(X.base64("fo"), "Zm8=", "two bytes")
eq(X.base64("foo"), "Zm9v", "three bytes")
eq(X.base64("\0\255\128"), "AP+A", "binary")
eq(X.base64, ns.Encode.base64, "the one base64, Encode's")

-- A part's DEFLATE made to go on: its last-block bit and LibDeflate's 1-bit padding cleared, then an empty
-- stored block (in the padding when three bits fit, else one byte more) to the next byte boundary.
eq(X.joinable("\203\229", 3), "\202\5\0\0\255\255", "three bits of padding hold the stored block's header")
eq(X.joinable("\203\255", 1), "\202\127\0\0\0\255\255", "one bit does not: a byte more")
eq(X.joinable("\203\7", 0), "\202\7\0\0\0\255\255", "no padding")
eq(X.joinable("\255", 2), "\62\0\0\0\255\255", "one byte, first and last")

-- Built a little at a time (review B-1): with a frame's share used at every check it takes many steps,
-- the text cut into parts of PART bytes, each deflated alone, the last as the last; the same string
-- as built at once.
local part = X.PART
X.PART = 64
local function deflate(text)
	return "<" .. text .. ">", 0
end
local step, steps = X.builder(db, nil, 50, deflate), 0
local text, held
repeat
	steps = steps + 1
	text, held = step(function()
		return true
	end)
until text or steps > 10000
eq(steps > 10, true, "many steps")
eq(held.export.t, 50, "and what it holds")
eq(text, (X.build(db, nil, 50, deflate)), "the same string as built at once")
local joined = ns.Encode.unbase64(string.sub(text, #X.PREFIX + 1))
local parts, whole = {}, {}
for piece in string.gmatch(joined .. "\0\0\0\255\255", "(.-)%z%z%z\255\255") do
	parts[#parts + 1] = piece
	whole[#whole + 1] = string.sub(piece, 2, -2)
end
eq(table.concat(whole), X.serialize(held), "the parts hold the text in order")
eq(#parts[1], 64 + 2, "a part is PART bytes")
eq(#parts[#parts] <= 64 + 2 and #parts[#parts] > 2, true, "the last holds what is left, never nothing")
X.PART = part

return checks()
