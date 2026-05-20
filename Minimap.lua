local addonName, ns = ...

-- Создаем кнопку для мини-карты
local minimapButton = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
minimapButton:SetSize(32, 32)

minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(1)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- ХИТРОСТЬ ДЛЯ SexyMap: 
-- 1. Говорим ему, что мы "сами" управляем движением (он не тронет наши скрипты)
-- 2. При этом он видит кнопку и управляет её видимостью/затуханием
minimapButton.sexyMapMovable = true 

-- Сама иконка
local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Стандартная близардовская рамка
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

-- -----------------------------------------------------------------------
-- Логика перетаскивания (С учетом формы карты для SexyMap)
-- -----------------------------------------------------------------------
local function UpdatePosition(angle)
    local cos = math.cos(angle)
    local sin = math.sin(angle)
    
    -- --- НАСТРОЙКИ ОРБИТЫ ---
    local radius = 72 -- Попробуй 76, 77 или 78. Чем меньше число, тем ближе к центру.
    local squareExp = 106 -- Коэффициент выталкивания в углы для квадрата (в Dominos 110)
    -- ------------------------

    local shape = GetMinimapShape and GetMinimapShape() or "ROUND"
    local isRound = true
    if shape == "SQUARE" then isRound = false
    elseif shape == "CORNER-TOPRIGHT" then isRound = not(cos < 0 or sin < 0)
    elseif shape == "CORNER-TOPLEFT" then isRound = not(cos > 0 or sin < 0)
    elseif shape == "CORNER-BOTTOMRIGHT" then isRound = not(cos < 0 or sin > 0)
    elseif shape == "CORNER-BOTTOMLEFT" then isRound = not(cos > 0 or sin > 0)
    elseif shape == "SIDE-LEFT" then isRound = cos <= 0
    elseif shape == "SIDE-RIGHT" then isRound = cos >= 0
    elseif shape == "SIDE-TOP" then isRound = sin <= 0
    elseif shape == "SIDE-BOTTOM" then isRound = sin >= 0
    end

    local x, y
    if isRound then
        -- Обычный круг
        x = cos * radius
        y = sin * radius
    else
        -- Квадратная математика Dominos, но с твоим радиусом
        -- Мы ограничиваем (clamp) иконку, чтобы она не улетала за края текстуры
        x = math.max(-(radius + 2), math.min(squareExp * cos, radius + 4))
        y = math.max(-(radius + 6), math.min(squareExp * sin, radius + 2))
    end

    minimapButton:ClearAllPoints()
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

    if PartySpellsDB.settings.lockSpells then
        icon:SetTexture("Interface\\Icons\\Spell_Nature_Rejuvenation") 
    else
        icon:SetTexture("Interface\\Icons\\Spell_Nature_ResistNature") 
    end

    if ns.IsActive() then
        icon:SetDesaturated(false)
        icon:SetVertexColor(1, 1, 1)
    else
        icon:SetDesaturated(true)
        icon:SetVertexColor(0.6, 0.6, 0.6)
    end
end

-- -----------------------------------------------------------------------
-- Клики и Тултипы (Без изменений)
-- -----------------------------------------------------------------------

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(addonName)
    
    local statusText = ns.IsActive() and "|cff00ff00Включен|r" or "|cff808080Выключен|r"
    GameTooltip:AddLine("Статус: " .. statusText)
    
    local lockText = (PartySpellsDB and PartySpellsDB.settings and PartySpellsDB.settings.lockSpells) 
                     and "|cff00ff00Да|r" 
                     or "|cff808080Нет|r"
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
    if IsShiftKeyDown() then
        if InCombatLockdown() then
            print("|cffff0000[PartySpells]|r Нельзя менять закрепление заклинаний во время боя!")
            return
        end
        PartySpellsDB.settings.lockSpells = not PartySpellsDB.settings.lockSpells
        if ns.UpdateCastingBehavior then ns.UpdateCastingBehavior() end
        local cb = _G[addonName .. "lockSpellsCheckButton"]
        if cb then cb:SetChecked(PartySpellsDB.settings.lockSpells) end
        ns.UpdateMinimapIcon()
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
        return
    end

    if button == "RightButton" then
        if ns.OpenSettings then ns.OpenSettings() end
    elseif button == "LeftButton" then
        if ns.ToggleActive then ns.ToggleActive() end
        if GameTooltip:IsOwned(self) then ShowTooltip(self) end
    end
end)

minimapButton:SetScript("OnEnter", function(self) ShowTooltip(self) end)
minimapButton:SetScript("OnLeave", function() GameTooltip:Hide() end)

-- -----------------------------------------------------------------------
-- Загрузка позиции (Тут поправлен расчет дефолтного угла)
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Если угла в базе нет, ставим стандартный (радианы)
    local angle = (PartySpellsDB and PartySpellsDB.minimapAngle) or 3.92 -- 225 градусов
    UpdatePosition(angle)
    ns.UpdateMinimapIcon()
end)