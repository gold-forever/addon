-- Gold Forever: the ids in the save (ns.Encode): item keys and IDs, and loot sources and NPC IDs from GUIDs.
-- Pure Lua 5.1 with no game API.

local _, ns = ...
ns = ns or {}
local Encode = ns.Encode

-- Item key of an item link or item string: "itemId", or "itemId:suffixId" for random-suffix
-- items. nil when the text is not an item.
function Encode.itemKey(link)
	local fields = link and string.match(link, "item:([%-%d:]+)")
	if not fields then
		return nil
	end
	local parts = {}
	for part in string.gmatch(fields .. ":", "([^:]*):") do
		parts[#parts + 1] = part
	end
	local id = tonumber(parts[1])
	if not id then
		return nil
	end
	local suffix = tonumber(parts[7] or "")
	if suffix and suffix ~= 0 then
		return id .. ":" .. suffix
	end
	return tostring(id)
end

-- The item ID of an item key ("2589", "10221:612"), or of an ID given as a number.
function Encode.itemId(key)
	return key and tonumber(string.match(tostring(key), "^(%d+)"))
end

-- Loot source of a unit or object GUID: "n<npcId>" or "o<objectId>"; nil for anything else.
-- Creature-0-<server>-<instance>-<zoneUID>-<npcId>-<spawnUID>, GameObject the same.
function Encode.source(guid)
	if not guid then
		return nil
	end
	local parts = {}
	for part in string.gmatch(guid, "[^%-]+") do
		parts[#parts + 1] = part
	end
	local prefix = (parts[1] == "Creature" or parts[1] == "Vehicle") and "n" or parts[1] == "GameObject" and "o" or nil
	local id = tonumber(parts[6] or "")
	if prefix and id then
		return prefix .. id
	end
	return nil
end

-- The NPC ID of a loot source ("n7440"); nil for an object, an item or "?".
function Encode.npcOf(src)
	return src and tonumber(string.match(src, "^n(%d+)$"))
end

-- The NPC ID behind a unit or spawn GUID; nil for players, objects and anything else.
function Encode.npcId(guid)
	return Encode.npcOf(Encode.source(guid))
end
