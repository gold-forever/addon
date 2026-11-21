-- ns.market (Store/Characters.lua): the market of the auction house the player is at, "<region>-<realm>-<side>",
-- and the server's keys for it (Prices.markets). Since WoW: Forever's hotfix 1.60.1 the realm name is empty
-- there: one auction house serves a region's game mode and side, so the market names the game mode.

local ns = {}
local handlers = {}
ns.on = function(event, _, fn) handlers[event] = fn end
ns.afterCombat = function() end
ns.tornDown = function() return true end
ns.Prices = {}
for _, file in ipairs({ "Realms.lua", "Characters.lua", "PricesMarkets.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end

-- The stand-in client: a character on `interface`, on `realm`, in game mode `mode` (nil: no answer).
local db
local function client(interface, realm, mode)
	db = { client = { region = "EU", interface = interface }, characters = {} }
	ns.db = function() return db end
	function GetServerTime() return 1761148800 end
	function UnitGUID() return "Player-1-0000000A" end
	function UnitRace() return "Orc", "Orc" end
	function UnitClass() return "Warrior", "WARRIOR" end
	function UnitName() return "Grom", "Hellscream" end
	function UnitFactionGroup() return "Horde" end
	function UnitLevel() return 10 end
	function GetRealmName() return realm end
	function GetNormalizedRealmName() return (string.gsub(realm, "[%s%-]", "")) end
	C_AutoComplete = { GetAutoCompleteRealms = function() return { (string.gsub(realm, "[%s%-]", "")) } end }
	C_GameRules = { GetCurrentGameModeRecordID = function() return mode end }
	C_Timer = { NewTicker = function() end }
	handlers.PLAYER_LOGIN()
	local keys = ns.Prices.markets(ns.market("horde"), interface)
	return ns.market("horde"), keys and table.concat(keys, " ")
end

local FOREVER, RETAIL = 16001, 120105

-- Forever with no realm name: the game mode is the market's realm part, in the word the ruleset reads.
local market, keys = client(FOREVER, "", 15)
eq(market, "EU-PvE-horde", "Forever, no realm name, mode 15: PvE")
eq(keys, "forever-EU-normal-horde", "PvE reads as the normal pool")
market, keys = client(FOREVER, "", 14)
eq(market, "EU-PvP-horde", "Forever, no realm name, mode 14: PvP")
eq(keys, "forever-EU-pvp-horde", "PvP reads as the pvp pool")
market, keys = client(FOREVER, "", 16)
eq(market, "EU-RP-horde", "Forever, no realm name, mode 16: RP")
eq(keys, "forever-EU-rp-horde", "RP reads as the rp pool")
market, keys = client(FOREVER, "", 18)
eq(market, "EU-RP PvP-horde", "Forever, no realm name, mode 18: RP PvP, no '-' inside the word")
eq(keys, "forever-EU-rppvp-horde", "RP PvP reads as the rppvp pool")

-- A mode the addon does not know, or none, keeps the empty realm: no prices, as before.
market, keys = client(FOREVER, "", 99)
eq(market, "EU--horde", "an unknown mode: the empty realm")
eq(keys, nil, "and no pool")
market, keys = client(FOREVER, "", nil)
eq(market, "EU--horde", "no mode: the empty realm")
eq(keys, nil, "and no pool")
C_GameRules = nil
eq(ns.market("horde"), "EU--horde", "no C_GameRules at all")

-- A realm with a name keeps it, whatever the mode.
market, keys = client(FOREVER, "Classic Beta PvP 1", 15)
eq(market, "EU-Classic Beta PvP 1-horde", "Forever with a realm name: the name")
eq(keys, "forever-EU-pvp-horde", "its pool from the name")
market, keys = client(RETAIL, "Argent Dawn", 15)
eq(market, "EU-ArgentDawn-horde", "retail: the connected group")
eq(keys, "retail-EU-ArgentDawn retail-EU", "retail's keys")

return checks()
