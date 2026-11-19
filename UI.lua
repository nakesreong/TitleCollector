local addonName, addon = ...

-- ============================================================================
-- TitleCollector — UI.lua
-- Главное окно, вкладки («Почти готово», «В текущей зоне», «Все звания»,
-- «Собранные», «Авто-титулы», «Настройки»), правый Инспектор с живым
-- превью М/Ж, двойным блоком редкости (Мир + Сервер), чек-листом критериев,
-- круглая кнопка у миникарты и интеграция в окно персонажа.
-- ============================================================================

local LibStub = _G.LibStub
local LDB = LibStub and LibStub("LibDataBroker-1.1", true)

local ROW_HEIGHT = 40
local VISIBLE_ROWS = 11

local MINIMAP_ICONS = {
    { icon = 237537, name = "Сияние короны",         nameEN = "Radiant Crown" },
    { icon = 135921, name = "Золотой венец",         nameEN = "Golden Halo" },
    { icon = 135993, name = "Благословение королей", nameEN = "Crown of Kings" },
    { icon = 135880, name = "Кубок славы",           nameEN = "Chalice of Glory" },
}

local DIFF_META = {
    SOLO_FAST  = { key = "DIFF_SOLO_FAST",  color = "|cff00ff96", order = 1 },
    SOLO_RAID  = { key = "DIFF_SOLO_RAID",  color = "|cff00ccff", order = 2 },
    SOLO_GRIND = { key = "DIFF_SOLO_GRIND", color = "|cffffd100", order = 3 },
    GROUP      = { key = "DIFF_GROUP",      color = "|cffff8800", order = 4 },
    PVP        = { key = "DIFF_PVP",        color = "|cffff4466", order = 5 },
    LEGACY     = { key = "DIFF_LEGACY",     color = "|cff888888", order = 6 },
}

local ui = {
    currentTab = "ALMOST", -- ALMOST | ZONE | ALL | COLLECTED | AUTOTITLE | SETTINGS
    searchText = "",
    filterExp = 0,         -- 0 = Все, 1..12
    filterCat = "ALL",
    filterDiff = "ALL",
    filterAffix = "ALL",   -- ALL | PREFIX | SUFFIX
    onlyFavorites = false,
    sortBy = "PROGRESS",   -- PROGRESS | RARITY | NAME | EXP
    scrollOffset = 0,
    filteredTitles = {},
    selectedTitle = nil,
    previewFemale = nil,
    rows = {},
    critRows = {},
    tabButtons = {},
    autoRuleRows = {},
}
addon.UIState = ui

-- ============================================================================
-- БАЗОВЫЕ ХЕЛПЕРЫ ОФОРМЛЕНИЯ (ТЁМНО-ЗОЛОТОЙ СТИЛЬ КОЛЛЕКТОРОВ)
-- ============================================================================
local function ApplyBackdrop(frame, bgR, bgG, bgB, bgA, brR, brG, brB, brA)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    frame:SetBackdropColor(bgR or 0.06, bgG or 0.06, bgB or 0.07, bgA or 0.96)
    frame:SetBackdropBorderColor(brR or 0.24, brG or 0.22, brB or 0.18, brA or 1.0)
end

local function CreateCollectorButton(parent, width, height, text, isGold)
    local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
    btn:SetSize(width, height)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    if isGold then
        ApplyBackdrop(btn, 0.18, 0.14, 0.05, 0.96, 0.85, 0.68, 0.15, 1.0)
        btn.defaultBg = { 0.18, 0.14, 0.05, 0.96 }
        btn.defaultBorder = { 0.85, 0.68, 0.15, 1.0 }
    else
        ApplyBackdrop(btn, 0.11, 0.11, 0.13, 0.96, 0.26, 0.26, 0.30, 1.0)
        btn.defaultBg = { 0.11, 0.11, 0.13, 0.96 }
        btn.defaultBorder = { 0.26, 0.26, 0.30, 1.0 }
    end

    btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.label:SetPoint("LEFT", btn, "LEFT", 6, 0)
    btn.label:SetPoint("RIGHT", btn, "RIGHT", -6, 0)
    btn.label:SetJustifyH("CENTER")
    btn.label:SetWordWrap(false)
    btn.label:SetText(text or "")
    if isGold then
        btn.label:SetTextColor(1.0, 0.86, 0.22, 1.0)
    else
        btn.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
    end

    btn:SetScript("OnEnter", function(self)
        if not self:IsEnabled() then return end
        self:SetBackdropColor(0.24, 0.19, 0.08, 0.98)
        self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
        self.label:SetTextColor(1.0, 0.92, 0.40, 1.0)
    end)
    btn:SetScript("OnLeave", function(self)
        if self.isActiveTab then
            self:SetBackdropColor(0.22, 0.17, 0.06, 0.98)
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
            self.label:SetTextColor(1.0, 0.86, 0.20, 1.0)
        else
            self:SetBackdropColor(unpack(self.defaultBg))
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
            if not self:IsEnabled() then
                self.label:SetTextColor(0.45, 0.45, 0.48, 1.0)
            elseif isGold then
                self.label:SetTextColor(1.0, 0.86, 0.22, 1.0)
            else
                self.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
            end
        end
    end)

    btn:SetScript("OnDisable", function(self)
        self:SetBackdropColor(0.08, 0.08, 0.09, 0.90)
        self:SetBackdropBorderColor(0.18, 0.18, 0.20, 0.90)
        self.label:SetTextColor(0.42, 0.42, 0.45, 1.0)
    end)
    btn:SetScript("OnEnable", function(self)
        self:SetBackdropColor(unpack(self.defaultBg))
        self:SetBackdropBorderColor(unpack(self.defaultBorder))
        if isGold then
            self.label:SetTextColor(1.0, 0.86, 0.22, 1.0)
        else
            self.label:SetTextColor(0.92, 0.92, 0.95, 1.0)
        end
    end)

    function btn:SetText(str)
        self.label:SetText(str or "")
    end

    function btn:SetActiveTab(active)
        self.isActiveTab = active
        if active then
            self:SetBackdropColor(0.22, 0.17, 0.06, 0.98)
            self:SetBackdropBorderColor(1.0, 0.82, 0.0, 1.0)
            self.label:SetTextColor(1.0, 0.86, 0.20, 1.0)
        else
            self:SetBackdropColor(unpack(self.defaultBg))
            self:SetBackdropBorderColor(unpack(self.defaultBorder))
            self.label:SetTextColor(0.90, 0.90, 0.94, 1.0)
        end
    end

    return btn
end

-- Всплывающее меню-выпадашка в тёмно-золотом стиле для фильтров
local dropdownFrame = nil
local function HideCollectorDropdown()
    if dropdownFrame and dropdownFrame:IsShown() then
        dropdownFrame:Hide()
        dropdownFrame.anchorBtn = nil
    end
end

local function ToggleCollectorDropdown(anchorBtn, items, minWidth)
    if not dropdownFrame then
        dropdownFrame = CreateFrame("Frame", "TitleCollectorFilterDropdown", UIParent, "BackdropTemplate")
        dropdownFrame:SetFrameStrata("TOOLTIP")
        dropdownFrame:SetToplevel(true)
        dropdownFrame:EnableMouse(true)
        ApplyBackdrop(dropdownFrame, 0.06, 0.06, 0.08, 0.98, 0.80, 0.65, 0.18, 1.0)
        dropdownFrame.rows = {}
        dropdownFrame:Hide()
    end

    if dropdownFrame:IsShown() and dropdownFrame.anchorBtn == anchorBtn then
        HideCollectorDropdown()
        return
    end

    dropdownFrame.anchorBtn = anchorBtn
    local rowH = 22
    local pad = 6
    local w = math.max(minWidth or 180, anchorBtn:GetWidth())

    for i, item in ipairs(items) do
        local r = dropdownFrame.rows[i]
        if not r then
            r = CreateFrame("Button", nil, dropdownFrame, "BackdropTemplate")
            r:SetHeight(rowH)
            ApplyBackdrop(r, 0.08, 0.08, 0.10, 0.0, 0, 0, 0, 0)
            r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            r.label:SetPoint("LEFT", r, "LEFT", 8, 0)
            r.label:SetPoint("RIGHT", r, "RIGHT", -8, 0)
            r.label:SetJustifyH("LEFT")
            r.label:SetWordWrap(false)
            r:SetScript("OnEnter", function(selfR)
                selfR:SetBackdropColor(0.24, 0.19, 0.08, 0.95)
            end)
            r:SetScript("OnLeave", function(selfR)
                if selfR.isChecked then
                    selfR:SetBackdropColor(0.16, 0.13, 0.05, 0.85)
                else
                    selfR:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
                end
            end)
            dropdownFrame.rows[i] = r
        end

        r:SetPoint("TOPLEFT", dropdownFrame, "TOPLEFT", pad, -pad - (i - 1) * rowH)
        r:SetPoint("TOPRIGHT", dropdownFrame, "TOPRIGHT", -pad, -pad - (i - 1) * rowH)
        r.isChecked = item.checked == true
        if r.isChecked then
            r:SetBackdropColor(0.16, 0.13, 0.05, 0.85)
        else
            r:SetBackdropColor(0.08, 0.08, 0.10, 0.0)
        end
        local mark = item.checked
            and "|TInterface\\RaidFrame\\ReadyCheck-Ready:12:12:0:0|t "
            or "    "
        r.label:SetText(mark .. (item.text or ""))
        local reqW = (r.label:GetStringWidth() or 120) + 28
        if reqW > w then w = reqW end

        r:SetScript("OnClick", function()
            HideCollectorDropdown()
            if item.func then item.func() end
        end)
        r:Show()
    end

    for i = #items + 1, #dropdownFrame.rows do
        dropdownFrame.rows[i]:Hide()
    end

    dropdownFrame:SetSize(w, (#items * rowH) + pad * 2)
    dropdownFrame:ClearAllPoints()
    dropdownFrame:SetPoint("TOPLEFT", anchorBtn, "BOTTOMLEFT", 0, -2)
    dropdownFrame:Show()
end

local function GetPlayerClassColorHex()
    local _, classFile = UnitClass("player")
    local c = classFile and _G.RAID_CLASS_COLORS and _G.RAID_CLASS_COLORS[classFile]
    if c and c.colorStr then
        return "|c" .. c.colorStr
    end
    return "|cff00ff96"
end

-- ============================================================================
-- ФИЛЬТРАЦИЯ И СОРТИРОВКА СПИСКА ЗВАНИЙ
-- ============================================================================
local function MatchesCategoryFilter(title, filterCat)
    if not filterCat or filterCat == "ALL" then return true end
    local c = string.upper(title.cat or "")
    local k = string.upper(title.kind or "")
    if filterCat == "RAID" then return c == "RAID" end
    if filterCat == "DUNGEON" then return c == "DUNGEON" end
    if filterCat == "PVP" then return c == "PVP" or k == "PVP RANK" end
    if filterCat == "REPUTATION" then return c == "REPUTATION" or k == "REPUTATION" or (title.factionID ~= nil) end
    if filterCat == "QUEST" then return c == "QUEST" or c == "CAMPAIGN" or k == "QUEST" end
    if filterCat == "EXPLORATION" then return c == "EXPLORATION" or c == "OUTDOOR" end
    if filterCat == "HOLIDAY" then return c == "HOLIDAY" end
    if filterCat == "PROFESSION" then return c == "PROFESSION" end
    if filterCat == "ACHIEVEMENT" then return c == "ACHIEVEMENT" end
    return true
end

function addon:RebuildFilteredTitles()
    wipe(ui.filteredTitles)
    local hideUnobtainable = self.db and self.db.settings and self.db.settings.hideUnobtainable
    local hideOppFac = self.db and self.db.settings and self.db.settings.hideOppositeFaction
    local searchLow = string.lower(strtrim(ui.searchText or ""))
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")

    for _, t in ipairs(self.Titles) do
        local isCol = self:IsTitleCollected(t.maskID)
        local pass = true

        if hideOppFac and not self:IsTitleRelevantForPlayerFaction(t) and not isCol then
            pass = false
        end
        if pass and hideUnobtainable and not t.obtainable and not isCol and ui.filterDiff ~= "LEGACY" then
            pass = false
        end

        -- Фильтр по вкладке
        if pass then
            if ui.currentTab == "ALMOST" then
                if isCol or not t.obtainable then
                    pass = false
                end
            elseif ui.currentTab == "ZONE" then
                if isCol then
                    pass = false
                elseif not playerMapID or t.mapID ~= playerMapID then
                    pass = false
                end
            elseif ui.currentTab == "COLLECTED" then
                if not isCol then
                    pass = false
                end
            end
        end

        -- Пользовательские фильтры
        if pass and ui.onlyFavorites and not self:IsTitleFavorite(t.maskID) then
            pass = false
        end
        if pass and ui.filterExp and ui.filterExp > 0 and t.exp ~= ui.filterExp then
            pass = false
        end
        if pass and ui.filterCat ~= "ALL" and not MatchesCategoryFilter(t, ui.filterCat) then
            pass = false
        end
        if pass and ui.filterDiff ~= "ALL" and t.difficulty ~= ui.filterDiff then
            pass = false
        end
        if pass and ui.filterAffix ~= "ALL" then
            local isPref = self:IsTitlePrefix(t, ui.previewFemale)
            if ui.filterAffix == "PREFIX" and not isPref then
                pass = false
            elseif ui.filterAffix == "SUFFIX" and isPref then
                pass = false
            end
        end

        -- Текстовый поиск (RU + EN название, ачивка, зона, подсказка)
        if pass and searchLow ~= "" then
            local blob = string.lower(table.concat({
                t.clean_ru or "",
                t.clean_en or "",
                t.achName_ru or "",
                t.achName_en or "",
                t.zone_ru or "",
                t.zone_en or "",
                t.note_ru or "",
                t.note_en or "",
            }, " "))
            if not string.find(blob, searchLow, 1, true) then
                pass = false
            end
        end

        if pass then
            table.insert(ui.filteredTitles, t)
        end
    end

    -- Сортировка
    table.sort(ui.filteredTitles, function(a, b)
        local favA = self:IsTitleFavorite(a.maskID) and 1 or 0
        local favB = self:IsTitleFavorite(b.maskID) and 1 or 0
        if favA ~= favB then return favA > favB end

        local progA = self:EvaluateTitleProgress(a, false, true)
        local progB = self:EvaluateTitleProgress(b, false, true)

        if ui.currentTab == "COLLECTED" and (ui.sortBy == "RARITY" or ui.sortBy == "PROGRESS") then
            local rA = a.rarity or 999
            local rB = b.rarity or 999
            if math.abs(rA - rB) > 0.0001 then return rA < rB end
        elseif ui.currentTab == "ALMOST" or ui.sortBy == "PROGRESS" then
            local pctA = progA and progA.pct or 0
            local pctB = progB and progB.pct or 0
            if math.abs(pctA - pctB) > 0.05 then
                return pctA > pctB
            end
            local dA = (DIFF_META[a.difficulty] and DIFF_META[a.difficulty].order) or 9
            local dB = (DIFF_META[b.difficulty] and DIFF_META[b.difficulty].order) or 9
            if dA ~= dB then return dA < dB end
        elseif ui.sortBy == "RARITY" then
            local rA = a.rarity or 999
            local rB = b.rarity or 999
            if math.abs(rA - rB) > 0.0001 then return rA < rB end
        elseif ui.sortBy == "EXP" then
            if (a.exp or 0) ~= (b.exp or 0) then
                return (a.exp or 0) > (b.exp or 0)
            end
        end

        local nameA = self:GetTitleCleanName(a)
        local nameB = self:GetTitleCleanName(b)
        return nameA < nameB
    end)

    if not ui.selectedTitle or not self.TitleByMaskID[ui.selectedTitle.maskID] then
        ui.selectedTitle = ui.filteredTitles[1] or self.Titles[1]
    end
end

-- ============================================================================
-- ОТРИСОВКА ПРАВОГО ИНСПЕКТОРА ВЫБРАННОГО ЗВАНИЯ
-- ============================================================================
function addon:RefreshInspector()
    if not ui.mainFrame or not ui.inspector then return end
    local insp = ui.inspector
    local t = ui.selectedTitle

    if not t then
        insp.titleFS:SetText("—")
        insp.previewFS:SetText("—")
        return
    end

    if ui.previewFemale == nil then
        ui.previewFemale = self:IsPlayerFemale()
    end

    local isCol = self:IsTitleCollected(t.maskID)
    local curActiveMask = (_G.GetCurrentTitle and GetCurrentTitle()) or -1
    local isEquipped = (curActiveMask == t.maskID)
    local cleanName = self:GetTitleCleanName(t, ui.previewFemale)
    local expInfo = self.ExpansionNames[t.exp or 1] or self.ExpansionNames[1]
    local expName = self:IsEnglish() and expInfo.en or expInfo.ru
    local diffMeta = DIFF_META[t.difficulty or "SOLO_GRIND"] or DIFF_META.SOLO_GRIND

    local isPref = self:IsTitlePrefix(t, ui.previewFemale)
    insp.iconTex:SetTexture(t.icon or "Interface\\ICONS\\INV_Crown_01")
    insp.titleFS:SetText((isCol and "|cff00ff96" or "|cffffd100") .. cleanName .. "|r")
    insp.subMetaFS:SetText(string.format(
        "%s%s|r • |cff88ccff%s|r • %s%s|r",
        expInfo.color, expName,
        isPref and self:L("INSP_AFFIX_PREFIX") or self:L("INSP_AFFIX_SUFFIX"),
        diffMeta.color, self:L(diffMeta.key)
    ))

    -- Живой предпросмотр над головой персонажа
    local classHex = GetPlayerClassColorHex()
    local playerName = classHex .. (UnitName("player") or "Герой") .. "|r"
    local formattedPreview = self:FormatTitleWithPlayerName(t, playerName, ui.previewFemale)
    insp.previewFS:SetText(formattedPreview)

    insp.genderMBtn:SetActiveTab(not ui.previewFemale)
    insp.genderFBtn:SetActiveTab(ui.previewFemale)

    -- Кнопки Надеть / В трекер целей
    if isCol then
        insp.equipBtn:Enable()
        if isEquipped then
            insp.equipBtn:SetText(self:L("INSP_BTN_UNEQUIP"))
        else
            insp.equipBtn:SetText(self:L("INSP_BTN_EQUIP"))
        end
    else
        insp.equipBtn:Disable()
        insp.equipBtn:SetText(self:L("INSP_BTN_EQUIP"))
    end

    if t.achID and t.achID > 0 and not isCol then
        insp.trackBtn:Enable()
        local tracked = self:IsTitleTracked(t)
        insp.trackBtn:SetText(tracked and self:L("INSP_BTN_UNTRACK") or self:L("INSP_BTN_TRACK"))
    else
        insp.trackBtn:Disable()
        insp.trackBtn:SetText(self:L("INSP_BTN_TRACK"))
    end

    -- Двойной блок редкости (По миру + По серверу, как в MountCollector)
    local dispRealm, realmPop, estOwners, seenCount, globalPct = self:GetServerRarityInfo(t)
    local pctText, tierLabel = self:FormatRarityTier(globalPct)
    insp.rarityGlobalVal:SetText(string.format("%s |cffaaaaaa(%s)|r", pctText, tierLabel))
    insp.rarityServerLbl:SetText(self:L("RARITY_SERVER_LABEL_FMT", dispRealm))
    if estOwners then
        insp.rarityServerVal:SetText(self:L("RARITY_SERVER_VAL_FMT", estOwners, realmPop, seenCount))
    else
        insp.rarityServerVal:SetText(self:L("RARITY_SERVER_SEEN_ONLY_FMT", seenCount))
    end

    -- Прогресс-бар и чек-лист критериев
    local prog = self:EvaluateTitleProgress(t, false, false)
    local pct = prog and prog.pct or 0
    insp.progBar:SetValue(pct)
    if isCol then
        insp.progBar:SetStatusBarColor(0.15, 0.80, 0.35, 0.95)
        insp.progText:SetText(string.format("100%% (%d / %d)", prog.totalCount or 1, prog.totalCount or 1))
    elseif pct >= 70 then
        insp.progBar:SetStatusBarColor(0.20, 0.72, 0.95, 0.95)
        insp.progText:SetText(string.format("%.0f%% (%d / %d)", pct, prog.doneCount or 0, prog.totalCount or 1))
    else
        insp.progBar:SetStatusBarColor(0.85, 0.62, 0.12, 0.95)
        insp.progText:SetText(string.format("%.0f%% (%d / %d)", pct, prog.doneCount or 0, prog.totalCount or 1))
    end

    local onlyMissing = self.db and self.db.settings and self.db.settings.onlyMissingCriteria
    local displayCriteria = {}
    for _, c in ipairs((prog and prog.criteria) or {}) do
        if not onlyMissing or not c.completed then
            table.insert(displayCriteria, c)
        end
    end
    insp.totalCritCount = #displayCriteria
    local maxCritOffset = math.max(0, #displayCriteria - #ui.critRows)
    local critOffset = math.max(0, math.min(ui.critScrollOffset or 0, maxCritOffset))
    ui.critScrollOffset = critOffset

    for idx, cRow in ipairs(ui.critRows) do
        local item = displayCriteria[critOffset + idx]
        if item then
            cRow.item = item
            if item.isSubStep then
                cRow.textFS:SetText("     |cff88ccff•|r |cffcccccc" .. item.text .. "|r")
            else
                local mark = item.completed
                    and "|TInterface\\RaidFrame\\ReadyCheck-Ready:13:13:0:0|t |cff66dd88"
                    or "|TInterface\\RaidFrame\\ReadyCheck-NotReady:13:13:0:0|t |cffeeeeee"
                cRow.textFS:SetText(mark .. item.text .. "|r")
            end
            cRow:Show()
        else
            cRow.item = nil
            cRow:Hide()
        end
    end

    if #displayCriteria == 0 then
        insp.emptyCritFS:SetText(isCol and self:L("INSP_ALL_CRIT_DONE") or self:L("INSP_NO_CRITERIA_INFO"))
        insp.emptyCritFS:Show()
    else
        insp.emptyCritFS:Hide()
    end

    -- Как получить и источники
    local srcLines = {}
    if t.achID and t.achID > 0 then
        local aName = (self:IsEnglish() and t.achName_en or t.achName_ru) or ("#" .. tostring(t.achID))
        table.insert(srcLines, self:L("INSP_SOURCE_ACH_FMT", aName, t.achID))
    end
    if t.questID and t.questID > 0 then
        local qName = (self:IsEnglish() and t.questName_en or t.questName_ru) or ("#" .. tostring(t.questID))
        table.insert(srcLines, self:L("INSP_SOURCE_QUEST_FMT", qName, t.questID))
    end
    local zName = self:GetTitleZoneName(t)
    if zName ~= "" then
        local coordStr = (t.x and t.y) and string.format(" (%.1f, %.1f)", t.x, t.y) or ""
        table.insert(srcLines, self:L("INSP_LOCATION_FMT", zName, coordStr))
    end
    local note = self:GetTitleNote(t)
    if note ~= "" then
        table.insert(srcLines, "|cffdddddd" .. note .. "|r")
    end
    insp.howToFS:SetText(table.concat(srcLines, "\n"))

    -- Кнопки внизу инспектора
    if t.mapID and t.mapID > 0 then
        insp.waypointBtn:Enable()
    else
        insp.waypointBtn:Disable()
    end
    if t.achID and t.achID > 0 then
        insp.openAchBtn:Enable()
    else
        insp.openAchBtn:Disable()
    end
end

-- ============================================================================
-- ОТРИСОВКА СПИСКА ЗВАНИЙ И ВКЛАДОК
-- ============================================================================
function addon:RefreshListRows()
    if not ui.mainFrame then return end
    local total = #ui.filteredTitles
    local maxOffset = math.max(0, total - VISIBLE_ROWS)
    if ui.scrollOffset > maxOffset then ui.scrollOffset = maxOffset end
    if ui.scrollOffset < 0 then ui.scrollOffset = 0 end

    if ui.scrollBar then
        ui.scrollBar:SetMinMaxValues(0, maxOffset)
        ui.scrollBar:SetValue(ui.scrollOffset)
    end

    local curActiveMask = (_G.GetCurrentTitle and GetCurrentTitle()) or -1

    for i = 1, VISIBLE_ROWS do
        local row = ui.rows[i]
        local t = ui.filteredTitles[ui.scrollOffset + i]
        if t then
            row.title = t
            local isCol = self:IsTitleCollected(t.maskID)
            local isFav = self:IsTitleFavorite(t.maskID)
            local isSelected = (ui.selectedTitle and ui.selectedTitle.maskID == t.maskID)
            local isEquipped = (curActiveMask == t.maskID)

            row.favBtn.tex:SetVertexColor(isFav and 1.0 or 0.35, isFav and 0.85 or 0.35, isFav and 0.15 or 0.35, 1.0)
            row.iconTex:SetTexture(t.icon or "Interface\\ICONS\\INV_Crown_01")

            local cleanName = self:GetTitleCleanName(t)
            local eqBadge = isEquipped and " |cff00ff96[Надето]|r" or ""
            row.nameFS:SetText((isCol and "|cff00ff96" or "|cffffd100") .. cleanName .. "|r" .. eqBadge)

            local expInfo = self.ExpansionNames[t.exp or 1] or self.ExpansionNames[1]
            local expName = self:IsEnglish() and expInfo.en or expInfo.ru
            local diffMeta = DIFF_META[t.difficulty or "SOLO_GRIND"] or DIFF_META.SOLO_GRIND
            local zName = self:GetTitleZoneName(t)
            local subText = string.format(
                "%s%s|r • %s%s|r%s",
                expInfo.color, expName,
                diffMeta.color, self:L(diffMeta.key),
                (zName ~= "" and (" • |cff88ccff" .. zName .. "|r") or "")
            )
            row.subFS:SetText(subText)

            local prog = self:EvaluateTitleProgress(t, false, true)
            local pct = prog and prog.pct or 0
            row.progBar:SetValue(pct)
            if isCol then
                if (ui.currentTab == "COLLECTED" or ui.sortBy == "RARITY") and type(t.rarity) == "number" then
                    local r = t.rarity
                    local fmtStr
                    if r < 0.05 then
                        row.progBar:SetStatusBarColor(0.90, 0.48, 0.08, 0.92)
                        fmtStr = string.format("%.3f%%", r)
                    elseif r < 1.0 then
                        row.progBar:SetStatusBarColor(0.90, 0.48, 0.08, 0.92)
                        fmtStr = string.format("%.2f%%", r)
                    elseif r < 3.0 then
                        row.progBar:SetStatusBarColor(0.86, 0.30, 0.12, 0.92)
                        fmtStr = string.format("%.2f%%", r)
                    elseif r < 10.0 then
                        row.progBar:SetStatusBarColor(0.56, 0.22, 0.84, 0.92)
                        fmtStr = string.format("%.1f%%", r)
                    elseif r < 25.0 then
                        row.progBar:SetStatusBarColor(0.10, 0.44, 0.85, 0.92)
                        fmtStr = string.format("%.1f%%", r)
                    elseif r < 50.0 then
                        row.progBar:SetStatusBarColor(0.15, 0.72, 0.32, 0.92)
                        fmtStr = string.format("%.1f%%", r)
                    else
                        row.progBar:SetStatusBarColor(0.36, 0.40, 0.46, 0.92)
                        fmtStr = string.format("%.1f%%", r)
                    end
                    row.progFS:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:11:11:0:0|t |cffffffff" .. fmtStr .. "|r")
                else
                    row.progBar:SetStatusBarColor(0.15, 0.78, 0.35, 0.90)
                    row.progFS:SetText("|TInterface\\RaidFrame\\ReadyCheck-Ready:11:11:0:0|t 100%")
                end
            elseif pct >= 70 then
                row.progBar:SetStatusBarColor(0.18, 0.70, 0.95, 0.90)
                row.progFS:SetText(string.format("%.0f%%", pct))
            elseif pct > 0 then
                row.progBar:SetStatusBarColor(0.85, 0.62, 0.12, 0.90)
                row.progFS:SetText(string.format("%.0f%%", pct))
            else
                row.progBar:SetStatusBarColor(0.25, 0.25, 0.30, 0.80)
                row.progFS:SetText("0%")
            end

            if isSelected then
                row:SetBackdropColor(0.22, 0.18, 0.07, 0.96)
                row:SetBackdropBorderColor(1.0, 0.82, 0.15, 1.0)
            else
                row:SetBackdropColor(0.09, 0.09, 0.11, 0.92)
                row:SetBackdropBorderColor(0.20, 0.20, 0.24, 1.0)
            end
            row:Show()
        else
            row.title = nil
            row:Hide()
        end
    end

    if total == 0 and ui.emptyListFS then
        if ui.currentTab == "ALMOST" then
            ui.emptyListFS:SetText(self:L("EMPTY_LIST_ALMOST"))
        elseif ui.currentTab == "ZONE" then
            local pMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
            local mInfo = pMap and C_Map.GetMapInfo and C_Map.GetMapInfo(pMap)
            local zStr = (mInfo and mInfo.name) or self:L("UNKNOWN_ZONE")
            ui.emptyListFS:SetText(self:L("EMPTY_LIST_ZONE", zStr))
        else
            ui.emptyListFS:SetText(self:L("EMPTY_LIST_DEFAULT"))
        end
        ui.emptyListFS:Show()
    elseif ui.emptyListFS then
        ui.emptyListFS:Hide()
    end
end

function addon:RefreshAutoTitlePanel()
    if not ui.autoPanel or not ui.autoPanel:IsShown() then return end
    local rules = self:GetCharAutoRules()
    ui.autoPanel.masterCB:SetChecked(self.db.settings.enableAutoTitle == true)

    local numSpecs = (_G.GetNumSpecializations and GetNumSpecializations()) or 0
    for i = 1, 4 do
        local sRow = ui.autoRuleRows["SPEC_" .. i]
        if sRow then
            if i <= numSpecs and _G.GetSpecializationInfo then
                local _, specName, _, specIcon = GetSpecializationInfo(i)
                sRow.iconTex:SetTexture(specIcon or 134400)
                sRow.labelFS:SetText(string.format("%d. %s:", i, specName or ("Spec " .. i)))
                sRow.valFS:SetText(self:FormatAutoRuleValue(rules.specs[i]))
                sRow:Show()
            else
                sRow:Hide()
            end
        end
    end

    for _, ctxKey in ipairs({ "PVP", "RAID", "CITY" }) do
        local cRow = ui.autoRuleRows["CTX_" .. ctxKey]
        if cRow then
            cRow.valFS:SetText(self:FormatAutoRuleValue(rules.contexts[ctxKey]))
        end
    end
end

function addon:RefreshSettingsPanel()
    if not ui.settingsPanel or not ui.settingsPanel:IsShown() then return end
    local s = self.db.settings
    for k, cb in pairs(ui.settingsPanel.checkboxes or {}) do
        if k == "showMinimap" then
            cb:SetChecked(not self.db.minimap.hide)
        else
            cb:SetChecked(s[k] == true)
        end
    end
end

function addon:RefreshUI()
    if not ui.mainFrame or not ui.mainFrame:IsShown() then return end

    local col, tot = self:GetOverallCollectionStats()
    local pct = (tot > 0) and math.floor((col / tot) * 100 + 0.5) or 0
    ui.mainFrame.progressFS:SetText(self:L("HEADER_COLLECTED_FMT", col, tot, pct))

    local curMask = (_G.GetCurrentTitle and GetCurrentTitle()) or -1
    local curTitleObj = (curMask and curMask > 0) and self.TitleByMaskID[curMask] or nil
    if curTitleObj then
        ui.mainFrame.activeTitleFS:SetText(self:L("HEADER_ACTIVE_TITLE_FMT", self:GetTitleCleanName(curTitleObj)))
    else
        ui.mainFrame.activeTitleFS:SetText(self:L("HEADER_ACTIVE_TITLE_NONE"))
    end

    for tabID, btn in pairs(ui.tabButtons) do
        btn:SetActiveTab(ui.currentTab == tabID)
    end

    local isCatalogTab = (ui.currentTab ~= "AUTOTITLE" and ui.currentTab ~= "SETTINGS")
    ui.catalogContainer:SetShown(isCatalogTab)
    ui.autoPanel:SetShown(ui.currentTab == "AUTOTITLE")
    ui.settingsPanel:SetShown(ui.currentTab == "SETTINGS")

    if isCatalogTab then
        self:RebuildFilteredTitles()
        self:RefreshListRows()
    elseif ui.currentTab == "AUTOTITLE" then
        self:RefreshAutoTitlePanel()
    elseif ui.currentTab == "SETTINGS" then
        self:RefreshSettingsPanel()
    end

    self:RefreshInspector()
end

-- ============================================================================
-- ПОСТРОЕНИЕ ГЛАВНОГО ОКНА TITLECOLLECTOR
-- ============================================================================
function addon:EnsureMainWindow()
    if ui.mainFrame then return ui.mainFrame end

    local f = CreateFrame("Frame", "TitleCollectorMainFrame", UIParent, "BackdropTemplate")
    f:SetSize(980, 620)
    f:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    ApplyBackdrop(f, 0.05, 0.05, 0.06, 0.97, 0.72, 0.58, 0.16, 1.0)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        local found = false
        for _, fn in ipairs(UISpecialFrames) do
            if fn == "TitleCollectorMainFrame" then found = true; break end
        end
        if not found then
            tinsert(UISpecialFrames, "TitleCollectorMainFrame")
        end
    end
    ui.mainFrame = f

    -- 1. Шапка окна
    local header = CreateFrame("Frame", nil, f, "BackdropTemplate")
    header:SetPoint("TOPLEFT", f, "TOPLEFT", 8, -8)
    header:SetPoint("TOPRIGHT", f, "TOPRIGHT", -8, -8)
    header:SetHeight(46)
    ApplyBackdrop(header, 0.09, 0.08, 0.06, 0.96, 0.35, 0.28, 0.14, 1.0)

    local logoTex = header:CreateTexture(nil, "ARTWORK")
    logoTex:SetSize(32, 32)
    logoTex:SetPoint("LEFT", header, "LEFT", 10, 0)
    logoTex:SetTexture(237537)
    logoTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local titleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titleFS:SetPoint("TOPLEFT", logoTex, "TOPRIGHT", 10, -1)
    titleFS:SetText("|cffffd100Title|r|cff00ccffCollector|r |cff888888v1.0.0|r")

    local subFS = header:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFS:SetPoint("BOTTOMLEFT", logoTex, "BOTTOMRIGHT", 10, 1)
    subFS:SetTextColor(0.80, 0.78, 0.72, 1.0)
    subFS:SetText(self:L("ADDON_SUBTITLE"))
    f.subFS = subFS

    local activeTitleFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    activeTitleFS:SetPoint("TOP", header, "TOP", 40, -8)
    f.activeTitleFS = activeTitleFS

    local progressFS = header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    progressFS:SetPoint("BOTTOM", header, "BOTTOM", 40, 7)
    progressFS:SetTextColor(1.0, 0.86, 0.25, 1.0)
    f.progressFS = progressFS

    local closeBtn = CreateCollectorButton(header, 26, 26, "X", false)
    closeBtn:SetPoint("RIGHT", header, "RIGHT", -8, 0)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    local langBtn = CreateCollectorButton(header, 46, 26, self:IsEnglish() and "EN" or "RU", false)
    langBtn:SetPoint("RIGHT", closeBtn, "LEFT", -6, 0)
    langBtn:SetScript("OnClick", function(selfBtn)
        addon.db.settings.language = addon:IsEnglish() and "ruRU" or "enUS"
        selfBtn:SetText(addon:IsEnglish() and "EN" or "RU")
        addon:ApplyLocaleToStaticUI()
        addon:RefreshUI()
    end)
    f.langBtn = langBtn

    -- 2. Ряд вкладок
    local tabBar = CreateFrame("Frame", nil, f)
    tabBar:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -6)
    tabBar:SetSize(536, 28)

    local tabDefs = {
        { id = "ALMOST",    key = "TAB_ALMOST",    w = 94 },
        { id = "ZONE",      key = "TAB_ZONE",      w = 104 },
        { id = "ALL",       key = "TAB_ALL",       w = 84 },
        { id = "COLLECTED", key = "TAB_COLLECTED", w = 82 },
        { id = "AUTOTITLE", key = "TAB_AUTOTITLE", w = 86 },
        { id = "SETTINGS",  key = "TAB_SETTINGS",  w = 76 },
    }
    local prevTab = nil
    for _, td in ipairs(tabDefs) do
        local tb = CreateCollectorButton(tabBar, td.w, 26, self:L(td.key), false)
        if not prevTab then
            tb:SetPoint("LEFT", tabBar, "LEFT", 0, 0)
        else
            tb:SetPoint("LEFT", prevTab, "RIGHT", 4, 0)
        end
        tb:SetScript("OnClick", function()
            HideCollectorDropdown()
            ui.currentTab = td.id
            ui.scrollOffset = 0
            if td.id == "COLLECTED" then
                ui.sortBy = "RARITY"
                if ui.sortBtn then ui.sortBtn:SetText(addon:L("SORT_RARITY")) end
                ui.selectedTitle = nil
            elseif td.id == "ALMOST" then
                ui.sortBy = "PROGRESS"
                if ui.sortBtn then ui.sortBtn:SetText(addon:L("SORT_PROGRESS")) end
                ui.selectedTitle = nil
            end
            addon:RefreshUI()
        end)
        ui.tabButtons[td.id] = tb
        prevTab = tb
    end
    f:HookScript("OnHide", HideCollectorDropdown)

    -- 3. Левый контейнер каталога (фильтры + список)
    local catCont = CreateFrame("Frame", nil, f, "BackdropTemplate")
    catCont:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    catCont:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    catCont:SetWidth(536)
    ApplyBackdrop(catCont, 0.06, 0.06, 0.08, 0.96, 0.24, 0.24, 0.28, 1.0)
    ui.catalogContainer = catCont

    -- Поиск
    local searchBox = CreateFrame("EditBox", nil, catCont, "BackdropTemplate")
    searchBox:SetSize(250, 24)
    searchBox:SetPoint("TOPLEFT", catCont, "TOPLEFT", 8, -8)
    searchBox:SetAutoFocus(false)
    searchBox:SetFontObject("GameFontHighlightSmall")
    searchBox:SetTextInsets(8, 20, 0, 0)
    ApplyBackdrop(searchBox, 0.04, 0.04, 0.05, 0.98, 0.30, 0.30, 0.35, 1.0)
    searchBox:SetScript("OnEscapePressed", function(eb) eb:ClearFocus() end)
    searchBox:SetScript("OnEnterPressed", function(eb) eb:ClearFocus() end)
    searchBox:SetScript("OnTextChanged", function(eb, userInput)
        if userInput then
            ui.searchText = eb:GetText() or ""
            ui.scrollOffset = 0
            addon:RefreshUI()
        end
    end)
    ui.searchBox = searchBox

    -- Кнопка-выпадашка Дополнения (ЛКМ — выпадающее меню, ПКМ — сброс на Все дополнения)
    local expBtn = CreateCollectorButton(catCont, 130, 24, self:L("FILTER_EXP_ALL"), false)
    expBtn:SetPoint("LEFT", searchBox, "RIGHT", 6, 0)
    expBtn:SetScript("OnClick", function(selfBtn, button)
        if button == "RightButton" then
            HideCollectorDropdown()
            ui.filterExp = 0
            selfBtn:SetText(addon:L("FILTER_EXP_ALL"))
            ui.scrollOffset = 0
            addon:RefreshUI()
            return
        end
        local items = {
            {
                text = addon:L("FILTER_EXP_ALL"),
                checked = (ui.filterExp == 0),
                func = function()
                    ui.filterExp = 0
                    selfBtn:SetText(addon:L("FILTER_EXP_ALL"))
                    ui.scrollOffset = 0
                    addon:RefreshUI()
                end,
            },
        }
        for expID = 12, 1, -1 do
            local eInfo = addon.ExpansionNames[expID]
            if eInfo then
                local eName = addon:IsEnglish() and eInfo.en or eInfo.ru
                table.insert(items, {
                    text = (eInfo.color or "|cffffffff") .. eName .. "|r",
                    checked = (ui.filterExp == expID),
                    func = function()
                        ui.filterExp = expID
                        selfBtn:SetText(eName)
                        ui.scrollOffset = 0
                        addon:RefreshUI()
                    end,
                })
            end
        end
        ToggleCollectorDropdown(selfBtn, items, 200)
    end)
    ui.expBtn = expBtn

    -- Кнопка-выпадашка Сложности
    local diffOrder = { "ALL", "SOLO_FAST", "SOLO_RAID", "SOLO_GRIND", "GROUP", "PVP", "LEGACY" }
    local diffBtn = CreateCollectorButton(catCont, 130, 24, self:L("FILTER_DIFF_ALL"), false)
    diffBtn:SetPoint("LEFT", expBtn, "RIGHT", 6, 0)
    diffBtn:SetScript("OnClick", function(selfBtn, button)
        if button == "RightButton" then
            HideCollectorDropdown()
            ui.filterDiff = "ALL"
            selfBtn:SetText(addon:L("FILTER_DIFF_ALL"))
            ui.scrollOffset = 0
            addon:RefreshUI()
            return
        end
        local items = {}
        for _, k in ipairs(diffOrder) do
            local dm = DIFF_META[k]
            local lbl = (k == "ALL") and addon:L("FILTER_DIFF_ALL") or ((dm and dm.color or "") .. addon:L(dm.key) .. "|r")
            local plainLbl = (k == "ALL") and addon:L("FILTER_DIFF_ALL") or (dm and addon:L(dm.key) or k)
            table.insert(items, {
                text = lbl,
                checked = (ui.filterDiff == k),
                func = function()
                    ui.filterDiff = k
                    selfBtn:SetText(plainLbl)
                    ui.scrollOffset = 0
                    addon:RefreshUI()
                end,
            })
        end
        ToggleCollectorDropdown(selfBtn, items, 190)
    end)
    ui.diffBtn = diffBtn

    -- Вторая строка мини-фильтров (Категория, Префикс/Суффикс, Сортировка, Избранные)
    local catOrder = { "ALL", "ACHIEVEMENT", "RAID", "DUNGEON", "REPUTATION", "QUEST", "EXPLORATION", "PVP", "HOLIDAY", "PROFESSION" }
    local catBtn = CreateCollectorButton(catCont, 145, 22, self:L("FILTER_CAT_ALL"), false)
    catBtn:SetPoint("TOPLEFT", searchBox, "BOTTOMLEFT", 0, -5)
    catBtn:SetScript("OnClick", function(selfBtn, button)
        if button == "RightButton" then
            HideCollectorDropdown()
            ui.filterCat = "ALL"
            selfBtn:SetText(addon:L("FILTER_CAT_ALL"))
            ui.scrollOffset = 0
            addon:RefreshUI()
            return
        end
        local items = {}
        for _, k in ipairs(catOrder) do
            local lbl = (k == "ALL") and addon:L("FILTER_CAT_ALL") or addon:L("CAT_" .. k)
            table.insert(items, {
                text = lbl,
                checked = (ui.filterCat == k),
                func = function()
                    ui.filterCat = k
                    selfBtn:SetText(lbl)
                    ui.scrollOffset = 0
                    addon:RefreshUI()
                end,
            })
        end
        ToggleCollectorDropdown(selfBtn, items, 175)
    end)
    ui.catBtn = catBtn

    local affixOrder = { "ALL", "PREFIX", "SUFFIX" }
    local affixBtn = CreateCollectorButton(catCont, 135, 22, self:L("FILTER_AFFIX_ALL"), false)
    affixBtn:SetPoint("LEFT", catBtn, "RIGHT", 6, 0)
    affixBtn:SetScript("OnClick", function(selfBtn, button)
        if button == "RightButton" then
            HideCollectorDropdown()
            ui.filterAffix = "ALL"
            selfBtn:SetText(addon:L("FILTER_AFFIX_ALL"))
            ui.scrollOffset = 0
            addon:RefreshUI()
            return
        end
        local items = {}
        for _, k in ipairs(affixOrder) do
            local lbl = addon:L("FILTER_AFFIX_" .. k)
            table.insert(items, {
                text = lbl,
                checked = (ui.filterAffix == k),
                func = function()
                    ui.filterAffix = k
                    selfBtn:SetText(lbl)
                    ui.scrollOffset = 0
                    addon:RefreshUI()
                end,
            })
        end
        ToggleCollectorDropdown(selfBtn, items, 175)
    end)
    ui.affixBtn = affixBtn

    local sortOrder = { "PROGRESS", "RARITY", "NAME", "EXP" }
    local sortBtn = CreateCollectorButton(catCont, 125, 22, self:L("SORT_PROGRESS"), false)
    sortBtn:SetPoint("LEFT", affixBtn, "RIGHT", 6, 0)
    sortBtn:SetScript("OnClick", function(selfBtn)
        local items = {}
        for _, k in ipairs(sortOrder) do
            local lbl = addon:L("SORT_" .. k)
            table.insert(items, {
                text = lbl,
                checked = (ui.sortBy == k),
                func = function()
                    ui.sortBy = k
                    selfBtn:SetText(lbl)
                    ui.scrollOffset = 0
                    addon:RefreshUI()
                end,
            })
        end
        ToggleCollectorDropdown(selfBtn, items, 165)
    end)
    ui.sortBtn = sortBtn

    local favFilterBtn = CreateCollectorButton(catCont, 96, 22, self:L("FILTER_ONLY_FAV"), false)
    favFilterBtn:SetPoint("LEFT", sortBtn, "RIGHT", 6, 0)
    favFilterBtn:SetScript("OnClick", function(selfBtn)
        ui.onlyFavorites = not ui.onlyFavorites
        selfBtn:SetActiveTab(ui.onlyFavorites)
        ui.scrollOffset = 0
        addon:RefreshUI()
    end)
    ui.favFilterBtn = favFilterBtn

    -- Скролл-область строк званий
    local listFrame = CreateFrame("Frame", nil, catCont)
    listFrame:SetPoint("TOPLEFT", catBtn, "BOTTOMLEFT", 0, -8)
    listFrame:SetPoint("BOTTOMRIGHT", catCont, "BOTTOMRIGHT", -24, 8)
    listFrame:EnableMouseWheel(true)
    listFrame:SetScript("OnMouseWheel", function(_, delta)
        ui.scrollOffset = ui.scrollOffset - delta * 3
        addon:RefreshListRows()
    end)

    local scrollBar = CreateFrame("Slider", nil, catCont, "UIPanelScrollBarTemplate")
    scrollBar:SetPoint("TOPLEFT", listFrame, "TOPRIGHT", 2, -16)
    scrollBar:SetPoint("BOTTOMLEFT", listFrame, "BOTTOMRIGHT", 2, 16)
    scrollBar:SetMinMaxValues(0, 1)
    scrollBar:SetValueStep(1)
    scrollBar:SetObeyStepOnDrag(true)
    scrollBar:SetScript("OnValueChanged", function(_, val)
        local rounded = math.floor(val + 0.5)
        if rounded ~= ui.scrollOffset then
            ui.scrollOffset = rounded
            addon:RefreshListRows()
        end
    end)
    ui.scrollBar = scrollBar

    for i = 1, VISIBLE_ROWS do
        local row = CreateFrame("Button", nil, listFrame, "BackdropTemplate")
        row:SetHeight(ROW_HEIGHT - 2)
        row:SetPoint("TOPLEFT", listFrame, "TOPLEFT", 0, -(i - 1) * ROW_HEIGHT)
        row:SetPoint("TOPRIGHT", listFrame, "TOPRIGHT", 0, -(i - 1) * ROW_HEIGHT)
        row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        ApplyBackdrop(row, 0.09, 0.09, 0.11, 0.92, 0.20, 0.20, 0.24, 1.0)

        local favBtn = CreateFrame("Button", nil, row)
        favBtn:SetSize(20, 20)
        favBtn:SetPoint("LEFT", row, "LEFT", 6, 0)
        local favTex = favBtn:CreateTexture(nil, "ARTWORK")
        favTex:SetAllPoints()
        favTex:SetTexture("Interface\\COMMON\\ReputationStar")
        favTex:SetTexCoord(0, 0.5, 0, 0.5)
        favBtn.tex = favTex
        favBtn:SetScript("OnClick", function()
            if row.title then addon:ToggleTitleFavorite(row.title.maskID) end
        end)
        row.favBtn = favBtn

        local iconTex = row:CreateTexture(nil, "ARTWORK")
        iconTex:SetSize(26, 26)
        iconTex:SetPoint("LEFT", favBtn, "RIGHT", 4, 0)
        iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.iconTex = iconTex

        local progBar = CreateFrame("StatusBar", nil, row, "BackdropTemplate")
        progBar:SetSize(92, 16)
        progBar:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        progBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
        progBar:SetMinMaxValues(0, 100)
        ApplyBackdrop(progBar, 0.04, 0.04, 0.05, 0.95, 0.25, 0.25, 0.30, 1.0)
        row.progBar = progBar

        local progFS = progBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        progFS:SetPoint("CENTER", progBar, "CENTER", 0, 0)
        row.progFS = progFS

        local nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameFS:SetPoint("TOPLEFT", iconTex, "TOPRIGHT", 8, -1)
        nameFS:SetPoint("RIGHT", progBar, "LEFT", -8, 0)
        nameFS:SetJustifyH("LEFT")
        nameFS:SetWordWrap(false)
        row.nameFS = nameFS

        local subFS_row = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        subFS_row:SetPoint("BOTTOMLEFT", iconTex, "BOTTOMRIGHT", 8, 1)
        subFS_row:SetPoint("RIGHT", progBar, "LEFT", -8, 0)
        subFS_row:SetJustifyH("LEFT")
        subFS_row:SetWordWrap(false)
        row.subFS = subFS_row

        row:SetScript("OnClick", function(selfRow, button)
            if not selfRow.title then return end
            ui.selectedTitle = selfRow.title
            ui.critScrollOffset = 0
            if button == "RightButton" and addon:IsTitleCollected(selfRow.title.maskID) then
                addon:EquipTitle(selfRow.title.maskID, false)
            end
            addon:RefreshListRows()
            addon:RefreshInspector()
        end)

        ui.rows[i] = row
    end

    local emptyListFS = listFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    emptyListFS:SetPoint("CENTER", listFrame, "CENTER", 0, 10)
    emptyListFS:SetWidth(440)
    emptyListFS:SetJustifyH("CENTER")
    emptyListFS:SetTextColor(0.65, 0.65, 0.70, 1.0)
    ui.emptyListFS = emptyListFS

    -- 4. Панель Авто-титулов (Вкладка AUTOTITLE)
    local autoPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    autoPanel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    autoPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    autoPanel:SetWidth(536)
    ApplyBackdrop(autoPanel, 0.06, 0.06, 0.08, 0.96, 0.24, 0.24, 0.28, 1.0)
    autoPanel:Hide()
    ui.autoPanel = autoPanel

    local autoHeader = autoPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    autoHeader:SetPoint("TOPLEFT", autoPanel, "TOPLEFT", 14, -14)
    autoHeader:SetTextColor(1.0, 0.85, 0.20, 1.0)
    autoHeader:SetText(self:L("AUTO_HEADER_TITLE"))
    autoPanel.autoHeader = autoHeader

    local masterCB = CreateFrame("CheckButton", nil, autoPanel, "UICheckButtonTemplate")
    masterCB:SetSize(26, 26)
    masterCB:SetPoint("TOPLEFT", autoHeader, "BOTTOMLEFT", -2, -10)
    masterCB.text:SetFontObject("GameFontNormal")
    masterCB.text:SetTextColor(0.20, 1.0, 0.60, 1.0)
    masterCB.text:SetText(self:L("AUTO_MASTER_ENABLE"))
    masterCB:SetScript("OnClick", function(cb)
        addon.db.settings.enableAutoTitle = cb:GetChecked() == true
        if addon.db.settings.enableAutoTitle then
            addon:EvaluateAutoTitleRules("MANUAL")
        end
    end)
    autoPanel.masterCB = masterCB

    local masterDesc = autoPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    masterDesc:SetPoint("TOPLEFT", masterCB, "BOTTOMLEFT", 4, -2)
    masterDesc:SetTextColor(0.75, 0.75, 0.80, 1.0)
    masterDesc:SetText(self:L("AUTO_MASTER_DESC"))
    autoPanel.masterDesc = masterDesc

    local function CreateAutoRuleRow(parent, yOffset, key, iconPath, labelText, applyCallback)
        local r = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        r:SetSize(508, 42)
        r:SetPoint("TOPLEFT", parent, "TOPLEFT", 14, yOffset)
        ApplyBackdrop(r, 0.10, 0.10, 0.12, 0.94, 0.22, 0.22, 0.26, 1.0)

        local ic = r:CreateTexture(nil, "ARTWORK")
        ic:SetSize(26, 26)
        ic:SetPoint("LEFT", r, "LEFT", 8, 0)
        ic:SetTexture(iconPath or 134400)
        ic:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        r.iconTex = ic

        local lbl = r:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        lbl:SetPoint("TOPLEFT", ic, "TOPRIGHT", 8, -1)
        lbl:SetTextColor(1.0, 0.86, 0.30, 1.0)
        lbl:SetText(labelText or "")
        r.labelFS = lbl

        local val = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        val:SetPoint("BOTTOMLEFT", ic, "BOTTOMRIGHT", 8, 1)
        val:SetWidth(210)
        val:SetJustifyH("LEFT")
        val:SetWordWrap(false)
        r.valFS = val

        local clrBtn = CreateCollectorButton(r, 72, 24, addon:L("AUTO_BTN_CLEAR"), false)
        clrBtn:SetPoint("RIGHT", r, "RIGHT", -6, 0)
        clrBtn:SetScript("OnClick", function() applyCallback(nil) end)

        local favBtn = CreateCollectorButton(r, 64, 24, addon:L("AUTO_BTN_ASSIGN_FAV_RND"), false)
        favBtn:SetPoint("RIGHT", clrBtn, "LEFT", -4, 0)
        favBtn:SetScript("OnClick", function() applyCallback("FAV") end)

        local setBtn = CreateCollectorButton(r, 110, 24, addon:L("AUTO_BTN_ASSIGN_SELECTED"), true)
        setBtn:SetPoint("RIGHT", favBtn, "LEFT", -4, 0)
        setBtn:SetScript("OnClick", function()
            if ui.selectedTitle then
                applyCallback(ui.selectedTitle.maskID)
            end
        end)

        ui.autoRuleRows[key] = r
        return r
    end

    for i = 1, 4 do
        CreateAutoRuleRow(autoPanel, -95 - (i - 1) * 46, "SPEC_" .. i, 134400, "Spec " .. i, function(val)
            local rules = addon:GetCharAutoRules()
            rules.specs[i] = val
            addon:RefreshAutoTitlePanel()
            addon:EvaluateAutoTitleRules("MANUAL")
        end)
    end

    local ctxDefs = {
        { key = "PVP",  icon = 236396, lblKey = "AUTO_CTX_PVP" },
        { key = "RAID", icon = 133074, lblKey = "AUTO_CTX_RAID" },
        { key = "CITY", icon = 134414, lblKey = "AUTO_CTX_CITY" },
    }
    for idx, cd in ipairs(ctxDefs) do
        CreateAutoRuleRow(autoPanel, -295 - (idx - 1) * 46, "CTX_" .. cd.key, cd.icon, self:L(cd.lblKey), function(val)
            local rules = addon:GetCharAutoRules()
            rules.contexts[cd.key] = val
            addon:RefreshAutoTitlePanel()
            addon:EvaluateAutoTitleRules("MANUAL")
        end)
    end

    local rollNowBtn = CreateCollectorButton(autoPanel, 280, 30, self:L("AUTO_BTN_ROLL_FAV_NOW"), true)
    rollNowBtn:SetPoint("BOTTOM", autoPanel, "BOTTOM", 0, 16)
    rollNowBtn:SetScript("OnClick", function()
        addon:EquipRandomFavorite(false)
    end)
    autoPanel.rollNowBtn = rollNowBtn

    -- 5. Панель Настроек (Вкладка SETTINGS)
    local setPanel = CreateFrame("Frame", nil, f, "BackdropTemplate")
    setPanel:SetPoint("TOPLEFT", tabBar, "BOTTOMLEFT", 0, -6)
    setPanel:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", 8, 8)
    setPanel:SetWidth(536)
    ApplyBackdrop(setPanel, 0.06, 0.06, 0.08, 0.96, 0.24, 0.24, 0.28, 1.0)
    setPanel:Hide()
    setPanel.checkboxes = {}
    ui.settingsPanel = setPanel

    local setHeader = setPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    setHeader:SetPoint("TOPLEFT", setPanel, "TOPLEFT", 16, -16)
    setHeader:SetTextColor(1.0, 0.85, 0.20, 1.0)
    setHeader:SetText(self:L("SET_HEADER"))

    local setOptions = {
        { key = "hideUnobtainable",  lbl = "SET_HIDE_UNOBTAINABLE" },
        { key = "hideOppositeFaction", lbl = "SET_HIDE_OPPOSITE_FAC" },
        { key = "enableAutoTitle",   lbl = "SET_ENABLE_AUTO_TITLE" },
        { key = "showGlobalRarity",  lbl = "SET_SHOW_GLOBAL_RARITY" },
        { key = "showServerRarity",  lbl = "SET_SHOW_SERVER_RARITY" },
        { key = "scanRealmTitles",   lbl = "SET_SCAN_REALM_CENSUS" },
        { key = "showPlayerTooltips", lbl = "SET_SHOW_PLAYER_TT" },
        { key = "showProgressToast", lbl = "SET_SHOW_PROG_TOAST" },
        { key = "showMinimap",       lbl = "SET_SHOW_MINIMAP" },
        { key = "showCharPaneButton", lbl = "SET_SHOW_CHAR_BTN" },
    }
    for idx, opt in ipairs(setOptions) do
        local cb = CreateFrame("CheckButton", nil, setPanel, "UICheckButtonTemplate")
        cb:SetSize(26, 26)
        cb:SetPoint("TOPLEFT", setPanel, "TOPLEFT", 16, -46 - (idx - 1) * 32)
        cb.text:SetFontObject("GameFontNormal")
        cb.text:SetText(self:L(opt.lbl))
        cb.lblKey = opt.lbl
        cb:SetScript("OnClick", function(selfCB)
            local checked = selfCB:GetChecked() == true
            if opt.key == "showMinimap" then
                addon.db.minimap.hide = not checked
                addon:SetupRoundMinimapButton()
            else
                addon.db.settings[opt.key] = checked
            end
            addon:RefreshUI()
        end)
        setPanel.checkboxes[opt.key] = cb
    end

    -- 6. Правая панель — Инспектор выбранного звания
    local insp = CreateFrame("Frame", nil, f, "BackdropTemplate")
    insp:SetPoint("TOPLEFT", catCont, "TOPRIGHT", 8, 28)
    insp:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -8, 8)
    ApplyBackdrop(insp, 0.07, 0.07, 0.09, 0.96, 0.30, 0.26, 0.16, 1.0)
    ui.inspector = insp

    local inspIcon = insp:CreateTexture(nil, "ARTWORK")
    inspIcon:SetSize(38, 38)
    inspIcon:SetPoint("TOPLEFT", insp, "TOPLEFT", 12, -12)
    inspIcon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    insp.iconTex = inspIcon

    local inspTitle = insp:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    inspTitle:SetPoint("TOPLEFT", inspIcon, "TOPRIGHT", 10, -1)
    inspTitle:SetPoint("RIGHT", insp, "RIGHT", -12, 0)
    inspTitle:SetJustifyH("LEFT")
    inspTitle:SetWordWrap(false)
    insp.titleFS = inspTitle

    local inspSubMeta = insp:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    inspSubMeta:SetPoint("BOTTOMLEFT", inspIcon, "BOTTOMRIGHT", 10, 2)
    inspSubMeta:SetPoint("RIGHT", insp, "RIGHT", -12, 0)
    inspSubMeta:SetJustifyH("LEFT")
    insp.subMetaFS = inspSubMeta

    -- Подиум живого превью над персонажем + кнопки М/Ж
    local prevBox = CreateFrame("Frame", nil, insp, "BackdropTemplate")
    prevBox:SetPoint("TOPLEFT", inspIcon, "BOTTOMLEFT", 0, -10)
    prevBox:SetPoint("TOPRIGHT", insp, "TOPRIGHT", -12, 0)
    prevBox:SetHeight(52)
    ApplyBackdrop(prevBox, 0.04, 0.04, 0.05, 0.95, 0.28, 0.24, 0.14, 1.0)

    local prevLbl = prevBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    prevLbl:SetPoint("TOPLEFT", prevBox, "TOPLEFT", 8, -6)
    prevLbl:SetTextColor(0.75, 0.75, 0.80, 1.0)
    prevLbl:SetText(self:L("INSP_PREVIEW_LABEL"))
    insp.prevLbl = prevLbl

    local genderFBtn = CreateCollectorButton(prevBox, 48, 18, self:L("INSP_GENDER_F"), false)
    genderFBtn:SetPoint("TOPRIGHT", prevBox, "TOPRIGHT", -6, -4)
    genderFBtn:SetScript("OnClick", function()
        ui.previewFemale = true
        addon:RefreshInspector()
    end)
    insp.genderFBtn = genderFBtn

    local genderMBtn = CreateCollectorButton(prevBox, 48, 18, self:L("INSP_GENDER_M"), false)
    genderMBtn:SetPoint("RIGHT", genderFBtn, "LEFT", -4, 0)
    genderMBtn:SetScript("OnClick", function()
        ui.previewFemale = false
        addon:RefreshInspector()
    end)
    insp.genderMBtn = genderMBtn

    local previewFS = prevBox:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    previewFS:SetPoint("BOTTOM", prevBox, "BOTTOM", 0, 8)
    previewFS:SetWidth(380)
    previewFS:SetJustifyH("CENTER")
    previewFS:SetWordWrap(false)
    insp.previewFS = previewFS

    -- Кнопки Надеть звание и В трекер целей
    local equipBtn = CreateCollectorButton(insp, 194, 26, self:L("INSP_BTN_EQUIP"), true)
    equipBtn:SetPoint("TOPLEFT", prevBox, "BOTTOMLEFT", 0, -8)
    equipBtn:SetScript("OnClick", function()
        if not ui.selectedTitle then return end
        local curMask = (_G.GetCurrentTitle and GetCurrentTitle()) or -1
        if curMask == ui.selectedTitle.maskID then
            addon:EquipTitle(0, false)
        else
            addon:EquipTitle(ui.selectedTitle.maskID, false)
        end
    end)
    insp.equipBtn = equipBtn

    local trackBtn = CreateCollectorButton(insp, 194, 26, self:L("INSP_BTN_TRACK"), false)
    trackBtn:SetPoint("TOPRIGHT", prevBox, "BOTTOMRIGHT", 0, -8)
    trackBtn:SetScript("OnClick", function()
        if not ui.selectedTitle then return end
        addon:ToggleTrackTitleAchievement(ui.selectedTitle)
        addon:RefreshInspector()
    end)
    insp.trackBtn = trackBtn

    -- Двойной блок редкости (Глобальная по миру + По серверу, как в MountCollector)
    local rarityBox = CreateFrame("Frame", nil, insp, "BackdropTemplate")
    rarityBox:SetPoint("TOPLEFT", equipBtn, "BOTTOMLEFT", 0, -8)
    rarityBox:SetPoint("TOPRIGHT", trackBtn, "BOTTOMRIGHT", 0, -8)
    rarityBox:SetHeight(44)
    ApplyBackdrop(rarityBox, 0.05, 0.05, 0.07, 0.94, 0.22, 0.22, 0.28, 1.0)

    local rgLbl = rarityBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rgLbl:SetPoint("TOPLEFT", rarityBox, "TOPLEFT", 8, -6)
    rgLbl:SetText(self:L("RARITY_GLOBAL_LABEL"))
    insp.rarityGlobalLbl = rgLbl

    local rgVal = rarityBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rgVal:SetPoint("TOPRIGHT", rarityBox, "TOPRIGHT", -8, -6)
    insp.rarityGlobalVal = rgVal

    local rsLbl = rarityBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rsLbl:SetPoint("BOTTOMLEFT", rarityBox, "BOTTOMLEFT", 8, 6)
    insp.rarityServerLbl = rsLbl

    local rsVal = rarityBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rsVal:SetPoint("BOTTOMRIGHT", rarityBox, "BOTTOMRIGHT", -8, 6)
    insp.rarityServerVal = rsVal

    -- Полоса прогресса и чек-лист критериев
    local progHeader = insp:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    progHeader:SetPoint("TOPLEFT", rarityBox, "BOTTOMLEFT", 0, -8)
    progHeader:SetTextColor(1.0, 0.85, 0.25, 1.0)
    progHeader:SetText(self:L("INSP_PROGRESS_HEADER"))
    insp.progHeader = progHeader

    local onlyMissCB = CreateFrame("CheckButton", nil, insp, "UICheckButtonTemplate")
    onlyMissCB:SetSize(20, 20)
    onlyMissCB:SetPoint("TOPRIGHT", rarityBox, "BOTTOMRIGHT", -150, -4)
    onlyMissCB.text:SetFontObject("GameFontHighlightSmall")
    onlyMissCB.text:SetText(self:L("INSP_ONLY_MISSING_CRIT"))
    onlyMissCB:SetChecked(self.db.settings.onlyMissingCriteria == true)
    onlyMissCB:SetScript("OnClick", function(cb)
        addon.db.settings.onlyMissingCriteria = cb:GetChecked() == true
        addon:RefreshInspector()
    end)
    insp.onlyMissCB = onlyMissCB

    local progBar = CreateFrame("StatusBar", nil, insp, "BackdropTemplate")
    progBar:SetPoint("TOPLEFT", progHeader, "BOTTOMLEFT", 0, -6)
    progBar:SetPoint("TOPRIGHT", rarityBox, "BOTTOMRIGHT", 0, -24)
    progBar:SetHeight(16)
    progBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
    progBar:SetMinMaxValues(0, 100)
    ApplyBackdrop(progBar, 0.03, 0.03, 0.04, 0.96, 0.25, 0.25, 0.30, 1.0)
    insp.progBar = progBar

    local progText = progBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    progText:SetPoint("CENTER", progBar, "CENTER", 0, 0)
    insp.progText = progText

    local critBox = CreateFrame("Frame", nil, insp, "BackdropTemplate")
    critBox:SetPoint("TOPLEFT", progBar, "BOTTOMLEFT", 0, -6)
    critBox:SetPoint("TOPRIGHT", progBar, "BOTTOMRIGHT", 0, -6)
    critBox:SetHeight(158)
    ApplyBackdrop(critBox, 0.04, 0.04, 0.05, 0.95, 0.20, 0.20, 0.24, 1.0)
    critBox:EnableMouseWheel(true)
    local function OnCritWheel(_, delta)
        local tot = insp.totalCritCount or 0
        local maxOff = math.max(0, tot - 8)
        ui.critScrollOffset = math.max(0, math.min((ui.critScrollOffset or 0) - delta * 2, maxOff))
        addon:RefreshInspector()
    end
    critBox:SetScript("OnMouseWheel", OnCritWheel)

    for i = 1, 8 do
        local cRow = CreateFrame("Button", nil, critBox)
        cRow:SetHeight(18)
        cRow:SetPoint("TOPLEFT", critBox, "TOPLEFT", 6, -4 - (i - 1) * 19)
        cRow:SetPoint("TOPRIGHT", critBox, "TOPRIGHT", -6, -4 - (i - 1) * 19)
        cRow:EnableMouseWheel(true)
        cRow:SetScript("OnMouseWheel", OnCritWheel)
        local cFS = cRow:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        cFS:SetAllPoints()
        cFS:SetJustifyH("LEFT")
        cFS:SetWordWrap(false)
        cRow.textFS = cFS
        cRow:SetScript("OnClick", function(selfCR)
            if selfCR.item and selfCR.item.subAchID then
                addon:OpenTitleAchievement(ui.selectedTitle, selfCR.item.subAchID)
            elseif ui.selectedTitle and ui.selectedTitle.achID then
                addon:OpenTitleAchievement(ui.selectedTitle)
            end
        end)
        ui.critRows[i] = cRow
    end

    local emptyCritFS = critBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    emptyCritFS:SetPoint("CENTER", critBox, "CENTER", 0, 0)
    emptyCritFS:SetWidth(360)
    emptyCritFS:SetJustifyH("CENTER")
    emptyCritFS:SetTextColor(0.65, 0.75, 0.68, 1.0)
    insp.emptyCritFS = emptyCritFS

    -- Блок «Как получить» + Кнопки навигации внизу
    local howBox = CreateFrame("Frame", nil, insp, "BackdropTemplate")
    howBox:SetPoint("TOPLEFT", critBox, "BOTTOMLEFT", 0, -6)
    howBox:SetPoint("BOTTOMRIGHT", insp, "BOTTOMRIGHT", -12, 42)
    ApplyBackdrop(howBox, 0.05, 0.05, 0.06, 0.94, 0.20, 0.20, 0.24, 1.0)

    local howToFS = howBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    howToFS:SetPoint("TOPLEFT", howBox, "TOPLEFT", 8, -8)
    howToFS:SetPoint("BOTTOMRIGHT", howBox, "BOTTOMRIGHT", -8, 8)
    howToFS:SetJustifyH("LEFT")
    howToFS:SetJustifyV("TOP")
    howToFS:SetWordWrap(true)
    insp.howToFS = howToFS

    local waypointBtn = CreateCollectorButton(insp, 200, 26, self:L("INSP_BTN_WAYPOINT"), true)
    waypointBtn:SetPoint("BOTTOMLEFT", insp, "BOTTOMLEFT", 12, 10)
    waypointBtn:SetScript("OnClick", function()
        if ui.selectedTitle then addon:NavigateToTitle(ui.selectedTitle, false) end
    end)
    insp.waypointBtn = waypointBtn

    local openAchBtn = CreateCollectorButton(insp, 118, 26, self:L("INSP_BTN_OPEN_ACH"), false)
    openAchBtn:SetPoint("LEFT", waypointBtn, "RIGHT", 4, 0)
    openAchBtn:SetScript("OnClick", function()
        if ui.selectedTitle then addon:OpenTitleAchievement(ui.selectedTitle) end
    end)
    insp.openAchBtn = openAchBtn

    local whBtn = CreateCollectorButton(insp, 72, 26, "Wowhead", false)
    whBtn:SetPoint("LEFT", openAchBtn, "RIGHT", 4, 0)
    whBtn:SetScript("OnClick", function()
        if ui.selectedTitle then addon:ShowWowheadCopyPopup(ui.selectedTitle) end
    end)
    insp.whBtn = whBtn

    return f
end

function addon:ApplyLocaleToStaticUI()
    if not ui.mainFrame then return end
    ui.mainFrame.subFS:SetText(self:L("ADDON_SUBTITLE"))
    local tabKeys = {
        ALMOST = "TAB_ALMOST", ZONE = "TAB_ZONE", ALL = "TAB_ALL",
        COLLECTED = "TAB_COLLECTED", AUTOTITLE = "TAB_AUTOTITLE", SETTINGS = "TAB_SETTINGS",
    }
    for id, k in pairs(tabKeys) do
        if ui.tabButtons[id] then ui.tabButtons[id]:SetText(self:L(k)) end
    end
end

function addon:ToggleMainWindow()
    local f = self:EnsureMainWindow()
    if f:IsShown() then
        f:Hide()
    else
        f:Show()
        self:RefreshUI()
    end
end

-- ============================================================================
-- КНОПКА В СТАНДАРТНОМ ОКНЕ ЗВАНИЙ ПЕРСОНАЖА (PaperDollTitlesPane)
-- ============================================================================
function addon:HookCharacterTitlesPane()
    if self.charPaneHooked or not _G.PaperDollTitlesPane then return end
    self.charPaneHooked = true

    local btn = CreateCollectorButton(_G.PaperDollTitlesPane, 136, 22, "|cffffd100Title|r|cff00ccffCollector|r", true)
    btn:SetPoint("BOTTOM", _G.PaperDollTitlesPane, "TOP", 0, 4)
    btn:SetFrameLevel((_G.PaperDollTitlesPane:GetFrameLevel() or 10) + 10)
    btn:SetScript("OnClick", function()
        addon:ToggleMainWindow()
    end)
    self.charPaneBtn = btn
end

-- ============================================================================
-- КРУГЛАЯ КНОПКА У МИНИКАРТЫ + LIBDATABROKER
-- ============================================================================
local function PositionRoundMinimapButton(btn, angleDeg)
    local mm = _G.Minimap
    if not btn or not mm then return end
    local rad = math.rad(angleDeg or 212)
    local halfW = (mm:GetWidth() or 140) * 0.5 + 6
    local halfH = (mm:GetHeight() or 140) * 0.5 + 6
    local x = math.cos(rad) * halfW
    local y = math.sin(rad) * halfH

    local isSquare = (_G.GetMinimapShape and _G.GetMinimapShape() == "SQUARE") or (_G.ElvUI and _G.ElvUI[1])
    if isSquare then
        local maxW = (mm:GetWidth() or 140) * 0.5 + 2
        local maxH = (mm:GetHeight() or 140) * 0.5 + 2
        x = math.max(-maxW, math.min(maxW, x * 1.28))
        y = math.max(-maxH, math.min(maxH, y * 1.28))
    end

    btn:ClearAllPoints()
    btn:SetPoint("CENTER", mm, "CENTER", x, y)
end

function addon:SetupRoundMinimapButton()
    local mm = _G.Minimap
    if not mm then return end
    if not self.db then self:InitDB() end

    if not self.roundMinimapBtn then
        local btn = CreateFrame("Button", nil, mm)
        btn:SetSize(32, 32)
        btn:SetFrameStrata("MEDIUM")
        if btn.SetFixedFrameStrata then btn:SetFixedFrameStrata(true) end
        btn:SetFrameLevel(22)
        if btn.SetFixedFrameLevel then btn:SetFixedFrameLevel(true) end
        btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        btn:RegisterForDrag("LeftButton")

        local bg = btn:CreateTexture(nil, "BACKGROUND")
        bg:SetSize(25, 25)
        bg:SetPoint("CENTER", btn, "CENTER", 0, 1)
        bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
        bg:SetVertexColor(0.05, 0.05, 0.06, 0.95)
        btn.bg = bg

        local icon = btn:CreateTexture(nil, "ARTWORK")
        icon:SetSize(20, 20)
        icon:SetPoint("CENTER", btn, "CENTER", 0, 1)
        icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        if btn.CreateMaskTexture and icon.AddMaskTexture then
            local mask = btn:CreateMaskTexture()
            mask:SetTexture("Interface\\CharacterFrame\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
            mask:SetAllPoints(icon)
            icon:AddMaskTexture(mask)
        end
        btn.icon = icon

        local border = btn:CreateTexture(nil, "OVERLAY")
        border:SetSize(54, 54)
        border:SetPoint("TOPLEFT", btn, "TOPLEFT", 0, 0)
        border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
        border:SetVertexColor(1.0, 0.88, 0.55, 1.0)
        btn.border = border

        btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")

        btn:SetScript("OnDragStart", function(selfBtn)
            GameTooltip:Hide()
            selfBtn:SetScript("OnUpdate", function(b)
                local mx, my = mm:GetCenter()
                local cx, cy = GetCursorPosition()
                local scale = mm:GetEffectiveScale() or 1
                if mx and my and cx and cy then
                    local dx = (cx / scale) - mx
                    local dy = (cy / scale) - my
                    local deg = math.deg(math.atan2(dy, dx)) % 360
                    addon.db.minimap.angle = deg
                    PositionRoundMinimapButton(b, deg)
                end
            end)
        end)

        btn:SetScript("OnDragStop", function(selfBtn)
            selfBtn:SetScript("OnUpdate", nil)
        end)

        btn:SetScript("OnClick", function(selfBtn, button)
            if button == "RightButton" and IsShiftKeyDown() then
                local nextIdx = (addon.db.minimap.iconIdx % #MINIMAP_ICONS) + 1
                addon.db.minimap.iconIdx = nextIdx
                local info = MINIMAP_ICONS[nextIdx]
                selfBtn.icon:SetTexture(info.icon)
                if addon.ldbObj then addon.ldbObj.icon = info.icon end
                if GameTooltip:IsOwned(selfBtn) then
                    selfBtn:GetScript("OnEnter")(selfBtn)
                end
            elseif button == "RightButton" then
                addon:EquipRandomFavorite(false)
            else
                addon:ToggleMainWindow()
            end
        end)

        btn:SetScript("OnEnter", function(selfBtn)
            GameTooltip:SetOwner(selfBtn, "ANCHOR_LEFT")
            local col, tot, almostCnt = addon:GetOverallCollectionStats()
            local pct = (tot > 0) and ((col / tot) * 100.0) or 0
            GameTooltip:AddLine("|cffffd100Title|r|cff00ccffCollector|r — " .. addon:L("MINIMAP_TT_SUBTITLE"))
            GameTooltip:AddLine(addon:L("MINIMAP_TT_COLLECTED_FMT", col, tot, pct), 0.92, 0.92, 0.95)
            GameTooltip:AddLine(addon:L("MINIMAP_TT_ALMOST_FMT", almostCnt), 0.92, 0.92, 0.95)
            GameTooltip:AddLine(" ")
            GameTooltip:AddLine(addon:L("MINIMAP_TT_LCLICK"), 0.7, 0.9, 1.0)
            GameTooltip:AddLine(addon:L("MINIMAP_TT_RCLICK"), 0.7, 0.9, 1.0)
            GameTooltip:AddLine(addon:L("MINIMAP_TT_SHIFT_RCLICK"), 0.7, 0.9, 1.0)
            GameTooltip:AddLine(addon:L("MINIMAP_TT_DRAG"), 0.65, 0.65, 0.65)
            GameTooltip:Show()
        end)

        btn:SetScript("OnLeave", function()
            GameTooltip:Hide()
        end)

        self.roundMinimapBtn = btn
    end

    local iconInfo = MINIMAP_ICONS[self.db.minimap.iconIdx] or MINIMAP_ICONS[1]
    self.roundMinimapBtn.icon:SetTexture(iconInfo.icon)
    PositionRoundMinimapButton(self.roundMinimapBtn, self.db.minimap.angle)

    if self.db.minimap.hide then
        self.roundMinimapBtn:Hide()
    else
        self.roundMinimapBtn:Show()
    end
end

function addon:InitLDB()
    self:SetupRoundMinimapButton()
    if not LDB or self.ldbObj then return end
    local iconInfo = (self.db and self.db.minimap and MINIMAP_ICONS[self.db.minimap.iconIdx]) or MINIMAP_ICONS[1]
    self.ldbObj = LDB:NewDataObject("TitleCollector", {
        type = "data source",
        text = "TitleCollector",
        icon = iconInfo.icon,
        OnClick = function(_, button)
            if button == "RightButton" then
                addon:EquipRandomFavorite(false)
            else
                addon:ToggleMainWindow()
            end
        end,
    })
end

-- ============================================================================
-- КАСТОМНЫЙ ПОПАП WOWHEAD (ЗАКРЫТИЕ ПО ESC И ENTER) + ТОСТ ПРОГРЕССА ЗВАНИЯ
-- ============================================================================
function addon:ShowWowheadCopyPopup(title)
    if not title then return end
    local url = self:GetTitleWowheadURL(title)

    if not ui.copyPopup then
        local p = CreateFrame("Frame", "TitleCollectorCopyPopup", UIParent, "BackdropTemplate")
        p:SetSize(420, 96)
        p:SetPoint("CENTER", UIParent, "CENTER", 0, 80)
        p:SetFrameStrata("DIALOG")
        p:SetToplevel(true)
        p:SetMovable(true)
        p:EnableMouse(true)
        p:RegisterForDrag("LeftButton")
        ApplyBackdrop(p, 0.06, 0.06, 0.08, 0.98, 0.88, 0.70, 0.18, 1.0)
        p:SetScript("OnDragStart", p.StartMoving)
        p:SetScript("OnDragStop", p.StopMovingOrSizing)
        p:Hide()

        if type(UISpecialFrames) == "table" then
            local found = false
            for _, fn in ipairs(UISpecialFrames) do
                if fn == "TitleCollectorCopyPopup" then found = true; break end
            end
            if not found then
                tinsert(UISpecialFrames, "TitleCollectorCopyPopup")
            end
        end

        local hdr = p:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        hdr:SetPoint("TOPLEFT", p, "TOPLEFT", 14, -12)
        hdr:SetTextColor(1.0, 0.86, 0.22, 1.0)
        p.hdrFS = hdr

        local closeB = CreateCollectorButton(p, 22, 22, "X", false)
        closeB:SetPoint("TOPRIGHT", p, "TOPRIGHT", -8, -8)
        closeB:SetScript("OnClick", function() p:Hide() end)

        local eb = CreateFrame("EditBox", nil, p, "BackdropTemplate")
        eb:SetSize(392, 26)
        eb:SetPoint("TOPLEFT", hdr, "BOTTOMLEFT", 0, -8)
        eb:SetFontObject("ChatFontNormal")
        eb:SetTextInsets(8, 8, 0, 0)
        eb:SetAutoFocus(true)
        ApplyBackdrop(eb, 0.03, 0.03, 0.04, 0.98, 0.35, 0.35, 0.42, 1.0)
        eb:SetScript("OnEscapePressed", function() p:Hide() end)
        eb:SetScript("OnEnterPressed", function() p:Hide() end)
        p.editBox = eb

        local hint = p:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        hint:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", 14, 10)
        p.hintFS = hint

        ui.copyPopup = p
    end

    local p = ui.copyPopup
    p.hdrFS:SetText(self:L("WOWHEAD_POPUP_TITLE") .. " |cffffffff" .. self:GetTitleCleanName(title) .. "|r")
    p.hintFS:SetText(self:L("WOWHEAD_POPUP_HINT"))
    p:Show()
    p.editBox:SetText(url)
    p.editBox:SetFocus()
    p.editBox:HighlightText()
end

addon.lastKnownPctByMask = {}
addon.lastToastTime = 0
addon.scanWorkerToken = 0
addon.scanDebounceToken = 0
addon.pendingScanMode = nil
addon.pendingCombatScanMode = nil

-- Фоновый кадровый пересчёт прогресса с жёстким бюджетом <= 2.0 мс на кадр (0 фризов в StutterAlert!)
function addon:StartSlicedProgressWorker(mode)
    self.scanWorkerToken = (self.scanWorkerToken or 0) + 1
    local myToken = self.scanWorkerToken
    local total = #self.Titles
    if total == 0 then
        if mode == "BASELINE" then self.baselineReady = true end
        return
    end

    local isBaseline = (mode == "BASELINE") or (not self.baselineReady)
    local wantToast = (not isBaseline) and self.db and self.db.settings and self.db.settings.showProgressToast
    local toastFired = false
    local idx = 1
    local getMs = _G.debugprofilestop

    local function ProcessNextSlice()
        if self.scanWorkerToken ~= myToken then return end

        -- В бою мгновенно ставим фоновый обход на паузу (0.00 мс нагрузки в бою!)
        if InCombatLockdown and InCombatLockdown() then
            if isBaseline then
                self.pendingCombatScanMode = "BASELINE"
            elseif not self.pendingCombatScanMode then
                self.pendingCombatScanMode = "DELTA"
            end
            return
        end

        local startMs = getMs and getMs() or nil
        local processedInSlice = 0

        while idx <= total do
            local t = self.Titles[idx]
            idx = idx + 1
            processedInSlice = processedInSlice + 1

            local isCol = self:IsTitleCollected(t.maskID)
            if isBaseline then
                if isCol then
                    self.lastKnownPctByMask[t.maskID] = 100.0
                    self:EvaluateTitleProgress(t, true, true)
                elseif t.obtainable then
                    local prog = self:EvaluateTitleProgress(t, true, true)
                    self.lastKnownPctByMask[t.maskID] = prog and prog.pct or 0.0
                end
            else
                local oldPct = self.lastKnownPctByMask[t.maskID] or 0.0
                if isCol then
                    self.lastKnownPctByMask[t.maskID] = 100.0
                    self:EvaluateTitleProgress(t, true, true)
                    if wantToast and not toastFired and oldPct < 100.0 then
                        toastFired = true
                        local fullProg = self:EvaluateTitleProgress(t, true, false)
                        self:TriggerProgressToast(t, fullProg, true, false)
                    end
                elseif t.obtainable then
                    local prog = self:EvaluateTitleProgress(t, true, true)
                    local newPct = prog and prog.pct or 0.0
                    self.lastKnownPctByMask[t.maskID] = newPct
                    if wantToast and not toastFired and newPct > (oldPct + 0.5)
                        and (newPct >= 70.0 or self:IsTitleTracked(t) or self:IsTitleFavorite(t.maskID))
                    then
                        toastFired = true
                        local fullProg = self:EvaluateTitleProgress(t, true, false)
                        self:TriggerProgressToast(t, fullProg, false, false)
                    end
                end
            end

            if processedInSlice >= 35 then
                break
            end
            if startMs and (processedInSlice % 5 == 0) and ((getMs() - startMs) >= 2.0) then
                break
            end
        end

        if idx <= total then
            C_Timer.After(0.03, ProcessNextSlice)
        else
            if isBaseline then
                self.baselineReady = true
            end
            if ui.mainFrame and ui.mainFrame:IsShown() then
                if ui.selectedTitle then
                    self:EvaluateTitleProgress(ui.selectedTitle, true, false)
                end
                self:RefreshUI()
            end
        end
    end

    C_Timer.After(0.02, ProcessNextSlice)
end

-- Мягкий дебаунс (схлопывает пачки по 20+ CRITERIA_UPDATE / UPDATE_FACTION при сдаче охоты и квестов в один проход)
function addon:ScheduleProgressScan(mode, fastAchID)
    -- Быстрый O(1) путь для прямого получения достижения со званием (< 0.05 мс)
    if fastAchID and type(fastAchID) == "number" and self.TitlesByAchID and self.TitlesByAchID[fastAchID] then
        local directTitle = self.TitlesByAchID[fastAchID]
        local oldPct = self.lastKnownPctByMask[directTitle.maskID] or 0.0
        local fullProg = self:EvaluateTitleProgress(directTitle, true, false)
        if self:IsTitleCollected(directTitle.maskID) then
            self.lastKnownPctByMask[directTitle.maskID] = 100.0
            if self.baselineReady and oldPct < 100.0 then
                self:TriggerProgressToast(directTitle, fullProg, true, false)
            end
        elseif fullProg then
            self.lastKnownPctByMask[directTitle.maskID] = fullProg.pct or 0.0
        end
    end

    if mode == "BASELINE" then
        self.pendingScanMode = "BASELINE"
    elseif self.pendingScanMode ~= "BASELINE" then
        self.pendingScanMode = "DELTA"
    end

    if InCombatLockdown and InCombatLockdown() then
        if self.pendingScanMode == "BASELINE" then
            self.pendingCombatScanMode = "BASELINE"
        elseif not self.pendingCombatScanMode then
            self.pendingCombatScanMode = "DELTA"
        end
        return
    end

    self.scanDebounceToken = (self.scanDebounceToken or 0) + 1
    local myDebToken = self.scanDebounceToken
    local delay = (self.pendingScanMode == "BASELINE") and 0.25 or 0.65

    C_Timer.After(delay, function()
        if self.scanDebounceToken ~= myDebToken then return end
        local runMode = self.pendingScanMode or "DELTA"
        self.pendingScanMode = nil
        if InCombatLockdown and InCombatLockdown() then
            self.pendingCombatScanMode = runMode
            return
        end
        self:StartSlicedProgressWorker(runMode)
    end)
end

function addon:SnapshotProgressBaseline()
    self:ScheduleProgressScan("BASELINE")
end

function addon:EnsureProgressToastFrame()
    if self.toastFrame then return self.toastFrame end

    local f = CreateFrame("Button", "TitleCollectorToastFrame", UIParent, "BackdropTemplate")
    f:SetSize(446, 82)
    f:SetPoint("TOP", UIParent, "TOP", 0, -130)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    ApplyBackdrop(f, 0.06, 0.05, 0.04, 0.96, 1.0, 0.78, 0.16, 1.0)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local iconBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    iconBox:SetSize(52, 52)
    iconBox:SetPoint("LEFT", f, "LEFT", 14, 0)
    ApplyBackdrop(iconBox, 0, 0, 0, 1, 1.0, 0.78, 0.16, 1.0)

    local iconTex = iconBox:CreateTexture(nil, "ARTWORK")
    iconTex:SetPoint("TOPLEFT", 1, -1)
    iconTex:SetPoint("BOTTOMRIGHT", -1, 1)
    iconTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    iconTex:SetTexture(237537)
    f.iconTex = iconTex

    local headerFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    headerFS:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 12, -2)
    headerFS:SetPoint("RIGHT", f, "RIGHT", -28, 0)
    headerFS:SetJustifyH("LEFT")
    headerFS:SetTextColor(1.0, 0.82, 0.18, 1.0)
    f.headerFS = headerFS

    local nameFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    nameFS:SetPoint("TOPLEFT", headerFS, "BOTTOMLEFT", 0, -4)
    nameFS:SetPoint("RIGHT", f, "RIGHT", -28, 0)
    nameFS:SetJustifyH("LEFT")
    nameFS:SetWordWrap(false)
    nameFS:SetTextColor(0.20, 1.0, 0.60, 1.0)
    f.nameFS = nameFS

    local subFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subFS:SetPoint("TOPLEFT", nameFS, "BOTTOMLEFT", 0, -4)
    subFS:SetPoint("RIGHT", f, "RIGHT", -14, 0)
    subFS:SetJustifyH("LEFT")
    f.subFS = subFS

    local closeBtn = CreateCollectorButton(f, 20, 20, "X", false)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
    closeBtn:SetScript("OnClick", function() f:Hide() end)

    f:SetScript("OnClick", function(frame, button)
        if button == "RightButton" then
            frame:Hide()
            return
        end
        if frame.title then
            ui.selectedTitle = frame.title
            local mf = addon:EnsureMainWindow()
            mf:Show()
            addon:RefreshUI()
            frame:Hide()
        end
    end)

    self.toastFrame = f
    return f
end

function addon:TriggerProgressToast(title, prog, isUnlocked, forceTest)
    if not title then return end
    if not forceTest and (not self.db or not self.db.settings or not self.db.settings.showProgressToast) then
        return
    end
    local now = GetTime and GetTime() or 0
    if not forceTest and (now - (self.lastToastTime or 0)) < 8.0 then
        return
    end
    self.lastToastTime = now

    local f = self:EnsureProgressToastFrame()
    f.title = title
    f.iconTex:SetTexture(title.icon or 237537)
    f.headerFS:SetText("|T237537:13:13:0:0|t TitleCollector — " .. (isUnlocked and self:L("TOAST_HEADER_UNLOCKED") or self:L("TOAST_HEADER_PROGRESS")))
    f.nameFS:SetText(self:GetTitleCleanName(title))

    if isUnlocked then
        f.subFS:SetText(self:L("TOAST_SUB_UNLOCKED"))
    else
        local pct = prog and prog.pct or 85
        local doneC = prog and prog.doneCount or 4
        local totC = prog and prog.totalCount or 5
        f.subFS:SetText(self:L("TOAST_SUB_PROGRESS_FMT", pct, doneC, totC))
    end

    f:Show()
    if PlaySound then
        pcall(PlaySound, 8959, "Master")
    end

    f.toastToken = (f.toastToken or 0) + 1
    local myToken = f.toastToken
    C_Timer.After(14.0, function()
        if f.toastToken == myToken and f:IsShown() then
            f:Hide()
        end
    end)
end

function addon:CheckProgressDeltasAndToast()
    self:ScheduleProgressScan("DELTA")
end

-- ============================================================================
-- СЛЭШ-КОМАНДЫ И ГЛАВНЫЙ ОБРАБОТЧИК СОБЫТИЙ
-- ============================================================================
SLASH_TITLECOLLECTOR1 = "/tc"
SLASH_TITLECOLLECTOR2 = "/titlecollector"
SlashCmdList["TITLECOLLECTOR"] = function(msg)
    local cmd = strtrim(string.lower(msg or ""))
    if cmd == "lang" or cmd == "ru" or cmd == "en" then
        addon.db.settings.language = addon:IsEnglish() and "ruRU" or "enUS"
        addon:ApplyLocaleToStaticUI()
        addon:RefreshUI()
    elseif cmd == "fav" or cmd == "random" then
        addon:EquipRandomFavorite(false)
    elseif cmd == "testalert" or cmd == "toast" then
        local sample = ui.selectedTitle or addon.Titles[1]
        if sample then
            local prog = addon:EvaluateTitleProgress(sample)
            addon:TriggerProgressToast(sample, prog, false, true)
        end
    elseif cmd == "minimap" or cmd == "mm" then
        addon.db.minimap.hide = not addon.db.minimap.hide
        addon:SetupRoundMinimapButton()
    else
        addon:ToggleMainWindow()
    end
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("KNOWN_TITLES_UPDATE")
eventFrame:RegisterEvent("UNIT_NAME_UPDATE")
eventFrame:RegisterEvent("ACHIEVEMENT_EARNED")
eventFrame:RegisterEvent("CRITERIA_UPDATE")
eventFrame:RegisterEvent("QUEST_TURNED_IN")
eventFrame:RegisterEvent("UPDATE_FACTION")
eventFrame:RegisterEvent("MAJOR_FACTION_RENOWN_LEVEL_CHANGED")
eventFrame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
eventFrame:RegisterEvent("ZONE_CHANGED_NEW_AREA")
eventFrame:RegisterEvent("ZONE_CHANGED_INDOORS")
eventFrame:RegisterEvent("ZONE_CHANGED")
eventFrame:RegisterEvent("USER_WAYPOINT_UPDATED")
eventFrame:RegisterEvent("PLAYER_UPDATE_RESTING")
eventFrame:RegisterEvent("PLAYER_REGEN_ENABLED")
eventFrame:RegisterEvent("PLAYER_TARGET_CHANGED")
eventFrame:RegisterEvent("UPDATE_MOUSEOVER_UNIT")

eventFrame:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" and arg1 == addonName then
        addon:InitDB()
        addon:BuildTitleIndex()
        addon:InitPlayerTooltips()
        if addon.InitWaypointHooks then
            addon:InitWaypointHooks()
        end
        addon:InitLDB()
    elseif event == "PLAYER_ENTERING_WORLD" then
        C_Timer.After(0.8, function()
            addon:BuildTitleIndex()
            addon:ScheduleProgressScan("BASELINE")
            addon:SetupRoundMinimapButton()
            addon:HookCharacterTitlesPane()
            addon:CheckPortalRouteProgress()
            addon:EvaluateAutoTitleRules("ENTER_WORLD")
        end)
        C_Timer.After(2.0, function() addon:CheckPortalRouteProgress() end)
    elseif event == "KNOWN_TITLES_UPDATE" or (event == "UNIT_NAME_UPDATE" and arg1 == "player") then
        addon:ScheduleProgressScan("DELTA")
        if ui.mainFrame and ui.mainFrame:IsShown() then
            if ui.selectedTitle then
                addon:EvaluateTitleProgress(ui.selectedTitle, true, false)
            end
            addon:RefreshUI()
        end
    elseif event == "ACHIEVEMENT_EARNED" then
        local earnedID = (addon.SafeNotSecret(arg1) and type(arg1) == "number") and arg1 or nil
        addon:ScheduleProgressScan("DELTA", earnedID)
    elseif event == "CRITERIA_UPDATE" or event == "QUEST_TURNED_IN" or event == "UPDATE_FACTION" or event == "MAJOR_FACTION_RENOWN_LEVEL_CHANGED" then
        addon:ScheduleProgressScan("DELTA")
    elseif event == "USER_WAYPOINT_UPDATED" then
        if addon.OnUserWaypointUpdated then
            addon:OnUserWaypointUpdated()
        end
    elseif event == "ZONE_CHANGED_INDOORS" or event == "ZONE_CHANGED" then
        C_Timer.After(0.4, function() addon:CheckPortalRouteProgress() end)
    elseif event == "PLAYER_SPECIALIZATION_CHANGED" or event == "ZONE_CHANGED_NEW_AREA" or event == "PLAYER_UPDATE_RESTING" then
        if event == "ZONE_CHANGED_NEW_AREA" then
            C_Timer.After(0.4, function() addon:CheckPortalRouteProgress() end)
            C_Timer.After(1.4, function() addon:CheckPortalRouteProgress() end)
        end
        C_Timer.After(0.5, function()
            addon:EvaluateAutoTitleRules(event)
            if ui.mainFrame and ui.mainFrame:IsShown() and ui.currentTab == "ZONE" then
                addon:RefreshUI()
            end
        end)
    elseif event == "PLAYER_REGEN_ENABLED" then
        if addon.pendingEquipMaskID ~= nil then
            local targetMask = addon.pendingEquipMaskID
            addon.pendingEquipMaskID = nil
            addon:EquipTitle(targetMask, false)
        end
        if addon.pendingCombatScanMode then
            local resumeMode = addon.pendingCombatScanMode
            addon.pendingCombatScanMode = nil
            addon:ScheduleProgressScan(resumeMode)
        end
    elseif event == "PLAYER_TARGET_CHANGED" then
        addon:ScanUnitTitle("target")
    elseif event == "UPDATE_MOUSEOVER_UNIT" then
        addon:ScanUnitTitle("mouseover")
    end
end)
