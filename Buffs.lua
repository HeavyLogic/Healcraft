local addonName, ns = ...

local BUFF_SIZE = 16 -- at 19, built-in timer appears
local BUFF_GAP  = 3
local BUFF_OFFSET_Y = -1
local URGENT_TIME = 5
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

local buffRows = {}
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
-- Centralized buff timer (called from the main file)
-- -----------------------------------------------------------------------
function ns.UpdateAllBuffTimers()
    local now = GetTime()
    
    for unitID, rowData in pairs(buffRows) do
        -- Update timers only if the buff frame is currently visible on screen
        if rowData.frame:IsVisible() then
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = rowData.slots[i]
                
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
                            
                            -- Change text style to red (urgent)
                            if remain <= URGENT_TIME then
                                if slot.textStyle ~= "urgent" then
                                    SetBuffTextStyle(slot, "urgent")
                                end
                            elseif slot.textStyle == "urgent" then
                                SetBuffTextStyle(slot, "normal")
                            end

                            -- Show countdown digits only if 20 seconds or less remain
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

local function CreateBuffSlot(parent, unitID)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(BUFF_SIZE, BUFF_SIZE)
    slot.unitID = unitID

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    -- Slightly trim edges to remove the default gray border of 3.3.5 icons
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
    textFrame:SetFrameLevel(cd:GetFrameLevel() + 2) -- Set higher frame level than cd

    -- Text for timer and spell stacks
    local buffText = textFrame:CreateFontString(nil, "OVERLAY")
    buffText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    slot.buffText = buffText
    SetBuffTextStyle(slot, "normal")

    slot.hasStacks = false
    slot.isTimerActive = false -- Boolean flag instead of OnUpdate script
    slot.lastSec = -1 

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
        if not HealcraftDB.settings.showTooltipsBuffs then return end
        
        if self.buffIndex then
            GameTooltip:SetOwner(self, "ANCHOR_BOTTOMRIGHT", 15, -25)
            GameTooltip:SetUnitBuff(self.unitID, self.buffIndex)
        end
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    return slot
end

function ns.CreateBuffRow(unitID)
    if buffRows[unitID] then return end

    local memberIndex = string.match(unitID, "%d+")
    local manaBar = _G["PartyMemberFrame" .. memberIndex .. "ManaBar"]
    if not manaBar then return end

    -- Attach directly to the mana bar
    local row = CreateFrame("Frame", addonName .. "BuffRow_" .. unitID, manaBar:GetParent())
    row:SetSize((BUFF_SIZE + BUFF_GAP) * MAX_SUPPORTED_SLOTS, BUFF_SIZE)
    row:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, BUFF_OFFSET_Y)
    -- Raise level to avoid being overlapped by default frames
    row:SetFrameLevel(manaBar:GetParent():GetFrameLevel() + 5)

    local slots = {}
    for i = 1, MAX_SUPPORTED_SLOTS do
        local slot = CreateBuffSlot(row, unitID)
        if i == 1 then
            slot:SetPoint("LEFT", row, "LEFT", 0, 0)
        else
            slot:SetPoint("LEFT", slots[i-1], "RIGHT", BUFF_GAP, 0)
        end
        slot:Hide()
        slots[i] = slot
    end

    buffRows[unitID] = { frame = row, slots = slots }
    previousBuffs[unitID] = {}
end

function ns.UpdateBuffs(unitID)
    if not unitID or not buffRows[unitID] then return end
    local rowData = buffRows[unitID]
    local settings = HealcraftDB.settings
    
    rowData.frame:SetAlpha(settings.alphaBuffs / 100)
    
    if not ns.IsActive() or not settings.buffsActive then
        for i = 1, MAX_SUPPORTED_SLOTS do
            local slot = rowData.slots[i]
            slot:Hide()
            slot.expirationTime = 0
            slot.isTimerActive = false -- Reset
        end
        previousBuffs[unitID] = {}
        return
    end

    local activeSpells = ns.GetActiveSpells(unitID)
    local currentBuffs = {}
    local displayIndex = 1

    -- Loop up to 40 (max buffs in 3.3.5)
    for i = 1, 40 do
        local name, _, icon, stacks, _, duration, expirationTime, unitCaster = UnitBuff(unitID, i)
        if not name then break end

        -- stacks = 9 --debug

        if activeSpells[name] and unitCaster == "player" then
            currentBuffs[name] = true

            local slot = rowData.slots[displayIndex]
            if slot then
                slot.icon:SetTexture(icon)
                slot.buffIndex = i
                
                if stacks and stacks > 1 and settings.showStacks then
                    slot.buffText:SetText("x"..stacks)
                    slot.hasStacks = true
                    SetBuffTextStyle(slot, "stacks")
                else
                    slot.buffText:SetText("")
                    slot.hasStacks = false
                end

                if duration and duration > 0 and expirationTime then
                    if not slot.hasStacks and settings.showTimer then
                        slot.isTimerActive = true -- Start timer via flag
                    else
                        slot.isTimerActive = false
                    end

                    -- Update cooldown only if expiration time changed
                    if slot.expirationTime ~= expirationTime then
                        local start = expirationTime - duration
                        CooldownFrame_SetTimer(slot.cd, start, duration, 1)
                        slot.expirationTime = expirationTime
                        slot.lastSec = -1 
                    end
                    
                    -- Reset red color on buff refresh
                    local remain = expirationTime - GetTime()
                    if remain > URGENT_TIME then
                        if settings.showTimer and not slot.hasStacks then
                            SetBuffTextStyle(slot, "normal")
                        end
                    end
                else
                    slot.cd:Hide()
                    slot.expirationTime = 0
                    slot.isTimerActive = false -- Reset flag
                    slot.buffText:SetText("")
                end

                slot:Show()
                displayIndex = displayIndex + 1
            end
            
            if displayIndex > settings.slotsCount then break end
        end
    end

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

    -- Hide unused slots
    for i = displayIndex, MAX_SUPPORTED_SLOTS do
        local slot = rowData.slots[i]
        slot:Hide()
        slot.expirationTime = 0
        slot.isTimerActive = false -- Reset
        slot.buffText:SetText("")
    end
end

function ns.RefreshAllBuffs()
    for unitID in pairs(buffRows) do
        ns.UpdateBuffs(unitID)
    end
end