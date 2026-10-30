-- Gold Forever: the items the characters hold, and what they are worth (ns.Views): the Inventory tab's
-- rows, the tooltip's holdings, the bank and mail the auction house pays for, and the craft queue's reagents.
-- Pure Lua 5.1, as Views.lua.

local _, ns = ...
local Views = ns.Views

-- What a set of held items is worth, most first: held = { [id] = count }, worth(id) -> one unit's copper
-- or nil. Returns the list { id, count, value }, the total, and how many units have no price.
function Views.worthList(held, worth)
	local list, total, unpriced = {}, 0, 0
	for id, n in pairs(held or {}) do
		local w, where = worth(id)
		if w then
			list[#list + 1] = { id = id, count = n, value = w * n, where = where }
			total = total + w * n
		else
			unpriced = unpriced + n
		end
	end
	table.sort(list, function(a, b)
		if a.value ~= b.value then
			return a.value > b.value
		end
		return a.id < b.id
	end)
	return list, total, unpriced
end

-- The Inventory tab's rows: everything the characters hold ({ [guid] = { name, bags, bank, mail } }, each
-- place's items read by parse), one row an item, filtered by filter = { char = guid, place = "bags" |
-- "bank" | "mail", quality = minimum, query = lower-case text }; with where it is held and its worth
-- (worth(id) a unit, quality(id), name(id)). Returns rows and totals { items, units, worth }.
Views.PLACES = { "bags", "bank", "mail" }
-- The equipped gear of a character as counts: c.gear is { [slot] = key }.
local function gearCounts(c, parse)
	local out = {}
	for slot, key in pairs(c.gear or {}) do
		if type(slot) == "number" then
			for id in pairs(parse(key .. "*1")) do
				out[id] = (out[id] or 0) + 1
			end
		end
	end
	return out
end

-- Rows of what the characters hold. filter.place "gear" shows equipped items, which are worth nothing
-- here (they are not for sale); otherwise bags, bank and mail. Soulbound units (a place's `bound`) are
-- worth what a vendor pays, vendor(id), and filter.tradeable leaves them out (owner's answers,
-- 2026-10-24, manual test run 001).
function Views.inventory(characters, parse, worth, quality, name, filter, vendor)
	filter = filter or {}
	local byItem = {}
	local places = filter.place == "gear" and { "gear" } or Views.PLACES
	for guid, c in pairs(characters or {}) do
		if not filter.char or filter.char == guid then
			for _, place in ipairs(places) do
				if not filter.place or filter.place == place then
					local held = place == "gear" and gearCounts(c, parse) or parse(c[place] and c[place].items)
					local bound = place ~= "gear" and parse(c[place] and c[place].bound) or {}
					for id, n in pairs(held) do
						local b = math.min(n, bound[id] or 0)
						if filter.tradeable then
							n, b = n - b, 0
						end
						if n > 0 then
							local it = byItem[id] or { held = 0, bound = 0, where = {} }
							byItem[id] = it
							it.held, it.bound = it.held + n, it.bound + b
							it.where[#it.where + 1] = string.format("%s %d (%s)", c.name or "?", n, place == "gear" and "equipped" or place)
						end
					end
				end
			end
		end
	end
	local rows, totals = {}, { items = 0, units = 0, worth = 0 }
	for id, it in pairs(byItem) do
		local q = quality(id) or 1
		local label = name(id)
		if (not filter.quality or q >= filter.quality) and (not filter.query or filter.query == "" or string.find(string.lower(label), filter.query, 1, true)) then
			table.sort(it.where)
			local value = 0
			if filter.place ~= "gear" then
				value = (worth(id) or 0) * (it.held - it.bound) + ((vendor and vendor(id)) or 0) * it.bound
			end
			rows[#rows + 1] = { id = id, name = label, quality = q, held = it.held, bound = it.bound, where = table.concat(it.where, ", "), holders = it.where, value = value }
			totals.items = totals.items + 1
			totals.units = totals.units + it.held
			totals.worth = totals.worth + value
		end
	end
	return rows, totals
end

-- What every character holds of each item, for the tooltip's "Held" line (owner's answer, 2026-10-24):
-- { [id] = { total, by = { { name, bags, bank, mail, total }, … most first } } } from the characters'
-- saved places, each read by parse.
function Views.holdings(characters, parse)
	local index = {}
	for _, c in pairs(characters or {}) do
		local mine = {}
		for _, place in ipairs(Views.PLACES) do
			for id, n in pairs(parse(c[place] and c[place].items)) do
				local h = mine[id]
				if not h then
					h = { name = c.name or "?", bags = 0, bank = 0, mail = 0, total = 0 }
					mine[id] = h
					local e = index[id] or { total = 0, by = {} }
					index[id] = e
					e.by[#e.by + 1] = h
				end
				h[place] = h[place] + n
				h.total = h.total + n
				index[id].total = index[id].total + n
			end
		end
	end
	for _, e in pairs(index) do
		table.sort(e.by, function(a, b)
			if a.total ~= b.total then
				return a.total > b.total
			end
			return a.name < b.name
		end)
	end
	return index
end

-- Views.holdings for only the items in `ids` (a set of item IDs), so the craft queue's few reagents do
-- not build every item of every character; `skip`, a character left out (the one playing). The same
-- entries as Views.holdings, for those items.
function Views.holdingsOf(characters, parse, ids, skip)
	local index = {}
	for _, c in pairs(characters or {}) do
		if c ~= skip then
			local mine = {}
			for _, place in ipairs(Views.PLACES) do
				for id, n in pairs(parse(c[place] and c[place].items)) do
					if ids[id] then
						local h = mine[id]
						if not h then
							h = { name = c.name or "?", bags = 0, bank = 0, mail = 0, total = 0 }
							mine[id] = h
							local e = index[id] or { total = 0, by = {} }
							index[id] = e
							e.by[#e.by + 1] = h
						end
						h[place] = h[place] + n
						h.total = h.total + n
						index[id].total = index[id].total + n
					end
				end
			end
		end
	end
	for _, e in pairs(index) do
		table.sort(e.by, function(a, b)
			if a.total ~= b.total then
				return a.total > b.total
			end
			return a.name < b.name
		end)
	end
	return index
end

-- The "Held" line for one item's holdings: "Held 12: Zerie 10 (bags 8, bank 2), Zeripala 2 (mail)",
-- at most `most` characters (3) and "+N more"; nil when nobody holds any.
function Views.heldText(entry, most)
	if not entry or entry.total == 0 then
		return nil
	end
	most = most or 3
	local parts = {}
	for i, h in ipairs(entry.by) do
		if i > most then
			parts[#parts + 1] = string.format("+%d more", #entry.by - most)
			break
		end
		local where = {}
		for _, place in ipairs(Views.PLACES) do
			if h[place] > 0 then
				where[#where + 1] = h[place] == h.total and place or (place .. " " .. h[place])
			end
		end
		parts[#parts + 1] = string.format("%s %d (%s)", h.name, h.total, table.concat(where, ", "))
	end
	return string.format("Held %d: %s", entry.total, table.concat(parts, ", "))
end

-- What this character keeps out of its bags that the auction house would pay for: its bank and mailbox,
-- each item with its market value (value(id), a unit; nil or 0 drops it, as a bound item has none),
-- the dearest first. Returns { items = { { id, name, count, place, worth } }, total, count }.
function Views.elsewhere(character, parse, value, name)
	local out = { items = {}, total = 0, count = 0 }
	for _, place in ipairs({ "bank", "mail" }) do
		-- Soulbound units never go to the auction house: left out.
		local bound = parse(character and character[place] and character[place].bound)
		for id, n in pairs(parse(character and character[place] and character[place].items)) do
			local unit = value(id)
			n = n - math.min(n, bound[id] or 0)
			if unit and unit > 0 and n > 0 then
				local worth = unit * n
				out.items[#out.items + 1] = { id = id, name = name(id), count = n, place = place, worth = worth }
				out.total = out.total + worth
				out.count = out.count + 1
			end
		end
	end
	table.sort(out.items, function(a, b)
		if a.worth ~= b.worth then
			return a.worth > b.worth
		end
		return a.id < b.id
	end)
	return out
end

-- The craft queue's reagents, each with where to get it (owner, 2026-10-25: "what to pick up at the
-- bank / guild bank, what to get from other characters and what to buy"). needs = { [id] = units };
-- mine = { bags, bank, mail } counts by id (mail with what was bought since it was read); guild = counts
-- in the guild bank; others = { [id] = { { name, total } } } on other characters. Bags, bank and mail
-- are the player's and count against the need; the guild bank and other characters are where the rest
-- can come from; what none of them covers is to buy. Rows, most to buy first, then by id.
function Views.queuePlan(needs, mine, guild, others)
	local rows = {}
	for id, need in pairs(needs or {}) do
		local bags = mine.bags[id] or 0
		local bank = mine.bank[id] or 0
		local mail = mine.mail[id] or 0
		local missing = math.max(0, need - bags - bank - mail)
		local g = math.min(missing, (guild or {})[id] or 0)
		local from = {}
		local left = missing - g
		for _, o in ipairs((others or {})[id] or {}) do
			if left <= 0 then
				break
			end
			local n = math.min(left, o.total)
			from[#from + 1] = { name = o.name, n = n }
			left = left - n
		end
		rows[#rows + 1] = {
			id = id, need = need, bags = bags,
			bank = math.min(bank, math.max(0, need - bags - mail)), -- to pick up from the bank: what the bags and mail leave
			mail = mail, guild = g, others = from, buy = left,
		}
	end
	table.sort(rows, function(a, b)
		if a.buy ~= b.buy then
			return a.buy > b.buy
		end
		return a.id < b.id
	end)
	return rows
end

-- What the bags would sell for (Home's "Sell your bags"): Views.worthList over bags = { items, bound },
-- the soulbound units left out, as Views.inventory leaves them out of what sells.
function Views.bagWorth(bags, parse, worth)
	local items, bound, sellable = parse(bags and bags.items), parse(bags and bags.bound), {}
	for id, n in pairs(items) do
		local left = n - math.min(n, bound[id] or 0)
		if left > 0 then
			sellable[id] = left
		end
	end
	return Views.worthList(sellable, worth)
end
