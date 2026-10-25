-- Gold Forever: the auction house's saved settings (the rule, durations, quantities, lists, sale
-- profiles), read by the panel, its hub pages, the lists and the purchase ledger.

local _, ns = ...
local Post = ns.Post

function ns.auctionSettings()
	-- The saved table as it is, once there: no defaults made on every call (it is read per row).
	local s = ns.db().settings.auction or ns.settings("auction")
	s.durations = s.durations or {}
	s.quantities = s.quantities or {}
	for k, v in pairs(Post.DEFAULT) do
		if s.rule[k] == nil then
			s.rule[k] = v
		end
	end
	return s
end

-- The active sale profile (the Selling rules page), or nil.
function ns.activeProfile(s)
	s = s or ns.auctionSettings()
	return s.profile and s.profiles and s.profiles[s.profile] or nil
end
