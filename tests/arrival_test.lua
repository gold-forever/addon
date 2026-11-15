-- Lists.lua: after a login or /reload, one chat line with what came from the site (gf#407): the shared
-- lists' and profiles' changes the merge counted and the prices' age when the file is newer than the last
-- one seen; nothing when nothing changed.

local ns = { test = {} }
loadEncode(ns)
assert(load(SOURCES["Locale.lua"], "@Locale.lua"))("GoldForever", ns)
assert(load(SOURCES["enUS.lua"], "@enUS.lua"))("GoldForever", ns)
assert(load(SOURCES["Views.lua"], "@Views.lua"))("GoldForever", ns)
assert(load(SOURCES["DataFormat.lua"], "@DataFormat.lua"))("GoldForever", ns)
ns.on, ns.listen = function() end, function() end
ns.auctionSettings = function() return {} end
ns.Holdings = { heldHere = function() return 0 end }
assert(load(SOURCES["Lists.lua"], "@Lists.lua"))("GoldForever", ns)
local line = ns.Lists.arrivalLine

local NOW = 1761148800
eq(line(2, NOW - 180, NOW - 3600, NOW), "from the site: 2 list changes, prices from 3m ago.", "list changes and new prices")
eq(line(1, NOW - 180, NOW - 180, NOW), "from the site: 1 list change.", "list changes, prices already seen")
eq(line(0, NOW - 180, NOW - 3600, NOW), "from the site: prices from 3m ago.", "new prices alone")
eq(line(0, NOW - 10, nil, NOW), "from the site: prices from just now.", "prices under a minute old, none seen before")
eq(line(3, nil, nil, NOW), "from the site: 3 list changes.", "no prices file")
eq(line(0, NOW - 180, NOW - 180, NOW), nil, "nothing new: no line")
eq(line(0, nil, nil, NOW), nil, "nothing at all: no line")
return checks()
