-- Gold Forever: Legacy (design 002, State: account). Found on the live client with /gf legacy:
-- Legacy is renown faction 2802 ("Legacy Track", C_MajorFactions) and its perks are trait tree
-- 1187 (C_Traits), paid for with trait currency 4225 earned from achievements.

local _, ns = ...
local Encode = ns.Encode

local FACTION = 2802
local TREE = 1187

ns.FIELDS.legacyPerk = "name,maxRank,spell,description,tree,x,y"
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

local text = Encode.text

-- Legacy has a perk tree per tab. 1187 (professions) came from the trace; the others are found by
-- asking the configuration for its trees and, failing that, by searching tree IDs for ones paid
-- in the same currency (findTrees).
local trees = { [TREE] = true }
local CURRENCY = 4225

local function readTree(tree, legacy, ranks)
	local config = C_Traits.GetConfigIDByTreeID(tree)
	if not config then
		return
	end
	local catalogue = ns.db().catalogue.legacyPerks
	for _, node in ipairs(C_Traits.GetTreeNodes(tree) or {}) do
		local info = C_Traits.GetNodeInfo(config, node)
		if info and info.ID and info.ID ~= 0 then
			local rank = math.max(info.activeRank or 0, info.currentRank or 0, info.ranksPurchased or 0,
				info.activeEntry and info.activeEntry.rank or 0)
			ranks[#ranks + 1] = node .. ":" .. rank
			local entry = info.activeEntry and info.activeEntry.entryID or (info.entryIDs and info.entryIDs[1])
			local entryInfo = entry and C_Traits.GetEntryInfo(config, entry)
			local definition = entryInfo and entryInfo.definitionID and C_Traits.GetDefinitionInfo(entryInfo.definitionID)
			if definition then
				local name, spell, description = perkText(definition)
				catalogue[node] = Encode.row(text(name), info.maxRanks, spell, text(description), tree, info.posX, info.posY)
			end
		end
	end
	local summary = { config = config }
	for _, c in ipairs(C_Traits.GetTreeCurrencyInfo(config, tree, false) or {}) do
		summary.currency = c.traitCurrencyID
		summary.available = c.quantity
		summary.spent = c.spent
		summary.spentInTree = c.spentInTree
		summary.earned = c.maxQuantity
	end
	legacy.trees[tree] = summary
	if summary.currency == CURRENCY and not legacy.currency then
		legacy.currency = summary.currency
		legacy.available = summary.available
		legacy.spent = summary.spent
		legacy.earned = summary.earned
		legacy.config = config
		if C_Traits.GetMaxAvailableTraitCurrency then
			legacy.possible = C_Traits.GetMaxAvailableTraitCurrency(summary.currency, false)
		end
	end
	-- The configuration may name its other trees.
	local configInfo = C_Traits.GetConfigInfo and C_Traits.GetConfigInfo(config)
	for _, other in ipairs(configInfo and configInfo.treeIDs or {}) do
		trees[other] = true
	end
end

local function readPerks(legacy)
	local ranks = {}
	legacy.trees = {}
	local done = {}
	-- readTree can add trees; loop until no new ones appear.
	local again = true
	while again do
		again = false
		-- The trees known now, copied: readTree adds to `trees`, and a table must not grow while pairs walks it.
		local known = {}
		for tree in pairs(trees) do
			known[#known + 1] = tree
		end
		for _, tree in ipairs(known) do
			if not done[tree] then
				done[tree] = true
				again = true
				ns.safely("legacy", readTree, tree, legacy, ranks)
			end
		end
	end
	table.sort(ranks)
	legacy.ranks = table.concat(ranks, ",")
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

-- Legacy is WoW: Forever's: on retail the reads find nothing of it (faction 2802 may be something else).
local function forever()
	local client = ns.db().client
	return not ns.Realms.isRetail(client and client.interface)
end

local function readLegacy()
	if not (C_Traits and C_MajorFactions) or not forever() then
		return
	end
	local db = ns.db()
	db.account = db.account or {}
	local legacy = { t = ns.now(), tree = TREE, faction = FACTION }
	ns.safely("legacy", readRenown, legacy)
	ns.safely("legacy", readPerks, legacy)
	db.account.legacy = legacy
	-- Points are earned account-wide but spent per character: each keeps its own ranks.
	local me = ns.me()
	if me then
		me.legacy = legacy
	end
end

-- Searches tree IDs 1-5000, 250 per step, for trees paid in the Legacy currency; reads Legacy again
-- when done. Once per session.
local searched = false
local function findTrees()
	if searched or not C_Traits.GetConfigIDByTreeID or not forever() then
		return
	end
	searched = true
	local id, found = 0, {}
	local function step()
		for _ = 1, 250 do
			id = id + 1
			local ok, config = pcall(C_Traits.GetConfigIDByTreeID, id)
			if ok and config then
				local okInfo, currencies = pcall(C_Traits.GetTreeCurrencyInfo, config, id, false)
				for _, c in ipairs(okInfo and currencies or {}) do
					if c.traitCurrencyID == CURRENCY then
						trees[id] = true
						found[#found + 1] = id
					end
				end
			end
		end
		if id < 5000 then
			ns.after(0.1, "legacy", step)
		else
			local db = ns.db()
			db.account = db.account or {}
			db.account.legacyTreeSearch = { t = ns.now(), found = table.concat(found, ",") }
			readLegacy()
		end
	end
	step()
end

ns.on("PLAYER_ENTERING_WORLD", "legacy", function()
	ns.after(8, "legacy", function()
		readLegacy()
		findTrees()
	end)
end)
local legacySoon = ns.throttle("legacy", 5, readLegacy)
ns.on("TRAIT_CONFIG_UPDATED", "legacy", legacySoon)
ns.on("TRAIT_TREE_CURRENCY_INFO_UPDATED", "legacy", legacySoon)
ns.on("MAJOR_FACTION_RENOWN_LEVEL_CHANGED", "legacy", legacySoon)
ns.on("ACHIEVEMENT_EARNED", "legacy", legacySoon)
