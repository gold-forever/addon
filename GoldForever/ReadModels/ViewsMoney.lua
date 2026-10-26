-- Gold Forever: where money came from and went, from the saved money, flight and sale rows (ns.Views);
-- the same rules as the web app's Ledger.kt. Pure Lua 5.1, as Views.lua.

local _, ns = ...
local Views = ns.Views

-- Where a change in money came from, by the windows open at the time; a flight is matched by time.
local CATEGORIES = {
	{ "loot", { loot = true } },
	{ "quest", { quest = true } },
	{ "training", { trainer = true } },
	{ "travel", { taxinode = true, taxi = true } },
	{ "auction", { auctioneer = true, auction = true } },
	{ "vendor", { merchant = true } },
	{ "mail", { mailinfo = true, mail = true } },
	{ "trade", { trade = true } },
}

Views.CATEGORY_LABELS = {
	loot = "Loot", quest = "Quests", training = "Training", travel = "Flights", auction = "Auction house",
	vendor = "Vendors", mail = "Mail", trade = "Trade", other = "Other",
}

function Views.category(ctx, isFlight)
	if isFlight then
		return "travel"
	end
	local windows = {}
	for name in string.gmatch(ctx or "", "[^+]+") do
		windows[name] = true
	end
	for _, c in ipairs(CATEGORIES) do
		for name in pairs(c[2]) do
			if windows[name] then
				return c[1]
			end
		end
	end
	return "other"
end

-- Money in and out by where it came from, for one character's ref (nil for all) since `from`:
-- { categories = { { key, label, n, gained, spent, net } }, gained, spent, days = { [day] = net } }.
-- `flights` are the flight rows: a payment of a flight's cost within a few seconds of it is that flight.
Views.FLIGHT_SECONDS = 3

local function isFlight(flights, r, delta)
	for _, f in ipairs(flights or {}) do
		if f.char == r.char and math.abs(f.t - r.t) <= Views.FLIGHT_SECONDS and tonumber(f.cost) == -delta then
			return true
		end
	end
	return false
end

function Views.ledger(money, flights, ref, from, dayOf)
	local by, out = {}, { categories = {}, gained = 0, spent = 0, days = {} }
	for _, r in ipairs(money or {}) do
		local delta = tonumber(r.delta)
		if delta and (ref == nil or r.char == ref) and r.t >= (from or 0) then
			local key = Views.category(r.ctx, delta < 0 and isFlight(flights, r, delta))
			local c = by[key]
			if not c then
				c = { key = key, label = Views.CATEGORY_LABELS[key], n = 0, gained = 0, spent = 0, net = 0 }
				by[key] = c
				out.categories[#out.categories + 1] = c
			end
			c.n = c.n + 1
			c.net = c.net + delta
			if delta > 0 then
				c.gained, out.gained = c.gained + delta, out.gained + delta
			else
				c.spent, out.spent = c.spent - delta, out.spent - delta
			end
			if dayOf then
				local day = dayOf(r.t)
				out.days[day] = (out.days[day] or 0) + delta
			end
		end
	end
	out.net = out.gained - out.spent
	return out
end

-- Auction house sales from the sale stream ({ t, char, item, qty, price, deposit, cut }, the "sold" mail):
-- for one character (ref) or all (nil), from `from` on, newest first, each with what it brought after
-- the cut; and the totals. The deposit comes back with the sale and is not counted as earned.
function Views.sales(rows, ref, from)
	local out = { list = {}, count = 0, gross = 0, cut = 0, net = 0 }
	for _, r in ipairs(rows or {}) do
		local price = tonumber(r.price)
		if price and (ref == nil or r.char == ref) and r.t >= (from or 0) then
			local cut = tonumber(r.cut) or 0
			local sale = { t = r.t, char = r.char, item = r.item or "?", qty = tonumber(r.qty) or 1, price = price, cut = cut, net = price - cut }
			out.list[#out.list + 1] = sale
			out.count = out.count + 1
			out.gross = out.gross + price
			out.cut = out.cut + cut
			out.net = out.net + sale.net
		end
	end
	table.sort(out.list, function(a, b)
		return a.t > b.t
	end)
	return out
end
