local addonName, ns = ...

-- -----------------------------------------------------------------------
-- Инициализация Базы Данных
-- -----------------------------------------------------------------------
function ns.InitDB()
    if not PartySpellsDB then PartySpellsDB = {} end
    if type(PartySpellsDB.isActive) ~= "boolean" then PartySpellsDB.isActive = true end
    if not PartySpellsDB.settings then PartySpellsDB.settings = {} end

    -- Настройки по умолчанию
    local defs = {
        slotsCount = 5,
        slotSize   = 32,
        slotGap    = -1,
        offsetX    = -7,
        offsetY    = 6,
        flashMode  = 2,
        lockSpells = false,
        alphaButtons = 80,
        -- Настройки Buffs:
        buffsActive = true,
        showTimer   = true,
        alphaBuffs  = 80,
    }
    for k, v in pairs(defs) do
        if PartySpellsDB.settings[k] == nil then
            PartySpellsDB.settings[k] = v
        end
    end
end

-- -----------------------------------------------------------------------
-- Master-Switch логика
-- -----------------------------------------------------------------------
function ns.IsActive() return PartySpellsDB and PartySpellsDB.isActive end
function ns.SetActive(state)
    PartySpellsDB.isActive = state
    if _G[addonName .. "ActiveCheckbox"] then _G[addonName .. "ActiveCheckbox"]:SetChecked(state) end
    if ns.UpdateMinimapIcon then ns.UpdateMinimapIcon() end
    if ns.RefreshAllVisibility then ns.RefreshAllVisibility() end
end
function ns.ToggleActive() ns.SetActive(not ns.IsActive()) end
function ns.OpenSettings()
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "MainPanel"])
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "MainPanel"])
end

-- -----------------------------------------------------------------------
-- Создание Окна Настроек
-- -----------------------------------------------------------------------
local mainPanel = CreateFrame("Frame", addonName .. "MainPanel", UIParent)
mainPanel.name = addonName
InterfaceOptions_AddCategory(mainPanel)

-- -----------------------------------------------------------------------
-- Наполнение вкладки General
-- -----------------------------------------------------------------------
local title = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("PartySpells: General")

local activeCb = CreateFrame("CheckButton", addonName .. "ActiveCheckbox", mainPanel, "InterfaceOptionsCheckButtonTemplate")
activeCb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
_G[activeCb:GetName() .. "Text"]:SetText(" Включить аддон (Master Switch)")
activeCb:SetScript("OnClick", function(self) ns.SetActive(self:GetChecked() ~= nil) end)

-- Шаблон создания слайдера
local function CreateSlider(name, text, minVal, maxVal, step, dbKey, x, y)
    local slider = CreateFrame("Slider", addonName..name.."Slider", mainPanel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", activeCb, "BOTTOMLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5) -- Округляем до целых
        PartySpellsDB.settings[dbKey] = value
        _G[self:GetName().."Text"]:SetText(text .. ": " .. value)
        
        -- Умное обновление
        if dbKey == "alphaBuffs" then
            if ns.RefreshAllBuffs then ns.RefreshAllBuffs() end
        else
            if ns.RefreshLayout then ns.RefreshLayout() end
        end
    end)
    return slider
end

-- === Левая колонка ===
local slotsSlider    = CreateSlider("Slots", "Кол-во слотов", 1, 5, 1, "slotsCount", 0, -20)
local sizeSlider     = CreateSlider("Size", "Размер слота", 18, 75, 1, "slotSize", 0, -70)
local gapSlider      = CreateSlider("Gap", "Отступ между слотами", -4, 30, 1, "slotGap", 0, -120)

-- Выпадающий список (Dropdown) переехал в левую колонку под слайдеры
local flashDD = CreateFrame("Frame", addonName.."FlashDropdown", mainPanel, "UIDropDownMenuTemplate")
-- UIDropDownMenu имеет скрытый пустой отступ слева, поэтому смещаем на X = -15, чтобы выровнять с ползунками
flashDD:SetPoint("TOPLEFT", activeCb, "BOTTOMLEFT", -15, -170) 
local flashLabel = flashDD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
flashLabel:SetPoint("BOTTOMLEFT", flashDD, "TOPLEFT", 16, 3)
flashLabel:SetText("Режим вспышки слота:")

local function InitFlashDropdown(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    local options = {
        { text = "0: Нет (Отключено)", value = 0 },
        { text = "1: Плавная заливка", value = 1 },
        { text = "2: Резкая рамка", value = 2 },
        { text = "3: Отблеск (Bling)", value = 3 }
    }
    for _, opt in ipairs(options) do
        info.text = opt.text
        info.arg1 = opt.value
        local currentMode = (PartySpellsDB and PartySpellsDB.settings and PartySpellsDB.settings.flashMode) or 2
        info.checked = (currentMode == opt.value)
        info.func = function(self, arg1)
            PartySpellsDB.settings.flashMode = arg1
            UIDropDownMenu_SetSelectedValue(flashDD, arg1)
            UIDropDownMenu_SetText(flashDD, opt.text)
        end
        UIDropDownMenu_AddButton(info)
    end
end
UIDropDownMenu_Initialize(flashDD, InitFlashDropdown)

local modeTexts = {
    [0] = "0: Нет", [1] = "1: Плавная заливка", [2] = "2: Резкая рамка", [3] = "3: Отблеск (Bling)"
}


-- === Правая колонка ===
local offsetXSlider   = CreateSlider("OffsetX", "Смещение по X", -12, 30, 1, "offsetX", 200, -20)
local offsetYSlider   = CreateSlider("OffsetY", "Смещение по Y", -20, 30, 1, "offsetY", 200, -70)
-- Прозрачность кнопок переехала в правую колонку
local btnAlphaSlider  = CreateSlider("BtnAlpha", "Прозрачность кнопок (%)", 10, 100, 5, "alphaButtons", 200, -120)


-- -----------------------------------------------------------------------
-- Различные переключатели
-- -----------------------------------------------------------------------
local lockSpellsCb = CreateFrame("CheckButton", addonName .. "LockSpellsCheckbox", mainPanel, "InterfaceOptionsCheckButtonTemplate")
lockSpellsCb:SetPoint("TOPLEFT", activeCb, "BOTTOMLEFT", 0, -220)
_G[lockSpellsCb:GetName() .. "Text"]:SetText(" Закрепить заклинания (Мгновенный каст, без Drag&Drop)")
lockSpellsCb:SetScript("OnClick", function(self)
    if InCombatLockdown() then
        print("|cffff0000[PartySpells]|r Нельзя менять эту настройку прямо во время боя!")
        self:SetChecked(PartySpellsDB.settings.lockSpells)
        return
    end
    PartySpellsDB.settings.lockSpells = (self:GetChecked() ~= nil)
    if ns.UpdateCastingBehavior then ns.UpdateCastingBehavior() end
end)

-- TODO: Модификаторы для перетаскивания
-- TODO: Спрятать подсказки

-- -----------------------------------------------------------------------
-- Настройки баффов
-- -----------------------------------------------------------------------
local buffsTitle = mainPanel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
buffsTitle:SetPoint("TOPLEFT", activeCb, "BOTTOMLEFT", 0, -260)
buffsTitle:SetText("Настройки модуля баффов:")

local buffsActiveCb = CreateFrame("CheckButton", addonName .. "BuffsActiveCheckbox", mainPanel, "InterfaceOptionsCheckButtonTemplate")
buffsActiveCb:SetPoint("TOPLEFT", buffsTitle, "BOTTOMLEFT", 0, -5)
_G[buffsActiveCb:GetName() .. "Text"]:SetText(" Включить отображение баффов")
buffsActiveCb:SetScript("OnClick", function(self)
    PartySpellsDB.settings.buffsActive = (self:GetChecked() ~= nil)
    if ns.RefreshAllBuffs then ns.RefreshAllBuffs() end
end)

local showTimerCb = CreateFrame("CheckButton", addonName .. "ShowTimerCheckbox", mainPanel, "InterfaceOptionsCheckButtonTemplate")
showTimerCb:SetPoint("TOPLEFT", buffsActiveCb, "BOTTOMLEFT", 0, -5)
_G[showTimerCb:GetName() .. "Text"]:SetText(" Показывать таймер на иконке")
showTimerCb:SetScript("OnClick", function(self)
    PartySpellsDB.settings.showTimer = (self:GetChecked() ~= nil)
    if ns.RefreshAllBuffs then ns.RefreshAllBuffs() end
end)

-- Прозрачность баффов (Создаем с заглушками координат, затем перевешиваем под чекбокс)
local buffAlphaSlider = CreateSlider("BuffAlpha", "Прозрачность баффов (%)", 10, 100, 5, "alphaBuffs", 0, 0)
buffAlphaSlider:ClearAllPoints()
buffAlphaSlider:SetPoint("TOPLEFT", showTimerCb, "BOTTOMLEFT", 0, -20)

-- -----------------------------------------------------------------------
-- Синхронизация UI с базой при загрузке
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    ns.InitDB()
    activeCb:SetChecked(ns.IsActive())
    
    local s = PartySpellsDB.settings
    slotsSlider:SetValue(s.slotsCount)
    sizeSlider:SetValue(s.slotSize)
    gapSlider:SetValue(s.slotGap)
    
    offsetXSlider:SetValue(s.offsetX)
    offsetYSlider:SetValue(s.offsetY)
    
    UIDropDownMenu_SetSelectedValue(flashDD, s.flashMode)
    UIDropDownMenu_SetText(flashDD, modeTexts[s.flashMode] or "1: Плавная заливка")
    
    btnAlphaSlider:SetValue(s.alphaButtons)
    buffAlphaSlider:SetValue(s.alphaBuffs)
    
    lockSpellsCb:SetChecked(s.lockSpells)
    buffsActiveCb:SetChecked(s.buffsActive)
    showTimerCb:SetChecked(s.showTimer)
end)