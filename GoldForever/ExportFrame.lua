-- Gold Forever: /gf export, the string a player copies into the site's Upload page (design 005).
-- `/gf export` holds what is new since the last export; `/gf export all` holds everything again.

local _, ns = ...
local UI, Export, Theme = ns.UI, ns.Export, ns.Theme

local SITE = "gold-forever.app/me/upload"
local DEFLATE = { level = Export.LEVEL }
-- The player waits on an export: a larger share of each frame than background work, still far under
-- what the client lets a script run.
local EXPORT_MS = 20

local building -- when the export being built began; one the client stopped is let go after a minute

local frame

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

-- What the string holds counts as sent once the player copies it (review B-26): closed without copying,
-- the next export holds it again.
local function copied()
	local pending = frame.pending
	if pending then
		frame.pending = nil
		local db = ns.db()
		db.exportedAt = pending.now
		Export.markSent(db, pending.picked)
	end
	frame.summary:SetText("Copied. Paste it at " .. SITE)
end

local function build()
	frame = UI.Dialog({ name = "GoldForeverExport", width = 560, height = 190, at = { "CENTER" }, strata = "DIALOG", movable = true,
		title = "Gold Forever export" })
	-- Closed without copying: nothing counts as sent, and what it held is let go.
	frame:SetScript("OnHide", function()
		frame.pending = nil
	end)

	frame.summary = UI.Text(frame, "", { tone = "muted" })
	frame.summary:SetPoint("TOPLEFT", frame.heading, "BOTTOMLEFT", 0, -6)
	local how = UI.Text(frame, "Press Ctrl+C to copy, then paste it at " .. SITE, { tone = "faint" })
	how:SetPoint("TOPLEFT", frame.summary, "BOTTOMLEFT", 0, -6)

	-- One line: a long string shows far faster in a single-line box than a scrolling one. All of it
	-- stays selected, so Ctrl+C takes it whole; typing puts it back.
	local box = CreateFrame("EditBox", nil, frame)
	box:SetPoint("TOPLEFT", how, "BOTTOMLEFT", 0, -10)
	box:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
	box:SetHeight(26)
	box:SetAutoFocus(false)
	box:SetMaxLetters(0)
	box:SetFontObject(ChatFontNormal)
	box:SetTextInsets(8, 8, 0, 0)
	box:SetTextColor(Theme.rgb(Theme.color.text))
	UI.border(box, Theme.color.borderStrong)
	box:SetScript("OnEscapePressed", function()
		frame:Hide()
	end)
	box:SetScript("OnTextChanged", function(self, typed)
		if typed and frame.text then
			self:SetText(frame.text)
			self:HighlightText()
		end
	end)
	box:SetScript("OnEditFocusGained", function(self)
		self:HighlightText()
	end)
	box:SetScript("OnKeyUp", function(_, key)
		if key == "C" and IsControlKeyDown() then
			ns.safely("export", copied)
		end
	end)
	frame.box = box

	local close = UI.Button(frame, "Close", function()
		frame:Hide()
	end)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
end

local function show(text, picked, now)
	if not frame then
		build()
	end
	local scans, days = #picked.scans, count(picked.events)
	frame.text = text
	frame.pending = { picked = picked, now = now }
	frame.summary:SetText(string.format("%d characters, %d %s of play, %d auction %s · %d characters of text",
		count(picked.characters), days, days == 1 and "day" or "days", scans, scans == 1 and "scan" or "scans", #text))
	frame.box:SetText(text)
	frame:Show()
	frame.box:SetFocus()
	frame.box:HighlightText()
end

-- `/gf export`, or `/gf export all` for everything again. Built over frames: a heavy save is several
-- seconds of work.
ns.commands.export = function(arg)
	if building and GetTime() - building < 60 then
		ns.say("the export is still being built.")
		return
	end
	local db = ns.db()
	local LibDeflate = LibStub("LibDeflate")
	local now = ns.now()
	local since = string.lower(arg or "") ~= "all" and db.exportedAt or nil
	local step = Export.builder(db, since, now, function(part)
		return LibDeflate:CompressDeflate(part, DEFLATE)
	end)
	building = GetTime()
	local told = false
	local function more()
		local started = ns.frameStart()
		local ok, text, picked = pcall(step, function(done)
			return ns.frameSpent(started, done, 100, EXPORT_MS)
		end)
		if not ok then
			building = nil
			error(text, 0)
		end
		if not text then
			if not told then
				told = true
				ns.say("building the export: a few seconds for a big save.")
			end
			ns.after(0, "export", more)
			return
		end
		building = nil
		show(text, picked, now)
	end
	more()
end

-- A box of text to copy: a report the player pastes into a bug report (/gf uidebug). Many lines,
-- scrolling; all of it selected so Ctrl+C takes it whole.
local copy
function ns.showCopy(title, text)
	if not copy then
		copy = UI.Dialog({ name = "GoldForeverCopy", width = 640, height = 420, at = { "CENTER" }, strata = "DIALOG", movable = true, title = "" })
		local how = UI.Text(copy, "Ctrl+A, then Ctrl+C to copy it all.", { tone = "faint" })
		how:SetPoint("TOPLEFT", copy.heading, "BOTTOMLEFT", 0, -6)
		local scroll = CreateFrame("ScrollFrame", nil, copy, "UIPanelScrollFrameTemplate")
		scroll:SetPoint("TOPLEFT", how, "BOTTOMLEFT", 0, -10)
		scroll:SetPoint("BOTTOMRIGHT", -36, 52)
		local box = CreateFrame("EditBox", nil, scroll)
		box:SetMultiLine(true)
		box:SetAutoFocus(false)
		box:SetMaxLetters(0)
		box:SetFontObject(ChatFontNormal)
		box:SetWidth(580)
		box:SetTextColor(Theme.rgb(Theme.color.text))
		box:SetScript("OnEscapePressed", function()
			copy:Hide()
		end)
		box:SetScript("OnTextChanged", function(self, typed)
			if typed and copy.text then
				self:SetText(copy.text)
				self:HighlightText()
			end
		end)
		scroll:SetScrollChild(box)
		copy.box = box
		local close = UI.Button(copy, "Close", function()
			copy:Hide()
		end)
		close:SetPoint("BOTTOMRIGHT", -16, 14)
	end
	copy.heading:SetText(title)
	copy.text = text
	copy.box:SetText(text)
	copy:Show()
	copy:Raise()
	copy.box:SetFocus()
	copy.box:HighlightText()
end

-- For the smoke test.
function ns.exportFrame()
	return frame
end
