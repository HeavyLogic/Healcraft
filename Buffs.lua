local addonName, ns = ...

local BUFF_SIZE = 16 -- на 19 появляется встроенный таймер
local BUFF_GAP  = 3
local BUFF_OFFSET_Y = -1
local URGENT_TIME = 5
local MAX_SUPPORTED_SLOTS = 5 -- Резервируем максимум слотов

-- Настройки шрифта
local FONT_FILE = "Fonts\\FRIZQT__.TTF" -- Стандартный шрифт интерфейса WoW
local FONT_NORMAL_SIZE = 10
local FONT_URGENT_SIZE = 13

local buffRows = {}
local previousBuffs = {}

local function CreateBuffSlot(parent, unitID)
    local slot = CreateFrame("Frame", nil, parent)
    slot:SetSize(BUFF_SIZE, BUFF_SIZE)
    slot.unitID = unitID

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    -- Немного подрезаем края, чтобы убрать стандартную серую рамку иконок 3.3.5
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
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
    local buffText = textFrame:CreateFontString(nil, "OVERLAY")
    buffText:SetPoint("CENTER", textFrame, "CENTER", 0, 0)
    buffText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
    slot.buffText = buffText

    slot.isUrgent = false
    slot.hasStacks = false
    slot.lastSec = -1 -- Для оптимизации OnUpdate

    slot:SetScript("OnUpdate", function(self)
        if self.hasStacks then
            return
        end

        if self.expirationTime and self.expirationTime > 0 then
            local remain = self.expirationTime - GetTime()
            if remain > 0 then
                -- ОПТИМИЗАЦИЯ: Обновляем текст и проверки только если изменилась целая секунда
                local currentSec = math.ceil(remain)
                if currentSec ~= self.lastSec then
                    self.lastSec = currentSec
                    
                    local s = PartySpellsDB.settings
                    if remain <= URGENT_TIME then
                        if not self.isUrgent then
                            self.isUrgent = true
                            if s.showTimer then
                                self.buffText:SetFont(FONT_FILE, FONT_URGENT_SIZE, "OUTLINE")
                                self.buffText:SetTextColor(1, 0, 0)
                            end
                        end
                    else
                        if self.isUrgent then
                            self.isUrgent = false
                            if s.showTimer then
                                self.buffText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
                                self.buffText:SetTextColor(1, 0.82, 0)
                            end
                        end
                    end

                    -- 2. Рисуем текст ТОЛЬКО если осталось <= 20 секунд
                    if s.showTimer and remain <= 20 then
                        self.buffText:SetText(currentSec)
                    else
                        self.buffText:SetText("")
                    end
                end
            else
                self.expirationTime = 0
                self.isUrgent = false
                self.buffText:SetText("")
                self.lastSec = -1
            end
        end
    end)

    slot:EnableMouse(true)
    slot:SetScript("OnEnter", function(self)
        if not PartySpellsDB.settings.showTooltipsBuffs then return end
        
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

    -- Прикрепляем к мана-бару напрямую
    local row = CreateFrame("Frame", addonName .. "BuffRow_" .. unitID, manaBar:GetParent())
    row:SetSize((BUFF_SIZE + BUFF_GAP) * MAX_SUPPORTED_SLOTS, BUFF_SIZE)
    row:SetPoint("TOPLEFT", manaBar, "BOTTOMLEFT", 0, BUFF_OFFSET_Y)
    -- Поднимаем уровень, чтобы не перекрывалось стандартными фреймами
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
    local settings = PartySpellsDB.settings
    
    rowData.frame:SetAlpha(settings.alphaBuffs / 100)
    
    if not ns.IsActive() or not settings.buffsActive then
        for i = 1, MAX_SUPPORTED_SLOTS do
            local slot = rowData.slots[i]
            slot:Hide()
            slot.expirationTime = 0
        end
        previousBuffs[unitID] = {}
        return
    end

    local activeSpells = ns.GetActiveSpells(unitID)
    local currentBuffs = {}
    local displayIndex = 1

    -- Используем цикл до 40 (макс. баффов в 3.3.5)
    for i = 1, 40 do
        local name, _, icon, stacks, _, duration, expirationTime, unitCaster = UnitBuff(unitID, i)
        if not name then break end

        if activeSpells[name] and unitCaster == "player" then
            currentBuffs[name] = true

            local slot = rowData.slots[displayIndex]
            if slot then
                slot.icon:SetTexture(icon)
                slot.buffIndex = i
                
                if stacks and stacks > 1 then
                    slot.buffText:SetText("x"..stacks)
                    slot.buffText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
                    slot.buffText:SetTextColor(0.4, 1, 0.4)
                    slot.hasStacks = true
                else
                    slot.buffText:SetText("")
                    slot.hasStacks = false
                end

                if duration and duration > 0 and expirationTime then
                    -- Обновляем кулдаун только если изменилось время истечения
                    if slot.expirationTime ~= expirationTime then
                        local start = expirationTime - duration
                        CooldownFrame_SetTimer(slot.cd, start, duration, 1)
                        slot.expirationTime = expirationTime
                        slot.lastSec = -1 -- Сброс таймера для OnUpdate
                    end
                    
                    -- ИСПРАВЛЕНИЕ: Сбрасываем красный цвет при обновлении баффа
                    local remain = expirationTime - GetTime()
                    if remain > URGENT_TIME then
                        slot.isUrgent = false
                        if settings.showTimer and not slot.hasStacks then
                            slot.buffText:SetFont(FONT_FILE, FONT_NORMAL_SIZE, "OUTLINE")
                            slot.buffText:SetTextColor(1, 0.82, 0)
                        end
                    end
                else
                    slot.cd:Hide()
                    slot.expirationTime = 0
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

    -- Скрываем неиспользованные слоты
    for i = displayIndex, MAX_SUPPORTED_SLOTS do
        local slot = rowData.slots[i]
        slot:Hide()
        slot.expirationTime = 0
        slot.isUrgent = false
        slot.buffText:SetText("")
    end
end

function ns.RefreshAllBuffs()
    for unitID in pairs(buffRows) do
        ns.UpdateBuffs(unitID)
    end
end