-- The client's grammar markers in the message formats the addon reads (Encode.matcher). The game resolves
-- each before the message is sent: Korean's |1X;Y; to the particle X or Y the word before it takes, French's
-- |2 to "de " or "d'", Russian's |4A:B:C; to the plural form of the number before it. So a format read as
-- written matches no message. Every format below is the client's own: Ketho/BlizzardInterfaceResources,
-- branch forever, Resources/GlobalStrings/<locale>.lua (commit d1ee5698, 2026-10-21); each message is
-- as the game shows it.

local ns = {}
loadEncode(ns)
local E = ns.Encode

local function read(format, message, whole)
	return table.concat({ E.matcher(format, whole)(message) }, "|")
end

local LINK = "|cffffffff|Hitem:2996::::::::30|h[리넨 두루마리]|h|r"

-- koKR: the three formats of the addon's readers that hold a marker (ERR_AUCTION_SOLD_S has none).
local XP_KO = "%s|1이;가; 죽었습니다. %d의 경험치를 획득했습니다."
eq(read(XP_KO, "늑대가 죽었습니다. 120의 경험치를 획득했습니다."), "늑대|120", "koKR COMBATLOG_XPGAIN_FIRSTPERSON: a kill, 가")
eq(read(XP_KO, "멧돼지 왕이 죽었습니다. 45의 경험치를 획득했습니다."), "멧돼지 왕|45", "koKR COMBATLOG_XPGAIN_FIRSTPERSON: a kill, 이")
eq(read(XP_KO, "고양이가 죽었습니다. 3의 경험치를 획득했습니다."), "고양이|3", "koKR COMBATLOG_XPGAIN_FIRSTPERSON: a name ending in 이 keeps it")
local CREATED_KO = "%s|1을;를; 만들었습니다."
eq(read(CREATED_KO, LINK .. "를 만들었습니다."), LINK, "koKR LOOT_ITEM_CREATED_SELF: a craft, 를")
eq(read(CREATED_KO, LINK .. "을 만들었습니다."), LINK, "koKR LOOT_ITEM_CREATED_SELF: a craft, 을")
local MULTIPLE_KO = "%s|1을;를; %d개 만들었습니다."
eq(read(MULTIPLE_KO, LINK .. "를 2개 만들었습니다."), LINK .. "|2", "koKR LOOT_ITEM_CREATED_SELF_MULTIPLE: a craft of two")
eq(read(MULTIPLE_KO, LINK .. "을 5개 만들었습니다."), LINK .. "|5", "koKR LOOT_ITEM_CREATED_SELF_MULTIPLE: of five, 을")
eq(E.matcher(CREATED_KO)(LINK .. "를 2개 만들었습니다."), nil, "koKR: a craft of two is not a craft of one")
eq(E.matcher(XP_KO)("늑대가 죽었습니다."), nil, "koKR: a death without XP is no XP")

-- frFR: |2 before a name.
local SOLD_FR = "Un acheteur a été trouvé pour votre enchère |2 %s."
eq(read(SOLD_FR, "Un acheteur a été trouvé pour votre enchère de Toile de lin.", true), "Toile de lin", "frFR ERR_AUCTION_SOLD_S: de")
eq(read(SOLD_FR, "Un acheteur a été trouvé pour votre enchère d'Étoffe de laine.", true), "Étoffe de laine", "frFR ERR_AUCTION_SOLD_S: d'")
eq(read("Réputation auprès |2 %s augmentée de %d points.", "Réputation auprès de Hurlevent augmentée de 250 points."), "Hurlevent|250", "frFR FACTION_STANDING_INCREASED")
eq(read("Réputation auprès |2 %s baissée de %d points.", "Réputation auprès d'Ironforge baissée de 50 points."), "Ironforge|50", "frFR FACTION_STANDING_DECREASED")
eq(E.matcher("Réputation auprès |2 %s augmentée de %d points.")("Réputation auprès d'Ironforge baissée de 50 points."), nil, "frFR: a loss is no gain")

-- ruRU: |4 after a number, three forms.
local XP_RU = "%s погибает, вы получаете %d |4очко:очка:очков; опыта."
eq(read(XP_RU, "Кобольд погибает, вы получаете 1 очко опыта."), "Кобольд|1", "ruRU COMBATLOG_XPGAIN_FIRSTPERSON: one")
eq(read(XP_RU, "Кобольд погибает, вы получаете 3 очка опыта."), "Кобольд|3", "ruRU COMBATLOG_XPGAIN_FIRSTPERSON: a few")
eq(read(XP_RU, "Кобольд погибает, вы получаете 120 очков опыта."), "Кобольд|120", "ruRU COMBATLOG_XPGAIN_FIRSTPERSON: many")
eq(read("Открыта новая территория: %s. Получено %d |4очко:очка:очков; опыта.", "Открыта новая территория: Долина Северного Щита. Получено 55 очков опыта."),
	"Долина Северного Щита|55", "ruRU ERR_ZONE_EXPLORED_XP")

-- A format without a marker reads as before.
eq(read("You create: %sx%d.", "You create: " .. LINK .. "x2."), LINK .. "|2", "no marker: one form")

return checks()
