-- ns.module (Kernel/Modules.lua): each module's init runs once the addon has loaded and its enable once the
-- player has logged in, after the modules it requires whatever order the files declared them in; a failing,
-- missing or circular module is recorded, not raised, and the others still start.

-- Modules.lua, Core.lua and Schema.lua on a stand-in client: enough to load them and run their ADDON_LOADED
-- and PLAYER_LOGIN.
local handler
local said = {}
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
function print(text) said[#said + 1] = text end
unpack = table.unpack
SlashCmdList = {}
local ns = {}
assert(load(SOURCES["Encode.lua"], "@Encode.lua"))("GoldForever", ns)
assert(load(SOURCES["Realms.lua"], "@Realms.lua"))("GoldForever", ns)
assert(load(SOURCES["Modules.lua"], "@Modules.lua"))("GoldForever", ns)
assert(load(SOURCES["Core.lua"], "@Core.lua"))("GoldForever", ns)
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)

local ran = {}
local function step(what)
	return function()
		ran[#ran + 1] = what
	end
end
ns.module("Late", { requires = { "Early" }, init = step("init Late"), enable = step("enable Late") })
ns.module("Early", { init = step("init Early"), enable = step("enable Early") })
ns.module("Early", { init = step("init Early again") })
ns.module("Broken", { init = function() error("boom") end, enable = step("enable Broken") })
ns.module("AfterBroken", { requires = { "Broken" }, init = step("init AfterBroken"), enable = step("enable AfterBroken") })
ns.module("Lonely", { requires = { "Nowhere" }, init = step("init Lonely") })
ns.module("Ping", { requires = { "Pong" }, init = step("init Ping") })
ns.module("Pong", { requires = { "Ping" }, init = step("init Pong") })
ns.module("Echo", { requires = { "Ping" }, init = step("init Echo") })
ns.module("Free", { enable = step("enable Free") })

eq(#ran, 0, "nothing starts while the files load")
handler(nil, "ADDON_LOADED", "GoldForever")
eq(table.concat(ran, ", "), "init Early, init Late", "each init once the addon has loaded, after the modules it requires")
handler(nil, "PLAYER_LOGIN")
eq(table.concat(ran, ", "), "init Early, init Late, enable Early, enable Late, enable Free", "each enable once the player has logged in, in the same order")

local errors = GoldForeverDB.errors
eq(errors.Early and errors.Early.msg, "module declared twice", "a module declared twice is recorded, the first kept")
eq(errors.Broken and errors.Broken.msg:find("boom") ~= nil, true, "a failing init is recorded")
eq(errors.AfterBroken and errors.AfterBroken.msg, "requires Broken, which failed", "a module that requires a failed one does not start")
eq(errors.Lonely and errors.Lonely.msg, "requires Nowhere, which no module declares", "a missing requirement is recorded")
eq(errors.Ping and errors.Ping.msg, "requires Pong, which requires it in turn", "a cycle is recorded")
eq(errors.Pong and errors.Pong.msg, "requires Ping, which requires it in turn", "each module in a cycle")
eq(errors.Echo and errors.Echo.msg, "requires Ping, which cannot start", "a module that requires one in a cycle does not start")
eq(errors.Late or errors.Free, nil, "the modules that start record no error")

-- Modules set themselves up through ns.module: these files still do on PLAYER_LOGIN or
-- PLAYER_ENTERING_WORLD; the list only shrinks. A file that moves leaves it, and a new one fails here.
local KNOWN = {
	"Achievements.lua",
	"Catalogue.lua",
	"Character.lua",
	"Core.lua",
	"CraftQueue.lua",
	"FirstRun.lua",
	"Inventory.lua",
	"Knowledge.lua",
	"Ledger.lua",
	"Legacy.lua",
	"Levelling.lua",
	"Lists.lua",
	"Looks.lua",
	"Loot.lua",
	"Market.lua",
	"Minimap.lua",
	"MobStats.lua",
	"Prices.lua",
	"Professions.lua",
	"Session.lua",
}
local onLogin = {}
for file, source in pairs(SOURCES) do
	if source:find('"PLAYER_LOGIN"', 1, true) or source:find('"PLAYER_ENTERING_WORLD"', 1, true) then
		onLogin[#onLogin + 1] = file
	end
end
table.sort(onLogin)
eq(table.concat(onLogin, ", "), table.concat(KNOWN, ", "), "the files that set themselves up on PLAYER_LOGIN or PLAYER_ENTERING_WORLD")
return checks()
