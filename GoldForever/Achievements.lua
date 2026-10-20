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

-- Every statistic's value for this character, raw as the client shows it ("12", money with
-- texture codes, "--" for none).
local function readStatistics()
	local me = ns.me()
	if not me or not GetStatisticsCategoryList then
		return
	end
	local names = ns.db().catalogue.statistics
	local values = {}
	for _, category in ipairs(GetStatisticsCategoryList() or {}) do
		local group = categoryName(category)
		for i = 1, GetCategoryNumAchievements(category) or 0 do
			local id, name = GetAchievementInfo(category, i)
			if id then
				values[id] = GetStatistic(id)
				names[id] = Encode.row(text(name), group)
			end
		end
	end
	values.t = ns.now()
	me.statistics = values
end

-- Every achievement: the catalogue, and which ones are earned (account-wide), with the date.
local function readAchievements()
	if not GetCategoryList then
		return
	end
	local db = ns.db()
	local catalogue = db.catalogue.achievements
	local earned = {}
	for _, category in ipairs(GetCategoryList() or {}) do
		local group = categoryName(category)
		for i = 1, GetCategoryNumAchievements(category, true) or 0 do
			local id, name, points, completed, month, day, year, description, _, icon, reward = GetAchievementInfo(category, i)
			if id then
				catalogue[id] = Encode.row(text(name), points, group, icon, text(description), text(reward))
				if completed then
					earned[#earned + 1] = string.format("%d:20%02d-%02d-%02d", id, year or 0, month or 0, day or 0)
				end
			end
		end
	end
	table.sort(earned)
	db.account = db.account or {}
	-- "id:YYYY-MM-DD", comma-joined.
	db.account.achievements = { earned = table.concat(earned, ","), points = GetTotalAchievementPoints and GetTotalAchievementPoints() or nil, t = ns.now() }
end

ns.on("PLAYER_ENTERING_WORLD", "achievements", function()
	ns.after(12, "achievements", readAchievements)
	ns.after(14, "statistics", readStatistics)
end)
ns.on("ACHIEVEMENT_EARNED", "achievements", ns.throttle("achievements", 10, readAchievements))
ns.on("PLAYER_LOGOUT", "statistics", function()
	if not ns.tornDown() then
		readStatistics()
	end
end)
ns.on("CRITERIA_UPDATE", "statistics", ns.throttle("statistics", 60, readStatistics))
