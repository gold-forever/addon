-- Gold Forever: the module lifecycle. A file declares its module with
-- ns.module(name, { requires = { names }, init = fn, enable = fn }) instead of setting itself up on
-- PLAYER_LOGIN in .toc order. The kernel (Core.lua) runs every init once the addon has loaded and every
-- enable once the player has logged in, each module after the ones it requires, otherwise in the order
-- declared. A module that fails is recorded (ns.fail) and the others still start; one that requires a
-- failed, missing or circular module does not start, and is recorded too.

local _, ns = ...

local modules, declared = {}, {} -- name -> module; the modules in the order the files declared them

function ns.module(name, def)
	if modules[name] then
		ns.fail(name, "module declared twice")
		return
	end
	local m = { name = name, requires = def.requires or {}, init = def.init, enable = def.enable }
	modules[name] = m
	declared[#declared + 1] = m
end

local function placeable(m, placed)
	for _, need in ipairs(m.requires) do
		if not placed[need] then
			return false
		end
	end
	return true
end

-- Whether `from` requires `to`, directly or through modules that are not placed.
local function reaches(from, to, placed, seen)
	for _, need in ipairs(from.requires) do
		local r = modules[need]
		if need == to.name then
			return true
		end
		if r and not placed[need] and not seen[need] then
			seen[need] = true
			if reaches(r, to, placed, seen) then
				return true
			end
		end
	end
	return false
end

-- Why a module left over by the ordering cannot start: its first requirement that is not placed.
local function unplaceable(m, placed)
	for _, need in ipairs(m.requires) do
		if not placed[need] then
			local r = modules[need]
			if not r then
				return "requires " .. need .. ", which no module declares"
			elseif reaches(r, m, placed, {}) then
				return "requires " .. need .. ", which requires it in turn"
			end
			return "requires " .. need .. ", which cannot start"
		end
	end
end

-- Every module after the ones it requires: each time the first declared that can go next. Those left over
-- are recorded as failed.
local order
local function ordered()
	if order then
		return order
	end
	order = {}
	local placed = {}
	local found = true
	while found do
		found = false
		for _, m in ipairs(declared) do
			if not placed[m.name] and placeable(m, placed) then
				placed[m.name], found = true, true
				order[#order + 1] = m
				break
			end
		end
	end
	for _, m in ipairs(declared) do
		if not placed[m.name] then
			m.failed = true
			ns.fail(m.name, unplaceable(m, placed))
		end
	end
	return order
end

-- Runs each module's `step` ("init" or "enable") in dependency order.
function ns.startModules(step)
	for _, m in ipairs(ordered()) do
		if not m.failed then
			for _, need in ipairs(m.requires) do
				if modules[need].failed and not m.failed then
					m.failed = true
					ns.fail(m.name, "requires " .. need .. ", which failed")
				end
			end
		end
		if not m.failed and m[step] and not ns.safely(m.name, m[step]) then
			m.failed = true
		end
	end
end
