#!/usr/bin/env python3
"""
TitleCollector — Database Pipeline (TitlesDB-1.0)
Combines official Blizzard DB2 tables (CharTitles, Achievement, Faction, UiMap via Wago.tools)
with community rarity/obtainability metadata and curated coordinates, reputations, and quest chains.
"""

import csv
import io
import os
import re
import sys
import urllib.request
import zipfile
from datetime import datetime, timezone

ROOT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE_DIR = os.path.join(ROOT_DIR, "tools", "_cache")
OUT_FILE = os.path.join(ROOT_DIR, "Libs", "TitlesDB-1.0", "TitlesDB-1.0.lua")
MOUNT_DUNGEONS_PATH = os.path.join(os.path.dirname(ROOT_DIR), "MountCollector", "MountDungeonsDB.lua")

WAGO_FILES = {
    "CharTitles_ruRU.csv": "https://wago.tools/db2/CharTitles/csv?locale=ruRU",
    "CharTitles_enUS.csv": "https://wago.tools/db2/CharTitles/csv?locale=enUS",
    "Achievement_ruRU.csv": "https://wago.tools/db2/Achievement/csv?locale=ruRU",
    "Achievement_enUS.csv": "https://wago.tools/db2/Achievement/csv?locale=enUS",
    "Faction_ruRU.csv": "https://wago.tools/db2/Faction/csv?locale=ruRU",
    "Faction_enUS.csv": "https://wago.tools/db2/Faction/csv?locale=enUS",
    "UiMap_ruRU.csv": "https://wago.tools/db2/UiMap/csv?locale=ruRU",
    "UiMap_enUS.csv": "https://wago.tools/db2/UiMap/csv?locale=enUS",
}

EXP_MAP = {
    "classic": 1,
    "vanilla": 1,
    "tbc": 2,
    "bc": 2,
    "wotlk": 3,
    "wrath": 3,
    "cata": 4,
    "cataclysm": 4,
    "mop": 5,
    "pandaria": 5,
    "wod": 6,
    "draenor": 6,
    "legion": 7,
    "bfa": 8,
    "sl": 9,
    "shadowlands": 9,
    "df": 10,
    "dragonflight": 10,
    "tww": 11,
    "warwithin": 11,
    "thewarwithin": 11,
    "midnight": 12,
}

# Curated coordinates, reputations, quest chains, and zone mappings keyed by lowercase clean_en
CURATED_BY_TITLE = {
    # Classic / World / Iconic Solo
    "jenkins": {
        "achID": 2188, "mapID": 84, "x": 48.7, "y": 88.1, "difficulty": "SOLO_FAST",
        "note_ru": "Убейте 50 дракончиков в Верхней части пика Черной горы за 15 секунд (делается соло за 2 минуты).",
        "note_en": "Kill 50 rookery whelps within 15 seconds in Upper Blackrock Spire (easy 2-minute solo).",
    },
    "the patient": {
        "achID": 4477, "difficulty": "SOLO_FAST",
        "note_ru": "Пройдите случайные героические подземелья с 50 случайными игроками через Поиск группы.",
        "note_en": "Complete random heroic dungeons with 50 random players via Dungeon Finder.",
    },
    "the explorer": {
        "achID": 46, "difficulty": "SOLO_FAST",
        "note_ru": "Исследуйте все континенты классического мира, Запределья и Нордскола (быстро пролетается на драконе).",
        "note_en": "Explore the continents of Eastern Kingdoms, Kalimdor, Outland, and Northrend.",
    },
    "loremaster": {
        "achID": 7520, "difficulty": "SOLO_GRIND",
        "note_ru": "Глобальное мета-достижение «Хранитель мудрости»: завершите сюжетные цепочки квестов континентов.",
        "note_en": "Complete the quest achievements across major continents to earn The Loremaster.",
    },
    "the insane": {
        "achID": 2336, "difficulty": "SOLO_GRIND",
        "note_ru": "Легендарный подвиг «Чокнутый»: превознесение с Пиратами Кровавого Паруса (до Уважения), Картелью Хитрой Шестеренки, Ярмаркой Новолуния и Черным Вороном.",
        "note_en": "Exalted with Booty Bay, Everlook, Gadgetzan, Ratchet, Darkmoon Faire, Ravenholdt, and Honored with Bloodsail Buccaneers.",
    },
    # TBC / Outland
    "hand of a'dal": {
        "obtainable": False, "difficulty": "LEGACY",
    },
    "champion of the naaru": {
        "obtainable": False, "difficulty": "LEGACY",
    },
    "of the shattered sun": {
        "factionID": 1077, "reqStanding": 8, "mapID": 122, "x": 48.0, "y": 25.2, "difficulty": "SOLO_FAST",
        "note_ru": "Достигните Превознесения с Армией Расколотого Солнца на Острове Кель'Данас и купите звание за 1000 золотых у Эльдара Вестника Зари (Терраса Магистров проносится за 15 минут).",
        "note_en": "Reach Exalted with Shattered Sun Offensive on Isle of Quel'Danas and donate 1,000g to Eldara Dawnrunner.",
    },
    # WotLK Raid Solo Classics
    "of the nightfall": {
        "achID": 2051, "mapID": 115, "x": 60.0, "y": 57.0, "difficulty": "SOLO_FAST",
        "note_ru": "Убейте Сартариона в Обсидиановом святилище (10 игроков, Драконий Погост), оставив всех 3 сумеречных драконов живыми (ваншот на любом капе).",
        "note_en": "Engage and defeat Sartharion the Onyx Guardian in 10-player mode with all three Twilight Drakes still alive (Obsidian Sanctum, Dragonblight).",
    },
    "twilight vanquisher": {
        "achID": 2054, "mapID": 115, "x": 60.0, "y": 57.0, "difficulty": "SOLO_FAST",
        "note_ru": "Убейте Сартариона в Обсидиановом святилище (25 игроков, Драконий Погост), оставив всех 3 сумеречных драконов живыми (делается соло за 1 минуту!).",
        "note_en": "Engage and defeat Sartharion in 25-player mode with all three Twilight Drakes still alive (Obsidian Sanctum, Dragonblight).",
    },
    "the astral walker": {
        "achID": 3037, "mapID": 120, "x": 41.6, "y": 17.8, "difficulty": "SOLO_FAST",
        "note_ru": "Победите Алгалона Наблюдателя в Ульдуаре (Грозовая Гряда, Нордскол) — проносится соло за несколько минут.",
        "note_en": "Defeat Algalon the Observer in Ulduar (The Storm Peaks, Northrend).",
    },
    "starcaller": {
        "achID": 3036, "mapID": 120, "x": 41.6, "y": 17.8, "difficulty": "SOLO_FAST",
        "note_ru": "Победите Алгалона Наблюдателя в Ульдуаре.",
        "note_en": "Defeat Algalon the Observer in Ulduar.",
    },
    "the kingslayer": {
        "achID": 4530, "mapID": 118, "x": 53.8, "y": 87.0, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Короля-лича в Цитадели Ледяной Короны (10 или 25 игроков, Ледяная Корона).",
        "note_en": "Defeat the Lich King in Icecrown Citadel (10 or 25-player mode).",
    },
    "the light of dawn": {
        "achID": 4584, "mapID": 118, "x": 53.8, "y": 87.0, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Короля-лича в героическом режиме Цитадели Ледяной Короны на 25 игроков.",
        "note_en": "Defeat the Lich King in 25-player Heroic mode in Icecrown Citadel.",
    },
    "bane of the fallen king": {
        "achID": 4583, "mapID": 118, "x": 53.8, "y": 87.0, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Короля-лича в героическом режиме Цитадели Ледяной Короны на 10 игроков.",
        "note_en": "Defeat the Lich King in 10-player Heroic mode in Icecrown Citadel.",
    },
    "the argent champion": {
        "achID": 945, "mapID": 118, "x": 79.8, "y": 71.8, "difficulty": "SOLO_GRIND",
        "note_ru": "Достигните Превознесения у Серебряного Рассвета и Серебряного Авангарда.",
        "note_en": "Earn Exalted status with the Argent Dawn and the Argent Crusade.",
    },
    "of the ashen verdict": {
        "factionID": 1156, "reqStanding": 8, "mapID": 118, "x": 53.8, "y": 87.0, "difficulty": "SOLO_RAID",
        "note_ru": "Достигните Превознесения с Пепельным союзом внутри Цитадели Ледяной Короны.",
        "note_en": "Reach Exalted with The Ashen Verdict in Icecrown Citadel.",
    },
    # Cataclysm Solo Raids
    "dragonslayer": {
        "achID": 5121, "mapID": 241, "x": 34.0, "y": 78.0, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Синестру в героическом режиме Сумеречного бастиона (Сумеречное нагорье).",
        "note_en": "Defeat Sinestra in Heroic mode in The Bastion of Twilight.",
    },
    "blackwing's bane": {
        "achID": 5116, "mapID": 36, "x": 23.0, "y": 26.4, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Нефариана в героическом режиме Твердыни Крыла Тьмы (Пылающие степи).",
        "note_en": "Defeat Nefarian in Heroic mode in Blackwing Descent.",
    },
    "of the four winds": {
        "achID": 5123, "mapID": 249, "x": 38.4, "y": 80.6, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Ал'акира в героическом режиме Трона Четырёх Ветров (Ульдум).",
        "note_en": "Defeat Al'Akir in Heroic mode in Throne of the Four Winds.",
    },
    "firelord": {
        "achID": 5803, "mapID": 198, "x": 47.2, "y": 78.0, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Рагнароса в героическом режиме Огненных Просторов (Гора Хиджал).",
        "note_en": "Defeat Ragnaros in Heroic mode in the Firelands.",
    },
    "savior of azeroth": {
        "achID": 6116, "mapID": 71, "x": 64.7, "y": 49.9, "difficulty": "SOLO_RAID",
        "note_ru": "Победите Смертокрыла в героическом режиме Души Дракона (Пещеры Времени, Танарис).",
        "note_en": "Defeat Madness of Deathwing in Heroic mode in Dragon Soul.",
    },
    # MoP / WoD / Legion / BfA / SL / DF / TWW / Midnight Highlights
    "the wakener": {
        "achID": 8023, "factionID": 1337, "reqStanding": 8, "mapID": 422, "x": 54.4, "y": 35.8, "difficulty": "SOLO_GRIND",
        "note_ru": "Достигните Превознесения с Клакси и пробудите всех Идеалов в Жутких пустошах (Пандария).",
        "note_en": "Awaken all Klaxxi Paragons and reach Exalted with The Klaxxi in Dread Wastes.",
    },
    "barter boss": {
        "achID": 17841, "mapID": 2133, "x": 58.0, "y": 53.8, "difficulty": "SOLO_GRIND",
        "note_ru": "Купите шляпу Понзо за 249 валунов для обмена в Пещере Заралек (Лоамм).",
        "note_en": "Purchase Ponzo's hat for 249 Barter Boulders in Loamm (Zaralek Cavern).",
    },
}


def ensure_cache(force_fetch: bool = False):
    os.makedirs(CACHE_DIR, exist_ok=True)
    for fname, url in WAGO_FILES.items():
        fpath = os.path.join(CACHE_DIR, fname)
        if not force_fetch and os.path.exists(fpath) and os.path.getsize(fpath) > 500:
            continue
        print(f"[FETCH] Downloading {fname} from Wago.tools...")
        req = urllib.request.Request(url, headers={"User-Agent": "TitleCollector-DBBuilder/1.0"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            data = resp.read()
        with open(fpath, "wb") as f:
            f.write(data)


def read_csv_file(fname: str):
    fpath = os.path.join(CACHE_DIR, fname)
    with open(fpath, "r", encoding="utf-8", errors="replace") as f:
        return list(csv.DictReader(f))


def parse_epithet_zip():
    zip_path = os.path.join(CACHE_DIR, "Epithet-1.3.3-release.zip")
    en_by_mask = {}
    ru_by_mask = {}
    if not os.path.exists(zip_path):
        return en_by_mask, ru_by_mask

    with zipfile.ZipFile(zip_path, "r") as z:
        en_txt = z.read("Epithet/data/TitlesDB.enGB.lua").decode("utf-8", errors="replace")
        ru_txt = z.read("Epithet/data/TitlesDB.ruRU.lua").decode("utf-8", errors="replace")

    # Parse enGB blocks
    block_re = re.compile(r'\["([^"]+)"\]\s*=\s*\{(.*?)\n\s*\},', re.DOTALL)
    for m in block_re.finditer(en_txt):
        body = m.group(2)
        tid_m = re.search(r"titleID\s*=\s*(\d+)", body)
        if not tid_m:
            continue
        mask_id = int(tid_m.group(1))
        rec = {"maskID": mask_id}
        for key in ("type", "exp", "cat", "kind", "obtainable", "availability", "faction", "obtainability_reason", "achievement", "quest", "source_item"):
            km = re.search(rf'\b{key}\s*=\s*"((?:\\.|[^"\\])*)"', body)
            if km:
                rec[key] = km.group(1).replace('\\"', '"').replace("\\\\", "\\")
        for nkey in ("q", "achievement_id", "quest_id"):
            nm = re.search(rf"\b{nkey}\s*=\s*(\d+)", body)
            if nm:
                rec[nkey] = int(nm.group(1))
        rm = re.search(r"\brarity\s*=\s*([0-9.]+)", body)
        if rm:
            rec["rarity"] = float(rm.group(1))
        en_by_mask[mask_id] = rec

    # Parse ruRU blocks
    ru_block_re = re.compile(r"\[(\d+)\]\s*=\s*\{(.*?)\n\s*\},", re.DOTALL)
    for m in ru_block_re.finditer(ru_txt):
        mask_id = int(m.group(1))
        body = m.group(2)
        rec = {}
        for key in ("obtainability_reason", "achievement", "quest", "source_item"):
            km = re.search(rf'\b{key}\s*=\s*"((?:\\.|[^"\\])*)"', body)
            if km:
                rec[key] = km.group(1).replace('\\"', '"').replace("\\\\", "\\")
        ru_by_mask[mask_id] = rec

    return en_by_mask, ru_by_mask


def parse_mount_dungeons_coords():
    """Extracts instance/raid entrance coordinates from MountCollector/MountDungeonsDB.lua."""
    by_name = {}
    for k, (mid, cx, cy) in RAID_AND_ZONE_ENTRANCES.items():
        by_name[k] = {"mapID": mid, "x": cx, "y": cy}
    if not os.path.exists(MOUNT_DUNGEONS_PATH):
        return by_name
    with open(MOUNT_DUNGEONS_PATH, "r", encoding="utf-8", errors="replace") as f:
        txt = f.read()
    for block in re.findall(r"\{[^{}]*mapID\s*=\s*\d+[^{}]*\}", txt, re.DOTALL):
        map_m = re.search(r"mapID\s*=\s*(\d+)", block)
        x_m = re.search(r"\bx\s*=\s*([0-9.]+)", block)
        y_m = re.search(r"\by\s*=\s*([0-9.]+)", block)
        if not (map_m and x_m and y_m):
            continue
        coords = {
            "mapID": int(map_m.group(1)),
            "x": float(x_m.group(1)),
            "y": float(y_m.group(1)),
        }
        for key in ("instanceRU", "instanceEN", "bossRU", "bossEN"):
            sm = re.search(rf'{key}\s*=\s*"([^"]+)"', block)
            if sm:
                by_name[sm.group(1).strip().lower()] = coords
                coords[key] = sm.group(1).strip()
    return by_name


RAID_AND_ZONE_ENTRANCES = {
    # Classic / TBC / WotLK
    "molten core": (36, 28.4, 84.6),
    "blackwing lair": (36, 28.4, 84.6),
    "ahn'qiraj": (81, 29.0, 92.4),
    "karazhan": (42, 46.9, 74.8),
    "serpentshrine": (102, 50.3, 33.3),
    "tempest keep": (109, 73.6, 63.7),
    "black temple": (104, 71.1, 46.4),
    "sunwell": (122, 44.3, 45.7),
    "naxxramas": (115, 87.4, 51.1),
    "obsidian sanctum": (115, 60.0, 57.0),
    "eye of eternity": (114, 27.5, 26.6),
    "ulduar": (120, 41.6, 17.8),
    "trial of the crusader": (118, 75.1, 21.8),
    "onyxia's lair": (70, 52.2, 76.2),
    "icecrown citadel": (118, 53.8, 87.0),
    "ruby sanctum": (115, 60.0, 53.0),
    # Cataclysm / MoP / WoD
    "blackwing descent": (36, 23.0, 26.4),
    "bastion of twilight": (241, 34.0, 78.0),
    "throne of the four winds": (249, 38.4, 80.6),
    "firelands": (198, 47.2, 78.0),
    "dragon soul": (71, 64.7, 49.9),
    "mogu'shan vaults": (379, 59.6, 39.2),
    "heart of fear": (422, 38.9, 35.0),
    "terrace of endless spring": (433, 48.4, 61.4),
    "throne of thunder": (504, 63.6, 32.2),
    "siege of orgrimmar": (390, 73.9, 42.1),
    "highmaul": (550, 32.9, 38.3),
    "blackrock foundry": (543, 51.5, 27.2),
    "hellfire citadel": (534, 45.6, 53.6),
    # Legion / BfA / Shadowlands
    "emerald nightmare": (641, 56.4, 36.8),
    "trial of valor": (634, 71.1, 72.8),
    "nighthold": (680, 44.1, 59.7),
    "tomb of sargeras": (646, 64.6, 21.1),
    "antorus": (885, 54.8, 62.4),
    "uldir": (863, 51.4, 25.1),
    "battle of dazar'alor": (1165, 38.8, 2.5),
    "eternal palace": (1355, 50.4, 12.1),
    "ny'alotha": (1527, 38.0, 45.0),
    "castle nathria": (1525, 46.3, 41.4),
    "sanctum of domination": (1543, 69.7, 32.0),
    "sepulcher of the first ones": (1970, 80.4, 53.3),
    # Dragonflight / TWW / Midnight
    "vault of the incarnates": (2025, 73.0, 55.6),
    "aberrus": (2133, 48.2, 11.7),
    "amirdrassil": (2200, 27.3, 30.9),
    "nerub-ar palace": (2255, 35.6, 72.1),
    "liberation of undermine": (2346, 42.0, 52.0),
    "zaralek": (2133, 56.2, 56.2),
    "emerald dream": (2200, 50.0, 62.0),
    "dornogal": (2339, 46.0, 48.0),
    "isle of dorn": (2248, 55.0, 55.0),
    "ringing deeps": (2214, 48.0, 32.0),
    "hallowfall": (2215, 42.0, 52.0),
    "azj-kahet": (2255, 56.8, 42.0),
    "harandar": (2413, 53.3, 55.5),
    "silvermoon": (2395, 52.5, 25.6),
    "eversong": (2395, 48.0, 46.0),
    "zul'aman": (2437, 45.0, 50.0),
    "voidstorm": (2405, 50.0, 50.0),
}



def clean_title_pattern(pat: str) -> str:
    if not pat:
        return ""
    s = pat.replace("%s", "").strip()
    s = re.sub(r"^[,\s\-–—:]+|[,\s\-–—:]+$", "", s)
    return s.strip()


def is_prefix_pattern(pat: str) -> bool:
    if not pat:
        return True
    idx = pat.find("%s")
    if idx < 0:
        return True
    # If %s is at the end (e.g. "Private %s"), title comes before player name -> prefix
    return idx > len(pat) // 2


def lua_str(val) -> str:
    if val is None:
        return "nil"
    s = str(val).replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
    return f'"{s}"'


def main():
    force_fetch = "--fetch" in sys.argv
    ensure_cache(force_fetch)

    char_ru = {int(r["Mask_ID"]): r for r in read_csv_file("CharTitles_ruRU.csv") if r.get("Mask_ID", "").isdigit()}
    char_en = {int(r["Mask_ID"]): r for r in read_csv_file("CharTitles_enUS.csv") if r.get("Mask_ID", "").isdigit()}

    ach_ru = {int(r["ID"]): r for r in read_csv_file("Achievement_ruRU.csv") if r.get("ID", "").isdigit()}
    ach_en = {int(r["ID"]): r for r in read_csv_file("Achievement_enUS.csv") if r.get("ID", "").isdigit()}

    uimap_ru = {int(r["ID"]): r.get("Name_lang", "") for r in read_csv_file("UiMap_ruRU.csv") if r.get("ID", "").isdigit()}
    uimap_en = {int(r["ID"]): r.get("Name_lang", "") for r in read_csv_file("UiMap_enUS.csv") if r.get("ID", "").isdigit()}

    faction_by_name = {}
    for r in read_csv_file("Faction_enUS.csv"):
        if r.get("ID", "").isdigit():
            fid = int(r["ID"])
            fnm = (r.get("Name_lang") or "").strip().lower()
            if fnm and len(fnm) >= 5 and fnm not in faction_by_name:
                faction_by_name[fnm] = fid
                if fnm.startswith("the ") and len(fnm) >= 9:
                    faction_by_name[fnm[4:]] = fid
    for r in read_csv_file("Faction_ruRU.csv"):
        if r.get("ID", "").isdigit():
            fid = int(r["ID"])
            fnm = (r.get("Name_lang") or "").strip().lower()
            if fnm and len(fnm) >= 5 and fnm not in faction_by_name:
                faction_by_name[fnm] = fid

    # Build zone name -> uiMapID lookup for open-world/zone matching
    zone_to_mapid = {}
    for r in read_csv_file("UiMap_enUS.csv"):
        if r.get("ID", "").isdigit() and r.get("Type") in ("3", "2", "4"):
            mid = int(r["ID"])
            nm = r.get("Name_lang", "").strip().lower()
            if nm and len(nm) >= 4 and nm not in zone_to_mapid:
                zone_to_mapid[nm] = mid
    for r in read_csv_file("UiMap_ruRU.csv"):
        if r.get("ID", "").isdigit() and r.get("Type") in ("3", "2", "4"):
            mid = int(r["ID"])
            nm = r.get("Name_lang", "").strip().lower()
            if nm and len(nm) >= 4 and nm not in zone_to_mapid:
                zone_to_mapid[nm] = mid

    # Build Achievement reward text -> achievement ID index
    reward_to_ach_id = {}
    for aid, row in ach_en.items():
        rew = (row.get("Reward_lang") or "").strip()
        if not rew:
            continue
        low = rew.lower()
        if "title" in low or ":" in low:
            cleaned = re.sub(r"^.*?:\s*", "", rew).replace("%s", "").strip(" ,.-'\"")
            if cleaned and len(cleaned) >= 3:
                reward_to_ach_id[cleaned.lower()] = aid

    for aid, row in ach_ru.items():
        rew = (row.get("Reward_lang") or "").strip()
        if not rew:
            continue
        low = rew.lower()
        if "звани" in low or "титул" in low or ":" in low:
            cleaned = re.sub(r"^.*?:\s*", "", rew).replace("%s", "").strip(" ,.-'\"«»")
            if cleaned and len(cleaned) >= 3 and cleaned.lower() not in reward_to_ach_id:
                reward_to_ach_id[cleaned.lower()] = aid

    en_meta, ru_meta = parse_epithet_zip()
    dungeon_coords = parse_mount_dungeons_coords()

    all_masks = sorted(set(char_en.keys()) | set(char_ru.keys()))
    records = []

    for mask_id in all_masks:
        if mask_id <= 0:
            continue
        row_en = char_en.get(mask_id) or char_ru.get(mask_id)
        row_ru = char_ru.get(mask_id) or row_en
        if not row_en:
            continue

        db_id = int(row_en.get("ID") or 0)
        name_m_en = (row_en.get("Name_lang") or "").strip()
        name_f_en = (row_en.get("Name1_lang") or name_m_en).strip()
        name_m_ru = (row_ru.get("Name_lang") or name_m_en).strip()
        name_f_ru = (row_ru.get("Name1_lang") or name_m_ru).strip()

        clean_en = clean_title_pattern(name_m_en)
        clean_ru = clean_title_pattern(name_m_ru)
        if not clean_en or clean_en.startswith("UNUSED") or "TEST" in clean_en.upper() or "PH " in clean_en.upper():
            continue

        meta_en = en_meta.get(mask_id, {})
        meta_ru = ru_meta.get(mask_id, {})
        curated = CURATED_BY_TITLE.get(clean_en.lower(), {})

        # Skip pure unreferenced test/duplicate IDs unless they are in meta_en or matched to an achievement
        ach_id = curated.get("achID") or meta_en.get("achievement_id")
        if not ach_id:
            ach_id = reward_to_ach_id.get(clean_en.lower()) or reward_to_ach_id.get(clean_ru.lower())

        # If neither in Epithet curated 694 titles nor has an achievement reward match nor curated, check if high ID (Midnight 12.x)
        if not meta_en and not ach_id and not curated and db_id < 800:
            continue

        ach_row_en = ach_en.get(ach_id) if ach_id else None
        ach_row_ru = ach_ru.get(ach_id) if ach_id else None

        exp_str = (meta_en.get("exp") or "").lower()
        exp_num = EXP_MAP.get(exp_str)
        if not exp_num:
            if db_id >= 820 or (ach_id and ach_id >= 40000):
                exp_num = 12 # Midnight
            elif db_id >= 770 or (ach_id and ach_id >= 19000):
                exp_num = 11 # The War Within
            elif db_id >= 710 or (ach_id and ach_id >= 16000):
                exp_num = 10 # Dragonflight
            elif db_id >= 640:
                exp_num = 9
            elif db_id >= 530:
                exp_num = 8
            elif db_id >= 450:
                exp_num = 7
            elif db_id >= 390:
                exp_num = 6
            elif db_id >= 310:
                exp_num = 5
            elif db_id >= 220:
                exp_num = 4
            elif db_id >= 120:
                exp_num = 3
            elif db_id >= 50:
                exp_num = 2
            else:
                exp_num = 1

        cat = curated.get("cat") or meta_en.get("cat") or "Achievement"
        kind = meta_en.get("kind") or cat
        obtainable_raw = meta_en.get("obtainable", "yes")
        obtainable = curated.get("obtainable")
        if obtainable is None:
            obtainable = obtainable_raw == "yes" and meta_en.get("availability") != "removed"

        rarity_pct = curated.get("rarity") or meta_en.get("rarity")
        rarity_tier = meta_en.get("q") or (5 if (rarity_pct and rarity_pct < 1.5) else 4 if (rarity_pct and rarity_pct < 5.0) else 3 if (rarity_pct and rarity_pct < 15.0) else 2)

        faction_str = meta_en.get("faction") or ""
        faction = 1 if faction_str == "Alliance" else 2 if faction_str == "Horde" else 0
        if faction == 0 and ach_row_en:
            afac = int(ach_row_en.get("Faction") or -1)
            if afac == 1:
                faction = 1
            elif afac == 0:
                faction = 2

        ach_name_en = (ach_row_en and ach_row_en.get("Title_lang")) or meta_en.get("achievement") or ""
        ach_name_ru = (ach_row_ru and ach_row_ru.get("Title_lang")) or meta_ru.get("achievement") or ach_name_en
        ach_desc_en = (ach_row_en and ach_row_en.get("Description_lang")) or ""
        ach_desc_ru = (ach_row_ru and ach_row_ru.get("Description_lang")) or ach_desc_en
        icon_id = int(ach_row_en.get("IconFileID") or 0) if ach_row_en else 0

        note_en = curated.get("note_en") or meta_en.get("obtainability_reason") or ach_desc_en or ""
        note_ru = curated.get("note_ru") or meta_ru.get("obtainability_reason") or ach_desc_ru or note_en

        quest_id = curated.get("questID") or meta_en.get("quest_id")
        quest_name_en = meta_en.get("quest") or ""
        quest_name_ru = meta_ru.get("quest") or quest_name_en

        faction_id = curated.get("factionID")
        req_standing = curated.get("reqStanding")
        req_renown = curated.get("reqRenown")

        search_blob = f"{ach_name_en} {ach_desc_en} {note_en} {ach_name_ru} {ach_desc_ru}".lower()
        if not faction_id and (cat == "Reputation" or kind == "Reputation" or "exalted" in search_blob or "renown" in search_blob or "превознесен" in search_blob or "известност" in search_blob):
            for fname_low, fid in sorted(faction_by_name.items(), key=lambda kv: -len(kv[0])):
                if fname_low in search_blob:
                    faction_id = fid
                    rm_num = re.search(r"renown\s+(?:level\s+)?(\d+)|(\d+)\s*(?:-го|-й)?\s*уров\w*\s+известност", search_blob)
                    if rm_num:
                        req_renown = int(rm_num.group(1) or rm_num.group(2))
                    else:
                        req_standing = 8
                    break

        # Resolve mapID and coordinates (Curated -> Raid/Dungeon entrance -> Zone name match)
        map_id = curated.get("mapID")
        coord_x = curated.get("x")
        coord_y = curated.get("y")

        if not map_id:
            for inst_key, cinfo in dungeon_coords.items():
                if len(inst_key) >= 5 and inst_key in search_blob:
                    map_id = cinfo["mapID"]
                    coord_x = cinfo["x"]
                    coord_y = cinfo["y"]
                    break
            if not map_id:
                for zname, mid in zone_to_mapid.items():
                    if len(zname) >= 6 and zname in search_blob:
                        map_id = mid
                        break

        # Determine smart difficulty tag
        difficulty = curated.get("difficulty")
        if not difficulty:
            if not obtainable:
                difficulty = "LEGACY"
            elif cat in ("PvP", "PvP Rank") or kind == "PvP Rank":
                difficulty = "PVP"
            elif cat in ("Raid", "Dungeon"):
                difficulty = "SOLO_RAID" if exp_num <= 10 else "GROUP"
            elif cat in ("Exploration", "Quest", "Holiday", "Campaign") and (not rarity_pct or rarity_pct >= 8.0):
                difficulty = "SOLO_FAST"
            elif cat == "Reputation" or faction_id:
                difficulty = "SOLO_GRIND"
            elif exp_num <= 9 and rarity_pct and rarity_pct >= 12.0:
                difficulty = "SOLO_FAST"
            else:
                difficulty = "SOLO_GRIND"

        records.append({
            "maskID": mask_id,
            "dbID": db_id,
            "nameM_ru": name_m_ru,
            "nameF_ru": name_f_ru,
            "nameM_en": name_m_en,
            "nameF_en": name_f_en,
            "clean_ru": clean_ru,
            "clean_en": clean_en,
            "isPrefix": is_prefix_pattern(name_m_en),
            "exp": exp_num,
            "cat": cat,
            "kind": kind,
            "difficulty": difficulty,
            "faction": faction,
            "obtainable": bool(obtainable),
            "rarity": rarity_pct,
            "rarityTier": rarity_tier,
            "achID": ach_id,
            "achName_ru": ach_name_ru,
            "achName_en": ach_name_en,
            "achDesc_ru": ach_desc_ru,
            "achDesc_en": ach_desc_en,
            "icon": icon_id if icon_id > 0 else None,
            "questID": quest_id,
            "questName_ru": quest_name_ru,
            "questName_en": quest_name_en,
            "factionID": faction_id,
            "reqStanding": req_standing,
            "reqRenown": req_renown,
            "mapID": map_id,
            "x": coord_x,
            "y": coord_y,
            "zone_ru": uimap_ru.get(map_id, "") if map_id else "",
            "zone_en": uimap_en.get(map_id, "") if map_id else "",
            "note_ru": note_ru,
            "note_en": note_en,
        })

    os.makedirs(os.path.dirname(OUT_FILE), exist_ok=True)
    now_str = datetime.now(timezone.utc).strftime("%Y-%m-%d")
    minor_ver = int(datetime.now(timezone.utc).strftime("%Y%m%d%H"))

    lines = [
        "-- =============================================================================",
        f"-- TitlesDB-1.0 — Embedded Title Collector Database ({len(records)} titles)",
        f"-- Generated automatically by tools/build_titles_db.py on {now_str}",
        "-- =============================================================================",
        'local MAJOR, MINOR = "TitlesDB-1.0", ' + str(minor_ver),
        "local lib = LibStub and LibStub:NewLibrary(MAJOR, MINOR)",
        "if not lib then return end",
        "",
        f'lib.LastUpdated = "{now_str}"',
        f"lib.TotalCount = {len(records)}",
        "lib.Titles = {",
    ]

    for r in records:
        parts = [
            f"dbID={r['dbID']}",
            f"maskID={r['maskID']}",
            f"nameM_ru={lua_str(r['nameM_ru'])}",
            f"nameF_ru={lua_str(r['nameF_ru'])}",
            f"nameM_en={lua_str(r['nameM_en'])}",
            f"nameF_en={lua_str(r['nameF_en'])}",
            f"clean_ru={lua_str(r['clean_ru'])}",
            f"clean_en={lua_str(r['clean_en'])}",
            f"isPrefix={'true' if r['isPrefix'] else 'false'}",
            f"exp={r['exp']}",
            f"cat={lua_str(r['cat'])}",
            f"kind={lua_str(r['kind'])}",
            f"difficulty={lua_str(r['difficulty'])}",
            f"faction={r['faction']}",
            f"obtainable={'true' if r['obtainable'] else 'false'}",
            f"rarityTier={r['rarityTier']}",
        ]
        if r["rarity"] is not None:
            parts.append(f"rarity={r['rarity']:.2f}")
        if r["achID"]:
            parts.append(f"achID={r['achID']}")
        if r["achName_ru"]:
            parts.append(f"achName_ru={lua_str(r['achName_ru'])}")
        if r["achName_en"]:
            parts.append(f"achName_en={lua_str(r['achName_en'])}")
        if r["achDesc_ru"]:
            parts.append(f"achDesc_ru={lua_str(r['achDesc_ru'])}")
        if r["achDesc_en"]:
            parts.append(f"achDesc_en={lua_str(r['achDesc_en'])}")
        if r["icon"]:
            parts.append(f"icon={r['icon']}")
        if r["questID"]:
            parts.append(f"questID={r['questID']}")
        if r["questName_ru"]:
            parts.append(f"questName_ru={lua_str(r['questName_ru'])}")
        if r["questName_en"]:
            parts.append(f"questName_en={lua_str(r['questName_en'])}")
        if r["factionID"]:
            parts.append(f"factionID={r['factionID']}")
        if r["reqStanding"]:
            parts.append(f"reqStanding={r['reqStanding']}")
        if r["reqRenown"]:
            parts.append(f"reqRenown={r['reqRenown']}")
        if r["mapID"]:
            parts.append(f"mapID={r['mapID']}")
        if r["x"] is not None and r["y"] is not None:
            parts.append(f"x={r['x']:.1f}")
            parts.append(f"y={r['y']:.1f}")
        if r["zone_ru"]:
            parts.append(f"zone_ru={lua_str(r['zone_ru'])}")
        if r["zone_en"]:
            parts.append(f"zone_en={lua_str(r['zone_en'])}")
        if r["note_ru"]:
            parts.append(f"note_ru={lua_str(r['note_ru'])}")
        if r["note_en"]:
            parts.append(f"note_en={lua_str(r['note_en'])}")

        lines.append(f"    [{r['maskID']}] = {{ " + ", ".join(parts) + " },")

    lines.append("}")
    lines.append("")

    with open(OUT_FILE, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))

    with_ach = sum(1 for r in records if r["achID"])
    with_map = sum(1 for r in records if r["mapID"])
    with_coords = sum(1 for r in records if r["x"] is not None)
    obtainable_cnt = sum(1 for r in records if r["obtainable"])
    print(f"[OK] Generated {OUT_FILE}")
    print(f"     Total titles: {len(records)} (Obtainable: {obtainable_cnt}, With achID: {with_ach}, With mapID: {with_map}, With exact coords: {with_coords})")


if __name__ == "__main__":
    main()
