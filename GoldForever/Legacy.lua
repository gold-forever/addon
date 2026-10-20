-- Gold Forever: Legacy (design 002, State: account). Found on the live client with /gf legacy:
-- Legacy is renown faction 2802 ("Legacy Track", C_MajorFactions) and its perks are trait tree
-- 1187 (C_Traits), paid for with trait currency 4225 earned from achievements.

local _, ns = ...
local Encode = ns.Encode

local FACTION = 2802
local TREE = 1187

ns.FIELDS.legacyPerk = "name,maxRank,spell,description"
ns.FIELDS.legacyReward = "level,item,name,description"

-- Perk name and description: the definition's own text, else its spell's.
local function perkText(definition)
	local name = definition.overrideName
	local spell = definition.spellID or definition.overriddenSpellID
	if (not name or name == "") and spell and C_Spell and C_Spell.GetSpellName then
		name = C_Spell.GetSpellName(spell)
	end
	local description = definition.overrideDescription
	if (not description or description == "") and spell and C_Spell and C_Spell.GetSpellDescription then
		description = C_Spell.GetSpellDescription(spell)
	end
	return name, spell, description
end

-- Free text in a catalogue row: no commas (columns), semicolons or line breaks.
local function text(s)
	if not s or s == "" then
		return nil
	end
	return (Encode.name(s):gsub(";", ".") :gsub("[\r\n]+", " "))
end

local function readPerks(legacy)
	local config = C_Traits.GetConfigIDByTreeID(TREE)
	if not config then
		return
	end
	local catalogue = ns.db().catalogue.legacyPerks
	local ranks = {}
	for _, node in ipairs(C_Traits.GetTreeNodes(TREE) or {}) do
		local info = C_Traits.GetNodeInfo(config, node)
		if info and info.ID and info.ID ~= 0 then
			local rank = info.activeRank or info.ranksPurchased or 0
			ranks[#ranks + 1] = node .. ":" .. rank
			local entry = info.activeEntry and info.activeEntry.entryID or (info.entryIDs and info.entryIDs[1])
			local entryInfo = entry and C_Traits.GetEntryInfo(config, entry)
			local definition = entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
			if definition then
				local name, spell, description = perkText(definition)
				catalogue[node] = Encode.row(text(name), info.maxRanks, spell, text(description))
			end
		end
	end
	legacy.ranks = table.concat(ranks, ",")
	legacy.config = config
	for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(config, TREE, false) or {}) do
		legacy.currency = c.traitCurrencyID
		legacy.available = c.quantity
		legacy.spent = c.spent
		legacy.earned = c.maxQuantity
		if C_Traits.GetMaxAvailableTraitCurrency then
			legacy.possible = C_Traits.GetMaxAvailableTraitCurrency(c.traitCurrencyID, false)
		end
	end
end

local function readRenown(legacy)
	local data = C_MajorFactions.GetMajorFactionData(FACTION)
	if not data then
		return
	end
	legacy.renown = data.renownLevel
	legacy.renownMax = data.maxLevel
	legacy.renownEarned = data.renownReputationEarned
	legacy.renownThreshold = data.renownLevelThreshold
	local rewards = ns.db().catalogue.legacyRewards
	for _, level in ipairs(C_MajorFactions.GetRenownLevels(FACTION) or {}) do
		for i, r in ipairs(C_MajorFactions.GetRenownRewardsForLevel(FACTION, level.level) or {}) do
			rewards[level.level .. ":" .. i] = Encode.row(level.level, r.itemID, text(r.toastDescription or r.name),
				text(r.description))
			if r.itemID then
				ns.catalogueItem(r.itemID)
			end
		end
	end
end

local function readLegacy()
	if not (C_Traits and C_MajorFactions) then
		return
	end
	local db = ns.db()
	db.account = db.account or {}
	local legacy = { t = ns.now(), tree = TREE, faction = FACTION }
	ns.safely("legacy", readRenown, legacy)
	ns.safely("legacy", readPerks, legacy)
	db.account.legacy = legacy
end

ns.on("PLAYER_ENTERING_WORLD", "legacy", function()
	ns.after(8, "legacy", readLegacy)
end)
local legacySoon = ns.throttle("legacy", 5, readLegacy)
ns.on("TRAIT_CONFIG_UPDATED", "legacy", legacySoon)
ns.on("TRAIT_TREE_CURRENCY_INFO_UPDATED", "legacy", legacySoon)
ns.on("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "legacy", legacySoon)
ns.on("ACHIEVEMENT_EARNED", "legacy", legacySoon)
