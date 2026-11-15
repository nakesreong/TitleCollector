local _, addon = ...

-- ============================================================================
-- TitleCollector — AutoTitle.lua
-- Модуль умной автоматической смены званий по специализациям персонажа (1..4)
-- и типам контента (PvP, Рейд/Данж, Столица/Отдых).
-- Полностью отключаемый через настройку db.settings.enableAutoTitle!
-- ============================================================================

addon.lastAutoTitleEvalTime = 0

function addon:GetCharAutoRules()
    if not self.db then self:InitDB() end
    local key = self:GetCharKey()
    self.db.autoRules[key] = self.db.autoRules[key] or {
        specs = {},
        contexts = {},
    }
    return self.db.autoRules[key]
end

function addon:FormatAutoRuleValue(ruleVal)
    if not ruleVal then
        return self:L("AUTO_RULE_NONE")
    elseif ruleVal == "FAV" then
        return self:L("AUTO_RULE_FAV_RND")
    elseif type(ruleVal) == "number" then
        local t = self.TitleByMaskID and self.TitleByMaskID[ruleVal]
        if t then
            local col = self:IsTitleCollected(ruleVal) and "|cff00ff96" or "|cffff5555"
            return col .. self:GetTitleCleanName(t) .. "|r"
        end
    end
    return self:L("AUTO_RULE_NONE")
end

function addon:EvaluateAutoTitleRules(reason)
    if not self.db or not self.db.settings or not self.db.settings.enableAutoTitle then
        return
    end
    local now = GetTime and GetTime() or 0
    if (now - (self.lastAutoTitleEvalTime or 0)) < 1.0 and reason ~= "MANUAL" then
        return
    end
    self.lastAutoTitleEvalTime = now

    local rules = self:GetCharAutoRules()
    if not rules then return end

    local targetRule = nil

    -- 1. Приоритет контекста (PvP / Рейд или Данж / Столица и отдых)
    local inInstance, instType = IsInInstance()
    if inInstance and (instType == "pvp" or instType == "arena") and rules.contexts.PVP then
        targetRule = rules.contexts.PVP
    elseif inInstance and (instType == "raid" or instType == "party") and rules.contexts.RAID then
        targetRule = rules.contexts.RAID
    elseif IsResting and IsResting() and rules.contexts.CITY then
        targetRule = rules.contexts.CITY
    end

    -- 2. Если контекст не перекрыл, проверяем активную специализацию персонажа
    if not targetRule and _G.GetSpecialization then
        local specIdx = GetSpecialization()
        if specIdx and rules.specs and rules.specs[specIdx] then
            targetRule = rules.specs[specIdx]
        end
    end

    if not targetRule then return end

    if targetRule == "FAV" then
        self:EquipRandomFavorite(true)
    elseif type(targetRule) == "number" and targetRule > 0 then
        local curMask = (_G.GetCurrentTitle and GetCurrentTitle()) or -1
        if curMask ~= targetRule and self:IsTitleCollected(targetRule) then
            self:EquipTitle(targetRule, true)
        end
    end
end
