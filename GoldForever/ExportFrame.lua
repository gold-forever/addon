-- Gold Forever: /gf export, the string a player copies into the site's Upload page (design 005).
-- `/gf export` holds what is new since the last export; `/gf export all` holds everything again.

local _, ns = ...
local UI, Export, Theme = ns.UI, ns.Export, ns.Theme

local SITE = "gold-forever.app/me/upload"
-- The highest level: a first export is a third smaller than at the default, for half a second more.
local DEFLATE = { level = 9 }

local frame

local function count(t)
	local n = 0
	for _ in pairs(t or {}) do
		n = n + 1
	end
	return n
end

local function build()
	frame = UI.Panel(UIParent, { name = "GoldForeverExport" })
	frame:SetSize(560, 190)
	frame:SetPoint("CENTER")
	frame:SetFrameStrata("DIALOG")
	frame:SetMovable(true)
	frame:EnableMouse(true)
	frame:RegisterForDrag("LeftButton")
	frame:SetScript("OnDragStart", frame.StartMoving)
	frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
	table.insert(UISpecialFrames, "GoldForeverExport") -- Escape closes it

	local title = UI.Text(frame, "Gold Forever export", { size = "lg" })
	title:SetPoint("TOPLEFT", 16, -14)
	frame.summary = UI.Text(frame, "", { tone = "muted" })
	frame.summary:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -6)
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
			frame.summary:SetText("Copied. Paste it at " .. SITE)
		end
	end)
	frame.box = box

	local close = UI.Button(frame, "Close", function()
		frame:Hide()
	end)
	close:SetPoint("BOTTOMRIGHT", -16, 14)
end

local function show(text, picked)
	if not frame then
		build()
	end
	local scans, days = #picked.scans, count(picked.events)
	frame.text = text
	frame.summary:SetText(string.format("%d characters, %d %s of play, %d auction %s · %d characters of text",
		count(picked.characters), days, days == 1 and "day" or "days", scans, scans == 1 and "scan" or "scans", #text))
	frame.box:SetText(text)
	frame:Show()
	frame.box:SetFocus()
	frame.box:HighlightText()
end

-- `/gf export`, or `/gf export all` for everything again.
ns.commands.export = function(arg)
	local db = ns.db()
	local LibDeflate = LibStub("LibDeflate")
	local now = ns.now()
	local since = string.lower(arg or "") ~= "all" and db.exportedAt or nil
	local text, picked = Export.build(db, since, now, function(raw)
		return LibDeflate:CompressDeflate(raw, DEFLATE)
	end)
	db.exportedAt = now
	Export.markSent(db, picked)
	show(text, picked)
end
