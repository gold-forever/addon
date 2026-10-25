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

-- The column a saved order names: by its key, so a column moved keeps the order (review B-42); an
-- order saved before by index alone, by that index. nil when the column is gone.
function UI.layout.sortColumn(columns, saved)
	if saved.key ~= nil then
		for i, c in ipairs(columns) do
			if c.key == saved.key then
				return i
			end
		end
		return nil
	end
	return columns[saved.column or 0] and saved.column or nil
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
-- Text without its colour codes, to show it in one tone (a greyed amount).
function UI.layout.plain(text)
	return (string.gsub(string.gsub(text or "", "|c%x%x%x%x%x%x%x%x", ""), "|r", ""))
end

-- A whole number in groups of three, with the client's separator ("3,000,000").
function UI.layout.group(n)
	local sign, digits = string.match(tostring(math.floor(n or 0)), "^(%-?)(%d+)$")
	local sep = LARGE_NUMBER_SEPARATOR or ","
	local out = string.gsub(string.reverse(digits or "0"), "(%d%d%d)", "%1" .. sep)
	out = string.reverse(out)
	if string.sub(out, 1, #sep) == sep then
		out = string.sub(out, #sep + 1)
	end
	return (sign or "") .. out
end

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
		parts[#parts + 1] = coin(UI.layout.group(g), "g", Theme.color.gold)
	end
	-- "silver": gold and silver, as auction prices are set (8g 69s); copper only under a gold, and only
	-- when there is some (7s, not 7s 0c).
	if precision == "silver" and (g > 0 or (s > 0 and c == 0)) then
		if s > 0 then
			parts[#parts + 1] = coin(s, "s", Theme.color.silver)
		end
	elseif precision ~= "gold" or g == 0 then
		if s > 0 or g > 0 then
			parts[#parts + 1] = coin(s, "s", Theme.color.silver)
		end
		parts[#parts + 1] = coin(c, "c", Theme.color.copper)
	end
	return sign .. table.concat(parts, " ")
end

-- Money in a table cell: a faint dash for nothing, so rows of "0c" don't drown the amounts; gold and
-- silver unless told otherwise (manual test run 001: "17g 70s 0c" in Auction sales, "1,425g 0s 0c").
function UI.layout.amount(copper, precision)
	if math.floor(math.abs(copper or 0) + 0.5) == 0 then
		return Theme.escape(Theme.color.textFaint) .. "—|r"
	end
	return UI.layout.money(copper, precision or "silver")
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
		-- Opaque: at 0.96 the world's names showed through (manual test run 001: the auctioneer's green
		-- name behind the auction panel).
		f:SetBackdropColor(1, 1, 1, opts.alpha or 1)
		f:SetBackdropBorderColor(Theme.rgb(Theme.color.borderStrong))
		-- The dialog background file is itself see-through: a solid layer under it, inside the edge, so
		-- what lies behind (the auction panel under the hub, the world's names) never shows.
		if not opts.alpha then
			local base = f:CreateTexture(nil, "BACKGROUND", nil, -8)
			base:SetTexture(WHITE)
			base:SetVertexColor(Theme.rgb(Theme.color.bg))
			local inset = skin.backdrop.insets and skin.backdrop.insets.left or 4
			base:SetPoint("TOPLEFT", inset, -inset)
			base:SetPoint("BOTTOMRIGHT", -inset, inset)
		end
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
		local tones = { text = Theme.color.text, muted = Theme.color.textMuted, faint = Theme.color.textFaint, accent = Theme.color.accent }
		self:SetVertexColor(Theme.rgb(tones[newTone or "muted"] or newTone))
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

-- A value a slider stands on: `value` held in min…max and rounded to the nearest step.
function UI.layout.step(value, min, max, step)
	step = step or 1
	local v = min + math.floor((value - min) / step + 0.5) * step
	return math.max(min, math.min(max, v))
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
-- under it, over everything. options = { { value, label } }; onChange(value) when one is picked.
function UI.Dropdown(parent, options, value, onChange)
	local d = CreateFrame("Button", nil, parent)
	d:SetHeight(28)
	d.bg, d.rim = surface(d, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, radius("control"))
	d.text = UI.Text(d, "", { size = "sm" })
	d.text:SetPoint("LEFT", 10, 0)
	d.text:SetPoint("RIGHT", -28, 0)
	d.chevron = UI.Icon(d, "chevron-down", 14, "muted")
	d.chevron:SetPoint("RIGHT", -10, 0)
	local menu = UI.Panel(d, { color = Theme.color.surfaceRaised, borderColor = Theme.color.borderStrong, radius = radius("control") })
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
	menu:SetPoint("TOPRIGHT", d, "BOTTOMRIGHT", 0, -2)
	menu:EnableMouse(true)
	menu:Hide()
	menu.rows = {}
	-- The choices, again when they change (a list added, an override removed): the rows are reused, as
	-- frames are never freed.
	function d:SetOptions(list)
		options = list
		menu:SetHeight(#options * 24 + 8)
		for i, o in ipairs(options) do
			local row = menu.rows[i]
			if not row then
				row = CreateFrame("Button", nil, menu)
				row:SetPoint("TOPLEFT", 4, -4 - (i - 1) * 24)
				row:SetPoint("TOPRIGHT", -4, -4 - (i - 1) * 24)
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
			row:Show()
		end
		for i = #options + 1, #menu.rows do
			menu.rows[i]:Hide()
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

-- A page header's art in the look in use (Theme.skin.hero): a gradient top to bottom, soft lights, the
-- arcane look's stars, fading at the bottom into the window. The frame clips it; width and height place
-- the lights.
function UI.HeroArt(frame, width, height)
	local hero = Theme.skin.hero or { top = Theme.color.surfaceRaised, bottom = Theme.color.surface, lights = {} }
	-- Drawn in a child frame, which the client clips to the frame for certain: the lights reach past it.
	frame:SetClipsChildren(true)
	frame = CreateFrame("Frame", nil, frame)
	frame:SetAllPoints()
	local base = frame:CreateTexture(nil, "BACKGROUND", nil, -4)
	base:SetTexture(WHITE)
	base:SetAllPoints()
	UI.gradient(base, "VERTICAL", { hero.top, 1, hero.bottom, 1 })
	for _, l in ipairs(hero.lights or {}) do
		local t = frame:CreateTexture(nil, "BACKGROUND", nil, -3)
		t:SetTexture(Theme.media.glow)
		t:SetBlendMode("ADD")
		t:SetSize(l[5], l[6])
		t:SetPoint("CENTER", frame, "TOPLEFT", l[3] * width, -l[4] * height)
		local r, g, b = Theme.rgb(l[1])
		t:SetVertexColor(r, g, b, l[2])
	end
	for _, star in ipairs(hero.stars or {}) do
		local t = frame:CreateTexture(nil, "BACKGROUND", nil, -2)
		t:SetTexture(Theme.media.rune)
		t:SetBlendMode("ADD")
		t:SetSize(8, 8)
		t:SetPoint("CENTER", frame, "TOPLEFT", star[1] * width, -star[2] * height)
		local r, g, b = Theme.rgb(star[3])
		t:SetVertexColor(r, g, b, 0.8)
	end
	local fade = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
	fade:SetTexture(WHITE)
	fade:SetPoint("BOTTOMLEFT")
	fade:SetPoint("BOTTOMRIGHT")
	fade:SetHeight(height * 0.6)
	UI.gradient(fade, "VERTICAL", { Theme.color.bg, 0, Theme.color.bg, 1 })
	return base
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
	-- Its height from the start: set only later, in its first size change, what is anchored below it
	-- (Remove, Edit lists, the Sell box, the craft queue's buttons) was now and then never placed and not
	-- drawn until the panel was shown again (manual test run 001).
	t:SetHeight(ROW + 2 + t.size * ROW + 24)
	local saved = opts.sort and UI.layout.sortColumn(columns, opts.sort)
	if saved then
		t.sortColumn, t.sortDescending = saved, opts.sort.descending
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
				opts.sort.column, opts.sort.key, opts.sort.descending = i, c.key, t.sortDescending
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
			-- opts.itemId(row): the row's item, whose own tooltip shows, the cut cells under it (manual test
			-- run 001: hovering an item should show it).
			local id = opts.itemId and opts.itemId(self.row)
			if id and GameTooltip then
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if GameTooltip.SetItemByID then
					GameTooltip:SetItemByID(id)
				else
					GameTooltip:SetHyperlink("item:" .. id)
				end
				for _, part in ipairs(tip) do
					GameTooltip:AddLine(part.title, Theme.rgb(Theme.color.textMuted))
					for _, text in ipairs(part.lines) do
						GameTooltip:AddLine(text, 1, 1, 1, true)
					end
				end
				GameTooltip:Show()
				return
			end
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

	-- New rows from page 1, or with keepPage on the page shown (a refresh while reading, as a click on a
	-- row or a ticker does; past the end it is the last page).
	-- The rows in order, kept until the rows or the order change: a wheel tick or a resize only pages
	-- (review C-11). New rows are sorted again, even in the same table.
	local sorted = {}
	function t:SetRows(rows, keepPage)
		sorted.all = nil
		self.all = rows or {}
		if not keepPage then
			self.page = 1
		end
		self:Refresh()
	end

	function t:Refresh()
		local widths = UI.layout.columnWidths(self.columns, (self:GetWidth() or 400) - 2)
		-- The sorted column in the accent (game fonts may lack arrow glyphs); the footer says which way.
		for i, h in ipairs(self.heads) do
			cellPoints(h, i, widths)
			h.text:SetTextColor(Theme.rgb(self.sortColumn == i and Theme.color.accent or Theme.color.textMuted))
		end
		local rows = self.all
		if self.sortColumn then
			if sorted.all ~= self.all or sorted.column ~= self.sortColumn or sorted.descending ~= self.sortDescending then
				sorted.rows = UI.layout.sortRows(self.all, self.columns[self.sortColumn], self.sortDescending)
				sorted.all, sorted.column, sorted.descending = self.all, self.sortColumn, self.sortDescending
			end
			rows = sorted.rows
		end
		local shown = UI.layout.page(rows, self.page, self.size)
		self.page = shown.page
		for n = 1, math.max(#self.lines, #shown.rows) do
			local l = line(n)
			local row = shown.rows[n]
			l.row = row
			l:SetShown(row ~= nil)
			-- The chosen row (opts.isSelected) lit in the accent's soft shade.
			if row and opts.isSelected and opts.isSelected(row) then
				l.bg:SetVertexColor(Theme.rgb(Theme.color.accentSoft))
				l.bg:SetAlpha(1)
			else
				l.bg:SetVertexColor(Theme.rgb(Theme.color.surfaceHover))
				l.bg:SetAlpha(n % 2 == 0 and Theme.skin.radius and 0.45 or 0)
			end
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

-- The sidebar's rows for a search: each group's heading, then its pages whose label or title holds the
-- query (any case); a group with none left out. pages = { { key, label, title, group } } in order.
function UI.layout.navRows(pages, query)
	query = string.lower(query or "")
	local rows, group = {}, nil
	for _, p in ipairs(pages) do
		local hay = string.lower((p.label or "") .. " " .. (p.title or ""))
		local found, tab = query == "" or string.find(hay, query, 1, true), nil
		-- Else a tab's name: the page is found, opening on that tab.
		for _, t in ipairs(not found and p.tabs or {}) do
			if not tab and string.find(string.lower(t.label or ""), query, 1, true) then
				found, tab = true, t.key
			end
		end
		if found then
			if p.group and p.group ~= group then
				rows[#rows + 1] = { head = p.group }
			end
			group = p.group
			rows[#rows + 1] = { page = p, tab = tab }
		end
	end
	return rows
end

-- The addon's own footprint as the sidebar shows it: memory in kilobytes, CPU in milliseconds (or nil).
function UI.layout.footprint(kb, ms)
	local text = string.format("Memory %.1f MB", (kb or 0) / 1024)
	if ms then
		text = text .. string.format(" · CPU %.3f ms", ms)
	end
	return text
end

-- What the client says about the addon's memory and recent CPU time, when it says anything.
-- `fresh`: measure memory anew. UpdateAddOnMemoryUsage walks every addon loaded, which a big set of
-- addons makes slow enough for the client to stop it (manual test run 001: "exceeded its execution time
-- limit", about every 10 s while the hub was open); so only when asked, the last figure kept between.
local lastKb
local function footprint(addon, fresh)
	local kb, ms
	if fresh and UpdateAddOnMemoryUsage and GetAddOnMemoryUsage then
		UpdateAddOnMemoryUsage()
		lastKb = GetAddOnMemoryUsage(addon)
	end
	kb = lastKb
	if C_AddOnProfiler and C_AddOnProfiler.GetAddOnMetric and Enum and Enum.AddOnProfilerMetric then
		ms = C_AddOnProfiler.GetAddOnMetric(addon, Enum.AddOnProfilerMetric.RecentAverageTime)
	end
	return kb and UI.layout.footprint(kb, ms) or ""
end

local SIDE, HERO, FOOT, PAD = 236, 118, 56, 28

-- The main window, the hub (design 009, the playground's Hub v2): a sidebar with the brand, a search and
-- the pages in groups with an icon each, a large page title over the look's art, the page, and a footer
-- with Reload UI and Close; the addon's memory and CPU at the sidebar's foot. Drag it by any bare part;
-- Escape closes it. pages = { { key, label, icon, group, title, lede, build = function(content) } }: a
-- page is built the first time it is shown. Its position, page and scale are kept in `store`.
-- opts: width, height, version, look (the look's label for the footer), onReload.
function UI.Window(name, title, pages, store, opts)
	opts = opts or {}
	local skin = Theme.skin
	local web = skin.radius ~= nil
	local W, H = opts.width or 1000, opts.height or 660
	local w = UI.Panel(UIParent, { name = name, window = true, color = Theme.color.bg, borderColor = Theme.color.borderStrong })
	w:SetSize(W, H)
	w:SetFrameStrata("HIGH")
	-- Over the auction panel and the other HIGH frames when it opens or is clicked (manual test run 001:
	-- Rule › opened it under the panel).
	w:SetToplevel(true)
	w:SetClampedToScreen(true)
	w:SetMovable(true)
	w:EnableMouse(true)
	w:RegisterForDrag("LeftButton")
	w:SetScript("OnDragStart", function(self)
		self:StartMoving()
	end)
	w:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rel, x, y = self:GetPoint()
		store.point = { p, rel, x, y }
	end)
	-- Back to where the player left it, at the scale they set (the store is shared by every look's window).
	function w:Restore()
		self:SetScale(store.scale or 1)
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
	local decor = skin.decor

	-- The sidebar ----
	local side = CreateFrame("Frame", nil, w)
	side:SetPoint("TOPLEFT", inset, -inset)
	side:SetPoint("BOTTOMLEFT", inset, inset)
	side:SetWidth(SIDE - inset)
	if web then
		side.bg = surface(side, Theme.color.surface, decor and 0.55 or 1, nil, radius("window") - 1, { TOPRIGHT = true, BOTTOMRIGHT = true })
	else
		side.bg = solid(side, "BACKGROUND", "#000000", 0.3)
		side.bg:SetAllPoints()
	end
	local divider = solid(side, "BORDER", Theme.color.border)
	divider:SetPoint("TOPRIGHT")
	divider:SetPoint("BOTTOMRIGHT")
	divider:SetWidth(UI.pixel())

	local emblem = CreateFrame("Frame", nil, side)
	emblem:SetSize(44, 44)
	emblem:SetPoint("TOPLEFT", 20, -22)
	surface(emblem, Theme.color.accentSoft, 1, Theme.color.accent, radius("card"))
	local coin = UI.Icon(emblem, "coins", 24, "accent")
	coin:SetPoint("CENTER")
	if decor and decor.mark == "rune" then
		local glow = emblem:CreateTexture(nil, "ARTWORK", nil, -1)
		glow:SetTexture(Theme.media.glow)
		glow:SetBlendMode("ADD")
		glow:SetPoint("TOPLEFT", -10, 10)
		glow:SetPoint("BOTTOMRIGHT", 10, -10)
		local r, g, b = Theme.rgb(Theme.color.accent)
		glow:SetVertexColor(r, g, b, 0.35)
	end
	w.title = UI.Text(side, skin.titleCaps and string.upper(title) or title, { size = "xl", medium = true, tone = web and "text" or "accent" })
	w.title:SetPoint("TOPLEFT", emblem, "TOPRIGHT", 12, -2)
	local tagline = UI.Text(side, "FOR WOW: FOREVER", { size = "xs", tone = "faint" })
	tagline:SetPoint("TOPLEFT", w.title, "BOTTOMLEFT", 1, -5)

	local nav = CreateFrame("Frame", nil, side)
	nav:SetPoint("TOPLEFT", 8, -130)
	nav:SetPoint("BOTTOMRIGHT", -8, FOOT + 8)
	local search = UI.SearchBox(side, "Search pages…", function(text)
		if w.Filter then
			w:Filter(text)
		end
	end)
	search:SetPoint("TOPLEFT", 18, -88)
	search:SetWidth(SIDE - 36)

	local foot = solid(side, "BORDER", Theme.color.border)
	foot:SetPoint("BOTTOMLEFT", 0, FOOT)
	foot:SetPoint("BOTTOMRIGHT", 0, FOOT)
	foot:SetHeight(UI.pixel())
	local version = UI.Text(side, opts.version and ("v" .. opts.version) or "", { size = "xs", tone = "faint" })
	version:SetPoint("BOTTOMLEFT", 20, 32)
	local perf = UI.Text(side, "", { size = "xs", tone = "faint" })
	perf:SetPoint("BOTTOMLEFT", 20, 14)
	-- Memory when the window opens and when the line is clicked; the CPU (cheap to ask) every ten
	-- seconds while the window shows, and never while it is closed.
	local ticker
	local function measure(fresh)
		perf:SetText(footprint(opts.addon or "GoldForever", fresh))
	end
	local perfButton = CreateFrame("Button", nil, side)
	perfButton:SetAllPoints(perf)
	perfButton:SetScript("OnClick", function()
		ns.safely("footprint", measure, true)
	end)
	local function started()
		ns.safely("footprint", measure, true)
		if C_Timer and C_Timer.NewTicker and not ticker then
			ticker = C_Timer.NewTicker(10, function()
				ns.safely("footprint", measure, false)
			end)
		end
	end
	-- Opened again: the page in view shows what changed while it was closed (manual test run 001).
	w:SetScript("OnShow", function()
		w:Raise()
		started()
		local page = w.pages and w.pages[store.page]
		if page and page.Refresh then
			ns.safely("ui " .. store.page, page.Refresh, page)
		end
	end)
	w:SetScript("OnHide", function()
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
	end)

	-- The page header over the look's art ----
	local hero = CreateFrame("Frame", nil, w)
	hero:SetPoint("TOPLEFT", SIDE, -inset)
	hero:SetPoint("TOPRIGHT", -inset, -inset)
	hero:SetHeight(HERO)
	UI.HeroArt(hero, W - SIDE - inset, HERO)
	-- The title and its line in a frame over the art's.
	local words = CreateFrame("Frame", nil, hero)
	words:SetAllPoints()
	words:SetFrameLevel(hero:GetFrameLevel() + 2)
	w.pageTitle = UI.Text(words, "", { size = "xxl", medium = true })
	w.pageTitle:SetPoint("TOPLEFT", PAD, -30)
	w.pageLede = UI.Text(words, "", { size = "sm", tone = "muted", wrap = true })
	w.pageLede:SetPoint("TOPLEFT", PAD, -72)
	w.pageLede:SetWidth(W - SIDE - 160)
	local rule = solid(w, "BORDER", Theme.color.border)
	rule:SetPoint("TOPLEFT", hero, "BOTTOMLEFT")
	rule:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT")
	rule:SetHeight(UI.pixel())
	if decor and decor.rule then
		UI.gradient(rule, "HORIZONTAL", decor.rule)
	end
	-- A light sweeping along the rule: the Spark texture, added, moved by a looping Translation, inside
	-- a strip that clips it to the header's width.
	if decor and decor.shimmer then
		local strip = CreateFrame("Frame", nil, w)
		strip:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", 0, 1)
		strip:SetPoint("TOPRIGHT", hero, "BOTTOMRIGHT", 0, 1)
		strip:SetHeight(3)
		strip:SetClipsChildren(true)
		local inside = CreateFrame("Frame", nil, strip)
		inside:SetAllPoints()
		local light = inside:CreateTexture(nil, "OVERLAY")
		light:SetTexture(Theme.media.spark)
		light:SetBlendMode("ADD")
		light:SetSize(110, 3)
		light:SetPoint("RIGHT", strip, "LEFT", 0, 0)
		local sweep = light:CreateAnimationGroup()
		sweep:SetLooping("REPEAT")
		local move = sweep:CreateAnimation("Translation")
		move:SetOffset(W - SIDE + 110, 0)
		move:SetDuration(3.2)
		sweep:Play()
		w.shimmer = sweep
	end
	local close
	if skin.closeTemplate then
		close = CreateFrame("Button", nil, w, skin.closeTemplate)
		close:SetPoint("TOPRIGHT", hero, "TOPRIGHT", 2, 2)
	else
		close = UI.Button(w, "", nil, { kind = "ghost", width = 30, height = 30 })
		local x = UI.Icon(close, "x", 16, "muted")
		x:SetPoint("CENTER")
		close:SetPoint("TOPRIGHT", hero, "TOPRIGHT", -14, -14)
	end
	close:SetFrameLevel(hero:GetFrameLevel() + 5)
	close:SetScript("OnClick", function()
		w:Hide()
	end)

	-- The page ----
	local content = CreateFrame("Frame", nil, w)
	content:SetPoint("TOPLEFT", hero, "BOTTOMLEFT", PAD, -20)
	content:SetPoint("BOTTOMRIGHT", -PAD - inset, FOOT + 16)
	w.content = content

	-- The footer ----
	local footRule = solid(w, "BORDER", Theme.color.border)
	footRule:SetPoint("BOTTOMLEFT", SIDE, FOOT)
	footRule:SetPoint("BOTTOMRIGHT", -inset, FOOT)
	footRule:SetHeight(UI.pixel())
	local reload = UI.Button(w, "Reload UI", function()
		if opts.onReload then
			opts.onReload()
		elseif ReloadUI then
			ReloadUI()
		end
	end, { width = 130, height = 30 })
	reload:SetPoint("BOTTOMLEFT", SIDE + PAD, 13)
	local note = UI.Text(w, (opts.look and ("Look: " .. opts.look .. " · ") or "") .. "gold-forever.app", { size = "xs", tone = "faint", align = "CENTER" })
	note:SetPoint("BOTTOM", SIDE / 2, 22)
	local done = UI.Button(w, "Close", function()
		w:Hide()
	end, { kind = "primary", width = 130, height = 30 })
	done:SetPoint("BOTTOMRIGHT", -PAD - inset, 13)

	-- The sidebar's rows: a heading per group, a row per page; the search hides and restacks them.
	w.pages, w.items, w.heads = {}, {}, {}
	local byKey = {}
	for _, p in ipairs(pages) do
		byKey[p.key] = p
		local item = CreateFrame("Button", nil, nav)
		item.key = p.key
		item:SetHeight(32)
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
			edge:SetTexture(WHITE)
			edge:SetVertexColor(Theme.rgb(Theme.color.accent))
			edge:SetPoint("TOPLEFT")
			edge:SetPoint("BOTTOMLEFT")
			edge:SetWidth(2)
			item.bg.parts.edge = edge
		else
			item.bg = surface(item, Theme.color.accentSoft, 1, nil, radius("item"))
		end
		item.icon = UI.Icon(item, p.icon or "package", 17, "muted")
		item.icon:SetPoint("LEFT", 14, 0)
		item.label = UI.Text(item, p.label, { size = "md", medium = web, tone = "muted" })
		item.label:SetPoint("LEFT", 42, 0)
		item:SetScript("OnClick", function(self)
			w:SelectPage(p.key, self.tab)
		end)
		w.items[#w.items + 1] = item
		if p.group and not w.heads[p.group] then
			local head = CreateFrame("Frame", nil, nav)
			head:SetHeight(28)
			head.text = UI.Text(head, string.upper(p.group), { size = "xs", medium = true, tone = "accent" })
			head.text:SetPoint("BOTTOMLEFT", 12, 6)
			w.heads[p.group] = head
		end
	end
	local empty = UI.Text(nav, "No page matches.", { size = "sm", tone = "faint" })
	empty:SetPoint("TOPLEFT", 12, -8)
	function w:Filter(query)
		for _, item in ipairs(self.items) do
			item:Hide()
		end
		for _, head in pairs(self.heads) do
			head:Hide()
		end
		local y = 0
		local rows = UI.layout.navRows(pages, query)
		for _, row in ipairs(rows) do
			local f = row.head and self.heads[row.head]
			if row.page then
				for _, item in ipairs(self.items) do
					if item.key == row.page.key then
						f = item
						item.tab = row.tab
					end
				end
			end
			f:ClearAllPoints()
			f:SetPoint("TOPLEFT", 0, -y)
			f:SetPoint("TOPRIGHT", 0, -y)
			f:Show()
			y = y + f:GetHeight()
		end
		empty:SetShown(#rows == 0)
	end

	-- `tab`: the tab to open on a tabbed page (a search that matched it), else the page's last.
	function w:SelectPage(key, tab)
		local def = byKey[key] or pages[1]
		if not def then
			return
		end
		key = def.key
		for _, p in pairs(self.pages) do
			p:Hide()
		end
		for _, item in ipairs(self.items) do
			local on = item.key == key
			item.bg:SetAlpha(on and 1 or 0)
			item.label:SetTextColor(Theme.rgb(on and Theme.color.text or Theme.color.textMuted))
			item.icon:SetTone(on and "accent" or "muted")
		end
		self.pageTitle:SetText(def.title or def.label)
		self.pageLede:SetText(def.lede or "")
		local page = self.pages[key]
		if not page then
			page = CreateFrame("Frame", nil, content)
			page:SetAllPoints()
			-- A page can name itself more closely once it knows more (whose levelling it shows).
			function page.SetTitle(_, text)
				self.pageTitle:SetText(text)
			end
			page.title = def.title or def.label
			ns.safely("ui " .. key, def.build, page)
			self.pages[key] = page
		end
		page:Show()
		if tab and page.SelectTab then
			page.tab = tab
		end
		if page.Refresh then
			ns.safely("ui " .. key, page.Refresh, page)
		end
		store.page = key
	end
	w:Filter("")
	w:SelectPage(store.page or (pages[1] and pages[1].key))
	-- A new frame is shown already, so OnShow does not come for the first opening.
	if w:IsShown() then
		started()
	end
	return w
end
