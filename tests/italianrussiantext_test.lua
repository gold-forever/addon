-- The game's own text on the Italian (itIT) and Russian (ruRU) clients, read by the addon's patterns from
-- gf#341, as spanishportuguesetext_test.lua does Spanish's and Portuguese's: each of the client's formats
-- clienttext.lua sets in English, as each client words it, formatted as the game would and read back. The
-- wordings are recalled, not copied from a client: each is confirmed in game with /run print(NAME) (the
-- owner's manual test, gf#356); a wording that differs goes here first.

local CLIENTS = {
	itIT = {
		LOOT_ITEM_CREATED_SELF = "Hai creato: %s.",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "Hai creato: %sx%d.",
		ERR_AUCTION_SOLD_S = "È stato trovato un acquirente per la tua asta di %s.",
		AUCTION_SOLD_MAIL_SUBJECT = "Asta conclusa: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "Asta scaduta: %s",
		AUCTION_REMOVED_MAIL_SUBJECT = "Asta annullata: %s",
		AUCTION_WON_MAIL_SUBJECT = "Asta vinta: %s",
		AUCTION_OUTBID_MAIL_SUBJECT = "Offerta superata per %s",
		FACTION_STANDING_INCREASED = "La tua reputazione con %s è aumentata di %d.",
		FACTION_STANDING_DECREASED = "La tua reputazione con %s è diminuita di %d.",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "La reputazione della tua brigata con %s è aumentata di %d.",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "La reputazione della tua brigata con %s è diminuita di %d.",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s muore, ottieni %d punti esperienza.",
		ERR_ZONE_EXPLORED_XP = "Hai scoperto %s: %d punti esperienza ottenuti",
	},
	ruRU = {
		LOOT_ITEM_CREATED_SELF = "Вы создаете: %s.",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "Вы создаете: %sx%d.",
		ERR_AUCTION_SOLD_S = "Найден покупатель на ваш лот: %s.",
		AUCTION_SOLD_MAIL_SUBJECT = "Аукцион состоялся: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "Аукцион не состоялся: %s",
		AUCTION_REMOVED_MAIL_SUBJECT = "Аукцион отменен: %s",
		AUCTION_WON_MAIL_SUBJECT = "Аукцион выигран: %s",
		AUCTION_OUTBID_MAIL_SUBJECT = "Ваша ставка на %s перебита",
		FACTION_STANDING_INCREASED = "Отношение фракции %s к вам улучшилось на %d.",
		FACTION_STANDING_DECREASED = "Отношение фракции %s к вам ухудшилось на %d.",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "Отношение фракции %s к вашему отряду улучшилось на %d.",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "Отношение фракции %s к вашему отряду ухудшилось на %d.",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s погибает, вы получаете %d ед. опыта.",
		ERR_ZONE_EXPLORED_XP = "Открыта местность: %s. Получено опыта: %d.",
	},
}

local ns = { on = function() end }
loadEncode(ns)
assert(load(SOURCES["MailHelper.lua"], "@MailHelper.lua"))("GoldForever", ns)
local E, M = ns.Encode, ns.Mail

local ENGLISH = { "LOOT_ITEM_CREATED_SELF", "LOOT_ITEM_CREATED_SELF_MULTIPLE", "ERR_AUCTION_SOLD_S", "AUCTION_SOLD_MAIL_SUBJECT",
	"AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT", "AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT",
	"FACTION_STANDING_INCREASED", "FACTION_STANDING_DECREASED", "FACTION_STANDING_INCREASED_ACCOUNT_WIDE",
	"FACTION_STANDING_DECREASED_ACCOUNT_WIDE", "COMBATLOG_XPGAIN_FIRSTPERSON", "ERR_ZONE_EXPLORED_XP" }
-- Names as each client spells them: Russian's in Cyrillic, which the patterns read byte for byte.
local NAMES = {
	itIT = { link = "|cffffffff|Hitem:2996::::::::30|h[Rotolo di lino]|h|r", item = "Stoffa di lana", faction = "Roccavento",
		warband = "Gli Assaltaconsiglio", mob = "Coboldo", zone = "Colline: Nord", mail = "Minerale di ferro (20)" },
	ruRU = { link = "|cffffffff|Hitem:2996::::::::30|h[Рулон льняной ткани]|h|r", item = "Шерстяная ткань", faction = "Штормград",
		warband = "Расхитители Совета", mob = "Кобольд", zone = "Холмы: Север", mail = "Железная руда (20)" },
}
for code, F in pairs(CLIENTS) do
	local N = NAMES[code]
	-- Every English format has this client's one here.
	for _, name in ipairs(ENGLISH) do
		eq(type(_G[name]) == "string" and type(F[name]), "string", code .. ": a wording of " .. name)
	end

	-- A message as the game sends it, and what the addon's matcher reads from it.
	local function read(name, whole, ...)
		return table.concat({ E.matcher(F[name], whole)(string.format(F[name], ...)) }, "|")
	end
	eq(read("LOOT_ITEM_CREATED_SELF", false, N.link), N.link, code .. ": a craft")
	eq(read("LOOT_ITEM_CREATED_SELF_MULTIPLE", false, N.link, 2), N.link .. "|2", code .. ": a craft of two")
	eq(read("ERR_AUCTION_SOLD_S", true, N.item), N.item, code .. ": an auction sold")
	eq(read("FACTION_STANDING_INCREASED", false, N.faction, 250), N.faction .. "|250", code .. ": reputation up")
	eq(read("FACTION_STANDING_DECREASED", false, N.faction, 50), N.faction .. "|50", code .. ": reputation down")
	eq(read("FACTION_STANDING_INCREASED_ACCOUNT_WIDE", false, N.warband, 75), N.warband .. "|75", code .. ": warband reputation up")
	eq(read("FACTION_STANDING_DECREASED_ACCOUNT_WIDE", false, N.warband, 75), N.warband .. "|75", code .. ": warband reputation down")
	eq(read("COMBATLOG_XPGAIN_FIRSTPERSON", false, N.mob, 120), N.mob .. "|120", code .. ": a kill's XP")
	eq(read("ERR_ZONE_EXPLORED_XP", false, N.zone, 55), N.zone .. "|55", code .. ": a discovery, a colon in its name")
	eq(E.matcher(F.FACTION_STANDING_INCREASED)(string.format(F.FACTION_STANDING_DECREASED, N.faction, 50)), nil, code .. ": a loss is no gain")

	-- The auction house's mail subjects, as MailHelper.lua tells them from a player's letter.
	local P = M.patterns({ F.AUCTION_SOLD_MAIL_SUBJECT, F.AUCTION_EXPIRED_MAIL_SUBJECT, F.AUCTION_REMOVED_MAIL_SUBJECT,
		F.AUCTION_WON_MAIL_SUBJECT, F.AUCTION_OUTBID_MAIL_SUBJECT })
	for _, name in ipairs({ "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
		"AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT" }) do
		eq(M.isAuction(string.format(F[name], N.mail), P), true, code .. ": " .. name)
	end
	eq(M.isAuction("RE: " .. string.format(F.AUCTION_SOLD_MAIL_SUBJECT, "lol"), P), false, code .. ": a player's reply is not")
end
return checks()
