SkillBook - Ashita v4 addon
Version 1.1

Purpose
-------
Automatically consumes any of FFXI's current skill-up book items from your
normal Inventory by repeatedly queuing the ordinary /item command through Ashita.

Install
-------
Extract the "skillbook" folder to:

    Ashita\addons\skillbook\

Then in FFXI:

    /addon load skillbook

Examples
--------
See what skill books you currently have:

    /skillbook list

Select Yomi's Diagram:

    /skillbook set yomi

Select Dark Deeds:

    /skillbook set dark

Select Aid for All:

    /skillbook set aid

Start:

    /skillbook on

Stop:

    /skillbook off

Status:

    /skillbook status

Change interval:

    /skillbook delay 2

Notes
-----
* /skillbook on will auto-select a recognized skill book if none is selected.
* If multiple different skill books are in Inventory, use /skillbook list and
  /skillbook set <partial name> so it does not consume the wrong one.
* It stops automatically when the selected book runs out.
* It only looks in normal Inventory because the regular /item command needs the
  usable item available there.
* It does NOT automatically switch to another skill book when one runs out.
