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

-- A loot slot as the window holds it: its item, its sources and their amounts, and whether it is coin.
local function readSlot(w, slot)
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
	return info
end

ns.on("LOOT_READY", "loot", function()
	if window then
		return -- LOOT_READY can fire twice for one window
	end
	local w = { t = ns.now(), slots = {}, sources = {}, order = {}, coinFrom = {} }
	w.map, w.x, w.y = ns.position()
	if not w.map then
		w.instanceId = ns.instanceId() -- old raids (Molten Core) have no map: the instance names the place
	end
	w.fish = IsFishingLoot and IsFishingLoot() or nil
	for slot = 1, GetNumLootItems() do
		w.slots[slot] = readSlot(w, slot)
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

-- Windows whose coin was taken and whose rows are not written yet, oldest first. The coin of one
-- loot window can arrive after the next window opened (looting corpse after corpse), and in a group
-- as several rises, one per share. So a rise goes to the oldest window still without coin, else to the
-- newest one, as more of its coin.
local awaitingCoin = {}
local purse -- GetMoney() at the last money change
-- { amount, at, from }: rises in the last second no window was waiting for first, the last at `at`,
-- given to `from` as more of its coin or to none. The next money slot to clear takes them: they can be
-- its coin come before the slot cleared.
local early
local EARLY_SECONDS = 1
-- A rise given to no window is claimed by a money slot cleared, or a window closed with its money slot
-- still showing, up to this long after it: fast auto-loot clears the slot after the close, or late.
local CLAIM_SECONDS = 2

-- Whether a rise now would be taken as a loot window's coin, for the money row's context (Ledger.lua).
function ns.lootCoinDue()
	return #awaitingCoin > 0
end

-- Whether a window closed with its money slot showing has waited too long for a rise to be its coin.
local function claimOver(w)
	return w.claimUntil and not w.coinAt and GetTime() > w.claimUntil
end

local function coinFor()
	local newest
	for _, w in ipairs(awaitingCoin) do
		if not claimOver(w) then
			if not w.coinAt then
				return w
			end
			newest = w
		end
	end
	return newest
end

-- The rise given to no window, if it came at most `seconds` ago; it is then no longer unclaimed.
local function claimUnclaimed(seconds)
	if not (early and not early.from and GetTime() - early.at <= seconds) then
		return nil
	end
	local rise = early
	early = nil
	return rise
end

ns.on("PLAYER_MONEY", "loot coin", function()
	local now = GetMoney()
	local rise = purse and now - purse or 0
	purse = now
	if rise <= 0 then
		return
	end
	local w, at = coinFor(), GetTime()
	if w and not w.coinAt then
		w.coin, w.coinAt = rise, at
		return
	end
	if w then
		w.coin, w.coinAt = w.coin + rise, at
	end
	if early and early.from == w and at - early.at <= EARLY_SECONDS then
		early.amount, early.at = early.amount + rise, at
	else
		early = { amount = rise, at = at, from = w }
	end
end)

ns.on("LOOT_SLOT_CLEARED", "loot", function(slot)
	local info = window and window.slots[slot]
	if not info or info.taken then
		return
	end
	if info.money then
		info.taken = true
		local unclaimed = claimUnclaimed(CLAIM_SECONDS)
		if unclaimed then
			window.coin, window.coinAt = (window.coin or 0) + unclaimed.amount, unclaimed.at
		elseif early and GetTime() - early.at <= EARLY_SECONDS then
			if early.from then
				early.from.coin = early.from.coin - early.amount
			end
			window.coin, window.coinAt = (window.coin or 0) + early.amount, early.at
		end
		early = nil
		if not window.awaiting then
			window.awaiting = true
			awaitingCoin[#awaitingCoin + 1] = window
		end
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

-- Coin: GetMoney() rises a moment after the money slot clears, so the rows are written once the
-- window's coin has settled (above): a second after the window closed or after its last rise, or,
-- while its coin has not come, up to COIN_WAIT_SECONDS; and in the order the windows closed. It goes
-- to the money slot's sources (by their amounts when the client gives them), else to every source. In
-- a group the rise is this character's share, not the slot's amount.
local SETTLE_SECONDS = 1
local COIN_WAIT_SECONDS = 5
local closing = {} -- windows closed and not written yet, oldest first

-- A window closed with its money slot showing: fast auto-loot clears it after the close, so the rise
-- given to no window just before is its coin, else the next one within CLAIM_SECONDS.
local function awaitLateCoin(w)
	local unclaimed = claimUnclaimed(CLAIM_SECONDS)
	if unclaimed then
		w.coin, w.coinAt = unclaimed.amount, unclaimed.at
	end
	w.claimUntil = GetTime() + CLAIM_SECONDS
	w.awaiting = true
	awaitingCoin[#awaitingCoin + 1] = w
end

local function moneyShowing(w)
	for _, info in pairs(w.slots) do
		if info.money and not info.taken then
			return true
		end
	end
	return false
end

local function stopAwaiting(w)
	for i, waiting in ipairs(awaitingCoin) do
		if waiting == w then
			table.remove(awaitingCoin, i)
			return
		end
	end
end

-- The window's coin by source: to the money slot's sources by their amounts, else evenly to every source.
local function coinShares(w, coin)
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
	return shares
end

-- Whether this is the first loot of a spawn; an item opened or a source unknown always is.
local function firstLoot(guid)
	if guid == "?" or string.find(guid, "^Item%-") then
		return true
	end
	local first = not seen[guid] or nil
	seen[guid] = true
	return first
end

-- Every item the window gave, from all its sources.
local function itemsTaken(w)
	local taken = {}
	for _, guid in ipairs(w.order) do
		for key, n in pairs(w.sources[guid].items) do
			taken[key] = (taken[key] or 0) + n
		end
	end
	return taken
end

local function finish(w)
	stopAwaiting(w)
	local me = ns.me()
	if not me then
		return
	end
	local coin = w.coin or 0
	local shares = coinShares(w, coin)
	local rows = {}
	for _, guid in ipairs(w.order) do
		local first = firstLoot(guid)
		local items = w.sources[guid].items
		for key in pairs(items) do
			ns.catalogueItem(key)
		end
		local src = w.sources[guid].src or sourceOf(guid)
		ns.record("loot", { t = w.t, char = me.ref, map = w.map, x = w.x, y = w.y, src = src, first = first, coin = shares[guid] or 0, items = Encode.items(items), fish = w.fish, instanceId = w.instanceId })
		-- guid and first stay in memory, for the session HUD's kill count; the row saved is the one above.
		rows[#rows + 1] = { src = src, coin = shares[guid] or 0, items = items, guid = guid, first = first }
	end
	lastLoot = GetTime()
	-- The loot window as a whole, for whoever listens (the appraiser): coin and every item taken.
	local taken = itemsTaken(w)
	for _, listener in ipairs(ns.lootListeners) do
		ns.safely("loot listener", listener, coin, taken, rows)
	end
end

ns.on("LOOT_CLOSED", "loot", function()
	local w = window
	window = nil
	ns.lootAt = GetTime() -- coin arrives a moment after the window closes
	if not w then
		return
	end
	if not w.awaiting and moneyShowing(w) then
		awaitLateCoin(w)
	end
	closing[#closing + 1] = w
	local closed = GetTime()
	local function settle()
		local now = GetTime()
		local coinDue = w.awaiting and not w.coinAt and not claimOver(w) and now - closed < COIN_WAIT_SECONDS
		local coinComing = w.coinAt and now - w.coinAt < SETTLE_SECONDS
		if coinDue or coinComing then
			ns.after(SETTLE_SECONDS, "loot", settle)
			return
		end
		w.settled = true
		while closing[1] and closing[1].settled do
			finish(table.remove(closing, 1))
		end
	end
	ns.after(SETTLE_SECONDS, "loot", settle)
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
