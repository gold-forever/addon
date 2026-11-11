-- The game's own text on the Korean (koKR), Simplified Chinese (zhCN) and Traditional Chinese (zhTW) clients,
-- read by the addon's patterns from gf#341, as spanishportuguesetext_test.lua does Spanish's: each of the
-- client's formats clienttext.lua sets in English, as each client words it, formatted as the game would and
-- read back. The wordings are recalled, not copied from a client: each is confirmed in game with
-- /run print(NAME) (the owner's manual test, gf#357); a wording that differs goes here first.
--
-- Not here: Korean's ERR_AUCTION_SOLD_S and COMBATLOG_XPGAIN_FIRSTPERSON, recalled with the client's particle
-- markers ("%s|1이;가; 판매되었습니다."), which the game resolves before the message is sent and
-- Encode.matcher takes as written (gf#357's report).

local CLIENTS = {
	koKR = {
		LOOT_ITEM_CREATED_SELF = "아이템을 만들었습니다: %s.",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "아이템을 만들었습니다: %sx%d.",
		AUCTION_SOLD_MAIL_SUBJECT = "경매 성공: %s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "경매 기간 만료: %s",
		AUCTION_REMOVED_MAIL_SUBJECT = "경매 취소: %s",
		AUCTION_WON_MAIL_SUBJECT = "경매 낙찰: %s",
		AUCTION_OUTBID_MAIL_SUBJECT = "상회 입찰: %s",
		FACTION_STANDING_INCREASED = "%s 평판이 %d만큼 올랐습니다.",
		FACTION_STANDING_DECREASED = "%s 평판이 %d만큼 떨어졌습니다.",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "전투부대의 %s 평판이 %d만큼 올랐습니다.",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "전투부대의 %s 평판이 %d만큼 떨어졌습니다.",
		ERR_ZONE_EXPLORED_XP = "%s 탐험: 경험치 %d 획득",
	},
	zhCN = {
		LOOT_ITEM_CREATED_SELF = "你制造了：%s。",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "你制造了：%sx%d。",
		ERR_AUCTION_SOLD_S = "你拍卖的%s已经售出。",
		AUCTION_SOLD_MAIL_SUBJECT = "拍卖成功：%s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "拍卖到期：%s",
		AUCTION_REMOVED_MAIL_SUBJECT = "拍卖取消：%s",
		AUCTION_WON_MAIL_SUBJECT = "竞拍获胜：%s",
		AUCTION_OUTBID_MAIL_SUBJECT = "竞拍失败：%s",
		FACTION_STANDING_INCREASED = "你在%s中的声望值提高了%d点。",
		FACTION_STANDING_DECREASED = "你在%s中的声望值降低了%d点。",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "你的战团在%s中的声望值提高了%d点。",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "你的战团在%s中的声望值降低了%d点。",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s死亡，你获得%d点经验值。",
		ERR_ZONE_EXPLORED_XP = "发现%s：获得%d点经验值",
	},
	zhTW = {
		LOOT_ITEM_CREATED_SELF = "你製造了：%s。",
		LOOT_ITEM_CREATED_SELF_MULTIPLE = "你製造了：%sx%d。",
		ERR_AUCTION_SOLD_S = "你拍賣的%s已售出。",
		AUCTION_SOLD_MAIL_SUBJECT = "拍賣成功：%s",
		AUCTION_EXPIRED_MAIL_SUBJECT = "拍賣過期：%s",
		AUCTION_REMOVED_MAIL_SUBJECT = "拍賣取消：%s",
		AUCTION_WON_MAIL_SUBJECT = "競標成功：%s",
		AUCTION_OUTBID_MAIL_SUBJECT = "出價被超過：%s",
		FACTION_STANDING_INCREASED = "你在%s的聲望提高了%d點。",
		FACTION_STANDING_DECREASED = "你在%s的聲望降低了%d點。",
		FACTION_STANDING_INCREASED_ACCOUNT_WIDE = "你的戰隊在%s的聲望提高了%d點。",
		FACTION_STANDING_DECREASED_ACCOUNT_WIDE = "你的戰隊在%s的聲望降低了%d點。",
		COMBATLOG_XPGAIN_FIRSTPERSON = "%s死亡，你獲得%d點經驗值。",
		ERR_ZONE_EXPLORED_XP = "發現%s：獲得%d點經驗值",
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
local NOT_HERE = { koKR = { ERR_AUCTION_SOLD_S = true, COMBATLOG_XPGAIN_FIRSTPERSON = true } }
local LINK = "|cffffffff|Hitem:2996::::::::30|h[亚麻布卷]|h|r"
for code, F in pairs(CLIENTS) do
	-- Every English format has this client's one here, but the two Korean ones above.
	for _, name in ipairs(ENGLISH) do
		local want = (NOT_HERE[code] or {})[name] and "nil" or "string"
		eq(type(_G[name]) == "string" and type(F[name]), want, code .. ": a wording of " .. name)
	end

	-- A message as the game sends it, and what the addon's matcher reads from it.
	local function read(name, whole, ...)
		return table.concat({ E.matcher(F[name], whole)(string.format(F[name], ...)) }, "|")
	end
	eq(read("LOOT_ITEM_CREATED_SELF", false, LINK), LINK, code .. ": a craft")
	eq(read("LOOT_ITEM_CREATED_SELF_MULTIPLE", false, LINK, 2), LINK .. "|2", code .. ": a craft of two")
	if F.ERR_AUCTION_SOLD_S then
		eq(read("ERR_AUCTION_SOLD_S", true, "毛料"), "毛料", code .. ": an auction sold")
	end
	eq(read("FACTION_STANDING_INCREASED", false, "暴风城", 250), "暴风城|250", code .. ": reputation up")
	eq(read("FACTION_STANDING_DECREASED", false, "暴风城", 50), "暴风城|50", code .. ": reputation down")
	eq(read("FACTION_STANDING_INCREASED_ACCOUNT_WIDE", false, "议会", 75), "议会|75", code .. ": warband reputation up")
	eq(read("FACTION_STANDING_DECREASED_ACCOUNT_WIDE", false, "议会", 75), "议会|75", code .. ": warband reputation down")
	if F.COMBATLOG_XPGAIN_FIRSTPERSON then
		eq(read("COMBATLOG_XPGAIN_FIRSTPERSON", false, "狗头人", 120), "狗头人|120", code .. ": a kill's XP")
	end
	eq(read("ERR_ZONE_EXPLORED_XP", false, "北郡：山谷", 55), "北郡：山谷|55", code .. ": a discovery, a colon in its name")
	eq(E.matcher(F.FACTION_STANDING_INCREASED)(string.format(F.FACTION_STANDING_DECREASED, "暴风城", 50)), nil, code .. ": a loss is no gain")

	-- The auction house's mail subjects, as MailHelper.lua tells them from a player's letter.
	local P = M.patterns({ F.AUCTION_SOLD_MAIL_SUBJECT, F.AUCTION_EXPIRED_MAIL_SUBJECT, F.AUCTION_REMOVED_MAIL_SUBJECT,
		F.AUCTION_WON_MAIL_SUBJECT, F.AUCTION_OUTBID_MAIL_SUBJECT })
	for _, name in ipairs({ "AUCTION_SOLD_MAIL_SUBJECT", "AUCTION_EXPIRED_MAIL_SUBJECT", "AUCTION_REMOVED_MAIL_SUBJECT",
		"AUCTION_WON_MAIL_SUBJECT", "AUCTION_OUTBID_MAIL_SUBJECT" }) do
		eq(M.isAuction(string.format(F[name], "铁矿石 (20)"), P), true, code .. ": " .. name)
	end
	eq(M.isAuction("RE: " .. string.format(F.AUCTION_SOLD_MAIL_SUBJECT, "lol"), P), false, code .. ": a player's reply is not")
end
return checks()
