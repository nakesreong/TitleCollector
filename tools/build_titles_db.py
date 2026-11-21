#!/usr/bin/env python3
"""
TitleCollector — Database Pipeline (TitlesDB-1.0)
Combines official Blizzard DB2 tables (CharTitles, Achievement, Achievement_Category, Faction, UiMap via Wago.tools)
with real Data for Azeroth ownership rarity and metadata (`dfa_titles.json`, `dfa_titlesrarity.json`)
plus curated coordinates, reputations, and quest chains.
"""

import csv
import json
import os
import re
import sys
import urllib.request
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
    "Achievement_Category_enUS.csv": "https://wago.tools/db2/Achievement_Category/csv?locale=enUS",
    "Faction_ruRU.csv": "https://wago.tools/db2/Faction/csv?locale=ruRU",
    "Faction_enUS.csv": "https://wago.tools/db2/Faction/csv?locale=enUS",
    "UiMap_ruRU.csv": "https://wago.tools/db2/UiMap/csv?locale=ruRU",
    "UiMap_enUS.csv": "https://wago.tools/db2/UiMap/csv?locale=enUS",
}

# Curated coordinates, reputations, quest chains, and zone mappings keyed by lowercase clean_en
CURATED_BY_TITLE = {
    # Classic / World / Iconic Solo
    "jenkins": {
        "achID": 2188, "mapID": 36, "x": 28.4, "y": 84.6, "difficulty": "SOLO_FAST",
        "note_ru": "Убейте 50 дракончиков в Верхней части пика Черной горы за 15 секунд (делается соло за 2 минуты).",
        "note_en": "Kill 50 rookery whelps within 15 seconds in Upper Blackrock Spire (easy 2-minute solo).",
    },
    "the patient": {
        "achID": 4477, "noZone": True, "difficulty": "SOLO_FAST",
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
    "slayer of the deeps": {
        "achID": 40097, "mapID": 2339, "x": 59.0, "y": 69.2, "difficulty": "PVP",
        "note_ru": "Мета-достижение открытого PvP в Каз Алгаре «Ставка Руффио» (штаб Руффио в Дорногале, 59.0, 69.2).",
        "note_en": "Khaz Algar World PvP meta-achievement 'Ruffious's Bid' (Ruffious in Dornogal, 59.0, 69.2).",
    },
    "the lightbringer": {
        "achID": 12083, "mapID": 830, "x": 56.0, "y": 67.0, "difficulty": "SOLO_FAST",
        "note_ru": "Мета-достижение кампании Аргуса «Образцовый воин Света» (Крокуун / Пустоши Анторуса / Эредат).",
        "note_en": "Argus campaign meta-achievement 'Paragon of Argus' (Krokuun, Antoran Wastes, Eredath).",
    },
    "demonslayer": {
        "achID": 12104, "mapID": 885, "x": 54.8, "y": 62.4, "difficulty": "SOLO_FAST",
        "note_ru": "Убейте 2000 демонов на Аргусе — достижение «И у нас закончились булочки из маны...» (Пустоши Анторуса, Крокуун и Эредат).",
        "note_en": "Kill 2,000 non-trivial demons on Argus ('And We're All Out of Mana Buns').",
    },
    "stormbreaker": {
        "achID": 8121, "mapID": 504, "x": 50.0, "y": 50.0, "difficulty": "SOLO_GRIND",
        "note_ru": "Мета-достижение Острова Грома в Пандарии «Гроза бурь».",
        "note_en": "Isle of Thunder meta-achievement 'Stormbreaker'.",
    },
    "architect": {
        "achID": 9094, "mapID": 539, "x": 30.0, "y": 34.0, "difficulty": "SOLO_GRIND",
        "note_ru": "Соберите и изучите чертежи всех зданий Гарнизона Дренора 3-го уровня.",
        "note_en": "Learn all Level 3 Draenor Garrison blueprints.",
    },
    "expedition leader": {
        "achID": 13134, "mapID": 1161, "x": 66.4, "y": 36.0, "difficulty": "SOLO_FAST",
        "note_ru": "Мета-достижение Островных экспедиций Battle for Azeroth (стол экспедиций в гавани Боралуса / Дазар'алора).",
        "note_en": "Island Expeditions meta-achievement in Battle for Azeroth (harbor expedition table).",
    },
    "the esteemed": {
        "achID": 12953, "mapID": 1161, "x": 73.6, "y": 25.0, "difficulty": "SOLO_GRIND",
        "note_ru": "Заработайте 100 превознесений с фракциями по всему Азероту.",
        "note_en": "Earn Exalted status with 100 reputations.",
    },
}

FACTION_COORDS = {
    1077: (122, 48.0, 25.2),  # Shattered Sun Offensive (Isle of Quel'Danas)
    1156: (118, 53.8, 87.0),  # The Ashen Verdict (Icecrown Citadel)
    1337: (422, 54.4, 35.8),  # The Klaxxi (Dread Wastes)
    2463: (1565, 63.0, 23.0), # Marasmius (Ardenweald)
    2503: (2023, 60.4, 37.6), # Maruuk Centaur (Ohn'ahran Plains - Maruukai)
    2507: (2022, 47.0, 82.6), # Dragonscale Expedition (The Waking Shores)
    2510: (2112, 58.0, 35.5), # Valdrakken Accord (Valdrakken)
    2511: (2024, 13.6, 49.4), # Iskaara Tuskarr (The Azure Span - Iskaara)
    2553: (2025, 51.0, 56.8), # Soridormi (Thaldraszus - Tyrhold Reservoir)
    2564: (2133, 56.0, 55.6), # Loamm Niffen (Zaralek Cavern - Loamm)
    2574: (2200, 50.2, 61.8), # Dream Wardens (Emerald Dream - Central Encampment)
    2590: (2339, 39.2, 24.4), # Council of Dornogal (Dornogal)
    2594: (2214, 47.4, 32.8), # The Assembly of the Deeps (The Ringing Deeps - Gundargaz)
    2570: (2215, 41.3, 53.0), # Hallowfall Arathi (Hallowfall - Mereldar)
    2600: (2255, 55.3, 41.2), # The Severed Threads (Azj-Kahet - Weaver's Lair)
    2653: (2346, 43.2, 50.8), # Cartels of Undermine (Undermine)
    2685: (2346, 43.2, 50.8), # Gallagio Loyalty Rewards Club (Undermine)
    2688: (2215, 41.3, 53.0), # Flame's Radiance (Hallowfall)
    2658: (2339, 46.6, 48.2), # The K'aresh Trust
    2736: (2339, 46.6, 48.2), # Manaforge Vandals
    2704: (2413, 53.3, 55.5), # Hara'ti (Harandar)
    2710: (2395, 52.5, 25.6), # Silvermoon Court (Silvermoon / Eversong)
    2696: (2437, 45.0, 50.0), # Amani Tribe (Zul'Aman)
    2699: (2405, 50.0, 50.0), # The Singularity (Voidstorm)
    2772: (2437, 45.0, 50.0), # Zul'jarra's Forces (Zul'Aman)
    2836: (2437, 45.0, 50.0), # The Labyrinth of Kindo'jan
}

EXPANSION_HUB_FALLBACKS = {
    2:  (111, 54.0, 44.5),  # TBC -> Shattrath City
    3:  (125, 49.5, 48.0),  # WotLK -> Dalaran (Northrend)
    5:  (390, 80.0, 33.0),  # MoP -> Vale of Eternal Blossoms
    6:  (539, 30.0, 34.0),  # WoD -> Shadowmoon Valley (Draenor)
    7:  (627, 49.5, 48.0),  # Legion -> Dalaran (Broken Isles)
    8:  (1161, 70.0, 26.0), # BfA -> Boralus
    9:  (1670, 50.0, 50.0), # Shadowlands -> Oribos
    10: (2112, 58.0, 35.5), # Dragonflight -> Valdrakken
    11: (2339, 46.6, 48.2), # The War Within -> Dornogal
    12: (2395, 52.5, 25.6), # Midnight -> Eversong / Silvermoon
}

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

COVENANT_LABELS_RU = {
    "Kyrian Covenant": "Ковенант Кирий",
    "Necrolords Covenant": "Ковенант Некролордов",
    "Night Fae Covenant": "Ковенант Ночного Народа",
    "Venthyr Covenant": "Ковенант Вентиров",
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


def load_dfa_data():
    titles_path = os.path.join(CACHE_DIR, "dfa_titles.json")
    rarity_path = os.path.join(CACHE_DIR, "dfa_titlesrarity.json")
    dfa_by_mask = {}
    rarity_by_mask = {}

    if os.path.exists(titles_path):
        with open(titles_path, "r", encoding="utf-8") as f:
            raw_t = json.load(f).get("titles", [])
            for item in raw_t:
                mid = item.get("id")
                if isinstance(mid, int):
                    dfa_by_mask[mid] = item

    if os.path.exists(rarity_path):
        with open(rarity_path, "r", encoding="utf-8") as f:
            raw_r = json.load(f).get("titles", {})
            for k, v in raw_r.items():
                if str(k).isdigit() and isinstance(v, (int, float)):
                    rarity_by_mask[int(k)] = float(v)

    return dfa_by_mask, rarity_by_mask


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
    return idx > len(pat) // 2


def lua_str(val) -> str:
    if val is None:
        return "nil"
    s = str(val).replace("\\", "\\\\").replace('"', '\\"').replace("\r", "").replace("\n", "\\n")
    return f'"{s}"'


def classify_achievement_category(ach_row_en, cat_by_id):
    if not ach_row_en:
        return "Achievement"
    cid = int(ach_row_en.get("Category") or 0)
    chain_names = []
    root_id = cid
    visited = set()
    cur = cid
    while cur in cat_by_id and cur not in visited:
        visited.add(cur)
        c_row = cat_by_id[cur]
        chain_names.append((c_row.get("Name_lang") or "").lower())
        parent = int(c_row.get("Parent") or -1)
        if parent <= 0:
            root_id = cur
            break
        cur = parent

    joined = " | ".join(chain_names)
    title_low = (ach_row_en.get("Title_lang") or "").lower()
    desc_low = (ach_row_en.get("Description_lang") or "").lower()
    blob = f"{title_low} {desc_low}"

    if "raid" in joined:
        return "Raid"
    if "dungeon" in joined or root_id == 168:
        return "Dungeon"
    if root_id == 95 or "arena" in joined or "battleground" in joined:
        return "PvP"
    if root_id == 201:
        return "Reputation"
    if root_id == 96:
        return "Quest"
    if root_id == 97:
        return "Exploration"
    if root_id == 155 or "brawler" in joined or "darkmoon" in joined:
        return "Holiday"
    if root_id == 169:
        return "Profession"
    if root_id == 15522 or "delve" in joined:
        return "Delves"
    if root_id == 15117:
        return "Pet Battles"
    if root_id == 15301:
        return "Campaign"

    # Feats of Strength (81) or Legacy (15234): infer from description/title
    if any(k in blob for k in ("gladiator", "arena", "rbg", "rated battleground", "solo shuffle", "battleground blitz", "rank 14", "marshal", "warlord", "pvp season")):
        return "PvP"
    if any(k in blob for k in ("mythic:", "heroic:", "cutting edge", "ahead of the curve", "hall of fame", "raid")):
        return "Raid"
    if any(k in blob for k in ("keystone", "mythic+", "challenge mode", "dungeon")):
        return "Dungeon"
    if any(k in blob for k in ("exalted", "renown", "reputation")):
        return "Reputation"
    if any(k in blob for k in ("delve", "zekvir", "underpin", "nemesis")):
        return "Delves"
    return "Achievement"


def main():
    force_fetch = "--fetch" in sys.argv
    ensure_cache(force_fetch)

    char_ru = {int(r["Mask_ID"]): r for r in read_csv_file("CharTitles_ruRU.csv") if r.get("Mask_ID", "").isdigit()}
    char_en = {int(r["Mask_ID"]): r for r in read_csv_file("CharTitles_enUS.csv") if r.get("Mask_ID", "").isdigit()}

    ach_ru = {int(r["ID"]): r for r in read_csv_file("Achievement_ruRU.csv") if r.get("ID", "").isdigit()}
    ach_en = {int(r["ID"]): r for r in read_csv_file("Achievement_enUS.csv") if r.get("ID", "").isdigit()}
    cat_en = {int(r["ID"]): r for r in read_csv_file("Achievement_Category_enUS.csv") if r.get("ID", "").isdigit()}

    uimap_ru = {int(r["ID"]): r.get("Name_lang", "") for r in read_csv_file("UiMap_ruRU.csv") if r.get("ID", "").isdigit()}
    uimap_en = {int(r["ID"]): r.get("Name_lang", "") for r in read_csv_file("UiMap_enUS.csv") if r.get("ID", "").isdigit()}

    faction_by_id_en = {}
    faction_by_id_ru = {}
    faction_by_name = {}
    for r in read_csv_file("Faction_enUS.csv"):
        if r.get("ID", "").isdigit():
            fid = int(r["ID"])
            fnm_raw = (r.get("Name_lang") or "").strip()
            faction_by_id_en[fid] = fnm_raw
            fnm = fnm_raw.lower()
            if fnm and len(fnm) >= 4 and fnm not in faction_by_name:
                faction_by_name[fnm] = fid
                if fnm.startswith("the ") and len(fnm) >= 8:
                    faction_by_name[fnm[4:]] = fid
    for r in read_csv_file("Faction_ruRU.csv"):
        if r.get("ID", "").isdigit():
            fid = int(r["ID"])
            fnm_raw = (r.get("Name_lang") or "").strip()
            faction_by_id_ru[fid] = fnm_raw
            fnm = fnm_raw.lower()
            if fnm and len(fnm) >= 4 and fnm not in faction_by_name:
                faction_by_name[fnm] = fid

    # Build zone name -> uiMapID lookup for open-world/zone matching (Type 3 = World Zone)
    zone_to_mapid = {}
    for r in read_csv_file("UiMap_enUS.csv"):
        if r.get("ID", "").isdigit() and r.get("Type") == "3":
            mid = int(r["ID"])
            nm = r.get("Name_lang", "").strip().lower()
            if nm and len(nm) >= 5 and nm not in zone_to_mapid:
                zone_to_mapid[nm] = mid
    for r in read_csv_file("UiMap_ruRU.csv"):
        if r.get("ID", "").isdigit() and r.get("Type") == "3":
            mid = int(r["ID"])
            nm = r.get("Name_lang", "").strip().lower()
            if nm and len(nm) >= 5 and nm not in zone_to_mapid:
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

    dfa_by_mask, rarity_by_mask = load_dfa_data()
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
        if not clean_en or clean_en.startswith("UNUSED") or "TEST" in clean_en.upper() or "[PH]" in clean_en.upper() or clean_en.upper().startswith("PH "):
            continue

        dfa = dfa_by_mask.get(mask_id, {})
        dfa_unob = dfa.get("unobtainable")
        rarity_pct = rarity_by_mask.get(mask_id)

        # Skip never-implemented / PH titles (unobtainable == 2) unless players actually own it in Armory
        if dfa_unob == 2 and rarity_pct is None:
            continue

        curated = CURATED_BY_TITLE.get(clean_en.lower(), {})
        sources = dfa.get("source") or []

        # Extract achievement / quest / faction / currency from dfa sources
        dfa_ach_id = None
        dfa_quest_id = None
        dfa_faction_name = None
        dfa_standing_str = None
        dfa_currency = None
        dfa_drop_name = None
        dfa_drop_zone = None
        dfa_source_type = None

        for s in sources:
            stype = s.get("type")
            if not dfa_source_type:
                dfa_source_type = stype
            if stype == "achievement" and isinstance(s.get("achievement"), int) and not dfa_ach_id:
                dfa_ach_id = s["achievement"]
            elif stype == "quest":
                if isinstance(s.get("quest"), int) and not dfa_quest_id:
                    dfa_quest_id = s["quest"]
                elif s.get("name") and not dfa_drop_name:
                    dfa_drop_name = s["name"]
            elif stype == "faction":
                dfa_faction_name = s.get("faction") or s.get("name")
                dfa_standing_str = s.get("standing") or s.get("zone")
            elif stype == "currency":
                dfa_currency = s.get("currency") or s.get("name")
            elif stype in ("drop", "vendor", "promotion", "other"):
                dfa_drop_name = s.get("name")
                dfa_drop_zone = s.get("zone")

        ach_id = dfa_ach_id or curated.get("achID")
        if not ach_id:
            ach_id = reward_to_ach_id.get(clean_en.lower()) or reward_to_ach_id.get(clean_ru.lower())

        # Skip pure unreferenced internal IDs that are not in Data for Azeroth and have no achievement
        if not dfa and not ach_id and not curated:
            continue

        ach_row_en = ach_en.get(ach_id) if ach_id else None
        ach_row_ru = ach_ru.get(ach_id) if ach_id else None

        # Determine Expansion (1..12) from dfa patch string (e.g. "12.0", "11.1.5", "3.3")
        exp_num = None
        patch_str = str(dfa.get("patch") or "")
        pm = re.match(r"^(\d+)\.", patch_str)
        if pm:
            exp_num = int(pm.group(1))
        if not exp_num:
            if db_id >= 820 or (ach_id and ach_id >= 40000):
                exp_num = 12
            elif db_id >= 770 or (ach_id and ach_id >= 19000):
                exp_num = 11
            elif db_id >= 710 or (ach_id and ach_id >= 16000):
                exp_num = 10
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

        # Determine obtainability
        obtainable = curated.get("obtainable")
        if obtainable is None:
            obtainable = dfa_unob not in (1, 2)

        # Determine Faction (1 = Alliance, 2 = Horde, 0 = Neutral)
        dfa_fac = dfa.get("faction")
        if dfa_fac == 0:
            faction = 1
        elif dfa_fac == 1:
            faction = 2
        else:
            faction = 0
            if ach_row_en:
                afac = int(ach_row_en.get("Faction") or -1)
                if afac == 1:
                    faction = 1
                elif afac == 0:
                    faction = 2

        # Resolve Reputation / Faction ID and Renown / Standing
        faction_id = curated.get("factionID")
        req_standing = curated.get("reqStanding")
        req_renown = curated.get("reqRenown")

        grant_reps = dfa.get("grantreputations")
        if not faction_id and isinstance(grant_reps, list) and len(grant_reps) > 0:
            faction_id = int(grant_reps[0])

        if not faction_id and dfa_faction_name:
            fn_low = dfa_faction_name.strip().lower()
            faction_id = faction_by_name.get(fn_low) or faction_by_name.get("the " + fn_low)

        if dfa_standing_str:
            rm = re.search(r"(?:renown|level)\s+(\d+)", dfa_standing_str, re.IGNORECASE)
            if rm:
                req_renown = int(rm.group(1))
            elif faction_id and not req_standing:
                req_standing = 8
        elif faction_id and not req_renown and not req_standing:
            req_standing = 8

        ach_name_en = (ach_row_en and ach_row_en.get("Title_lang")) or ""
        ach_name_ru = (ach_row_ru and ach_row_ru.get("Title_lang")) or ach_name_en
        ach_desc_en = (ach_row_en and ach_row_en.get("Description_lang")) or ""
        ach_desc_ru = (ach_row_ru and ach_row_ru.get("Description_lang")) or ach_desc_en
        icon_id = int(ach_row_en.get("IconFileID") or 0) if ach_row_en else 0

        # Also scan achievement description for reputation if not yet set
        search_blob = f"{ach_name_en} {ach_desc_en} {ach_name_ru} {ach_desc_ru}".lower()
        if not faction_id and ("exalted" in search_blob or "renown" in search_blob or "превознесен" in search_blob or "известност" in search_blob):
            for fname_low, fid in sorted(faction_by_name.items(), key=lambda kv: -len(kv[0])):
                if fname_low in search_blob:
                    faction_id = fid
                    rm_num = re.search(r"renown\s+(?:level\s+)?(\d+)|(\d+)\s*(?:-го|-й)?\s*уров\w*\s+известност", search_blob)
                    if rm_num:
                        req_renown = int(rm_num.group(1) or rm_num.group(2))
                    else:
                        req_standing = 8
                    break

        # Determine Category (`cat` / `kind`)
        if curated.get("cat"):
            cat = curated["cat"]
        elif ach_row_en:
            cat = classify_achievement_category(ach_row_en, cat_en)
        elif dfa_source_type == "faction" or faction_id:
            cat = "Reputation"
        elif dfa_source_type == "currency":
            cat = "Holiday"
        elif dfa_source_type == "quest":
            cat = "Campaign" if exp_num == 7 else "Quest"
        elif dfa_source_type == "drop":
            cat = "Raid" if dfa_drop_zone in ("Blackwing Descent", "Siege of Orgrimmar") else "Exploration"
        elif mask_id <= 28:
            cat = "PvP"
        else:
            cat = "Achievement"
        kind = cat

        # Build localized notes (`note_ru`, `note_en`) from official DB2 / Data for Azeroth metadata
        note_en = curated.get("note_en") or ""
        note_ru = curated.get("note_ru") or ""

        if not note_en or not note_ru:
            if ach_desc_en or ach_desc_ru:
                note_en = note_en or ach_desc_en
                note_ru = note_ru or ach_desc_ru
            elif dfa_source_type == "faction" or faction_id:
                fac_en_label = faction_by_id_en.get(faction_id) or dfa_faction_name or "Faction"
                fac_ru_label = faction_by_id_ru.get(faction_id) or COVENANT_LABELS_RU.get(dfa_faction_name or "") or fac_en_label
                if req_renown:
                    note_en = note_en or f"Reach Renown {req_renown} with {fac_en_label}."
                    note_ru = note_ru or f"Достигните {req_renown}-го уровня известности у фракции «{fac_ru_label}»."
                else:
                    note_en = note_en or f"Reach Exalted reputation with {fac_en_label}."
                    note_ru = note_ru or f"Достигните Превознесения у фракции «{fac_ru_label}»."
            elif dfa_source_type == "currency" and dfa_currency:
                if "timewarped" in dfa_currency.lower():
                    note_en = note_en or "Purchased from Timewalking vendors for Timewarped Badges during Timewalking events."
                    note_ru = note_ru or "Приобретается у торговцев Путешествий во времени за Искаженные временем знаки."
                else:
                    note_en = note_en or f"Purchased with currency: {dfa_currency}."
                    note_ru = note_ru or f"Приобретается за валюту: {dfa_currency}."
            elif dfa_source_type == "quest":
                if dfa_quest_id and exp_num == 7:
                    note_en = note_en or f"Complete the Legion Class Order Hall campaign (Quest #{dfa_quest_id})."
                    note_ru = note_ru or f"Завершите кампанию классового оплота Legion (Задание #{dfa_quest_id})."
                elif dfa_quest_id:
                    note_en = note_en or f"Reward from quest #{dfa_quest_id}."
                    note_ru = note_ru or f"Награда за выполнение задания #{dfa_quest_id}."
                elif dfa_drop_name:
                    note_en = note_en or f"Reward from quest: {dfa_drop_name}."
                    note_ru = note_ru or f"Награда за задание «{dfa_drop_name}»."
            elif dfa_source_type == "drop" and dfa_drop_name:
                note_en = note_en or f"Granted by defeating or looting: {dfa_drop_name}."
                note_ru = note_ru or f"Добывается или дается за победу: {dfa_drop_name}."
            elif dfa_source_type == "vendor" and dfa_drop_name:
                note_en = note_en or f"Purchased from vendor: {dfa_drop_name}."
                note_ru = note_ru or f"Приобретается у торговца: {dfa_drop_name}."
            elif dfa_source_type == "promotion" and dfa_drop_name:
                note_en = note_en or f"Special promotion reward: {dfa_drop_name}."
                note_ru = note_ru or f"Награда специальной акции: {dfa_drop_name}."
            elif dfa_drop_name:
                note_en = note_en or f"Source: {dfa_drop_name}."
                note_ru = note_ru or f"Источник: {dfa_drop_name}."

        if not obtainable:
            if note_en and "no longer obtainable" not in note_en.lower():
                note_en = f"{note_en} (No longer obtainable)"
            elif not note_en:
                note_en = "Legacy title — no longer obtainable in-game."
            if note_ru and "недоступно" not in note_ru.lower():
                note_ru = f"{note_ru} (Более недоступно для получения)"
            elif not note_ru:
                note_ru = "Наследие прошлых сезонов — более недоступно для получения."

        quest_id = curated.get("questID") or dfa_quest_id

        # Resolve mapID and coordinates (Curated -> Faction HQ -> Raid/Dungeon entrance -> Zone name match -> Expansion Hub)
        map_id = curated.get("mapID")
        coord_x = curated.get("x")
        coord_y = curated.get("y")

        if not map_id and faction_id and faction_id in FACTION_COORDS and not curated.get("noZone"):
            map_id, coord_x, coord_y = FACTION_COORDS[faction_id]

        full_search_blob = f"{search_blob} {note_en} {note_ru} {dfa_drop_zone or ''} {dfa_faction_name or ''}".lower()
        if not map_id and not curated.get("noZone"):
            for inst_key, cinfo in dungeon_coords.items():
                if len(inst_key) >= 5 and inst_key in full_search_blob:
                    map_id = cinfo["mapID"]
                    coord_x = cinfo["x"]
                    coord_y = cinfo["y"]
                    break
            if not map_id:
                for zname, mid in sorted(zone_to_mapid.items(), key=lambda kv: -len(kv[0])):
                    if len(zname) >= 6 and re.search(rf"\b{re.escape(zname)}\b", full_search_blob):
                        map_id = mid
                        break
            if not map_id and obtainable and cat in ("Reputation", "Quest", "Exploration", "Campaign", "Delves") and exp_num in EXPANSION_HUB_FALLBACKS:
                map_id, coord_x, coord_y = EXPANSION_HUB_FALLBACKS[exp_num]

        # Determine smart difficulty tag
        difficulty = curated.get("difficulty")
        if not difficulty:
            if not obtainable:
                difficulty = "LEGACY"
            elif cat in ("PvP", "PvP Rank"):
                difficulty = "PVP"
            elif cat in ("Raid", "Dungeon"):
                difficulty = "SOLO_RAID" if exp_num <= 10 else "GROUP"
            elif cat in ("Exploration", "Quest", "Holiday", "Campaign") and (not rarity_pct or rarity_pct >= 8.0):
                difficulty = "SOLO_FAST"
            elif cat == "Reputation" or faction_id:
                difficulty = "SOLO_GRIND"
            elif exp_num <= 9 and rarity_pct and rarity_pct >= 15.0:
                difficulty = "SOLO_FAST"
            else:
                difficulty = "SOLO_GRIND"

        rarity_tier = (
            5 if (rarity_pct is not None and rarity_pct < 1.0)
            else 4 if (rarity_pct is not None and rarity_pct < 3.0)
            else 3 if (rarity_pct is not None and rarity_pct < 10.0)
            else 2 if (rarity_pct is not None and rarity_pct < 25.0)
            else 1
        )

        fac_name_en = (faction_by_id_en.get(faction_id) or dfa_faction_name or "") if faction_id else ""
        fac_name_ru = (faction_by_id_ru.get(faction_id) or COVENANT_LABELS_RU.get(dfa_faction_name or "") or fac_name_en) if faction_id else ""

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
            "factionID": faction_id,
            "facName_ru": fac_name_ru,
            "facName_en": fac_name_en,
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
    minor_ver = int(datetime.now(timezone.utc).strftime("%Y%m%d%H")) + 1

    lines = [
        "-- =============================================================================",
        f"-- TitlesDB-1.0 — Embedded Title Collector Database ({len(records)} titles)",
        f"-- Generated automatically by tools/build_titles_db.py on {now_str}",
        "-- Rarity & obtainability powered by Data for Azeroth + Blizzard DB2 (Wago.tools)",
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
            if r["rarity"] < 0.1:
                parts.append(f"rarity={r['rarity']:.4f}")
            else:
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
        if r["factionID"]:
            parts.append(f"factionID={r['factionID']}")
        if r["facName_ru"]:
            parts.append(f"facName_ru={lua_str(r['facName_ru'])}")
        if r["facName_en"]:
            parts.append(f"facName_en={lua_str(r['facName_en'])}")
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
    with_rarity = sum(1 for r in records if r["rarity"] is not None)
    with_map = sum(1 for r in records if r["mapID"])
    with_coords = sum(1 for r in records if r["x"] is not None)
    obtainable_cnt = sum(1 for r in records if r["obtainable"])
    print(f"[OK] Generated {OUT_FILE}")
    print(f"     Total titles: {len(records)} (Obtainable: {obtainable_cnt}, With DfA Rarity: {with_rarity}, With achID: {with_ach}, With mapID: {with_map}, With exact coords: {with_coords})")


if __name__ == "__main__":
    main()
