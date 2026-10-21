-- The export on real saves, under LuaJIT (the game's Lua 5.1): builds the string the way the addon
-- does, inflates it again, checks it is the same text, and reports sizes. Usage:
--   luajit addon/tests/export_check.lua addon/GoldForever <save.lua> [<fixture out>]
local dir, savePath, fixture = arg[1], arg[2], arg[3]
date = os.date
dofile(dir .. "/Libs/LibStub/LibStub.lua")
dofile(dir .. "/Libs/LibDeflate/LibDeflate.lua")
local LibDeflate = LibStub:GetLibrary("LibDeflate")
local ns = {}
assert(loadfile(dir .. "/Encode.lua"))("GoldForever", ns)
assert(loadfile(dir .. "/Export.lua"))("GoldForever", ns)
local X = ns.Export

dofile(savePath)
local db = GoldForeverDB
local latest = 0
for day in pairs(db.events or {}) do
	latest = math.max(latest, os.time({ year = tonumber(day:sub(1, 4)), month = tonumber(day:sub(6, 7)), day = tonumber(day:sub(9, 10)), hour = 12 }))
end

local function report(label, since, level)
	local started = os.clock()
	local picked = X.select(db, since, latest)
	local text = X.serialize(picked)
	local packed = LibDeflate:CompressDeflate(text, level and { level = level } or nil)
	local s = X.PREFIX .. X.base64(packed)
	local seconds = os.clock() - started
	assert(LibDeflate:DecompressDeflate(packed) == text, "inflates back to the same text")
	print(string.format("%-28s text %8d B  deflated %7d B  string %7d chars  %.2f s", label, #text, #packed, #s, seconds))
	return s, picked
end

local first, picked = report("first export", nil)
report("first export, level 9", nil, 9)
X.markSent(db, picked)
report("a day later", latest - 86400)
report("a week later", latest - 7 * 86400)
if fixture then
	local f = assert(io.open(fixture, "w"))
	f:write(first)
	f:close()
end
