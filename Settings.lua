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
        slotsCount = 3,
        slotSize   = 32,
        slotGap    = 2,
        offsetX    = 8,
        offsetY    = 0,
        flashMode  = 2
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
    if state then print("|cff00ff00[PartySpells]|r Аддон включен.") else print("|cff808080[PartySpells]|r Аддон выключен.") end
    if ns.UpdateMinimapIcon then ns.UpdateMinimapIcon() end
    if ns.RefreshAllVisibility then ns.RefreshAllVisibility() end
end
function ns.ToggleActive() ns.SetActive(not ns.IsActive()) end
function ns.OpenSettings()
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "GeneralPanel"])
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "GeneralPanel"])
end

-- -----------------------------------------------------------------------
-- Создание Окон Настроек (OmniCC Style)
-- -----------------------------------------------------------------------
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
-- Наполнение вкладки General
-- -----------------------------------------------------------------------
local title = generalPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
title:SetPoint("TOPLEFT", 16, -16)
title:SetText("PartySpells: General")

local activeCb = CreateFrame("CheckButton", addonName .. "ActiveCheckbox", generalPanel, "InterfaceOptionsCheckButtonTemplate")
activeCb:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
_G[activeCb:GetName() .. "Text"]:SetText(" Включить аддон (Master Switch)")
activeCb:SetScript("OnClick", function(self) ns.SetActive(self:GetChecked()) end)

-- Шаблон создания слайдера
local function CreateSlider(name, text, minVal, maxVal, step, dbKey, x, y)
    local slider = CreateFrame("Slider", addonName..name.."Slider", generalPanel, "OptionsSliderTemplate")
    slider:SetPoint("TOPLEFT", activeCb, "BOTTOMLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5) -- Округляем до целых
        PartySpellsDB.settings[dbKey] = value
        _G[self:GetName().."Text"]:SetText(text .. ": " .. value)
        if ns.RefreshLayout then ns.RefreshLayout() end
    end)
    return slider
end

-- Левая колонка
local slotsSlider = CreateSlider("Slots", "Кол-во слотов", 1, 5, 1, "slotsCount", 0, -20)
local sizeSlider  = CreateSlider("Size", "Размер слота", 18, 50, 1, "slotSize", 0, -70)
-- Слайдер Gap теперь поддерживает от -2 (слоты будут наслаиваться друг на друга)
local gapSlider   = CreateSlider("Gap", "Отступ между слотами", -2, 10, 1, "slotGap", 0, -120)

-- Правая колонка
-- Слайдеры для смещения (от -20 до 30)
local offsetXSlider = CreateSlider("OffsetX", "Смещение по X", -20, 30, 1, "offsetX", 200, -20)
local offsetYSlider = CreateSlider("OffsetY", "Смещение по Y", -20, 30, 1, "offsetY", 200, -70)

-- Выпадающий список (Dropdown)
local flashDD = CreateFrame("Frame", addonName.."FlashDropdown", generalPanel, "UIDropDownMenuTemplate")
flashDD:SetPoint("TOPLEFT", activeCb, "BOTTOMLEFT", 180, -120) -- Сдвинут под правые слайдеры
local flashLabel = flashDD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
flashLabel:SetPoint("BOTTOMLEFT", flashDD, "TOPLEFT", 16, 3)
flashLabel:SetText("Режим вспышки баффа:")

local function InitFlashDropdown(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    local options = {
        { text = "1: Плавная заливка", value = 1 },
        { text = "2: Резкая рамка", value = 2 }
    }
    for _, opt in ipairs(options) do
        info.text = opt.text
        info.arg1 = opt.value
        info.func = function(self, arg1)
            PartySpellsDB.settings.flashMode = arg1
            UIDropDownMenu_SetSelectedValue(flashDD, arg1)
            UIDropDownMenu_SetText(flashDD, opt.text)
        end
        UIDropDownMenu_AddButton(info)
    end
end
UIDropDownMenu_Initialize(flashDD, InitFlashDropdown)

-- -----------------------------------------------------------------------
-- Синхронизация UI с базой при загрузке
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    -- Инициализируем базу первой!
    ns.InitDB()

    -- Выставляем UI элементы в актуальное состояние
    activeCb:SetChecked(ns.IsActive())
    local s = PartySpellsDB.settings
    slotsSlider:SetValue(s.slotsCount)
    sizeSlider:SetValue(s.slotSize)
    gapSlider:SetValue(s.slotGap)
    
    offsetXSlider:SetValue(s.offsetX)
    offsetYSlider:SetValue(s.offsetY)
    
    UIDropDownMenu_SetSelectedValue(flashDD, s.flashMode)
    UIDropDownMenu_SetText(flashDD, s.flashMode == 1 and "1: Плавная заливка" or "2: Резкая рамка")
end)