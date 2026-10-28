# Gold Forever addon

Records what your characters see and earn in **WoW: Forever** (it also loads in retail), for the
[Gold Forever](https://gold-forever.app) web app, which turns it into prices, ledgers and plans. The
addon only records; `/gf export` gives you the text to paste at gold-forever.app, or the
[companion app](https://github.com/gold-forever/companion) uploads it for you.

It records your own characters and what you loot and scan, and **never other players**: auction
owners and bidders are not read. The web app's privacy page:
<https://gold-forever.app/privacy>.

## Install

- **CurseForge app, WowUp or the Wago app** (coming): search for "Gold Forever"; they keep it up to
  date.
- **By hand:** download `GoldForever-<version>.zip` from
  [the releases](https://github.com/gold-forever/addon/releases) and unzip it into your WoW: Forever
  folder's `Interface/AddOns/` (for example `<WoW>/_forever_/Interface/AddOns/`), so that
  `AddOns/GoldForever/GoldForever.toc` exists.

Then, on the character select screen under AddOns, check that **Gold Forever** is listed and not
marked out of date. In game, `/gf` shows what it has recorded.

**Checking a download:** every release zip has a build attestation. With the
[GitHub CLI](https://cli.github.com):

```sh
gh attestation verify GoldForever-<version>.zip --repo gold-forever/addon
```

It passes only when this repository's release workflow built that exact file.

## What it records

Per character: name, race, class, faction, level, money, realm, region, guild, rested XP (below
max level), zone and subzone, professions with known recipes, and bag and bank contents.

Account-wide: login, reload, resume and logout times; every loot (source, first loot of a spawn,
coin, items taken, position); positions every 5 s while farming; auction house scans (one per
visit, at most every 15 minutes; `/gf scan` retries); guild bank tabs; and a catalogue of every
item, recipe and vendor price seen. `/gf` shows today's counts and any collector that failed.

Nothing about other players: auction owners and bidders are never read. The full format is design 002 in the Gold Forever project.

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

## Your auctions (0.7.4)

Every auction you post is recorded (item, count, price per unit, duration), and every sale from the
auction house's "successful" mail (item, count, price, deposit, the house's cut), once per mail;
the buyer the mail names is not kept. The loot window's **Stop** button ends the farming session
there and then.

## Developing

Clone, then link both addon folders into the game's AddOns folder, so a `git pull` updates them.
`GoldForever_Auctions` is the auction house panel, which `GoldForever` loads when the auction house opens:
without it the game answers `MISSING` there.

```sh
# Linux (Wine, Lutris, Steam) or macOS: adjust the path to your install and flavour folder
for a in GoldForever GoldForever_Auctions; do ln -s "$PWD/$a" "<WoW>/_forever_/Interface/AddOns/$a"; done
```

```bat
:: Windows (run as administrator; _retail_ for retail)
mklink /D "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GoldForever" "%CD%\GoldForever"
mklink /D "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GoldForever_Auctions" "%CD%\GoldForever_Auctions"
```

**Tests:**

```sh
cd tests && npm ci && npm test        # every file compiles; the *_test.lua files run on fengari
luajit tests/smoke.lua GoldForever    # the whole addon loads on a stand-in game API; "errors" must be empty
```

The game runs Lua 5.1 and fengari 5.3, so the unit tests cover pure helpers; anything that calls the
game API is tested in game. The `tests` folder sits beside `GoldForever`, so it is never installed.

**Code layout:** the files load in the TOC's order and share one table, `ns`. Each layer calls only the
layers below it; a lower file tells the ones above what happened by an event (`ns.emit`, heard with
`ns.listen`): `ready`, `queueChanged`, `pricesReady` and `lookChanged`.

1. **Pure** (no game API, unit tested): `Encode`, `Money`, `Scans`, `Export`, `Realms`, `Views`, `Post`,
   `SalePlan`, `Shopping`, `Crafting`, `Disenchant`, `Theme`, `UILayout`.
2. **Runtime:** `Core`: the saved table, the game's events (`ns.on`), the addon's own, `ns.safely`, the
   settings and their defaults (`ns.DEFAULTS`).
3. **Collectors**, which record into the save: `Catalogue`, `Loot`, `Inventory`, `Professions`, `Market`,
   `Ledger`, `Knowledge`, `Character`, `Legacy`, `Achievements`, `Rares`, `Auctions`, `Levelling`,
   `Claim`.
4. **Services:** `Pricing` (`ns.price`), `Prices` (everyone's prices), `Session`, `MobStats`,
   `CraftPlanner` (the craft quotes and queue), `Holdings`, `Lists`, `AuctionSettings`.
5. **UI kit:** `UIDraw`, `UIControls`, `UIData`, `UIWindows` (`UI.perLook`, `UI.Dialog`), `Looks`,
   `HubKit`, `HubWindow`.
6. **Surfaces:** `Hud`, `Tooltips`, `Advisor`, `CraftQueue`, `CraftingStrip`, `MailHelper`, `FirstRun`,
   `Minimap`, `ExportFrame`; the auction panel, `AuctionPanel` with `AuctionWaits`, `AuctionBlizzard`,
   `AuctionBooks` and a file a tab (`AuctionScanTab`, `AuctionSell`, `AuctionBuy`, `AuctionCancel`,
   `AuctionBank`); the hub's pages, a file each (`HubHome`, `HubLedger`, `HubSession`, `HubCrafting`,
   `HubRares`, `HubCompanion`, `HubSettings`, `HubGuide`, `DesignSystem`, `SellingRulesPage`,
   `ShoppingListsPage`); `Hub` (the window, its pages, `/gf ui`); `UiDebug`.

## What to test (in this order)

1. **Loads:** log in. `/gf` prints the number of characters and today's events.
2. **API check:** `/gf check` lists which APIs the web app relies on exist on this client
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

**Releasing:** a tag `addon-v<version>` runs `.github/workflows/addon-release.yml`. The tag must
match the three TOCs' `## Version` and Core.lua's `VERSION` (a test keeps those four, and the TOCs'
file lists, the same). It tests, packages with the BigWigs packager (`.pkgmeta`), attests the
zip, and publishes it to this repository's releases (and to CurseForge and Wago once their project
ids and tokens are set).

## Licence

**Source-available, all rights reserved** (not open source): the code is published so anyone can
read what the addon records and does, but it may not be copied, modified or redistributed without
written permission. Installing and using the released addon is of course fine. See [LICENSE](LICENSE).

Roboto (Apache-2.0, `GoldForever/Media/Roboto-LICENSE.txt`), the web look's font, Exo 2 (SIL Open Font
License 1.1, `GoldForever/Media/Exo2-OFL.txt`), the arcane look's, LibDeflate (zlib,
`GoldForever/Libs/LibDeflate/LICENSE.txt`) and LibStub (public domain) keep their
own licences. World of Warcraft is Blizzard Entertainment's; this addon is not affiliated with or
endorsed by Blizzard.
