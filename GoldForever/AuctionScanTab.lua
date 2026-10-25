-- Gold Forever: the auction panel's Scan tab: the full scan made visible: asking, reading N of M, the
-- cooldown, the last result.

local _, ns = ...
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
	local button = UI.Button(page, "Scan now", function()
		ns.startScan()
	end, { kind = "primary", width = 140, height = 30 })
	button:SetPoint("TOPLEFT", line, "BOTTOMLEFT", 0, -14)
	-- Off at first: a scan starts when the player asks (manual test run 001).
	local scanSettings = ns.settings("scan", { auto = false })
	local auto = UI.Switch(page, scanSettings.auto, function(on)
		scanSettings.auto = on
	end)
	auto:SetPoint("LEFT", button, "RIGHT", 16, 0)
	local autoLabel = UI.Text(page, "Scan when I open the auction house", { size = "sm", tone = "muted" })
	autoLabel:SetPoint("LEFT", auto, "RIGHT", 8, 0)
	local cards = {}
	for i, label in ipairs({ "Listings", "Prices", "Took", "Scanned" }) do
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
	local note = UI.Text(page, "One full scan every 15 minutes per account: the server's limit. Sellers are never stored.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", cards[3], "BOTTOMLEFT", 0, -16)
	note:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local st = ns.scanState()
		if st.phase == "asking" then
			status:SetText("Asking the server…")
			bar:Set(1, { { value = 0, color = Theme.color.accent } })
		elseif st.phase == "reading" then
			status:SetText(string.format("Reading %s of %s", BreakUpLargeNumbers and BreakUpLargeNumbers(st.done) or st.done, BreakUpLargeNumbers and BreakUpLargeNumbers(st.total) or st.total))
			bar:Set(math.max(1, st.total), { { value = st.done, color = Theme.color.accent } })
		else
			status:SetText(st.wait > 0 and "Scanned" or "Ready to scan")
			bar:Set(1, { { value = st.wait > 0 and 1 or 0, color = Theme.color.accent } })
		end
		line:SetText(st.wait > 0 and string.format("Next full scan in %d:%02d", math.floor(st.wait / 60), st.wait % 60) or "A full scan can start now.")
		button:SetEnabled(st.wait <= 0 and st.phase == "idle")
		local last = st.last
		if not last then
			-- After a /reload: the newest scan in the save.
			for _, s in ipairs(ns.db().scans or {}) do
				if s.kind == "full" and (not last or s.t > last.t) then
					last = { t = s.t, auctions = s.auctions, prices = nil }
				end
			end
		end
		cards[1]:Set(last and tostring(last.auctions or 0) or "—", "auctions read")
		cards[2]:Set(last and last.prices and tostring(last.prices) or "—", "item and price pairs")
		cards[3]:Set(last and last.seconds and (last.seconds .. " s") or "—", "asking and reading")
		cards[4]:Set(last and ns.Views.ago(last.t, ns.now()) or "never", last and (last.kind == "partial" and "cut short: not used" or last.kind == "throttled" and "the server said wait") or "")
	end
end

ns.AuctionScanTab = { key = "scan", label = "Scan", build = buildScan, refresh = function(page)
	page:Refresh()
end }
