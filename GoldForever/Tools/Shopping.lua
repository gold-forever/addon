-- Gold Forever: shopping lists' rules (design 009, Shop; the web playground's shopping.ts, line for line
-- with its tests): the most a list pays, what a list can buy from the book, when a quote moved too much,
-- and the GFL1 string players share. Pure Lua 5.1 with no game API, so it is tested outside the client.

local _, ns = ...
ns = ns or {}
local L = ns.L
local Encode = ns.Encode

local Shopping = {}
ns.Shopping = Shopping

Shopping.PREFIX = "GFL1:"
-- MAX_LISTS is the site's too (MAX_SHARED_ITEMS): a pasted string cannot fill the save with lists.
local MAX_STRING, MAX_ENTRIES, MAX_COPPER, MAX_LISTS = 16384, 200, Encode.MAX_COPPER, 50
-- A share of the market value (owner's answer, 2026-10-24: "% of market"), and how many to hold.
local MAX_PCT, MAX_UPTO = 1000, 1000000

-- An entry: { itemId, maxUnit? (copper), pct? (of market value), lowest? (a share of the market value
-- to check over), upTo? (units to hold) }; with no price, "under market". The most it pays a unit without
-- asking: its own price, its share of the market value, or a copper under the market value. `lowest` is
-- for what the player needs (owner, 2026-10-24: raid consumables): the cheapest first, and past its share
-- Buy next asks before it buys.
function Shopping.limit(entry, market)
	if entry.maxUnit then
		return entry.maxUnit
	end
	local share = entry.pct or entry.lowest
	if share then
		return market and math.max(1, math.floor(market * share / 100)) or nil
	end
	return market and math.max(1, market - 1) or nil
end

-- Takes other players' units from a book of levels { unitPrice, quantity, own }, cheapest first: those
-- at or under `cap` (nil: any price), up to `need` units (nil: every one). Returns quantity, total, top
-- (the dearest unit price taken, nil when none).
function Shopping.take(levels, cap, need)
	local sorted = {}
	for i, l in ipairs(levels or {}) do
		sorted[i] = l
	end
	table.sort(sorted, function(a, b)
		return a.unitPrice < b.unitPrice
	end)
	local quantity, total, top = 0, 0, nil
	for _, l in ipairs(sorted) do
		if need == 0 or (cap and l.unitPrice > cap) then
			break
		end
		local n = (l.quantity or 0) - (l.own or 0)
		if need then
			n = math.min(need, n)
		end
		if n > 0 then
			quantity, total, top = quantity + n, total + n * l.unitPrice, l.unitPrice
			if need then
				need = need - n
			end
		end
	end
	return quantity, total, top
end

-- What an entry can buy from a book of levels { unitPrice, quantity, own }: every unit by other players
-- at or under its limit, cheapest first. Returns { itemId, quantity, total, topUnit, limit } or nil.
function Shopping.deal(entry, levels, market)
	local limit = Shopping.limit(entry, market)
	if not limit then
		return nil
	end
	local quantity, total, top = Shopping.take(levels, limit, nil)
	if quantity == 0 or not top then
		return nil
	end
	return { itemId = entry.itemId, quantity = quantity, total = total, topUnit = top, limit = limit }
end

-- What a `lowest` entry buys now, for the units still needed (upTo less what is held), cheapest first:
-- those at or under its share of the market value; when none are and some are still needed, the cheapest
-- above it, marked `over` (Buy next asks before buying them). Returns a deal as Shopping.deal's, or nil.
function Shopping.lowestDeal(entry, held, levels, market)
	local need = math.max(0, (entry.upTo or 0) - (held or 0))
	local limit = Shopping.limit(entry, market)
	if need == 0 or not limit then
		return nil
	end
	local quantity, total, top = Shopping.take(levels, limit, need)
	if quantity > 0 then
		return { itemId = entry.itemId, quantity = quantity, total = total, topUnit = top, limit = limit }
	end
	quantity, total, top = Shopping.take(levels, nil, need)
	if quantity == 0 then
		return nil
	end
	return { itemId = entry.itemId, quantity = quantity, total = total, topUnit = top, limit = top, over = true, share = entry.lowest }
end

-- The deal for a list entry from its item's book: a `lowest` entry's as Shopping.lowestDeal; an entry
-- with How many (a profile's buy rule) up to it, counting `held` (decision 12); else Shopping.deal. `held`
-- is what this character holds, read only for an entry with How many.
function Shopping.entryDeal(entry, levels, held, market)
	if entry.lowest and entry.upTo then
		return Shopping.lowestDeal(entry, held, levels, market)
	end
	if entry.upTo then
		local limit = Shopping.limit(entry, market)
		if not limit then
			return nil
		end
		local quantity, total, top = Shopping.take(levels, limit, math.max(0, entry.upTo - held))
		if quantity == 0 then
			return nil
		end
		return { itemId = entry.itemId, quantity = quantity, total = total, topUnit = top, limit = limit }
	end
	return Shopping.deal(entry, levels, market)
end

-- A quote dearer than the deal by more than `pct` percent (10 by default): Buy next asks again.
function Shopping.moved(expected, quoted, pct)
	return quoted > expected * (1 + (pct or 10) / 100)
end

-- One entry's line: "item <id> max <copper>", "item <id> pct <n>" or "item <id> market", then
-- " upto <n>" when it holds a number to buy up to. A list with neither pct nor upto reads as before.
function Shopping.line(e)
	local price = e.maxUnit and ("max " .. e.maxUnit) or e.pct and ("pct " .. e.pct) or e.lowest and ("lowest " .. e.lowest) or "market"
	return "item " .. e.itemId .. " " .. price .. (e.upTo and (" upto " .. e.upTo) or "")
end

-- The lists as plain lines: "list <name>", "for <GUID>" when it is one character's, then an entry's line each.
function Shopping.text(lists)
	local lines = {}
	for _, l in ipairs(lists) do
		lines[#lines + 1] = "list " .. l.name
		if l.character then
			lines[#lines + 1] = "for " .. l.character
		end
		for _, e in ipairs(l.entries) do
			lines[#lines + 1] = Shopping.line(e)
		end
	end
	return table.concat(lines, "\n")
end

function Shopping.encode(lists)
	return Shopping.PREFIX .. Encode.base64(Shopping.text(lists))
end

-- The character a "for" line names, by its GUID as the game writes it: "Player-<server id>-<8 hex digits>";
-- nil when the line is not that. A list's and a profile's (SalePlan.decode) alike.
function Shopping.forLine(line)
	local server, hex = string.match(line, "^for Player%-(%d+)%-([0-9A-F]+)$")
	if not server or #server > 5 or #hex ~= 8 then
		return nil
	end
	return string.sub(line, 5)
end

-- Reads a list string someone shared: untrusted, so bounded and stripped of the game's "|" escapes.
-- A line it does not know is skipped (a later format may add some); a known line that is wrong refuses it.
-- Returns lists, or nil and what is wrong.
function Shopping.decode(input)
	local s = string.match(input or "", "^%s*(.-)%s*$")
	if string.sub(s, 1, #Shopping.PREFIX) ~= Shopping.PREFIX then
		return nil, string.format(L["Not a shopping list string: it starts with %s"], Shopping.PREFIX)
	end
	if #s > MAX_STRING then
		return nil, L["Too long for shopping lists"]
	end
	local text = Encode.unbase64(string.sub(s, #Shopping.PREFIX + 1))
	if not text then
		return nil, L["The string is damaged (copy it again, all of it)"]
	end
	local lists, entries, n = {}, 0, 0
	for raw in string.gmatch(text .. "\n", "([^\n]*)\n") do
		n = n + 1
		local line = string.match(raw, "^%s*(.-)%s*$")
		if line ~= "" then
			local function bad()
				return nil, string.format(L["Line %d is not understood: \"%s\""], n, string.sub(line, 1, 60))
			end
			local word = string.match(line, "^(%S+)")
			if word == "list" then
				if #lists >= MAX_LISTS then
					return nil, string.format(L["More than %d lists"], MAX_LISTS)
				end
				local name = string.match(string.sub(string.gsub(string.sub(line, 6), "|", ""), 1, 40), "^%s*(.-)%s*$")
				lists[#lists + 1] = { name = name ~= "" and name or "Unnamed", entries = {} }
			elseif word == "for" then
				-- One character's list.
				local list, character = lists[#lists], Shopping.forLine(line)
				if not list or list.character or not character then
					return bad()
				end
				list.character = character
			elseif word == "item" then
				local id, rest = string.match(line, "^item (%d+) (.+)$")
				local list = lists[#lists]
				if not id or not list or #id > 8 then
					return bad()
				end
				local maxUnit, pct, lowest, upTo
				local price, u = string.match(rest, "^(.-) upto (%d+)$")
				if price then
					if #u > 7 then
						return bad()
					end
					upTo, rest = tonumber(u), price
					if upTo == 0 or upTo > MAX_UPTO then
						return bad()
					end
				end
				if rest ~= "market" then
					local m = string.match(rest, "^max (%d+)$")
					local p = string.match(rest, "^pct (%d+)$")
					local lo = string.match(rest, "^lowest (%d+)$")
					if m and #m <= 11 then
						maxUnit = tonumber(m)
						if maxUnit == 0 or maxUnit > MAX_COPPER then
							return bad()
						end
					elseif p and #p <= 4 then
						pct = tonumber(p)
						if pct == 0 or pct > MAX_PCT then
							return bad()
						end
					elseif lo and #lo <= 4 then
						lowest = tonumber(lo)
						if lowest == 0 or lowest > MAX_PCT then
							return bad()
						end
					else
						return bad()
					end
				end
				if tonumber(id) == 0 then
					return bad()
				end
				entries = entries + 1
				if entries > MAX_ENTRIES then
					return nil, string.format(L["More than %d items"], MAX_ENTRIES)
				end
				list.entries[#list.entries + 1] = { itemId = tonumber(id), maxUnit = maxUnit, pct = pct, lowest = lowest, upTo = upTo }
			end
			-- Any other line is one a later format added: skipped, so it cannot break the lists around it.
		end
	end
	return lists
end

-- Whether a list shows for the character with this GUID: one for every character (no `character`), or its own.
function Shopping.forCharacter(list, guid)
	return list.character == nil or (guid ~= nil and list.character == guid)
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

-- The coins' letters in the client's language ("po", "pa", "pc" in French) as g, s and c.
local function englishCoins(text)
	for letter, symbol in pairs({ g = GOLD_AMOUNT_SYMBOL, s = SILVER_AMOUNT_SYMBOL, c = COPPER_AMOUNT_SYMBOL }) do
		symbol = string.lower(symbol or letter)
		if symbol ~= letter then
			text = string.gsub(text, "(%d)%s*" .. string.gsub(symbol, "%p", "%%%0"), "%1" .. letter)
		end
	end
	return text
end

-- The client's thousands separator taken out where it groups digits ("1.234g" on a German client).
local function ungrouped(text)
	local sep = string.gsub(LARGE_NUMBER_SEPARATOR or ",", "%p", "%%%0")
	local before
	repeat
		before = text
		text = string.gsub(text, "(%d)" .. sep .. "(%d%d%d)%f[%D]", "%1%2")
	until text == before
	return text
end

-- A price typed as gold: "4.5", "4,5", "4g 50s", "45s", "4g50s25c", or with the client's own coin letters
-- ("4po 50pa", "4g 50s 25k"); copper, or nil when it is none. A comma is a decimal point only before one or
-- two digits at the end ("4,5", "4,50"); else it separates thousands ("1,000" is a thousand gold, not one),
-- as the client's own separator does before three digits ("1.000" on a German client).
function Shopping.parseGold(text)
	text = ungrouped(englishCoins(string.lower(string.match(text or "", "^%s*(.-)%s*$"))))
	if text == "" then
		return nil
	end
	local copper
	if string.find(text, "^[%d%.,]+$") then
		local whole, cents = string.match(text, "^(.-),(%d%d?)$")
		if whole then
			text = whole .. "." .. cents
		end
		local gold = tonumber((string.gsub(text, ",", "")))
		copper = gold and math.floor(gold * 10000 + 0.5)
	else
		local g, s, c, rest = 0, 0, 0, text
		for n, unit in string.gmatch(text, "(%d+)%s*([gsc])") do
			n = tonumber(n)
			if unit == "g" then g = n elseif unit == "s" then s = n else c = n end
		end
		rest = string.gsub(text, "%d+%s*[gsc]", "")
		if string.find(rest, "%S") then
			return nil
		end
		copper = g * 10000 + s * 100 + c
	end
	return copper and copper > 0 and copper <= MAX_COPPER and copper or nil
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

-- Merges items carried from elsewhere (the site, by the companion) into the game's: by id, the newer
-- `edited` wins and the other is dropped; an id only one side has is added (owner's answer, 2026-10-24:
-- keeping the loser as "<name> (older copy)" made copies pile up, since the site keeps a list's version
-- from before it was changed in the game). Returns the merged list and how many changed.
-- `removed` (id -> edited time when deleted in the game) keeps a deleted item away, unless the site's
-- copy was edited after it was deleted; an earlier merge's "(older copy)" (marked copyOf) is never taken.
function Shopping.merge(mine, incoming, removed)
	removed = removed or {}
	local out, byId, changed = {}, {}, 0
	for i, m in ipairs(mine or {}) do
		out[i] = m
		if m.id then
			byId[m.id] = i
		end
	end
	for _, inc in ipairs(incoming or {}) do
		local at = inc.id and byId[inc.id]
		local gone = inc.id and removed[inc.id]
		if inc.copyOf or (gone and (inc.edited or 0) <= gone) then
			-- a copy, or deleted here and not changed on the site since: left out
		elseif not at then
			out[#out + 1] = inc
			if inc.id then
				byId[inc.id] = #out
			end
			changed = changed + 1
		elseif (inc.edited or 0) > (out[at].edited or 0) then
			out[at] = inc
			changed = changed + 1
		end
	end
	return out, changed
end

-- The copies an earlier merge kept ("(older copy)", marked `copyOf`), taken out once. Returns how many.
function Shopping.dropCopies(items)
	local n = 0
	for i = #(items or {}), 1, -1 do
		if items[i].copyOf then
			table.remove(items, i)
			n = n + 1
		end
	end
	return n
end

-- Where an item is now after a merge or a drop moved things: the same table, else the one with its id,
-- else, for a copy, the one it was copied from. Returns the index, or nil when it is gone.
function Shopping.refind(items, was)
	if not was then
		return nil
	end
	for _, id in ipairs({ false, was.id or false, type(was.copyOf) == "string" and was.copyOf or false }) do
		for i, x in ipairs(items or {}) do
			if (id == false and x == was) or (id and x.id == id) then
				return i
			end
		end
	end
	return nil
end

-- Item goals (gf#337): list entries flagged `goal` with a How many, each item once in list order, at most
-- `most` (the HUD's room).
function Shopping.goals(lists, most)
	local out, seen = {}, {}
	for _, l in ipairs(lists or {}) do
		for _, e in ipairs(l.entries or {}) do
			if #out < most and e.goal and e.upTo and not seen[e.itemId] then
				seen[e.itemId] = true
				out[#out + 1] = e
			end
		end
	end
	return out
end

-- A goal's progress: `have` of `want` held, and the pace from what was `looted` this session in `elapsed`
-- seconds, so a purchase, mail or trade raises the count but not the pace. pace is units an hour and eta
-- seconds to go, nil without loot or time; a goal reached has no eta.
function Shopping.goalProgress(want, have, looted, elapsed)
	local p = { want = want, have = have, reached = have >= want }
	if looted > 0 and elapsed and elapsed > 0 then
		p.pace = looted * 3600 / elapsed
	end
	if p.pace and not p.reached then
		p.eta = (want - have) * 3600 / p.pace
	end
	return p
end

-- A goal's HUD line: "34/40 Linen Cloth · about 12m at this pace"; `duration` writes the seconds.
function Shopping.goalText(name, p, duration)
	local tail = p.reached and L["reached"] or p.eta and string.format(L["about %s at this pace"], duration(p.eta)) or L["no pace yet"]
	return string.format("%d/%d %s \194\183 %s", p.have, p.want, name, tail)
end

-- Whether a goal has just been reached: seen short of it before, reached now. `seen` keeps each key's last state.
function Shopping.newlyReached(seen, key, reached)
	local was = seen[key]
	seen[key] = reached
	return reached and was == false
end

return Shopping
