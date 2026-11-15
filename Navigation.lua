local _, addon = ...

-- ============================================================================
-- TitleCollector — Navigation.lua
-- Межконтинентальный портальный навигатор (3D Waypoint + SuperTrack + TomTom),
-- интеграция с журналом достижений Blizzard, трекером целей и ссылками Wowhead.
-- ============================================================================

local SafeNotSecret = addon.SafeNotSecret

addon.activePortalRoute = nil
addon.portalTomTomUids = {}

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

    if (playerRegion == targetRegion or (playerInstID and targetInstID and playerInstID == targetInstID and playerRegion == targetRegion))
        and playerRegion ~= "HARANDAR" and targetRegion ~= "HARANDAR"
        and playerRegion ~= "VOIDSTORM" and targetRegion ~= "VOIDSTORM"
        and playerRegion ~= "EMERALD_DREAM" and targetRegion ~= "EMERALD_DREAM"
    then
        table.insert(steps, { mapID = targetMapID, x = targetX, y = targetY, zone = targetZone, note = targetNote or targetName })
        return steps
    end

    local isAlliance = (UnitFactionGroup("player") == "Alliance")
    local capMapID   = isAlliance and 84 or 85
    local capName    = isAlliance and "Зал порталов Штормграда" or "Зал порталов Оргриммара"
    local capX       = isAlliance and 48.7 or 57.3
    local capY       = isAlliance and 88.1 or 89.7
    local capRegion  = isAlliance and "EASTERN_KINGDOMS" or "KALIMDOR"

    if playerRegion == "HARANDAR" then
        table.insert(steps, {
            mapID = 2413, x = 53.3, y = 55.5, subMapID = 2576, subX = 64.5, subY = 71.4,
            zone = "Харандар (Логово)", note = "Корнистый путь в леса Вечной Песни / Луносвет",
        })
        if targetRegion ~= "MIDNIGHT_QUELTHALAS" then
            table.insert(steps, {
                mapID = 2395, x = isAlliance and 52.6 or 52.5, y = isAlliance and 25.5 or 25.7,
                subMapID = 2393, subX = isAlliance and 52.6 or 52.2, subY = isAlliance and 64.5 or 65.2,
                zone = "Луносвет", note = isAlliance and "Зал с порталами Луносвета: Портал в Штормград" or "Зал с порталами Луносвета: Портал в Оргриммар",
            })
        end
    elseif playerRegion == "MIDNIGHT_QUELTHALAS" then
        table.insert(steps, {
            mapID = 2395, x = isAlliance and 52.6 or 52.5, y = isAlliance and 25.5 or 25.7,
            subMapID = 2393, subX = isAlliance and 52.6 or 52.2, subY = isAlliance and 64.5 or 65.2,
            zone = "Луносвет", note = isAlliance and "Зал с порталами Луносвета: Портал в Штормград" or "Зал с порталами Луносвета: Портал в Оргриммар",
        })
    elseif playerRegion == "KHAZ_ALGAR" then
        table.insert(steps, {
            mapID = 2339, x = 41.9, y = 28.3, zone = "Дорногал",
            note = isAlliance and "Комната порталов Дорногала: Портал в Штормград" or "Комната порталов Дорногала: Портал в Оргриммар",
        })
    elseif playerRegion == "DRAGON_ISLES" then
        table.insert(steps, {
            mapID = 2112, x = 57.9, y = 35.3, zone = "Вальдраккен",
            note = "Престол Аспектов (Вальдраккен): Портал в столицу",
        })
    elseif playerRegion == "SHADOWLANDS" then
        table.insert(steps, {
            mapID = 1670, x = 22.4, y = 50.2, zone = "Орибос",
            note = "Портал в столицу (Кольцо Судеб, Орибос)",
        })
    elseif playerRegion == "PANDARIA" then
        table.insert(steps, {
            mapID = 371, x = isAlliance and 46.2 or 28.5, y = isAlliance and 85.2 or 14.0, zone = "Нефритовый лес",
            note = isAlliance and "Портал в Штормград (Деревня Лап'дон)" or "Портал в Оргриммар (Деревня Медовой Росы)",
        })
    end

    if targetRegion ~= capRegion then
        local skipCapStep = (playerRegion == "HARANDAR" and targetRegion == "MIDNIGHT_QUELTHALAS")
        if not skipCapStep then
            table.insert(steps, {
                mapID = capMapID, x = capX, y = capY,
                zone = isAlliance and "Штормград" or "Оргриммар",
                note = capName .. " -> Портал в целевой континент",
            })
        end
    end

    if targetRegion == "HARANDAR" and playerRegion ~= "HARANDAR" then
        table.insert(steps, {
            mapID = 2395, x = 47.9, y = 26.6, subMapID = 2393, subX = 36.7, subY = 68.2,
            zone = "Луносвет (Сады Памяти)", note = "Корнистый путь в Харандар (36.7, 68.2)",
        })
    end

    table.insert(steps, {
        mapID = targetMapID, x = targetX, y = targetY,
        zone = targetZone, note = targetNote or targetName,
    })
    return steps
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

    local totalSteps = #route.steps
    local isEN = self:IsEnglish()
    local stepLabel = totalSteps > 1
        and string.format(isEN and "[Step %d/%d] %s" or "[Шаг %d/%d] %s", route.currentStep, totalSteps, step.note or route.targetName)
        or string.format("TitleCollector: %s", route.targetName)

    if _G.TomTom and _G.TomTom.AddWaypoint then
        local ok, uid = pcall(_G.TomTom.AddWaypoint, _G.TomTom, step.mapID, step.x / 100, step.y / 100, {
            title = stepLabel, persistent = false, minimap = true, world = true, crazy = true,
        })
        if ok and uid then table.insert(self.portalTomTomUids, uid) end
    end

    if C_Map and C_Map.SetUserWaypoint and _G.UiMapPoint and _G.UiMapPoint.CreateFromCoordinates then
        local pinMapID, pinX, pinY = ResolvePinnableMapCoords(step.mapID, step.x / 100, step.y / 100)
        local okCan, canSet = pcall(C_Map.CanSetUserWaypointOnMap, pinMapID)
        if not okCan or canSet then
            local uiPt = UiMapPoint.CreateFromCoordinates(pinMapID, pinX, pinY)
            pcall(C_Map.SetUserWaypoint, uiPt)
            if C_SuperTrack and C_SuperTrack.SetSuperTrackedUserWaypoint then
                pcall(C_SuperTrack.SetSuperTrackedUserWaypoint, true)
            end
        end
    end

    if not silent then
        local zoneName = step.zone or self:L("UNKNOWN_ZONE")
        print(string.format(
            isEN
                and "|cffffd100[TitleCollector]|r Route plotted to |cff00ccff%s|r: %s (%.1f, %.1f)"
                or "|cffffd100[TitleCollector]|r Проложен путь к |cff00ccff%s|r: %s (%.1f, %.1f)",
            route.targetName, zoneName, step.x or 50, step.y or 50
        ))
    end
end

function addon:CheckPortalRouteProgress()
    local route = self.activePortalRoute
    if not route or not route.steps or #route.steps == 0 then return end
    local playerMapID = C_Map and C_Map.GetBestMapForUnit and C_Map.GetBestMapForUnit("player")
    if not playerMapID then return end

    local finalStep = route.steps[#route.steps]
    if playerMapID == finalStep.mapID then
        if route.currentStep ~= #route.steps then
            route.currentStep = #route.steps
            self:ActivateCurrentRouteStep(false)
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
