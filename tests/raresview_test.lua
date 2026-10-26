-- RaresView.lua: the Rares page's rows, from the rare stream of a save and the mobs' loot counts.

local save = {
	fields = { rare = "t,char,npc,map,x,y,how" },
	events = {
		["2026-10-20"] = { rare = { "300,1,61,1429,500,600,target;400,1,79,1436,100,200,nameplate" } },
		["2026-10-19"] = { rare = { "100,2,61,1429,450,550,minimap" } },
	},
}
local ns = { db = function() return save end }
for _, file in ipairs({ "Views.lua", "ViewsMoney.lua", "ViewsSession.lua", "ViewsItems.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["RaresView.lua"], "@RaresView.lua"))("GoldForever", ns)
local R = ns.RaresView

local mobs = { [61] = { loots = 2, coin = 100, items = { [5] = { dropped = 1, units = 3 } } } }
local rows = R.rows(mobs, function(id) return id == 5 and 10 or nil end)
eq(#rows, 2, "a row a rare, every character's sightings")
eq(rows[1].npc, 79, "the latest first")
eq(rows[1].value, nil, "a rare never looted has no value")
eq(rows[2].seen, 2, "seen twice")
eq(rows[2].last, 300, "last seen")
eq(rows[2].map .. " " .. rows[2].x .. " " .. rows[2].y .. " " .. rows[2].how, "1429 500 600 target", "the last sighting's place and way")
eq(rows[2].value, (100 + 3 * 10) / 2, "what a loot of it is worth")
eq(#R.rows(nil, function() end), 2, "the rows before the loot is counted")

save = { fields = { rare = "t,char,npc,map,x,y,how" } }
eq(#R.rows(mobs, function() end), 0, "none seen")
return checks()
