# Gold Forever addon

Records your characters into `GoldForeverDB`, the format of
[design 002](../docs/design/002-savedvariables-schema.md). It only records; the web app does the
rest. Version 0.1.0 is the skeleton: characters, rested XP, login/reload/logout, and an API check.

## Install

Link the folder into the game's AddOns folder, so a `git pull` updates the addon:

```sh
# macOS — adjust the flavour folder (_forever_, _classic_beta_ …) to your install
ln -s "$PWD/addon/GoldForever" "/Applications/World of Warcraft/_forever_/Interface/AddOns/GoldForever"
```

```bat
:: Windows (run as administrator)
mklink /D "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GoldForever" "%CD%\addon\GoldForever"
```

Or copy the folder there. On the character select screen, under AddOns, check that **Gold
Forever** is listed and not marked out of date.

## What to test (in this order)

1. **Loads:** log in. `/gf` prints the number of characters and today's events.
2. **API check:** `/gf check` lists which APIs design 002 relies on exist on this client
   (green yes, red no), plus the realm name and region. The same answers are saved in the file.
3. **Reload:** type `/reload`, then open the saved file (below). Under `events` → today → `sys`,
   the last entries should be `…,reload` then `…,resume` — not `logout`.
4. **Logout:** log out to character select, open the file again: the newest entry is `…,logout`.
5. **Second character:** log in on another character and log out: `characters` has both, each
   with its own `ref`.
6. **Send the file** (after logout or `/reload`): it becomes a parser test fixture.

The file is at:

```
<WoW>/<flavour>/WTF/Account/<ACCOUNT>/SavedVariables/GoldForever.lua
```

The game writes it only at logout, exit and `/reload`; a crash writes nothing. It keeps the
previous version as `GoldForever.lua.bak`.

## Tests

```sh
cd addon/tests && npm install && npm test
```

Compiles every addon file and runs the `*_test.lua` files on [fengari](https://fengari.io)
(Lua in JavaScript). The game runs Lua 5.1 and fengari 5.3, so only code that does not depend on
the difference — `Encode.lua` and other pure helpers — is unit-tested here; anything that calls
the game API is tested in game. The `tests` folder sits beside `GoldForever`, so it is never
installed into the game.

## What it records

Per character: name, race, class, faction, level, money, realm, region, rested XP (below max
level), zone and subzone. Account-wide: login, reload, resume and logout times, and the API check.
Nothing about other players. See design 002, "Data minimisation".
