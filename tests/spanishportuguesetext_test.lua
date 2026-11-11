-- The game's own text on the Spanish (esES, esMX) and Brazilian Portuguese (ptBR) clients, read by the
-- addon's patterns from gf#341, as germantext_test.lua does German's: each of the client's formats
-- clienttext.lua sets in English, as each client words it, formatted as the game would and read back. The
-- wordings are recalled, not copied from a client: each is confirmed in game with /run print(NAME) (the
-- owner's manual test, gf#352); a wording that differs goes here first.

local CLIENTS = {
	esES = {
		LOOT_ITEM_CREATED_SELF = "Creas: %s.",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "Creas: %sx%d.",
		ERR_AUCTION_SOLD_S = "Se ha encontrado un comprador para tu subasta de %s.",
		AUCTION_SOLD_MAIL_SUBJECT = "Subasta completada: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "Subasta caducada: %s",
		AUCTION_REMOVED_MAIL_SUBJECT = "Subasta cancelada: %s",
		AUCTION_WON_MAIL_SUBJECT = "Subasta ganada: %s",
		AUCTION_OUTBID_MAIL_SUBJECT = "Puja superada en %s",
		FACTION_STANDING_INCREASED = "Tu reputación con %s ha aumentado en %d.",
		FACTION_STANDING_DECREASED = "Tu reputación con %s ha disminuido en %d.",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "La reputación de tu banda guerrera con %s ha aumentado en %d.",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "La reputación de tu banda guerrera con %s ha disminuido en %d.",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s muere, ganas %d p. de experiencia.",
		ERR_ZONE_EXPLORED_XP = "Descubierto: %s: %d p. de experiencia ganados",
	},
	esMX = {
		LOOT_ITEM_CREATED_SELF = "Creas: %s.",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "Creas: %sx%d.",
		ERR_AUCTION_SOLD_S = "Se encontró un comprador para tu subasta de %s.",
		AUCTION_SOLD_MAIL_SUBJECT = "Subasta exitosa: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "Subasta expirada: %s",
		AUCTION_REMOVED_MAIL_SUBJECT = "Subasta cancelada: %s",
		AUCTION_WON_MAIL_SUBJECT = "Subasta ganada: %s",
		AUCTION_OUTBID_MAIL_SUBJECT = "Oferta superada en %s",
		FACTION_STANDING_INCREASED = "Tu reputación con %s aumentó %d.",
		FACTION_STANDING_DECREASED = "Tu reputación con %s disminuyó %d.",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "La reputación de tu banda guerrera con %s aumentó %d.",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "La reputación de tu banda guerrera con %s disminuyó %d.",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s muere, ganas %d de experiencia.",
		ERR_ZONE_EXPLORED_XP = "%s descubierto: ganaste %d de experiencia",
	},
	ptBR = {
		LOOT_ITEM_CREATED_SELF = "Você cria: %s.",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "Você cria: %sx%d.",
		ERR_AUCTION_SOLD_S = "Um comprador foi encontrado para o seu leilão de %s.",
		AUCTION_SOLD_MAIL_SUBJECT = "Leilão bem-sucedido: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "Leilão expirado: %s",
		AUCTION_REMOVED_MAIL_SUBJECT = "Leilão cancelado: %s",
		AUCTION_WON_MAIL_SUBJECT = "Leilão ganho: %s",
		AUCTION_OUTBID_MAIL_SUBJECT = "Lance superado em %s",
		FACTION_STANDING_INCREASED = "Reputação com %s aumentou em %d.",
		FACTION_STANDING_DECREASED = "Reputação com %s diminuiu em %d.",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "A reputação do seu Bando de Guerra com %s aumentou em %d.",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "A reputação do seu Bando de Guerra com %s diminuiu em %d.",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s morre, você ganha %d de experiência.",
		ERR_ZONE_EXPLORED_XP = "Descobriu %s: %d de experiência ganha",
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
local LINK = "|cffffffff|Hitem:2996::::::::30|h[Rollo de lino]|h|r"
for code, F in pairs(CLIENTS) do
	-- Every English format has this client's one here.
	for _, name in ipairs(ENGLISH) do
		eq(type(_G[name]) == "string" and type(F[name]), "string", code .. ": a wording of " .. name)
	end

	-- A message as the game sends it, and what the addon's matcher reads from it.
	local function read(name, whole, ...)
		return table.concat({ E.matcher(F[name], whole)(string.format(F[name], ...)) }, "|")
	end
	eq(read("LOOT_ITEM_CREATED_SELF", false, LINK), LINK, code .. ": a craft")
	eq(read("LOOT_ITEM_CREATED_SELF_MULTIPLE", false, LINK, 2), LINK .. "|2", code .. ": a craft of two")
	eq(read("ERR_AUCTION_SOLD_S", true, "Paño de lana"), "Paño de lana", code .. ": an auction sold")
	eq(read("FACTION_STANDING_INCREASED", false, "Ventormenta", 250), "Ventormenta|250", code .. ": reputation up")
	eq(read("FACTION_STANDING_DECREASED", false, "Ventormenta", 50), "Ventormenta|50", code .. ": reputation down")
	eq(read("FACTION_STANDING_INCREASED_ACCOUNT_WIDE", false, "Los Asaltaconcejos", 75), "Los Asaltaconcejos|75", code .. ": warband reputation up")
	eq(read("FACTION_STANDING_DECREASED_ACCOUNT_WIDE", false, "Los Asaltaconcejos", 75), "Los Asaltaconcejos|75", code .. ": warband reputation down")
	eq(read("COMBATLOG_XPGAIN_FIRSTPERSON", false, "Kóbold", 120), "Kóbold|120", code .. ": a kill's XP")
	eq(read("ERR_ZONE_EXPLORED_XP", false, "Colinas: Norte", 55), "Colinas: Norte|55", code .. ": a discovery, a colon in its name")
	eq(E.matcher(F.FACTION_STANDING_INCREASED)(string.format(F.FACTION_STANDING_DECREASED, "Ventormenta", 50)), nil, code .. ": a loss is no gain")

	-- The auction house's mail subjects, as MailHelper.lua tells them from a player's letter.
	local P = M.patterns({ F.AUCTION_SOLD_MAIL_SUBJECT, F.AUCTION_EXPIRED_MAIL_SUBJECT, F.AUCTION_REMOVED_MAIL_SUBJECT,
		F.AUCTION_WON_MAIL_SUBJECT, F.AUCTION_OUTBID_MAIL_SUBJECT })
	for _, name in ipairs({ "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
		"AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT" }) do
		eq(M.isAuction(string.format(F[name], "Mena de hierro (20)"), P), true, code .. ": " .. name)
	end
	eq(M.isAuction("RE: " .. string.format(F.AUCTION_SOLD_MAIL_SUBJECT, "lol"), P), false, code .. ": a player's reply is not")
end
return checks()
