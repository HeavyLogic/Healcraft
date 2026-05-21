local addonName, ns = ...

-- Create the minimap button
local minimapButton = CreateFrame("Button", addonName .. "MinimapButton", Minimap)
minimapButton:SetSize(32, 32)

minimapButton:SetFrameStrata("MEDIUM")
minimapButton:SetFrameLevel(1)
minimapButton:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

-- SexyMap support:
-- Tell it we manage the movement ourselves
-- It still sees the button and manages its visibility/fading
minimapButton.sexyMapMovable = true

-- The icon itself
local icon = minimapButton:CreateTexture(nil, "BACKGROUND")
icon:SetSize(20, 20)
icon:SetPoint("CENTER", minimapButton, "CENTER", 0, 0)
icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

-- Standard Blizzard border
local border = minimapButton:CreateTexture(nil, "OVERLAY")
border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
border:SetSize(54, 54)
border:SetPoint("TOPLEFT", minimapButton, "TOPLEFT", 0, 0)

-- -----------------------------------------------------------------------
-- Drag logic (With SexyMap shape awareness)
-- -----------------------------------------------------------------------
local function UpdatePosition(angle)
    local cos = math.cos(angle)
    local sin = math.sin(angle)
    
    -- --- ORBIT SETTINGS ---
    local radius = 72 -- Try 76, 77 or 78. Smaller values = closer to the center.
    local squareExp = 106 -- Corner push-out coefficient for square (110 in Dominos)
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
        -- Regular circle
        x = cos * radius
        y = sin * radius
    else
        -- Dominos square math with your radius
        -- We clamp the icon so it doesn't fly off the texture edges
        x = math.max(-(radius + 2), math.min(squareExp * cos, radius + 4))
        y = math.max(-(radius + 6), math.min(squareExp * sin, radius + 2))
    end

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

local dragTimer = 0
local DRAG_TICK = 0.02 -- Интервал обновления (0.02 сек = 50 FPS). Плавно, но ограничено.

minimapButton:RegisterForDrag("LeftButton")
minimapButton:SetScript("OnDragStart", function(self)
    self:LockHighlight()
    
    local scale = Minimap:GetEffectiveScale()
    local mx, my = Minimap:GetCenter()
    
    if not HealcraftDB then HealcraftDB = {} end
    dragTimer = 0 -- Сбрасываем таймер перед началом
    
    self:SetScript("OnUpdate", function(f, elapsed)
        dragTimer = dragTimer + elapsed
        if dragTimer >= DRAG_TICK then
            dragTimer = 0 -- Сбрасываем накопитель времени
            
            local px, py = GetCursorPosition()
            px, py = px / scale, py / scale
            
            local angle = math.atan2(py - my, px - mx)
            HealcraftDB.minimapAngle = angle
            
            UpdatePosition(angle)
        end
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:UnlockHighlight()
    self:SetScript("OnUpdate", nil) -- Полностью убираем OnUpdate
end)

-- -----------------------------------------------------------------------
-- Icon visual status
-- -----------------------------------------------------------------------
function ns.UpdateMinimapIcon()
    if not HealcraftDB or not HealcraftDB.settings then return end

    if HealcraftDB.settings.lockSpells then
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
-- Clicks and Tooltips
-- -----------------------------------------------------------------------

local function ShowTooltip(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(addonName)
    
    local statusText = ns.IsActive() and "|cff00ff00On|r" or "|cff808080Off|r"
    GameTooltip:AddLine("Status: " .. statusText)
    
    local lockText = (HealcraftDB and HealcraftDB.settings and HealcraftDB.settings.lockSpells) 
                     and "|cff00ff00Yes|r" 
                     or "|cff808080No|r"
    GameTooltip:AddLine("Locked: " .. lockText)
    
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Left click - toggle addon on/off", 1, 1, 1)
    GameTooltip:AddLine("Right click - settings", 1, 1, 1)
    GameTooltip:AddLine("Shift+Click - lock spells", 1, 1, 1)
    GameTooltip:AddLine("Drag - move icon", 0.5, 0.5, 0.5)
    GameTooltip:Show()
end

minimapButton:RegisterForClicks("RightButtonUp", "LeftButtonUp")
minimapButton:SetScript("OnClick", function(self, button)
    if IsShiftKeyDown() then
        if InCombatLockdown() then
            print("|cffff0000[Healcraft]|r Cannot change spell locking during combat!")
            return
        end
        HealcraftDB.settings.lockSpells = not HealcraftDB.settings.lockSpells
        if ns.UpdateCastingBehavior then ns.UpdateCastingBehavior() end
        local cb = _G[addonName .. "lockSpellsCheckButton"]
        if cb then cb:SetChecked(HealcraftDB.settings.lockSpells) end
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
-- Load position (Default angle calculation fixed here)
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- If no angle in DB, use default (radians)
    local angle = (HealcraftDB and HealcraftDB.minimapAngle) or 3.92 -- 225 degrees
    UpdatePosition(angle)
    ns.UpdateMinimapIcon()
end)