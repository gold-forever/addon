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

-- An X that closes `parent`: the client's own close button in a look that has one (classic), else a
-- ghost button with an x. Not placed; close.template says which it is, as the two sit differently.
function UI.CloseButton(parent)
	local close
	if Theme.skin.closeTemplate then
		close = CreateFrame("Button", nil, parent, Theme.skin.closeTemplate)
		close.template = true
	else
		close = UI.Button(parent, "", nil, { kind = "ghost", width = 30, height = 30 })
		local x = UI.Icon(close, "x", 16, "muted")
		x:SetPoint("CENTER")
	end
	close:SetScript("OnClick", function()
		parent:Hide()
	end)
	return close
end

-- A panel of its own over the world. opts:
--   window         the look's window (its colours, shadow and decorations), else a plain panel
--   width, height  its size; strata, its frame strata
--   name           a global name, so Escape closes it as it closes the game's own windows
--   movable        dragged by any bare part; store, a function giving the table whose `point` keeps
--                  where it was left; f:Restore() puts it back there, else at `at` ({ point, x, y })
--   title, icon    its heading: after the icon, small and in the look's case; alone, large as given
--   close          an X in its corner; a function runs before it hides
function UI.Dialog(opts)
	local f
	if opts.window then
		f = UI.Panel(UIParent, { name = opts.name, window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	else
		f = UI.Panel(UIParent, { name = opts.name })
	end
	if opts.width then
		f:SetWidth(opts.width)
	end
	if opts.height then
		f:SetHeight(opts.height)
	end
	if opts.strata then
		f:SetFrameStrata(opts.strata)
	end
	if opts.name and UISpecialFrames then
		table.insert(UISpecialFrames, opts.name)
	end
	if opts.movable then
		f:SetMovable(true)
		f:EnableMouse(true)
		f:RegisterForDrag("LeftButton")
		f:SetScript("OnDragStart", f.StartMoving)
		f:SetScript("OnDragStop", function(self)
			self:StopMovingOrSizing()
			if opts.store then
				local p, _, rel, x, y = self:GetPoint()
				opts.store().point = { p, rel, x, y }
			end
		end)
	end
	function f:Restore()
		local p = opts.store and opts.store().point
		self:ClearAllPoints()
		if p then
			self:SetPoint(p[1], UIParent, p[2], p[3], p[4])
		elseif opts.at then
			self:SetPoint(opts.at[1], UIParent, opts.at[1], opts.at[2] or 0, opts.at[3] or 0)
		end
	end
	if opts.at then
		f:Restore()
	end
	if opts.icon then
		f.mark = UI.Icon(f, opts.icon, 16, "accent")
		f.mark:SetPoint("TOPLEFT", 14, -14)
		local text = opts.title or ""
		f.heading = UI.Text(f, Theme.skin.titleCaps and string.upper(text) or text, { size = opts.titleSize or "sm", medium = true, tone = opts.titleTone })
		f.heading:SetPoint("LEFT", f.mark, "RIGHT", 6, 0)
	elseif opts.title then
		f.heading = UI.Text(f, opts.title, { size = opts.titleSize or "lg" })
		f.heading:SetPoint("TOPLEFT", 16, -14)
	end
	if opts.close then
		f.close = UI.CloseButton(f)
		f.close:SetPoint("TOPRIGHT", f.close.template and -4 or -8, f.close.template and -4 or -8)
		if type(opts.close) == "function" then
			f.close:SetScript("OnClick", function()
				opts.close()
				f:Hide()
			end)
		end
	end
	return f
end
