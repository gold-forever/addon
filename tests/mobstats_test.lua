-- MobStats.lua: the loot counts per NPC are built from the save's loot rows 20 seconds after a loading screen,
-- when they are not built yet, so the first mob tooltip need not build them in its own frame.

local handler
local timers = {}
function GetBuildInfo() return "1.16.0", "60000", "", 16001 end
function GetServerTime() return 1761148800 end
function GetLocale() return "enUS" end
function CreateFrame()
	return { RegisterEvent = function() end, RegisterUnitEvent = function() end, SetScript = function(_, _, fn) handler = handler or fn end }
end
function print() end
function strsplit(sep, text)
	local out = {}
	for part in string.gmatch(text .. sep, "([^" .. sep .. "]*)" .. sep) do
		out[#out + 1] = part
	end
	return table.unpack(out)
end
C_Timer = { After = function(seconds, fn) timers[#timers + 1] = { at = seconds, fn = fn } end }
unpack = table.unpack
SlashCmdList = {}

-- Runs the timers due within `seconds`; those they start count from now.
local function wait(seconds)
	local due = timers
	timers = {}
	for _, t in ipairs(due) do
		if t.at <= seconds then
			t.fn()
		else
			timers[#timers + 1] = { at = t.at - seconds, fn = t.fn }
		end
	end
end

local ns = {}
for _, file in ipairs({ "Encode.lua", "Realms.lua", "Modules.lua", "Errors.lua", "Events.lua", "Chat.lua", "Commands.lua", "Save.lua", "Characters.lua", "Core.lua", "Schema.lua", "Migrations.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
-- What MobStats reads from files it is not tested with: the price of an item and the loot listeners.
ns.price = { worth = function() return 0 end }
ns.lootListeners = {}
assert(load(SOURCES["MobStats.lua"], "@MobStats.lua"))("GoldForever", ns)

GoldForeverDB = { schema = 1, events = { ["2026-10-22"] = { loot = { "1761148800,1,1429,0.5,0.5,n1922,,50,,;1761148801,1,1429,0.5,0.5,n1922,,30,," } } } }
handler(nil, "ADDON_LOADED", "GoldForever")
handler(nil, "PLAYER_LOGIN")
handler(nil, "PLAYER_ENTERING_WORLD", true, false)
wait(19)
local loots = GoldForeverDB.events["2026-10-22"]
wait(1)
-- Built from the rows the save held then: asked once they are gone, the counts still have them.
GoldForeverDB.events["2026-10-22"] = nil
local mobs = ns.mobStats()
eq(mobs and mobs[1922] and mobs[1922].loots, 2, "the counts are built 20 seconds after a loading screen")
eq(mobs[1922].coin, 80, "from every loot row")

-- Built already: the next loading screen leaves them as they are.
loots.loot[1] = loots.loot[1] .. ";1761148802,1,1429,0.5,0.5,n1922,,20,,"
GoldForeverDB.events["2026-10-22"] = loots
handler(nil, "PLAYER_ENTERING_WORLD", false, false)
wait(20)
eq(ns.mobStats()[1922].loots, 2, "counts already built are not built again at the next loading screen")

return checks()
