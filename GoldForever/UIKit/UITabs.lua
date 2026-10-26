-- Gold Forever: the UI kit's tabs (UI.TabBar), in the look in use.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local solid, surface, radius = UI.solid, UI.surface, UI.radius

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
