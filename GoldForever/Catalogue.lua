-- Gold Forever: the item catalogue (design 002, State: catalogue). Every collector that records an
-- item key calls ns.catalogueItem, which writes the item's info once it has loaded.
--
-- From 0.4.0 each item also keeps its tooltip text: Forever-only items exist nowhere else once
-- the game is gone. Items catalogued before that are filled in by a slow pass after login.

local _, ns = ...
local Encode = ns.Encode

-- minLevel and equipLoc are appended to design 002's columns.
ns.FIELDS.item = "name,quality,ilvl,class,subclass,stack,sell,bind,icon,minLevel,equipLoc"

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local pending = {} -- item IDs waiting for their info to load

-- Tooltip lines joined with "\n", right-hand text after a tab.
local function tooltip(id)
	if not (C_TooltipInfo and C_TooltipInfo.GetItemByID) then
		return nil
	end
	local data = C_TooltipInfo.GetItemByID(id)
	if not data or not data.lines then
		return nil
	end
	local lines = {}
	for _, line in ipairs(data.lines) do
		local text = line.leftText or ""
		if line.rightText and line.rightText ~= "" then
			text = text .. "\t" .. line.rightText
		end
		lines[#lines + 1] = text
	end
	return table.concat(lines, "\n")
end

local function write(id)
	local name, _, quality, ilvl, minLevel, _, _, stack, equipLoc, icon, sell, class, subclass, bind = GetItemInfo(id)
	if not name then
		return false
	end
	local catalogue = ns.db().catalogue
	catalogue.items[id] = Encode.row(Encode.name(name), quality, ilvl, class, subclass, stack, sell, bind, icon,
		minLevel, equipLoc ~= "" and equipLoc or nil)
	catalogue.tooltips[id] = tooltip(id) or catalogue.tooltips[id]
	return true
end

local function load(id)
	if write(id) then
		return
	end
	pending[id] = true
	if Item and Item.CreateFromItemID then
		Item:CreateFromItemID(id):ContinueOnItemLoad(function()
			pending[id] = nil
			ns.safely("catalogue", write, id)
		end)
	end
end

-- Records the catalogue entry for an item key ("14047", "10221:612" or a number), once.
function ns.catalogueItem(key)
	local id = tonumber(string.match(tostring(key), "^(%d+)"))
	local catalogue = ns.db().catalogue
	if not id or (catalogue.items[id] and catalogue.tooltips[id]) or pending[id] then
		return
	end
	load(id)
end

-- Fills in tooltips (and the new columns) for items catalogued before 0.4.0, a few at a time so
-- the server is not asked for thousands of items at once.
ns.on("PLAYER_ENTERING_WORLD", "catalogue", function()
	local todo = {}
	local catalogue = ns.db().catalogue
	for id in pairs(catalogue.items) do
		if not catalogue.tooltips[id] then
			todo[#todo + 1] = id
		end
	end
	local i = 0
	local function batch()
		for _ = 1, 20 do
			i = i + 1
			if not todo[i] then
				return
			end
			if not pending[todo[i]] then
				load(todo[i])
			end
		end
		ns.after(0.2, "catalogue", batch)
	end
	ns.after(5, "catalogue", batch)
end)
