-- Gold Forever: crafts, money changes and quests — the additive streams design 002 reserves for
-- the ledger (rule 4). Recorded from 0.3.0; no names of other players, ever.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.craft = "t,char,recipe,item,qty,skill,map"
ns.FIELDS.money = "t,char,delta,ctx"
ns.FIELDS.quest = "t,char,quest,kind,xp,money,map"
ns.FIELDS.questName = "name"

local function GetItemCount(id)
	return (C_Item and C_Item.GetItemCount or _G.GetItemCount)(id)
end

-- Crafts -----------------------------------------------------------------------------------------

local before = {} -- castGUID -> output count in the bags when the cast started

-- Output item and skill line of a catalogued recipe; recipes are catalogued when the profession
-- window opens, which crafting needs.
local function recipe(id)
	local row = ns.db().catalogue.recipes[id]
	if not row then
		return nil
	end
	local line, output = string.match(row, "^([^,]*),([^,]*)")
	return tonumber(output), tonumber(line)
end

ns.on("UNIT_SPELLCAST_START", "craft", function(unit, cast, spell)
	if unit ~= "player" then
		return
	end
	local output = recipe(spell)
	if output then
		before[cast] = GetItemCount(output)
	end
end, "player")

-- What a craft made: the game's "You create: [Bolt of Linen Cloth]x2." says it exactly. Counting the
-- bags instead misses with "Create All", where the next cast starts before this one's items arrive.
-- A craft waits for its message a moment, then falls back to the bag count.
local CREATED_MULTIPLE = Encode.pattern(LOOT_ITEM_CREATED_SELF_MULTIPLE or "You create: %sx%d.")
local CREATED = Encode.pattern(LOOT_ITEM_CREATED_SELF or "You create: %s.")
local MESSAGE_WAIT = 2 -- seconds
local crafting = {} -- casts done, oldest first: { t, spell, output, line, map, start, me }

local function writeCraft(c, qty)
	ns.append("craft", Encode.row(c.t, c.me.ref, c.spell, c.output, qty, c.line and ns.skill(c.line), c.map))
end

ns.on("UNIT_SPELLCAST_SUCCEEDED", "craft", function(unit, cast, spell)
	local me = ns.me()
	if unit ~= "player" or not me or not ns.db().catalogue.recipes[spell] then
		return
	end
	local output, line = recipe(spell)
	local c = {
		t = ns.now(), spell = spell, output = output, line = line, map = C_Map.GetBestMapForUnit("player"), me = me,
		start = output and (before[cast] or GetItemCount(output)),
	}
	before[cast] = nil
	crafting[#crafting + 1] = c
	ns.after(MESSAGE_WAIT, "craft", function()
		for i, waiting in ipairs(crafting) do
			if waiting == c then
				table.remove(crafting, i)
				writeCraft(c, c.output and math.max(0, GetItemCount(c.output) - c.start) or nil)
				break
			end
		end
	end)
end, "player")

ns.on("CHAT_MSG_LOOT", "craft", function(message)
	if #crafting == 0 then
		return
	end
	-- A message the client keeps from addons (in combat) cannot be read; the bag count stands in.
	local ok, link, count = pcall(string.match, message, CREATED_MULTIPLE)
	if not (ok and link) then
		ok, link = pcall(string.match, message, CREATED)
		count = 1
	end
	if not (ok and link) then
		return
	end
	local item = Encode.itemId(Encode.itemKey(link))
	for i, c in ipairs(crafting) do
		if c.output == item then
			table.remove(crafting, i)
			writeCraft(c, tonumber(count))
			return
		end
	end
end)

-- Money ------------------------------------------------------------------------------------------

local money -- last known GetMoney()
local open = {} -- windows open now: merchant, auctioneer, mail, trainer, taxi, ...
local questAt -- GetTime() of the last quest turned in

-- Interaction types by number, so every window the interaction manager opens has a name.
local INTERACTION = {}
for name, id in pairs(Enum and Enum.PlayerInteractionType or {}) do
	INTERACTION[id] = string.lower(name)
end

-- The Blizzard frames behind window names. A close event does not always come (the mailbox, a
-- gossip window left by walking away), so a window whose frame is hidden is closed when money moves.
local FRAMES = {
	merchant = { "MerchantFrame" },
	auction = { "AuctionHouseFrame", "AuctionFrame" },
	auctioneer = { "AuctionHouseFrame", "AuctionFrame" },
	mail = { "MailFrame" },
	mailinfo = { "MailFrame" },
	trade = { "TradeFrame" },
	tradepartner = { "TradeFrame" },
	taxi = { "TaxiFrame", "FlightMapFrame" },
	taxinode = { "TaxiFrame", "FlightMapFrame" },
	trainer = { "ClassTrainerFrame" },
	gossip = { "GossipFrame" },
	banker = { "BankFrame" },
}

-- Whether a window still shows: unknown (no frame of that name) counts as showing.
local function showing(name)
	local known = false
	for _, frame in ipairs(FRAMES[name] or {}) do
		local f = _G[frame]
		if f and f.IsShown then
			known = true
			if f:IsShown() then
				return true
			end
		end
	end
	return not known
end

local function context()
	if ns.lootAt and GetTime() - ns.lootAt < 2 then
		return "loot"
	end
	if questAt and GetTime() - questAt < 3 then
		return "quest"
	end
	for name in pairs(open) do
		if not showing(name) then
			open[name] = nil
		end
	end
	local names = {}
	for name in pairs(open) do
		names[#names + 1] = name
	end
	table.sort(names)
	return table.concat(names, "+") -- "+" keeps several windows in one column
end

ns.on("PLAYER_ENTERING_WORLD", "money", function()
	money = GetMoney()
end)

ns.on("PLAYER_MONEY", "money", function()
	local me = ns.me()
	if not me or ns.tornDown() then
		return
	end
	local now = GetMoney()
	if money and now ~= money then
		ns.append("money", Encode.row(ns.now(), me.ref, now - money, context()))
	end
	money = now
end)

ns.on("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "money", function(kind)
	open[INTERACTION[kind] or tostring(kind)] = true
end)
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "money", function(kind)
	open[INTERACTION[kind] or tostring(kind)] = nil
end)
-- Older clients, and windows the interaction manager does not cover.
for show, hide in pairs({
	MERCHANT_SHOW = "MERCHANT_CLOSED",
	AUCTION_HOUSE_SHOW = "AUCTION_HOUSE_CLOSED",
	MAIL_SHOW = "MAIL_CLOSED",
	TRADE_SHOW = "TRADE_CLOSED",
	TAXIMAP_OPENED = "TAXIMAP_CLOSED",
	TRAINER_SHOW = "TRAINER_CLOSED",
}) do
	local name = string.lower(string.match(show, "^([^_]+)"))
	ns.on(show, "money", function()
		open[name] = true
	end)
	ns.on(hide, "money", function()
		open[name] = nil
	end)
end

-- Quests -----------------------------------------------------------------------------------------

local function questName(id)
	local names = ns.db().catalogue.questNames
	if names[id] then
		return
	end
	local title = C_QuestLog and C_QuestLog.GetTitleForQuestID and C_QuestLog.GetTitleForQuestID(id)
	if title then
		names[id] = Encode.name(title)
	end
end

local function quest(id, kind, xp, reward)
	local me = ns.me()
	if not me or not id then
		return
	end
	ns.append("quest", Encode.row(ns.now(), me.ref, id, kind, xp, reward, C_Map.GetBestMapForUnit("player")))
	questName(id)
end

ns.on("QUEST_ACCEPTED", "quest", function(a, b)
	-- Mainline passes the quest ID first; older clients pass the log index, then the ID.
	quest(b or a, "accept")
end)
ns.on("QUEST_TURNED_IN", "quest", function(id, xp, reward)
	questAt = GetTime()
	quest(id, "done", xp, reward)
end)

-- Flights ----------------------------------------------------------------------------------------

ns.FIELDS.flight = "t,char,from,to,cost,map"
ns.FIELDS.taxiNode = "name"

local CURRENT = Enum and Enum.FlightPathState and Enum.FlightPathState.Current

-- Taxi node IDs by slot on the open flight map, and the node the player is at. Node names go
-- into the catalogue; without node IDs the names themselves are written.
local function taxiNodes()
	local bySlot, current = {}, nil
	local map = GetTaxiMapID and GetTaxiMapID()
	local nodes = map and C_TaxiMap and C_TaxiMap.GetAllTaxiNodes and C_TaxiMap.GetAllTaxiNodes(map) or {}
	local names = ns.db().catalogue.taxiNodes
	for _, node in ipairs(nodes) do
		if node.nodeID then
			if node.slotIndex then
				bySlot[node.slotIndex] = node.nodeID
			end
			if node.name then
				names[node.nodeID] = Encode.name(node.name)
			end
			if (CURRENT and node.state == CURRENT) or (node.slotIndex and TaxiNodeGetType(node.slotIndex) == "CURRENT") then
				current = node.nodeID
			end
		end
	end
	if not current then
		for slot = 1, NumTaxiNodes() do
			if TaxiNodeGetType(slot) == "CURRENT" then
				current = bySlot[slot] or Encode.name(TaxiNodeName(slot))
			end
		end
	end
	return bySlot, current
end

local function flight(slot)
	local me = ns.me()
	if not me then
		return
	end
	local bySlot, from = taxiNodes()
	local to = bySlot[slot] or Encode.name(TaxiNodeName(slot))
	local cost = TaxiNodeCost(slot) or 0
	ns.append("flight", Encode.row(ns.now(), me.ref, from, to, cost, C_Map.GetBestMapForUnit("player")))
	local total = me.flights or { n = 0, cost = 0 }
	me.flights = total
	total.n = total.n + 1
	total.cost = total.cost + cost
end

if TakeTaxiNode then
	hooksecurefunc("TakeTaxiNode", function(slot)
		ns.safely("flight", flight, slot)
	end)
end
