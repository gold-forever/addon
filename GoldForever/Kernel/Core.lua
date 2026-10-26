-- Gold Forever: records the player's characters into GoldForeverDB (design 002, schema v1).
-- The addon only records; everything else happens in the web app.
--
-- Core wires the kernel's parts together: the error path (Errors.lua), the event bus (Events.lua), chat
-- (Chat.lua), /gf (Commands.lua) and the module lifecycle (Modules.lua). The save is the Store's
-- (Store/Save.lua, Store/Characters.lua). Collectors in their own files subscribe with ns.on; a collector
-- that fails records its error in db.errors and leaves the others running.

local addonName, ns = ...

local VERSION = "0.16.1"
ns.VERSION = VERSION

-- The client this is, the one place a file asks: retail or WoW: Forever (Realms.lua knows the numbers).
local interface = select(4, GetBuildInfo())
ns.retail = ns.Realms.isRetail(interface)
ns.forever = ns.Realms.isForever(interface)

-- A retail client keeps a lean save (owner's answer, 2026-10-24): the catalogue exists to keep
-- WoW: Forever's knowledge, which retail's does not need, so tooltip text, the achievement catalogue
-- and map art are neither recorded there nor kept. Forever keeps everything.
ns.lean = ns.retail

local reloading = false -- set by the ReloadUI hook just before the UI unloads

-- What the tests reach in a file and the addon itself does not use: kept apart from the names the files share.
ns.test = {}

-- Whether the client handed us a "secret" value (newer clients hide some unit and marker values from
-- addons): such a value may be passed back to the client but not compared or read here.
function ns.secret(v)
	return issecretvalue ~= nil and issecretvalue(v) or false
end

-- A value the addon may read, or nil when the client keeps it secret (UnitGUID, UnitName and
-- UnitCreatureType are, for a unit whose identity is restricted).
function ns.readable(v)
	if ns.secret(v) then
		return nil
	end
	return v
end

ns.now = GetServerTime

-- A deep copy: the saved file never holds the defaults' own tables, and a save is upgraded on a copy.
function ns.copy(value)
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in pairs(value) do
		out[k] = ns.copy(v)
	end
	return out
end

-- Called with (gained, kind) for every XP gain once Levelling.lua knows what earned it (`quest`,
-- `boss`, `kill`, `explore`, `other`), a few seconds after the gain: the session listens (Session.lua).
ns.xpListeners = {}

-- On a real logout the client has already cleared money, XP and bags when PLAYER_LOGOUT fires
-- (a /reload has not), so values read then are zeros, not the character's state.
function ns.tornDown()
	return UnitXPMax("player") == 0 and GetMoney() == 0
end

-- Whether the UI is unloading for a /reload, not a logout (the session ends at a logout only).
function ns.reloading()
	return reloading
end

-- Wiring -----------------------------------------------------------------------------------------

-- The Store's files load just before this one, so their handlers for an event run before the modules'.
ns.on("ADDON_LOADED", "core", function(name)
	if name ~= addonName then
		return
	end
	ns.startModules("init")
end)

ns.on("PLAYER_LOGIN", "modules", function()
	ns.startModules("enable")
end)

ns.on("PLAYER_ENTERING_WORLD", "modules", function(isInitialLogin, isReloadingUi)
	ns.enterWorld(isInitialLogin, isReloadingUi)
end)

-- /reload and addons call ReloadUI; flag it so PLAYER_LOGOUT records a reload, not a logout.
if ReloadUI then
	hooksecurefunc("ReloadUI", function()
		reloading = true
	end)
end
if C_UI and C_UI.Reload then
	hooksecurefunc(C_UI, "Reload", function()
		reloading = true
	end)
end
