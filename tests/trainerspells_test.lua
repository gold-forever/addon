-- KnowledgeTrainers.lua: a trainer's service records the spell it teaches (schema 11, gf#384), read from a
-- hidden tooltip of the addon's own; empty where the client cannot tell it.

unpack = unpack or table.unpack
local SPELLS = { 2050, nil, 585 }
local NAMES = { "Lesser Heal", "Generic", "Smite" }
function GetNumTrainerServices() return #NAMES end
function GetTrainerServiceInfo(i) return NAMES[i], "available", 135924 end
function GetTrainerServiceLevelReq() return 4 end
function GetTrainerServiceCost() return 100 end
function UnitGUID() return "Creature-0-1-2-3-8661-0000000000" end
function UnitClass() return "Priest", "PRIEST" end
function UnitFactionGroup() return "Alliance" end

local tips = 0
local function tooltip()
	local tip = { service = nil }
	function tip:SetOwner() self.service = nil end
	function tip:SetTrainerService(i) self.service = i end
	-- The client's answer is the spell's name and ID; nothing for a service that teaches no spell.
	function tip:GetSpell()
		local id = self.service and SPELLS[self.service]
		if id then return NAMES[self.service], id end
	end
	return tip
end
function CreateFrame(kind)
	assert(kind == "GameTooltip", "a tooltip of the addon's own")
	tips = tips + 1
	return tooltip()
end

local save = { catalogue = { trainers = {} } }
local handlers = {}
local ns = {
	on = function(event, _, fn) handlers[event] = fn end,
	after = function(_, _, fn) fn() end,
	throttle = function(_, _, fn) return fn end,
	db = function() return save end,
	readable = function(v) return v end,
	position = function() return 1429, 412, 679 end,
}
loadEncode(ns)
assert(load(SOURCES["KnowledgeTrainers.lua"], "@KnowledgeTrainers.lua"))("GoldForever", ns)

handlers.TRAINER_SHOW()
eq(save.catalogue.trainers[8661], "Lesser Heal,available,135924,100,,,4,2050;Generic,available,135924,100,,,4,;Smite,available,135924,100,,,4,585",
	"each service ends in the spell it teaches, empty for one the tooltip names no spell for")
handlers.TRAINER_SHOW()
eq(tips, 1, "one tooltip, made once")

-- A client whose tooltip cannot show a trainer's service: the column stays empty.
save.catalogue.trainers[8661] = nil
tips = 0
CreateFrame = function()
	tips = tips + 1
	return { SetOwner = function() end }
end
assert(load(SOURCES["KnowledgeTrainers.lua"], "@KnowledgeTrainers.lua"))("GoldForever", ns)
handlers.TRAINER_SHOW()
eq(save.catalogue.trainers[8661], "Lesser Heal,available,135924,100,,,4,;Generic,available,135924,100,,,4,;Smite,available,135924,100,,,4,",
	"no SetTrainerService: every spell empty, the rest as before")

-- A tooltip that raises on a trainer's service: the column stays empty and the list is kept.
save.catalogue.trainers[8661] = nil
CreateFrame = function()
	return { SetOwner = function() end, SetTrainerService = function() error("not a trainer service") end, GetSpell = function() end }
end
assert(load(SOURCES["KnowledgeTrainers.lua"], "@KnowledgeTrainers.lua"))("GoldForever", ns)
handlers.TRAINER_SHOW()
eq(save.catalogue.trainers[8661], "Lesser Heal,available,135924,100,,,4,;Generic,available,135924,100,,,4,;Smite,available,135924,100,,,4,",
	"SetTrainerService raising: every spell empty, the list still recorded")

return checks()
