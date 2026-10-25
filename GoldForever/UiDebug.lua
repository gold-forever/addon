-- Gold Forever: "/gf uidebug", a report of the auction panel's widgets for a bug report.

local _, ns = ...
local Theme = ns.Theme
local ah = ns.ah

-- "/gf uidebug": what the client says of the widgets seen without their text (manual test run 001: Buy's
-- Remove, Sell's Rule › and quantity box, now and then right after opening), and every shown frame that
-- overlaps one and is drawn over it, in a box to copy.
local STRATA = { BACKGROUND = 1, LOW = 2, MEDIUM = 3, HIGH = 4, DIALOG = 5, FULLSCREEN = 6, FULLSCREEN_DIALOG = 7, TOOLTIP = 8 }
local function num(x)
	return type(x) == "number" and string.format("%.1f", x) or tostring(x)
end
local function call(obj, method)
	return obj and obj[method] and num(obj[method](obj)) or "-"
end
local function frameName(f)
	return (f.GetDebugName and f:GetDebugName()) or (f.GetName and f:GetName()) or tostring(f)
end
-- Whether `a` is `b` or inside it.
local function within(a, b)
	while a do
		if a == b then
			return true
		end
		a = a.GetParent and a:GetParent()
	end
	return false
end
local function covering(w, out)
	if not (EnumerateFrames and w.GetRect) then
		return
	end
	local l, b, wd, ht = w:GetRect()
	if not l then
		out[#out + 1] = "    (no rect)"
		return
	end
	local strata, level = STRATA[w:GetFrameStrata()] or 0, w:GetFrameLevel() or 0
	local found, f = 0, EnumerateFrames()
	-- One frame looked at; a forbidden one (the client's own, closed to addons) errors and is skipped.
	local function look(f)
		if f == w or not f:IsVisible() or within(w, f) or within(f, w) then
			return
		end
		local fl, fb, fw, fh = f:GetRect()
		if fl and fl < l + wd and fl + fw > l and fb < b + ht and fb + fh > b then
			local fs, flv = STRATA[f:GetFrameStrata()] or 0, f:GetFrameLevel() or 0
			if fs > strata or (fs == strata and flv >= level) then
				found = found + 1
				out[#out + 1] = string.format("    over it: %s %s/%d at %.0f,%.0f %.0fx%.0f alpha %.2f", frameName(f), f:GetFrameStrata(), flv, fl, fb, fw, fh, f:GetEffectiveAlpha() or -1)
			end
		end
	end
	while f and found < 15 do
		pcall(look, f)
		f = EnumerateFrames(f)
	end
	if found == 0 then
		out[#out + 1] = "    nothing shown over it"
	end
end
local function describe(label, w, out)
	if not w then
		out[#out + 1] = "  " .. label .. ": not made"
		return
	end
	local fs = w.label or (w.GetFontString and w:GetFontString())
	local font, size
	if fs and fs.GetFont then
		font, size = fs:GetFont()
	elseif w.GetFont then
		font, size = w:GetFont()
	end
	out[#out + 1] = "  " .. label .. ": shown " .. call(w, "IsShown") .. " visible " .. call(w, "IsVisible") .. " alpha " .. call(w, "GetAlpha")
		.. "/" .. call(w, "GetEffectiveAlpha") .. " size " .. call(w, "GetWidth") .. "x" .. call(w, "GetHeight") .. " at " .. call(w, "GetLeft") .. "," .. call(w, "GetBottom")
		.. " strata " .. call(w, "GetFrameStrata") .. " level " .. call(w, "GetFrameLevel")
		.. " text [" .. call(w, "GetText") .. "] fs [" .. call(fs, "GetText") .. "] fs shown " .. call(fs, "IsShown") .. " fs alpha " .. call(fs, "GetAlpha")
		.. " fs width " .. call(fs, "GetStringWidth") .. " fs at " .. call(fs, "GetLeft") .. "," .. call(fs, "GetBottom")
		.. " font " .. tostring(font) .. " " .. num(size)
	covering(w, out)
end
ns.commands.uidebug = function()
	local out, n = {}, 0
	out[#out + 1] = string.format("Gold Forever %s, %s, interface %s", tostring(ns.db() and ns.db().addon), date and date("%Y-%m-%d %H:%M:%S") or "", tostring(select(4, GetBuildInfo())))
	for key, p in pairs(ah.panels) do
		n = n + 1
		out[#out + 1] = string.format("panel %s: shown %s, tab %s, the one in use %s, strata %s level %s", key, tostring(p:IsShown()), tostring(p.tab), tostring(p == ah.panel), tostring(p:GetFrameStrata()), tostring(p:GetFrameLevel()))
	end
	out[#out + 1] = string.format("  %d panels; Theme.key %s; built %s", n, tostring(Theme.key), tostring(ah.built))
	if ah.panel then
		describe("Buy Edit lists", ah.panel.shop and ah.panel.shop.editLists, out)
		describe("Sell Rule", ah.panel.post and ah.panel.post.ruleButton, out)
		describe("Sell quantity box", ah.panel.post and ah.panel.post.quantity and ah.panel.post.quantity.readout, out)
		describe("Sell Post button", ah.panel.post and ah.panel.post.button, out)
	end
	local text = table.concat(out, "\n")
	ns.showCopy("Gold Forever: widget report", text)
end
