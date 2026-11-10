-- Gold Forever: the addons of its own loaded on demand (GoldForever_Auctions, at the auction house), so a
-- session that never needs them never loads them. ns.loadOnDemand(addon) loads one once, out of combat
-- (ns.afterCombat); its files share this namespace (it is handed over as GoldForever_Core while they load)
-- and its modules start at once (ns.startLate).

local _, ns = ...
local L = ns.L

local loads = {} -- addon -> the function that loads it, made once so a wait in combat queues it once
local done = {} -- addon -> true once asked to load

-- What the client's refusal means for the player, and what to do; any other reason is an error.
local TOLD = {
	DISABLED = L["%s is turned off in the AddOns list: turn it on there to use the auction house panel."],
	MISSING = L["the %s folder is not installed: reinstall Gold Forever, or in a developer install link both folders into AddOns."],
}

local function loader(addon)
	return function()
		if done[addon] then
			return
		end
		done[addon] = true
		local load = C_AddOns and C_AddOns.LoadAddOn or LoadAddOn
		GoldForever_Core = ns
		local ok, loaded, why = pcall(load, addon)
		GoldForever_Core = nil
		if not ok then
			ns.fail("load " .. addon, loaded)
		elseif loaded then
			ns.forgetError("load " .. addon) -- a MISSING an older version recorded, before the folder was installed
			ns.startLate()
		elseif TOLD[why] then
			ns.say(string.format(TOLD[why], addon))
		else
			ns.fail("load " .. addon, "not loaded: " .. tostring(why))
		end
	end
end

function ns.loadOnDemand(addon)
	loads[addon] = loads[addon] or loader(addon)
	ns.afterCombat("load " .. addon, loads[addon])
end
