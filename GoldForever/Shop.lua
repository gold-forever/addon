-- Gold Forever: a craft shopping list at the auction house. The recipes the character knows that
-- make a profit at the latest scan, best first, and what to buy for them, where, and at what price.
-- The same rules as the web app's Crafting view ("use what I have"): Crafting.lua.

local _, ns = ...

local SHOWN = 8 -- recipes listed

local frame, body

local function settings()
	local s = ns.db().settings
	s.shop = s.shop or { shown = true }
	return s.shop
end

-- Columns by name from fields.<format>, so a row is read as the file declares it.
local function columns(format)
	local out, i = {}, 0
	for name in string.gmatch(ns.db().fields[format] or "", "[^,]+") do
		i = i + 1
		out[name] = i
	end
	return out
end

local function itemList(text)
	local out = {}
	for key, n in string.gmatch(text or "", "([^+*]+)%*(%d+)") do
		local id = tonumber(string.match(key, "^(%d+)"))
		if id then
			out[id] = (out[id] or 0) + tonumber(n)
		end
	end
	return out
end

-- What the character holds: bags and bank, as last read.
local function stock()
	local me = ns.me()
	local held = itemList(me.bags and me.bags.items)
	for id, n in pairs(itemList(me.bank and me.bank.items)) do
		held[id] = (held[id] or 0) + n
	end
	return held
end

local function recipe(id, cols)
	local row = ns.db().catalogue.recipes[id]
	if not row then
		return nil
	end
	local values = { strsplit(",", row) }
	local output = tonumber(values[cols.output] or "")
	if not output then
		return nil -- enchants on gear make no item
	end
	local min = tonumber(values[cols.min] or "") or 1
	local max = tonumber(values[cols.max] or "") or min
	local reagents = {}
	for rid, n in pairs(itemList(values[cols.reagents])) do
		reagents[#reagents + 1] = { id = rid, count = n }
	end
	return { id = id, output = output, yield = (min + max) / 2, reagents = reagents }
end

-- Every known recipe that makes a profit, best first, each with its quote.
local function profitable()
	local me = ns.me()
	if not me then
		return {}
	end
	local p, cols, held = ns.price, columns("recipe"), stock()
	local have = function(id)
		return held[id] or 0
	end
	local out = {}
	for _, prof in pairs(me.prof or {}) do
		for id in string.gmatch(prof.recipes or "", "%d+") do
			local r = recipe(tonumber(id), cols)
			if r then
				local q = ns.Crafting.quote(r, p, have, p.cut)
				if q.profit and q.profit > 0 then
					q.recipe = r
					local fromStock = math.huge
					for _, x in ipairs(r.reagents) do
						fromStock = math.min(fromStock, math.floor(have(x.id) / x.count))
					end
					q.fromStock = fromStock == math.huge and 0 or fromStock
					out[#out + 1] = q
				end
			end
		end
	end
	table.sort(out, function(a, b)
		return a.profit > b.profit
	end)
	return out
end

local function name(id)
	local _, _, _, _, n = ns.price.itemInfo(id)
	return n or ("item " .. id)
end

local function text()
	local coins = ns.price.coins
	local list = profitable()
	if #list == 0 then
		return "None of your recipes makes a profit at the latest scan."
	end
	local lines = {}
	for i = 1, math.min(SHOWN, #list) do
		local q = list[i]
		local r = q.recipe
		if i > 1 then
			table.insert(lines, " ")
		end
		table.insert(lines, string.format("|cffffffff%s%s|r · |cff56c98f+%s|r a craft", r.yield ~= 1 and (r.yield .. "× ") or "", name(r.output), coins(q.profit)))
		local buys = {}
		for _, l in ipairs(q.lines) do
			if l.toBuy > 0 then
				local where = l.from == "vendor" and "vendor" or "AH"
				buys[#buys + 1] = string.format("%d× %s (%s, %s each)", l.toBuy, name(l.id), where, coins(l.unit))
			end
		end
		if #buys > 0 then
			table.insert(lines, "|cffaaaaaabuy " .. table.concat(buys, ", ") .. "|r")
		end
		if q.fromStock > 0 then
			table.insert(lines, string.format("|cffaaaaaayour stock makes %d now|r", q.fromStock))
		end
	end
	if #list > SHOWN then
		table.insert(lines, " ")
		table.insert(lines, string.format("|cff999999and %d more profitable recipes on the web app's Crafting page|r", #list - SHOWN))
	end
	return table.concat(lines, "\n")
end

local function refresh()
	if frame and frame:IsShown() then
		body:SetText(text())
		frame:SetHeight(body:GetStringHeight() + 40)
	end
end

local function show()
	if not frame then
		frame, body = ns.makeWindow("GoldForeverShop", "Gold Forever · crafts to make", settings(), { "LEFT", 60, -120 }, nil)
		frame:SetWidth(380)
		body:SetWidth(360)
	end
	frame:Show()
	refresh()
end

local function hide()
	if frame then
		frame:Hide()
	end
end

ns.on("AUCTION_HOUSE_SHOW", "shop", function()
	if settings().shown then
		show()
	end
end)
ns.on("AUCTION_HOUSE_CLOSED", "shop", hide)
-- A new scan gives new prices; bought reagents change the stock.
ns.on("REPLICATE_ITEM_LIST_UPDATE", "shop", function()
	ns.after(5, "shop", refresh)
end)
ns.on("BAG_UPDATE_DELAYED", "shop", function()
	ns.after(1, "shop", refresh)
end)

-- /gf shop shows or hides it; hidden at the auction house, it stops opening there.
ns.commands.shop = function()
	if frame and frame:IsShown() then
		hide()
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			settings().shown = false
			print("|cffe0ac45Gold Forever|r: the craft list no longer opens at the auction house; /gf shop there turns it back on.")
		end
	else
		if AuctionHouseFrame and AuctionHouseFrame:IsShown() then
			settings().shown = true
		end
		show()
	end
end
