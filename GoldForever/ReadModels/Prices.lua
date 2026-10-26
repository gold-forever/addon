-- Gold Forever: the pool's prices. The companion writes GoldForever_Prices into a separate addon,
-- GoldForever_Data (an optional dependency), from the server's pooled, screened figures; this reads the
-- player's own market's prices from it (on retail the connected realm group's, else the region's
-- commodity price), which the item tooltip shows (Tooltips.lua). The file comes from outside the addon,
-- so every field is checked and anything unexpected shows nothing. The server's keys for a market:
-- PricesMarkets.lua.

local _, ns = ...
ns = ns or {}

local Prices = {}
ns.Prices = Prices

-- The GoldForever_Prices layout this addon reads, its fields and an item's figures (DataFormat.lua).
local VERSION = ns.DataFormat.VERSION
local F, ITEM = ns.DataFormat.field, ns.DataFormat.item
local STALE_SECONDS = 3 * 86400 -- a price scanned longer ago than this is greyed

-- A number the file may carry: a price, a count or a time, none of them above a million gold's copper
-- (a time stays under it until the year 2286), so an absurd price never reaches a post.
local MAX = ns.Encode.MAX_COPPER
local function amount(x)
	return type(x) == "number" and x >= 0 and x <= MAX
end

local function field(t, key)
	local value = type(t) == "table" and t[key] or nil
	return type(value) == "table" and value or nil
end

-- The first market's valid entry for the item: value, minimum buyout, players, scan time.
-- An item's entry: { market value, min buyout, players, scanned at[, week: the typical price, the median of
-- its daily values over the 7 full days before the scan's day, absent with fewer than 3 or in a reset] }.
-- A file without the fifth, or with it unusable, shows no typical price and no trend.
local function entry(data, markets, id)
	for _, market in ipairs(markets) do
		local e = field(field(field(data, F.markets), market), id)
		if e and amount(e[ITEM.value]) and amount(e[ITEM.minBuyout]) and amount(e[ITEM.players]) and amount(e[ITEM.scannedAt]) then
			local week = e[ITEM.week]
			return e[ITEM.value], e[ITEM.minBuyout], e[ITEM.players], e[ITEM.scannedAt], (amount(week) and week > 0) and week or nil
		end
	end
end

-- The market value against the week before, in whole percent; nil without both.
function Prices.trend(value, week)
	if not value or not week or week <= 0 then
		return nil
	end
	return math.floor((value - week) / week * 100 + 0.5)
end

-- What Sell measures the floor and normal price against (owner's answer, 2026-10-24, manual test run
-- 001: a pool value far over today's listings held every Small Egg): the typical price where the pool
-- has one, so a day's dip or spike does not move it; else the value, and where it came from.
function Prices.sellBase(value, from, week)
	if week and week > 0 then
		return week, "typical price"
	end
	return value, from
end

local function signed(pct)
	if math.abs(pct) < 1 then
		return "steady"
	end
	return string.format("%s%d%%", pct > 0 and "+" or "-", math.abs(pct))
end

-- " · +8% vs typical", " · steady vs typical" within 1%, or "" without a trend. The typical price is the
-- median of the item's daily values over the 7 full days before its scan (the server's `week`), as the
-- site names it.
function Prices.trendText(pct)
	if not pct then
		return ""
	end
	return " · " .. signed(pct) .. " vs typical"
end

-- Whether data is a prices file this addon reads.
function Prices.loaded(data)
	return type(data) == "table" and data[F.version] == VERSION and type(data[F.markets]) == "table"
end

local function ago(t, now)
	local text = ns.Views.ago(t, now)
	return text == "now" and "just now" or text
end

local function scanned(scannedAt, now)
	return "scanned " .. ago(scannedAt, now), now - scannedAt > STALE_SECONDS
end

-- data: GoldForever_Prices; markets: the server's keys (Prices.markets); id: the item. The tooltip's rows,
-- one price a row as { label, value } (addon#20: one long line was hard to read), and whether they are
-- stale; nil without a valid price. The value, the typical price with the value against it, the cheapest,
-- and the age only once it is old.
function Prices.rows(data, markets, id, now, label)
	if not Prices.loaded(data) or type(markets) ~= "table" or id == nil then
		return nil
	end
	local value, minBuyout, _, scannedAt, week = entry(data, markets, id)
	if not value then
		return nil
	end
	local coins = ns.price.coins
	local rows = { { label or "Market", coins(value) } }
	local pct = Prices.trend(value, week)
	if pct then
		rows[#rows + 1] = { "Typical", coins(week) .. " (" .. signed(pct) .. ")" }
	end
	rows[#rows + 1] = { "Min", coins(minBuyout) }
	local stale = now - scannedAt > STALE_SECONDS
	if stale then
		rows[#rows + 1] = { "Scanned", ago(scannedAt, now) }
	end
	return rows, stale
end

-- The player's own latest scan (the appraiser's prices), for an item the file lacks.
function Prices.ownLine(value, cheapest, scannedAt, now)
	if not value or not scannedAt then
		return nil
	end
	local coins = ns.price.coins
	local age, stale = scanned(scannedAt, now)
	local min = cheapest and (" · min " .. coins(cheapest)) or ""
	return "Your scan " .. coins(value) .. min .. (stale and (" · " .. age) or ""), stale
end

local function count(t)
	local n = 0
	for _ in pairs(type(t) == "table" and t or {}) do
		n = n + 1
	end
	return n
end

-- /gf prices: the file's age, then each market with its item count; mine are the keys the tooltip reads.
function Prices.summary(data, mine, now)
	if type(data) ~= "table" then
		return { "no prices file loaded. The companion app writes it into the GoldForever_Data addon." }
	end
	if data[F.version] ~= VERSION then
		return { string.format("the prices file is version %s; this addon reads version %d. Update the addon.", tostring(data[F.version]), VERSION) }
	end
	if not Prices.loaded(data) then
		return { "the prices file cannot be read. The companion app writes it again on its next update." }
	end
	local keys, used = {}, {}
	for key in pairs(data[F.markets]) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	for _, key in ipairs(mine or {}) do
		used[key] = true
	end
	local age = amount(data[F.at]) and ("written " .. ago(data[F.at], now)) or "of unknown age"
	local lines = { string.format("prices file %s · %d %s", age, #keys, #keys == 1 and "market" or "markets") }
	for _, key in ipairs(keys) do
		local n = count(data[F.markets][key])
		lines[#lines + 1] = string.format("%s: %d %s%s", key, n, n == 1 and "item" or "items", used[key] and " · this character's" or "")
	end
	return lines
end

-- The server's keys for the character being played; nil before login.
-- The character's markets, worked out again only when what they are made of changes (every tooltip and
-- Post row asked, and each answer was new tables and strings).
local myMarkets, made = nil, {}
local function mine()
	local me = ns.me()
	if not me then
		return nil
	end
	local client = ns.db().client
	if not myMarkets or made.faction ~= me.faction or made.realm ~= me.realm or made.region ~= client.region
		or made.interface ~= client.interface or made.portal ~= client.portal then
		made.faction, made.realm, made.region, made.interface, made.portal = me.faction, me.realm, client.region, client.interface, client.portal
		myMarkets = Prices.markets(ns.market(string.lower(me.faction or "?")), client.interface, client.portal)
	end
	return myMarkets
end

-- An item's market value for the character being played: the pool's when the companion's file has it,
-- else the own latest full scan's. Returns value and where it came from ("pool" or "scan"), or nil.
-- An item's market value and where it came from ("pool" or "scan"), and with the pool's its trend on
-- the week (Prices.trend), when the file carries one.
-- The pool's value, unless the player's own scan is newer and more than twice or under half of it: then
-- the own scan's (manual test run 001: Nylon Thread at 48g in the pool from a scan read in part, 99s in a
-- full scan made after it). Returns the value and where it came from.
function Prices.pick(pool, poolAt, own, ownAt)
	if pool and own and poolAt and ownAt and ownAt > poolAt and own > 0 and (pool > own * 2 or pool * 2 < own) then
		return own, "scan"
	end
	return pool, "pool"
end

function Prices.value(id)
	local markets = mine()
	if markets and Prices.loaded(GoldForever_Prices) then
		local value, _, _, scannedAt, week = entry(GoldForever_Prices, markets, id)
		if value then
			local own, _, ownAt = ns.ownPrice(id)
			local picked, from = Prices.pick(value, scannedAt, own, ownAt)
			if from == "scan" then
				return picked, "scan"
			end
			return value, "pool", Prices.trend(value, week), week
		end
	end
	local own = ns.ownPrice(id)
	if own then
		return own, "scan"
	end
end

-- What buying one costs at the auction house: the pool's minimum buyout, picked against the own scan's
-- cheapest unit as the value is (Prices.pick), else the own scan's. A craft's reagents are priced so, the
-- same source as its output's value, so a player with the prices file and no scan of their own sees profits.
function Prices.cheapest(id)
	local _, own, ownAt = ns.ownPrice(id)
	local markets = mine()
	if markets and Prices.loaded(GoldForever_Prices) then
		local _, low, _, scannedAt = entry(GoldForever_Prices, markets, id)
		if low and low > 0 then
			return (Prices.pick(low, scannedAt, own, ownAt))
		end
	end
	return own
end

-- The companion's file as the hub's Companion page shows it: state "missing", "version", "broken" or
-- "ok"; the time it was written; and each market { key, items, mine }, this character's first.
function Prices.status(data, mine, now)
	if type(data) ~= "table" then
		return { state = "missing", markets = {} }
	end
	if data[F.version] ~= VERSION then
		return { state = "version", version = data[F.version], markets = {} }
	end
	if not Prices.loaded(data) then
		return { state = "broken", markets = {} }
	end
	local used = {}
	for _, key in ipairs(mine or {}) do
		used[key] = true
	end
	local markets = {}
	for key, items in pairs(data[F.markets]) do
		markets[#markets + 1] = { key = tostring(key), items = count(items), mine = used[key] or false }
	end
	table.sort(markets, function(a, b)
		if a.mine ~= b.mine then
			return a.mine
		end
		return a.key < b.key
	end)
	local missing = {}
	for _, key in ipairs(mine or {}) do
		if not data[F.markets][key] then
			missing[#missing + 1] = key
		end
	end
	return { state = "ok", at = amount(data[F.at]) and data[F.at] or nil, age = amount(data[F.at]) and ago(data[F.at], now) or nil, markets = markets, missing = missing }
end

-- The neutral auction house's market keys while the player is in its zone, on Forever; else nil.
local neutralMarkets, neutralFor -- the neutral auction house's markets, and the region they are for
function Prices.neutralMarkets()
	if not ns.atNeutralZone() then
		return nil
	end
	local client = ns.db().client
	if not ns.Realms.isForever(client.interface) then
		return nil
	end
	local key = client.region
	if not neutralMarkets or neutralFor ~= key then
		neutralMarkets, neutralFor = Prices.markets(ns.market("neutral"), client.interface, client.portal), key
	end
	return neutralMarkets
end

-- At login: the warning when the companion's prices file is older than a day (owner's answer,
-- 2026-10-24), at most once a day; nil when there is nothing to say (no file, a fresh one, warned today).
Prices.STALE_FILE = 86400
function Prices.staleWarning(data, now, lastWarned)
	if type(data) ~= "table" or not amount(data[F.at]) then
		return nil
	end
	local age = now - data[F.at]
	if age <= Prices.STALE_FILE or (lastWarned and now - lastWarned < 86400) then
		return nil
	end
	local days = math.floor(age / 86400)
	return string.format("everyone's prices are %d %s old: is the companion app running? gold-forever.app/companion", days, days == 1 and "day" or "days")
end

-- Whether the companion app is at work: its prices file is loaded and no older than a day, as it writes
-- one every hour. Without it the player uploads their save by hand (/gf export).
function Prices.connected(data, now)
	return Prices.status(data, nil, now).state == "ok" and amount(data[F.at]) and now - data[F.at] <= Prices.STALE_FILE or false
end

-- This character's market keys, for the Companion page.
Prices.mine = function()
	return mine()
end

ns.module("Prices", {
	requires = { "Store" },
	-- The stale-prices warning, at the login's loading screen only.
	world = function(isInitialLogin)
		if not isInitialLogin then
			return
		end
		local s = ns.settings("prices")
		local text = Prices.staleWarning(GoldForever_Prices, GetServerTime(), s.staleWarned)
		if text then
			s.staleWarned = GetServerTime()
			ns.say(text)
		end
	end,
})

ns.commands.prices = function()
	local lines = Prices.summary(GoldForever_Prices, mine(), GetServerTime())
	ns.say(lines[1])
	for i = 2, #lines do
		print("  " .. lines[i])
	end
end
