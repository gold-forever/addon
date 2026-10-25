# Gold Forever

## Unreleased

- **Lists for one character.** A shopping list made for one character on the site shows on that
  character only, on the Buy tab and the Shopping lists page; other lists, and the craft queue's, show
  on every character. Importing another character's list makes it yours. A list string with a line Gold Forever does not know yet is still read, that line
  skipped.
- **Sale profiles for one character.** A sale profile made for one character on the site is offered on
  the Selling rules page, and prices the Sell tab, on that character only; other profiles work on every
  character. Importing another character's profile makes it yours.

## 0.16.1 (2026-10-25)

- **Text takes the same room in every look.** Web and Arcane size their text so a line is as wide as in
  Classic, measured in game against Friz Quadrata at login. The Scan tab's "Scan when I open the auction
  house" no longer runs out of the panel in Web.

## 0.16.0 (2026-10-25)

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
  you want in all, bags and bank counted. **Lowest, ask over %** is for what you need (raid consumables):
  Buy next buys the cheapest first, and above your share of the market value it asks before buying, so
  you can choose something cheaper instead. The craft queue's list is there too, its prices set the same way.
- **Selling rules**, a page of the window (Trading → Selling rules; **Rule ›** on the Sell tab opens it
  for the item in view): undercut by 1 silver or a percentage, a floor and a normal price as shares of
  the market value, and hold or post at the floor, each with a line saying what it does, and beside them
  what the rule does to an item worth 10g. **Rule for** adds a rule for one item or a whole category.
  **Sale profiles** (`GFP1:` strings, made at gold-forever.app/me/lists or shared by others) price the
  items they name: keep this many, undercut, a fixed price or a point in the supply, with a floor; their
  buy rules become a list in the Buy tab.
- With the companion app, lists and profiles you keep on gold-forever.app come into the game (the
  newer edit wins).
- Prices are whole silver unless the auction house takes copper (the addon asks the game). One or two
  cheap units more than 30% under the next price are ignored when pricing ("sneaky prices"), the same way
  in Sell, Auctions and the sale profiles.
- The panel's title row says what your bank and mailbox hold that the auction house pays for; a click
  opens the **Bank** tab: click an item to see its listings, then **Take all** or **Take…** an amount;
  it moves into your bags the next time you open your bank (a part of a stack is split off).
- A **mail helper** beside the mailbox: one press opens all the auction-house mails in turn, quickly (sold gold,
  bought, expired, cancelled and outbid items), stopping when your bags are full. A player's letter or a
  cash-on-delivery mail is never touched.

### The window

- The Gold Forever window (`/gf`, or the minimap button) is a hub: a sidebar with a page search (a tab's
  name finds its page and opens that tab: "inv" opens Ledger's Inventory), the pages in groups, and the addon's own memory and CPU use at its foot.
- An **Export** button beside Reload UI while the companion app is not at work (no prices file, or one
  over a day old): it makes the `/gf export` text to paste on the site. The companion uploads your save
  by itself.
- **Home**: your next moves (when you can scan, what your bags would sell for, the best craft), today's
  money by where it came from, the bag items worth most (each says whether it sells best at the auction
  house or to a vendor; hover for the item), and a **gold goal** with the gold a day still needed. It
  keeps up as your money and bags change. Large gold amounts are grouped (3,000,000g).
- **Ledger**: Money, Characters, **Inventory** (filter by character, place and quality; soulbound items
  marked and counted at a vendor's price, **Tradeable only** leaves them out; **Equipped** shows what you
  wear, not counted; hover an item for its tooltip) and **Auction sales** (what sold, for how much, after
  the cut).
- **Crafting**: every recipe your characters know, by profit, with cost, price after the cut and margin,
  for all professions or one; "Use my own ingredients" counts what you hold at no cost. **Queue** a recipe and the Buy tab's "Craft queue" list
  buys only the reagents still missing. A **craft queue window** opens while crafts are queued: for each reagent what you
  have, what to pick up from the bank (**Take from bank** marks it for your next visit), what the guild
  bank and your other characters hold, and what is left to buy; a reagent a vendor sells is marked
  "vendor" and bought when you open a merchant that has it. Close it with its X; **Queue window** on
  the Crafting page or the Craft queue list opens it again. `/gf shop` opens it; the old floating "crafts to make" window at
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

- Records three new things for your pages on the site and the shared prices: how long each scanned
  listing has left (so the site can tell a sale from an auction that ran out), what you sell to and buy
  from vendors, and what you buy on the auction house and your auctions that expire or that you cancel.
  As before, nothing about other players is kept: no buyer or seller names.
- On retail, mob and object names hidden in combat are no longer saved as "Unknown": the addon looks
  again after the fight and at the loot window, and fills a missing name in later, so your farming
  sessions on the site name what you killed and gathered.
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

### More fixes

- **Auction house**: a scan with many bid-only listings is no longer thrown away as cut short. Sell,
  Buy and Auctions each wait for their own answer from the server, so one never unblocks another, and a
  purchase with no answer is let go. Blizzard's own Sell window can still confirm a warned post. Check my
  auctions ends, and says so, when the server sends no list. Gear at two item levels is judged against
  its own listings. A price typed as "1,000" is a thousand gold. A sale profile never posts under its
  floor after rounding to the silver. `/gf ah` away from the auction house no longer opens an empty
  panel. A price over a million gold in the prices file is refused.
- **Crafting**: reagents are priced like the item they make, so crafts show a profit with the prices
  file and no scan of your own. No disenchant values on retail, where the table does not apply. The craft
  queue reopens only when you add a craft, not when you make one, says "ready to craft" once, counts
  your mail when taking from the bank, and listens only to your own casts. The crafting strip no longer
  shows the last profession's recipe in another profession's window.
- **Home and the window**: the bags' worth leaves out soulbound items. The last scan on Home and the
  Scan tab are your own market's: on WoW: Forever a Horde character no longer sees an Alliance alt's
  scan as its own (on retail one auction house serves both sides, so it still counts). "At the level
  cap" counts characters by level. Settings shows each switch as it is when opened, and the first-run
  presets show or hide the HUD at once. A table's sort order survives a column added or moved. The
  craft queue's close button follows the look.
- **Saves**: event days not yet exported are kept past the 14-day window, up to 30 days. `/gf export`
  is built over several frames, so a big save no longer stalls the game, and its text is let go when the
  window closes, and a character with over 214k gold no longer stops it. A loss in the chat reads
  "-1s 50c", not "98s 50c".
- The mail helper takes one mail at a time, so a slow inbox cannot start a second run.

## 0.15.0 (never released on its own; part of 0.16.0)

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
