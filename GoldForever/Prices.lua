-- Gold Forever: the pool's prices in item tooltips. The companion writes GoldForever_Prices into a
-- separate addon, GoldForever_Data (an optional dependency), from the server's pooled, screened
-- figures; the tooltip shows the player's own market's line under the appraiser's (on retail the
-- connected realm group's, else the region's commodity price). The file comes
-- from outside the addon, so every field is checked and anything unexpected shows nothing.

local _, ns = ...
ns = ns or {}

local Prices = {}
ns.Prices = Prices

local VERSION = 1 -- the GoldForever_Prices layout this addon reads
local STALE_SECONDS = 3 * 86400 -- a price scanned longer ago than this is greyed
local STALE_SHADE = 0.6 -- the tooltip's grey, as the addon's muted text (|cff999999)
local REGIONS = { US = "NA", NA = "NA", EU = "EU", KR = "KR", TW = "TW", CN = "CN" }
-- GetCurrentRegion's ids, which the addon writes when GetCurrentRegionName answers "".
local REGION_IDS = { ["1"] = "NA", ["2"] = "KR", ["3"] = "EU", ["4"] = "TW", ["5"] = "CN" }
local BETA_REGION, BETA_PORTAL = "110", "test"
local MAX_REGION_CODE, MAX_RULESET = 8, 32

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

local function trim(x)
	return (string.gsub(x, "^%s*(.-)%s*$", "%1"))
end

-- A live region's key for a raw region name or id, else nil.
local function live(raw)
	if type(raw) ~= "string" then
		return nil
	end
	local r = string.upper(trim(raw))
	return REGIONS[r] or REGION_IDS[r]
end

-- Backend Markets.region: as the client named it, else as the portal CVar does; the beta's "110" and
-- portal "test" are the beta ("110" wins over a live portal). Anything else is a market of its own:
-- "X" and its code ("X41"), or UNKNOWN with none; never the beta.
function Prices.region(raw, portal)
	local r = live(raw)
	if r then
		return r
	end
	if type(raw) == "string" and trim(raw) == BETA_REGION then
		return "BETA"
	end
	r = live(portal)
	if r then
		return r
	end
	if type(portal) == "string" and string.lower(trim(portal)) == BETA_PORTAL then
		return "BETA"
	end
	local code = type(raw) == "string" and string.sub(string.gsub(string.upper(raw), "[^A-Z0-9]", ""), 1, MAX_REGION_CODE) or ""
	return code == "" and "UNKNOWN" or ("X" .. code)
end

-- A realm name's words as the server reads them, byte by byte over its UTF-8: A–Z lowercased, a–z and
-- 0–9 kept, any byte from 0x80 up written as its two lowercase hex digits (so "Гордунни" is one ASCII
-- word, and ’ joins its word as "e28099"), any other byte a separator.
function Prices.words(realm)
	local words, word = {}, {}
	local function close()
		if #word > 0 then
			words[#words + 1] = table.concat(word)
			word = {}
		end
	end
	for i = 1, #realm do
		local b = string.byte(realm, i)
		if b >= 65 and b <= 90 then
			word[#word + 1] = string.char(b + 32)
		elseif (b >= 97 and b <= 122) or (b >= 48 and b <= 57) then
			word[#word + 1] = string.char(b)
		elseif b >= 128 then
			word[#word + 1] = string.format("%02x", b)
		else
			close()
		end
	end
	close()
	return words
end

-- Backend Markets.ruleset: from the realm name's words (Prices.words): Hardcore; RP and PvP together (or
-- "rppvp") RP-PvP; PvP; RP, Roleplay(ing) or "Role Play"; PvE or Normal. A name saying none of these is
-- a market of its own, keyed by its words joined and cut to 32 characters ("shendralas").
function Prices.ruleset(realm)
	if type(realm) ~= "string" then
		return "normal"
	end
	local words, has = Prices.words(realm), {}
	for _, w in ipairs(words) do
		has[w] = true
	end
	local rp = has.rp or has.roleplay or has.roleplaying or has.rppvp
	for i = 1, #words - 1 do
		if words[i] == "role" and words[i + 1] == "play" then
			rp = true
		end
	end
	local pvp = has.pvp or has.rppvp
	if has.hardcore then
		return "hardcore"
	elseif rp and pvp then
		return "rppvp"
	elseif pvp then
		return "pvp"
	elseif rp then
		return "rp"
	elseif has.pve or has.normal then
		return "normal"
	end
	local joined = string.sub(table.concat(words), 1, MAX_RULESET)
	return joined == "" and "unknown" or joined
end

-- The server's key for the addon's market "<region>-<realm>-<side>" (backend Markets.kt key()):
-- "forever-<region>-<ruleset>-<side>". Forever only; nil on retail and for anything malformed.
-- `portal` is the save's portal CVar, for a region the client named only by a number.
function Prices.poolMarket(market, interface, portal)
	if type(market) ~= "string" or not ns.Realms.isForever(interface) then
		return nil
	end
	local region, realm, side = string.match(market, "^([^-]+)-(.+)-([^-]+)$")
	if not region then
		return nil
	end
	return "forever-" .. Prices.region(region, portal) .. "-" .. Prices.ruleset(realm) .. "-" .. side
end

local SIDES = { alliance = true, horde = true, neutral = true }

-- Backend Markets.parts: region, realm and side of "<region>-<realm>-<side>"; the realm may be empty.
local function parts(market)
	local first = string.find(market, "-", 1, true)
	local last = string.match(market, ".*()%-")
	if not first or first == 1 or last == first then
		return nil
	end
	local side = string.lower(string.sub(market, last + 1))
	if not SIDES[side] then
		return nil
	end
	return string.sub(market, 1, first - 1), string.sub(market, first + 1, last - 1), side
end

-- Backend Markets.retail: the connected realm group's market, then the region's commodities.
local function retailMarkets(market)
	local region, realm = parts(market)
	if not region then
		return nil
	end
	local r = Prices.region(region)
	return { "retail-" .. r .. "-" .. string.gsub(realm, "[ %-%.]", ""), "retail-" .. r }
end

-- The server's keys to read for the addon's market, in order; nil when there are none.
function Prices.markets(market, interface, portal)
	if type(market) ~= "string" then
		return nil
	end
	if ns.Realms.isRetail(interface) then
		return retailMarkets(market)
	end
	local key = Prices.poolMarket(market, interface, portal)
	return key and { key } or nil
end

-- The first market's valid entry for the item: value, minimum buyout, players, scan time.
-- An item's entry: { market value, min buyout, players, scanned at[, week: the mean of its daily values
-- over the 7 full days before the scan's day, absent with fewer than 3 or in a reset] }. The fifth is new (owner's answer, 2026-10-24: a trend at launch); a file without it, or
-- with it unusable, shows no trend.
local function entry(data, markets, id)
	for _, market in ipairs(markets) do
		local e = field(field(field(data, "markets"), market), id)
		if e and amount(e[1]) and amount(e[2]) and amount(e[3]) and amount(e[4]) then
			return e[1], e[2], e[3], e[4], (amount(e[5]) and e[5] > 0) and e[5] or nil
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
-- 001: a pool value far over today's listings held every Small Egg): the 7-day average where the pool
-- has one, so a day's dip or spike does not move it; else the value, and where it came from.
function Prices.sellBase(value, from, week)
	if week and week > 0 then
		return week, "7-day avg"
	end
	return value, from
end

-- " · +8% vs 7-day avg", " · steady vs 7-day avg" within 1%, or "" without a trend. The average is the
-- mean of the item's daily values over the 7 full days before its scan (the server's `week`).
function Prices.trendText(pct)
	if not pct then
		return ""
	end
	if math.abs(pct) < 1 then
		return " · steady vs 7-day avg"
	end
	return string.format(" · %s%d%% vs 7-day avg", pct > 0 and "+" or "-", math.abs(pct))
end

-- Whether data is a prices file this addon reads.
function Prices.loaded(data)
	return type(data) == "table" and data.v == VERSION and type(data.markets) == "table"
end

local function ago(t, now)
	local text = ns.Views.ago(t, now)
	return text == "now" and "just now" or text
end

local function scanned(scannedAt, now)
	return "scanned " .. ago(scannedAt, now), now - scannedAt > STALE_SECONDS
end

-- data: GoldForever_Prices; markets: the server's keys (Prices.markets); id: the item. The line and whether it
-- is stale; nil without a valid price.
function Prices.line(data, markets, id, now, label)
	if not Prices.loaded(data) or type(markets) ~= "table" or id == nil then
		return nil
	end
	local value, minBuyout, players, scannedAt, week = entry(data, markets, id)
	if not value then
		return nil
	end
	-- Short (manual test run 001): the value, the trend, the cheapest; the age only once it is old.
	local coins = ns.price.coins
	local age, stale = scanned(scannedAt, now)
	return string.format("%s %s%s · min %s%s", label or "Market", coins(value), Prices.trendText(Prices.trend(value, week)),
		coins(minBuyout), stale and (" · " .. age) or ""), stale
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
	if data.v ~= VERSION then
		return { string.format("the prices file is version %s; this addon reads version %d. Update the addon.", tostring(data.v), VERSION) }
	end
	if not Prices.loaded(data) then
		return { "the prices file cannot be read. The companion app writes it again on its next update." }
	end
	local keys, used = {}, {}
	for key in pairs(data.markets) do
		keys[#keys + 1] = tostring(key)
	end
	table.sort(keys)
	for _, key in ipairs(mine or {}) do
		used[key] = true
	end
	local age = amount(data.at) and ("written " .. ago(data.at, now)) or "of unknown age"
	local lines = { string.format("prices file %s · %d %s", age, #keys, #keys == 1 and "market" or "markets") }
	for _, key in ipairs(keys) do
		local n = count(data.markets[key])
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

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function poolTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not ns.me() then
			return
		end
		-- Settings → Modules can switch the line off.
		if ns.settings("prices").tooltip == false then
			return
		end
		local now = GetServerTime()
		-- In a zone with a neutral auction house, its market's line first (design 009 decision 9).
		local neutral = Prices.neutralMarkets()
		if neutral then
			local nline, nstale = Prices.line(GoldForever_Prices, neutral, data.id, now, "Neutral AH")
			if nline then
				local shade = nstale and STALE_SHADE or 1
				tooltip:AddLine(ns.tipPrefix(tooltip) .. nline, shade, shade, shade)
			end
		end
		-- The own scan has its own line (Tooltips.lua): only the pool's here.
		local line, stale = Prices.line(GoldForever_Prices, mine(), data.id, now)
		if line then
			local shade = stale and STALE_SHADE or 1
			tooltip:AddLine(ns.tipPrefix(tooltip) .. line, shade, shade, shade)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("pool tooltip", poolTooltip, tooltip, data)
	end)
end

-- The companion's file as the hub's Companion page shows it: state "missing", "version", "broken" or
-- "ok"; the time it was written; and each market { key, items, mine }, this character's first.
function Prices.status(data, mine, now)
	if type(data) ~= "table" then
		return { state = "missing", markets = {} }
	end
	if data.v ~= VERSION then
		return { state = "version", version = data.v, markets = {} }
	end
	if not Prices.loaded(data) then
		return { state = "broken", markets = {} }
	end
	local used = {}
	for _, key in ipairs(mine or {}) do
		used[key] = true
	end
	local markets = {}
	for key, items in pairs(data.markets) do
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
		if not data.markets[key] then
			missing[#missing + 1] = key
		end
	end
	return { state = "ok", at = amount(data.at) and data.at or nil, age = amount(data.at) and ago(data.at, now) or nil, markets = markets, missing = missing }
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
	if type(data) ~= "table" or not amount(data.at) then
		return nil
	end
	local age = now - data.at
	if age <= Prices.STALE_FILE or (lastWarned and now - lastWarned < 86400) then
		return nil
	end
	local days = math.floor(age / 86400)
	return string.format("everyone's prices are %d %s old: is the companion app running? gold-forever.app/companion", days, days == 1 and "day" or "days")
end

-- This character's market keys, for the Companion page.
Prices.mine = function()
	return mine()
end

ns.on("PLAYER_ENTERING_WORLD", "stale prices", function(isInitialLogin)
	if not isInitialLogin then
		return
	end
	local s = ns.settings("prices")
	local text = Prices.staleWarning(GoldForever_Prices, GetServerTime(), s.staleWarned)
	if text then
		s.staleWarned = GetServerTime()
		ns.say(text)
	end
end)

ns.commands.prices = function()
	local lines = Prices.summary(GoldForever_Prices, mine(), GetServerTime())
	ns.say(lines[1])
	for i = 2, #lines do
		print("  " .. lines[i])
	end
end
