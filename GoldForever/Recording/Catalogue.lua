-- Gold Forever: the item catalogue (design 002, State: catalogue). Every collector that records an
-- item key calls ns.catalogueItem, which reads the item's info from the game once a session, when it has
-- loaded, and rewrites its row stamped with readAt (gf#392): the server takes a sell price as the game's
-- only from a row read since launch, never from one carried over from the beta.
--
-- From 0.4.0 each item also keeps its tooltip text: Forever-only items exist nowhere else once
-- the game is gone. Items catalogued before that are filled in by a slow pass after login.

local _, ns = ...
local Encode = ns.Encode

local Catalogue = {}
ns.Catalogue = Catalogue

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local pending = {} -- item IDs waiting for their info to load

-- Tooltip lines joined with "\n", right-hand text after a tab.
local function tooltip(id)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		return nil
	end
	local data = C_TooltipInfo.GetItemByID(id)
	if not data or not data.lines then
		return nil
	end
	local lines = {}
	for _, line in ipairs(data.lines) do
		local text = line.leftText or ""
		if line.rightText and line.rightText ~= "" then
			text = text .. "\t" .. line.rightText
		end
		lines[#lines + 1] = text
	end
	return table.concat(lines, "\n")
end

-- For a lean (retail) save, which keeps none: an item's tooltip text read when asked.
ns.itemTooltipText = tooltip

-- A retail item's crafting-quality tier: the client's answer (a reagent's 1–3, a crafted item's 1–5), else the
-- quality markup in its link. Asked only where the schema declares the column; even there the calls may be
-- missing or fail (owner: "it has to not fail on Forever as well"), so they are looked up and protected, and
-- anything that is not a tier is none.
local TIERED = Encode.columns(ns.FIELDS.item).tier ~= nil
local TIER_MARKUP = "Professions%-ChatIcon%-Quality%-.-Tier(%d)"
local TIER_CALLS = { "GetItemReagentQualityByItemInfo", "GetItemCraftedQualityByItemInfo" }
local function tier(id, link)
	if not TIERED then
		return nil
	end
	for _, call in ipairs(TIER_CALLS) do
		local quality = C_TradeSkillUI and C_TradeSkillUI[call]
		if quality then
			local ok, value = pcall(quality, id)
			if ok and type(value) == "number" and value >= 1 then
				return value
			end
		end
	end
	return type(link) == "string" and tonumber(string.match(link, TIER_MARKUP)) or nil
end

-- A retail item's expansion from GetItemInfo's 15th return; anything the server would not store (the client
-- docs give 254 on Classic clients) is none.
local function expansion(value)
	if TIERED and type(value) == "number" and value >= 0 and value <= 99 and value % 1 == 0 then
		return value
	end
	return nil
end

-- A retail row may end before its tier (catalogued before schema 9, addon#72) or its expansion, and an item
-- with neither looks the same; such a row is read again after login. Values after the row's end are placed
-- in their columns, the ones between left empty.
local TIER_AT = TIERED and Encode.columns(ns.FIELDS.item).tier
local EXPANSION_AT = TIERED and Encode.columns(ns.FIELDS.item).expansion
local READ_AT = Encode.columns(ns.FIELDS.item).readAt
local function commas(row)
	local _, count = string.gsub(row, ",", "")
	return count
end
local function unfilled(row)
	return TIERED and commas(row) < EXPANSION_AT - 1
end
local function place(row, at, value)
	return row .. string.rep(",", at - 1 - commas(row)) .. value
end

local function write(id)
	local name, link, quality, ilvl, minLevel, _, _, stack, equipLoc, icon, sell, class, subclass, bind, expansionID = GetItemInfo(id)
	if not name then
		return false
	end
	local catalogue = ns.db().catalogue
	local row = Encode.row(Encode.name(name), quality, ilvl, class, subclass, stack, sell, bind, icon, minLevel,
		equipLoc ~= "" and equipLoc or nil)
	-- Without a tier or an expansion the row ends at equipLoc, as every row did before the columns.
	local itemTier = tier(id, link)
	if itemTier then
		row = place(row, TIER_AT, itemTier)
	end
	local itemExpansion = expansion(expansionID)
	if itemExpansion then
		row = place(row, EXPANSION_AT, itemExpansion)
	end
	catalogue.items[id] = place(row, READ_AT, ns.now())
	if not ns.lean then
		catalogue.tooltips[id] = tooltip(id) or catalogue.tooltips[id]
	end
	return true
end

-- fn now, or in a fight once it ends: the tier is never asked in combat, and an AH scan's thousands of
-- items never cost a fight's frames.
local function outOfFight(fn)
	ns.afterCombat("catalogue", fn)
end

local function load(id)
	if write(id) then
		return
	end
	pending[id] = true
	if Item and Item.CreateFromItemID then
		Item:CreateFromItemID(id):ContinueOnItemLoad(function()
			outOfFight(function()
				pending[id] = nil
				write(id)
			end)
		end)
	end
end

-- Items to catalogue, oldest first, BATCH every PAUSE seconds and at most BUDGET_MS of a frame: a scan
-- names thousands of items at once, and asking the client (and through it the server) for all of them in
-- one frame stutters the game and gets throttled. One queue serves loot, scans, bags and the backfill below.
local BATCH, PAUSE, BUDGET_MS = 20, 0.2, 2
-- head and tail are explicit: # on a table emptied from the front is any border, and an append at
-- #queue + 1 then landed behind head and was never drained (half of a retail scan's items, 0.14.0).
local queue, head, tail = {}, 1, 0
local queued = {} -- item ID -> true while it waits in the queue
local tried = {} -- item IDs asked for this session: one with no tooltip is not asked again and again
local draining = false

-- After a batch that read anything the next waits PAUSE, so items named meanwhile (a scan's, a frame at a
-- time) queue for it instead of each being read at once.
local function drain()
	if ns.inCombat() then
		ns.afterCombat("catalogue", drain)
		return
	end
	if not queue[head] then
		draining = false
		return
	end
	local started = ns.frameStart()
	for _ = 1, BATCH do
		local id = queue[head]
		if not id then
			break
		end
		queue[head] = nil
		head = head + 1
		queued[id] = nil
		tried[id] = true
		if not pending[id] then
			load(id)
		end
		if started and ns.frameStart() - started >= BUDGET_MS then
			break
		end
	end
	ns.after(PAUSE, "catalogue", drain)
end

-- Reads an item key's ("14047", "10221:612" or a number) catalogue entry from the game, once a session.
function ns.catalogueItem(key)
	local id = Encode.itemId(key)
	if not id or pending[id] or queued[id] or tried[id] then
		return
	end
	queued[id] = true
	tail = tail + 1
	queue[tail] = id
	if not draining then
		draining = true
		drain() -- the first batch now: a single loot is catalogued at once
	end
end

-- Reads again after login, through the queue: on Forever the items catalogued before 0.4.0 without a
-- tooltip, on retail the rows written without tier and expansion.
ns.module("Catalogue", {
	requires = { "Store" },
	enable = function()
		if ns.lean and not TIERED then
			return
		end
		ns.after(5, "catalogue", function()
			local catalogue = ns.db().catalogue
			for id, row in pairs(catalogue.items) do
				if unfilled(row) or not (ns.lean or catalogue.tooltips[id]) then
					ns.catalogueItem(id)
				end
			end
		end)
	end,
})

-- One column of an entry's row, by its name in ns.FIELDS (kind "item" reads catalogue.items, "npc"
-- catalogue.npcs); nil when there is no row or the column is empty.
local patterns = {} -- "kind column" -> a pattern capturing that column
local function column(kind, id, name)
	local section = ns.db().catalogue[kind .. "s"]
	local row = section and section[id]
	if not row then
		return nil
	end
	local key = kind .. " " .. name
	local pattern = patterns[key]
	if pattern == nil then
		local i = Encode.columns(ns.FIELDS[kind])[name]
		pattern = i and ("^" .. string.rep("[^,]*,", i - 1) .. "([^,]*)") or false
		patterns[key] = pattern
	end
	local value = pattern and string.match(row, pattern)
	return value ~= "" and value or nil
end

-- An entry's name as the catalogue has it ("item", "npc", "object", …).
function Catalogue.name(kind, id)
	return column(kind, id, "name")
end

-- An item's quality (0 poor … 4 epic) as the catalogue has it.
function Catalogue.quality(id)
	return tonumber(column("item", id, "quality"))
end

-- The quest an item starts: its ID when a loot window said so, true when only its tooltip does.
function Catalogue.startsQuest(id)
	local catalogue = ns.db().catalogue
	local quest = catalogue.questStarters and catalogue.questStarters[id]
	if quest then
		return quest
	end
	local tooltip = catalogue.tooltips[id] or (ns.lean and ns.itemTooltipText(id))
	return tooltip and ITEM_STARTS_QUEST and (string.find(tooltip, ITEM_STARTS_QUEST, 1, true) and true) or nil
end

-- Whether this character finished the quest; unknown (nil) without a quest ID.
function Catalogue.questDone(quest)
	if type(quest) ~= "number" then
		return nil
	end
	local completed = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
	return completed and completed(quest) or false
end
