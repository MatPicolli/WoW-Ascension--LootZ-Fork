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
| `CTRL` + left click a creature | Opens its loot table (`CTRL` is the default, change it with `/lootz keybind`) |
| Mouse over a creature | Tooltip shows how often you looted it, and what you got |
| `ALT` while hovering a row | Shows the item tooltip |
| `SHIFT` + click a row | Puts the item link into your chat box |
| `CTRL` + click a row | Previews the item in the dressing room |
| `ESC` | Closes the panel |

Useful commands (`/lz` works too):

```
/lootz help              list every command
/lootz controls          list the hotkeys
/lootz creature 3561     show a loot table by creature id
/lootz object 1731       show a loot table by object id
/lootz keybind           rebind the modifier key (SHIFT / CTRL / ALT)
/lootz stats gather      stop or resume recording your own loot
/lootz reset             wipe everything the addon recorded
```

The panel has two modes, switched with the button in its header:

- **Data** - the loot table from the database.
- **Stats** - what *you* have actually looted, counted per creature.

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
data buttons, the row hotkeys, every slash command, a world object, and a
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
