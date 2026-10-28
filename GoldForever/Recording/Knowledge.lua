-- Gold Forever: game knowledge that exists nowhere else once WoW: Forever is gone — names and
-- levels of NPCs and objects the player meets, and zone maps. What trainers teach and the client's
-- API: KnowledgeTrainers.lua and KnowledgeClient.lua. Catalogue only: never anything about other players.

local _, ns = ...
local Encode = ns.Encode

-- NPCs -------------------------------------------------------------------------------------------

local levels = {} -- npc ID -> { min, max } seen this session, to widen the level range

-- A name worth keeping: readable (newer clients keep a restricted unit's name secret), not empty,
-- and not the client's "Unknown" for a name it has not loaded yet. nil otherwise: such a name is
-- never written, so a later real one fills the row (the server reads "" and "Unknown" as no name).
local function realName(v)
	v = ns.readable(v)
	if type(v) ~= "string" or v == "" or v == "?" or v == "Unknown" or v == UNKNOWNOBJECT or v == UNKNOWN then
		return nil
	end
	return v
end

-- A stored row's fields: name, minLevel, maxLevel, classification, type.
local function fields(row)
	local out = {}
	for v in string.gmatch((row or "") .. ",", "([^,]*),") do
		out[#out + 1] = v
	end
	return out
end

-- Units met while their identity was secret (in combat on newer clients): looked at again out of
-- combat, when the client shows them.
local missed = false
local seeAgain
local function miss()
	missed = true
	if ns.inCombat() then
		ns.afterCombat("npcs", seeAgain)
	end
end

local function seeUnit(unit)
	if not UnitExists(unit) or UnitIsPlayer(unit) then
		return
	end
	local id = Encode.npcId(ns.readable(UnitGUID(unit)))
	if not id then
		if ns.secret(UnitGUID(unit)) then
			miss()
		end
		return
	end
	local npcs = ns.db().catalogue.npcs
	local stored = npcs[id] and fields(npcs[id])
	local named = stored and realName(stored[1]) and stored[1] -- already encoded
	local name = realName(UnitName(unit))
	if not name then
		miss()
	end
	local level = ns.readable(UnitLevel(unit))
	if type(level) ~= "number" or level <= 0 then
		-- "??": too far above the player to show; the range stays as it was. A row without a name
		-- still takes one.
		if stored and not named and name then
			stored[1] = Encode.name(name)
			npcs[id] = table.concat(stored, ",")
		end
		return
	end
	local range = levels[id]
	if not range and stored then
		range = { tonumber(stored[2]), tonumber(stored[3]) }
	end
	if range and range[1] and range[2] and level >= range[1] and level <= range[2] and (named or not name) then
		levels[id] = range
		return
	end
	range = range or {}
	range[1] = math.min(range[1] or level, level)
	range[2] = math.max(range[2] or level, level)
	levels[id] = range
	local kind = ns.readable(UnitCreatureType(unit))
	local classification = ns.readable(UnitClassification(unit))
	npcs[id] = Encode.row(name and Encode.name(name) or named or "", range[1], range[2],
		classification or (stored and stored[4]) or nil, kind and Encode.name(kind) or (stored and stored[5]) or nil)
end

ns.on("PLAYER_TARGET_CHANGED", "npcs", function()
	seeUnit("target")
end)
ns.on("UPDATE_MOUSEOVER_UNIT", "npcs", function()
	seeUnit("mouseover")
end)
ns.on("NAME_PLATE_UNIT_ADDED", "npcs", seeUnit)
for _, event in ipairs({ "GOSSIP_SHOW", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE", "MERCHANT_SHOW",
	"TRAINER_SHOW", "PLAYER_INTERACTION_MANAGER_FRAME_SHOW" }) do
	ns.on(event, "npcs", function()
		seeUnit("npc")
	end)
end

-- Out of combat, and at a corpse's loot window, the units around are looked at again when one was
-- met unreadable: what combat hid is shown now.
function seeAgain()
	if not missed then
		return
	end
	missed = false
	for _, unit in ipairs({ "target", "focus", "mouseover" }) do
		seeUnit(unit)
	end
	for i = 1, 40 do
		seeUnit("nameplate" .. i)
	end
end
ns.on("LOOT_READY", "npcs", seeAgain)

-- A mob looted in a fight was secret on every unit while it lasted, and once it ends its corpse is
-- seldom one; the loot window gave its GUID, and the client's unit tooltip for it names the mob.
local unnamed = {} -- npc ID -> a GUID looted from it, until a readable name is found

local function nameLooted()
	local npcs = ns.db().catalogue.npcs
	for id, guid in pairs(unnamed) do
		local data = C_TooltipInfo.GetHyperlink("unit:" .. guid)
		local name = data and data.lines and data.lines[1] and realName(data.lines[1].leftText)
		if name then
			unnamed[id] = nil
			local stored = fields(npcs[id])
			npcs[id] = Encode.row(Encode.name(name), stored[2], stored[3], stored[4], stored[5])
		end
	end
end

table.insert(ns.lootListeners, function(_, _, rows)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
		return -- a client without unit tooltips by GUID
	end
	local npcs = ns.db().catalogue.npcs
	for _, row in ipairs(rows) do
		local id = Encode.npcId(row.guid)
		if id and not realName(fields(npcs[id])[1]) then
			unnamed[id] = row.guid
		end
	end
	if next(unnamed) then
		ns.afterCombat("npc names", nameLooted)
	end
end)

-- Objects: a gathering or opening cast names its target; the loot window that follows gives the
-- object's ID.
local cast -- { name, at }

-- A cast on a unit (a buff on oneself or a friend, a spell on a mob) names no object: it is never
-- kept, so no player's name can end up as an object's (design 002: no other players' names).
local function onUnit(target)
	for _, unit in ipairs({ "player", "target", "mouseover", "focus" }) do
		if UnitExists(unit) and ns.readable(UnitName(unit)) == target then
			return true
		end
	end
	return false
end

ns.on("UNIT_SPELLCAST_SENT", "objects", function(unit, target)
	if unit ~= "player" then
		return
	end
	-- Every cast replaces the last, so an older cast never names the next loot.
	target = realName(target)
	cast = target and not onUnit(target) and { name = target, at = GetTime() } or nil
end, "player")
ns.on("LOOT_READY", "objects", function()
	local id = ns.lootSource and string.match(ns.lootSource, "^o(%d+)$")
	if id and cast and GetTime() - cast.at < 10 then
		ns.db().catalogue.objects[tonumber(id)] = Encode.name(cast.name)
	end
	cast = nil
end)

-- Objects by tooltip: mousing over a herb, vein, chest or fishing pool shows a tooltip whose
-- data carries the object's GUID on newer clients.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	-- A mob's tooltip names it too: a catalogued mob still without a name takes the name it shows.
	local function objectTooltip(_, data)
		-- The GUID and the first line are secret for a unit whose identity the client keeps.
		local guid = data and ns.readable(data.guid)
		local src = guid and type(guid) == "string" and Encode.source(guid)
		local kind, id
		if src then
			kind, id = string.match(src, "^([on])(%d+)$")
		end
		local line = id and data.lines and data.lines[1] and realName(data.lines[1].leftText)
		if not (line and ns.db()) then
			return
		end
		id = tonumber(id)
		local catalogue = ns.db().catalogue
		if kind == "o" then
			catalogue.objects[id] = Encode.name(line)
		elseif catalogue.npcs[id] then
			local stored = fields(catalogue.npcs[id])
			if not realName(stored[1]) then
				stored[1] = Encode.name(line)
				catalogue.npcs[id] = table.concat(stored, ",")
			end
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(_, data)
		ns.safely("objects", objectTooltip, _, data)
	end)
end

-- Maps -------------------------------------------------------------------------------------------

local function seeMap()
	local maps = ns.db().catalogue.maps
	local map = C_Map.GetBestMapForUnit("player")
	while map and map ~= 0 and not maps[map] do
		local info = C_Map.GetMapInfo(map)
		if not info then
			return
		end
		maps[map] = Encode.row(Encode.name(info.name or "?"), info.mapType, info.parentMapID)
		map = info.parentMapID
	end
end

for _, event in ipairs({ "ZONE_CHANGED", "ZONE_CHANGED_INDOORS", "ZONE_CHANGED_NEW_AREA" }) do
	ns.on(event, "maps", seeMap)
end

-- Map art: which texture files draw each map, and how they tile. The web app draws routes over
-- the zone's own map, cut from the player's installed client by tools/maps (never from the web).
-- Read once per client build, every map with art, a batch a frame-step so the login does not stall.
-- db.mapArt = { build, maps = { [uiMapID] = "layerWidth,layerHeight,tileWidth,tileHeight;id+id+…" },
--   rects = { [uiMapID] = "continentID,left,right,top,bottom" } }: where each map lies on its
--   continent (0–1), so the web app can tile zones together into one map.
local MAP_IDS = 3000 -- uiMapIDs searched; Classic's are well under it
local MAP_BATCH = 100

local function readMapArt(manual)
	local db = ns.db()
	local build = db.client and db.client.build
	if not manual and (ns.lean or (db.mapArt and db.mapArt.build == build and db.mapArt.rects)) then
		return
	end
	if not (C_Map and C_Map.GetMapArtLayers and C_Map.GetMapArtLayerTextures and C_Map.GetMapInfo) then
		return
	end
	local maps, rects = {}, {}
	local id = 0
	local CONTINENT = Enum and Enum.UIMapType and Enum.UIMapType.Continent or 2
	local function continentOf(map)
		for _ = 1, 10 do
			local info = C_Map.GetMapInfo(map)
			if not info then
				return nil
			end
			if info.mapType == CONTINENT then
				return map
			end
			map = info.parentMapID
		end
	end
	local function step()
		local last = math.min(MAP_IDS, id + MAP_BATCH)
		for map = id + 1, last do
			local layers = C_Map.GetMapInfo(map) and C_Map.GetMapArtLayers(map)
			local layer = layers and layers[1]
			local textures = layer and C_Map.GetMapArtLayerTextures(map, 1)
			if textures and #textures > 0 then
				maps[map] = string.format("%d,%d,%d,%d;%s", layer.layerWidth, layer.layerHeight, layer.tileWidth, layer.tileHeight,
					table.concat(textures, "+"))
				local continent = C_Map.GetMapRectOnMap and continentOf(map)
				if continent and continent ~= map then
					local left, right, top, bottom = C_Map.GetMapRectOnMap(map, continent)
					if left and right and right > left then
						rects[map] = string.format("%d,%.5f,%.5f,%.5f,%.5f", continent, left, right, top, bottom)
					end
				end
			end
		end
		id = last
		if id < MAP_IDS then
			ns.after(0.05, "map art", step)
		else
			db.mapArt = { build = build, t = ns.now(), maps = maps, rects = rects }
			if manual then
				local n = 0
				for _ in pairs(maps) do
					n = n + 1
				end
				ns.say(string.format("map art of %d maps recorded; /reload to write it.", n))
			end
		end
	end
	step()
end

ns.commands.maps = function()
	readMapArt(true)
end

ns.module("Knowledge", {
	requires = { "Store" },
	enable = function()
		ns.after(10, "map art", readMapArt)
	end,
	-- The map is seen on every zone change, a loading screen's too.
	world = function()
		ns.safely("maps", seeMap)
	end,
})
