-- Spellbook.lua: a character's known class spells, by ID, from the spellbook's class tabs (gf#384), on both
-- the older spell-tab calls (Forever) and C_SpellBook (retail).

unpack = unpack or table.unpack
local me = { ref = 1 }
local handlers, module = {}, nil
local ns = {
	on = function(event, _, fn) handlers[event] = fn end,
	after = function(_, _, fn) fn() end,
	throttle = function(_, _, fn) return fn end,
	safely = function(_, fn, ...) return fn(...) end,
	module = function(_, m) module = m end,
	me = function() return me end,
}
assert(load(SOURCES["Spellbook.lua"], "@Spellbook.lua"))("GoldForever", ns)

-- The older calls: tab 1 General, tab 2 the class, tab 3 a guild tab, tab 4 an off-spec tab.
local tabs = {
	{ "General", 0, 0, 2 },
	{ "Holy", 0, 2, 4 },
	{ "Guild", 0, 6, 1, true },
	{ "Shadow", 0, 7, 1, false, 258 },
}
local book = {
	{ "SPELL", 6603 }, { "SPELL", 2382 }, -- General: Attack, Generic
	{ "SPELL", 2050 }, { "SPELL", 585 }, { "FUTURESPELL", 591 }, { "FLYOUT", 1 }, -- Holy
	{ "SPELL", 83958 }, -- Guild
	{ "SPELL", 589 }, -- off-spec
}
function GetNumSpellTabs() return #tabs end
function GetSpellTabInfo(tab) return unpack(tabs[tab]) end
function GetSpellBookItemInfo(slot, bank)
	assert(bank == "spell", "the player's spells")
	return unpack(book[slot])
end

module.world()
eq(me.spells, "585,2050", "the class tab's known spells, sorted: not General's, a future spell's, a flyout's, the guild's or an off-spec's")

book[5] = { "SPELL", 591 }
handlers.LEARNED_SPELL_IN_TAB(591, 2)
eq(me.spells, "585,591,2050", "a spell learned is read again")

me.spells = nil
handlers.TRAINER_CLOSED()
eq(me.spells, "585,591,2050", "the trainer closed is read again")

me.spells = "585"
GetNumSpellTabs = function() return 0 end
module.world()
eq(me.spells, "585", "a spellbook not loaded yet keeps what was read before")

-- C_SpellBook: skill line 1 General, 2 the class, 3 a spec line, 4 an off-spec line.
GetNumSpellTabs, GetSpellTabInfo, GetSpellBookItemInfo = nil, nil, nil
Enum = { SpellBookSpellBank = { Player = 0 }, SpellBookItemType = { Spell = 1, FutureSpell = 2 }, PlayerInteractionType = { Trainer = 7, Merchant = 5 } }
local lines = {
	{ itemIndexOffset = 0, numSpellBookItems = 1 },
	{ itemIndexOffset = 1, numSpellBookItems = 2 },
	{ itemIndexOffset = 3, numSpellBookItems = 2 },
	{ itemIndexOffset = 5, numSpellBookItems = 1, offSpecID = 258 },
}
local items = {
	{ itemType = 1, spellID = 6603 },
	{ itemType = 1, spellID = 2061 }, { itemType = 2, spellID = 2060 },
	{ itemType = 1, spellID = 47540 }, { itemType = 1, spellID = 17, isOffSpec = true },
	{ itemType = 1, spellID = 589 },
}
C_SpellBook = {
	GetNumSpellBookSkillLines = function() return #lines end,
	GetSpellBookSkillLineInfo = function(i) return lines[i] end,
	GetSpellBookItemInfo = function(slot, bank)
		assert(bank == 0, "the player's spell bank")
		return items[slot]
	end,
}
handlers.LEARNED_SPELL_IN_SKILL_LINE(2060, 2)
eq(me.spells, "2061,47540", "retail: the class and spec lines' spells, no future or off-spec spell")

me.spells = nil
handlers.PLAYER_INTERACTION_MANAGER_FRAME_HIDE(5)
eq(me.spells, nil, "a merchant closed reads nothing")
handlers.PLAYER_INTERACTION_MANAGER_FRAME_HIDE(7)
eq(me.spells, "2061,47540", "the trainer closed (the interaction manager) is read again")

C_SpellBook = nil
me.spells = "2061"
module.world()
eq(me.spells, "2061", "a client with neither call writes nothing")

me = nil
module.world()

return checks()
