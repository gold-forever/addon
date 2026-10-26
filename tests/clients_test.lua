-- Retail and WoW: Forever differ in one place per concern: Kernel/ names the client (ns.retail, ns.forever,
-- ns.lean in Core.lua, the interface numbers in Realms.lua), and every other file asks those. No file
-- outside Kernel/ reads the client's interface, tests an interface number, or asks the client which game
-- it is; a new one fails here.

local function clientChecks(source)
	local found = {}
	local n = 0
	for line in (source .. "\n"):gmatch("([^\n]*)\n") do
		n = n + 1
		local code = line:gsub("\\.", "__"):gsub('"[^"]*"', '""'):gsub("'[^']*'", "''"):gsub("%-%-.*$", "")
		if code:find("GetBuildInfo", 1, true) or code:find("WOW_PROJECT_", 1, true) or code:find("LE_EXPANSION_", 1, true)
			or code:find("GetExpansionLevel", 1, true) or code:find("%f[%w_]Is%a*Retail%f[^%w_]") or code:find("%f[%w_]Is%a*Classic%f[^%w_]")
			or code:find("Realms%.is%u") or code:find("[Ii]nterface%s*[<>~=]=?%s*%d") then
			found[#found + 1] = "line " .. n
		end
	end
	return table.concat(found, ", ")
end

-- These files still do, each with why it stays; the list only shrinks.
local KNOWN = {
	["Save.lua"] = "records the client's build and interface into the save, which the site reads; it checks nothing",
	["UiDebug.lua"] = "prints the interface number in /gf uidebug's report; it checks nothing",
	["PricesMarkets.lua"] = "works out the server's market keys for the client the save names, as a function of its interface that prices_test.lua runs for each client",
}
local known = {}
for file, why in pairs(KNOWN) do
	known[#known + 1] = file
	eq(why ~= "", true, file .. " says why it stays")
end
table.sort(known)

local checking = {}
local files = 0
for file, source in pairs(SOURCES) do
	if not PATHS[file]:find("^Kernel\\") then
		files = files + 1
		if clientChecks(source) ~= "" then
			checking[#checking + 1] = file
		end
	end
end
table.sort(checking)
eq(files > 0, true, "the files outside Kernel/ are read")
eq(table.concat(checking, ", "), table.concat(known, ", "), "the files outside Kernel/ that check the client themselves")

-- The scan sees each kind of check, and not one in a comment or a string, nor ns.retail asked.
eq(clientChecks("local i = select(4, GetBuildInfo())"), "line 1", "the client's interface read")
eq(clientChecks("if WOW_PROJECT_ID == WOW_PROJECT_MAINLINE then end"), "line 1", "the client's project")
eq(clientChecks("if ns.Realms.isRetail(x) then end"), "line 1", "Realms asked directly")
eq(clientChecks("if client.interface >= 110000 then end"), "line 1", "an interface number tested")
eq(clientChecks("if IsClassic() then end"), "line 1", "the client asked which game it is")
eq(clientChecks('if ns.retail then end -- GetBuildInfo()\nlocal s = "WOW_PROJECT_ID"'), "", "ns.retail, and checks in a comment or a string")
return checks()
