-- Gold Forever: the save's streams and their columns (design 002, schema v1).

local _, ns = ...

-- Column dictionary; each collector adds its own entries when its file loads.
ns.FIELDS = {
	sys = "t,char,kind",
}
