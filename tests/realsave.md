# The addon on a real save

The smoke test can play a copy of a real `GoldForever.lua` instead of its own session: the save's
character logs in, then every hub page and tab in every look, the Settings tabs, the HUD, the auction
house panel's tabs, the mailbox, an item tooltip for every catalogued item, and logout. Each step is
timed with the memory it allocated; errors the addon recorded during the run fail it.

```sh
cp "<WoW>/_retail_/WTF/Account/<account>/SavedVariables/GoldForever.lua" /tmp/save.lua   # a copy, never the file
GF_SMOKE_INTERFACE=120105 GF_SMOKE_SAVE=/tmp/save.lua GF_SMOKE_GUID=Player-3666-098F9386 \
  luajit tests/smoke.lua GoldForever
```

`GF_SMOKE_GUID` picks the character (any key of the save's `characters`); without it, the first one.
On retail, `GF_SMOKE_CONNECTED` lists the realm's connected realms as the client does (the owner's
Shadowsong: `Aszune,Shadowsong`), which name its market; without it, the realm alone.
The run writes nothing back. Timings are of the addon's Lua against stand-in frames, so they show
where the addon's own work grows with the data, not what the client spends drawing.

First run, 2026-10-24, on the owner's retail save (11 MB file, 20 873 catalogued items, three
characters): no errors as any of the three; the save alone holds 13.4 MB, 19.4 MB after the whole tour;
every page under 3 ms; a tooltip for each of the 20 873 items in 160 ms together.

## The made-up big save

`tests/bigsave.lua` writes a save of the same shapes and size with every value generated (20 000 items,
three characters, two markets of 110 000 scan rows, fourteen days of events), so the same tour runs with
no one's data: `npm test` runs it on both clients when `luajit` is installed, and CI always does. A step
over `GF_SMOKE_BUDGET_MS` (1000 by default) fails the run.

What it found first (2026-10-24): the Mobs tab counted every loot row in one frame (now a chunk a frame
from 20 s after login), a folded tab refreshed the page's previous tab before its own, and the Ledger,
Sales and Levelling tabs split every character's rows to keep one's (now passed over unsplit). Revisiting
every page: 116 ms to 13 ms.
