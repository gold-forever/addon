-- Gold Forever: money as text, one formatter for the whole addon. Pure Lua with no game API but the
-- client's coin icons and number separator where it has them, so it is tested outside the client.
--
-- Money.format(copper, mode, precision), the mode one of:
--   "plain"   every unit from the largest there is, "1g 9s 25c" (the chat, the trainer line);
--   "colour"  in the game's coin colours, the larger units only when there are any; precision "gold"
--             drops silver and copper above a gold, "silver" the copper ("8g 69s");
--   "cell"    as "colour" for a table cell: a faint dash for nothing, gold and silver unless told;
--   "icons"   with the client's coin icons, from a gold up gold and silver only (the tooltips), else plain.

local _, ns = ...

local Money = {}
ns.Money = Money

-- Retail has the function under C_CurrencyInfo (manual test run 001: the tooltips showed plain text).
local coinTexture = (C_CurrencyInfo and C_CurrencyInfo.GetCoinTextureString) or GetCoinTextureString

-- A whole number in groups of three, with the client's separator ("3,000,000").
function Money.group(n)
	local sign, digits = string.match(tostring(math.floor(n or 0)), "^(%-?)(%d+)$")
	local sep = LARGE_NUMBER_SEPARATOR or ","
	local out = string.gsub(string.reverse(digits or "0"), "(%d%d%d)", "%1" .. sep)
	out = string.reverse(out)
	if string.sub(out, 1, #sep) == sep then
		out = string.sub(out, #sep + 1)
	end
	return (sign or "") .. out
end

local function plain(copper)
	copper = math.floor(copper + 0.5)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	if g > 0 then
		return string.format("%dg %ds %dc", g, s, c)
	elseif s > 0 then
		return string.format("%ds %dc", s, c)
	end
	return string.format("%dc", c)
end

local function colour(copper, precision)
	local Theme = ns.Theme
	copper = math.floor((copper or 0) + 0.5)
	local sign = copper < 0 and "-" or ""
	copper = math.abs(copper)
	local g, s, c = math.floor(copper / 10000), math.floor(copper / 100) % 100, copper % 100
	local function coin(n, unit, hex)
		return Theme.escape(hex) .. n .. unit .. "|r"
	end
	local parts = {}
	if g > 0 then
		parts[#parts + 1] = coin(Money.group(g), "g", Theme.color.gold)
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
local function cell(copper, precision)
	if math.floor(math.abs(copper or 0) + 0.5) == 0 then
		local Theme = ns.Theme
		return Theme.escape(Theme.color.textFaint) .. "—|r"
	end
	return colour(copper, precision or "silver")
end

-- Money with the game's coin icons, as its own Sell Price line; from a gold up, gold and silver only.
local function icons(copper)
	copper = math.floor(copper + 0.5)
	if copper >= 10000 then
		copper = math.floor(copper / 100) * 100
	end
	if coinTexture then
		return coinTexture(copper)
	end
	return plain(copper)
end

local MODES = { plain = plain, colour = colour, cell = cell, icons = icons }

function Money.format(copper, mode, precision)
	return MODES[mode or "plain"](copper, precision)
end
