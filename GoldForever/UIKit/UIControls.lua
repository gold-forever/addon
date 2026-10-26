-- Gold Forever: the UI kit's text and controls: text at three levels, buttons, badges, a search field,
-- icons, switches and swatches, in the look in use. Tabs, sliders and dropdowns: UITabs.lua, UISlider.lua
-- and UIDropdown.lua.

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
