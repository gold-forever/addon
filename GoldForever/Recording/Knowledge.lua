-- Gold Forever: game knowledge that exists nowhere else once WoW: Forever is gone — names and
-- levels of NPCs and objects the player meets, and zone maps. What trainers teach and the client's
-- API: KnowledgeTrainers.lua and KnowledgeClient.lua. Catalogue only: never anything about other players.

local _, ns = ...
local Encode = ns.Encode

-- NPCs -------------------------------------------------------------------------------------------

local levels = {} -- npc ID -> { min, max } seen this session, to widen the level range

-- A name worth keeping: readable (newer clients keep a restricted unit's name secret) and naming
-- something (Encode.noName); nil otherwise.
local function realName(v)
	v = ns.readable(v)
	if type(v) ~= "string" or Encode.noName(v) then
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

-- A unit's classification and encoded type, the stored ones where the client does not tell them.
local function described(unit, stored)
	local classification = ns.readable(UnitClassification(unit))
	local kind = ns.readable(UnitCreatureType(unit))
	return classification or (stored and stored[4]) or nil, kind and Encode.name(kind) or (stored and stored[5]) or nil
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
		-- "??": too far above the player to show, or a boss; the range stays as it was, the rest is written.
		local classification, kind = described(unit, stored)
		if not (stored or name or classification or kind) then
			return
		end
		npcs[id] = Encode.row(name and Encode.name(name) or named or "", stored and stored[2], stored and stored[3],
			classification, kind)
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
	npcs[id] = Encode.row(name and Encode.name(name) or named or "", range[1], range[2], described(unit, stored))
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

-- A unit tooltip's level line as the client words it ("Level 80 Humanoid (Elite)", "Level ?? Boss"):
-- its level ("??" is none), classification and creature type, each nil where the lines do not tell.
local creatureTypes -- the client's creature type names, read once

local function escaped(text)
	return (string.gsub(text, "%p", "%%%0"))
end

local function wordedType(text)
	if not creatureTypes and C_CreatureInfo and C_CreatureInfo.GetCreatureTypeIDs then
		creatureTypes = {}
		for _, typeId in ipairs(C_CreatureInfo.GetCreatureTypeIDs() or {}) do
			local info = C_CreatureInfo.GetCreatureTypeInfo(typeId)
			creatureTypes[#creatureTypes + 1] = info and info.name
		end
	end
	for _, typeName in ipairs(creatureTypes or {}) do
		if string.find(text, typeName, 1, true) then
			return typeName
		end
	end
	return nil
end

local function wordedClassification(text)
	local function has(word)
		return word and string.find(text, word, 1, true)
	end
	if has(BOSS) then
		return "worldboss"
	elseif has(RARE) then
		return has(ELITE) and "rareelite" or "rare"
	end
	return has(ELITE) and "elite" or "normal"
end

-- A line without its colours (|cffRRGGBB, |cnNAME:, |r). A texture for the level (a boss's skull) has
-- no spaces, so it stays one word: no level.
local function plain(text)
	text = string.gsub(text, "|c%x%x%x%x%x%x%x%x", "")
	text = string.gsub(text, "|cn[^:|]*:", "")
	return (string.gsub(text, "|r", ""))
end

-- The words after the level that are neither a classification nor in brackets: the type as the line
-- names it, for a type the client's list lacks or a client giving none.
local function restType(rest)
	rest = string.gsub(rest, "%b()", " ")
	for _, word in pairs({ BOSS, RARE, ELITE }) do
		rest = string.gsub(" " .. rest .. " ", "%s" .. escaped(word) .. "%s", " ")
	end
	rest = string.match((string.gsub(rest, "%s+", " ")), "^%s*(.-)%s*$")
	return rest ~= "" and rest or nil
end

local function tooltipLevel(lines)
	local before, after = string.match(TOOLTIP_UNIT_LEVEL or "", "^(.-)%%s(.*)$")
	if not before then
		return nil
	end
	local pattern = "^" .. escaped(before) .. "(%S+)" .. escaped(after) .. "(.*)$"
	for i = 2, #(lines or {}) do
		local text = ns.readable(lines[i].leftText)
		text = text and plain(text)
		local token, rest = nil, nil
		if text then
			token, rest = string.match(text, pattern)
		end
		if token then
			local level = tonumber(token)
			return level and level > 0 and level or nil, wordedClassification(text), wordedType(text) or restType(rest)
		end
	end
	return nil
end

-- An NPC named from anywhere but its unit: the name fills its row, or makes one, unless it has a name.
-- A unit tooltip's lines widen its level range and fill a classification and type it lacks. The save
-- stops waiting for it (unnamed, below). Rares.lua names a rare seen only as a minimap marker.
local forget
function ns.nameNpc(id, name, lines)
	name = realName(name)
	if not name then
		return false
	end
	local npcs = ns.db().catalogue.npcs
	local stored = fields(npcs[id])
	local level, classification, kind = tooltipLevel(lines)
	local low, high = tonumber(stored[2]), tonumber(stored[3])
	if level then
		low, high = math.min(low or level, level), math.max(high or level, level)
		levels[id] = { low, high }
	end
	npcs[id] = Encode.row(realName(stored[1]) and stored[1] or Encode.name(name), low, high,
		(stored[4] or "") ~= "" and stored[4] or classification,
		(stored[5] or "") ~= "" and stored[5] or kind and Encode.name(kind))
	forget(id)
	return true
end

-- A mob looted in a fight was secret on every unit while it lasted, and once it ends its corpse is
-- seldom one; the loot window gave its GUID, and the client's unit tooltip for it names the mob. In an
-- instance that tooltip stays secret out of combat too, so the mob is named after it, at a loading
-- screen. Until named it waits in the save, db.unnamedNpcs: npc ID -> "GUID,sessions tried" (not in the
-- catalogue, which is uploaded), and is tried in up to SESSIONS sessions.
local SESSIONS = 10
local tried = {} -- npc ID -> true once its try is counted this session

function forget(id)
	local db = ns.db()
	if db.unnamedNpcs then
		db.unnamedNpcs[id] = nil
		if not next(db.unnamedNpcs) then
			db.unnamedNpcs = nil
		end
	end
end

local probe = {} -- the last values "/gf probe" reports (temporary, below)

local function nameLooted()
	local unnamed = ns.db().unnamedNpcs or {}
	for id, entry in pairs(unnamed) do
		local guid, sessions = string.match(entry, "^([^,]+),(%d+)$")
		local data = guid and C_TooltipInfo.GetHyperlink("unit:" .. guid)
		local lines = data and data.lines
		if not ns.nameNpc(id, lines and lines[1] and lines[1].leftText, lines) and not tried[id] then
			tried[id] = true
			sessions = (tonumber(sessions) or SESSIONS) + 1
			if sessions >= SESSIONS then
				forget(id)
			else
				unnamed[id] = guid .. "," .. sessions
			end
		end
	end
end

-- A client without unit tooltips by GUID names no looted mob.
local function retryLooted()
	if C_TooltipInfo and C_TooltipInfo.GetHyperlink and ns.db().unnamedNpcs then
		ns.afterCombat("npc names", nameLooted)
	end
end

table.insert(ns.lootListeners, function(_, _, rows)
	if not (C_TooltipInfo and C_TooltipInfo.GetHyperlink) then
		return
	end
	local db = ns.db()
	for _, row in ipairs(rows) do
		local id = Encode.npcId(row.guid)
		probe.looted = id and row.guid or probe.looted
		if id and not realName(fields(db.catalogue.npcs[id])[1]) and not (db.unnamedNpcs and db.unnamedNpcs[id]) then
			db.unnamedNpcs = db.unnamedNpcs or {}
			db.unnamedNpcs[id] = row.guid .. ",0"
		end
	end
	retryLooted()
end)

-- Objects: a gathering or opening cast names its target; the loot window that follows gives the
-- object's ID.
local cast -- { name, at }
-- An object's tooltip whose GUID was secret (in an instance), its first line readable: { name, at }.
local shown
local OBJECT = Enum and Enum.TooltipDataType and Enum.TooltipDataType.Object
local RECENT = 10 -- seconds from the cast or tooltip to the loot window

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
	probe.cast = target
	target = realName(target)
	cast = target and not onUnit(target) and { name = target, at = GetTime() } or nil
end, "player")
local function recent(seen)
	return seen and GetTime() - seen.at < RECENT and seen.name or nil
end

ns.on("LOOT_READY", "objects", function()
	local id = ns.lootSource and tonumber(string.match(ns.lootSource, "^o(%d+)$"))
	local objects = ns.db().catalogue.objects
	if id and recent(cast) then
		objects[id] = Encode.name(cast.name)
	elseif id and not objects[id] and recent(shown) then
		objects[id] = Encode.name(shown.name)
	end
	cast, shown = nil, nil
end)

-- Objects by tooltip: mousing over a herb, vein, chest or fishing pool shows a tooltip whose
-- data carries the object's GUID on newer clients.
if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and TooltipDataProcessor.AllTypes then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	-- A mob's tooltip names it too: a mob still without a name takes the name it shows, in a new row if need be.
	local function objectTooltip(_, data)
		-- The GUID and the first line are secret for a unit whose identity the client keeps.
		local guid = data and ns.readable(data.guid)
		local src = guid and type(guid) == "string" and Encode.source(guid)
		local kind, id
		if src then
			kind, id = string.match(src, "^([on])(%d+)$")
		end
		local shownType = data and ns.readable(data.type)
		if data and (shownType == nil or shownType == OBJECT) then
			probe.guid, probe.type, probe.line = data.guid, data.type, data.lines and data.lines[1] and data.lines[1].leftText
		end
		-- An object whose GUID is secret: its name, for the loot window that follows.
		local object = not id and OBJECT and shownType == OBJECT
		local line = (id or object) and data.lines and data.lines[1] and realName(data.lines[1].leftText)
		if not (line and ns.db()) then
			return
		end
		if object then
			shown = { name = line, at = GetTime() }
		elseif kind == "o" then
			ns.db().catalogue.objects[tonumber(id)] = Encode.name(line)
		else
			ns.nameNpc(tonumber(id), line, data.lines)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(TooltipDataProcessor.AllTypes, function(_, data)
		ns.safely("objects", objectTooltip, _, data)
	end)
end

-- Temporary, until instance loot is named in game: "/gf probe" says which of the values the naming
-- reads the client keeps secret or empty, here and now.
local function told(v)
	if ns.secret(v) then
		return "secret"
	end
	return (v == nil or v == "") and "empty" or tostring(v)
end

ns.commands.probe = function()
	local say = { "instance " .. told(IsInInstance and IsInInstance()) .. ", in combat " .. told(ns.inCombat()) }
	for _, unit in ipairs({ "target", "mouseover", "nameplate1" }) do
		say[#say + 1] = unit .. ": GUID " .. told(UnitGUID(unit)) .. ", name " .. told(UnitName(unit))
	end
	local hyperlink = probe.looted and C_TooltipInfo and C_TooltipInfo.GetHyperlink
	local data = hyperlink and C_TooltipInfo.GetHyperlink("unit:" .. probe.looted)
	local shown = {}
	for i, line in ipairs(data and data.lines or {}) do
		-- Markup escaped, so the chat frame shows a level line's colour codes rather than applying them.
		local text = told(line.leftText)
		shown[i] = (string.gsub(text, "|", "||"))
	end
	say[#say + 1] = "last looted mob " .. told(probe.looted) .. ": unit tooltip "
		.. (#shown > 0 and table.concat(shown, " / ") or "empty")
	say[#say + 1] = "last cast target " .. told(probe.cast)
	say[#say + 1] = "last object tooltip: GUID " .. told(probe.guid) .. ", type " .. told(probe.type) .. ", line " .. told(probe.line)
	for _, line in ipairs(say) do
		ns.say(line)
	end
end

-- Maps -------------------------------------------------------------------------------------------

local asked = {} -- map IDs rows recorded this session, looked up once each
local waiting = {} -- map IDs rows recorded in combat, looked up once it ends

local function catalogueMap(map)
	local maps = ns.db().catalogue.maps
	while map and map ~= 0 and not maps[map] do
		local info = C_Map.GetMapInfo(map)
		if not info then
			return
		end
		maps[map] = Encode.row(Encode.name(info.name or "?"), info.mapType, info.parentMapID)
		map = info.parentMapID
	end
end

local function catalogueWaiting()
	for map in pairs(waiting) do
		catalogueMap(map)
	end
	waiting = {}
end

local function seeMap()
	catalogueMap(C_Map.GetBestMapForUnit("player"))
end

-- A map a stream row records: a floor reached without a zone event is named too.
ns.listen("mapRecorded", "maps", function(map)
	if type(map) ~= "number" or asked[map] or ns.db().catalogue.maps[map] then
		return
	end
	asked[map] = true
	if ns.inCombat() then
		waiting[map] = true
		ns.afterCombat("maps", catalogueWaiting)
		return
	end
	catalogueMap(map)
end)

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
	-- The map is seen on every zone change, a loading screen's too. Leaving an instance is one: the mobs
	-- looted in it are named then.
	world = function()
		ns.safely("maps", seeMap)
		ns.safely("npc names", retryLooted)
	end,
})
