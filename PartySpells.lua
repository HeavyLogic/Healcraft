local addonName, ns = ...

local ADDON_NAME  = "PartySpells"
local SLOTS_COUNT = 3
local SLOT_SIZE   = 32
local SLOT_GAP    = 2
local OFFSET_X    = 8
local OFFSET_Y    = 0
local FLASH_MODE = 2 -- 1 = Плавная заливка (Иммерсивно), 2 = Резкая зеленая рамка (Заметно)

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

-- -----------------------------------------------------------------------
-- Cooldowns update
-- -----------------------------------------------------------------------
local function UpdateCooldowns()
    -- Проходим по всем созданным строкам
    for unitID, row in pairs(rows) do
        -- Обновляем кулдауны только если фрейм игрока сейчас отображается
        if row.frame:IsVisible() then
            for i = 1, SLOTS_COUNT do
                local slot = row.slots[i]
                if slot.spellName then
                    -- GetSpellCooldown понимает имя спелла в 3.3.5
                    local start, duration, enable = GetSpellCooldown(slot.spellName)
                    if start and duration then
                        -- Эта стандартная функция WoW берет на себя всю отрисовку спиральки
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
    -- Накапливаем время, прошедшее с предыдущего кадра
    rangeTimer = rangeTimer + elapsed
    
    -- Как только набралось 0.2 сек, делаем проверку
    if rangeTimer >= RANGE_CHECK_INTERVAL then
        rangeTimer = 0 -- Сбрасываем таймер
        
        -- Проходим только по существующим строкам
        for unitID, row in pairs(rows) do
            -- Проверяем только если строка видима (член группы существует)
            if row.frame:IsVisible() then
                for i = 1, SLOTS_COUNT do
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
    -- print("[PartySpells] SAVE unit=" .. unitID .. " slot=" .. slotIndex .. " name=" .. tostring(spellName))
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
        -- print("[PartySpells] FillSlot FAILED name=" .. tostring(spellName) .. " texture=" .. tostring(texture))
        return
    end
    slot.spellName = spellName
    slot.icon:SetTexture(texture)
    slot.icon:Show()

    -- secure attributes for casting
    slot:SetAttribute("type", "spell")
    slot:SetAttribute("spell", spellName)
    slot:SetAttribute("unit", slot.unitID)

    -- print("[PartySpells] FillSlot OK name=" .. spellName)
    
    -- Обновляем кулдауны, чтобы только что брошенный спелл показал правильный таймер
    UpdateCooldowns()
    ns.UpdateSlotsVisibility()
end

local function ClearSlot(slot)
    -- print("[PartySpells] ClearSlot unit=" .. slot.unitID .. " slot=" .. slot.slotIndex)
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

-- Функция для вызова вспышки из других файлов
function ns.FlashSpellSlot(unitID, spellName)
    if rows[unitID] then
        for i = 1, SLOTS_COUNT do
            local slot = rows[unitID].slots[i]
            if slot.spellName == spellName then
                slot.PlayFlash()
                break
            end
        end
    end
end
-- -----------------------------------------------------------------------
-- Create one spell slot
-- -----------------------------------------------------------------------

local function CreateSpellSlot(parent, unitID, slotIndex)
    local slot = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
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
    
    if FLASH_MODE == 1 then
        flash:SetAllPoints(icon)
        flash:SetTexture(0, 1, 0, 0.6)
    else
        flash:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
        flash:SetVertexColor(0, 1, 0, 1)
        -- Привязываем центр рамки к центру СЛОТА, а не иконки
        flash:SetPoint("CENTER", slot, "CENTER", 0, 0)
        -- Множитель 1.8 делает текстуру достаточно большой, чтобы покрыть бордер слота
        flash:SetSize(SLOT_SIZE * 1.8, SLOT_SIZE * 1.8)
    end
    flash:Hide()

    local fader = CreateFrame("Frame", nil, slot)
    fader:Hide()
    fader.elapsed = 0
    fader:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        -- Увеличили время до 600 мс (0.6 сек)
        if self.elapsed >= 0.6 then
            flash:Hide()
            self:Hide()
        else
            if FLASH_MODE == 1 then
                -- Плавное затухание
                flash:SetAlpha(1 - (self.elapsed / 0.6))
            else
                -- Режим 2: Резко (просто держим яркость на 100% все 600мс)
                flash:SetAlpha(1)
            end
        end
    end)

    slot.PlayFlash = function()
        flash:SetAlpha(1)
        flash:Show()
        fader.elapsed = 0
        fader:Show()
    end

    local hl = slot:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints(slot)
    hl:SetBlendMode("ADD")

    slot:EnableMouse(true)
    slot:RegisterForClicks("AnyUp")
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
        -- print("[PartySpells] HandleReceiveSpell: name=" .. tostring(name) .. " texture=" .. tostring(texture))
    
        if name and texture then
            -- Запоминаем старый спелл (если он был)
            local oldName = self.spellName
    
            -- Заполняем слот (FillSlot сам обновит атрибуты на type="spell")
            FillSlot(self, name, texture)
            SaveSlot(self.unitID, self.slotIndex, name)
            ClearCursor() -- На всякий случай очищаем курсор
    
            -- Если в слоте уже был спелл, берем его на курсор
            if oldName then
                -- print("[PartySpells] SWAP put old spell back to cursor: " .. oldName)
                PickupSpell(oldName)
            end
            return true
        else
            -- print("[PartySpells] ERROR: GetSpellInfo returned nil")
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
            else
                -- print("[PartySpells] Ошибка: Нельзя менять заклинания в бою!")
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
        if self.spellName and not InCombatLockdown() then
            -- print("[PartySpells] PICKUP " .. self.spellName)
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
    local totalWidth = SLOTS_COUNT * SLOT_SIZE + (SLOTS_COUNT - 1) * SLOT_GAP
    row:SetSize(totalWidth, SLOT_SIZE)
    row:SetPoint("LEFT", anchor, "RIGHT", OFFSET_X, OFFSET_Y)

    local slots = {}
    for i = 1, SLOTS_COUNT do
        local slot = CreateSpellSlot(row, unitID, i)
        if i == 1 then
            slot:SetPoint("LEFT", row, "LEFT", 0, 0)
        else
            slot:SetPoint("LEFT", slots[i-1], "RIGHT", SLOT_GAP, 0)
        end
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
    for i = 1, SLOTS_COUNT do
        local savedName = LoadSlot(unitID, i)
        if savedName then
            -- print("[PartySpells] LOAD unit=" .. unitID .. " slot=" .. i .. " name=" .. savedName)
            local texture = GetTextureByName(savedName)
            if texture then
                FillSlot(rows[unitID].slots[i], savedName, texture)
            else
                -- print("[PartySpells] LOAD FAILED: texture not found for '" .. savedName .. "'")
            end
        end
    end
end
-- -----------------------------------------------------------------------
-- Show / hide rows based on current party size
-- -----------------------------------------------------------------------

local function RefreshRows()
    local groupSize = GetNumPartyMembers()  -- excludes player, 0 if solo
    -- print("[PartySpells] RefreshRows groupSize=" .. groupSize)

    for i = 1, 4 do
        local unitID = "party" .. i
        if rows[unitID] then
            if i <= groupSize then
                rows[unitID].frame:Show()
                -- print("[PartySpells] Show row " .. unitID)
            else
                rows[unitID].frame:Hide()
                -- print("[PartySpells] Hide row " .. unitID)
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- API для других модулей аддона
-- -----------------------------------------------------------------------
function ns.GetActiveSpells(unitID)
    local activeSpells = {}
    if rows[unitID] then
        for i = 1, SLOTS_COUNT do
            local spellName = rows[unitID].slots[i].spellName
            if spellName then
                -- Добавляем имя спелла как ключ для быстрого поиска
                activeSpells[spellName] = true
            end
        end
    end
    return activeSpells
end

-- скрывает пустые слоты, если мы не перетаскиваем заклинание
function ns.UpdateSlotsVisibility()
    local cursorType = GetCursorInfo()
    local isDraggingSpell = (cursorType == "spell")

    for unitID, row in pairs(rows) do
        for i = 1, SLOTS_COUNT do
            local slot = row.slots[i]
            if slot.spellName or isDraggingSpell then
                -- Показываем фон и рамку
                slot:SetBackdropColor(0, 0, 0, 0.85)
                slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
            else
                -- Делаем слот полностью прозрачным
                slot:SetBackdropColor(0, 0, 0, 0)
                slot:SetBackdropBorderColor(0, 0, 0, 0)
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Init
-- -----------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
-- Регистрируем эвент обновления кулдаунов заклинаний
initFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
initFrame:RegisterEvent("UNIT_AURA")
initFrame:RegisterEvent("CURSOR_UPDATE")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- print("[PartySpells] PLAYER_LOGIN")

        for _, unitID in ipairs(UNITS) do
            local anchor = FRAMES[unitID]
            if anchor then
                CreateRow(unitID, anchor)
                LoadRow(unitID)
                
                ns.CreateBuffRow(unitID)
                ns.UpdateBuffs(unitID)
            end
        end

        if SpellBookFrame then
            SpellBookFrame:SetMovable(true)
            SpellBookFrame:EnableMouse(true)
            SpellBookFrame:RegisterForDrag("LeftButton")
            SpellBookFrame:SetScript("OnDragStart", function(f) f:StartMoving() end)
            SpellBookFrame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
        end

        RefreshRows()
        UpdateCooldowns()
        ns.UpdateSlotsVisibility()
        -- print("[PartySpells] loaded, slots per member: " .. SLOTS_COUNT)

    elseif event == "PARTY_MEMBERS_CHANGED" then
        -- print("[PartySpells] PARTY_MEMBERS_CHANGED")
        RefreshRows()
        for _, unitID in ipairs(UNITS) do
            ns.UpdateBuffs(unitID)
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        UpdateCooldowns()

    elseif event == "CURSOR_UPDATE" then
        ns.UpdateSlotsVisibility()

    elseif event == "UNIT_AURA" then
        -- Вызываем функцию обновления баффов
        -- Она сама внутри проверит, относится ли этот arg1 к нашей группе
        ns.UpdateBuffs(arg1)
    end
end)