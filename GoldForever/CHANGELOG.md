# Gold Forever

## Unreleased

- The Gold Forever window (`/gf ui`) has two looks. **Web**, the default, looks like gold-forever.app:
  rounded panels with a soft shadow, the site's colours and text sizes, in Roboto. **Classic** looks
  like the game's own windows: the dark dialog box, red buttons, gold Friz Quadrata. Switch with the
  button in the window's title bar or `/gf look web` / `/gf look classic`; no reload needed.
- A Gold Forever button on the minimap: left-click opens the window, right-click switches its look,
  drag it around the rim. `/gf minimap` hides it (and brings it back). On clients with the addon
  compartment (the minimap's addon list), Gold Forever is there too.
- Key bindings under AddOns in the game's Key Bindings: open or close the window, and switch its look.
- A third look, **Arcane**: deep indigo lit from within, a cyan glow around the window, runes at its
  corners, a cyan-to-violet line under the title with a light running along it, buttons that softly
  glow, in Exo 2. `/gf look arcane`, or step through the looks with the minimap button's right-click.
- The window is a hub: the Gold Forever emblem and a page search at the top of a sidebar, the pages in
  groups with an icon each, a large page title over art in the look's colours, and a footer with
  Reload UI and Close. The sidebar's foot shows the addon's own memory and CPU use.
- A **Home** page, the hub's first: the next moves (when you can scan, what your bags would sell for,
  the best craft at the latest prices), today's money by where it came from, and the bag items worth
  most.
- A **Settings** page with the settings the addon has, changed at once: the look, an accent colour over
  any look (also `/gf accent #rrggbb`), the minimap button, the window's size and the alerts. Its
  **Modules** tab switches each part on or off without a reload: the session HUD, the auction house
  panel, prices in tooltips, bag advice at vendors, the craft list and rare alerts. What the save
  records stays the same whatever is off.
- The loot window is now the **session HUD**: one line to drag anywhere with the session's time, gold,
  XP and kills an hour and when you will ding, drawn in the window's look. Click it for the session:
  coin, loot at what it sells for, XP, kills (from kill XP and looted corpses, never the combat log), bags
  and the best loot, with Stop and New session. Settings can hide it in combat; `/gf hud` shows or
  hides it, `/gf session` prints it.
- An **auction house panel** beside the auction house (`/gf ah` hides or brings it back). **Scan**: the
  full scan made visible, asking, reading N of M, the cooldown and the last result. **Post**: the items
  in your bags the auction house takes, each priced by your rule against the cheapest listing by someone
  else (a live search when you choose it; your own listings left out), with the reason: Undercut, No one
  else, Normal price, At floor or Hold. Click Post, or press Space while the panel shows; it waits for
  the server's answer, then moves to the next item. A post under vendor value or far under the market
  asks for a second press. **Rule**: undercut by 1 silver or a percentage, a floor and a normal price
  as shares of the market value (the pool's, else your own scan), and hold or post at the floor.
- The pool's prices find the launch realms' markets: the region from a region number or the portal
  when the client gives no name, and the ruleset from the realm's name (Hardcore, RP-PvP, PvP, RP,
  Normal, or the realm's own name), as the server files them now.
- Retail saves keep one full auction scan per connected realm group (either side's auctioneer opens the
  same auction house): a retail scan is about 2 MB, and a save with four of them grew past the server's
  10 MB upload limit, so nothing new reached the site. The server keeps every scan it received.
- **Announce dings on Discord** from the game: Settings → Discord (or `/gf dings on|off`) switches it
  for the character you are playing. The webhook is added at gold-forever.app/settings; the switch
  needs the companion app, which carries the choice to the site at the next upload.

## 0.15.0

- Prices from everyone's scans in the item tooltip: "Pool: 12s 34c · min buyout 11s 0c · 3 players ·
  scanned 2h ago", for the market of the character you are playing. The Gold Forever companion app
  (v0.1.0 or newer) fetches them every hour and writes them into a small addon, GoldForever_Data.
  After the companion's first install, restart the game fully once; later, `/reload` picks up new prices.
- A price scanned more than 3 days ago is shown in grey.
- An item the shared prices lack shows your own latest scan instead ("Your scan: …").
- Retail: gear shows your connected realm group's price, commodities the region's.
- `/gf prices`: how old the prices file is, its markets and item counts, and which one this
  character reads.

## 0.14.1

- Retail: the rare announcer is off for now. Retail's cities are full of minimap markers for ordinary NPCs,
  and it took them for rares. `/gf rares` says so. WoW: Forever is unchanged.
- Every item an auction scan names now reaches the item catalogue: about half were lost when the
  catalogue's queue was emptied while a scan was still adding to it.
- Retail: each auction scan records every item's class and, when the client knows it, its stack size,
  so commodities and gear are told apart even before the catalogue has loaded the item.

## 0.14.0

- Retail: auction scans are filed under the connected realm group, as retail's auction house trades gear,
  so prices from every realm of the group meet in one market. WoW: Forever is unchanged.

## 0.13.2

- Retail: the addon is no longer out of date on patch 12.1.5 (interface 120105).
- The first release from the addon's own repository, github.com/gold-forever/addon.

## 0.13.1

- The website moved to gold-forever.app. `/gf export` and the addon's notes name the new address; the
  old one forwards there.

## 0.13.0

- `/gf claim <code>`: prove a character is yours when another Gold Forever account uploaded it first.
  Get the code on the website's Characters page.

## 0.12.0

- `/gf export`: a text to paste at gold-forever.evensberget.com/me/upload, so you can upload without
  finding the saved file.
- Loads in retail as well as WoW: Forever.

## Earlier

- A window (`/gf ui`) with your characters, levelling, ledger, mobs and inventory.
- A loot appraiser while you farm: gold per hour, XP per hour and bag space.
- At a vendor: what to vendor, post or disenchant. Alerts for big drops, rares and quest starters.
- A shopping list of profitable crafts at the auction house.
- Records your characters, loot, auction scans, your own auctions and sales, for the website.
