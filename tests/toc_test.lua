-- The version and the files, the same everywhere (review A-12): Core.lua's VERSION and the three TOCs'
-- "## Version", and the three TOCs' files, the same list in the same order, each one there. The release
-- (addon-release.yml) checks the version against the tag.

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

local first = files(TOCS["GoldForever.toc"])
for _, name in ipairs({ "GoldForever.toc", "GoldForever_Mainline.toc", "GoldForever_Forever.toc" }) do
	local toc = TOCS[name]
	eq(type(toc), "string", name .. " is there")
	eq(toc:match("\n## Version: *([^\r\n]+)"), version, name .. "'s version is Core.lua's")
	local list = files(toc)
	eq(table.concat(list, "\n"), table.concat(first, "\n"), name .. " lists GoldForever.toc's files, in its order")
	for _, file in ipairs(list) do
		eq(FILES[file], true, name .. " lists " .. file .. ", which is there")
	end
end

-- Every addon file is in the TOCs: one left out is never loaded.
local listed = {}
for _, file in ipairs(first) do
	listed[file] = true
end
for name in pairs(SOURCES) do
	eq(listed[name], true, name .. " is in the TOCs")
end
return checks()
