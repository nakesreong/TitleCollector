local addonName, addon = ...
_G.TitleCollector = addon

-- ============================================================================
-- TitleCollector — Core.lua
-- Ядро аддона:
--   1. Инициализация SavedVariables (TitleCollectorDB) и индексация TitlesDB-1.0
--   2. Живое досканирование клиентских званий (1..GetNumTitles / IsTitleKnown)
--   3. Глобальная редкость (% по миру) + Серверная редкость (Realm Census)
--   4. Форматирование званий (Префикс/Суффикс + Мужской/Женский род %s)
--   5. Безопасная смена звания SetCurrentTitle с очередью выхода из боя
-- ============================================================================

local LibStub = _G.LibStub
local TitlesDB = LibStub and LibStub("TitlesDB-1.0", true)

local function SafeNotSecret(val)
    if val == nil then return false end
    if _G.issecretvalue and _G.issecretvalue(val) then
        return false
    end
    return true
end
addon.SafeNotSecret = SafeNotSecret

addon.Titles = {}
addon.TitleByMaskID = {}
addon.TitleByCleanText = {}
addon.TitlesByMapID = {}
addon.TitlesByAchID = {}
addon.pendingEquipMaskID = nil

addon.RealmPopulations = {
    -- RU Realms
    ["Гордунни"] = 23400,
    ["Свежеватель Душ"] = 21500,
    ["Ревущий фьорд"] = 24800,
    ["Пиратская Бухта"] = 6200,
    ["Вечная Песня"] = 6200,
    ["Дракономор"] = 6500,
    ["Ясеневый лес"] = 5200,
    ["Страж Смерти"] = 4800,
    ["Черный Шрам"] = 5100,
    ["Борейская тундра"] = 4900,
    ["Галакронд"] = 5800,
    ["Голдринн"] = 4100,
    -- Major EU / US Realms
    ["Silvermoon"] = 28500,
    ["Draenor"] = 29200,
    ["Kazzak"] = 26400,
    ["Tarren Mill"] = 24900,
    ["Twisting Nether"] = 23800,
    ["Ravencrest"] = 21200,
    ["Argent Dawn"] = 22500,
    ["Area 52"] = 31000,
    ["Illidan"] = 29800,
    ["Stormrage"] = 28900,
    ["Tichondrius"] = 22400,
}
addon.DefaultRealmPopulation = 14000

local RuRealmToEnglish = {
    ["Пиратская Бухта"] = "Booty Bay",
    ["Свежеватель Душ"] = "Soulflayer",
    ["Ревущий фьорд"] = "Howling Fjord",
    ["Гордунни"] = "Gordunni",
    ["Дракономор"] = "Fordragon",
    ["Ясеневый лес"] = "Ashenvale",
    ["Страж Смерти"] = "Deathguard",
    ["Черный Шрам"] = "Blackscar",
    ["Борейская тундра"] = "Borean Tundra",
    ["Вечная Песня"] = "Eversong",
    ["Галакронд"] = "Galakrond",
    ["Голдринн"] = "Goldrinn",
}

addon.ExpansionNames = {
    [1]  = { ru = "Classic (Ванилла)",       en = "Classic",                color = "|cffffd100" },
    [2]  = { ru = "The Burning Crusade",     en = "The Burning Crusade",    color = "|cff1eff00" },
    [3]  = { ru = "Wrath of the Lich King",  en = "Wrath of the Lich King", color = "|cff00ccff" },
    [4]  = { ru = "Cataclysm",               en = "Cataclysm",              color = "|cffff5500" },
    [5]  = { ru = "Mists of Pandaria",       en = "Mists of Pandaria",      color = "|cff00ff96" },
    [6]  = { ru = "Warlords of Draenor",     en = "Warlords of Draenor",    color = "|cffff8800" },
    [7]  = { ru = "Legion",                  en = "Legion",                 color = "|cffa335ee" },
    [8]  = { ru = "Battle for Azeroth",      en = "Battle for Azeroth",     color = "|cff0070dd" },
    [9]  = { ru = "Shadowlands",             en = "Shadowlands",            color = "|cffb0c4de" },
    [10] = { ru = "Dragonflight",            en = "Dragonflight",           color = "|cff33937f" },
    [11] = { ru = "The War Within",          en = "The War Within",         color = "|cffff7c0a" },
    [12] = { ru = "Midnight (Полночь)",      en = "Midnight",               color = "|cffc678dd" },
}

function addon:GetCharKey()
    local name = UnitName("player") or "Player"
    local realm = GetRealmName() or "Realm"
    return name .. " - " .. realm
end

function addon:LocalizeRealmName(realm)
    if not realm or type(realm) ~= "string" then return "Realm" end
    if self:IsEnglish() then
        return RuRealmToEnglish[realm] or realm
    end
    return realm
end

function addon:InitDB()
    if type(_G.TitleCollectorDB) ~= "table" then
        _G.TitleCollectorDB = {}
    end
    local db = _G.TitleCollectorDB
    db.favorites = db.favorites or {}
    db.realmCensus = db.realmCensus or {}
    db.autoRules = db.autoRules or {}
    db.minimap = db.minimap or { hide = false, angle = 212, iconIdx = 1 }
    if type(db.minimap.angle) ~= "number" then db.minimap.angle = 212 end
    if type(db.minimap.iconIdx) ~= "number" then db.minimap.iconIdx = 1 end

    db.settings = db.settings or {}
    local defaults = {
        language = "AUTO",
        hideUnobtainable = true,
        hideOppositeFaction = true,
        showGlobalRarity = true,
        showServerRarity = true,
        scanRealmTitles = true,
        showPlayerTooltips = true,
        showProgressToast = true,
        showCharPaneButton = true,
        enableAutoTitle = false, -- Отключаемая опция по запросу Ани!
        onlyMissingCriteria = false,
    }
    for k, v in pairs(defaults) do
        if db.settings[k] == nil then
            db.settings[k] = v
        end
    end

    self.db = db
end

local function NormalizeCleanTitle(str)
    if not str or type(str) ~= "string" then return "" end
    local s = string.gsub(str, "%%s", "")
    s = string.gsub(s, "^[%s,%.%-–—:]+", "")
    s = string.gsub(s, "[%s,%.%-–—:]+$", "")
    return string.lower(strtrim(s))
end

function addon:BuildTitleIndex()
    wipe(self.Titles)
    wipe(self.TitleByMaskID)
    wipe(self.TitleByCleanText)
    wipe(self.TitlesByMapID)
    wipe(self.TitlesByAchID)

    if not TitlesDB and LibStub then
        TitlesDB = LibStub("TitlesDB-1.0", true)
    end

    local isHordePlayer = (UnitFactionGroup and UnitFactionGroup("player") == "Horde")
    local rawMap = (TitlesDB and TitlesDB.Titles) or {}
    for maskID, t in pairs(rawMap) do
        t.maskID = maskID
        -- Фракционные координаты Бойцовской гильдии («Звезда арены» #61429 и «Боец»)
        if not t.mapID and (t.achID == 61429 or t.clean_en == "Brawler") then
            if isHordePlayer then
                t.mapID, t.x, t.y = 85, 70.6, 30.8
                t.zone_ru, t.zone_en = "Оргриммар (Арена Морд'Бой)", "Orgrimmar (Brawl'gar Arena)"
            else
                t.mapID, t.x, t.y = 84, 64.0, 30.2
                t.zone_ru, t.zone_en = "Штормград (Потасовочная «У Бизмо»)", "Stormwind (Bizmo's Brawlpub)"
            end
        end
        self.TitleByMaskID[maskID] = t
        table.insert(self.Titles, t)

        for _, field in ipairs({ "clean_ru", "clean_en", "nameM_ru", "nameF_ru", "nameM_en", "nameF_en" }) do
            local norm = NormalizeCleanTitle(t[field])
            if norm ~= "" and not self.TitleByCleanText[norm] then
                self.TitleByCleanText[norm] = maskID
            end
        end

        if t.mapID and t.mapID > 0 then
            self.TitlesByMapID[t.mapID] = self.TitlesByMapID[t.mapID] or {}
            table.insert(self.TitlesByMapID[t.mapID], t)
        end
        if t.achID and t.achID > 0 then
            self.TitlesByAchID[t.achID] = t
        end
    end

    -- Досканируем живой клиент (GetNumTitles / GetTitleName) на случай новых званий патча
    local numClient = (_G.GetNumTitles and GetNumTitles()) or 0
    for maskID = 1, numClient do
        local ok, rawClientName = pcall(GetTitleName, maskID)
        if ok and SafeNotSecret(rawClientName) and type(rawClientName) == "string" and rawClientName ~= "" then
            local cleanClient = strtrim(rawClientName)
            if cleanClient ~= "" and not string.find(string.upper(cleanClient), "UNUSED", 1, true) then
                local existing = self.TitleByMaskID[maskID]
                if existing then
                    existing.clientText = cleanClient
                    local normC = NormalizeCleanTitle(cleanClient)
                    if normC ~= "" then
                        self.TitleByCleanText[normC] = maskID
                    end
                elseif _G.IsTitleKnown and IsTitleKnown(maskID) then
                    local isPrefix = (string.sub(rawClientName, -1) == " ")
                    local pat = isPrefix and (cleanClient .. " %s") or ("%s, " .. cleanClient)
                    local dynTitle = {
                        dbID = maskID,
                        maskID = maskID,
                        nameM_ru = pat,
                        nameF_ru = pat,
                        nameM_en = pat,
                        nameF_en = pat,
                        clean_ru = cleanClient,
                        clean_en = cleanClient,
                        clientText = cleanClient,
                        isPrefix = isPrefix,
                        exp = 12,
                        cat = "Achievement",
                        kind = "Achievement",
                        difficulty = "SOLO_GRIND",
                        faction = 0,
                        obtainable = true,
                        rarityTier = 3,
                    }
                    self.TitleByMaskID[maskID] = dynTitle
                    table.insert(self.Titles, dynTitle)
                    local normC = NormalizeCleanTitle(cleanClient)
                    if normC ~= "" then
                        self.TitleByCleanText[normC] = maskID
                    end
                end
            end
        end
    end

    table.sort(self.Titles, function(a, b)
        return (a.maskID or 0) < (b.maskID or 0)
    end)
end

-- ============================================================================
-- ПРОВЕРКА КОЛЛЕКЦИИ, ИМЕНИ И ПРЕВЬЮ РОДА (М/Ж)
-- ============================================================================
function addon:IsTitleCollected(titleOrMaskID)
    local maskID = type(titleOrMaskID) == "table" and titleOrMaskID.maskID or titleOrMaskID
    if not maskID or not _G.IsTitleKnown then return false end
    local ok, known = pcall(IsTitleKnown, maskID)
    return ok and known == true
end

function addon:IsTitleFavorite(maskID)
    return (self.db and self.db.favorites and self.db.favorites[maskID]) == true
end

function addon:ToggleTitleFavorite(maskID)
    if not maskID or not self.db then return end
    if self.db.favorites[maskID] then
        self.db.favorites[maskID] = nil
    else
        self.db.favorites[maskID] = true
    end
    if self.RefreshUI then self:RefreshUI() end
end

function addon:IsPlayerFemale()
    return (_G.UnitSex and UnitSex("player") == 3)
end

function addon:GetTitleCleanName(title, useFemale)
    if not title then return "" end
    if useFemale == nil then
        useFemale = self:IsPlayerFemale()
    end
    local isEN = self:IsEnglish()
    local pat = isEN
        and (useFemale and title.nameF_en or title.nameM_en)
        or (useFemale and title.nameF_ru or title.nameM_ru)
    if not pat or pat == "" then
        pat = isEN and title.clean_en or title.clean_ru or ""
    end
    local s = string.gsub(pat, "%%s", "")
    s = string.gsub(s, "^[%s,]+", "")
    s = string.gsub(s, "[%s,]+$", "")
    return (s ~= "" and s) or title.clean_ru or title.clean_en or ("Title #" .. tostring(title.maskID))
end

function addon:IsTitlePrefix(title, useFemale)
    if not title then return true end
    if useFemale == nil then
        useFemale = self:IsPlayerFemale()
    end
    local isEN = self:IsEnglish()
    local pat = isEN
        and (useFemale and title.nameF_en or title.nameM_en)
        or (useFemale and title.nameF_ru or title.nameM_ru)
    if pat and type(pat) == "string" then
        local idx = string.find(pat, "%%s", 1, true)
        if idx then
            return idx > (#pat / 2)
        end
    end
    return title.isPrefix == true
end

local CYR_NAME_OVERRIDES = {
    ["ньярлатхотеп"] = "Nyarlathotep",
    ["ньярлатокэт"] = "Nyarlatocat",
    ["гитхард"] = "Githard",
    ["гитпулл"] = "Gitpull",
    ["трипобраз"] = "Tripobraz",
    ["котастрофа"] = "Catastrophe",
}

local CYR_TO_LAT = {
    ["А"]="A", ["Б"]="B", ["В"]="V", ["Г"]="G", ["Д"]="D", ["Е"]="E", ["Ё"]="Yo", ["Ж"]="Zh",
    ["З"]="Z", ["И"]="I", ["Й"]="Y", ["К"]="K", ["Л"]="L", ["М"]="M", ["Н"]="N", ["О"]="O",
    ["П"]="P", ["Р"]="R", ["С"]="S", ["Т"]="T", ["У"]="U", ["Ф"]="F", ["Х"]="Kh", ["Ц"]="Ts",
    ["Ч"]="Ch", ["Ш"]="Sh", ["Щ"]="Shch", ["Ъ"]="", ["Ы"]="Y", ["Ь"]="", ["Э"]="E", ["Ю"]="Yu", ["Я"]="Ya",
    ["а"]="a", ["б"]="b", ["в"]="v", ["г"]="g", ["д"]="d", ["е"]="e", ["ё"]="yo", ["ж"]="zh",
    ["з"]="z", ["и"]="i", ["й"]="y", ["к"]="k", ["л"]="l", ["м"]="m", ["н"]="n", ["о"]="o",
    ["п"]="p", ["р"]="r", ["с"]="s", ["т"]="t", ["у"]="u", ["ф"]="f", ["х"]="kh", ["ц"]="ts",
    ["ч"]="ch", ["ш"]="sh", ["щ"]="shch", ["ъ"]="", ["ы"]="y", ["ь"]="", ["э"]="e", ["ю"]="yu", ["я"]="ya",
}

function addon:FormatPreviewPlayerName(rawName)
    local isEN = self:IsEnglish()
    local fallback = isEN and "Hero" or "Герой"
    if not rawName or not SafeNotSecret(rawName) or type(rawName) ~= "string" or rawName == "" then
        return fallback
    end
    if not isEN then
        return rawName
    end
    local ov = CYR_NAME_OVERRIDES[string.lower(rawName)]
    if ov then
        return ov
    end
    local out = string.gsub(rawName, "[\208-\209][\128-\191]", function(ch)
        return CYR_TO_LAT[ch] or ch
    end)
    return out
end

function addon:FormatTitleWithPlayerName(title, playerName, useFemale)
    if not title then return playerName or "" end
    playerName = playerName or UnitName("player") or "Герой"
    if useFemale == nil then
        useFemale = self:IsPlayerFemale()
    end
    local isEN = self:IsEnglish()
    local pat = isEN
        and (useFemale and title.nameF_en or title.nameM_en)
        or (useFemale and title.nameF_ru or title.nameM_ru)
    if pat and string.find(pat, "%%s") then
        return (string.gsub(pat, "%%s", playerName))
    end
    local clean = self:GetTitleCleanName(title, useFemale)
    if self:IsTitlePrefix(title, useFemale) then
        return clean .. " " .. playerName
    else
        return playerName .. ", " .. clean
    end
end

function addon:GetTitleNote(title)
    if not title then return "" end
    if self:IsEnglish() then
        return (title.note_en and title.note_en ~= "" and title.note_en)
            or (title.achDesc_en and title.achDesc_en ~= "" and title.achDesc_en)
            or title.note_ru or ""
    end
    return (title.note_ru and title.note_ru ~= "" and title.note_ru)
        or (title.achDesc_ru and title.achDesc_ru ~= "" and title.achDesc_ru)
        or title.note_en or ""
end

function addon:GetTitleZoneName(title)
    if not title then return "" end
    if self:IsEnglish() and title.zone_en and title.zone_en ~= "" then
        return title.zone_en
    elseif not self:IsEnglish() and title.zone_ru and title.zone_ru ~= "" then
        return title.zone_ru
    end
    if title.mapID and C_Map and C_Map.GetMapInfo then
        local info = C_Map.GetMapInfo(title.mapID)
        if info and SafeNotSecret(info.name) and info.name then
            return info.name
        end
    end
    return ""
end

function addon:IsTitleRelevantForPlayerFaction(title)
    if not title or not title.faction or title.faction == 0 then
        return true
    end
    local fac = UnitFactionGroup and UnitFactionGroup("player")
    if fac == "Alliance" then
        return title.faction == 1
    elseif fac == "Horde" then
        return title.faction == 2
    end
    return true
end

-- ============================================================================
-- НАДЕВАНИЕ И СНЯТИЕ ЗВАНИЯ (С ОЧЕРЕДЬЮ ВНЕ БОЯ)
-- ============================================================================
function addon:EquipTitle(maskID, silent)
    if not _G.SetCurrentTitle then return end
    if maskID and maskID > 0 and not self:IsTitleCollected(maskID) then
        return
    end
    local tObj = maskID and maskID > 0 and self.TitleByMaskID[maskID] or nil
    local tName = tObj and self:GetTitleCleanName(tObj) or "—"

    if InCombatLockdown and InCombatLockdown() then
        self.pendingEquipMaskID = maskID or 0
        if not silent then
            print(self:L("CHAT_COMBAT_QUEUED_FMT", tName))
        end
        return
    end

    self.pendingEquipMaskID = nil
    pcall(SetCurrentTitle, maskID or 0)
    if not silent and maskID and maskID > 0 then
        print(self:L("CHAT_EQUIPPED_FMT", tName))
    end
    if self.RefreshUI then
        C_Timer.After(0.15, function() self:RefreshUI() end)
    end
end

function addon:EquipRandomFavorite(silent)
    local pool = {}
    local curMask = (_G.GetCurrentTitle and GetCurrentTitle()) or -1
    if self.db and self.db.favorites then
        for maskID, isFav in pairs(self.db.favorites) do
            if isFav and self:IsTitleCollected(maskID) then
                table.insert(pool, maskID)
            end
        end
    end
    if #pool == 0 then
        if not silent then
            print(self:L("CHAT_NO_FAVS"))
        end
        return false
    end
    local chosen = pool[1]
    if #pool > 1 then
        local filtered = {}
        for _, m in ipairs(pool) do
            if m ~= curMask then table.insert(filtered, m) end
        end
        if #filtered > 0 then
            chosen = filtered[math.random(1, #filtered)]
        end
    end
    self:EquipTitle(chosen, silent)
    return true
end

-- ============================================================================
-- ГЛОБАЛЬНАЯ И СЕРВЕРНАЯ РЕДКОСТЬ (КАК В MOUNTCOLLECTOR)
-- ============================================================================
function addon:GetGlobalRarity(titleOrMaskID)
    local t = type(titleOrMaskID) == "table" and titleOrMaskID or self.TitleByMaskID[titleOrMaskID]
    if not t then return nil end
    if type(t.rarity) == "number" then
        return t.rarity
    end
    return nil
end

function addon:FormatRarityTier(rarityPct)
    if type(rarityPct) ~= "number" then
        return self:L("NO_DATA"), self:L("TIER_UNKNOWN"), "|cff999999"
    end
    if rarityPct < 0.05 then
        return string.format("|cffff8000%.3f%%|r", rarityPct), self:L("TIER_MYTHIC"), "|cffff8000"
    elseif rarityPct < 1.0 then
        return string.format("|cffff8000%.2f%%|r", rarityPct), self:L("TIER_MYTHIC"), "|cffff8000"
    elseif rarityPct < 3.0 then
        return string.format("|cffff5500%.2f%%|r", rarityPct), self:L("TIER_ULTRA"), "|cffff5500"
    elseif rarityPct < 10.0 then
        return string.format("|cffa335ee%.1f%%|r", rarityPct), self:L("TIER_EPIC"), "|cffa335ee"
    elseif rarityPct < 25.0 then
        return string.format("|cff0070dd%.1f%%|r", rarityPct), self:L("TIER_RARE"), "|cff0070dd"
    elseif rarityPct < 50.0 then
        return string.format("|cff1eff00%.1f%%|r", rarityPct), self:L("TIER_UNCOMMON"), "|cff1eff00"
    else
        return string.format("|cffffffff%.1f%%|r", rarityPct), self:L("TIER_COMMON"), "|cffffffff"
    end
end

function addon:GetServerRarityInfo(titleOrMaskID)
    local maskID = type(titleOrMaskID) == "table" and titleOrMaskID.maskID or titleOrMaskID
    local rawRealm = GetRealmName() or "Realm"
    local realmPop = self.RealmPopulations[rawRealm] or self.DefaultRealmPopulation
    local globalPct = self:GetGlobalRarity(titleOrMaskID)

    local seenCount = 0
    if maskID and self.db and self.db.realmCensus and self.db.realmCensus[rawRealm] and self.db.realmCensus[rawRealm][maskID] then
        seenCount = self.db.realmCensus[rawRealm][maskID].count or 0
    end

    local estOwners = nil
    if type(globalPct) == "number" then
        estOwners = math.max(seenCount, math.floor((globalPct / 100.0) * realmPop + 0.5))
    end

    local displayRealm = self:LocalizeRealmName(rawRealm)
    return displayRealm, realmPop, estOwners, seenCount, globalPct
end

-- Извлекает объект звания, надетого на указанного юнита-игрока (с полной защитой от Secret Values 12.x)
function addon:ExtractUnitTitle(unit)
    if not unit or not SafeNotSecret(unit) or type(unit) ~= "string" then return nil, nil, nil end
    if not UnitExists or not UnitIsPlayer then return nil, nil, nil end

    local okE, exists = pcall(UnitExists, unit)
    if not okE or not SafeNotSecret(exists) or not exists then return nil, nil, nil end

    local okP, isPlayer = pcall(UnitIsPlayer, unit)
    if not okP or not SafeNotSecret(isPlayer) or not isPlayer then return nil, nil, nil end

    local okN, uName, uRealm = pcall(UnitName, unit)
    local okPVP, pvpName = false, nil
    if UnitPVPName then
        okPVP, pvpName = pcall(UnitPVPName, unit)
    end
    if not okN or not okPVP or not SafeNotSecret(uName) or not SafeNotSecret(pvpName) then
        return nil, nil, nil
    end
    if type(uName) ~= "string" or type(pvpName) ~= "string" or uName == "" or pvpName == "" then
        return nil, nil, nil
    end
    if pvpName == uName then return nil, nil, nil end

    local sIdx, eIdx = string.find(pvpName, uName, 1, true)
    if not sIdx then return nil, nil, nil end
    local before = string.sub(pvpName, 1, sIdx - 1)
    local after = string.sub(pvpName, eIdx + 1)
    local extracted = (before ~= "" and before) or after
    local norm = NormalizeCleanTitle(extracted)
    if norm == "" then return nil, nil, nil end

    local maskID = self.TitleByCleanText[norm]
    if not maskID then return nil, nil, nil end
    return self.TitleByMaskID[maskID], uName, uRealm
end

-- Пассивный сканер званий на игроках вокруг (Realm Census)
function addon:ScanUnitTitle(unit)
    if not self.db or not self.db.settings or not self.db.settings.scanRealmTitles then return end
    if InCombatLockdown and InCombatLockdown() then return end

    local titleObj, uName, uRealm = self:ExtractUnitTitle(unit)
    if not titleObj or not uName then return end
    local maskID = titleObj.maskID

    local realm = (SafeNotSecret(uRealm) and uRealm and uRealm ~= "") and uRealm or (GetRealmName() or "Realm")
    self.db.realmCensus[realm] = self.db.realmCensus[realm] or {}
    local entry = self.db.realmCensus[realm][maskID]
    if not entry then
        entry = { count = 0, players = {} }
        self.db.realmCensus[realm][maskID] = entry
    end
    if not entry.players[uName] then
        entry.players[uName] = time()
        entry.count = (entry.count or 0) + 1
    else
        entry.players[uName] = time()
    end
end

-- Интеграция в тултип игроков в мире (показывает редкость, источник и ваш прогресс по званию игрока)
function addon:InitPlayerTooltips()
    if self.playerTooltipsHooked then return end
    if not _G.TooltipDataProcessor or not _G.Enum or not _G.Enum.TooltipDataType then return end
    self.playerTooltipsHooked = true

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
        if tooltip ~= GameTooltip then return end
        if not self.db or not self.db.settings or not self.db.settings.showPlayerTooltips then return end
        if InCombatLockdown and InCombatLockdown() then return end

        local okU, _, unit = pcall(tooltip.GetUnit, tooltip)
        unit = (okU and SafeNotSecret(unit) and unit) or "mouseover"
        local titleObj = self:ExtractUnitTitle(unit)
        if not titleObj then return end

        -- Защита от дублирования строк
        local ttName = tooltip.GetName and tooltip:GetName()
        local numLines = (tooltip.NumLines and tooltip:NumLines()) or 0
        if ttName and SafeNotSecret(numLines) and type(numLines) == "number" then
            for i = 1, numLines do
                local leftLine = _G[ttName .. "TextLeft" .. i]
                local txt = leftLine and leftLine.GetText and leftLine:GetText()
                if SafeNotSecret(txt) and type(txt) == "string" and string.find(txt, "TitleCollector", 1, true) then
                    return
                end
            end
        end

        local cleanName = self:GetTitleCleanName(titleObj)
        local expInfo = self.ExpansionNames[titleObj.exp or 1] or self.ExpansionNames[1]
        local expName = self:IsEnglish() and expInfo.en or expInfo.ru

        tooltip:AddLine(" ")
        tooltip:AddDoubleLine(
            self:L("TT_PLAYER_TITLE_HDR") .. " |cffffd100" .. cleanName .. "|r",
            expInfo.color .. expName .. "|r"
        )

        if self.db.settings.showGlobalRarity then
            local gPct = self:GetGlobalRarity(titleObj)
            local pctText, tierLabel = self:FormatRarityTier(gPct)
            tooltip:AddLine(self:L("TT_RARITY_FMT", pctText, tierLabel), 0.9, 0.9, 0.9, true)
        end

        local srcName = (self:IsEnglish() and titleObj.achName_en or titleObj.achName_ru)
            or (self:IsEnglish() and titleObj.questName_en or titleObj.questName_ru)
            or titleObj.cat
        if srcName and srcName ~= "" then
            tooltip:AddLine(self:L("TT_SOURCE_FMT", srcName), 0.85, 0.88, 0.95, true)
        end

        if self:IsTitleCollected(titleObj.maskID) then
            tooltip:AddLine(self:L("TT_COLLECTED_YES"))
        else
            local prog = self:EvaluateTitleProgress(titleObj, false, true)
            local pct = prog and prog.pct or 0
            tooltip:AddLine(self:L("TT_COLLECTED_NO_FMT", pct))
        end
        tooltip:Show()
    end)
end
