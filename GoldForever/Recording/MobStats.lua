-- Gold Forever: what the characters have looted from each NPC, counted from the loot rows in the file
-- once a session and kept up per loot, for the mob tooltips and the hub's Mobs and Rares pages.

local _, ns = ...
local Encode = ns.Encode
local worth = ns.price.worth

local mobs -- npc ID -> { loots, coin, items = { [id] = { dropped, units } } }; built once, then kept up per loot

-- One loot row counted in: by the full build and by every loot after it.
local function countLoot(npc, coin, items)
	local m = mobs[npc] or { loots = 0, coin = 0, items = {} }
	mobs[npc] = m
	m.loots = m.loots + 1
	m.coin = m.coin + coin
	for item, n in pairs(items) do
		local d = m.items[item] or { dropped = 0, units = 0 }
		m.items[item] = d
		d.dropped = d.dropped + 1
		d.units = d.units + n
	end
end

-- New loot updates the counts in place, rather than reading every loot row again at the next
-- tooltip (two weeks of rows, in the tooltip's own frame).
local countingRows -- loot rows that came while the counts were being built, counted in after them
local function countRows(rows)
	for _, row in ipairs(rows or {}) do
		local npc = Encode.npcOf(row.src)
		if npc then
			local items = {}
			for key, n in pairs(row.items) do
				local id = Encode.itemId(key)
				if id then
					items[id] = (items[id] or 0) + n
				end
			end
			countLoot(npc, row.coin or 0, items)
		end
	end
end
table.insert(ns.lootListeners, function(_, _, rows)
	if mobs then
		countRows(rows)
	elseif countingRows then
		countingRows[#countingRows + 1] = rows
	end -- not started: the build reads everything, this loot included
end)

-- The counts from every saved loot row. Two weeks of heavy farming is tens of thousands of rows, more
-- than one frame may spend on: CHUNKS_A_FRAME chunks (500 rows each) a frame, from a list of the chunks
-- taken at the start (rows written meanwhile come through the listener above). Until it is done the
-- counts are nil: no tooltip line, and the Mobs page says it is counting.
-- A frame's share (ns.frameSpent), else ROWS_A_FRAME rows: chunks of 500 rows were 6 ms each on two
-- weeks of loot, too much for one frame.
local ROWS_A_FRAME = 250
local mobCountWaiters = {} -- what to call once the counts are in
local function buildMobs()
	if countingRows then
		return
	end
	local db = ns.db()
	local columns = Encode.columns(db.fields and db.fields.loot)
	if not (columns.src and columns.coin and columns.items) then
		mobs = {}
		return
	end
	local chunks = {}
	for _, bucket in pairs(db.events) do
		for _, chunk in ipairs(bucket.loot or {}) do
			chunks[#chunks + 1] = chunk
		end
	end
	countingRows = {}
	local counted, i, pos = {}, 1, 1 -- the chunk and the place in it the next row starts
	local step
	-- A step that fails (a malformed row) drops the half-built counts: the next tooltip or page builds
	-- them again, rather than showing part of them for the session.
	local function failed(err)
		mobs, countingRows, mobCountWaiters = nil, nil, {}
		ns.fail("mob counts", err)
	end
	local function guarded()
		local ok, err = pcall(step)
		if not ok then
			failed(err)
		end
	end
	step = function()
		local saved = mobs
		mobs = counted
		local started, rows = ns.frameStart(), 0
		while chunks[i] do
			local chunk = chunks[i]
			local stop = string.find(chunk, ";", pos, true)
			local row = string.sub(chunk, pos, (stop or 0) - 1)
			if stop then
				pos = stop + 1
			else
				i, pos = i + 1, 1
			end
			if row ~= "" then
				local values = { strsplit(",", row) }
				local id = Encode.npcOf(values[columns.src])
				if id then
					countLoot(id, tonumber(values[columns.coin]) or 0, Encode.parseItems(values[columns.items]))
				end
			end
			rows = rows + 1
			if ns.frameSpent(started, rows, ROWS_A_FRAME) then
				break
			end
		end
		if chunks[i] then
			mobs = saved
			C_Timer.After(0, guarded)
			return
		end
		for _, rows in ipairs(countingRows) do
			countRows(rows)
		end
		countingRows = nil
		for _, fn in ipairs(mobCountWaiters) do
			ns.safely("mob counts", fn)
		end
		mobCountWaiters = {}
	end
	guarded()
end
-- Counts that failed to build are built again at the next loading screen.
ns.module("MobStats", {
	requires = { "Store" },
	world = function()
		if not mobs then
			ns.after(20, "mob counts", buildMobs)
		end
	end,
})

-- Every NPC looted, for the in-game pages: { [npc] = { loots, coin, items = { [id] = { dropped, units } } } }
-- and what one unit of an item is worth; nil while the counts are built, and `whenBuilt` is called once
-- they are.
function ns.mobStats(whenBuilt)
	if not mobs then
		if whenBuilt then
			mobCountWaiters[#mobCountWaiters + 1] = whenBuilt
		end
		buildMobs()
	end
	return mobs, worth
end
