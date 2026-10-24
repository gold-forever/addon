# Gold Forever

## 0.16.0 (not released yet)

The auction house tools and a new window. Gold Forever gets a panel beside the auction house (scan, post,
shop, cancel undercut, rules and sale profiles), a hub window with pages for your money, characters,
crafting, sessions and rares, three looks to choose from, a session HUD, and more in your tooltips.

### The auction house

- A **panel beside the auction house** (`/gf ah` hides or brings it back). Its Buy, Sell and Auctions tabs
  follow Blizzard's and move them. It opens on Scan when a full scan may start, else on the tab
  Blizzard's window shows. Prices show gold and
  silver, as the auction house sets them.
  - **Scan**: the full scan made visible: asking, reading N of M, the cooldown and the last result. A
    scan starts when you press Scan now, or by itself on opening if you switch "Scan when I open the
    auction house" on.
    After a scan, one chat line names your list items now listed at or under your price.
  - **Sell**: the items in your bags the auction house takes, each priced by your rule against the
    cheapest listing by someone else, with the reason (Undercut, No one else, Normal price, At floor,
    Under your floor). The floor and normal price are measured against the item's 7-day average where
    the shared prices have one, so a day's dip does not move them. An item held under your floor can be
    posted anyway at the undercut price, on a second press. Click Post or press Space; it waits for the
    server, then moves to the next item. A price under
    vendor value or far under the market asks for a second press. The duration and the quantity you
    choose are remembered for each item. Alt-click an item in your bags to choose it; its tooltip says
    what Post would ask.
  - **Buy**: a shopping list's items with what can be bought at your price; click one to see its
    listings. **Buy next** asks the auction house for the price and a second press buys; a price more
    than 10% above the deal is named first. **Edit lists ›** opens the Shopping lists page.
  - **Auctions**: checks your auctions against other players' listings and cancels the most undercut
    one a press, past your tolerance (5% at first), showing the cancel cost. Click one to see its
    listings in Blizzard's window.
- **Shopping lists**, a page of the window (Trading → Shopping lists): make, rename, delete, import and
  export lists (`GFL1:` strings); add an item by dropping it on the slot or shift-clicking it anywhere;
  for each, the most you pay (under market, a fixed price, or a share of the market value) and how many
  you want in all, bags and bank counted. The craft queue's list is there too, its prices set the same way.
- **Selling rules**, a page of the window (Trading → Selling rules; **Rule ›** on the Sell tab opens it
  for the item in view): undercut by 1 silver or a percentage, a floor and a normal price as shares of
  the market value, and hold or post at the floor, each with a line saying what it does, and beside them
  what the rule does to an item worth 10g. **Rule for** adds a rule for one item or a whole category.
  **Sale profiles** (`GFP1:` strings, made at gold-forever.app/me/lists or shared by others) price the
  items they name: keep this many, undercut, a fixed price or a point in the supply, with a floor; their
  buy rules become a list in the Buy tab.
- With the companion app, lists and profiles you keep on gold-forever.app come into the game (the
  newer edit wins).
- Prices are whole silver unless the auction house takes copper (the addon asks the game). A single cheap
  unit far under the rest is ignored when pricing ("sneaky prices").
- The panel's title row says what your bank and mailbox hold that the auction house pays for; a hover
  lists it, to fetch before posting.
- A **mail helper** beside the mailbox: one press opens up to ten auction-house mails in turn (sold gold,
  bought, expired, cancelled and outbid items), stopping when your bags are full. A player's letter or a
  cash-on-delivery mail is never touched.

### The window

- The Gold Forever window (`/gf`, or the minimap button) is a hub: a sidebar with a page search (a tab's
  name finds its page and opens that tab: "inv" opens Ledger's Inventory), the pages in groups, and the addon's own memory and CPU use at its foot.
- **Home**: your next moves (when you can scan, what your bags would sell for, the best craft), today's
  money by where it came from, the bag items worth most (each says whether it sells best at the auction
  house or to a vendor; hover for the item), and a **gold goal** with the gold a day still needed. It
  keeps up as your money and bags change. Large gold amounts are grouped (3,000,000g).
- **Ledger**: Money, Characters, **Inventory** (filter by character, place and quality) and **Auction
  sales** (what sold, for how much, after the cut).
- **Crafting**: every recipe your characters know, by profit, with cost, price after the cut and margin;
  "I have these" counts what you hold at no cost. **Queue** a recipe and the Buy tab's "Craft queue" list
  buys only the reagents still missing. `/gf shop` opens it; the old floating "crafts to make" window at
  the auction house is gone.
- **Session**: This session (the HUD at full size, with its loot), Levelling and Mobs.
- **Rares**: every rare your characters have seen, how often, when and where, and what a loot has been
  worth.
- **Companion**: whether the companion's prices are loaded, how old they are, and its markets.
- **Settings**: the look, an accent colour (also `/gf accent #rrggbb`), the minimap button, the window's
  size (set when you let go of the slider, or type it in its box), the alerts, and **Modules** to switch any part on or off without a reload. What the save records
  stays the same whatever is off.
- **Guide**: how to use it all, and every command (`/gf help` lists the main ones, `/gf help all` the
  rest; `/gf check` gives the details for a bug report).
- Three **looks**: **Web** (like gold-forever.app), **Classic** (like the game's own windows) and
  **Arcane** (deep indigo with a cyan glow). Switch with the minimap button's right-click, the title bar
  or `/gf look`; no reload needed.
- A minimap button (`/gf minimap` hides it), the addon compartment, and key bindings to open the window,
  switch the look and show the HUD.
- A **first-run card** for new installs: what Gold Forever records and shares, a preset to start with
  (Prices only, Trader, Everything), the look and accent colour (seen at once), and the companion app,
  which is open source. `/gf welcome` shows it again.

### While you play

- The loot window is now the **session HUD**: one line with the session's time, gold, XP and kills an
  hour and when you will ding. Click it for the session: coin, loot at what it sells for, XP, kills, bags
  and the best loot. `/gf hud` shows or hides it; Settings can hide it in combat.
- A **crafting strip** beside the profession window: the chosen recipe's reagent cost, what the item
  sells for after the cut, the profit and margin, and what you still have to buy.
- **Sell junk** at a vendor, where the merchant window has no button for it (WoW: Forever): the loot
  advisor's button says how many and for how much, and a second press sells them with the game's own
  call, so they stay in the buyback tab.
- Rare alerts can **tell your party** (Settings → General, off at first; WoW: Forever).
- **Announce dings on Discord** from the game: Settings → Discord (or `/gf dings on|off`), with the
  webhook added at gold-forever.app/settings and the companion app installed.

### Tooltips and prices

- **Held**: how many each of your characters holds of an item, in bags, bank and mail.
- **Price trend**: the pool's price against its 7-day average ("+12% vs 7-day avg"), once the server has
  a week of prices; Post advises "rising: maybe wait" or "falling" at 10% either way.
- In Stranglethorn, Tanaris and Winterspring, the neutral auction house's price comes first (WoW:
  Forever).
- When everyone's prices are more than a day old, one line at login asks whether the companion app is
  running.
- The pool's prices find the launch realms' markets, by region and ruleset, as the server files them.

### Saves and fixes

- **Retail saves are lean**: tooltip text, the achievement catalogue and map art are no longer kept on
  retail (about 5 MB on a busy save), and a retail save keeps one full scan per connected realm group, so
  it stays under the site's upload limit. A WoW: Forever save keeps everything.
- On retail, a Horde character's own scan prices come from any side's auctioneer (one auction house
  serves the realm group).
- Statistics and achievements are read a little at a time: a retail client stopped the read as "script
  ran too long".
- Units the client keeps secret (newer clients hide some names and GUIDs) are skipped instead of causing
  errors in tooltips.
- A new addon version starts with no recorded errors.
- Big saves stay smooth: scans, prices and mob counts are worked over several frames, and tooltips do
  less work per hover.

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
