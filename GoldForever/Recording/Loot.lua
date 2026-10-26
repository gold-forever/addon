-- Gold Forever: loot and farming positions (design 002, Stream: events).
--
-- One loot row per source per loot window: the items actually taken and the coin, split over the
-- window's sources. Positions are sampled only while farming: from a loot until 15 minutes after
-- the last one.

local _, ns = ...
local Encode = ns.Encode

local FARMING_SECONDS = 15 * 60 -- the frontend's idle split
local ITEM_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Item or 1
local MONEY_SLOT = Enum and Enum.LootSlotType and Enum.LootSlotType.Money or 2

-- Called with (coin, { [itemKey] = count }, rows) after every loot window, rows one per source:
-- { src, coin, items = { [itemKey] = count } }; see Session.lua.
ns.lootListeners = {}

local window -- the open loot window
local seen = {} -- spawn GUIDs looted this session, for `first`; never written
local opened -- { id, at }: the container item last used, for `i<itemId>` sources
local lastLoot -- GetTime() of the last loot, while farming

-- Map position of the player, coordinates empty in instances.
function ns.position()
	local map = C_Map.GetBestMapForUnit("player")
	if not map then
		return nil
	end
	local p = C_Map.GetPlayerMapPosition(map, "player")
	local x, y
	if p then
		x, y = p:GetXY()
	end
	if not x or (x == 0 and y == 0) then
		return map
	end
	return map, Encode.coord(x), Encode.coord(y)
end

-- Item ID behind an Item GUID: the container being opened, still in the bags while its loot shows.
local function itemOf(guid)
	if C_Item and C_Item.GetItemGUID and ItemLocation then
		for bag = 0, (NUM_BAG_SLOTS or 4) + 1 do
			for slot = 1, C_Container.GetContainerNumSlots(bag) or 0 do
				local location = ItemLocation:CreateFromBagAndSlot(bag, slot)
				if location:IsValid() and C_Item.GetItemGUID(location) == guid then
					return C_Item.GetItemID(location)
				end
			end
		end
	end
	if opened and GetTime() - opened.at < 5 then
		return opened.id
	end
	return nil
end

local function sourceOf(guid)
	local src = Encode.source(guid)
	if src then
		return src
	end
	if guid == "?" or string.find(guid, "^Item%-") then
		local id = itemOf(guid)
		if id then
			return "i" .. id
		end
	end
	-- Not in design 002's source kinds yet; recorded raw so the parser can learn it.
	if guid == "?" and IsFishingLoot and IsFishingLoot() then
		return "fishing"
	end
	return ""
end

local function addSource(w, guid)
	if not w.sources[guid] then
		w.sources[guid] = { items = {} }
		w.order[#w.order + 1] = guid
	end
end

ns.on("LOOT_READY", "loot", function()
	if window then
		return -- LOOT_READY can fire twice for one window
	end
	local w = { t = ns.now(), slots = {}, sources = {}, order = {}, coinFrom = {} }
	w.map, w.x, w.y = ns.position()
	w.fish = IsFishingLoot and IsFishingLoot() or nil
	for slot = 1, GetNumLootItems() do
		local kind = GetLootSlotType(slot)
		local _, _, quantity, _, _, _, _, questID = GetLootSlotInfo(slot)
		local info = { sources = {} }
		if kind == ITEM_SLOT then
			info.key = Encode.itemKey(GetLootSlotLink(slot))
			-- An item that starts a quest: kept by item, for the mob tooltips and the loot alert.
			local item = Encode.itemId(info.key)
			if item and questID and questID > 0 then
				ns.db().catalogue.questStarters[item] = questID
			end
		end
		local list = { GetLootSourceInfo(slot) }
		for i = 1, #list, 2 do
			local guid = list[i]
			if guid then
				addSource(w, guid)
				info.sources[#info.sources + 1] = { guid = guid, n = list[i + 1] or quantity }
			end
		end
		if #info.sources == 0 then
			addSource(w, "?")
			info.sources[1] = { guid = "?", n = quantity }
		end
		if kind == MONEY_SLOT then
			info.money = true
			for _, s in ipairs(info.sources) do
				w.coinFrom[s.guid] = (w.coinFrom[s.guid] or 0) + (tonumber(s.n) or 0)
			end
		end
		w.slots[slot] = info
	end
	-- Resolve item and unknown sources now, while the container is in the bags and the window open.
	for _, guid in ipairs(w.order) do
		if guid == "?" or string.find(guid, "^Item%-") then
			w.sources[guid].src = sourceOf(guid)
		end
	end
	window = w
	ns.lootAt = GetTime()
	local first = w.order[1]
	ns.lootSource = first and (w.sources[first].src or sourceOf(first)) or nil -- for skill-ups from gathering
end)

-- Windows whose coin was taken and has not reached the purse yet, oldest first. The coin of one
-- loot window can arrive after the next window opened (looting corpse after corpse), so each rise
-- in money goes to the oldest window waiting, never to whichever window is open.
local awaitingCoin = {}
local purse -- GetMoney() at the last money change
local early -- { amount, at }: a rise that came before its money slot cleared, for a second
local EARLY_SECONDS = 1

ns.on("PLAYER_MONEY", "loot coin", function()
	local now = GetMoney()
	local rise = purse and now - purse or 0
	purse = now
	if rise <= 0 then
		return
	end
	if #awaitingCoin > 0 then
		local w = table.remove(awaitingCoin, 1)
		w.coin = (w.coin or 0) + rise
	else
		early = { amount = rise, at = GetTime() }
	end
end)

ns.on("LOOT_SLOT_CLEARED", "loot", function(slot)
	local info = window and window.slots[slot]
	if not info or info.taken then
		return
	end
	if info.money then
		info.taken = true
		if early and GetTime() - early.at <= EARLY_SECONDS then
			window.coin = (window.coin or 0) + early.amount
		else
			awaitingCoin[#awaitingCoin + 1] = window
		end
		early = nil
		return
	end
	if not info.key then
		return
	end
	info.taken = true
	for _, s in ipairs(info.sources) do
		local items = window.sources[s.guid].items
		items[info.key] = (items[info.key] or 0) + (tonumber(s.n) or 1)
	end
end)

-- Coin: GetMoney() rises a moment after the money slot clears, so the rows are written a second
-- after the window closes, with the rise the window was given (above). It goes to the money slot's
-- sources (by their amounts when the client gives them), else to every source. In a group the rise
-- is this character's share, not the slot's amount.
local function finish(w)
	for i, waiting in ipairs(awaitingCoin) do
		if waiting == w then
			table.remove(awaitingCoin, i) -- its coin never came
			break
		end
	end
	local me = ns.me()
	if not me then
		return
	end
	local coin = w.coin or 0
	local takers, weights = {}, {}
	for _, guid in ipairs(w.order) do
		if w.coinFrom[guid] then
			takers[#takers + 1] = guid
			weights[#weights + 1] = w.coinFrom[guid]
		end
	end
	if #takers == 0 then
		for i, guid in ipairs(w.order) do
			takers[i], weights[i] = guid, 0
		end
	end
	local shares = {}
	if #takers > 0 then
		for i, part in ipairs(Encode.split(coin, weights)) do
			shares[takers[i]] = part
		end
	end
	local rows = {}
	for _, guid in ipairs(w.order) do
		local first = nil
		if guid ~= "?" and not string.find(guid, "^Item%-") then
			first = not seen[guid] or nil
			seen[guid] = true
		else
			first = true
		end
		local items = w.sources[guid].items
		for key in pairs(items) do
			ns.catalogueItem(key)
		end
		local src = w.sources[guid].src or sourceOf(guid)
		ns.record("loot", { t = w.t, char = me.ref, map = w.map, x = w.x, y = w.y, src = src, first = first, coin = shares[guid] or 0, items = Encode.items(items), fish = w.fish })
		-- guid and first stay in memory, for the session HUD's kill count; the row saved is the one above.
		rows[#rows + 1] = { src = src, coin = shares[guid] or 0, items = items, guid = guid, first = first }
	end
	lastLoot = GetTime()
	-- The loot window as a whole, for whoever listens (the appraiser): coin and every item taken.
	local taken = {}
	for _, guid in ipairs(w.order) do
		for key, n in pairs(w.sources[guid].items) do
			taken[key] = (taken[key] or 0) + n
		end
	end
	for _, listener in ipairs(ns.lootListeners) do
		ns.safely("loot listener", listener, coin, taken, rows)
	end
end

ns.on("LOOT_CLOSED", "loot", function()
	local w = window
	window = nil
	ns.lootAt = GetTime() -- coin arrives a moment after the window closes
	if w then
		ns.after(1, "loot", function()
			finish(w)
		end)
	end
end)

-- Remember which container item was used, for loot whose source is an Item GUID.
local function used(bag, slot)
	local id = C_Container.GetContainerItemID(bag, slot)
	if id then
		opened = { id = id, at = GetTime() }
	end
end
if C_Container and C_Container.UseContainerItem then
	hooksecurefunc(C_Container, "UseContainerItem", used)
end
if UseContainerItem then
	hooksecurefunc("UseContainerItem", used)
end

-- Positions ----------------------------------------------------------------------------------------

local last -- previous sample, skipped when unchanged

local function sample()
	local me = ns.me()
	if not me or not lastLoot or GetTime() - lastLoot > FARMING_SECONDS then
		return
	end
	if IsResting() or (IsFlying and IsFlying()) or UnitOnTaxi("player") or UnitIsDeadOrGhost("player") then
		return
	end
	local map, x, y = ns.position()
	if not x then
		return
	end
	local here = map .. "," .. x .. "," .. y
	if here == last then
		return
	end
	last = here
	ns.record("pos", { t = ns.now(), char = me.ref, map = map, x = x, y = y })
end

ns.module("Loot", {
	requires = { "Store" },
	enable = function()
		C_Timer.NewTicker(ns.db().settings.sampleSeconds or 5, function()
			ns.safely("positions", sample)
		end)
	end,
	-- The money a coin loot is measured from is taken again after every loading screen.
	world = function()
		purse = GetMoney()
	end,
})
