# SkillBook - Ashita v4 addon

Version 2.0

## Purpose

SkillBook repeatedly uses an item from your normal FFXI Inventory by queuing the ordinary `/item` command through Ashita.

The original version only recognized a hard-coded list of skill-up books. Version 2.0 instead searches **every item in normal Inventory by partial name**, so books such as **Throwing Weapon Enchiridion** work without needing to be added to a list first.

This also means it can be used with other consumable items that work with FFXI's normal `/item "<name>" <me>` command.

## Install

Place `skillbook.lua` in:

```text
Ashita\addons\skillbook\skillbook.lua
```

Then in FFXI:

```text
/addon load skillbook
```

## Examples

### Throwing Weapon Enchiridion

First see what the addon finds:

```text
/skillbook list throw
```

Select it:

```text
/skillbook set throwing
```

Start repeatedly using it:

```text
/skillbook on
```

Stop:

```text
/skillbook off
```

### Yomi's Diagram

```text
/skillbook set yomi
/skillbook on
```

## Commands

```text
/skillbook set <partial item name>
/skillbook on
/skillbook off
/skillbook status
/skillbook list
/skillbook list <filter>
/skillbook delay 2
/skillbook help
```

`/itemloop` is also accepted as an alias for `/skillbook`.

## Behavior

- Searches **normal Inventory only**.
- Partial-name matching is case-insensitive.
- If a search matches multiple items, the addon lists the matches and asks for a longer name fragment instead of guessing.
- The exact resource name of the selected item is used for the queued `/item` command.
- The default repeat interval is **2.0 seconds**.
- The minimum configurable interval is **1.2 seconds**.
- It automatically stops when the selected item runs out.
- It does **not** automatically switch to another item.
- Items that cannot normally be activated with FFXI's `/item` command will still be searchable, but the game will not be able to use them.

## Upgrade from 1.1

Replace your old `skillbook.lua` with the new one and reload:

```text
/addon reload skillbook
```

The existing `/skillbook` command name is unchanged.
