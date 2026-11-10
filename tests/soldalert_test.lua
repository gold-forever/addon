-- SoldAlert.lua: the client's "sold" system message becomes one coin sound and one chat line naming the item
-- and what arrives after the cut, read from the character's own post rows; nothing is recorded.

local NOW = 1792517410
local NAMES = { [2589] = "Linen Cloth", [2592] = "Wool Cloth" }

-- One load of Auctions.lua with the client's wording `format` (nil: the English client's), the save's post
-- rows and the auction settings. Returns fire(message), the lines said, the sounds played, the rows written.
local ENGLISH = ERR_AUCTION_SOLD_S
local function start(format, posts, auction)
	ERR_AUCTION_SOLD_S = format or ENGLISH
	SOUNDKIT = { LOOT_WINDOW_COIN_SOUND = 120 }
	local sounds, cvar = {}, { Sound_EnableAllSound = "1" }
	function PlaySound(kit, channel) sounds[#sounds + 1] = kit .. " " .. tostring(channel) end
	function GetCVar(name) return cvar[name] end
	local said, appended, handlers = {}, {}, {}
	local ns = {
		on = function(event, _, fn) handlers[event] = fn end,
		throttle = function(_, _, fn) return fn end,
		safely = function(_, fn, ...) return fn(...) end,
		me = function() return { ref = 1 } end,
		now = function() return NOW end,
		db = function() return { fields = { post = "t,char,item,qty,unit,duration,commodity,deposit" }, events = { [20261107] = { post = { table.concat(posts, ";") } } } } end,
		settings = function() return auction or {} end,
		itemName = function(id) return NAMES[id] or ("item " .. id) end,
		price = { cut = 0.05 },
		append = function(stream, row) appended[#appended + 1] = stream .. " " .. row end,
		say = function(text) said[#said + 1] = text end,
	}
	loadEncode(ns)
	for _, file in ipairs({ "Views.lua", "Money.lua", "Chat.lua", "SoldAlert.lua" }) do
		assert(load(SOURCES[file], "@" .. file))("GoldForever", ns)
	end
	ns.say = function(text) said[#said + 1] = ns.plainText(text) end
	ns.Money.paint(function() return "" end)
	return function(message) handlers.CHAT_MSG_SYSTEM(message) end, said, sounds, appended, cvar
end

local function post(ago, item, qty, unit, duration)
	return table.concat({ NOW - ago, 1, item, qty, unit, duration or 2, "1", "" }, ",")
end

-- The client's own wording, and when it has none the English one.
local fire, said, sounds, appended = start(nil, { post(3600, "2589", 20, 632) })
fire("A buyer has been found for your auction of Linen Cloth.")
eq(said[1], "sold Linen Cloth x20 for 1g 20s (arrives by mail)", "the amount after the 5% cut: 20 × 6s 32c = 1g 26s 40c, less the cut")
eq(sounds[1], "120 Master", "the coin sound on the Master channel")
eq(#said, 1, "one line a sale")
eq(#sounds, 1, "one sound a sale")
eq(#appended, 0, "nothing recorded: the mail records the sale")
fire("Discovered Razor Hill: 55 experience gained")
eq(#said, 1, "another system message says nothing")

fire, said = start("Es wurde ein Käufer für Eure Auktion gefunden: %s.", { post(60, "2592", 5, 1000) })
fire("A buyer has been found for your auction of Wool Cloth.")
eq(#said, 0, "the English line is not the German client's")
fire("Es wurde ein Käufer für Eure Auktion gefunden: Wool Cloth.")
eq(said[1], "sold Wool Cloth x5 for 47s 50c (arrives by mail)", "the German client's wording, the amount after the cut")

-- Unknown: no post of that item, or one no longer listed (a 12-hour post 13 hours ago). The line has the item.
fire, said, sounds = start(nil, { post(13 * 3600, "2589", 20, 632, 1) })
fire("A buyer has been found for your auction of Linen Cloth.")
eq(said[1], "sold Linen Cloth (arrives by mail)", "a post past its duration is not the one sold")
eq(#sounds, 1, "an unknown amount still sounds")
fire("A buyer has been found for your auction of Copper Ore.")
eq(said[2], "sold Copper Ore (arrives by mail)", "no post of the item: no amount")

-- Two alike posts are two sales; a third has no post left.
fire, said = start(nil, { post(7200, "2589", 20, 632), post(3600, "2589", 10, 700) })
fire("A buyer has been found for your auction of Linen Cloth.")
fire("A buyer has been found for your auction of Linen Cloth.")
fire("A buyer has been found for your auction of Linen Cloth.")
eq(said[1], "sold Linen Cloth x20 for 1g 20s (arrives by mail)", "the oldest post first")
eq(said[2], "sold Linen Cloth x10 for 66s 50c (arrives by mail)", "then the next")
eq(said[3], "sold Linen Cloth (arrives by mail)", "a sale more than posted has no amount")

-- Off in Settings: no line, no sound.
fire, said, sounds = start(nil, { post(60, "2589", 20, 632) }, { soldAlert = false })
fire("A buyer has been found for your auction of Linen Cloth.")
eq(#said, 0, "off: no line")
eq(#sounds, 0, "off: no sound")

-- The game's sound off: the line, no sound.
local cvar
fire, said, sounds, _, cvar = start(nil, { post(60, "2589", 20, 632) })
cvar.Sound_EnableAllSound = "0"
fire("A buyer has been found for your auction of Linen Cloth.")
eq(#said, 1, "sound off: the line still")
eq(#sounds, 0, "sound off: no sound")

return checks()
