-- Gold Forever: the item catalogue (design 002, State: catalogue). Every collector that records an
-- item key calls ns.catalogueItem, which writes the item's info once it has loaded.
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

-- A retail item's crafting-quality tier: the client's answer, else the quality markup in its link. Asked only
-- where the schema declares the column; even there the call may be missing or fail (owner: "it has to not
-- fail on Forever as well"), so it is looked up and protected, and anything that is not a tier is none.
local TIERED = Encode.columns(ns.FIELDS.item).tier ~= nil
local TIER_MARKUP = "Professions%-ChatIcon%-Quality%-.-Tier(%d)"
local function tier(id, link)
	if not TIERED then
		return nil
	end
	local quality = C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityByItemInfo
	if quality then
		local ok, value = pcall(quality, id)
		if ok and type(value) == "number" and value >= 1 then
			return value
		end
	end
	return type(link) == "string" and tonumber(string.match(link, TIER_MARKUP)) or nil
end

local function write(id)
	local name, link, quality, ilvl, minLevel, _, _, stack, equipLoc, icon, sell, class, subclass, bind = GetItemInfo(id)
	if not name then
		return false
	end
	local catalogue = ns.db().catalogue
	local row = Encode.row(Encode.name(name), quality, ilvl, class, subclass, stack, sell, bind, icon, minLevel,
		equipLoc ~= "" and equipLoc or nil)
	-- Without a tier the row ends at equipLoc, as every row did before the column.
	local itemTier = tier(id, link)
	catalogue.items[id] = itemTier and (row .. "," .. itemTier) or row
	if not ns.lean then
		catalogue.tooltips[id] = tooltip(id) or catalogue.tooltips[id]
	end
	return true
end

local function load(id)
	if write(id) then
		return
	end
	pending[id] = true
	if Item and Item.CreateFromItemID then
		Item:CreateFromItemID(id):ContinueOnItemLoad(function()
			pending[id] = nil
			ns.safely("catalogue", write, id)
		end)
	end
end

-- Items to catalogue, oldest first, BATCH every PAUSE seconds: a scan names thousands of items at
-- once, and asking the client (and through it the server) for all of them in one frame stutters
-- the game and gets throttled. One queue serves loot, scans, bags and the backfill below.
local BATCH, PAUSE = 20, 0.2
-- head and tail are explicit: # on a table emptied from the front is any border, and an append at
-- #queue + 1 then landed behind head and was never drained (half of a retail scan's items, 0.14.0).
local queue, head, tail = {}, 1, 0
local queued = {} -- item ID -> true while it waits in the queue
local tried = {} -- item IDs asked for this session: one with no tooltip is not asked again and again
local draining = false

local function drain()
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
	end
	if queue[head] then
		ns.after(PAUSE, "catalogue", drain)
	else
		draining = false
	end
end

-- Records the catalogue entry for an item key ("14047", "10221:612" or a number), once.
function ns.catalogueItem(key)
	local id = Encode.itemId(key)
	local catalogue = ns.db().catalogue
	if not id or (catalogue.items[id] and (ns.lean or catalogue.tooltips[id])) or pending[id] or queued[id] or tried[id] then
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

-- Fills in tooltips (and the new columns) for items catalogued before 0.4.0, through the queue,
-- once a session.
ns.module("Catalogue", {
	requires = { "Store" },
	enable = function()
		if ns.lean then
			return
		end
		ns.after(5, "catalogue", function()
			local catalogue = ns.db().catalogue
			for id in pairs(catalogue.items) do
				if not catalogue.tooltips[id] then
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
	return tooltip and (string.find(tooltip, ITEM_STARTS_QUEST or "This Item Begins a Quest", 1, true) and true) or nil
end

-- Whether this character finished the quest; unknown (nil) without a quest ID.
function Catalogue.questDone(quest)
	if type(quest) ~= "number" then
		return nil
	end
	local completed = C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted or IsQuestFlaggedCompleted
	return completed and completed(quest) or false
end
