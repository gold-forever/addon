-- Each feature's settings and their defaults (Core.lua: ns.DEFAULTS, ns.settings): a fresh save gets these
-- tables, pinned as each file asked for them before they were kept in one place (review C-26).

-- Core.lua on a stand-in client: enough to load it and run its ADDON_LOADED.
local handler
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
SlashCmdList = {}
local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
assert(load(SOURCES["Core.lua"], "@Core.lua"))("GoldForever", ns)
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
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
	appraiser = "{ shown = true }",
	advisor = "{ shown = true }",
	rares = "{ announce = true, mark = true }",
	crafting = "{ strip = true }",
	craftQueue = "{ closed = false }",
	scan = "{ auto = false }",
	prices = "{ tooltip = true }",
	auction = "{ duration = 2, rule = {  } }",
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

-- Defaults given still win over ns.DEFAULTS (a section the tests make).
eq(show(ns.settings("smoke", { a = 1 })), "{ a = 1 }", "defaults given")
return checks()
