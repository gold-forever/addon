-- The game's own text on a German client (deDE), read by the addon's patterns from gf#341: each of the
-- client's formats clienttext.lua sets in English, as the German client words it, formatted as the game
-- would and read back. The wordings are recalled, not copied from a client: each is confirmed in game
-- with /run print(NAME) (the owner's manual test, gf#342); a wording that differs goes here first.

local DE = {
	LOOT_ITEM_CREATED_SELF = "Ihr stellt her: %s.",
	LOOT_ITEM_CREATED_SELF_MULTIPLE = "Ihr stellt her: %sx%d.",
	ERR_AUCTION_SOLD_S = "Es wurde ein Käufer für Eure Auktion gefunden: %s.",
	AUCTION_SOLD_MAIL_SUBJECT = "Auktion erfolgreich: %s",
	AUCTION_EXPIRED_MAIL_SUBJECT = "Auktion abgelaufen: %s",
	AUCTION_REMOVED_MAIL_SUBJECT = "Auktion abgebrochen: %s",
	AUCTION_WON_MAIL_SUBJECT = "Auktion gewonnen: %s",
	AUCTION_OUTBID_MAIL_SUBJECT = "Überboten: %s",
	FACTION_STANDING_INCREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verbessert.",
	FACTION_STANDING_DECREASED = "Euer Ruf bei der Fraktion '%s' hat sich um %d verschlechtert.",
	FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "Der Ruf Eurer Kriegsmeute bei der Fraktion '%s' hat sich um %d verbessert.",
	FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "Der Ruf Eurer Kriegsmeute bei der Fraktion '%s' hat sich um %d verschlechtert.",
	COMBATLOG_XPGAIN_FIRSTPERSON = "%s stirbt, Ihr bekommt %d Erfahrung.",
	ERR_ZONE_EXPLORED_XP = "Entdeckt: %s: %d Erfahrungspunkte erhalten",
}

local ns = { on = function() end }
loadEncode(ns)
assert(load(SOURCES["MailHelper.lua"], "@MailHelper.lua"))("GoldForever", ns)
local E, M = ns.Encode, ns.Mail

-- Every English format has its German one here.
local English = { "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE", "ERR_AUCTION_SOLD_S", "AUCTION_SOLD_MAIL_SUBJECT",
	"AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT",
	"FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED", "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
	"FACTION_STANDING_DECREASED_ACCOUNT_WIDE", "COMBATLOG_XPGAIN_FIRSTPERSON", "ERR_ZONE_EXPLORED_XP" }
for _, name in ipairs(English) do
	eq(type(_G[name]) == "string" and type(DE[name]), "string", "a German wording of " .. name)
end

-- A message as the game sends it, and what the addon's matcher reads from it.
local function read(name, whole, ...)
	return table.concat({ E.matcher(DE[name], whole)(string.format(DE[name], ...)) }, "|")
end
local LINK = "|cffffffff|Hitem:2996::::::::30|h[Leinenstoffballen]|h|r"
eq(read("LOOT_ITEM_CREATED_SELF", false, LINK), LINK, "a craft")
eq(read("LOOT_ITEM_CREATED_SELF_MULTIPLE", false, LINK, 2), LINK .. "|2", "a craft of two")
eq(read("ERR_AUCTION_SOLD_S", true, "Wollstoff"), "Wollstoff", "an auction sold")
eq(read("FACTION_STANDING_INCREASED", false, "Sturmwind", 250), "Sturmwind|250", "reputation up")
eq(read("FACTION_STANDING_DECREASED", false, "Sturmwind", 50), "Sturmwind|50", "reputation down")
eq(read("FACTION_STANDING_INCREASED_ACCOUNT_WIDE", false, "Die Weltenwanderer", 75), "Die Weltenwanderer|75", "warband reputation up")
eq(read("FACTION_STANDING_DECREASED_ACCOUNT_WIDE", false, "Die Weltenwanderer", 75), "Die Weltenwanderer|75", "warband reputation down")
eq(read("COMBATLOG_XPGAIN_FIRSTPERSON", false, "Kobold", 120), "Kobold|120", "a kill's XP")
eq(read("ERR_ZONE_EXPLORED_XP", false, "Klingenhügel", 55), "Klingenhügel|55", "a discovery, its colon within the format")
eq(E.matcher(DE.FACTION_STANDING_INCREASED)(string.format(DE.FACTION_STANDING_DECREASED, "Sturmwind", 50)), nil, "a loss is no gain")

-- The auction house's mail subjects, as MailHelper.lua tells them from a player's letter.
local P = M.patterns({ DE.AUCTION_SOLD_MAIL_SUBJECT, DE.AUCTION_EXPIRED_MAIL_SUBJECT, DE.AUCTION_REMOVED_MAIL_SUBJECT,
	DE.AUCTION_WON_MAIL_SUBJECT, DE.AUCTION_OUTBID_MAIL_SUBJECT })
eq(M.isAuction("Auktion erfolgreich: Wollstoff", P), true, "sold")
eq(M.isAuction("Auktion abgelaufen: Leinenstoff (20)", P), true, "expired, with a stack in brackets")
eq(M.isAuction("Auktion abgebrochen: Seidenstoff", P), true, "cancelled")
eq(M.isAuction("Auktion gewonnen: Eisenerz", P), true, "won")
eq(M.isAuction("Überboten: Kupferbarren", P), true, "outbid")
eq(M.isAuction("AW: Auktion erfolgreich: lol", P), false, "a player's reply is not")
return checks()
