-- Kills.lua: kills without the combat log, across fights.

local ns = {}
assert(load(SOURCES["Kills.lua"], "@Kills.lua"))("GoldForever", ns)
local K = ns.Kills

-- Across fights: a corpse looted after its fight closed is the kill its XP already counted.
do
  local pending, seen = {}, {}
  eq(K.credit(pending, 1, {}, seen, 100), 1, "killed; the fight closes before the loot")
  eq(K.credit(pending, 0, { "Creature-0-1-a" }, seen, 110), 0, "its corpse, looted late, is no second kill")
  -- Kill one, pull the next before looting, loot both in the second fight: two kills, not three.
  eq(K.credit(pending, 1, {}, seen, 200), 1, "the first fight")
  eq(K.credit(pending, 1, { "Creature-0-1-b", "Creature-0-1-c" }, seen, 215), 1, "the second fight with both corpses")
  eq(#pending, 0, "every XP kill has its corpse")
  -- A grey mob: no XP, a corpse, a kill.
  eq(K.credit(pending, 0, { "Creature-0-1-rat" }, seen, 300), 1, "a grey mob")
  -- A kill never looted is let go after MATCH_SECONDS: a later grey mob still counts.
  eq(K.credit(pending, 1, {}, seen, 400), 1, "killed, never looted")
  eq(K.credit(pending, 0, { "Creature-0-1-rat2" }, seen, 400 + K.MATCH_SECONDS + 1), 1, "a grey mob long after")
  eq(K.credit(pending, 0, { "Creature-0-1-rat2" }, seen, 900), 0, "a corpse looted again is no new kill")
  eq(K.credit(pending, 0, { "GameObject-0-1-chest" }, seen, 900), 0, "a chest is no kill")
end

return checks()
