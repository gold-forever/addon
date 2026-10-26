-- SessionView.lua: the Levelling tab's character and its levelling, from the level and XP streams of a save.

local me = { ref = 1, name = "Testchar", class = "MAGE", level = 12, xp = { cur = 300, max = 1000, rested = 200, resting = 1, t = 0 } }
local save = {
	fields = { level = "t,char,kind,level,played,levelPlayed,money,map,x,y", xp = "t,char,xp,kind,rested,instance,map,level,x,y" },
	events = {
		["2026-10-20"] = {
			level = { "1000,1,up,12,5000,0,4200,1429,,;1100,2,up,30,9000,0,9,1429,," },
			xp = { "1200,1,40,kill,20,,1429,12,,;1260,1,60,quest,,,1429,12,,;1300,2,500,kill,,,1429,30,," },
		},
	},
}
local ns = { db = function() return save end, me = function() return me end }
for _, file in ipairs({ "Views.lua", "ViewsMoney.lua", "ViewsSession.lua", "ViewsItems.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["SessionView.lua"], "@SessionView.lua"))("GoldForever", ns)
local S = ns.SessionView

local v = S.levelling()
eq(v.character.name .. " " .. v.character.class .. " " .. v.character.level, "Testchar MAGE 12", "who is levelling")
eq(v.character.xp.cur .. "/" .. v.character.xp.max .. " +" .. v.character.xp.rested, "300/1000 +200", "where in the level")
eq(#v.levelling.levels, 1, "this character's levels only")
eq(v.levelling.levels[1].money, 4200, "the gold when the level was reached")
eq(v.levelling.xp, 100, "this character's XP only")
eq(v.levelling.sources.kill .. " " .. v.levelling.sources.quest, "40 60", "by source")

me = nil
eq(S.levelling(), nil, "no character yet")
return checks()
