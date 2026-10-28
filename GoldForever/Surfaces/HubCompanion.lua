-- Gold Forever: the hub's Companion page: what the companion app has brought into the game.

local _, ns = ...
local Theme, UI = ns.Theme, ns.UI
local Kit = ns.HubKit

-- What the addon can know of the companion without the internet (design 009): whether its file loaded,
-- when it was written, its markets and items, and what is missing.
local function buildCompanion(page)
	local status = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	status:SetPoint("TOPLEFT")
	status:SetPoint("RIGHT", page, "RIGHT")
	status:SetHeight(76)
	local icon = UI.Icon(status, "coins", 22, "accent")
	icon:SetPoint("LEFT", 20, 0)
	local head = UI.Text(status, "", { size = "md", medium = true })
	head:SetPoint("TOPLEFT", 58, -18)
	head:SetPoint("RIGHT", status, "RIGHT", -16, 0)
	local line = UI.Text(status, "", { size = "xs", tone = "faint", wrap = true })
	line:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -6)
	line:SetPoint("RIGHT", status, "RIGHT", -16, 0)

	local cards = {}
	for i, label in ipairs({ "Prices written", "Markets", "This character's market" }) do
		local c = UI.StatCard(page, label, "", "")
		c:SetWidth(math.floor((Kit.pageWidth(page) - 24) / 3))
		if i == 1 then
			c:SetPoint("TOPLEFT", status, "BOTTOMLEFT", 0, -12)
		else
			c:SetPoint("LEFT", cards[i - 1], "RIGHT", 12, 0)
		end
		cards[i] = c
	end
	local tbl = UI.Table(page, {
		{ key = "key", title = "Market", flex = 3 },
		{ key = "items", title = "Items", width = 90, align = "RIGHT" },
		{ key = "mine", title = "", width = 140, align = "RIGHT", text = function(r) return r.mine and "this character's" or "" end,
			color = function() return Theme.color.accent end },
	}, { pageSize = 6, empty = "No markets in the file." })
	tbl:SetPoint("TOPLEFT", cards[1], "BOTTOMLEFT", 0, -12)
	tbl:SetPoint("RIGHT", page, "RIGHT")
	local note = UI.Text(page, "The companion uploads your save whenever the game writes it (at /reload or logout) and brings everyone's prices into the game every hour. It needs nothing from you in game.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", tbl, "BOTTOMLEFT", 0, -10)
	note:SetPoint("RIGHT", page, "RIGHT")

	function page:Refresh()
		local st = ns.Prices.status(GoldForever_Prices, ns.Prices.mine(), ns.now())
		local warn = Theme.escape(Theme.color.warning)
		if st.state == "ok" then
			head:SetText("Connected: the companion's prices are loaded")
			icon:SetTone("accent")
			line:SetText(#st.missing > 0 and (warn .. "No prices yet for " .. table.concat(st.missing, ", ") .. ": the pool fills as players scan there.|r")
				or "Everyone's prices show in your tooltips and the auction panel.")
		elseif st.state == "missing" then
			head:SetText(warn .. "No companion data in the game|r")
			icon:SetTone(Theme.color.warning)
			line:SetText("The companion app writes the GoldForever_Data addon; start it, then restart the game. Get it at gold-forever.app/companion.")
		elseif st.state == "version" then
			head:SetText(warn .. "The companion's file is a newer version|r")
			icon:SetTone(Theme.color.warning)
			line:SetText("Update the addon to read it.")
		else
			head:SetText(warn .. "The companion's file cannot be read|r")
			icon:SetTone(Theme.color.warning)
			line:SetText("The companion writes it again at its next update.")
		end
		local mine
		for _, m in ipairs(st.markets) do
			if m.mine and not mine then
				mine = m
			end
		end
		cards[1]:Set(st.age or "—", st.state == "ok" and "the prices file" or "")
		cards[2]:Set(tostring(#st.markets), "in the file")
		cards[3]:Set(mine and tostring(mine.items) or "—", mine and "items priced" or "none yet")
		tbl:SetRows(st.markets)
	end
end

ns.hubPages.companion = buildCompanion
