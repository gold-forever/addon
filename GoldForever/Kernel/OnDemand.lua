-- Gold Forever: the addons of its own loaded on demand (GoldForever_Auctions, at the auction house), so a
-- session that never needs them never loads them. ns.loadOnDemand(addon) loads one once, out of combat
-- (ns.afterCombat); its files share this namespace (it is handed over as GoldForever_Core while they load)
-- and its modules start at once (ns.startLate).

local _, ns = ...

local loads = {} -- addon -> the function that loads it, made once so a wait in combat queues it once
local done = {} -- addon -> true once asked to load

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
			ns.startLate()
		elseif why ~= "DISABLED" then -- one turned off in the AddOns list is the player's choice
			ns.fail("load " .. addon, "not loaded: " .. tostring(why))
		end
	end
end

function ns.loadOnDemand(addon)
	loads[addon] = loads[addon] or loader(addon)
	ns.afterCombat("load " .. addon, loads[addon])
end
