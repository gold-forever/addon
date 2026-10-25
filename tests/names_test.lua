-- Every name a file reads on ns is set by some file (nsnames.lua; review A-2): a name renamed or dropped
-- in one file and still read in another fails here, not silently in game. The smoke run checks the same
-- names are set once the session has loaded.

local sets, reads = {}, {}
for file, source in pairs(SOURCES) do
	local r, s = nsNames(source)
	for name in pairs(s) do
		sets[name] = true
	end
	for name, line in pairs(r) do
		reads[#reads + 1] = { name = name, at = file .. ":" .. line }
	end
end
table.sort(reads, function(a, b)
	return a.at < b.at
end)
for _, r in ipairs(reads) do
	eq(sets[r.name], true, "ns." .. r.name .. " read at " .. r.at .. " is set by a file")
end

-- The scanner itself: reads, sets, and what it leaves out.
local r, s = nsNames(table.concat({
	"local x = ns.alpha(ns.beta)",
	"function ns.gamma() end",
	"ns.delta = 1",
	"ns.eps, ns.zeta = 1, 2",
	"if ns.eta == 1 then end",
	"ns.theta.sub = 1",
	'print("ns.inString") -- ns.inComment',
	"local y = notns.other",
}, "\n"))
eq(r.alpha and r.beta and r.eta and r.theta and true, true, "calls, arguments, comparisons and fields of a name are reads")
eq(s.gamma and s.delta and s.eps and s.zeta and true, true, "functions, assignments and a list assigned are sets")
eq(r.inString or r.inComment or r.other or s.theta, nil, "strings, comments and another table's fields are neither")
return checks()
