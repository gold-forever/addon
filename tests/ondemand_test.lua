-- The auction house panel is an addon of its own, GoldForever_Auctions, which the core loads when the
-- auction house opens (Kernel/OnDemand.lua): once, out of combat, its files given the core's namespace and
-- its modules started at once. Nothing in the core needs it loaded: no core file reads a name only it sets.

-- Modules.lua, Errors.lua, Events.lua, Combat.lua and OnDemand.lua on a stand-in client.
local handler
function GetTime() return 100 end
function GetServerTime() return 1761148800 end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
local function fire(event, ...)
	handler(nil, event, ...)
end

local ns = { say = function() end, stopped = function() return false end }
for _, file in ipairs({ "Modules.lua", "Errors.lua", "Events.lua", "Combat.lua", "OnDemand.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
local errors = {}
ns.recordErrorsIn(errors, {})
ns.startModules("init")
ns.startModules("enable")

-- The client's loader: GoldForever_Auctions runs its first file (Namespace.lua) and a module of its own.
local loaded, started = {}, {}
local refusal = { GoldForever_Off = "DISABLED", GoldForever_Gone = "MISSING" }
C_AddOns = {
	LoadAddOn = function(addon)
		loaded[#loaded + 1] = addon
		if refusal[addon] then
			return false, refusal[addon]
		end
		local own = {}
		assert(load(SOURCES["Namespace.lua"], "@Namespace.lua"))(addon, own)
		own.module(addon, { enable = function() started[#started + 1] = addon end })
		own.seen = own.ah
		return true
	end,
}

ns.ah = { state = true }
ns.loadOnDemand("GoldForever_Auctions")
eq(table.concat(loaded, ", "), "GoldForever_Auctions", "loaded when asked")
eq(table.concat(started, ", "), "GoldForever_Auctions", "its modules start at once")
eq(ns.seen, ns.ah, "its files read and set the core's namespace")
eq(GoldForever_Core, nil, "the core's namespace is handed over only while it loads")
ns.loadOnDemand("GoldForever_Auctions")
eq(#loaded, 1, "once")

fire("PLAYER_REGEN_DISABLED")
ns.loadOnDemand("GoldForever_Later")
ns.loadOnDemand("GoldForever_Later")
eq(#loaded, 1, "not in combat")
fire("PLAYER_REGEN_ENABLED")
eq(table.concat(loaded, ", "), "GoldForever_Auctions, GoldForever_Later", "once the fight ends, once however often asked")

ns.loadOnDemand("GoldForever_Off")
ns.loadOnDemand("GoldForever_Gone")
eq(errors["load GoldForever_Off"], nil, "one turned off in the AddOns list is not an error")
eq(errors["load GoldForever_Gone"] and errors["load GoldForever_Gone"].msg, "not loaded: MISSING", "one the client cannot load is recorded")

-- The core needs nothing of GoldForever_Auctions: every name a core file reads on ns is set by a core file.
local coreSets = {}
for file, source in pairs(SOURCES) do
	if ADDON[file] == "GoldForever" then
		for name in pairs(select(2, nsNames(source))) do
			coreSets[name] = true
		end
	end
end
local moved = 0
for file, source in pairs(SOURCES) do
	if ADDON[file] == "GoldForever" then
		for name, line in pairs((nsNames(source))) do
			eq(coreSets[name], true, "ns." .. name .. " read at " .. file .. ":" .. line .. " is set in the core, not only in GoldForever_Auctions")
		end
	else
		moved = moved + 1
	end
end
eq(moved > 0, true, "GoldForever_Auctions has files")
return checks()
