local _, addon = ...

-- ============================================================================
-- TitleCollector — ProgressEngine.lua
-- Движок живого расчёта прогресса получения званий (0% - 100%):
--   1. Достижения и 2-уровневые Мета-достижения (GetAchievementNumCriteria + assetID)
--   2. Известность Отряда (C_MajorFactions) и Классические Репутации (C_Reputation)
--   3. Задания и цепочки квестов (C_QuestLog.IsQuestFlaggedCompleted)
--   4. Событийный кэш (0 нагрузки на FPS в бою, пересчёт только при событиях прогресса)
-- ============================================================================

local SafeNotSecret = addon.SafeNotSecret

addon.ProgressCache = {}

function addon:InvalidateProgressCache()
    wipe(self.ProgressCache)
end

-- Оценка прогресса под-достижения (1 уровень вглубь для Мета-ачивок)
local function EvaluateSubAchievementFraction(subAchID)
    if not subAchID or subAchID <= 0 or not _G.GetAchievementInfo then
        return 0, 0, 0
    end
    local ok, _, _, _, completed = pcall(GetAchievementInfo, subAchID)
    if not ok then return 0, 0, 0 end
    if completed then return 1.0, 1, 1 end

    local okNum, numCrit = pcall(GetAchievementNumCriteria, subAchID)
    if not okNum or not numCrit or numCrit <= 0 then
        return 0, 0, 1
    end

    local doneWeight = 0
    for i = 1, numCrit do
        local okC, _, _, critCompleted, qty, reqQty = pcall(GetAchievementCriteriaInfo, subAchID, i)
        if okC then
            if critCompleted then
                doneWeight = doneWeight + 1.0
            elseif type(qty) == "number" and type(reqQty) == "number" and reqQty > 1 and qty > 0 then
                doneWeight = doneWeight + math.min(0.99, qty / reqQty)
            end
        end
    end
    return doneWeight / numCrit, math.floor(doneWeight + 0.001), numCrit
end

-- Оценка прогресса фракции (Renown / MajorFaction или классическая репутация)
local function EvaluateFactionProgress(factionID, reqStanding, reqRenown)
    if not factionID or factionID <= 0 then return nil end

    -- 1. Проверяем Major Faction (Известность Dragonflight / TWW / Midnight)
    if C_MajorFactions and C_MajorFactions.GetMajorFactionData then
        local okM, data = pcall(C_MajorFactions.GetMajorFactionData, factionID)
        if okM and data and type(data.renownLevel) == "number" then
            local targetRenown = reqRenown or data.maxLevel or 25
            local curRenown = data.renownLevel or 0
            local earned = data.renownReputationEarned or 0
            local thresh = (data.renownLevelThreshold and data.renownLevelThreshold > 0) and data.renownLevelThreshold or 2500
            local frac = math.min(1.0, (curRenown + (earned / thresh)) / math.max(1, targetRenown))
            local isDone = (curRenown >= targetRenown)
            local name = (SafeNotSecret(data.name) and data.name) or ("Faction #" .. tostring(factionID))
            local label = string.format("%s: Renown %d / %d", name, curRenown, targetRenown)
            return {
                pct = isDone and 100.0 or (frac * 100.0),
                completed = isDone,
                text = label,
                quantity = curRenown,
                reqQuantity = targetRenown,
            }
        end
    end

    -- 2. Проверяем классическую репутацию (C_Reputation.GetFactionDataByID)
    if C_Reputation and C_Reputation.GetFactionDataByID then
        local okF, fdata = pcall(C_Reputation.GetFactionDataByID, factionID)
        if okF and fdata and type(fdata.reaction) == "number" then
            local targetReaction = reqStanding or 8 -- 8 = Exalted (Превознесение)
            local reaction = fdata.reaction
            local isDone = (reaction >= targetReaction)
            local curVal = (fdata.currentStanding or 0) - (fdata.currentReactionThreshold or 0)
            local maxVal = (fdata.nextReactionThreshold or 1) - (fdata.currentReactionThreshold or 0)
            local stageFrac = (maxVal > 0) and math.max(0, math.min(1, curVal / maxVal)) or 0
            -- Базовый прогресс по уровням отношения (4=Neutral .. 8=Exalted)
            local baseStages = math.max(1, targetReaction - 4)
            local curStage = math.max(0, reaction - 4) + stageFrac
            local totalPct = isDone and 100.0 or math.min(99.0, (curStage / baseStages) * 100.0)
            local fname = (SafeNotSecret(fdata.name) and fdata.name) or ("Faction #" .. tostring(factionID))
            local standingLabel = _G["FACTION_STANDING_LABEL" .. tostring(reaction)] or tostring(reaction)
            local targetLabel = _G["FACTION_STANDING_LABEL" .. tostring(targetReaction)] or "Exalted"
            return {
                pct = totalPct,
                completed = isDone,
                text = string.format("%s: %s (%d / %d -> %s)", fname, standingLabel, math.max(0, curVal), math.max(1, maxVal), targetLabel),
                quantity = math.max(0, curVal),
                reqQuantity = math.max(1, maxVal),
            }
        end
    end

    return nil
end

function addon:EvaluateTitleProgress(title, forceRefresh)
    if not title or not title.maskID then
        return { isCollected = false, pct = 0, doneCount = 0, totalCount = 0, criteria = {} }
    end

    if not forceRefresh and self.ProgressCache[title.maskID] then
        return self.ProgressCache[title.maskID]
    end

    local isCollected = self:IsTitleCollected(title.maskID)
    local criteria = {}
    local totalWeight = 0
    local earnedWeight = 0
    local doneCount = 0
    local totalCount = 0

    -- 1. Достижение и его критерии (включая Мета-ачивки)
    if title.achID and title.achID > 0 and _G.GetAchievementInfo then
        local okA, _, achName, _, achCompleted, _, _, _, achDesc = pcall(GetAchievementInfo, title.achID)
        if okA and achName then
            local okN, numCrit = pcall(GetAchievementNumCriteria, title.achID)
            numCrit = (okN and type(numCrit) == "number") and numCrit or 0

            if numCrit > 0 then
                for i = 1, numCrit do
                    local okC, critString, critType, critCompleted, qty, reqQty, _, _, assetID, qtyString = pcall(GetAchievementCriteriaInfo, title.achID, i)
                    if okC then
                        totalCount = totalCount + 1
                        totalWeight = totalWeight + 1.0
                        local cText = (SafeNotSecret(critString) and critString and critString ~= "") and critString or nil
                        local subAchID = (critType == 8 and type(assetID) == "number" and assetID > 0) and assetID or nil
                        if not cText and subAchID then
                            local okSub, _, subName = pcall(GetAchievementInfo, subAchID)
                            if okSub and SafeNotSecret(subName) and subName then
                                cText = subName
                            end
                        end
                        cText = cText or ("Step #" .. tostring(i))

                        local itemPct = 0
                        local progressSuffix = nil
                        if critCompleted or achCompleted or isCollected then
                            critCompleted = true
                            doneCount = doneCount + 1
                            earnedWeight = earnedWeight + 1.0
                            itemPct = 100.0
                        elseif subAchID then
                            local subFrac, subDone, subTot = EvaluateSubAchievementFraction(subAchID)
                            earnedWeight = earnedWeight + subFrac
                            itemPct = subFrac * 100.0
                            if subTot > 1 then
                                progressSuffix = string.format("[%d/%d]", subDone, subTot)
                            end
                        elseif type(qty) == "number" and type(reqQty) == "number" and reqQty > 1 then
                            local frac = math.max(0, math.min(0.99, qty / reqQty))
                            earnedWeight = earnedWeight + frac
                            itemPct = frac * 100.0
                            progressSuffix = string.format("(%d / %d)", qty, reqQty)
                        elseif SafeNotSecret(qtyString) and type(qtyString) == "string" and qtyString ~= "" and qtyString ~= "0" then
                            progressSuffix = "(" .. qtyString .. ")"
                        end

                        table.insert(criteria, {
                            index = i,
                            text = progressSuffix and (cText .. " |cff88ccff" .. progressSuffix .. "|r") or cText,
                            rawText = cText,
                            completed = critCompleted == true,
                            pct = itemPct,
                            quantity = qty,
                            reqQuantity = reqQty,
                            subAchID = subAchID,
                        })
                    end
                end
            else
                -- Одношаговое достижение без под-критериев
                totalCount = 1
                totalWeight = 1.0
                local done = (achCompleted == true or isCollected)
                if done then
                    doneCount = 1
                    earnedWeight = 1.0
                end
                local cleanAch = (SafeNotSecret(achName) and achName) or self:GetTitleCleanName(title)
                local cleanDesc = (SafeNotSecret(achDesc) and achDesc and achDesc ~= "") and (" — " .. achDesc) or ""
                table.insert(criteria, {
                    index = 1,
                    text = cleanAch .. cleanDesc,
                    rawText = cleanAch,
                    completed = done,
                    pct = done and 100.0 or 0.0,
                    subAchID = title.achID,
                })
            end
        end
    end

    -- 2. Репутация / Известность (если задана factionID)
    if title.factionID and title.factionID > 0 then
        local fProg = EvaluateFactionProgress(title.factionID, title.reqStanding, title.reqRenown)
        if fProg then
            totalCount = totalCount + 1
            totalWeight = totalWeight + 1.0
            local fDone = fProg.completed or isCollected
            if fDone then
                doneCount = doneCount + 1
                earnedWeight = earnedWeight + 1.0
            else
                earnedWeight = earnedWeight + (fProg.pct / 100.0)
            end
            table.insert(criteria, 1, {
                index = 0,
                text = fProg.text,
                rawText = fProg.text,
                completed = fDone,
                pct = fDone and 100.0 or fProg.pct,
                quantity = fProg.quantity,
                reqQuantity = fProg.reqQuantity,
                isFaction = true,
            })
        end
    end

    -- 3. Задание (если задано questID)
    if title.questID and title.questID > 0 and C_QuestLog and C_QuestLog.IsQuestFlaggedCompleted then
        local okQ, qDone = pcall(C_QuestLog.IsQuestFlaggedCompleted, title.questID)
        qDone = (okQ and qDone == true) or isCollected
        totalCount = totalCount + 1
        totalWeight = totalWeight + 1.0
        if qDone then
            doneCount = doneCount + 1
            earnedWeight = earnedWeight + 1.0
        end
        local qName = (self:IsEnglish() and title.questName_en or title.questName_ru) or ("Quest #" .. tostring(title.questID))
        table.insert(criteria, {
            index = #criteria + 1,
            text = string.format("%s (#%d)", qName, title.questID),
            rawText = qName,
            completed = qDone,
            pct = qDone and 100.0 or 0.0,
            questID = title.questID,
        })
    end

    local finalPct = 0.0
    if isCollected then
        finalPct = 100.0
    elseif totalWeight > 0 then
        finalPct = math.min(99.4, (earnedWeight / totalWeight) * 100.0)
    end

    local result = {
        isCollected = isCollected,
        pct = finalPct,
        doneCount = doneCount,
        totalCount = totalCount,
        criteria = criteria,
    }
    self.ProgressCache[title.maskID] = result
    return result
end

function addon:GetOverallCollectionStats()
    local collected, totalObtainable, almostDoneCount = 0, 0, 0
    local hideUnobtainable = self.db and self.db.settings and self.db.settings.hideUnobtainable
    local hideOppFac = self.db and self.db.settings and self.db.settings.hideOppositeFaction

    for _, t in ipairs(self.Titles) do
        if not hideOppFac or self:IsTitleRelevantForPlayerFaction(t) then
            local isCol = self:IsTitleCollected(t.maskID)
            if isCol then
                collected = collected + 1
                totalObtainable = totalObtainable + 1
            elseif t.obtainable or not hideUnobtainable then
                totalObtainable = totalObtainable + 1
                local prog = self:EvaluateTitleProgress(t)
                if prog and prog.pct >= 70.0 then
                    almostDoneCount = almostDoneCount + 1
                end
            end
        end
    end
    return collected, math.max(collected, totalObtainable), almostDoneCount
end
