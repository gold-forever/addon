-- Gold Forever: the server's keys for the addon's market (ns.Prices), as the backend's Markets.kt works
-- them out: the region, the realm's ruleset, the pool's key on Forever and the realm group's and region's
-- on retail.

local _, ns = ...
local Prices = ns.Prices

local REGIONS = { US = "NA", NA = "NA", EU = "EU", KR = "KR", TW = "TW", CN = "CN" }
-- GetCurrentRegion's ids, which the addon writes when GetCurrentRegionName answers "".
local REGION_IDS = { ["1"] = "NA", ["2"] = "KR", ["3"] = "EU", ["4"] = "TW", ["5"] = "CN" }
local BETA_REGION, BETA_PORTAL = "110", "test"
local MAX_REGION_CODE, MAX_RULESET = 8, 32

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
