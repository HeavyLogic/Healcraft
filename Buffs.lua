local addonName, ns = ...

local BUFF_SIZE = 16 -- на 19 появляется встроенный таймер
local BUFF_GAP  = 3
local BUFF_OFFSET_Y = -1
local PRE_URGENT_TIME = 9
local URGENT_TIME = 5

-- Настройки шрифта
local FONT_FILE = "Fonts\\FRIZQT__.TTF" -- Стандартный шрифт интерфейса WoW
local FONT_NORMAL_SIZE = 10
local FONT_URGENT_SIZE = 12

local buffRows = {}
local previousBuffs = {}

local function CreateBuffSlot(parent, unitID)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(BUFF_SIZE, BUFF_SIZE)
    slot.unitID = unitID

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    slot.icon = icon

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    cd:SetDrawEdge(true)
    slot.cd = cd

    -- Создаем отдельный фрейм для текстов, чтобы поднять его НАД тенью кулдауна
    local textFrame = CreateFrame("Frame", nil, slot)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(cd:GetFrameLevel() + 2) -- Делаем уровень выше, чем у cd

    -- Это стаки заклинаний (Lifebloom у друида)
    local countText = textFrame:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
    countText:SetPoint("BOTTOMRIGHT", textFrame, "BOTTOMRIGHT", 2, -2)
    slot.countText = countText
    -- TODO: не влезает - пофиксить
    -- slot.countText:SetText("9")

    local timerText = textFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    timerText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
    timerText:SetTextColor(1, 0.82, 0)
    slot.timerText = timerText

    slot.isUrgent = false

    slot:SetScript("OnUpdate", function(self)
        if self.expirationTime and self.expirationTime > 0 then
            local remain = self.expirationTime - GetTime()
            if remain > 0 then
                local s = PartySpellsDB.settings
                if remain <= URGENT_TIME then
                    if not self.isUrgent then
                        self.isUrgent = true
                        -- 1. Сделали затемнение гораздо мягче (0.85 вместо 0.7)
                        -- self.icon:SetVertexColor(0.85, 0.85, 0.85) 
                        if s.showTimer then
                            self.timerText:SetFont(FONT_FILE, FONT_URGENT_SIZE, "OUTLINE")
                            self.timerText:SetTextColor(1, 0, 0)
                        end
                    end
                else
                    if self.isUrgent then
                        self.isUrgent = false
                        -- self.icon:SetVertexColor(1, 1, 1)
                        if s.showTimer then
                            self.timerText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
                            self.timerText:SetTextColor(1, 0.82, 0)
                        end
                    end
                end

                -- 2. Рисуем текст ТОЛЬКО если осталось <= 20 секунд
                if s.showTimer and remain <= 20 then
                    self.timerText:SetText(math.ceil(remain))
                else
                    self.timerText:SetText("")
                end
            else
                self.expirationTime = 0
                self.isUrgent = false
                -- self.icon:SetVertexColor(1, 1, 1)
                self.timerText:SetText("")
            end
        end
    end)

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
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

    local row = CreateFrame("Frame", addonName .. "BuffRow_" .. unitID, manaBar:GetParent())
    row:SetSize((BUFF_SIZE + BUFF_GAP) * PartySpellsDB.settings.slotsCount, BUFF_SIZE)
    row:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, BUFF_OFFSET_Y)

    local slots = {}
    for i = 1, PartySpellsDB.settings.slotsCount do
        local slot = CreateBuffSlot(row, unitID)
        if i == 1 then
            slot:SetPoint("LEFT", row, "LEFT", 0, 0)
        else
            slot:SetPoint("LEFT", slots[i-1], "RIGHT", BUFF_GAP, 0)
        end
        slots[i] = slot
    end

    buffRows[unitID] = { frame = row, slots = slots }
    previousBuffs[unitID] = {}
end

function ns.UpdateBuffs(unitID)
    local rowData = buffRows[unitID]
    if not rowData then return end
    rowData.frame:SetAlpha(PartySpellsDB.settings.alphaBuffs / 100)
    
    if not ns.IsActive() or not PartySpellsDB.settings.buffsActive then
        for i = 1, PartySpellsDB.settings.slotsCount do
            local slot = rowData.slots[i]
            slot:Hide()
            slot.buffIndex = nil
            slot.expirationTime = 0
            slot.isUrgent = false
            slot.timerText:SetText("")
        end
        previousBuffs[unitID] = {}
        return
    end

    local activeSpells = ns.GetActiveSpells(unitID)
    local currentBuffs = {}
    local displayIndex = 1
    local buffIndex = 1

    while true do
        local name, _, icon, count, _, duration, expirationTime, unitCaster = UnitBuff(unitID, buffIndex)
        if not name then break end

        if activeSpells[name] and unitCaster == "player" then
            currentBuffs[name] = true

            local slot = rowData.slots[displayIndex]
            if not slot then break end

            slot.icon:SetTexture(icon)
            slot.buffIndex = buffIndex
            
            if count and count > 1 then
                slot.countText:SetText(count)
            else
                slot.countText:SetText("")
            end

            if duration and duration > 0 and expirationTime then
                local start = expirationTime - duration
                CooldownFrame_SetTimer(slot.cd, start, duration, 1)
                slot.expirationTime = expirationTime
                
                -- ИСПРАВЛЕНИЕ: Сбрасываем красный цвет при обновлении баффа
                local remain = expirationTime - GetTime()
                if remain > URGENT_TIME then
                    slot.isUrgent = false
                    -- slot.icon:SetVertexColor(1, 1, 1)
                    if PartySpellsDB.settings.showTimer then
                        slot.timerText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
                        slot.timerText:SetTextColor(1, 0.82, 0)
                    end
                end
            else
                slot.cd:Hide()
                slot.expirationTime = 0
                slot.timerText:SetText("")
            end

            slot:Show()
            displayIndex = displayIndex + 1
        end
        buffIndex = buffIndex + 1
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

    for i = displayIndex, PartySpellsDB.settings.slotsCount do
        local slot = rowData.slots[i]
        slot:Hide()
        slot.buffIndex = nil
        slot.expirationTime = 0
        slot.isUrgent = false
        -- slot.icon:SetVertexColor(1, 1, 1)
        slot.timerText:SetText("")
    end
end

function ns.RefreshAllBuffs()
    for unitID in pairs(buffRows) do
        ns.UpdateBuffs(unitID)
    end
end