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

-- The bytes of a value as the client writes it into SavedVariables at a depth: a table one entry a line,
-- indented by tabs, its list part as "value, -- [n]" and the rest as "[key] = value,".
local written
-- The bytes of one entry of a table at a depth whose list part has n entries.
local function entry(key, value, depth, n)
	local bytes = depth + 1 + written(value, depth + 1) + 2
	if type(key) == "number" and key >= 1 and key <= n and key % 1 == 0 then
		return bytes + #tostring(key) + 6
	end
	return bytes + written(key, 0) + 5
end
function written(value, depth)
	local kind = type(value)
	if kind == "string" then
		-- Most strings (every scan row) have nothing to escape: found without the copy gsub makes.
		if not string.find(value, '[\n\r"\\]') then
			return #value + 2
		end
		local _, escapes = string.gsub(value, '[\n\r"\\]', "")
		return #value + escapes + 2
	elseif kind ~= "table" then
		return #tostring(value)
	end
	local bytes, n = 3 + depth, #value
	for key, v in pairs(value) do
		bytes = bytes + entry(key, v, depth, n)
	end
	return bytes
end

-- About how many bytes the save takes on disk ("GoldForeverDB = " and the table): what the companion
-- uploads, which the site takes up to 10 MiB of (gf#402).
function ns.saveSize(db)
	return #"GoldForeverDB = " + written(db, 0) + 1
end

-- About how many bytes db.scans[i] takes of that size.
function ns.scanSize(scans, i)
	return entry(i, scans[i], 1, #scans)
end

-- "45m", "3h", "2d": how long ago `t` was.
local function age(t, now)
	local s = math.max(0, now - (t or now))
	if s < 3600 then
		return math.floor(s / 60) .. "m"
	elseif s < 86400 then
		return math.floor(s / 3600) .. "h"
	end
	return math.floor(s / 86400) .. "d"
end

-- How far the last logout's size guard got (Market.lua): its marker as the load found it.
local LAST_LOGOUT = {
	ran = "ran",
	started = "started but did not finish (the client stopped it)",
	waiting = "did not run (the client stopped a logout listener before it)",
}

-- One line a scan, oldest first as stored, for the size guard (gf#404): what each takes of the save.
local function scanLines(out, db)
	local now = GetServerTime()
	for i, s in ipairs(db.scans) do
		table.insert(out, string.format("  scan %s %s, %s old, %.2f MiB", tostring(s.market),
			s.partial and "partial" or tostring(s.kind), age(s.t, now), ns.scanSize(db.scans, i) / 1048576))
	end
	local last = ns.Scans.lastLogout
	table.insert(out, "  the size guard at the last logout: " .. (LAST_LOGOUT[last] or "no record"))
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
	table.insert(out, string.format("  the save: about %.1f MiB (the site takes up to 10 MiB) · %d old scans dropped this session to keep it under %d MiB",
		ns.saveSize(db) / 1048576, ns.Scans.dropped, ns.Scans.MOST / 1048576))
	scanLines(out, db)
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
