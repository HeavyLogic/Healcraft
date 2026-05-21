local addonName, ns = ...

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
-- Templates
-- -----------------------------------------------------------------------
local function RefreshVisuals(panelName)
    if panelName == "General" then
        if ns.RefreshLayout then ns.RefreshLayout() end
    elseif panelName == "Buffs" then
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

local function CreateScrollablePanel(parent, titleText, scrollHeight)
    -- 1. Создаем неподвижный заголовок на основной панели (вне скролла)
    local title = parent:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText(titleText)

    -- 2. Создаем ScrollFrame
    local scrollFrame = CreateFrame("ScrollFrame", parent:GetName() .. "ScrollFrame", parent, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 16, -50)
    scrollFrame:SetPoint("BOTTOMRIGHT", -32, 16)

    -- 3. Создаем ScrollChild
    local scrollChild = CreateFrame("Frame", parent:GetName() .. "ScrollChild", scrollFrame)
    -- Задаем фиксированную ширину (400px идеально подходит под стандартное окно настроек 3.3.5)
    scrollChild:SetWidth(400) 
    scrollChild:SetHeight(scrollHeight or 500) 
    
    scrollFrame:SetScrollChild(scrollChild)

    -- Копируем имя родительской панели, чтобы работал метод RefreshVisuals(panel.name)
    scrollChild.name = parent.name

    -- Настраиваем полосу прокрутки
    local scrollBar = _G[scrollFrame:GetName() .. "ScrollBar"]
    scrollBar:ClearAllPoints()
    scrollBar:SetPoint("TOPLEFT", scrollFrame, "TOPRIGHT", 6, -16)
    scrollBar:SetPoint("BOTTOMLEFT", scrollFrame, "BOTTOMRIGHT", 6, 16)

    return scrollChild
end
-- -----------------------------------------------------------------------
-- General tab contents
-- -----------------------------------------------------------------------
-- Создаем скролл-панель (высота контента 550px)
local generalScroll = CreateScrollablePanel(generalPanel, "Healcraft: General", 550)

local gapYTitles = -16;
local gapYSliders = -32;
local gapYCheckboxes = -5;
local slidersOffset = 9;
local dropdownsOffset = 10;
local addYGap = 7;

-- Невидимый фрейм-якорь в самом верху скролл-панели
alignFrom = CreateFrame("Frame", nil, generalScroll)
alignFrom:SetSize(1, 1)
alignFrom:SetPoint("TOPLEFT", generalScroll, "TOPLEFT", 0, 0)

-- Master switch (родитель — generalScroll)
local activeCb = CreateCheckbox(generalScroll, "Enable addon (Master Switch)", "isActive", 0, gapYTitles, function(self)
    ns.SetActive(self:GetChecked() ~= nil)
end)

-- === Left slider column ===
alignFrom = activeCb
alignFrom = CreateSlider(generalScroll, "Slots count", 1, 5, 1, "slotsCount", slidersOffset, gapYSliders+addYGap)
alignFrom = CreateSlider(generalScroll, "Offset X", -12, 30, 1, "offsetX", 0, gapYSliders)
alignFrom = CreateSlider(generalScroll, "Slots gap", -4, 30, 1, "slotGap", 0, gapYSliders)

local lastLeftItem = alignFrom;

-- === Right slider column ===
alignFrom = activeCb
alignFrom = CreateSlider(generalScroll, "Slot size", 18, 75, 1, "slotSize", 200, gapYSliders+addYGap)
alignFrom = CreateSlider(generalScroll, "Offset Y", -20, 30, 1, "offsetY", 0, gapYSliders)
alignFrom = CreateSlider(generalScroll, "Spells transparency", 10, 100, 5, "alphaButtons", 0, gapYSliders)

-- === Below columns ===
-- Slot flash mode (родитель — generalScroll)
local flashDD = CreateFrame("Frame", addonName.."FlashDropdown", generalScroll, "UIDropDownMenuTemplate")
flashDD:SetPoint("TOPLEFT", lastLeftItem, "BOTTOMLEFT", 0-slidersOffset-dropdownsOffset, gapYSliders-addYGap)
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

alignFrom = CreateCheckbox(generalScroll, "Show tooltips on spells", "showTooltips", 0, gapYCheckboxes)



-- TODO: Modifiers for drag & drop

-- -----------------------------------------------------------------------
-- Buff settings
-- -----------------------------------------------------------------------
alignFrom = buffsPanel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
alignFrom:SetPoint("TOPLEFT", 16, -16)
alignFrom:SetText("Healcraft: Buffs")

alignFrom = CreateCheckbox(buffsPanel, "Enable buffs", "buffsActive", 0, gapYTitles)
alignFrom = CreateCheckbox(buffsPanel, "Show timer on buffs", "showTimer", 0, gapYCheckboxes)
alignFrom = CreateCheckbox(buffsPanel, "Show spell stacks", "showStacks", 0, gapYCheckboxes)
alignFrom = CreateCheckbox(buffsPanel, "Show tooltips on buffs", "showTooltipsBuffs", 0, gapYCheckboxes)
alignFrom = CreateSlider(buffsPanel, "Buffs transparency", 10, 100, 5, "alphaBuffs", slidersOffset, gapYSliders+addYGap)
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