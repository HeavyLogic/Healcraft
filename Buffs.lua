local addonName, ns = ...

local BUFF_SIZE = 16 
local BUFF_GAP  = 3
local BUFF_OFFSET_Y = -1
local MAX_SUPPORTED_SLOTS = 5 

local FONT_FILE = "Fonts\\FRIZQT__.TTF"
local FONT_NORMAL_SIZE = 10
local FONT_URGENT_SIZE = 11

local buffRows = {}
local previousBuffs = {}

local function CreateBuffSlot(parent, unitID)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(BUFF_SIZE, BUFF_SIZE)
    slot.unitID = unitID

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    slot.icon = icon

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints()
    cd:SetReverse(true)
    cd:SetDrawEdge(false)
    slot.cd = cd

    local textFrame = CreateFrame("Frame", nil, slot)
    textFrame:SetAllPoints()
    textFrame:SetFrameLevel(cd:GetFrameLevel() + 5) -- Гарантированно выше анимации КД

    local countText = textFrame:CreateFontString(nil, "OVERLAY")
    countText:SetFont(FONT_FILE, 10, "OUTLINE")
    countText:SetPoint("BOTTOMRIGHT", textFrame, "BOTTOMRIGHT", 1, 0)
    slot.countText = countText

    local timerText = textFrame:CreateFontString(nil, "OVERLAY")
    timerText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    timerText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
    timerText:SetTextColor(1, 0.82, 0)
    slot.timerText = timerText

    slot.lastSec = -1

    slot:SetScript("OnUpdate", function(self)
        if self.expirationTime and self.expirationTime > 0 then
            local remain = self.expirationTime - GetTime()
            if remain > 0 then
                local currentSec = math.ceil(remain)
                if currentSec ~= self.lastSec then
                    self.lastSec = currentSec
                    local s = PartySpellsDB.settings
                    
                    if remain <= 5 then
                        if not self.isUrgent then
                            self.isUrgent = true
                            if s.showTimer then
                                self.timerText:SetFont(FONT_FILE, FONT_URGENT_SIZE, "OUTLINE")
                                self.timerText:SetTextColor(1, 0.1, 0.1)
                            end
                        end
                    else
                        if self.isUrgent then
                            self.isUrgent = false
                            if s.showTimer then
                                self.timerText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
                                self.timerText:SetTextColor(1, 0.82, 0)
                            end
                        end
                    end

                    if s.showTimer and remain <= 20 then
                        self.timerText:SetText(currentSec)
                    else
                        self.timerText:SetText("")
                    end
                end
            else
                self.expirationTime = 0
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
    slot:SetScript("OnLeave", function() GameTooltip:Hide() end)

    return slot
end

function ns.CreateBuffRow(unitID)
    if buffRows[unitID] then return end

    local memberIndex = string.match(unitID, "%d+")
    local manaBar = _G["PartyMemberFrame" .. memberIndex .. "ManaBar"]
    if not manaBar then return end

    -- Важно: используем родителя манабара, чтобы координаты были такими же, как раньше
    local parentFrame = manaBar:GetParent()
    local row = CreateFrame("Frame", addonName .. "BuffRow_" .. unitID, parentFrame)
    
    -- Поднимаем уровень фрейма, чтобы он не перекрывался основным окном группы
    row:SetFrameLevel(parentFrame:GetFrameLevel() + 10)
    
    row:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, BUFF_OFFSET_Y)
    row:SetSize(100, BUFF_SIZE) -- Задаем примерный размер

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
    local s = PartySpellsDB.settings
    
    -- Если аддон выключен или настройки не прогрузились
    if not ns.IsActive() or not s or not s.buffsActive then
        for i = 1, MAX_SUPPORTED_SLOTS do rowData.slots[i]:Hide() end
        return
    end

    rowData.frame:SetAlpha(s.alphaBuffs / 100)
    
    -- Получаем список заклинаний из первого модуля
    local activeSpells = ns.GetActiveSpells(unitID)
    local currentBuffs = {}
    local displayIndex = 1

    -- Сканируем баффы (в 3.3.5 их максимум 40)
    for i = 1, 40 do
        -- В 3.3.5 UnitBuff возвращает: name, rank, icon, count, debuffType, duration, expirationTime, unitCaster...
        local name, _, icon, count, _, duration, expirationTime, unitCaster = UnitBuff(unitID, i, "HELPFUL")
        
        if not name then break end

        -- Проверяем: наш ли это спелл (unitCaster == "player")
        if activeSpells[name] and (unitCaster == "player" or unitCaster == "vehicle") then
            currentBuffs[name] = true
            
            local slot = rowData.slots[displayIndex]
            if slot then
                slot.buffIndex = i
                slot.icon:SetTexture(icon)
                slot.countText:SetText((count and count > 1) and count or "")
                
                if duration and duration > 0 and expirationTime then
                    if slot.expirationTime ~= expirationTime then
                        local start = expirationTime - duration
                        CooldownFrame_SetTimer(slot.cd, start, duration, 1)
                        slot.expirationTime = expirationTime
                        slot.lastSec = -1 -- Сброс таймера для OnUpdate
                    end
                else
                    slot.cd:Hide()
                    slot.expirationTime = 0
                    slot.timerText:SetText("")
                end
                
                slot:Show()
                displayIndex = displayIndex + 1
            end
            
            if displayIndex > s.slotsCount then break end
        end
    end

    -- Логика вспышки при исчезновении
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

    -- Скрываем лишние слоты
    for i = displayIndex, MAX_SUPPORTED_SLOTS do
        rowData.slots[i]:Hide()
        rowData.slots[i].expirationTime = 0
        rowData.slots[i].buffIndex = nil
    end
end