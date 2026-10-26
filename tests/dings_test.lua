-- Dings.lua: what the "Announce dings on Discord" switch shows, from the save and the companion's file.

local ns = { commands = {} }
assert(load(SOURCES["DataFormat.lua"], "@DataFormat.lua"))("GoldForever", ns)
assert(load(SOURCES["Dings.lua"], "@Dings.lua"))("GoldForever", ns)
local D = ns.Dings

local ME = "Player-4620-006C0FC1"

-- Without the companion: nothing to change, and the hint says why.
local s = D.state(nil, nil, ME)
eq(s.companion, false, "no companion file")
eq(s.on, false, "off")
eq(D.changeable(s), false, "not changeable without the companion")
eq(D.hint(s):find("companion app", 1, true) ~= nil, true, "the hint names the companion")

-- A companion too old to say anything about dings: changeable, off until chosen.
s = D.state(nil, { at = 1000 }, ME)
eq(s.companion, true, "a companion file")
eq(s.webhook, nil, "the file does not say")
eq(D.changeable(s), true, "changeable")

-- The site's side: no webhook yet, so the switch waits for one.
s = D.state(nil, { at = 1000, dings = { webhook = false, characters = {} } }, ME)
eq(s.webhook, false, "no webhook on the site")
eq(D.changeable(s), false, "not changeable without a webhook")
eq(D.hint(s):find("gold-forever.app/settings", 1, true) ~= nil, true, "the hint sends the player to the site")

-- The site's choice shows until the player changes it in game.
local file = { at = 1000, dings = { webhook = true, characters = { [ME] = true } } }
s = D.state(nil, file, ME)
eq(s.on, true, "on, as the site says")
eq(s.pending, false, "nothing waiting")
eq(D.state(nil, file, "Player-1-other").on, false, "another character is off")

-- A choice made in game after the file was written wins, and waits for the upload.
s = D.state({ on = false, t = 1500 }, file, ME)
eq(s.on, false, "the newer choice in the save")
eq(s.pending, true, "waiting for the companion")
-- One made before the file was written has reached the site already: the site's answer stands.
s = D.state({ on = false, t = 900 }, file, ME)
eq(s.on, true, "the site's newer answer")
eq(s.pending, false, "nothing waiting")

-- The site's own time for its ding state: the companion rewrites the file for dings alone, keeping the
-- prices' older `at`, so a choice the site has taken stops waiting.
local rewritten = { at = 1000, dings = { at = 1600, webhook = true, characters = { [ME] = false } } }
s = D.state({ on = false, t = 1500 }, rewritten, ME)
eq(s.pending, false, "the site's state is newer than the choice: taken")
eq(s.on, false, "as the site has it")
s = D.state({ on = true, t = 1700 }, rewritten, ME)
eq(s.pending, true, "a choice after the site's last change still waits")
eq(s.on, true, "and shows")

-- Anything malformed in either place counts as nothing.
s = D.state({ on = "yes", t = 2000 }, { at = "soon", dings = { webhook = "maybe", characters = "all" } }, ME)
eq(s.on, false, "a malformed choice and file read as off")
eq(s.webhook, nil, "a malformed webhook flag says nothing")

-- The site's side is read whatever the file's v says (DataFormat.lua), and a field it does not know is ignored.
s = D.state(nil, { v = 2, at = 1000, future = true, dings = { webhook = true, characters = { [ME] = true }, future = 1 } }, ME)
eq(s.webhook, true, "another version: the webhook flag read")
eq(s.on, true, "another version: the character's choice read")
return checks()
