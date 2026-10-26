-- Gold Forever: the UI kit's dropdown (UI.Dropdown), in the look in use.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local solid, surface, radius = UI.solid, UI.surface, UI.radius

-- A dropdown: a button with the chosen option's label and a chevron; a click opens a menu of the options
-- under it, over everything. options = { { value, label } }; onChange(value) when one is picked. The menu
-- closes on a pick, a click anywhere else or Escape; past MENU_ROWS options it scrolls with the wheel.
local MENU_ROWS = 12
local dropdowns = 0
function UI.Dropdown(parent, options, value, onChange)
	local d = CreateFrame("Button", nil, parent)
	d:SetHeight(28)
	d.bg, d.rim = surface(d, Theme.color.surfaceSunken, 1, Theme.color.borderStrong, radius("control"))
	d.text = UI.Text(d, "", { size = "sm" })
	d.text:SetPoint("LEFT", 10, 0)
	d.text:SetPoint("RIGHT", -28, 0)
	d.chevron = UI.Icon(d, "chevron-down", 14, "muted")
	d.chevron:SetPoint("RIGHT", -10, 0)
	-- Named, so Escape closes it as it closes the game's own menus.
	dropdowns = dropdowns + 1
	local name = "GoldForeverDropdownMenu" .. dropdowns
	local menu = UI.Panel(d, { name = name, color = Theme.color.surfaceRaised, borderColor = Theme.color.borderStrong, radius = radius("control") })
	if UISpecialFrames then
		table.insert(UISpecialFrames, name)
	end
	menu:SetFrameStrata("FULLSCREEN_DIALOG")
	menu:SetPoint("TOPLEFT", d, "BOTTOMLEFT", 0, -2)
	menu:SetPoint("TOPRIGHT", d, "BOTTOMRIGHT", 0, -2)
	menu:EnableMouse(true)
	menu:Hide()
	menu.rows, menu.offset = {}, 0
	-- The rows from the scroll offset on, MENU_ROWS at most.
	local function place()
		menu.offset = math.max(0, math.min(menu.offset, #options - MENU_ROWS))
		for i = 1, #options do
			local row, at = menu.rows[i], i - menu.offset
			row:ClearAllPoints()
			row:SetPoint("TOPLEFT", 4, -4 - (at - 1) * 24)
			row:SetPoint("TOPRIGHT", -4, -4 - (at - 1) * 24)
			row:SetShown(at >= 1 and at <= MENU_ROWS)
		end
	end
	menu:EnableMouseWheel(true)
	menu:SetScript("OnMouseWheel", function(_, delta)
		menu.offset = menu.offset - delta
		place()
	end)
	-- A click outside the menu and its button closes it.
	menu:SetScript("OnUpdate", function(self)
		if IsMouseButtonDown and (IsMouseButtonDown("LeftButton") or IsMouseButtonDown("RightButton"))
			and not self:IsMouseOver() and not d:IsMouseOver() then
			self:Hide()
		end
	end)
	-- The choices, again when they change (a list added, an override removed): the rows are reused, as
	-- frames are never freed. The value shown is set again, `v` or the one chosen before, as its label
	-- may have changed.
	function d:SetOptions(list, v)
		options = list
		menu:SetHeight(math.min(#options, MENU_ROWS) * 24 + 8)
		for i, o in ipairs(options) do
			local row = menu.rows[i]
			if not row then
				row = CreateFrame("Button", nil, menu)
				row:SetHeight(24)
				row.hover = surface(row, Theme.color.surfaceHover, 1, nil, radius("item"))
				row.hover:SetShown(false)
				row.text = UI.Text(row, "", { size = "sm" })
				row.text:SetPoint("LEFT", 8, 0)
				row:SetScript("OnEnter", function(self)
					self.hover:SetShown(true)
				end)
				row:SetScript("OnLeave", function(self)
					self.hover:SetShown(false)
				end)
				row:SetScript("OnClick", function(self)
					menu:Hide()
					d:Set(self.value)
					if onChange then
						onChange(self.value)
					end
				end)
				menu.rows[i] = row
			end
			row.text:SetText(o.label)
			row.value = o.value
		end
		for i = #options + 1, #menu.rows do
			menu.rows[i]:Hide()
		end
		place()
		if self.Set then
			self:Set(v == nil and self.value or v)
		end
	end
	d:SetOptions(options)
	function d:Set(v)
		self.value = v
		local label = v
		for _, o in ipairs(options) do
			if o.value == v then
				label = o.label
			end
		end
		self.text:SetText(label)
		for i = 1, #options do
			local row = menu.rows[i]
			row.text:SetTextColor(Theme.rgb(row.value == v and Theme.color.accent or Theme.color.text))
		end
	end
	d:SetScript("OnClick", function()
		menu:SetShown(not menu:IsShown())
	end)
	d:SetScript("OnHide", function()
		menu:Hide()
	end)
	d.menu = menu
	d:Set(value)
	return d
end
