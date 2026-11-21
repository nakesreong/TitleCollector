# TitleCollector — Live Title Progress Tracker, Rarity Database & Multi-Hop Navigator

**Version:** 1.0.0  
**Authors:** Gemini (Tiger) & Anya (5cr3am1ng5oul)  
**Compatibility:** World of Warcraft: Retail / Midnight (`12.1.7`, `12.1.5`, `12.0.1`) & The War Within (`11.2.7`)  
**Source Repository:** [https://github.com/nakesreong/TitleCollector](https://github.com/nakesreong/TitleCollector)  
**License:** Attribution-NonCommercial-ShareAlike 4.0 International (CC BY-NC-SA 4.0)

> **CurseForge Short Summary (1-line tagline):**  
> Track all 688 player titles with live achievement & Renown progress, "Almost Done" roadmap, real global & realm rarity, portal routing, and optional spec auto-title switching.

***

## Overview

**TitleCollector** transforms World of Warcraft player titles from a tiny, buried Character Pane dropdown into a full **Progression Journal, Completionist Roadmap, Real Rarity Encyclopedia, and Multi-Hop Portal Route Navigator** (*Midnight* `12.0+`). Built in the same sleek dark-gold Collector UI style as **MountCollector** and **BeastCollector**, it tracks **688 titles** from *Classic* through *Midnight* with zero-stutter background frame slicing (`<= 2.0 ms/frame`).

*   **"Almost Done" Roadmap (`Almost Done` Tab):** Automatically calculates your **live completion percentage (`0%–99%`)** across all uncollected titles and sorts your closest wins right to the top, tagged by practical solo/group difficulty (*Solo Quick Win*, *Solo Legacy Raid*, *Solo Grind / Rep*, *Group / Current*, *PvP / Rated*, and *Unobtainable Legacy*).
*   **Deep 2-Level Meta-Achievement, Renown & Quest Progress Engine:** Evaluates quantitative criteria (`[3/5]`), Warband Major Faction Renown (`C_MajorFactions`), Classic Reputations (`C_Reputation`), Quest chains (`C_QuestLog`), and **automatically expands incomplete sub-achievements** inside two-tier meta-achievements into an interactive, scrollable step-by-step checklist.
*   **Real Global & Realm Rarity (Powered by Data for Azeroth + Live Realm Census):** Displays true Armory ownership percentages (`0.001%` *Mythic* to *Common*) with tier-colored badges in your **Collected** trophy showcase, estimated owner counts on your realm, and a lightweight passive **Realm Census** counter of players you've personally spotted wearing each title in the world (100% Patch 12.x Secret-Value safe).
*   **"Current Zone" Radar & Multi-Hop Portal Navigator:** Instantly filters uncollected titles tied to the zone or raid you are standing in, and plots step-by-step **intercontinental portal chains** (*Harandar / The Den*, *Silvermoon City*, *Voidstorm*, *Dornogal*, *Valdrakken*, *Oribos*, *Boralus / Dazar'alor*, *Stormwind / Orgrimmar*) using Blizzard's native 3D SuperTrack waypoint pin (`C_Map.SetUserWaypoint`) and **TomTom**—with smart anti-zombie-pin cleanup when you clear or change map pins manually.
*   **Live Nameplate Preview (Class-Colored & Male/Female Forms):** Preview how any Prefix or Suffix title looks above your character's class-colored name in both **Male** and **Female** grammatical forms before farming or equipping it.
*   **Smart Auto-Title Switcher (100% Optional & Disabled by Default):** Never touches your active title unless you turn on the master switch! When enabled, automatically equips a chosen title—or rolls a random **★ Favorite**—per character specialization (`1..4`) or content context (*Arenas & Battlegrounds*, *Raids & Mythic+*, *Sanctuaries & Rested Cities*), safely queuing changes until combat ends.
*   **Bilingual Instant Hot-Swap (`[EN]` / `[RU]`):** Switch the entire UI, title database, specialization names, criteria, and portal instructions between English and Russian on the fly with zero `/reload`.

***

## Interface Tabs & Features

1.  **Almost Done:** Your personalized completionist hit-list—shows every uncollected title you've already made progress on, sorted from `99%` down so you can knock out fast wins in minutes.
2.  **Current Zone:** Automatic zone radar highlighting uncollected titles obtainable in your current map or instance (including *Midnight* zones like *Harandar*, *Eversong Woods*, *Zul'Aman*, and *Voidstorm*).
3.  **All Titles:** Full searchable catalog of all **688 titles** with 1-click dropdown filters for **Expansion** (*Midnight* back to *Classic*), **Difficulty**, **Source Category** (*Achievements*, *Raids*, *Dungeons*, *Reputation / Renown*, *Quests & Campaign*, *Exploration*, *PvP*, *World Events*, *Professions*), **Prefix / Suffix**, and **★ Favorites**.
4.  **Collected:** Your personal trophy hall sorted by **Global Rarity** by default—showcasing your rarest *Mythic* (`<1%`), *Ultra Rare* (`<3%`), and *Epic* (`<10%`) titles at the very top with tier-colored rarity bars and right-click instant equipping.
5.  **Auto-Titles:** Configure per-specialization (`1..4`) and content-context (*PvP*, *Raids/M+*, *Rested Cities*) title rules, or click **★ Equip Random Favorite Now** anytime.
6.  **Settings:** Toggle unobtainable/legacy visibility, opposite-faction filtering, global & realm rarity displays, open-world player unit tooltips, `70%+` progress milestone toast banners, round minimap button, and Character Pane integration button.

***

## Slash Commands & Controls

*   `/tc` or `/titlecollector` — Toggle the main **TitleCollector** window (closes cleanly with `Esc`).
*   `/tc fav` or `/tc random` — Equip a random unlocked **★ Favorite** title immediately.
*   `/tc lang` — Instantly hot-swap UI and database language (`EN` / `RU`) without reloading UI.
*   `/tc toast` — Preview the movable **Title Progress Toast Banner** at the top of the screen.
*   `/tc minimap` or `/tc mm` — Show or hide the round golden minimap button.
*   **Left-Click (Minimap Button):** Open or close **TitleCollector**.
*   **Right-Click (Minimap Button):** Equip a random **★ Favorite** title.
*   **Shift + Right-Click (Minimap Button):** Cycle between 4 native golden minimap icons (*Radiant Crown*, *Golden Halo*, *Crown of Kings*, *Chalice of Glory*).
