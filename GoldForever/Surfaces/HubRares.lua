-- Gold Forever: the hub's Rares page: every rare the characters have seen.

local _, ns = ...
local Theme, UI, Views = ns.Theme, ns.UI, ns.Views
local Kit = ns.HubKit
local sortOf, isRetail = Kit.sortOf, Kit.isRetail

local function mapName(id)
	local info = id and C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(id)
	return info and info.name or (id and ("map " .. id)) or "?"
end

-- Every rare the characters have seen (Rares.lua's log): how often, when and where last, how it was
-- seen, and what a loot of it has been worth.
local function buildRares(page)
	local note = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT")
	note:SetPoint("RIGHT", page, "RIGHT")
	local tbl = UI.Table(page, {
		{ key = "name", title = "Rare", flex = 2 },
		{ key = "seen", title = "Seen", width = 50, align = "RIGHT" },
		{ key = "last", title = "Last", width = 80, align = "RIGHT", text = function(r) return Views.ago(r.last, ns.now()) end },
		{ key = "where", title = "Where", flex = 2, color = function() return Theme.color.textMuted end },
		{ key = "how", title = "How", width = 80, color = function() return Theme.color.textFaint end },
		{ key = "value", title = "A loot", width = 90, align = "RIGHT", text = function(r) return r.value and UI.layout.amount(r.value) or "—" end,
			sort = function(r) return r.value or -1 end },
	}, { pageSize = 14, empty = "No rare seen yet: they are logged when a nameplate, the target or the minimap shows one.", sort = sortOf("rares", "last") })
	tbl:SetPoint("TOPLEFT", note, "BOTTOMLEFT", 0, -10)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	function page:Refresh()
		-- On retail nothing is recorded (its cities are full of markers taken for rares), and what a retail save
		-- holds from before that was switched off is those false rares (manual test run 001: "NPC …" from
		-- Silvermoon): none listed.
		note:SetText(isRetail and "Rares are recorded on WoW: Forever only: retail's cities are full of map markers that are not rares."
			or "Logged from nameplates, your target and the minimap. Settings → Modules switches the alerts.")
		if isRetail then
			tbl:SetRows({})
			return -- no rare listed, so no mob's loot to count
		end
		local mobs = ns.mobStats(function()
			if page:IsShown() then
				page:Refresh()
			end
		end)
		local rows = {}
		for _, r in ipairs(ns.RaresView.rows(mobs, ns.price.worth)) do
			rows[#rows + 1] = {
				name = Kit.npcName(r.npc),
				seen = r.seen,
				last = r.last,
				where = mapName(r.map) .. ((r.x and r.y) and string.format("  %.1f, %.1f", r.x / 10, r.y / 10) or ""),
				how = r.how or "",
				value = r.value,
			}
		end
		tbl:SetRows(rows)
	end
end

ns.hubPages.rares = buildRares
