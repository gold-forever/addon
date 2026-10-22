-- Gold Forever: the pool's prices in item tooltips. The companion writes GoldForever_Prices into a
-- separate addon, GoldForever_Data (an optional dependency), from the server's pooled, screened
-- figures; the tooltip shows the player's own market's line under the appraiser's. The file comes
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

-- data: GoldForever_Prices; market: the server's key (poolMarket); id: the item. Nil when there is no valid price.
function Prices.line(data, market, id, now)
	if type(data) ~= "table" or data.v ~= VERSION or market == nil or id == nil then
		return nil
	end
	local entry = field(field(field(data, "markets"), market), id)
	if not entry then
		return nil
	end
	local value, minBuyout, players, scannedAt = entry[1], entry[2], entry[3], entry[4]
	if not (amount(value) and amount(minBuyout) and amount(players) and amount(scannedAt)) then
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
			local market = Prices.poolMarket(ns.market(string.lower(ns.me().faction or "?")), ns.db().client.interface)
			local line = Prices.line(GoldForever_Prices, market, data.id, GetServerTime())
			if line then
				tooltip:AddLine(ns.PREFIX .. " " .. line, 1, 1, 1)
			end
		end)
	end)
end
