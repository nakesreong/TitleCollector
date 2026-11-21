# TitleCollector — Live Title Progress Tracker, Almost Done Roadmap, Real Rarity Census & Portal Navigator

**Authors:** Gemini (Tiger) & Anya (5cr3am1ng5oul)  
**Compatibility:** World of Warcraft: Retail / Midnight (`12.1.7`, `12.1.5`, `12.0.1`) & The War Within (`11.2.7`)  
**Source Repository:** [https://github.com/nakesreong/TitleCollector](https://github.com/nakesreong/TitleCollector)  
**License:** Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)

***

## Overview

**TitleCollector** is a modular player title collection, live progression roadmap, real rarity encyclopedia, and multi-hop portal navigation suite for World of Warcraft. It transforms player titles from a tiny, buried Character Pane dropdown into an interactive progression journal—unifying fractional 2-level meta-achievement and Renown checklists, global and realm rarity statistics, open-world zone filtering, and optional per-specialization title automation into a sleek dark-gold UI modeled after **MountCollector** and **BeastCollector**.

*   **"Almost Done" Completionist Roadmap:** Automatically evaluates your live completion percentage (`0%–99%`) across all uncollected titles and sorts your closest wins to the top, tagged by practical solo/group difficulty (*Solo Quick Win*, *Solo Legacy Raid*, *Solo Grind / Rep*, *Group / Current*, *PvP / Rated*, and *Unobtainable Legacy*).
*   **Deep 2-Level Meta-Achievement, Renown & Quest Progress Engine:** Calculates real-time progress across quantitative criteria (`[3/5]`), Warband Major Faction Renown (`C_MajorFactions`), Classic Reputations (`C_Reputation`), and Quest chains (`C_QuestLog`), automatically expanding incomplete sub-achievements inside two-tier meta-achievements into a scrollable step-by-step checklist.
*   **Global & Realm Rarity Census:** Integrates **Data for Azeroth** global Armory ownership percentages across **688 titles** (`TitlesDB-1.0`) with realm population ownership estimates, tier-colored rarity badges, and a lightweight passive open-world player title scanner (`RealmCensus`).
*   **Current Zone Radar & Multi-Hop Portal Route Navigator:** Highlights uncollected titles tied to your current map or raid instance and plots automated step-by-step intercontinental portal chains (`C_Map.SetUserWaypoint` + `C_SuperTrack` + optional **TomTom**) that yield cleanly whenever you manually clear or replace a map pin.
*   **Live Nameplate Preview (Class-Colored & Male/Female Forms):** Previews how every Prefix and Suffix title renders with your character's class-colored name and grammatical gender (`Male` / `Female`) before farming or equipping it.
*   **Smart Auto-Title Switcher (100% Optional & Toggleable):** Disabled by default so it never overrides your active title unexpectedly; when enabled, automatically equips chosen or random **Favorite** titles per specialization (`1..4`) or content context (*PvP*, *Raids & Mythic+*, *Rested Cities*), queuing swaps safely until combat ends.
*   **World of Warcraft 12.x (Midnight) Secret-Value Safe & Zero-Stutter Architecture:** Engineered with `issecretvalue()` tooltip/unit guards, combat deferral (`0.00 ms` in combat), and a time-sliced background worker (`<= 2.0 ms/frame`), paired with instant **`[EN]` / `[RU]`** hot-swapping and a circular golden minimap button (`LibDataBroker-1.1` / `LibDBIcon-1.0`).

***

## Architecture & Core Subsystems

### 1\. Two-Column Collector Window (`/tc`) & Six Integrated Views

A standalone dark-gold flat interface (`TitleCollectorMainFrame`) organized into four catalog/progression views, an optional automation studio, and an integrated configuration panel:

1.  **Almost Done Tab:** Lists all uncollected titles with partial progress (`> 0%`), sorted from `99%` down so you can spot and finish nearly completed achievements, reputations, and legacy raid titles in minutes.
2.  **Current Zone Tab:** Dynamically detects your current map (`C_Map.GetBestMapForUnit("player")`) and surfaces uncollected titles obtainable right where you stand—from *Classic* raids through *The War Within* and *Midnight* (*Harandar*, *Eversong Woods*, *Zul'Aman*, *Voidstorm*).
3.  **All Titles Tab:** Complete searchable database of **688 titles** (`TitlesDB-1.0`, verified against official Blizzard `CharTitles.db2`, `Achievement.db2`, `Faction.db2`, and `UiMap.db2` data) with one-click dropdown filters for **Expansion**, **Difficulty**, **Source Category**, **Prefix / Suffix**, **Sort Order**, and **Favorites**.
4.  **Collected Tab:** Personal trophy showcase sorted by **Global Rarity** by default, highlighting your rarest *Mythic* (`<1%`), *Ultra Rare* (`<3%`), and *Epic* (`<10%`) titles at the top with tier-colored rarity bars and right-click instant equipping.
5.  **Auto-Titles Tab:** Dedicated rule builder for binding specific titles—or rolling a random **Favorite**—to each specialization (`1..4`) and activity context (*Arenas & Battlegrounds*, *Raids & Mythic+ Dungeons*, *Sanctuaries & Rested Cities*), governed by a master enable/disable toggle.
6.  **Settings Tab:** Fine-grained toggles for unobtainable/legacy visibility, opposite-faction filtering, global & realm rarity lines, passive `RealmCensus` scanning, player unit tooltips, `70%+` milestone toast banners, minimap icon, and Character Pane integration.

### 2\. Deep Progress Engine, Time-Sliced Worker & Milestone Toast Banner

Built on an event-driven progression core (`ProgressEngine.lua`) designed for zero combat impact:

*   **2-Level Meta-Achievement Unfolding:** Inspects `GetAchievementCriteriaInfo` and nested sub-achievements (`criteriaType == 8`), displaying inline step counters (`[3/5]`) directly beneath incomplete meta-criteria and opening the exact sub-achievement in Blizzard's Achievement UI on click.
*   **Zero-Stutter Frame Slicing (`StartSlicedProgressWorker`):** Coalesces bursts of `CRITERIA_UPDATE`, `QUEST_TURNED_IN`, and `UPDATE_FACTION` events with a soft debounce, defers background scans completely during `InCombatLockdown()`, and processes updates under a strict `<= 2.0 ms` per-frame budget.
*   **Movable Progress & Unlock Toast (`TitleCollectorToastFrame`):** Optionally celebrates newly unlocked titles and major progress jumps (`70%+` or tracked/favorite titles) with a clickable banner that opens the title directly in the inspector.

### 3\. Multi-Hop Portal Navigation, Player Tooltips & Character Pane Integration

Connects your title journal directly to the game world (`Navigation.lua` & `Core.lua`):

*   **Intercontinental Portal Routing:** Clicking **Plot Route (3D Waypoint)** builds an automatic multi-hop portal route from isolated hubs (*Harandar / The Den*, *Silvermoon City*, *Dornogal*, *Valdrakken*, *Oribos*, *Stormwind / Orgrimmar*) to faction quartermasters, raid entrances, and open-world objectives.
*   **Anti-Zombie Waypoint Yielding:** Hooks `C_Map` and `C_SuperTrack` (`USER_WAYPOINT_UPDATED`) so clearing a map pin or tracking a quest/rare immediately cancels the active route without re-pinning on zone transitions.
*   **Open-World Player Unit Tooltips & Character Pane Button:** Hovering over players in the world displays the global rarity, expansion, source, and your own completion percentage for the title they are wearing, while a one-click **TitleCollector** button sits right inside Blizzard's `PaperDollTitlesPane`.

***

## Slash Commands & Controls

*   `/tc` or `/titlecollector` — Toggle the main **TitleCollector** window (closes cleanly with `Esc`).
*   `/tc fav` or `/tc random` — Equip a random unlocked **Favorite** title immediately.
*   `/tc lang` — Instantly hot-swap UI and database language (**English `enUS`** / **Russian `ruRU`**) without `/reload`.
*   `/tc toast` — Preview the movable **Title Progress Toast Banner**.
*   `/tc minimap` or `/tc mm` — Show or hide the round golden minimap button.
*   **Left-Click (Minimap Crown Icon):** Toggle the **TitleCollector** window.
*   **Right-Click (Minimap Crown Icon):** Equip a random **Favorite** title.
*   **Shift + Right-Click (Minimap Crown Icon):** Cycle between 4 golden minimap icons (*Radiant Crown*, *Golden Halo*, *Crown of Kings*, *Chalice of Glory*).
*   **Right-Click (Any Collected Title Row):** Equip that title immediately.
*   **Right-Click (Filter Dropdown Button):** Reset that filter back to *All*.
