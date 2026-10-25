-- Gold Forever: the shopping lists and sale profiles in the save (design 009, Shop): the lists the Buy
-- tab and the Shopping lists page show, the craft queue's and the active profile's after the player's
-- own, the deals alert after a full scan, and the lists and profiles the site sends.

local _, ns = ...
local settings = ns.auctionSettings
local heldHere = ns.Holdings.heldHere

local Lists = {}
ns.Lists = Lists

-- An id for a list or profile made here, and its edited time stamped (design 009, decision 11).
function Lists.newId()
	return string.format("g%x%06x", ns.now(), math.random(0, 0xffffff))
end
function Lists.stamp(item)
	item.id = item.id or Lists.newId()
	item.edited = ns.now()
	return item
end

-- The player's lists (saved), and with them, while a sale profile with buy rules is active, the
-- profile's buy list after them (not saved: it is the profile's; "up to" counts what this character holds).
function Lists.lists()
	local s = settings()
	if not s.lists or #s.lists == 0 then
		s.lists = { Lists.stamp({ name = "My list", entries = {} }) }
	end
	local shown = {}
	for i, l in ipairs(s.lists) do
		shown[i] = l
	end
	local p = s.profile and s.profiles and s.profiles[s.profile]
	-- The craft queue's missing reagents, at under market value (Crafting page and strip).
	local needs = ns.queueNeeds and ns.queueNeeds() or {}
	if next(needs) then
		local entries = {}
		-- Its prices are kept by item (it is made anew from the queue): s.queuePrices[id] = { maxUnit | pct }.
		local prices = s.queuePrices or {}
		for id, n in pairs(needs) do
			-- A reagent held already (bags and bank) is not to buy: off the list (manual test run 001).
			local inBags = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or 0
			-- A vendor's reagent is bought at the vendor (CraftQueue.lua), not here.
			if heldHere(id, inBags) < n and not ns.price.vendorBuy(id) then
				local p = prices[id] or {}
				entries[#entries + 1] = { itemId = id, upTo = n, maxUnit = p.maxUnit, pct = p.pct, lowest = p.lowest }
			end
		end
		table.sort(entries, function(a, b)
			return a.itemId < b.itemId
		end)
		if #entries > 0 then
			shown[#shown + 1] = { name = "Craft queue", entries = entries, profile = true, queue = true }
		end
	end
	if p and #p.buy > 0 then
		local entries = {}
		for i, r in ipairs(p.buy) do
			entries[i] = { itemId = r.itemID, maxUnit = r.maxUnit, upTo = r.upTo }
		end
		shown[#shown + 1] = { name = "Profile: " .. p.name, entries = entries, profile = true }
	end
	s.list = math.max(1, math.min(s.list or 1, #shown))
	return s.lists, shown[s.list], shown
end

-- After a full scan: one chat line naming the list items now listed at or under their price.
function ns.announceDeals()
	if settings().dealsAlert == false then
		return
	end
	local _, _, shown = Lists.lists()
	local under = ns.Shopping.underPrice(shown, ns.price.cheapest, function(id)
		return ns.Prices.value(id)
	end)
	if #under == 0 then
		return
	end
	local names = {}
	for i = 1, math.min(3, #under) do
		local _, _, _, _, name = ns.price.itemInfo(under[i])
		names[i] = name or ("item " .. under[i])
	end
	ns.say(string.format("%d %s on your lists %s at or under your price: %s%s. Open the Buy tab.", #under, #under == 1 and "item" or "items",
		#under == 1 and "is" or "are", table.concat(names, ", "), #under > 3 and ", …" or ""))
end

-- Lists and profiles the companion carries from the site (Data.lua's `shared`), merged in at login:
-- by id, the newer edit wins and the other is dropped (Shopping.merge; no copies since 2026-10-24). A file
-- already merged is not merged again.
-- A copy the site kept: marked so by the server, or named so by an earlier merge. In the save, only a list
-- or profile with no id is taken for one by its name: one the player made (stamped with an id) keeps any
-- name. What the site sends is judged by its name too (left out, never deleted).
local function copyMark(x, name)
	if type(x.copyOf) == "string" then
		return x.copyOf
	end
	return not x.id and type(name) == "string" and string.find(name, " %(older copy%)$") and "named" or nil
end

local function mergeShared()
	local shared = type(GoldForever_Prices) == "table" and type(GoldForever_Prices.shared) == "table" and GoldForever_Prices.shared or nil
	local s = settings()
	-- The list and profile in use are kept by index: found again once the drop and the merge are done.
	local before = #(s.lists or {})
	local listWas = s.list and (s.lists or {})[s.list]
	local generated = s.list and s.list > before and s.list - before or nil
	local profileWas = s.profile and (s.profiles or {})[s.profile]
	local function restore()
		if profileWas then
			s.profile = ns.Shopping.refind(s.profiles, profileWas)
		end
		if listWas then
			s.list = ns.Shopping.refind(s.lists, listWas) or 1
		elseif generated then
			s.list = #(s.lists or {}) + generated
		end
	end
	-- The "(older copy)" lists and profiles earlier merges kept (owner, 2026-10-24: they piled up),
	-- marked or only named so.
	for _, items in ipairs({ s.lists or {}, s.profiles or {} }) do
		for _, x in ipairs(items) do
			x.copyOf = x.copyOf or copyMark({ id = x.id }, x.name)
		end
	end
	local n = ns.Shopping.dropCopies(s.lists or {}) + ns.Shopping.dropCopies(s.profiles or {})
	if n > 0 then
		ns.say(string.format("removed %d \"older copy\" %s the site sync had made.", n, n == 1 and "list" or "lists"))
	end
	if not shared or shared.at == s.sharedAt then
		restore()
		return
	end
	local lists, profiles = {}, {}
	for _, x in ipairs(type(shared.lists) == "table" and shared.lists or {}) do
		local got = type(x) == "table" and type(x.string) == "string" and ns.Shopping.decode(x.string)
		if got and got[1] and type(x.id) == "string" then
			got[1].id, got[1].edited = x.id, tonumber(x.edited) or 0
			got[1].copyOf = copyMark({ copyOf = x.copyOf }, got[1].name)
			lists[#lists + 1] = got[1]
		end
	end
	for _, x in ipairs(type(shared.profiles) == "table" and shared.profiles or {}) do
		local p = type(x) == "table" and type(x.string) == "string" and ns.SalePlan.decode(x.string)
		if p and type(x.id) == "string" then
			p.id, p.edited = x.id, tonumber(x.edited) or 0
			p.copyOf = copyMark({ copyOf = x.copyOf }, p.name)
			profiles[#profiles + 1] = p
		end
	end
	local a, b
	s.removedShared = s.removedShared or {}
	s.lists, a = ns.Shopping.merge(s.lists or {}, lists, s.removedShared)
	s.profiles, b = ns.Shopping.merge(s.profiles or {}, profiles, s.removedShared)
	s.sharedAt = shared.at
	restore()
	if a + b > 0 then
		ns.say(string.format("lists and profiles from the site: %d %s.", a + b, a + b == 1 and "change" or "changes"))
	end
end
ns.on("PLAYER_LOGIN", "shared lists", function()
	mergeShared()
end)
ns.mergeShared = mergeShared
