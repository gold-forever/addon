-- Gold Forever: what the in-game pages show, worked out from the saved file: characters and rested
-- XP, levelling, and where money came from. Pure Lua 5.1 with no game API, so it can be tested
-- outside the client; the same rules as the web app's (rested.ts, levelling, Ledger.kt).

local _, ns = ...
ns = ns or {}

local Views = {}
ns.Views = Views

-- Classic Era's rested rules, as the web app has them (not yet verified on Forever): 5% of a level
-- every 8 hours at an inn, a quarter of that elsewhere, at most 1.5 levels.
Views.RESTED_GAIN_PER_8H = 0.05
Views.RESTED_OUTSIDE_FACTOR = 0.25
Views.RESTED_CAP_LEVELS = 1.5

-- Gaps between XP gains longer than this are time away, not play.
Views.PLAY_GAP = 600

-- "a,,b" -> { "a", "", "b" }: empty columns kept.
local function split(row)
	local out = {}
	for value in string.gmatch(row .. ",", "([^,]*),") do
		out[#out + 1] = value
	end
	return out
end

-- A stream's rows across every saved day, each as { column = value } by the declared columns, in
-- time order. Numbers stay strings; the callers convert what they use. With `char` only that
-- character's rows, and with `from` only rows from then on: the others are passed over before they
-- are split (every stream starts "t,char"), which on two weeks of rows is most of the work.
function Views.rows(db, stream, char, from)
	local names = {}
	for name in string.gmatch(db.fields and db.fields[stream] or "", "[^,]+") do
		names[#names + 1] = name
	end
	local out = {}
	for _, bucket in pairs(db.events or {}) do
		for _, chunk in ipairs(bucket[stream] or {}) do
			for row in string.gmatch(chunk, "[^;]+") do
				if char or from then
					local t, c = string.match(row, "^(%d*),(%d*)")
					if (char and tonumber(c) ~= char) or (from and (tonumber(t) or 0) < from) then
						row = nil
					end
				end
				if row then
					local values, r = split(row), {}
					for i, name in ipairs(names) do
						r[name] = values[i] ~= "" and values[i] or nil
					end
					r.t = tonumber(r.t) or 0
					r.char = tonumber(r.char)
					out[#out + 1] = r
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.t < b.t
	end)
	return out
end

-- Rested XP now for a character saved with xp = { cur, max, rested, resting, t }: as read when it is
-- the one online, else grown since its save by the rules above. Returns rested, cap.
function Views.rested(xp, now, online)
	if not xp or not xp.max or xp.max <= 0 then
		return 0, 0
	end
	local cap = xp.max * Views.RESTED_CAP_LEVELS
	local rested = math.min(xp.rested or 0, cap)
	if online then
		return rested, cap
	end
	local factor = xp.resting and 1 or Views.RESTED_OUTSIDE_FACTOR
	local perSecond = xp.max * Views.RESTED_GAIN_PER_8H * factor / (8 * 3600)
	return math.min(cap, rested + perSecond * math.max(0, now - (xp.t or now))), cap
end

-- Every character as a row (`display` is its name with its surname, and its realm when that is not
-- enough to tell it apart), and the one to play next: the most rested XP waiting in levels, among
-- those not online and not at the cap. db.characters is keyed by GUID; `online` is the one playing.
function Views.characters(characters, now, online)
	local rows, best = {}, nil
	for guid, c in pairs(characters or {}) do
		local isOnline = guid == online
		local rested = Views.rested(c.xp, now, isOnline)
		local row = {
			guid = guid,
			name = c.name or "?",
			class = c.class,
			faction = c.faction,
			level = c.level or 0,
			money = c.money or 0,
			progress = c.xp and c.xp.max and c.xp.max > 0 and c.xp.cur / c.xp.max or nil,
			restedLevels = c.xp and c.xp.max and c.xp.max > 0 and rested / c.xp.max or nil,
			seen = isOnline and now or c.seen,
			online = isOnline,
		}
		row.display = c.surname and c.surname ~= "" and (row.name .. " " .. c.surname) or row.name
		row.realm = c.realm
		rows[#rows + 1] = row
		if row.restedLevels and not isOnline and (not best or row.restedLevels > best.restedLevels) then
			best = row
		end
	end
	-- Names still shared (no surname, another realm) get the realm after them.
	local seen = {}
	for _, r in ipairs(rows) do
		seen[r.display] = (seen[r.display] or 0) + 1
	end
	for _, r in ipairs(rows) do
		if seen[r.display] > 1 and r.realm then
			r.display = r.display .. " · " .. r.realm
		end
	end
	return rows, best
end

-- Where a change in money came from, by the windows open at the time; a flight is matched by time.
local CATEGORIES = {
	{ "loot", { loot = true } },
	{ "quest", { quest = true } },
	{ "training", { trainer = true } },
	{ "travel", { taxinode = true, taxi = true } },
	{ "auction", { auctioneer = true, auction = true } },
	{ "vendor", { merchant = true } },
	{ "mail", { mailinfo = true, mail = true } },
	{ "trade", { trade = true } },
}

Views.CATEGORY_LABELS = {
	loot = "Loot", quest = "Quests", training = "Training", travel = "Flights", auction = "Auction house",
	vendor = "Vendors", mail = "Mail", trade = "Trade", other = "Other",
}

function Views.category(ctx, isFlight)
	if isFlight then
		return "travel"
	end
	local windows = {}
	for name in string.gmatch(ctx or "", "[^+]+") do
		windows[name] = true
	end
	for _, c in ipairs(CATEGORIES) do
		for name in pairs(c[2]) do
			if windows[name] then
				return c[1]
			end
		end
	end
	return "other"
end

-- Money in and out by where it came from, for one character's ref (nil for all) since `from`:
-- { categories = { { key, label, n, gained, spent, net } }, gained, spent, days = { [day] = net } }.
-- `flights` are the flight rows: a payment of a flight's cost within a few seconds of it is that flight.
Views.FLIGHT_SECONDS = 3

local function isFlight(flights, r, delta)
	for _, f in ipairs(flights or {}) do
		if f.char == r.char and math.abs(f.t - r.t) <= Views.FLIGHT_SECONDS and tonumber(f.cost) == -delta then
			return true
		end
	end
	return false
end

function Views.ledger(money, flights, ref, from, dayOf)
	local by, out = {}, { categories = {}, gained = 0, spent = 0, days = {} }
	for _, r in ipairs(money or {}) do
		local delta = tonumber(r.delta)
		if delta and (ref == nil or r.char == ref) and r.t >= (from or 0) then
			local key = Views.category(r.ctx, delta < 0 and isFlight(flights, r, delta))
			local c = by[key]
			if not c then
				c = { key = key, label = Views.CATEGORY_LABELS[key], n = 0, gained = 0, spent = 0, net = 0 }
				by[key] = c
				out.categories[#out.categories + 1] = c
			end
			c.n = c.n + 1
			c.net = c.net + delta
			if delta > 0 then
				c.gained, out.gained = c.gained + delta, out.gained + delta
			else
				c.spent, out.spent = c.spent - delta, out.spent - delta
			end
			if dayOf then
				local day = dayOf(r.t)
				out.days[day] = (out.days[day] or 0) + delta
			end
		end
	end
	out.net = out.gained - out.spent
	return out
end

-- One character's levelling from its level and XP rows:
-- { levels = { { level, seconds, reached, money } }, sources = { [kind] = xp }, xp, rested,
--   playSeconds, perHour }. A level's time is from /played: each row knows when its level started
-- (played - levelPlayed), so a level lasted from its start to the next one's.
function Views.levelling(levelRows, xpRows, ref)
	local starts, reached = {}, {}
	for _, r in ipairs(levelRows or {}) do
		if r.char == ref then
			local level, played, levelPlayed = tonumber(r.level), tonumber(r.played), tonumber(r.levelPlayed)
			if level and played and levelPlayed then
				starts[level] = starts[level] or (played - levelPlayed)
			end
			if level and r.kind == "up" then
				reached[level] = { t = r.t, money = tonumber(r.money) }
			end
		end
	end
	local out = { levels = {}, sources = {}, xp = 0, rested = 0, playSeconds = 0 }
	for level, start in pairs(starts) do
		local nextStart = starts[level + 1]
		local seconds = nextStart and nextStart >= start and (nextStart - start) or nil
		if seconds or reached[level] then
			out.levels[#out.levels + 1] = {
				level = level,
				seconds = seconds,
				reached = reached[level] and reached[level].t,
				money = reached[level] and reached[level].money,
			}
		end
	end
	for level, r in pairs(reached) do
		if not starts[level] then
			out.levels[#out.levels + 1] = { level = level, reached = r.t, money = r.money }
		end
	end
	table.sort(out.levels, function(a, b)
		return a.level > b.level
	end)

	local last
	for _, r in ipairs(xpRows or {}) do
		local xp = tonumber(r.xp)
		if r.char == ref and xp and xp > 0 then
			local kind = r.kind or "other"
			out.sources[kind] = (out.sources[kind] or 0) + xp
			out.xp = out.xp + xp
			out.rested = out.rested + (tonumber(r.rested) or 0)
			if last and r.t - last <= Views.PLAY_GAP then
				out.playSeconds = out.playSeconds + (r.t - last)
			end
			last = r.t
		end
	end
	out.perHour = out.playSeconds >= 300 and out.xp / out.playSeconds * 3600 or nil
	return out
end

-- "2d 4h", "3h 12m", "45m", "under a minute".
function Views.duration(seconds)
	if not seconds then
		return "—"
	end
	seconds = math.floor(seconds)
	local d, h, m = math.floor(seconds / 86400), math.floor(seconds / 3600) % 24, math.floor(seconds / 60) % 60
	if d > 0 then
		return h > 0 and string.format("%dd %dh", d, h) or string.format("%dd", d)
	elseif h > 0 then
		return m > 0 and string.format("%dh %dm", h, m) or string.format("%dh", h)
	elseif m > 0 then
		return string.format("%dm", m)
	end
	return "under a minute"
end

-- "now", "12m ago", "3h ago", "2d ago".
function Views.ago(t, now)
	if not t then
		return "—"
	end
	local s = now - t
	if s < 60 then
		return "now"
	end
	return Views.duration(s < 3600 and s or s < 86400 and math.floor(s / 3600) * 3600 or math.floor(s / 86400) * 86400) .. " ago"
end

-- The session HUD's numbers (design 009, Session module) from a session { coin, xp, killXp, kills } that
-- has run `elapsed` seconds, its loot worth `value`, and `toLevel` XP to the next level (0 or less at the
-- cap). No rate in the first minute: one lucky drop is not a rate. dingIn is seconds at this XP pace;
-- killsToLevel at this session's XP a kill.
Views.SESSION_MIN_RATE = 60

function Views.sessionRates(s, elapsed, value, toLevel)
	local total = (s.coin or 0) + (value or 0)
	local r = { total = total, rated = elapsed >= Views.SESSION_MIN_RATE }
	if r.rated then
		r.goldPerHour = total * 3600 / elapsed
		r.xpPerHour = (s.xp or 0) * 3600 / elapsed
		r.killsPerHour = (s.kills or 0) * 3600 / elapsed
		if r.xpPerHour > 0 and toLevel and toLevel > 0 then
			r.dingIn = toLevel / r.xpPerHour * 3600
		end
	end
	-- XP a kill from the kills that gave XP (grey mobs give none and count only as kills).
	local xpKills = s.xpKills or s.kills or 0
	if xpKills > 0 and (s.killXp or 0) > 0 and toLevel and toLevel > 0 then
		r.killsToLevel = math.ceil(toLevel / (s.killXp / xpKills))
	end
	return r
end

-- "12.3k" for the HUD: thousands with one decimal, millions likewise, smaller numbers whole.
function Views.short(n)
	n = n or 0
	if n >= 1e6 then
		return string.format("%.1fm", n / 1e6)
	elseif n >= 1e3 then
		return string.format("%.1fk", n / 1e3)
	end
	return tostring(math.floor(n + 0.5))
end

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

-- The start of the server's UTC day that `t` falls in, as the saved days are bucketed.
function Views.dayStart(t)
	return t - t % 86400
end

-- Kills in one fight without the combat log (design 009; the playground's killsInFight): when the fight
-- closes (combat over and a few seconds to loot), the larger of its kill-XP gains and the creature
-- corpses looted for the first time. A corpse looted again is no new kill; a grey mob gives no XP but its
-- corpse counts; a chest or herb (not a creature) never does. `seen` (guid -> true) is updated in place.
-- Kills to add for a closed fight (or a loot or kill XP outside any), across fights: a kill credited
-- by its XP whose corpse is looted later, after its fight closed or inside the next one, is not counted
-- again. `pending` holds the times of XP kills with no corpse yet; a fresh corpse first matches one of
-- those (from the last MATCH_SECONDS), then counts as a kill of its own. Returns the kills to add.
Views.MATCH_SECONDS = 120
function Views.creditKills(pending, xpKills, corpses, seen, now)
	for i = #pending, 1, -1 do
		if now - pending[i] > Views.MATCH_SECONDS then
			table.remove(pending, i)
		end
	end
	local fresh = 0
	for _, guid in ipairs(corpses or {}) do
		if string.find(guid, "^Creature%-") and not seen[guid] then
			seen[guid] = true
			fresh = fresh + 1
		end
	end
	local matched = math.min(fresh, #pending)
	for _ = 1, matched do
		table.remove(pending, 1)
	end
	fresh = fresh - matched
	for _ = 1, (xpKills or 0) - fresh do
		pending[#pending + 1] = now
	end
	return math.max(xpKills or 0, fresh)
end

function Views.killsInFight(xpKills, corpses, seen)
	local fresh = 0
	for _, guid in ipairs(corpses or {}) do
		if string.find(guid, "^Creature%-") and not seen[guid] then
			seen[guid] = true
			fresh = fresh + 1
		end
	end
	return math.max(xpKills or 0, fresh)
end

-- The rares seen, one row each from the rare stream's rows ({ t, npc, map, x, y, how }): how often, the
-- last sighting's time, place and how it was seen; the latest first.
function Views.rares(rows)
	local by, out = {}, {}
	for _, r in ipairs(rows or {}) do
		local npc = tonumber(r.npc)
		if npc then
			local e = by[npc]
			if not e then
				e = { npc = npc, seen = 0, last = 0 }
				by[npc] = e
				out[#out + 1] = e
			end
			e.seen = e.seen + 1
			if r.t >= e.last then
				e.last, e.map, e.x, e.y, e.how = r.t, tonumber(r.map), tonumber(r.x), tonumber(r.y), r.how
			end
		end
	end
	table.sort(out, function(a, b)
		return a.last > b.last
	end)
	return out
end

-- Auction house sales from the sale stream ({ t, char, item, qty, price, deposit, cut }, the "sold" mail):
-- for one character (ref) or all (nil), from `from` on, newest first, each with what it brought after
-- the cut; and the totals. The deposit comes back with the sale and is not counted as earned.
function Views.sales(rows, ref, from)
	local out = { list = {}, count = 0, gross = 0, cut = 0, net = 0 }
	for _, r in ipairs(rows or {}) do
		local price = tonumber(r.price)
		if price and (ref == nil or r.char == ref) and r.t >= (from or 0) then
			local cut = tonumber(r.cut) or 0
			local sale = { t = r.t, char = r.char, item = r.item or "?", qty = tonumber(r.qty) or 1, price = price, cut = cut, net = price - cut }
			out.list[#out.list + 1] = sale
			out.count = out.count + 1
			out.gross = out.gross + price
			out.cut = out.cut + cut
			out.net = out.net + sale.net
		end
	end
	table.sort(out.list, function(a, b)
		return a.t > b.t
	end)
	return out
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
			bank = math.min(bank, math.max(0, need - bags)), -- to pick up from the bank
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

-- A gold goal on Home: gold now (copper, all characters) against goal = { gold (copper), by (Unix time) }.
-- Returns { pct (0–100), left (copper still to make), daysLeft, perDay (copper a day to make it, nil once
-- reached or past), reached, late }.
function Views.goal(now, total, goal)
	local pct = goal.gold > 0 and math.min(100, math.floor(total / goal.gold * 100)) or 100
	local left = math.max(0, goal.gold - total)
	local daysLeft = math.max(0, math.ceil((goal.by - now) / 86400))
	local reached = left == 0
	local late = not reached and now >= goal.by
	return { pct = pct, left = left, daysLeft = daysLeft, reached = reached, late = late,
		perDay = (not reached and not late) and math.ceil(left / math.max(1, daysLeft)) or nil }
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

-- n lines in room rows: all of them when they fit, else room - 1 and a last row for the rest. Returns how
-- many show and how many are left for "+N more".
function Views.fit(n, room)
	if n <= room then
		return n, 0
	end
	return room - 1, n - room + 1
end

-- How many character rows (Views.characters) are at the level cap: by level, not by the XP missing, which
-- a character not yet read has missing too.
function Views.capped(rows, maxLevel)
	local n = 0
	for _, r in ipairs(rows) do
		if (r.level or 0) >= maxLevel then
			n = n + 1
		end
	end
	return n
end
