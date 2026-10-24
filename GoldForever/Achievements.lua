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
-- reads go a category a frame (the client stops a script that runs too long), then finish with `done`.
local function eachCategory(name, categories, perCategory, done)
	local i = 0
	local function step()
		i = i + 1
		local category = categories[i]
		if category == nil then
			done()
			return
		end
		perCategory(category)
		C_Timer.After(0, function()
			ns.safely(name, step)
		end)
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
	eachCategory("statistics", GetStatisticsCategoryList() or {}, function(category)
		local group = categoryName(category)
		for i = 1, GetCategoryNumAchievements(category) or 0 do
			local id, name = GetAchievementInfo(category, i)
			if id then
				values[id] = GetStatistic(id)
				names[id] = Encode.row(text(name), group)
			end
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
	eachCategory("achievements", GetCategoryList() or {}, function(category)
		local group = categoryName(category)
		for i = 1, GetCategoryNumAchievements(category, true) or 0 do
			local id, name, points, completed, month, day, year, description, _, icon, reward = GetAchievementInfo(category, i)
			if id then
				if not ns.lean then
					catalogue[id] = Encode.row(text(name), points, group, icon, text(description), text(reward))
				end
				if completed then
					earned[#earned + 1] = string.format("%d:20%02d-%02d-%02d", id, year or 0, month or 0, day or 0)
				end
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
