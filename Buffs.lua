local addonName, ns = ...

local BUFF_SIZE = 16 -- Size of the icon
local BUFF_GAP  = 3
local BUFF_OFFSET_Y = -1
local DEBUFF_GAP_X = 8 -- Gap between the buff row and the debuff row
local URGENT_TIME = 5 -- Time threshold for urgent countdown display (in seconds)
local MAX_SUPPORTED_SLOTS = ns.MAX_SUPPORTED_SLOTS -- Reserve maximum slots

local GetTime = GetTime
local ceil = math.ceil

-- Font settings
local FONT_FILE = "Fonts\\FRIZQT__.TTF" -- Standard WoW interface font
local FONT_NORMAL_SIZE = 10
local FONT_URGENT_SIZE = 13

local TEXT_STYLES = {
    normal = {
        size = FONT_NORMAL_SIZE,
        r = 1,
        g = 0.82,
        b = 0
    },
    urgent = {
        size = FONT_URGENT_SIZE,
        r = 1,
        g = 0,
        b = 0
    },
    stacks = {
        size = FONT_NORMAL_SIZE,
        r = 0.4,
        g = 1,
        b = 0.4
    }
}

-- Sorting weights for debuffs (Magic is usually highest priority for healers)
local DEBUFF_ORDER = {
    ["Magic"]   = 1,
    ["Curse"]   = 2,
    ["Poison"]  = 3,
    ["Disease"] = 4,
}

local auraRows = {}
local previousBuffs = {}

local function SetBuffTextStyle(slot, styleName)
    if slot.textStyle == styleName then
        return
    end

    slot.textStyle = styleName
    local style = TEXT_STYLES[styleName]

    slot.buffText:SetFont(
        FONT_FILE,
        style.size,
        "OUTLINE"
    )
    slot.buffText:SetTextColor(
        style.r,
        style.g,
        style.b
    )
end

-- -----------------------------------------------------------------------
-- Centralized aura timer (called from the main file)
-- -----------------------------------------------------------------------
function ns.UpdateAllBuffTimers()
    local now = GetTime()
    
    for unitID, auraGroup in pairs(auraRows) do
        -- Update Buffs
        if auraGroup.buffs.frame:IsVisible() then
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = auraGroup.buffs.slots[i]
                if slot:IsVisible() and slot.isTimerActive and slot.expirationTime and slot.expirationTime > 0 then
                    local remain = slot.expirationTime - now
                    if remain <= 0 then
                        slot.expirationTime = 0
                        slot.isTimerActive = false
                        slot.lastSec = -1
                        slot.buffText:SetText("")
                    else
                        local currentSec = ceil(remain)
                        if currentSec ~= slot.lastSec then
                            slot.lastSec = currentSec
                            
                            if remain <= URGENT_TIME then
                                if slot.textStyle ~= "urgent" then SetBuffTextStyle(slot, "urgent") end
                            elseif slot.textStyle == "urgent" then
                                SetBuffTextStyle(slot, "normal")
                            end

                            if remain <= 20 then
                                slot.buffText:SetText(currentSec)
                            else
                                slot.buffText:SetText("")
                            end
                        end
                    end
                end
            end
        end

        -- Update Debuffs
        if auraGroup.debuffs.frame:IsVisible() then
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = auraGroup.debuffs.slots[i]
                if slot:IsVisible() and slot.isTimerActive and slot.expirationTime and slot.expirationTime > 0 then
                    local remain = slot.expirationTime - now
                    if remain <= 0 then
                        slot.expirationTime = 0
                        slot.isTimerActive = false
                        slot.lastSec = -1
                        slot.buffText:SetText("")
                    else
                        local currentSec = ceil(remain)
                        if currentSec ~= slot.lastSec then
                            slot.lastSec = currentSec
                            
                            if remain <= URGENT_TIME then
                                if slot.textStyle ~= "urgent" then SetBuffTextStyle(slot, "urgent") end
                            elseif slot.textStyle == "urgent" then
                                SetBuffTextStyle(slot, "normal")
                            end

                            if remain <= 20 then
                                slot.buffText:SetText(currentSec)
                            else
                                slot.buffText:SetText("")
                            end
                        end
                    end
                end
            end
        end
    end
end

local function CreateAuraSlot(parent, unitID, isDebuff)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(BUFF_SIZE, BUFF_SIZE)
    slot.unitID = unitID
    slot.isDebuff = isDebuff

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.icon = icon

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    cd:SetDrawEdge(true)
    slot.cd = cd

    -- Create a separate frame for texts to raise it above the cooldown shadow
    local textFrame = CreateFrame("Frame", nil, slot)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(cd:GetFrameLevel() + 2)

    -- Text for timer and spell stacks
    local buffText = textFrame:CreateFontString(nil, "OVERLAY")
    buffText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    slot.buffText = buffText
    SetBuffTextStyle(slot, "normal")

    slot.hasStacks = false
    slot.isTimerActive = false
    slot.lastSec = -1 

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
        if not HealcraftDB.settings.showTooltipsBuffs then return end
        
        if self.auraIndex then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 15, -25)
            if self.isDebuff then
                GameTooltip:SetUnitDebuff(self.unitID, self.auraIndex)
            else
                GameTooltip:SetUnitBuff(self.unitID, self.auraIndex)
            end
        end
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return slot
end

function ns.CreateBuffRow(unitID)
    if auraRows[unitID] then return end

    local memberIndex = string.match(unitID, "%d+")
    local manaBar = _G["PartyMemberFrame" .. memberIndex .. "ManaBar"]
    if not manaBar then return end

    local parentFrame = manaBar:GetParent()

    -- 1. Create Row for Beneficial Buffs (Player's spells)
    local buffRow = CreateFrame("Frame", addonName .. "BuffRow_" .. unitID, parentFrame)
    buffRow:SetSize((BUFF_SIZE + BUFF_GAP) * MAX_SUPPORTED_SLOTS, BUFF_SIZE)
    buffRow:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, BUFF_OFFSET_Y)
    buffRow:SetFrameLevel(parentFrame:GetFrameLevel() + 5)

    local buffSlots = {}
    for i = 1, MAX_SUPPORTED_SLOTS do
        local slot = CreateAuraSlot(buffRow, unitID, false)
        if i == 1 then
            slot:SetPoint("LEFT", buffRow, "LEFT", 0, 0)
        else
            slot:SetPoint("LEFT", buffSlots[i-1], "RIGHT", BUFF_GAP, 0)
        end
        slot:Hide()
        buffSlots[i] = slot
    end

    -- 2. Create Row for Harmful Debuffs (Curses, Diseases, etc.) aligned horizontally to the right
    local debuffRow = CreateFrame("Frame", addonName .. "DebuffRow_" .. unitID, parentFrame)
    debuffRow:SetSize((BUFF_SIZE + BUFF_GAP) * MAX_SUPPORTED_SLOTS, BUFF_SIZE)
    debuffRow:SetPoint("LEFT", buffRow, "RIGHT", DEBUFF_GAP_X, 0) -- Anchored to the right of the buff row
    debuffRow:SetFrameLevel(parentFrame:GetFrameLevel() + 5)

    local debuffSlots = {}
    for i = 1, MAX_SUPPORTED_SLOTS do
        local slot = CreateAuraSlot(debuffRow, unitID, true)
        if i == 1 then
            slot:SetPoint("LEFT", debuffRow, "LEFT", 0, 0)
        else
            slot:SetPoint("LEFT", debuffSlots[i-1], "RIGHT", BUFF_GAP, 0)
        end
        slot:Hide()
        debuffSlots[i] = slot
    end

    auraRows[unitID] = {
        buffs = { frame = buffRow, slots = buffSlots },
        debuffs = { frame = debuffRow, slots = debuffSlots }
    }
    previousBuffs[unitID] = {}
end

function ns.UpdateBuffs(unitID)
    if not unitID or not auraRows[unitID] then return end
    local rowGroup = auraRows[unitID]
    local settings = HealcraftDB.settings
    
    rowGroup.buffs.frame:SetAlpha(settings.alphaBuffs / 100)
    rowGroup.debuffs.frame:SetAlpha(settings.alphaBuffs / 100)
    
    -- Hide all if addon or feature is disabled
    if not ns.IsActive() or not settings.buffsActive then
        for i = 1, MAX_SUPPORTED_SLOTS do
            rowGroup.buffs.slots[i]:Hide()
            rowGroup.buffs.slots[i].expirationTime = 0
            rowGroup.buffs.slots[i].isTimerActive = false

            rowGroup.debuffs.slots[i]:Hide()
            rowGroup.debuffs.slots[i].expirationTime = 0
            rowGroup.debuffs.slots[i].isTimerActive = false
        end
        previousBuffs[unitID] = {}
        return
    end

    local activeSpells = ns.GetActiveSpells(unitID)
    local currentBuffs = {}

    -- Temporary collections to store filtered auras
    local tempBuffs = {}
    local tempDebuffs = {}

    -- Combined single loop to scan both Buffs and Debuffs simultaneously
    for i = 1, 40 do
        local bName, _, bIcon, bStacks, _, bDuration, bExpirationTime, bUnitCaster = UnitBuff(unitID, i)
        local dName, _, dIcon, dStacks, dDebuffType, dDuration, dExpirationTime, dUnitCaster = UnitDebuff(unitID, i)

        -- If both lists are fully exhausted, we can safely terminate the loop early (massive CPU saving)
        if not bName and not dName then
            break
        end

        -- Filter and collect Beneficial Buffs
        if bName and activeSpells[bName] and bUnitCaster == "player" then
            currentBuffs[bName] = true
            table.insert(tempBuffs, {
                name = bName,
                icon = bIcon,
                stacks = bStacks,
                duration = bDuration,
                expirationTime = bExpirationTime,
                index = i
            })
        end

        -- Filter and collect Harmful Debuffs
        if dName then
            local isAllowed = false
            if dDebuffType == "Curse" and settings.showCurses then
                isAllowed = true
            elseif dDebuffType == "Poison" and settings.showPoisons then
                isAllowed = true
            elseif dDebuffType == "Disease" and settings.showDiseases then
                isAllowed = true
            elseif dDebuffType == "Magic" and settings.showMagic then
                isAllowed = true
            end

            if isAllowed then
                table.insert(tempDebuffs, {
                    name = dName,
                    icon = dIcon,
                    stacks = dStacks,
                    debuffType = dDebuffType,
                    duration = dDuration,
                    expirationTime = dExpirationTime,
                    index = i
                })
            end
        end
    end

    -- Sort debuffs by their type weight (Magic -> Curse -> Poison -> Disease)
    table.sort(tempDebuffs, function(a, b)
        local weightA = DEBUFF_ORDER[a.debuffType] or 5
        local weightB = DEBUFF_ORDER[b.debuffType] or 5
        return weightA < weightB
    end)

    -- -----------------------------------------------------------------------
    -- Render Beneficial Buffs
    -- -----------------------------------------------------------------------
    local buffIndex = 1
    for _, buffData in ipairs(tempBuffs) do
        local slot = rowGroup.buffs.slots[buffIndex]
        if slot then
            slot.icon:SetTexture(buffData.icon)
            slot.auraIndex = buffData.index
            slot.lastSec = -1

            local showStacks = (buffData.stacks and buffData.stacks > 1 and settings.showStacks)
            local showTimer  = (buffData.duration and buffData.duration > 0 and buffData.expirationTime and not showStacks and settings.showTimer)

            if showStacks then
                slot.buffText:SetText("x"..buffData.stacks)
                slot.hasStacks = true
                SetBuffTextStyle(slot, "stacks")
                slot.isTimerActive = false
            else
                slot.hasStacks = false
                if not showTimer then slot.buffText:SetText("") end
            end

            if buffData.duration and buffData.duration > 0 and buffData.expirationTime then
                slot.isTimerActive = showTimer
                if slot.expirationTime ~= buffData.expirationTime then
                    local start = buffData.expirationTime - buffData.duration
                    CooldownFrame_SetTimer(slot.cd, start, buffData.duration, 1)
                    slot.expirationTime = buffData.expirationTime
                end
                
                local remain = buffData.expirationTime - GetTime()
                if remain > URGENT_TIME and showTimer then
                    SetBuffTextStyle(slot, "normal")
                end
            else
                slot.cd:Hide()
                slot.expirationTime = 0
                slot.isTimerActive = false
                slot.buffText:SetText("")
            end

            slot:Show()
            buffIndex = buffIndex + 1
        end

        if buffIndex > settings.slotsCount then break end
    end

    -- Trigger button flashes on the main panel if player's buff faded
    if previousBuffs[unitID] then
        for oldSpellName, _ in pairs(previousBuffs[unitID]) do
            if not currentBuffs[oldSpellName] then
                if ns.FlashSpellSlot then
                    ns.FlashSpellSlot(unitID, oldSpellName)
                end
            end
        end
    end
    previousBuffs[unitID] = currentBuffs

    -- Hide unused buff slots
    for i = buffIndex, MAX_SUPPORTED_SLOTS do
        local slot = rowGroup.buffs.slots[i]
        slot:Hide()
        slot.expirationTime = 0
        slot.isTimerActive = false
        slot.buffText:SetText("")
    end

    -- -----------------------------------------------------------------------
    -- Render Harmful Debuffs
    -- -----------------------------------------------------------------------
    local debuffIndex = 1
    for _, debuffData in ipairs(tempDebuffs) do
        local slot = rowGroup.debuffs.slots[debuffIndex]
        if slot then
            slot.icon:SetTexture(debuffData.icon)
            slot.auraIndex = debuffData.index
            slot.lastSec = -1

            local showStacks = (debuffData.stacks and debuffData.stacks > 1 and settings.showStacks)
            local showTimer  = (debuffData.duration and debuffData.duration > 0 and debuffData.expirationTime and not showStacks and settings.showTimer)

            if showStacks then
                slot.buffText:SetText("x"..debuffData.stacks)
                slot.hasStacks = true
                SetBuffTextStyle(slot, "stacks")
                slot.isTimerActive = false
            else
                slot.hasStacks = false
                if not showTimer then slot.buffText:SetText("") end
            end

            if debuffData.duration and debuffData.duration > 0 and debuffData.expirationTime then
                slot.isTimerActive = showTimer
                if slot.expirationTime ~= debuffData.expirationTime then
                    local start = debuffData.expirationTime - debuffData.duration
                    CooldownFrame_SetTimer(slot.cd, start, debuffData.duration, 1)
                    slot.expirationTime = debuffData.expirationTime
                end
                
                local remain = debuffData.expirationTime - GetTime()
                if remain > URGENT_TIME and showTimer then
                    SetBuffTextStyle(slot, "normal")
                end
            else
                slot.cd:Hide()
                slot.expirationTime = 0
                slot.isTimerActive = false
                slot.buffText:SetText("")
            end

            slot:Show()
            debuffIndex = debuffIndex + 1
        end

        if debuffIndex > settings.slotsCount then break end
    end

    -- Hide unused debuff slots
    for i = debuffIndex, MAX_SUPPORTED_SLOTS do
        local slot = rowGroup.debuffs.slots[i]
        slot:Hide()
        slot.expirationTime = 0
        slot.isTimerActive = false
        slot.buffText:SetText("")
    end
end

function ns.RefreshAllBuffs()
    for unitID in pairs(auraRows) do
        ns.UpdateBuffs(unitID)
    end
end