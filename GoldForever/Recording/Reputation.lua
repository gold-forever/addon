-- Gold Forever: every reputation gain or loss (`rep` rows), with the standing after it, so the web app can
-- show a faction's progress over time; Character.lua keeps only the standings now.

local _, ns = ...
local Encode = ns.Encode

local SETTLE = 3 -- seconds for a message and the standings it changed to arrive, in either order

-- "Reputation with Stormwind increased by 250.", as patterns from the client's own text, each with the
-- sign of its delta. Retail tells a warband faction's change in its own words.
local CHANGES = {
	{ FACTION_STANDING_INCREASED or "Reputation with %s increased by %d.", 1 },
	{ FACTION_STANDING_DECREASED or "Reputation with %s decreased by %d.", -1 },
}
if ns.retail then
	CHANGES[#CHANGES + 1] = { FACTION_STANDING_INCREASED_ACCOUNT_WIDE or "Your Warband's reputation with %s increased by %d.", 1 }
	CHANGES[#CHANGES + 1] = { FACTION_STANDING_DECREASED_ACCOUNT_WIDE or "Your Warband's reputation with %s decreased by %d.", -1 }
end
for _, change in ipairs(CHANGES) do
	change[1] = Encode.pattern(change[1])
end

-- The factions the reputation list shows, by ID: { name, standing }, standing nil for a renown faction (its
-- standing does not move; its renown does). A faction under a closed header is not shown.
local function readFactions()
	local out = {}
	if C_Reputation and C_Reputation.GetNumFactions and C_Reputation.GetFactionDataByIndex then
		local major = C_Reputation.IsMajorFaction
		for i = 1, C_Reputation.GetNumFactions() do
			local f = C_Reputation.GetFactionDataByIndex(i)
			if f and f.factionID and f.factionID ~= 0 and (not f.isHeader or f.isHeaderWithRep) then
				local renown = major and major(f.factionID)
				out[f.factionID] = { name = f.name, standing = not renown and f.currentStanding or nil }
			end
		end
	elseif GetNumFactions and GetFactionInfo then
		for i = 1, GetNumFactions() do
			local name, _, _, _, _, value, _, _, isHeader, _, hasRep, _, _, id = GetFactionInfo(i)
			if id and (not isHeader or hasRep) then
				out[id] = { name = name, standing = value }
			end
		end
	end
	return out
end

local last -- the standings at the last reading, by faction ID; nil before the first
local told = {} -- changes the client told since: { name, delta }, in order
local pending = false

-- A faction's ID by its name: in the list, else in the catalogue (a faction under a closed header).
local function factionId(name, factions)
	for id, f in pairs(factions) do
		if f.name == name then
			return id
		end
	end
	for id, known in pairs(ns.db().catalogue.factions) do
		if known == Encode.name(name) then
			return id
		end
	end
end

-- The rows since the last reading: each change told (its delta from the message), then each faction
-- whose standing moved with nothing told of it (a message kept secret). Changes told of one faction share
-- its standing now, each row the standing after it.
local function changes(factions)
	local rows, byFaction = {}, {}
	for _, change in ipairs(told) do
		local id = factionId(change.name, factions)
		if id then
			local row = { faction = id, delta = change.delta }
			rows[#rows + 1] = row
			byFaction[id] = byFaction[id] or {}
			table.insert(byFaction[id], row)
		end
	end
	for id, list in pairs(byFaction) do
		local standing = factions[id] and factions[id].standing
		for i = #list, 1, -1 do
			list[i].standing = standing
			standing = standing and standing - list[i].delta
		end
	end
	for id, f in pairs(factions) do
		local before = last and last[id]
		if not byFaction[id] and f.standing and before and f.standing ~= before then
			rows[#rows + 1] = { faction = id, delta = f.standing - before, standing = f.standing }
		end
	end
	return rows
end

local function settle()
	pending = false
	local me = ns.me()
	local factions = readFactions()
	if me then
		local t, map = ns.now(), ns.position()
		for _, row in ipairs(changes(factions)) do
			row.t, row.char, row.map = t, me.ref, map
			ns.record("rep", row)
		end
	end
	-- A faction no longer shown (its header closed) keeps its standing for when it shows again.
	last = last or {}
	for id, f in pairs(factions) do
		last[id] = f.standing
	end
	told = {}
end

local function later()
	if not pending then
		pending = true
		ns.after(SETTLE, "reputation", settle)
	end
end

ns.on("CHAT_MSG_COMBAT_FACTION_CHANGE", "reputation", function(message)
	if ns.secret(message) then
		later()
		return
	end
	for _, change in ipairs(CHANGES) do
		local name, delta = string.match(message or "", change[1])
		if delta then
			told[#told + 1] = { name = name, delta = change[2] * tonumber(delta) }
			break
		end
	end
	later()
end)
ns.on("UPDATE_FACTION", "reputation", later)

-- The standings at the first loading screen are where the changes start.
ns.module("Reputation", {
	requires = { "Store" },
	world = function()
		if not last then
			ns.safely("reputation", settle)
		end
	end,
})
