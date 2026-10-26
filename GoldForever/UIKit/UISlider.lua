-- Gold Forever: the UI kit's slider (UI.Slider), in the look in use.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local box, solid, surface, radius = UI.box, UI.solid, UI.surface, UI.radius

-- A slider: a sunken track, the part up to the thumb in the accent, the thumb, and the value in a small
-- box at the right (format(value) gives its text). onChange(value) when the player moves it; the wheel
-- steps it too. sl:Set(value) moves it without calling onChange.
-- opts.onRelease: a drag calls onChange once, where it is let go (the window's size, which would move the
-- slider under the pointer). The box at its right takes a typed number too, Enter setting it.
function UI.Slider(parent, min, max, step, value, onChange, format, opts)
	format = format or tostring
	local onRelease = opts and opts.onRelease
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(20)
	local s = CreateFrame("Slider", nil, f)
	s:SetPoint("LEFT", 0, 0)
	s:SetPoint("RIGHT", -56, 0)
	s:SetHeight(18)
	s:SetOrientation("HORIZONTAL")
	s:SetMinMaxValues(min, max)
	s:SetValueStep(step)
	if s.SetObeyStepOnDrag then
		s:SetObeyStepOnDrag(true)
	end
	s:SetThumbTexture(Theme.media.round)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(14, 14)
	thumb:SetVertexColor(Theme.rgb(Theme.color.accent))
	local track = solid(s, "BACKGROUND", Theme.color.surfaceSunken)
	track:SetPoint("LEFT")
	track:SetPoint("RIGHT")
	track:SetHeight(6)
	local fill = solid(s, "BORDER", Theme.color.accent)
	fill:SetPoint("LEFT", track, "LEFT")
	fill:SetPoint("RIGHT", thumb, "CENTER")
	fill:SetHeight(6)
	if Theme.skin.decor and Theme.skin.decor.bar then
		UI.gradient(fill, "HORIZONTAL", Theme.skin.decor.bar)
	end
	local readout = CreateFrame("EditBox", nil, f)
	readout:SetSize(48, 20)
	readout:SetPoint("RIGHT")
	readout:SetAutoFocus(false)
	UI.setFont(readout, Theme.skin.font, Theme.text.xs, "")
	readout:SetTextColor(Theme.rgb(Theme.color.text))
	readout:SetJustifyH("CENTER")
	readout.bg, readout.rim = surface(readout, Theme.color.surfaceSunken, 1, Theme.color.border, radius("control") > 0 and 5 or 0)
	-- The number as a label, which the client always draws: the edit box's own text went undrawn in the
	-- Sell panel (manual test run 001, R5.3). The box holds text only while a number is typed.
	readout.label = UI.Text(readout, "", { size = "xs", align = "CENTER" })
	readout.label:SetPoint("LEFT", 2, 0)
	readout.label:SetPoint("RIGHT", -2, 0)
	local quiet, dragging, current = false, false, value
	local function show(v)
		readout.label:SetText(format(v))
	end
	s:SetScript("OnValueChanged", function(_, v)
		v = UI.layout.step(v, min, max, step)
		current = v
		show(v)
		if not quiet and onChange and not (onRelease and dragging) then
			onChange(v)
		end
	end)
	s:SetScript("OnMouseDown", function()
		dragging = true
	end)
	s:SetScript("OnMouseUp", function(self)
		if dragging then
			dragging = false
			if onRelease and onChange then
				onChange(UI.layout.step(self:GetValue(), min, max, step))
			end
		end
	end)
	s:EnableMouseWheel(true)
	s:SetScript("OnMouseWheel", function(self, delta)
		self:SetValue(UI.layout.step(self:GetValue() + delta * step, min, max, step))
	end)
	-- A typed number, its first digits ("110%" reads 110), stepped into the range.
	readout:SetScript("OnEnterPressed", function(self)
		local n = tonumber(string.match(self:GetText() or "", "%-?%d+%.?%d*") or "")
		self:ClearFocus()
		if n then
			n = UI.layout.step(n, min, max, step)
			if n ~= current then
				s:SetValue(n)
			end
		end
		show(current)
	end)
	readout:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	readout:SetScript("OnEditFocusGained", function(self)
		self.rim:SetColor(Theme.color.focus)
		self.label:Hide()
		self:SetText(tostring(current))
		self:HighlightText()
	end)
	readout:SetScript("OnEditFocusLost", function(self)
		self.rim:SetColor(Theme.color.border)
		self:SetText("")
		self.label:Show()
		show(current)
	end)
	-- Its number again when shown (manual test run 001: the Sell quantity's box showed empty).
	readout:SetScript("OnShow", function()
		show(current)
	end)
	function f:Set(v)
		quiet = true
		s:SetValue(v)
		current = UI.layout.step(v, min, max, step)
		show(current)
		quiet = false
	end
	-- A new range (the units of the item in view), without calling onChange.
	function f:SetRange(newMin, newMax)
		min, max = newMin, math.max(newMin, newMax)
		quiet = true
		s:SetMinMaxValues(min, max)
		quiet = false
	end
	f.slider = s
	f.readout = readout
	f:Set(value)
	return f
end
