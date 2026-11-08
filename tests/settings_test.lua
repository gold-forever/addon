-- Each feature's settings and their defaults (Core.lua: ns.DEFAULTS, ns.settings): a fresh save gets these
-- tables, pinned as each file asked for them before they were kept in one place (review C-26).

-- Modules.lua and Core.lua on a stand-in client: enough to load them and run their ADDON_LOADED.
local handler
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
SlashCmdList = {}
local ns = {}
loadEncode(ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
assert(load(SOURCES["Modules.lua"], "@Modules.lua"))("GoldForever", ns)
for _, file in ipairs({ "Errors.lua", "Scheduling.lua", "Events.lua", "Chat.lua", "Commands.lua", "Save.lua", "Characters.lua", "Diagnostics.lua", "Core.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
assert(load(SOURCES["Migrations.lua"], "@Migrations.lua"))("GoldForever", ns)
handler(nil, "ADDON_LOADED", "GoldForever")

local function show(v)
	if type(v) ~= "table" then
		return tostring(v)
	end
	local keys = {}
	for k in pairs(v) do
		keys[#keys + 1] = k
	end
	table.sort(keys)
	local out = {}
	for _, k in ipairs(keys) do
		out[#out + 1] = k .. " = " .. show(v[k])
	end
	return "{ " .. table.concat(out, ", ") .. " }"
end

local PINNED = {
	window = "{  }",
	appraiser = "{ recap = true, shown = true }",
	rares = "{ announce = true, mark = true }",
	crafting = "{ strip = true }",
	craftQueue = "{ closed = false }",
	scan = "{ auto = false }",
	prices = "{  }",
	tooltip = "{ bagMark = shift, bagVerdict = shift, bestReward = shift, disenchant = shift, held = shift, mob = shift, payback = shift, price = always, scan = always, starter = shift, supply = shift, vendorResale = always }",
	auction = "{ duration = 2, rule = {  }, sellWide = false }",
	mail = "{ helper = true }",
	minimap = "{ angle = 225, hidden = false }",
	firstRun = "{  }",
	fetch = "{  }",
}
local sections = 0
for name, want in pairs(PINNED) do
	sections = sections + 1
	eq(show(ns.settings(name)), want, name .. ": a fresh save's defaults")
	eq(ns.settings(name) == ns.DEFAULTS[name], false, name .. ": the saved table is not the defaults' own")
end
for name in pairs(ns.DEFAULTS) do
	eq(PINNED[name] ~= nil, true, name .. " is pinned")
end

-- The auction rule is the save's own table too, so a rule set is never written into the defaults.
ns.settings("auction").rule.markup = 5
eq(ns.DEFAULTS.auction.rule.markup, nil, "a nested default is copied")

-- A section saved by an older version gets a default added since; what the player set stays.
ns.db().settings.minimap = { angle = 90 }
eq(show(ns.settings("minimap")), "{ angle = 90, hidden = false }", "a default added later reaches a saved section")

-- The loot advisor is gone (addon#77): no default, and an old save's section stays as it was, unread.
eq(ns.DEFAULTS.advisor, nil, "no loot advisor default")
ns.db().settings.advisor = { shown = false }
for name in pairs(ns.DEFAULTS) do
	ns.settings(name)
end
eq(show(ns.db().settings.advisor), "{ shown = false }", "an old save's advisor section is left alone")

-- The tooltip lines' old on/off switches (addon#98) become their modes at the first read, on is Always and
-- off is Off, and leave prices; a line never switched takes its default; a second read changes nothing.
local function carried(prices)
	ns.db().settings.prices, ns.db().settings.tooltip = prices, nil
	ns.settings("tooltip")
	local p = ns.db().settings.prices
	local t = ns.settings("tooltip")
	return tostring(t.price) .. " " .. tostring(t.held) .. " " .. tostring(p.tooltip) .. " " .. tostring(p.held)
end
eq(carried({ tooltip = true, held = true }), "always always nil nil", "both on: Always")
eq(carried({ tooltip = false, held = false }), "off off nil nil", "both off: Off")
eq(carried({ tooltip = true }), "always shift nil nil", "held never switched: its default")
eq(carried({ bagMark = false }), "always shift nil nil", "neither switched: the defaults")
eq(ns.db().settings.prices.bagMark, false, "the other prices settings stay")
ns.db().settings.tooltip.held = "always"
ns.settings("tooltip")
eq(ns.db().settings.tooltip.held, "always", "read again: a mode set since stays")

-- Defaults given still win over ns.DEFAULTS (a section the tests make).
eq(show(ns.settings("smoke", { a = 1 })), "{ a = 1 }", "defaults given")
return checks()
