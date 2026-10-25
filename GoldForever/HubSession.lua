-- Gold Forever: the hub's Session tabs: this session, levelling at this character's pace, and the mobs
-- by what a loot of each is worth.

local _, ns = ...
local Theme, UI, Views = ns.Theme, ns.UI, ns.Views
local Kit = ns.HubKit
local sortOf, header, classColor = Kit.sortOf, Kit.header, Kit.classColor

-- 12345.6 -> "12,346".
local function count(n)
	return UI.layout.group(math.floor((n or 0) + 0.5))
end

-- This session --------------------------------------------------------------------------------------------------

-- The session as the HUD has it, at full size (design 009, Session module: the rates, the session's
-- loot, the big-drop threshold): refreshed once a second only while the tab shows.
local function buildSessionNow(page)
	local cards = {}
	for i, label in ipairs({ "Time", "Gold an hour", "XP an hour", "Kills an hour" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(160)
		if i == 1 then
			c:SetPoint("TOPLEFT")
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	local lines = {}
	for i, label in ipairs({ "Coin", "Loot, at what it sells for", "XP", "Kills", "Bags" }) do
		local l = UI.Text(page, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -14 - (i - 1) * 20)
		local v = UI.Text(page, "", { size = "sm" })
		v:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 200, -14 - (i - 1) * 20)
		v:SetPoint("RIGHT", page, "RIGHT")
		lines[i] = v
	end
	local tbl = UI.Table(page, {
		{ key = "name", title = "Loot", flex = 3, color = function(r) return Theme.quality[r.quality] or Theme.color.text end },
		{ key = "n", title = "Count", width = 60, align = "RIGHT" },
		{ key = "value", title = "Worth", width = 100, align = "RIGHT", text = function(r) return r.value > 0 and UI.layout.amount(r.value) or "—" end },
	}, { pageSize = 5, empty = "Nothing looted this session." })
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -124)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -8)
	note:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local sum = ns.sessionSummary and ns.sessionSummary()
		local faint = Theme.escape(Theme.color.textFaint)
		if not sum then
			for _, c in ipairs(cards) do
				c:Set("—", "")
			end
			for _, l in ipairs(lines) do
				l:SetText("")
			end
			tbl:SetRows({})
			note:SetText("Loot or kill something to start a session. A break of 15 minutes ends it.")
			return
		end
		local r = sum.rates
		cards[1]:Set(Views.duration(math.max(60, sum.elapsed)), sum.ended and "ended" or "running")
		cards[2]:Set(r.rated and UI.layout.money(r.goldPerHour, "gold") or "—", r.rated and "" or "after a minute")
		cards[3]:Set(r.rated and Views.short(r.xpPerHour) or "—", r.dingIn and ("ding in " .. Views.duration(r.dingIn)) or "")
		cards[4]:Set(r.rated and Views.short(r.killsPerHour) or "—", "no combat log")
		lines[1]:SetText(UI.layout.money(sum.coin))
		lines[2]:SetText(UI.layout.money(sum.value) .. (sum.unpriced > 0 and (faint .. string.format("  +%d unpriced", sum.unpriced) .. "|r") or ""))
		lines[3]:SetText(Views.short(sum.xp) .. (r.killsToLevel and (faint .. string.format("  · ~%d kills to level %d", r.killsToLevel, sum.nextLevel or 0) .. "|r") or ""))
		lines[4]:SetText(tostring(sum.kills))
		lines[5]:SetText(sum.bagFree == 0 and "full" or (sum.bagFree .. " free" .. (sum.fullIn and (faint .. "  · full in ~" .. Views.duration(sum.fullIn) .. "|r") or "")))
		local rows = {}
		for i, it in ipairs(sum.ranked) do
			local quality, name = ns.sessionItem(it.id)
			rows[i] = { name = name or ("item " .. it.id), quality = quality or 1, n = it.n, value = it.value }
		end
		tbl:SetRows(rows, true) -- a click or the ticker keeps the page
		note:SetText("A big drop (" .. UI.layout.money(sum.bigDrop, "gold") .. " or more, or rare and better) gets a message and a sound; change it in Settings → General.")
	end
	-- Once a second while shown, and no ticker otherwise.
	local ticker
	local function start(self)
		if C_Timer and C_Timer.NewTicker and not ticker then
			ticker = C_Timer.NewTicker(1, function()
				ns.safely("ui session", self.Refresh, self)
			end)
		end
	end
	page:SetScript("OnShow", start)
	-- A new frame is shown already, so OnShow does not come for the first opening.
	if page:IsShown() then
		start(page)
	end
	page:SetScript("OnHide", function()
		if ticker and ticker.Cancel then
			ticker:Cancel()
		end
		ticker = nil
	end)
end

-- Levelling -----------------------------------------------------------------------------------------------

local SOURCES = {
	{ key = "kill", label = "Kills", color = Theme.color.chart1 },
	{ key = "quest", label = "Quests", color = Theme.color.chart2 },
	{ key = "boss", label = "Bosses", color = Theme.color.xp },
	{ key = "explore", label = "Exploring", color = Theme.color.success },
	{ key = "other", label = "Other", color = Theme.color.chartMuted },
}

local function buildLevelling(page)
	local lede = header(page)
	local progress = UI.Text(page, "", { size = "sm", tone = "muted" })
	progress:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	local bar = UI.Bar(page, 1, {})
	bar:SetPoint("TOPLEFT", progress, "BOTTOMLEFT", 0, -6)
	bar:SetPoint("RIGHT", page, "RIGHT")
	local pace = UI.StatCard(page, "XP an hour", "", "")
	pace:SetPoint("TOPLEFT", bar, "BOTTOMLEFT", 0, -12)
	pace:SetWidth(200)
	local ding = UI.StatCard(page, "Next level", "", "")
	ding:SetPoint("LEFT", pace, "RIGHT", 12, 0)
	ding:SetWidth(200)
	local rested = UI.StatCard(page, "Rested", "", "")
	rested:SetPoint("LEFT", ding, "RIGHT", 12, 0)
	rested:SetWidth(200)
	local mixLabel = UI.Text(page, "", { size = "sm", tone = "muted" })
	mixLabel:SetPoint("TOPLEFT", pace, "BOTTOMLEFT", 0, -12)
	local mix = UI.Bar(page, 1, {}, 6)
	mix:SetPoint("TOPLEFT", mixLabel, "BOTTOMLEFT", 0, -6)
	mix:SetPoint("RIGHT", page, "RIGHT")
	local tbl = UI.Table(page, {
		{ key = "level", title = "Level", width = 60, align = "RIGHT" },
		{ key = "seconds", title = "Time on it", flex = 1, align = "RIGHT", text = function(r) return r.seconds and Views.duration(r.seconds) or Theme.escape(Theme.color.textFaint) .. "—|r" end },
		{ key = "money", title = "Gold when reached", flex = 1, align = "RIGHT", text = function(r) return r.money and UI.layout.amount(r.money) or Theme.escape(Theme.color.textFaint) .. "—|r" end },
		{ key = "reached", title = "Reached", flex = 1, align = "RIGHT", text = function(r) return r.reached and Views.ago(r.reached, ns.now()) or Theme.escape(Theme.color.textFaint) .. "—|r" end,
			color = function() return Theme.color.textMuted end },
	}, { pageSize = 6, empty = "No level-ups recorded yet.", sort = sortOf("levelling", 1) })
	tbl:SetPoint("TOPLEFT", mix, "BOTTOMLEFT", 0, -16)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local me, db = ns.me(), ns.db()
		if not me then
			return
		end
		page:SetTitle(string.format("Levelling · %s%s|r, level %d", Theme.escape(classColor(me.class)), me.name or "?", me.level or 0))
		local lv = Views.levelling(Views.rows(db, "level", me.ref), Views.rows(db, "xp", me.ref), me.ref)
		local xp = me.xp
		if xp and xp.max and xp.max > 0 then
			local have = math.min(xp.rested or 0, xp.max * Views.RESTED_CAP_LEVELS)
			progress:SetText(string.format("%s / %s XP · %d%% · %s rested", count(xp.cur), count(xp.max), math.floor(xp.cur / xp.max * 100), count(have)))
			bar:Set(xp.max, { { value = xp.cur, color = Theme.color.xp }, { value = math.min(have, xp.max - xp.cur), color = Theme.color.rested } })
			local left = xp.max - xp.cur
			ding:Set(lv.perHour and ("in " .. Views.duration(left / lv.perHour * 3600)) or "—", count(left) .. " XP to go" .. (lv.perHour and " at your pace" or ""))
			rested:Set(string.format("%.2f levels", have / xp.max), have > 0 and "kills give double XP until it is used" or "rest in an inn or a city to build it")
		else
			progress:SetText("At the level cap: nothing left to level.")
			bar:Set(1, { { value = 1, color = Theme.color.xp } })
			ding:Set("—", "at the level cap")
			rested:Set("—", "at the level cap")
		end
		pace:Set(lv.perHour and count(lv.perHour) or "—", lv.perHour and Views.duration(lv.playSeconds) .. " of play counted" or "not enough play recorded yet")
		local segments, legend = {}, {}
		for _, s in ipairs(SOURCES) do
			local n = lv.sources[s.key] or 0
			if s.key == "other" then
				for kind, v in pairs(lv.sources) do
					if kind ~= "kill" and kind ~= "quest" and kind ~= "boss" and kind ~= "explore" and kind ~= "other" then
						n = n + v
					end
				end
			end
			if n > 0 then
				segments[#segments + 1] = { value = n, color = s.color }
				legend[#legend + 1] = string.format("%s%s|r %d%%", Theme.escape(s.color), s.label, math.floor(n / lv.xp * 100 + 0.5))
			end
		end
		mixLabel:SetText(lv.xp > 0 and ("XP by source: " .. table.concat(legend, " · ")) or "XP by source: none recorded yet")
		mix:Set(math.max(1, lv.xp), segments)
		tbl:SetRows(lv.levels)
	end
end

-- Mobs ---------------------------------------------------------------------------------------------------

local function buildMobs(page)
	local lede = header(page)
	local tbl = UI.Table(page, {
		{ key = "name", title = "Mob", flex = 2 },
		{ key = "loots", title = "Looted", width = 70, align = "RIGHT" },
		{ key = "coin", title = "Coin a loot", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.coin) end, sort = function(r) return r.coin end },
		{ key = "value", title = "A loot", width = 100, align = "RIGHT", text = function(r) return UI.layout.amount(r.value) end, sort = function(r) return r.value end },
	}, { pageSize = 13, empty = "No loot recorded yet.", sort = sortOf("mobs", 4) })
	tbl:SetPoint("TOPLEFT", lede, "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		local mobs, worth = ns.mobStats(function()
			if page:IsShown() then
				page:Refresh()
			end
		end)
		if not mobs then
			tbl:SetRows({})
			tbl.footer:SetText("Counting the loot…")
			return
		end
		local rows = {}
		for id, m in pairs(mobs or {}) do
			local value = m.coin
			for item, d in pairs(m.items) do
				value = value + (worth(item) or 0) * d.units
			end
			rows[#rows + 1] = {
				name = Kit.npcName(id),
				loots = m.loots,
				coin = m.coin / m.loots,
				value = value / m.loots,
			}
		end
		tbl:SetRows(rows)
	end
end

ns.hubPages.now = buildSessionNow
ns.hubPages.levelling = buildLevelling
ns.hubPages.mobs = buildMobs
