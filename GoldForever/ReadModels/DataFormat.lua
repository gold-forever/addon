-- Gold Forever: the shape of the price data file, the twin of the companion's internal/addondata/format.go.
-- The companion writes Interface/AddOns/GoldForever_Data/ (an optional dependency): Data.lua sets one global,
-- GoldForever_Prices, and nothing else. Its readers (Prices, Lists, the auction panel) index it by
-- the names below, never by literal strings; the smoke run fails on a field read that is not listed here.
--
-- What the addon does with a file it was not written for (today's behaviour, tested in prices_test.lua):
--   * prices are read only from a file whose v is VERSION: any other, newer or older, shows no prices;
--     /gf prices says which version the file is and which this addon reads, and the Companion page calls
--     it a newer version and asks for the addon to be updated, whichever way it differs;
--   * the shared lists and profiles are read whatever v says;
--   * a field the addon does not know is ignored, as is an item figure past the fifth; a known field of
--     another type is taken as absent.

local _, ns = ...

local DataFormat = {}
ns.DataFormat = DataFormat

-- Data.lua's v. It changes when an addon reading the file as it is would misread it: a field removed,
-- renamed or given another type, or the item figures reordered. A new optional field does not, nor does
-- dropping one the addon reads as absent: dings was dropped at v = 1, and a file that still has it is read
-- as any other, that field ignored.
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
	markets = "markets",
	units = "units",
}
DataFormat.field = F

-- An item's figures in markets[<market key>][<item id>], by place: integers, week optional. Beside them,
-- keyed so that it never takes week's place, the item's fields (tables.item).
DataFormat.item = { value = 1, minBuyout = 2, players = 3, scannedAt = 4, week = 5 }

-- Each table and its fields' types. Times are epoch seconds; every number is an integer; keys and strings
-- are quoted printable ASCII.
DataFormat.tables = {
	prices = {
		[F.version] = "integer",
		[F.at] = "integer: when the server built the prices",
		[F.shared] = "shared, optional: the account's shared lists and sale profiles",
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
	item = {
		[F.units] = "integer, optional: the units on sale, there only for a thin price",
	},
}
