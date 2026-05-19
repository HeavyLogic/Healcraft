local addonName, ns = ...

local ADDON_NAME  = "PartySpells"

-- party1..4 only — player is NOT included
-- PartyMemberFrame1 = first party member, etc.
local UNITS = { "party1", "party2", "party3", "party4" }

local FRAMES = {
    party1 = PartyMemberFrame1,
    party2 = PartyMemberFrame2,
    party3 = PartyMemberFrame3,
    party4 = PartyMemberFrame4,
}

local rows = {}
local MAX_SUPPORTED_SLOTS = 5

-- Функция, которая переключает режим работы кнопок
function ns.UpdateCastingBehavior()
    -- Проверяем: загружена ли база. Если нет - по умолчанию false (разрешено таскать)
    local isLocked = false
    if PartySpellsDB and PartySpellsDB.settings and type(PartySpellsDB.settings.lockSpells) == "boolean" then
        isLocked = PartySpellsDB.settings.lockSpells
    end

    local clickMode = isLocked and "AnyDown" or "AnyUp"
    
    for unitID, row in pairs(rows) do
        if row.slots then
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = row.slots[i]
                if slot then
                    slot:RegisterForClicks(clickMode)
                end
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Cooldowns update
-- -----------------------------------------------------------------------
local function UpdateCooldowns()
    -- Проходим по всем созданным строкам
    local s = PartySpellsDB.settings
    for unitID, row in pairs(rows) do
        -- Обновляем кулдауны только если фрейм игрока сейчас отображается
        if row.frame:IsVisible() then
            for i = 1, s.slotsCount do
                local slot = row.slots[i]
                if slot.spellName then
                    local start, duration, enable = GetSpellCooldown(slot.spellName)
                    if start and duration then
                        CooldownFrame_SetTimer(slot.cd, start, duration, enable)
                    end
                end
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Range Check (Оптимизированный таймер)
-- -----------------------------------------------------------------------
local RANGE_CHECK_INTERVAL = 0.2 -- Проверяем 5 раз в секунду
local rangeTimer = 0

local rangeFrame = CreateFrame("Frame")
rangeFrame:SetScript("OnUpdate", function(self, elapsed)
    if not ns.IsActive() then return end

    rangeTimer = rangeTimer + elapsed

    -- Как только набралось 0.2 сек, делаем проверку
    if rangeTimer >= RANGE_CHECK_INTERVAL then
        rangeTimer = 0
        local s = PartySpellsDB.settings
        
        -- Проходим только по существующим строкам
        for unitID, row in pairs(rows) do
            -- Проверяем только если строка видима (член группы существует)
            if row.frame:IsVisible() then
                for i = 1, s.slotsCount do
                    local slot = row.slots[i]
                    if slot.spellName then
                        -- IsSpellInRange нативно понимает строковое имя спелла в 3.3.5
                        local inRange = IsSpellInRange(slot.spellName, slot.unitID)
                        
                        -- Если вернулся 0, значит спелл точно не достает до цели
                        if inRange == 0 then
                            slot.outOfRange:Show()
                        else
                            -- Во всех остальных случаях (в зоне или цель невалидна) - скрываем
                            slot.outOfRange:Hide()
                        end
                    end
                end
            end
        end
    end
end)

-- -----------------------------------------------------------------------
-- SavedVariables: store spell NAME (stable across reloads in 3.3.5)
-- -----------------------------------------------------------------------

local function GetDB()
    if not PartySpellsDB then PartySpellsDB = {} end
    return PartySpellsDB
end

local function SaveSlot(unitID, slotIndex, spellName)
    local db = GetDB()
    if not db[unitID] then db[unitID] = {} end
    db[unitID][slotIndex] = spellName
end

local function LoadSlot(unitID, slotIndex)
    local db = GetDB()
    if db[unitID] then
        return db[unitID][slotIndex]
    end
    return nil
end

-- -----------------------------------------------------------------------
-- Resolve texture by spell name (scan spellbook)
-- Returns: texture string or nil
-- -----------------------------------------------------------------------

local function GetTextureByName(targetName)
    for i = 1, 1024 do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == targetName then
            local _, _, texture = GetSpellInfo(i, BOOKTYPE_SPELL)
            -- keep scanning — last match = highest rank, same texture family
            if texture then
                return texture
            end
        end
    end
    return nil
end

-- -----------------------------------------------------------------------
-- Fill / clear slot
-- -----------------------------------------------------------------------

local function FillSlot(slot, spellName, texture)
    if not spellName or not texture then
        return
    end
    slot.spellName = spellName
    slot.icon:SetTexture(texture)
    slot.icon:Show()

    -- secure attributes for casting
    slot:SetAttribute("type", "spell")
    slot:SetAttribute("spell", spellName)
    slot:SetAttribute("unit", slot.unitID)
    
    -- Обновляем кулдауны, чтобы только что брошенный спелл показал правильный таймер
    UpdateCooldowns()
    ns.UpdateSlotsVisibility()
end

local function ClearSlot(slot)
    slot.spellName = nil
    slot.icon:Hide()
    if slot.cd then slot.cd:Hide() end
    if slot.outOfRange then slot.outOfRange:Hide() end
    SaveSlot(slot.unitID, slot.slotIndex, nil)

    -- Очищаем атрибуты (только вне боя, в бою это запрещено ядром игры)
    if not InCombatLockdown() then
        slot:SetAttribute("type", nil)
        slot:SetAttribute("spell", nil)
    end
    ns.UpdateSlotsVisibility()
end
-- -----------------------------------------------------------------------
-- Create one spell slot
-- -----------------------------------------------------------------------

local function CreateSpellSlot(parent, unitID, slotIndex)
    local s = PartySpellsDB.settings
    local slot = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    slot:SetSize(s.slotSize, s.slotSize)
    slot.unitID    = unitID
    slot.slotIndex = slotIndex
    slot.spellName = nil

    slot:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    slot:SetBackdropColor(0, 0, 0, 0.85)
    slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",      4, -4)
    icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -4,  4)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    slot.icon = icon

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints(icon) -- Кулдаун будет покрывать только саму иконку
    cd:SetReverse(false)  -- Обычное затемнение
    slot.cd = cd

    local outOfRange = slot:CreateTexture(nil, "OVERLAY")
    outOfRange:SetAllPoints(icon) -- Слой накладывается поверх самой иконки
    -- Задаем цвет: Красный (R=1, G=0, B=0) с прозрачностью 60% (Alpha=0.6)
    outOfRange:SetTexture(1, 0, 0, 0.6) 
    outOfRange:Hide() -- Скрыт по умолчанию
    slot.outOfRange = outOfRange

    local flash = slot:CreateTexture(nil, "OVERLAY")
    flash:SetBlendMode("ADD")
    flash:Hide()

    local fader = CreateFrame("Frame", nil, slot)
    fader:Hide()
    fader.elapsed = 0
    fader:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.6 then
            flash:Hide()
            self:Hide()
        else
            local s = PartySpellsDB.settings
            local progress = self.elapsed / 0.6
            
            if s.flashMode == 1 then
                flash:SetAlpha(1 - progress)
            elseif s.flashMode == 2 then
                flash:SetAlpha(1)
            elseif s.flashMode == 3 then
                -- 1. Плавное появление и затухание (Синусоида: 0 -> 1 -> 0)
                flash:SetAlpha(math.sin(progress * math.pi))
                
                -- 2. Вращение текстуры по часовой стрелке
                -- Вращаем на 90 градусов (math.pi / 2) за время анимации
                local angle = progress * (math.pi / 2)
                local cosA, sinA = math.cos(angle), math.sin(angle)
                
                -- Матрица поворота текстурных координат вокруг центра (0.5, 0.5)
                local ULx, ULy = 0.5 - 0.5*cosA + 0.5*sinA, 0.5 - 0.5*sinA - 0.5*cosA
                local LLx, LLy = 0.5 - 0.5*cosA - 0.5*sinA, 0.5 - 0.5*sinA + 0.5*cosA
                local URx, URy = 0.5 + 0.5*cosA + 0.5*sinA, 0.5 + 0.5*sinA - 0.5*cosA
                local LRx, LRy = 0.5 + 0.5*cosA - 0.5*sinA, 0.5 + 0.5*sinA + 0.5*cosA
                
                flash:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
            end
        end
    end)

    slot.PlayFlash = function()
        local s = PartySpellsDB.settings
        if not s.flashMode or s.flashMode == 0 then return end 

        flash:ClearAllPoints()
        flash:SetTexCoord(0, 1, 0, 1) -- Обязательно сбрасываем координаты в дефолт
        
        if s.flashMode == 1 then
            flash:SetAllPoints(slot.icon)
            flash:SetTexture(0, 1, 0, 0.6)
            flash:SetVertexColor(1, 1, 1, 1)
        elseif s.flashMode == 2 then
            flash:SetAllPoints(slot)
            flash:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            flash:SetVertexColor(0, 1, 0, 1)
        elseif s.flashMode == 3 then
            flash:SetPoint("CENTER", slot, "CENTER", 0, 0)
            flash:SetSize(s.slotSize * 1.25, s.slotSize * 1.25) -- Меньше в 2 раза
            flash:SetTexture("Interface\\Cooldown\\star4")
            flash:SetVertexColor(1, 1, 1, 1) -- Белый цвет
        end
        
        -- Для режима 3 альфа стартует с 0, чтобы появиться плавно
        flash:SetAlpha(s.flashMode == 3 and 0 or 1)
        flash:Show()
        fader.elapsed = 0
        fader:Show()
    end

    local hl = slot:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints(slot)
    hl:SetBlendMode("ADD")
    slot.hl = hl -- Сохраняем, чтобы обращаться к ней позже!

    slot:EnableMouse(true)
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnEnter", function(self)
        if self.spellName then
            local texture = GetTextureByName(self.spellName)
            if texture then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- SetSpellByID not reliable; use spellbook scan for tooltip
                local bookSlot = nil
                for i = 1, 1024 do
                    local n = GetSpellName(i, BOOKTYPE_SPELL)
                    if not n then break end
                    if n == self.spellName then bookSlot = i end
                end
                if bookSlot then
                    GameTooltip:SetSpell(bookSlot, BOOKTYPE_SPELL)
                    GameTooltip:Show()
                end
            end
        end
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- -----------------------------------------------------------------------
    -- Receive Drag / Swap Logic
    -- -----------------------------------------------------------------------
    
    local function HandleReceiveSpell(self, id, subType)
        local name, _, texture = GetSpellInfo(id, subType)
    
        if name and texture then
            -- Запоминаем старый спелл (если он был)
            local oldName = self.spellName
    
            -- Заполняем слот (FillSlot сам обновит атрибуты на type="spell")
            FillSlot(self, name, texture)
            SaveSlot(self.unitID, self.slotIndex, name)
            ClearCursor() -- На всякий случай очищаем курсор
    
            -- Если в слоте уже был спелл, берем его на курсор
            if oldName then
                PickupSpell(oldName)
            end
            return true
        else
            return false
        end
    end
    
    local function TryReceiveSpell(self)
        local infoType, id, subType = GetCursorInfo()
        if infoType == "spell" then
            return HandleReceiveSpell(self, id, subType)
        end
        return false
    end

    slot:SetScript("OnReceiveDrag", TryReceiveSpell)

    slot:SetScript("OnReceiveDrag", TryReceiveSpell)

    slot:SetScript("PreClick", function(self, button)
        -- Обрабатываем дроп только левой кнопкой мыши
        if button ~= "LeftButton" then return end
        
        local infoType, id, subType = GetCursorInfo()
        if infoType == "spell" then
            self.isDropping = true
            -- Сохраняем данные заклинания до того, как клиент успеет очистить курсор
            self.dropID = id
            self.dropSubType = subType
            
            if not InCombatLockdown() then
                -- Временно удаляем type, чтобы SecureActionButton не скастовал спелл на этом же клике
                self.oldType = self:GetAttribute("type")
                self:SetAttribute("type", nil)
            end
        else
            self.isDropping = false
        end
    end)

    slot:SetScript("PostClick", function(self, button)
        if button ~= "LeftButton" then return end
        
        if self.isDropping then
            self.isDropping = false
            if not InCombatLockdown() then
                -- Вызываем нашу функцию обмена
                local success = HandleReceiveSpell(self, self.dropID, self.dropSubType)
                
                -- Если что-то пошло не так (вернулся false), восстанавливаем старый атрибут
                if not success and self.oldType then
                    self:SetAttribute("type", self.oldType)
                end
            end
        end
    end)

    -- drag start (pick up spell from slot like action bar)
    slot:SetScript("OnDragStart", function(self)
        if self.spellName and not InCombatLockdown() and not PartySpellsDB.settings.lockSpells then
            PickupSpell(self.spellName)
            ClearSlot(self)
        end
    end)

    return slot
end

-- -----------------------------------------------------------------------
-- Create row for one party member
-- -----------------------------------------------------------------------

local function CreateRow(unitID, anchor)
    if rows[unitID] then return end

    local row = CreateFrame("Frame", ADDON_NAME .. "Row_" .. unitID, UIParent)
    -- Размеры зададутся позже в ns.RefreshLayout
    local slots = {}
    for i = 1, MAX_SUPPORTED_SLOTS do
        local slot = CreateSpellSlot(row, unitID, i)
        slots[i] = slot
    end

    row:Hide()
    rows[unitID] = { frame = row, slots = slots }
end

-- -----------------------------------------------------------------------
-- Load saved spells into row slots (called after spellbook is available)
-- -----------------------------------------------------------------------

local function LoadRow(unitID)
    if not rows[unitID] then return end
    local s = PartySpellsDB.settings
    for i = 1, s.slotsCount do
        local savedName = LoadSlot(unitID, i)
        if savedName then
            local texture = GetTextureByName(savedName)
            if texture then
                FillSlot(rows[unitID].slots[i], savedName, texture)
            end
        end
    end
end
-- -----------------------------------------------------------------------
-- Show / hide rows based on current party size
-- -----------------------------------------------------------------------

local function RefreshRows()
    local groupSize = GetNumPartyMembers()
    local isActive = ns.IsActive() -- Проверяем мастер-свитч

    for i = 1, 4 do
        local unitID = "party" .. i
        if rows[unitID] then
            -- Если аддон включен И игрок есть в группе
            if isActive and i <= groupSize then
                rows[unitID].frame:Show()
            else
                -- Иначе прячем все слоты
                rows[unitID].frame:Hide()
            end
        end
    end
end

function ns.RefreshAllVisibility()
    RefreshRows()
    ns.UpdateSlotsVisibility()
    for _, unitID in ipairs(UNITS) do
        if ns.UpdateBuffs then
            ns.UpdateBuffs(unitID)
        end
    end
end

-- -----------------------------------------------------------------------
-- API для других модулей аддона
-- -----------------------------------------------------------------------
-- Функция для вызова вспышки из других файлов
function ns.FlashSpellSlot(unitID, spellName)
    if rows[unitID] then
        local s = PartySpellsDB.settings
        for i = 1, s.slotsCount do
            local slot = rows[unitID].slots[i]
            if slot.spellName == spellName then
                slot.PlayFlash()
                break
            end
        end
    end
end

function ns.GetActiveSpells(unitID)
    local activeSpells = {}
    if rows[unitID] then
        local s = PartySpellsDB.settings
        for i = 1, s.slotsCount do
            local spellName = rows[unitID].slots[i].spellName
            if spellName then
                activeSpells[spellName] = true
            end
        end
    end
    return activeSpells
end

function ns.UpdateSlotsVisibility()
    local cursorType = GetCursorInfo()
    local isDraggingSpell = (cursorType == "spell")
    local s = PartySpellsDB.settings

    for unitID, row in pairs(rows) do
        for i = 1, s.slotsCount do
            local slot = row.slots[i]
            if slot.spellName or isDraggingSpell then
                -- Показываем слот
                slot:SetBackdropColor(0, 0, 0, 0.85)
                slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
                -- Возвращаем синюю подсветку при наведении
                if slot.hl then slot.hl:SetAlpha(1) end 
            else
                -- Делаем слот невидимым
                slot:SetBackdropColor(0, 0, 0, 0)
                slot:SetBackdropBorderColor(0, 0, 0, 0)
                -- Отключаем свечение при наведении (прячем слой)
                if slot.hl then slot.hl:SetAlpha(0) end 
            end
        end
    end
end

function ns.RefreshLayout()
    if not PartySpellsDB or not PartySpellsDB.settings then return end
    local s = PartySpellsDB.settings

    for unitID, rowData in pairs(rows) do
        local anchor = FRAMES[unitID]
        if anchor then
            local totalWidth = s.slotsCount * s.slotSize + (s.slotsCount - 1) * s.slotGap
            rowData.frame:SetSize(totalWidth, s.slotSize)
            rowData.frame:SetPoint("LEFT", anchor, "RIGHT", s.offsetX, s.offsetY)

            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = rowData.slots[i]
                if i <= s.slotsCount then
                    slot:SetSize(s.slotSize, s.slotSize)
                    slot:ClearAllPoints()
                    if i == 1 then
                        slot:SetPoint("LEFT", rowData.frame, "LEFT", 0, 0)
                    else
                        slot:SetPoint("LEFT", rowData.slots[i-1], "RIGHT", s.slotGap, 0)
                    end
                    slot:Show()
                else
                    slot:Hide()
                end
            end
        end
    end
    ns.UpdateSlotsVisibility()
end

-- -----------------------------------------------------------------------
-- Init
-- -----------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
initFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
initFrame:RegisterEvent("UNIT_AURA")
initFrame:RegisterEvent("CURSOR_UPDATE")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- 1. Сначала загружаем базу и настройки
        ns.InitDB()

        -- 2. Затем создаем UI
        for _, unitID in ipairs(UNITS) do
            local anchor = FRAMES[unitID]
            if anchor then
                CreateRow(unitID, anchor)
                LoadRow(unitID)
                ns.CreateBuffRow(unitID)
            end
        end

        ns.RefreshLayout()
        ns.RefreshAllVisibility()
        
        -- Устанавливаем правильный режим кнопок при загрузке
        ns.UpdateCastingBehavior()

        if SpellBookFrame then
            SpellBookFrame:SetMovable(true)
            SpellBookFrame:EnableMouse(true)
            SpellBookFrame:RegisterForDrag("LeftButton")
            SpellBookFrame:SetScript("OnDragStart", function(f) f:StartMoving() end)
            SpellBookFrame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
        end

    elseif event == "PARTY_MEMBERS_CHANGED" then
        RefreshRows()
        for _, unitID in ipairs(UNITS) do
            ns.UpdateBuffs(unitID)
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if ns.IsActive() then UpdateCooldowns() end

    elseif event == "CURSOR_UPDATE" then
        if ns.IsActive() then ns.UpdateSlotsVisibility() end

    elseif event == "UNIT_AURA" then
        -- Вызываем функцию обновления баффов
        -- Она сама внутри проверит, относится ли этот arg1 к нашей группе
        if ns.IsActive() then ns.UpdateBuffs(arg1) end
    end
end)