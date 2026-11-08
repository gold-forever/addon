-- The session recap: what a closed session came to, and which sessions earn a card. The card's life (when it
-- opens, waits for combat, closes and reopens) is played in the smoke test.

local ns = {
	on = function() end, listen = function() end, UI = { perLook = function() return { onLook = function() end } end },
	Session = { watch = function() end },
}
for _, file in ipairs({ "Views.lua", "ViewsMoney.lua", "ViewsSession.lua", "ViewsItems.lua" }) do
	assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
end
assert(load(SOURCES["SessionRecap.lua"], "@SessionRecap.lua"))("GoldForever", ns)
local Recap = ns.SessionRecap

local PRICES = { [10] = 500, [20] = 3000, [30] = 1500 }
local function worth(id) return PRICES[id] end
local function session(over)
	local s = { start = 1000, last = 2800, coin = 20000, items = { [10] = 4, [20] = 1, [40] = 7 }, kills = 37 }
	for k, v in pairs(over or {}) do s[k] = v end
	return s
end

local r = Recap.of(session(), worth)
eq(r.elapsed, 1800, "its time runs from the start to the last loot or Stop")
eq(r.coin, 20000, "the gold looted")
eq(r.value, 5000, "the items at their prices; one without a price adds nothing")
eq(r.goldPerHour, 50000, "gold an hour counts the coin and the items' worth")
eq(r.kills, 37, "the kills")
eq(r.best.id .. " x" .. r.best.n .. " = " .. r.best.value, "20 x1 = 3000", "the best drop is the stack worth most")

eq(Recap.of(session({ items = { [30] = 2, [20] = 1 } }), worth).best.id, 20, "a tie goes to the lower id, the same every time")
eq(Recap.of(session({ items = { [40] = 7 } }), worth).best, nil, "nothing priced: no best drop")

eq(Recap.earned(Recap.of(session(), worth)), true, "a half hour with loot earns a card")
eq(Recap.earned(Recap.of(session({ last = 1299 }), worth)), false, "just under 5 minutes: no card")
eq(Recap.earned(Recap.of(session({ last = 1300 }), worth)), true, "5 minutes exactly: a card")
eq(Recap.earned(Recap.of(session({ coin = 0, items = {} }), worth)), false, "nothing looted: no card")
eq(Recap.earned(Recap.of(session({ items = {} }), worth)), true, "coin alone is loot")
eq(Recap.earned(Recap.of(session({ coin = 0, items = { [40] = 1 } }), worth)), true, "an unpriced item alone is loot")
return checks()
