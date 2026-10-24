-- Gold Forever: shopping lists' rules (design 009, Shop; the web playground's shopping.ts, line for line
-- with its tests): the most a list pays, what a list can buy from the book, when a quote moved too much,
-- and the GFL1 string players share. Pure Lua 5.1 with no game API, so it is tested outside the client.

local _, ns = ...
ns = ns or {}
local Encode = ns.Encode

local Shopping = {}
ns.Shopping = Shopping

Shopping.PREFIX = "GFL1:"
-- MAX_LISTS is the site's too (MAX_SHARED_ITEMS): a pasted string cannot fill the save with lists.
local MAX_STRING, MAX_ENTRIES, MAX_COPPER, MAX_LISTS = 16384, 200, 10000000000, 50

-- The most an entry pays a unit: its own price, or a copper under market value ("under market").
function Shopping.limit(entry, market)
	if entry.maxUnit then
		return entry.maxUnit
	end
	return market and math.max(1, market - 1) or nil
end

-- What an entry can buy from a book of levels { unitPrice, quantity, own }: every unit by other players
-- at or under its limit, cheapest first. Returns { itemId, quantity, total, topUnit, limit } or nil.
function Shopping.deal(entry, levels, market)
	local limit = Shopping.limit(entry, market)
	if not limit then
		return nil
	end
	local sorted = {}
	for i, l in ipairs(levels or {}) do
		sorted[i] = l
	end
	table.sort(sorted, function(a, b)
		return a.unitPrice < b.unitPrice
	end)
	local quantity, total, top = 0, 0, nil
	for _, l in ipairs(sorted) do
		if l.unitPrice > limit then
			break
		end
		local n = (l.quantity or 0) - (l.own or 0)
		if n > 0 then
			quantity = quantity + n
			total = total + n * l.unitPrice
			top = l.unitPrice
		end
	end
	if quantity == 0 or not top then
		return nil
	end
	return { itemId = entry.itemId, quantity = quantity, total = total, topUnit = top, limit = limit }
end

-- A quote dearer than the deal by more than `pct` percent (10 by default): Buy next asks again.
function Shopping.moved(expected, quoted, pct)
	return quoted > expected * (1 + (pct or 10) / 100)
end

-- The lists as plain lines: "list <name>", then "item <id> max <copper>" or "item <id> market".
function Shopping.text(lists)
	local lines = {}
	for _, l in ipairs(lists) do
		lines[#lines + 1] = "list " .. l.name
		for _, e in ipairs(l.entries) do
			lines[#lines + 1] = "item " .. e.itemId .. " " .. (e.maxUnit and ("max " .. e.maxUnit) or "market")
		end
	end
	return table.concat(lines, "\n")
end

function Shopping.encode(lists)
	return Shopping.PREFIX .. Encode.base64(Shopping.text(lists))
end

-- Reads a list string someone shared: untrusted, so bounded and stripped of the game's "|" escapes.
-- Returns lists, or nil and what is wrong.
function Shopping.decode(input)
	local s = string.match(input or "", "^%s*(.-)%s*$")
	if string.sub(s, 1, #Shopping.PREFIX) ~= Shopping.PREFIX then
		return nil, "Not a shopping list string: it starts with " .. Shopping.PREFIX
	end
	if #s > MAX_STRING then
		return nil, "Too long for shopping lists"
	end
	local text = Encode.unbase64(string.sub(s, #Shopping.PREFIX + 1))
	if not text then
		return nil, "The string is damaged (copy it again, all of it)"
	end
	local lists, entries, n = {}, 0, 0
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n = n + 1
		local line = string.match(raw, "^%s*(.-)%s*$")
		if line ~= "" then
			local function bad()
				return nil, string.format("Line %d is not understood: \"%s\"", n, string.sub(line, 1, 60))
			end
			if string.sub(line, 1, 5) == "list " then
				if #lists >= MAX_LISTS then
					return nil, "More than " .. MAX_LISTS .. " lists"
				end
				local name = string.match(string.sub(string.gsub(string.sub(line, 6), "|", ""), 1, 40), "^%s*(.-)%s*$")
				lists[#lists + 1] = { name = name ~= "" and name or "Unnamed", entries = {} }
			else
				local id, rest = string.match(line, "^item (%d+) (.+)$")
				local list = lists[#lists]
				if not id or not list or #id > 8 then
					return bad()
				end
				local maxUnit
				if rest ~= "market" then
					local m = string.match(rest, "^max (%d+)$")
					if not m or #m > 11 then
						return bad()
					end
					maxUnit = tonumber(m)
					if maxUnit == 0 or maxUnit > MAX_COPPER then
						return bad()
					end
				end
				if tonumber(id) == 0 then
					return bad()
				end
				entries = entries + 1
				if entries > MAX_ENTRIES then
					return nil, "More than " .. MAX_ENTRIES .. " items"
				end
				list.entries[#list.entries + 1] = { itemId = tonumber(id), maxUnit = maxUnit }
			end
		end
	end
	return lists
end

-- What the Shop's field holds: an item (a shift-clicked link, or an ID typed) and, after it, a price in
-- gold ("12", "1.5", "0.25g"); returns the item ID and the price in copper, or nil for "under market".
function Shopping.parseAdd(text)
	text = text or ""
	local id, rest = string.match(text, "|Hitem:(%d+)[^|]*|h.-|h|r(.*)$")
	if not id then
		id, rest = string.match(text, "^%s*(%d+)(.*)$")
	end
	if not id then
		return nil
	end
	local gold = tonumber(string.match(rest or "", "^%s*([%d%.]+)%s*g?%s*$") or "")
	local copper = gold and math.floor(gold * 10000 + 0.5) or nil
	return tonumber(id), (copper and copper > 0) and copper or nil
end

-- The entries listed at or under their price in a scan: cheapest(id) is the scan's cheapest unit and
-- market(id) the market value (for "under market" entries). Each item once, in list order.
function Shopping.underPrice(lists, cheapest, market)
	local out, seen = {}, {}
	for _, l in ipairs(lists or {}) do
		for _, e in ipairs(l.entries or {}) do
			if not seen[e.itemId] then
				local limit = Shopping.limit(e, market(e.itemId))
				local low = cheapest(e.itemId)
				if limit and low and low <= limit then
					seen[e.itemId] = true
					out[#out + 1] = e.itemId
				end
			end
		end
	end
	return out
end

-- Merges items carried from elsewhere (the site, by the companion) into the game's (design 009, Lists and
-- profiles carried by the companion; decision 11): by id, the newer `edited` wins; the loser is kept once
-- as "<name> (older copy)" with a new id (newId()), so nothing is silently lost; an id only one side has
-- is added. Returns the merged list and how many changed.
function Shopping.merge(mine, incoming, newId)
	local out, byId, changed = {}, {}, 0
	for i, m in ipairs(mine or {}) do
		out[i] = m
		if m.id then
			byId[m.id] = i
		end
	end
	local function kept(loser)
		for _, x in ipairs(out) do
			if x.copyOf == loser.id and x.copyEdited == loser.edited then
				return true
			end
		end
		return false
	end
	local function copyOf(loser)
		local c = {}
		for k, v in pairs(loser) do
			c[k] = v
		end
		c.id, c.copyOf, c.copyEdited = newId(), loser.id, loser.edited
		c.name = (loser.name or "Unnamed") .. " (older copy)"
		return c
	end
	for _, inc in ipairs(incoming or {}) do
		local at = inc.id and byId[inc.id]
		if not at then
			out[#out + 1] = inc
			if inc.id then
				byId[inc.id] = #out
			end
			changed = changed + 1
		else
			local m = out[at]
			local a, b = m.edited or 0, inc.edited or 0
			if b > a then
				if not kept(m) then
					out[#out + 1] = copyOf(m)
				end
				out[at] = inc
				changed = changed + 1
			elseif a > b and not kept(inc) then
				out[#out + 1] = copyOf(inc)
				changed = changed + 1
			end
		end
	end
	return out, changed
end

return Shopping
