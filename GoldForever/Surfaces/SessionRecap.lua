-- Gold Forever: the card that says what a farming session came to when it closes (15 minutes without loot,
-- or Stop). It waits out combat, closes on a click or after 30 seconds, and the HUD reopens it until the next
-- session starts. Nothing is recorded.

local _, ns = ...
local L = ns.L
local Session = ns.Session

local Recap = {}
ns.SessionRecap = Recap

local SHORTEST = 5 * 60 -- a shorter session earns no card
local OPEN_SECONDS = 30
local POLL_SECONDS = 5 -- nothing announces a session going idle
local W, H = 360, 214
local ROWS = { L["Time"], L["Gold looted"], L["Items, at what they sell for"], L["Gold an hour"], L["Kills"], L["Best drop"] }

local running -- the session under way; kept because Session.get gives nothing for a short one once it ends
local ticker
local latest -- what the HUD reopens
local waiting -- a recap held back by combat
local showing -- the recap on the card
local opened = 0 -- which opening the 30 seconds belong to

local function settings()
	return ns.settings("appraiser")
end

-- A closed session in figures. Taken from the session itself: by now the next one may have replaced it.
function Recap.of(session, worth)
	local value, best = 0, nil
	for id, n in pairs(session.items) do
		local stack = (worth(id) or 0) * n
		value = value + stack
		if stack > 0 and (not best or stack > best.value or (stack == best.value and id < best.id)) then
			best = { id = id, n = n, value = stack }
		end
	end
	local elapsed = session.last - session.start
	return {
		elapsed = elapsed, coin = session.coin, value = value, kills = session.kills, best = best,
		goldPerHour = ns.Views.sessionRates(session, elapsed, value).goldPerHour,
		looted = session.coin > 0 or next(session.items) ~= nil,
	}
end

function Recap.earned(recap)
	return recap.looted and recap.elapsed >= SHORTEST
end

local function bestDrop(best)
	local Theme, UI = ns.Theme, ns.UI
	if not best then
		return Theme.escape(Theme.color.textFaint) .. L["nothing priced"] .. "|r"
	end
	local quality, name = ns.sessionItem(best.id)
	local color = Theme.quality[quality or 1] or Theme.color.text
	local count = best.n > 1 and (" x" .. best.n) or ""
	return Theme.escape(color) .. (name or string.format(L["item %d"], best.id)) .. "|r" .. count .. "  " .. UI.layout.money(best.value, "gold")
end

local function fill(card, r)
	local UI, Views = ns.UI, ns.Views
	card.values[1]:SetText(Views.duration(r.elapsed))
	card.values[2]:SetText(UI.layout.money(r.coin))
	card.values[3]:SetText(UI.layout.money(r.value))
	card.values[4]:SetText(UI.layout.money(r.goldPerHour, "gold"))
	card.values[5]:SetText(tostring(r.kills))
	card.values[6]:SetText(bestDrop(r.best))
end

local function hide()
	showing = nil
	opened = opened + 1 -- a timer still running belongs to no opening now
	if Recap.cards.frame then
		Recap.cards.frame:Hide()
	end
end

local function build()
	local Theme, UI = ns.Theme, ns.UI
	local card = UI.Panel(UIParent, { color = Theme.color.surface, alpha = 0.96, borderColor = Theme.color.borderStrong })
	card:SetSize(W, H)
	card:SetFrameStrata("DIALOG")
	card:SetClampedToScreen(true)
	card:SetPoint("TOP", UIParent, "TOP", 0, -170)
	card:Hide()
	card.hit = CreateFrame("Button", nil, card)
	card.hit:SetAllPoints()
	card.hit:SetScript("OnClick", hide)
	local title = UI.Text(card.hit, Theme.skin.titleCaps and L["SESSION RECAP"] or L["Session recap"], { size = "lg", medium = true })
	title:SetPoint("TOPLEFT", 16, -14)
	card.values = {}
	for i, label in ipairs(ROWS) do
		local l = UI.Text(card.hit, label, { size = "sm", tone = "muted" })
		l:SetPoint("TOPLEFT", 16, -24 - i * 20)
		local v = UI.Text(card.hit, "", { size = "sm", align = "RIGHT" })
		v:SetPoint("TOPRIGHT", -16, -24 - i * 20)
		v:SetWidth(i == #ROWS and W - 100 or W - 200) -- the best drop has a short label and a long value
		card.values[i] = v
	end
	local foot = UI.Text(card.hit, L["See it on the map: goldforever site > Sessions"], { size = "xs", tone = "faint" })
	foot:SetPoint("BOTTOMLEFT", 16, 14)
	return card
end

Recap.cards = ns.UI.perLook(build, function(card)
	fill(card, showing)
end)
Recap.cards:onLook("session recap")

local function open(recap)
	local card = Recap.cards:get()
	showing = recap
	fill(card, recap)
	card:Show()
	opened = opened + 1
	local this = opened
	ns.after(OPEN_SECONDS, "session recap", function()
		if this == opened then
			hide()
		end
	end)
end

local function showWaiting()
	local recap = waiting
	waiting = nil
	if recap and settings().recap ~= false then
		open(recap)
	end
end

local function showWhenOutOfCombat(recap)
	waiting = recap
	ns.afterCombat("session recap", showWaiting)
end

local function close(session)
	local recap = Recap.of(session, ns.price.worth)
	if Recap.earned(recap) then
		latest = recap
		showWhenOutOfCombat(recap)
	end
end

-- Whether the session seen running has closed, or a new one has begun; a new one ends the reopening.
local function check()
	local now = not Session.idle() and Session.get() or nil
	if now == running then
		return
	end
	local was = running
	running = now
	if was then
		close(was)
	end
	if now then
		latest = nil
	end
end

-- The clock is only watched while a session runs.
local function checkAndPoll()
	check()
	if running and not ticker then
		ticker = C_Timer.NewTicker(POLL_SECONDS, function()
			ns.safely("session recap", checkAndPoll)
		end)
	elseif ticker and not running then
		ticker:Cancel()
		ticker = nil
	end
end

-- "New session" throws the session away: nothing closed, so no card, and nothing left to reopen.
local function changed(how)
	if how == "reset" then
		running, latest, waiting = nil, nil, nil
		hide()
	end
	checkAndPoll()
end

Session.watch(function(how)
	ns.safely("session recap", changed, how)
end)

ns.on("PLAYER_REGEN_DISABLED", "session recap", hide)

function Recap.available()
	return latest ~= nil and settings().recap ~= false
end

function Recap.reopen()
	if Recap.available() then
		showWhenOutOfCombat(latest)
	end
end
