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
        isActive = true,
        slotsCount = 5,
        slotSize   = 32,
        slotGap    = -1,
        offsetX    = -7,
        offsetY    = 6,
        flashMode  = 3,
        lockSpells = false,
        alphaButtons = 80,
        buffsActive = true,
        showTimer   = true,
        alphaBuffs  = 80,
        showTooltips = false,
        showTooltipsBuffs = false,
    }
    for k, v in pairs(defs) do
        if PartySpellsDB.settings[k] == nil then
            PartySpellsDB.settings[k] = v
        end
    end
end

local FLASH_OPTIONS = {
    { text = "0: Нет (Отключено)", value = 0 },
    { text = "1: Плавная заливка", value = 1 },
    { text = "2: Резкая рамка", value = 2 },
    { text = "3: Отблеск (Bling)", value = 3 }
}

local FLASH_TEXTS = {}

for _, opt in ipairs(FLASH_OPTIONS) do
    FLASH_TEXTS[opt.value] = opt.text
end

-- -----------------------------------------------------------------------
-- Master-Switch логика
-- -----------------------------------------------------------------------
function ns.IsActive()
    return PartySpellsDB and PartySpellsDB.settings.isActive
end

function ns.SetActive(state)
    PartySpellsDB.settings.isActive = state
    if _G[addonName .. "isActiveCheckButton"] then _G[addonName .. "isActiveCheckButton"]:SetChecked(state) end
    if ns.UpdateMinimapIcon then ns.UpdateMinimapIcon() end
    if ns.RefreshAllVisibility then ns.RefreshAllVisibility() end
end

function ns.ToggleActive() ns.SetActive(not ns.IsActive()) end
-- -----------------------------------------------------------------------
-- Создание Окон Настроек (OmniCC Style)
-- -----------------------------------------------------------------------
function ns.OpenSettings()
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "GeneralPanel"])
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "GeneralPanel"])
end

local mainPanel = CreateFrame("Frame", addonName .. "MainPanel", UIParent)
mainPanel.name = addonName
InterfaceOptions_AddCategory(mainPanel)

local generalPanel = CreateFrame("Frame", addonName .. "GeneralPanel", mainPanel)
generalPanel.name = "General"
generalPanel.parent = addonName
InterfaceOptions_AddCategory(generalPanel)

local buffsPanel = CreateFrame("Frame", addonName .. "BuffsPanel", mainPanel)
buffsPanel.name = "Buffs"
buffsPanel.parent = addonName
InterfaceOptions_AddCategory(buffsPanel)

mainPanel:SetScript("OnShow", function()
    ns.OpenSettings()
end)

-- -----------------------------------------------------------------------
-- Шаблоны
-- -----------------------------------------------------------------------
local function RefreshVisuals(panelName)
    if panelName == "General" then
        if ns.RefreshLayout then ns.RefreshLayout() end
    elseif panelName == "Buffs" then
        if ns.RefreshAllBuffs then ns.RefreshAllBuffs() end
    end
end

-- Шаблон создания слайдера
local function CreateSlider(panel, text, minVal, maxVal, step, dbKey, alignFrom, x, y)
    local slider = CreateFrame("Slider", addonName..dbKey.."Slider", panel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5) -- Округляем до целых
        PartySpellsDB.settings[dbKey] = value
        _G[self:GetName().."Text"]:SetText(text .. ": " .. value)
        RefreshVisuals(panel.name)
    end)
    return slider
end

local function CreateCheckbox(panel, text, dbKey, alignFrom, x, y, callback)
    local checkbox = CreateFrame("CheckButton", addonName .. dbKey.."CheckButton", panel, "InterfaceOptionsCheckButtonTemplate")
    checkbox:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", x, y)
    _G[checkbox:GetName() .. "Text"]:SetText(" " .. text)

    checkbox:SetScript("OnClick", function(self)
        if callback then
            callback(self)
        else
            PartySpellsDB.settings[dbKey] = (self:GetChecked() ~= nil)
            RefreshVisuals(panel.name)
        end
    end)

    return checkbox
end
-- -----------------------------------------------------------------------
-- Наполнение вкладки General
-- -----------------------------------------------------------------------
local title = generalPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("PartySpells: General")

local gapYTitles = -16;
local gapYSliders = -32;
local gapYCheckboxes = -5;
local slidersOffset = 9;
local dropdownsOffset = 10;
local addYGap = 7;

-- Master switch
local activeCb = CreateCheckbox(generalPanel, "Включить аддон (Master Switch)", "isActive", title, 0, gapYTitles, function(self)
    ns.SetActive(self:GetChecked() ~= nil)
    print(self:GetName())
end)

-- === Левая колонка слайдеров ===
local slotsSlider    = CreateSlider(generalPanel, "Кол-во слотов", 1, 5, 1, "slotsCount", activeCb, slidersOffset, gapYSliders+addYGap)
local offsetXSlider   = CreateSlider(generalPanel, "Смещение по X", -12, 30, 1, "offsetX", slotsSlider, 0, gapYSliders)
local gapSlider      = CreateSlider(generalPanel, "Отступ между слотами", -4, 30, 1, "slotGap", offsetXSlider, 0, gapYSliders)

-- === Правая колонка слайдеров ===
local sizeSlider     = CreateSlider(generalPanel, "Размер слота", 18, 75, 1, "slotSize", activeCb, 200, gapYSliders+addYGap)
local offsetYSlider   = CreateSlider(generalPanel, "Смещение по Y", -20, 30, 1, "offsetY", sizeSlider, 0, gapYSliders)
local btnAlphaSlider   = CreateSlider(generalPanel, "Прозрачность", 10, 100, 5, "alphaButtons", offsetYSlider, 0, gapYSliders)

-- === Под колонками ===
-- Режим вспышки слота
local flashDD = CreateFrame("Frame", addonName.."FlashDropdown", generalPanel, "UIDropDownMenuTemplate")
flashDD:SetPoint("TOPLEFT", gapSlider, "BOTTOMLEFT", 0-slidersOffset-dropdownsOffset, gapYSliders-addYGap)
local flashLabel = flashDD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
flashLabel:SetPoint("BOTTOMLEFT", flashDD, "TOPLEFT", 16, 3)
flashLabel:SetText("Режим вспышки слота:")

local function InitFlashDropdown(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    for _, opt in ipairs(FLASH_OPTIONS) do
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

-- Закрепить заклинания
local lockSpellsCb = CreateCheckbox(generalPanel, "Lock spells (Insta-cast, no Drag&Drop)", "lockSpells", flashDD, dropdownsOffset, gapYCheckboxes-addYGap, function(self)
    if InCombatLockdown() then
        print("|cffff0000[PartySpells]|r Нельзя менять эту настройку прямо во время боя!")
        self:SetChecked(PartySpellsDB.settings.lockSpells)
        return
    end
    PartySpellsDB.settings.lockSpells = (self:GetChecked() ~= nil)
    if ns.UpdateCastingBehavior then ns.UpdateCastingBehavior() end
end)

-- TODO: Модификаторы для перетаскивания

-- -----------------------------------------------------------------------
-- Настройки баффов
-- -----------------------------------------------------------------------
local buffsTitle = buffsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
buffsTitle:SetPoint("TOPLEFT", 16, -16)
buffsTitle:SetText("PartySpells: Buffs")

local buffsActiveCb = CreateCheckbox(buffsPanel, "Включить отображение баффов", "buffsActive", buffsTitle, 0, gapYTitles)
local showTimerCb = CreateCheckbox(buffsPanel, "Показывать таймер на иконке", "showTimer", buffsActiveCb, 0, gapYCheckboxes)

-- Прозрачность баффов
local buffAlphaSlider  = CreateSlider(buffsPanel, "Прозрачность", 10, 100, 5, "alphaBuffs", showTimerCb, slidersOffset, gapYSliders+addYGap)

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
    UIDropDownMenu_SetText(
        flashDD,
        FLASH_TEXTS[s.flashMode] or FLASH_TEXTS[defs.flashMode]
    )

    btnAlphaSlider:SetValue(s.alphaButtons)
    buffAlphaSlider:SetValue(s.alphaBuffs)
    
    lockSpellsCb:SetChecked(s.lockSpells)
    buffsActiveCb:SetChecked(s.buffsActive)
    showTimerCb:SetChecked(s.showTimer)
end)