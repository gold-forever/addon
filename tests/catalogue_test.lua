-- Catalogue.lua: every item a scan names reaches the catalogue. A retail scan names about 19,000 items
-- while the queue is draining; on the owner's first retail scan (2026-10-22) exactly half never did.

local catalogued = {}
GetItemInfo = function(id)
	catalogued[id] = true
	return "Item " .. id, nil, 1, 1, 1, nil, nil, 20, "", 1, 1, 7, 5, 0
end

local scheduled = {}
local ns = {
	FIELDS = {},
	db = function()
		return { catalogue = { items = {}, tooltips = {} } }
	end,
	after = function(_, _, fn)
		scheduled[#scheduled + 1] = fn
	end,
	safely = function(_, fn, ...)
		return fn(...)
	end,
	on = function() end,
}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Catalogue.lua"], "@Catalogue.lua"))("GoldForever", ns)

local checks = 0
local function eq(actual, expected, what)
	checks = checks + 1
	if actual ~= expected then
		error(string.format("%s: expected [%s], got [%s]", what, tostring(expected), tostring(actual)), 2)
	end
end

-- Runs the earliest scheduled callback, as the game's timer would.
local function tick()
	local fn = table.remove(scheduled, 1)
	if fn then
		fn()
	end
	return fn ~= nil
end

-- A scan reads its listings in batches, and the queue drains between them.
local N = 5000
local id = 100000
for _ = 1, N / 250 do
	for _ = 1, 250 do
		id = id + 1
		ns.catalogueItem(id)
	end
	tick()
end
while tick() do
end

local count = 0
for i = 100001, 100000 + N do
	if catalogued[i] then
		count = count + 1
	end
end
eq(count, N, "items catalogued after a scan named them while the queue drained")

return checks
