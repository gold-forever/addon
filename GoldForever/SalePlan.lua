-- Gold Forever: sale plans and profiles (design 009, Sale plans and profiles; the web playground's
-- salePlan.ts, line for line with its tests): what a sell rule does with what the player holds and the
-- book, what a buy rule takes from it, and the GFP1 profile string players and creators share. Pure Lua
-- 5.1 with no game API, so it is tested outside the client.
--
-- A rule: sell = { itemID, keep, price = { kind = "undercut", by } | { kind = "fixed", unit, askIfMovedPct }
-- | { kind = "percentile", pct }, floorPct }; buy = { itemID, upTo, maxUnit }. A level of the book:
-- { unitPrice, quantity, own }.

local _, ns = ...
ns = ns or {}
local Encode = ns.Encode

local SalePlan = {}
ns.SalePlan = SalePlan

-- The "sneaky price" guard (decision 13): up to maxUnits cheap units more than belowPct under the first
-- price after them are ignored when pricing a sale (and gladly bought).
SalePlan.GUARD = { maxUnits = 2, belowPct = 30 }

local function copyLevels(levels)
	local others = {}
	for _, l in ipairs(levels or {}) do
		local q = (l.quantity or 0) - (l.own or 0)
		if q > 0 then
			others[#others + 1] = { unitPrice = l.unitPrice, quantity = q, own = 0 }
		end
	end
	table.sort(others, function(a, b)
		return a.unitPrice < b.unitPrice
	end)
	return others
end

-- Other players' levels, cheapest first, with the outliers set apart: returns levels, ignored.
function SalePlan.clean(levels, guard, market)
	guard = guard or SalePlan.GUARD
	local others = copyLevels(levels)
	local units, ref = 0, nil
	for i, l in ipairs(others) do
		units = units + l.quantity
		if units > guard.maxUnits then
			ref = i
			break
		end
	end
	local reference = ref and others[ref].unitPrice or market
	ref = ref or (#others + 1)
	if not reference then
		return others, {}
	end
	local limit = reference * (1 - guard.belowPct / 100)
	local kept, ignored = {}, {}
	for i, l in ipairs(others) do
		if i < ref and l.unitPrice < limit then
			ignored[#ignored + 1] = l
		else
			kept[#kept + 1] = l
		end
	end
	return kept, ignored
end

-- The price at which pct percent of the listed units are cheaper or equal (10: the cheapest tenth).
function SalePlan.percentile(levels, pct)
	local total = 0
	for _, l in ipairs(levels) do
		total = total + l.quantity
	end
	if total == 0 then
		return nil
	end
	local target = math.max(1, math.ceil(total * pct / 100))
	local units = 0
	for _, l in ipairs(levels) do
		units = units + l.quantity
		if units >= target then
			return l.unitPrice
		end
	end
	return levels[#levels].unitPrice
end

-- What one sell rule does now: { action = "post"|"ask"|"hold"|"skip", reason, quantity, unitPrice,
-- choices = { plan, undercut } for "ask", ignored (units left out as outliers), floor }.
function SalePlan.sell(rule, held, levels, market, guard)
	local quantity = math.max(0, held - rule.keep)
	local kept, out = SalePlan.clean(levels, guard, market)
	local ignored = 0
	for _, l in ipairs(out) do
		ignored = ignored + l.quantity
	end
	local floor = (market and rule.floorPct > 0) and math.ceil(market * rule.floorPct / 100) or nil
	local function step(action, reason, unitPrice, extra)
		local s = { action = action, reason = reason, quantity = quantity, unitPrice = unitPrice, ignored = ignored, floor = floor }
		for k, v in pairs(extra or {}) do
			s[k] = v
		end
		return s
	end
	if quantity == 0 then
		return step("skip", "keeping", nil)
	end
	local cheapest = kept[1] and kept[1].unitPrice or nil
	local function guarded(price, reason)
		if floor and price < floor then
			return step("hold", "under-floor", nil)
		end
		return step("post", reason, price)
	end
	local p = rule.price
	if p.kind == "fixed" then
		if cheapest and math.abs(cheapest - p.unit) * 100 / p.unit > p.askIfMovedPct then
			return step("ask", "market-moved", nil, { choices = { plan = p.unit, undercut = cheapest - 1 } })
		end
		return step("post", "fixed", p.unit)
	elseif p.kind == "undercut" then
		if not cheapest then
			return market and guarded(market, "no-competition") or step("hold", "no-price", nil)
		end
		return guarded(math.max(1, cheapest - p.by), "undercut")
	elseif p.kind == "percentile" then
		local at = SalePlan.percentile(kept, p.pct)
		if not at then
			return market and guarded(market, "no-competition") or step("hold", "no-price", nil)
		end
		return guarded(at, "percentile")
	end
	return step("hold", "no-price", nil)
end

-- What one buy rule takes from the book: the cheapest other players' units at or under the cap, up to
-- the target (outliers welcome). Returns { quantity, topUnit, total }.
function SalePlan.buy(rule, held, levels)
	local need = math.max(0, rule.upTo - held)
	local quantity, total, top = 0, 0, nil
	local sorted = {}
	for i, l in ipairs(levels or {}) do
		sorted[i] = l
	end
	table.sort(sorted, function(a, b)
		return a.unitPrice < b.unitPrice
	end)
	for _, l in ipairs(sorted) do
		if need == 0 or l.unitPrice > rule.maxUnit then
			break
		end
		local n = math.min(need, (l.quantity or 0) - (l.own or 0))
		if n > 0 then
			quantity = quantity + n
			total = total + n * l.unitPrice
			top = l.unitPrice
			need = need - n
		end
	end
	return { quantity = quantity, topUnit = top, total = total }
end

-- The profile string ----------------------------------------------------------------------------------

SalePlan.PREFIX = "GFP1:"
local MAX_STRING, MAX_RULES, MAX_COPPER, MAX_UNITS = 16384, 200, 10000000000, 1000000

function SalePlan.text(p)
	local lines = { "name " .. p.name, "by " .. p.author }
	for _, r in ipairs(p.sell) do
		local price
		if r.price.kind == "undercut" then
			price = "undercut " .. r.price.by
		elseif r.price.kind == "fixed" then
			price = "fixed " .. r.price.unit .. " ask " .. r.price.askIfMovedPct
		else
			price = "percentile " .. r.price.pct
		end
		lines[#lines + 1] = string.format("sell %d keep %d %s floor %d", r.itemID, r.keep, price, r.floorPct)
	end
	for _, r in ipairs(p.buy) do
		lines[#lines + 1] = string.format("buy %d upto %d max %d", r.itemID, r.upTo, r.maxUnit)
	end
	return table.concat(lines, "\n")
end

function SalePlan.encode(p)
	return SalePlan.PREFIX .. Encode.base64(SalePlan.text(p))
end

local function int(v, max)
	if v and string.match(v, "^%d+$") and #v <= 11 and tonumber(v) <= max then
		return tonumber(v)
	end
	return nil
end

local function cleanName(v)
	return (string.match(string.sub(string.gsub(v, "|", ""), 1, 40), "^%s*(.-)%s*$"))
end

-- Reads a profile string someone shared. It is untrusted: every number is bounded, names lose the game's
-- "|" escapes, and anything unexpected is refused with its line. Returns the profile, or nil and why.
function SalePlan.decode(input)
	local s = string.match(input or "", "^%s*(.-)%s*$")
	if string.sub(s, 1, #SalePlan.PREFIX) ~= SalePlan.PREFIX then
		return nil, "Not a profile string: it starts with " .. SalePlan.PREFIX
	end
	if #s > MAX_STRING then
		return nil, "Too long for a profile"
	end
	local text = Encode.unbase64(string.sub(s, #SalePlan.PREFIX + 1))
	if not text then
		return nil, "The string is damaged (copy it again, all of it)"
	end
	local profile = { name = "Unnamed", author = "", sell = {}, buy = {} }
	local n = 0
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n = n + 1
		local line = string.match(raw, "^%s*(.-)%s*$")
		if line ~= "" then
			local function bad()
				return nil, string.format("Line %d is not understood: \"%s\"", n, string.sub(line, 1, 60))
			end
			local words = {}
			for w in string.gmatch(line, "%S+") do
				words[#words + 1] = w
			end
			local word = words[1]
			if word == "name" or word == "by" then
				local v = cleanName(string.sub(line, #word + 1))
				if word == "name" then
					profile.name = v ~= "" and v or "Unnamed"
				else
					profile.author = v
				end
			else
				if #profile.sell + #profile.buy >= MAX_RULES then
					return nil, "More than " .. MAX_RULES .. " rules"
				end
				local itemID = int(words[2], 10000000)
				-- words[3..] are key value pairs: an odd count after the item is malformed.
				if not itemID or itemID == 0 or (#words - 2) % 2 ~= 0 then
					return bad()
				end
				local kv, size = {}, 0
				for k = 3, #words - 1, 2 do
					if kv[words[k]] == nil then
						size = size + 1
					end
					kv[words[k]] = words[k + 1]
				end
				if word == "buy" then
					local upTo, maxUnit = int(kv.upto, MAX_UNITS), int(kv.max, MAX_COPPER)
					if not upTo or not maxUnit or maxUnit == 0 or size ~= 2 then
						return bad()
					end
					profile.buy[#profile.buy + 1] = { itemID = itemID, upTo = upTo, maxUnit = maxUnit }
				elseif word == "sell" then
					local keep = int(kv.keep, MAX_UNITS)
					local floorPct = int(kv.floor or "0", 100)
					local price
					local expected = kv.floor and 3 or 2
					if kv.undercut then
						local by = int(kv.undercut, MAX_COPPER)
						price = by and { kind = "undercut", by = by }
					elseif kv.fixed then
						local unit, ask = int(kv.fixed, MAX_COPPER), int(kv.ask, 100)
						price = unit and unit > 0 and ask and { kind = "fixed", unit = unit, askIfMovedPct = ask } or nil
						expected = expected + 1
					elseif kv.percentile then
						local pct = int(kv.percentile, 100)
						price = pct and pct > 0 and { kind = "percentile", pct = pct } or nil
					end
					if not keep or not floorPct or not price or size ~= expected then
						return bad()
					end
					profile.sell[#profile.sell + 1] = { itemID = itemID, keep = keep, price = price, floorPct = floorPct }
				else
					return bad()
				end
			end
		end
	end
	return profile
end

-- The sell rule for an item in a profile, or nil.
function SalePlan.ruleFor(profile, itemID)
	for _, r in ipairs(profile and profile.sell or {}) do
		if r.itemID == itemID then
			return r
		end
	end
	return nil
end

return SalePlan
