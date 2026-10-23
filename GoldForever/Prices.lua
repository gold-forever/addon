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

local function amount(x)
	return type(x) == "number" and x >= 0 and x < math.huge
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
local function entry(data, markets, id)
	for _, market in ipairs(markets) do
		local e = field(field(field(data, "markets"), market), id)
		if e and amount(e[1]) and amount(e[2]) and amount(e[3]) and amount(e[4]) then
			return e[1], e[2], e[3], e[4]
		end
	end
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
	local value, minBuyout, players, scannedAt = entry(data, markets, id)
	if not value then
		return nil
	end
	players = math.floor(players)
	local coins = ns.price.coins
	local age, stale = scanned(scannedAt, now)
	return string.format("%s: %s · min buyout %s · %d %s · %s", label or "Pool", coins(value), coins(minBuyout), players,
		players == 1 and "player" or "players", age), stale
end

-- The player's own latest scan (the appraiser's prices), for an item the file lacks.
function Prices.ownLine(value, cheapest, scannedAt, now)
	if not value or not scannedAt then
		return nil
	end
	local coins = ns.price.coins
	local age, stale = scanned(scannedAt, now)
	local min = cheapest and (" · min buyout " .. coins(cheapest)) or ""
	return "Your scan: " .. coins(value) .. min .. " · " .. age, stale
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
local function mine()
	local me = ns.me()
	local client = ns.db().client
	return me and Prices.markets(ns.market(string.lower(me.faction or "?")), client.interface, client.portal)
end

-- An item's market value for the character being played: the pool's when the companion's file has it,
-- else the own latest full scan's. Returns value and where it came from ("pool" or "scan"), or nil.
function Prices.value(id)
	local markets = mine()
	if markets and Prices.loaded(GoldForever_Prices) then
		local value = entry(GoldForever_Prices, markets, id)
		if value then
			return value, "pool"
		end
	end
	local own = ns.price and ns.price.market(id)
	if own then
		return own, "scan"
	end
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("pool tooltip", function()
			if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not ns.me() then
				return
			end
			-- Settings → Modules can switch the line off.
			if ns.settings("prices", { tooltip = true }).tooltip == false then
				return
			end
			local now = GetServerTime()
			-- In a zone with a neutral auction house, its market's line first (design 009 decision 9).
			local neutral = Prices.neutralMarkets()
			if neutral then
				local nline, nstale = Prices.line(GoldForever_Prices, neutral, data.id, now, "Neutral AH")
				if nline then
					local shade = nstale and STALE_SHADE or 1
					tooltip:AddLine(ns.PREFIX .. " " .. nline, shade, shade, shade)
				end
			end
			local line, stale = Prices.line(GoldForever_Prices, mine(), data.id, now)
			-- Without a file the appraiser's own line is the price; with one, an item it lacks shows the own scan.
			if not line and Prices.loaded(GoldForever_Prices) and ns.ownPrice then
				local value, cheapest, scannedAt = ns.ownPrice(data.id)
				line, stale = Prices.ownLine(value, cheapest, scannedAt, now)
			end
			if line then
				local shade = stale and STALE_SHADE or 1
				tooltip:AddLine(ns.PREFIX .. " " .. line, shade, shade, shade)
			end
		end)
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
function Prices.neutralMarkets()
	if not (ns.atNeutralZone and ns.atNeutralZone()) then
		return nil
	end
	local client = ns.db().client
	if not ns.Realms.isForever(client.interface) then
		return nil
	end
	return Prices.markets(ns.market("neutral"), client.interface, client.portal)
end

-- This character's market keys, for the Companion page.
Prices.mine = function()
	return mine()
end

ns.commands.prices = function()
	local lines = Prices.summary(GoldForever_Prices, mine(), GetServerTime())
	ns.say(lines[1])
	for i = 2, #lines do
		print("  " .. lines[i])
	end
end
