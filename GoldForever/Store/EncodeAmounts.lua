-- Gold Forever: amounts worked out from what is recorded (ns.Encode): shares of coin, a scan's market value,
-- XP gained. Pure Lua 5.1 with no game API.

local _, ns = ...
ns = ns or {}
local Encode = ns.Encode

-- The most copper any price the addon takes from outside may be (a million gold).
Encode.MAX_COPPER = 10000000000

-- Splits an integer amount over weights (numbers ≥ 0) in proportion, remainder to the first
-- shares, so the parts always add up to the amount. Equal shares when every weight is 0.
function Encode.split(amount, weights)
	local total = 0
	for _, w in ipairs(weights) do
		total = total + w
	end
	local parts, given = {}, 0
	for i, w in ipairs(weights) do
		local share = total > 0 and w / total or 1 / #weights
		parts[i] = math.floor(amount * share)
		given = given + parts[i]
	end
	local i = 1
	while given < amount and #parts > 0 do
		parts[i] = parts[i] + 1
		given = given + 1
		i = i % #parts + 1
	end
	return parts
end

-- Market value of an item from one scan's listings ({ { unit, qty }, … }, any order): the average
-- unit price of the cheapest 15% of units, at least one. The web app's price engine does the same
-- (backend/Prices.kt), so the two agree.
function Encode.marketValue(listings)
	local sorted = {}
	local total = 0
	for i, l in ipairs(listings) do
		sorted[i] = l
		total = total + l.qty
	end
	if total == 0 then
		return nil
	end
	table.sort(sorted, function(a, b)
		return a.unit < b.unit
	end)
	local wanted = math.max(1, math.ceil(total * 0.15))
	local units, copper = 0, 0
	for _, l in ipairs(sorted) do
		local take = math.min(wanted - units, l.qty)
		units = units + take
		copper = copper + take * l.unit
		if units >= wanted then
			break
		end
	end
	return math.floor(copper / units)
end

-- The same market value from a flat list { unit1, qty1, unit2, qty2, … }: one table an item instead of one a
-- listing, for reading a whole scan (a retail scan has ~110,000 rows).
function Encode.marketValueFlat(flat)
	local n = #flat / 2
	local total = 0
	for k = 2, #flat, 2 do
		total = total + flat[k]
	end
	if total == 0 then
		return nil
	end
	local wanted = math.max(1, math.ceil(total * 0.15))
	if n == 1 then
		return flat[1]
	end
	local order
	if n <= 24 then
		-- Few listings (most items): sorted in place by unit, pairs moved together; no table, no closure.
		for i = 2, n do
			local u, q = flat[2 * i - 1], flat[2 * i]
			local j = i - 1
			while j >= 1 and flat[2 * j - 1] > u do
				flat[2 * j + 1], flat[2 * j + 2] = flat[2 * j - 1], flat[2 * j]
				j = j - 1
			end
			flat[2 * j + 1], flat[2 * j + 2] = u, q
		end
	else
		order = {}
		for k = 1, n do
			order[k] = k
		end
		table.sort(order, function(a, b)
			return flat[2 * a - 1] < flat[2 * b - 1]
		end)
	end
	local units, copper = 0, 0
	for i = 1, n do
		local k = order and order[i] or i
		local take = math.min(wanted - units, flat[2 * k])
		units = units + take
		copper = copper + take * flat[2 * k - 1]
		if units >= wanted then
			break
		end
	end
	return math.floor(copper / units)
end

-- The cheapest unit in a flat list.
function Encode.cheapestFlat(flat)
	local low
	for k = 1, #flat, 2 do
		if not low or flat[k] < low then
			low = flat[k]
		end
	end
	return low
end

-- XP gained between two readings: within a level, the difference; across a level-up, the rest of
-- the old level plus what the new one has so far.
function Encode.xpGained(before, beforeMax, now, levelledUp)
	if levelledUp then
		return math.max(0, beforeMax - before) + now
	end
	return math.max(0, now - before)
end
