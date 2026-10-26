-- Gold Forever Auctions: the auction house panel, loaded by the core when the auction house opens
-- (GoldForever/Kernel/OnDemand.lua). Its files share the core's namespace: what they read on this addon's
-- own table is the core's, and what they set there the core's, so they run as they did in the core.

local _, ns = ...

local core = GoldForever_Core -- the core's namespace, while the core loads this addon
assert(core, "Gold Forever Auctions is loaded by Gold Forever when the auction house opens")
setmetatable(ns, { __index = core, __newindex = core })
