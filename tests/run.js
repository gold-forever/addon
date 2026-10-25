// Runs the addon's Lua unit tests on fengari. The game runs Lua 5.1 and fengari 5.3; the tested
// code avoids everything that differs between them.
//
// Every addon file is compiled (not run) so syntax errors fail here instead of in game, then each
// *_test.lua file runs with the addon sources available as SOURCES[name] and the harness of helpers.lua.

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
  // The three TOCs, as TOCS[name], and whether each file a TOC lists is there (FILES[path], for toc_test.lua).
  lua.lua_newtable(L)
  for (const name of fs.readdirSync(addonDir).filter((f) => f.endsWith('.toc'))) {
    lua.lua_pushstring(L, to_luastring(fs.readFileSync(path.join(addonDir, name), 'utf8')))
    lua.lua_setfield(L, -2, to_luastring(name))
  }
  lua.lua_setglobal(L, to_luastring('TOCS'))
  lua.lua_newtable(L)
  for (const toc of fs.readdirSync(addonDir).filter((f) => f.endsWith('.toc'))) {
    for (const line of fs.readFileSync(path.join(addonDir, toc), 'utf8').split(/\r?\n/)) {
      const file = line.trim()
      if (file && !file.startsWith('#')) {
        lua.lua_pushboolean(L, fs.existsSync(path.join(addonDir, ...file.split('\\'))))
        lua.lua_setfield(L, -2, to_luastring(file))
      }
    }
  }
  lua.lua_setglobal(L, to_luastring('FILES'))
  // The game's global date, with UTC ("!") formats that hold in every time zone (gamedate.lua).
  const gamedate = fs.readFileSync(path.join(__dirname, 'gamedate.lua'), 'utf8')
  if (lauxlib.luaL_dostring(L, to_luastring(gamedate)) !== lua.LUA_OK) {
    throw new Error(`gamedate.lua: ${lua.lua_tojsstring(L, -1)}`)
  }
  // The shared harness: eq, near and checks() (helpers.lua).
  const helpers = fs.readFileSync(path.join(__dirname, 'helpers.lua'), 'utf8')
  if (lauxlib.luaL_loadbuffer(L, to_luastring(helpers), null, to_luastring('@helpers.lua')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(`helpers.lua: ${lua.lua_tojsstring(L, -1)}`)
  }
  // The names the addon's files read and set on ns (nsnames.lua), for names_test.lua.
  const names = fs.readFileSync(path.join(__dirname, 'nsnames.lua'), 'utf8')
  if (lauxlib.luaL_loadbuffer(L, to_luastring(names), null, to_luastring('@nsnames.lua')) !== lua.LUA_OK || lua.lua_pcall(L, 0, 0, 0) !== lua.LUA_OK) {
    throw new Error(`nsnames.lua: ${lua.lua_tojsstring(L, -1)}`)
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
// Lua 5.2+ syntax the game's Lua 5.1 refuses, though fengari (5.3) and LuaJIT accept some of it: goto and
// ::labels::, // and the bitwise operators. Read with strings and comments taken out.
function code(source) {
  let out = ''
  let i = 0
  const longBracket = (at) => {
    const m = /^\[(=*)\[/.exec(source.slice(at, at + 64))
    return m && m[1].length
  }
  while (i < source.length) {
    const c = source[i]
    if (c === '-' && source[i + 1] === '-') {
      const level = longBracket(i + 2)
      if (level !== null) {
        const close = source.indexOf(']' + '='.repeat(level) + ']', i)
        const end = close < 0 ? source.length : close + level + 2
        out += source.slice(i, end).replace(/[^\n]/g, '')
        i = end
      } else {
        while (i < source.length && source[i] !== '\n') i++
      }
      out += ' '
    } else if (c === '[' && longBracket(i) !== null) {
      const level = longBracket(i)
      const close = source.indexOf(']' + '='.repeat(level) + ']', i)
      const end = close < 0 ? source.length : close + level + 2
      out += '""' + source.slice(i, end).replace(/[^\n]/g, '')
      i = end
    } else if (c === '"' || c === "'") {
      i++
      const start = i
      while (i < source.length && source[i] !== c && source[i] !== '\n') i += source[i] === '\\' ? 2 : 1
      i++
      out += '""' + source.slice(start, i).replace(/[^\n]/g, '')
    } else {
      out += c
      i++
    }
  }
  return out
}
const NEWER = [
  [/\bgoto\b/, 'goto'],
  [/::\s*[A-Za-z_]\w*\s*::/, 'a ::label::'],
  [/\/\//, 'floor division //'],
  [/&|\||<<|>>|~(?!=)/, 'a bitwise operator'],
]
for (const name of addonFiles) {
  const lines = code(fs.readFileSync(path.join(addonDir, name), 'utf8')).split('\n')
  for (const [pattern, what] of NEWER) {
    const at = lines.findIndex((l) => pattern.test(l))
    if (at >= 0) {
      console.error(`✗ ${name}:${at + 1} uses ${what}, which Lua 5.1 does not have`)
      failed++
    }
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
// The whole addon on the stand-in game API, when luajit is installed: the session smoke.lua plays, on
// both clients, as an Alliance and a Horde character; then a made-up save the size of a heavy player's
// (bigsave.lua) on both clients. A run fails on an assert, or on any error the addon recorded.
const { spawnSync } = require('child_process')
const os = require('os')
const repo = path.join(__dirname, '..')
function smoke(label, env) {
  const run = spawnSync('luajit', ['tests/smoke.lua', 'GoldForever'], { cwd: repo, env: { ...process.env, ...env }, maxBuffer: 64 << 20 })
  const out = String(run.stdout)
  if (run.status !== 0) {
    // The session's dump of the save is long: the end, where the failure is, without the chat.
    const lines = out.split('\n').filter((l) => !l.startsWith('[chat]'))
    console.error(`✗ ${label}:\n${lines.slice(-40).join('\n')}${run.stderr}`)
    failed++
  }
  return run.status === 0 && out
}
if (spawnSync('luajit', ['-v']).status === 0) {
  for (const interfaceNumber of ['16001', '120105']) {
    for (const faction of ['Alliance', 'Horde']) {
      const out = smoke(`session on ${interfaceNumber} as ${faction}`, { GF_SMOKE_INTERFACE: interfaceNumber, GF_SMOKE_FACTION: faction })
      if (out) console.log(`✓ session on ${interfaceNumber} as ${faction}: ${out.match(/SCAN BUDGET .*?mean [\d.]+ ms a frame/)?.[0] ?? ''}`)
    }
  }
  const save = path.join(fs.mkdtempSync(path.join(os.tmpdir(), 'gf-bigsave-')), 'GoldForever.lua')
  fs.writeFileSync(save, spawnSync('luajit', [path.join(__dirname, 'bigsave.lua')], { maxBuffer: 64 << 20 }).stdout)
  for (const interfaceNumber of ['16001', '120105']) {
    const out = smoke(`big save on ${interfaceNumber}`, { GF_SMOKE_INTERFACE: interfaceNumber, GF_SMOKE_SAVE: save, GF_SMOKE_GUID: 'Player-3666-0000000A' })
    if (out) console.log(`✓ big save on ${interfaceNumber}: ${out.match(/MEMORY .*/)?.[0] ?? ''}`)
  }
} else if (process.env.CI) {
  // CI installs luajit first: without it the gate would pass on the unit tests alone.
  console.error('✗ no luajit: the smoke runs cannot run')
  failed++
} else {
  console.log('- smoke runs skipped: no luajit')
}
process.exit(failed ? 1 : 0)
