# Gold Forever

## 0.16.0 (not released yet)

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
- **Inventory** (Ledger tab) filters by character, place (bags, bank, mail) and quality, with totals that
  follow; at the auction house a click on an item chooses it in Post.
- Fewer rows in the hub: **Ledger** holds Money, Characters, Inventory and **Auction sales** (what sold,
  for how much, after the cut) as tabs, and **Session** holds **This session** (the HUD's figures at full
  size, with the session's loot), Levelling and Mobs; each page remembers its tab, and `/gf ui levelling` and the like still work.
- `/gf` on its own opens or closes the hub; `/gf help` lists every command.
- A **Home** page, the hub's first: the next moves (when you can scan, what your bags would sell for,
  the best craft at the latest prices), today's money by where it came from, and the bag items worth
  most. A **gold goal** (an amount and 7–60 days) shows how far you are across all characters and
  the gold a day still needed.
- A **Crafting** page: every recipe your characters know, by profit, with cost, price after the cut and
  margin (grey under 10%, green from 30%), the chosen recipe's reagents, and "I have these" to count what
  you hold at no cost. **Queue** 1 or 5 of a recipe (also from the crafting strip): the Shop gets a
  "Craft queue" list that buys only the reagents still missing for the whole queue.
- A **Rares** page: every rare your characters have seen, how often, when and where last, how it was
  seen, and what a loot of one has been worth.
- When everyone's prices in the game are more than a day old, one line at login asks whether the
  companion app is running (at most once a day).
- A **Guide** page: how to use the auction house panel, crafting, the session, Discord, and the commands.
- A **Companion** page: whether the companion's prices are loaded and when they were written, its
  markets with their items (this character's first, and any it has no prices for yet), and this
  character's Discord dings.
- A **Settings** page with the settings the addon has, changed at once: the look, an accent colour over
  any look (also `/gf accent #rrggbb`; Arcane's glow and gradients take it too), the minimap button, the window's size and the alerts. Its
  **Modules** tab switches each part on or off without a reload: the session HUD, the auction house
  panel, prices in tooltips, the crafting strip, bag advice at vendors, the craft list and rare alerts. What the save
  records stays the same whatever is off.
- The loot window is now the **session HUD**: one line to drag anywhere with the session's time, gold,
  XP and kills an hour and when you will ding, drawn in the window's look. Click it for the session:
  coin, loot at what it sells for, XP, kills (from kill XP and looted corpses, never the combat log), bags
  and the best loot, with Stop and New session. Settings can hide it in combat; `/gf hud` shows or
  hides it (so does a key binding), `/gf session` prints it.
- An **auction house panel** beside the auction house (`/gf ah` hides or brings it back). **Scan**: the
  full scan made visible, asking, reading N of M, the cooldown and the last result. **Post**: the items
  in your bags the auction house takes, each priced by your rule against the cheapest listing by someone
  else (a live search when you choose it; your own listings left out), with the reason: Undercut, No one
  else, Normal price, At floor or Hold. Click Post, or press Space while the panel shows; it waits for
  the server's answer, then moves to the next item. A post under vendor value or far under the market
  asks for a second press. Alt-click an item in your bags to choose it in Post; its tooltip says what Post would ask. The duration you choose for an item, and how many of a stackable item to
  post (all at first), are remembered for it. **Rule**: undercut by 1 silver or a percentage, a floor and a normal price
  as shares of the market value (the pool's, else your own scan), and hold or post at the floor. Prices
  are whole silver unless the auction house takes copper (the addon asks the game).
  **Shop**: shopping lists of items with the most you pay a unit (or "under market"); shift-click an
  item into the field to add it. Choosing one searches it and shows what you can buy at or under your
  price; **Buy next** asks the auction house for the price, and a second press buys (a price more than
  10% above the deal is named first). Gear is bought one auction a press. Lists import and export as
  `GFL1:` strings to share. After a full scan, one chat line names the list items now listed at or under
  your price (Settings → Modules: "Deals after a scan").
  **Cancel**: checks your auctions one by one against other players' listings (a single cheap unit far
  under the rest is ignored) and lists those undercut past your tolerance (5% at first); **Cancel next**
  cancels the most undercut one a press, showing the cancel cost. The items come back by mail.
  **Overrides** (Rule tab): "Rule for" picks the default, or adds a rule for the item chosen in Post
  or its whole category; the controls then change only that rule, and Post says "(item rule)" or
  "(category rule)" where one priced it.
  Lists and profiles carry an id and an edit time; with a companion that brings them from the site,
  they merge in at login (the newer edit wins, the other kept as an older copy).
  **Sale profiles** (Rule tab): import a `GFP1:` string (from the site or a creator) and its rules price
  the items it names in Post: keep this many, undercut, a fixed price (asking when the market moved) or
  a point in the supply, with a floor; a single cheap unit far under the rest is ignored. Its buy rules
  appear as a list in the Shop, buying only up to what you still need. Export shares yours.
- The pool's prices find the launch realms' markets: the region from a region number or the portal
  when the client gives no name, and the ruleset from the realm's name (Hardcore, RP-PvP, PvP, RP,
  Normal, or the realm's own name), as the server files them now.
- Retail saves keep one full auction scan per connected realm group (either side's auctioneer opens the
  same auction house): a retail scan is about 2 MB, and a save with four of them grew past the server's
  10 MB upload limit, so nothing new reached the site. The server keeps every scan it received.
- A **crafting strip** beside the profession window: for the recipe you choose, what its reagents
  cost (each at the cheaper of the auction house and a vendor), what the item sells for after the cut,
  the profit and margin, and what you still have to buy. Settings → Modules switches it off.
- A **first-run card** for new installs (never in combat): what Gold Forever records and shares, a
  preset to start with (Prices only, Trader, Everything) and the companion app's address. An install
  that already has characters never sees it; `/gf welcome` shows it again.
- In Stranglethorn, Tanaris and Winterspring (the neutral auction houses), item tooltips show the
  neutral market's pool price first, then your faction's (WoW: Forever).
- A **mail helper** beside the mailbox: one press opens up to ten auction-house mails in turn (sold gold,
  bought, expired, cancelled and outbid items), stopping when your bags are full. A player's letter or a
  cash-on-delivery mail is never touched. Settings → Modules switches it off.
- Rare alerts can **tell your party** (Settings → General, off at first; WoW: Forever): one plain line in
  party chat a rare, never in say, yell or raid.
- **Announce dings on Discord** from the game: Settings → Discord (or `/gf dings on|off`) switches it
  for the character you are playing. The webhook is added at gold-forever.app/settings; the switch
  needs the companion app, which carries the choice to the site at the next upload.

- **Retail saves are lean**: on a retail client the item tooltip text, the achievement catalogue and the
  map art are no longer recorded, and an existing retail save drops them at load (about 5 MB on a busy
  save). They exist to keep WoW: Forever's knowledge; a Forever save keeps everything.
- **Price trend**: with prices from the companion, an item's pool line and Post's market say how the price
  stands against its 7-day average ("+12% vs 7-day avg", "steady" within 1%), once the server sends it.
  Post adds advice at 10% either way: "rising: maybe wait", or "falling".
- At the auction house, the panel's title row says what your bank and mailbox hold that the auction
  house pays for ("Bank & mail: 3 items · 45g"); a hover lists them, dearest first, to fetch first.
- **Held counts in tooltips**: how many each of your characters holds of an item, in bags, bank and mail
  ("Held 12: Zerie 10 (bags 8, bank 2), Zeripala 2 (mail)"). Settings → Modules switches it off.
- **Crafting**: Cost, Profit and Margin share one base: the reagents still to buy plus the held ones at
  what they would sell for.
- Recorded errors are of the version that recorded them: a new addon version starts with none.
- Statistics and achievements are read a category a frame (a retail client stopped the read as "script
  ran too long"); the counts of what each mob drops are built over frames after login.
- Units the client keeps secret (newer clients hide some names and GUIDs) are skipped, never an error.
- The mail helper never opens a letter a player could have titled like auction mail.
- The auction house panel never stays locked after a refused buy, cancel or post (it waits at most 5
  seconds), and a press after a price warning confirms only the price and quantity warned about.
- Kills: a corpse looted after its fight ended is no longer counted a second time.
- The HUD switch in Settings → Modules does what it shows; This session counts from the first opening.
- Switching looks no longer builds new panels each time (the window's, the HUD's, the auction house
  panel's, the mail helper's, the crafting strip's, the first-run card's).

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
