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
  // The game's global date, with UTC ("!") formats that hold in every time zone (gamedate.lua).
  const gamedate = fs.readFileSync(path.join(__dirname, 'gamedate.lua'), 'utf8')
  if (lauxlib.luaL_dostring(L, to_luastring(gamedate)) !== lua.LUA_OK) {
    throw new Error(`gamedate.lua: ${lua.lua_tojsstring(L, -1)}`)
  }
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
// The whole addon on a made-up save the size of a heavy player's (bigsave.lua), on both clients, when
// luajit is installed (CI runs it in its own step after installing it).
const { spawnSync } = require('child_process')
const os = require('os')
if (spawnSync('luajit', ['-v']).status === 0) {
  const repo = path.join(__dirname, '..')
  const save = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'gf-bigsave-')), 'GoldForever.lua')
  fs.writeFileSync(save, spawnSync('luajit', [path.join(__dirname, 'bigsave.lua')], { maxBuffer: 64 << 20 }).stdout)
  for (const interfaceNumber of ['16001', '120105']) {
    const run = spawnSync('luajit', ['tests/smoke.lua', 'GoldForever'], {
      cwd: repo,
      env: { ...process.env, GF_SMOKE_INTERFACE: interfaceNumber, GF_SMOKE_SAVE: save, GF_SMOKE_GUID: 'Player-3666-0000000A' },
      maxBuffer: 64 << 20,
    })
    const out = String(run.stdout)
    if (run.status !== 0) {
      console.error(`✗ big save on ${interfaceNumber}:\n${out.split('\n').filter((l) => !l.startsWith('[chat]')).join('\n')}${run.stderr}`)
      failed++
    } else {
      console.log(`✓ big save on ${interfaceNumber}: ${out.match(/MEMORY .*/)?.[0] ?? ''}`)
    }
  }
} else {
  console.log('- big save skipped: no luajit')
}
process.exit(failed ? 1 : 0)
