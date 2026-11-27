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

-- Исправление официальных опечаток локализации Blizzard в названиях под-достижений (ruRU)
local SUB_ACH_NAME_FIXES_RU = {
    [40086] = "Турне чемпиона: Каз Алгар",
    [40088] = "Турне чемпиона: Каз Алгар", -- В клиенте Blizzard для #40097 ошибочно скопировано «Турне чемпиона: Драконьи острова»
}

-- Оценка прогресса под-достижения (1 уровень вглубь для Мета-ачивок) + сбор незакрытых под-шагов
local function EvaluateSubAchievementFraction(subAchID)
    if not subAchID or subAchID <= 0 or not _G.GetAchievementInfo then
        return 0, 0, 0, nil
    end
    local ok, _, _, _, completed = pcall(GetAchievementInfo, subAchID)
    if not ok then return 0, 0, 0, nil end
    if completed then return 1.0, 1, 1, nil end

    local okNum, numCrit = pcall(GetAchievementNumCriteria, subAchID)
    if not okNum or not numCrit or numCrit <= 0 then
        return 0, 0, 1, nil
    end

    local doneWeight = 0
    local subSteps = {}
    for i = 1, numCrit do
        local okC, cStr, _, critCompleted, qty, reqQty = pcall(GetAchievementCriteriaInfo, subAchID, i)
        if okC then
            if critCompleted then
                doneWeight = doneWeight + 1.0
            else
                if type(qty) == "number" and type(reqQty) == "number" and reqQty > 1 and qty > 0 then
                    doneWeight = doneWeight + math.min(0.99, qty / reqQty)
                end
                local cleanSub = (SafeNotSecret(cStr) and type(cStr) == "string" and cStr ~= "") and cStr or nil
                if cleanSub then
                    local hasInlineCounter = string.find(cleanSub, "%d+%s*/%s*%d+") ~= nil
                    local qSuffix = ""
                    if not hasInlineCounter and type(qty) == "number" and type(reqQty) == "number" and reqQty > 1 then
                        qSuffix = string.format(" |cff88ccff(%d/%d)|r", qty, reqQty)
                    elseif hasInlineCounter then
                        cleanSub = string.gsub(cleanSub, "^(%d+%s*/%s*%d+)%s+", "|cff88ccff[%1]|r ")
                    end
                    table.insert(subSteps, {
                        text = cleanSub .. qSuffix,
                        rawText = cleanSub,
                        completed = false,
                        isSubStep = true,
                        subAchID = subAchID,
                    })
                end
            end
        end
    end
    return doneWeight / numCrit, math.floor(doneWeight + 0.001), numCrit, subSteps
end

local EN_STANDING_LABELS = {
    [1] = "Hated",
    [2] = "Hostile",
    [3] = "Unfriendly",
    [4] = "Neutral",
    [5] = "Friendly",
    [6] = "Honored",
    [7] = "Revered",
    [8] = "Exalted",
}

-- Оценка прогресса фракции (Renown / MajorFaction или классическая репутация)
local function EvaluateFactionProgress(factionID, reqStanding, reqRenown, title, isEN)
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
            local dbFacName = title and (isEN and title.facName_en or title.facName_ru)
            local name = (dbFacName and dbFacName ~= "" and dbFacName)
                or (SafeNotSecret(data.name) and data.name)
                or ("Faction #" .. tostring(factionID))
            local renownWord = isEN and "Renown" or "Известность"
            local label = string.format("%s: %s %d / %d", name, renownWord, curRenown, targetRenown)
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
            local dbFacName = title and (isEN and title.facName_en or title.facName_ru)
            local fname = (dbFacName and dbFacName ~= "" and dbFacName)
                or (SafeNotSecret(fdata.name) and fdata.name)
                or ("Faction #" .. tostring(factionID))
            local standingLabel = isEN
                and (EN_STANDING_LABELS[reaction] or tostring(reaction))
                or (_G["FACTION_STANDING_LABEL" .. tostring(reaction)] or tostring(reaction))
            local targetLabel = isEN
                and (EN_STANDING_LABELS[targetReaction] or "Exalted")
                or (_G["FACTION_STANDING_LABEL" .. tostring(targetReaction)] or "Exalted")
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

function addon:EvaluateTitleProgress(title, forceRefresh, summaryOnly)
    if not title or not title.maskID then
        return { isCollected = false, pct = 0, doneCount = 0, totalCount = 0, criteria = {} }
    end

    local cached = self.ProgressCache[title.maskID]
    if not forceRefresh and cached then
        if summaryOnly or not cached.summaryOnly then
            return cached
        end
    end

    local isCollected = self:IsTitleCollected(title.maskID)
    if isCollected and summaryOnly then
        local fastRes = {
            isCollected = true,
            pct = 100.0,
            doneCount = 1,
            totalCount = 1,
            criteria = (cached and not cached.summaryOnly and cached.criteria) or {},
            summaryOnly = (not cached or cached.summaryOnly == true),
        }
        if not cached or cached.summaryOnly or not cached.isCollected then
            self.ProgressCache[title.maskID] = fastRes
        end
        return self.ProgressCache[title.maskID]
    end

    local criteria = {}
    local totalWeight = 0
    local earnedWeight = 0
    local doneCount = 0
    local totalCount = 0

    local isEN = self:IsEnglish()
    local clientIsNonEN = ((GetLocale and GetLocale() or "enUS") == "ruRU")

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
                        local cText = (SafeNotSecret(critString) and critString and critString ~= "") and critString or nil
                        local subAchID = (critType == 8 and type(assetID) == "number" and assetID > 0) and assetID or nil
                        if not cText and subAchID then
                            local okSub, _, subName = pcall(GetAchievementInfo, subAchID)
                            if okSub and SafeNotSecret(subName) and subName then
                                cText = subName
                            end
                        end
                        if isEN and clientIsNonEN then
                            if subAchID and self.TitlesByAchID and self.TitlesByAchID[subAchID] and self.TitlesByAchID[subAchID].achName_en then
                                cText = self.TitlesByAchID[subAchID].achName_en
                            elseif numCrit == 1 and title.achName_en and title.achName_en ~= "" then
                                cText = title.achName_en
                            end
                        end
                        if subAchID and SUB_ACH_NAME_FIXES_RU[subAchID] and not isEN then
                            cText = SUB_ACH_NAME_FIXES_RU[subAchID]
                        elseif not isEN and cText and (title.exp or 0) >= 11 and string.find(cText, "Турне чемпиона: Драконьи острова", 1, true) then
                            cText = "Турне чемпиона: Каз Алгар"
                        elseif isEN and subAchID == 40088 then
                            cText = "A Champion's Tour: The War Within"
                        end
                        -- Если у ачивки 1 скрытый критерий без текста, а у звания уже задана factionID, не дублируем пустой "Step #1"
                        if not cText and numCrit == 1 and title.factionID and title.factionID > 0 then
                            cText = nil
                        elseif not cText and numCrit == 1 then
                            cText = (isEN and title.achName_en and title.achName_en ~= "" and title.achName_en)
                                or (SafeNotSecret(achName) and achName)
                                or ("Step #" .. tostring(i))
                        else
                            cText = cText or ("Step #" .. tostring(i))
                        end

                        if cText then
                            totalCount = totalCount + 1
                            totalWeight = totalWeight + 1.0

                            local itemPct = 0
                            local progressSuffix = nil
                            local childSteps = nil
                            if critCompleted or achCompleted or isCollected then
                                critCompleted = true
                                doneCount = doneCount + 1
                                earnedWeight = earnedWeight + 1.0
                                itemPct = 100.0
                            elseif subAchID then
                                local subFrac, subDone, subTot, subSteps = EvaluateSubAchievementFraction(subAchID)
                                earnedWeight = earnedWeight + subFrac
                                itemPct = subFrac * 100.0
                                childSteps = subSteps
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
                            if childSteps and #childSteps > 0 then
                                for _, cs in ipairs(childSteps) do
                                    table.insert(criteria, cs)
                                end
                            end
                        end
                    end
                end
            elseif not (title.currencyCost or title.itemCost) then
                -- Одношаговое достижение без под-критериев (когда нет отдельного счётчика валюты/предмета)
                totalCount = 1
                totalWeight = 1.0
                local done = (isCollected == true)
                if done then
                    doneCount = 1
                    earnedWeight = 1.0
                end
                local cleanAch = (isEN and title.achName_en and title.achName_en ~= "" and title.achName_en)
                    or (SafeNotSecret(achName) and achName)
                    or self:GetTitleCleanName(title)
                local rawDesc = (isEN and title.achDesc_en and title.achDesc_en ~= "" and title.achDesc_en)
                    or (SafeNotSecret(achDesc) and achDesc)
                    or ""
                local cleanDesc = (rawDesc ~= "") and (" — " .. rawDesc) or ""
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
        local fProg = EvaluateFactionProgress(title.factionID, title.reqStanding, title.reqRenown, title, isEN)
        if fProg then
            totalCount = totalCount + 1
            totalWeight = totalWeight + 1.0
            local hasFollowupCost = (title.goldCost ~= nil) or (title.currencyCost ~= nil) or (title.itemCost ~= nil)
            local fDone = isCollected or fProg.completed
            if fDone then
                doneCount = doneCount + 1
                earnedWeight = earnedWeight + ((isCollected or hasFollowupCost) and 1.0 or 0.97)
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

    -- 4. Валюта, предметы обмена в сумках/банке отряда и золото у торговцев
    if title.currencyID and title.currencyID > 0 and title.currencyCost and title.currencyCost > 0 and C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo then
        local okCur, cInfo = pcall(C_CurrencyInfo.GetCurrencyInfo, title.currencyID)
        if okCur and cInfo then
            local have = (SafeNotSecret(cInfo.quantity) and type(cInfo.quantity) == "number") and cInfo.quantity or 0
            local cost = title.currencyCost
            local cName = (SafeNotSecret(cInfo.name) and type(cInfo.name) == "string" and cInfo.name ~= "") and cInfo.name or ("Currency #" .. tostring(title.currencyID))
            if isEN and clientIsNonEN and title.currencyID == 1166 then
                cName = "Timewarped Badge"
            elseif not isEN and not clientIsNonEN and title.currencyID == 1166 then
                cName = "Искаженный временем знак"
            end
            local hasEnough = isCollected or (have >= cost)
            local frac = isCollected and 1.0 or (hasEnough and 0.97 or math.max(0, math.min(0.95, have / cost)))
            totalCount = totalCount + 1
            totalWeight = totalWeight + 1.0
            if hasEnough then
                doneCount = doneCount + 1
            end
            earnedWeight = earnedWeight + frac
            local readyTag = (not isCollected and have >= cost) and (" |cff00ff96[" .. self:L("CRIT_READY_TO_BUY") .. "]|r") or ""
            table.insert(criteria, {
                index = #criteria + 1,
                text = string.format("%s: |cff88ccff%d / %d|r%s", cName, have, cost, readyTag),
                rawText = cName,
                completed = hasEnough,
                pct = hasEnough and 100.0 or (frac * 100.0),
                quantity = have,
                reqQuantity = cost,
                isCurrency = true,
            })
        end
    end

    if title.itemID and title.itemID > 0 and title.itemCost and title.itemCost > 0 then
        local have = 0
        if C_Item and C_Item.GetItemCount then
            local okIt, cnt = pcall(C_Item.GetItemCount, title.itemID, true, false, true, true)
            if okIt and SafeNotSecret(cnt) and type(cnt) == "number" then
                have = cnt
            end
        elseif _G.GetItemCount then
            local okIt, cnt = pcall(_G.GetItemCount, title.itemID, true)
            if okIt and SafeNotSecret(cnt) and type(cnt) == "number" then
                have = cnt
            end
        end
        local cost = title.itemCost
        local iName = (isEN and title.itemName_en and title.itemName_en ~= "" and title.itemName_en)
            or (not isEN and title.itemName_ru and title.itemName_ru ~= "" and title.itemName_ru)
            or (C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(title.itemID))
            or ("Item #" .. tostring(title.itemID))
        local hasEnough = isCollected or (have >= cost)
        local frac = isCollected and 1.0 or (hasEnough and 0.97 or math.max(0, math.min(0.95, have / cost)))
        totalCount = totalCount + 1
        totalWeight = totalWeight + 1.0
        if hasEnough then
            doneCount = doneCount + 1
        end
        earnedWeight = earnedWeight + frac
        local readyTag = (not isCollected and have >= cost) and (" |cff00ff96[" .. self:L("CRIT_READY_TO_BUY") .. "]|r") or ""
        table.insert(criteria, {
            index = #criteria + 1,
            text = string.format("%s: |cff88ccff%d / %d|r%s", iName, have, cost, readyTag),
            rawText = iName,
            completed = hasEnough,
            pct = hasEnough and 100.0 or (frac * 100.0),
            quantity = have,
            reqQuantity = cost,
            isItemCost = true,
        })
    end

    if title.goldCost and title.goldCost > 0 and _G.GetMoney then
        local okM, rawCopper = pcall(GetMoney)
        local haveGold = (okM and SafeNotSecret(rawCopper) and type(rawCopper) == "number") and math.floor(rawCopper / 10000) or 0
        local costGold = title.goldCost
        local hasPriorPrereq = totalWeight > 0
        local gWeight = hasPriorPrereq and 0.15 or 1.0
        local hasEnough = isCollected or (haveGold >= costGold)
        local frac = isCollected and 1.0 or (hasEnough and (hasPriorPrereq and 1.0 or 0.97) or math.max(0, math.min(0.95, haveGold / costGold)))
        totalCount = totalCount + 1
        totalWeight = totalWeight + gWeight
        if hasEnough then
            doneCount = doneCount + 1
        end
        earnedWeight = earnedWeight + (frac * gWeight)
        local goldLabel = isEN and "Gold" or "Золото"
        local readyTag = (not isCollected and haveGold >= costGold and (not hasPriorPrereq or doneCount == totalCount))
            and (" |cff00ff96[" .. self:L("CRIT_READY_TO_BUY") .. "]|r")
            or ""
        table.insert(criteria, {
            index = #criteria + 1,
            text = string.format("%s: |cffffd100%d / %d|r |TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t%s", goldLabel, haveGold, costGold, readyTag),
            rawText = goldLabel,
            completed = hasEnough,
            pct = hasEnough and 100.0 or (frac * 100.0),
            quantity = haveGold,
            reqQuantity = costGold,
            isGoldCost = true,
        })
    end

    local finalPct = 0.0
    if isCollected then
        finalPct = 100.0
    elseif totalWeight > 0 then
        finalPct = math.min(99.4, (earnedWeight / totalWeight) * 100.0)
    end

    local isVendorSource = (title.cat == "Vendor")
        or (title.currencyCost ~= nil)
        or (title.itemCost ~= nil)
        or (title.goldCost ~= nil)
    local readyToBuy = (not isCollected)
        and (title.obtainable ~= false)
        and isVendorSource
        and (totalCount > 0)
        and (doneCount >= totalCount)

    local result = {
        isCollected = isCollected,
        pct = finalPct,
        doneCount = doneCount,
        totalCount = totalCount,
        readyToBuy = readyToBuy,
        criteria = criteria,
        summaryOnly = false,
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
                local prog = self:EvaluateTitleProgress(t, false, true)
                if prog and prog.pct >= 70.0 then
                    almostDoneCount = almostDoneCount + 1
                end
            end
        end
    end
    return collected, math.max(collected, totalObtainable), almostDoneCount
end
