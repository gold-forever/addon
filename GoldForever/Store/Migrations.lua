-- Gold Forever: the save's migrations (WeakAuras' "Modernize"). Add one for every change to a stream's columns
-- or to where the save keeps something: raise ns.SCHEMA (Schema.lua) by one and append
-- { from = old, to = old + 1, run = function(save) ... end }, which turns a save at `from` into one at `to`.
-- The Store runs those a save needs at load, in order, before any module that requires it starts, and records
-- each run in save.migrated. A migration that fails leaves the save as it was, and the Store does not start.

local _, ns = ...

-- In order; schema 1 is the baseline and needs none.
ns.MIGRATIONS = {
	-- A character's guild was its name; it is now { name, rank, rankIndex, seen } or { none = true, seen }
	-- (Characters.lua). A name kept is seen when the character was, its rank unknown; no name stays unknown.
	{
		from = 1,
		to = 2,
		run = function(save)
			for _, c in pairs(save.characters or {}) do
				if type(c.guild) == "string" then
					c.guild = { name = c.guild, seen = c.seen }
				end
			end
		end,
	},
	-- The "Announce dings on Discord" choices, by character guid, are retired: the site decides what each
	-- webhook posts.
	{
		from = 2,
		to = 3,
		run = function(save)
			save.dings = nil
		end,
	},
	-- An NPC named with the client's placeholder for a name not yet loaded (Encode.noName) loses that
	-- name; the rest of its row stays, and a later sighting names it.
	{
		from = 3,
		to = 4,
		run = function(save)
			local npcs = save.catalogue and save.catalogue.npcs or {}
			for id, row in pairs(npcs) do
				local name, rest = string.match(row, "^([^,]*)(.*)$")
				if name ~= "" and ns.Encode.noName(name) then
					npcs[id] = rest
				end
			end
		end,
	},
	-- The mail stream (Mail.lua) is new; nothing the save holds changes.
	{
		from = 4,
		to = 5,
		run = function() end,
	},
}

-- `save` brought to `schema` by `migrations`: the same table when none was needed, else an upgraded copy.
-- Nil and why when it cannot be: a newer save, a gap in the chain, or a migration that raised.
function ns.upgrade(save, schema, migrations, now)
	local at = save.schema or schema
	if at > schema then
		return nil, "this file was written by a newer version of the addon (schema " .. at .. ", this one reads " .. schema .. "). Update the addon."
	end
	if at == schema then
		return save
	end
	local upgraded = ns.copy(save)
	for _, m in ipairs(migrations) do
		if m.from == at then
			local ok, err = pcall(m.run, upgraded)
			if not ok then
				return nil, "migration " .. m.from .. " to " .. m.to .. ": " .. tostring(err)
			end
			at = m.to
			upgraded.schema = at
			upgraded.migrated = upgraded.migrated or {}
			table.insert(upgraded.migrated, { from = m.from, to = m.to, t = now })
		end
	end
	if at ~= schema then
		return nil, "no migration from schema " .. at
	end
	return upgraded
end
