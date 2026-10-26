-- ns.module (Kernel/Modules.lua): each module's init runs once the addon has loaded, its enable once the
-- player has logged in and its world on every loading screen, after the modules it requires whatever order
-- the files declared them in; a failing, missing or circular module is recorded, not raised, and the others
-- still start.

-- Modules.lua, Core.lua, Schema.lua and Migrations.lua on a stand-in client: enough to load them and run their ADDON_LOADED
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
for _, file in ipairs({ "Errors.lua", "Events.lua", "Chat.lua", "Commands.lua", "Core.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["Schema.lua"], "@Schema.lua"))("GoldForever", ns)
assert(load(SOURCES["Migrations.lua"], "@Migrations.lua"))("GoldForever", ns)

local ran, worlds = {}, {}
local function world(name)
	return function(isInitialLogin, isReloadingUi)
		worlds[#worlds + 1] = name .. " " .. tostring(isInitialLogin) .. " " .. tostring(isReloadingUi)
	end
end
local function step(what)
	return function()
		ran[#ran + 1] = what
	end
end
-- The Store (Core.lua) is a module too: one that requires it starts with the save loaded.
ns.module("Reader", { requires = { "Store" }, init = function()
	ran[#ran + 1] = GoldForeverDB and "init Reader with the save" or "init Reader without the save"
end })
ns.module("Late", { requires = { "Early" }, init = step("init Late"), enable = step("enable Late"), world = world("Late") })
ns.module("Early", { init = step("init Early"), enable = step("enable Early"), world = world("Early") })
ns.module("Early", { init = step("init Early again") })
ns.module("Broken", { init = function() error("boom") end, enable = step("enable Broken"), world = world("Broken") })
ns.module("AfterBroken", { requires = { "Broken" }, init = step("init AfterBroken"), enable = step("enable AfterBroken"), world = world("AfterBroken") })
ns.module("NoEnable", { enable = function() error("no enable") end, world = world("NoEnable") })
local shaky = 0
ns.module("Shaky", { world = function()
	shaky = shaky + 1
	if shaky == 1 then
		error("first loading screen")
	end
	worlds[#worlds + 1] = "Shaky"
end })
ns.module("Lonely", { requires = { "Nowhere" }, init = step("init Lonely") })
ns.module("Ping", { requires = { "Pong" }, init = step("init Ping") })
ns.module("Pong", { requires = { "Ping" }, init = step("init Pong") })
ns.module("Echo", { requires = { "Ping" }, init = step("init Echo") })
ns.module("Free", { enable = step("enable Free") })

eq(#ran, 0, "nothing starts while the files load")
handler(nil, "ADDON_LOADED", "GoldForever")
eq(table.concat(ran, ", "), "init Reader with the save, init Early, init Late", "each init once the addon has loaded, after the modules it requires")
handler(nil, "PLAYER_LOGIN")
eq(table.concat(ran, ", "), "init Reader with the save, init Early, init Late, enable Early, enable Late, enable Free", "each enable once the player has logged in, in the same order")

local errors = GoldForeverDB.errors
eq(errors.Early and errors.Early.msg, "module declared twice", "a module declared twice is recorded, the first kept")
eq(errors.Broken and errors.Broken.msg:find("boom") ~= nil, true, "a failing init is recorded")
eq(errors.AfterBroken and errors.AfterBroken.msg, "requires Broken, which failed", "a module that requires a failed one does not start")
eq(errors.Lonely and errors.Lonely.msg, "requires Nowhere, which no module declares", "a missing requirement is recorded")
eq(errors.Ping and errors.Ping.msg, "requires Pong, which requires it in turn", "a cycle is recorded")
eq(errors.Pong and errors.Pong.msg, "requires Ping, which requires it in turn", "each module in a cycle")
eq(errors.Echo and errors.Echo.msg, "requires Ping, which cannot start", "a module that requires one in a cycle does not start")
eq(errors.Store or errors.Reader or errors.Late or errors.Free, nil, "the modules that start record no error")

eq(#worlds, 0, "no world before the first loading screen")
handler(nil, "PLAYER_ENTERING_WORLD", true, false)
eq(table.concat(worlds, ", "), "Early true false, Late true false", "each world at a loading screen, in the same order, with isInitialLogin and isReloadingUi")
eq(errors.Shaky and errors.Shaky.msg:find("first loading screen") ~= nil, true, "a failing world is recorded")
worlds = {}
handler(nil, "PLAYER_ENTERING_WORLD", false, true)
eq(table.concat(worlds, ", "), "Early false true, Late false true, Shaky", "and again at every loading screen, a world that failed included; none for a module that did not start")

-- Modules set themselves up through ns.module: these files still subscribe to PLAYER_LOGIN or
-- PLAYER_ENTERING_WORLD, each line a file and the event with why it stays; the list only shrinks. A file
-- that moves leaves it, and a new one fails here.
local KNOWN = {
	["Achievements.lua PLAYER_ENTERING_WORLD"] = "achievements and statistics are read again after every loading screen",
	["Character.lua PLAYER_ENTERING_WORLD"] = "currencies, reputation and gear are read again after every loading screen",
	["Core.lua PLAYER_ENTERING_WORLD"] = "the kernel itself: it runs every module's world and records the login or resume row",
	["Core.lua PLAYER_LOGIN"] = "the kernel itself: it runs every module's enable and records the character",
	["CraftQueue.lua PLAYER_ENTERING_WORLD"] = "a window, not a collector: it moves with the surfaces",
	["FirstRun.lua PLAYER_ENTERING_WORLD"] = "a window, not a collector: the first-run card is offered again after every loading screen",
	["Knowledge.lua PLAYER_ENTERING_WORLD"] = "the map is seen on every zone change; the API and game rules are read again after every loading screen",
	["Ledger.lua PLAYER_ENTERING_WORLD"] = "the money a change is measured from is taken again after every loading screen",
	["Legacy.lua PLAYER_ENTERING_WORLD"] = "the Legacy perks are read again after every loading screen",
	["Levelling.lua PLAYER_ENTERING_WORLD"] = "the login row needs isInitialLogin; XP and the zone are read again after every loading screen",
	["Lists.lua PLAYER_LOGIN"] = "a tool, not a collector: merging the site's lists moves with the tools",
	["Looks.lua PLAYER_LOGIN"] = "the UI kit, not a collector: applying the look moves with the UI kit",
	["Minimap.lua PLAYER_LOGIN"] = "a window, not a collector: it moves with the surfaces",
	["MobStats.lua PLAYER_ENTERING_WORLD"] = "counts that failed to build are built again at the next loading screen",
	["Prices.lua PLAYER_ENTERING_WORLD"] = "the stale-prices warning needs isInitialLogin, so a reload does not repeat it",
	["Session.lua PLAYER_ENTERING_WORLD"] = "XP is read again after every loading screen; restoring needs isInitialLogin and isReloadingUi",
}
local known = {}
for entry, why in pairs(KNOWN) do
	known[#known + 1] = entry
	eq(why ~= "", true, entry .. " says why it stays")
end
table.sort(known)
local EVENTS = { "PLAYER_ENTERING_WORLD", "PLAYER_LOGIN" }
local subscribed = {}
for file, source in pairs(SOURCES) do
	for _, event in ipairs(EVENTS) do
		if source:find('"' .. event .. '"', 1, true) then
			subscribed[#subscribed + 1] = file .. " " .. event
		end
	end
end
table.sort(subscribed)
eq(table.concat(subscribed, ", "), table.concat(known, ", "), "the files that subscribe to PLAYER_LOGIN or PLAYER_ENTERING_WORLD")
return checks()
