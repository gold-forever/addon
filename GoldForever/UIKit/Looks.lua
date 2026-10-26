-- Gold Forever: the look and accent every window and panel draws in, and /gf look, /gf accent.

local _, ns = ...
local Theme = ns.Theme

local function settings()
	return ns.settings("window")
end

local function look()
	local name = settings().look
	return Theme.skins[name] and name or "web"
end

-- The accent panels draw in this session. Each new colour draws every window and panel anew (frames are
-- never freed), so a session draws in at most MAX_ACCENTS of them; one more is saved and shows after a
-- /reload. Enough for every swatch in Settings and the look's own (manual test run 001: the fourth
-- swatch clicked waited for a reload); only typed /gf accent colours past those wait.
local MAX_ACCENTS = #Theme.accents + 1
local drawnAccents, drawnCount, sessionAccent, accentRead = {}, 0, nil, false
local function accent()
	if not accentRead then
		accentRead = true
		sessionAccent = settings().accent
		drawnAccents[sessionAccent or "none"], drawnCount = true, 1
	end
	return sessionAccent
end

-- The look and accent the player set, for panels outside the window (the session HUD) to draw in.
function ns.applyLook()
	Theme.apply(look(), accent())
end

-- The saved look, whichever was drawn last (the minimap's right-click steps on from it).
ns.currentLook = look

-- The accent this session draws in, which the hub's windows are kept by.
ns.sessionAccent = accent

-- In the saved look from login, before anything is drawn.
ns.on("PLAYER_LOGIN", "look", function()
	-- By now the addon's fonts are loaded, so the look's text can be measured against Classic's (Theme.lua).
	Theme.canMeasure = true
	ns.applyLook()
end)

-- An open hub window rebuilt in the look and accent now set (ns.hubReopen, Hub.lua), or else the look set
-- for what draws next; then the panels outside the hub redraw.
local function reopen()
	if not ns.hubReopen() then
		Theme.apply(look(), accent())
	end
	ns.emit("lookChanged")
end

-- "/gf look web", "/gf look classic" or "/gf look arcane": the window's look, kept in the settings. An
-- open window switches in place, on the same page.
ns.commands.look = function(name)
	name = string.lower(name or "")
	if not Theme.skins[name] then
		print(string.format("Gold Forever: the look is %s. /gf look %s", Theme.skins[look()].label, table.concat(Theme.order, " · /gf look ")))
		return
	end
	settings().look = name
	reopen()
end

-- "/gf accent #2fd1a8" puts an accent colour over the look; "/gf accent" goes back to the look's own.
ns.commands.accent = function(hex)
	hex = string.lower(hex or "")
	if hex ~= "" and not string.match(hex, "^#%x%x%x%x%x%x$") then
		print("Gold Forever: /gf accent #rrggbb, or /gf accent alone for the look's own colour.")
		return
	end
	local chosen = hex ~= "" and hex or nil
	-- The session's accent read before the new one is saved, or the new one would count as drawn already.
	accent()
	settings().accent = chosen
	if not drawnAccents[chosen or "none"] then
		if drawnCount >= MAX_ACCENTS then
			ns.say("accent saved; it shows after /reload (each new colour draws every panel again, which stays until a reload).")
			return
		end
		drawnAccents[chosen or "none"], drawnCount = true, drawnCount + 1
	end
	sessionAccent = chosen
	reopen()
end
