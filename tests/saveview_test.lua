-- SaveView.lua: what the windows read about the save itself, from a save.

local save
local ns = { db = function() return save end }
assert(load(SOURCES["SaveView.lua"], "@SaveView.lua"))("GoldForever", ns)
local V = ns.SaveView

save = nil
eq(V.loaded(), false, "no save before the addon has loaded")
eq(V.addon(), nil, "nor the version that loaded it")
save = { characters = {} }
eq(V.loaded(), true, "a save, empty or not, is loaded")
eq(V.isNew(), true, "no characters: a new install")
save = {}
eq(V.isNew(), true, "no table either")
save = { characters = { ["Player-1"] = {} }, addon = "0.16.1" }
eq(V.isNew(), false, "a save with characters is not new")
eq(V.addon(), "0.16.1", "the addon version that loaded the save")
return checks()
