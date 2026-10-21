-- Smoke test: loads the addon with a stubbed game API and plays a short session.
local dir = arg[1]
local now, money, clock = 1792517410, 79098, 100
local timers = {}
local frames = {}
function GetServerTime() return now end
function GetTime() return clock end
function date(f, t) return os.date(f, t) end
function print(...) io.write("[chat] ", table.concat({...}, " "), "\n") end
function hooksecurefunc(a, b, c)
  if type(a) == "string" then local orig = _G[a]; _G[a] = function(...) local r = orig(...); b(...); return r end
  else local orig = a[b]; a[b] = function(...) local r = orig(...); c(...); return r end end
end
function TakeTaxiNode(slot) end
tooltipHooks = {}
itemTooltipHooks, unitTooltipHooks = {}, {}
TooltipDataProcessor = { AllTypes = "ALL", AddTooltipPostCall = function(kind, fn)
  if kind == "ALL" then tooltipHooks[#tooltipHooks + 1] = fn elseif kind == 2 then unitTooltipHooks[#unitTooltipHooks + 1] = fn else itemTooltipHooks[#itemTooltipHooks + 1] = fn end end }
function GetStatisticsCategoryList() return { 130 } end
function GetCategoryList() return { 92 } end
function GetCategoryInfo(c) return c == 130 and "Character" or "General, misc" end
function GetCategoryNumAchievements(c) return 2 end
function GetAchievementInfo(c, i) local id = c * 100 + i; return id, c == 130 and ("Total gold acquired" .. i) or "Level 10", 10, i == 1, 10, 20, 26, "Reach level 10;\nnow", 0, 236, "", false end
function GetStatistic(id) return id == 13001 and "1|TInterface\\MoneyFrame\\UI-GoldIcon:0:0:2:0|t 5" or "--" end
function GetTotalAchievementPoints() return 10 end
C_MajorFactions = { GetMajorFactionData = function() return { renownLevel = 16, maxLevel = 90, renownReputationEarned = 300, renownLevelThreshold = 1000 } end,
  GetRenownLevels = function() return { { level = 15 }, { level = 25 } } end,
  GetRenownRewardsForLevel = function(_, l) if l == 15 then return { { itemID = 276236, toastDescription = "Replica Ironforge Air Rifle", description = "Join a shootout, with your rifle;|nVisit Wiley." } } end return {} end }
C_Traits = { GetConfigIDByTreeID = function(t) return (t == 1187 or t == 1190) and 597063 or nil end, GetTreeNodes = function(t) if t == 1190 then return { 201 } end return { 101, 102, 103 } end, GetConfigInfo = function() return { treeIDs = { 1187 } } end,
  GetNodeInfo = function(_, n) if n == 103 then return { ID = 0 } end if n == 201 then return { ID = 201, activeRank = 5, maxRanks = 5, activeEntry = { entryID = 2010, rank = 5 } } end return { ID = n, activeRank = 0, ranksPurchased = n == 101 and 5 or 0, maxRanks = 5, activeEntry = { entryID = n * 10 } } end,
  GetEntryInfo = function(_, e) return { definitionID = e + 1 } end,
  GetDefinitionInfo = function(d) return { spellID = d * 2, overrideName = d == 1011 and "Bountiful Harvest" or nil } end,
  GetTreeCurrencyInfo = function() return { { traitCurrencyID = 4225, quantity = 0, spent = 16, maxQuantity = 16 } } end,
  GetMaxAvailableTraitCurrency = function() return 81 end }
C_Spell = { GetSpellName = function(id) return "Spell " .. id end, GetSpellDescription = function(id) return "Gather, more.\nFaster." end }
C_FakePerks = { GetPerkRanks = function(tree) return { { id = "bountiful-harvest", rank = 5 }, { id = "working-overtime", rank = 3 } } end, Spend = function() end }
C_Background = { GetThing = function() return 1 end }
function ToggleLegacySystemUI() C_Background.GetThing() C_FakePerks.GetPerkRanks(7) C_FakePerks.Spend() end
C_GameRules = { GetActiveGameMode = function() return 4 end, GetForeverExperiencePreset = function() return 2 end, IsHardcoreActive = function() return false end, IsGameRuleActive = function(id) return id == 1 end, GetGameRuleAsFloat = function() return 1.5 end }
function GetTaxiMapID() return 1415 end
C_TaxiMap = { GetAllTaxiNodes = function() return { { nodeID = 2, name = "Stormwind, Elwynn", slotIndex = 1, state = 0 }, { nodeID = 4, name = "Lakeshire, Redridge", slotIndex = 2, state = 1 } } end }
function TaxiNodeGetType(i) return i == 1 and "CURRENT" or "REACHABLE" end
function NumTaxiNodes() return 2 end
function TaxiNodeName(i) return "n" .. i end
function TaxiNodeCost(i) return 50 end
tailoring = 75
-- Any widget method not stubbed here is a no-op returning another such widget.
-- Sizes come back as numbers and text as strings, so the UI kit's layout arithmetic runs.
local NUMBERS = { GetWidth = 400, GetHeight = 300, GetStringWidth = 60, GetVerticalScroll = 0, GetEffectiveScale = 1, GetScale = 1 }
local function widget(t)
  return setmetatable(t or {}, { __index = function(_, k)
    if NUMBERS[k] then return function() return NUMBERS[k] end end
    if k == "GetText" then return function() return "" end end
    -- Only methods (capitalised, as the client's are); a missing field is nil, as on a real frame.
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    return function() return widget() end
  end })
end
function GetPhysicalScreenSize() return 2560, 1440 end
UISpecialFrames = {}
function CreateFrame() local f = widget({ events = {}, shown = false })
  function f:RegisterEvent(e) if e == "COMBAT_LOG_EVENT_UNFILTERED" then error("ADDON_ACTION_FORBIDDEN: " .. e) end if e:find("^UNKNOWN") then error("unknown event") end self.events[e] = true end
  function f:SetScript(name, fn) if name == "OnEvent" then self.handler = fn end end
  function f:Show() self.shown = true end
  function f:Hide() self.shown = false end
  function f:IsShown() return self.shown end
  function f:CreateFontString() local fs = widget({}); function fs:SetText(t) self.text = t; appraiserText = t end; function fs:GetStringHeight() return 80 end; return fs end
  frames[#frames+1] = f; return f end
UIParent = widget()
function strsplit(sep, s) local out = {} for part in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out + 1] = part end return unpack(out) end
GameTooltip = widget({ lines = {} }); function GameTooltip:AddLine(t) table.insert(self.lines, t) end
C_Timer = { After = function(s, fn) timers[#timers+1] = { at = clock + s, fn = fn, n = #timers } end, NewTicker = function(s, fn) ticker = fn end }
local function runTimers(upto) local i = 0 while #timers > 0 and i < 5000 do table.sort(timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.n < b.n end); if timers[1].at > (upto or clock + 2) then break end local t = table.remove(timers, 1); if t.at > clock then clock = t.at end t.fn(); i = i + 1 end end
function fire(e, ...) for _, f in ipairs(frames) do if f.events[e] then f.handler(f, e, ...) end end runTimers() end
-- An event without running the timers due, for orderings within a second.
function fireNow(e, ...) for _, f in ipairs(frames) do if f.events[e] then f.handler(f, e, ...) end end end
function wait(s) runTimers(clock + s) clock = clock + s end
function GetBuildInfo() return "1.60.1", "70450", "", 16001 end
function GetLocale() return "enUS" end
function GetCurrentRegionName() return "" end
function GetCurrentRegion() return 3 end
function GetCVar() return "test" end
function UnitRace() return "Human", "Human" end
function UnitClass() return "Priest", "PRIEST" end
function UnitName() return "Testchar", "Testguild" end
function UnitLevel(u) return u == "player" and 30 or (u == "npc" and 25 or 12) end
function GetRealmName() return "Classic Beta PvE 2" end
function GetGuildInfo() return "Vault" end
function GetMoney() return money end
function UnitExists(u) return u == "npc" or u == "target" end
function UnitIsPlayer(u) return false end
function UnitIsDead(u) return false end
function UnitClassification() return "normal" end
function UnitCreatureType() return "Humanoid" end
C_TooltipInfo = { GetItemByID = function(id) return { lines = { { leftText = "Item " .. id }, { leftText = "Binds when picked up" }, { leftText = "Two-Hand", rightText = "Staff" } } } end }
C_CurrencyInfo = { GetCurrencyListSize = function() return 2 end, GetCurrencyListInfo = function(i) if i == 1 then return { isHeader = true, name = "Misc" } end return { name = "Favor, of the Forever", quantity = 12 } end,
  GetCurrencyListLink = function(i) return i == 2 and "|Hcurrency:3001|h[Favor]|h" or nil end }
C_Reputation = { GetNumFactions = function() return 2 end, GetFactionDataByIndex = function(i) if i == 1 then return { isHeader = true, factionID = 0, name = "Alliance" } end return { factionID = 72, name = "Stormwind", reaction = 5, currentStanding = 3200 } end }
function GetInventoryItemLink(_, slot) return slot == 16 and "|Hitem:249392::::::::30|h[Glimmering Staff]|h" or nil end
function GetNumTrainerServices() return 2 end
function GetTrainerServiceInfo(i) return ({ "Bolt of Linen Cloth", "Heavy Linen Gloves" })[i], "", ({ "used", "available" })[i] end
function GetTrainerServiceCost(i) return 50 * i end
function GetTrainerServiceSkillReq(i) return "Tailoring", 35 * i, true end
function GetTrainerServiceLevelReq() return 0 end
filters = { available = true, unavailable = false, used = false }
function GetTrainerServiceTypeFilter(f) return filters[f] end
function SetTrainerServiceTypeFilter(f, on) filters[f] = on end
function UnitGUID(u) if u == "npc" then return "Creature-0-4620-0-12-8661-000A" end return "Player-4620-006C0FC1" end
function UnitFactionGroup(u) if u == "npc" then return nil end return "Alliance" end
function GetMaxPlayerLevel() return 60 end
xpmax = 47400
function UnitXP() return xpcur or 2570 end function UnitXPMax() return xpmax end
function GetXPExhaustion() return nil end
function IsResting() return false end
function IsFlying() return false end
function UnitOnTaxi() return false end
function UnitIsDeadOrGhost() return false end
function GetZoneText() return "Elwynn Forest" end
function GetSubZoneText() return "" end
C_Map = { GetBestMapForUnit = function() return 1429 end,
  GetPlayerMapPosition = function() return { GetXY = function() return 0.4123, 0.6789 end } end,
  GetMapArtLayers = function(m) if m == 1411 or m == 1429 then return { { layerWidth = 1002, layerHeight = 668, tileWidth = 256, tileHeight = 256 } } end return {} end,
  GetMapArtLayerTextures = function(m) return { 768730, 768731, 768732, 768733 } end,
  GetMapRectOnMap = function(m, c) return 0.4, 0.6, 0.3, 0.5 end,
  GetMapInfo = function(m) return m == 1429 and { name = "Elwynn Forest", mapType = 3, parentMapID = 1415 } or { name = "Eastern Kingdoms", mapType = 2, parentMapID = 0 } end }
Enum = { TooltipDataType = { Item = 0, Unit = 2 }, GameRule = { XpRate = 1, NoTrade = 2 }, LootSlotType = { None = 0, Item = 1, Money = 2 }, BagIndex = { Backpack = 0, Bag_1 = 1, Bag_2 = 2, Bag_3 = 3, Bag_4 = 4, Bank = -1, BankBag_1 = 6 } }
bagFree = 10
C_Container = { GetContainerNumFreeSlots = function(bag) if bag == 0 then return bagFree, 0 end return 0, 0 end, GetContainerNumSlots = function(b) return b == 0 and (bagsFull and 3 or 2) or 0 end,
  GetContainerItemInfo = function(b, s)
    if b ~= 0 then return nil end
    if s == 1 then return { itemID = 2589, stackCount = 7, hyperlink = "|Hitem:2589::::::::30|h[Linen]|h" } end
    if s == 2 and bagsFull then return { itemID = 251962, stackCount = 1, hyperlink = "|Hitem:251962::::::::30|h[Violet Sash]|h" } end
    if s == 3 and bagsFull then return { itemID = 271206, stackCount = 1, isBound = true, hyperlink = "|Hitem:271206::::::::30|h[Skin]|h" } end
  end,
  GetContainerItemID = function() return 2589 end }
C_Item = { GetItemInfo = function(id) return "Item, " .. id, nil, 1, 10, 1, "", "", 20, "", 132889, 13, 7, 5, 0 end }
C_TradeSkillUI = { GetAllRecipeIDs = function() return { 2963, 3915 } end, GetRecipeInfo = function(id) return { learned = id == 2963, name = "Bolt of Linen" } end,
  GetBaseProfessionInfo = function() return { professionID = 197, professionName = "Tailoring", skillLevel = 75, maxSkillLevel = 150 } end,
  GetRecipeSchematic = function() return { outputItemID = 2996, quantityMin = 1, quantityMax = 1, reagentSlotSchematics = { { reagentType = 1, quantityRequired = 2, reagents = { { itemID = 2589 } } } } } end }
function GetProfessions() return 1, 2, nil, 4, nil end
function GetProfessionInfo(i) if i == 2 then return "Enchanting", 0, 101, 150, 0, 0, 333 end return i == 1 and "Tailoring" or "Fishing", 0, i == 1 and tailoring or 75, 150, 0, 0, i == 1 and 197 or 356 end
local slots = {
  { kind = 2, sources = { "Creature-0-4620-0-12-299-000A", 30, "Creature-0-4620-0-12-299-000B", 70 } },
  { kind = 1, link = "|Hitem:2589::::::::30|h[Linen Cloth]|h", qty = 2, sources = { "Creature-0-4620-0-12-299-000A", 2 } },
  { kind = 1, link = "|Hitem:10221::::::612::30|h[Gloves]|h", qty = 1, sources = { "Creature-0-4620-0-12-299-000B", 1 } },
}
function GetNumLootItems() return #slots end
function GetLootSlotType(s) return slots[s].kind end
function GetLootSlotInfo(s) return nil, nil, slots[s].qty or 0, nil, 1, false, slots[s].quest ~= nil, slots[s].quest, false end
function GetLootSlotLink(s) return slots[s].link end
function GetLootSourceInfo(s) return unpack(slots[s].sources) end
function IsFishingLoot() return fishing end
function GetMerchantNumItems() return 1 end
function GetMerchantItemID() return 159 end
function GetMerchantItemInfo() return "Water", 0, 25, 5, -1, true, true, false end
C_AuctionHouse = { PostItem = function() end, PostCommodity = function() end, ConfirmPostCommodity = function() end, ReplicateItems = function() end, GetNumReplicateItems = function() return 3 end,
  GetReplicateItemInfo = function(i) local c = ({5, 10, 1})[i+1]; return "x", 0, c, 1, true, 1, 0, 1, 1, ({500, 1000, 9000})[i+1], 0, false, "Bidder", "Owner", "Owner-Realm", 0, ({2589, 2589, 14047})[i+1], true end,
  GetReplicateItemLink = function() return nil end }
function GetNumSkillLines() return 0 end
function GetSkillLineInfo() end

function GetInstanceInfo() if inDungeon then return "Ragefire Chasm", "party", 1, "Normal", 5, 0, false, 389 end return "Kalimdor", "none", 0, "", 0, 0, false, 1 end
function UnitAffectingCombat() return fighting or false end
function IsInInstance() return inDungeon or false, inDungeon and "party" or "none" end
played = { 86400, 600 }
function RequestTimePlayed() C_Timer.After(0.2, function() fire("TIME_PLAYED_MSG", played[1], played[2]) end) end
function CombatLogGetCurrentEventInfo() return unpack(cleu) end
NUM_CHAT_WINDOWS = 1
ChatFrame1 = { registered = { TIME_PLAYED_MSG = true }, heard = 0 }
function ChatFrame1:IsEventRegistered(e) return self.registered[e] end
function ChatFrame1:UnregisterEvent(e) self.registered[e] = nil end
function ChatFrame1:RegisterEvent(e) self.registered[e] = true end
SlashCmdList = {}
-- The files the client loads, in its order: the TOC's own list.
function tocFiles()
  local out = {}
  for line in io.lines(dir .. "/GoldForever_Forever.toc") do
    if line:match("%.lua%s*$") then out[#out + 1] = line:match("^%s*(.-)%s*$") end
  end
  return out
end
local ns = {}
for _, f in ipairs(tocFiles()) do
  assert(loadfile(dir .. "/" .. f))("GoldForever", ns)
end
fire("ADDON_LOADED", "GoldForever")
fire("PLAYER_LOGIN")
fire("PLAYER_ENTERING_WORLD", true, false)
fire("LOOT_READY")
fire("LOOT_READY")
fire("LOOT_SLOT_CLEARED", 1)
money = money + 100; fire("PLAYER_MONEY")
fire("LOOT_SLOT_CLEARED", 2) fire("LOOT_SLOT_CLEARED", 3)
fire("LOOT_CLOSED")
now = now + 5; clock = clock + 5; ticker(); ticker()
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-9", 2366)
slots = { { kind = 1, link = "|Hitem:2447::::::::30|h[Peacebloom]|h", qty = 2, sources = { "GameObject-0-4620-0-12-1618-000C", 2 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
fire("TRAINER_SHOW")
for _, h in ipairs(tooltipHooks) do h(nil, { guid = "GameObject-0-4620-0-12-180682-000D", lines = { { leftText = "Oily Blackmouth School" } } }) end
fishing = true
slots = { { kind = 1, link = "|Hitem:6358::::::::30|h[Oily Blackmouth]|h", qty = 1, sources = { "GameObject-0-4620-0-12-180682-000D", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
fishing = false
-- A buff on oneself, then a bobber: the bobber is not named after the player.
fire("UNIT_SPELLCAST_SENT", "player", "Testchar", "Cast-8", 1243)
slots = { { kind = 1, link = "|Hitem:6358::::::::30|h[Oily Blackmouth]|h", qty = 1, sources = { "GameObject-0-4620-0-12-35591-000E", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
print("BOBBER NAMED " .. tostring(GoldForeverDB.catalogue.objects[35591]))
wait(30)
fire("TRADE_SKILL_SHOW")
fire("MERCHANT_SHOW")
-- The trainer was left without its close event; its frame is hidden, so the sale is the vendor's alone.
ClassTrainerFrame = { IsShown = function() return false end }
money = money + 37; fire("PLAYER_MONEY")
bolts = 0
C_Item.GetItemCount = function(id) return id == 2996 and bolts or 0 end
fire("UNIT_SPELLCAST_START", "player", "Cast-1", 2963)
bolts = 1
fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2963)
tailoring = 76; fire("SKILL_LINES_CHANGED")
-- "Create All": the second cast starts before the first's bolt is in the bags; the chat says what each made.
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
bolts = 1
fireNow("UNIT_SPELLCAST_START", "player", "Cast-2", 2963)
fireNow("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-2", 2963)
fireNow("UNIT_SPELLCAST_START", "player", "Cast-3", 2963)
bolts = 2
fireNow("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2996::::::::30|h[Bolt of Linen Cloth]|h|r.")
fireNow("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-3", 2963)
bolts = 4
fireNow("CHAT_MSG_LOOT", "You create: |cffffffff|Hitem:2996::::::::30|h[Bolt of Linen Cloth]|h|rx2.")
wait(3)
print("CRAFTS " .. tostring(GoldForeverDB.events["2026-10-20"].craft and GoldForeverDB.events["2026-10-20"].craft[1]))
Enum.FlightPathState = { Current = 0 }
TakeTaxiNode(2)
C_QuestLog = { GetTitleForQuestID = function() return "The Fargodeep Mine, part 2" end }
fire("QUEST_ACCEPTED", 62)
wait(10)
fire("QUEST_TURNED_IN", 62, 450, 75)
money = money + 75; fire("PLAYER_MONEY")
wait(10)
fire("AUCTION_HOUSE_SHOW")
fire("REPLICATE_ITEM_LIST_UPDATE")
wait(70)
SlashCmdList.GOLDFOREVER("scan")
C_Background.GetThing()
SlashCmdList.GOLDFOREVER("legacy")
C_Background.GetThing()
wait(60)
-- Appraiser: a scan of the character's market, then two loot windows.
table.insert(GoldForeverDB.scans, { t = 1792520000, kind = "full", market = "EU-Classic Beta PvE 2-alliance", rows = { "2589,40,100,10;2589,50,200,5;2934,500,3,1" } })
ns.scanVersion = (ns.scanVersion or 0) + 1
GoldForeverDB.catalogue.items[2589] = "Linen Cloth,1,5,7,5,20,13,0,132889"
GoldForeverDB.settings.appraiser = nil
appraiserCommands = true
SlashCmdList.GOLDFOREVER("reset")
xpcur = 2900; fire("PLAYER_XP_UPDATE")
slots = { { kind = 2, sources = { "Creature-0-4620-0-12-1922-000F", 50 } }, { kind = 1, link = "|Hitem:2589::::::::30|h[Linen]|h", qty = 3, sources = { "Creature-0-4620-0-12-1922-000F", 3 } } }
-- The coin reaches the purse before its slot reports cleared: it is still this window's.
fire("LOOT_READY") money = money + 50; fire("PLAYER_MONEY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_SLOT_CLEARED", 2) fire("LOOT_CLOSED")
clock = clock + 120
bagFree = 8; fire("BAG_UPDATE_DELAYED")
xpcur = 3300; fire("PLAYER_XP_UPDATE")
slots = { { kind = 1, link = "|Hitem:2934::::::::30|h[Light Leather]|h", qty = 2, sources = { "Creature-0-4620-0-12-1922-000G", 2 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
-- A blue drop: a big-drop alert.
raidNotices = {}
RaidWarningFrame = {}; function RaidNotice_AddMessage(_, text) table.insert(raidNotices, text) end
GoldForeverDB.catalogue.items[271206] = "Leftover Abomination Skin,3,20,4,1,1,687,1,132687,15,INVTYPE_CHEST"
GoldForeverDB.catalogue.tooltips[271206] = "Leftover Abomination Skin"
GoldForeverDB.catalogue.items[251962] = "Violet Sash,2,36,4,1,1,1585,1,132493,0,INVTYPE_WAIST"
GoldForeverDB.catalogue.items[11137] = "Vision Dust,1,40,7,12,20,1,0,132858"
table.insert(GoldForeverDB.scans, { t = 1792520100, kind = "full", market = "EU-Classic Beta PvE 2-alliance",
  rows = { "2589,40,100,10;2589,50,200,5;2934,500,3,1;11137,2850,40,8;11135,3851,10,2;11139,25743,2,2" } })
ns.scanVersion = (ns.scanVersion or 0) + 1
slots = { { kind = 1, link = "|Hitem:271206::::::::30|h[Skin]|h", qty = 1, sources = { "Creature-0-4620-0-12-1922-000H", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
print("BIG DROP " .. tostring(raidNotices[1]))
GameTooltip.lines = {}
for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 251962 }) end
print("SASH TOOLTIP " .. table.concat(GameTooltip.lines, " / "))
bagsFull = true
fire("MERCHANT_SHOW")
print("ADVISOR\n" .. tostring(appraiserText))
-- A rare on a nameplate: announced once, recorded, marked with a skull.
raidNotices = {}
marks = {}
function UnitClassification(u) return u == "nameplate3" and "rareelite" or "normal" end
function UnitIsDead() return false end
function IsInGroup() return false end
function GetRaidTargetIndex(u) return marks[u] end
function SetRaidTarget(u, i) marks[u] = i end
local unitGUID = UnitGUID
UnitGUID = function(u) if u == "nameplate3" then return "Creature-0-4620-0-12-947-0000ABC1" end return unitGUID(u) end
UnitExists = function(u) return u == "npc" or u == "target" or u == "nameplate3" end
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
print("RARE " .. tostring(raidNotices[1]) .. " | notices " .. #raidNotices .. " | skull " .. tostring(marks.nameplate3))
-- The craft list at the auction house: Bolt of Linen Cloth from 2 Linen, Bolts selling at 2s.
table.insert(GoldForeverDB.scans, { t = 1792520200, kind = "full", market = "EU-Classic Beta PvE 2-alliance",
  rows = { "2589,40,100,10;2589,50,200,5;2996,200,20,4;2934,500,3,1" } })
ns.scanVersion = (ns.scanVersion or 0) + 1
GoldForeverDB.catalogue.items[2996] = "Bolt of Linen Cloth,1,10,7,5,10,25,0,132890"
GoldForeverDB.catalogue.tooltips[2996] = "Bolt of Linen Cloth"
fire("AUCTION_HOUSE_SHOW")
print("SHOP\n" .. tostring(appraiserText))
-- A quest starter drops: recorded, alerted; the mob's tooltip names it.
GoldForeverDB.catalogue.items[1357] = "Captain Sander's Treasure Map,1,15,12,0,1,0,1,134269"
GoldForeverDB.catalogue.tooltips[1357] = "Captain Sander's Treasure Map\nThis Item Begins a Quest"
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
raidNotices = {}
slots = { { kind = 1, link = "|Hitem:1357::::::::30|h[Map]|h", qty = 1, quest = 136, sources = { "Creature-0-4620-0-12-1922-000Q", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
print("QUEST ALERT " .. tostring(raidNotices[1]) .. " | recorded quest " .. tostring(GoldForeverDB.catalogue.questStarters[1357]))
GameTooltip.lines = {}
for _, h in ipairs(unitTooltipHooks) do h(GameTooltip, { guid = "Creature-0-4620-0-12-1922-000F" }) end
print("MOB STARTER " .. tostring(GameTooltip.lines[3]))
-- Stop: the session ends and its clock stops.
SlashCmdList.GOLDFOREVER("reset")
-- Posting: a commodity and its confirmation are one post; an item's unit price is its buyout per item.
C_Item.GetItemLink = function() return "|Hitem:2592::::::::30|h[Wool Cloth]|h" end
C_Item.GetItemID = function() return 2592 end
C_AuctionHouse.PostCommodity({}, 2, 20, 95)
C_AuctionHouse.ConfirmPostCommodity({}, 2, 20, 95)
C_AuctionHouse.PostItem({}, 3, 2, 0, 3000)
C_AuctionHouse.PostItem({}, 3, 2, 0, 3000) -- a second alike auction, no confirmation: two posts
local day = GoldForeverDB.events["2026-10-20"]
print("POSTS " .. tostring(day.post and day.post[1]))
-- A sale mail, read twice: one sale row, no buyer.
function GetInboxNumItems() return 1 end
function GetInboxInvoiceInfo(i) return "seller", "Wool Cloth, bundle", "SomeBuyer", 0, 1900, 120, 95, 0, 0, 20, false end
function GetInboxHeaderInfo(i) return nil, nil, "Alliance Auction House", "Auction successful", 1925, 0, 29.95 end
fire("MAIL_INBOX_UPDATE") wait(2) fire("MAIL_INBOX_UPDATE") wait(2)
print("SALES " .. tostring(day.sale and day.sale[1]))
-- The same mail two minutes later (fewer days left): still one sale. Then two alike mails: two.
clock = clock + 120; now = now + 120
function GetInboxHeaderInfo(i) return nil, nil, "Alliance Auction House", "Auction successful", 1925, 0, 29.95 - 120 / 86400 end
fire("MAIL_INBOX_UPDATE") wait(2)
print("SALES AFTER DRIFT " .. tostring(day.sale and day.sale[1]))
function GetInboxNumItems() return 2 end
function GetInboxHeaderInfo(i) return nil, nil, "Alliance Auction House", "Auction successful", 1925, 0, i == 1 and (29.95 - 120 / 86400) or 29.999 end
fire("MAIL_INBOX_UPDATE") wait(2)
print("SALES AFTER SECOND MAIL " .. tostring(day.sale and day.sale[1]))
-- The mailbox as a snapshot: a returned stack and gold; no sender kept.
function GetInboxHeaderInfo(i) return nil, nil, "SomeBuyer", "Auction expired", i == 1 and 1925 or 0, 0, 29.5 + i, 1 end
function GetInboxItemLink(i, slot) return slot == 1 and "|Hitem:2592::::::::30|h[Wool Cloth]|h" or nil end
function GetInboxItem(i, slot) return "Wool Cloth", 2592, 0, 20, 1, true end
ATTACHMENTS_MAX_RECEIVE = 12
fire("MAIL_INBOX_UPDATE") wait(3)
do
  local m = GoldForeverDB.characters["Player-4620-006C0FC1"].mail
  print("MAIL " .. m.used .. " mails, " .. m.items .. ", " .. m.money .. "c, expires in " .. (m.expires - now) .. " s, sender kept: " .. tostring(m.sender ~= nil))
end
print("BUYER KEPT " .. tostring((table.concat(day.sale or {}, ";")):find("SomeBuyer") ~= nil))
print("RARE ROWS " .. tostring(GoldForeverDB.events["2026-10-20"] and GoldForeverDB.events["2026-10-20"].rare and GoldForeverDB.events["2026-10-20"].rare[1]))
print("APPRAISER\n" .. tostring(appraiserText))
for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 2589 }) end
print("TOOLTIP " .. tostring(GameTooltip.lines[1]))
GameTooltip.lines = {}
for _, h in ipairs(unitTooltipHooks) do h(GameTooltip, { guid = "Creature-0-4620-0-12-1922-000F" }) end
print("MOB " .. tostring(GameTooltip.lines[1]) .. " | " .. tostring(GameTooltip.lines[2]))
-- One more loot of that mob after its tooltip was built: counted in place, not by reading every row.
slots = { { kind = 2, sources = { "Creature-0-4620-0-12-1922-000J", 40 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) money = money + 40; fire("PLAYER_MONEY") fire("LOOT_CLOSED")
GameTooltip.lines = {}
for _, h in ipairs(unitTooltipHooks) do h(GameTooltip, { guid = "Creature-0-4620-0-12-1922-000F" }) end
print("MOB AFTER LOOT " .. tostring(GameTooltip.lines[1]))
-- Two corpses looted back to back: the first window's coin arrives after the second opened.
local coinDay = GoldForeverDB.events["2026-10-20"]
local before = #(table.concat(coinDay.loot, ";"))
slots = { { kind = 2, sources = { "Creature-0-4620-0-12-299-00C1", 30 } } }
fireNow("LOOT_READY") fireNow("LOOT_SLOT_CLEARED", 1) fireNow("LOOT_CLOSED")
slots = { { kind = 2, sources = { "Creature-0-4620-0-12-299-00C2", 20 } } }
fireNow("LOOT_READY")
money = money + 30; fireNow("PLAYER_MONEY")
fireNow("LOOT_SLOT_CLEARED", 1) fireNow("LOOT_CLOSED")
money = money + 20; fireNow("PLAYER_MONEY")
wait(3)
print("BACK TO BACK " .. string.sub(table.concat(coinDay.loot, ";"), before + 1))

-- A class trainer: spells by level, no profession skill. Tagged with the visitor's class; at the
-- level-up below, what is new there comes up in chat.
do
  local saved = { GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceLevelReq, GetTrainerServiceCost }
  GetNumTrainerServices = function() return 3 end
  GetTrainerServiceInfo = function(i) return ({ "Smite", "Renew", "Smite" })[i], "unavailable", 135924 end
  GetTrainerServiceSkillReq = function() return nil end
  GetTrainerServiceLevelReq = function(i) return ({ 31, 31, 24 })[i] end
  GetTrainerServiceCost = function(i) return ({ 5000, 4000, 3000 })[i] end
  fire("TRAINER_SHOW") wait(2)
  GetNumTrainerServices, GetTrainerServiceInfo, GetTrainerServiceSkillReq, GetTrainerServiceLevelReq, GetTrainerServiceCost = unpack(saved)
  print("TRAINER CLASS " .. tostring(GoldForeverDB.catalogue.trainerClasses and GoldForeverDB.catalogue.trainerClasses[8661]))
end

-- A faction and a currency under closed headers keep what was read before; what shows is updated.
do
  local me = GoldForeverDB.characters["Player-4620-006C0FC1"]
  me.reputation = { factions = "69:6:1000+72:5:100" }
  me.currencies = { items = "3002*5+3001*1" }
  fire("UPDATE_FACTION") fire("CURRENCY_DISPLAY_UPDATE") wait(12)
  print("REPUTATION " .. me.reputation.factions .. " | CURRENCIES " .. me.currencies.items)
end

-- Levelling: a group kill in a dungeon with rested XP, a quest whose event follows its XP, a level-up.
local lday = GoldForeverDB.events["2026-10-20"]
print("LOGIN LEVEL " .. tostring(lday.level and lday.level[1]) .. " | chat listens " .. tostring(ChatFrame1.registered.TIME_PLAYED_MSG))
inDungeon = true
GetXPExhaustion = function() return 1000 end; fire("UPDATE_EXHAUSTION")

fighting = true
GetXPExhaustion = function() return 900 end
xpcur = 3600; fire("PLAYER_XP_UPDATE")
fighting = false
-- A boss in the dungeon: its kill's XP is boss XP; a wipe is a boss row too.
fire("ZONE_CHANGED_NEW_AREA")
wait(10)
fire("ENCOUNTER_END", 1443, "Taragaman the Hungerer", 1, 5, 0)
wait(10)
fire("ENCOUNTER_END", 1443, "Taragaman the Hungerer", 1, 5, 1)
-- The rested pool's fall reported before the XP itself: still rested XP spent.
GetXPExhaustion = function() return 800 end; fire("UPDATE_EXHAUSTION")
xpcur = 3700; fire("PLAYER_XP_UPDATE")
wait(10)
inDungeon = false
wait(10)
xpcur = 4200; fire("PLAYER_XP_UPDATE")
wait(1)
fire("QUEST_TURNED_IN", 63, 600, 0)
wait(10)
-- A place discovered, no zone change: the game's message says it is exploration XP.
fire("UI_INFO_MESSAGE", 0, "Discovered Razor Hill: 55 experience gained")
xpcur = 4255; fire("PLAYER_XP_UPDATE") wait(10)
xpcur = 47000; fire("PLAYER_XP_UPDATE") wait(10)
xpcur = 300; xpmax = 49000; played = { 90000, 0 }
fire("PLAYER_REGEN_ENABLED")
fire("PLAYER_XP_UPDATE") fire("PLAYER_LEVEL_UP", 31)
wait(15)
print("MAP RECT " .. tostring(GoldForeverDB.mapArt and GoldForeverDB.mapArt.rects[1429]))
print("MAP ART " .. tostring(GoldForeverDB.mapArt and GoldForeverDB.mapArt.maps[1411]) .. " | maps " .. tostring(GoldForeverDB.mapArt and GoldForeverDB.mapArt.build))
print("XP ROWS " .. tostring(lday.xp and lday.xp[1]))
print("LEVEL ROWS " .. tostring(lday.level and lday.level[1]) .. " | chat listens " .. tostring(ChatFrame1.registered.TIME_PLAYED_MSG))
print("ZONE ROWS " .. tostring(lday.zone and lday.zone[1]))
print("BOSS ROWS " .. tostring(lday.boss and lday.boss[1]) .. " | instance " .. tostring(GoldForeverDB.catalogue.instances and GoldForeverDB.catalogue.instances[389]))
-- Scans from three days, several a day: the newest two and one from each earlier day stay.
for _, t in ipairs({ 1792300000, 1792300900, 1792390000, 1792390900 }) do
  table.insert(GoldForeverDB.scans, 1, { t = t, kind = "full", market = "EU-Classic Beta PvE 2-alliance", rows = {} })
end
-- The in-game window: every page builds and fills from the saved file.
SlashCmdList.GOLDFOREVER("ui")
SlashCmdList.GOLDFOREVER("ui mobs")
SlashCmdList.GOLDFOREVER("ui inventory")
SlashCmdList.GOLDFOREVER("ui design")
SlashCmdList.GOLDFOREVER("ui characters")
SlashCmdList.GOLDFOREVER("ui levelling")
SlashCmdList.GOLDFOREVER("ui ledger")
print("UI WINDOW " .. tostring(GoldForeverDB.settings.window and GoldForeverDB.settings.window.page))
do
  local V, db = ns.Views, GoldForeverDB
  local rows, best = V.characters(db.characters, GetServerTime(), UnitGUID("player"))
  print("UI CHARACTERS " .. #rows .. " best " .. tostring(best and best.name))
  local led = V.ledger(V.rows(db, "money"), V.rows(db, "flight"), nil, 0)
  local cats = {}
  for _, c in ipairs(led.categories) do cats[#cats + 1] = c.key .. "=" .. c.net end
  print("UI LEDGER " .. table.concat(cats, " ") .. " net " .. led.net)
  local lv = V.levelling(V.rows(db, "level"), V.rows(db, "xp"), ns.me().ref)
  print("UI LEVELLING levels " .. #lv.levels .. " xp " .. lv.xp .. " perHour " .. tostring(lv.perHour))
end

-- A /reload: the file is written, the addon loads again from scratch with the same saved table.
local before = appraiserText
fire("PLAYER_LOGOUT")
for k in pairs(frames) do frames[k] = nil end
local ns2 = {}
for _, f in ipairs(tocFiles()) do
  assert(loadfile(dir .. "/" .. f))("GoldForever", ns2)
end
clock = clock + 5; now = now + 5
fire("ADDON_LOADED", "GoldForever") fire("PLAYER_LOGIN") fire("PLAYER_ENTERING_WORLD", false, true)
print("AFTER RELOAD\n" .. tostring(appraiserText))
do
  local kinds = {}
  for _, sc in ipairs(GoldForeverDB.scans) do kinds[#kinds + 1] = sc.kind .. "@" .. tostring(sc.t) end
  print("SCANS KEPT " .. table.concat(kinds, " "))
end
print("SAME TOTALS " .. tostring((before:match("Total: [^|]*")) == (appraiserText:match("Total: [^|]*"))))
SlashCmdList.GOLDFOREVER("")
money = 0; xpmax = 0; C_Container.GetContainerNumSlots = function() return 0 end
fire("PLAYER_LEAVING_WORLD")
fire("PLAYER_LOGOUT")
local function dump(v, indent)
  indent = indent or ""
  if type(v) ~= "table" then return type(v) == "string" and string.format("%q", v) or tostring(v) end
  local keys = {} for k in pairs(v) do keys[#keys+1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local out = {}
  for _, k in ipairs(keys) do out[#out+1] = indent .. "  [" .. (type(k) == "string" and string.format("%q", k) or k) .. "] = " .. dump(v[k], indent .. "  ") end
  return "{\n" .. table.concat(out, ",\n") .. "\n" .. indent .. "}"
end
print("GoldForeverDB = " .. dump(GoldForeverDB))
