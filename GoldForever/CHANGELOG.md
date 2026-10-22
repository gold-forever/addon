# Gold Forever

## 0.14.1

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
