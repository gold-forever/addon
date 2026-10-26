-- Gold Forever: the auction panel's sizes and the waits for an action's answer.

local _, ns = ...
local Theme = ns.Theme

local ah = ns.ah

ah.WIDTH = 420 -- the panel's width
ah.CONFIRM_TIMEOUT = 5 -- seconds to wait for a post's answer before the next press is taken

-- An action sent (a post, a buy, a cancel): the panel waits for its answer before the next press, and
-- never longer than CONFIRM_TIMEOUT, so a failure the client reports nowhere the panel hears cannot
-- leave Post, Shop and Cancel disabled. Each kind waits apart, so one kind's answer never ends
-- another's wait. `note` is the tab's line for the timeout; `onTimeout` lets go of what the action held.
function ah.await(kind, key, note, onTimeout)
	local w = { key = key, at = GetTime() }
	ah.waits[kind] = w
	C_Timer.After(ah.CONFIRM_TIMEOUT, function()
		if ah.waits[kind] == w then
			ah.waits[kind] = nil
			if onTimeout then
				onTimeout()
			end
			if note then
				note:SetText(Theme.escape(Theme.color.warning) .. "No answer from the auction house; check it before trying again.|r")
			end
			ns.auctionRefresh()
		end
	end)
end

-- Whether any action waits for its answer: a press of Post, Buy next or Cancel next waits for it.
function ah.busy()
	return ah.waits.post or ah.waits.shop or ah.waits.cancel
end
