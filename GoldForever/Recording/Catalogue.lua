-- Gold Forever: the item catalogue (design 002, State: catalogue). Every collector that records an
-- item key calls ns.catalogueItem, which reads the item's info from the game once a session, when it has
-- loaded, and rewrites its row stamped with readAt (gf#392): the server takes a sell price as the game's
-- only from a row read since launch, never from one carried over from the beta.
--
-- On Forever an item a character holds also keeps its tooltip text: Forever-only items exist nowhere else
-- once the game is gone. Only those (gf#402): a scan's thousands and the re-read with theirs took the
-- owner's save past the server's 10 MiB. A held item without one is filled in after login.

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

-- What some character holds (gf#402): the item IDs in every character's saved bags, bank and mail, and
-- worn. Built again only when one of those was saved anew (each read saves a new table).
local PLACES = { "bags", "bank", "mail" }
local heldIds, heldStamp
local function stamp(characters)
	local parts = {}
	for guid, c in pairs(characters) do
		parts[#parts + 1] = guid
		for _, place in ipairs(PLACES) do
			parts[#parts + 1] = tostring(c[place])
		end
		parts[#parts + 1] = tostring(c.gear)
	end
	return table.concat(parts, " ")
end
local function held(id)
	local characters = ns.db().characters or {}
	local now = stamp(characters)
	if heldStamp ~= now then
		heldIds, heldStamp = {}, now
		for _, c in pairs(characters) do
			for _, place in ipairs(PLACES) do
				for item in pairs(Encode.parseItems(c[place] and c[place].items)) do
					heldIds[item] = true
				end
			end
			for _, key in pairs(c.gear or {}) do
				local item = Encode.itemId(key)
				if item then
					heldIds[item] = true
				end
			end
		end
	end
	return heldIds[id] == true
end

local tooltipAsked = {} -- item IDs written with their tooltip this session

-- Whether an item already read this session is read again for its tooltip: held now, and without one.
local function wantsTooltip(id)
	return not ns.lean and not tooltipAsked[id] and not ns.db().catalogue.tooltips[id] and held(id)
end

-- The item's row, and its tooltip when keepTooltip (a held item, on Forever).
local function write(id, keepTooltip)
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
	if keepTooltip and not ns.lean then
		tooltipAsked[id] = true
		catalogue.tooltips[id] = tooltip(id) or catalogue.tooltips[id]
	end
	return true
end

-- fn now, or in a fight once it ends: the tier is never asked in combat, and an AH scan's thousands of
-- items never cost a fight's frames.
local function outOfFight(fn)
	ns.afterCombat("catalogue", fn)
end

local function load(id, keepTooltip)
	if write(id, keepTooltip) then
		return
	end
	pending[id] = true
	if Item and Item.CreateFromItemID then
		Item:CreateFromItemID(id):ContinueOnItemLoad(function()
			outOfFight(function()
				pending[id] = nil
				write(id, keepTooltip)
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
			load(id, held(id))
		end
		if started and ns.frameStart() - started >= BUDGET_MS then
			break
		end
	end
	ns.after(PAUSE, "catalogue", drain)
end

-- Reads an item key's ("14047", "10221:612" or a number) catalogue entry from the game, once a session,
-- and again when it is held since without its tooltip (looted, then the bags read).
function ns.catalogueItem(key)
	local id = Encode.itemId(key)
	if not id or pending[id] or queued[id] or tried[id] and not wantsTooltip(id) then
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

-- The re-read (gf#392): every row without readAt, seen this session or not, is read from the game once, in
-- the background: one item each PASS seconds (four a second, on a ticker), out of combat, never while the
-- auction house or a profession window is open (a scan or a craft has the frames), and a tick checks rows
-- already read for at most PASS_BUDGET_MS (PASS_CHECKS where the client has no timer). save.reread.after is
-- the last item taken, in ID order, so the next session goes on after it and an item the game never answered
-- is not asked twice; save.reread.done once the walk is through. A row written since always has readAt.
-- The names wanted (below) take the same ticker once the re-read is through.
local PASS, PASS_START, PASS_BUDGET_MS, PASS_CHECKS = 0.25, 30, 1, 200
local busy = {} -- "auction house", "profession" -> true while that window is open
local walk -- { ids, at }: this session's item IDs after the saved place, in order
local names -- { list = { { kind, id }, ... }, at }: this session's names wanted, in the file's order
local ticker

local function lacksReadAt(row)
	return commas(row) < READ_AT - 1
end

-- A beat's checks are spent: its millisecond, or PASS_CHECKS without the client's timer.
local function spent(started, checked)
	return started and ns.frameStart() - started >= PASS_BUDGET_MS or not started and checked >= PASS_CHECKS
end

local function stopWhenIdle()
	if not (walk or names) and ticker then
		ticker:Cancel()
		ticker = nil
	end
end

local function finish(state)
	state.done, state.after = true, nil
	walk = nil
	stopWhenIdle()
end

local function rereadStep()
	local state = ns.db().reread
	local items = ns.db().catalogue.items
	local started, checked = ns.frameStart(), 0
	while true do
		local id = walk.ids[walk.at]
		if not id then
			finish(state)
			return
		end
		walk.at = walk.at + 1
		state.after = id
		local row = items[id]
		if row and lacksReadAt(row) and not (pending[id] or queued[id] or tried[id]) then
			tried[id] = true
			load(id, false)
			return
		end
		checked = checked + 1
		if spent(started, checked) then
			return
		end
	end
end

-- Names wanted (gf#397): the IDs the server has no name for in this client's language, as the companion's
-- data file lists them (DataFormat.lua), asked of the game one a beat once the re-read is through, while
-- "Help translate names" is on. Each name goes into the catalogue as the game gives it, the row it keeps
-- today, so the save uploads it in the client's locale; a recipe's name goes into recipeNames (gf#401), never
-- its row, since a spell's name alone is no recipe. What the save names already (a recipe row's name too) is
-- not asked; an ID the game did not answer
-- is kept in save.names.unanswered and not asked again in that language.
local GetSpellName = C_Spell and C_Spell.GetSpellName or function(id)
	return GetSpellInfo and (GetSpellInfo(id)) or nil
end
local NAME_AT = Encode.columns(ns.FIELDS.recipe).name
local function text(value)
	return type(value) == "string" and value ~= "" and value or nil
end
local function factionName(id)
	if C_Reputation and C_Reputation.GetFactionDataByID then
		local faction = C_Reputation.GetFactionDataByID(id)
		return faction and text(faction.name)
	end
	return GetFactionInfoByID and text((GetFactionInfoByID(id))) or nil
end
local requested = {} -- quest IDs asked of the client this session, named when it has loaded them
local function questTitle(id)
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and text(C_QuestLog.GetTitleForQuestID(id))
	if not title and C_QuestLog and C_QuestLog.RequestLoadQuestByID then
		requested[id] = true
		C_QuestLog.RequestLoadQuestByID(id) -- QUEST_DATA_LOAD_RESULT names it
	end
	return title
end

-- Each kind of the data file: whether the save lacks the name (wants), and the ask, true when it named it.
local NAMERS = {
	items = {
		section = "items",
		wants = function(rows, id)
			return not rows[id] and not (pending[id] or queued[id] or tried[id])
		end,
		ask = function(id)
			tried[id] = true
			load(id, false)
			return ns.db().catalogue.items[id] ~= nil
		end,
	},
	recipes = {
		section = "recipeNames",
		wants = function(rows, id)
			local row = ns.db().catalogue.recipes[id]
			return not rows[id] and not (row and commas(row) >= NAME_AT - 1)
		end,
		ask = function(id)
			local name = text(GetSpellName(id))
			if name then
				ns.db().catalogue.recipeNames[id] = Encode.name(name)
			end
			return name ~= nil
		end,
	},
	quests = {
		section = "questNames",
		wants = function(rows, id)
			return not rows[id]
		end,
		ask = function(id)
			local title = questTitle(id)
			if title then
				ns.db().catalogue.questNames[id] = Encode.name(title)
			end
			return title ~= nil
		end,
	},
	factions = {
		section = "factions",
		wants = function(rows, id)
			return not rows[id]
		end,
		ask = function(id)
			local name = factionName(id)
			if name then
				ns.db().catalogue.factions[id] = Encode.name(name)
			end
			return name ~= nil
		end,
	},
	maps = {
		section = "maps",
		wants = function(rows, id)
			return not rows[id]
		end,
		ask = function(id)
			local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
			local name = info and text(info.name)
			if name then
				ns.db().catalogue.maps[id] = Encode.row(Encode.name(name), info.mapType, info.parentMapID)
			end
			return name ~= nil
		end,
	},
}
local NAME_KINDS = { "items", "recipes", "quests", "factions", "maps" } -- DataFormat.field's names of them

local function helping()
	return ns.settings("names").help ~= false
end

-- The IDs unanswered in this client's language, as save.names keeps them: another language's record is
-- dropped, an ID named since (an item loaded later) leaves it, and an empty record is not kept.
local function unansweredIn(locale)
	local db = ns.db()
	local unanswered = db.names and db.names.locale == locale and db.names.unanswered or {}
	for _, kind in ipairs(NAME_KINDS) do
		local rows, kept = db.catalogue[NAMERS[kind].section], unanswered[kind]
		for id in pairs(kept or {}) do
			if rows[id] then
				kept[id] = nil
			end
		end
		unanswered[kind] = kept and next(kept) and kept or nil
	end
	db.names = next(unanswered) and { locale = locale, unanswered = unanswered } or nil
	return unanswered
end

local function keepUnanswered(kind, id)
	local db, unanswered = ns.db(), names.unanswered
	unanswered[kind] = unanswered[kind] or {}
	unanswered[kind][id] = true
	db.names = db.names or { locale = names.locale, unanswered = unanswered }
end

-- This session's names wanted: the data file's list when it is of this client's language, else none.
local function namesWanted()
	local D = ns.DataFormat
	local F = D and D.field
	local data = F and _G[D.GLOBAL]
	local wanted = type(data) == "table" and data[F.namesWanted]
	local locale = GetLocale and GetLocale()
	if type(wanted) ~= "table" or not locale or wanted[F.locale] ~= locale then
		return nil
	end
	local list = {}
	for _, kind in ipairs(NAME_KINDS) do
		local ids = wanted[F[kind]]
		for _, id in ipairs(type(ids) == "table" and ids or {}) do
			if type(id) == "number" then
				list[#list + 1] = { kind, id }
			end
		end
	end
	return #list > 0 and { list = list, at = 1, locale = locale, unanswered = unansweredIn(locale) } or nil
end

local function namesStep()
	local catalogue = ns.db().catalogue
	local started, checked = ns.frameStart(), 0
	while true do
		local entry = names.list[names.at]
		if not entry then
			names = nil
			stopWhenIdle()
			return
		end
		names.at = names.at + 1
		local kind, id = entry[1], entry[2]
		local namer, unanswered = NAMERS[kind], names.unanswered
		if not (unanswered[kind] and unanswered[kind][id]) and namer.wants(catalogue[namer.section], id) then
			if not namer.ask(id) then
				keepUnanswered(kind, id)
			end
			return
		end
		checked = checked + 1
		if spent(started, checked) then
			return
		end
	end
end

-- A quest the client loaded on request: named, and no longer unanswered.
ns.on("QUEST_DATA_LOAD_RESULT", "catalogue", function(id, success)
	if not (requested[id] and success) then
		return
	end
	requested[id] = nil
	local title = text(C_QuestLog.GetTitleForQuestID(id))
	if title then
		ns.db().catalogue.questNames[id] = Encode.name(title)
		local unanswered = names and names.unanswered.quests
		if unanswered then
			unanswered[id] = nil
		end
	end
end)

local function step()
	if ns.inCombat() or next(busy) then
		return
	end
	if walk then
		rereadStep()
	elseif names and helping() then
		namesStep()
	end
end

-- The re-read's IDs, after the saved place, in order, until it is done; then the names wanted: one frame's
-- work once a session.
local function rereadWalk()
	local db = ns.db()
	db.reread = db.reread or {}
	if db.reread.done then
		return nil
	end
	local after, ids = db.reread.after or 0, {}
	for id in pairs(db.catalogue.items) do
		if type(id) == "number" and id > after then
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return { ids = ids, at = 1 }
end

local function startWalk()
	if not (C_Timer and C_Timer.NewTicker) then
		return
	end
	walk, names = rereadWalk(), namesWanted()
	if not (walk or names) then
		return
	end
	ticker = C_Timer.NewTicker(PASS, function()
		ns.safely("catalogue", step)
	end)
	step()
end

local function windowOpened(window)
	busy[window] = true
end
local function windowClosed(window)
	busy[window] = nil
end
ns.on("AUCTION_HOUSE_SHOW", "catalogue", function() windowOpened("auction house") end)
ns.on("AUCTION_HOUSE_CLOSED", "catalogue", function() windowClosed("auction house") end)
ns.on("TRADE_SKILL_SHOW", "catalogue", function() windowOpened("profession") end)
ns.on("TRADE_SKILL_CLOSE", "catalogue", function() windowClosed("profession") end)
-- Newer clients open the auction house through the interaction manager.
local INTERACTION = Enum and Enum.PlayerInteractionType or {}
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "catalogue", function(kind)
	if kind and kind == INTERACTION.Auctioneer then
		windowOpened("auction house")
	end
end)
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "catalogue", function(kind)
	if kind and kind == INTERACTION.Auctioneer then
		windowClosed("auction house")
	end
end)

-- Once (gf#402): every stored tooltip of an item no character holds goes; the server keeps the ones it was
-- sent, and one held again is read again. db.tooltipsTrimmed marks it done.
local function trimTooltips()
	local db = ns.db()
	if db.tooltipsTrimmed then
		return
	end
	local tooltips = db.catalogue.tooltips
	for id in pairs(tooltips) do
		if not held(id) then
			tooltips[id] = nil
		end
	end
	db.tooltipsTrimmed = true
end

-- After login: on Forever the tooltips trimmed once and the held items without one, on retail the rows
-- written without tier and expansion, through the queue; then the re-read.
ns.module("Catalogue", {
	requires = { "Store" },
	enable = function()
		trimTooltips()
		if not (ns.lean and not TIERED) then
			ns.after(5, "catalogue", function()
				local catalogue = ns.db().catalogue
				for id, row in pairs(catalogue.items) do
					if unfilled(row) or not ns.lean and not catalogue.tooltips[id] and held(id) then
						ns.catalogueItem(id)
					end
				end
			end)
		end
		ns.after(PASS_START, "catalogue", startWalk)
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
