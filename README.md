# TitleCollector — Live Title Progress Tracker & Navigator (WoW Midnight 12.x)

**TitleCollector** transforms World of Warcraft player titles from a passive dropdown into an active **progression journal, completionist roadmap, and portal-aware navigator**.

---

## ✨ Key Features

1. **🔥 "Almost Done" Roadmap Tab (`Почти готово`)**
   - Automatically calculates your **live completion percentage (`0%–99%`)** across all uncollected titles and sorts your closest wins to the top.
   - Smart difficulty tags: **Solo (Quick Win)**, **Solo (Legacy Raid)**, **Solo (Grind / Rep)**, **Group / Current**, **PvP**, and **Unobtainable (Legacy)**.
2. **🌳 Deep Progress Engine (`ProgressEngine.lua`)**
   - **Achievements & Meta-Achievements:** Evaluates both quantitative criteria (`42 / 50`) and 2-level nested meta-achievements (`criteriaType == 8`), showing fractional progress for every sub-achievement in an interactive checklist.
   - **Warband Renown & Classic Reputations:** Queries `C_MajorFactions` and `C_Reputation` in real time.
   - **Quests:** Checks `C_QuestLog.IsQuestFlaggedCompleted` on the fly.
3. **📍 "Current Zone" Radar & Multi-Hop Portal Navigator (`Navigation.lua`)**
   - Highlights uncollected titles tied to your current zone or raid instance.
   - One-click **3D Waypoint (`C_Map.SetUserWaypoint` + `SuperTrack`) + TomTom** integration with step-by-step **intercontinental portal routing** (Harandar, Silvermoon, Dornogal, Valdrakken, Oribos, Stormwind/Orgrimmar).
4. **🌍 Global & Realm Rarity (`RealmCensus`)**
   - Displays both **Global Rarity (%)** and **Estimated Realm Owners** on your server (plus a lightweight, passive live counter of players you've personally spotted wearing each title).
5. **🎭 Smart Auto-Title Switcher (Optional & Toggleable)**
   - Disabled by default so it never overrides your title unexpectedly.
   - When enabled in Settings or the **Auto-Titles** tab, automatically equips your chosen title (or a random ★ Favorite!) per specialization (`1..4`) or content context (*PvP*, *Raids/M+*, *Rested Cities*), safely queuing changes if you are in combat.
6. **👑 Live Nameplate Preview (Male / Female Forms)**
   - Previews how every prefix and suffix title renders with your character's name, class color, and grammatical gender (`ruRU` & `enUS` instant language toggle).

---

## 💬 Slash Commands

- `/tc` or `/titlecollector` — Toggle the TitleCollector window
- `/tc fav` — Equip a random ★ Favorite title
- `/tc lang` — Switch UI & database language between Russian (`ruRU`) and English (`enUS`)
- `/tc mm` — Toggle the round minimap button
