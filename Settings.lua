local addonName, ns = ...

local gapYSliders = -32;
local gapYCheckboxes = -5;
local slidersOffset = 9;
local dropdownsOffset = 10;
local addYGap = 7;
local tabsWidth = 600

-- -----------------------------------------------------------------------
-- Database Initialization
-- -----------------------------------------------------------------------
function ns.InitDB()
    if not HealcraftDB then HealcraftDB = {} end
    if type(HealcraftDB.isActive) ~= "boolean" then HealcraftDB.isActive = true end
    if not HealcraftDB.settings then HealcraftDB.settings = {} end

    -- Default settings
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
        dragCtrl = false,
        dragAlt = false,
        dragShift = false,
        alphaButtonsHover = 100,
        rangeCheck = true,
    }
    for k, v in pairs(defs) do
        if HealcraftDB.settings[k] == nil then
            HealcraftDB.settings[k] = v
        end
    end
end

local FLASH_OPTIONS = {
    { text = "0: None (Disabled)", value = 0 },
    { text = "1: Smooth fill", value = 1 },
    { text = "2: Sharp border", value = 2 },
    { text = "3: Sparkle", value = 3 }
}

local FLASH_TEXTS = {}
local CHECKBOXES = {}
local SLIDERS = {}

for _, opt in ipairs(FLASH_OPTIONS) do
    FLASH_TEXTS[opt.value] = opt.text
end

-- -----------------------------------------------------------------------
-- Master-Switch logic
-- -----------------------------------------------------------------------
function ns.IsActive()
    return HealcraftDB and HealcraftDB.settings.isActive
end

function ns.SetActive(state)
    HealcraftDB.settings.isActive = state
    if _G[addonName .. "isActiveCheckButton"] then _G[addonName .. "isActiveCheckButton"]:SetChecked(state) end
    if ns.UpdateMinimapIcon then ns.UpdateMinimapIcon() end
    if ns.RefreshAllVisibility then ns.RefreshAllVisibility() end
end

function ns.ToggleActive() ns.SetActive(not ns.IsActive()) end
-- -----------------------------------------------------------------------
-- Create Settings Windows (OmniCC Style)
-- -----------------------------------------------------------------------
mainPanel = nil
function ns.OpenSettings()
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "Panel1"])
    InterfaceOptionsFrame_OpenToCategory(_G[addonName .. "Panel1"])
end

mainPanel = CreateFrame("Frame", addonName .. "MainPanel", UIParent)
mainPanel.name = addonName
InterfaceOptions_AddCategory(mainPanel)

mainPanel:SetScript("OnShow", function()
    ns.OpenSettings()
end)
-- -----------------------------------------------------------------------
-- Templates
-- -----------------------------------------------------------------------
local function RefreshVisuals(panelName)
    if panelName == addonName .. "Panel1" then
        -- General
        if ns.RefreshLayout then ns.RefreshLayout() end
    elseif panelName == addonName .. "Panel2" then
        -- Buffs
        if ns.RefreshAllBuffs then ns.RefreshAllBuffs() end
    end
end

local alignFrom = nil

-- Slider creation template
local function CreateSlider(panel, text, minVal, maxVal, step, dbKey, x, y)
    local slider = CreateFrame("Slider", addonName..dbKey.."Slider", panel, "OptionsSliderTemplate")
    SLIDERS[dbKey] = slider;
    slider:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", x, y)
    slider:SetMinMaxValues(minVal, maxVal)
    slider:SetValueStep(step)
    _G[slider:GetName().."Low"]:SetText(minVal)
    _G[slider:GetName().."High"]:SetText(maxVal)
    
    slider:SetScript("OnValueChanged", function(self, value)
        value = math.floor(value + 0.5) -- Round to integers
        HealcraftDB.settings[dbKey] = value
        _G[self:GetName().."Text"]:SetText(text .. ": " .. value)
        RefreshVisuals(panel.name)
    end)
    return slider
end

local function CreateCheckbox(panel, text, dbKey, x, y, callback)
    local checkbox = CreateFrame("CheckButton", addonName .. dbKey.."CheckButton", panel, "InterfaceOptionsCheckButtonTemplate")
    CHECKBOXES[dbKey] = checkbox;
    checkbox:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", x, y)
    _G[checkbox:GetName() .. "Text"]:SetText(" " .. text)

    checkbox:SetScript("OnClick", function(self)
        if callback then
            callback(self)
        else
            HealcraftDB.settings[dbKey] = (self:GetChecked() ~= nil)
            RefreshVisuals(panel.name)
        end
    end)

    return checkbox
end

local boxCounter = 0
local function CreateGroupBox(panel, titleText, height, y)
    boxCounter = boxCounter + 1
    local box = CreateFrame("Frame", addonName .. "GroupBox" .. boxCounter, panel)
    box:SetSize(tabsWidth-130, height)
    box:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", 0, y)
    
    box:SetBackdrop({
        bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = { left = 5, right = 5, top = 5, bottom = 5 }
    })
    box:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)
    box:SetBackdropColor(0, 0, 0, 0)
    
    -- ИСПОЛЬЗУЕМ КЛАССИЧЕСКИЙ ЖЕЛТЫЙ ШРИФТ (он меньше)
    -- GameFontNormalSmall	Желтый	~10pt	Мелкие подписи, время на баффах
    -- GameFontNormal	Желтый	~12pt	Стандартные подписи, имена НПС
    -- GameFontNormalLarge	Желтый	~14pt	Заголовки средней величины
    -- GameFontNormalHuge	Желтый	~18pt	Очень крупные заголовки окон
    local title = box:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    title:SetPoint("TOPLEFT", box, "TOPLEFT", 12, -12)
    title:SetText(titleText)
    
    -- УВЕЛИЧИВАЕМ ОТСТУП ПОСЛЕ ПОДЗАГОЛОВКА
    -- Смещение -16px вниз от текста заголовка создаст комфортный визуальный пробел
    local anchor = CreateFrame("Frame", nil, box)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, 0-addYGap) 
    
    return box, anchor
end
-- -----------------------------------------------------------------------
-- Helper Functions for Scrollable Tabs
-- -----------------------------------------------------------------------

-- Инициализирует вкладку, создает неподвижный заголовок и возвращает контейнер настроек
-- Инициализирует вкладку: создает базовую панель, регистрирует в системе настроек и настраивает скролл
local tabId = 0;
local function tabStart(titleText)
    tabId = tabId + 1
    local tabSlug = addonName .. "Panel" .. tabId;
    -- 1. Создаем базовый фрейм панели настроек
    local panel = CreateFrame("Frame", tabSlug, mainPanel)
    panel.name = titleText
    panel.parent = mainPanel.name or mainPanel:GetName()
    
    InterfaceOptions_AddCategory(panel)

    -- 2. Создаем неподвижный заголовок
    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetPoint("TOPRIGHT", -16, -16)
    title:SetJustifyH("LEFT")
    title:SetJustifyV("TOP")
    title:SetText(addonName .. ": " .. titleText)

    -- 3. Создаем ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", panel:GetName() .. "ScrollFrame", panel, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -42)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 16)

    -- 4. Создаем ScrollChild (контейнер контента)
    local scrollChild = CreateFrame("Frame", panel:GetName() .. "ScrollChild", scrollFrame)
    scrollChild:SetWidth(tabsWidth)
    scrollChild:SetHeight(1)
    
    scrollFrame:SetScrollChild(scrollChild)

    scrollChild.name = tabSlug 
    scrollChild.scrollFrame = scrollFrame

    -- 5. Настройка полосы прокрутки
    local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

    -- 6. Создаем невидимый стартовый якорь для элементов внутри scrollChild
    local anchor = CreateFrame("Frame", nil, scrollChild)
    anchor:SetSize(1, 1)
    anchor:SetPoint("TOPLEFT", scrollChild, "TOPLEFT", 0, 0)

    -- Возвращаем два значения: сам контейнер и стартовый якорь для элементов
    return scrollChild, anchor
end

-- -----------------------------------------------------------------------
-- General tab contents
-- -----------------------------------------------------------------------
-- 1. Начинаем вкладку (передаем саму панель и текст заголовка)
local generalScroll, anchor = tabStart("General")
alignFrom = anchor -- Задаем начальную точку привязки для элементов

-- Master switch
local activeCb = CreateCheckbox(generalScroll, "Enable addon (Master Switch)", "isActive", 0, 0, function(self)
    ns.SetActive(self:GetChecked() ~= nil)
end)

-- === Left slider column ===
alignFrom = activeCb
alignFrom = CreateSlider(generalScroll, "Slots count", 1, 5, 1, "slotsCount", slidersOffset, gapYSliders+addYGap)
alignFrom = CreateSlider(generalScroll, "Offset X", -12, 30, 1, "offsetX", 0, gapYSliders)
alignFrom = CreateSlider(generalScroll, "Transparency", 10, 100, 5, "alphaButtons", 0, gapYSliders)
alignFrom = CreateSlider(generalScroll, "Slots gap", -4, 30, 1, "slotGap", 0, gapYSliders)
local lastLeftItem = alignFrom;

-- === Right slider column ===
alignFrom = activeCb
alignFrom = CreateSlider(generalScroll, "Slot size", 18, 75, 1, "slotSize", 200, gapYSliders+addYGap)
alignFrom = CreateSlider(generalScroll, "Offset Y", -20, 30, 1, "offsetY", 0, gapYSliders)
alignFrom = CreateSlider(generalScroll, "Hover transparency", 10, 100, 5, "alphaButtonsHover", 0, gapYSliders)
alignFrom = lastLeftItem

-- === Below columns ===
-- Slot flash mode
local flashDD = CreateFrame("Frame", addonName.."FlashDropdown", generalScroll, "UIDropDownMenuTemplate")
flashDD:SetPoint("TOPLEFT", alignFrom, "BOTTOMLEFT", 0-slidersOffset-dropdownsOffset, gapYSliders-addYGap)
local flashLabel = flashDD:CreateFontString(nil, "OVERLAY", "GameFontNormal")
flashLabel:SetPoint("BOTTOMLEFT", flashDD, "TOPLEFT", 16, 3)
flashLabel:SetText("Slot flash mode:")

local function InitFlashDropdown(self, level, menuList)
    local info = UIDropDownMenu_CreateInfo()
    for _, opt in ipairs(FLASH_OPTIONS) do
        info.text = opt.text
        info.arg1 = opt.value
        local currentMode = (HealcraftDB and HealcraftDB.settings and HealcraftDB.settings.flashMode) or 2
        info.checked = (currentMode == opt.value)
        info.func = function(self, arg1)
            HealcraftDB.settings.flashMode = arg1
            UIDropDownMenu_SetSelectedValue(flashDD, arg1)
            UIDropDownMenu_SetText(flashDD, opt.text)
        end
        UIDropDownMenu_AddButton(info)
    end
end
UIDropDownMenu_Initialize(flashDD, InitFlashDropdown)

-- Lock spells
alignFrom = flashDD
alignFrom = CreateCheckbox(generalScroll, "Lock spells (instant cast, no drag&drop)", "lockSpells", dropdownsOffset, gapYCheckboxes-addYGap, function(self)
    if InCombatLockdown() then
        print("|cffff0000[Healcraft]|r Cannot change this setting during combat!")
        self:SetChecked(HealcraftDB.settings.lockSpells)
        return
    end
    HealcraftDB.settings.lockSpells = (self:GetChecked() ~= nil)
    if ns.UpdateCastingBehavior then ns.UpdateCastingBehavior() end
end)

local modifierBox, anchor = CreateGroupBox(generalScroll, "Drag modifiers", 70, 0)
alignFrom = anchor
CreateCheckbox(modifierBox, "Ctrl", "dragCtrl", 0, 0)
CreateCheckbox(modifierBox, "Shift", "dragShift", 100, 0)
CreateCheckbox(modifierBox, "Alt", "dragAlt", 200, 0)
alignFrom = modifierBox

alignFrom = CreateCheckbox(generalScroll, "Show tooltips on spells", "showTooltips", 0, 0-addYGap)
alignFrom = CreateCheckbox(generalScroll, "Range check", "rangeCheck", 0, gapYCheckboxes)

-- -----------------------------------------------------------------------
-- Buff settings
-- -----------------------------------------------------------------------
-- 1. Начинаем вкладку
local buffsScroll, anchor = tabStart("Баффы")
alignFrom = anchor

alignFrom = CreateCheckbox(buffsScroll, "Enable buffs", "buffsActive", 0, 0)
alignFrom = CreateCheckbox(buffsScroll, "Show timer on buffs", "showTimer", 0, gapYCheckboxes)
alignFrom = CreateCheckbox(buffsScroll, "Show spell stacks", "showStacks", 0, gapYCheckboxes)
alignFrom = CreateCheckbox(buffsScroll, "Show tooltips on buffs", "showTooltipsBuffs", 0, gapYCheckboxes)
alignFrom = CreateSlider(buffsScroll, "Buffs transparency", 10, 100, 5, "alphaBuffs", slidersOffset, gapYSliders+addYGap)

-- -----------------------------------------------------------------------
-- Sync UI with DB on load
-- -----------------------------------------------------------------------
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
    ns.InitDB()
    local s = HealcraftDB.settings

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