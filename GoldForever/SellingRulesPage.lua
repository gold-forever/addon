-- Gold Forever: the hub's Selling rules page: the rule Sell prices by, its overrides for an item or a
-- category, and the sale profiles.

local _, ns = ...
local Theme, UI, Post = ns.Theme, ns.UI, ns.Post
local ah = ns.ah
local settings, activeProfile = ns.auctionSettings, ns.activeProfile
local stamp = ns.Lists.stamp
local money = ns.Money.auction

-- The selling rules, a page of the hub (manual test run 001: too much for the panel, and hard to read):
-- the rule's controls at the left, each saying what it does; at the right what the rule does to an item
-- worth 10g, and the sale profile.
local function buildRule(page)
	local s = settings()
	s.overrides = s.overrides or { items = {}, classes = {} }
	s.overrides.items = s.overrides.items or {}
	s.overrides.classes = s.overrides.classes or {}
	local LEFT, LABEL = 400, 130 -- the controls' column, and where a control starts in it
	local RIGHT = LEFT + 28 -- the column at the right starts here
	-- Which rule the controls below edit: the default, or an override (only the fields it changes).
	local scope = "default"
	local function className(class)
		local name = C_Item and C_Item.GetItemClassInfo and C_Item.GetItemClassInfo(class) or (GetItemClassInfo and GetItemClassInfo(class))
		return name or ("category " .. class)
	end
	local function target()
		local kind, id = string.match(scope, "^(%a+):(%d+)$")
		if kind == "item" then
			return s.overrides.items[tonumber(id)]
		elseif kind == "class" then
			return s.overrides.classes[tonumber(id)]
		end
		return s.rule
	end
	-- The values the controls show: the default's with the override's over them.
	local function shown()
		local t, out = target(), {}
		for k, v in pairs(s.rule) do
			out[k] = v
		end
		if t ~= s.rule then
			for k, v in pairs(t or {}) do
				out[k] = v
			end
		end
		return out
	end

	-- What the rule does, at the right.
	local exampleCard = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	exampleCard:SetPoint("TOPLEFT", RIGHT, 0)
	exampleCard:SetPoint("RIGHT", page, "RIGHT")
	exampleCard:SetHeight(196)
	local exampleHead = UI.Text(exampleCard, "WHAT IT DOES TO AN ITEM WORTH 10G", { size = "xs", medium = true, tone = "faint" })
	exampleHead:SetPoint("TOPLEFT", 14, -12)
	local exampleText = UI.Text(exampleCard, "", { size = "xs", wrap = true })
	exampleText:SetPoint("TOPLEFT", exampleHead, "BOTTOMLEFT", 0, -10)
	exampleText:SetPoint("RIGHT", exampleCard, "RIGHT", -14, 0)
	local function showExamples()
		local lines = Post.examples(shown(), money)
		for i, l in ipairs(lines) do
			lines[i] = Theme.escape(Theme.color.accent) .. "•|r " .. l
		end
		exampleText:SetText(table.concat(lines, "\n\n"))
	end

	local function set(field, v)
		local t = target()
		if t then
			t[field] = v
		end
		showExamples()
	end
	-- A row: its name, the control, and a line under them saying what it does.
	local function row(y, label, control, says)
		local l = UI.Text(page, label, { size = "sm" })
		l:SetPoint("TOPLEFT", 0, y)
		control:SetPoint("TOPLEFT", LABEL, y + 6)
		control:SetPoint("RIGHT", page, "LEFT", LEFT, 0)
		local line = UI.Text(page, says, { size = "xs", tone = "faint", wrap = true })
		line:SetPoint("TOPLEFT", 0, y - 32)
		line:SetWidth(LEFT)
		return control
	end
	local undercuts = {}
	for _, u in ipairs(Post.UNDERCUTS) do
		undercuts[#undercuts + 1] = { value = u.value, label = u.label }
	end
	local v = shown()
	local controls = {
		undercut = row(-84, "Undercut by", UI.Dropdown(page, undercuts, v.undercut, function(x) set("undercut", x) end),
			"How far under the cheapest other seller you post."),
		floor = row(-156, "Never under", UI.Slider(page, 50, 100, 5, v.floor, function(x) set("floor", x) end, function(x) return x .. "%" end),
			"Your floor, as a share of the market value: nothing posts below it."),
		normal = row(-228, "Normal price", UI.Slider(page, 100, 200, 5, v.normal, function(x) set("normal", x) end, function(x) return x .. "%" end),
			"What you ask when no one else sells it, or everyone asks more than this."),
		belowFloor = row(-300, "Under the floor", UI.Dropdown(page, { { value = "hold", label = "Hold it" }, { value = "floor", label = "Post at the floor" } }, v.belowFloor, function(x) set("belowFloor", x) end),
			"When undercutting would go under your floor: keep the item, or post at the floor anyway."),
	}
	local scopePick, removeButton
	local function pickOptions()
		local out = { { value = "default", label = "Every item" } }
		for id in pairs(s.overrides.items) do
			local _, _, _, _, name = ns.price.itemInfo(id)
			out[#out + 1] = { value = "item:" .. id, label = "Item: " .. (name or id) }
		end
		for class in pairs(s.overrides.classes) do
			out[#out + 1] = { value = "class:" .. class, label = "Category: " .. className(class) }
		end
		out[#out + 1] = { value = "add-item", label = "+ The item chosen in Sell" }
		out[#out + 1] = { value = "add-class", label = "+ Its category" }
		return out
	end
	local rebuildPick
	local function choose(value)
		if value == "add-item" or value == "add-class" then
			if not ah.chosen then
				value = "default"
			elseif value == "add-item" then
				s.overrides.items[ah.chosen.id] = s.overrides.items[ah.chosen.id] or {}
				value = "item:" .. ah.chosen.id
			else
				local _, _, class = ns.price.itemInfo(ah.chosen.id)
				if class then
					s.overrides.classes[class] = s.overrides.classes[class] or {}
					value = "class:" .. class
				else
					value = "default"
				end
			end
		end
		scope = value
		local now = shown()
		for field, c in pairs(controls) do
			c:Set(now[field])
		end
		removeButton:SetShown(scope ~= "default")
		rebuildPick()
		showExamples()
	end
	rebuildPick = function()
		if scopePick then
			scopePick:SetOptions(pickOptions())
			scopePick:Set(scope)
			return
		end
		scopePick = UI.Dropdown(page, pickOptions(), scope, choose)
		scopePick:SetPoint("TOPLEFT", LABEL, 6)
		scopePick:SetPoint("RIGHT", page, "LEFT", LEFT - 94, 0)
	end
	local pickLabel = UI.Text(page, "Rule for", { size = "sm" })
	pickLabel:SetPoint("TOPLEFT", 0, 0)
	removeButton = UI.Button(page, "Remove", function()
		local kind, id = string.match(scope, "^(%a+):(%d+)$")
		if kind == "item" then
			s.overrides.items[tonumber(id)] = nil
		elseif kind == "class" then
			s.overrides.classes[tonumber(id)] = nil
		end
		choose("default")
	end, { kind = "ghost", width = 86, height = 28 })
	removeButton:SetPoint("TOPRIGHT", page, "TOPLEFT", LEFT, 6)
	removeButton:Hide()
	rebuildPick()
	page.chooseScope = choose
	page.setField = set
	local scopeLine = UI.Text(page, "A rule for one item or a category changes only what you set for it; the rest comes from Every item.", { size = "xs", tone = "faint", wrap = true })
	scopeLine:SetPoint("TOPLEFT", 0, -34)
	scopeLine:SetWidth(LEFT)
	local note = UI.Text(page, "The market value is everyone's price from the companion, else your own last scan. Prices are whole silver.", { size = "xs", tone = "faint", wrap = true })
	note:SetPoint("TOPLEFT", 0, -376)
	note:SetWidth(LEFT)

	-- Sale profiles (GFP1 strings from the site or other players): one active at a time.
	s.profiles = s.profiles or {}
	local head = UI.Text(page, "SALE PROFILE", { size = "xs", medium = true, tone = "faint" })
	head:SetPoint("TOPLEFT", exampleCard, "BOTTOMLEFT", 0, -18)
	local pick
	local summary = UI.Text(page, "", { size = "xs", tone = "muted", wrap = true })
	local function options()
		local out = { { value = 0, label = "None: the rules" } }
		for i, p in ipairs(s.profiles) do
			out[#out + 1] = { value = i, label = p.name }
		end
		return out
	end
	local function describe()
		local p = activeProfile()
		summary:SetText(p and string.format("%s by %s: %d items to sell, %d to buy. The items it names follow it instead of the rules.", p.name, p.author ~= "" and p.author or "?", #p.sell, #p.buy)
			or "A profile from gold-forever.app/me/lists prices the items it names; the rules price the rest.")
	end
	local function rebuild()
		if pick then
			pick:SetOptions(options())
			pick:Set(s.profile or 0)
			describe()
			return
		end
		pick = UI.Dropdown(page, options(), s.profile or 0, function(v)
			s.profile = v ~= 0 and v or nil
			describe()
		end)
		pick:SetPoint("TOPLEFT", head, "BOTTOMLEFT", 0, -8)
		pick:SetPoint("RIGHT", page, "RIGHT")
		summary:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -8)
		summary:SetPoint("RIGHT", page, "RIGHT")
		describe()
	end
	rebuild()
	local field = UI.SearchBox(page, "Paste a GFP1 string", nil)
	field:SetMaxLetters(0) -- a profile string runs to 16 KB (SalePlan.decode bounds it)
	field:SetPoint("TOPLEFT", pick, "BOTTOMLEFT", 0, -48)
	field:SetPoint("RIGHT", page, "RIGHT", -152, 0)
	local message = UI.Text(page, "", { size = "xs", tone = "faint", wrap = true })
	message:SetPoint("TOPLEFT", field, "BOTTOMLEFT", 0, -6)
	message:SetPoint("RIGHT", page, "RIGHT")
	local function doImport(text)
		local p, err = ns.SalePlan.decode(text or field:GetText())
		if not p then
			message:SetText(Theme.escape(Theme.color.danger) .. err .. "|r")
			return
		end
		-- Decision 11: each profile has an id and an edited time, so a later sync keeps the newest.
		stamp(p)
		s.profiles[#s.profiles + 1] = p
		s.profile = #s.profiles
		field:SetText("")
		rebuild()
		message:SetText("Imported and in use.")
	end
	local import = UI.Button(page, "Import", function()
		doImport()
	end, { width = 72, height = 28 })
	import:SetPoint("LEFT", field, "RIGHT", 6, 0)
	local export = UI.Button(page, "Export", function()
		local p = activeProfile()
		if p then
			field:SetText(ns.SalePlan.encode(p))
			field:SetFocus()
			field:HighlightText()
			message:SetText("Copy it with Ctrl+C.")
		end
	end, { width = 72, height = 28 })
	export:SetPoint("LEFT", import, "RIGHT", 4, 0)
	page.importProfile = doImport
	showExamples()
	-- The newest drawn (the window in the look in use), for the Sell tab's Rule button and the tests.
	ns.rulesPage = page
	function page:Refresh()
		choose(scope) -- an override added or removed from the Sell tab shows
	end
end
ns.buildSellingRules = buildRule
