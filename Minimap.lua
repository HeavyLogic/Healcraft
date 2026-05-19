local addonName, ns = ...

-- Создаем кнопку для мини-карты
local minimapButton = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
minimapButton:SetSize(32, 32)
minimapButton:SetFrameLevel(8)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- Сама иконка
local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetTexture("Interface\\Icons\\Spell_Nature_Rejuvenation")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
-- Обрезаем края иконки, чтобы она лучше смотрелась в круглом обрамлении
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
    -- Радиус мини-карты примерно равен 80
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
        
        -- Вычисляем угол между центром мини-карты и курсором
        local angle = math.atan2(py - my, px - mx)
        
        -- Сохраняем угол в БД аддона
        if not PartySpellsDB then PartySpellsDB = {} end
        PartySpellsDB.minimapAngle = angle
        
        UpdatePosition(angle)
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil) -- Отключаем просчет позиции при отпускании
end)

-- -----------------------------------------------------------------------
-- Визуальный статус иконки
-- -----------------------------------------------------------------------
function ns.UpdateMinimapIcon()
    if ns.IsActive() then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
    else
        -- Делаем иконку черно-белой и слегка темной, если аддон выключен
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.6, 0.6, 0.6)
    end
end

-- -----------------------------------------------------------------------
-- Клики и Тултипы
-- -----------------------------------------------------------------------
minimapButton:RegisterForClicks("RightButtonUp", "LeftButtonUp")
minimapButton:SetScript("OnClick", function(self, button)
    if button == "RightButton" then
        if ns.OpenSettings then ns.OpenSettings() end
    elseif button == "LeftButton" then
        if ns.ToggleActive then ns.ToggleActive() end
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(addonName)
    local statusText = ns.IsActive() and "|cff00ff00Включен|r" or "|cff808080Выключен|r"
    GameTooltip:AddLine("Статус: " .. statusText)
    GameTooltip:AddLine("Левый клик - вкл/выкл аддон", 1, 1, 1)
    GameTooltip:AddLine("Правый клик - настройки", 1, 1, 1)
    GameTooltip:AddLine("Shift + Перетаскивание - переместить", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

-- Обновляем цвет иконки при старте
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    local angle = (PartySpellsDB and PartySpellsDB.minimapAngle) or math.rad(225)
    UpdatePosition(angle)
    ns.UpdateMinimapIcon()
end)

-- -----------------------------------------------------------------------
-- Загрузка позиции при старте игры
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Загружаем сохраненный угол. Если его еще нет, ставим 225 градусов (снизу слева)
    local angle = (PartySpellsDB and PartySpellsDB.minimapAngle) or math.rad(225)
    UpdatePosition(angle)
end)