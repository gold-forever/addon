-- A made-up save the size of a heavy player's (owner's answer, 2026-10-24): the shapes of the owner's
-- retail save of that day, with every value generated, so the smoke test's GF_SMOKE_SAVE tour runs on
-- big data with no one's data in the repository. Same output every run.
--
--   luajit tests/bigsave.lua > /tmp/bigsave.lua
--   GF_SMOKE_INTERFACE=120105 GF_SMOKE_SAVE=/tmp/bigsave.lua luajit tests/smoke.lua GoldForever
--
-- Volumes: 20 000 catalogued items with tooltips, 5 300 achievements, 2 060 statistics, three characters,
-- two scans of 110 000 rows (the neutral and the Horde auction house), and fourteen days of events (positions every five seconds for
-- four hours a day, loot, money, experience, sales).

local seed = 20261024
local function rand(n)
  seed = (seed * 1103515245 + 12345) % 2147483648
  return seed % n
end

local NOW = 1792835263
local DAY = 86400
local ITEMS, ACHIEVEMENTS, STATISTICS = 20000, 5300, 2060
local SCAN_ROWS, CHUNK = 110000, 500

local items = {}
for i = 1, ITEMS do
  items[i] = 2000 + i * 13
end
local function item()
  return items[rand(ITEMS) + 1]
end

local db = {
  schema = 1, addon = "0.16.0", writtenAt = NOW,
  client = { build = "12.1.5.70575", interface = 120105, locale = "enUS", region = "EU", regionId = 3, portal = "EU" },
  catalogue = { items = {}, tooltips = {}, achievements = {}, statistics = {}, npcs = {}, objects = {}, maps = {},
    recipes = {}, vendor = {}, questNames = {}, taxiNodes = {}, trainers = {}, merchants = {}, currencies = {},
    factions = {}, legacyPerks = {}, questStarters = {}, legacyRewards = {} },
  characters = {}, events = {}, scans = {}, guildBanks = {}, errors = {}, account = {},
  settings = { retentionDays = 14, sampleSeconds = 5, share = false },
}

local c = db.catalogue
for i, id in ipairs(items) do
  c.items[id] = string.format("Made-up Item %d,%d,%d,%d,%d,%d,%d,%d,%d,%d,%s", i, rand(5), 1 + rand(600), rand(16), rand(12),
    ({ 1, 20, 200, 1000 })[rand(4) + 1], rand(500000), rand(3), 130000 + rand(9000), rand(80), rand(3) == 0 and "INVTYPE_CHEST" or "")
  c.tooltips[id] = string.format("Made-up Item %d\nItem Level %d\nBinds when picked up\nSell Price: %d", i, 1 + rand(600), rand(500000))
end
for i = 1, ACHIEVEMENTS do
  c.achievements[100000 + i] = string.format("Achievement %d,%d,Category %d,%d,Do the thing %d times.,", i, 5 * rand(5), rand(40), 236000 + rand(900), i)
end
for i = 1, STATISTICS do
  c.statistics[60000 + i] = string.format("Statistic %d,Category %d", i, rand(20))
end
-- Mobs, each with a loot table of eight items, as real ones have.
local drops = {}
for i = 1, 300 do
  c.npcs[100000 + i] = string.format("Made-up Mob %d,%d,%d,normal,Beast", i, 10 + rand(70), 10 + rand(70))
  drops[i] = {}
  for k = 1, 8 do
    drops[i][k] = item()
  end
end

-- Characters: bags, bank, statistics, professions, experience.
local guids = { "Player-3666-0000000A", "Player-3666-0000000B", "Player-3666-0000000C" }
for n, guid in ipairs(guids) do
  local function stacks(count)
    local out = {}
    for i = 1, count do
      out[i] = item() .. "*" .. (1 + rand(200))
    end
    return table.concat(out, "+")
  end
  local stats = {}
  for i = 1, STATISTICS do
    stats[60000 + i] = rand(3) == 0 and "--" or tostring(rand(100000))
  end
  stats.t = NOW - 3600
  db.characters[guid] = {
    name = "Bigsave" .. string.char(96 + n), realm = "Shadowsong", region = "EU", faction = "Horde", race = "Troll",
    class = "SHAMAN", level = 70 + 5 * n, money = rand(500000000), seen = NOW - 3600, ref = n,
    bags = { total = 184, used = 160, items = stacks(160), t = NOW - 3600 },
    bank = { total = 588, used = 400, items = stacks(400), t = NOW - 3600 },
    mail = { items = "", used = 0, total = 0, money = 0, cod = 0, t = NOW - 3600 },
    statistics = stats,
    prof = { [171] = { name = "Alchemy", skill = 75, max = 100, t = NOW - 3600 }, [182] = { name = "Herbalism", skill = 90, max = 100, t = NOW - 3600 } },
    xp = { cur = 80000, max = 480000, rested = 380000, resting = 1, t = NOW - 3600 },
    loc = { map = 2393, zone = "Silvermoon City", sub = "The Bazaar" },
  }
end

-- Scans: two markets, a full scan each, rows "item,unit,qty,count,band" in chunks of 500.
for m, market in ipairs({ "EU-Shadowsong-neutral", "EU-Shadowsong-horde" }) do
  local chunks, rows = {}, {}
  for i = 1, SCAN_ROWS do
    rows[#rows + 1] = string.format("%d,%d,%d,%d,%d", item(), 100 + rand(5000000), 1 + rand(200), 1 + rand(5), rand(4))
    if #rows == CHUNK then
      chunks[#chunks + 1] = table.concat(rows, ";")
      rows = {}
    end
  end
  if #rows > 0 then
    chunks[#chunks + 1] = table.concat(rows, ";")
  end
  db.scans[m] = { kind = "full", market = market, t = NOW - 7200 * m, rows = chunks, bands = 0, auctions = SCAN_ROWS * 2,
    map = 2393, zone = "The Bazaar", npc = "n239621", npcFaction = "none", items = {} }
end

-- Fourteen days of events, each kind's rows in chunks of 500.
local function chunked(rows)
  local out = {}
  for i = 1, #rows, CHUNK do
    out[#out + 1] = table.concat(rows, ";", i, math.min(#rows, i + CHUNK - 1))
  end
  return out
end
for d = 0, 13 do
  local day = NOW - d * DAY
  local start = day - 4 * 3600
  local ref = 1 + d % 3
  local pos, loot, money, xp, sale, zone, sys = {}, {}, {}, {}, {}, {}, {}
  for t = start, day, 5 do
    pos[#pos + 1] = string.format("%d,%d,2395,%d,%d", t, ref, 400 + rand(200), 400 + rand(200))
  end
  for i = 1, 1500 do
    local t = start + rand(4 * 3600)
    local mob = 1 + rand(300)
    loot[#loot + 1] = string.format("%d,%d,2395,%d,%d,n%d,1,%d,%d*%d+%d*1,", t, ref, 400 + rand(200), 400 + rand(200), 100000 + mob, rand(3000),
      drops[mob][1 + rand(8)], 1 + rand(5), drops[mob][1 + rand(8)])
    if i % 5 == 0 then
      money[#money + 1] = string.format("%d,%d,%d,loot", t, ref, rand(30000))
    end
    if i % 3 == 0 then
      xp[#xp + 1] = string.format("%d,%d,%d,kill,%d,,2395,%d,%d,%d", t, ref, 500 + rand(2000), rand(2), 75, 400 + rand(200), 400 + rand(200))
    end
  end
  for i = 1, 60 do
    sale[#sale + 1] = string.format("%d,%d,%d,%d,%d,%d,%d", start + rand(4 * 3600), ref, item(), 1 + rand(20), 1000 + rand(5000000), rand(5000), rand(250000))
  end
  zone[1] = string.format("%d,%d,2395,,", start, ref)
  sys[1] = string.format("%d,%d,login", start, ref)
  sys[2] = string.format("%d,%d,logout", day, ref)
  db.events[os.date("!%Y-%m-%d", day)] = { pos = chunked(pos), loot = chunked(loot), money = chunked(money), xp = chunked(xp),
    sale = chunked(sale), zone = zone, sys = sys }
end

-- Written as the client writes a SavedVariables file.
local out = { "GoldForeverDB = " }
local function write(v, indent)
  if type(v) == "table" then
    out[#out + 1] = "{\n"
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      if type(a) == type(b) then
        return a < b
      end
      return type(a) == "number"
    end)
    for _, k in ipairs(keys) do
      out[#out + 1] = indent .. "\t[" .. (type(k) == "string" and string.format("%q", k) or tostring(k)) .. "] = "
      write(v[k], indent .. "\t")
      out[#out + 1] = ",\n"
    end
    out[#out + 1] = indent .. "}"
  elseif type(v) == "string" then
    out[#out + 1] = string.format("%q", v)
  else
    out[#out + 1] = tostring(v)
  end
end
write(db, "")
out[#out + 1] = "\n"
io.write(table.concat(out))
