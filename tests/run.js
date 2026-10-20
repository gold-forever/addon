// Runs the addon's Lua unit tests on fengari. The game runs Lua 5.1 and fengari 5.3; the tested
// code avoids everything that differs between them.
//
// Every addon file is compiled (not run) so syntax errors fail here instead of in game, then each
// *_test.lua file runs with the addon sources available as SOURCES[name].

const fs = require('fs')
const path = require('path')
const { lua, lauxlib, lualib, to_luastring } = require('fengari')

const addonDir = path.join(__dirname, '..', 'GoldForever')
const addonFiles = fs.readdirSync(addonDir).filter((f) => f.endsWith('.lua'))
const tests = fs.readdirSync(__dirname).filter((f) => f.endsWith('_test.lua'))

function state() {
  const L = lauxlib.luaL_newstate()
  lualib.luaL_openlibs(L)
  lua.lua_newtable(L)
  for (const name of addonFiles) {
    lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(addonDir, name), 'utf8')))
    lua.lua_setfield(L, -2, to_luastring(name))
  }
  lua.lua_setglobal(L, to_luastring('SOURCES'))
  return L
}

let failed = 0
for (const name of addonFiles) {
  const L = state()
  const source = fs.readFileSync(path.join(addonDir, name), 'utf8')
  if (lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring('@' + name)) !== lua.LUA_OK) {
    console.error(`✗ ${name} does not compile: ${lua.lua_tojsstring(L, -1)}`)
    failed++
  } else {
    console.log(`✓ ${name} compiles`)
  }
}
for (const name of tests) {
  const L = state()
  const source = fs.readFileSync(path.join(__dirname, name), 'utf8')
  const ok =
    lauxlib.luaL_loadbuffer(L, to_luastring(source), null, to_luastring('@' + name)) === lua.LUA_OK &&
    lua.lua_pcall(L, 0, 1, 0) === lua.LUA_OK
  if (!ok) {
    console.error(`✗ ${name}: ${lua.lua_tojsstring(L, -1)}`)
    failed++
  } else {
    console.log(`✓ ${name}: ${lua.lua_tojsstring(L, -1)} checks`)
  }
}
process.exit(failed ? 1 : 0)
