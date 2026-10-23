-- Gold Forever: the design tokens, the same as the web app's (frontend/src/design-system/tokens.css),
-- so the addon's windows and the web pages look like one product: ink surfaces, a gold accent,
-- the game's own quality, class and coin colours, and a 4-pixel spacing grid.

local _, ns = ...

local Theme = {}
ns.Theme = Theme

-- "#e0ac45" -> 0.878, 0.675, 0.271: the client takes colours as 0–1 floats.
function Theme.rgb(hex)
	hex = string.gsub(hex, "^#", "")
	return tonumber(string.sub(hex, 1, 2), 16) / 255, tonumber(string.sub(hex, 3, 4), 16) / 255, tonumber(string.sub(hex, 5, 6), 16) / 255
end

-- "|cffe0ac45": the same colour as an escape for text.
function Theme.escape(hex)
	return "|cff" .. string.lower(string.gsub(hex, "^#", ""))
end

local INK = {
	["950"] = "#0a0c11", ["900"] = "#10131a", ["850"] = "#151922", ["800"] = "#1b202b", ["700"] = "#252b39",
	["600"] = "#333b4d", ["500"] = "#4a5367", ["400"] = "#6c7690", ["300"] = "#9ba4b9", ["200"] = "#c5cbd9", ["100"] = "#e7eaf1",
}

Theme.color = {
	bg = INK["950"],
	surface = INK["900"],
	surfaceRaised = INK["850"],
	surfaceHover = INK["800"],
	surfaceSunken = "#07080c",
	border = INK["700"],
	borderStrong = INK["600"],
	text = INK["100"],
	textMuted = INK["300"],
	textFaint = INK["400"],
	accent = "#e0ac45",
	accentStrong = "#efc565",
	accentSoft = "#33270f",
	accentContrast = INK["950"],
	focus = "#f6d78c",
	success = "#56c98f",
	warning = "#e9a93d",
	danger = "#e8615a",
	info = "#62a8f2",
	chart1 = "#3987e5",
	chart2 = "#d95926",
	chartMuted = INK["500"],
	chartGrid = INK["700"],
	xp = "#9a44c8",
	rested = "#3f86e0",
	gold = "#f2c94c",
	silver = "#c9ced6",
	copper = "#c97b3e",
	alliance = "#4a86e8",
	horde = "#d6453b",
}

-- Item quality 0 poor … 5 legendary, as the game draws them.
Theme.quality = { [0] = "#9d9d9d", "#ffffff", "#1eff00", "#0070dd", "#a335ee", "#ff8000" }

Theme.class = {
	WARRIOR = "#c69b6d", PALADIN = "#f48cba", HUNTER = "#aad372", ROGUE = "#fff468", PRIEST = "#ffffff",
	SHAMAN = "#0070dd", MAGE = "#3fc7eb", WARLOCK = "#8788ee", DRUID = "#ff7c0a",
}

-- The 4-pixel grid.
Theme.space = { [1] = 4, [2] = 8, [3] = 12, [4] = 16, [5] = 20, [6] = 24, [8] = 32, [10] = 40 }

-- Text sizes in points; the look in use sets them (Theme.apply).
Theme.text = { xs = 12, sm = 13, md = 14, lg = 16, xl = 20, xxl = 28 }

-- Looks ------------------------------------------------------------------------------------------------

-- Two looks, one setting (design 009; the web playground's Look switch is the reference). A look swaps
-- the tokens above in place, so code that reads Theme.color and Theme.text needs no change, and tells
-- UI.lua how to draw: the web's rounded, shadowed cards in a bundled Roboto, or the client's own
-- dialog boxes, red buttons and Friz Quadrata from files the game ships.

local MEDIA = "Interface\\AddOns\\GoldForever\\Media\\"
Theme.media = { round = MEDIA .. "Round.tga", shadow = MEDIA .. "Shadow.tga", glow = MEDIA .. "Glow.tga", rune = MEDIA .. "Rune.tga", spark = MEDIA .. "Spark.tga" }

-- An icon's file: Lucide's shapes in white (tools/icons.sh), tinted where they are drawn.
function Theme.icon(name)
	return MEDIA .. "Icons\\" .. name .. ".tga"
end

Theme.skins = {
	web = {
		name = "web",
		label = "Web",
		font = MEDIA .. "Roboto-Regular.ttf",
		fontMedium = MEDIA .. "Roboto-Medium.ttf",
		-- The site's rem sizes at 16 px.
		text = { xs = 12, sm = 13, md = 14, lg = 16, xl = 20, xxl = 28 },
		color = {},
		textShadow = false,
		-- Corner radii in pixels: rounded with the Round texture, cut in nine.
		radius = { window = 12, card = 8, control = 8, tab = 5, item = 6 },
		windowShadow = true,
		tabs = "segmented",
		badgeFill = 0.16,
		-- The page header's art: a gradient top to bottom and soft lights (Glow, added) at fractions of
		-- its width and height, sized in pixels.
		hero = { top = "#171c27", bottom = "#10131a", lights = { { "#e0ac45", 0.22, 0.88, 0, 520, 260 }, { "#3987e5", 0.14, 0.08, 1, 360, 220 } } },
	},
	classic = {
		name = "classic",
		label = "Classic",
		font = "Fonts\\FRIZQT__.TTF",
		fontMedium = "Fonts\\FRIZQT__.TTF",
		-- GameFontNormalSmall 10, GameFontNormal 12, GameFontNormalLarge 16, GameFontNormalHuge 20.
		text = { xs = 10, sm = 11, md = 12, lg = 14, xl = 16, xxl = 20 },
		color = {
			bg = "#000000", surface = "#0a0a0b", surfaceRaised = "#151515", surfaceHover = "#222222", surfaceSunken = "#000000",
			border = "#4a4a4a", borderStrong = "#8b8b8b",
			text = "#ffffff", textMuted = "#d8cfb4", textFaint = "#9d9d9d",
			accent = "#ffd100", accentStrong = "#ffe566", accentSoft = "#3a3000", accentContrast = "#ffd100", focus = "#ffd100",
			success = "#1eff00", warning = "#ff8000", danger = "#ff2020", info = "#3fc7eb",
		},
		textShadow = true,
		-- The client's own files: the dark dialog background with the tooltip's grey edge, the
		-- red panel buttons, the quest log's highlight.
		backdrop = {
			bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
			edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
			tile = true, tileSize = 32, edgeSize = 16,
			insets = { left = 4, right = 4, top = 4, bottom = 4 },
		},
		buttonTemplate = "UIPanelButtonTemplate",
		closeTemplate = "UIPanelCloseButton",
		highlight = "Interface\\QuestFrame\\UI-QuestLogTitleHighlight",
		tabs = "tabs",
		badgeFill = 0,
		hero = { top = "#1c1c1e", bottom = "#08080a", lights = { { "#ffd100", 0.16, 0.85, 0, 480, 240 } } },
	},
	-- Indigo lit from within: a violet light at the top, a cyan glow around the window, runes at its
	-- corners, a cyan-to-violet rule with a light sweeping along it, gradient buttons that breathe. The
	-- web playground's Arcane look (/design/addon?look=arcane) is the reference.
	arcane = {
		name = "arcane",
		label = "Arcane",
		font = MEDIA .. "Exo2-Regular.ttf",
		fontMedium = MEDIA .. "Exo2-SemiBold.ttf",
		text = { xs = 11, sm = 12, md = 13, lg = 15, xl = 19, xxl = 26 },
		color = {
			bg = "#05060f", surface = "#0c0e22", surfaceRaised = "#141838", surfaceHover = "#1c2150", surfaceSunken = "#070818",
			border = "#2a2f6a", borderStrong = "#4a52a8",
			text = "#e6e9ff", textMuted = "#a3a9e0", textFaint = "#6f75b0",
			accent = "#6ee7ff", accentStrong = "#a7f3ff", accentSoft = "#123048", accentContrast = "#04121a", focus = "#a7f3ff",
			success = "#5df2b0", warning = "#ffc56b", danger = "#ff6b8a", info = "#b48cff",
		},
		-- A FontString's shadow: an offset and a colour, never a blur.
		textShadow = { 0, -1, "#00001e", 0.8 },
		titleCaps = true,
		radius = { window = 10, card = 8, control = 6, tab = 5, item = 6 },
		windowShadow = true,
		tabs = "segmented",
		badgeFill = 0.14,
		-- Lights in violet and cyan, and a few stars (Rune points) over them.
		hero = {
			top = "#141638", bottom = "#090a1c",
			lights = { { "#b48cff", 0.4, 0.8, 0.1, 460, 260 }, { "#6ee7ff", 0.25, 0.2, 1, 380, 220 } },
			stars = { { 0.12, 0.3, "#ffffff" }, { 0.31, 0.62, "#a7f3ff" }, { 0.46, 0.22, "#ffffff" }, { 0.63, 0.7, "#a7f3ff" }, { 0.77, 0.38, "#ffffff" }, { 0.93, 0.64, "#a7f3ff" } },
		},
		decor = {
			-- The window's background, top to bottom, and the light at its top (Glow, added).
			gradient = { "#10122c", 0.95, "#06070f", 0.97 },
			innerLight = { "#7a5aff", 0.35 },
			-- The glow around the window: the Shadow texture in cyan, added.
			glow = { "#6ee7ff", 0.22 },
			corners = "rune",
			mark = "rune",
			-- The title band and its rule, left to right; the light that sweeps along the rule.
			band = { "#6ee7ff", 0.12, "#b48cff", 0.12 },
			rule = { "#6ee7ff", 1, "#b48cff", 1 },
			shimmer = true,
			-- The primary button, left to right, its text, and the glow that breathes in it.
			primary = { "#4fd1ff", 1, "#9b6bff", 1 },
			primaryText = "#04121a",
			pulse = true,
			-- A chosen row: the accent fading out to the right, with a bar at its left edge.
			selected = { "#6ee7ff", 0.24, "#b48cff", 0.04 },
			-- A bar's fill and the spark at its end.
			bar = { "#6ee7ff", 1, "#b48cff", 1 },
			spark = true,
		},
	},
}

-- The looks in the order the window's button and the minimap's right-click step through them.
Theme.order = { "web", "classic", "arcane" }

-- The look after `name`, round the list.
function Theme.nextLook(name)
	for i, n in ipairs(Theme.order) do
		if n == name then
			return Theme.order[i % #Theme.order + 1]
		end
	end
	return Theme.order[1]
end

-- The web's tokens as written above, before any look changed them.
local BASE_COLOR, BASE_TEXT = {}, {}
for k, v in pairs(Theme.color) do
	BASE_COLOR[k] = v
end
for k, v in pairs(Theme.text) do
	BASE_TEXT[k] = v
end

-- "#rrggbb" a share `t` of the way from `a` to `b`.
function Theme.mix(a, b, t)
	local ar, ag, ab = Theme.rgb(a)
	local br, bg, bb = Theme.rgb(b)
	local function channel(x, y)
		return math.floor((x + (y - x) * t) * 255 + 0.5)
	end
	return string.format("#%02x%02x%02x", channel(ar, br), channel(ag, bg), channel(ab, bb))
end

-- The accent colours a player can put over any look (Settings), as the web playground offers them.
Theme.accents = {
	{ hex = "#e0ac45", label = "Gold" },
	{ hex = "#2fd1a8", label = "Teal" },
	{ hex = "#d6453b", label = "Horde red" },
	{ hex = "#4a86e8", label = "Alliance blue" },
	{ hex = "#a77bff", label = "Violet" },
}

-- Puts a look's tokens into Theme.color and Theme.text and makes it Theme.skin. Unknown names get the
-- web look. An `accent` ("#rrggbb") goes over the look's own: lighter for its strong shade, mixed into
-- the background for its soft one.
function Theme.apply(name, accent)
	local skin = Theme.skins[name] or Theme.skins.web
	for k, v in pairs(BASE_COLOR) do
		Theme.color[k] = skin.color[k] or v
	end
	for k, v in pairs(BASE_TEXT) do
		Theme.text[k] = skin.text[k] or v
	end
	if accent and string.match(accent, "^#%x%x%x%x%x%x$") then
		Theme.color.accent = accent
		Theme.color.accentStrong = Theme.mix(accent, "#ffffff", 0.3)
		Theme.color.accentSoft = Theme.mix(Theme.color.bg, accent, 0.2)
		Theme.color.focus = Theme.color.accentStrong
	end
	Theme.skin = skin
	Theme.accent = Theme.color.accent
	-- Which look and accent are in: a panel built under another key redraws itself.
	Theme.key = skin.name .. Theme.color.accent
	return skin
end

Theme.apply("web")
