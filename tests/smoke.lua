-- Smoke test: loads the addon with a stubbed game API and plays a short session.
local dir = arg[1]
local now, money, clock = 1792517410, 79098, 100
local timers = {}
local frames = {}
function GetServerTime() return now end
function GetTime() return clock end
-- The client's profiling timer (milliseconds), which work spread over frames budgets against.
function debugprofilestop() return os.clock() * 1000 end
function date(f, t) return os.date(f, t) end
function print(...) io.write("[chat] ", table.concat({...}, " "), "\n") end
function hooksecurefunc(a, b, c)
  if type(a) == "string" then local orig = _G[a]; _G[a] = function(...) local r = orig(...); b(...); return r end
  else local orig = a[b]; a[b] = function(...) local r = orig(...); c(...); return r end end
end
-- The client's modified-click handler, which the addon hooks (alt-click chooses in Sell, shift-click adds
-- to a shopping list).
function HandleModifiedItemClick() end
ChatFrameUtil = { InsertLink = function() return false end }
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
local NUMBERS = { GetWidth = 400, GetHeight = 300, GetStringWidth = 60, GetVerticalScroll = 0, GetEffectiveScale = 1, GetScale = 1, GetFrameLevel = 1 }
-- The widget methods the client documents (tests/widget_methods.lua, generated from Blizzard's API docs),
-- for the client this run plays; a method the client lacks fails the run, as it would fail in game.
local METHODS = assert(loadfile((dir or "GoldForever") .. "/../tests/widget_methods.lua"))()
local FLAVOUR = (tonumber(os.getenv("GF_SMOKE_INTERFACE") or "") or 16001) >= 110000 and "retail" or "forever"
-- Methods Blizzard's own frames, templates and mixins add (not in the widget docs), which the addon calls,
-- and child frames it reads by key.
local MIXIN = { AddLine = true, SetOwner = true, SelectBrowseResult = true, GetRecipeInfo = true, GetBagAndSlot = true, AddDoubleLine = true,
  SetBackdrop = true, SetBackdropColor = true, SetBackdropBorderColor = true }
local CHILDREN = { CraftingPage = true, SchematicForm = true }
-- What a widget was given by SetText and SetHeight (or SetSize), kept beside it: the addon keeps child
-- frames under keys such as `text` itself.
local texts, heights = setmetatable({}, { __mode = "k" }), setmetatable({}, { __mode = "k" })
local function widget(t)
  return setmetatable(t or {}, { __index = function(_, k)
    if NUMBERS[k] then return function() return NUMBERS[k] end end
    if k == "GetText" then return function(self) return texts[self] or "" end end
    if k == "SetText" and METHODS[FLAVOUR][k] then
      return function(self, text) texts[self] = type(text) == "number" and tostring(text) or text end
    end
    if k == "SetHeight" and METHODS[FLAVOUR][k] then return function(self, h) heights[self] = h end end
    if k == "SetSize" and METHODS[FLAVOUR][k] then return function(self, _, h) heights[self] = h end end
    -- Only methods (capitalised, as the client's are); a missing field is nil, as on a real frame.
    if type(k) ~= "string" or not k:match("^%u") then return nil end
    if CHILDREN[k] then return widget() end
    -- Anything else the client does not have is nil, as on a real frame: calling it fails as in game.
    if not METHODS[FLAVOUR][k] and not MIXIN[k] then return nil end
    return function() return widget() end
  end })
end
-- The stand-in refuses what the client lacks: a misspelt method is nil, a documented one works.
assert(widget().SetPointt == nil and type(widget().SetPoint) == "function", "the stand-in knows the client's methods")
do
  local w = widget()
  w:SetText("Linen")
  assert(w:GetText() == "Linen" and widget():GetText() == "", "GetText gives back what SetText was given")
end
function GetPhysicalScreenSize() return 2560, 1440 end
UISpecialFrames = {}
BackdropTemplateMixin = {}
function CreateColor(r, g, b, a) return { r = r, g = g, b = b, a = a } end
-- Frames as the client's: shown when made, visible when their parents are, and OnShow/OnHide (with
-- hooks) run on a frame and its shown children when what is visible changes.
local function visible(f)
  while f do
    if f.shown == false then return false end
    f = f.parent
  end
  return true
end
local function run(f, script)
  local fn = f.scripts[script]
  if fn then fn(f) end
  for _, c in ipairs(f.children) do
    if c.shown then run(c, script) end
  end
end
function CreateFrame(_, _, parent) local f = widget({ events = {}, shown = true, scripts = {}, children = {} })
  if type(parent) == "table" and parent.children then f.parent = parent; table.insert(parent.children, f) end
  function f:RegisterEvent(e) if e == "COMBAT_LOG_EVENT_UNFILTERED" then error("ADDON_ACTION_FORBIDDEN: " .. e) end if e:find("^UNKNOWN") then error("unknown event") end self.events[e] = true end
  -- One unit's event only: the client passes the unit first, and calls the frame for no other.
  function f:RegisterUnitEvent(e, ...) self:RegisterEvent(e) self.units = self.units or {} self.units[e] = {} for _, u in ipairs({...}) do self.units[e][u] = true end end
  function f:SetScript(name, fn) if name == "OnEvent" then self.handler = fn else self.scripts[name] = fn end end
  function f:GetScript(name) return self.scripts[name] end
  function f:HookScript(name, fn) local old = self.scripts[name]; self.scripts[name] = function(...) if old then old(...) end fn(...) end end
  function f:Show() if self.shown then return end local was = visible(self) self.shown = true if not was and visible(self) then run(self, "OnShow") end end
  function f:Hide() if not self.shown then return end local was = visible(self) self.shown = false if was then run(self, "OnHide") end end
  function f:SetShown(on) if on then self:Show() else self:Hide() end end
  function f:IsShown() return self.shown end
  function f:IsVisible() return visible(self) end
  function f:CreateFontString() local fs = widget({}); function fs:SetText(t) self.text = t; texts[self] = t; appraiserText = t end; function fs:GetStringHeight() return 80 end; return fs end
  frames[#frames+1] = f; return f end
UIParent = widget()
Minimap = widget()
function GetCursorPosition() return 0, 0 end
function strsplit(sep, s) local out = {} for part in (s .. sep):gmatch("([^" .. sep .. "]*)" .. sep) do out[#out + 1] = part end return unpack(out) end
GameTooltip = widget({ lines = {}, shades = {} }); function GameTooltip:AddLine(t, r) table.insert(self.lines, t); self.shades[t] = r end
-- Tickers run only when the session says so (tick), each its own handle.
C_Timer = { After = function(s, fn) timers[#timers+1] = { at = clock + s, fn = fn, n = #timers } end,
  NewTicker = function(s, fn) local t = { every = s, fn = fn, Cancel = function(self) self.cancelled = true end }; liveTickers[#liveTickers + 1] = t; return t end }
liveTickers = {}
-- Tickers of `every` seconds still running.
function running(every) local n = 0 for _, t in ipairs(liveTickers) do if t.every == every and not t.cancelled then n = n + 1 end end return n end
-- One beat of every ticker of `every` seconds still running; there must be one.
function tick(every)
  local beat = {}
  for _, t in ipairs(liveTickers) do if t.every == every and not t.cancelled then beat[#beat + 1] = t end end
  assert(#beat > 0, "no ticker of " .. every .. " s is running")
  for _, t in ipairs(beat) do if not t.cancelled then t.fn(t) end end
end
-- The timers due by `upto`; a chain that never ends (more than 5,000 in one go) fails the run.
local function runTimers(upto) local i = 0 while #timers > 0 do table.sort(timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.n < b.n end); if timers[1].at > (upto or clock + 2) then break end assert(i < 5000, "more than 5,000 timers in one go"); local t = table.remove(timers, 1); if t.at > clock then clock = t.at end t.fn(); i = i + 1 end end
local function hears(f, e, unit) return f.events[e] and not (f.units and f.units[e] and not f.units[e][unit]) end
function fire(e, ...) for _, f in ipairs(frames) do if hears(f, e, ...) then f.handler(f, e, ...) end end runTimers() end
-- An event without running the timers due, for orderings within a second.
function fireNow(e, ...) for _, f in ipairs(frames) do if hears(f, e, ...) then f.handler(f, e, ...) end end end
function wait(s) runTimers(clock + s) clock = clock + s end
-- GF_SMOKE_INTERFACE=120105 plays the same session on a retail client.
local INTERFACE = tonumber(os.getenv("GF_SMOKE_INTERFACE") or "") or 16001
function GetBuildInfo() return "1.60.1", "70450", "", INTERFACE end
function GetNormalizedRealmName() return "ClassicBetaPvE2" end
C_AutoComplete = { GetAutoCompleteRealms = function() return { "ClassicBetaPvE2", "AnotherRealm" } end }
function GetLocale() return "enUS" end
function GetCurrentRegionName() return "" end
function GetCurrentRegion() return 3 end
function GetCVar() return "test" end
-- GF_SMOKE_FACTION=Horde plays the session as a Horde character (an Orc) instead of an Alliance Human.
SIDE = os.getenv("GF_SMOKE_FACTION") == "Horde" and "Horde" or "Alliance"
local side, otherSide = string.lower(SIDE), SIDE == "Horde" and "alliance" or "horde"
function UnitRace() if SIDE == "Horde" then return "Orc", "Orc" end return "Human", "Human" end
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
function UnitFactionGroup(u) if u == "npc" then return nil end return SIDE end
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
-- Retail's interaction manager names its windows as well as the older events do.
if INTERFACE >= 110000 then Enum.PlayerInteractionType = { TradePartner = 1, Merchant = 5, TaxiNode = 6, Trainer = 7, MailInfo = 17, Auctioneer = 21 } end
bagFree = 10
C_Container = { GetContainerNumFreeSlots = function(bag) if bag == 0 then return bagFree, 0 end return 0, 0 end, GetContainerNumSlots = function(b) return b == 0 and (bagsFull and 3 or 2) or 0 end,
  GetContainerItemInfo = function(b, s)
    if b ~= 0 then return nil end
    if s == 1 then return { itemID = 2589, stackCount = 7, hyperlink = "|Hitem:2589::::::::30|h[Linen]|h" } end
    if s == 2 and bagsFull then return { itemID = 251962, stackCount = 1, hyperlink = "|Hitem:251962::::::::30|h[Violet Sash]|h" } end
    if s == 3 and bagsFull then return { itemID = 271206, stackCount = 1, isBound = true, hyperlink = "|Hitem:271206::::::::30|h[Skin]|h" } end
  end,
  GetContainerItemID = function() return 2589 end }
C_Item = { GetItemInfo = function(id) return "Item, " .. id, nil, 1, 10, 1, "", "", 20, "", 132889, 13, 7, 5, 0 end,
  GetItemInfoInstant = function(id) return id, "Tradeskill", "Cloth", "", 132889, 7, 5 end,
  GetItemMaxStackSizeByID = function(id) return id == 2589 and 1000 or nil end }
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
-- The files the client loads, in its order: the list in the TOC this client reads.
function tocFiles()
  local out = {}
  for line in io.lines(dir .. (FLAVOUR == "retail" and "/GoldForever_Mainline.toc" or "/GoldForever_Forever.toc")) do
    -- The TOC's paths use the client's backslash.
    if line:match("%.lua%s*$") then out[#out + 1] = (line:match("^%s*(.-)%s*$"):gsub("\\", "/")) end
  end
  return out
end
local ns = {}
-- An observation the run prints, pinned: its value on WoW: Forever, and on retail where that differs.
local function seen(label, value, forever, retail)
  value = tostring(value)
  print(label .. value)
  local want = FLAVOUR == "retail" and retail or forever
  if value ~= want then error(label:gsub("%s+$", "") .. ": expected [" .. tostring(want) .. "], got [" .. value .. "]", 2) end
end
-- GF_SMOKE_SAVE=<a copy of a SavedVariables file>: the addon on a real save instead of the session
-- below, as that save's character, through every page, tab, look and panel, timed (tests/realsave.md).
local SAVE = os.getenv("GF_SMOKE_SAVE")
if SAVE then
  dofile(SAVE)
  local guid = os.getenv("GF_SMOKE_GUID")
  if not guid then for g in pairs(GoldForeverDB.characters or {}) do guid = guid or g end end
  local me = GoldForeverDB.characters[guid] or {}
  local realm = me.realm or "Shadowsong"
  UnitGUID = function(u) if u == "npc" then return "Creature-0-4620-0-12-8661-000A" end return guid end
  UnitName = function() return me.name or "Saved", nil end
  UnitFactionGroup = function(u) if u == "npc" then return nil end return me.faction or "Horde" end
  GetNormalizedRealmName = function() return (realm:gsub("[%s%-]", "")) end
  -- The realm's connected realms as the client lists them (GF_SMOKE_CONNECTED="Aszune,Shadowsong"),
  -- else the realm alone: on retail they name the market.
  local connected = {}
  for name in (os.getenv("GF_SMOKE_CONNECTED") or realm):gmatch("[^,]+") do connected[#connected + 1] = name end
  C_AutoComplete = { GetAutoCompleteRealms = function() return connected end }
  GetRealmName = function() return realm end
  now = math.max(now, GoldForeverDB.writtenAt or now)
  -- GF_SMOKE_PRICES=<a copy of the companion's Data.lua>: the shared prices the game has, as the pool
  -- every value comes from first.
  if os.getenv("GF_SMOKE_PRICES") then
    dofile(os.getenv("GF_SMOKE_PRICES"))
  end
end
-- Every UI.Table has its height when it is made: what is anchored below one is placed only then (manual
-- test run 001: the craft queue's buttons, Remove, Edit lists and the Sell box came up blank).
tablesMade = 0
local function tablesHaveHeights(ns)
  local make = ns.UI.Table
  ns.UI.Table = function(...)
    local t = make(...)
    assert(heights[t], "a UI.Table without a height when made")
    tablesMade = tablesMade + 1
    return t
  end
end
for _, f in ipairs(tocFiles()) do
  assert(loadfile(dir .. "/" .. f))("GoldForever", ns)
end
tablesHaveHeights(ns)
if SAVE then
  local rows = {}
  local function timed(label, fn)
    -- The collector stopped while a step runs, so what it allocates is counted, not what was freed.
    collectgarbage("collect")
    collectgarbage("stop")
    local kb, t = collectgarbage("count"), os.clock()
    local ok, err = pcall(fn)
    local ms = (os.clock() - t) * 1000
    local allocated = collectgarbage("count") - kb
    collectgarbage("restart")
    -- A loose budget a step (GF_SMOKE_BUDGET_MS, 1000 by default): it catches work grown tenfold, not noise.
    if ok and ms > (tonumber(os.getenv("GF_SMOKE_BUDGET_MS")) or 1000) then
      ok, err = false, "over the budget"
    end
    if not ok then failedSteps = (failedSteps or 0) + 1 end
    rows[#rows + 1] = string.format("%-34s %8.1f ms %8.0f KB%s", label, ms, allocated, ok and "" or ("  FAILED: " .. tostring(err)))
  end
  -- Login and the work it schedules; what stalls the game is the slowest single step, so each timer's
  -- step is timed too, and the worst one named.
  local worst, worstAt = 0, "?"
  local after = C_Timer.After
  C_Timer.After = function(sec, fn)
    after(sec, function()
      local t = os.clock()
      fn()
      local ms = (os.clock() - t) * 1000
      if ms > worst then
        local info = debug.getinfo(fn, "S")
        worst, worstAt = ms, info.short_src:match("[^/]+$") .. ":" .. info.linedefined
      end
    end)
  end
  timed("load and log in", function()
    local t = os.clock()
    fire("ADDON_LOADED", "GoldForever")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD", true, false)
    local ms = (os.clock() - t) * 1000
    if ms > worst then worst, worstAt = ms, "the login events themselves" end
    wait(40)
  end)
  C_Timer.After = after
  rows[#rows + 1] = string.format("%-34s %8.1f ms  (%s)", "slowest single step after login", worst, worstAt)
  local pages = { "home", "money", "characters", "inventory", "sales", "crafting", "now", "levelling", "mobs", "rares", "companion", "settings", "guide", "design" }
  for _, look in ipairs({ "web", "classic", "arcane" }) do
    timed(look .. ": open the hub", function() SlashCmdList.GOLDFOREVER("look " .. look) SlashCmdList.GOLDFOREVER("ui home") end)
    for _, page in ipairs(pages) do
      timed(look .. ": " .. page, function() SlashCmdList.GOLDFOREVER("ui " .. page) end)
    end
    timed(look .. ": settings tabs", function()
      local p = ns.hubWindow().pages.settings
      for _, tab in ipairs({ "general", "modules", "discord", "looks" }) do p.ensure(tab) end
    end)
    timed(look .. ": revisit every page", function() for _, page in ipairs(pages) do SlashCmdList.GOLDFOREVER("ui " .. page) end end)
  end
  -- The character's own latest scan gives prices: an item of it is priced.
  do
    local latest
    for _, sc in ipairs(GoldForeverDB.scans or {}) do if sc.kind == "full" and (not latest or sc.t > latest.t) then latest = sc end end
    local id = latest and latest.rows[1] and tonumber(latest.rows[1]:match("^(%d+)"))
    if id then
      local value = ns.price.market(id)
      wait(5)
      value = ns.price.market(id)
      rows[#rows + 1] = string.format("%-34s %s (scan %s, item %d)", "own scan prices", value and "yes" or "NO", latest.market, id)
      if not value then failedSteps = (failedSteps or 0) + 1 end
    end
  end
  timed("HUD on and off", function() GoldForever_ToggleHud() wait(1) GoldForever_ToggleHud() end)
  local AP = ns.AuctionPanel
  AuctionHouseFrame = widget()
  timed("auction house: open", function() fire("AUCTION_HOUSE_SHOW") end)
  for _, tab in ipairs({ "scan", "post", "shop", "cancel" }) do
    timed("auction house: " .. tab, function() AP.tab(tab) end)
  end
  timed("selling rules page", function() SlashCmdList.GOLDFOREVER("ui rules") end)
  SlashCmdList.GOLDFOREVER("ui")
  timed("auction house: close", function() fire("AUCTION_HOUSE_CLOSED") end)
  timed("mailbox", function() fire("MAIL_SHOW") fire("MAIL_CLOSED") end)
  -- Each item tooltip hook on its own, over every catalogued item, so its share shows.
  -- Twice: a first look at every item, then a working set shown again and again, as play does.
  for pass = 1, 2 do
  for _, h in ipairs(itemTooltipHooks) do
    local where = debug.getinfo(h, "S")
    timed("item tooltips" .. (pass == 2 and " again: " or ": ") .. where.short_src:match("[^/]+$") .. ":" .. where.linedefined, function()
      local data = { id = 0, type = 0 }
      local ids = {}
      for id in pairs(GoldForeverDB.catalogue.items or {}) do ids[#ids + 1] = id end
      -- First a look at every item; again, the same 500 items 40 times over (hovering bags and the AH).
      local n, rounds = pass == 1 and #ids or math.min(500, #ids), pass == 1 and 1 or 40
      for _ = 1, rounds do
        for i = 1, n do
          GameTooltip.lines[1] = nil
          data.id = ids[i]
          h(GameTooltip, data)
        end
      end
    end)
  end
  end
  timed("logout", function() fire("PLAYER_LOGOUT") end)
  for _, r in ipairs(rows) do io.write(r, "\n") end
  local errors = {}
  for name, e in pairs(GoldForeverDB.errors or {}) do
    if (e.t or 0) >= now - 3600 then errors[#errors + 1] = name .. ": " .. tostring(e.msg) end
  end
  io.write("ERRORS " .. #errors .. "\n", table.concat(errors, "\n"), "\n")
  io.write(string.format("MEMORY %.0f KB after a full collect\n", (function() collectgarbage("collect") return collectgarbage("count") end)()))
  os.exit((#errors == 0 and not failedSteps) and 0 or 1)
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
-- Five seconds on: a position sample and the HUD's clock.
now = now + 5; clock = clock + 5; tick(5); tick(1)
fire("PLAYER_TARGET_CHANGED")
fire("UNIT_SPELLCAST_SENT", "player", "Peacebloom", "Cast-9", 2366)
slots = { { kind = 1, link = "|Hitem:2447::::::::30|h[Peacebloom]|h", qty = 2, sources = { "GameObject-0-4620-0-12-1618-000C", 2 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
-- The client may say the trainer changed whenever a filter is switched: the read's own switches start no
-- read of their own (they did, once a second, while the window stayed open).
do
  local reads, set, count = 0, SetTrainerServiceTypeFilter, GetNumTrainerServices
  function SetTrainerServiceTypeFilter(f, on) filters[f] = on fireNow("TRAINER_UPDATE") end
  function GetNumTrainerServices() reads = reads + 1 return count() end
  fire("TRAINER_SHOW")
  wait(5)
  SetTrainerServiceTypeFilter, GetNumTrainerServices = set, count
  assert(reads == 1, "the trainer read once: " .. reads)
end
for _, h in ipairs(tooltipHooks) do h(nil, { guid = "GameObject-0-4620-0-12-180682-000D", lines = { { leftText = "Oily Blackmouth School" } } }) end
fishing = true
slots = { { kind = 1, link = "|Hitem:6358::::::::30|h[Oily Blackmouth]|h", qty = 1, sources = { "GameObject-0-4620-0-12-180682-000D", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
fishing = false
-- A buff on oneself, then a bobber: the bobber is not named after the player.
fire("UNIT_SPELLCAST_SENT", "player", "Testchar", "Cast-8", 1243)
slots = { { kind = 1, link = "|Hitem:6358::::::::30|h[Oily Blackmouth]|h", qty = 1, sources = { "GameObject-0-4620-0-12-35591-000E", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
seen("BOBBER NAMED ", tostring(GoldForeverDB.catalogue.objects[35591]), "nil")
wait(30)
fire("TRADE_SKILL_SHOW")
fire("MERCHANT_SHOW")
-- The trainer was left without its close event; its frame is hidden, so the sale is the vendor's alone.
ClassTrainerFrame = { IsShown = function() return false end }
money = money + 37; fire("PLAYER_MONEY")
bolts = 0
C_Item.GetItemCount = function(id) return id == 2996 and bolts or 0 end
-- The addon hears its own casts only, not every unit's in a group.
for _, e in ipairs({ "UNIT_SPELLCAST_START", "UNIT_SPELLCAST_SENT" }) do
  local player, party = false, false
  for _, f in ipairs(frames) do player = player or hears(f, e, "player"); party = party or hears(f, e, "party1") end
  assert(player and not party, e .. " is registered for the player alone")
end
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
seen("CRAFTS ", tostring(GoldForeverDB.events["2026-10-20"].craft and GoldForeverDB.events["2026-10-20"].craft[1]), "1792517415,1,2963,2996,1,75,1429;1792517415,1,2963,2996,1,76,1429;1792517415,1,2963,2996,2,76,1429")
Enum.FlightPathState = { Current = 0 }
TakeTaxiNode(2)
-- /gf check shows the flights' cost with the addon's own money text, which works on retail too.
do
  local me, said, saved = ns.me(), {}, print
  local cost = me.flights.cost
  me.flights.cost = 12345
  function print(...) said[#said + 1] = table.concat({...}, " ") end
  SlashCmdList.GOLDFOREVER("check")
  print = saved
  me.flights.cost = cost
  local line
  for _, l in ipairs(said) do if l:find("paid flights", 1, true) then line = l end end
  assert(line and line:find(ns.price.coins(12345), 1, true) and not line:find("12345c", 1, true), "flights line: " .. tostring(line))
end
-- A settings table saved before a default was added gets it; what the player set stays.
do
  GoldForeverDB.settings.smokeOld = { shown = false }
  local s = ns.settings("smokeOld", { shown = true, added = 3 })
  assert(s.shown == false and s.added == 3, "a later default reaches an older table")
  GoldForeverDB.settings.smokeOld = nil
end
C_QuestLog = { GetTitleForQuestID = function() return "The Fargodeep Mine, part 2" end }
fire("QUEST_ACCEPTED", 62)
wait(10)
fire("QUEST_TURNED_IN", 62, 450, 75)
money = money + 75; fire("PLAYER_MONEY")
wait(10)
-- Money changed at the auction house has "auction" in ctx once, whichever events said the window opened.
do
  local day = GoldForeverDB.events[ns.Encode.day(now)]
  local rows = {}
  for i, chunk in ipairs(day.money or {}) do rows[i] = chunk end
  fire("AUCTION_HOUSE_SHOW")
  if Enum.PlayerInteractionType then fire("PLAYER_INTERACTION_MANAGER_FRAME_SHOW", Enum.PlayerInteractionType.Auctioneer) end
  money = money - 20; fire("PLAYER_MONEY")
  fire("AUCTION_HOUSE_CLOSED")
  if Enum.PlayerInteractionType then fire("PLAYER_INTERACTION_MANAGER_FRAME_HIDE", Enum.PlayerInteractionType.Auctioneer) end
  local last
  for _, r in ipairs(ns.Views.rows(GoldForeverDB, "money")) do if not last or r.t >= last.t then last = r end end
  assert(last and last.delta == "-20" and ("+" .. tostring(last.ctx) .. "+"):find("+auction+", 1, true) and not last.ctx:find("auctioneer"), "auction money ctx: " .. tostring(last and last.ctx))
  -- Given back, and both rows taken out again, so the rest of the session is as it was.
  money = money + 20; fire("PLAYER_MONEY")
  day.money = rows
  wait(10)
end
-- No scan at the auction house until the player switches it on (manual test run 001).
do
  local before = GoldForeverDB.lastReplicate
  fire("AUCTION_HOUSE_SHOW")
  wait(2)
  assert(GoldForeverDB.lastReplicate == before, "no scan by itself while Scan when I open is off")
  fire("AUCTION_HOUSE_CLOSED")
  ns.settings("scan", {}).auto = true
end
fire("AUCTION_HOUSE_SHOW")
fire("REPLICATE_ITEM_LIST_UPDATE")
wait(70)
do -- the scan's market names the realm on WoW: Forever, the connected group on retail
  local scan = GoldForeverDB.scans[#GoldForeverDB.scans]
  local want = INTERFACE >= 110000 and "-AnotherRealm-" or "-Classic Beta PvE 2-"
  assert(scan and scan.market and scan.market:find(want, 1, true), "scan market: " .. tostring(scan and scan.market))
  -- Retail records each distinct item's class and stack; WoW: Forever's scan keeps its shape.
  if INTERFACE >= 110000 then
    local items = table.concat(scan.items or {}, ";")
    assert(items == "2589,7,5,1000;14047,7,5,", "retail scan items: " .. items)
  else
    assert(scan.items == nil, "a WoW: Forever scan records no items")
  end
end
SlashCmdList.GOLDFOREVER("scan")
C_Background.GetThing()
SlashCmdList.GOLDFOREVER("legacy")
-- Legacy is WoW: Forever's own: read there, never on retail.
if INTERFACE >= 110000 then
  assert(not (GoldForeverDB.account and (GoldForeverDB.account.legacy or GoldForeverDB.account.legacyTreeSearch)), "no Legacy read on retail")
else
  assert(GoldForeverDB.account and GoldForeverDB.account.legacy and GoldForeverDB.account.legacy.renown == 16, "Legacy read on WoW: Forever")
end
-- A claim code from the site, typed on this character (security review finding 4).
SlashCmdList.GOLDFOREVER("claim bcdf-2345")
C_Background.GetThing()
wait(60)
-- Appraiser: a scan of the character's market, then two loot windows.
table.insert(GoldForeverDB.scans, { t = 1792520000, kind = "full", market = "EU-Classic Beta PvE 2-" .. side, rows = { "2589,40,100,10;2589,50,200,5;2934,500,3,1" } })
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
table.insert(GoldForeverDB.scans, { t = 1792520100, kind = "full", market = "EU-Classic Beta PvE 2-" .. side,
  rows = { "2589,40,100,10;2589,50,200,5;2934,500,3,1;11137,2850,40,8;11135,3851,10,2;11139,25743,2,2" } })
ns.scanVersion = (ns.scanVersion or 0) + 1
slots = { { kind = 1, link = "|Hitem:271206::::::::30|h[Skin]|h", qty = 1, sources = { "Creature-0-4620-0-12-1922-000H", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
seen("BIG DROP ", tostring(raidNotices[1]), "Big drop: Leftover Abomination Skin — 6s 87c")
GameTooltip.lines = {}
for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 251962 }) end
seen("SASH TOOLTIP ", table.concat(GameTooltip.lines, " / "), "|cffe0ac45Gold Forever|r Vendor 15s 85c / Disenchant ≈ 53s 66c · |cff56c98fbetter than selling|r", "|cffe0ac45Gold Forever|r Vendor 15s 85c / Disenchant ≈ 1c")
bagsFull = true
-- Where the merchant window has no junk button of its own (WoW: Forever), the advisor sells junk with
-- Blizzard's own call: the first press says what, the second sells, once.
local sold = 0
MerchantFrame = widget({ shown = true })
function MerchantFrame:IsShown() return true end
C_MerchantFrame = { GetNumJunkItems = function() return 3 end, IsSellAllJunkEnabled = function() return true end,
  SellAllJunkItems = function() sold = sold + 1 end }
fire("MERCHANT_SHOW")
seen("ADVISOR\n", tostring(appraiserText), "Sell junk: 3 items · 0c")
do
  local sell = ns.Advisor.sellButton()
  assert(sell and sell:IsShown() and (sell.label:GetText()):find("Sell junk: 3 items", 1, true), "Sell junk shows: " .. tostring(sell and sell.label:GetText()))
  sell.scripts.OnClick(sell)
  assert(sold == 0 and (sell.label:GetText()):find("Press again", 1, true), "the first press only asks")
  sell.scripts.OnClick(sell)
  assert(sold == 1, "the second press sells")
  -- A client whose merchant window has Blizzard's own button: none of ours.
  MerchantSellAllJunkButton = widget()
  fire("BAG_UPDATE_DELAYED")
  assert(not sell:IsShown(), "no second junk button beside Blizzard's")
  MerchantSellAllJunkButton = nil
end
MerchantFrame, C_MerchantFrame = nil, nil
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
seen("RARE ", tostring(raidNotices[1]) .. " | notices " .. #raidNotices .. " | skull " .. tostring(marks.nameplate3), "Rare: Testchar (12 elite) near 41.2, 67.9 | notices 1 | skull 8", "nil | notices 0 | skull nil")
-- Off on retail for now: its cities' minimap markers made the announcer fire on ordinary NPCs (2026-10-22).
if INTERFACE >= 110000 then
  assert(#raidNotices == 0 and marks.nameplate3 == nil, "retail: no rare notice and no skull")
else
  assert(#raidNotices == 1 and marks.nameplate3 == 8, "WoW: Forever: the rare is announced once and marked")
end
-- A value the client keeps secret (newer clients): anything but type() and issecretvalue() on it fails,
-- as in game: reading it as text, comparing it, indexing it, counting it, doing sums with it.
local function secretValue()
  local function refuse() error("attempt to use a secret value", 2) end
  return setmetatable({}, { __tostring = refuse, __concat = refuse, __eq = refuse, __lt = refuse, __le = refuse,
    __index = refuse, __newindex = refuse, __len = refuse, __call = refuse, __unm = refuse,
    __add = refuse, __sub = refuse, __mul = refuse, __div = refuse, __mod = refuse, __pow = refuse })
end
assert(not pcall(function() return secretValue().find end) and not pcall(function() return secretValue() < 1 end), "a secret refuses use")
-- A marker the client keeps secret: never compared, the rare still marked once.
do
  local SECRET = secretValue()
  function issecretvalue(v) return rawequal(v, SECRET) end
  local index = GetRaidTargetIndex
  GetRaidTargetIndex = function() return SECRET end
  UnitGUID = function(u) if u == "nameplate3" then return "Creature-0-4620-0-12-947-0000ABC9" end return unitGUID(u) end
  marks.nameplate3 = nil
  fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
  if INTERFACE < 110000 then
    assert(marks.nameplate3 == 8, "marked without reading the secret marker")
  end
  GetRaidTargetIndex = index
  issecretvalue = nil
end
-- A unit whose identity the client keeps secret (GUID, name, creature type): nothing read, nothing
-- recorded, no error (the errors table is checked at the end of the run).
do
  local SECRET = secretValue()
  function issecretvalue(v) return rawequal(v, SECRET) end
  local guid, name, kind = UnitGUID, UnitName, UnitCreatureType
  UnitGUID = function(u) if u == "nameplate3" or u == "npc" then return SECRET end return guid(u) end
  UnitName = function(u) if u == "nameplate3" then return SECRET end return name(u) end
  UnitCreatureType = function(u) if u == "nameplate3" then return SECRET end return kind(u) end
  local notices = #raidNotices
  fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
  fire("PLAYER_TARGET_CHANGED")
  assert(#raidNotices == notices, "no alert for a unit the client keeps secret")
  for _, h in ipairs(tooltipHooks) do h(nil, { guid = SECRET, lines = { { leftText = SECRET } } }) end
  for _, h in ipairs(tooltipHooks) do h(nil, { guid = "GameObject-0-4620-0-12-180683-000D", lines = { { leftText = SECRET } } }) end
  assert(GoldForeverDB.catalogue.objects[180683] == nil, "no object named from a secret line")
  fire("UNIT_SPELLCAST_SENT", "player", SECRET, "Cast-10", 2366)
  UnitGUID, UnitName, UnitCreatureType = guid, name, kind
  issecretvalue = nil
end
-- A mob whose name is secret but whose GUID is not: recorded without a name, no error; out of combat
-- the readable name fills the row.
do
  local SECRET = secretValue()
  function issecretvalue(v) return rawequal(v, SECRET) end
  local guid, name = UnitGUID, UnitName
  UnitGUID = function(u) if u == "nameplate3" then return "Creature-0-4620-0-12-61234-0000ABD1" end return guid(u) end
  UnitName = function(u) if u == "nameplate3" then return SECRET end return name(u) end
  fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
  local row = GoldForeverDB.catalogue.npcs[61234]
  assert(row and row:find("^,"), "a secret name is not written: " .. tostring(row))
  UnitName = function(u) if u == "nameplate3" then return "Ashfang Prowler" end return name(u) end
  fire("PLAYER_REGEN_ENABLED")
  row = GoldForeverDB.catalogue.npcs[61234]
  assert(row and row:find("^Ashfang Prowler,"), "the readable name fills the row: " .. tostring(row))
  UnitGUID, UnitName = guid, name
  issecretvalue = nil
end
-- "Tell my party": nothing in chat while it is off (the default); on and in a party, one line a spawn.
do
  local said = {}
  function SendChatMessage(text, channel) said[#said + 1] = channel .. ": " .. text end
  assert(#said == 0, "nothing sent with it off")
  ns.settings("rares", { announce = true, mark = true }).party = true
  IsInGroup = function() return true end
  function UnitIsGroupLeader() return false end
  function UnitIsGroupAssistant() return false end
  IsInRaid = function() return false end
  UnitGUID = function(u) if u == "nameplate3" then return "Creature-0-4620-0-12-947-0000ABC2" end return unitGUID(u) end
  fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
  fire("NAME_PLATE_UNIT_ADDED", "nameplate3")
  if INTERFACE < 110000 then
    assert(#said == 1 and said[1]:find("^PARTY: %[Gold Forever%] Rare: "), "one party line for the new spawn: " .. tostring(said[1]))
  else
    assert(#said == 0, "retail: rare alerts are off, nothing told")
  end
  ns.settings("rares", { announce = true, mark = true }).party = nil
  IsInGroup = function() return false end
end
-- The craft list at the auction house: Bolt of Linen Cloth from 2 Linen, Bolts selling at 2s.
table.insert(GoldForeverDB.scans, { t = 1792520200, kind = "full", market = "EU-Classic Beta PvE 2-" .. side,
  rows = { "2589,40,100,10;2589,50,200,5;2996,200,20,4;2934,500,3,1" } })
ns.scanVersion = (ns.scanVersion or 0) + 1
GoldForeverDB.catalogue.items[2996] = "Bolt of Linen Cloth,1,10,7,5,10,25,0,132890"
GoldForeverDB.catalogue.tooltips[2996] = "Bolt of Linen Cloth"
fire("AUCTION_HOUSE_SHOW")
seen("SHOP\n", tostring(appraiserText), "|cffffd100Vendor these|r · 6s 87c\n1× Leftover Abomination Skin · 6s 87c\n \n|cff56c98fPost these|r · 2s 66c\n7× Item‚ 2589 · 2s 66c|cff999999 (post at 40c each)|r\n \n|cffa335eeDisenchant these|r · 53s 66c\n1× Violet Sash · 53s 66c\n \n|cffffffffAll of it: 63s 19c|r", "|cffffd100Vendor these|r · 22s 72c\n1× Violet Sash · 15s 85c\n1× Leftover Abomination Skin · 6s 87c\n \n|cff56c98fPost these|r · 6s 65c\n7× Item‚ 2589 · 6s 65c|cff999999 (post at 1s 0c each)|r\n \n|cffffffffAll of it: 29s 37c|r")
-- The crafting strip: beside the profession window, the selected recipe's cost, sale and profit.
do
  ProfessionsFrame = widget()
  fire("TRADE_SKILL_SHOW")
  ns.CraftingStrip.select(2963)
  local title = ns.CraftingStrip.shown()
  assert(title and title:find("Bolt of Linen Cloth", 1, true), "the strip names the recipe's item: " .. tostring(title))
  fire("TRADE_SKILL_CLOSE")
  assert(not ns.CraftingStrip.shown(), "and closes with the window")
  ProfessionsFrame = nil
end
-- The auction panel: docked to the auction house, the bags' Linen priced and posted as a commodity.
do
  AuctionHouseFrame = widget()
  ItemLocation = { CreateFromBagAndSlot = function(_, bag, slot) return { bag = bag, slot = slot } end }
  C_Item.DoesItemExist = function() return true end
  local posts = {}
  C_AuctionHouse.IsSellItemValid = function() return true end
  C_AuctionHouse.GetItemCommodityStatus = function() return 2 end
  C_AuctionHouse.GetItemKeyFromItem = function() return { itemID = 2589, itemLevel = 0 } end
  C_AuctionHouse.SendSearchQuery = function() end
  C_AuctionHouse.GetNumCommoditySearchResults = function() return 2 end
  C_AuctionHouse.GetCommoditySearchResultInfo = function(_, i) return ({ { unitPrice = 3000, quantity = 5, numOwnerItems = 5 }, { unitPrice = 4250, quantity = 20, numOwnerItems = 0 } })[i] end
  C_AuctionHouse.PostCommodity = function(...) posts[#posts + 1] = { ... } end
  local framesBefore = #frames
  fire("AUCTION_HOUSE_SHOW")
  print("AH PANEL FRAMES at opening: " .. (#frames - framesBefore))
  assert((#frames - framesBefore) <= 21, "the auction panel builds at most 21 frames at opening: " .. (#frames - framesBefore))
  local AP = ns.AuctionPanel
  function SetOverrideBindingClick() end
  function ClearOverrideBindings() end
  AP.tab("scan")
  assert(not AP.bound(), "Space is free on the Scan tab")
  -- Alt-click on the bag's Linen (bag 0, slot 1) chooses it in Post, by slot or by link.
  ns.AuctionPanelAltClick(nil, { bag = 0, slot = 1 })
  local _, picked = AP.state()
  assert(picked and picked.id == 2589 and AP.bound(), "alt-click chose Linen and opened Post")
  AP.tab("scan")
  ns.AuctionPanelAltClick("|cffffffff|Hitem:2589::::::::30|h[Linen Cloth]|h|r", nil)
  _, picked = AP.state()
  assert(picked and picked.id == 2589, "by link where no slot is given")
  AP.tab("scan")
  AP.tab("post")
  assert(AP.bound(), "Space posts on the Post tab")
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
  local rows, chosen = AP.state()
  assert(#rows >= 1 and chosen and chosen.id == 2589 and chosen.count == 7, "the bags' Linen is the row")
  assert(chosen.cheapest == 4250 and chosen.cheapestFrom == "live", "own listings left out of the cheapest")
  seen("AH POST ", tostring(chosen.suggestion and chosen.suggestion.reason) .. " " .. tostring(chosen.suggestion and chosen.suggestion.unit), "normal 100")
  -- A bag item's tooltip at the auction house says what Post would ask.
  GameTooltip.lines = {}
  for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 2589 }) end
  local postLine
  for _, l in ipairs(GameTooltip.lines) do if l:find("Post at", 1, true) then postLine = l end end
  assert(postLine, "the Post line in the tooltip: " .. table.concat(GameTooltip.lines, " | "))
  -- A sale profile for Linen: keep 2, undercut 1 copper, floor 50%: the Post tab follows it.
  AP.importProfile(ns.SalePlan.encode({ name = "Cloth", author = "Test", sell = { { itemID = 2589, keep = 2, price = { kind = "undercut", by = 1 }, floorPct = 50 } }, buy = {} }))
  AP.tab("post")
  local sug = AP.suggestion()
  assert(sug and sug.reason == "plan" and sug.quantity == 5, "the profile's plan prices Linen and keeps 2: " .. tostring(sug and sug.label) .. " " .. tostring(sug and sug.quantity))
  assert(sug.unit and sug.unit % 100 == 0, "in whole silver")
  GoldForeverDB.settings.auction.profile = nil -- back to the rule for the rest of the run
  -- An override for the item chosen in Post (Rule → Rule for → + The item): Post names it.
  AP.ruleScope("add-item")
  AP.ruleSet("normal", 200)
  assert(GoldForeverDB.settings.auction.overrides.items[2589].normal == 200, "the item's override holds what it changes")
  AP.tab("post")
  local over = AP.suggestion()
  assert(over and tostring(over.label):find("(item rule)", 1, true), "Post names the item's rule: " .. tostring(over and over.label))
  GoldForeverDB.settings.auction.overrides.items[2589] = nil
  AP.ruleScope("default")
  -- Held under the floor: Post anyway posts at the undercut price on a second press, never the first.
  do
    local _, row = AP.state()
    local inner, sent = C_AuctionHouse.PostCommodity, nil
    C_AuctionHouse.PostCommodity = function(_, _, _, unit) sent = unit end
    row.suggestion = { reason = "hold", floor = 9000 }
    row.anyway = 4200
    AP.post()
    assert(sent == nil and (AP.panel().post.note:GetText()):find("Press again to post anyway", 1, true), "the first press only warns: " .. tostring(AP.panel().post.note:GetText()))
    AP.post()
    assert(sent == 4200, "the second posts at the undercut price: " .. tostring(sent))
    C_AuctionHouse.PostCommodity = inner
    fire("AUCTION_HOUSE_SHOW_ERROR", 2) -- let the wait go
  end
  -- The title row names what the bank and mailbox hold that the auction house pays for; a hover lists it.
  do
    local me = ns.me()
    local bank = me.bank
    me.bank = { items = "2589*40", t = now + 1 }
    AP.tab("post")
    local away = AP.panel().away
    assert((away.text:GetText()):find("Bank & mail: 1 item", 1, true), "the bank's Linen in the title row: " .. tostring(away.text:GetText()))
    GameTooltip.lines = {}
    away.scripts.OnEnter(away)
    local listed = false
    for _, l in ipairs(GameTooltip.lines) do if l:find("sell for", 1, true) then listed = true end end
    assert(listed, "the hover says what they sell for")
    -- A click on it opens the Bank tab; a click on a bank row chooses it to take.
    away.scripts.OnClick(away)
    assert(AP.panel().tab == "bank", "the title line opens the Bank tab")
    local bankPage = AP.panel().bank
    local rows = bankPage.rows
    assert(rows and rows[1] and rows[1].id == 2589 and rows[1].place == "bank", "the bank's Linen on the Bank tab")
    -- A click chooses it (and shows it in Blizzard's window); Take all marks it, Don't take unmarks it.
    bankPage.table.lines[1].scripts.OnClick(bankPage.table.lines[1])
    bankPage.take.all.scripts.OnClick(bankPage.take.all)
    assert(ns.fetchList()[2589] == true and bankPage.rows[1].take == true, "Take all marks it")
    bankPage.take.none.scripts.OnClick(bankPage.take.none)
    assert(ns.fetchList()[2589] == nil, "Don't take unmarks it")
    bankPage.take.typed(25)
    assert(ns.fetchList()[2589] == 25, "Take… 25")
    -- At the bank: its stacks move into the bags, and it leaves the list.
    local keep = { C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_Container.UseContainerItem, C_Container.GetContainerNumFreeSlots,
      C_Container.SplitContainerItem, C_Container.PickupContainerItem }
    local used = {}
    local inBank = { [-1] = { [1] = 2589, [3] = 2589 } }
    C_Container.GetContainerNumSlots = function(bag) return inBank[bag] and 4 or (bag == 0 and 16) or 0 end
    C_Container.SplitContainerItem = function(bag, slot, n) used[#used + 1] = "split " .. bag .. ":" .. slot .. "x" .. n end
    C_Container.PickupContainerItem = function(bag, slot) used[#used + 1] = "to " .. bag .. ":" .. slot end
    C_Container.GetContainerItemInfo = function(bag, slot) local id = inBank[bag] and inBank[bag][slot] return id and { itemID = id, stackCount = 20, hyperlink = "|Hitem:" .. id .. "::::::::30|h[x]|h" } or nil end
    C_Container.UseContainerItem = function(bag, slot) used[#used + 1] = bag .. ":" .. slot end
    C_Container.GetContainerNumFreeSlots = function() return 10, 0 end
    fire("BANKFRAME_OPENED")
    wait(2)
    assert(table.concat(used, ",") == "-1:1,split -1:3x5,to 0:1", "25 of two stacks of 20: one whole, five split off: " .. table.concat(used, ","))
    assert(ns.fetchList()[2589] == nil, "and off the list")
    fire("BANKFRAME_CLOSED")
    -- The bank closed before its last stack was taken: the choice stays for the next visit.
    inBank[-1][3], used = nil, {}
    ns.fetchList()[2589] = true
    fireNow("BANKFRAME_OPENED")
    fireNow("BANKFRAME_CLOSED")
    wait(2)
    assert(#used == 0 and ns.fetchList()[2589] == true, "nothing taken, still chosen: " .. table.concat(used, ","))
    ns.fetchList()[2589] = nil
    C_Container.GetContainerNumSlots, C_Container.GetContainerItemInfo, C_Container.UseContainerItem, C_Container.GetContainerNumFreeSlots = keep[1], keep[2], keep[3], keep[4]
    C_Container.SplitContainerItem, C_Container.PickupContainerItem = keep[5], keep[6]
    AP.tab("post")
    me.bank = bank
  end
  -- Changing the rule's scope again and again builds no new frames (the picker's rows are reused).
  do
    local before = #frames
    for _ = 1, 5 do AP.ruleScope("add-item") AP.ruleScope("default") end
    assert(#frames == before, "no frames built by scope changes: " .. (#frames - before))
  end
  AP.tab("post")
  -- A post the client says needs confirming: nothing is waited for, the next press confirms it with the
  -- same four arguments.
  do
    local postInner, confirmed, asked = C_AuctionHouse.PostCommodity, nil, false
    C_AuctionHouse.PostCommodity = function() asked = true return true end
    C_AuctionHouse.ConfirmPostCommodity = function(...) confirmed = { n = select("#", ...), ... } end
    AP.post()
    if not asked then AP.post() end -- a sanity check's second press first, if one was asked
    assert(asked and not confirmed, "posted, the client asked to confirm")
    assert(select(3, AP.state()) == nil, "nothing waited for when the client asks to confirm")
    AP.post()
    assert(confirmed and confirmed.n == 4 and confirmed[3] >= 1 and confirmed[4] and confirmed[4] % 100 == 0, "confirmed with the post's four arguments")
    -- A refused post clears the wait at once (AUCTION_HOUSE_POST_ERROR), the item still chosen.
    fire("AUCTION_HOUSE_POST_ERROR")
    assert(select(3, AP.state()) == nil, "the refusal ends the wait")
    -- Warned, then the quantity changed: the press posts afresh rather than confirming the old one.
    confirmed, asked = nil, false
    AP.post()
    assert(asked and not confirmed, "warned again")
    local chosenRow = select(2, AP.state())
    GoldForeverDB.settings.auction.quantities[chosenRow.key] = 1
    asked = false
    AP.post()
    assert(asked and not confirmed, "a changed quantity is posted afresh, not confirmed")
    GoldForeverDB.settings.auction.quantities[chosenRow.key] = nil
    C_AuctionHouse.PostCommodity = postInner
    -- A post the server never answers frees the panel after the timeout; a stray game error does not
    -- end the wait, the auction house's own error does.
    AP.post()
    if select(3, AP.state()) == nil then AP.post() end
    assert(select(3, AP.state()) ~= nil, "waiting for the post's answer")
    fire("UI_ERROR_MESSAGE", 51, "Not enough mana")
    assert(select(3, AP.state()) ~= nil, "an unrelated error is not the answer")
    fire("AUCTION_HOUSE_SHOW_ERROR", 2)
    assert(select(3, AP.state()) == nil, "the auction house's error is")
    AP.post()
    if select(3, AP.state()) == nil then AP.post() end
    wait(6)
    assert(select(3, AP.state()) == nil, "no answer: the panel takes presses again after the timeout")
    for k in pairs(posts) do posts[k] = nil end
  end
  AP.duration(3) -- 48 hours for Linen, remembered for it
  AP.quantity(5) -- 5 of the 7 held, remembered for it
  AP.post()
  if chosen.suggestion and chosen.suggestion.unit then
    if #posts == 0 then AP.post() end -- a sanity check asked for a second press
    assert(#posts == 1 and posts[1][3] == 5, "one commodity post of the 5 chosen: " .. tostring(posts[1] and posts[1][3]))
    assert(posts[1][2] == 3, "for the duration remembered for the item")
    assert(GoldForeverDB.settings.auction.durations["2589"] == 3 and GoldForeverDB.settings.auction.duration == 2, "kept for Linen, the default unchanged")
    fire("AUCTION_HOUSE_AUCTION_CREATED", 1)
    assert(select(3, AP.state()) == nil, "the post is answered")
  end
  -- The Shop: a list entry for Linen up to 45s; its book from a search; Buy next quotes, a second press
  -- confirms; a quote more than 10% dearer than the deal asks again before buying.
  local calls = {}
  C_AuctionHouse.MakeItemKey = function(id) return { itemID = id, itemLevel = 0 } end
  -- Recorded around whatever the stand-in has (other files hook these: keep their hooks).
  local function around(name, label)
    local inner = C_AuctionHouse[name] or function() end
    C_AuctionHouse[name] = function(id, n, ...) calls[#calls + 1] = label .. " " .. id .. " " .. n return inner(id, n, ...) end
  end
  around("StartCommoditiesPurchase", "start")
  around("ConfirmCommoditiesPurchase", "confirm")
  GoldForeverDB.settings.auction.lists = { { name = "Mats", entries = { { itemId = 2589, maxUnit = 4500 } } } }
  AP.tab("shop")
  AP.shopChoose(GoldForeverDB.settings.auction.lists[1].entries[1])
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589) -- 5 own at 30s (left out), 20 at 42s50
  AP.shopBuy()
  assert(calls[#calls] == "start 2589 20", "Buy next asks a quote for the 20 at or under 45s: " .. tostring(calls[#calls]))
  fire("COMMODITY_PRICE_UPDATED", 4250, 85000)
  AP.shopBuy()
  assert(calls[#calls] == "confirm 2589 20", "the second press confirms the quote")
  fire("COMMODITY_PURCHASE_SUCCEEDED")
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
  AP.shopBuy()
  fire("COMMODITY_PRICE_UPDATED", 5000, 100000) -- 18% dearer than the deal
  assert(tostring(AP.shopNote()):find("price moved", 1, true), "a moved price is named before buying: " .. tostring(AP.shopNote()))
  -- A profile's buy rule (up to 12 Linen at 45s at most) is the Shop's last list: holding 7, Buy next
  -- asks for the 5 still needed, not every cheap unit.
  -- The 20 bought above count as held until the mailbox is read: they are in it now.
  assert(ns.boughtSince(2589) == 20, "a purchase counts as held until the mailbox is read")
  GoldForeverDB.settings.auction.bought = nil
  local count = C_Item.GetItemCount
  C_Item.GetItemCount = function(id) if id == 2589 then return 7 end return count and count(id) or 0 end
  AP.importProfile(ns.SalePlan.encode({ name = "Mats", author = "Test", sell = {}, buy = { { itemID = 2589, upTo = 12, maxUnit = 4500 } } }))
  GoldForeverDB.settings.auction.list = #GoldForeverDB.settings.auction.lists + 1
  AP.tab("shop")
  AP.shopChoose({ itemId = 2589, maxUnit = 4500, upTo = 12 })
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
  AP.shopBuy()
  assert(calls[#calls] == "start 2589 5", "only what the profile still needs: " .. tostring(calls[#calls]))
  C_Item.GetItemCount = count
  GoldForeverDB.settings.auction.profile = nil
  GoldForeverDB.settings.auction.list = 1
  -- The craft queue: 3 Bolts of Linen need 6 Linen; with none in the bags the Shop's "Craft queue" list
  -- buys what the bank does not hold.
  ns.queueAdd(2963, 3)
  assert(ns.queueNeeds()[2589] == 6, "the queue needs 6 Linen")
  -- The craft queue window opens with a craft queued, plans each reagent, closes with its X and comes
  -- back with the next craft queued.
  local cq = ns.CraftQueue.window()
  assert(cq and cq:IsShown(), "the craft queue window opens")
  local planned
  for _, r in ipairs(ns.CraftQueue.plan()) do if r.id == 2589 then planned = r end end
  assert(planned and planned.need == 6, "it plans the Linen")
  GoldForeverDB.settings.craftQueue.closed = true
  cq:Hide()
  ns.queueAdd(2963, 0)
  assert(cq:IsShown() and not GoldForeverDB.settings.craftQueue.closed, "a craft queued opens it again")
  -- Crafting a queued recipe counts it down.
  fire("UNIT_SPELLCAST_SUCCEEDED", "player", "Cast-1", 2963)
  assert(ns.queueList()[1].count == 2, "one Bolt of Linen crafted: two left in the queue")
  ns.queueAdd(2963, 1)
  C_Item.GetItemCount = function() return 0 end
  -- A market value above the listings (the queue's list buys under market).
  local value = ns.Prices.value
  ns.Prices.value = function(id) if id == 2589 then return 5000, "pool" end return value(id) end
  calls[#calls + 1] = "-"
  local all = { unpack(GoldForeverDB.settings.auction.lists) }
  GoldForeverDB.settings.auction.list = #all + 1
  AP.tab("shop")
  AP.shopChoose({ itemId = 2589, upTo = 6 })
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
  AP.shopBuy()
  local me = ns.me()
  local inBank = me and me.bank and ns.Encode.parseItems(me.bank.items)[2589] or 0
  assert(calls[#calls] == "start 2589 " .. (6 - inBank), "the queue's missing Linen, the bank's counted: " .. tostring(calls[#calls]))
  -- A vendor's reagent: marked so, bought at a merchant that sells it, off the auction house's list.
  do
    local vendorRow = GoldForeverDB.catalogue.vendor[2589]
    GoldForeverDB.catalogue.vendor[2589] = "50,,1,1"
    local plan
    for _, r in ipairs(ns.CraftQueue.plan()) do if r.id == 2589 then plan = r end end
    assert(plan and plan.vendor, "Linen sold by a vendor: marked so")
    local keep = { GetMerchantNumItems, GetMerchantItemID, GetMerchantItemInfo, BuyMerchantItem, GetMerchantItemMaxStack }
    local buys = {}
    GetMerchantNumItems = function() return 1 end
    GetMerchantItemID = function() return 2589 end
    GetMerchantItemInfo = function() return "Linen Cloth", 1, 50, 1, -1, true, false, false end
    BuyMerchantItem = function(i, n) buys[#buys + 1] = i .. "x" .. n end
    GetMerchantItemMaxStack = function() return 200 end
    local mf = C_MerchantFrame
    C_MerchantFrame = nil
    fire("MERCHANT_SHOW")
    wait(1)
    assert(#buys == 1 and buys[1]:find("^1x%d+$"), "bought at the merchant: " .. table.concat(buys, ","))
    fire("MERCHANT_CLOSED")
    C_MerchantFrame = mf
    GetMerchantNumItems, GetMerchantItemID, GetMerchantItemInfo, BuyMerchantItem, GetMerchantItemMaxStack = keep[1], keep[2], keep[3], keep[4], keep[5]
    GoldForeverDB.catalogue.vendor[2589] = vendorRow
  end
  ns.queueClear()
  assert(not ns.CraftQueue.window():IsShown(), "an empty queue closes the window")
  ns.Prices.value = value
  C_Item.GetItemCount = count
  GoldForeverDB.settings.auction.list = 1
  -- The purchase above is a test's, not one later checks expect to find recorded.
  for _, d in pairs(GoldForeverDB.events) do d.ahBuy = nil end
  -- Cancel undercut: one auction of 10 Linen at 50s; the book's cheapest other is 42s50 (15% under,
  -- past the 5% tolerance), so Cancel next cancels it.
  local cancelled
  local saved = {}
  for _, k in ipairs({ "QueryOwnedAuctions", "GetNumOwnedAuctions", "GetOwnedAuctionInfo", "GetItemKeyInfo", "GetCancelCost", "CancelAuction" }) do saved[k] = C_AuctionHouse[k] end
  C_AuctionHouse.QueryOwnedAuctions = function() end
  C_AuctionHouse.GetNumOwnedAuctions = function() return 1 end
  C_AuctionHouse.GetOwnedAuctionInfo = function() return { auctionID = 777, itemKey = { itemID = 2589, itemLevel = 0 }, status = 0, quantity = 10, buyoutAmount = 5000 } end
  C_AuctionHouse.GetItemKeyInfo = function() return { isCommodity = true, itemName = "Linen Cloth" } end
  C_AuctionHouse.GetCancelCost = function() return 300 end
  local cancelInner = C_AuctionHouse.CancelAuction or function() end
  C_AuctionHouse.CancelAuction = function(id, ...) cancelled = id return cancelInner(id, ...) end
  AP.tab("cancel")
  AP.cancelCheck()
  fire("OWNED_AUCTIONS_UPDATED")
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 1234) -- another item's search: the check waits for its own
  local _, stillChecking = AP.owned()
  assert(stillChecking == 1, "another search does not move the check on")
  fire("COMMODITY_SEARCH_RESULTS_UPDATED", 2589)
  wait(1)
  local mine, checking = AP.owned()
  assert(#mine == 1 and mine[1].under == 15 and not checking, "the auction is 15% undercut, the check done: " .. tostring(mine[1] and mine[1].under))
  AP.cancelNext()
  assert(cancelled == 777, "Cancel next cancels it")
  fire("AUCTION_CANCELED", 777)
  assert(#(AP.owned()) == 0, "and it leaves the list")
  for _, d in pairs(GoldForeverDB.events) do d.auctionEnd = nil end
  for k, f in pairs(saved) do C_AuctionHouse[k] = f end
  for _, k in ipairs({ "QueryOwnedAuctions", "GetNumOwnedAuctions", "GetOwnedAuctionInfo", "GetItemKeyInfo", "GetCancelCost" }) do if not saved[k] then C_AuctionHouse[k] = nil end end
  AP.tab("scan")
  assert(not AP.bound(), "and is free again off it")
  fire("AUCTION_HOUSE_CLOSED")
  GameTooltip.lines = {}
  for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 2589 }) end
  for _, l in ipairs(GameTooltip.lines) do assert(not l:find("Post at", 1, true), "no Post line away from the auction house") end
  AuctionHouseFrame = nil
end
-- Blizzard's tabs and the panel's in step (manual test run 001): it opens on Blizzard's tab, follows it,
-- and moves it; showing an item from the panel does not switch the panel.
do
  local M = { Buy = {}, ItemBuy = {}, CommoditiesBuy = {}, ItemSell = {}, CommoditiesSell = {}, Auctions = {} }
  AuctionHouseFrameDisplayMode = M
  local f, clicked = widget(), nil
  f.displayMode = M.Auctions
  function f:SetDisplayMode(mode) self.displayMode = mode end
  function f:SelectBrowseResult() self:SetDisplayMode(M.ItemBuy) end
  for name, mode in pairs({ BuyTab = M.Buy, SellTab = M.ItemSell, AuctionsTab = M.Auctions }) do
    f[name] = widget()
    f[name].Click = function() clicked = name; f:SetDisplayMode(mode) end
  end
  AuctionHouseFrame = f
  -- A full scan possible: the panel opens on Scan, to prod one; else on Blizzard's tab.
  local lastScan, auto = GoldForeverDB.lastReplicate, ns.settings("scan", {}).auto
  GoldForeverDB.lastReplicate = 0
  ns.settings("scan", {}).auto = false
  fire("AUCTION_HOUSE_SHOW")
  local p = ns.AuctionPanel.panel()
  assert(p.tab == "scan", "a scan possible: opens on Scan, not " .. tostring(p.tab))
  fire("AUCTION_HOUSE_CLOSED")
  GoldForeverDB.lastReplicate = now
  fire("AUCTION_HOUSE_SHOW")
  assert(p.tab == "cancel", "in the cooldown: opens on Blizzard's tab, Auctions, not " .. tostring(p.tab))
  GoldForeverDB.lastReplicate = lastScan
  ns.settings("scan", {}).auto = auto
  f:SetDisplayMode(M.CommoditiesSell)
  assert(p.tab == "post", "Blizzard's Sell switches the panel to Sell")
  ns.AuctionPanel.tab("shop")
  assert(clicked == "BuyTab" and f.displayMode == M.Buy and p.tab == "shop", "the panel's Buy moves Blizzard's window")
  clicked = nil
  ns.AuctionPanel.tab("scan")
  assert(clicked == nil and p.tab == "scan", "Scan leaves Blizzard's window as it is")
  ns.AuctionPanel.tab("cancel")
  f:SelectBrowseResult()
  assert(p.tab == "shop", "an item shown by Blizzard itself is its Buy")
  -- An item chosen on Sell goes into Blizzard's Sell window; the panel stays on Sell.
  local posted
  function f:SetPostItem(loc) posted = loc; self:SetDisplayMode(M.CommoditiesSell) end
  ns.AuctionPanel.tab("post")
  ns.AuctionPanelAltClick(nil, { bag = 0, slot = 1 })
  assert(posted and p.tab == "post", "chosen on Sell: into Blizzard's Sell window")
  -- Posting from the panel empties Blizzard's Sell window first (its frame would ask the emptied bag slot
  -- for an item level and fail).
  f.ItemSellFrame = { itemLocation = { bag = 0, slot = 1 }, SetItem = function(self, loc) self.itemLocation = loc end }
  local _, row = ns.AuctionPanel.state()
  assert(row, "a row is chosen")
  row.suggestion = { unit = 4200, reason = "undercut", floor = 100, normal = 9000 }
  ns.AuctionPanel.post()
  assert(f.ItemSellFrame.itemLocation == nil, "Blizzard's Sell window emptied before the panel posts")
  fire("AUCTION_HOUSE_SHOW_ERROR", 2) -- let the wait go
  f.ItemSellFrame = nil
  -- Without it, Blizzard's Buy view shows the item, but only once the client has the item key's info.
  f.SetPostItem = nil
  local browsed, info = 0, nil
  function f:SelectBrowseResult() browsed = browsed + 1 end
  local keyInfo = C_AuctionHouse.GetItemKeyInfo
  C_AuctionHouse.GetItemKeyInfo = function() return info end
  ns.AuctionPanelAltClick(nil, { bag = 0, slot = 1 })
  assert(browsed == 0, "not shown before the item key's info is loaded")
  info = { isCommodity = true }
  fire("ITEM_KEY_ITEM_INFO_RECEIVED", 2589)
  assert(browsed == 1, "shown when it arrives")
  -- An item chosen on Buy is shown in Blizzard's window too.
  ns.AuctionPanel.tab("shop")
  ns.AuctionPanel.shopChoose({ itemId = 2589 })
  assert(browsed == 2 and p.tab == "shop", "chosen on Buy: its listings in Blizzard's window")
  -- Shopping lists in the hub: a new list, an item shift-clicked in while the page shows, priced at 80% of
  -- market up to 20, renamed, exported and read back, and deleted on the second press only.
  do
    SlashCmdList.GOLDFOREVER("ui lists")
    local L = ns.listsPage
    assert(L and L:IsVisible(), "the Shopping lists page shows")
    local c, mine = L.controls, GoldForeverDB.settings.auction.lists
    local before = #mine
    c.new.scripts.OnClick(c.new)
    assert(#mine == before + 1, "New makes a list")
    local list = mine[#mine]
    local shift = IsShiftKeyDown
    IsShiftKeyDown = function() return true end
    HandleModifiedItemClick("|cffffffff|Hitem:2589::::::::30|h[Linen Cloth]|h|r")
    IsShiftKeyDown = shift
    assert(list.entries[1] and list.entries[1].itemId == 2589, "a shift-click adds the item")
    -- A shift-click in the auction house sends the link to the chat link function only.
    ChatFrameUtil.InsertLink("|cffffffff|Hitem:2592::::::::30|h[Wool Cloth]|h|r")
    assert(list.entries[2] and list.entries[2].itemId == 2592, "an auction house shift-click adds it too")
    ChatFrameUtil.InsertLink("|cffffffff|Hitem:2592::::::::30|h[Wool Cloth]|h|r")
    assert(#list.entries == 2, "the same item twice is added once")
    c.setPrice("pct", "80")
    c.setMany("20")
    assert(list.entries[2].pct == 80 and list.entries[2].upTo == 20 and not list.entries[2].maxUnit, "80% of market, up to 20")
    c.setPrice("lowest", "120")
    assert(list.entries[2].lowest == 120 and not list.entries[2].pct and not list.entries[2].maxUnit, "lowest, asking over 120%")
    c.setPrice("fixed", "4g 50s")
    assert(list.entries[2].maxUnit == 45000 and not list.entries[2].pct, "a fixed price replaces the share")
    c.rename("Cloth")
    assert(list.name == "Cloth", "renamed")
    local back = ns.Shopping.decode(ns.Shopping.encode({ list }))
    assert(back[1].entries[2].maxUnit == 45000 and back[1].entries[2].upTo == 20, "its string reads back")
    c.delete.scripts.OnClick(c.delete)
    assert(#mine == before + 1, "the first Delete only asks")
    c.delete.scripts.OnClick(c.delete)
    assert(#mine == before, "the second deletes")
    SlashCmdList.GOLDFOREVER("ui")
  end
  -- The widget report runs on what the client has.
  ns.AuctionPanel.tab("post")
  SlashCmdList.GOLDFOREVER("uidebug")
  assert(not GoldForeverDB.errors["/gf uidebug"], "uidebug: " .. tostring(GoldForeverDB.errors["/gf uidebug"] and GoldForeverDB.errors["/gf uidebug"].msg))
  ns.AuctionPanel.tab("shop")
  -- A browse result carries a price, as Blizzard's list hands it; one Blizzard refuses falls back to its
  -- search bar.
  local given
  function f:SelectBrowseResult(r) given = r; error("refused") end
  local typed, searched
  f.SearchBar = { SearchBox = { SetText = function(_, t) typed = t end }, StartSearch = function() searched = true end }
  C_Item.GetItemNameByID = C_Item.GetItemNameByID or function() return "Linen Cloth" end
  ns.AuctionPanel.shopChoose({ itemId = 2589 })
  assert(given and type(given.minPrice) == "number", "the browse result has a price")
  assert(typed and searched and p.tab == "shop", "refused: the name searched in Blizzard's search bar")
  C_AuctionHouse.GetItemKeyInfo = keyInfo
  fire("AUCTION_HOUSE_CLOSED")
  AuctionHouseFrame, AuctionHouseFrameDisplayMode = nil, nil
end
-- A quest starter drops: recorded, alerted; the mob's tooltip names it.
GoldForeverDB.catalogue.items[1357] = "Captain Sander's Treasure Map,1,15,12,0,1,0,1,134269"
GoldForeverDB.catalogue.tooltips[1357] = "Captain Sander's Treasure Map\nThis Item Begins a Quest"
C_QuestLog.IsQuestFlaggedCompleted = function() return false end
raidNotices = {}
slots = { { kind = 1, link = "|Hitem:1357::::::::30|h[Map]|h", qty = 1, quest = 136, sources = { "Creature-0-4620-0-12-1922-000Q", 1 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) fire("LOOT_CLOSED")
seen("QUEST ALERT ", tostring(raidNotices[1]) .. " | recorded quest " .. tostring(GoldForeverDB.catalogue.questStarters[1357]), "Starts a quest: Captain Sander's Treasure Map — right-click it in your bags to start it. | recorded quest 136")
GameTooltip.lines = {}
for _, h in ipairs(unitTooltipHooks) do h(GameTooltip, { guid = "Creature-0-4620-0-12-1922-000F" }) end
seen("MOB STARTER ", tostring(GameTooltip.lines[3]), "Drops a quest starter: Captain Sander's Treasure Map (25% of loots) · not done")
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
seen("POSTS ", tostring(day.post and day.post[1]), "1792517415,1,2592,2,1500,3,;1792517415,1,2592,2,1500,3,")
-- A sale mail, read twice: one sale row, no buyer.
function GetInboxNumItems() return 1 end
function GetInboxInvoiceInfo(i) return "seller", "Wool Cloth, bundle", "SomeBuyer", 0, 1900, 120, 95, 0, 0, 20, false end
function GetInboxHeaderInfo(i) return nil, nil, "Alliance Auction House", "Auction successful", 1925, 0, 29.95 end
fire("MAIL_INBOX_UPDATE") wait(2) fire("MAIL_INBOX_UPDATE") wait(2)
seen("SALES ", tostring(day.sale and day.sale[1]), "1792517415,1,Wool Cloth‚ bundle,20,1900,120,95")
-- The same mail two minutes later (fewer days left): still one sale. Then two alike mails: two.
clock = clock + 120; now = now + 120
function GetInboxHeaderInfo(i) return nil, nil, "Alliance Auction House", "Auction successful", 1925, 0, 29.95 - 120 / 86400 end
fire("MAIL_INBOX_UPDATE") wait(2)
seen("SALES AFTER DRIFT ", tostring(day.sale and day.sale[1]), "1792517415,1,Wool Cloth‚ bundle,20,1900,120,95")
function GetInboxNumItems() return 2 end
function GetInboxHeaderInfo(i) return nil, nil, "Alliance Auction House", "Auction successful", 1925, 0, i == 1 and (29.95 - 120 / 86400) or 29.999 end
fire("MAIL_INBOX_UPDATE") wait(2)
seen("SALES AFTER SECOND MAIL ", tostring(day.sale and day.sale[1]), "1792517415,1,Wool Cloth‚ bundle,20,1900,120,95;1792517535,1,Wool Cloth‚ bundle,20,1900,120,95")
-- The mailbox as a snapshot: a returned stack and gold; no sender kept.
function GetInboxHeaderInfo(i) return nil, nil, "SomeBuyer", "Auction expired", i == 1 and 1925 or 0, 0, 29.5 + i, 1 end
function GetInboxItemLink(i, slot) return slot == 1 and "|Hitem:2592::::::::30|h[Wool Cloth]|h" or nil end
function GetInboxItem(i, slot) return "Wool Cloth", 2592, 0, 20, 1, true end
ATTACHMENTS_MAX_RECEIVE = 12
fire("MAIL_INBOX_UPDATE") wait(3)
do
  local m = GoldForeverDB.characters["Player-4620-006C0FC1"].mail
  seen("MAIL ", m.used .. " mails, " .. m.items .. ", " .. m.money .. "c, expires in " .. (m.expires - now) .. " s, sender kept: " .. tostring(m.sender ~= nil), "2 mails, 2592*40, 1925c, expires in 2635200 s, sender kept: false")
end
seen("BUYER KEPT ", tostring((table.concat(day.sale or {}, ";")):find("SomeBuyer") ~= nil), "false")
-- Lists and profiles carried from the site (Data.lua's `shared`): merged into the save, newest wins.
do
  local prices = GoldForever_Prices
  local site = ns.Shopping.encode({ { name = "From the site", entries = { { itemId = 2589, maxUnit = 3000 } } } })
  local profile = ns.SalePlan.encode({ name = "Site profile", author = "Me", sell = {}, buy = { { itemID = 2589, upTo = 10, maxUnit = 3000 } } })
  GoldForever_Prices = { v = 1, at = now, markets = {}, shared = { at = 77, lists = { { id = "s1", edited = 100, string = site } }, profiles = { { id = "p1", edited = 100, string = profile } } } }
  ns.mergeShared()
  local auction = ns.settings("auction", { rule = {}, duration = 2 })
  local found
  for _, l in ipairs(auction.lists) do if l.id == "s1" then found = l end end
  assert(found and found.name == "From the site" and found.entries[1].maxUnit == 3000, "the site's list is in the save")
  local p1
  for _, p in ipairs(auction.profiles) do if p.id == "p1" then p1 = p end end
  assert(p1 and p1.buy[1].upTo == 10, "and its profile")
  local count = #auction.lists
  ns.mergeShared()
  assert(#auction.lists == count, "the same file is not merged twice")
  -- A list deleted in the game stays deleted, and the site's copies are never taken (manual test run 001:
  -- deleted lists and "(older copy)" lists came back at every reload).
  for i, l in ipairs(auction.lists) do if l.id == "s1" then table.remove(auction.lists, i) end end
  auction.removedShared = auction.removedShared or {}
  auction.removedShared.s1 = now
  local copy = ns.Shopping.encode({ { name = "From the site (older copy)", entries = {} } })
  GoldForever_Prices.shared = { at = 78, lists = { { id = "s1", edited = 100, string = site }, { id = "c1", edited = 100, string = copy } }, profiles = {} }
  ns.mergeShared()
  for _, l in ipairs(auction.lists) do
    assert(l.id ~= "s1" and l.id ~= "c1", "neither the deleted list nor a site copy came back: " .. tostring(l.name))
  end
  GoldForever_Prices = prices
end
-- The mail helper: one press opens the auction mails in turn (a player's letter and a COD mail stay),
-- the next when the inbox has changed.
do
  local keep = { GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo, AutoLootMailItem }
  local inbox = {
    { "Kael", "Hello", 500, 0, 0, true },
    { "Mallory", "Auction successful: Free gold", 700, 0, 0, true },
    { "Alliance Auction House", "Auction expired: Linen Cloth", 0, 0, 1 },
    { "Alliance Auction House", "Auction successful: Wool Cloth", 1900, 0, 0 },
    { "Bob", "Auction won: Ore", 0, 100, 2 },
  }
  function GetInboxNumItems() return #inbox end
  function GetInboxHeaderInfo(i) local m = inbox[i] if m then return nil, nil, m[1], m[2], m[3], m[4], 20, m[5], false, false, false, m[6] or false end end
  function GetInboxInvoiceInfo() return nil end
  local opened = {}
  function AutoLootMailItem(i) opened[#opened + 1] = inbox[i][2]; table.remove(inbox, i) end
  MailFrame = widget({ hooks = {} })
  function MailFrame:HookScript(name, fn) self.hooks[name] = fn end
  fire("MAIL_SHOW")
  assert(ns.Mail.panel():IsShown(), "the panel shows beside the mailbox")
  -- The inbox closed without MAIL_CLOSED (its close button, Escape): the panel goes with it.
  MailFrame.hooks.OnHide(MailFrame)
  assert(not ns.Mail.panel():IsShown(), "the panel closes when the inbox does")
  fire("MAIL_SHOW")
  assert(ns.Mail.panel():IsShown(), "and shows again at the next mailbox")
  ns.Mail.press()
  fireNow("MAIL_INBOX_UPDATE")
  wait(2)
  fireNow("MAIL_INBOX_UPDATE")
  wait(2)
  assert(#opened == 2 and opened[1]:find("expired") and opened[2]:find("Wool"), "the two auction mails, in order: " .. table.concat(opened, " | "))
  assert(#inbox == 3 and inbox[1][2] == "Hello" and inbox[2][1] == "Mallory", "the letters (one titled like the auction house's) and the COD mail stay")
  -- While the server still works on a mail nothing is taken; a refusal stops the batch.
  local pending = true
  C_Mail = C_Mail or {}
  C_Mail.IsCommandPending = function() return pending end
  table.insert(inbox, { "Alliance Auction House", "Auction successful: Silk", 500, 0, 0 })
  local before = #opened
  ns.Mail.press()
  wait(1)
  assert(#opened == before, "nothing taken while a command is pending")
  pending = false
  wait(1)
  assert(#opened == before + 1, "taken once the server is free")
  fire("MAIL_FAILED")
  C_Mail.IsCommandPending = nil
  fire("MAIL_CLOSED")
  GetInboxNumItems, GetInboxHeaderInfo, GetInboxInvoiceInfo, AutoLootMailItem = keep[1], keep[2], keep[3], keep[4]
  MailFrame = nil
end
seen("RARE ROWS ", tostring(GoldForeverDB.events["2026-10-20"] and GoldForeverDB.events["2026-10-20"].rare and GoldForeverDB.events["2026-10-20"].rare[1]), "1792517415,1,947,1429,412,679,nameplate;1792517415,1,947,1429,412,679,nameplate;1792517415,1,61234,1429,412,679,nameplate;1792517415,1,947,1429,412,679,nameplate", "nil")
seen("APPRAISER\n", tostring(ns.sessionText and ns.sessionText()), "Loot something to start a session.")
for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 2589 }) end
seen("TOOLTIP ", tostring(GameTooltip.lines[1]), "looted 4× · ~4s 50c a loot", "looted 4× · ~2s 62c a loot")
-- The pool's prices from GoldForever_Data (contract T01): one line for the player's own market.
local function poolLine(id, label)
  GameTooltip.lines = {}
  for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = id }) end
  for _, l in ipairs(GameTooltip.lines) do if l:find(label or "Market ", 1, true) then return l, GameTooltip.shades[l] end end
end
assert(poolLine(2589) == nil, "no pool line without GoldForever_Prices")
-- Held: how many each character holds, from the saved bags, bank and mail; Settings → Modules switches it.
do
  local line = poolLine(2589, "Held ")
  assert(line and line:find("Held %d+: Testchar %d+ %(") , "the character's Linen in the tooltip: " .. tostring(line))
  GoldForeverDB.settings.prices.held = false
  assert(poolLine(2589, "Held ") == nil, "switched off, no line")
  GoldForeverDB.settings.prices.held = nil
  assert(poolLine(999999, "Held ") == nil, "nobody holds it, no line")
end
-- /gf prices without a file.
local said = {}
do
  local saved = print
  function print(...) said[#said + 1] = table.concat({...}, " ") end
  SlashCmdList.GOLDFOREVER("prices")
  print = saved
end
assert(#said == 1 and said[1]:find("no prices file loaded", 1, true), "/gf prices without a file: " .. tostring(said[1]))
-- The server's key for this character's market ("EU-Classic Beta PvE 2-alliance" on Forever), and the
-- other side's.
local POOL_MINE, POOL_OTHER = "forever-EU-normal-" .. side, "forever-EU-normal-" .. otherSide
GoldForever_Prices = { v = 1, at = now, markets = { [POOL_MINE] = { [2589] = { 1234, 1100, 3, now - 7200 } } } }
local pool = poolLine(2589)
seen("POOL ", tostring(pool), "Market 12s 34c · min 11s 0c", "nil")
if INTERFACE < 110000 then
  assert(pool and pool:find("Market 12s 34c · min 11s 0c", 1, true), "the pool line")
else
  assert(pool == nil, "no Forever market on retail")
  -- Retail (T06): the connected group's market ("EU-AnotherRealm-alliance" here), then the region's commodities.
  GoldForever_Prices.markets = { ["retail-EU-AnotherRealm"] = { [2589] = { 100, 90, 2, now } },
    ["retail-EU"] = { [2589] = { 500, 490, 9, now }, [2590] = { 200, 190, 4, now } } }
  assert((poolLine(2589) or ""):find("Market 1s 0c · min 90c", 1, true), "retail: the group's price first")
  assert((poolLine(2590) or ""):find("Market 2s 0c · min 1s 90c", 1, true), "retail: the region's commodity price")
  assert(poolLine(2591) == nil, "retail: neither market has it")
  GoldForever_Prices.markets = { [POOL_MINE] = { [2589] = { 1234, 1100, 3, now } } }
end
-- The week's trend, when the companion's file carries the mean of the 7 days before.
if INTERFACE < 110000 then
  local e = GoldForever_Prices.markets[POOL_MINE][2589]
  e[5] = 1100
  local at = e[4]
  e[4] = now + 86400 -- newer than the own scan, which would win by far otherwise (Prices.pick)
  assert((poolLine(2589) or ""):find("12s 34c · +12% vs 7-day avg", 1, true), "the pool line with its trend: " .. tostring(poolLine(2589)))
  assert(select(3, ns.Prices.value(2589)) == 12, "Post gets the trend with the value")
  e[5], e[4] = nil, at
end
assert(poolLine(2590) == nil, "no pool line for an item without a price")
-- In a zone with a neutral auction house (Tanaris here), the neutral market's line comes first, on
-- Forever only; elsewhere it is not shown (design 009 decision 9).
if INTERFACE < 110000 then
  local neutralKey = POOL_MINE:gsub("%-" .. side .. "$", "-neutral")
  GoldForever_Prices.markets[neutralKey] = { [2589] = { 5000, 4500, 2, now } }
  assert(poolLine(2589, "Neutral AH ") == nil, "no neutral line outside a neutral zone")
  local where = C_Map.GetBestMapForUnit
  C_Map.GetBestMapForUnit = function() return 1446 end
  fire("ZONE_CHANGED_NEW_AREA")
  GameTooltip.lines = {}
  for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 2589 }) end
  local neutralAt, poolAt
  for k, l in ipairs(GameTooltip.lines) do
    if l:find("Neutral AH 50s 0c", 1, true) then neutralAt = k end
    if l:find("Market ", 1, true) then poolAt = k end
  end
  assert(neutralAt and poolAt and neutralAt < poolAt, "the neutral line before the faction's in Tanaris: " .. table.concat(GameTooltip.lines, " | "))
  C_Map.GetBestMapForUnit = where
  fire("ZONE_CHANGED_NEW_AREA")
  GoldForever_Prices.markets[neutralKey] = nil
end
-- Settings → Modules: prices in tooltips off takes the line away at once, and back.
do
  local before = poolLine(2589)
  GoldForeverDB.settings.prices = { tooltip = false }
  assert(poolLine(2589) == nil, "no pool line with the module off")
  GoldForeverDB.settings.prices = { tooltip = true }
  assert(poolLine(2589) == before, "and back as it was with it on")
end
if INTERFACE < 110000 then
  -- Older than three days: greyed, the words kept.
  local fresh, freshShade = poolLine(2589)
  assert(freshShade == 1, "a fresh price is white")
  GoldForever_Prices.markets[POOL_MINE][2589][4] = now - 3 * 86400 - 1
  local old, oldShade = poolLine(2589)
  assert(old:find("scanned 3d ago", 1, true) and oldShade < 1, "a price older than three days is greyed: " .. tostring(oldShade))
  GoldForever_Prices.markets[POOL_MINE][2589][4] = now - 3 * 86400
  assert(select(2, poolLine(2589)) == 1, "three days old is not greyed yet")
  -- One line names the addon; the own scan has the appraiser's line, never a second one (manual test run
  -- 001: three named lines were hard to read).
  GameTooltip.lines = {}
  for _, h in ipairs(itemTooltipHooks) do h(GameTooltip, { id = 2589 }) end
  local named, scans = 0, 0
  for _, l in ipairs(GameTooltip.lines) do
    if l:find("Gold Forever", 1, true) then named = named + 1 end
    if l:find("Your scan", 1, true) then scans = scans + 1 end
  end
  assert(named <= 1 and scans <= 1, "one line named, one own-scan line: " .. table.concat(GameTooltip.lines, " | "))
  -- /gf prices with a file: its age, each market's item count, this character's marked.
  said = {}
  local saved = print
  function print(...) said[#said + 1] = table.concat({...}, " ") end
  SlashCmdList.GOLDFOREVER("prices")
  print = saved
  seen("PRICES ", table.concat(said, " / "), "|cffe0ac45Gold Forever|r: prices file written just now · 1 market /   " .. POOL_MINE .. ": 1 item · this character's")
  assert(said[1]:find("prices file written just now · 1 market", 1, true), "/gf prices: the file")
  assert(said[2] and said[2]:find(POOL_MINE .. ": 1 item · this character's", 1, true), "/gf prices: the market")
end
GoldForever_Prices.markets = { [POOL_OTHER] = { [2589] = { 1234, 1100, 3, now } }, [ns.market(side)] = { [2589] = { 1234, 1100, 3, now } } }
assert(poolLine(2589) == nil, "no pool line from another side's market or the addon's own key")
GoldForever_Prices = { v = 1, markets = { [POOL_MINE] = { [2589] = { "x", 1100 } } } }
assert(poolLine(2589) == nil, "no pool line from a malformed entry")
GoldForever_Prices = { v = 1, markets = { [POOL_MINE] = "x" } }
assert(poolLine(2589) == nil, "no pool line from a malformed market")
-- One file with both factions and two regions (contract T05): each character reads its own market.
GoldForever_Prices = { v = 1, at = now, markets = {
  ["forever-EU-normal-alliance"] = { [2589] = { 100, 90, 2, now } },
  ["forever-EU-normal-horde"] = { [2589] = { 200, 190, 4, now } },
  ["forever-NA-normal-horde"] = { [2589] = { 300, 290, 6, now } },
} }
if INTERFACE < 110000 then
  local me, client = ns.me(), ns.db().client
  local faction, region = me.faction, client.region
  me.faction = "Alliance"
  assert((poolLine(2589) or ""):find("Market 1s 0c · min 90c", 1, true), "the Alliance character reads its market")
  me.faction = "Horde"
  assert((poolLine(2589) or ""):find("Market 2s 0c · min 1s 90c", 1, true), "a Horde character reads its market")
  client.region = "US"
  assert((poolLine(2589) or ""):find("Market 3s 0c · min 2s 90c", 1, true), "a Horde character in NA reads NA's")
  me.faction = "Alliance"
  assert(poolLine(2589) == nil, "an Alliance character in NA has no market in the file")
  me.faction, client.region = faction, region
end
GoldForever_Prices = nil
assert(not (GoldForeverDB.errors and GoldForeverDB.errors["pool tooltip"]), "the pool tooltip recorded no error")
-- A client without TooltipDataProcessor loads the file without registering anything.
do
  local saved, before = TooltipDataProcessor, #itemTooltipHooks
  TooltipDataProcessor = nil
  assert(loadfile(dir .. "/Prices.lua"))("GoldForever", { Views = ns.Views, Realms = ns.Realms, commands = {} })
  TooltipDataProcessor = saved
  assert(#itemTooltipHooks == before, "nothing registered without TooltipDataProcessor")
end
GameTooltip.lines = {}
for _, h in ipairs(unitTooltipHooks) do h(GameTooltip, { guid = "Creature-0-4620-0-12-1922-000F" }) end
seen("MOB ", tostring(GameTooltip.lines[1]) .. " | " .. tostring(GameTooltip.lines[2]), "looted 4× · ~4s 50c a loot | Linen Cloth 25% · Item‚ 2934 25% · Captain Sander's Treasure Map 25%", "looted 4× · ~2s 62c a loot | Linen Cloth 25% · Item‚ 2934 25% · Captain Sander's Treasure Map 25%")
-- One more loot of that mob after its tooltip was built: counted in place, not by reading every row.
-- It is a fight of its own with no kill XP (a grey mob): its corpse counts as one kill once the fight
-- closes, and looting it again later counts nothing.
local killsBefore = ns.sessionKills() or 0
fire("PLAYER_REGEN_DISABLED")
fire("PLAYER_REGEN_ENABLED")
slots = { { kind = 2, sources = { "Creature-0-4620-0-12-1922-000J", 40 } } }
fire("LOOT_READY") fire("LOOT_SLOT_CLEARED", 1) money = money + 40; fire("PLAYER_MONEY") fire("LOOT_CLOSED")
wait(10)
assert(ns.sessionKills() == killsBefore + 1, "a grey mob's corpse is a kill: " .. tostring(ns.sessionKills()) .. " after " .. killsBefore)
GameTooltip.lines = {}
for _, h in ipairs(unitTooltipHooks) do h(GameTooltip, { guid = "Creature-0-4620-0-12-1922-000F" }) end
seen("MOB AFTER LOOT ", tostring(GameTooltip.lines[1]), "looted 5× · ~3s 68c a loot", "looted 5× · ~2s 18c a loot")
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
seen("BACK TO BACK ", string.sub(table.concat(coinDay.loot, ";"), before + 1), ";1792517535,1,1429,412,679,n299,1,30,,;1792517535,1,1429,412,679,n299,1,20,,")

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
  seen("TRAINER CLASS ", tostring(GoldForeverDB.catalogue.trainerClasses and GoldForeverDB.catalogue.trainerClasses[8661]), "PRIEST")
end

-- A faction and a currency under closed headers keep what was read before; what shows is updated.
do
  local me = GoldForeverDB.characters["Player-4620-006C0FC1"]
  me.reputation = { factions = "69:6:1000+72:5:100" }
  me.currencies = { items = "3002*5+3001*1" }
  fire("UPDATE_FACTION") fire("CURRENCY_DISPLAY_UPDATE") wait(12)
  seen("REPUTATION ", me.reputation.factions .. " | CURRENCIES " .. me.currencies.items, "69:6:1000+72:5:3200 | CURRENCIES 3001*12+3002*5")
end

-- Levelling: a group kill in a dungeon with rested XP, a quest whose event follows its XP, a level-up.
local lday = GoldForeverDB.events["2026-10-20"]
seen("LOGIN LEVEL ", tostring(lday.level and lday.level[1]) .. " | chat listens " .. tostring(ChatFrame1.registered.TIME_PLAYED_MSG), "1792517410,1,login,30,86400,600,79098,1429,412,679 | chat listens true")
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
seen("MAP RECT ", tostring(GoldForeverDB.mapArt and GoldForeverDB.mapArt.rects[1429]), "1415,0.40000,0.60000,0.30000,0.50000", "nil")
seen("MAP ART ", tostring(GoldForeverDB.mapArt and GoldForeverDB.mapArt.maps[1411]) .. " | maps " .. tostring(GoldForeverDB.mapArt and GoldForeverDB.mapArt.build), "1002,668,256,256;768730+768731+768732+768733 | maps 1.60.1.70450", "nil | maps nil")
seen("XP ROWS ", tostring(lday.xp and lday.xp[1]), "1792517415,1,330,other,,,1429,30,412,679;1792517415,1,400,other,,,1429,30,412,679;1792517535,1,300,kill,100,party,1429,30,412,679;1792517535,1,100,boss,100,party,1429,30,412,679;1792517535,1,500,quest,,,1429,30,412,679;1792517535,1,55,explore,,,1429,30,412,679;1792517535,1,42745,other,,,1429,30,412,679;1792517535,1,700,kill,,,1429,30,412,679")
seen("LEVEL ROWS ", tostring(lday.level and lday.level[1]) .. " | chat listens " .. tostring(ChatFrame1.registered.TIME_PLAYED_MSG), "1792517410,1,login,30,86400,600,79098,1429,412,679;1792517535,1,up,31,90000,0,79450,1429,412,679 | chat listens true")
seen("ZONE ROWS ", tostring(lday.zone and lday.zone[1]), "1792517410,1,1429,,;1792517535,1,1446,,;1792517535,1,1429,,;1792517535,1,1429,party,389", "1792517410,1,1429,,;1792517535,1,1429,party,389")
seen("BOSS ROWS ", tostring(lday.boss and lday.boss[1]) .. " | instance " .. tostring(GoldForeverDB.catalogue.instances and GoldForeverDB.catalogue.instances[389]), "1792517535,1,1443,Taragaman the Hungerer,1,5,,1429,389;1792517535,1,1443,Taragaman the Hungerer,1,5,1,1429,389 | instance Ragefire Chasm,party")
-- Scans from three days, several a day: the newest two and one from each earlier day stay.
for _, t in ipairs({ 1792300000, 1792300900, 1792390000, 1792390900 }) do
  table.insert(GoldForeverDB.scans, 1, { t = t, kind = "full", market = "EU-Classic Beta PvE 2-" .. side, rows = {} })
end
-- The in-game window: every page builds and fills from the saved file.
SlashCmdList.GOLDFOREVER("ui")
SlashCmdList.GOLDFOREVER("ui mobs")
SlashCmdList.GOLDFOREVER("ui inventory")
SlashCmdList.GOLDFOREVER("ui design")
SlashCmdList.GOLDFOREVER("ui characters")
SlashCmdList.GOLDFOREVER("ui levelling")
SlashCmdList.GOLDFOREVER("ui ledger")
-- The classic look: the window of that look opens in place of the web one, on the same page, and the
-- choice is kept; a name it does not know changes nothing.
SlashCmdList.GOLDFOREVER("look classic")
assert(GoldForeverDB.settings.window.look == "classic", "the look is kept in the settings")
SlashCmdList.GOLDFOREVER("ui design")
SlashCmdList.GOLDFOREVER("ui inventory")
SlashCmdList.GOLDFOREVER("look nonsense")
assert(GoldForeverDB.settings.window.look == "classic", "an unknown look changes nothing")
-- "/gf" alone opens the hub; "/gf help" lists the commands.
do
  local helped = false
  local chat = print
  print = function(...) if table.concat({ ... }, " "):find("/gf hud", 1, true) then helped = true end chat(...) end
  local before = ns.hubWindow() ~= nil
  SlashCmdList.GOLDFOREVER("")
  assert((ns.hubWindow() ~= nil) ~= before, "/gf opens the hub, or closes it")
  SlashCmdList.GOLDFOREVER("help")
  print = chat
  assert(helped, "/gf help lists the commands")
  SlashCmdList.GOLDFOREVER("")
end
SlashCmdList.GOLDFOREVER("look arcane")
assert(GoldForeverDB.settings.window.look == "arcane", "the arcane look is kept")
SlashCmdList.GOLDFOREVER("ui design")
SlashCmdList.GOLDFOREVER("ui levelling")
SlashCmdList.GOLDFOREVER("look web")
SlashCmdList.GOLDFOREVER("ui ledger")
-- The first-run card: due on this fresh save, shown after login, and a preset sets the modules.
do
  assert(GoldForeverDB.settings.firstRun.due == true, "a save with no characters at load is a new install")
  local card = ns.FirstRun.card()
  assert(card and card:IsShown(), "the card shows after login")
  card.show(2)
  card.choose("prices")
  -- Step 3: a look is seen at once, the card drawn again in it on the same step, the preset kept.
  card.show(3)
  card.pickLook("arcane")
  assert(GoldForeverDB.settings.window.look == "arcane", "the card's look button sets the look")
  local arcane = ns.FirstRun.card()
  assert(arcane ~= card and arcane:IsShown() and not card:IsShown(), "the card is drawn again in the new look")
  card = arcane
  card.finish(false)
  SlashCmdList.GOLDFOREVER("look web")
  assert(GoldForeverDB.settings.firstRun.done == true and not card:IsShown(), "done, and closed")
  assert(GoldForeverDB.settings.auction.hidden == true and GoldForeverDB.settings.prices.tooltip == true, "prices only: the tooltip, no auction panel")
  -- Back to everything on, for the rest of the run.
  ns.FirstRun.apply("everything", { prices = GoldForeverDB.settings.prices, auction = GoldForeverDB.settings.auction,
    crafting = ns.settings("crafting", { strip = true }), appraiser = GoldForeverDB.settings.appraiser,
    advisor = GoldForeverDB.settings.advisor })
end
-- Settings draws its General tab only when it first opens; the others when chosen.
do
  local before = #frames
  SlashCmdList.GOLDFOREVER("look web")
  SlashCmdList.GOLDFOREVER("ui settings")
  print("SETTINGS FRAMES at opening: " .. (#frames - before))
  assert((#frames - before) <= 47, "Settings builds at most 47 frames at opening: " .. (#frames - before))
end
-- The Guide names only commands the addon has.
for _, c in ipairs(ns.GUIDE_COMMANDS) do
  local word = c[1]:match("^/gf%s*(%S*)")
  assert(word == "" or ns.commands[word], "the Guide's command exists: " .. c[1])
end
-- A gold goal, so Home draws its strip with one.
GoldForeverDB.settings.window.goal = { gold = 10000000, by = now + 10 * 86400 }
-- The hub: every page builds in every look, and an accent goes over the look and back.
for _, look in ipairs({ "classic", "arcane", "web" }) do
  SlashCmdList.GOLDFOREVER("look " .. look)
  for _, page in ipairs({ "home", "ledger", "characters", "inventory", "money", "sales", "crafting", "session", "now", "levelling", "mobs", "rares", "companion", "settings", "guide", "design" }) do
    SlashCmdList.GOLDFOREVER("ui " .. page)
  end
  -- Every Settings tab, drawn as a click would.
  local w = ns.hubWindow()
  local settingsPage = w and w.pages.settings
  assert(settingsPage and settingsPage.ensure, "the Settings page is open")
  for _, tab in ipairs({ "general", "modules", "discord", "looks" }) do
    settingsPage.ensure(tab)
    assert(settingsPage[tab].built, "Settings tab drawn: " .. tab)
  end
end
-- A window opened for the first time (a new accent builds one) straight onto This session: the tab's
-- once-a-second refresh and the footer's 10-second memory reading run at once, and stop when it closes.
do
  local open = ns.hubWindow()
  if open then open:Hide() end
  local ones, tens = running(1), running(10)
  SlashCmdList.GOLDFOREVER("accent #123456")
  SlashCmdList.GOLDFOREVER("ui now")
  assert(running(1) == ones + 1, "This session ticks from its first opening: " .. running(1) - ones)
  assert(running(10) == tens + 1, "the memory line reads from the window's first opening")
  ns.hubWindow():Hide()
  assert(running(1) == ones and running(10) == tens, "both stop with the window")
  SlashCmdList.GOLDFOREVER("accent")
end
-- Switching looks back and forth builds nothing new once each look has been drawn: the HUD, the
-- first-run card and the crafting strip are reused per look (frames are never freed).
do
  ns.setHud(true)
  local function cycle()
    for _, look in ipairs({ "web", "classic", "arcane" }) do
      SlashCmdList.GOLDFOREVER("look " .. look)
      SlashCmdList.GOLDFOREVER("welcome")
      ns.FirstRun.card():Hide()
    end
  end
  cycle()
  local before = #frames
  cycle() cycle()
  assert(#frames == before, "switching looks again builds no frames: " .. (#frames - before))
  SlashCmdList.GOLDFOREVER("look web")
end
-- The Session page's This session tab reads the HUD's figures.
do
  local sum = ns.sessionSummary()
  assert(sum and sum.rates and sum.ranked, "the session's figures for the page")
end
-- The Crafting page's recipes: the known Bolt of Linen, quoted.
do
  local quotes = ns.allCraftQuotes()
  assert(#quotes >= 1 and quotes[1].recipe.output == 2996, "the known recipe is on the Crafting page")
end
-- Pages folded into tabs (design 009 decision 2): an old key opens its page on its tab.
SlashCmdList.GOLDFOREVER("ui levelling")
assert(GoldForeverDB.settings.window.page == "session" and GoldForeverDB.settings.window.tabs.session == "levelling", "levelling is Session's tab")
SlashCmdList.GOLDFOREVER("ui inventory")
assert(GoldForeverDB.settings.window.page == "ledger" and GoldForeverDB.settings.window.tabs.ledger == "inventory", "inventory is Ledger's tab")
do
  local sales = ns.Views.sales(ns.Views.rows(GoldForeverDB, "sale"), nil, 0)
  assert(sales.count >= 1 and sales.list[1].item ~= "?", "the sale mail is a row on the Sales tab")
end
SlashCmdList.GOLDFOREVER("look arcane")
SlashCmdList.GOLDFOREVER("accent #d6453b")
SlashCmdList.GOLDFOREVER("ui home")
assert(ns.Theme.skin.decor.rule[1] == "#d6453b", "Arcane draws in the chosen accent")
SlashCmdList.GOLDFOREVER("look web")
SlashCmdList.GOLDFOREVER("accent #2fd1a8")
assert(GoldForeverDB.settings.window.accent == "#2fd1a8", "the accent is kept")
assert(ns.Theme.color.accent == "#2fd1a8", "and goes over the look")
SlashCmdList.GOLDFOREVER("accent")
assert(GoldForeverDB.settings.window.accent == nil, "/gf accent alone goes back to the look's own")
-- Each new accent draws every panel again: past four in a session, one more is saved and waits for a reload.
do
  local before = #frames
  for _, hex in ipairs({ "#111111", "#222222", "#333333" }) do SlashCmdList.GOLDFOREVER("accent " .. hex) end
  assert(GoldForeverDB.settings.window.accent == "#333333", "the fifth colour is saved")
  assert(ns.Theme.color.accent ~= "#333333", "but not drawn until a reload")
  local drawn = #frames
  SlashCmdList.GOLDFOREVER("accent #444444")
  assert(#frames == drawn, "and builds nothing")
  SlashCmdList.GOLDFOREVER("accent")
end
-- Discord dings: changed in game only with the companion's file, and only once the site has a webhook.
do
  local prices, guid = GoldForever_Prices, UnitGUID("player")
  GoldForever_Prices = nil
  SlashCmdList.GOLDFOREVER("ui companion") -- the Companion page without the companion's file
  SlashCmdList.GOLDFOREVER("dings on")
  assert(not (GoldForeverDB.dings and GoldForeverDB.dings[guid]), "no choice without the companion")
  GoldForever_Prices = { v = 1, at = now - 60, dings = { webhook = false, characters = {} } }
  SlashCmdList.GOLDFOREVER("dings on")
  assert(not (GoldForeverDB.dings and GoldForeverDB.dings[guid]), "no choice without a webhook on the site")
  GoldForever_Prices.dings.webhook = true
  SlashCmdList.GOLDFOREVER("dings on")
  assert(GoldForeverDB.dings[guid].on == true and GoldForeverDB.dings[guid].t == now, "the choice is saved with the time")
  SlashCmdList.GOLDFOREVER("ui settings")
  SlashCmdList.GOLDFOREVER("dings")
  GoldForever_Prices = prices
end
SlashCmdList.GOLDFOREVER("ui ledger")
-- The ways in without a slash command: the compartment's click and the key bindings open and close
-- the window and switch the look; /gf minimap hides the button and brings it back, and remembers.
assert(type(GoldForever_OnAddonCompartmentClick) == "function", "the TOC's compartment function exists")
assert(BINDING_HEADER_GOLDFOREVER and BINDING_NAME_GOLDFOREVER_WINDOW and BINDING_NAME_GOLDFOREVER_LOOK and BINDING_NAME_GOLDFOREVER_HUD, "Bindings.xml's names are set")
do
  GoldForever_ToggleHud()
  local first = GoldForeverDB.settings.appraiser.shown
  GoldForever_ToggleHud()
  assert(GoldForeverDB.settings.appraiser.shown == not first, "the HUD binding toggles the HUD")
  if not GoldForeverDB.settings.appraiser.shown then GoldForever_ToggleHud() end
  -- Settings → Modules sets the HUD as switched, whatever the frame shows now.
  ns.setHud(false)
  assert(GoldForeverDB.settings.appraiser.shown == false, "switched off, it is off")
  ns.setHud(true)
  assert(GoldForeverDB.settings.appraiser.shown == true, "switched on, it is on")
  -- Tucked away in combat, the binding turns it off rather than on.
  local lockdown, hide = InCombatLockdown, GoldForeverDB.settings.appraiser.hideInCombat
  GoldForeverDB.settings.appraiser.hideInCombat = true
  InCombatLockdown = function() return true end
  fire("PLAYER_REGEN_DISABLED")
  GoldForever_ToggleHud()
  assert(GoldForeverDB.settings.appraiser.shown == false, "the binding in combat turns a tucked HUD off")
  InCombatLockdown, GoldForeverDB.settings.appraiser.hideInCombat = lockdown, hide
  fire("PLAYER_REGEN_ENABLED")
  ns.setHud(true)
end
-- Performance budget: no once-a-second ticker while the HUD is hidden (the auction panel's is closed).
do
  if GoldForeverDB.settings.appraiser.shown then GoldForever_ToggleHud() end
  for _, t in ipairs(liveTickers) do if t.every == 1 and not t.cancelled then t.fn() end end
  assert(running(1) == 0, "no ticker once the HUD is hidden: " .. running(1))
  GoldForever_ToggleHud()
  assert(running(1) == 1, "one while it shows")
end
-- Every binding Bindings.xml names calls a function the addon defines.
for call in io.open(dir .. "/Bindings.xml"):read("*a"):gmatch("([%w_]+)%(%)") do
  assert(type(_G[call]) == "function", "Bindings.xml calls " .. call)
end
GoldForever_SwitchLook()
assert(GoldForeverDB.settings.window.look == "classic", "the look binding switches the look")
GoldForever_OnAddonCompartmentClick("GoldForever", "RightButton")
assert(GoldForeverDB.settings.window.look == "arcane", "a right-click in the compartment steps on to the next look")
GoldForever_SwitchLook()
assert(GoldForeverDB.settings.window.look == "web", "and round again to the first")
GoldForever_ToggleWindow()
GoldForever_OnAddonCompartmentClick("GoldForever", "LeftButton")
GoldForever_OnAddonCompartmentEnter("GoldForever", UIParent)
GoldForever_OnAddonCompartmentLeave()
SlashCmdList.GOLDFOREVER("minimap")
assert(GoldForeverDB.settings.minimap.hidden == true, "/gf minimap hides the button")
SlashCmdList.GOLDFOREVER("minimap")
assert(GoldForeverDB.settings.minimap.hidden == false, "and brings it back")
seen("UI WINDOW ", tostring(GoldForeverDB.settings.window and GoldForeverDB.settings.window.page), "ledger")
do
  local V, db = ns.Views, GoldForeverDB
  local rows, best = V.characters(db.characters, GetServerTime(), UnitGUID("player"))
  seen("UI CHARACTERS ", #rows .. " best " .. tostring(best and best.name), "1 best nil")
  local led = V.ledger(V.rows(db, "money"), V.rows(db, "flight"), nil, 0)
  local cats = {}
  for _, c in ipairs(led.categories) do cats[#cats + 1] = c.key .. "=" .. c.net end
  seen("UI LEDGER ", table.concat(cats, " ") .. " net " .. led.net, "loot=240 quest=75 vendor=37 net 352")
  local lv = V.levelling(V.rows(db, "level"), V.rows(db, "xp"), ns.me().ref)
  seen("UI LEVELLING levels ", #lv.levels .. " xp " .. lv.xp .. " perHour " .. tostring(lv.perHour), "2 xp 45130 perHour nil")
end

-- A retail save is lean: no tooltip text, achievement catalogue or map art; Forever keeps them all.
do
  local function count(t) local n = 0 for _ in pairs(t or {}) do n = n + 1 end return n end
  local c = GoldForeverDB.catalogue
  if FLAVOUR == "retail" then
    -- (the run seeds a few tooltips itself; Linen is one the addon catalogued)
    assert(c.items[2589] and c.tooltips[2589] == nil and count(c.achievements) == 0, "retail keeps a lean save")
    assert(count(c.items) > 0, "but the items the hub names")
  else
    assert(c.tooltips[2589] and count(c.achievements) > 0, "Forever keeps its tooltips and achievements")
  end
end
-- Statistics go entry by entry on the frame budget (a retail category can be more than a frame may
-- spend on: "script ran too long"); logout, with no next frame, refreshes only the values already read.
do
  local lists = { GetStatisticsCategoryList, GetCategoryNumAchievements, debugprofilestop }
  GetStatisticsCategoryList = function() return { 130, 131, 132 } end
  GetCategoryNumAchievements = function() return 20 end
  -- A clock 10 ms on at every look: the budget runs out at its first check, after 25 entries.
  local ms = 0
  debugprofilestop = function() ms = ms + 10 return ms end
  local reads, stat = 0, GetStatistic
  GetStatistic = function(id) reads = reads + 1 return stat(id) end
  ns.me().statistics = nil
  wait(61)
  fireNow("CRITERIA_UPDATE")
  assert(ns.me().statistics == nil and reads == 25, "the first frame's share read, the rest on later frames: " .. reads)
  wait(1)
  assert(ns.me().statistics and ns.me().statistics[13201] == "--" and reads == 60, "all three categories read: " .. reads)
  reads = 0
  fire("PLAYER_LOGOUT")
  assert(reads > 0, "logout refreshes the values read")
  GetStatisticsCategoryList, GetCategoryNumAchievements, debugprofilestop, GetStatistic = lists[1], lists[2], lists[3], stat
end

-- A scan read only in part (the auction house closed mid-read) is no market: stored without rows.
assert(ns.Market.partial(1000, 500, false) and ns.Market.partial(1000, 1000, true), "half read, or cut short: partial")
assert(not ns.Market.partial(1000, 950, false) and not ns.Market.partial(0, 0, false), "nearly all read: full; none announced: not partial")
-- A call the client stops for running too long never returns, and the next call in a later frame records
-- it (Core.lua). The stand-in cannot stop a call; this checks only that calls which return or error are
-- never recorded as stopped.
do
  pcall(ns.safely, "erring", function() error("caught") end)
  ns.safely("returning", function() end)
  wait(1)
  ns.safely("next frame", function() end)
  assert(not GoldForeverDB.stopped, "nothing recorded as stopped")
  assert(GoldForeverDB.errors.erring and GoldForeverDB.errors.erring.n == 1, "the caught error is recorded")
  local stack = GoldForeverDB.errors.erring.stack
  assert(type(stack) == "string" and stack:find("smoke") and #stack <= 800, "with a trimmed stack that names where it came from: " .. tostring(stack))
  ns.safely("erring with arguments", function(a, b, c) assert(a == 1 and b == nil and c == 3) error("caught") end, 1, nil, 3)
  assert(GoldForeverDB.errors["erring with arguments"].msg:find("caught"), "the arguments, a nil among them, reach the call")
  GoldForeverDB.errors["erring with arguments"] = nil
  GoldForeverDB.errors.erring = nil
end
assert(tablesMade > 0, "the session made tables")
-- What the run recorded before the reload clears it: nothing failed, nothing was stopped.
local function recorded()
  local out = {}
  for name, e in pairs(GoldForeverDB.errors or {}) do out[#out + 1] = name .. ": " .. tostring(e.msg) end
  for name, e in pairs(GoldForeverDB.stopped or {}) do out[#out + 1] = name .. ": stopped " .. tostring(e.n) .. "x" end
  table.sort(out)
  return out
end
assert(#recorded() == 0, "errors before the reload:\n" .. table.concat(recorded(), "\n"))
-- A /reload: the file is written, the addon loads again from scratch with the same saved table.
local before = ns.sessionText()
fire("PLAYER_LOGOUT")
-- The save was written by an older version, with an error it recorded: the new version starts with none.
local thisVersion = GoldForeverDB.addon
GoldForeverDB.addon = "0.15.0"
GoldForeverDB.errors.old = { n = 3, msg = "fixed since", t = now - 86400 }
-- A newer version wrote the file: its schema stays, the data is not relabelled as the older one's.
GoldForeverDB.schema = 99
-- Days older than the 14 kept but not yet exported stay, up to 30 days; an older one goes.
local exportedBefore = GoldForeverDB.exportedAt
GoldForeverDB.exportedAt = now - 26 * 86400
for _, day in ipairs({ "2026-09-01", "2026-09-24", "2026-10-01" }) do GoldForeverDB.events[day] = { sys = {} } end
for k in pairs(frames) do frames[k] = nil end
local ns2 = {}
for _, f in ipairs(tocFiles()) do
  assert(loadfile(dir .. "/" .. f))("GoldForever", ns2)
end
tablesHaveHeights(ns2)
clock = clock + 5; now = now + 5
fire("ADDON_LOADED", "GoldForever") fire("PLAYER_LOGIN") fire("PLAYER_ENTERING_WORLD", false, true)
assert(GoldForeverDB.errors.old == nil and GoldForeverDB.addon == thisVersion, "an older version's errors are cleared")
assert(GoldForeverDB.schema == 99, "a newer schema is never lowered")
GoldForeverDB.schema = 1
assert(GoldForeverDB.events["2026-09-24"] and GoldForeverDB.events["2026-10-01"] and not GoldForeverDB.events["2026-09-01"],
  "days not yet exported are kept, within 30 days")
GoldForeverDB.events["2026-09-24"], GoldForeverDB.events["2026-10-01"] = nil, nil
GoldForeverDB.exportedAt = exportedBefore
local after = ns2.sessionText and ns2.sessionText() or ""
seen("AFTER RELOAD\n", tostring(after), "Farming 3:57\nCoin: 90c\nItems: 0c\n|cffffffffTotal: 90c|r\n|cffffd100Per hour: 13s 64c|r\nXP: 44400 · 673011/h · level 31 in 4m (~133 kills)\nBags: 8 free")
do
  local kinds = {}
  for _, sc in ipairs(GoldForeverDB.scans) do kinds[#kinds + 1] = sc.kind .. "@" .. tostring(sc.t) end
  seen("SCANS KEPT ", table.concat(kinds, " "), "full@1792300900 full@1792390900 full@1792517415 full@1792520100 full@1792520200", "full@1792517415 full@1792520200")
end
seen("SAME TOTALS ", tostring((before:match("Total: [^|]*")) == (after:match("Total: [^|]*"))), "true")
assert(before:match("Total: [^|]*") and before:match("Total: [^|]*") == after:match("Total: [^|]*"), "the session survives a /reload")
-- An old prices file: one line at login, not again the same day.
do
  local prices, warned = GoldForever_Prices, 0
  GoldForever_Prices = { v = 1, at = now - 3 * 86400, markets = {} }
  local chat = print
  print = function(...) if table.concat({ ... }, " "):find("is the companion app running", 1, true) then warned = warned + 1 end chat(...) end
  fire("PLAYER_ENTERING_WORLD", true, false)
  fire("PLAYER_ENTERING_WORLD", true, false)
  print = chat
  assert(warned == 1, "one warning for an old file: " .. warned)
  GoldForever_Prices = prices
end
-- /gf export: the first holds everything, the next only what is new; both build without error.
SlashCmdList.GOLDFOREVER("export")
local firstAt = GoldForeverDB.exportedAt
seen("EXPORT AT ", tostring(firstAt) .. " sent items " .. tostring(GoldForeverDB.exportSent and GoldForeverDB.exportSent.items ~= nil), "1792517540 sent items true")
now = now + 60
SlashCmdList.GOLDFOREVER("export")
seen("EXPORT AGAIN after ", tostring(GoldForeverDB.exportedAt and firstAt and GoldForeverDB.exportedAt - firstAt) .. " s", "60 s")
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
-- Performance budget (design 009): a 30,000-auction scan read 500 a frame stays under ~2 ms a frame.
-- Measured with the JIT off, closer to the game's own Lua; printed always.
do
  local N = 30000
  C_AuctionHouse.GetNumReplicateItems = function() return N end
  C_AuctionHouse.GetReplicateItemInfo = function(i)
    local id = 2000 + i % 3000
    return "x", 0, 1 + i % 20, 1, true, 1, 0, 1, 1, 100 + (i % 97) * 37, 0, false, nil, nil, nil, 0, id, true
  end
  C_AuctionHouse.GetReplicateItemLink = function(i) return "|Hitem:" .. (2000 + i % 3000) .. "::::::::30|h[x]|h" end
  C_AuctionHouse.GetReplicateItemTimeLeft = function(i) return 1 + i % 4 end
  if jit then jit.off() end
  -- The chat, for the deals line.
  local chat = print
  print = function(...) local line = table.concat({ ... }, " ") if line:find("at or under your price", 1, true) then dealsLine = line end chat(...) end
  GoldForeverDB.settings.auction.lists = { { name = "Mats", entries = { { itemId = 2589, maxUnit = 4500 } } } }
  -- At an auctioneer of the character's side, so the scan is its market and its prices are rebuilt.
  local factionOf = UnitFactionGroup
  UnitFactionGroup = function(u) if u == "npc" then return SIDE end return factionOf(u) end
  GoldForeverDB.lastReplicate = 0
  now = 1792600000 -- after every scan in the file, so this one is the newest
  fire("AUCTION_HOUSE_SHOW")
  wait(2)
  local frames, worst, total = 0, 0, 0
  local before = #timers
  local slowest = {}
  local function step()
    local start = os.clock()
    table.sort(timers, function(a, b) if a.at ~= b.at then return a.at < b.at end return a.n < b.n end)
    while #timers > 0 and timers[1].at <= clock + 0.001 do
      local t = table.remove(timers, 1)
      local t0 = os.clock()
      t.fn()
      local one = (os.clock() - t0) * 1000
      if one > (slowest.ms or 0) then local info = debug.getinfo(t.fn, "S"); slowest = { ms = one, where = info.short_src .. ":" .. info.linedefined } end
    end
    return (os.clock() - start) * 1000
  end
  fireNow("REPLICATE_ITEM_LIST_UPDATE")
  clock = clock + 1
  while #timers > 0 and frames < 200 do
    local ms = step()
    frames = frames + 1
    total = total + ms
    if ms > worst then worst = ms end
    clock = clock + 0.001
  end
  -- The first price asked after the scan rebuilds the prices from it (Appraiser.lua), over frames too.
  -- (The addon was reloaded above: ns2 is the one running now.)
  local rframes, rworst = 0, 0
  ns2.price.market(2001)
  while #timers > 0 and rframes < 400 do
    local ms = step()
    rframes = rframes + 1
    if ms > rworst then rworst = ms end
    clock = clock + 0.001
  end
  print(string.format("PRICE REBUILD after a %d-auction scan: %d frames, worst %.2f ms", N, rframes, rworst))
  -- The deals line once the prices were in: the list's Linen (up to 45s) is listed cheaper in this scan.
  assert(dealsLine, "the deals line after the scan")
  seen("DEALS ", dealsLine, "|cffe0ac45Gold Forever|r: 1 item on your lists is at or under your price: Linen Cloth. Open the Buy tab.")
  assert(ns2.price.market(2001) and ns2.price.cheapest(2001), "the big scan's prices arrive")
  assert(rworst < 20, string.format("a frame of the price rebuild took %.2f ms", rworst))
  UnitFactionGroup = factionOf
  print = chat
  if jit then jit.on() end
  print(string.format("SCAN BUDGET %d auctions in %d frames: worst %.2f ms, mean %.2f ms a frame; slowest step %.2f ms at %s", N, frames, worst, total / frames, slowest.ms or 0, tostring(slowest.where)))
  -- A frame averages under the budget; the worst may hold a garbage-collection step, so it fails only
  -- far above it (saving the scan in one frame took ~100 ms here before it was spread).
  assert(total / frames < 2, string.format("scan frames average %.2f ms (budget ~2 ms)", total / frames))
  assert(worst < 20, string.format("a frame of the scan took %.2f ms", worst))
  fire("AUCTION_HOUSE_CLOSED")
end
-- A scan whose listings stop coming part-way (what the client does once the auction house is closed
-- mid-read) is stored without rows as partial, and the full scan before it stays the market.
do
  local scans = GoldForeverDB.scans
  local before = #scans
  local info = C_AuctionHouse.GetReplicateItemInfo
  -- As the client does once the auction house is closed: the item still, but no price or count.
  C_AuctionHouse.GetReplicateItemInfo = function(i)
    if i >= 10000 then
      return "x", 0, 0, 1, true, 1, 0, 1, 1, 0, 0, false, nil, nil, nil, 0, 2000 + i % 3000, true
    end
    return info(i)
  end
  dealsLine = nil
  GoldForeverDB.lastReplicate = 0
  now = now + 3600
  fire("AUCTION_HOUSE_SHOW")
  wait(2)
  fire("REPLICATE_ITEM_LIST_UPDATE")
  wait(5)
  local rec = scans[#scans]
  assert(#scans == before + 1 and rec.kind == "throttled" and rec.partial == true, "a scan read in part is stored as partial: " .. tostring(rec.kind) .. " " .. tostring(rec.partial))
  local rows = 0
  for _, c in ipairs(rec.rows or {}) do rows = rows + #c end
  assert(rows == 0, "with no rows")
  wait(5)
  assert(dealsLine == nil, "no deals line after a partial scan: " .. tostring(dealsLine))
  fire("AUCTION_HOUSE_CLOSED")
  C_AuctionHouse.GetReplicateItemInfo = info
end
-- On WoW: Forever an auction may have a bid and no buyout. A scan where a fifth of the listings are such is
-- read whole: it is stored full, its prices from the listings with a buyout.
do
  local scans = GoldForeverDB.scans
  local before = #scans
  local info = C_AuctionHouse.GetReplicateItemInfo
  C_AuctionHouse.GetReplicateItemInfo = function(i)
    if i % 5 == 0 then
      return "x", 0, 1 + i % 20, 1, true, 1, 0, 50, 1, 0, 0, false, nil, nil, nil, 0, 2000 + i % 3000, true
    end
    return info(i)
  end
  GoldForeverDB.lastReplicate = 0
  now = now + 3600
  fire("AUCTION_HOUSE_SHOW")
  wait(2)
  fire("REPLICATE_ITEM_LIST_UPDATE")
  wait(5)
  local rec = scans[#scans]
  assert(#scans == before + 1 and rec.kind == "full" and not rec.partial, "a scan with bid-only listings is full: " .. tostring(rec.kind) .. " " .. tostring(rec.partial))
  local rows = 0
  for _, c in ipairs(rec.rows or {}) do for row in c:gmatch("[^;]+") do rows = rows + 1; assert(not row:find("^[^,]*,0,"), "no price of 0: " .. row) end end
  assert(rows > 0 and ns2.lastScan.kind == "full", "with its prices")
  fire("AUCTION_HOUSE_CLOSED")
  C_AuctionHouse.GetReplicateItemInfo = info
end
-- Anything the addon recorded after the reload fails the run, as the big-save tour does: an error
-- caught by ns.safely is not raised, so only this sees it.
do
  local left = recorded()
  io.write("ERRORS " .. #left .. "\n", table.concat(left, "\n"), "\n")
  os.exit(#left == 0 and 0 or 1)
end
