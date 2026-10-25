-- Gold Forever: the in-game window (/gf ui): web pages brought into the game from the saved file
-- (characters and who to play next, levelling, the ledger, mobs by what a loot is worth, everything
-- the characters hold), one window per look, with the pages the Hub*.lua files and DesignSystem.lua add
-- to ns.hubPages.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local settings = ns.HubKit.settings

-- One window per look and accent, built the first time it opens: frames cannot be restyled in place,
-- and switching should not need a /reload. All share the saved position, page, scale and sorts.
local windows = {}

-- A page of tabs (design 009 decision 2, settled: the old pages folded into fewer rows, each a tab):
-- underline tabs at the top, each tab's page built the first time it is shown, the tab kept per page.
local function tabbed(key, tabs)
	return function(page)
		local store = settings()
		store.tabs = store.tabs or {}
		local bar = UI.TabBar(page, tabs, function(k)
			page:SelectTab(k)
		end, { variant = "underline" })
		bar:SetPoint("TOPLEFT")
		bar:SetPoint("TOPRIGHT")
		local subs = {}
		function page:SelectTab(k)
			local def
			for _, t in ipairs(tabs) do
				if t.key == k then
					def = t
				end
			end
			def = def or tabs[1]
			for _, f in pairs(subs) do
				f:Hide()
			end
			local sub = subs[def.key]
			if not sub then
				sub = CreateFrame("Frame", nil, page)
				sub:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -14)
				sub:SetPoint("BOTTOMRIGHT")
				-- A tab can name the page more closely (whose levelling it shows), as a page can.
				function sub.SetTitle(_, text)
					if page.SetTitle then
						page:SetTitle(text)
					end
				end
				ns.safely("ui " .. def.key, def.build, sub)
				subs[def.key] = sub
			end
			sub:Show()
			if page.SetTitle and page.title then
				page:SetTitle(page.title) -- a tab that names the page more closely sets it again on refresh
			end
			bar:Select(def.key)
			store.tabs[key] = def.key
			self.tab = def.key
			if sub.Refresh then
				ns.safely("ui " .. def.key, sub.Refresh, sub)
			end
		end
		function page:Refresh()
			self:SelectTab(self.tab or store.tabs[key])
		end
		-- The window refreshes a page right after building it, which shows this tab.
		page.tab = store.tabs[key] or tabs[1].key
	end
end

-- The tabbed pages' tabs; the sidebar's search finds a page by a tab's name too.
local LEDGER_TABS = {
	{ key = "money", label = "Money", build = ns.hubPages.money },
	{ key = "characters", label = "Characters", build = ns.hubPages.characters },
	{ key = "inventory", label = "Inventory", build = ns.hubPages.inventory },
	{ key = "sales", label = "Auction sales", build = ns.hubPages.sales },
}
local SESSION_TABS = {
	{ key = "now", label = "This session", build = ns.hubPages.now },
	{ key = "levelling", label = "Levelling", build = ns.hubPages.levelling },
	{ key = "mobs", label = "Mobs", build = ns.hubPages.mobs },
}
local PAGES = {
	{ key = "home", label = "Home", icon = "coins", group = "Overview", build = ns.hubPages.home, title = "Home",
		lede = "Your next moves, from everyone's prices and your own bags." },
	{ key = "ledger", label = "Ledger", icon = "book-open", group = "Overview", title = "Ledger",
		lede = "Where your money went and came from, your characters, and everything they hold.",
		tabs = LEDGER_TABS, build = tabbed("ledger", LEDGER_TABS) },
	{ key = "crafting", label = "Crafting", icon = "flask-conical", group = "Trading", build = ns.hubPages.crafting, title = "Crafting",
		lede = "Your recipes by profit: reagents at the cheaper of auction house and vendor, the item at its price after the cut." },
	{ key = "lists", label = "Shopping lists", icon = "backpack", group = "Trading", title = "Shopping lists",
		lede = "What the auction panel's Buy tab buys: your lists, their items, the most you pay and how many.",
		build = function(page)
			ns.buildShoppingLists(page)
		end },
	{ key = "rules", label = "Selling rules", icon = "tag", group = "Trading", title = "Selling rules",
		lede = "How the auction panel's Sell tab prices your items: by these rules, or a sale profile.",
		build = function(page)
			ns.buildSellingRules(page)
		end },
	{ key = "session", label = "Session", icon = "timer", group = "Play", title = "Session",
		lede = "Levelling at this character's pace, and every mob by what a loot of it is worth. The HUD shows the session live.",
		tabs = SESSION_TABS, build = tabbed("session", SESSION_TABS) },
	{ key = "rares", label = "Rares", icon = "skull", group = "Play", build = ns.hubPages.rares, title = "Rares",
		lede = "Every rare your characters have seen, where and when last, and what a loot of one has been worth." },
	{ key = "companion", label = "Companion", icon = "rotate-ccw", group = "Addon", build = ns.hubPages.companion, title = "Companion",
		lede = "Everyone's prices in the game, and your save on the site: what the companion app has brought in." },
	{ key = "settings", label = "Settings", icon = "settings", group = "Addon", build = ns.hubPages.settings, title = "Settings",
		lede = "How Gold Forever looks and behaves. Changes apply at once." },
	{ key = "guide", label = "Guide", icon = "circle-help", group = "Addon", build = ns.hubPages.guide, title = "Guide",
		lede = "How to use Gold Forever: the auction house panel, crafting, the session, Discord, and the commands." },
	{ key = "design", label = "Design system", icon = "palette", group = "Addon", build = ns.hubPages.design, title = "Design system",
		lede = "Every part of the window kit with example data, in the look in use." },
}

-- The pages that became tabs, by their old keys: /gf ui levelling, a saved page, a card's link.
local FOLDED = {
	characters = { "ledger", "characters" }, inventory = { "ledger", "inventory" }, money = { "ledger", "money" },
	sales = { "ledger", "sales" },
	levelling = { "session", "levelling" }, mobs = { "session", "mobs" }, now = { "session", "now" },
}

-- Opens a page, or the page and tab an old key names.
local function openIn(window, key)
	local f = FOLDED[key]
	if f then
		settings().tabs = settings().tabs or {}
		settings().tabs[f[1]] = f[2]
		-- The page shows this tab as it opens, rather than refreshing the last one first.
		local page = window.pages[f[1]]
		if page then
			page.tab = f[2]
		end
		window:SelectPage(f[1])
		page = window.pages[f[1]]
		if page and page.SelectTab and page.tab ~= f[2] then
			page:SelectTab(f[2])
		end
	else
		window:SelectPage(key)
	end
end
ns.openPage = function(key)
	ns.commands.ui(key)
end

local function windowFor(name)
	-- A page saved before the pages were folded opens as its tab.
	local folded = FOLDED[settings().page or ""]
	if folded then
		settings().tabs = settings().tabs or {}
		settings().tabs[folded[1]] = folded[2]
		settings().page = folded[1]
	end
	local hex = ns.sessionAccent()
	Theme.apply(name, hex)
	local key = name .. (hex and string.gsub(hex, "#", "_") or "")
	local built = not windows[key]
	if built then
		windows[key] = UI.Window(key == "web" and "GoldForeverWindow" or "GoldForeverWindow_" .. key, "Gold Forever", PAGES, settings(), {
			version = ns.VERSION,
			look = Theme.skins[name].label,
			extra = { label = "Export", onClick = function()
				ns.commands.export()
			end, shown = function()
				return not ns.Prices.connected(GoldForever_Prices, ns.now())
			end },
		})
	end
	return windows[key], built
end

-- Whether the window has in view the page (and tab) a key names, as the saved page: a window just built
-- or shown again has then refreshed it already, and opening it again would refresh it twice.
local function showing(window, key)
	local f = FOLDED[key]
	local name = f and f[1] or key
	local page = window.pages[name]
	return settings().page == name and page ~= nil and page:IsShown() and (not f or page.tab == f[2])
end

local function shown()
	for _, w in pairs(windows) do
		if w:IsShown() then
			return w
		end
	end
end

-- For the smoke test: the window open now.
ns.hubWindow = function()
	return shown()
end

ns.commands.ui = function(page)
	local open = shown()
	if open and (page == nil or page == "") then
		open:Hide()
		return
	end
	-- An old key's tab, set before the window builds or shows its page.
	local f = page and FOLDED[page]
	if f then
		settings().tabs = settings().tabs or {}
		settings().tabs[f[1]] = f[2]
	end
	local window, built = windowFor(ns.currentLook())
	local fresh = built or not window:IsShown()
	if f and fresh and window.pages[f[1]] then
		window.pages[f[1]].tab = f[2]
	end
	-- Another page than the one it shows opens refreshed once, by openIn, not first the old one as it
	-- shows (review C-18).
	local other = page and page ~= "" and not (fresh and showing(window, page))
	window:Restore()
	window.opening = other
	window:Show()
	window.opening = nil
	-- In front every time, an open window too (manual test run 001: Rule › left it under the panel).
	window:Raise()
	if other then
		openIn(window, page)
	end
end

-- An open window rebuilt in the look and accent now set, on the same page (/gf look, /gf accent in
-- Looks.lua). Returns whether a window was open.
ns.hubReopen = function()
	local open = shown()
	if not open then
		return false
	end
	open:Hide()
	local window, built = windowFor(ns.currentLook())
	local fresh = built or not window:IsShown()
	window:Restore()
	window:Show()
	local key = settings().page or PAGES[1].key
	if not (fresh and showing(window, key)) then
		window:SelectPage(key)
	end
	return true
end
