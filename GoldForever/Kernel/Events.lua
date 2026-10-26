-- Gold Forever: the event bus. ns.on subscribes to a game event; ns.listen hears the addon's own messages,
-- which ns.emit sends.

local _, ns = ...

local frame = CreateFrame("Frame")
local listeners = {} -- event -> { { name, fn } }
local missing = {} -- events this client does not know, for the diagnostics

-- The listeners there when the event came: one added meanwhile (an addon loaded on demand) hears the next.
local function dispatch(list, ...)
	for i = 1, #list do
		if ns.stopped() then
			return
		end
		ns.safely(list[i].name, list[i].fn, ...)
	end
end

frame:SetScript("OnEvent", function(_, event, ...)
	dispatch(listeners[event], ...)
end)

-- The addon's own events: a file says what happened with ns.emit(name, ...), and the files above it that
-- care hear it with ns.listen(name, label, fn), so a lower file never calls up into a higher one.
--   "ready"        the saved table is loaded and upgraded, before PLAYER_LOGIN: what needs only the save
--                  starts here, not on ADDON_LOADED, so it never runs before the table exists;
--   "queueChanged" the craft queue changed, with "added", "crafted" or "cleared" (CraftPlanner.lua);
--   "pricesReady"  a new full scan's prices are in (Pricing.lua);
--   "lookChanged"  the look or accent changed (Looks.lua): the panels outside the hub redraw while they
--                  show (manual test run 001: the crafting strip stayed arcane after a switch to classic).
-- Each listener runs on its own, in the order they listened, so one that fails leaves the rest running.
local heard = {} -- name -> { { name, fn } }
function ns.listen(event, name, fn)
	heard[event] = heard[event] or {}
	table.insert(heard[event], { name = name, fn = fn })
end
function ns.emit(event, ...)
	if heard[event] then
		dispatch(heard[event], ...)
	end
end

-- A unit event for one unit only ("player") has a frame of its own, so the client does not call the addon
-- for every unit in a group: RegisterUnitEvent is per frame. Without it, every unit's.
local unitListeners = {} -- "event unit" -> { { name, fn } }
local function onUnit(event, unit, name, fn)
	local key = event .. " " .. unit
	if not unitListeners[key] then
		local list = {}
		unitListeners[key] = list
		local f = CreateFrame("Frame")
		local ok
		if f.RegisterUnitEvent then
			ok = pcall(f.RegisterUnitEvent, f, event, unit)
		else
			ok = pcall(f.RegisterEvent, f, event)
		end
		if not ok then
			missing[#missing + 1] = event
		end
		f:SetScript("OnEvent", function(_, _, ...)
			dispatch(list, ...)
		end)
	end
	table.insert(unitListeners[key], { name = name, fn = fn })
end

-- fn(...) on every `event`; with `unit`, only on that unit's.
function ns.on(event, name, fn, unit)
	if unit then
		return onUnit(event, unit, name, fn)
	end
	if not listeners[event] then
		listeners[event] = {}
		if not pcall(frame.RegisterEvent, frame, event) then
			missing[#missing + 1] = event
		end
	end
	table.insert(listeners[event], { name = name, fn = fn })
end

-- The events this client does not know, for the diagnostics (/gf check).
function ns.unknownEvents()
	return missing
end
