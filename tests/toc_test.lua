-- The version and the files, the same everywhere (review A-12): Core.lua's VERSION and every TOC's
-- "## Version", and each addon's three TOCs' files, the same list in the same order, each one there. The
-- release (addon-release.yml) checks the version against the tag. The auction house panel is an addon of
-- its own, GoldForever_Auctions, which the core loads on demand: its TOCs say so and mirror the core's.

local version = SOURCES["Core.lua"]:match('\nlocal VERSION = "([^"]+)"')
eq(type(version), "string", "Core.lua has a VERSION")

local function files(toc)
	local out = {}
	for line in (toc .. "\n"):gmatch("([^\n]*)\n") do
		line = line:gsub("\r$", ""):match("^%s*(.-)%s*$")
		if line ~= "" and not line:find("^#") then
			out[#out + 1] = line
		end
	end
	return out
end

local function field(toc, name)
	return toc:match("\n## " .. name .. ": *([^\r\n]+)") or toc:match("^## " .. name .. ": *([^\r\n]+)")
end

local FLAVOURS = { "", "_Mainline", "_Forever" }
local listed = {}
for _, addon in ipairs({ "GoldForever", "GoldForever_Auctions" }) do
	local first = files(TOCS[addon .. ".toc"])
	for _, flavour in ipairs(FLAVOURS) do
		local name = addon .. flavour .. ".toc"
		local toc = TOCS[name]
		eq(type(toc), "string", name .. " is there")
		eq(field(toc, "Version"), version, name .. "'s version is Core.lua's")
		local list = files(toc)
		eq(table.concat(list, "\n"), table.concat(first, "\n"), name .. " lists " .. addon .. ".toc's files, in its order")
		for _, file in ipairs(list) do
			eq(FILES[addon .. "\\" .. file], true, name .. " lists " .. file .. ", which is in " .. addon .. "/")
		end
	end
	for _, file in ipairs(first) do
		listed[addon .. "\\" .. file] = true
	end
end

-- Loaded on demand, after the core, for the same clients.
for _, flavour in ipairs(FLAVOURS) do
	local toc = TOCS["GoldForever_Auctions" .. flavour .. ".toc"]
	eq(field(toc, "LoadOnDemand"), "1", "GoldForever_Auctions" .. flavour .. ".toc loads on demand")
	eq(field(toc, "Dependencies"), "GoldForever", "GoldForever_Auctions" .. flavour .. ".toc needs the core")
	eq(field(toc, "Interface"), field(TOCS["GoldForever" .. flavour .. ".toc"], "Interface"), "GoldForever_Auctions" .. flavour .. ".toc's interface is the core's")
end
eq(files(TOCS["GoldForever_Auctions.toc"])[1], "Kernel\\Namespace.lua", "the auction addon's first file links it to the core's namespace")

-- Every addon file is in its addon's TOCs: one left out is never loaded.
for name in pairs(SOURCES) do
	eq(listed[ADDON[name] .. "\\" .. PATHS[name]], true, name .. " is in " .. ADDON[name] .. "'s TOCs")
end
return checks()
