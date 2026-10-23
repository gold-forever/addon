-- Gold Forever: the ways in that need no slash command (design 009, Phase 0). A button on the minimap's
-- rim (drag it around; left-click the window, right-click the other look), the addon compartment's entry
-- on clients that have one, and key bindings (Bindings.xml) for the window and the look. Built at login,
-- once the saved settings are read; dragging is the only time it runs code every frame.

local _, ns = ...
local Theme = ns.Theme

local Minimap_ = {}
ns.Minimap = Minimap_

local ICON = "Interface\\AddOns\\GoldForever\\Media\\Icon.tga"

-- Pure: where the button sits and where a drag puts it ---------------------------------------------------

-- The button's offset from the minimap's centre for an angle in degrees (0 is east, 90 north).
function Minimap_.offset(angle, radius)
	local a = math.rad(angle)
	return math.cos(a) * radius, math.sin(a) * radius
end

-- The angle in degrees, 0 to 360, of a point seen from the centre: where a drag leaves the button.
function Minimap_.angle(x, y, centreX, centreY)
	local dx, dy = x - centreX, y - centreY
	local a
	if dx == 0 then
		a = dy >= 0 and 90 or 270
	else
		a = math.deg(math.atan(dy / dx))
		if dx < 0 then
			a = a + 180
		end
	end
	return a % 360
end

-- The settings: the angle on the rim and whether the player hid the button.
local function settings()
	return ns.settings("minimap", { angle = 225, hidden = false })
end

-- What a click does, shared by the button, the compartment and the bindings ---------------------------------

-- The next look round the list (Theme.order): what a right-click or the binding switches to.
local function otherLook()
	return Theme.nextLook(Theme.skin.name)
end

function Minimap_.toggleWindow()
	ns.commands.ui()
end

function Minimap_.switchLook()
	ns.commands.look(otherLook())
end

local function tooltip(owner)
	if not GameTooltip then
		return
	end
	GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
	GameTooltip:AddLine("Gold Forever", Theme.rgb(Theme.color.accent))
	GameTooltip:AddLine("Left-click: open or close the window", 1, 1, 1)
	GameTooltip:AddLine(string.format("Right-click: the %s look", Theme.skins[otherLook()].label), 1, 1, 1)
	GameTooltip:AddLine("Drag: move it around the minimap", Theme.rgb(Theme.color.textFaint))
	GameTooltip:Show()
end

-- The minimap button ------------------------------------------------------------------------------------------

local button

local function place()
	local radius = (Minimap:GetWidth() or 140) / 2 + 10
	local x, y = Minimap_.offset(settings().angle, radius)
	button:ClearAllPoints()
	button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-- The round button the client's own minimap buttons are made of: its background, the tracking border
-- and the zoom buttons' highlight, around our coin.
local function build()
	button = CreateFrame("Button", "GoldForeverMinimapButton", Minimap)
	button:SetSize(31, 31)
	button:SetFrameStrata("MEDIUM")
	button:SetFrameLevel(8)
	button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	button:RegisterForDrag("LeftButton")
	button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	local back = button:CreateTexture(nil, "BACKGROUND")
	back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	back:SetSize(20, 20)
	back:SetPoint("CENTER")
	local icon = button:CreateTexture(nil, "ARTWORK")
	icon:SetTexture(ICON)
	icon:SetSize(18, 18)
	icon:SetPoint("CENTER")
	local border = button:CreateTexture(nil, "OVERLAY")
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetSize(53, 53)
	border:SetPoint("TOPLEFT")

	button:SetScript("OnClick", function(_, mouse)
		if mouse == "RightButton" then
			Minimap_.switchLook()
		else
			Minimap_.toggleWindow()
		end
	end)
	button:SetScript("OnEnter", tooltip)
	button:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
	-- Only while dragging: follow the cursor around the rim, then stop.
	button:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local scale = Minimap:GetEffectiveScale()
			local x, y = GetCursorPosition()
			local cx, cy = Minimap:GetCenter()
			settings().angle = Minimap_.angle(x / scale, y / scale, cx, cy)
			place()
		end)
	end)
	button:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
	end)
	place()
end

local function refresh()
	if not Minimap then
		return
	end
	if settings().hidden then
		if button then
			button:Hide()
		end
		return
	end
	if not button then
		build()
	end
	button:Show()
end

ns.on("PLAYER_LOGIN", "minimap", refresh)

-- "/gf minimap": hide the button or bring it back.
ns.commands.minimap = function()
	local s = settings()
	s.hidden = not s.hidden
	refresh()
	print(string.format("%s minimap button %s. /gf minimap brings it %s.", ns.PREFIX, s.hidden and "hidden" or "shown", s.hidden and "back" or "away"))
end

-- The addon compartment (the TOC names these) and the key bindings (Bindings.xml) -----------------------------

function GoldForever_OnAddonCompartmentClick(_, mouse)
	if mouse == "RightButton" then
		Minimap_.switchLook()
	else
		Minimap_.toggleWindow()
	end
end

function GoldForever_OnAddonCompartmentEnter(_, frame)
	tooltip(frame)
end

function GoldForever_OnAddonCompartmentLeave()
	if GameTooltip then
		GameTooltip:Hide()
	end
end

function GoldForever_ToggleWindow()
	ns.safely("binding", Minimap_.toggleWindow)
end

function GoldForever_SwitchLook()
	ns.safely("binding", Minimap_.switchLook)
end

BINDING_HEADER_GOLDFOREVER = "Gold Forever"
BINDING_NAME_GOLDFOREVER_WINDOW = "Open or close the window"
BINDING_NAME_GOLDFOREVER_LOOK = "Switch the window's look"
