-- Gold Forever: one of your auctions sold while you are logged in, as a coin sound and one chat line.

local _, ns = ...
local L = ns.L
local Encode = ns.Encode

-- The client's own "A buyer has been found for your auction of %s." (ERR_AUCTION_SOLD_S), on both clients.
-- Nothing is recorded: the sale is recorded from its mail (Auctions.lua). The amount is the oldest post of that
-- item still listed and not yet told, after the cut; unknown, the line has none.
local readSold = ERR_AUCTION_SOLD_S and Encode.matcher(ERR_AUCTION_SOLD_S, true)
local SOLD_SOUND = SOUNDKIT and SOUNDKIT.LOOT_WINDOW_COIN_SOUND or 120 -- the coin sound
local HOURS = { 12, 24, 48 } -- a post's duration index, as PostItem takes it
local told = {} -- post rows told as sold this session: their row -> how many alike

local function soldPost(me, name, now)
	local seen = {}
	for _, r in ipairs(ns.Views.rows(ns.db(), "post", me.ref, now - HOURS[3] * 3600)) do
		local id = Encode.itemId(r.item)
		local listedUntil = r.t + (HOURS[tonumber(r.duration)] or HOURS[3]) * 3600
		if id and listedUntil >= now and ns.itemName(id) == name then
			local row = table.concat({ r.t, r.item, r.qty or "", r.unit or "" }, "|")
			seen[row] = (seen[row] or 0) + 1
			if seen[row] > (told[row] or 0) then
				told[row] = seen[row]
				return r
			end
		end
	end
end

local function sold(message)
	local me = ns.me()
	local ok, name = pcall(readSold or function() end, message or "")
	if not me or not ok or not name or ns.settings("auction").soldAlert == false then
		return
	end
	name = string.match(name, "|h%[(.-)%]|h") or name -- a link, where a client gives one
	local post = soldPost(me, name, ns.now())
	local qty, unit = tonumber(post and post.qty), tonumber(post and post.unit)
	ns.chime(SOLD_SOUND)
	if qty and unit then
		local net = math.floor(qty * unit * (1 - ns.price.cut))
		ns.say(string.format(L["sold %s x%d for %s (arrives by mail)"], name, qty, ns.Money.auction(net)))
	else
		ns.say(string.format(L["sold %s (arrives by mail)"], name))
	end
end

ns.on("CHAT_MSG_SYSTEM", "sold", sold)
