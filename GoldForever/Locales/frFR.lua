-- Gold Forever: the addon's texts in French, for a French client (Locale.lua). Game terms are those of
-- Blizzard's French client. tests/locale_test.lua fails on a text missing here or not in enUS.lua.

local _, ns = ...

ns.Locale.add("frFR", {
	-- Kernel
	["Translated with AI: it may contain mistakes."] = "Traduction faite par une IA : elle peut contenir des erreurs.",
	["%s commands:"] = "Commandes de %s :",
	["  /gf - open or close the window"] = "  /gf - ouvrir ou fermer la fenêtre",
	["  /gf hud - show or hide the session HUD"] = "  /gf hud - afficher ou masquer le HUD de la session",
	["  /gf ah - show or hide the auction panel · /gf scan - scan the auction house"] = "  /gf ah - afficher ou masquer le panneau des enchères · /gf scan - analyser l'hôtel des ventes",
	["  /gf shop - your crafts by profit"] = "  /gf shop - vos fabrications par bénéfice",
	["  /gf look web|classic|arcane - change the look · /gf minimap - the minimap button"] = "  /gf look web|classic|arcane - changer l'apparence · /gf minimap - le bouton de la minicarte",
	["  /gf ui <page> - open a page · /gf session - the session in chat · /gf reset - a new session"] = "  /gf ui <page> - ouvrir une page · /gf session - la session dans la discussion · /gf reset - une nouvelle session",
	["  /gf bigdrop <gold> - big-drop alerts · /gf accent #rrggbb · /gf welcome - the first-run card"] = "  /gf bigdrop <or> - alertes de gros butin · /gf accent #rrggbb · /gf welcome - la carte de bienvenue",
	["  /gf prices - the prices file · /gf rares [mark] · /gf mark (skull the rare) · /gf claim <code> · /gf export · /gf check - details for a bug report"] = "  /gf prices - le fichier des prix · /gf rares [mark] · /gf mark (un crâne sur le rare) · /gf claim <code> · /gf export · /gf check - les détails pour un rapport de bug",
	["  /gf bags - why bag marks do or don't show"] = "  /gf bags - pourquoi les marques des sacs s'affichent ou non",
	["  More: /gf help all"] = "  Plus : /gf help all",
	["off this session: %s"] = "désactivé pour cette session : %s",
	["%s: no command \"%s\". /gf help lists them."] = "%s : pas de commande \"%s\". /gf help les liste.",
	["%s failed: %s"] = "%s a échoué : %s",
	["%s is turned off in the AddOns list: turn it on there to use the auction house panel."] = "%s est désactivé dans la liste des AddOns : activez-le pour utiliser le panneau de l'hôtel des ventes.",
	["the %s folder is not installed: reinstall Gold Forever, or in a developer install link both folders into AddOns."] = "le dossier %s n'est pas installé : réinstallez Gold Forever, ou, dans une installation de développement, liez les deux dossiers dans AddOns.",
})
