-- Gold Forever: the UI kit's text and controls: text at three levels, buttons, badges, tabs, a search
-- field, icons, switches, sliders, dropdowns and swatches, in the look in use.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local box, solid, surface, radius = UI.box, UI.solid, UI.surface, UI.radius

-- The tones text and icons take by name, as the colours they stand for in the look now set.
local TONES = { text = "text", muted = "textMuted", faint = "textFaint", accent = "accent" }
local function toneHex(tone)
	return TONES[tone] and Theme.color[TONES[tone]] or tone
end


-- Text -----------------------------------------------------------------------------------------------

-- SetFont, falling back to the game's own font when a file will not load (the client says false), so
-- text never goes blank over a missing font.
function UI.setFont(region, file, size, flags)
	if region:SetFont(file, size, flags) == false then
		region:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, flags)
	end
end

-- Text at a size from Theme.text and a tone: "text" (default), "muted", "faint", "accent", or a hex,
-- in the look's font (opts.medium for the heavier weight). The classic look keeps the game's shadow.
function UI.Text(parent, text, opts)
	opts = opts or {}
	local skin = Theme.skin
	local fs = parent:CreateFontString(nil, "OVERLAY")
	UI.setFont(fs, opts.medium and skin.fontMedium or skin.font, Theme.text[opts.size or "md"] or Theme.text.md, opts.outline and "OUTLINE" or "")
	if type(skin.textShadow) == "table" then
		local sh = skin.textShadow
		fs:SetShadowOffset(sh[1], sh[2])
		local r, g, b = Theme.rgb(sh[3])
		fs:SetShadowColor(r, g, b, sh[4])
	elseif skin.textShadow then
		fs:SetShadowOffset(1, -1)
		fs:SetShadowColor(0, 0, 0, 1)
	else
		fs:SetShadowOffset(0, 0)
	end
	fs:SetTextColor(Theme.rgb(toneHex(opts.tone or "text")))
	fs:SetJustifyH(opts.align or "LEFT")
	fs:SetWordWrap(opts.wrap or false)
	if text then
		fs:SetText(text)
	end
	return fs
end

-- Controls ---------------------------------------------------------------------------------------------

-- A button: `primary`, `ghost` or the default. On the web: the site's rounded buttons (gold, bordered
-- raised, or bare), lifting on hover. Classic: the client's red panel button, and a framed one for ghost.
-- b:SetLabel(text) changes its text in the look's case; a button turned off is faded in every look. A
-- click that fails is recorded, as every handler's is.
function UI.Button(parent, label, onClick, opts)
	opts = opts or {}
	local skin = Theme.skin
	local kind = opts.kind or "default"
	local caps = skin.titleCaps
	local b
	-- In the classic look every button is the game's own, a ghost one too (manual test run 001: Stop and
	-- New session, Clear queue, Rule › stood out as not classic).
	if skin.buttonTemplate then
		b = CreateFrame("Button", nil, parent, skin.buttonTemplate)
		b:SetHeight(opts.height or 22)
		-- The game's red button, with a label of our own over it: the template's own text was now and then
		-- never placed (manual test run 001, /gf uidebug: the button placed, its text at nil,nil, unseen
		-- until the panel was opened again). Our labels are always drawn. Yellow as the game's, grey when
		-- the button is off.
		b.label = UI.Text(b, label, { size = "sm", align = "CENTER" })
		b.label:SetPoint("LEFT", 6, 1)
		b.label:SetPoint("RIGHT", -6, 1)
		b.label:SetWordWrap(false)
		local function tint(self)
			self.label:SetTextColor(Theme.rgb(self:IsEnabled() and "#ffd100" or "#808080"))
		end
		tint(b)
		b:HookScript("OnEnable", tint)
		b:HookScript("OnDisable", tint)
		b:SetWidth(opts.width or math.max(60, (b.label:GetStringWidth() or 40) + 28))
	else
		b = CreateFrame("Button", nil, parent)
		b:SetHeight(opts.height or 24)
		local web = skin.radius ~= nil
		local fill = ({ primary = Theme.color.accent, default = Theme.color.surfaceRaised, ghost = Theme.color.surfaceHover })[kind]
		local lift = ({ primary = Theme.color.accentStrong, default = Theme.color.surfaceHover, ghost = Theme.color.surfaceHover })[kind]
		local rest = kind == "ghost" and (web and 0 or 0.35) or 1
		local edge = (kind == "default" or (kind == "ghost" and not web)) and Theme.color.borderStrong or nil
		b.bg = surface(b, kind == "ghost" and not web and "#000000" or fill, rest, edge, radius("control"))
		local tone = kind == "primary" and Theme.color.accentContrast or kind == "ghost" and (web and "muted" or "accent") or "text"
		local decor = skin.decor
		local gradient = kind == "primary" and decor and decor.primary
		if gradient then
			tone = decor.primaryText or tone
			b.bg:SetGradient("HORIZONTAL", gradient)
			if decor.pulse then
				b.pulse = UI.pulse(b, Theme.color.accentStrong)
			end
		end
		b.label = UI.Text(b, caps and string.upper(label) or label, { size = "sm", medium = true, tone = tone, align = "CENTER" })
		b.label:SetPoint("CENTER")
		b:SetWidth(opts.width or math.max(60, (b.label:GetStringWidth() or 40) + 24))
		-- A gradient lifts towards white: fading it showed the rounded slices' seams (manual test run 001).
		local lifted = gradient and { Theme.mix(gradient[1], "#ffffff", 0.18), gradient[2], Theme.mix(gradient[3], "#ffffff", 0.18), gradient[4] }
		-- Hooked, so a caller's own OnEnter (a tooltip) keeps the lift.
		b:HookScript("OnEnter", function(self)
			if gradient then
				self.bg:SetGradient("HORIZONTAL", lifted)
			else
				self.bg:SetColor(lift, kind == "ghost" and (web and 1 or 0.6) or 1)
			end
		end)
		b:HookScript("OnLeave", function(self)
			if gradient then
				self.bg:SetGradient("HORIZONTAL", gradient)
			else
				self.bg:SetColor(kind == "ghost" and not web and "#000000" or fill, rest)
			end
		end)
	end
	function b:SetLabel(text)
		self.label:SetText(caps and string.upper(text) or text)
	end
	-- Off: faded, in the classic look as well as its grey label.
	b:HookScript("OnDisable", function(self)
		self:SetAlpha(0.5)
	end)
	b:HookScript("OnEnable", function(self)
		self:SetAlpha(1)
	end)
	if onClick then
		b:SetScript("OnClick", function(...)
			ns.safely("button " .. label, onClick, ...)
		end)
	end
	return b
end

-- A small label in a tone: the web's soft pill, or a framed label in the classic look.
function UI.Badge(parent, text, hex)
	local skin = Theme.skin
	local tone = hex or Theme.color.accent
	local f = CreateFrame("Frame", nil, parent)
	f.text = UI.Text(f, text, { size = "xs", medium = true, tone = tone, align = "CENTER" })
	f.text:SetPoint("CENTER")
	local h = skin.radius and 18 or 16
	f:SetSize((f.text:GetStringWidth() or 30) + 16, h)
	if skin.radius then
		f.bg = UI.round(f, "BACKGROUND", 0, tone, skin.badgeFill, h / 2)
	else
		f.bg = box(UI.border(f, tone, 0.55))
	end
	return f
end

-- Page tabs: bold labels in a row over a 1-pixel line, the chosen one bright with a 2-pixel accent line
-- under it, the others muted (the hub's Settings).
local function underlineTabs(parent, tabs, onSelect)
	local bar = CreateFrame("Frame", nil, parent)
	bar:SetHeight(40)
	bar.line = solid(bar, "BORDER", Theme.color.border)
	bar.line:SetPoint("BOTTOMLEFT")
	bar.line:SetPoint("BOTTOMRIGHT")
	bar.line:SetHeight(UI.pixel())
	bar.buttons = {}
	local x = 0
	for i, tab in ipairs(tabs) do
		local b = CreateFrame("Button", nil, bar)
		b.key = tab.key
		b.label = UI.Text(b, Theme.skin.titleCaps and string.upper(tab.label) or tab.label, { size = "md", medium = true, tone = "muted" })
		b.label:SetPoint("CENTER", 0, 1)
		local w = (b.label:GetStringWidth() or 50) + 28
		b:SetSize(w, 40)
		b:SetPoint("BOTTOMLEFT", x, 0)
		x = x + w + 4
		b.under = solid(b, "ARTWORK", Theme.color.accent)
		b.under:SetPoint("BOTTOMLEFT", 6, 0)
		b.under:SetPoint("BOTTOMRIGHT", -6, 0)
		b.under:SetHeight(2)
		b:SetScript("OnClick", function()
			bar:Select(tab.key)
			if onSelect then
				onSelect(tab.key)
			end
		end)
		bar.buttons[i] = b
	end
	bar:SetWidth(x)
	function bar:Select(key)
		for _, b in ipairs(self.buttons) do
			local on = b.key == key
			b.under:SetShown(on)
			b.label:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
		end
		self.selected = key
	end
	if tabs[1] then
		bar:Select(tabs[1].key)
	end
	return bar
end

-- A row of tabs; onSelect(key) when one is clicked. The web's segmented control (a sunken track, the
-- chosen tab raised), or the client's framed tabs with the chosen one lit and its label gold.
-- opts.variant = "underline" draws page tabs instead, in every look.
function UI.TabBar(parent, tabs, onSelect, opts)
	if opts and opts.variant == "underline" then
		return underlineTabs(parent, tabs, onSelect)
	end
	local skin = Theme.skin
	local segmented = skin.tabs == "segmented"
	local bar = CreateFrame("Frame", nil, parent)
	local inner = segmented and 3 or 0
	bar:SetHeight(segmented and 30 or 28)
	if segmented then
		bar.bg = surface(bar, Theme.color.surfaceSunken, 1, Theme.color.border, radius("control"))
	else
		bar.line = solid(bar, "BORDER", Theme.color.border)
		bar.line:SetPoint("BOTTOMLEFT")
		bar.line:SetPoint("BOTTOMRIGHT")
		bar.line:SetHeight(UI.pixel())
	end
	bar.buttons = {}
	local x = inner
	for i, tab in ipairs(tabs) do
		local b = CreateFrame("Button", nil, bar)
		b.key = tab.key
		b.label = UI.Text(b, tab.label, { size = "sm", medium = segmented, tone = "muted" })
		b.label:SetPoint("CENTER", 0, segmented and 0 or 1)
		local w = (b.label:GetStringWidth() or 50) + 24
		b:SetSize(w, segmented and 24 or 26)
		b:SetPoint(segmented and "LEFT" or "BOTTOMLEFT", x, 0)
		x = x + w + (segmented and 2 or 2)
		if segmented then
			b.on = surface(b, Theme.color.surfaceHover, 1, Theme.color.borderStrong, radius("tab"))
		else
			b.on = surface(b, "#000000", 0.45, Theme.color.border)
		end
		b:SetScript("OnClick", function()
			bar:Select(tab.key)
			if onSelect then
				onSelect(tab.key)
			end
		end)
		bar.buttons[i] = b
	end
	bar:SetWidth(x + inner)
	function bar:Select(key)
		for _, b in ipairs(self.buttons) do
			local on = b.key == key
			if segmented then
				b.on:SetShown(on)
			else
				b.on:SetColor(on and Theme.color.surfaceHover or "#000000", on and 1 or 0.45)
			end
			b.label:SetTextColor(Theme.rgb(on and (segmented and Theme.color.accentStrong or Theme.color.accent) or Theme.color.textMuted))
		end
		self.selected = key
	end
	if tabs[1] then
		bar:Select(tabs[1].key)
	end
	return bar
end

-- A search field with a placeholder; onChange(text) as it is typed. Its edge lights up while it has focus.
function UI.SearchBox(parent, placeholder, onChange)
	local box = CreateFrame("EditBox", nil, parent)
	box:SetAutoFocus(false)
	box:SetHeight(Theme.skin.radius and 28 or 24)
	UI.setFont(box, Theme.skin.font, Theme.text.md, "")
	box:SetTextColor(Theme.rgb(Theme.color.text))
	box:SetTextInsets(10, 10, 0, 0)
	box.bg, box.rim = surface(box, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, radius("control"))
	box.hint = UI.Text(box, placeholder, { tone = "faint" })
	box.hint:SetPoint("LEFT", 10, 0)
	-- Cut at the box's edge, never under what stands beside it.
	box.hint:SetPoint("RIGHT", -10, 0)
	box.hint:SetWordWrap(false)
	box:SetScript("OnTextChanged", function(self)
		local text = self:GetText() or ""
		self.hint:SetShown(text == "")
		if onChange then
			onChange(text)
		end
	end)
	box:SetScript("OnEscapePressed", function(self)
		self:ClearFocus()
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self.rim:SetColor(Theme.color.focus)
	end)
	box:SetScript("OnEditFocusLost", function(self)
		self.rim:SetColor(Theme.color.borderStrong)
	end)
	return box
end

-- An icon from Theme.icon, `size` pixels, tinted in a tone ("text", "muted", "faint", "accent") or a hex.
function UI.Icon(parent, name, size, tone)
	local t = parent:CreateTexture(nil, "ARTWORK")
	t:SetTexture(Theme.icon(name))
	t:SetSize(size or 16, size or 16)
	function t:SetTone(newTone)
		self:SetVertexColor(Theme.rgb(toneHex(newTone or "muted")))
	end
	t:SetTone(tone)
	return t
end

-- An on/off switch; onChange(on) when clicked. A pill with a sliding thumb, or the client's own check
-- box in the classic look. sw:Set(on) changes it without calling onChange.
function UI.Switch(parent, on, onChange)
	local sw
	if not Theme.skin.radius then
		sw = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
		sw:SetSize(24, 24)
		function sw:Set(value)
			self.on = value and true or false
			self:SetChecked(self.on)
		end
		sw:SetScript("OnClick", function(self)
			self.on = self:GetChecked() and true or false
			if onChange then
				onChange(self.on)
			end
		end)
	else
		sw = CreateFrame("Button", nil, parent)
		sw:SetSize(32, 18)
		sw.track, sw.rim = surface(sw, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, 9)
		sw.thumb = CreateFrame("Frame", nil, sw)
		sw.thumb:SetSize(12, 12)
		sw.thumb.bg = UI.round(sw.thumb, "ARTWORK", 0, Theme.color.textMuted, 1, 6)
		function sw:Set(value)
			self.on = value and true or false
			self.thumb:ClearAllPoints()
			self.thumb:SetPoint("LEFT", self.on and 17 or 3, 0)
			self.thumb.bg:SetColor(self.on and Theme.color.accent or Theme.color.textMuted)
			self.track:SetColor(self.on and Theme.color.accentSoft or Theme.color.surfaceSunken)
			self.rim:SetColor(self.on and Theme.color.accent or Theme.color.borderStrong)
		end
		sw:SetScript("OnClick", function(self)
			self:Set(not self.on)
			if onChange then
				onChange(self.on)
			end
		end)
	end
	sw:Set(on)
	return sw
end


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

-- A dropdown: a button with the chosen option's label and a chevron; a click opens a menu of the options
-- under it, over everything. options = { { value, label } }; onChange(value) when one is picked. The menu
-- closes on a pick, a click anywhere else or Escape; past MENU_ROWS options it scrolls with the wheel.
local MENU_ROWS = 12
local dropdowns = 0
function UI.Dropdown(parent, options, value, onChange)
	local d = CreateFrame("Button", nil, parent)
	d:SetHeight(28)
	d.bg, d.rim = surface(d, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, radius("control"))
	d.text = UI.Text(d, "", { size = "sm" })
	d.text:SetPoint("LEFT", 10, 0)
	d.text:SetPoint("RIGHT", -28, 0)
	d.chevron = UI.Icon(d, "chevron-down", 14, "muted")
	d.chevron:SetPoint("RIGHT", -10, 0)
	-- Named, so Escape closes it as it closes the game's own menus.
	dropdowns = dropdowns + 1
	local name = "GoldForeverDropdownMenu" .. dropdowns
	local menu = UI.Panel(d, { name = name, color = Theme.color.surfaceRaised, borderColor = Theme.color.borderStrong, radius = radius("control") })
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
	menu:SetPoint("TOPRIGHT", d, "BOTTOMRIGHT", 0, -2)
	menu:EnableMouse(true)
	menu:Hide()
	menu.rows, menu.offset = {}, 0
	-- The rows from the scroll offset on, MENU_ROWS at most.
	local function place()
		menu.offset = math.max(0, math.min(menu.offset, #options - MENU_ROWS))
		for i = 1, #options do
			local row, at = menu.rows[i], i - menu.offset
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 4, -4 - (at - 1) * 24)
			row:SetPoint("TOPRIGHT", -4, -4 - (at - 1) * 24)
			row:SetShown(at >= 1 and at <= MENU_ROWS)
		end
	end
	menu:EnableMouseWheel(true)
	menu:SetScript("OnMouseWheel", function(_, delta)
		menu.offset = menu.offset - delta
		place()
	end)
	-- A click outside the menu and its button closes it.
	menu:SetScript("OnUpdate", function(self)
		if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			and not self:IsMouseOver() and not d:IsMouseOver() then
			self:Hide()
		end
	end)
	-- The choices, again when they change (a list added, an override removed): the rows are reused, as
	-- frames are never freed. The value shown is set again, `v` or the one chosen before, as its label
	-- may have changed.
	function d:SetOptions(list, v)
		options = list
		menu:SetHeight(math.min(#options, MENU_ROWS) * 24 + 8)
		for i, o in ipairs(options) do
			local row = menu.rows[i]
			if not row then
				row = CreateFrame("Button", nil, menu)
				row:SetHeight(24)
				row.hover = surface(row, Theme.color.surfaceHover, 1, nil, radius("item"))
				row.hover:SetShown(false)
				row.text = UI.Text(row, "", { size = "sm" })
				row.text:SetPoint("LEFT", 8, 0)
				row:SetScript("OnEnter", function(self)
					self.hover:SetShown(true)
				end)
				row:SetScript("OnLeave", function(self)
					self.hover:SetShown(false)
				end)
				row:SetScript("OnClick", function(self)
					menu:Hide()
					d:Set(self.value)
					if onChange then
						onChange(self.value)
					end
				end)
				menu.rows[i] = row
			end
			row.text:SetText(o.label)
			row.value = o.value
		end
		for i = #options + 1, #menu.rows do
			menu.rows[i]:Hide()
		end
		place()
		if self.Set then
			self:Set(v == nil and self.value or v)
		end
	end
	d:SetOptions(options)
	function d:Set(v)
		self.value = v
		local label = v
		for _, o in ipairs(options) do
			if o.value == v then
				label = o.label
			end
		end
		self.text:SetText(label)
		for i = 1, #options do
			local row = menu.rows[i]
			row.text:SetTextColor(Theme.rgb(row.value == v and Theme.color.accent or Theme.color.text))
		end
	end
	d:SetScript("OnClick", function()
		menu:SetShown(not menu:IsShown())
	end)
	d:SetScript("OnHide", function()
		menu:Hide()
	end)
	d.menu = menu
	d:Set(value)
	return d
end

-- A colour swatch: a square of `hex`, ringed in the text colour when chosen. sw:SetOn(on).
function UI.Swatch(parent, hex, onClick)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(24, 24)
	b.ring = box(UI.border(b, Theme.color.text))
	local fill = solid(b, "ARTWORK", hex)
	fill:SetPoint("TOPLEFT", 3, -3)
	fill:SetPoint("BOTTOMRIGHT", -3, 3)
	function b:SetOn(on)
		self.ring:SetShown(on)
	end
	b:SetOn(false)
	if onClick then
		b:SetScript("OnClick", onClick)
	end
	return b
end
