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
	local amounts = {}
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
	-- factionID:reaction:value, joined with "+"; reaction 1 hated … 8 exalted.
	me.reputation = { factions = table.concat(standing, "+"), t = ns.now() }
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

-- Names: on Forever a character has two names, and UnitName gives only the first. Until the API
-- for the second is known, every candidate is kept (me.names), with the names of client functions
-- that sound like one (db.client.nameApis; listed, never called).
local function readNames()
	local me = ns.me()
	if not me then
		return
	end
	local names = {}
	local function try(key, fn, ...)
		local ok, a, b = pcall(fn, ...)
		if ok and a ~= nil then
			names[key] = tostring(a) .. (b ~= nil and (" | " .. tostring(b)) or "")
		end
	end
	try("unit", UnitName, "player")
	if UnitFullName then try("full", UnitFullName, "player") end
	if GetUnitName then try("realmName", GetUnitName, "player", true) end
	if UnitPVPName then try("pvp", UnitPVPName, "player") end
	if C_TooltipInfo and C_TooltipInfo.GetUnit then
		try("tooltip", function()
			local data = C_TooltipInfo.GetUnit("player")
			local lines = {}
			for i = 1, math.min(3, data and data.lines and #data.lines or 0) do
				lines[i] = data.lines[i].leftText or ""
			end
			return table.concat(lines, " / ")
		end)
	end
	me.names = names

	local apis = {}
	for space, t in pairs(_G) do
		if type(space) == "string" and string.find(space, "^C_") and type(t) == "table" then
			for fn in pairs(t) do
				local lower = type(fn) == "string" and string.lower(fn) or ""
				if string.find(lower, "surname") or string.find(lower, "lastname") or string.find(lower, "fullname")
					or string.find(lower, "familyname") or string.find(lower, "secondname") or string.find(lower, "charactername") then
					apis[#apis + 1] = space .. "." .. fn
				end
			end
		end
	end
	table.sort(apis)
	ns.db().client.nameApis = table.concat(apis, ",")
end

ns.on("PLAYER_ENTERING_WORLD", "names", function()
	ns.after(2, "names", readNames)
end)
