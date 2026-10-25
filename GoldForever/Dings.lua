-- Gold Forever: "Announce dings on Discord" for the character you are playing (design 008). The webhook
-- is added on the site (gold-forever.app/settings), never in the game: the addon cannot reach the
-- internet. The switch writes the choice into the save, GoldForeverDB.dings[guid] = { on, t }, and the
-- companion app uploads it; the server takes it when it is newer than the site's own choice. The
-- companion brings the site's side back in its data file (GoldForever_Prices.dings: when it last
-- changed, whether a webhook is connected, and each character's choice), so without the companion there
-- is nothing to change.

local _, ns = ...
ns = ns or {}

local Dings = {}
ns.Dings = Dings

-- What the switch shows for a character, from its choice in the save (`mine`: { on, t } or nil), the
-- companion's data file (`data`: GoldForever_Prices, or nil without the companion) and its guid.
-- Returns { companion, webhook (true, false, or nil when the file does not say), on, pending }: pending
-- when the choice in the save is newer than the site's ding state (dings.at), so the site has not had it.
function Dings.state(mine, data, guid)
	local companion = type(data) == "table"
	local site = companion and type(data.dings) == "table" and data.dings or nil
	local webhook = nil
	if site and type(site.webhook) == "boolean" then
		webhook = site.webhook
	end
	local siteOn = site and type(site.characters) == "table" and site.characters[guid] == true or false
	-- When the site's ding state last changed (the companion rewrites the file for it alone, keeping the
	-- prices' `at`); an older file without it falls back to the file's own time.
	local at = site and type(site.at) == "number" and site.at or (companion and type(data.at) == "number" and data.at) or nil
	local choice = type(mine) == "table" and type(mine.on) == "boolean" and type(mine.t) == "number" and mine or nil
	if choice and (not at or choice.t > at) then
		return { companion = companion, webhook = webhook, on = choice.on, pending = true }
	end
	return { companion = companion, webhook = webhook, on = siteOn, pending = false }
end

-- The line under the switch: what it does, or what is missing before it can.
function Dings.hint(state)
	if not state.companion then
		return "No companion data in the game (the GoldForever_Data addon). Needs a companion app that brings prices into the game: it carries this choice to the site."
	elseif state.webhook == false then
		return "No Discord webhook yet. Add one at gold-forever.app/settings (Discord), then switch this on."
	elseif state.pending then
		return "Saved. The companion uploads it when the game writes its save: at /reload or logout."
	elseif state.on then
		return "Each level-up is posted to your webhook, with a public page anyone with the link can open."
	end
	return "Off: this character's level-ups are not posted."
end

-- The switch can change only with the companion, and not while the site says there is no webhook.
function Dings.changeable(state)
	return state.companion and state.webhook ~= false
end

-- The state for the character online.
function Dings.current()
	local me = ns.me()
	local guid = me and me.guid or (UnitGUID and UnitGUID("player"))
	local db = ns.db()
	local mine = db and db.dings and guid and db.dings[guid]
	return Dings.state(mine, GoldForever_Prices, guid), guid
end

-- The player's choice for the character online, written into the save with the server's time.
function Dings.set(on)
	local state, guid = Dings.current()
	if not guid or not Dings.changeable(state) then
		return false
	end
	local db = ns.db()
	db.dings = db.dings or {}
	db.dings[guid] = { on = on and true or false, t = GetServerTime() }
	return true
end

-- "/gf dings on" or "/gf dings off"; "/gf dings" says where it stands.
ns.commands.dings = function(arg)
	arg = string.lower(arg or "")
	if arg == "on" or arg == "off" then
		if not Dings.set(arg == "on") then
			ns.say(Dings.hint(Dings.current()))
			return
		end
	end
	local state = Dings.current()
	ns.say(string.format("Discord dings are %s for this character. %s", state.on and "on" or "off", Dings.hint(state)))
end
