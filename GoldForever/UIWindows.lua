-- Gold Forever: the UI kit's floating windows: the panels beside the game's own windows, the HUD and
-- the craft queue, drawn once per look.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI

-- One frame per look and accent: frames cannot be restyled in place and are never freed, so a look
-- draws its own frame the first time one is wanted and gets the same one back when it comes again.
-- build() draws a frame in the look now set, hidden. dock(frame, old) puts a frame drawn again in a new
-- look where the old one showed.
--   view:get()            the frame in the look now set (set first), the one before hidden
--   view.frame, view.key  the frame last given and the look it is drawn in
--   view:redraw()         a frame that shows, drawn in another look than the one now set, drawn again:
--                         the old one hidden, the new one docked and shown. True when it was.
--   view:onLook(name, fn) on each look change, the frame drawn again, then fn(redrawn)
function UI.perLook(build, dock)
	local view = { frames = {} }
	function view:get()
		ns.applyLook()
		local old, f = self.frame, self.frames[Theme.key]
		if not f then
			f = build()
			self.frames[Theme.key] = f
		end
		if old and old ~= f then
			old:Hide()
		end
		self.frame, self.key = f, Theme.key
		return f
	end
	function view:redraw()
		local old = self.frame
		if not old or not old:IsShown() or self.key == Theme.key then
			return false
		end
		old:Hide()
		local f = self:get()
		if dock then
			dock(f, old)
		end
		f:Show()
		return true
	end
	function view:onLook(name, fn)
		ns.onLook(name, function()
			local redrawn = self:redraw()
			if fn then
				fn(redrawn)
			end
		end)
	end
	return view
end
