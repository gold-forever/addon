-- ExportView.lua: the export over the save, from the last export on or everything again, and what an
-- export held marked as sent.

local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
local day = ns.Encode.day
local T = 1000000
local save = {
	schema = 1, addon = "0.12.0", fields = { loot = "t" }, client = { build = "1.60" },
	characters = { c1 = { name = "Testchar" } },
	events = { [day(T)] = { loot = { "a" } }, [day(T + 3 * 86400)] = { loot = { "b" } } },
	scans = {}, guildBanks = {}, catalogue = { items = { [2589] = "Linen" } },
	settings = {}, errors = {},
	exportedAt = T + 86400,
}
ns.db = function() return save end
assert(load(SOURCES["Export.lua"], "@Export.lua"))("GoldForever", ns)
assert(load(SOURCES["ExportView.lua"], "@ExportView.lua"))("GoldForever", ns)
local V = ns.ExportView

-- Built to the end, a frame's share never used: what it holds.
local function held(all)
	local step = V.builder(all, T + 4 * 86400, function(part) return part, 0 end)
	local text, picked
	repeat
		text, picked = step(function() return false end)
	until text
	return picked
end

local function days(picked)
	local out = {}
	for d in pairs(picked.events) do
		out[#out + 1] = d
	end
	table.sort(out)
	return table.concat(out, " ")
end
eq(days(held(false)), day(T + 3 * 86400), "the days from the last export on")
eq(days(held(true)), day(T) .. " " .. day(T + 3 * 86400), "all: every day again")

local picked = held(true)
V.sent(picked, T + 4 * 86400)
eq(save.exportedAt, T + 4 * 86400, "sent: the next export starts from it")
eq(save.exportSent.items[2589], true, "and what it held is remembered as sent")
eq(days(held(false)), "", "nothing new since")
return checks()
