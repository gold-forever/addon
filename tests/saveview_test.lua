-- SaveView.lua: what the windows read about the save itself, from a save.

local save
local ns = { db = function() return save end }
assert(load(SOURCES["SaveView.lua"], "@SaveView.lua"))("GoldForever", ns)
local V = ns.SaveView

save = { characters = {} }
eq(V.isNew(), true, "no characters: a new install")
save = {}
eq(V.isNew(), true, "no table either")
save = { characters = { ["Player-1"] = {} } }
eq(V.isNew(), false, "a save with characters is not new")
return checks()
