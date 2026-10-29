-- Gold Forever: when each cooldown recipe of this character is ready again (design 013): its cooldowns,
-- recipe ID -> ready-at in server time, the latest only. Read while the profession window is open and a
-- moment after a craft, never in combat. A recipe never seen on cooldown records nothing.

local _, ns = ...

-- A spell cooldown this short is the global cooldown every cast starts, not the recipe's.
local GLOBAL_COOLDOWN = 1.5

-- The recipe's spell cooldown, for a client without the recipe call: seconds left, or nil.
local function spellCooldown(id)
	local start, duration
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = C_Spell.GetSpellCooldown(id)
		start, duration = cd and cd.startTime, cd and cd.duration
	elseif GetSpellCooldown then
		start, duration = GetSpellCooldown(id)
	else
		return nil
	end
	if not start or start == 0 or not duration or duration <= GLOBAL_COOLDOWN then
		return 0
	end
	return math.max(0, start + duration - GetTime())
end

-- Seconds until a recipe can be crafted again: 0 when it can now (or has no cooldown), nil when the client
-- cannot tell. A recipe with a charge left can be crafted now.
local function remaining(id)
	if not (C_TradeSkillUI and C_TradeSkillUI.GetRecipeCooldown) then
		return spellCooldown(id)
	end
	local seconds, _, charges, maxCharges = C_TradeSkillUI.GetRecipeCooldown(id)
	if maxCharges and maxCharges > 0 and charges and charges > 0 then
		return 0
	end
	return seconds or 0
end

-- On cooldown: ready-at is now plus what is left. Ready: a recorded ready-at still to come is now (the
-- cooldown was reset); one already past stays.
local function read(id)
	local me = ns.me()
	local left = me and remaining(id)
	if not left then
		return
	end
	local now = ns.now()
	if left > 0 then
		me.cooldowns = me.cooldowns or {}
		me.cooldowns[id] = now + math.ceil(left)
	elseif me.cooldowns and me.cooldowns[id] and me.cooldowns[id] > now then
		me.cooldowns[id] = now
	end
end

ns.listen("recipesRead", "cooldowns", function(learned)
	ns.afterCombat("cooldowns", function()
		for _, ids in pairs(learned) do
			for _, id in ipairs(ids) do
				read(id)
			end
		end
	end)
end)

-- The client starts a craft's cooldown just after the cast succeeds.
ns.on("UNIT_SPELLCAST_SUCCEEDED", "cooldowns", function(unit, _, spell)
	if unit ~= "player" or not ns.me() or not ns.db().catalogue.recipes[spell] then
		return
	end
	ns.after(1, "cooldowns", function()
		ns.afterCombat("cooldowns", function()
			read(spell)
		end)
	end)
end, "player")
