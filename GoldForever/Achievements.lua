-- Gold Forever: achievements and statistics. Statistics are the character's lifetime totals
-- (gold looted, quests completed, kills, deaths, flights); achievements earn Legacy points.

local _, ns = ...
local Encode = ns.Encode

ns.FIELDS.achievement = "name,points,category,icon,description,reward"
ns.FIELDS.statistic = "name,category"

-- Free text in a catalogue row: no commas (columns), semicolons or line breaks.
local function text(s)
	if not s or s == "" then
		return nil
	end
	return (Encode.name(s):gsub(";", "."):gsub("[\r\n]+", " "))
end

local function categoryName(category)
	local name = GetCategoryInfo and GetCategoryInfo(category)
	return text(name)
end

-- A retail client has thousands of achievements and statistics, more than one frame may spend on: the
-- reads go entry by entry on the frame budget (a category a frame was too much for retail's largest
-- ones: "script ran too long", manual test run 001), then finish with `done`. count(category) is its
-- number of entries; perEntry(category, index, group) reads one, group the category's name.
local function eachEntry(name, categories, count, perEntry, done)
	local c, i, n, group = 1, 0, nil, nil
	local function step()
		local started, work = ns.frameStart(), 0
		while categories[c] ~= nil do
			local category = categories[c]
			if n == nil then
				n, group = count(category) or 0, categoryName(category)
			end
			i = i + 1
			if i > n then
				c, i, n = c + 1, 0, nil
			else
				perEntry(category, i, group)
				work = work + 1
				if ns.frameSpent(started, work, 100) then
					C_Timer.After(0, function()
						ns.safely(name, step)
					end)
					return
				end
			end
		end
		done()
	end
	step()
end

-- Every statistic's value for this character, raw as the client shows it ("12", money with
-- texture codes, "--" for none).
local reading -- when a statistics read started; one that failed halfway is let go after a minute
local function readStatistics()
	local me = ns.me()
	if not me or not GetStatisticsCategoryList or (reading and GetTime() - reading < 60) then
		return
	end
	local names = ns.db().catalogue.statistics
	local values = {}
	reading = GetTime()
	eachEntry("statistics", GetStatisticsCategoryList() or {}, GetCategoryNumAchievements, function(category, i, group)
		local id, name = GetAchievementInfo(category, i)
		if id then
			values[id] = GetStatistic(id)
			names[id] = Encode.row(text(name), group)
		end
	end, function()
		reading = nil
		values.t = ns.now()
		me.statistics = values
	end)
end

-- At logout there is no next frame: only the values of the statistics already read, one call each.
local function refreshStatistics()
	local me = ns.me()
	local values = me and me.statistics
	if not values or not GetStatistic then
		return
	end
	for id in pairs(values) do
		if id ~= "t" then
			values[id] = GetStatistic(id)
		end
	end
	values.t = ns.now()
end

-- Every achievement: the catalogue, and which ones are earned (account-wide), with the date.
local readingAchievements -- when a read started: one at a time (every loading screen asks), let go after a minute
local function readAchievements()
	if not GetCategoryList or (readingAchievements and GetTime() - readingAchievements < 60) then
		return
	end
	readingAchievements = GetTime()
	local db = ns.db()
	local catalogue = db.catalogue.achievements
	local earned = {}
	eachEntry("achievements", GetCategoryList() or {}, function(category)
		return GetCategoryNumAchievements(category, true)
	end, function(category, i, group)
		local id, name, points, completed, month, day, year, description, _, icon, reward = GetAchievementInfo(category, i)
		if id then
			if not ns.lean then
				catalogue[id] = Encode.row(text(name), points, group, icon, text(description), text(reward))
			end
			if completed then
				earned[#earned + 1] = string.format("%d:20%02d-%02d-%02d", id, year or 0, month or 0, day or 0)
			end
		end
	end, function()
		readingAchievements = nil
		table.sort(earned)
		db.account = db.account or {}
		-- "id:YYYY-MM-DD", comma-joined.
		db.account.achievements = { earned = table.concat(earned, ","), points = GetTotalAchievementPoints and GetTotalAchievementPoints() or nil, t = ns.now() }
	end)
end

ns.on("PLAYER_ENTERING_WORLD", "achievements", function()
	ns.after(12, "achievements", readAchievements)
	ns.after(14, "statistics", readStatistics)
end)
ns.on("ACHIEVEMENT_EARNED", "achievements", ns.throttle("achievements", 10, readAchievements))
ns.on("PLAYER_LOGOUT", "statistics", function()
	if not ns.tornDown() then
		refreshStatistics()
	end
end)
ns.on("CRITERIA_UPDATE", "statistics", ns.throttle("statistics", 60, readStatistics))
