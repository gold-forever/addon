-- Gold Forever: the save. Loads GoldForeverDB (design 002) as the Store module, upgrades it through its
-- migrations (Migrations.lua), drops days past the retention window, and holds each feature's settings and
-- the write to today's bucket of a stream.

local _, ns = ...
local Encode = ns.Encode

local db -- GoldForeverDB, once loaded

function ns.db()
	return db
end

-- Each feature's settings section and its defaults, in one place (db.settings[section]).
ns.DEFAULTS = {
	window = {}, -- the look, the accent, the hub's place and its pages' choices
	appraiser = { shown = true }, -- the session HUD
	rares = { announce = true, mark = true },
	crafting = { strip = true }, -- the crafting strip, and the craft queue's recipes
	craftQueue = { closed = false },
	scan = { auto = false },
	prices = {},
	-- Each tooltip line's mode, "off", "shift" (shown while Shift is held) or "always" (Tooltips.lua,
	-- addon#98): the prices and vendor resale always, the rest on Shift.
	tooltip = { price = "always", scan = "always", held = "shift", disenchant = "shift", mob = "shift", starter = "shift",
		bestReward = "shift", bagMark = "shift", vendorResale = "always", supply = "shift" },
	auction = { rule = {}, duration = 2, sellWide = false }, -- sellWide: the Sell tab's wide layout (addon#84)
	mail = { helper = true },
	minimap = { angle = 225, hidden = false },
	firstRun = {},
	fetch = {},
}

-- The price and held-count lines' old on/off switches (prices.tooltip, prices.held) become their modes in
-- settings.tooltip (addon#98): on is Always, off is Off, and the switch goes. A settings change, not a
-- schema one: the server never reads settings. Run at every read, it finds nothing to do after the first.
local CARRIED = { tooltip = "price", held = "held" }
local function carryTooltipSwitches(s)
	local prices = s.prices
	if not prices or (prices.tooltip == nil and prices.held == nil) then
		return
	end
	s.tooltip = s.tooltip or {}
	for from, line in pairs(CARRIED) do
		if prices[from] ~= nil then
			s.tooltip[line] = prices[from] and "always" or "off"
			prices[from] = nil
		end
	end
end

-- A feature's settings table in the saved file, made with its defaults the first time (ns.DEFAULTS
-- unless others are given). A default added in a later version reaches a table saved before it; what the
-- player set stays.
function ns.settings(name, defaults)
	defaults = defaults or ns.DEFAULTS[name]
	local s = ns.db().settings
	if name == "tooltip" then
		carryTooltipSwitches(s)
	end
	if not s[name] then
		s[name] = ns.copy(defaults)
	elseif defaults then
		local saved = s[name]
		for key, value in pairs(defaults) do
			if saved[key] == nil then
				saved[key] = ns.copy(value)
			end
		end
	end
	return s[name]
end

-- Appends a row to today's bucket of a stream.
function ns.append(stream, row)
	local day = Encode.day(GetServerTime())
	db.events[day] = db.events[day] or {}
	local bucket = db.events[day]
	bucket[stream] = bucket[stream] or {}
	Encode.append(bucket[stream], row)
end

-- Setup ------------------------------------------------------------------------------------------

local REGIONS = { "US", "KR", "EU", "TW", "CN" }

-- GetCurrentRegionName returns "" on the Forever client; fall back to the region number.
local function region()
	local name = GetCurrentRegionName and GetCurrentRegionName()
	if name and name ~= "" then
		return name
	end
	local id = GetCurrentRegion and GetCurrentRegion()
	return id and (REGIONS[id] or tostring(id)) or nil
end

-- A call the client stopped for running too long (Errors.lua), counted under db.stopped[name].
local function countStopped(name)
	db.stopped = db.stopped or {}
	local e = db.stopped[name] or { n = 0 }
	e.n, e.t = e.n + 1, GetServerTime and GetServerTime() or 0
	db.stopped[name] = e
end

-- The catalogue's sections, each made when missing.
local CATALOGUE = {
	"items", "recipes", "vendor", "questNames", "taxiNodes", "tooltips", "npcs", "objects", "maps", "trainers",
	"merchants", "currencies", "factions", "legacyPerks", "questStarters", "legacyRewards", "achievements",
	"statistics",
}

-- Every part of the save a module writes into, made when missing; a lean save drops what only Forever keeps.
local function addMissingParts()
	db.fields = db.fields or {}
	for name, columns in pairs(ns.FIELDS) do
		db.fields[name] = columns -- columns only ever grow (design 002, rule 2)
	end
	db.characters = db.characters or {}
	db.events = db.events or {}
	db.scans = db.scans or {}
	db.guildBanks = db.guildBanks or {}
	db.catalogue = db.catalogue or {}
	for _, section in ipairs(CATALOGUE) do
		db.catalogue[section] = db.catalogue[section] or {}
	end
	if ns.lean then
		db.catalogue.tooltips = {}
		db.catalogue.achievements = {}
		db.mapArt = nil
	end
	db.settings = db.settings or { retentionDays = 14, sampleSeconds = 5, share = false }
	db.errors = db.errors or {}
end

local function clientInfo()
	local version, build, _, interface = GetBuildInfo()
	return {
		build = version .. "." .. build,
		interface = interface,
		locale = GetLocale(),
		region = region(),
		regionId = GetCurrentRegion and GetCurrentRegion() or nil,
		portal = GetCVar and GetCVar("portal") or nil,
	}
end

-- Creates or upgrades the saved table: its migrations first (Migrations.lua), then only missing parts are
-- added. A save that cannot be upgraded, or one from a newer version, is left as it is and not loaded.
local function init()
	local upgraded, why = ns.upgrade(GoldForeverDB or {}, ns.SCHEMA, ns.MIGRATIONS, GetServerTime())
	if not upgraded then
		ns.stop(why)
		error(why, 0)
	end
	GoldForeverDB = upgraded
	db = upgraded
	db.schema = ns.SCHEMA
	-- Errors are of the build that recorded them (owner's answer, 2026-10-24): a new version starts with
	-- none, so what the player and the site see is only from the build running.
	if db.addon ~= ns.VERSION then
		db.errors, db.stopped = nil, nil
	end
	db.addon = ns.VERSION
	addMissingParts()
	ns.recordErrorsIn(db.errors, countStopped)
	db.client = clientInfo()
end

-- Drops event days older than the retention window (design 002, Retention). A player who exports keeps
-- the days not yet exported too (an export holds the last one's day on), up to KEEP_MOST days so the file
-- stays under what the site takes. The companion app uploads the whole file and leaves no mark, so
-- without an export the window alone decides.
local KEEP_MOST = 30
local function prune()
	local now = GetServerTime()
	local keep = (db.settings.retentionDays or 14) * 86400
	local cutoff = Encode.day(now - keep)
	if db.exportedAt then
		local exported = Encode.day(math.max(db.exportedAt, now - KEEP_MOST * 86400))
		if exported < cutoff then
			cutoff = exported
		end
	end
	for day in pairs(db.events) do
		if day < cutoff then
			db.events[day] = nil
		end
	end
end

-- The Store: the saved table, loaded and upgraded before any module that requires it starts.
ns.module("Store", {
	init = function()
		init()
		prune()
		ns.emit("ready")
	end,
})
