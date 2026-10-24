-- Gold Forever: bags, bank and guild bank contents (design 002, State: characters, guild banks).
-- Items are aggregated per item key; slot positions are never recorded.

local _, ns = ...
local Encode = ns.Encode

-- Container IDs by name from Enum.BagIndex when the client has it, else the classic numbering.
local function containers(patterns, fallback)
	local ids = {}
	if Enum and Enum.BagIndex then
		for name, id in pairs(Enum.BagIndex) do
			for _, pattern in ipairs(patterns) do
				if string.find(name, pattern) then
					ids[#ids + 1] = id
				end
			end
		end
	end
	if #ids == 0 then
		ids = fallback
	end
	table.sort(ids)
	return ids
end

local BAGS = containers({ "^Backpack$", "^Bag_%d+$", "^ReagentBag$" }, { 0, 1, 2, 3, 4 })
local BANK = containers({ "^Bank$", "^BankBag_%d+$", "^CharacterBankTab_%d+$", "^Reagentbank$" }, { -1, 5, 6, 7, 8, 9, 10, 11 })

local function read(ids)
	local counts, used, total = {}, 0, 0
	for _, bag in ipairs(ids) do
		local n = C_Container.GetContainerNumSlots(bag) or 0
		total = total + n
		for slot = 1, n do
			local info = C_Container.GetContainerItemInfo(bag, slot)
			if info then
				used = used + 1
				local key = Encode.itemKey(info.hyperlink) or (info.itemID and tostring(info.itemID))
				if key then
					counts[key] = (counts[key] or 0) + (info.stackCount or 1)
					ns.catalogueItem(key)
				end
			end
		end
	end
	return { used = used, total = total, items = Encode.items(counts), t = ns.now() }
end

-- Pages that show the bags (Home) and redraw when they are read.
local bagsRead = {}
function ns.onBagsRead(fn)
	bagsRead[#bagsRead + 1] = fn
end

local function readBags()
	local me = ns.me()
	if me and not ns.tornDown() then
		local bags = read(BAGS)
		if bags.total > 0 then
			me.bags = bags
			for _, fn in ipairs(bagsRead) do
				ns.safely("bags read", fn)
			end
		end
	end
end

local bankOpen = false

local function readBank()
	local me = ns.me()
	if me and bankOpen then
		local bank = read(BANK)
		if bank.total > 0 then -- 0 slots: the bank's contents are not loaded
			me.bank = bank
		end
	end
end

-- Mail: what waits in the mailbox as last seen, like the bags: items, gold, cash on delivery, how many
-- mails and when the first runs out. Never who sent them or what they say: senders are players.
local function readMail()
	local me = ns.me()
	if not me or not GetInboxNumItems or not GetInboxHeaderInfo then
		return
	end
	local shown, total = GetInboxNumItems()
	local counts, money, cod, expires = {}, 0, 0, nil
	for i = 1, shown or 0 do
		local _, _, _, _, gold, codAmount, daysLeft, itemCount = GetInboxHeaderInfo(i)
		money = money + (gold or 0)
		cod = cod + (codAmount or 0)
		if daysLeft then
			local at = ns.now() + math.floor(daysLeft * 86400)
			expires = expires and math.min(expires, at) or at
		end
		for slot = 1, (itemCount or 0) > 0 and (ATTACHMENTS_MAX_RECEIVE or 16) or 0 do
			local link = GetInboxItemLink and GetInboxItemLink(i, slot)
			local key = link and Encode.itemKey(link)
			if key then
				local count = select(4, GetInboxItem(i, slot))
				counts[key] = (counts[key] or 0) + (count or 1)
				ns.catalogueItem(key)
			end
		end
	end
	me.mail = { used = shown or 0, total = total or shown or 0, items = Encode.items(counts), money = money, cod = cod, expires = expires, t = ns.now() }
end

ns.on("MAIL_INBOX_UPDATE", "mail", ns.throttle("mail", 2, readMail))

local bagsSoon = ns.throttle("bags", 10, readBags)
local bankSoon = ns.throttle("bank", 2, readBank)

ns.on("PLAYER_ENTERING_WORLD", "bags", function()
	ns.after(3, "bags", readBags)
end)
ns.on("BAG_UPDATE_DELAYED", "bags", function()
	bagsSoon()
	if bankOpen then
		bankSoon()
	end
end)
ns.on("PLAYER_LEAVING_WORLD", "bags", readBags)
ns.on("PLAYER_LOGOUT", "bags", readBags)

local function bankOpened()
	bankOpen = true
	ns.after(0.5, "bank", readBank)
end
local function bankClosed()
	readBank()
	bankOpen = false
end
ns.on("BANKFRAME_OPENED", "bank", bankOpened)
ns.on("BANKFRAME_CLOSED", "bank", bankClosed)
ns.on("PLAYERBANKSLOTS_CHANGED", "bank", bankSoon)

-- Guild bank -------------------------------------------------------------------------------------

local SLOTS_PER_TAB = MAX_GUILDBANK_SLOTS_PER_TAB or 98

local function readGuildBank()
	local me = ns.me()
	local guild = GetGuildInfo("player")
	if not me or not guild then
		return
	end
	local key = ns.market(string.lower(me.faction or "?")) .. ":" .. guild
	local banks = ns.db().guildBanks
	local bank = banks[key] or { tabs = {} }
	banks[key] = bank
	local current = GetCurrentGuildBankTab and GetCurrentGuildBankTab()
	for tab = 1, GetNumGuildBankTabs() do
		local name, _, viewable = GetGuildBankTabInfo(tab)
		if viewable then
			local counts, any = {}, false
			for slot = 1, SLOTS_PER_TAB do
				local link = GetGuildBankItemLink(tab, slot)
				if link then
					any = true
					local _, count = GetGuildBankItemInfo(tab, slot)
					local itemKey = Encode.itemKey(link)
					if itemKey then
						counts[itemKey] = (counts[itemKey] or 0) + (count or 1)
						ns.catalogueItem(itemKey)
					end
				end
			end
			-- A tab not yet sent by the server reads empty; keep what an earlier visit saw.
			if any or tab == current then
				bank.tabs[tab] = { name = name, items = Encode.items(counts), t = ns.now() }
			end
		end
	end
	bank.t = ns.now()
end

local guildBankSoon = ns.throttle("guildBank", 1, readGuildBank)

local function guildBankOpened()
	for tab = 1, GetNumGuildBankTabs() do
		local _, _, viewable = GetGuildBankTabInfo(tab)
		if viewable then
			QueryGuildBankTab(tab)
		end
	end
	guildBankSoon()
end

ns.on("GUILDBANKFRAME_OPENED", "guildBank", guildBankOpened)
ns.on("GUILDBANKBAGSLOTS_CHANGED", "guildBank", guildBankSoon)

-- Newer clients open the bank and guild bank through the interaction manager.
local INTERACTION = Enum and Enum.PlayerInteractionType or {}
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", "bank", function(kind)
	if kind == INTERACTION.Banker and not bankOpen then
		bankOpened()
	elseif kind == INTERACTION.GuildBanker then
		guildBankOpened()
	end
end)
ns.on("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", "bank", function(kind)
	if kind == INTERACTION.Banker and bankOpen then
		bankClosed()
	end
end)

-- "Held" in item tooltips (owner's answer, 2026-10-24): how many every character holds, from what the
-- save has of their bags, bank and mail. The index is built again only when one of those changed.
local held, heldStamp
local function stamp()
	local sum, n = 0, 0
	for _, c in pairs(ns.db().characters or {}) do
		n = n + 1
		for _, place in ipairs(ns.Views.PLACES) do
			sum = sum + (c[place] and c[place].t or 0)
		end
	end
	return sum * 1000 + n
end

if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
	-- Defined once and handed the arguments, so a tooltip shown makes no new closure.
	local function heldTooltip(tooltip, data)
		if (tooltip ~= GameTooltip and tooltip ~= ItemRefTooltip) or not data or not data.id or not ns.db() then
			return
		end
		if ns.settings("prices", { tooltip = true }).held == false then
			return
		end
		local now = stamp()
		if not held or heldStamp ~= now then
			held, heldStamp = ns.Views.holdings(ns.db().characters, Encode.parseItems), now
		end
		local line = ns.Views.heldText(held[data.id])
		if line then
			tooltip:AddLine(ns.PREFIX .. " " .. line, 0.8, 0.8, 0.8, true)
		end
	end
	TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, data)
		ns.safely("held tooltip", heldTooltip, tooltip, data)
	end)
end
