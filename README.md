# LootZ for WoW Ascension (3.3.5a)

A port of **LootZ - The Loot Wikipedia** by Aleksander Fimreite (Ledii) to the
3.3.5a client that WoW Ascension uses.

LootZ shows you the full loot table of whatever you are looking at, and keeps
statistics of everything you personally loot.

The original addon is on CurseForge:
<https://www.curseforge.com/wow/addons/lootz-wotlk>. It targets the modern
client, so it does not run on 3.3.5a as-is - this fork fixes that.

---

## Install

**1. Copy the addon in**

Put this folder into your Ascension client's AddOns folder, named exactly
`LootZ`:

```
<your Ascension client>/Interface/AddOns/LootZ/
```

If you use the Ascension Launcher, the client usually lives under
`Ascension Launcher/resources/client/`. The folder is correct when you see
`Interface/AddOns/LootZ/LootZ.toc`.

**2. Add the loot database (important)**

The loot tables themselves are not in this repository - they are very large and
they belong to the original author. Without them the addon still runs, but the
**Data** tab has nothing to show.

1. Download **LootZ** from
   [CurseForge](https://www.curseforge.com/wow/addons/lootz-wotlk) (the WotLK
   files - `LootZ 1.2.x.zip`).
2. Open the zip and find the `Database` folder inside it.
3. Copy that whole `Database` folder into your `LootZ` folder, replacing the
   one that is already there.

You should end up with files like
`LootZ/Database/WotLK/CreatureLoot.lua`.

> If the folder inside the zip is named something other than `WotLK`, either
> rename it to `WotLK` or edit the `Database/...` lines at the bottom of
> `LootZ.toc` so they match the real file names.

**3. Enable it**

At the character screen, click **AddOns** and make sure LootZ is checked. If it
shows as out of date, tick **Load out of date AddOns**.

Type `/lootz` in game to check it loaded.

---

## Using it

| Action | What it does |
|---|---|
| `CTRL` + left click a creature | Opens its loot table (`CTRL` is the default, change it in the options) |
| `CTRL` + left click an item | Opens that item's loot table - what a container holds, or what prospecting, milling or disenchanting it gives. Works anywhere the game shows an item tooltip: bags, bank, character sheet, merchants |
| Mouse over a creature | Tooltip shows how often you looted it, and what you got |
| `ALT` while hovering a row | Shows the item tooltip |
| `SHIFT` + click a row | Puts the item link into your chat box |
| `CTRL` + click a row | Previews the item in the dressing room |
| `ESC` | Closes the panel |

## Options window

Everything is on one screen. Open it with the **#** button in the loot window
header, or:

```
/lootz options
```

It has:

- **Statistics** - record the loot you pick up, show statistics in unit
  tooltips, use statistics shared by other players, credit loot your companion
  picks up.
- **Chat** - the welcome message, warnings, errors, problem reports while
  gathering, and debug logging.
- **Hotkey** - click to cycle the modifier between `SHIFT`, `CTRL` and `ALT`.
- **Collected data** - how many creatures and lootings you have recorded, how
  much shared data is loaded, and how many deaths the companion tracker has
  seen. That last number is the quickest way to tell whether companion looting
  is working.
- **Where is my data?** and **Reset data**. Reset asks for confirmation before
  it wipes anything.

Hovering an option explains what it does. The window can be dragged, and closes
with `ESC`.

Every setting still has a chat command, so nothing that worked before is gone.

---

Useful commands (`/lz` works too):

```
/lootz options           open the options window
/lootz help              list every command
/lootz controls          list the hotkeys
/lootz creature 3561     show a loot table by creature id
/lootz object 1731       show a loot table by object id
/lootz keybind           rebind the modifier key by pressing it
/lootz stats gather      stop or resume recording your own loot
/lootz companion         credit loot that a companion picks up for you
/lootz shared            use (or ignore) statistics shared by other players
/lootz export            show where your statistics are saved
/lootz diag              report how kills are being detected
/lootz debug             log loot events, for reporting problems
/lootz reset             wipe everything the addon recorded
```

The panel has two modes, switched with the button in its header:

- **Data** - the loot table from the database.
- **Stats** - what *you* have actually looted, counted per creature.

---

## Loot picked up by a companion (Lootbot 3000)

A companion that loots for you never opens a loot window, so the addon has
nothing to attach the loot to. The only trace left is the chat line
*"You receive loot: ..."*, which does not say which creature it came from.

Turn it on with:

```
/lootz companion
```

### How a kill is spotted

Ascension's combat log does not report deaths to addons at all, and at max
level there is no experience message either, so the addon uses four sources:

1. **Watching creatures die.** Any creature seen alive and then seen dead, on
   your target, mouseover or focus, is a kill. This needs no combat log and no
   experience, so it is the one that works at max level. You do not need the
   mouse on it at the moment it dies, and the loot can turn up long afterwards.
2. **The combat log.** Carries a GUID, so the creature is known exactly. Used
   wherever it works, which is not on Ascension.
3. **The kill text in chat** - *"Scourge Champion dies, you gain 213
   experience."* Below max level this catches kills you never targeted. It only
   carries a name, so the addon remembers the name and id of every creature you
   target or hover; **seeing a creature once, ever, is enough**, and the list is
   saved between sessions.
4. **A corpse under the cursor**, only while nothing else has reported a kill.

A corpse that was already dead the first time you saw it is somebody else's
kill, and is never counted.

**What this means at max level:** a creature has to pass under your target,
mouseover or focus at some point while alive. Anything you kill purely with
AoE, without ever touching it, cannot be counted, so sample counts run low and
drop rates read slightly high. Tab targeting through a pull is enough to fix
that.

### How the counting works

With a companion looting there is no per corpse loot window, so **the kill is
what counts as a sample**, and the chat messages supply the items. That is what
makes several kills at once work: three dead Scourge Champions are three
samples, and the three drops that follow are three drops, instead of all of it
landing on one corpse and reporting a 300% drop rate.

While companion looting is on, the loot window stops recording, because the
same items also arrive in chat when you loot by hand. Nothing is ever counted
twice.

### What it will not guess at

- Loot arriving after a kill it could not identify is **dropped**, not credited
  to the previous creature. If that happens, target that creature once and it
  will be recognised from then on.
- Loot from a chest, herb or ore node is never credited to the last creature
  you killed.
- Loot with no kill behind it at all is ignored, and the addon says why -
  either the last kill was too long ago (it prints how long), or nothing has
  reported a kill yet.
- **Still turn it off in a group.** Several people killing different things at
  once is beyond what a name and a timestamp can sort out.

`/lootz diag` is the quickest way to see whether this is working. It reports
how many kills were found, broken down by which of the four sources found them,
how many creature names are remembered, and whether the combat log is saying
anything at all. `/lootz debug` additionally prints every loot event as it
happens and the reason any kill was ignored.

---

## Where your data is saved, and how to share it

Type `/lootz export` in game and it prints the path plus how much you have
gathered. The file is:

```
WTF\Account\<YOUR ACCOUNT>\SavedVariables\LootZ.lua
```

It is written when you log out or `/reload`, **not** while you play - so
`/reload` before copying it. It is per account, not per character, and it
survives reinstalling the addon. If you want a backup, that one file is all you
need.

### Sharing it (and pooling with other people)

Copy that `LootZ.lua` somewhere, then turn it into a shareable file:

```
lua5.1 Tools/MergeStats.lua Database/Shared/SharedStats.lua path/to/LootZ.lua
```

Commit `Database/Shared/SharedStats.lua` and anyone who downloads the addon
gets your numbers. The addon loads it at startup and **merges** it with each
player's own statistics in the Stats view, so downloading someone else's data
never overwrites your own. Anyone can hide it again with `/lootz shared`.

To pool data from several players, pass every file at once - looting counts and
drop counts are added together, and the smallest and largest stack sizes are
kept:

```
lua5.1 Tools/MergeStats.lua Database/Shared/SharedStats.lua alice.lua bob.lua carol.lua
```

The tool also reads the file it produced last time, so you can keep adding to
it as people send you more:

```
lua5.1 Tools/MergeStats.lua new.lua Database/Shared/SharedStats.lua dave.lua
```

Output is sorted and deterministic, so git diffs stay readable and two runs on
the same input produce byte-identical files.

> You need Lua 5.1 to run the tool (`sudo apt install lua5.1`, or
> `brew install lua@5.1`). If you would rather not, just commit your raw
> `LootZ.lua` to the repo and I - or anyone else - can convert it.

---

## What to expect on Ascension

Ascension is a custom server, so be aware of the difference between the two
modes:

- **Stats mode is always correct.** It only counts loot you saw with your own
  eyes, on this server.
- **Data mode is Blizzard's original WotLK data.** Wherever Ascension changed a
  drop rate, added custom items, or rewrote a loot table, the Data tab will not
  match the server. Treat it as a reference, not as truth.
- Custom Ascension items may show up as *Slow Loading Trinket* style
  placeholders or take a moment to appear. The addon asks the server for any
  item the client has not seen yet and redraws the list once it arrives.
- Creature names in `/lootz creature <id>` only appear for creatures you have
  already looted. Otherwise you get `Creature #<id>`, because the 3.3.5a client
  cannot look a creature name up by id.

---

## What was changed in the port

The 3.3.5a client is missing a lot of what the original addon assumed. All of
the client differences live in one new file, `Compat.lua`, so the rest of the
addon reads the same as upstream. It feature-detects, so the addon still works
on the retail and Classic clients it was originally written for.

| Original (modern client) | 3.3.5a replacement |
|---|---|
| `C_Timer.After / NewTimer / NewTicker` | Polyfilled on an `OnUpdate` driver |
| `C_AddOns.GetAddOnMetadata` | Falls back to the global `GetAddOnMetadata` |
| `Item:CreateFromItemID` + `ContinueOnItemLoad` | Item request queue that asks the server, then calls back |
| `GetItemInfoFromHyperlink` | Reads the id out of the link |
| Dashed GUIDs (`Creature-0-970-...`) | Parses the 3.3.5a hex GUID (`0xF130000DE9000E38`) |
| `GLOBAL_MOUSE_UP` / `GLOBAL_MOUSE_DOWN` | Mouse buttons are polled and reported the same way |
| `LOOT_READY` | The loot source is resolved on `LOOT_OPENED` instead |
| `CURSOR_CHANGED` | `CURSOR_UPDATE` |
| `C_Map.GetBestMapForUnit` | `GetCurrentMapContinent` / `GetMapContinents` |
| `UnitPosition` | Not available at all, object distance checks are skipped |
| `SetPropagateKeyboardInput` | Keyboard is only captured while binding a hotkey, so it never eats your keys |

Fixes made along the way, which also apply to the original:

- The addon crashed on the very first login, before its saved variables existed.
- Missing loot database files caused an error on every single lookup instead of
  one clear message.
- Items the client had not cached yet were dropped from the list and never came
  back. They are now redrawn once they arrive - this matters a lot on 3.3.5a,
  where almost nothing is cached on a fresh install.
- Shift or ctrl clicking a group header row threw an error.
- Frames were created with generic global names (`MainPanel`, `Row`, `Icon`),
  which could collide with other addons.
- The coin string is now parsed per locale instead of assuming English word
  order.

---

## For developers

There is a mock of the 3.3.5a API in `Tools/`, so the addon can be run outside
of the game. It loads every file listed in `LootZ.toc`, then plays through a
session: login, looting a creature, the tooltip, opening the panel, the sort and
data buttons, the row hotkeys, every slash command, a world object, companion
looting, shared statistics (round tripped through `Tools/MergeStats.lua`), and a
missing database.

```
lua5.1 Tools/SmokeTest.lua
```

It exits non-zero if anything fails. The mock deliberately leaves out everything
3.3.5a does not have, so any modern API that sneaks back in fails there the same
way it would fail in game.

`Tools/` is not shipped to the client - it is not referenced by the toc.

---

## Credit

All of the actual addon is the work of **Aleksander Fimreite (Ledii)**, and the
loot database is his too. This repository only carries the 3.3.5a port. If you
like the addon, go give the original a thumbs up on
[CurseForge](https://www.curseforge.com/wow/addons/lootz-wotlk).
