-- Gold Forever: /gf claim <code>, the proof in game that a character another account holds on the
-- site is yours (security review finding 4). The site hands out the code; typed on the character, it
-- is saved with it, and the next upload from your account hands the character over.
-- Pure Lua 5.1 apart from the command at the end.

local _, ns = ...
ns = ns or {}

local Claim = {}
ns.Claim = Claim

-- The site's codes: eight of these, which hold no vowels and nothing that reads as another character.
local ALPHABET = "BCDFGHJKMNPQRSTVWXZ23456789"
local LENGTH = 8

-- The code as the site stores it (upper case, no dash or spaces), or nil when it cannot be one.
function Claim.normalize(text)
	if type(text) ~= "string" then
		return nil
	end
	local code = string.upper(string.gsub(text, "[%s%-]", ""))
	if #code ~= LENGTH then
		return nil
	end
	for i = 1, LENGTH do
		if not string.find(ALPHABET, string.sub(code, i, i), 1, true) then
			return nil
		end
	end
	return code
end

-- Keeps the code on [character] with the time, replacing an earlier one; the code, or nil when it
-- is not one or there is no character.
function Claim.record(character, text, now)
	local code = Claim.normalize(text)
	if not code or type(character) ~= "table" then
		return nil
	end
	character.claim = { code = code, t = now }
	return code
end

ns.commands.claim = function(arg)
	local code = Claim.record(ns.me(), arg, ns.now())
	if code then
		ns.say("claim code " .. string.sub(code, 1, 4) .. "-" .. string.sub(code, 5) .. " saved on this character. /reload or log out, then upload as usual.")
	else
		ns.say("type the code the site gave you: /gf claim ABCD-EFGH")
	end
end
