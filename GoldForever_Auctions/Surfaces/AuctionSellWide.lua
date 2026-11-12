-- Gold Forever: the Sell tab's wide box (addon#91), beside the list: the place to decide and post. The
-- chosen item; the price it posts at in large type and why; floor, typical and cheapest other; quantity,
-- duration and a full-width Post; then the item's listings as a table in the height left. AuctionSell.lua
-- places it and hands it what posting needs; the texts below are pure, so the tests read them.

local _, ns = ...
local L = ns.L
local Theme, UI = ns.Theme, ns.UI

local Wide = {}
ns.AuctionSellWide = Wide

local IN = 14 -- the box's inner inset
local ICON = 36
local SIDE = 210 -- the name's room left for Cancel, Narrow and Rule beside it
local DEPOSIT = 110 -- the deposit at the note line's right
local ALL = 100 -- Post all, beside Post
local LIST_TOP = 256 -- the listings' heading, from the box's top
local LIST_HEADING = 18
local LIST_HEADER = 22
local LIST_ROW = 20
local LIST_BOTTOM = 10
local DURATION = { width = 44, height = 24, step = 48 }
local DURATIONS = { { value = 1, label = string.format(L["%dh"], 12) }, { value = 2, label = string.format(L["%dh"], 24) }, { value = 3, label = string.format(L["%dh"], 48) } }

local function money(copper)
	return ns.Money.format(copper, "colour")
end

local function tint(tone, text)
	return Theme.escape(Theme.color[tone]) .. text .. "|r"
end

-- Where the box's parts go in a box `width` by `height`: the widths that would otherwise run into each
-- other, and the listing rows the height leaves.
function Wide.geometry(width, height)
	local inner = width - 2 * IN
	local listHeight = height - LIST_TOP - LIST_BOTTOM - LIST_HEADING - LIST_HEADER
	return {
		inner = inner,
		name = inner - ICON - 10 - SIDE,
		fact = math.floor(inner / 3),
		slider = inner - 70 - (3 * DURATION.step + 22),
		note = inner - DEPOSIT,
		rows = math.max(0, math.floor(listHeight / LIST_ROW)),
	}
end

-- A book's levels ({ unitPrice, quantity, own }, cheapest first) as the table's lines: gear's auctions of
-- one price and stack size on one line, counted; a commodity's by price, its quantity summed. Also the
-- number of prices and of units for sale.
function Wide.lines(levels, commodity)
	local out, prices, units, lastUnit = {}, 0, 0, nil
	for _, l in ipairs(levels or {}) do
		local own = (l.own or 0) > 0
		local stack = not commodity and l.quantity or nil
		local adds = commodity and l.quantity or 1
		local last = out[#out]
		if last and last.unit == l.unitPrice and last.stack == stack and last.own == own then
			last.count = last.count + adds
		else
			out[#out + 1] = { unit = l.unitPrice, stack = stack, count = adds, own = own }
		end
		if l.unitPrice ~= lastUnit then
			prices, lastUnit = prices + 1, l.unitPrice
		end
		units = units + l.quantity
	end
	return out, prices, units
end

function Wide.heading(prices, units)
	return ns.plural(prices, L["LISTINGS · %d PRICE · %d FOR SALE"], L["LISTINGS · %d PRICES · %d FOR SALE"], units)
end

local BADGES = {
	undercut = { label = L["Undercut"], tone = "accent" }, alone = { label = L["No one else"], tone = "success" },
	maximum = { label = L["At the maximum"], tone = "info" }, floor = { label = L["At floor"], tone = "warning" },
	hold = { label = L["Hold"], tone = "danger" },
}

-- The reason as a badge: { label, tone }; a sale plan's step by its own label. Nil with no price.
function Wide.badge(sug)
	if not sug then
		return nil
	end
	if sug.reason == "plan" then
		return { label = sug.label or L["Plan"], tone = sug.unit and "accent" or "warning" }
	end
	return BADGES[sug.reason]
end

local function because(r, sug)
	local reason = sug.reason
	if reason == "undercut" and r.cheapest and sug.unit then
		return string.format(L["%s under the cheapest other listing, above your floor."], money(r.cheapest - sug.unit))
	elseif reason == "alone" then
		return sug.day and L["No one else lists it: today's price."] or L["No one else lists it: your normal price."]
	elseif reason == "maximum" then
		return string.format(L["The others ask more than %sx the market: posted at the maximum."], tostring(sug.times))
	elseif reason == "floor" then
		return L["An undercut would go under your floor: posted at the floor."]
	elseif reason == "hold" then
		return (sug.floorBy == "vendor" and L["The cheapest other is under the vendor price after the cut: held."] or L["The cheapest other is under your floor: held."])
			.. (r.anyway and string.format(L[" Anyway: %s."], money(r.anyway)) or "")
	end
	return (sug.label or L["The sale plan's step"]) .. "."
end

-- A commodity's live price counts the account's alts' listings as others' (gf#375): its search results
-- name no sellers. The note saying so, else nil.
function Wide.altsNote(r)
	return r.commodity and r.cheapestFrom == "live" and L["Commodity results name no sellers: your alts' listings count as others'."] or nil
end

-- Why the price is what it is, in a sentence, and the post size's reason (gf#368); until the live
-- search answers, that it is searching (a price from the last scan is never posted).
function Wide.why(r)
	local sug = r.suggestion
	if not sug then
		return L["No price yet: scan first."]
	end
	if sug.estimate then
		return L["Searching the auction house for the live price..."]
	end
	local note = Wide.altsNote(r)
	return because(r, sug) .. (r.sizeReason and string.format(L[" Posting %s."], r.sizeReason) or "") .. (note and (" " .. note) or "")
end

-- The price line: the unit price, or Held under the floor; nil with no price.
function Wide.price(r)
	local sug = r.suggestion
	if sug and sug.unit then
		return { text = money(sug.unit) }
	end
	if sug and (r.anyway or sug.reason == "hold") then
		return { held = true }
	end
	return nil
end

-- The Post button: { label, kind, enabled }. Held under the floor it is the plain one, Post anyway, and
-- once pressed (`armed`) it asks for the second press.
function Wide.button(r, quantity, armed, busy)
	local sug = r and r.suggestion
	if sug and sug.estimate then
		return { label = L["Searching..."], kind = "primary", enabled = false }
	end
	if sug and sug.unit then
		return { label = string.format(L["Post %d x %s"], quantity, money(sug.unit)), kind = "primary", enabled = not busy }
	end
	if sug and r.anyway then
		local what = string.format("%d x %s", quantity, money(r.anyway))
		return { label = armed and string.format(L["Press again: post %s"], what) or string.format(L["Post anyway: %s"], what), kind = "default", enabled = not busy }
	end
	return { label = sug and sug.reason == "hold" and L["Under your floor"] or L["Post"], kind = "primary", enabled = false }
end

-- The note line after the first press of Post anyway.
function Wide.underFloor(r)
	return string.format(L["Under your floor of %s."], money(r.suggestion.floor or 0))
end

-- Drawing ----------------------------------------------------------------------------------------------

-- A caps xs label over a value in md, a third of the content wide.
local function fact(box, x, label, width)
	local head = UI.Text(box, ns.upper(label), { size = "xs", tone = "faint" })
	head:SetPoint("TOPLEFT", x, -124)
	head:SetWidth(width - 8)
	local value = UI.Text(box, "", { size = "md" })
	value:SetPoint("TOPLEFT", x, -137)
	value:SetWidth(width - 8)
	return value
end

-- The listings table: a header and as many rows of text as the height leaves, paged by the wheel.
local function listings(box)
	local heading = UI.Text(box, L["LISTINGS"], { size = "xs", tone = "faint" })
	heading:SetPoint("TOPLEFT", IN, -LIST_TOP)
	local t = UI.Panel(box, { color = Theme.color.surface })
	t:SetPoint("TOPLEFT", IN, -(LIST_TOP + LIST_HEADING))
	t:SetPoint("BOTTOMRIGHT", -IN, LIST_BOTTOM)
	local header = UI.solid(t, "BORDER", Theme.color.surfaceRaised)
	header:SetPoint("TOPLEFT", 1, -1)
	header:SetPoint("TOPRIGHT", -1, -1)
	header:SetHeight(LIST_HEADER - 1)
	local function column(parent, x, width, align, size, y)
		local fs = UI.Text(parent, "", { size = size, tone = size == "xs" and "muted" or nil, align = align })
		fs:SetPoint("TOPLEFT", x, y)
		fs:SetWidth(width)
		return fs
	end
	t.heads = { price = column(t, 10, 140, "LEFT", "xs", -5), mid = column(t, 160, 70, "RIGHT", "xs", -5), right = column(t, 240, 70, "RIGHT", "xs", -5) }
	t.heads.price:SetText(L["PRICE EACH"])
	t.empty = UI.Text(t, "", { size = "sm", tone = "faint" })
	t.empty:SetPoint("TOPLEFT", 10, -(LIST_HEADER + 4))
	t.rows, t.offset, t.lines = {}, 0, {}
	local function row(n)
		local r = t.rows[n]
		if r then
			return r
		end
		local y = -(LIST_HEADER + (n - 1) * LIST_ROW + 4)
		r = { price = column(t, 10, 140, "LEFT", "sm", y), mid = column(t, 160, 70, "RIGHT", "sm", y), right = column(t, 240, 70, "RIGHT", "sm", y) }
		r.yours = UI.Text(t, "", { size = "xs", tone = "accent", align = "RIGHT" })
		r.yours:SetPoint("TOPRIGHT", -10, y)
		r.yours:SetWidth(60)
		t.rows[n] = r
		return r
	end
	function t:Draw(lines, commodity, empty, rows)
		self.lines, self.commodity, self.size = lines, commodity, rows
		self.offset = math.max(0, math.min(self.offset, #lines - rows))
		self.heads.mid:SetText(commodity and L["QUANTITY"] or L["STACK"])
		self.heads.right:SetText(commodity and "" or L["COUNT"])
		self.empty:SetText(#lines == 0 and empty or "")
		for n = 1, math.max(rows, #self.rows) do
			local r = row(n)
			local l = n <= rows and lines[self.offset + n]
			r.price:SetText(l and money(l.unit) or "")
			r.mid:SetText(l and tostring(commodity and l.count or l.stack) or "")
			r.right:SetText(l and not commodity and tostring(l.count) or "")
			r.yours:SetText(l and l.own and L["yours"] or "")
		end
	end
	t:EnableMouseWheel(true)
	t:SetScript("OnMouseWheel", function(self, delta)
		self.offset = self.offset - delta
		self:Draw(self.lines, self.commodity, "", self.size)
	end)
	t.heading = heading
	return t
end

-- The box: `act` is what posting needs from AuctionSell.lua: post(), toggle(), rule(), quantity(v),
-- duration(v) (each remembered for the chosen item).
function Wide.build(page, act)
	local box = UI.Panel(page, { color = Theme.color.surfaceRaised, borderColor = Theme.color.border })
	local g = Wide.geometry(416, 436)
	box.icon = box:CreateTexture(nil, "ARTWORK")
	box.icon:SetSize(ICON, ICON)
	box.icon:SetPoint("TOPLEFT", IN, -12)
	box.name = UI.Text(box, "", { size = "lg", medium = true })
	box.name:SetPoint("TOPLEFT", IN + ICON + 10, -12)
	box.name:SetWidth(g.name)
	box.sub = UI.Text(box, "", { size = "xs", tone = "muted" })
	box.sub:SetPoint("TOPLEFT", IN + ICON + 10, -32)
	box.sub:SetWidth(g.name)
	box.rule = UI.Button(box, L["Rule >"], act.rule, { width = 64, height = 22 })
	box.rule:SetPoint("TOPRIGHT", -IN, -12)
	box.layoutButton = UI.Button(box, L["Narrow"], act.toggle, { kind = "ghost", width = 64, height = 22 })
	box.layoutButton:SetPoint("TOPRIGHT", -(IN + 70), -12)
	box.cancelButton = UI.Button(box, L["Cancel >"], act.cancel, { kind = "ghost", width = 64, height = 22 })
	box.cancelButton:SetPoint("TOPRIGHT", -(IN + 140), -12)
	local divider = UI.solid(box, "BORDER", Theme.color.border)
	divider:SetPoint("TOPLEFT", IN, -52)
	divider:SetPoint("TOPRIGHT", -IN, -52)
	divider:SetHeight(UI.pixel())

	local postAt = UI.Text(box, L["POST AT"], { size = "xs", tone = "muted" })
	postAt:SetPoint("TOPLEFT", IN, -60)
	box.price = UI.Text(box, "", { size = "xxl", medium = true })
	box.price:SetPoint("TOPLEFT", IN, -74)
	box.price:SetWidth(g.inner - DEPOSIT)
	box.badges = {}
	box.why = UI.Text(box, "", { size = "sm", tone = "muted" })
	box.why:SetPoint("TOPLEFT", IN, -108)
	box.why:SetWidth(g.inner)
	box.floor = fact(box, IN, L["Floor"], g.fact)
	box.typical = fact(box, IN + g.fact, L["Typical"], g.fact)
	box.cheapest = fact(box, IN + 2 * g.fact, L["Cheapest other"], g.fact)
	box.supply = UI.Text(box, "", { size = "xs", tone = "muted" })
	box.supply:SetPoint("TOPLEFT", IN, -152)
	box.supply:SetWidth(g.inner)

	local qtyLabel = UI.Text(box, L["Quantity"], { size = "sm", tone = "muted" })
	qtyLabel:SetPoint("TOPLEFT", IN, -168)
	box.quantity = UI.Slider(box, 1, 2, 1, 1, act.quantity, tostring)
	box.quantity:SetPoint("TOPLEFT", IN + 70, -166)
	box.quantity:SetWidth(g.slider)
	box.one = UI.Text(box, "", { size = "sm" })
	box.one:SetPoint("TOPLEFT", IN + 70, -168)
	box.one:SetWidth(g.slider)
	-- Each duration a primary button (chosen) and a ghost one, the one that fits shown: a button's kind
	-- is set when it is made.
	box.durations = {}
	for k, d in ipairs(DURATIONS) do
		local x = -(IN + (#DURATIONS - k) * DURATION.step)
		local pair = {}
		for _, kind in ipairs({ "primary", "ghost" }) do
			local b = UI.Button(box, d.label, function()
				act.duration(d.value)
			end, { kind = kind, width = DURATION.width, height = DURATION.height })
			b:SetPoint("TOPRIGHT", x, -164)
			-- The classic look's buttons are all the game's own: the chosen one stays lit.
			if kind == "primary" and Theme.skin.buttonTemplate then
				b:LockHighlight()
			end
			pair[kind] = b
		end
		box.durations[d.value] = pair
	end
	-- Post, primary; Post anyway under the floor, the plain one. The same press either way.
	box.inner = g.inner
	box.post = UI.Button(box, L["Post"], act.post, { kind = "primary", width = g.inner, height = 32 })
	box.anyway = UI.Button(box, L["Post anyway"], act.post, { kind = "default", width = g.inner, height = 32 })
	for _, b in ipairs({ box.post, box.anyway }) do
		b:SetPoint("TOPLEFT", IN, -196)
	end
	-- Post all, beside Post while the post is a few days of supply of more held (gf#368).
	box.all = UI.Button(box, L["Post all"], act.postAll, { kind = "default", width = ALL, height = 32 })
	box.all:SetPoint("TOPRIGHT", -IN, -196)
	box.all:Hide()
	box.hint = UI.Text(box, L["Space posts · one press, one post"], { size = "xs", tone = "faint" })
	box.hint:SetPoint("TOPLEFT", IN, -234)
	box.hint:SetWidth(g.note)
	box.deposit = UI.Text(box, "", { size = "xs", tone = "muted", align = "RIGHT" })
	box.deposit:SetPoint("TOPRIGHT", -IN, -234)
	box.deposit:SetWidth(DEPOSIT)
	box.listings = listings(box)

	-- The badge for a reason, made once per label and tone.
	local function badge(b)
		box.badge = b
		for _, f in pairs(box.badges) do
			f:Hide()
		end
		if not b then
			return
		end
		local key = b.label .. ":" .. b.tone
		local f = box.badges[key]
		if not f then
			f = UI.Badge(box, b.label, Theme.color[b.tone])
			f:SetPoint("TOPRIGHT", -IN, -80)
			box.badges[key] = f
		end
		f:Show()
	end

	-- The note line: where the panel's messages go; the hint while there is none. The page's own note,
	-- moved into the box so the box's background does not cover it.
	function box.placeNote(note)
		note:SetParent(box)
		note:SetPoint("TOPLEFT", box, "TOPLEFT", IN, -234)
		note:SetWidth(g.note)
		note:SetWordWrap(false)
	end

	-- `v`: the chosen row and what goes with it: { r, quantity, duration, armed, busy, live, levels,
	-- deposit, note, all (Post all offered) }.
	function box:Draw(v)
		local r = v.r
		local faint = Theme.escape(Theme.color.textFaint)
		self.hint:SetShown((v.note or "") == "")
		if not r then
			self.icon:SetTexture(nil)
			self.name:SetText(faint .. L["Choose an item."] .. "|r")
			self.sub:SetText("")
			self.price:SetText("")
			self.why:SetText("")
			self.supply:SetText("")
			badge(nil)
			self.post:Show()
			self.anyway:Hide()
			self.all:Hide()
			self.post:SetWidth(self.inner)
			self.post:SetLabel(L["Post"])
			self.post:SetEnabled(false)
			return
		end
		local sug = r.suggestion
		self.icon:SetTexture(r.icon)
		self.name:SetText(Theme.escape(Theme.quality[r.quality] or Theme.color.text) .. r.name .. "|r")
		self.sub:SetText(string.format(L["%d in bags · %s"], r.count, r.commodity and L["all at one price"] or L["one at a time"]))
		local p = Wide.price(r)
		self.price:SetText(p and (p.held and tint("warning", L["Held"]) or (p.text .. faint .. L[" each"] .. "|r")) or (faint .. "-|r"))
		badge(Wide.badge(sug))
		self.why:SetText(Wide.why(r))
		self.supply:SetText(r.supplyLine or "")
		self.floor:SetText(sug and money(sug.floor) or (faint .. "-|r"))
		self.typical:SetText(r.typical and money(r.typical) or (faint .. "-|r"))
		self.cheapest:SetText(not v.live and (faint .. L["searching..."] .. "|r") or r.cheapest and money(r.cheapest) or tint("success", L["nobody"]))
		local many = r.commodity and r.count > 1
		self.quantity:SetShown(many)
		self.one:SetShown(not many)
		if many then
			self.quantity:SetRange(1, r.count)
			self.quantity:Set(v.quantity)
		else
			self.one:SetText(r.commodity and "1" or L["1 (one at a time)"])
		end
		for value, pair in pairs(self.durations) do
			pair.primary:SetShown(value == v.duration)
			pair.ghost:SetShown(value ~= v.duration)
		end
		local b = Wide.button(r, v.quantity, v.armed, v.busy)
		self.all:SetShown(v.all and true or false)
		self.post:SetWidth(v.all and (self.inner - ALL - 6) or self.inner)
		local shown = b.kind == "primary" and self.post or self.anyway
		self.post:SetShown(shown == self.post)
		self.anyway:SetShown(shown == self.anyway)
		shown:SetLabel(b.label)
		shown:SetEnabled(b.enabled)
		self.deposit:SetText(v.deposit and string.format(L["Deposit %s"], money(v.deposit)) or "")
		local lines, prices, units = Wide.lines(v.levels, r.commodity)
		local rows = Wide.geometry(416, (self:GetHeight() or 0) > 0 and self:GetHeight() or 436).rows
		self.listings.heading:SetText(v.levels and Wide.heading(prices, units) or L["LISTINGS"])
		self.listings:Draw(lines, r.commodity, v.levels and L["No one lists it."] or L["Searching..."], rows)
	end
	return box
end
