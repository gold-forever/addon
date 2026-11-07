-- RollValue.lua: on a group loot roll, one line under the item's name with its auction and vendor value,
-- "AH 1g 20s · vendor 15s", times how many drop; an unknown price stays unknown.

local ns = { on = function() end, settings = function() return {} end, price = {}, Money = {} }
assert(load(SOURCES["RollValue.lua"], "@RollValue.lua"))("GoldForever", ns)
local line = ns.RollValue.line

ns.Money.auction = function(copper) return copper .. "c" end
eq(line(12000, 1500), "AH 12000c · vendor 1500c", "both values")
eq(line(nil, 1500), "AH ? · vendor 1500c", "no auction price: unknown")
eq(line(12000, nil), "AH 12000c · vendor ?", "no vendor price: unknown")
eq(line(nil, nil), nil, "neither: no line")

ns.price.market = function(id) return ({ [2589] = 120 })[id] end
ns.price.vendor = function(id) return ({ [2589] = 13, [6070] = 40 })[id] end
eq(ns.RollValue.text(2589, 1), "AH 120c · vendor 13c", "one Linen Cloth")
eq(ns.RollValue.text(2589, 3), "AH 360c · vendor 39c", "three: each value times three")
eq(ns.RollValue.text(6070, 1), "AH ? · vendor 40c", "never scanned")
eq(ns.RollValue.text(9999, 1), nil, "no price at all")
eq(ns.RollValue.text(nil, 1), nil, "no item")

return checks()
