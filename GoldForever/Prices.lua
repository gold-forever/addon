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
local REGIONS = { US = "NA", NA = "NA", EU = "EU", KR = "KR", TW = "TW", CN = "CN" }

local function amount(x)
	return type(x) == "number" and x >= 0 and x < math.huge
end

local function field(t, key)
	local value = type(t) == "table" and t[key] or nil
	return type(value) == "table" and value or nil
end

local function ruleset(realm)
	if string.find(string.lower(realm), "%f[%w]pvp%f[%W]") then
		return "pvp"
	elseif string.find(realm, "%f[%w]RP%f[%W]") then
		return "rp"
	end
	return "normal"
end

-- The server's key for the addon's market "<region>-<realm>-<side>" (backend Markets.kt key()):
-- "forever-<region>-<ruleset>-<side>". Forever only; nil on retail and for anything malformed.
function Prices.poolMarket(market, interface)
	if type(market) ~= "string" or not ns.Realms.isForever(interface) then
		return nil
	end
	local region, realm, side = string.match(market, "^([^-]+)-(.+)-([^-]+)$")
	if not region then
		return nil
	end
	return "forever-" .. (REGIONS[string.upper(region)] or "BETA") .. "-" .. ruleset(realm) .. "-" .. side
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
	local r = REGIONS[string.upper(region)] or "BETA"
	return { "retail-" .. r .. "-" .. string.gsub(realm, "[ %-%.]", ""), "retail-" .. r }
end

-- The server's keys to read for the addon's market, in order; nil when there are none.
function Prices.markets(market, interface)
	if type(market) ~= "string" then
		return nil
	end
	if ns.Realms.isRetail(interface) then
		return retailMarkets(market)
	end
	local key = Prices.poolMarket(market, interface)
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

-- data: GoldForever_Prices; markets: the server's keys (Prices.markets); id: the item. Nil without a valid price.
function Prices.line(data, markets, id, now)
	if type(data) ~= "table" or data.v ~= VERSION or type(markets) ~= "table" or id == nil then
		return nil
	end
	local value, minBuyout, players, scannedAt = entry(data, markets, id)
	if not value then
		return nil
	end
	players = math.floor(players)
	local coins = ns.price.coins
	return string.format("Pool: %s · min %s · %d %s · %s", coins(value), coins(minBuyout), players,
		players == 1 and "player" or "players", ns.Views.ago(scannedAt, now))
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("pool tooltip", function()
			if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not ns.me() then
				return
			end
			local markets = Prices.markets(ns.market(string.lower(ns.me().faction or "?")), ns.db().client.interface)
			local line = Prices.line(GoldForever_Prices, markets, data.id, GetServerTime())
			if line then
				tooltip:AddLine(ns.PREFIX .. " " .. line, 1, 1, 1)
			end
		end)
	end)
end
