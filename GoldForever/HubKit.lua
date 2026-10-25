-- Gold Forever: what the hub's pages share: the window's settings, a section heading, a table's saved
-- order, names from the catalogue, an item's tooltip on hover, a scrolling body. Each page file adds its
-- builder to ns.hubPages, which Hub.lua puts in the window.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI

local Kit = {}
ns.HubKit = Kit

-- The page builders by key: ns.hubPages.home = function(page) ... end.
ns.hubPages = {}

function Kit.settings()
	return ns.settings("window", {})
end

-- A page's table order, saved with the window: the column and direction last picked, at first the given
-- column, highest first.
function Kit.sortOf(page, column)
	local s = Kit.settings()
	s.sort = s.sort or {}
	s.sort[page] = s.sort[page] or { column = column, descending = true }
	return s.sort[page]
end

-- A section heading with a line under it; returns where the next thing goes.
function Kit.heading(page, text, y)
	local h = UI.Text(page, text, { size = "lg" })
	h:SetPoint("TOPLEFT", 0, y)
	local rule = UI.solid(page, "BORDER", Theme.color.border)
	rule:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -4)
	rule:SetPoint("RIGHT", page, "RIGHT")
	rule:SetHeight(UI.pixel())
	return y - 30
end

-- Where a page's own content starts: the window's header shows its title and the line under it
-- (PAGES), so this is an empty strip along the page's top edge to place what follows.
function Kit.header(page)
	local top = CreateFrame("Frame", nil, page)
	top:SetPoint("TOPLEFT")
	top:SetPoint("TOPRIGHT")
	top:SetHeight(1)
	return top
end

-- A page's width before the window has laid it out.
Kit.PAGE_WIDTH = 708

function Kit.pageWidth(page)
	return (page:GetWidth() and page:GetWidth() > 0) and page:GetWidth() or Kit.PAGE_WIDTH
end

function Kit.classColor(class)
	return Theme.class[class or ""] or Theme.color.text
end

Kit.isRetail = ns.Realms and ns.Realms.isRetail and ns.Realms.isRetail(select(4, GetBuildInfo()))

function Kit.itemName(id)
	local row = ns.db().catalogue.items[id]
	return (row and string.match(row, "^([^,]+)")) or ("Item " .. id)
end

function Kit.itemQuality(id)
	local row = ns.db().catalogue.items[id]
	return tonumber(row and select(2, strsplit(",", row))) or 1
end

function Kit.npcName(id)
	local row = ns.db().catalogue.npcs[id]
	return (row and string.match(row, "^([^,]+)")) or ("NPC " .. id)
end

-- The item's own tooltip while the pointer is over the frame: the item is frame.itemId, set as it changes.
function Kit.itemTooltip(frame)
	frame:SetScript("OnEnter", function(self)
		if self.itemId and GameTooltip then
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			if GameTooltip.SetItemByID then
				GameTooltip:SetItemByID(self.itemId)
			else
				GameTooltip:SetHyperlink("item:" .. self.itemId)
			end
			GameTooltip:Show()
		end
	end)
	frame:SetScript("OnLeave", function()
		if GameTooltip then
			GameTooltip:Hide()
		end
	end)
end

-- A body that scrolls with the wheel inside the page, as wide as the page; the caller sets its height to
-- what it holds.
function Kit.scrollBody(page, width, height)
	local scroll = CreateFrame("ScrollFrame", nil, page)
	scroll:SetAllPoints()
	local body = CreateFrame("Frame", nil, scroll)
	body:SetSize(width, height)
	scroll:SetScrollChild(body)
	scroll:EnableMouseWheel(true)
	scroll:SetScript("OnMouseWheel", function(self, delta)
		local max = math.max(0, body:GetHeight() - self:GetHeight())
		self:SetVerticalScroll(math.min(max, math.max(0, self:GetVerticalScroll() - delta * 48)))
	end)
	page:SetScript("OnSizeChanged", function(_, w)
		body:SetWidth(w)
	end)
	return body
end
