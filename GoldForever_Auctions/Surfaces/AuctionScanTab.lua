-- Gold Forever: the auction panel's Scan tab: the full scan made visible: asking, reading N of M, the
-- cooldown, the last result. And the scan's line on the title row of Gold Forever's auction window
-- (gf#394), whichever tab is open: "Scanning, don't close" while it runs, then how it
-- ended.

local _, ns = ...
local L = ns.L
local Theme, UI = ns.Theme, ns.UI
local W = ns.ah.WIDTH

local function buildScan(page)
	local status = UI.Text(page, "", { size = "lg", medium = true })
	status:SetPoint("TOPLEFT", 0, 0)
	local bar = UI.Bar(page, 1, {}, 8)
	bar:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -10)
	bar:SetPoint("RIGHT", page, "RIGHT")
	local line = UI.Text(page, "", { size = "sm", tone = "muted" })
	line:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -10)
	local button = UI.Button(page, L["Scan now"], function()
		ns.startScan()
	end, { kind = "primary", width = 140, height = 30 })
	button:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -14)
	-- On at first (gf#394): a scan starts at every visit the cooldown allows.
	local scanSettings = ns.settings("scan")
	local auto = UI.Switch(page, scanSettings.auto, function(on)
		scanSettings.auto = on
	end)
	auto:SetPoint("LEFT", button, "RIGHT", 16, 0)
	local autoLabel = UI.Text(page, L["Scan when I open the auction house"], { size = "sm", tone = "muted" })
	autoLabel:SetPoint("LEFT", auto, "RIGHT", 8, 0)
	local cards = {}
	for i, label in ipairs({ L["Listings"], L["Prices"], L["Took"], L["Scanned"] }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth((W - 40 - 12) / 2)
		if i == 1 then
			c:SetPoint("TOPLEFT", button, "BOTTOMLEFT", 0, -20)
		elseif i % 2 == 0 then
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		else
			c:SetPoint("TOPLEFT", cards[i - 2], "BOTTOMLEFT", 0, -12)
		end
		cards[i] = c
	end
	local note = UI.Text(page, L["One full scan every 15 minutes per account: the server's limit. Sellers are never stored."], { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", cards[3], "BOTTOMLEFT", 0, -16)
	note:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local st = ns.scanState()
		if st.phase == "asking" then
			status:SetText(L["Asking the server..."])
			bar:Set(1, { { value = 0, color = Theme.color.accent } })
		elseif st.phase == "reading" then
			status:SetText(string.format(L["Reading %s of %s"], BreakUpLargeNumbers and BreakUpLargeNumbers(st.done) or st.done, BreakUpLargeNumbers and BreakUpLargeNumbers(st.total) or st.total))
			bar:Set(math.max(1, st.total), { { value = st.done, color = Theme.color.accent } })
		else
			status:SetText(st.wait > 0 and L["Scanned"] or L["Ready to scan"])
			bar:Set(1, { { value = st.wait > 0 and 1 or 0, color = Theme.color.accent } })
		end
		line:SetText(st.wait > 0 and string.format(L["Next full scan in %d:%02d"], math.floor(st.wait / 60), st.wait % 60) or L["A full scan can start now."])
		button:SetEnabled(st.wait <= 0 and st.phase == "idle")
		local last = st.last
		if not last then
			-- After a /reload: the newest full scan of the character's market in the save.
			local s = ns.price.latestScan()
			last = s and { t = s.t, auctions = s.auctions, prices = nil }
		end
		cards[1]:Set(last and tostring(last.auctions or 0) or "-", L["auctions read"])
		cards[2]:Set(last and last.prices and tostring(last.prices) or "-", L["item and price pairs"])
		cards[3]:Set(last and last.seconds and string.format(L["%d s"], last.seconds) or "-", L["asking and reading"])
		cards[4]:Set(last and ns.Views.ago(last.t, ns.now()) or L["never"], last and (last.kind == "partial" and L["cut short: not used"] or last.kind == "throttled" and L["the server said wait"]) or "")
	end
end

ns.AuctionScanTab = { key = "scan", label = L["Scan"], build = buildScan, refresh = function(page)
	page:Refresh()
end }

-- The status line -------------------------------------------------------------------------------------

-- The line's state, from Market.lua's "scanState" and the auction house opening: { phase, reason, since }.
local Line = {
	YELLOW = { 1, 0.82, 0 }, -- the game's own yellow, as GameFontNormal's
	GREEN = { 0.25, 1, 0.25 },
	RED = { 1, 0.3, 0.3 },
	PULSE = 1.6, -- seconds a pulse takes, full to dim and back
	DIM = 0.45, -- the pulse's lowest alpha: dimmed, never gone
	SHOWN = 10, -- seconds "Scan complete" stays before it fades
	FADE = 1.5,
}
ns.ScanLine = Line

local FAILED = {
	["cut short"] = L["Scan cut short"],
	throttled = L["Scan failed"],
}

function Line.idle()
	return { phase = "idle" }
end

-- The state after `event` ("scanning", "scanned", "failed" with its reason, or "opened") at `now`. A new
-- visit starts idle unless a scan still runs: the last visit's result is not this one's.
function Line.heard(state, event, reason, now)
	if event == "opened" then
		return state.phase == "scanning" and state or Line.idle()
	end
	return { phase = event, reason = reason, since = now }
end

-- What the line shows at `now`: { text, color, alpha }, or nil for nothing.
function Line.view(state, now)
	local elapsed = now - (state.since or now)
	if state.phase == "scanning" then
		local wave = (1 + math.cos(2 * math.pi * elapsed / Line.PULSE)) / 2
		return { text = L["Scanning, don't close"], color = Line.YELLOW, alpha = Line.DIM + (1 - Line.DIM) * wave }
	elseif state.phase == "scanned" then
		local fade = elapsed - Line.SHOWN
		if fade >= Line.FADE then
			return nil
		end
		return { text = L["Scan complete"], color = Line.GREEN, alpha = fade > 0 and 1 - fade / Line.FADE or 1 }
	elseif state.phase == "failed" then
		return { text = FAILED[state.reason] or FAILED.throttled, color = Line.RED, alpha = 1 }
	end
	return nil
end

local state = Line.idle()
local frame -- on AuctionHouseFrame, made at the first visit
-- For the smoke test.
function Line.frame()
	return frame
end

-- In Gold Forever's own auction window (owner, 2026-11-14): on the title row, at its right edge, in the
-- bank-and-mail line's small size. The window is rebuilt when the look changes, so the line follows
-- whichever one is current.
local function home()
	local panel = ns.ah.panel
	if not panel or frame.home == panel then
		return
	end
	frame.home = panel
	frame:SetParent(panel)
	frame:SetFrameLevel(panel:GetFrameLevel() + 20)
	frame:ClearAllPoints()
	frame:SetPoint("TOPRIGHT", panel, "TOPRIGHT", -16, -16)
end

-- The bank-and-mail line steps left of the scan line while it shows, back to the edge when it goes.
local function makeRoom(shown)
	local away = frame.home and frame.home.away
	if not away or away.besideScan == shown then
		return
	end
	away.besideScan = shown
	away:ClearAllPoints()
	if shown then
		away:SetPoint("TOPRIGHT", frame, "TOPLEFT", -12, 0)
	else
		away:SetPoint("TOPRIGHT", frame.home, "TOPRIGHT", -16, -16)
	end
end

-- Drawn every frame while the panel shows (the pulse and the fade); text set only as it changes.
local function draw()
	home()
	local v = Line.view(state, GetTime())
	frame.text:SetShown(v ~= nil)
	makeRoom(v ~= nil)
	if not v then
		return
	end
	if frame.shown ~= v.text then
		frame.shown = v.text
		frame.text:SetText(v.text)
		frame.text:SetTextColor(unpack(v.color))
		-- As wide as its words, so the line hugs the window's right edge.
		frame:SetWidth(math.ceil((frame.text:GetStringWidth() or 0) + 2))
	end
	frame.text:SetAlpha(v.alpha)
end

-- Made once, then placed in Gold Forever's panel by home(); none until the panel exists.
local function make()
	if frame or not ns.ah.panel then
		return frame
	end
	frame = CreateFrame("Frame", nil, ns.ah.panel)
	frame:SetSize(160, 18)
	frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
	frame.text:SetAllPoints()
	frame.text:SetJustifyH("RIGHT")
	frame:SetScript("OnUpdate", function()
		ns.safely("scan line", draw)
	end)
	return frame
end

ns.listen("scanState", "scan line", function(phase, reason)
	state = Line.heard(state, phase, reason, GetTime())
	if make() then
		draw()
	end
end)
local function opened()
	state = Line.heard(state, "opened", nil, GetTime())
	-- A scan that started before this file loaded is heard from where it stands.
	if state.phase ~= "scanning" and ns.scanState().phase ~= "idle" then
		state = Line.heard(state, "scanning", nil, GetTime())
	end
	if make() then
		draw()
	end
end
ns.on("AUCTION_HOUSE_SHOW", "scan line", opened)
-- Loaded as the auction house opened (on demand): that visit's opening came before this file.
ns.module("ScanLine", {
	enable = function()
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			opened()
		end
	end,
})
