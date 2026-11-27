local _, addon = ...

-- ============================================================================
-- TitleCollector — Navigation.lua
-- Межконтинентальный портальный навигатор (3D Waypoint + SuperTrack + TomTom),
-- интеграция с журналом достижений Blizzard, трекером целей и ссылками Wowhead.
-- ============================================================================

local SafeNotSecret = addon.SafeNotSecret

addon.activePortalRoute = nil
addon.portalTomTomUids = {}
addon.isSettingWaypoint = false

function addon:ClearActivePortalRoute()
    self.activePortalRoute = nil
    if self.portalCompassFrame then
        self.portalCompassFrame:Hide()
    end
    if _G.TomTom and _G.TomTom.RemoveWaypoint and self.portalTomTomUids then
        for _, uid in ipairs(self.portalTomTomUids) do
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
        end
        wipe(self.portalTomTomUids)
    end
end

-- Определение, находится ли игрок прямо сейчас ВНУТРИ Зала порталов столицы
-- («Святилище волшебника» в Штормграде или «Пристанище следопыта» в Оргриммаре),
-- где Blizzard спрятали коробку зала за пределами 2D-карты (00, 00), но работает UnitPosition!
local function IsPlayerInsideCapitalPortalRoom()
    local sub = string.lower((_G.GetSubZoneText and GetSubZoneText()) or "")
    local msub = string.lower((_G.GetMinimapZoneText and GetMinimapZoneText()) or "")
    local blob = sub .. " " .. msub
    if string.find(blob, "святилище волшебника", 1, true)
        or string.find(blob, "wizard's sanctum", 1, true)
        or string.find(blob, "пристанище следопыта", 1, true)
        or string.find(blob, "pathfinder's den", 1, true)
    then
        return true
    end

    -- Резервная проверка для любых локалей клиента: в Зале порталов карта 84/85 отдаёт nil/(0,0), но UnitPosition валиден
    local pMap = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if (pMap == 84 or pMap == 85) and (not _G.IsInInstance or not IsInInstance()) and _G.UnitPosition then
        local pos = C_Map.GetPlayerMapPosition and C_Map.GetPlayerMapPosition(pMap, "player")
        local mx, my = pos and pos:GetXY()
        if not mx or not my or (mx == 0 and my == 0) then
            local okU, py, px, _, instID = pcall(UnitPosition, "player")
            if okU and py and px and (instID == 0 or instID == 1) then
                return true
            end
        end
    end
    return false
end

-- Справочник конкретных порталов внутри Зала порталов Штормграда и Оргриммара
-- (с точными мировыми координатами UnitPosition для 3D-компаса и шпаргалкой этажа/ниши)
local CAPITAL_PORTAL_GUIDES = {
    CAVERNS_OF_TIME = {
        nameRU = "Портал в Пещеры Времени (Танарис)",
        nameEN = "Portal to Caverns of Time (Tanaris)",
        hintAllianceRU = "1-й зал от входа: дальняя правая ниша (между Экзодаром и Шаттратом)",
        hintAllianceEN = "Main hall (ground floor): far-right alcove between Exodar & Shattrath",
        hintHordeRU    = "Нижний зал: сразу у входа поверните налево вниз по лестнице",
        hintHordeEN    = "Lower hall: take the stairs down on your left right inside the entrance",
        swWorldX = -9007.65, swWorldY = 870.42,
    },
    OUTLAND = {
        nameRU = "Портал в Шаттрат (Запределье)",
        nameEN = "Portal to Shattrath (Outland)",
        hintAllianceRU = "1-й зал от входа: первая правая ниша у входа",
        hintAllianceEN = "Main hall (ground floor): first alcove on the right",
        hintHordeRU    = "Главный верхний зал: левая сторона",
        hintHordeEN    = "Main upper hall: left wall",
    },
    NORTHREND = {
        nameRU = "Портал в Даларан (Лес Хрустальной Песни)",
        nameEN = "Portal to Dalaran (Crystalsong Forest)",
        hintAllianceRU = "1-й зал от входа: центральная ниша слева",
        hintAllianceEN = "Main hall (ground floor): middle alcove on the left",
        hintHordeRU    = "Главный верхний зал: правая сторона",
        hintHordeEN    = "Main upper hall: right wall",
    },
    PANDARIA = {
        nameRU = "Портал в Нефритовый лес (Пандария)",
        nameEN = "Portal to The Jade Forest (Pandaria)",
        hintAllianceRU = "1-й зал от входа: вторая ниша слева",
        hintAllianceEN = "Main hall (ground floor): second alcove on the left",
        hintHordeRU    = "Главный верхний зал: дальняя правая ниша",
        hintHordeEN    = "Main upper hall: far-right alcove",
    },
    DRAENOR = {
        nameRU = "Портал в Ашран (Дренор)",
        nameEN = "Portal to Ashran (Draenor)",
        hintAllianceRU = "1-й зал от входа: центральная ниша справа",
        hintAllianceEN = "Main hall (ground floor): middle alcove on the right",
        hintHordeRU    = "Нижний зал: сразу у входа поверните налево вниз по лестнице",
        hintHordeEN    = "Lower hall: take the stairs down on your left right inside the entrance",
    },
    BROKEN_ISLES = {
        nameRU = "Портал в Азсуну (Расколотые острова)",
        nameEN = "Portal to Azsuna (Broken Isles)",
        hintAllianceRU = "1-й зал от входа: первая левая ниша у входа",
        hintAllianceEN = "Main hall (ground floor): first alcove on the left",
        hintHordeRU    = "Главный верхний зал: левая сторона",
        hintHordeEN    = "Main upper hall: left wall",
    },
    KUL_TIRAS = {
        nameRU = "Портал в Боралус (Кул-Тирас)",
        nameEN = "Portal to Boralus (Kul Tiras)",
        hintAllianceRU = "1-й зал от входа: дальняя левая ниша у лестницы",
        hintAllianceEN = "Main hall (ground floor): back-left alcove near the stairs",
        hintHordeRU    = "Портал в Зулдазар -> корабль/кампания Кул-Тираса",
        hintHordeEN    = "Main upper hall: Zuldazar portal",
    },
    ZANDALAR = {
        nameRU = "Портал в Дазар'алор (Зандалар)",
        nameEN = "Portal to Dazar'alor (Zandalar)",
        hintAllianceRU = "1-й зал: портал в Боралус -> корабль кампании в Зандалар",
        hintAllianceEN = "Main hall: Boralus portal -> War Campaign ship",
        hintHordeRU    = "Главный верхний зал: центральная ниша дальней стены",
        hintHordeEN    = "Main upper hall: back-center alcove",
    },
    SHADOWLANDS = {
        nameRU = "Портал в Орибос (Тёмные Земли)",
        nameEN = "Portal to Oribos (Shadowlands)",
        hintAllianceRU = "2-й этаж: поднимитесь по лестнице в глубине зала и поверните налево",
        hintAllianceEN = "Upper floor: go up the back stairs and turn into the left wing",
        hintHordeRU    = "Нижний зал: сразу у входа поверните налево вниз по лестнице",
        hintHordeEN    = "Lower hall: take the stairs down on your left right inside the entrance",
    },
    DRAGON_ISLES = {
        nameRU = "Портал в Вальдраккен (Драконьи острова)",
        nameEN = "Portal to Valdrakken (Dragon Isles)",
        hintAllianceRU = "2-й этаж: поднимитесь по лестнице в верхний зал",
        hintAllianceEN = "Upper floor: go up the back stairs into the upper hall",
        hintHordeRU    = "Главный верхний зал: центральная ниша",
        hintHordeEN    = "Main upper hall: central alcove",
    },
    KHAZ_ALGAR = {
        nameRU = "Портал в Дорногал (Каз Алгар)",
        nameEN = "Portal to Dornogal (Khaz Algar)",
        hintAllianceRU = "2-й этаж: поднимитесь по лестнице и поверните направо в новое крыло",
        hintAllianceEN = "Upper floor: go up the back stairs and turn right into the new wing",
        hintHordeRU    = "Нижний зал: вниз по лестнице слева от входа",
        hintHordeEN    = "Lower hall: down the stairs on your left",
    },
    MIDNIGHT_QUELTHALAS = {
        nameRU = "Портал в Луносвет (Кель'Талас)",
        nameEN = "Portal to Silvermoon City (Quel'Thalas)",
        hintAllianceRU = "2-й этаж: верхнее крыло актуальных порталов -> Луносвет",
        hintAllianceEN = "Upper floor: expansion wing -> Silvermoon City",
        hintHordeRU    = "Зал порталов Оргриммара -> Портал в Луносвет",
        hintHordeEN    = "Orgrimmar Portal Room -> Portal to Silvermoon City",
    },
}

local function GetCapitalPortalGuideForTarget(targetMapID, targetRegion)
    if targetMapID == 71 or targetMapID == 249 then
        return CAPITAL_PORTAL_GUIDES.CAVERNS_OF_TIME
    end
    if targetRegion == "ARGUS" then
        return CAPITAL_PORTAL_GUIDES.BROKEN_ISLES
    end
    if targetRegion == "ZARALEK" or targetRegion == "EMERALD_DREAM" then
        return CAPITAL_PORTAL_GUIDES.DRAGON_ISLES
    end
    if targetRegion == "HARANDAR" or targetRegion == "VOIDSTORM" then
        return CAPITAL_PORTAL_GUIDES.MIDNIGHT_QUELTHALAS
    end
    if targetRegion == "KALIMDOR" then
        return CAPITAL_PORTAL_GUIDES.CAVERNS_OF_TIME
    end
    return CAPITAL_PORTAL_GUIDES[targetRegion]
end

local function GetMapAncestry(mapID)
    local chain = {}
    local visited = {}
    local cur = mapID
    while cur and cur > 0 and not visited[cur] do
        visited[cur] = true
        table.insert(chain, cur)
        local info = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(cur)
        cur = info and info.parentMapID or nil
    end
    return chain, visited
end

local function GetMapInstanceID(mapID)
    if not mapID or not C_Map or not C_Map.GetWorldPosFromMapPos or not _G.CreateVector2D then
        return nil
    end
    local ok, instID = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(0.5, 0.5))
    if ok and instID then
        return instID
    end
    return nil
end

local function GetMapMacroRegion(mapID)
    if not mapID then return "UNKNOWN" end
    local _, ancestors = GetMapAncestry(mapID)

    if mapID == 2413 or mapID == 2576 or ancestors[2413] then return "HARANDAR" end
    if mapID == 2405 or ancestors[2405] then return "VOIDSTORM" end
    if mapID == 2200 or ancestors[2200] then return "EMERALD_DREAM" end
    if mapID == 2133 or ancestors[2133] then return "ZARALEK" end

    if mapID == 2393 or mapID == 2605 or mapID == 2395 or mapID == 2594 or mapID == 2437 or mapID == 2537
        or ancestors[2393] or ancestors[2395] or ancestors[2437] or ancestors[2537] or ancestors[2424]
    then
        return "MIDNIGHT_QUELTHALAS"
    end
    if mapID == 2339 or ancestors[2274] or ancestors[2248] or ancestors[2214] or ancestors[2215] or ancestors[2255] then
        return "KHAZ_ALGAR"
    end
    if mapID == 2112 or ancestors[1978] or ancestors[2022] or ancestors[2023] or ancestors[2024] or ancestors[2025] or ancestors[2151] then
        return "DRAGON_ISLES"
    end
    if mapID == 1670 or ancestors[1550] or ancestors[1525] or ancestors[1533] or ancestors[1536] or ancestors[1565] or ancestors[1543] or ancestors[1970] then
        return "SHADOWLANDS"
    end
    if mapID == 1165 or ancestors[875] or ancestors[862] or ancestors[863] or ancestors[864] then
        return "ZANDALAR"
    end
    if mapID == 1161 or ancestors[876] or ancestors[895] or ancestors[896] or ancestors[942] then
        return "KUL_TIRAS"
    end
    if mapID == 627 or ancestors[619] or ancestors[630] or ancestors[641] or ancestors[650] or ancestors[634] or ancestors[680] or ancestors[646] then
        return "BROKEN_ISLES"
    end
    if ancestors[905] or mapID == 830 or mapID == 882 or mapID == 885 then
        return "ARGUS"
    end
    if ancestors[572] then return "DRAENOR" end
    if ancestors[424] or mapID == 371 or mapID == 507 or mapID == 504 or mapID == 554 or mapID == 376 or mapID == 379 or mapID == 388 or mapID == 390 or mapID == 418 or mapID == 422 then
        return "PANDARIA"
    end
    if ancestors[101] or mapID == 111 then return "OUTLAND" end
    if ancestors[113] or mapID == 125 then return "NORTHREND" end
    if ancestors[12] or mapID == 85 then return "KALIMDOR" end
    if ancestors[13] or mapID == 84 then return "EASTERN_KINGDOMS" end
    return "OTHER_" .. tostring(mapID)
end

local function ResolvePinnableMapCoords(mapID, normX, normY)
    if not mapID or not C_Map or not C_Map.CanSetUserWaypointOnMap then
        return mapID, normX, normY
    end
    local ok, canSet = pcall(C_Map.CanSetUserWaypointOnMap, mapID)
    if ok and canSet then
        return mapID, normX, normY
    end
    if not C_Map.GetMapInfo or not C_Map.GetWorldPosFromMapPos or not C_Map.GetMapPosFromWorldPos or not _G.CreateVector2D then
        return mapID, normX, normY
    end
    local curMap = mapID
    for _ = 1, 5 do
        local info = C_Map.GetMapInfo(curMap)
        if not info or not info.parentMapID or info.parentMapID == 0 then break end
        local parentID = info.parentMapID
        local okP, canParent = pcall(C_Map.CanSetUserWaypointOnMap, parentID)
        if okP and canParent then
            local okW, instID, worldPos = pcall(C_Map.GetWorldPosFromMapPos, mapID, CreateVector2D(normX, normY))
            if okW and instID and worldPos then
                local okM, _, parentPos = pcall(C_Map.GetMapPosFromWorldPos, instID, worldPos, parentID)
                if okM and parentPos then
                    local px, py = parentPos:GetXY()
                    if px and py and px > 0 and px < 1 and py > 0 and py < 1 then
                        return parentID, px, py
                    end
                end
            end
        end
        curMap = parentID
    end
    return mapID, normX, normY
end

function addon:BuildMultiHopRoute(targetMapID, targetX, targetY, targetName, targetZone, targetNote)
    local steps = {}
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID or playerMapID == targetMapID then
        table.insert(steps, { mapID = targetMapID, x = targetX, y = targetY, zone = targetZone, note = targetNote or targetName })
        return steps
    end

    local playerRegion = GetMapMacroRegion(playerMapID)
    local targetRegion = GetMapMacroRegion(targetMapID)
    local playerInstID = GetMapInstanceID(playerMapID)
    local targetInstID = GetMapInstanceID(targetMapID)

    local needTanarisPortalFromOrg = (not isAlliance and playerMapID == 85 and (targetMapID == 71 or targetMapID == 249))
    if not needTanarisPortalFromOrg
        and (playerRegion == targetRegion or (playerInstID and targetInstID and playerInstID == targetInstID and playerRegion == targetRegion))
        and playerRegion ~= "HARANDAR" and targetRegion ~= "HARANDAR"
        and playerRegion ~= "VOIDSTORM" and targetRegion ~= "VOIDSTORM"
        and playerRegion ~= "EMERALD_DREAM" and targetRegion ~= "EMERALD_DREAM"
    then
        table.insert(steps, { mapID = targetMapID, x = targetX, y = targetY, zone = targetZone, note = targetNote or targetName })
        return steps
    end

    local isEN       = self:IsEnglish()
    local isAlliance = (UnitFactionGroup("player") == "Alliance")
    local capMapID   = isAlliance and 84 or 85
    local capName    = isEN
        and (isAlliance and "Stormwind Portal Room" or "Orgrimmar Portal Room")
        or (isAlliance and "Зал порталов Штормграда" or "Зал порталов Оргриммара")
    local capX       = isAlliance and 48.7 or 57.3
    local capY       = isAlliance and 88.1 or 89.7
    local capRegion  = isAlliance and "EASTERN_KINGDOMS" or "KALIMDOR"

    if playerRegion == "HARANDAR" then
        table.insert(steps, {
            mapID = 2413, x = 53.3, y = 55.5, subMapID = 2576, subX = 64.5, subY = 71.4,
            zone = isEN and "Harandar (The Den)" or "Харандар (Логово)",
            note = isEN and "Rootway to Eversong Woods / Silvermoon" or "Корнистый путь в леса Вечной Песни / Луносвет",
        })
        if targetRegion ~= "MIDNIGHT_QUELTHALAS" then
            table.insert(steps, {
                mapID = 2395, x = isAlliance and 52.6 or 52.5, y = isAlliance and 25.5 or 25.7,
                subMapID = 2393, subX = isAlliance and 52.6 or 52.2, subY = isAlliance and 64.5 or 65.2,
                zone = isEN and "Silvermoon City" or "Луносвет",
                note = isEN
                    and (isAlliance and "Silvermoon Portal Room: Portal to Stormwind" or "Silvermoon Portal Room: Portal to Orgrimmar")
                    or (isAlliance and "Зал с порталами Луносвета: Портал в Штормград" or "Зал с порталами Луносвета: Портал в Оргриммар"),
            })
        end
    elseif playerRegion == "MIDNIGHT_QUELTHALAS" then
        table.insert(steps, {
            mapID = 2395, x = isAlliance and 52.6 or 52.5, y = isAlliance and 25.5 or 25.7,
            subMapID = 2393, subX = isAlliance and 52.6 or 52.2, subY = isAlliance and 64.5 or 65.2,
            zone = isEN and "Silvermoon City" or "Луносвет",
            note = isEN
                and (isAlliance and "Silvermoon Portal Room: Portal to Stormwind" or "Silvermoon Portal Room: Portal to Orgrimmar")
                or (isAlliance and "Зал с порталами Луносвета: Портал в Штормград" or "Зал с порталами Луносвета: Портал в Оргриммар"),
        })
    elseif playerRegion == "KHAZ_ALGAR" then
        table.insert(steps, {
            mapID = 2339, x = 41.9, y = 28.3,
            zone = isEN and "Dornogal" or "Дорногал",
            note = isEN
                and (isAlliance and "Dornogal Portal Room: Portal to Stormwind" or "Dornogal Portal Room: Portal to Orgrimmar")
                or (isAlliance and "Комната порталов Дорногала: Портал в Штормград" or "Комната порталов Дорногала: Портал в Оргриммар"),
        })
    elseif playerRegion == "DRAGON_ISLES" then
        table.insert(steps, {
            mapID = 2112, x = 57.9, y = 35.3,
            zone = isEN and "Valdrakken" or "Вальдраккен",
            note = isEN and "Seat of the Aspects (Valdrakken): Capital Portal" or "Престол Аспектов (Вальдраккен): Портал в столицу",
        })
    elseif playerRegion == "SHADOWLANDS" then
        table.insert(steps, {
            mapID = 1670, x = 22.4, y = 50.2,
            zone = isEN and "Oribos" or "Орибос",
            note = isEN and "Ring of Fates (Oribos): Capital Portal" or "Портал в столицу (Кольцо Судеб, Орибос)",
        })
    elseif playerRegion == "PANDARIA" then
        table.insert(steps, {
            mapID = 371, x = isAlliance and 46.2 or 28.5, y = isAlliance and 85.2 or 14.0,
            zone = isEN and "The Jade Forest" or "Нефритовый лес",
            note = isEN
                and (isAlliance and "Portal to Stormwind (Paw'don Village)" or "Portal to Orgrimmar (Honeydew Village)")
                or (isAlliance and "Портал в Штормград (Деревня Лап'дон)" or "Портал в Оргриммар (Деревня Медовой Росы)"),
        })
    end

    if targetRegion ~= capRegion or needTanarisPortalFromOrg then
        local skipCapStep = (playerRegion == "HARANDAR" and targetRegion == "MIDNIGHT_QUELTHALAS")
        if not skipCapStep then
            local pGuide = GetCapitalPortalGuideForTarget(targetMapID, targetRegion)
            local portalTitle = pGuide and (isEN and pGuide.nameEN or pGuide.nameRU)
                or (isEN and "Portal to destination continent" or "Портал в целевой континент")
            local roomHint = pGuide and (isAlliance
                and (isEN and pGuide.hintAllianceEN or pGuide.hintAllianceRU)
                or (isEN and pGuide.hintHordeEN or pGuide.hintHordeRU)) or nil
            table.insert(steps, {
                mapID = capMapID, x = capX, y = capY,
                isCapitalPortalRoom = true,
                portalTitle = portalTitle,
                roomHint = roomHint,
                worldX = (isAlliance and pGuide and pGuide.swWorldX) or nil,
                worldY = (isAlliance and pGuide and pGuide.swWorldY) or nil,
                zone = isEN and (isAlliance and "Stormwind City" or "Orgrimmar") or (isAlliance and "Штормград" or "Оргриммар"),
                note = capName .. " -> " .. portalTitle,
            })
        end
    end

    if targetRegion == "HARANDAR" and playerRegion ~= "HARANDAR" then
        table.insert(steps, {
            mapID = 2395, x = 47.9, y = 26.6, subMapID = 2393, subX = 36.7, subY = 68.2,
            zone = isEN and "Silvermoon (Memorial Gardens)" or "Луносвет (Сады Памяти)",
            note = isEN and "Rootway to Harandar (36.7, 68.2)" or "Корнистый путь в Харандар (36.7, 68.2)",
        })
    end

    table.insert(steps, {
        mapID = targetMapID, x = targetX, y = targetY,
        zone = targetZone, note = targetNote or targetName,
    })
    return steps
end

function addon:EnsurePortalCompassFrame()
    if self.portalCompassFrame then return self.portalCompassFrame end

    local f = CreateFrame("Frame", "TitleCollectorPortalCompass", UIParent, "BackdropTemplate")
    f:SetSize(486, 74)
    f:SetPoint("TOP", UIParent, "TOP", 0, -52)
    f:SetFrameStrata("HIGH")
    f:SetToplevel(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    f:SetBackdropColor(0.05, 0.05, 0.07, 0.96)
    f:SetBackdropBorderColor(0.92, 0.74, 0.18, 1.0)
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local iconBox = CreateFrame("Frame", nil, f, "BackdropTemplate")
    iconBox:SetSize(48, 48)
    iconBox:SetPoint("LEFT", f, "LEFT", 12, 0)
    iconBox:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    iconBox:SetBackdropColor(0.08, 0.08, 0.11, 0.98)
    iconBox:SetBackdropBorderColor(0.45, 0.38, 0.18, 1.0)

    local arrowTex = iconBox:CreateTexture(nil, "ARTWORK")
    arrowTex:SetSize(34, 34)
    arrowTex:SetPoint("CENTER", iconBox, "CENTER", 0, 4)
    arrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
    f.arrowTex = arrowTex

    local distFS = iconBox:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    distFS:SetPoint("BOTTOM", iconBox, "BOTTOM", 0, 2)
    distFS:SetTextColor(0.20, 1.0, 0.60, 1.0)
    f.distFS = distFS

    local hdrFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    hdrFS:SetPoint("TOPLEFT", iconBox, "TOPRIGHT", 10, -1)
    hdrFS:SetPoint("RIGHT", f, "RIGHT", -28, 0)
    hdrFS:SetJustifyH("LEFT")
    hdrFS:SetTextColor(1.0, 0.84, 0.20, 1.0)
    f.hdrFS = hdrFS

    local portalFS = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    portalFS:SetPoint("TOPLEFT", hdrFS, "BOTTOMLEFT", 0, -3)
    portalFS:SetPoint("RIGHT", f, "RIGHT", -28, 0)
    portalFS:SetJustifyH("LEFT")
    portalFS:SetWordWrap(false)
    portalFS:SetTextColor(0.25, 0.88, 1.0, 1.0)
    f.portalFS = portalFS

    local hintFS = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    hintFS:SetPoint("TOPLEFT", portalFS, "BOTTOMLEFT", 0, -3)
    hintFS:SetPoint("RIGHT", f, "RIGHT", -12, 0)
    hintFS:SetJustifyH("LEFT")
    hintFS:SetWordWrap(true)
    hintFS:SetTextColor(0.90, 0.90, 0.94, 1.0)
    f.hintFS = hintFS

    local closeBtn = CreateFrame("Button", nil, f, "BackdropTemplate")
    closeBtn:SetSize(18, 18)
    closeBtn:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5)
    closeBtn:SetBackdrop({ bgFile = "Interface\\Buttons\\WHITE8x8", edgeFile = "Interface\\Buttons\\WHITE8x8", edgeSize = 1 })
    closeBtn:SetBackdropColor(0.14, 0.14, 0.16, 0.95)
    closeBtn:SetBackdropBorderColor(0.32, 0.32, 0.36, 1.0)
    local xFS = closeBtn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    xFS:SetPoint("CENTER")
    xFS:SetText("X")
    closeBtn:SetScript("OnClick", function() addon:ClearActivePortalRoute() end)

    f.elapsedAcc = 0
    f:SetScript("OnUpdate", function(selfF, elapsed)
        selfF.elapsedAcc = (selfF.elapsedAcc or 0) + elapsed
        if selfF.elapsedAcc < 0.03 then return end
        selfF.elapsedAcc = 0

        local st = selfF.step
        if not st or not st.worldX or not st.worldY or not _G.UnitPosition or not _G.GetPlayerFacing then
            return
        end
        local okU, py, px = pcall(UnitPosition, "player")
        local okF, facing = pcall(GetPlayerFacing)
        if not okU or not okF or not SafeNotSecret(py) or not SafeNotSecret(px) or not SafeNotSecret(facing) then
            return
        end
        if type(py) ~= "number" or type(px) ~= "number" or type(facing) ~= "number" then
            return
        end
        local dNorth = st.worldX - px
        local dWest = st.worldY - py
        local dist = math.sqrt(dNorth * dNorth + dWest * dWest)
        local relAngle = math.atan2(dWest, dNorth) - facing
        selfF.arrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
        selfF.arrowTex:SetSize(34, 34)
        selfF.arrowTex:SetPoint("CENTER", iconBox, "CENTER", 0, 5)
        if selfF.arrowTex.SetRotation then
            pcall(selfF.arrowTex.SetRotation, selfF.arrowTex, relAngle)
        end
        selfF.distFS:SetText(addon:L("PORTAL_DIST_YARDS_FMT", math.floor(dist + 0.5)))
    end)

    self.portalCompassFrame = f
    return f
end

function addon:UpdatePortalRoomCompass(step, insideRoom)
    if not step or not step.isCapitalPortalRoom or not insideRoom then
        if self.portalCompassFrame then
            self.portalCompassFrame:Hide()
        end
        return
    end
    local f = self:EnsurePortalCompassFrame()
    f.step = step
    f.hdrFS:SetText("|T135744:12:12:0:0|t " .. self:L("PORTAL_COMPASS_HDR"))
    f.portalFS:SetText(step.portalTitle or step.note or "—")
    f.hintFS:SetText(step.roomHint or "")

    if step.worldX and step.worldY then
        f.arrowTex:SetTexture("Interface\\Minimap\\MinimapArrow")
        f.arrowTex:SetTexCoord(0, 1, 0, 1)
        f.distFS:Show()
    else
        if f.arrowTex.SetRotation then pcall(f.arrowTex.SetRotation, f.arrowTex, 0) end
        f.arrowTex:SetTexture(135744)
        f.arrowTex:SetSize(32, 32)
        f.arrowTex:ClearAllPoints()
        f.arrowTex:SetPoint("CENTER", f.arrowTex:GetParent(), "CENTER", 0, 0)
        f.arrowTex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        f.distFS:SetText("")
        f.distFS:Hide()
    end
    f:Show()
end

function addon:ActivateCurrentRouteStep(silent)
    local route = self.activePortalRoute
    if not route or not route.steps or #route.steps == 0 then return end
    local step = route.steps[route.currentStep] or route.steps[#route.steps]
    if not step then return end

    if _G.TomTom and _G.TomTom.RemoveWaypoint and self.portalTomTomUids then
        for _, uid in ipairs(self.portalTomTomUids) do
            pcall(_G.TomTom.RemoveWaypoint, _G.TomTom, uid)
        end
        wipe(self.portalTomTomUids)
    end

    local insidePortalRoom = step.isCapitalPortalRoom and IsPlayerInsideCapitalPortalRoom()
    self:UpdatePortalRoomCompass(step, insidePortalRoom)

    local totalSteps = #route.steps
    local isEN = self:IsEnglish()
    local stepLabel = totalSteps > 1
        and string.format(isEN and "[Step %d/%d] %s" or "[Шаг %d/%d] %s", route.currentStep, totalSteps, step.note or route.targetName)
        or string.format("TitleCollector: %s", route.targetName)

    -- Если игрок УЖЕ внутри Зала порталов столицы (00, 00), НЕ ставим уличную метку (48.7, 88.1),
    -- чтобы жёлтый ромбик не разворачивал игрока обратно к выходу из башни!
    if insidePortalRoom then
        route.activePinMapID = nil
        route.activePinX = nil
        route.activePinY = nil
        if C_Map and C_Map.HasUserWaypoint and C_Map.HasUserWaypoint() and C_Map.ClearUserWaypoint then
            self.isSettingWaypoint = true
            pcall(C_Map.ClearUserWaypoint)
            self.isSettingWaypoint = false
        end
        if not silent then
            print(string.format(
                "|cffffd100[TitleCollector %d/%d]|r |cff00ccff%s|r — %s",
                route.currentStep, totalSteps,
                step.portalTitle or step.note or route.targetName,
                step.roomHint or ""
            ))
        end
        return
    end

    if _G.TomTom and _G.TomTom.AddWaypoint then
        local ok, uid = pcall(_G.TomTom.AddWaypoint, _G.TomTom, step.mapID, step.x / 100, step.y / 100, {
            title = stepLabel, persistent = false, minimap = true, world = true, crazy = true,
        })
        if ok and uid then
            table.insert(self.portalTomTomUids, uid)
            if _G.TomTom.SetCrazyArrow then
                pcall(_G.TomTom.SetCrazyArrow, _G.TomTom, uid, 15, stepLabel)
            end
        end
        if step.subMapID and step.subX and step.subY then
            local okSub, uidSub = pcall(_G.TomTom.AddWaypoint, _G.TomTom, step.subMapID, step.subX / 100, step.subY / 100, {
                title = stepLabel, persistent = false, minimap = true, world = true, crazy = true,
            })
            if okSub and uidSub then
                table.insert(self.portalTomTomUids, uidSub)
            end
        end
    end

    if C_Map and C_Map.SetUserWaypoint and _G.UiMapPoint and _G.UiMapPoint.CreateFromCoordinates then
        local pinMapID, pinX, pinY = ResolvePinnableMapCoords(step.mapID, step.x / 100, step.y / 100)
        local okCan, canSet = pcall(C_Map.CanSetUserWaypointOnMap, pinMapID)
        if not okCan or canSet then
            route.activePinMapID = pinMapID
            route.activePinX = pinX
            route.activePinY = pinY
            self.isSettingWaypoint = true
            local uiPt = UiMapPoint.CreateFromCoordinates(pinMapID, pinX, pinY)
            pcall(C_Map.SetUserWaypoint, uiPt)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                C_Timer.After(0.10, function()
                    if self.activePortalRoute == route and C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                        self.isSettingWaypoint = true
                        pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
                        self.isSettingWaypoint = false
                    end
                end)
            end
            self.isSettingWaypoint = false
        end
    end

    if not silent then
        local mapInfo = C_Map and C_Map.GetMapInfo and C_Map.GetMapInfo(step.mapID)
        local zoneName = step.zone or (mapInfo and SafeNotSecret(mapInfo.name) and mapInfo.name) or self:L("UNKNOWN_ZONE")
        if totalSteps > 1 then
            print(string.format(
                isEN
                    and "|cffffd100[TitleCollector Route %d/%d]|r Minimap arrow leads to: |cff00ccff%s|r — %s (%.1f, %.1f)"
                    or "|cffffd100[TitleCollector Маршрут %d/%d]|r Стрелка миникарты ведёт: |cff00ccff%s|r — %s (%.1f, %.1f)",
                route.currentStep, totalSteps, step.note or route.targetName, zoneName, step.x or 50, step.y or 50
            ))
        else
            print(string.format(
                isEN
                    and "|cffffd100[TitleCollector]|r Route plotted to |cff00ccff%s|r: %s (%.1f, %.1f)"
                    or "|cffffd100[TitleCollector]|r Проложен путь к |cff00ccff%s|r: %s (%.1f, %.1f)",
                route.targetName, zoneName, step.x or 50, step.y or 50
            ))
        end
    end
end

function addon:CheckPortalRouteProgress()
    local route = self.activePortalRoute
    if not route or not route.steps or #route.steps == 0 then return end
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then return end

    local playerRegion = GetMapMacroRegion(playerMapID)
    local playerInstID = GetMapInstanceID(playerMapID)
    local finalStep = route.steps[#route.steps]
    local finalRegion = GetMapMacroRegion(finalStep.mapID)
    local finalInstID = GetMapInstanceID(finalStep.mapID)

    -- 1. Если игрок уже в целевой зоне или на том же континенте/макро-регионе, что и финальная цель
    if playerMapID == finalStep.mapID
        or playerRegion == finalRegion
        or (playerInstID and finalInstID and playerInstID == finalInstID and playerRegion == finalRegion)
    then
        if route.currentStep ~= #route.steps then
            route.currentStep = #route.steps
            self:ActivateCurrentRouteStep(false)
        end
        return
    end

    -- 2. Ищем самый дальний промежуточный шаг маршрута, в регионе или карте которого оказался игрок
    for i = #route.steps, 1, -1 do
        local st = route.steps[i]
        local stRegion = GetMapMacroRegion(st.mapID)
        if playerMapID == st.mapID or playerMapID == st.subMapID or playerRegion == stRegion then
            if i > route.currentStep then
                route.currentStep = i
                self:ActivateCurrentRouteStep(false)
            elseif i == route.currentStep and st.isCapitalPortalRoom then
                local nowInside = IsPlayerInsideCapitalPortalRoom()
                if nowInside ~= (route.wasInsidePortalRoom == true) then
                    route.wasInsidePortalRoom = nowInside
                    self:ActivateCurrentRouteStep(false)
                end
            end
            return
        end
    end
end

-- Защита от «зомби-метки»: если игрок вручную снял метку на карте или начал отслеживать другой объект
-- (квест, рарника, ящик с военными припасами), мгновенно сбрасываем activePortalRoute, чтобы метка не воскресала!
function addon:OnUserWaypointUpdated()
    if self.isSettingWaypoint or not self.activePortalRoute then return end
    if C_Map and C_Map.HasUserWaypoint and not C_Map.HasUserWaypoint() then
        self:ClearActivePortalRoute()
    elseif C_Map and C_Map.GetUserWaypoint then
        local ok, wp = pcall(C_Map.GetUserWaypoint)
        local route = self.activePortalRoute
        if ok and wp and route and route.activePinMapID then
            local pos = wp.position
            local wx, wy = nil, nil
            if pos then
                if type(pos.GetXY) == "function" then
                    wx, wy = pos:GetXY()
                else
                    wx, wy = pos.x, pos.y
                end
            end
            if wp.uiMapID ~= route.activePinMapID
                or (wx and route.activePinX and math.abs(wx - route.activePinX) > 0.005)
                or (wy and route.activePinY and math.abs(wy - route.activePinY) > 0.005)
            then
                self:ClearActivePortalRoute()
            end
        end
    end
end

function addon:InitWaypointHooks()
    if self.waypointHooksInitialized then return end
    self.waypointHooksInitialized = true
    if not _G.hooksecurefunc then return end

    if C_Map then
        if C_Map.ClearUserWaypoint then
            pcall(hooksecurefunc, C_Map, "ClearUserWaypoint", function()
                if not addon.isSettingWaypoint then
                    addon:ClearActivePortalRoute()
                end
            end)
        end
        if C_Map.SetUserWaypoint then
            pcall(hooksecurefunc, C_Map, "SetUserWaypoint", function()
                if not addon.isSettingWaypoint then
                    addon:ClearActivePortalRoute()
                end
            end)
        end
    end
    if C_SuperTrack then
        for _, fnName in ipairs({ "SetSuperTrackedVignette", "SetSuperTrackedContent", "SetSuperTrackedQuestID", "ClearAllSuperTracked" }) do
            if C_SuperTrack[fnName] then
                pcall(hooksecurefunc, C_SuperTrack, fnName, function()
                    if not addon.isSettingWaypoint then
                        addon:ClearActivePortalRoute()
                    end
                end)
            end
        end
    end
end

function addon:NavigateToTitle(title, openWorldMap)
    if not title then return end
    local tName = self:GetTitleCleanName(title)
    local tZone = self:GetTitleZoneName(title)

    if not title.mapID then
        if title.achID then
            self:OpenTitleAchievement(title)
        end
        return
    end

    if openWorldMap and _G.OpenWorldMap then
        pcall(OpenWorldMap, title.mapID)
    end

    local tx = title.x or 50.0
    local ty = title.y or 50.0
    local steps = self:BuildMultiHopRoute(title.mapID, tx, ty, tName, tZone, tName)
    self.activePortalRoute = {
        targetName = tName,
        targetMapID = title.mapID,
        steps = steps,
        currentStep = 1,
    }
    self:ActivateCurrentRouteStep(false)
end

-- Открытие достижения в стандартном окне Достижений Blizzard
function addon:OpenTitleAchievement(title, overrideAchID)
    local achID = overrideAchID or (title and title.achID)
    if not achID or achID <= 0 then return false end

    if not _G.AchievementFrame then
        if C_AddOns and C_AddOns.LoadAddOn then
            pcall(C_AddOns.LoadAddOn, "Blizzard_AchievementUI")
        elseif _G.UIParentLoadAddOn then
            pcall(UIParentLoadAddOn, "Blizzard_AchievementUI")
        end
    end

    if _G.OpenAchievementFrameToAchievement then
        pcall(OpenAchievementFrameToAchievement, achID)
    elseif _G.AchievementFrame then
        if _G.ShowUIPanel then pcall(ShowUIPanel, AchievementFrame) else AchievementFrame:Show() end
        if _G.AchievementFrame_SelectAchievement then
            pcall(AchievementFrame_SelectAchievement, achID)
        end
    end

    if _G.AchievementFrame and AchievementFrame:IsShown() then
        AchievementFrame:SetFrameStrata("DIALOG")
    end
    return true
end

-- Проверка и переключение отслеживания достижения в экранном трекере Blizzard
function addon:IsTitleTracked(title)
    if not title or not title.achID then return false end
    if C_ContentTracking and C_ContentTracking.IsTracking and Enum and Enum.ContentTrackingType then
        local ok, res = pcall(C_ContentTracking.IsTracking, Enum.ContentTrackingType.Achievement, title.achID)
        if ok then return res == true end
    end
    if _G.IsTrackedAchievement then
        local ok, res = pcall(IsTrackedAchievement, title.achID)
        if ok then return res == true end
    end
    return false
end

function addon:ToggleTrackTitleAchievement(title)
    if not title or not title.achID then return false end
    local currently = self:IsTitleTracked(title)
    if C_ContentTracking and Enum and Enum.ContentTrackingType then
        if currently and C_ContentTracking.StopTracking then
            pcall(C_ContentTracking.StopTracking, Enum.ContentTrackingType.Achievement, title.achID, Enum.ContentTrackingStopType and Enum.ContentTrackingStopType.Manual or 1)
            return false
        elseif not currently and C_ContentTracking.StartTracking then
            pcall(C_ContentTracking.StartTracking, Enum.ContentTrackingType.Achievement, title.achID)
            return true
        end
    end
    if currently and _G.RemoveTrackedAchievement then
        pcall(RemoveTrackedAchievement, title.achID)
        return false
    elseif not currently and _G.AddTrackedAchievement then
        pcall(AddTrackedAchievement, title.achID)
        return true
    end
    return currently
end

function addon:GetTitleWowheadURL(title)
    local sub = self:IsEnglish() and "" or "ru/"
    local base = "https://www.wowhead.com/" .. sub
    if title and title.achID and title.achID > 0 then
        return base .. "achievement=" .. tostring(title.achID)
    elseif title and title.questID and title.questID > 0 then
        return base .. "quest=" .. tostring(title.questID)
    elseif title and title.dbID and title.dbID > 0 then
        return base .. "title=" .. tostring(title.dbID)
    end
    return base .. "titles"
end
