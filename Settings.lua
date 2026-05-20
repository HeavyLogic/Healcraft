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
        showStacks  = true,
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
local CHECKBOXES = {}
local SLIDERS = {}

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

local workingPanel = nil
local alignFrom = nil

-- Шаблон создания слайдера
local function CreateSlider(text, minVal, maxVal, step, dbKey, x, y)
    local slider = CreateFrame("Slider", addonName..dbKey.."Slider", workingPanel, "OptionsSliderTemplate")
    SLIDERS[dbKey] = slider;
    slider:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5) -- Округляем до целых
        PartySpellsDB.settings[dbKey] = value
        _G[self:GetName().."Text"]:SetText(text .. ": " .. value)
        RefreshVisuals(workingPanel.name)
    end)
    return slider
end

local function CreateCheckbox(text, dbKey, x, y, callback)
    local checkbox = CreateFrame("CheckButton", addonName .. dbKey.."CheckButton", workingPanel, "InterfaceOptionsCheckButtonTemplate")
    CHECKBOXES[dbKey] = checkbox;
    checkbox:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", x, y)
    _G[checkbox:GetName() .. "Text"]:SetText(" " .. text)

    checkbox:SetScript("OnClick", function(self)
        if callback then
            callback(self)
        else
            PartySpellsDB.settings[dbKey] = (self:GetChecked() ~= nil)
            RefreshVisuals(workingPanel.name)
        end
    end)

    return checkbox
end
-- -----------------------------------------------------------------------
-- Наполнение вкладки General
-- -----------------------------------------------------------------------
workingPanel = generalPanel
alignFrom = generalPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
alignFrom:SetPoint("TOPLEFT", 16, -16)
alignFrom:SetText("PartySpells: General")

local gapYTitles = -16;
local gapYSliders = -32;
local gapYCheckboxes = -5;
local slidersOffset = 9;
local dropdownsOffset = 10;
local addYGap = 7;

-- Master switch
local activeCb = CreateCheckbox("Включить аддон (Master Switch)", "isActive", 0, gapYTitles, function(self)
    ns.SetActive(self:GetChecked() ~= nil)
    print(self:GetName())
end)

-- === Левая колонка слайдеров ===
alignFrom = activeCb
alignFrom = CreateSlider("Кол-во слотов", 1, 5, 1, "slotsCount", slidersOffset, gapYSliders+addYGap)
alignFrom = CreateSlider("Смещение по X", -12, 30, 1, "offsetX", 0, gapYSliders)
alignFrom = CreateSlider("Отступ между слотами", -4, 30, 1, "slotGap", 0, gapYSliders)

local lastLeftItem = alignFrom;

-- === Правая колонка слайдеров ===
alignFrom = activeCb
alignFrom = CreateSlider("Размер слота", 18, 75, 1, "slotSize", 200, gapYSliders+addYGap)
alignFrom = CreateSlider("Смещение по Y", -20, 30, 1, "offsetY", 0, gapYSliders)
alignFrom = CreateSlider("Прозрачность", 10, 100, 5, "alphaButtons", 0, gapYSliders)

-- === Под колонками ===
-- Режим вспышки слота
local flashDD = CreateFrame("Frame", addonName.."FlashDropdown", generalPanel, "UIDropDownMenuTemplate")
flashDD:SetPoint("TOPLEFT", lastLeftItem, "BOTTOMLEFT", 0-slidersOffset-dropdownsOffset, gapYSliders-addYGap)
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
alignFrom = flashDD
alignFrom = CreateCheckbox("Lock spells (Insta-cast, no Drag&Drop)", "lockSpells", dropdownsOffset, gapYCheckboxes-addYGap, function(self)
    if InCombatLockdown() then
        print("|cffff0000[PartySpells]|r Нельзя менять эту настройку прямо во время боя!")
        self:SetChecked(PartySpellsDB.settings.lockSpells)
        return
    end
    PartySpellsDB.settings.lockSpells = (self:GetChecked() ~= nil)
    if ns.UpdateCastingBehavior then ns.UpdateCastingBehavior() end
end)

alignFrom = CreateCheckbox("Show tooltips on spells", "showTooltips", 0, gapYCheckboxes)

-- TODO: Модификаторы для перетаскивания

-- -----------------------------------------------------------------------
-- Настройки баффов
-- -----------------------------------------------------------------------
workingPanel = buffsPanel;
alignFrom = buffsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
alignFrom:SetPoint("TOPLEFT", 16, -16)
alignFrom:SetText("PartySpells: Buffs")

alignFrom = CreateCheckbox("Включить отображение баффов", "buffsActive", 0, gapYTitles)
alignFrom = CreateCheckbox("Показывать таймер на иконке", "showTimer", 0, gapYCheckboxes)
alignFrom = CreateCheckbox("Показывать стаки заклинаний", "showStacks", 0, gapYCheckboxes)
alignFrom = CreateCheckbox("Show tooltips on buffs", "showTooltipsBuffs", 0, gapYCheckboxes)
alignFrom = CreateSlider("Прозрачность", 10, 100, 5, "alphaBuffs", slidersOffset, gapYSliders+addYGap)
-- -----------------------------------------------------------------------
-- Синхронизация UI с базой при загрузке
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    ns.InitDB()
    local s = PartySpellsDB.settings

    for dbKey, slider in pairs(SLIDERS) do
        slider:SetValue(s[dbKey])
    end

    for dbKey, checkbox in pairs(CHECKBOXES) do
        checkbox:SetChecked(s[dbKey])
    end
    
    UIDropDownMenu_SetSelectedValue(flashDD, s.flashMode)
    UIDropDownMenu_SetText(
        flashDD,
        FLASH_TEXTS[s.flashMode] or FLASH_TEXTS[defs.flashMode]
    )
end)