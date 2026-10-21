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

-- Text sizes in points, as the web's rem sizes at 16 px.
Theme.text = { xs = 11, sm = 12, md = 13, lg = 15, xl = 18, xxl = 24 }
