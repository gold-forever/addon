-- Gold Forever: the slash command, /gf, and its help.

local _, ns = ...

-- Collectors add subcommands: ns.commands.scan = function() ... end
ns.commands = {}

SLASH_GOLDFOREVER1 = "/gf"
SLASH_GOLDFOREVER2 = "/goldforever"
-- "/gf bigdrop 2" runs ns.commands.bigdrop("2").
-- "/gf" alone opens or closes the hub; "/gf help" lists the commands a player uses, "/gf help all" the
-- rest. The stored counts and failures are for bug reports, under "/gf check" (manual test run 001).
local function help(rest)
	print(ns.PREFIX .. " commands:")
	print("  /gf - open or close the window")
	print("  /gf hud - show or hide the session HUD")
	print("  /gf ah - show or hide the auction panel · /gf scan - scan the auction house")
	print("  /gf bags - what to do with your loot · /gf shop - your crafts by profit")
	print("  /gf look web|classic|arcane - change the look · /gf minimap - the minimap button")
	if rest == "all" then
		print("  /gf ui <page> - open a page · /gf session - the session in chat · /gf reset - a new session")
		print("  /gf bigdrop <gold> - big-drop alerts · /gf accent #rrggbb · /gf welcome - the first-run card")
		print("  /gf prices - the prices file · /gf rares [mark] · /gf claim <code> · /gf export · /gf check - details for a bug report")
	else
		print("  More: /gf help all")
	end
end

SlashCmdList.GOLDFOREVER = function(message)
	local name, rest = string.match(message or "", "^%s*(%S*)%s*(.-)%s*$")
	name = string.lower(name or "")
	local command = ns.commands[name]
	if ns.stopped() then
		ns.say("off this session: " .. ns.stopped())
	elseif command then
		ns.safely("/gf " .. name, command, rest)
	elseif name == "" and ns.commands.ui then
		ns.safely("/gf", ns.commands.ui, "")
	elseif name == "help" or name == "" then
		help(rest)
	else
		print(ns.PREFIX .. ": no command \"" .. name .. "\". /gf help lists them.")
	end
end
