local addonName, ns = ...

local ADDON_NAME  = "Healcraft"

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

-- -----------------------------------------------------------------------
-- Настройки внутренних отступов (Padding) фрейма-обёртки
-- -----------------------------------------------------------------------
local PADDING_LEFT   = 8
local PADDING_RIGHT  = 8
local PADDING_TOP    = 8
local PADDING_BOTTOM = 8

-- -----------------------------------------------------------------------
-- Логика изменения прозрачности при наведении (Hover Alpha)
-- -----------------------------------------------------------------------
local function GetRowAlphas()
    local s = HealcraftDB and HealcraftDB.settings
    -- Значения по умолчанию, если настройки еще не созданы в БД
    local normal = (s and s.alphaButtons or 80) / 100
    local hover  = (s and s.alphaButtonsHover or 100) / 100
    return normal, hover
end

local function UpdateHoverAlpha(row)
    if not row then return end
    local isOver = false
    
    -- Проверяем, наведен ли курсор на обертку
    if row.visual and row.visual:IsVisible() and row.visual:IsMouseOver() then
        isOver = true
    else
        -- Дополнительно проверяем кнопки (защита от потери фокуса на стыках)
        for i = 1, MAX_SUPPORTED_SLOTS do
            local slot = row.slots[i]
            if slot and slot:IsVisible() and slot:IsMouseOver() then
                isOver = true
                break
            end
        end
    end

    local normalAlpha, hoverAlpha = GetRowAlphas()
    row.frame:SetAlpha(isOver and hoverAlpha or normalAlpha)
end

-- Function that switches the button click mode
function ns.UpdateCastingBehavior()
    -- Check if DB is loaded. If not - default false (allowed to drag)
    local isLocked = false
    if HealcraftDB and HealcraftDB.settings and type(HealcraftDB.settings.lockSpells) == "boolean" then
        isLocked = HealcraftDB.settings.lockSpells
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
    -- Iterate over all created rows
    local s = HealcraftDB.settings
    for unitID, row in pairs(rows) do
        -- Update cooldowns only if the player frame is currently visible
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
-- Range Check (Optimized timer)
-- -----------------------------------------------------------------------
local RANGE_CHECK_INTERVAL = 0.2 -- Check 5 times per second
local rangeTimer = 0

local rangeFrame = CreateFrame("Frame")
rangeFrame:SetScript("OnUpdate", function(self, elapsed)
    local s = HealcraftDB.settings
    if not ns.IsActive() or not s.rangeCheck then return end

    rangeTimer = rangeTimer + elapsed

    -- Once 0.2 sec has passed, do the check
    if rangeTimer >= RANGE_CHECK_INTERVAL then
        rangeTimer = 0
        
        -- Iterate only over existing rows
        for unitID, row in pairs(rows) do
            -- Check only if the row is visible (party member exists)
            if row.frame:IsVisible() then
                for i = 1, s.slotsCount do
                    local slot = row.slots[i]
                    if slot.spellName then
                        -- IsSpellInRange natively understands string spell names in 3.3.5
                        local inRange = IsSpellInRange(slot.spellName, slot.unitID)
                        
                        -- If 0 is returned, the spell definitely doesn't reach the target
                        if inRange == 0 then
                            slot.outOfRange:Show()
                        else
                            -- In all other cases (in range or invalid target) - hide
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
    if not HealcraftDB then HealcraftDB = {} end
    return HealcraftDB
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
    
    -- Update cooldowns so a freshly cast spell shows the correct timer
    UpdateCooldowns()
    ns.UpdateSlotsVisibility()
end

local function ClearSlot(slot)
    slot.spellName = nil
    slot.icon:Hide()
    if slot.cd then slot.cd:Hide() end
    if slot.outOfRange then slot.outOfRange:Hide() end
    SaveSlot(slot.unitID, slot.slotIndex, nil)

    -- Clear attributes (only outside combat, it's forbidden by the game core during combat)
    if not InCombatLockdown() then
        slot:SetAttribute("type", nil)
        slot:SetAttribute("spell", nil)
    end
    ns.UpdateSlotsVisibility()
end

-- -----------------------------------------------------------------------
-- Проверка модификаторов для начала перетаскивания
-- -----------------------------------------------------------------------
local function IsDragAllowed()
    local s = HealcraftDB and HealcraftDB.settings
    if not s then return true end

    -- Если настройка включена, но соответствующая клавиша НЕ зажата — блокируем drag
    if s.dragCtrl and not IsControlKeyDown() then
        return false
    end
    if s.dragAlt and not IsAltKeyDown() then
        return false
    end
    if s.dragShift and not IsShiftKeyDown() then
        return false
    end

    -- Во всех остальных случаях (или если галочки не стоят вообще) — разрешаем
    return true
end

-- -----------------------------------------------------------------------
-- Create one spell slot
-- -----------------------------------------------------------------------
local function CreateSpellSlot(parent, unitID, slotIndex)
    local s = HealcraftDB.settings
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
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    slot.icon = icon

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints(icon) -- Cooldown will cover only the icon itself
    cd:SetReverse(false)  -- Normal darkening
    slot.cd = cd

    local outOfRange = slot:CreateTexture(nil, "OVERLAY")
    outOfRange:SetAllPoints(icon) -- Layer overlays the icon itself
    -- Set color: Red (R=1, G=0, B=0) with 60% transparency (Alpha=0.6)
    outOfRange:SetTexture(1, 0, 0, 0.6) 
    outOfRange:Hide() -- Hidden by default
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
            local s = HealcraftDB.settings
            local progress = self.elapsed / 0.6
            
            if s.flashMode == 1 then
                flash:SetAlpha(1 - progress)
            elseif s.flashMode == 2 then
                flash:SetAlpha(1)
            elseif s.flashMode == 3 then
                -- 1. Smooth fade in and out (Sine wave: 0 -> 1 -> 0)
                flash:SetAlpha(math.sin(progress * math.pi))
                
                -- 2. Rotate the texture clockwise
                -- Rotate 90 degrees (math.pi / 2) over the animation duration
                local angle = progress * (math.pi / 2)
                local cosA, sinA = math.cos(angle), math.sin(angle)
                
                -- Texture coordinate rotation matrix around center (0.5, 0.5)
                local ULx, ULy = 0.5 - 0.5*cosA + 0.5*sinA, 0.5 - 0.5*sinA - 0.5*cosA
                local LLx, LLy = 0.5 - 0.5*cosA - 0.5*sinA, 0.5 - 0.5*sinA + 0.5*cosA
                local URx, URy = 0.5 + 0.5*cosA + 0.5*sinA, 0.5 + 0.5*sinA - 0.5*cosA
                local LRx, LRy = 0.5 + 0.5*cosA - 0.5*sinA, 0.5 + 0.5*sinA + 0.5*cosA
                
                flash:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
            end
        end
    end)

    slot.PlayFlash = function()
        local s = HealcraftDB.settings
        if not s.flashMode or s.flashMode == 0 then return end 

        flash:ClearAllPoints()
        flash:SetTexCoord(0, 1, 0, 1) -- Always reset coords to default
        
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
            flash:SetSize(s.slotSize * 1.25, s.slotSize * 1.25) -- 2x smaller
            flash:SetTexture("Interface\\Cooldown\\star4")
            flash:SetVertexColor(1, 1, 1, 1) -- White color
        end
        
        -- For mode 3 alpha starts at 0 to fade in smoothly
        flash:SetAlpha(s.flashMode == 3 and 0 or 1)
        flash:Show()
        fader.elapsed = 0
        fader:Show()
    end

    local hl = slot:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints(slot)
    hl:SetBlendMode("ADD")
    slot.hl = hl -- Keep reference for later use!

    slot:EnableMouse(true)
    slot:RegisterForDrag("LeftButton")

    -- Хуки для отслеживания наведения мыши на кнопки
    slot:HookScript("OnEnter", function(self)
        if rows[self.unitID] then UpdateHoverAlpha(rows[self.unitID]) end

        if not HealcraftDB.settings.showTooltips then return end
        
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
    slot:HookScript("OnLeave", function(self)
        if rows[self.unitID] then UpdateHoverAlpha(rows[self.unitID]) end
        GameTooltip:Hide()
    end)

    -- -----------------------------------------------------------------------
    -- Receive Drag / Swap Logic
    -- -----------------------------------------------------------------------
    
    local function HandleReceiveSpell(self, id, subType)
        local name, _, texture = GetSpellInfo(id, subType)
    
        if name and texture then
            -- Remember the old spell (if any)
            local oldName = self.spellName
    
            -- Fill the slot (FillSlot will update attributes to type="spell")
            FillSlot(self, name, texture)
            SaveSlot(self.unitID, self.slotIndex, name)
            ClearCursor() -- Clear cursor just in case
    
            -- If there was already a spell in the slot, pick it up on the cursor
            if oldName then
                PickupSpell(oldName)
            end
            return true
        else
            return false
        end
    end
    
    local function TryReceiveSpell(self)
        -- Block adding if locked or in combat
        if InCombatLockdown() or HealcraftDB.settings.lockSpells then
            return false
        end

        local infoType, id, subType = GetCursorInfo()
        if infoType == "spell" then
            return HandleReceiveSpell(self, id, subType)
        end
        return false
    end

    slot:SetScript("OnReceiveDrag", TryReceiveSpell)

    slot:SetScript("PreClick", function(self, button)
        -- Handle drop only with left mouse button
        if button ~= "LeftButton" then return end
        
        -- Block click-to-drop if locked or in combat
        if InCombatLockdown() or HealcraftDB.settings.lockSpells then
            self.isDropping = false
            return
        end

        local infoType, id, subType = GetCursorInfo()
        if infoType == "spell" then
            self.isDropping = true
            -- Save spell data before the client clears the cursor
            self.dropID = id
            self.dropSubType = subType
            
            if not InCombatLockdown() then
                -- Temporarily remove type so SecureActionButton doesn't cast the spell on this click
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
            if not InCombatLockdown() and not HealcraftDB.settings.lockSpells then
                -- Call our swap function
                local success = HandleReceiveSpell(self, self.dropID, self.dropSubType)
                
                -- If something went wrong (returned false), restore the old attribute
                if not success and self.oldType then
                    self:SetAttribute("type", self.oldType)
                end
            elseif self.oldType then
                self:SetAttribute("type", self.oldType)
            end
        end
    end)

-- drag start (pick up spell from slot like action bar)
    slot:SetScript("OnDragStart", function(self)
        if self.spellName and not InCombatLockdown() and not HealcraftDB.settings.lockSpells then
            -- Проверяем, зажаты ли требуемые модификаторы перед тем, как «взять» заклинание
            if IsDragAllowed() then
                PickupSpell(self.spellName)
                ClearSlot(self)
            end
        end
    end)

    return slot
end

-- -----------------------------------------------------------------------
-- Create row for one party member
-- -----------------------------------------------------------------------

local function CreateRow(unitID, anchor)
    if rows[unitID] then return end

    -- 1. Невидимый логический фрейм-контейнер (не ловит мышь)
    local rowFrame = CreateFrame("Frame", ADDON_NAME .. "Row_" .. unitID, anchor) 
    rowFrame:SetSize(1, 1) -- Размер символический, все привязки пойдут к дочерним элементам

    -- 2. Визуальный фрейм-обертка (фон аддона и сенсор наведения мыши)
    local visual = CreateFrame("Frame", nil, rowFrame)
    visual:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 8,
        insets   = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    visual:SetBackdropColor(1, 0, 0, 0.45)    -- Красный полупрозрачный фон для теста
    visual:SetBackdropBorderColor(1, 0, 0, 0.7) -- Граница
    visual:SetFrameLevel(rowFrame:GetFrameLevel()) -- На уровень ниже кнопок (фон)
    visual:EnableMouse(true)

    -- Обработка наведения мыши на сам фон обёртки
    visual:SetScript("OnEnter", function()
        UpdateHoverAlpha(rows[unitID])
    end)
    visual:SetScript("OnLeave", function()
        UpdateHoverAlpha(rows[unitID])
    end)

    -- 3. Создаем слоты (их родителем является rowFrame)
    local slots = {}
    for i = 1, MAX_SUPPORTED_SLOTS do
        local slot = CreateSpellSlot(rowFrame, unitID, i)
        slot:SetFrameLevel(rowFrame:GetFrameLevel() + 2) -- Кнопки ВСЕГДА поверх фона обертки
        slots[i] = slot
    end

    rowFrame:Hide()
    rows[unitID] = { frame = rowFrame, visual = visual, slots = slots }
end

-- -----------------------------------------------------------------------
-- Load saved spells into row slots (called after spellbook is available)
-- -----------------------------------------------------------------------

local function LoadRow(unitID)
    if not rows[unitID] then return end
    local s = HealcraftDB.settings
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
    local isActive = ns.IsActive() -- Check master switch

    for i = 1, 4 do
        local unitID = "party" .. i
        if rows[unitID] then
            -- If addon is on AND player is in a group
            if isActive and i <= groupSize then
                rows[unitID].frame:Show()
            else
                -- Otherwise hide all slots
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
-- API for other addon modules
-- -----------------------------------------------------------------------
-- Function to trigger flash from other files
function ns.FlashSpellSlot(unitID, spellName)
    if rows[unitID] then
        local s = HealcraftDB.settings
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
        local s = HealcraftDB.settings
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
    local s = HealcraftDB.settings

    -- If locked or in combat, do not consider dragging as a reason to show slots
    if InCombatLockdown() or s.lockSpells then
        isDraggingSpell = false
    end

    for unitID, row in pairs(rows) do
        for i = 1, s.slotsCount do
            local slot = row.slots[i]
            if slot.spellName or isDraggingSpell then
                -- Show the slot
                slot:SetBackdropColor(0, 0, 0, 0.85)
                slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
                -- Restore blue highlight on hover
                if slot.hl then slot.hl:SetAlpha(1) end 
            else
                -- Make the slot invisible
                slot:SetBackdropColor(0, 0, 0, 0)
                slot:SetBackdropBorderColor(0, 0, 0, 0)
                -- Disable hover glow (hide the layer)
                if slot.hl then slot.hl:SetAlpha(0) end 
            end
        end
    end
end

function ns.RefreshLayout()
    if not HealcraftDB or not HealcraftDB.settings then return end
    -- Изменять структуру фреймов во время боя запрещено защищенными механизмами игры
    if InCombatLockdown() then return end 

    local s = HealcraftDB.settings
    local numRows = s.rows or 1 -- По умолчанию 1 ряд

    for unitID, rowData in pairs(rows) do
        local anchor = FRAMES[unitID]
        if anchor then
            -- 1. Позиционируем базовый невидимый фрейм-контейнер (он центрирован по высоте)
            rowData.frame:ClearAllPoints()
            rowData.frame:SetPoint("LEFT", anchor, "RIGHT", tonumber(s.offsetX) or 0, tonumber(s.offsetY) or 0)

            -- Вычисляем распределение слотов по рядам
            local slotsRow1 = s.slotsCount
            if numRows == 2 then
                slotsRow1 = math.ceil(s.slotsCount / 2)
            end

            -- Вычисляем общую высоту сетки и сдвиг вверх для вертикального центрирования
            local totalGridHeight
            if numRows == 2 then
                totalGridHeight = 2 * s.slotSize + s.slotGap
            else
                totalGridHeight = s.slotSize
            end
            local shiftY = totalGridHeight / 2 -- Сдвиг вверх на половину высоты блока

            -- 2. Пересчитываем положение кнопок
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = rowData.slots[i]
                if i <= s.slotsCount then
                    slot:SetSize(s.slotSize, s.slotSize)
                    slot:ClearAllPoints()
                    
                    if numRows == 2 then
                        if i <= slotsRow1 then
                            -- Первый ряд (Сверху)
                            if i == 1 then
                                -- Смещаем первый слот вверх на shiftY, чтобы отцентрировать всю группу
                                slot:SetPoint("TOPLEFT", rowData.frame, "TOPLEFT", 0, shiftY)
                            else
                                slot:SetPoint("LEFT", rowData.slots[i-1], "RIGHT", s.slotGap, 0)
                            end
                        else
                            -- Второй ряд (Снизу)
                            if i == slotsRow1 + 1 then
                                -- Вторая строка встает под первой кнопкой с отступом вниз
                                slot:SetPoint("TOPLEFT", rowData.slots[1], "BOTTOMLEFT", 0, -s.slotGap)
                            else
                                slot:SetPoint("LEFT", rowData.slots[i-1], "RIGHT", s.slotGap, 0)
                            end
                        end
                    else
                        -- Обычный один ряд
                        if i == 1 then
                            -- Смещаем единственный ряд вверх на половину высоты кнопки
                            slot:SetPoint("TOPLEFT", rowData.frame, "TOPLEFT", 0, shiftY)
                        else
                            slot:SetPoint("LEFT", rowData.slots[i-1], "RIGHT", s.slotGap, 0)
                        end
                    end
                    slot:Show()
                else
                    slot:Hide()
                end

                if not ns.IsActive() or not s.rangeCheck then
                    slot.outOfRange:Hide()
                end
            end

            -- 3. Вычисляем крайние активные (непустые) кнопки в двумерной сетке
            local cursorType = GetCursorInfo()
            local isDraggingSpell = (cursorType == "spell")
            if InCombatLockdown() or s.lockSpells then
                isDraggingSpell = false
            end

            local minCol, maxCol, minRow, maxRow = nil, nil, nil, nil
            for i = 1, s.slotsCount do
                local slot = rowData.slots[i]
                if slot.spellName or isDraggingSpell then
                    local rowNum, colNum
                    if numRows == 2 then
                        if i <= slotsRow1 then
                            rowNum = 1
                            colNum = i
                        else
                            rowNum = 2
                            colNum = i - slotsRow1
                        end
                    else
                        rowNum = 1
                        colNum = i
                    end

                    if not minCol or colNum < minCol then minCol = colNum end
                    if not maxCol or colNum > maxCol then maxCol = colNum end
                    if not minRow or rowNum < minRow then minRow = rowNum end
                    if not maxRow or rowNum > maxRow then maxRow = rowNum end
                end
            end

            -- 4. Растягиваем визуальную обертку rowData.visual по вычисленной сетке
            if minCol and maxCol and minRow and maxRow then
                -- Математический расчет координат с учетом вертикального сдвига shiftY
                local x1 = (minCol - 1) * (s.slotSize + s.slotGap) - PADDING_LEFT
                local x2 = maxCol * (s.slotSize + s.slotGap) - s.slotGap + PADDING_RIGHT
                
                local y1 = shiftY - (minRow - 1) * (s.slotSize + s.slotGap) + PADDING_TOP
                local y2 = shiftY - (maxRow * (s.slotSize + s.slotGap) - s.slotGap) - PADDING_BOTTOM

                rowData.visual:ClearAllPoints()
                rowData.visual:SetPoint("TOPLEFT", rowData.frame, "TOPLEFT", x1, y1)
                rowData.visual:SetPoint("BOTTOMRIGHT", rowData.frame, "TOPLEFT", x2, y2)
                rowData.visual:Show()
            else
                rowData.visual:Hide()
            end

            -- Принудительно обновляем прозрачность с учетом текущего положения курсора
            UpdateHoverAlpha(rowData)
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
        -- 1. First load the database and settings
        ns.InitDB()

        -- 2. Then create UI
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
        
        -- Set the correct button mode on load
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
        -- Вызываем RefreshLayout при изменении состояния курсора,
        -- чтобы фон обертки моментально реагировал на начало/конец перетаскивания заклинания.
        if ns.IsActive() then ns.RefreshLayout() end

    elseif event == "UNIT_AURA" then
        -- Call the buff update function
        -- It internally checks if this arg1 belongs to our group
        if ns.IsActive() then ns.UpdateBuffs(arg1) end
    end
end)