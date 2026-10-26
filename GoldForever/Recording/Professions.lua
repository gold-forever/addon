-- Gold Forever: professions, known recipes and the recipe catalogue (design 002, State:
-- characters and catalogue). Recipes are only readable while the profession window is open.

local _, ns = ...
local Encode = ns.Encode

local BASIC = Enum and Enum.CraftingReagentType and Enum.CraftingReagentType.Basic
local SALVAGE = Enum and Enum.TradeskillRecipeType and Enum.TradeskillRecipeType.Salvage

-- Each retail salvage recipe's first input item, from the game data (the recipe's salvage effect and
-- the items that salvage takes). The client lists none for some of them (the refines, shatters,
-- Thaumaturgy), and may not call them salvage.
local SALVAGE_INPUT = {
	[374627] = 190395, [375731] = 193216, [375763] = 193217, [376562] = 193050, [376611] = 193208,
	[376612] = 193210, [376613] = 193213, [376614] = 193214, [382374] = 198651, [382981] = 191472,
	[388274] = 194785, [388280] = 194793, [388281] = 194809, [388282] = 194801, [391088] = 191460,
	[391089] = 191461, [395696] = 192852, [427174] = 210796, [430315] = 211802, [430345] = 210796,
	[434018] = 210930, [434020] = 213453, [438811] = 210796, [438812] = 210797, [440929] = 212670,
	[440934] = 212672, [440937] = 212664, [440938] = 212665, [440942] = 212667, [440943] = 212668,
	[444181] = 210796, [444224] = 222654, [444225] = 222654, [444226] = 222663, [444227] = 222681,
	[445117] = 210796, [445118] = 223512, [445119] = 223512, [445120] = 222720, [445127] = 220153,
	[445466] = 213611, [446926] = 224828, [447310] = 219150, [447311] = 4359, [447313] = 221871,
	[447869] = 223972, [447870] = 222708, [447871] = 223512, [462857] = 222732, [470726] = 219949,
	[1226167] = 242308, [1229930] = 243574, [1230078] = 245830, [1230079] = 251923,
	[1230080] = 245830, [1230081] = 251923, [1230082] = 245838, [1230083] = 251923,
	[1230084] = 245830, [1230085] = 251923, [1231127] = 237359, [1231132] = 242612,
	[1232247] = 242273, [1233129] = 241289, [1233130] = 241327, [1235731] = 236951,
	[1259655] = 238365, [1269575] = 236761, [1280394] = 243602, [1280401] = 243605,
	[1296449] = 275280, [1296450] = 275285,
}

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
	-- A salvage recipe has no reagent slots: it takes any one of its salvagable items, as many as
	-- quantityMax (the count the client's salvage slot asks for).
	local item = SALVAGE_INPUT[id]
	if SALVAGE and s.recipeType == SALVAGE and C_TradeSkillUI.GetSalvagableItemIDs then
		item = (C_TradeSkillUI.GetSalvagableItemIDs(id) or {})[1] or item
	end
	if item then
		reagents[tostring(item)] = s.quantityMax or 1
		ns.catalogueItem(item)
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

local function ids(list)
	return #list > 0 and table.concat(list, ", ") or "none"
end

-- For a bug report: what the client says of one recipe, and the catalogue row the reader makes of it.
ns.commands.recipeprobe = function(arg)
	local id = tonumber(arg)
	if not id or not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
		print(ns.PREFIX .. ": /gf recipeprobe <recipe ID>")
		return
	end
	local info = C_TradeSkillUI.GetRecipeInfo and C_TradeSkillUI.GetRecipeInfo(id) or {}
	local s = C_TradeSkillUI.GetRecipeSchematic(id, false) or {}
	print(ns.PREFIX .. ": recipe " .. id .. " " .. tostring(info.name))
	print(("type %s, salvage %s, output %s, %s-%s"):format(tostring(s.recipeType), tostring(info.isSalvageRecipe),
		tostring(s.outputItemID), tostring(s.quantityMin), tostring(s.quantityMax)))
	for i, slot in ipairs(s.reagentSlotSchematics or {}) do
		local items = {}
		for _, reagent in ipairs(slot.reagents or {}) do
			items[#items + 1] = reagent.itemID or ("currency " .. tostring(reagent.currencyID))
		end
		print(("slot %d: type %s, %s of %s"):format(i, tostring(slot.reagentType), tostring(slot.quantityRequired), ids(items)))
	end
	local salvagable = C_TradeSkillUI.GetSalvagableItemIDs and C_TradeSkillUI.GetSalvagableItemIDs(id)
	print("salvagable: " .. (salvagable and ids(salvagable) or "no API"))
	print("row: " .. tostring(schematic(id, lineOf(id), info.name)))
end

-- Skill-ups ---------------------------------------------------------------------------------------

local known -- skill line -> skill, to spot a rise
local lastSpell -- { id, at }: the player's last successful spell, the likely cause of a skill-up

local function skills()
	local out = {}
	if GetProfessions then
		local indices = { GetProfessions() }
		for i = 1, 5 do
			if indices[i] then
				local _, _, skill, max, _, _, line = GetProfessionInfo(indices[i])
				if line then
					out[line] = { skill = skill, max = max }
				end
			end
		end
	end
	return out
end

-- One row per rise, with the spell cast in the last 5 s (the recipe for a craft, the gathering
-- spell for a node) and, for gathering, the loot source opened in the last 5 s.
local function checkSkills()
	local me = ns.me()
	if not me then
		return
	end
	local now, current = GetTime(), skills()
	if known then
		for line, s in pairs(current) do
			local was = known[line]
			if was and s.skill > was then
				local spell = lastSpell and now - lastSpell.at < 5 and lastSpell.id or nil
				local t, map = ns.now(), C_Map.GetBestMapForUnit("player")
				-- The loot window of a gather opens a moment after the skill rises.
				ns.after(1, "skillup", function()
					local src = ns.lootAt and math.abs(GetTime() - ns.lootAt) < 5 and ns.lootSource or nil
					ns.append("skill", Encode.row(t, me.ref, line, s.skill, s.max, spell, src, map))
				end)
			end
		end
	end
	known = {}
	for line, s in pairs(current) do
		known[line] = s.skill
	end
end

ns.on("UNIT_SPELLCAST_SUCCEEDED", "skillup", function(unit, _, spell)
	if unit == "player" then
		lastSpell = { id = spell, at = GetTime() }
	end
end, "player")
ns.on("SKILL_LINES_CHANGED", "skillup", checkSkills)
ns.on("CHAT_MSG_SKILL", "skillup", checkSkills)
ns.on("PLAYER_LOGIN", "skillup", checkSkills)

ns.on("PLAYER_LOGIN", "skills", readSkills)
ns.on("SKILL_LINES_CHANGED", "skills", ns.throttle("skills", 2, readSkills))
ns.on("TRADE_SKILL_SHOW", "recipes", recipesSoon)
ns.on("TRADE_SKILL_LIST_UPDATE", "recipes", recipesSoon)
ns.on("TRADE_SKILL_DATA_SOURCE_CHANGED", "recipes", recipesSoon)
ns.on("NEW_RECIPE_LEARNED", "recipes", recipesSoon)
