-- KnowledgeTrainers.lua: a trainer visit records where the trainer stands and the visitor's side.

function GetNumTrainerServices() return services end
function GetTrainerServiceInfo() return "Bolt of Linen Cloth", "available", 1 end
function UnitGUID() return "Creature-0-1-2-3-8661-0000000000" end
function UnitClass() return "Priest", "PRIEST" end
local faction = "Horde"
function UnitFactionGroup(unit) return unit == "player" and faction or nil end

local position = { 1429, 412, 679 }
local save = { catalogue = { trainers = {} } }
local handlers = {}
local ns = {
	on = function(event, _, fn) handlers[event] = fn end,
	after = function(_, _, fn) fn() end,
	throttle = function(_, _, fn) return fn end,
	db = function() return save end,
	readable = function(v) return v end,
	position = function() return unpack(position, 1, 3) end,
}
unpack = unpack or table.unpack
loadEncode(ns)
assert(load(SOURCES["KnowledgeTrainers.lua"], "@KnowledgeTrainers.lua"))("GoldForever", ns)

local function visit(count)
	services = count or 1
	handlers.TRAINER_SHOW()
end

save.catalogue.trainers[99] = "Old,available,1,,,,"
visit()
eq(save.catalogue.trainerPlaces[8661], "1429,412,679,H", "a Horde visit records the place and side H")
eq(save.catalogue.trainerPlaces[99], nil, "a trainer from an old save keeps no place")
eq(save.catalogue.trainers[99], "Old,available,1,,,,", "and keeps its list")

faction = "Alliance"
visit()
eq(save.catalogue.trainerPlaces[8661], "1429,412,679,A", "an Alliance visit records side A")

position = { 125 }
visit()
eq(save.catalogue.trainerPlaces[8661], "125,,,A", "in an instance: the map, no coordinates")

position = {}
visit()
eq(save.catalogue.trainerPlaces[8661], "125,,,A", "no map known: the place already stored stays")

position = { 1429, 1, 2 }
visit(0)
eq(save.catalogue.trainerPlaces[8661], "125,,,A", "an empty read stores no place, as it stores no list")

return checks()
