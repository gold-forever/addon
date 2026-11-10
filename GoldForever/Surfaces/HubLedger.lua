-- Gold Forever: the hub's Ledger tabs: money in and out, the characters, everything they hold, and
-- the auction sales.

local _, ns = ...
local L = ns.L
local Theme, UI, Encode, Views = ns.Theme, ns.UI, ns.Encode, ns.Views
local Kit = ns.HubKit
local settings, sortOf, header, classColor, itemName, itemQuality = Kit.settings, Kit.sortOf, Kit.header, Kit.classColor, Kit.itemName, Kit.itemQuality

local LedgerView = ns.LedgerView
local LEDGER_DAYS = LedgerView.DAYS

-- Ledger ----------------------------------------------------------------------------------------------------

local function buildLedger(page)
	local tabs = UI.TabBar(page, { { key = "me", label = L["This character"] }, { key = "all", label = L["All characters"] } }, function(key)
		settings().ledger = key
		page:Refresh()
	end)
	tabs:SetPoint("TOPLEFT")
	local lede = tabs
	local gained = UI.StatCard(page, L["Money in"], "", "")
	gained:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	gained:SetWidth(150)
	local spent = UI.StatCard(page, L["Money out"], "", "")
	spent:SetPoint("LEFT", gained, "RIGHT", 12, 0)
	spent:SetWidth(150)
	local net = UI.StatCard(page, L["Net"], "", "")
	net:SetPoint("LEFT", spent, "RIGHT", 12, 0)
	net:SetWidth(150)
	local trend = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	trend:SetPoint("TOPLEFT", net, "TOPRIGHT", 12, 0)
	trend:SetPoint("RIGHT", page, "RIGHT")
	trend:SetHeight(72)
	local trendLabel = UI.Text(trend, L["NET A DAY"], { size = "xs", tone = "muted" })
	trendLabel:SetPoint("TOPLEFT", 12, -10)
	local spark = UI.Sparkline(trend, {}, Theme.color.accent)
	spark:SetPoint("TOPLEFT", trendLabel, "BOTTOMLEFT", 0, -8)
	spark:SetPoint("BOTTOMRIGHT", -12, 10)
	local tbl = UI.Table(page, {
		{ key = "label", title = L["Source"], flex = 2 },
		{ key = "n", title = L["Times"], width = 60, align = "RIGHT" },
		{ key = "gained", title = L["In"], width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.gained) end },
		{ key = "spent", title = L["Out"], width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.spent) end },
		{ key = "net", title = L["Net"], width = 110, align = "RIGHT", text = function(r) return UI.layout.amount(r.net) end },
	}, { pageSize = 8, empty = L["No money has moved yet."], sort = sortOf("ledger", "net") })
	tbl:SetPoint("TOPLEFT", gained, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		-- Shared with Auction sales: whichever tab chose last.
		local whose = settings().ledger or "me"
		tabs:Select(whose)
		local now = ns.now()
		local ledger = LedgerView.money(whose, now)
		gained:Set(UI.layout.money(ledger.gained, "gold"), string.format(L["last %d days"], LEDGER_DAYS))
		spent:Set(UI.layout.money(ledger.spent, "gold"), string.format(L["last %d days"], LEDGER_DAYS))
		net:Set(UI.layout.money(ledger.net, "gold"), ledger.net >= 0 and L["ahead"] or L["behind"])
		local days = {}
		for i = LEDGER_DAYS - 1, 0, -1 do
			days[#days + 1] = ledger.days[Encode.day(now - i * 86400)] or 0
		end
		spark:Set(days)
		tbl:SetRows(ledger.categories)
	end
end

-- Characters ----------------------------------------------------------------------------------------------

local function buildCharacters(page)
	local lede = header(page)
	local gold = UI.StatCard(page, L["Gold, all characters"], "", "")
	gold:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	gold:SetWidth(200)
	local nextUp = UI.StatCard(page, L["Play next"], "", "")
	nextUp:SetPoint("LEFT", gold, "RIGHT", 12, 0)
	nextUp:SetWidth(220)
	local capped = UI.StatCard(page, L["Characters"], "", "")
	capped:SetPoint("LEFT", nextUp, "RIGHT", 12, 0)
	capped:SetWidth(200)
	local tbl = UI.Table(page, {
		{ key = "name", title = L["Character"], flex = 2, text = function(r) return r.online and (r.display .. "  " .. Theme.escape(Theme.color.success) .. L["online"] .. "|r") or r.display end,
			color = function(r) return classColor(r.class) end },
		{ key = "level", title = L["Level"], width = 56, align = "RIGHT" },
		{ key = "progress", title = L["Into level"], width = 80, align = "RIGHT", text = function(r) return r.progress and string.format("%d%%", math.floor(r.progress * 100)) or "-" end,
			sort = function(r) return r.level + (r.progress or 0) end },
		{ key = "restedLevels", title = L["Rested"], width = 90, align = "RIGHT",
			text = function(r) return r.restedLevels and (r.restedLevels >= Views.RESTED_CAP_LEVELS - 0.005 and L["full"] or string.format(L["%.2f levels"], r.restedLevels)) or "-" end,
			color = function(r) return r.restedLevels and r.restedLevels >= 0.005 and Theme.color.rested or Theme.color.textFaint end },
		{ key = "money", title = L["Gold"], width = 110, align = "RIGHT", text = function(r) return UI.layout.amount(r.money, "gold") end },
		{ key = "seen", title = L["Seen"], width = 80, align = "RIGHT", text = function(r) return r.online and L["now"] or Views.ago(r.seen, ns.now()) end,
			color = function() return Theme.color.textMuted end },
	}, { pageSize = 10, empty = L["No characters yet."], sort = sortOf("characters", "restedLevels") })
	tbl:SetPoint("TOPLEFT", gold, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local rows, best = LedgerView.characters(ns.now(), UnitGUID and UnitGUID("player"))
		local money = 0
		for _, r in ipairs(rows) do
			money = money + r.money
		end
		local top = Views.capped(rows, GetMaxPlayerLevel and GetMaxPlayerLevel() or 60)
		gold:Set(UI.layout.money(money, "gold"), ns.plural(#rows, L["%d character"], L["%d characters"]))
		if best then
			nextUp:Set(Theme.escape(classColor(best.class)) .. best.display .. "|r", string.format(L["%.2f levels of rested XP waiting"], best.restedLevels))
		else
			nextUp:Set("-", L["no one else with rested XP"])
		end
		capped:Set(tostring(#rows), top > 0 and string.format(L["%d at the level cap"], top) or L["none at the level cap yet"])
		tbl:SetRows(rows)
	end
end

-- Inventory ---------------------------------------------------------------------------------------------

local function buildInventory(page)
	-- Filters: whose, where, how good, and a search; the totals follow them (Views.inventory).
	local filter = { query = "" }
	local QUALITY = { { value = 0, label = L["Any quality"] }, { value = 1, label = L["White and better"] }, { value = 2, label = L["Green and better"] }, { value = 3, label = L["Blue and better"] } }
	local PLACE = { { value = "all", label = L["Bags, bank, mail"] }, { value = "bags", label = L["Bags"] }, { value = "bank", label = L["Bank"] }, { value = "mail", label = L["Mail"] },
		{ value = "gear", label = L["Equipped"] } }
	local function chars()
		local out = { { value = "all", label = L["All characters"] } }
		for _, c in ipairs(LedgerView.characterNames()) do
			out[#out + 1] = { value = c.guid, label = c.name }
		end
		return out
	end
	local refresh = function()
		if page.Refresh then
			page:Refresh()
		end
	end
	local who = UI.Dropdown(page, chars(), "all", function(v)
		filter.char = v ~= "all" and v or nil
		refresh()
	end)
	who:SetPoint("TOPLEFT")
	who:SetWidth(150)
	local where = UI.Dropdown(page, PLACE, "all", function(v)
		filter.place = v ~= "all" and v or nil
		refresh()
	end)
	where:SetPoint("LEFT", who, "RIGHT", 8, 0)
	where:SetWidth(140)
	local quality = UI.Dropdown(page, QUALITY, 0, function(v)
		filter.quality = v > 0 and v or nil
		refresh()
	end)
	quality:SetPoint("LEFT", where, "RIGHT", 8, 0)
	quality:SetWidth(150)
	-- Typing gathers its keys into a refresh at most every 0.3 seconds: each one reads every bag.
	local searched = ns.throttle("ui inventory search", 0.3, refresh)
	local search = UI.SearchBox(page, L["Search items..."], function(text)
		filter.query = string.lower(text)
		searched()
	end)
	search:SetPoint("TOPRIGHT")
	search:SetPoint("LEFT", quality, "RIGHT", 8, 0)
	-- Four cards across the page; the fourth holds the soulbound switch (manual test run 001: the switch
	-- beside the cards looked out of place).
	local W = Kit.pageWidth(page)
	local cardW = math.floor((W - 36) / 4)
	local cards = {}
	for i, label in ipairs({ L["Worth"], L["Items"], L["Units"], L["Soulbound"] }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(cardW)
		if i == 1 then
			c:SetPoint("TOPLEFT", who, "BOTTOMLEFT", 0, -12)
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	-- Leave out: soulbound units hidden (they count at a vendor's price otherwise).
	local tradeable = UI.Switch(cards[4], false, function(on)
		filter.tradeable = on or nil
		refresh()
	end)
	tradeable:SetPoint("TOPLEFT", cards[4].label, "BOTTOMLEFT", 0, -10)
	local tradeableLabel = UI.Text(cards[4], L["Leave out"], { size = "sm", tone = "muted" })
	tradeableLabel:SetPoint("LEFT", tradeable, "RIGHT", 8, 0)
	local tbl = UI.Table(page, {
		{ key = "name", title = L["Item"], flex = 2, color = function(r) return Theme.quality[r.quality] or Theme.color.text end,
			text = function(r)
				return r.name .. (r.bound > 0 and (Theme.escape(Theme.color.textFaint) .. "  " .. (r.bound == r.held and L["bound"] or string.format(L["%d bound"], r.bound)) .. "|r") or "")
			end },
		{ key = "held", title = L["Held"], width = 60, align = "RIGHT" },
		{ key = "where", title = L["Where"], flex = 2, color = function() return Theme.color.textMuted end, tooltip = function(r) return r.holders end },
		{ key = "value", title = L["Worth"], width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.value, "silver") end, sort = function(r) return r.value end },
	}, {
		pageSize = 9,
		empty = L["Nothing matches."],
		sort = sortOf("inventory", 4),
		itemId = function(r) return r.id end,
		-- At the auction house, a click chooses the item in Post.
		onRowClick = function(r)
			ns.emit("itemChosen", r.id)
		end,
	})
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local rows, totals = LedgerView.inventory(function(id)
			return ns.price.worth(id)
		end, itemQuality, itemName, filter, function(id)
			return ns.price.vendor(id)
		end)
		cards[1]:Set(UI.layout.money(totals.worth, "gold"), filter.place == "gear" and L["equipped: not counted"] or L["bound at vendor price"])
		cards[4]:Set("", "") -- the switch stands where a value would
		cards[2]:Set(tostring(totals.items), L["different items"])
		cards[3]:Set(tostring(totals.units), L["in all"])
		tbl:SetRows(rows)
	end
end

-- Auction sales ----------------------------------------------------------------------------------------------

-- What sold on the auction house, from the "sold" mail the addon reads: for this character or all,
-- with the cut and what it brought, over the two weeks the save keeps.
local function buildSales(page)
	local tabs = UI.TabBar(page, { { key = "me", label = L["This character"] }, { key = "all", label = L["All characters"] } }, function(key)
		settings().ledger = key
		page:Refresh()
	end)
	tabs:SetPoint("TOPLEFT")
	local cards = {}
	for i, label in ipairs({ L["Sold"], L["Sold for"], L["After the cut"] }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(200)
		if i == 1 then
			c:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, -12)
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	local names = {}
	local tbl = UI.Table(page, {
		{ key = "item", title = L["Item"], flex = 3, text = function(r) return r.qty > 1 and (r.item .. Theme.escape(Theme.color.textFaint) .. " x" .. r.qty .. "|r") or r.item end },
		{ key = "char", title = L["Character"], flex = 2, text = function(r) return names[r.char] or "?" end, color = function() return Theme.color.textMuted end },
		{ key = "price", title = L["Sold for"], width = 90, align = "RIGHT", text = function(r) return UI.layout.amount(r.price) end },
		{ key = "net", title = L["After cut"], width = 90, align = "RIGHT", text = function(r) return UI.layout.amount(r.net) end },
		{ key = "t", title = L["When"], width = 70, align = "RIGHT", text = function(r) return Views.ago(r.t, ns.now()) end, color = function() return Theme.color.textFaint end },
	}, { pageSize = 8, empty = L["No sale yet: they are read from the auction house's mail when you open it."], sort = sortOf("sales", 5) })
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		-- Shared with Money: whichever tab chose last.
		local whose = settings().ledger or "me"
		tabs:Select(whose)
		local sales, refs = LedgerView.sales(whose, ns.now())
		for ref, name in pairs(refs) do
			names[ref] = name
		end
		cards[1]:Set(tostring(sales.count), ns.plural(sales.count, L["sale"], L["sales"]))
		cards[2]:Set(UI.layout.money(sales.gross, "gold"), string.format(L["last %d days"], LEDGER_DAYS))
		cards[3]:Set(UI.layout.money(sales.net, "gold"), string.format(L["%s to the auction house"], UI.layout.money(sales.cut, "gold")))
		tbl:SetRows(sales.list)
	end
end

ns.hubPages.money = buildLedger
ns.hubPages.characters = buildCharacters
ns.hubPages.inventory = buildInventory
ns.hubPages.sales = buildSales
