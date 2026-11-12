-- Gold Forever: the price to post at (design 009, Auction house module; gf#368): undercut the cheapest
-- listing by someone else, from a live search; never over a maximum of 3x the market value (5x on a highly
-- volatile item), never under a floor of the market value or of the vendor price after the cut; with
-- nobody to undercut, the higher of the normal price and today's. Pure Lua 5.1 with no game API, so it is
-- tested outside the client.

local _, ns = ...
ns = ns or {}
local L = ns.L

local Post = {}
ns.Post = Post

-- The default rule: 1 silver under the cheapest (the auction house takes whole silver), a floor of 80%
-- of the market value, a normal price of 120% when alone, hold when the cheapest is under the floor, a
-- maximum of 3x the market (5x when highly volatile) against outliers, and a post size of 2 days of supply.
Post.DEFAULT = { undercut = "1s", floor = 80, normal = 120, belowFloor = "hold", maximum = 3, volatileMaximum = 5, supplyDays = 2 }

-- The undercuts a player can pick: an amount in copper, or a share of the cheapest price.
Post.UNDERCUTS = {
	{ value = "1c", label = L["1 copper (where the auction house takes copper)"], copper = 1 },
	{ value = "1s", label = L["1 silver"], copper = 100 },
	{ value = "1%", label = L["1 percent"], pct = 1 },
	{ value = "5%", label = L["5 percent"], pct = 5 },
}

-- Whether this client's auction house takes copper (C_AuctionHouse.SupportsCopperValues, read when it
-- opens); without it prices are whole silver, as Blizzard's own sell window assumes.
Post.copper = false

-- A unit price the auction house takes: whole silver (down to it, at least one), or whole copper (at
-- least one) where the client takes copper.
function Post.silver(copper)
	if Post.copper then
		return math.max(1, math.floor(copper))
	end
	return math.max(100, math.floor(copper / 100) * 100)
end

-- Up to the next price the auction house takes, so a floor rounded to it stays at or over its bound.
local function up(copper)
	if Post.copper then
		return math.max(1, math.ceil(copper))
	end
	return math.max(100, math.ceil(copper / 100) * 100)
end

local function undercutBy(rule, cheapest)
	for _, u in ipairs(Post.UNDERCUTS) do
		if u.value == rule.undercut then
			return u.copper or math.max(1, math.floor(cheapest * u.pct / 100 + 0.5))
		end
	end
	return 100
end

-- The bounds of a post for an item worth `market`: { floor, floorBy ("market" or "vendor"), vendor (the
-- vendor price after the cut, up to the auction house's step; nil without one), maximum, times }. item:
-- { vendor, cut, volatile } (each optional). Sell and the sale plans share them.
function Post.limits(rule, market, item)
	rule, item = rule or Post.DEFAULT, item or {}
	local floor, floorBy = Post.silver(math.ceil(market * (rule.floor or 80) / 100)), "market"
	local vendor = item.vendor and item.vendor > 0 and up(item.vendor / (1 - (item.cut or 0.05))) or nil
	if vendor and vendor > floor then
		floor, floorBy = vendor, "vendor"
	end
	local times = item.volatile and (rule.volatileMaximum or Post.DEFAULT.volatileMaximum) or (rule.maximum or Post.DEFAULT.maximum)
	return { floor = floor, floorBy = floorBy, vendor = vendor, maximum = math.max(floor, Post.silver(market * times)), times = times }
end

-- The price for one unit from the market value and the cheapest buyout by someone else (nil: nobody);
-- item: { vendor, cut, volatile, day (today's price) }. Returns { unit (nil to hold), reason, floor,
-- floorBy, normal (the price alone), maximum, times, day (alone at today's price) }; reason is "undercut",
-- "alone" (nobody else), "maximum" (everyone over the maximum), "floor" (posted at the floor) or "hold".
function Post.suggest(rule, market, cheapest, item)
	rule = rule or Post.DEFAULT
	local b = Post.limits(rule, market, item)
	local floor = b.floor
	local function out(unit, reason, day)
		return { unit = unit, reason = reason, floor = floor, floorBy = b.floorBy, normal = b.normal, maximum = b.maximum, times = b.times, day = day or false }
	end
	-- To the nearest silver where the auction house takes silver; where it takes copper, to the copper.
	local normal = Post.silver(market * (rule.normal or 120) / 100 + (Post.copper and 0 or 50))
	local day = item and item.day and Post.silver(item.day)
	local atDay = day and day > normal
	b.normal = math.max(floor, math.min(b.maximum, atDay and day or normal))
	if not cheapest then
		return out(b.normal, "alone", atDay)
	end
	local under = cheapest - undercutBy(rule, cheapest)
	if under > b.maximum then
		return out(b.maximum, "maximum")
	end
	if under >= floor then
		-- What the auction house takes (whole silver, or copper), and still under the cheapest one.
		local unit = Post.copper and math.floor(under) or math.floor(under / 100) * 100
		if unit >= floor then
			return out(unit, "undercut")
		end
	end
	if rule.belowFloor == "floor" then
		return out(floor, "floor")
	end
	return out(nil, "hold")
end

-- What Sell suggests from a rule, the market value and the cheapest other listing (nil: nobody): the
-- suggestion, nil with neither price (with no market value the cheapest stands in for it); and for one
-- held under the floor, what undercutting would ask anyway (Post anyway, owner's answer, 2026-10-24).
function Post.advise(rule, market, cheapest, item)
	if not market then
		return cheapest and Post.suggest(rule, cheapest, cheapest, item) or nil, nil
	end
	local s = Post.suggest(rule, market, cheapest, item)
	if s.reason ~= "hold" or not cheapest then
		return s, nil
	end
	local loose = {}
	for k, x in pairs(rule or Post.DEFAULT) do
		loose[k] = x
	end
	loose.floor = 1
	return s, Post.suggest(loose, market, cheapest, item and { volatile = item.volatile, day = item.day }).unit
end

-- The undercut a rule names, as Sell says it: an amount (money(copper)), or a share.
local function undercutText(rule, money)
	for _, u in ipairs(Post.UNDERCUTS) do
		if u.value == (rule or Post.DEFAULT).undercut then
			return u.copper and money(u.copper) or (u.pct .. "%")
		end
	end
	return money(100)
end

-- Why Sell suggests what it does, in a few words (gf#368): "Undercut 1s (live)", "At the maximum, 3x
-- market", "Held: under the vendor price", "Alone: today's price". `live`: the cheapest is from a live
-- search, not the last scan. Nil without a suggestion.
function Post.label(s, rule, money, live)
	if not s then
		return nil
	end
	if s.reason == "undercut" then
		return string.format(live and L["Undercut %s (live)"] or L["Undercut %s (last scan)"], undercutText(rule, money))
	elseif s.reason == "maximum" then
		return string.format(L["At the maximum, %sx market"], tostring(s.times))
	elseif s.reason == "hold" then
		return s.floorBy == "vendor" and L["Held: under the vendor price"] or L["Held: under your floor"]
	elseif s.reason == "alone" then
		return s.day and L["Alone: today's price"] or string.format(L["Alone: %s%% of market"], tostring((rule or Post.DEFAULT).normal or 120))
	end
	return Post.REASONS[s.reason]
end

-- The post size's reason: "2 days of supply".
function Post.supplyReason(days)
	return ns.plural(days, L["%d day of supply"], L["%d days of supply"])
end

-- Cancel undercut: the auctions { unit, cheapest } undercut by more than `tolerance` percent, most
-- undercut first; each auction's `under` is set on the way.
function Post.undercutList(auctions, tolerance)
	local out = {}
	for _, a in ipairs(auctions) do
		a.under = Post.undercutPct(a.unit, a.cheapest)
		if a.under > tolerance then
			out[#out + 1] = a
		end
	end
	table.sort(out, function(x, y)
		return x.under > y.under
	end)
	return out
end

-- How many of other players' units a book's levels { unitPrice, quantity, own } list under `unit`.
function Post.ahead(unit, levels)
	local n = 0
	for _, l in ipairs(levels or {}) do
		if l.unitPrice < unit then
			n = n + math.max(0, (l.quantity or 0) - (l.own or 0))
		end
	end
	return n
end

-- The account's characters as an item search result's `owners` name them (gf#375): bare on the
-- player's realm, "Name-Realm" (the realm without spaces or hyphens) on any realm of the region.
function Post.ownerNames(characters, realm, region)
	local names = {}
	for _, c in pairs(characters or {}) do
		if c.name and c.realm and (not region or not c.region or c.region == region) then
			names[c.name .. "-" .. c.realm:gsub("[%s%-]", "")] = true
			if c.realm == realm then
				names[c.name] = true
			end
		end
	end
	return names
end

-- The names of the account's characters, as the auction house's owners list them, for the one playing.
function Post.accountNames()
	local me = ns.me() or {}
	return Post.ownerNames(ns.db().characters, me.realm, me.region)
end

-- A gear book's levels with the account's other characters' auctions counted as own (gf#375): those
-- whose `owners[auctionID]` are all in `names`. Commodity results name no owners, so this is for gear
-- only. Returns the levels (a copy when any changed; the same table when none did) and the alts'
-- auction ids as a set.
function Post.withAlts(levels, owners, names)
	if not levels then
		return nil, {}
	end
	local out, alts = levels, {}
	for i, l in ipairs(levels) do
		local who = l.auctionID and owners[l.auctionID]
		local all = who and #who > 0 and (l.own or 0) == 0
		for _, name in ipairs(all and who or {}) do
			all = all and names[name] == true
		end
		if all then
			if out == levels then
				out = {}
				for j, x in ipairs(levels) do
					out[j] = x
				end
			end
			local copy = {}
			for k, v in pairs(l) do
				copy[k] = v
			end
			copy.own = l.quantity or 0
			out[i], alts[l.auctionID] = copy, true
		end
	end
	return out, alts
end

-- The Sell tab's Cancel view (gf#369), from owned auctions { unit, levels (their item's live book; nil
-- before it is searched), repost (what the rule would post at now, nil to hold) }: `undercut`, more than
-- `ahead` units listed under them, most ahead first; `higher`, the rule's price now more than
-- `tolerance` percent over theirs (the cheaper listings sold), most gained first. Sets `ahead` and `up`.
function Post.cancelReview(auctions, ahead, tolerance)
	local undercut, higher = {}, {}
	for _, a in ipairs(auctions) do
		a.ahead, a.up = nil, nil
		if a.levels then
			a.ahead = Post.ahead(a.unit, a.levels)
			if a.ahead > ahead then
				undercut[#undercut + 1] = a
			elseif a.repost and a.repost > a.unit then
				a.up = math.floor((a.repost - a.unit) / a.unit * 1000 + 0.5) / 10
				if a.up > tolerance then
					higher[#higher + 1] = a
				end
			end
		end
	end
	table.sort(undercut, function(x, y)
		return x.ahead > y.ahead
	end)
	table.sort(higher, function(x, y)
		return x.up > y.up
	end)
	return { undercut = undercut, higher = higher }
end

-- The player's own auctions, from the client's list of them: `info(i)` for i up to `n` (as
-- C_AuctionHouse.GetOwnedAuctionInfo), `keyInfo(itemKey)` (GetItemKeyInfo, may be nil) and `itemInfo(id)`
-- (quality, _, _, _, name). Active ones with a buyout only (status 0); sold ones wait in the list for their
-- mail. Returns { auctionID, itemID, itemKey, quantity, unit, commodity, name, quality }.
function Post.readOwned(n, info, keyInfo, itemInfo)
	local owned = {}
	for i = 1, n do
		local a = info(i)
		if a and a.itemKey and (a.status or 0) == 0 and a.buyoutAmount and a.buyoutAmount > 0 then
			local key = keyInfo and keyInfo(a.itemKey)
			local commodity = key and key.isCommodity or false
			local qty = a.quantity or 1
			-- ASSUMED: a commodity's buyoutAmount is its unit price, an item's the whole auction's.
			local unit = commodity and a.buyoutAmount or math.floor(a.buyoutAmount / math.max(1, qty) + 0.5)
			local quality, _, _, _, name = itemInfo(a.itemKey.itemID)
			owned[#owned + 1] = { auctionID = a.auctionID, itemID = a.itemKey.itemID, itemKey = a.itemKey, quantity = qty,
				unit = unit, commodity = commodity, name = (key and key.itemName) or name or string.format(L["item %d"], a.itemKey.itemID), quality = quality or 1 }
		end
	end
	return owned
end

-- What a rule does, as four sentences for an item worth `market` (10g unless given): someone a little
-- under the market, no one else, someone far under (past the floor), someone far over. money(copper)
-- formats an amount.
function Post.examples(rule, money, market)
	market = market or 100000
	local out = {}
	local function say(situation, cheapest)
		local s = Post.suggest(rule, market, cheapest)
		out[#out + 1] = s.unit and string.format(L["%s: you post at %s (%s)"], situation, money(s.unit), string.lower(Post.REASONS[s.reason]))
			or string.format(L["%s: you hold it, as it is under your floor"], situation)
	end
	local near, low, high = math.floor(market * 0.95), math.floor(market / 2), market * 4
	say(string.format(L["Someone lists it at %s"], money(near)), near)
	say(L["No one else lists it"], nil)
	say(string.format(L["The cheapest is %s"], money(low)), low)
	say(string.format(L["The cheapest is %s"], money(high)), high)
	return out
end

-- Advice from the market's trend against its 7-day average (owner's answer, 2026-10-24), in percent:
-- 10% or more above it, "rising: maybe wait"; 10% or more under, "falling"; else nil. Advice only.
Post.TREND_HINT = 10
function Post.trendHint(pct)
	if not pct then
		return nil
	end
	if pct >= Post.TREND_HINT then
		return L["rising: maybe wait"]
	elseif pct <= -Post.TREND_HINT then
		return L["falling"]
	end
	return nil
end

-- What each reason says in the panel.
Post.REASONS = {
	undercut = L["Undercut"],
	alone = L["No one else"],
	maximum = L["At the maximum"],
	floor = L["At floor"],
	hold = L["Under your floor"], -- not "Hold", read as "keep this many" (manual test run 001)
	plan = L["Plan"], -- a sale plan's step; the panel shows the step's own label
}

-- A second press is asked for when a post looks like a mistake: under what a vendor pays after the
-- auction house's cut, or more than half under the market value. Returns the warning, or nil.
function Post.check(unit, market, vendor, cut)
	if vendor and vendor > 0 and math.floor(unit * (1 - (cut or 0.05))) < vendor then
		return L["under what a vendor pays"]
	end
	if market and market > 0 and unit < market * 0.5 then
		return L["more than half under the market value"]
	end
end

-- How far under the player's unit price the cheapest other listing sits, in percent to one decimal; 0
-- when nobody is cheaper (the playground's undercutPct). Cancel undercut acts past a tolerance only.
function Post.undercutPct(mine, other)
	if not other or other >= mine then
		return 0
	end
	return math.floor((mine - other) / mine * 1000 + 0.5) / 10
end

-- The cheapest other listing worth reacting to, from levels { unitPrice, quantity, own }: the sale
-- plans' sneaky-price guard (SalePlan.clean, design 009 decision 13), so Sell, Cancel and a sale plan
-- undercut the same price. `market` judges a book of a few units only. Returns the unit price, or nil.
function Post.honestCheapest(levels, market)
	local kept = ns.SalePlan.clean(levels, nil, market)
	return kept[1] and kept[1].unitPrice or nil
end

-- The rule an item posts by (design 009: one default, overridable per item category and per item): the
-- default with an item's override over it, else its category's; each override holds only what it
-- changes. Returns the rule and where it came from: "item", "category" or "default".
function Post.resolve(base, overrides, itemID, classID)
	overrides = overrides or {}
	local over, from = overrides.items and overrides.items[itemID], "item"
	if not over then
		over, from = classID and overrides.classes and overrides.classes[classID], "category"
	end
	if not over then
		return base, "default"
	end
	local rule = {}
	for k, v in pairs(base) do
		rule[k] = v
	end
	for k, v in pairs(over) do
		rule[k] = v
	end
	return rule, from
end
