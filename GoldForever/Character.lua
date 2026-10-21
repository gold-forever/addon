-- Gold Forever: the rest of a character's own state — currencies, reputations and equipped gear.
-- Names of currencies and factions go into the catalogue.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.currency = "name"
ns.FIELDS.faction = "name"

local function readCurrencies()
	local me = ns.me()
	if not me or not (C_CurrencyInfo and C_CurrencyInfo.GetCurrencyListSize) then
		return
	end
	local names = ns.db().catalogue.currencies
	-- The list shows only what is under an open header: a currency under a closed one keeps the
	-- amount read last, instead of dropping out of the file.
	local amounts = {}
	for key, n in pairs(Encode.parseItems(me.currencies and me.currencies.items)) do
		amounts[tostring(key)] = n
	end
	for i = 1, C_CurrencyInfo.GetCurrencyListSize() do
		local info = C_CurrencyInfo.GetCurrencyListInfo(i)
		local link = C_CurrencyInfo.GetCurrencyListLink and C_CurrencyInfo.GetCurrencyListLink(i)
		local id = link and tonumber(string.match(link, "currency:(%d+)"))
		if info and not info.isHeader and id then
			amounts[tostring(id)] = info.quantity or 0
			names[id] = Encode.name(info.name or "?")
		end
	end
	-- "id*amount" like an item list; zero amounts kept as "id*0" would break the item-list
	-- format, so they are left out.
	for id, n in pairs(amounts) do
		if n <= 0 then
			amounts[id] = nil
		end
	end
	me.currencies = { items = Encode.items(amounts), t = ns.now() }
end

local function readReputation()
	local me = ns.me()
	if not me then
		return
	end
	local names = ns.db().catalogue.factions
	-- As with currencies: a faction under a closed header keeps its standing read last.
	local byFaction, order = {}, {}
	local function keep(id, text)
		if not byFaction[id] then
			order[#order + 1] = id
		end
		byFaction[id] = text
	end
	for entry in string.gmatch((me.reputation and me.reputation.factions) or "", "[^+]+") do
		local id = tonumber(string.match(entry, "^(%d+):"))
		if id then
			keep(id, entry)
		end
	end
	local standing = {}
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		for i = 1, C_Reputation.GetNumFactions() do
			local f = C_Reputation.GetFactionDataByIndex(i)
			if f and f.factionID and f.factionID ~= 0 and (not f.isHeader or f.isHeaderWithRep) then
				standing[#standing + 1] = f.factionID .. ":" .. (f.reaction or "") .. ":" .. (f.currentStanding or "")
				names[f.factionID] = Encode.name(f.name or "?")
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local name, _, reaction, _, _, value, _, _, isHeader, _, hasRep, _, _, id = GetFactionInfo(i)
			if id and (not isHeader or hasRep) then
				standing[#standing + 1] = id .. ":" .. (reaction or "") .. ":" .. (value or "")
				names[id] = Encode.name(name or "?")
			end
		end
	end
	for _, entry in ipairs(standing) do
		keep(tonumber(string.match(entry, "^(%d+):")), entry)
	end
	local merged = {}
	for _, id in ipairs(order) do
		merged[#merged + 1] = byFaction[id]
	end
	-- factionID:reaction:value, joined with "+"; reaction 1 hated … 8 exalted.
	me.reputation = { factions = table.concat(merged, "+"), t = ns.now() }
end

local function readGear()
	local me = ns.me()
	if not me then
		return
	end
	local gear = {}
	for slot = 1, 19 do
		local key = Encode.itemKey(GetInventoryItemLink("player", slot))
		if key then
			gear[slot] = key
			ns.catalogueItem(key)
		end
	end
	gear.t = ns.now()
	me.gear = gear
end

local function readAll()
	ns.safely("currencies", readCurrencies)
	ns.safely("reputation", readReputation)
	ns.safely("gear", readGear)
end

ns.on("PLAYER_ENTERING_WORLD", "character", function()
	ns.after(4, "character", readAll)
end)
ns.on("CURRENCY_DISPLAY_UPDATE", "currencies", ns.throttle("currencies", 10, readCurrencies))
ns.on("UPDATE_FACTION", "reputation", ns.throttle("reputation", 10, readReputation))
ns.on("PLAYER_EQUIPMENT_CHANGED", "gear", ns.throttle("gear", 5, readGear))

