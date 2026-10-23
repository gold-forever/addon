-- Gold Forever: the in-game UI kit. The web app's components (frontend/src/design-system) in the
-- game's own frames, in the look the player picked (Theme.skin): the web's rounded, shadowed cards in
-- Roboto, or the client's own dialog boxes, red buttons and Friz Quadrata. Text at three levels, one
-- accent, everything on the pixel grid. Plain frames and Blizzard's plain templates only (no secure
-- ones), so every window can open in combat; nothing here reads a value the client keeps secret.
--
-- Pure helpers (ns.UI.layout) carry the arithmetic, so it is tested without the client.

local _, ns = ...
local Theme = ns.Theme

local UI = { layout = {} }
ns.UI = UI

local WHITE = "Interface\\Buttons\\WHITE8X8"


-- Layout: pure ---------------------------------------------------------------------------------------

-- Column widths for a table `total` pixels wide: fixed `width`s as given, the rest shared by the
-- columns with `flex` (a weight, 1 when neither is set), at least `min` each.
function UI.layout.columnWidths(columns, total)
	local fixed, weight = 0, 0
	for _, c in ipairs(columns) do
		if c.width then
			fixed = fixed + c.width
		else
			weight = weight + (c.flex or 1)
		end
	end
	local spare = math.max(0, total - fixed)
	local widths = {}
	for i, c in ipairs(columns) do
		widths[i] = c.width or math.max(c.min or 40, math.floor(spare * (c.flex or 1) / math.max(weight, 1)))
	end
	return widths
end

-- Rows sorted by a column's `sort` value (or its key), descending when asked; ties keep their order.
function UI.layout.sortRows(rows, column, descending)
	local value = column.sort or function(row)
		return row[column.key]
	end
	local indexed = {}
	for i, row in ipairs(rows) do
		indexed[i] = { row = row, i = i, v = value(row) }
	end
	table.sort(indexed, function(a, b)
		if a.v == b.v or a.v == nil or b.v == nil then
			if (a.v == nil) ~= (b.v == nil) then
				return b.v == nil -- unknown last, either way
			end
			return a.i < b.i
		end
		if descending then
			return a.v > b.v
		end
		return a.v < b.v
	end)
	local out = {}
	for i, x in ipairs(indexed) do
		out[i] = x.row
	end
	return out
end

-- One page of rows: { rows, page, pages }, the page held inside 1…pages.
function UI.layout.page(rows, page, size)
	local pages = math.max(1, math.ceil(#rows / size))
	page = math.min(math.max(1, page or 1), pages)
	local out = {}
	for i = (page - 1) * size + 1, math.min(#rows, page * size) do
		out[#out + 1] = rows[i]
	end
	return { rows = out, page = page, pages = pages }
end

-- Coins as coloured text: "12g 4s 50c" with the game's coin colours, the larger units only when
-- there are any (and "gold" precision drops silver and copper above a gold).
function UI.layout.money(copper, precision)
	copper = math.floor((copper or 0) + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local function coin(n, unit, hex)
		return Theme.escape(hex) .. n .. unit .. "|r"
	end
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = coin(g, "g", Theme.color.gold)
	end
	if precision ~= "gold" or g == 0 then
		if s > 0 or g > 0 then
			parts[#parts + 1] = coin(s, "s", Theme.color.silver)
		end
		parts[#parts + 1] = coin(c, "c", Theme.color.copper)
	end
	return sign .. table.concat(parts, " ")
end

-- Money in a table cell: a faint dash for nothing, so rows of "0c" don't drown the amounts.
function UI.layout.amount(copper, precision)
	if math.floor(math.abs(copper or 0) + 0.5) == 0 then
		return Theme.escape(Theme.color.textFaint) .. "—|r"
	end
	return UI.layout.money(copper, precision)
end

-- What a row's tooltip shows for the cells too narrow for their text: each column's title and its
-- full text, or the lines its `tooltip(row)` gives (a list reads better than a clipped sentence).
function UI.layout.overflowTip(columns, row, clipped)
	local out = {}
	for i, c in ipairs(columns) do
		if clipped[i] then
			local lines = c.tooltip and c.tooltip(row) or { c.text and c.text(row) or tostring(row[c.key] or "") }
			out[#out + 1] = { title = c.title, lines = lines }
		end
	end
	return out
end


-- Pixels -------------------------------------------------------------------------------------------

-- One physical pixel in UI units: 1-pixel lines stay 1 pixel at any UI scale.
function UI.pixel()
	local _, height = GetPhysicalScreenSize and GetPhysicalScreenSize()
	local scale = UIParent and UIParent.GetEffectiveScale and UIParent:GetEffectiveScale() or 1
	if not height or height == 0 or not scale or scale == 0 then
		return 1
	end
	return 768 / height / scale
end

-- The Round texture's solid middle, a sliver wide enough to stretch without its edge showing.
local MID_LO, MID_HI = 0.49, 0.51

-- Texture coordinates for the nine parts of a rounded box cut from the Round texture (a circle): a
-- rounded corner takes its quarter of the circle, a corner named in `square` the solid middle.
function UI.layout.nineSlice(square)
	square = square or {}
	local function corner(name, l, r, t, b)
		if square[name] then
			return { MID_LO, MID_HI, MID_LO, MID_HI }
		end
		return { l, r, t, b }
	end
	return {
		TOPLEFT = corner("TOPLEFT", 0, 0.5, 0, 0.5),
		TOPRIGHT = corner("TOPRIGHT", 0.5, 1, 0, 0.5),
		BOTTOMLEFT = corner("BOTTOMLEFT", 0, 0.5, 0.5, 1),
		BOTTOMRIGHT = corner("BOTTOMRIGHT", 0.5, 1, 0.5, 1),
		TOP = { MID_LO, MID_HI, 0, 0.5 },
		BOTTOM = { MID_LO, MID_HI, 0.5, 1 },
		LEFT = { 0, 0.5, MID_LO, MID_HI },
		RIGHT = { 0.5, 1, MID_LO, MID_HI },
		CENTER = { MID_LO, MID_HI, MID_LO, MID_HI },
	}
end

-- Which end of a two-colour gradient each of a rounded box's nine slices takes: the slices along the
-- start edge the first colour, along the far edge the second, and the band between them the gradient
-- itself (SetGradient), so a gradient runs across the box unbroken.
function UI.layout.sliceGradient(orientation)
	if orientation == "VERTICAL" then
		return { TOPLEFT = "from", TOP = "from", TOPRIGHT = "from", LEFT = "span", CENTER = "span", RIGHT = "span",
			BOTTOMLEFT = "to", BOTTOM = "to", BOTTOMRIGHT = "to" }
	end
	return { TOPLEFT = "from", LEFT = "from", BOTTOMLEFT = "from", TOP = "span", CENTER = "span", BOTTOM = "span",
		TOPRIGHT = "to", RIGHT = "to", BOTTOMRIGHT = "to" }
end

-- Drawing ------------------------------------------------------------------------------------------

-- A texture shaded from one colour to another: top to bottom (VERTICAL) or left to right (HORIZONTAL).
-- Spec: { fromHex, fromAlpha, toHex, toAlpha }. Without SetGradient's colour objects (older clients) the
-- texture takes the first colour.
function UI.gradient(tex, orientation, spec)
	local fr, fg, fb = Theme.rgb(spec[1])
	local tr, tg, tb = Theme.rgb(spec[3])
	if tex.SetGradient and CreateColor then
		tex:SetVertexColor(1, 1, 1, 1)
		local from, to = CreateColor(fr, fg, fb, spec[2]), CreateColor(tr, tg, tb, spec[4])
		if orientation == "VERTICAL" then
			tex:SetGradient("VERTICAL", to, from) -- the client's vertical gradient runs from the bottom
		else
			tex:SetGradient("HORIZONTAL", from, to)
		end
	else
		tex:SetVertexColor(fr, fg, fb, spec[2])
	end
end

-- A box: one or more textures recoloured, faded and shown together.
local function box(parts)
	local b = { parts = parts }
	function b:SetColor(hex, alpha)
		local r, g, bl = Theme.rgb(hex)
		for _, t in pairs(self.parts) do
			t:SetVertexColor(r, g, bl, alpha or 1)
		end
	end
	function b:SetAlpha(alpha)
		for _, t in pairs(self.parts) do
			t:SetAlpha(alpha)
		end
	end
	function b:SetShown(on)
		for _, t in pairs(self.parts) do
			t:SetShown(on)
		end
	end
	-- A gradient across the box: one texture shades whole; a rounded box shades slice by slice.
	function b:SetGradient(orientation, spec)
		local ends = UI.layout.sliceGradient(orientation)
		for key, t in pairs(self.parts) do
			local role = ends[key] or "span"
			-- The colour's own alpha, not the region's: SetAlpha stays free to show and hide the box.
			if role == "from" then
				local r, g, bl = Theme.rgb(spec[1])
				t:SetVertexColor(r, g, bl, spec[2])
			elseif role == "to" then
				local r, g, bl = Theme.rgb(spec[3])
				t:SetVertexColor(r, g, bl, spec[4])
			else
				UI.gradient(t, orientation, spec)
			end
		end
	end
	function b:SetBlendMode(mode)
		for _, t in pairs(self.parts) do
			t:SetBlendMode(mode)
		end
	end
	return b
end

local function solid(parent, layer, hex, alpha)
	local t = parent:CreateTexture(nil, layer or "BACKGROUND")
	t:SetTexture(WHITE)
	local r, g, b = Theme.rgb(hex)
	t:SetVertexColor(r, g, b, alpha or 1)
	return t
end
UI.solid = solid

-- A 1-pixel border inside a frame's edges, in four textures.
function UI.border(frame, hex, alpha)
	local px = UI.pixel()
	local edges = {}
	for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
		local t = solid(frame, "BORDER", hex or Theme.color.border, alpha)
		if side == "TOP" or side == "BOTTOM" then
			t:SetPoint(side .. "LEFT")
			t:SetPoint(side .. "RIGHT")
			t:SetHeight(px)
		else
			t:SetPoint("TOP" .. side)
			t:SetPoint("BOTTOM" .. side)
			t:SetWidth(px)
		end
		edges[side] = t
	end
	frame.edges = edges
	return edges
end

-- A rounded box of `hex`, `r` pixels round, `inset` in from the frame's edges: nine textures cut from
-- the Round texture. Corners named in `square` stay square. The frame must be at least 2r on each side.
function UI.round(frame, layer, sublevel, hex, alpha, r, inset, square)
	inset = inset or 0
	local p = {}
	for key, c in pairs(UI.layout.nineSlice(square)) do
		local t = frame:CreateTexture(nil, layer or "BACKGROUND", nil, sublevel or 0)
		t:SetTexture(Theme.media.round)
		t:SetTexCoord(c[1], c[2], c[3], c[4])
		p[key] = t
	end
	for _, corner in ipairs({ { "TOPLEFT", 1, -1 }, { "TOPRIGHT", -1, -1 }, { "BOTTOMLEFT", 1, 1 }, { "BOTTOMRIGHT", -1, 1 } }) do
		p[corner[1]]:SetPoint(corner[1], corner[2] * inset, corner[3] * inset)
		p[corner[1]]:SetSize(r, r)
	end
	p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT")
	p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT")
	p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT")
	p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT")
	p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT")
	p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT")
	p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT")
	p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT")
	p.CENTER:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMRIGHT")
	p.CENTER:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPLEFT")
	local b = box(p)
	b:SetColor(hex, alpha)
	return b
end

-- The web's soft shadow under a window: nine textures from the Shadow texture, spread around the frame
-- and dropped a little, behind everything the frame draws.
function UI.shadow(frame, spread, alpha, drop)
	spread = spread or 24
	local edge = spread / 64
	local cut = { 0, edge, 1 - edge, 1 }
	local p = {}
	local names = { { "TOPLEFT", 1, 1 }, { "TOP", 2, 1 }, { "TOPRIGHT", 3, 1 }, { "LEFT", 1, 2 }, { "CENTER", 2, 2 }, { "RIGHT", 3, 2 },
		{ "BOTTOMLEFT", 1, 3 }, { "BOTTOM", 2, 3 }, { "BOTTOMRIGHT", 3, 3 } }
	for _, n in ipairs(names) do
		local t = frame:CreateTexture(nil, "BACKGROUND", nil, -8)
		t:SetTexture(Theme.media.shadow)
		t:SetTexCoord(cut[n[2]], cut[n[2] + 1], cut[n[3]], cut[n[3] + 1])
		p[n[1]] = t
	end
	drop = drop or 8
	p.TOPLEFT:SetPoint("TOPLEFT", -spread, spread - drop)
	p.TOPRIGHT:SetPoint("TOPRIGHT", spread, spread - drop)
	p.BOTTOMLEFT:SetPoint("BOTTOMLEFT", -spread, -spread - drop)
	p.BOTTOMRIGHT:SetPoint("BOTTOMRIGHT", spread, -spread - drop)
	for _, c in ipairs({ "TOPLEFT", "TOPRIGHT", "BOTTOMLEFT", "BOTTOMRIGHT" }) do
		p[c]:SetSize(spread, spread)
	end
	p.TOP:SetPoint("TOPLEFT", p.TOPLEFT, "TOPRIGHT")
	p.TOP:SetPoint("BOTTOMRIGHT", p.TOPRIGHT, "BOTTOMLEFT")
	p.BOTTOM:SetPoint("TOPLEFT", p.BOTTOMLEFT, "TOPRIGHT")
	p.BOTTOM:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "BOTTOMLEFT")
	p.LEFT:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMLEFT")
	p.LEFT:SetPoint("BOTTOMRIGHT", p.BOTTOMLEFT, "TOPRIGHT")
	p.RIGHT:SetPoint("TOPLEFT", p.TOPRIGHT, "BOTTOMLEFT")
	p.RIGHT:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPRIGHT")
	p.CENTER:SetPoint("TOPLEFT", p.TOPLEFT, "BOTTOMRIGHT")
	p.CENTER:SetPoint("BOTTOMRIGHT", p.BOTTOMRIGHT, "TOPLEFT")
	local b = box(p)
	b:SetColor("#000000", alpha or 0.35)
	return b
end

-- A surface in the look in use: `hex` with a 1-pixel `edge` (or none), rounded `r` pixels on the web,
-- square in the classic look. Returns the fill and the edge as boxes, so they recolour together.
local function surface(frame, hex, alpha, edge, r, square)
	if Theme.skin.radius and r and r > 0 then
		local px = UI.pixel()
		local rim = edge and UI.round(frame, "BACKGROUND", -7, edge, 1, r, 0, square)
		local fill = UI.round(frame, "BACKGROUND", -6, hex, alpha, edge and math.max(1, r - px) or r, edge and px or 0, square)
		return fill, rim
	end
	local t = solid(frame, "BACKGROUND", hex, alpha)
	t:SetAllPoints()
	local rim = edge and box(UI.border(frame, edge))
	return box({ t }), rim
end
UI.surface = surface

local function radius(kind)
	return Theme.skin.radius and Theme.skin.radius[kind] or 0
end

-- A panel: a surface colour with a border. opts.window draws a window: the web's large rounded card
-- with its shadow, or the client's dialog box (its own background and edge files).
function UI.Panel(parent, opts)
	opts = opts or {}
	local skin = Theme.skin
	local classicWindow = opts.window and skin.backdrop and BackdropTemplateMixin
	local f = CreateFrame("Frame", opts.name, parent, classicWindow and "BackdropTemplate" or nil)
	if classicWindow then
		f:SetBackdrop(skin.backdrop)
		f:SetBackdropColor(1, 1, 1, opts.alpha or 0.96)
		f:SetBackdropBorderColor(Theme.rgb(Theme.color.borderStrong))
		return f
	end
	local edge = opts.border ~= false and (opts.borderColor or Theme.color.border) or nil
	f.bg, f.rim = surface(f, opts.color or Theme.color.surface, opts.alpha, edge, opts.radius or radius(opts.window and "window" or "card"), opts.square)
	if opts.window and skin.windowShadow then
		f.shadow = UI.shadow(f)
	end
	local decor = skin.decor
	if decor and opts.window then
		UI.decorate(f, decor)
	end
	return f
end

-- A look's decorations on a window: its background gradient, the light at its top, the glow around it
-- and its corner runes. Every piece is a texture we ship or the client's own white, coloured.
function UI.decorate(f, decor)
	if decor.gradient and f.bg then
		f.bg:SetGradient("VERTICAL", decor.gradient)
	end
	if decor.innerLight then
		local light = f:CreateTexture(nil, "BACKGROUND", nil, -5)
		light:SetTexture(Theme.media.glow)
		light:SetBlendMode("ADD")
		light:SetPoint("TOPLEFT", 0, 0)
		light:SetPoint("TOPRIGHT", 0, 0)
		light:SetHeight(220)
		light:SetTexCoord(0, 1, 0.5, 1) -- the glow's lower half: brightest along the top edge
		local r, g, b = Theme.rgb(decor.innerLight[1])
		light:SetVertexColor(r, g, b, decor.innerLight[2])
		f.light = light
	end
	if decor.glow then
		f.glow = UI.shadow(f, 22, decor.glow[2], 0)
		f.glow:SetColor(decor.glow[1], decor.glow[2])
		f.glow:SetBlendMode("ADD")
	end
	if decor.corners == "rune" then
		f.runes = {}
		for _, c in ipairs({ { "TOPLEFT", 4, -4 }, { "TOPRIGHT", -4, -4 }, { "BOTTOMLEFT", 4, 4 }, { "BOTTOMRIGHT", -4, 4 } }) do
			local t = f:CreateTexture(nil, "OVERLAY", nil, 7)
			t:SetTexture(Theme.media.rune)
			t:SetBlendMode("ADD")
			t:SetSize(16, 16)
			t:SetPoint(c[1], c[2], c[3])
			t:SetVertexColor(Theme.rgb(Theme.color.accent))
			f.runes[#f.runes + 1] = t
		end
	end
end

-- A breathing glow: an added texture whose alpha rises and falls for as long as it shows.
function UI.pulse(frame, hex, low, high, seconds)
	local t = frame:CreateTexture(nil, "ARTWORK", nil, 1)
	t:SetTexture(Theme.media.glow)
	t:SetBlendMode("ADD")
	t:SetAllPoints()
	t:SetVertexColor(Theme.rgb(hex))
	local group = t:CreateAnimationGroup()
	group:SetLooping("BOUNCE")
	local a = group:CreateAnimation("Alpha")
	a:SetFromAlpha(low or 0.15)
	a:SetToAlpha(high or 0.85)
	a:SetDuration(seconds or 1.2)
	group:Play()
	return t, group
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
	local tones = { text = Theme.color.text, muted = Theme.color.textMuted, faint = Theme.color.textFaint, accent = Theme.color.accent }
	fs:SetTextColor(Theme.rgb(tones[opts.tone or "text"] or opts.tone))
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
function UI.Button(parent, label, onClick, opts)
	opts = opts or {}
	local skin = Theme.skin
	local kind = opts.kind or "default"
	local b
	if skin.buttonTemplate and kind ~= "ghost" then
		b = CreateFrame("Button", nil, parent, skin.buttonTemplate)
		b:SetHeight(opts.height or 22)
		b:SetText(label)
		b.label = b:GetFontString()
		b:SetWidth(opts.width or math.max(60, (b.label and b.label:GetStringWidth() or 40) + 28))
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
		b.label = UI.Text(b, skin.titleCaps and string.upper(label) or label, { size = "sm", medium = true, tone = tone, align = "CENTER" })
		b.label:SetPoint("CENTER")
		b:SetWidth(opts.width or math.max(60, (b.label:GetStringWidth() or 40) + 24))
		b:SetScript("OnEnter", function(self)
			if gradient then
				self.bg:SetAlpha(0.85) -- a gradient lifts by fading a little; its colours stay
			else
				self.bg:SetColor(lift, kind == "ghost" and (web and 1 or 0.6) or 1)
			end
		end)
		b:SetScript("OnLeave", function(self)
			if gradient then
				self.bg:SetAlpha(1)
			else
				self.bg:SetColor(kind == "ghost" and not web and "#000000" or fill, rest)
			end
		end)
	end
	if onClick then
		b:SetScript("OnClick", onClick)
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

-- A row of tabs; onSelect(key) when one is clicked. The web's segmented control (a sunken track, the
-- chosen tab raised), or the client's framed tabs with the chosen one lit and its label gold.
function UI.TabBar(parent, tabs, onSelect)
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

-- Data display --------------------------------------------------------------------------------------------

-- A headline number: a small caps label, the value, a hint under it.
function UI.StatCard(parent, label, value, hint)
	local f = UI.Panel(parent, { color = Theme.color.surfaceRaised })
	f:SetHeight(76)
	f.label = UI.Text(f, string.upper(label), { size = "xs", medium = true, tone = "muted" })
	f.label:SetPoint("TOPLEFT", 14, -12)
	f.value = UI.Text(f, value, { size = "xl", medium = true })
	f.value:SetPoint("TOPLEFT", f.label, "BOTTOMLEFT", 0, -6)
	f.hint = UI.Text(f, hint, { size = "xs", tone = "faint" })
	f.hint:SetPoint("TOPLEFT", f.value, "BOTTOMLEFT", 0, -4)
	function f:Set(newValue, newHint)
		self.value:SetText(newValue)
		self.hint:SetText(newHint or "")
	end
	return f
end

-- A bar of stacked segments ({ value, color }), out of `max`: XP, rested, a share of something.
function UI.Bar(parent, max, segments, height)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(height or 8)
	f.track = solid(f, "BACKGROUND", Theme.color.surfaceSunken)
	f.track:SetAllPoints()
	f.fills = {}
	function f:Set(newMax, newSegments)
		self.max, self.segments = newMax, newSegments
		for _, t in ipairs(self.fills) do
			t:Hide()
		end
		local width = self:GetWidth() or 0
		local x = 0
		local decor = Theme.skin.decor
		for i, s in ipairs(newSegments) do
			local t = self.fills[i] or solid(self, "ARTWORK", s.color)
			self.fills[i] = t
			-- The look's own fill for an accent segment; others keep their colour (XP, rested, a share).
			if decor and decor.bar and s.color == Theme.color.accent then
				UI.gradient(t, "HORIZONTAL", decor.bar)
			else
				t:SetVertexColor(Theme.rgb(s.color))
			end
			local w = newMax > 0 and math.min(width - x, width * s.value / newMax) or 0
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", x, 0)
			t:SetPoint("BOTTOMLEFT", x, 0)
			t:SetWidth(math.max(0.001, w))
			t:SetShown(w > 0)
			x = x + w
		end
		-- A spark where the fill ends: the Spark texture, added.
		if decor and decor.spark then
			self.spark = self.spark or self:CreateTexture(nil, "OVERLAY")
			self.spark:SetTexture(Theme.media.spark)
			self.spark:SetBlendMode("ADD")
			self.spark:SetVertexColor(Theme.rgb(Theme.color.accentStrong))
			self.spark:SetSize(14, (self:GetHeight() or 8) + 8)
			self.spark:ClearAllPoints()
			self.spark:SetPoint("CENTER", self, "LEFT", x, 0)
			self.spark:SetShown(x > 0 and x < width)
		end
	end
	f:SetScript("OnSizeChanged", function(self)
		self:Set(self.max or max, self.segments or segments)
	end)
	f.max, f.segments = max, segments
	return f
end

-- A sparkline: values as a line across the frame, lowest at the bottom.
function UI.Sparkline(parent, values, hex)
	local f = CreateFrame("Frame", nil, parent)
	f.lines = {}
	function f:Set(newValues)
		self.values = newValues
		for _, l in ipairs(self.lines) do
			l:Hide()
		end
		local w, h = self:GetWidth() or 0, self:GetHeight() or 0
		if #newValues < 2 or w == 0 then
			return
		end
		local lo, hi = math.huge, -math.huge
		for _, v in ipairs(newValues) do
			lo, hi = math.min(lo, v), math.max(hi, v)
		end
		local span = hi - lo
		local function y(v)
			return span == 0 and h / 2 or (v - lo) / span * h
		end
		for i = 2, #newValues do
			local l = self.lines[i - 1] or self:CreateLine(nil, "ARTWORK")
			self.lines[i - 1] = l
			l:SetColorTexture(Theme.rgb(hex or Theme.color.chart1))
			l:SetThickness(2)
			l:SetStartPoint("BOTTOMLEFT", (i - 2) / (#newValues - 1) * w, y(newValues[i - 1]))
			l:SetEndPoint("BOTTOMLEFT", (i - 1) / (#newValues - 1) * w, y(newValues[i]))
			l:Show()
		end
	end
	f:SetScript("OnSizeChanged", function(self)
		self:Set(self.values or values)
	end)
	f.values = values
	return f
end

-- When there is nothing to show: a title and a line saying what to do.
function UI.EmptyState(parent, title, body)
	local f = CreateFrame("Frame", nil, parent)
	f:SetHeight(80)
	f.title = UI.Text(f, title, { size = "lg", align = "CENTER" })
	f.title:SetPoint("TOP", 0, -16)
	f.body = UI.Text(f, body, { size = "sm", tone = "muted", align = "CENTER", wrap = true })
	f.body:SetPoint("TOP", f.title, "BOTTOM", 0, -6)
	f.body:SetWidth(360)
	return f
end

-- Table ----------------------------------------------------------------------------------------------------

-- Whether a cell's text is cut short: the client's own answer where it has one, else the text's
-- full width against the cell's.
local function clipped(cell)
	if cell.IsTruncated then
		local truncated = cell:IsTruncated()
		if type(truncated) == "boolean" then
			return truncated
		end
	end
	local full = cell.GetUnboundedStringWidth and cell:GetUnboundedStringWidth()
	if type(full) ~= "number" then
		full = cell:GetStringWidth()
	end
	local width = cell:GetWidth()
	return type(full) == "number" and type(width) == "number" and full > width + 1
end

-- A table of rows: columns { key, title, width | flex, align, text = function(row), color = function(row),
-- sort = function(row), tooltip = function(row) -> lines }. Headers sort (click again to reverse), rows
-- alternate and light up under the pointer, the wheel and the page arrows page; a cell cut short shows
-- in full in the row's tooltip. opts.sort = { column, descending } is the starting order and is kept
-- up to date, so a saved table remembers it. Row frames are made once per visible line and reused.
function UI.Table(parent, columns, opts)
	opts = opts or {}
	local ROW = opts.rowHeight or 22
	local t = UI.Panel(parent, { color = Theme.color.surface })
	t.columns, t.all, t.page, t.size = columns, {}, 1, opts.pageSize or 12
	if opts.sort and columns[opts.sort.column] then
		t.sortColumn, t.sortDescending = opts.sort.column, opts.sort.descending
	end
	t.header = CreateFrame("Frame", nil, t)
	t.header:SetPoint("TOPLEFT", 1, -1)
	t.header:SetPoint("TOPRIGHT", -1, -1)
	t.header:SetHeight(ROW + 2)
	-- The header follows the table's rounded top; its bottom corners stay square against the rows.
	t.header.bg = surface(t.header, Theme.color.surfaceRaised, 1, nil, math.max(0, radius("card") - 1), { BOTTOMLEFT = true, BOTTOMRIGHT = true })
	t.heads, t.lines = {}, {}

	local function cellPoints(cell, i, widths)
		local x = 0
		for j = 1, i - 1 do
			x = x + widths[j]
		end
		cell:ClearAllPoints()
		cell:SetPoint("LEFT", x + 8, 0)
		cell:SetWidth(math.max(1, widths[i] - 16))
	end

	for i, c in ipairs(columns) do
		local h = CreateFrame("Button", nil, t.header)
		h:SetHeight(ROW)
		h.text = UI.Text(h, string.upper(c.title), { size = "xs", tone = "muted", align = c.align or "LEFT" })
		h.text:SetAllPoints()
		h:SetScript("OnClick", function()
			t.sortDescending = t.sortColumn == i and not t.sortDescending or (t.sortColumn ~= i and c.align == "RIGHT")
			t.sortColumn = i
			if opts.sort then
				opts.sort.column, opts.sort.descending = i, t.sortDescending
			end
			t.page = 1
			t:Refresh()
		end)
		t.heads[i] = h
	end

	t.footer = UI.Text(t, "", { size = "xs", tone = "faint", align = "RIGHT" })
	t.footer:SetPoint("BOTTOMRIGHT", -10, 6)
	t:EnableMouseWheel(true)
	t:SetScript("OnMouseWheel", function(self, delta)
		self.page = self.page - delta
		self:Refresh()
	end)

	local function line(n)
		local l = t.lines[n]
		if l then
			return l
		end
		l = CreateFrame("Button", nil, t)
		l:SetHeight(ROW)
		l:SetPoint("TOPLEFT", t.header, "BOTTOMLEFT", 0, -(n - 1) * ROW)
		l:SetPoint("TOPRIGHT", t.header, "BOTTOMRIGHT", 0, -(n - 1) * ROW)
		-- Alternate rows shaded on the web; the classic look lights a row with the quest log's highlight.
		l.bg = solid(l, "BACKGROUND", Theme.color.surfaceHover, n % 2 == 0 and Theme.skin.radius and 0.45 or 0)
		l.bg:SetAllPoints()
		if Theme.skin.highlight then
			l.hover = l:CreateTexture(nil, "HIGHLIGHT")
			l.hover:SetTexture(Theme.skin.highlight)
			l.hover:SetBlendMode("ADD")
		else
			l.hover = solid(l, "HIGHLIGHT", Theme.color.accent, 0.08)
		end
		l.hover:SetAllPoints()
		l.cells = {}
		for i, c in ipairs(columns) do
			l.cells[i] = UI.Text(l, "", { size = "sm", align = c.align or "LEFT" })
		end
		l:SetScript("OnClick", function(self)
			if opts.onRowClick and self.row then
				opts.onRowClick(self.row)
			end
		end)
		l:SetScript("OnEnter", function(self)
			if not self.row then
				return
			end
			if opts.onRowEnter then
				opts.onRowEnter(self, self.row)
				return
			end
			local cut = {}
			for i, cell in ipairs(self.cells) do
				cut[i] = clipped(cell)
			end
			local tip = UI.layout.overflowTip(columns, self.row, cut)
			if #tip == 0 or not GameTooltip then
				return
			end
			GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
			for _, part in ipairs(tip) do
				GameTooltip:AddLine(part.title, Theme.rgb(Theme.color.textMuted))
				for _, text in ipairs(part.lines) do
					GameTooltip:AddLine(text, 1, 1, 1, true)
				end
			end
			GameTooltip:Show()
		end)
		l:SetScript("OnLeave", function()
			if GameTooltip then
				GameTooltip:Hide()
			end
		end)
		t.lines[n] = l
		return l
	end

	function t:SetRows(rows)
		self.all = rows or {}
		self.page = 1
		self:Refresh()
	end

	function t:Refresh()
		local widths = UI.layout.columnWidths(self.columns, (self:GetWidth() or 400) - 2)
		-- The sorted column in the accent (game fonts may lack arrow glyphs); the footer says which way.
		for i, h in ipairs(self.heads) do
			cellPoints(h, i, widths)
			h.text:SetTextColor(Theme.rgb(self.sortColumn == i and Theme.color.accent or Theme.color.textMuted))
		end
		local rows = self.sortColumn and UI.layout.sortRows(self.all, self.columns[self.sortColumn], self.sortDescending) or self.all
		local shown = UI.layout.page(rows, self.page, self.size)
		self.page = shown.page
		for n = 1, math.max(#self.lines, #shown.rows) do
			local l = line(n)
			local row = shown.rows[n]
			l.row = row
			l:SetShown(row ~= nil)
			if row then
				for i, c in ipairs(self.columns) do
					local cell = l.cells[i]
					cellPoints(cell, i, widths)
					cell:SetText(c.text and c.text(row) or tostring(row[c.key] or ""))
					cell:SetTextColor(Theme.rgb(c.color and c.color(row) or Theme.color.text))
				end
			end
		end
		local sorted = self.sortColumn and string.format(" · by %s, %s first", string.lower(self.columns[self.sortColumn].title),
			self.sortDescending and "highest" or "lowest") or ""
		self.footer:SetText(#rows == 0 and (opts.empty or "Nothing yet.") or
			((shown.pages > 1 and string.format("%d–%d of %d · page %d of %d (wheel to page)", (shown.page - 1) * self.size + 1,
				math.min(#rows, shown.page * self.size), #rows, shown.page, shown.pages) or string.format("%d rows", #rows)) .. sorted))
		self:SetHeight(ROW + 2 + self.size * ROW + 24)
	end

	t:SetScript("OnSizeChanged", function(self)
		self:Refresh()
	end)
	return t
end

-- Window ------------------------------------------------------------------------------------------------------

-- The main window: a title bar to drag it by, a close button, a sidebar of pages and a content
-- area; Escape closes it. pages = { { key, label, build = function(content) } }: a page is built the
-- first time it is shown. Its position and page are kept in `store`. opts.onLook(name), when given,
-- puts a button in the title bar that switches to the other look.
function UI.Window(name, title, pages, store, opts)
	opts = opts or {}
	local skin = Theme.skin
	local web = skin.radius ~= nil
	local w = UI.Panel(UIParent, { name = name, window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	w:SetSize(opts.width or 860, opts.height or 560)
	w:SetFrameStrata("HIGH")
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	-- Back to where the player left it (the store is shared by the window of each look).
	function w:Restore()
		self:ClearAllPoints()
		if store.point then
			self:SetPoint(store.point[1], UIParent, store.point[2], store.point[3], store.point[4])
		else
			self:SetPoint("CENTER")
		end
	end
	w:Restore()
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end
	-- Inside the edge: the web's 1-pixel rim, or the dialog border's width.
	local inset = web and 1 or 5

	local bar = CreateFrame("Frame", nil, w)
	bar:SetPoint("TOPLEFT", inset, -inset)
	bar:SetPoint("TOPRIGHT", -inset, -inset)
	bar:SetHeight(36)
	bar:EnableMouse(true)
	bar:RegisterForDrag("LeftButton")
	bar:SetScript("OnDragStart", function()
		w:StartMoving()
	end)
	bar:SetScript("OnDragStop", function()
		w:StopMovingOrSizing()
		local p, _, rel, x, y = w:GetPoint()
		store.point = { p, rel, x, y }
	end)
	local decor = skin.decor
	if web then
		bar.bg = surface(bar, Theme.color.surface, decor and 0 or 1, nil, radius("window") - 1, { BOTTOMLEFT = true, BOTTOMRIGHT = true })
		if decor and decor.band then
			bar.bg:SetGradient("HORIZONTAL", decor.band)
		end
	else
		bar.bg = solid(bar, "BACKGROUND", "#000000", 0.35)
		bar.bg:SetAllPoints()
	end
	local rule = solid(bar, "BORDER", Theme.color.border)
	rule:SetPoint("BOTTOMLEFT")
	rule:SetPoint("BOTTOMRIGHT")
	rule:SetHeight(UI.pixel())
	if decor and decor.rule then
		UI.gradient(rule, "HORIZONTAL", decor.rule)
	end
	-- A light sweeping along the rule: the Spark texture, added, moved by a looping Translation, inside
	-- a strip that clips it to the window's width.
	if decor and decor.shimmer then
		local strip = CreateFrame("Frame", nil, bar)
		strip:SetPoint("BOTTOMLEFT", 0, -1)
		strip:SetPoint("BOTTOMRIGHT", 0, -1)
		strip:SetHeight(3)
		strip:SetClipsChildren(true)
		local light = strip:CreateTexture(nil, "OVERLAY")
		light:SetTexture(Theme.media.spark)
		light:SetBlendMode("ADD")
		light:SetSize(110, 3)
		light:SetPoint("RIGHT", strip, "LEFT", 0, 0)
		local sweep = light:CreateAnimationGroup()
		sweep:SetLooping("REPEAT")
		local move = sweep:CreateAnimation("Translation")
		move:SetOffset((opts.width or 860) + 110, 0)
		move:SetDuration(3.2)
		sweep:Play()
		w.shimmer = sweep
	end
	local mark = solid(bar, "ARTWORK", Theme.color.accent)
	mark:SetSize(10, 10)
	mark:SetPoint("LEFT", 14, 0)
	if decor and decor.mark == "rune" then
		mark:SetTexture(Theme.media.rune)
		mark:SetBlendMode("ADD")
		mark:SetSize(16, 16)
		mark:SetPoint("LEFT", 11, 0)
	end
	w.title = UI.Text(bar, skin.titleCaps and string.upper(title) or title, { size = "lg", medium = true, tone = web and "text" or "accent" })
	w.title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
	local close
	if skin.closeTemplate then
		close = CreateFrame("Button", nil, bar, skin.closeTemplate)
		close:SetPoint("RIGHT", 2, 0)
	else
		close = UI.Button(bar, "×", nil, { kind = "ghost", width = 28, height = 24 })
		close:SetPoint("RIGHT", -8, 0)
	end
	close:SetScript("OnClick", function()
		w:Hide()
	end)
	if opts.onLook then
		local other = Theme.nextLook(skin.name)
		local look = UI.Button(bar, Theme.skins[other].label .. " look", function()
			opts.onLook(other)
		end, { kind = "ghost", height = 22 })
		look:SetPoint("RIGHT", close, "LEFT", -6, 0)
	end

	local side = CreateFrame("Frame", nil, w)
	side:SetPoint("TOPLEFT", bar, "BOTTOMLEFT")
	side:SetPoint("BOTTOMLEFT", inset, inset)
	side:SetWidth(opts.sidebar or 170)
	if web then
		side.bg = surface(side, Theme.color.surface, 1, nil, radius("window") - 1, { TOPLEFT = true, TOPRIGHT = true, BOTTOMRIGHT = true })
	else
		side.bg = solid(side, "BACKGROUND", "#000000", 0.3)
		side.bg:SetAllPoints()
	end
	local divider = solid(side, "BORDER", Theme.color.border)
	divider:SetPoint("TOPRIGHT")
	divider:SetPoint("BOTTOMRIGHT")
	divider:SetWidth(UI.pixel())

	local content = CreateFrame("Frame", nil, w)
	content:SetPoint("TOPLEFT", side, "TOPRIGHT", 16, -16)
	content:SetPoint("BOTTOMRIGHT", -16 - inset, 16 + inset)
	w.content = content

	w.pages, w.items = {}, {}
	function w:SelectPage(key)
		for _, p in pairs(self.pages) do
			p:Hide()
		end
		for _, item in ipairs(self.items) do
			local on = item.key == key
			item.bg:SetAlpha(on and 1 or 0)
			item.label:SetTextColor(Theme.rgb(on and (web and Theme.color.accentStrong or Theme.color.accent) or Theme.color.textMuted))
		end
		local page = self.pages[key]
		if not page then
			for _, p in ipairs(pages) do
				if p.key == key then
					page = CreateFrame("Frame", nil, content)
					page:SetAllPoints()
					ns.safely("ui " .. key, p.build, page)
					self.pages[key] = page
				end
			end
		end
		if page then
			page:Show()
			if page.Refresh then
				ns.safely("ui " .. key, page.Refresh, page)
			end
		end
		store.page = key
	end
	for i, p in ipairs(pages) do
		local item = CreateFrame("Button", nil, side)
		item.key = p.key
		item:SetHeight(30)
		item:SetPoint("TOPLEFT", 8, -10 - (i - 1) * 32)
		item:SetPoint("TOPRIGHT", -8, -10 - (i - 1) * 32)
		if skin.highlight then
			local t = item:CreateTexture(nil, "BACKGROUND")
			t:SetTexture(skin.highlight)
			t:SetBlendMode("ADD")
			t:SetAllPoints()
			item.bg = box({ t })
		elseif decor and decor.selected then
			-- The accent fading to the right, with a bar at the left edge; shown and hidden together.
			item.bg = surface(item, Theme.color.accentSoft, 1, nil, radius("item"))
			item.bg:SetGradient("HORIZONTAL", decor.selected)
			local edge = item:CreateTexture(nil, "ARTWORK")
			edge:SetTexture("Interface\\Buttons\\WHITE8X8")
			edge:SetVertexColor(Theme.rgb(Theme.color.accent))
			edge:SetPoint("TOPLEFT")
			edge:SetPoint("BOTTOMLEFT")
			edge:SetWidth(2)
			item.bg.parts.edge = edge
		else
			item.bg = surface(item, Theme.color.accentSoft, 1, nil, radius("item"))
		end
		item.label = UI.Text(item, p.label, { size = "md", medium = web, tone = "muted" })
		item.label:SetPoint("LEFT", 12, 0)
		item:SetScript("OnClick", function()
			w:SelectPage(p.key)
		end)
		w.items[i] = item
	end
	w:SelectPage(store.page or (pages[1] and pages[1].key))
	return w
end
