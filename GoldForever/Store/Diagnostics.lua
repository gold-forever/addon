-- Gold Forever: /gf check's report, for bug reports: which APIs the client offers (db.diag, read at every
-- loading screen), then what the addon has stored and any failures.

local _, ns = ...
local Encode = ns.Encode

local function has(path)
	local value = _G
	for part in string.gmatch(path, "[^.]+") do
		if type(value) ~= "table" then
			return false
		end
		value = value[part]
	end
	return value ~= nil
end

-- Which of the APIs design 002 depends on exist on this client. Booleans only, so the file
-- answers the checklist without recording anything personal.
local function diagnose()
	local db = ns.db()
	local position = false
	if has("C_Map.GetPlayerMapPosition") then
		local map = C_Map.GetBestMapForUnit("player")
		position = map ~= nil and C_Map.GetPlayerMapPosition(map, "player") ~= nil
	end
	db.diag = {
		t = GetServerTime(),
		reloadHook = has("ReloadUI"),
		lootSource = has("GetLootSourceInfo"),
		mapPosition = position,
		tradeSkillUI = has("C_TradeSkillUI.GetAllRecipeIDs"),
		recipeSchematic = has("C_TradeSkillUI.GetRecipeSchematic"),
		container = has("C_Container.GetContainerItemInfo"),
		replicate = has("C_AuctionHouse.ReplicateItems"),
		guildBank = has("GetGuildBankItemInfo"),
		regionName = has("GetCurrentRegionName"),
		professions = has("GetProfessions"),
		skillLines = has("GetSkillLineInfo"),
		merchantInfo = has("C_MerchantFrame.GetItemInfo"),
		itemGUID = has("C_Item.GetItemGUID"),
		missingEvents = #ns.unknownEvents() > 0 and table.concat(ns.unknownEvents(), " ") or nil,
	}
	return db.diag
end

local function checkLines(out)
	local db = ns.db()
	local me = ns.me()
	local diag = diagnose()
	local names = {}
	for name, value in pairs(diag) do
		if type(value) == "boolean" then
			names[#names + 1] = name
		end
	end
	table.sort(names)
	table.insert(out, ns.PREFIX .. " " .. ns.VERSION .. " · schema " .. ns.SCHEMA .. " · " .. db.client.build)
	for _, name in ipairs(names) do
		table.insert(out, string.format("  %s %s", diag[name] and "|cff56c98fyes|r" or "|cffe8615ano|r", name))
	end
	if diag.missingEvents then
		table.insert(out, "  unknown events: " .. diag.missingEvents)
	end
	table.insert(out, "  realm: " .. tostring(me and me.realm) .. " · region: " .. tostring(db.client.region))
end

local function count(stream)
	local rows = 0
	for _, chunk in ipairs(stream or {}) do
		rows = rows + Encode.count(chunk)
	end
	return rows
end

local function size(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

local function statusLines(out)
	local db = ns.db()
	local me = ns.me()
	local today = db.events[Encode.day(GetServerTime())] or {}
	table.insert(out, string.format(
		ns.PREFIX .. ": %d characters · today %d loot, %d positions, %d sys · %d scans · catalogue %d items, %d recipes, %d vendor",
		size(db.characters),
		count(today.loot),
		count(today.pos),
		count(today.sys),
		#db.scans,
		size(db.catalogue.items),
		size(db.catalogue.recipes),
		size(db.catalogue.vendor)
	))
	table.insert(out, string.format("  today %d crafts, %d skill-ups, %d quests, %d money changes, %d flights",
		count(today.craft), count(today.skill), count(today.quest), count(today.money), count(today.flight)))
	if me and me.flights then
		table.insert(out, string.format("  %s: %d paid flights, %s", me.name, me.flights.n, ns.Money.format(me.flights.cost, "icons")))
	end
	for name, e in pairs(db.errors) do
		table.insert(out, string.format("  |cffe8615a%s|r failed %dx - %s", name, e.n, e.msg))
	end
	for name, e in pairs(db.stopped or {}) do
		table.insert(out, string.format("  |cffe8615a%s|r stopped by the client for running too long %dx", name, e.n))
	end
	table.insert(out, "  The file is written at logout and /reload.")
end

-- Read at every loading screen: in the world now, so the position check is meaningful.
ns.module("Diagnostics", {
	requires = { "Store" },
	world = function()
		diagnose()
	end,
})

-- For bug reports: what the client offers, then what the addon has stored and any failures. In chat, and
-- as plain text to copy ("checked": the copy box shows it).
ns.commands.check = function()
	local out = {}
	checkLines(out)
	statusLines(out)
	for i, line in ipairs(out) do
		print(line)
		out[i] = ns.plainText(line)
	end
	ns.emit("checked", table.concat(out, "\n"))
end
