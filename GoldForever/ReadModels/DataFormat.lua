-- Gold Forever: the shape of the price data file, the twin of the companion's internal/addondata/format.go.
-- The companion writes Interface/AddOns/GoldForever_Data/ (an optional dependency): Data.lua sets one global,
-- GoldForever_Prices, and nothing else. Its readers (Prices, Dings, Lists, the auction panel) index it by
-- the names below, never by literal strings; the smoke run fails on a field read that is not listed here.
--
-- What the addon does with a file it was not written for (today's behaviour, tested in prices_test.lua and
-- dings_test.lua):
--   * prices are read only from a file whose v is VERSION: any other, newer or older, shows no prices;
--     /gf prices says which version the file is and which this addon reads, and the Companion page calls
--     it a newer version and asks for the addon to be updated, whichever way it differs;
--   * the shared lists and profiles and the dings switch are read whatever v says;
--   * a field the addon does not know is ignored, as is an item figure past the fifth; a known field of
--     another type is taken as absent.

local _, ns = ...

local DataFormat = {}
ns.DataFormat = DataFormat

-- Data.lua's v. It changes when an addon reading the file as it is would misread it: a field removed,
-- renamed or given another type, or the item figures reordered. A new optional field does not.
DataFormat.VERSION = 1

-- The addon the companion writes, and the one global its Data.lua sets.
DataFormat.ADDON = "GoldForever_Data"
DataFormat.GLOBAL = "GoldForever_Prices"

-- The fields of Data.lua's tables, as the addon reads them.
local F = {
	version = "v",
	at = "at",
	shared = "shared",
	lists = "lists",
	profiles = "profiles",
	id = "id",
	edited = "edited",
	string = "string",
	dings = "dings",
	webhook = "webhook",
	characters = "characters",
	markets = "markets",
}
DataFormat.field = F

-- An item's figures in markets[<market key>][<item id>], by place: integers, week optional.
DataFormat.item = { value = 1, minBuyout = 2, players = 3, scannedAt = 4, week = 5 }

-- Each table and its fields' types. Times are epoch seconds; every number is an integer; keys and strings
-- are quoted printable ASCII.
DataFormat.tables = {
	prices = {
		[F.version] = "integer",
		[F.at] = "integer: when the server built the prices",
		[F.shared] = "shared, optional: the account's shared lists and sale profiles",
		[F.dings] = "dings, optional: the site's side of the dings switch",
		[F.markets] = "{ [market key] = { [item id] = item } }",
	},
	shared = {
		[F.at] = "integer: when the set last changed",
		[F.lists] = "{ entry, ... }",
		[F.profiles] = "{ entry, ... }",
	},
	entry = {
		[F.id] = "string",
		[F.edited] = "integer",
		[F.string] = "string",
	},
	dings = {
		[F.at] = "integer: when it last changed",
		[F.webhook] = "boolean: whether a level-up webhook is connected",
		[F.characters] = "{ [guid] = boolean }",
	},
}
