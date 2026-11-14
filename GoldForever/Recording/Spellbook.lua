-- Gold Forever: the class spells this character knows, by spell ID (characters[guid].spells, schema 11), so
-- the web app leaves what is trained out of the training still to buy (gf#384). Class tabs only: not General,
-- a guild's or an off-spec's, and no spell the book shows as still to learn.

local _, ns = ...

local GENERAL = 1 -- the spellbook's first tab or skill line

-- The older calls (Forever): GetSpellTabInfo's offset and count, GetSpellBookItemInfo's "SPELL" and ID.
local function tabSpells(ids)
	for tab = GENERAL + 1, GetNumSpellTabs() do
		local _, _, offset, count, isGuild, offSpec = GetSpellTabInfo(tab)
		if not isGuild and (offSpec or 0) == 0 then
			for slot = offset + 1, offset + count do
				local kind, id = GetSpellBookItemInfo(slot, "spell")
				if kind == "SPELL" and id then
					ids[#ids + 1] = id
				end
			end
		end
	end
end

-- C_SpellBook (retail): skill lines instead of tabs, an item's type instead of its kind.
local function skillLineSpells(ids)
	local bank = Enum.SpellBookSpellBank.Player
	local spell = Enum.SpellBookItemType.Spell
	for line = GENERAL + 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if info and not info.isGuild and (info.offSpecID or 0) == 0 then
			for slot = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
				local item = C_SpellBook.GetSpellBookItemInfo(slot, bank)
				if item and item.itemType == spell and not item.isOffSpec and item.spellID then
					ids[#ids + 1] = item.spellID
				end
			end
		end
	end
end

-- The class spells known, sorted; nil where the client has neither set of calls.
local function knownSpells()
	local ids = {}
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines and C_SpellBook.GetSpellBookSkillLineInfo and C_SpellBook.GetSpellBookItemInfo then
		skillLineSpells(ids)
	elseif GetNumSpellTabs and GetSpellTabInfo and GetSpellBookItemInfo then
		tabSpells(ids)
	else
		return nil
	end
	table.sort(ids)
	return ids
end

-- "id,id,…", as the professions' recipes. A book with no class spell is one not loaded yet (straight after
-- login): what was read before stays.
local function readSpells()
	local me = ns.me()
	local ids = me and knownSpells()
	if ids and #ids > 0 then
		me.spells = table.concat(ids, ",")
	end
end

local readSoon = ns.throttle("spellbook", 2, readSpells)

ns.module("Spellbook", {
	requires = { "Store" },
	world = function()
		ns.after(4, "spellbook", readSoon)
	end,
})
-- A spell learned (LEARNED_SPELL_IN_SKILL_LINE on retail), and the trainer closed: what was trained there.
ns.on("LEARNED_SPELL_IN_TAB", "spellbook", readSoon)
ns.on("LEARNED_SPELL_IN_SKILL_LINE", "spellbook", readSoon)
ns.on("TRAINER_CLOSED", "spellbook", readSoon)
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "spellbook", function(kind)
	if Enum and Enum.PlayerInteractionType and kind == Enum.PlayerInteractionType.Trainer then
		readSoon()
	end
end)
