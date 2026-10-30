-- Gold Forever: game knowledge (as Knowledge.lua): the client's API, its game rules and the Legacy
-- perks, which exist nowhere else once WoW: Forever is gone.

local _, ns = ...

-- Client API -------------------------------------------------------------------------------------

-- The names of every C_ namespace's functions, once per client build: Forever-only APIs (Legacy
-- perks, for one) can then be found after the client is gone.
local function dumpApi()
	local db = ns.db()
	local build = db.client and db.client.build
	if db.api and db.api.build == build then
		return
	end
	local api = { build = build, namespaces = {}, globals = {} }
	for name, value in pairs(_G) do
		if type(name) == "string" then
			if type(value) == "table" and string.find(name, "^C_") then
				local functions = {}
				-- A protected namespace may refuse to be walked; skip it, keep the rest.
				pcall(function()
					for key, v in pairs(value) do
						if type(v) == "function" then
							functions[#functions + 1] = key
						end
					end
				end)
				table.sort(functions)
				api.namespaces[name] = table.concat(functions, " ")
			elseif type(value) == "function" and (string.find(name, "Legacy") or string.find(name, "Forever")
				or string.find(name, "Favor")) then
				api.globals[#api.globals + 1] = name
			end
		end
	end
	table.sort(api.globals)
	api.globals = table.concat(api.globals, " ")
	if Enum then
		local enums = {}
		for name in pairs(Enum) do
			enums[#enums + 1] = name
		end
		table.sort(enums)
		api.enums = table.concat(enums, " ")
	end
	db.api = api
end

-- Game rules -------------------------------------------------------------------------------------

-- A plain copy of an API result, depth- and size-limited, for the saved file.
local function copy(value, depth)
	if type(value) ~= "table" then
		if type(value) == "function" or type(value) == "userdata" or type(value) == "thread" then
			return type(value)
		end
		return value
	end
	if depth <= 0 then
		return "..."
	end
	local out, n = {}, 0
	for k, v in pairs(value) do
		n = n + 1
		if n > 200 then
			break
		end
		if type(k) == "string" or type(k) == "number" then
			out[k] = copy(v, depth - 1)
		end
	end
	return out
end

local function call(fn, ...)
	if type(fn) ~= "function" then
		return nil
	end
	local results = { pcall(fn, ...) }
	if not results[1] then
		return nil
	end
	table.remove(results, 1)
	if #results <= 1 then
		return copy(results[1], 4)
	end
	return copy(results, 4)
end

-- The realm's ruleset and Forever's settings, per character since realms differ (checklist #8).
local function readGameRules()
	local me = ns.me()
	local rules = C_GameRules
	if not me or not rules then
		return
	end
	local active = {}
	for name, id in pairs(Enum and Enum.GameRule or {}) do
		local ok, on = pcall(rules.IsGameRuleActive, id)
		if ok and on then
			local okValue, value = pcall(rules.GetGameRuleAsFloat, id)
			active[name] = okValue and value or true
		end
	end
	me.gameRules = {
		t = ns.now(),
		mode = call(rules.GetActiveGameMode),
		modeRecord = call(rules.GetCurrentGameModeRecordID),
		modeInfo = call(rules.GetCurrentGameModeDisplayInfo),
		foreverExperience = call(rules.GetForeverExperiencePreset),
		hardcore = call(rules.IsHardcoreActive),
		selfFound = call(rules.IsSelfFoundAllowed),
		standard = call(rules.IsStandard),
		rulesets = C_Roleset and call(C_Roleset.GetActiveAllowedRolesets) or nil,
		active = active,
	}
end

-- The API and the game rules are read again after every loading screen.
ns.module("KnowledgeClient", {
	requires = { "Store" },
	world = function()
		ns.after(10, "api", dumpApi)
		ns.after(6, "gameRules", readGameRules)
	end,
})

-- Legacy perks ------------------------------------------------------------------------------------

-- No API is named for Legacy, so /gf legacy finds it: every C_ function is watched (hooksecurefunc
-- does not taint), the Legacy window is opened, and the read-only functions only the window calls
-- are called again with the same arguments and their results kept. Watching stays on until the
-- next /reload.
local hooked = false
local phase -- "before" while measuring the background, "open" while the window is open
local seen = {} -- "C_X.Fn" -> { phase, args }

local function hookAll()
	if hooked then
		return
	end
	hooked = true
	for name, namespace in pairs(_G) do
		if type(name) == "string" and string.find(name, "^C_") and type(namespace) == "table" then
			local functions = {}
			pcall(function()
				for fn, f in pairs(namespace) do
					if type(f) == "function" then
						functions[#functions + 1] = fn
					end
				end
			end)
			for _, fn in ipairs(functions) do
				local key = name .. "." .. fn
				pcall(hooksecurefunc, namespace, fn, function(...)
					if phase and not seen[key] then
						seen[key] = { phase = phase, args = { ... } }
					end
				end)
			end
		end
	end
end

local function finishTrace()
	phase = nil
	local found = {}
	for key, s in pairs(seen) do
		if s.phase == "open" then
			local namespace, fn = string.match(key, "^([^.]+)%.(.+)$")
			local entry = { args = copy(s.args, 3) }
			if string.find(fn, "^Get") or string.find(fn, "^Is") or string.find(fn, "^Has") or string.find(fn, "^Can") then
				entry.result = call(_G[namespace][fn], unpack(s.args))
			end
			found[key] = entry
		end
	end
	ns.db().legacyTrace = { t = ns.now(), calls = found }
	local n = 0
	for _ in pairs(found) do
		n = n + 1
	end
	ns.say(string.format("the Legacy window called %d functions; saved. /reload to stop watching.", n))
end

ns.commands.legacy = function()
	hookAll()
	seen = {}
	phase = "before"
	ns.say("watching the API for 3 s, then opening the Legacy window...")
	ns.after(3, "legacy", function()
		phase = "open"
		if not pcall(ToggleLegacySystemUI) and LegacySystemFrame_LoadUI then
			pcall(LegacySystemFrame_LoadUI)
			pcall(ToggleLegacySystemUI)
		end
		ns.say("open the Legacy window if it did not open, and click through its pages - 20 s.")
		ns.after(20, "legacy", finishTrace)
	end)
end
