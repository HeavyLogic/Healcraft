local addonName, ns = ...

-- Создаем кнопку для мини-карты
local minimapButton = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
minimapButton:SetSize(32, 32)
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Сама иконка (текстура будет задаваться динамически в функции UpdateMinimapIcon)
local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Стандартная близардовская рамка для мини-карты
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

-- -----------------------------------------------------------------------
-- Логика перетаскивания (Движение по кругу)
-- -----------------------------------------------------------------------
local function UpdatePosition(angle)
    local radius = 80
    local x = math.cos(angle) * radius
    local y = math.sin(angle) * radius
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    self:SetScript("OnUpdate", function()
        local mx, my = Minimap:GetCenter()
        local px, py = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        px, py = px / scale, py / scale
        
        local angle = math.atan2(py - my, px - mx)
        
        if not PartySpellsDB then PartySpellsDB = {} end
        PartySpellsDB.minimapAngle = angle
        
        UpdatePosition(angle)
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil)
end)

-- -----------------------------------------------------------------------
-- Визуальный статус иконки
-- -----------------------------------------------------------------------
function ns.UpdateMinimapIcon()
    if not PartySpellsDB or not PartySpellsDB.settings then return end

    -- Меняем саму текстуру в зависимости от закрепления
    if PartySpellsDB.settings.lockSpells then
        -- Фиолетовая (Омоложение)
        icon:SetTexture("Interface\\Icons\\Spell_Nature_Rejuvenation") 
    else
        -- Зеленая (Восстановление)
        icon:SetTexture("Interface\\Icons\\Spell_Nature_ResistNature") 
    end

    -- Меняем цвет (вкл/выкл аддон)
    if ns.IsActive() then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
    else
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.6, 0.6, 0.6)
    end
end

-- -----------------------------------------------------------------------
-- Клики и Тултипы
-- -----------------------------------------------------------------------

-- Локальная функция для отрисовки тултипа (чтобы вызывать ее на лету)
local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(addonName)
    
    local statusText = ns.IsActive() and "|cff00ff00Включен|r" or "|cff808080Выключен|r"
    GameTooltip:AddLine("Статус: " .. statusText)
    
    local lockText = (PartySpellsDB and PartySpellsDB.settings and PartySpellsDB.settings.lockSpells) 
                     and "|cff00ff00Да (Фиолетовая)|r" 
                     or "|cff808080Нет (Зеленая)|r"
    GameTooltip:AddLine("Закреплено: " .. lockText)
    
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Левый клик - вкл/выкл аддон", 1, 1, 1)
    GameTooltip:AddLine("Правый клик - настройки", 1, 1, 1)
    GameTooltip:AddLine("Shift + Клик - закрепить заклинания", 1, 1, 1)
    GameTooltip:AddLine("Перетаскивание - переместить иконку", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

minimapButton:RegisterForClicks("RightButtonUp", "LeftButtonUp")
minimapButton:SetScript("OnClick", function(self, button)
    -- Shift + Клик: Смена режима закрепления
    if IsShiftKeyDown() then
        if InCombatLockdown() then
            print("|cffff0000[PartySpells]|r Нельзя менять закрепление заклинаний во время боя!")
            return
        end
        
        PartySpellsDB.settings.lockSpells = not PartySpellsDB.settings.lockSpells
        
        -- Обновляем поведение кнопок
        if ns.UpdateCastingBehavior then 
            ns.UpdateCastingBehavior() 
        end
        
        -- Синхронизируем окно настроек
        local cb = _G[addonName .. "LockSpellsCheckbox"]
        if cb then cb:SetChecked(PartySpellsDB.settings.lockSpells) end
        
        -- Обновляем иконку
        ns.UpdateMinimapIcon()
        
        -- ПЕРЕРИСОВЫВАЕМ ТУЛТИП НА ЛЕТУ
        if GameTooltip:IsOwned(self) then
            ShowTooltip(self)
        end
        
        return
    end

    -- Обычные клики (без Shift)
    if button == "RightButton" then
        if ns.OpenSettings then ns.OpenSettings() end
    elseif button == "LeftButton" then
        if ns.ToggleActive then ns.ToggleActive() end
        -- Также обновляем тултип на лету для смены статуса (Включен/Выключен)
        if GameTooltip:IsOwned(self) then
            ShowTooltip(self)
        end
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    ShowTooltip(self)
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- -----------------------------------------------------------------------
-- Загрузка позиции и состояний при старте игры
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local angle = (PartySpellsDB and PartySpellsDB.minimapAngle) or math.rad(225)
    UpdatePosition(angle)
    ns.UpdateMinimapIcon()
end)