-- Gold Forever: professions, known recipes and the recipe catalogue (design 002, State:
-- characters and catalogue). Recipes are only readable while the profession window is open.

local _, ns = ...
local Encode = ns.Encode

-- name is appended to design 002's columns: it lets the web app show recipes whose output is not
-- an item (enchants).
ns.FIELDS.recipe = "skillLine,output,min,max,reagents,name"

local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic

-- Current skill in a profession, by skill line.
function ns.skill(line)
	if GetProfessions then
		local indices = { GetProfessions() }
		for i = 1, 5 do
			if indices[i] then
				local _, _, skill, _, _, _, own = GetProfessionInfo(indices[i])
				if own == line then
					return skill
				end
			end
		end
	end
	return nil
end

local function readSkills()
	local me = ns.me()
	if not me then
		return
	end
	me.prof = me.prof or {}
	if GetProfessions then
		local indices = { GetProfessions() }
		for i = 1, 5 do
			local index = indices[i]
			if index then
				local name, _, skill, max, _, _, line = GetProfessionInfo(index)
				if line then
					local p = me.prof[line] or {}
					me.prof[line] = p
					p.name, p.skill, p.max, p.t = name, skill, max, ns.now()
				end
			end
		end
	end
	-- Classic-style skill list: no skill line IDs, but every skill including the secondary ones.
	if GetNumSkillLines and GetSkillLineInfo then
		local skills = {}
		for i = 1, GetNumSkillLines() do
			local name, header, _, skill, _, _, max = GetSkillLineInfo(i)
			if name and not header then
				skills[Encode.name(name)] = skill .. "/" .. max
			end
		end
		me.skills = skills
	end
end

-- The recipe's catalogue row: output and basic reagents, from its schematic.
local function schematic(id, line, name)
	local s = C_TradeSkillUI.GetRecipeSchematic(id, false)
	if not s then
		return nil
	end
	local reagents = {}
	for _, slot in ipairs(s.reagentSlotSchematics or {}) do
		local basic = BASIC == nil or slot.reagentType == BASIC
		local reagent = slot.reagents and slot.reagents[1]
		if basic and reagent and reagent.itemID then
			reagents[tostring(reagent.itemID)] = slot.quantityRequired or 1
			ns.catalogueItem(reagent.itemID)
		end
	end
	if s.outputItemID then
		ns.catalogueItem(s.outputItemID)
	end
	return Encode.row(line, s.outputItemID, s.quantityMin, s.quantityMax, Encode.items(reagents), name and Encode.name(name))
end

local catalogued = {} -- skill lines whose recipes were catalogued this session

-- The profession a recipe belongs to. Right after switching profession windows the client still
-- returns the previous profession's recipe list, so the open window's line cannot be trusted.
local function lineOf(id)
	if C_TradeSkillUI.GetTradeSkillLineForRecipe then
		local line, _, parent = C_TradeSkillUI.GetTradeSkillLineForRecipe(id)
		if parent and parent ~= 0 then
			return parent
		end
		if line and line ~= 0 then
			return line
		end
	end
	if C_TradeSkillUI.GetProfessionInfoByRecipeID then
		local info = C_TradeSkillUI.GetProfessionInfoByRecipeID(id)
		local line = info and (info.parentProfessionID or info.professionID)
		if line and line ~= 0 then
			return line
		end
	end
	return nil
end

local function readRecipes()
	local me = ns.me()
	if not me or not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs then
		return
	end
	if C_TradeSkillUI.IsTradeSkillLinked and C_TradeSkillUI.IsTradeSkillLinked() then
		return -- someone else's profession
	end
	if C_TradeSkillUI.IsTradeSkillGuild and C_TradeSkillUI.IsTradeSkillGuild() then
		return
	end
	local base = C_TradeSkillUI.GetBaseProfessionInfo and C_TradeSkillUI.GetBaseProfessionInfo()
	local line = base and base.professionID
	local ids = C_TradeSkillUI.GetAllRecipeIDs()
	if not line or not ids or #ids == 0 then
		return
	end

	local recipes = ns.db().catalogue.recipes
	local learned = {} -- skill line -> learned recipe IDs
	for _, id in ipairs(ids) do
		local info = C_TradeSkillUI.GetRecipeInfo(id)
		local own = lineOf(id) or line
		learned[own] = learned[own] or {}
		if info and info.learned then
			table.insert(learned[own], id)
		end
		if not catalogued[own] or not recipes[id] then
			ns.safely("recipe", function()
				recipes[id] = schematic(id, own, info and info.name) or recipes[id]
			end)
		end
	end
	-- Only the lines the list really belongs to; a stale list leaves the open line untouched.
	for own, list in pairs(learned) do
		catalogued[own] = true
		table.sort(list)
		local p = me.prof[own] or {}
		me.prof[own] = p
		p.recipes = table.concat(list, ",")
		p.t = ns.now()
		if own == line then
			p.name = p.name or base.professionName
			p.skill = base.skillLevel or p.skill
			p.max = base.maxSkillLevel or p.max
		end
	end
end

local recipesSoon = ns.throttle("recipes", 2, readRecipes)

ns.on("PLAYER_LOGIN", "skills", readSkills)
ns.on("SKILL_LINES_CHANGED", "skills", ns.throttle("skills", 2, readSkills))
ns.on("TRADE_SKILL_SHOW", "recipes", recipesSoon)
ns.on("TRADE_SKILL_LIST_UPDATE", "recipes", recipesSoon)
ns.on("TRADE_SKILL_DATA_SOURCE_CHANGED", "recipes", recipesSoon)
ns.on("NEW_RECIPE_LEARNED", "recipes", recipesSoon)
