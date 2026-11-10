-- Gold Forever: every text the addon shows, in English, the source language (Locale.lua). A text written
-- L["…"] in a file is listed here; tests/locale_test.lua fails on one missing or no longer used.

local _, ns = ...

ns.Locale.source({
	-- Kernel
	"Translated with AI: it may contain mistakes.",
	"%s commands:",
	"  /gf - open or close the window",
	"  /gf hud - show or hide the session HUD",
	"  /gf ah - show or hide the auction panel · /gf scan - scan the auction house",
	"  /gf shop - your crafts by profit",
	"  /gf look web|classic|arcane - change the look · /gf minimap - the minimap button",
	"  /gf ui <page> - open a page · /gf session - the session in chat · /gf reset - a new session",
	"  /gf bigdrop <gold> - big-drop alerts · /gf accent #rrggbb · /gf welcome - the first-run card",
	"  /gf prices - the prices file · /gf rares [mark] · /gf mark (skull the rare) · /gf claim <code> · /gf export · /gf check - details for a bug report",
	"  /gf bags - why bag marks do or don't show",
	"  More: /gf help all",
	"off this session: %s",
	"%s: no command \"%s\". /gf help lists them.",
	"%s failed: %s",
	"%s is turned off in the AddOns list: turn it on there to use the auction house panel.",
	"the %s folder is not installed: reinstall Gold Forever, or in a developer install link both folders into AddOns.",
})
