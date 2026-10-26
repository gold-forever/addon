-- Gold Forever: the hub's Guide page: how to use Gold Forever, and the commands.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local Kit = ns.HubKit

-- How to use Gold Forever, for players at launch (owner's answer, 2026-10-24): short sections, the keys
-- and the commands. Every command named here exists (the tests check GUIDE_COMMANDS).
local GUIDE = {
	{ "Getting started", "Gold Forever records your characters, money, loot and auction scans for your pages on gold-forever.app, and brings everyone's prices into the game. Install the free companion app (gold-forever.app/companion): it uploads your save when the game writes it and brings prices in every hour. /gf opens this window; the minimap coin does too (right-click switches the look)." },
	{ "At the auction house", "A panel opens beside the auction house. Its tabs follow Blizzard's. Scan runs a full scan when you press Scan now (one every 15 minutes; switch on \"Scan when I open the auction house\" to have it start by itself). Sell lists what your bags can sell, priced by your selling rules against the cheapest listing by someone else; alt-click an item in your bags to choose it, then click Post or press Space. A price far under the market or a vendor's asks for a second press. Your bag items' tooltips say what Sell would ask; the panel's top line says what your bank and mail hold worth posting." },
	{ "Buy and Auctions", "Buy buys from a shopping list: choose a list, click an item to see its listings, and Buy next asks the auction house for a price; a second press buys. Lists are made on the Shopping lists page (Edit lists ›): drop an item on its slot or shift-click it anywhere, then set the most you pay (under market, a fixed price or a share of the market value) and how many you want. Auctions checks your auctions and cancels the most undercut one a press (the item comes back by mail); click one to see its listings." },
	{ "Selling rules and profiles", "The Selling rules page sets how you undercut, the floor and the normal price, and shows what that does to an item worth 10g; \"Rule for\" adds a rule for one item or a whole category (Rule › on the Sell tab opens it for the item in view). A sale profile (a GFP1 string, made at gold-forever.app/me/lists or shared by others) prices the items it names: keep so many, undercut, a fixed price or a point in the supply." },
	{ "Crafting", "The Crafting page lists your recipes by profit; \"I have these\" counts what you hold at no cost. Queue crafts there or on the strip beside the profession window, and the Buy tab's \"Craft queue\" list buys only what is missing." },
	{ "While you play", "The session HUD shows gold, XP and kills an hour; click it for the session. Big drops and rares get a message. The mail helper beside the mailbox opens auction mail a batch a press. Settings → Modules switches any part off; what the save records stays the same." },
	{ "Discord", "Add a Discord webhook at gold-forever.app/settings, then switch \"Announce dings\" on in Settings → Discord for the character you play: each level-up posts a picture and a public page." },
}
local GUIDE_COMMANDS = {
	{ "/gf", "this window (and /gf help: every command)" }, { "/gf hud", "the session HUD" }, { "/gf ah", "the auction panel" },
	{ "/gf look arcane", "a look (web, classic, arcane)" }, { "/gf accent #2fd1a8", "an accent colour" }, { "/gf dings on", "Discord dings" },
	{ "/gf scan", "a full scan at the auction house" }, { "/gf welcome", "the first-run card" }, { "/gf prices", "the prices file" },
}
ns.test.GUIDE_COMMANDS = GUIDE_COMMANDS

local function buildGuide(page)
	local body = Kit.scrollBody(page, 680, 900)
	local y = 0
	for _, section in ipairs(GUIDE) do
		local h = UI.Text(body, Theme.skin.titleCaps and string.upper(section[1]) or section[1], { size = "md", medium = true, tone = "accent" })
		h:SetPoint("TOPLEFT", 0, y)
		local t = UI.Text(body, section[2], { size = "sm", tone = "muted", wrap = true })
		t:SetPoint("TOPLEFT", h, "BOTTOMLEFT", 0, -6)
		t:SetWidth(660)
		y = y - 26 - math.max(36, (t:GetStringHeight() or 36)) - 14
	end
	local h = UI.Text(body, Theme.skin.titleCaps and "COMMANDS" or "Commands", { size = "md", medium = true, tone = "accent" })
	h:SetPoint("TOPLEFT", 0, y)
	y = y - 24
	for _, c in ipairs(GUIDE_COMMANDS) do
		local k = UI.Text(body, c[1], { size = "sm" })
		k:SetPoint("TOPLEFT", 0, y)
		local v = UI.Text(body, c[2], { size = "sm", tone = "muted" })
		v:SetPoint("TOPLEFT", 200, y)
		y = y - 20
	end
	body:SetHeight(-y + 20)
end

ns.hubPages.guide = buildGuide
