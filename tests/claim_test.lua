-- Claim.lua: /gf claim <code>, the proof in game that a character another account holds is yours
-- (security review finding 4). The site hands out codes of eight letters and digits, shown ABCD-EFGH.

local ns = { commands = {} }
assert(load(SOURCES["Claim.lua"], "@Claim.lua"))("GoldForever", ns)
local C = ns.Claim

-- Typed as the site shows it, or any way a player might copy it.
eq(C.normalize("BCDF-2345"), "BCDF2345", "as shown")
eq(C.normalize("  bcdf-2345 "), "BCDF2345", "lower case, spaces")
eq(C.normalize("bcdf2345"), "BCDF2345", "no dash")
eq(C.normalize("BC DF 23 45"), "BCDF2345", "spaces inside")

-- Not a code: nothing is recorded.
eq(C.normalize(""), nil, "empty")
eq(C.normalize(nil), nil, "nothing")
eq(C.normalize("BCDF-234"), nil, "too short")
eq(C.normalize("BCDF-23456"), nil, "too long")
eq(C.normalize("BCDF-23A5"), nil, "a vowel, which codes never hold")
eq(C.normalize("BCDF-2305"), nil, "a zero, which codes never hold")

-- Recorded on the character it is typed on, with the time; a new one replaces the old.
local character = { name = "Testchar" }
eq(C.record(character, "bcdf-2345", 1000), "BCDF2345", "recorded")
eq(character.claim.code, "BCDF2345", "the code on the character")
eq(character.claim.t, 1000, "and when")
C.record(character, "GHJK-6789", 2000)
eq(character.claim.code, "GHJK6789", "the newer code replaces it")
eq(C.record(character, "nonsense", 3000), nil, "a bad code is refused")
eq(character.claim.code, "GHJK6789", "and leaves the last good one")
eq(C.record(nil, "BCDF-2345", 4000), nil, "no character yet")

return checks()
