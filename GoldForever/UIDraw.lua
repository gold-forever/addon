-- Gold Forever: the UI kit's drawing. The web app's components (frontend/src/design-system) in the
-- game's own frames, in the look the player picked (Theme.skin): the web's rounded, shadowed cards, or
-- the client's own dialog boxes. Everything on the pixel grid. Plain frames and Blizzard's plain
-- templates only (no secure ones), so every window can open in combat; nothing here reads a value the
-- client keeps secret.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI

local WHITE = "Interface\\Buttons\\WHITE8X8"


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
UI.box = box

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
UI.radius = radius

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
