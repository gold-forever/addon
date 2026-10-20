-- Gold Forever: the item catalogue (design 002, State: catalogue). Every collector that records an
-- item key calls ns.catalogueItem, which writes the item's info once it has loaded.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.item = "name,quality,ilvl,class,subclass,stack,sell,bind,icon"

local GetItemInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
local pending = {} -- item IDs waiting for their info to load

local function write(id)
	local name, _, quality, ilvl, _, _, _, stack, _, icon, sell, class, subclass, bind = GetItemInfo(id)
	if not name then
		return false
	end
	ns.db().catalogue.items[id] = Encode.row(Encode.name(name), quality, ilvl, class, subclass, stack, sell, bind, icon)
	return true
end

-- Records the catalogue entry for an item key ("14047", "10221:612" or a number), once.
function ns.catalogueItem(key)
	local id = tonumber(string.match(tostring(key), "^(%d+)"))
	if not id or ns.db().catalogue.items[id] or pending[id] then
		return
	end
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
