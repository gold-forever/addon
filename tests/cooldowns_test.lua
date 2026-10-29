-- Cooldowns.lua: when each cooldown recipe of yours is ready again, per character and recipe in server time,
-- read while your profession window is open and a moment after a craft, never in combat. A recipe without a
-- cooldown records nothing.

local clock, server = 1000, 1792517535
function GetTime() return clock end

-- The profession window: Alchemy, its recipes, and the seconds each is still on cooldown.
local TRANSMUTE, MOONCLOTH, POTION, UNLEARNED = 17187, 18560, 2330, 17559
local learned = { [TRANSMUTE] = true, [MOONCLOTH] = true, [POTION] = true }
local left = { [TRANSMUTE] = 7200.4 }
local linked = false
C_TradeSkillUI = {
	GetAllRecipeIDs = function() return { TRANSMUTE, MOONCLOTH, POTION, UNLEARNED } end,
	GetRecipeInfo = function(id) return { name = "r" .. id, learned = learned[id] } end,
	GetRecipeSchematic = function() return nil end,
	GetBaseProfessionInfo = function() return { professionID = 171, professionName = "Alchemy" } end,
	IsTradeSkillLinked = function() return linked end,
	GetRecipeCooldown = function(id) return left[id] end,
}

local me = { ref = 1, prof = {} }
local save = { characters = { ["Player-1-a"] = me }, catalogue = { recipes = { [TRANSMUTE] = "171,", [MOONCLOTH] = "197," } } }
local handlers, heard, later = {}, {}, {}
local fighting = false
local ns = {
	on = function(event, _, fn)
		handlers[event] = handlers[event] or {}
		table.insert(handlers[event], fn)
	end,
	listen = function(event, _, fn)
		heard[event] = heard[event] or {}
		table.insert(heard[event], fn)
	end,
	emit = function(event, ...)
		for _, fn in ipairs(heard[event] or {}) do
			fn(...)
		end
	end,
	throttle = function(_, _, fn) return fn end,
	after = function(_, _, fn) later[#later + 1] = fn end,
	afterCombat = function(_, fn)
		if fighting then
			later[#later + 1] = fn
		else
			fn()
		end
	end,
	module = function() end,
	commands = {},
	safely = function(_, fn, ...) return fn(...) end,
	me = function() return me end,
	db = function() return save end,
	now = function() return server end,
	catalogueItem = function() end,
}
local function fire(event, ...)
	for _, fn in ipairs(handlers[event] or {}) do
		fn(...)
	end
end
local function wait()
	local due = later
	later = {}
	for _, fn in ipairs(due) do
		fn()
	end
end
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Professions.lua"], "@Professions.lua"))("GoldForever", ns)
assert(load(SOURCES["Cooldowns.lua"], "@Cooldowns.lua"))("GoldForever", ns)

local function cooldowns()
	local ids = {}
	for id in pairs(me.cooldowns or {}) do
		ids[#ids + 1] = id
	end
	table.sort(ids)
	for i, id in ipairs(ids) do
		ids[i] = id .. "@" .. me.cooldowns[id]
	end
	return table.concat(ids, " ")
end

-- The window opens: the transmute on cooldown is ready in 2 h (rounded up to the second); the potion has no
-- cooldown and Mooncloth's is over, so neither is recorded.
fire("TRADE_SKILL_SHOW")
eq(cooldowns(), TRANSMUTE .. "@" .. (server + 7201), "the transmute is ready again in two hours, in server time")

-- Someone else's profession window says nothing of yours.
linked, left[MOONCLOTH] = true, 345600
fire("TRADE_SKILL_LIST_UPDATE")
eq(cooldowns(), TRANSMUTE .. "@" .. (server + 7201), "a linked window records nothing")
linked, left[MOONCLOTH] = false, nil

-- A craft of Mooncloth: read a moment later, as the client starts the cooldown after the cast.
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", MOONCLOTH)
left[MOONCLOTH] = 345600
eq(cooldowns(), TRANSMUTE .. "@" .. (server + 7201), "nothing at the cast itself")
wait()
eq(cooldowns(), TRANSMUTE .. "@" .. (server + 7201) .. " " .. MOONCLOTH .. "@" .. (server + 345600), "Mooncloth is ready again in four days")

-- A spell that is no recipe, or someone else's cast, reads nothing.
left[133], left[MOONCLOTH] = 30, 30
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", 133)
fire("UNIT_SPELLCAST_SUCCEEDED", "party1", "cast", MOONCLOTH)
wait()
left[133], left[MOONCLOTH] = nil, 345600
eq(cooldowns(), TRANSMUTE .. "@" .. (server + 7201) .. " " .. MOONCLOTH .. "@" .. (server + 345600), "a spell that is no recipe, or another's cast, reads nothing")

-- In combat the craft's cooldown waits for the fight to end.
fighting = true
left[MOONCLOTH] = 345000
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "cast", MOONCLOTH)
wait()
eq(me.cooldowns[MOONCLOTH], server + 345600, "not read in combat")
fighting = false
wait()
eq(me.cooldowns[MOONCLOTH], server + 345000, "read once the fight ends")
left[MOONCLOTH] = 344000
fighting = true
fire("TRADE_SKILL_SHOW")
eq(me.cooldowns[MOONCLOTH], server + 345000, "the window is not read in combat either")
fighting = false
wait()
eq(me.cooldowns[MOONCLOTH], server + 344000, "but once the fight ends")

-- Already ready: a cooldown that ended earlier than recorded (a reset) is ready now; one recorded as over
-- stays as it was.
me.cooldowns[MOONCLOTH] = server - 50
left = {}
server = server + 60
fire("TRADE_SKILL_SHOW")
eq(cooldowns(), TRANSMUTE .. "@" .. server .. " " .. MOONCLOTH .. "@" .. (server - 110), "ready now; the one already over is kept")

-- A recipe with charges left can be cast now, whatever its next charge's wait.
C_TradeSkillUI.GetRecipeCooldown = function(id)
	if id == POTION then
		return 600, false, 1, 2
	end
end
fire("TRADE_SKILL_SHOW")
eq(me.cooldowns[POTION], nil, "a charge left is ready, and a recipe never on cooldown records nothing")

-- Without the recipe call: the recipe's spell cooldown, as start and duration in GetTime(); the global
-- cooldown after any cast is none.
C_TradeSkillUI.GetRecipeCooldown = nil
local spells = { [MOONCLOTH] = { startTime = 900, duration = 345600, isEnabled = true }, [POTION] = { startTime = 999, duration = 1.5, isEnabled = true } }
C_Spell = { GetSpellCooldown = function(id) return spells[id] end }
fire("TRADE_SKILL_SHOW")
eq(me.cooldowns[MOONCLOTH], server + 345500, "the spell's cooldown: 100 s of it gone")
eq(me.cooldowns[POTION], nil, "the global cooldown is none")

-- Nor that: the classic global.
C_Spell = nil
function GetSpellCooldown(id)
	if id == TRANSMUTE then
		return 1000, 3600, 1
	end
	return 0, 0, 1
end
fire("TRADE_SKILL_SHOW")
eq(me.cooldowns[TRANSMUTE], server + 3600, "the classic spell cooldown")

-- No call at all: nothing is read, and what was recorded stays.
GetSpellCooldown = nil
local before = cooldowns()
fire("TRADE_SKILL_SHOW")
eq(cooldowns(), before, "a client that cannot tell leaves the record as it was")

return checks()
