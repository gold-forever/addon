-- Gold Forever: the save's streams and their columns (design 002, schema v1), and ns.record, the one way
-- a collector appends a row to a stream.

local _, ns = ...
local Encode = ns.Encode

-- The save's schema: raised by one with each migration (Migrations.lua).
ns.SCHEMA = 5

-- Column dictionary: every stream and catalogue entry the save holds, by the file that records it, in
-- the order the TOCs load them.
ns.FIELDS = {
	sys = "t,char,kind",
	-- Catalogue.lua. minLevel and equipLoc are appended to design 002's columns. Retail appends tier, an
	-- item's crafting-quality tier (1–5), empty and left off the row's end for an untiered item; Forever
	-- has no tiers and declares no column.
	item = "name,quality,ilvl,class,subclass,stack,sell,bind,icon,minLevel,equipLoc" .. (ns.retail and ",tier" or ""),
	-- Loot.lua. fish is appended to design 002's columns: set when the loot is a fishing catch.
	loot = "t,char,map,x,y,src,first,coin,items,fish",
	pos = "t,char,map,x,y",
	-- Professions.lua. name is appended to design 002's columns: it lets the web app show recipes whose
	-- output is not an item (enchants).
	recipe = "skillLine,output,min,max,reagents,name",
	skill = "t,char,line,skill,max,spell,src,map",
	-- Market.lua. left: the auctions' time-left band (Enum.AuctionHouseTimeLeftBand: 0 under 30 minutes,
	-- 1 under 2 hours, 2 under 12 hours, 3 longer), so a listing that vanishes can be told sold from expired
	-- (data gap D1). Rows are grouped by item, unit price and band; empty on a client without the call.
	-- GetReplicateItemTimeLeft answers 1–4 (the owner's retail scan, 2026-10-23: 1, 2, 3 and 4, never 0), so
	-- the band is its answer less one; anything else is left empty. A scan written this way says so with
	-- `bands = 0` (the band numbering starts at 0); scans before it wrote the raw 1–4.
	scan = "item,unit,qty,auctions,left",
	-- Retail only: each distinct item a scan names, for telling commodities from gear (Encode.itemRow).
	scanItem = "item,class,subclass,stack",
	-- qty is appended to design 002's columns: buy is the price of one purchase of qty items.
	vendor = "buy,limited,t,qty",
	merchant = "map,x,y,items",
	-- Trade.lua.
	merchantTrade = "t,char,kind,item,qty,price,map",
	-- Ledger.lua.
	craft = "t,char,recipe,item,qty,skill,map",
	money = "t,char,delta,ctx",
	-- items: a turn-in's reward items, the fixed ones and the one chosen (Encode.items), as the reward window
	-- showed them; empty for an accept, a quest turned in without the window, and rows written before it.
	quest = "t,char,quest,kind,xp,money,map,items",
	questName = "name",
	flight = "t,char,from,to,cost,map",
	taxiNode = "name",
	-- Mail.lua: mail sent to one of your own characters, never anyone else's. to: the recipient's ref;
	-- items as Encode.items; money and cod in copper, empty for none.
	mail = "t,char,to,items,money,cod",
	-- Knowledge.lua.
	npc = "name,minLevel,maxLevel,classification,type",
	object = "name",
	map = "name,type,parent",
	-- On Forever GetTrainerServiceInfo returns name, category, icon; the columns follow that order.
	trainerService = "name,category,icon,cost,skill,skillRank,level",
	-- Character.lua.
	currency = "name",
	faction = "name",
	-- Legacy.lua.
	legacyPerk = "name,maxRank,spell,description,tree,x,y",
	legacyReward = "level,item,name,description",
	-- Achievements.lua.
	achievement = "name,points,category,icon,description,reward",
	statistic = "name,category",
	-- Rares.lua.
	rare = "t,char,npc,map,x,y,how",
	-- Auctions.lua.
	-- deposit: what the client took for the post, in copper; empty where it cannot tell it (Forever) and in
	-- rows written before it. The money row it moves is kept as before (ctx "auction").
	post = "t,char,item,qty,unit,duration,commodity,deposit",
	sale = "t,char,item,qty,price,deposit,cut",
	-- price: the total paid in copper; commodity: 1 for a commodity, empty for an item.
	ahBuy = "t,char,item,qty,price,commodity",
	-- unit: the price asked per unit, when known (a cancel knows it; an expiry mail does not).
	auctionEnd = "t,char,item,qty,unit,outcome",
	-- Levelling.lua.
	level = "t,char,kind,level,played,levelPlayed,money,map,x,y",
	-- mob: the name of the mob a kill's XP came from, as its combat XP message told it (Encode.text);
	-- empty for XP that is no kill's, a kill the client kept secret, and rows written before it.
	xp = "t,char,xp,kind,rested,instance,map,level,x,y,mob",
	zone = "t,char,map,instance,instanceId",
	boss = "t,char,encounter,name,difficulty,size,success,map,instanceId",
	instance = "name,type",
	-- Reputation.lua. delta: the gain, or a loss below 0; standing: the faction's standing after it, empty
	-- where it is not known (a renown faction's, which the client keeps at its base).
	rep = "t,char,faction,delta,standing,map",
}

-- A declaration's column names in order and by name, read once.
local layouts = {}
local function layout(declared)
	local known = layouts[declared]
	if not known then
		known = { names = {}, index = Encode.columns(declared) }
		for name, i in pairs(known.index) do
			known.names[i] = name
		end
		layouts[declared] = known
	end
	return known
end

-- Appends a row, its values by column name, to today's bucket of a stream; a column left out is empty.
-- A stream or column the schema does not have is recorded as an error (ns.fail) and nothing is written.
function ns.record(stream, row)
	local declared = ns.FIELDS[stream]
	if not declared then
		ns.fail("record", "no stream " .. tostring(stream) .. " in the schema")
		return
	end
	local columns = layout(declared)
	for name in pairs(row) do
		if not columns.index[name] then
			ns.fail("record", stream .. " has no column " .. tostring(name) .. " in the schema")
			return
		end
	end
	local values = {}
	for i, name in ipairs(columns.names) do
		values[i] = row[name]
	end
	ns.append(stream, Encode.row(unpack(values, 1, #columns.names)))
end
