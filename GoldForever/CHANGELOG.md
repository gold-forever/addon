# Gold Forever

## Unreleased

- **Gear prices on the Sell tab read right.** An item's buyout in a search is the price of one, as Blizzard's sell window shows it. The Sell tab divided it by how many were listed, so 23 Large Knapsacks at 1g each read as 4s 35c each, and the suggestion held the item under its floor with "Post anyway" at 3s 55c. The Cancel view read your own gear auctions the same way.
- **The tooltip's stack price and Suggestion with any bag addon.** The price block now reads the bag and slot from the tooltip itself, so with any bag addon (OneBag, Bagnon, ArkInventory, Baganator and others), in the bank and in Blizzard's bags, a stack shows its total (each), for example "AH 2s (50c/each)", and the Suggestion line. A merchant's or the auction house's item still shows one unit and no Suggestion. The marks on bag buttons are still drawn on Blizzard's bags only.
- **Your alts' gear is not undercut.** On gear and other items that are not commodities, the Sell tab now treats a listing by any of your characters on the realm as your own: it is left out of the cheapest price, marked "yours" in the listings, and not counted as ahead of you in the Cancel view. A listing your alt shares with another player still counts. Commodity search results do not name sellers, so for commodities your alts' listings still count as other players'; the Sell tab says so.
- **Cancel the undercut, and repost what would sell higher, from the Sell tab.** "Cancel >" on the Sell tab opens a Cancel view of your own auctions. "Check my auctions" searches each one live. The view then lists them in two lists, each with its reason. Undercut: more units than your tolerance are listed under yours, for example "10 ahead, cheapest 40s". The tolerance is 3 items at first; choose 0, 3 or 10 under "Undercut by more than". Repost higher: the cheaper listings sold, and your rule would now post more than 10% higher, for example "Cheaper ones sold: 59s now (+96.7%)". Cancel next, or Space while the view shows, cancels one auction a press, the undercut ones first, and shows the cancel cost. The items come back by mail, to post again from the Sell list. "< Sell" goes back.
- **Vendors know their side.** A vendor you visit now records whether you came as Horde or Alliance, as trainers already do, so the site can tell which side can buy a recipe there. A vendor seen by both sides counts as neutral. Vendors you visited before get a side the next time you open their window.
- **One price block in item tooltips.** An item's tooltip now shows one block, in this order: in your bags, Suggestion first (post, vendor, disenchant or keep, and why), then Vendor (what a vendor pays), AH (the market value), AH (min) (the cheapest listing) and Disenchant (the average value of disenchanting one, on items that can be disenchanted). A post names its listing price and what you get after the 5% cut, for example "Suggestion: Post at 4g 10s (you get 3g 89s)": the price the Sell tab would post at against your last scan, else the market value. On a stack each price reads total (each), for example "AH 2s (50c/each)"; a single item shows the price alone. A line with no value is left out. The block replaces the separate price, scan, disenchant, verdict and supply lines (how many sell a day stays on the Sell tab). Each line has its own setting under Settings, Tooltip: Vendor and AH show always, the rest with Shift. Your earlier choices carry over: AH and AH (min) take the price line's, Disenchant and Suggestion keep theirs.
- **Throw away the cheapest stack.** While your bags are full, a "Throw away cheapest" button appears beside Blizzard's backpack. It deletes the stack the copper coin marks. That is never soulbound, a quest item, or anything on a shopping list or in the craft queue. The first press shows the item and its worth on the button. A second press within 5 seconds deletes it, and one chat line says what went and what it was worth. Turn it off under Settings, Modules, Throw-away button.
- **Sell prices from a live search, against outliers only.** The Sell tab now posts only after a live search of the item, and undercuts the cheapest listing by another player, never your own. Until that search answers, the list shows the last scan's price and the Post button says "Searching...". Undercuts are no longer capped at 120% of the market value, so in a rising market you post just under the others. The cap is now a maximum of 3× the market value, 5× on items the site tags highly volatile, and above it you post at the maximum. The floor is the higher of your floor (80% of the market) and what a vendor pays after the auction house's cut. With nobody else listing, you post at the higher of 120% and today's price. Holding more than 2 days of sales, Sell suggests posting 2 days' worth, with a "Post all" button beside it. Every suggestion names its reason, for example "Undercut 1s (live)", "At the maximum, 3x market", "Held: under the vendor price", "Alone: 120% of market" or "2 days of supply". The maximums and the days are under Selling rules (Maximum, Volatile maximum, Post size), and sale plans use the same maximum, vendor floor and own-listings rule. The volatile tag and today's price come from the companion's price file, so update the companion app: with an older one's file every item uses 3× and 120%, as before.

## 0.20.0 (2026-11-11)

- **Gold Forever speaks Spanish and Brazilian Portuguese.** On a Spanish client (Spain's, and Latin America's, with its own words such as Calabozo) and on a Brazilian one, the addon is in that language, with the game's own terms (Casa de subastas, Casa de Leilões). Money shows as each client writes it (1o 9p 25c), and a price box takes it that way. As for French and German, the translation was made with AI and the addon says so once at login and at the top of Settings.
- **Gold Forever speaks Korean and Chinese.** On a Korean client and on a mainland or Taiwanese Chinese one, the addon is in that language (Simplified or Traditional), with the game's own terms (경매장, 拍卖行, 拍賣場), drawn in the client's own font. Money shows in the client's coins (1골 9실 25코, 1金 9银 25铜), and a price box takes it that way. As for the other languages, the translation was made with AI and the addon says so once at login and at the top of Settings.
- **Crafts, kill XP, reputation and auction sales are read on every client's wording.** Some clients write grammar into the game's messages (Korean's particles, French's "de"/"d'", Russian's plurals), and the addon missed those lines: Korean crafts and kill XP, French reputation and sold auctions. It now reads each form.
- **Gold Forever speaks Italian and Russian.** On an Italian or a Russian client the addon is in that language, with the game's own terms (Casa d'Aste, аукцион), and every look keeps its fonts, which have Cyrillic. Money shows as each client writes it (1o 9a 25r, 1.234o; 1з 9с 25м, 1234з), and a price box takes it that way. Sales, mail, reputation, XP and crafts are read in each client's own words, Russian's plural words included. As for the other languages, the translation was made with AI and the addon says so once at login and at the top of Settings.
- **Headings in capitals in every language.** Tabs, column titles and Settings headings are in capitals with their accents (É, Ü, Ñ, Œ) and in Cyrillic (СЕССИЯ); Korean and Chinese have no capitals and show as they are.
- **Large numbers are grouped as the client groups them.** The addon read the client's thousands separator under a name the game does not use, so it grouped with commas on every client: now German, Brazilian and Italian group with points ("1.234g"), Latin-American Spanish and English with commas, and French, Spanish (Spain) and Russian do not group, as their game does. A price box reads them the same way.

## 0.19.0 (2026-11-11)

- **Gold Forever speaks French.** On a French game client every window, tooltip, chat line and `/gf help` is in French, with the game's own terms (Hôtel des ventes, po/pa/pc). The translation was made with AI, and the addon says so once at login and at the top of Settings. Other clients stay in English. Sales, mail, reputation, XP and crafts are read in the client's own language, so they are recorded on a French client too. The saved file is the same in every language.
- **Gold Forever speaks German.** On a German game client the addon is in German, with the game's own terms (Auktionshaus, Verzauberkunst, Entzaubern). Money shows as the German client writes it (1g 9s 25k, 1.234g), and a price box takes it that way, "1.000" being a thousand gold. As for French, the translation was made with AI and the addon says so once at login and at the top of Settings.
- **Farm toward a number: item goals on the HUD.** On the Shopping lists page, choose an item with How many set and switch Goal on. While you farm, the HUD shows it under its line, for example "34/40 Linen Cloth · about 12m at this pace". The count is your bags plus your bank as of your last visit. The pace comes only from what you looted this session, so items you buy, get by mail or trade raise the count but not the pace. Before you have looted any it says "no pace yet". A reached goal gets a tick and one chat line. Up to 3 goals show; turn them off under Settings, Modules, Item goals.
- **No more phantom professions.** A profession window could briefly list another profession's recipes, and a character then got an empty row such as "Skill line 197" on the site, for a profession they don't have. It no longer records one.

## 0.18.0 (2026-11-09)

### Selling

- **See how fast an item sells and how many to post.** With a companion that carries sales, the Post screen
  says, for example, "about 6 sell a day · 84 listed: about 14 days of supply · post up to 12", and Post's
  quantity starts at that size: about two days of sales, at most what you hold. A number you chose for an
  item, or a sale plan's quantity, still wins. Hold Shift over an item to see the same line in its tooltip,
  or change that on the Tooltip tab (Supply and post size). The merchant's resale line now says how many
  sell a day, and an item the prices say did not sell in the last week is no longer marked.
- **See what a merchant sells for less than the auction house pays.** At a merchant, a small gold coin marks
  items whose auction price after the 5% cut beats the vendor's price by at least 20%, and the tooltip says
  "Resell: 4g 98s on the AH · +3g 83s after the cut". Only items with a lasting price count: a typical price
  from the companion's prices, or seen in at least two of your own full scans. Limited stock says "(limited)";
  items costing tokens or honour are never marked. Turn it off under Settings, Modules, Vendor resale, and
  choose when the line shows on the Tooltip tab.
- **The wide Sell tab, laid out again.** The list and the chosen item each take half the page. Beside
  the list is where you decide and post: the price in large type with its reason and why, your floor,
  the typical price and the cheapest other listing, quantity, 12h · 24h · 48h, a full-width Post button,
  and the deposit. Under it, the item's listings as a table: price, stack and count for gear, price and
  quantity for commodities, yours marked; the wheel scrolls it. Prices show in full (6g 98s 99c). Held
  under your floor, the price reads Held and the plain Post anyway button asks for a second press.
  The narrow layout is unchanged.
- **A sound and a chat line when one of your auctions sells.** While you are logged in, a sale plays
  the coin sound and says what sold and what you will get after the auction house's cut, for example
  "sold Linen Cloth x20 for 1g 20s (arrives by mail)"; when the addon did not see the post, the line
  names the item only. The sound plays only when the game's sound is on. Turn it off under Settings,
  Modules, Sale alert. The sale is still recorded from the mail, as before.

### Bags, loot and quests

- **See what to do with each bag item.** A small mark on items in your bags and bank says post on the auction
  house, sell to a vendor, or disenchant; items to keep have none. Hold Shift over an item for the same word
  and why, for example "Verdict: post (AH 1g 20s after the cut, vendor 15s)". Items on a shopping list or in
  the craft queue, soulbound gear and quest items are always keep. Nothing is moved or sold. Turn it off under
  Settings, Modules, Bag verdicts, and choose when the line shows on the Tooltip tab.
- **With your bags full, a copper coin marks what to drop.** When no bag slot is free, the stack worth least
  in all (by the addon's prices: the better of the auction after the cut and the vendor) gets a small copper
  coin in its slot's corner, and its tooltip says "Cheapest in your bags" with what it is worth. Soulbound and
  quest items, and items with no price, are never marked. Free a slot and the coin goes. The addon never
  moves or deletes anything. Blizzard's own bags only for now. Turn it off under Settings, Modules,
  Cheapest in full bags. The Modules list now scrolls with the mouse wheel, as it has grown past the page.
- **A loot roll shows what the item is worth.** On a Need/Greed roll, a small line under the item's name
  gives its auction and vendor value, for example "AH 1g 20s · vendor 15s", so you can choose Greed or
  pass without hovering. A price the addon does not know shows as "?". It never rolls for you. Turn it
  off under Settings, Modules, Loot roll value.
- **The quest reward worth the most to sell is marked.** When a quest offers a choice of rewards, the
  one worth the most carries a small gold coin in its corner, so you can take the gold without hovering
  each one. Its tooltip says what it is worth, for example "Best to sell: 1g 20s", the better of the
  auction price after the cut and the vendor price, times how many the quest gives. A reward without a
  price is left out and counted: "(1 reward unpriced)". Turn it off under Settings, Modules, Best quest
  reward.

### Crafting

- **See what learning a recipe is worth.** Hold Shift over a pattern, plans, formula or schematic whose recipe
  you have seen in a profession window: "Pays back in 7 crafts at today's margin (2s 10c a craft)", or "No
  profit at today's prices". It uses the vendor's price when a vendor sells it, else the market value, and
  shows nothing when either is unknown. A pattern that makes gear is greyed and adds "gear prices are rough".
  Choose when the line shows on the Tooltip tab (Recipe payback).
- **Reagents you choose.** A recipe slot you fill with your choice of reagent (any of several herbs, or a
  herb's qualities) is recorded with every choice. The crafting strip shows it as one line, "any of: …"
  with the cheapest first, and prices it at the cheapest choice you hold or can buy; the Crafting page
  and the Buy tab's Craft queue list use that choice too. Wild Experimentation no longer records the
  herbs it takes as what it makes. Open each profession window once to record its recipes anew.
- **The crafting strip reads more recipes right.** A recipe with a random result (Wild Experimentation)
  no longer shows a count in its title: the 20 was the herbs it takes. The To buy lines wrap instead of
  being cut off, and the strip grows to fit them.

### Farming and goals

- **See what a farming session came to.** When a session ends, after 15 minutes without loot or when you press
  Stop, a small card shows its time, the gold looted, what the items are worth, gold an hour, kills and the
  best drop. It waits until combat ends, and closes on a click or after 30 seconds; a Recap button on the HUD
  brings it back until the next session starts. Sessions under 5 minutes or with nothing looted show no card.
  Turn it off under Settings, Modules, Session recap.
- **Hear when your best farm changes.** Turn on Settings, Modules, Best farm changed, and after new prices
  (at login, with the companion's prices, and after a full scan) the addon picks the mob this character has
  looted at least 10 times whose loot is worth the most. When that is another mob than before, one chat line
  says so, for example "best farm now Bristleback Quilboar (Barrens), about 24s a loot (was Kolkar
  Centaur)". The first check says nothing; it only remembers the mob. Off by default.
- **Home's goal line reads cleanly.** With a goal set, the line shows the goal, how far you are and an
  X that cancels it: the first press asks, a second within 5 seconds cancels. Without a goal, it shows
  your gold across your characters, the amount field, the days and Set.

### Tooltips and prices

- **Choose which tooltip lines show, and when.** Settings has a new Tooltip tab listing every line the
  addon adds to a tooltip: auction prices, your scan, held counts, disenchant value, mob loot, quest
  starters, best quest reward and cheapest in your bags. Set each to Off, With Shift or Always. With
  Shift, the line appears while you hold Shift over the item or mob, and the open tooltip updates as you
  press or let go. By default the prices show always and the rest with Shift, so tooltips stay short. If
  you had switched off prices or held counts in tooltips, they stay off; if you had switched them on, they
  show always. Those two switches have moved from Modules to the Tooltip tab.
- **Prices from Auctionator when there are no others.** If an item has no price from the companion or your
  own scan and Auctionator is installed, Gold Forever uses Auctionator's price. Tooltips and the Sell tab
  label it "Auctionator". The companion's prices and your scans always come first.
- **Other addons can read Gold Forever's prices.** A new read-only table, `GoldForeverAPI`, gives an addon an
  item's market value with its source, age and number of players (`GetPrice`), what a vendor pays
  (`GetVendorPrice`) and what disenchanting it is worth (`GetDisenchantValue`). Nothing changes for you unless
  another addon uses it.

### What the addon records

- **Retail items now note their expansion.** The item list in your save records which expansion each retail
  item belongs to, so the site can pool disenchants by expansion: each has its own dust, essence and shard.
  Items already in your list get theirs over the first minutes after login. WoW: Forever is unchanged.
- **Trainers now remember where they stand.** When you open a trainer's window, the addon also notes the
  trainer's map position and your faction, so the site's skill plan can name the nearest trainer for your
  side. Trainers you visited before keep their spell lists and get a place the next time you visit them.
- **What your disenchants give now counts.** The loot of a disenchant is saved with the item you
  disenchanted, so once uploaded it joins what the site shows that items of its kind disenchant into.
  Containers are recorded as before.

### Fixes

- **Finding a rare no longer shows "GoldForever has been blocked from an action only available to the
  Blizzard UI".** The game now only lets a key press set a raid mark, so the addon no longer puts a skull
  on a rare by itself. The rare alert ends with "/gf mark to skull it": type it (or put it in a macro on a
  key) with the rare targeted or under the mouse, or while its nameplate shows. The setting is now "Offer a
  skull mark (/gf mark)".
- **When the auction house panel cannot load, chat says why.** If the GoldForever_Auctions folder is
  not installed, the line says so and to reinstall (or, in a developer install, to link both folders);
  if it is turned off in the AddOns list, it says to turn it on. Once a session, and no longer an error
  in /gf check; an old MISSING entry there goes once the panel loads.
- **Find out why bag marks do or don't show.** `/gf bags`, with your bags open, prints which bag frames exist,
  the item buttons found, a sample item and its verdict, the marks showing, both switches, the last error of
  each, and whether a replacement bag addon (Bagnon, ArkInventory, Baganator, AdiBags) is loaded.

## 0.17.0 (2026-11-04)

- **Coin looted fast is kept.** With auto-loot, looting several corpses in a row could leave a corpse's
  loot with no coin while the money still arrived. A coin rise no loot window took is now given to the
  window whose coin it is, if it comes within two seconds; no rise is counted twice.
  Loot in old raids where the game gives no map, such as Molten Core, now records the instance it
  was looted in.

- **The mail panel no longer covers an opened mail.** The Gold Forever box at the mailbox now sits under
  the inbox, or to its left when there is no room below, never where the opened mail shows. When a mail
  opens, closes or is moved by another mail addon, the box moves out of its way, at any UI scale.

- **Mobs whose tooltip the game hides are no longer looked up every session (retail).** Retail hides
  the tooltip of a mob looted in a delve or dungeon, even after the loading screen out of it. Such a mob
  is now left alone for 10 sessions, or until you loot it outside an instance. Where the tooltip can be
  read, the mob is filled as before.

- **Stale prices show beside the window's X.** While everyone's prices are over a day old, the main
  window shows it small, in the look's warning colour, left of its close button: "Prices 38 h old", then
  in days from two days. It goes once fresh prices are loaded, as the login warning does.

- **Previous and Next under the wide Sell list.** In the Sell tab's wide layout, when your items fill
  more than one page, Previous and Next buttons and the page you are on (such as "2 / 4") sit under the
  list at its right. Each is off at its end; the mouse wheel still pages. The narrow layout is unchanged.

- **The auction house's Sell tab can be wide.** A Wide button beside Rule › on the Sell tab widens the
  panel: the list of items to sell gets more rows and more width, and the chosen item's prices, listings
  and Post button stand in a column beside it. Narrow brings back the layout you know. Your choice is
  remembered. Only the Sell tab widens, never over the auction house; where the screen has too little
  room beside it at your UI scale, the tab stays narrow and says so.

- **Mobs from delves and dungeons get their creature type (retail).** The game shows a mob's type on
  its own line under "Level ?? (Elite)"; that line is now read, so a delve's mobs are stored as Beast,
  Humanoid and so on rather than with no type. A mob already stored without a type gets it the next
  time you loot it, after the loading screen when you loot it in an instance.

- **Every auction house sale's gold is tagged mail+sale.** When gold from several mails taken quickly
  arrived in one step, only the first mail was tagged and the rest was left plain mail; each mail's gold
  is now its own Ledger row with its own kind.

- **`/gf probe` opens a box to copy from.** Its lines now also show in the same copy box as `/gf check`,
  already selected, so Ctrl+C takes them whole to paste into an issue or a chat. Escape closes it.

- **Mobs named later get their creature type and level more often (retail).** A mob looted in an
  instance and named afterwards now takes its type from its tooltip's own words when the game's list of
  creature types doesn't name it, and a level the game colours by difficulty is read as a level. A mob
  shown at level ?? still gets no level. `/gf probe` now shows the last looted mob's whole tooltip.

- **Gold taken from mail says what kind of mail it was.** The Ledger's mail rows now tell an auction
  house sale (mail+sale), a bid given back when outbid or the auction was cancelled (mail+outbid), other
  auction house mail (mail+auction), mail from an NPC, the game or a GM (mail+npc) and a player's mail
  (mail+player); gold from your own characters stays mail+transfer. Only the kind is kept, never a
  sender's name or a subject. Plain mail is left only when the kind can't be told.

- **The guild bank's gold and your rank's withdrawals are recorded.** At the guild bank the addon now
  also saves the bank's gold, how much gold your rank may still take today, and for each tab you can
  view how many items a day your rank may take from it, so the site can count only what you can take.

- **Items you already had get their crafting tier (retail).** Items catalogued before the tier column
  was added kept their old row, so none of them got a tier. After login, and whenever you see such an
  item, the addon now asks the game for its tier once a session and adds it to the row. It never asks
  during a fight. WoW: Forever is unchanged.

- **Late loot coin is counted as loot in the Ledger.** Coin that came in more than two seconds after a
  loot window opened or closed, from a window kept open a while or a slow server, was shown as Other.
  Coin the loot window takes as its own is now tagged loot, up to the five seconds it waits after closing.

- **The "Bag advice at vendors" switch is gone.** It did nothing since the "your loot" window was
  removed, so it no longer shows in Settings → Modules, and the Everything preset on the first-run card
  no longer mentions bag advice. An older save's setting is left as it is and is no longer read.

- **Lists at the auction house keep their place.** Clicking an item on page 2 or further of the Sell,
  Buy or Auctions list sent the list back to page 1, as did the search results and auction checks that
  follow. The list now stays on the page you were reading, and the item you clicked stays chosen.

- **The "your loot" window is gone.** The unskinned "Gold Forever · your loot" window no longer opens
  at vendors, and `/gf bags` is gone with it. On WoW: Forever, whose merchant window has no Sell All
  Junk button, the Sell junk button now sits under the merchant window: the first press says what it
  will sell, the second sells.

- **Every loot window keeps its coin.** Some loot windows recorded no coin while the money came in, so a
  session's gold and the mob ranking came out short: in a group the coin of one window can come as
  several shares, a moment late, or before the window shows it taken. Every share is now counted with
  its window, the window's loot is recorded once its coin is in (up to five seconds), and windows are
  still recorded in the order they closed.

- **Each quality tier of a crafted item or reagent is told apart.** On retail the save records each
  item's crafting quality tier (1-3 for reagents, 1-5 for crafted gear and consumables), so the site
  can tell the tiers of, say, Argentleaf apart. It is read when an item is first recorded, never in
  combat: an item met in a fight is recorded once it ends. WoW: Forever has no tiers and records none.
  Gold Forever on the site must be up to date to read saves from this version.

- **Every dungeon floor is named.** A floor you reach without a zone change, as on some floors of
  Windrunner Spire, showed as "Map 2494" on the site for the XP and loot recorded there. Every map a
  row records is now added to the catalogue with the zone above it; in combat, once the fight ends.

- **Items a vendor sells for currency are named too.** Opening a vendor now records the name, quality
  and icon of everything it sells, not only what it sells for gold, so a recipe bought with currency or
  tokens shows its name on the site and as sold by that vendor. Vendor prices are still recorded only
  for gold.
- **XP from gathering is its own kind.** XP for picking a herb, mining a vein or skinning a corpse is
  recorded as gathering, not "other", and the Levelling page's XP by source shows it as Gathering, beside
  kills, quests and exploring; the site can show it too once updated. A kill
  or a discovery right next to a gather keeps its own kind. Gold Forever on the site must be up to date
  to read saves from this version.
- **Mobs and chests looted in dungeons and delves get their names.** A mob looted in an instance is
  named once you leave it (at the loading screen), even after a `/reload` or a logout in between; one
  the game still won't name is tried again in each of your next 10 sessions. A chest whose tooltip shows
  its name is named from it when you loot it. On WoW: Forever, a rare seen only on the minimap gives
  the catalogue its name. `/gf probe` (temporary) lists what the game lets the addon read where you
  stand, for the check in game.
- **No more empty squares in the text.** The first-run card's "Settings → General" showed an empty
  square: the arrow is in none of the fonts. Every text the addon shows now uses characters all its
  fonts draw: arrows and chevrons are ">", dashes "-", "…" is "...", "×" is "x" and "≈" is "~".
- **Recipes with a random result say so.** The crafting panel beside your profession window shows
  "random, can fail" for a recipe whose result is random or can fail (Wild Experimentation, the
  transmutations, prospecting), with no sale price or profit, instead of "unknown". Its reagents are
  still costed when their prices are known. Other recipes are unchanged.
- **Mail to your characters on your other WoW accounts counts too.** With the companion running, the
  addon knows the characters of every WoW account linked to your Gold Forever account, so mail to one of
  them on the same realm is recorded as mail to your own character, and its gold is a transfer on both
  sides. Without the companion's list, only the characters this WoW account has played count, as before.
  The game reads the list when you log in or `/reload`: a character the companion adds while you play
  (say, after you first log in on another WoW account) counts from your next `/reload`.
- **When your cooldown crafts are ready again.** For each of your characters, the save records when each
  recipe on a cooldown (transmutes, Mooncloth and the like) can be crafted again. It is read when you open
  your profession window and a moment after such a craft, never in combat. Recipes without a cooldown
  record nothing.
- **Mail to your own characters is known.** When a mail to one of your characters on the same realm is
  sent, its items, gold and cash on delivery are recorded, so items sent to your bank alt are not lost
  while they travel. The gold is shown as a transfer between your characters ("Your characters" in the
  Ledger), not as spent at the mailbox, and again as a transfer when the alt takes it; the postage is
  still mail. Mail to anyone else records nothing about them, as before.
- **No more "Unknown" NPCs.** A mob or NPC read before the client has loaded its name ("Unknown", or the
  word for it in your client's language) is recorded without a name, and its next sighting names it. Your
  save's NPCs already named that way lose the placeholder once. The rare alert shows "?" instead.
- **"Announce dings on Discord" is gone from the game.** Each Discord webhook now picks its own
  characters at gold-forever.app/settings, so the switch in Settings → Discord, `/gf dings` and the
  Companion page's Discord dings card are removed. The choices your save held are cleared once.
- **Your characters' guild, with your rank.** Each of your characters records its guild's name, your rank
  and when it was last seen, or that it is in no guild, so leaving one shows. It is read at login and when
  the guild changes, never in combat. Only your own characters' guild is recorded.
- **The auction house panel loads when you first open the auction house.** It is a second folder,
  GoldForever_Auctions, shown in the AddOns list as Gold Forever Auctions (load on demand); keep both
  folders. A character who never visits the auction house never loads it. Nothing else changes.
- **Sessions by hand.** A new setting, "Start and stop sessions by themselves", on by default, in the
  session HUD's panel and in Settings → General. On, nothing changes. Off, loot and kill XP start no
  session (they are still recorded); the HUD shows Start, and Stop while a session runs. Stop or a logout
  ends it; a /reload keeps it. Each Start and Stop, a logout's end and New session during a running
  session are recorded for the site, so its session is the game's.
- **No session under 10 minutes.** A session that ended less than 10 minutes from its first loot to its
  last is not shown as a finished session on the HUD, in /gf session or on the Session page.
- **Lists for one character.** A shopping list made for one character on the site shows on that
  character only, on the Buy tab and the Shopping lists page; other lists, and the craft queue's, show
  on every character. Importing another character's list makes it yours. A list string with a line Gold Forever does not know yet is still read, that line
  skipped.
- **Sale profiles for one character.** A sale profile made for one character on the site is offered on
  the Selling rules page, and prices the Sell tab, on that character only; other profiles work on every
  character. Importing another character's profile makes it yours. A profile string with a line Gold
  Forever does not know yet is still read, that line skipped.
- **The typical price in the tooltip.** An item's market line shows its typical price, the median of its
  daily prices over the last 7 full days (the price the site calls typical), and today's price against it:
  `Market 12s 34c · typical 11s 0c (+12%) · min 11s 0c`. With no typical price yet, the line is as before.
  The Sell tab says "typical price" and "vs typical" where it said "7-day avg".
- **Shopping lists page messages where you look.** Import's, Export's and Delete's messages show under the
  paste box and its buttons, left-aligned with them, in every look.

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
