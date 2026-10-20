# Gold Forever addon

Records your characters into `GoldForeverDB`, the format of
[design 002](../docs/design/002-savedvariables-schema.md). It only records; the web app does the
rest. Version 0.1.0 is the skeleton: characters, rested XP, login/reload/logout, and an API check.

## Install

Link the folder into the game's AddOns folder, so a `git pull` updates the addon. On Linux (Wine,
Lutris or Steam), `scripts/install-addon.sh` finds the game folder and does this; `--help` lists its
options.

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

Per character: name, race, class, faction, level, money, realm, region, guild, rested XP (below
max level), zone and subzone, professions with known recipes, and bag and bank contents.

Account-wide: login, reload, resume and logout times; every loot (source, first loot of a spawn,
coin, items taken, position); positions every 5 s while farming; auction house scans (one per
visit, at most every 15 minutes; `/gf scan` retries); guild bank tabs; and a catalogue of every
item, recipe and vendor price seen. `/gf` shows today's counts and any collector that failed.

Nothing about other players: auction owners and bidders are never read. See design 002, "Data
minimisation", and its "Findings on the live client" for where 0.2.0 departs from the design.

## Loot appraiser (0.6.0)

While you farm, a small window adds up what you loot: coin, the items' worth, the total and the
gold per hour, and the most valuable items so far; the XP gained, XP per hour, when you reach the
next level at that pace and about how many kills that is; and your free bag slots with when they
run out at the rate they are filling (it starts over after you sell). A session starts with the
first loot or kill and ends after 15 minutes without loot, as in the web app. Item tooltips show the auction value (before and
after the 5% cut) and the vendor price. A `/reload` keeps the
session. Mob tooltips show what your characters have looted from that mob: how often, what a loot
is worth at your prices, and its three likeliest drops.

Prices come from the newest full auction scan of your character's own auction house in the saved
file, so scan once in a while; an item is worth the better of its auction value after the cut and
its vendor price. `/gf appraise` shows or hides the window, `/gf reset` starts a new session; drag
the window to move it.

## Loot advisor and big drops (0.7.0)

At a vendor, and with `/gf bags`, a window sorts what is in your bags by what brings the most:
**vendor these** (a vendor pays more than the auction house would after the cut; soulbound items
cannot go there), **post these** (with the price to post at), and **disenchant these** (only when
your Enchanting is high enough), each with its total. Item tooltips also show what disenchanting is
worth and whether that beats selling.

A **big drop** (worth 1 gold or more, or any rare) gets a message mid-screen and a sound; `/gf
bigdrop 2` sets the threshold to 2 gold, `/gf bigdrop 0` alerts on rares only.

Disenchanting uses Classic's table (`Disenchant.lua`, the same as the web app's): the beta's one
disenchanted blue gave dust, not a shard, so Forever's may differ.

## Rare announcer (0.7.1)

A rare or rare elite NPC, seen on a nameplate, as your target, under the mouse or as a minimap
marker, gets a mid-screen message with a sound and a chat line with where you are, once per spawn,
and a skull raid mark (solo, or in a group as its leader or an assistant). Every sighting is
recorded in the file (`rare` rows: NPC, map, position, how it was seen). `/gf rares` turns the
announcing on or off, `/gf rares mark` the skull.

## Craft shopping list (0.7.2)

At the auction house (and with `/gf shop`), a window lists the recipes you know that make a profit
at the latest scan, best first: the profit per craft, what to buy for it (how many, from a vendor or
the auction house, at what price), and how many your bags and bank make now. It uses the web app's
Crafting rules (`Crafting.lua`, "use what I have"): reagents you own are charged at the lower of
buying them again and selling them, so a craft only shows if it beats selling the materials.

## Quest starters (0.7.3)

Loot that starts a quest you have not done gets an alert ("Starts a quest: …"). Mob tooltips name
the quest starters that mob has dropped for you, how often, and whether you have done the quest.
It knows only what your characters have looted: a starter nobody has seen drop is not shown.

## Keeping the data

`scripts/snapshot-data.sh` copies the saved file into `data/forever-beta/`, named by the time it
was written.
