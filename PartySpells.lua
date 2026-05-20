local addonName, ns = ...

local ADDON_NAME  = "PartySpells"

-- party1..4 only — player is NOT included
-- PartyMemberFrame1 = first party member, etc.
local UNITS = { "party1", "party2", "party3", "party4" }

local FRAMES = {
    party1 = PartyMemberFrame1,
    party2 = PartyMemberFrame2,
    party3 = PartyMemberFrame3,
    party4 = PartyMemberFrame4,
}

local rows = {}
local MAX_SUPPORTED_SLOTS = 5

-- Function that switches the button click mode
function ns.UpdateCastingBehavior()
    -- Check if DB is loaded. If not - default false (allowed to drag)
    local isLocked = false
    if PartySpellsDB and PartySpellsDB.settings and type(PartySpellsDB.settings.lockSpells) == "boolean" then
        isLocked = PartySpellsDB.settings.lockSpells
    end

    local clickMode = isLocked and "AnyDown" or "AnyUp"
    
    for unitID, row in pairs(rows) do
        if row.slots then
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = row.slots[i]
                if slot then
                    slot:RegisterForClicks(clickMode)
                end
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Cooldowns update
-- -----------------------------------------------------------------------
local function UpdateCooldowns()
    -- Iterate over all created rows
    local s = PartySpellsDB.settings
    for unitID, row in pairs(rows) do
        -- Update cooldowns only if the player frame is currently visible
        if row.frame:IsVisible() then
            for i = 1, s.slotsCount do
                local slot = row.slots[i]
                if slot.spellName then
                    local start, duration, enable = GetSpellCooldown(slot.spellName)
                    if start and duration then
                        CooldownFrame_SetTimer(slot.cd, start, duration, enable)
                    end
                end
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Range Check (Optimized timer)
-- -----------------------------------------------------------------------
local RANGE_CHECK_INTERVAL = 0.2 -- Check 5 times per second
local rangeTimer = 0

local rangeFrame = CreateFrame("Frame")
rangeFrame:SetScript("OnUpdate", function(self, elapsed)
    if not ns.IsActive() then return end

    rangeTimer = rangeTimer + elapsed

    -- Once 0.2 sec has passed, do the check
    if rangeTimer >= RANGE_CHECK_INTERVAL then
        rangeTimer = 0
        local s = PartySpellsDB.settings
        
        -- Iterate only over existing rows
        for unitID, row in pairs(rows) do
            -- Check only if the row is visible (party member exists)
            if row.frame:IsVisible() then
                for i = 1, s.slotsCount do
                    local slot = row.slots[i]
                    if slot.spellName then
                        -- IsSpellInRange natively understands string spell names in 3.3.5
                        local inRange = IsSpellInRange(slot.spellName, slot.unitID)
                        
                        -- If 0 is returned, the spell definitely doesn't reach the target
                        if inRange == 0 then
                            slot.outOfRange:Show()
                        else
                            -- In all other cases (in range or invalid target) - hide
                            slot.outOfRange:Hide()
                        end
                    end
                end
            end
        end
    end
end)

-- -----------------------------------------------------------------------
-- SavedVariables: store spell NAME (stable across reloads in 3.3.5)
-- -----------------------------------------------------------------------

local function GetDB()
    if not PartySpellsDB then PartySpellsDB = {} end
    return PartySpellsDB
end

local function SaveSlot(unitID, slotIndex, spellName)
    local db = GetDB()
    if not db[unitID] then db[unitID] = {} end
    db[unitID][slotIndex] = spellName
end

local function LoadSlot(unitID, slotIndex)
    local db = GetDB()
    if db[unitID] then
        return db[unitID][slotIndex]
    end
    return nil
end

-- -----------------------------------------------------------------------
-- Resolve texture by spell name (scan spellbook)
-- Returns: texture string or nil
-- -----------------------------------------------------------------------

local function GetTextureByName(targetName)
    for i = 1, 1024 do
        local name = GetSpellName(i, BOOKTYPE_SPELL)
        if not name then break end
        if name == targetName then
            local _, _, texture = GetSpellInfo(i, BOOKTYPE_SPELL)
            -- keep scanning — last match = highest rank, same texture family
            if texture then
                return texture
            end
        end
    end
    return nil
end

-- -----------------------------------------------------------------------
-- Fill / clear slot
-- -----------------------------------------------------------------------

local function FillSlot(slot, spellName, texture)
    if not spellName or not texture then
        return
    end
    slot.spellName = spellName
    slot.icon:SetTexture(texture)
    slot.icon:Show()

    -- secure attributes for casting
    slot:SetAttribute("type", "spell")
    slot:SetAttribute("spell", spellName)
    slot:SetAttribute("unit", slot.unitID)
    
    -- Update cooldowns so a freshly cast spell shows the correct timer
    UpdateCooldowns()
    ns.UpdateSlotsVisibility()
end

local function ClearSlot(slot)
    slot.spellName = nil
    slot.icon:Hide()
    if slot.cd then slot.cd:Hide() end
    if slot.outOfRange then slot.outOfRange:Hide() end
    SaveSlot(slot.unitID, slot.slotIndex, nil)

    -- Clear attributes (only outside combat, it's forbidden by the game core during combat)
    if not InCombatLockdown() then
        slot:SetAttribute("type", nil)
        slot:SetAttribute("spell", nil)
    end
    ns.UpdateSlotsVisibility()
end
-- -----------------------------------------------------------------------
-- Create one spell slot
-- -----------------------------------------------------------------------

local function CreateSpellSlot(parent, unitID, slotIndex)
    local s = PartySpellsDB.settings
    local slot = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    slot:SetSize(s.slotSize, s.slotSize)
    slot.unitID    = unitID
    slot.slotIndex = slotIndex
    slot.spellName = nil

    slot:SetBackdrop({
        bgFile   = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 16,
        insets   = { left = 5, right = 5, top = 5, bottom = 5 },
    })
    slot:SetBackdropColor(0, 0, 0, 0.85)
    slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)

    local icon = slot:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT",     slot, "TOPLEFT",      4, -4)
    icon:SetPoint("BOTTOMRIGHT", slot, "BOTTOMRIGHT", -4,  4)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
    icon:Hide()
    slot.icon = icon

    local cd = CreateFrame("Cooldown", nil, slot, "CooldownFrameTemplate")
    cd:SetAllPoints(icon) -- Cooldown will cover only the icon itself
    cd:SetReverse(false)  -- Normal darkening
    slot.cd = cd

    local outOfRange = slot:CreateTexture(nil, "OVERLAY")
    outOfRange:SetAllPoints(icon) -- Layer overlays the icon itself
    -- Set color: Red (R=1, G=0, B=0) with 60% transparency (Alpha=0.6)
    outOfRange:SetTexture(1, 0, 0, 0.6) 
    outOfRange:Hide() -- Hidden by default
    slot.outOfRange = outOfRange

    local flash = slot:CreateTexture(nil, "OVERLAY")
    flash:SetBlendMode("ADD")
    flash:Hide()

    local fader = CreateFrame("Frame", nil, slot)
    fader:Hide()
    fader.elapsed = 0
    fader:SetScript("OnUpdate", function(self, elapsed)
        self.elapsed = self.elapsed + elapsed
        if self.elapsed >= 0.6 then
            flash:Hide()
            self:Hide()
        else
            local s = PartySpellsDB.settings
            local progress = self.elapsed / 0.6
            
            if s.flashMode == 1 then
                flash:SetAlpha(1 - progress)
            elseif s.flashMode == 2 then
                flash:SetAlpha(1)
            elseif s.flashMode == 3 then
                -- 1. Smooth fade in and out (Sine wave: 0 -> 1 -> 0)
                flash:SetAlpha(math.sin(progress * math.pi))
                
                -- 2. Rotate the texture clockwise
                -- Rotate 90 degrees (math.pi / 2) over the animation duration
                local angle = progress * (math.pi / 2)
                local cosA, sinA = math.cos(angle), math.sin(angle)
                
                -- Texture coordinate rotation matrix around center (0.5, 0.5)
                local ULx, ULy = 0.5 - 0.5*cosA + 0.5*sinA, 0.5 - 0.5*sinA - 0.5*cosA
                local LLx, LLy = 0.5 - 0.5*cosA - 0.5*sinA, 0.5 - 0.5*sinA + 0.5*cosA
                local URx, URy = 0.5 + 0.5*cosA + 0.5*sinA, 0.5 + 0.5*sinA - 0.5*cosA
                local LRx, LRy = 0.5 + 0.5*cosA - 0.5*sinA, 0.5 + 0.5*sinA + 0.5*cosA
                
                flash:SetTexCoord(ULx, ULy, LLx, LLy, URx, URy, LRx, LRy)
            end
        end
    end)

    slot.PlayFlash = function()
        local s = PartySpellsDB.settings
        if not s.flashMode or s.flashMode == 0 then return end 

        flash:ClearAllPoints()
        flash:SetTexCoord(0, 1, 0, 1) -- Always reset coords to default
        
        if s.flashMode == 1 then
            flash:SetAllPoints(slot.icon)
            flash:SetTexture(0, 1, 0, 0.6)
            flash:SetVertexColor(1, 1, 1, 1)
        elseif s.flashMode == 2 then
            flash:SetAllPoints(slot)
            flash:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
            flash:SetVertexColor(0, 1, 0, 1)
        elseif s.flashMode == 3 then
            flash:SetPoint("CENTER", slot, "CENTER", 0, 0)
            flash:SetSize(s.slotSize * 1.25, s.slotSize * 1.25) -- 2x smaller
            flash:SetTexture("Interface\\Cooldown\\star4")
            flash:SetVertexColor(1, 1, 1, 1) -- White color
        end
        
        -- For mode 3 alpha starts at 0 to fade in smoothly
        flash:SetAlpha(s.flashMode == 3 and 0 or 1)
        flash:Show()
        fader.elapsed = 0
        fader:Show()
    end

    local hl = slot:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints(slot)
    hl:SetBlendMode("ADD")
    slot.hl = hl -- Keep reference for later use!

    slot:EnableMouse(true)
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnEnter", function(self)
        if not PartySpellsDB.settings.showTooltips then return end
        
        if self.spellName then
            local texture = GetTextureByName(self.spellName)
            if texture then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                -- SetSpellByID not reliable; use spellbook scan for tooltip
                local bookSlot = nil
                for i = 1, 1024 do
                    local n = GetSpellName(i, BOOKTYPE_SPELL)
                    if not n then break end
                    if n == self.spellName then bookSlot = i end
                end
                if bookSlot then
                    GameTooltip:SetSpell(bookSlot, BOOKTYPE_SPELL)
                    GameTooltip:Show()
                end
            end
        end
    end)
    slot:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)

    -- -----------------------------------------------------------------------
    -- Receive Drag / Swap Logic
    -- -----------------------------------------------------------------------
    
    local function HandleReceiveSpell(self, id, subType)
        local name, _, texture = GetSpellInfo(id, subType)
    
        if name and texture then
            -- Remember the old spell (if any)
            local oldName = self.spellName
    
            -- Fill the slot (FillSlot will update attributes to type="spell")
            FillSlot(self, name, texture)
            SaveSlot(self.unitID, self.slotIndex, name)
            ClearCursor() -- Clear cursor just in case
    
            -- If there was already a spell in the slot, pick it up on the cursor
            if oldName then
                PickupSpell(oldName)
            end
            return true
        else
            return false
        end
    end
    
    local function TryReceiveSpell(self)
        local infoType, id, subType = GetCursorInfo()
        if infoType == "spell" then
            return HandleReceiveSpell(self, id, subType)
        end
        return false
    end

    slot:SetScript("OnReceiveDrag", TryReceiveSpell)

    slot:SetScript("OnReceiveDrag", TryReceiveSpell)

    slot:SetScript("PreClick", function(self, button)
        -- Handle drop only with left mouse button
        if button ~= "LeftButton" then return end
        
        local infoType, id, subType = GetCursorInfo()
        if infoType == "spell" then
            self.isDropping = true
            -- Save spell data before the client clears the cursor
            self.dropID = id
            self.dropSubType = subType
            
            if not InCombatLockdown() then
                -- Temporarily remove type so SecureActionButton doesn't cast the spell on this click
                self.oldType = self:GetAttribute("type")
                self:SetAttribute("type", nil)
            end
        else
            self.isDropping = false
        end
    end)

    slot:SetScript("PostClick", function(self, button)
        if button ~= "LeftButton" then return end
        
        if self.isDropping then
            self.isDropping = false
            if not InCombatLockdown() then
                -- Call our swap function
                local success = HandleReceiveSpell(self, self.dropID, self.dropSubType)
                
                -- If something went wrong (returned false), restore the old attribute
                if not success and self.oldType then
                    self:SetAttribute("type", self.oldType)
                end
            end
        end
    end)

    -- drag start (pick up spell from slot like action bar)
    slot:SetScript("OnDragStart", function(self)
        if self.spellName and not InCombatLockdown() and not PartySpellsDB.settings.lockSpells then
            PickupSpell(self.spellName)
            ClearSlot(self)
        end
    end)

    return slot
end

-- -----------------------------------------------------------------------
-- Create row for one party member
-- -----------------------------------------------------------------------

local function CreateRow(unitID, anchor)
    if rows[unitID] then return end

    local row = CreateFrame("Frame", ADDON_NAME .. "Row_" .. unitID, anchor) 
    -- Dimensions will be set later in ns.RefreshLayout
    local slots = {}
    for i = 1, MAX_SUPPORTED_SLOTS do
        local slot = CreateSpellSlot(row, unitID, i)
        slots[i] = slot
    end

    row:Hide()
    rows[unitID] = { frame = row, slots = slots }
end

-- -----------------------------------------------------------------------
-- Load saved spells into row slots (called after spellbook is available)
-- -----------------------------------------------------------------------

local function LoadRow(unitID)
    if not rows[unitID] then return end
    local s = PartySpellsDB.settings
    for i = 1, s.slotsCount do
        local savedName = LoadSlot(unitID, i)
        if savedName then
            local texture = GetTextureByName(savedName)
            if texture then
                FillSlot(rows[unitID].slots[i], savedName, texture)
            end
        end
    end
end
-- -----------------------------------------------------------------------
-- Show / hide rows based on current party size
-- -----------------------------------------------------------------------

local function RefreshRows()
    local groupSize = GetNumPartyMembers()
    local isActive = ns.IsActive() -- Check master switch

    for i = 1, 4 do
        local unitID = "party" .. i
        if rows[unitID] then
            -- If addon is on AND player is in a group
            if isActive and i <= groupSize then
                rows[unitID].frame:Show()
            else
                -- Otherwise hide all slots
                rows[unitID].frame:Hide()
            end
        end
    end
end

function ns.RefreshAllVisibility()
    RefreshRows()
    ns.UpdateSlotsVisibility()
    for _, unitID in ipairs(UNITS) do
        if ns.UpdateBuffs then
            ns.UpdateBuffs(unitID)
        end
    end
end

-- -----------------------------------------------------------------------
-- API for other addon modules
-- -----------------------------------------------------------------------
-- Function to trigger flash from other files
function ns.FlashSpellSlot(unitID, spellName)
    if rows[unitID] then
        local s = PartySpellsDB.settings
        for i = 1, s.slotsCount do
            local slot = rows[unitID].slots[i]
            if slot.spellName == spellName then
                slot.PlayFlash()
                break
            end
        end
    end
end

function ns.GetActiveSpells(unitID)
    local activeSpells = {}
    if rows[unitID] then
        local s = PartySpellsDB.settings
        for i = 1, s.slotsCount do
            local spellName = rows[unitID].slots[i].spellName
            if spellName then
                activeSpells[spellName] = true
            end
        end
    end
    return activeSpells
end

function ns.UpdateSlotsVisibility()
    local cursorType = GetCursorInfo()
    local isDraggingSpell = (cursorType == "spell")
    local s = PartySpellsDB.settings

    for unitID, row in pairs(rows) do
        for i = 1, s.slotsCount do
            local slot = row.slots[i]
            if slot.spellName or isDraggingSpell then
                -- Show the slot
                slot:SetBackdropColor(0, 0, 0, 0.85)
                slot:SetBackdropBorderColor(0.35, 0.35, 0.35, 1)
                -- Restore blue highlight on hover
                if slot.hl then slot.hl:SetAlpha(1) end 
            else
                -- Make the slot invisible
                slot:SetBackdropColor(0, 0, 0, 0)
                slot:SetBackdropBorderColor(0, 0, 0, 0)
                -- Disable hover glow (hide the layer)
                if slot.hl then slot.hl:SetAlpha(0) end 
            end
        end
    end
end

function ns.RefreshLayout()
    if not PartySpellsDB or not PartySpellsDB.settings then return end
    -- Cannot change positions during combat (due to Secure buttons inside)
    if InCombatLockdown() then return end 

    local s = PartySpellsDB.settings

    for unitID, rowData in pairs(rows) do
        local anchor = FRAMES[unitID]
        if anchor then
            local totalWidth = s.slotsCount * s.slotSize + (s.slotsCount - 1) * s.slotGap
            rowData.frame:SetSize(totalWidth, s.slotSize)
            
            rowData.frame:ClearAllPoints()
            -- Attach LEFT of our frame to RIGHT of the anchor (PartyMemberFrame)
            -- Use numbers directly.
            rowData.frame:SetPoint("LEFT", anchor, "RIGHT", tonumber(s.offsetX) or 0, tonumber(s.offsetY) or 0)
            
            rowData.frame:SetAlpha(s.alphaButtons / 100)

            -- Update dimensions and position of the slots themselves
            for i = 1, MAX_SUPPORTED_SLOTS do
                local slot = rowData.slots[i]
                if i <= s.slotsCount then
                    slot:SetSize(s.slotSize, s.slotSize)
                    slot:ClearAllPoints()
                    if i == 1 then
                        slot:SetPoint("LEFT", rowData.frame, "LEFT", 0, 0)
                    else
                        slot:SetPoint("LEFT", rowData.slots[i-1], "RIGHT", s.slotGap, 0)
                    end
                    slot:Show()
                else
                    slot:Hide()
                end
            end
        end
    end
    ns.UpdateSlotsVisibility()
end

-- -----------------------------------------------------------------------
-- Init
-- -----------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")
initFrame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
initFrame:RegisterEvent("UNIT_AURA")
initFrame:RegisterEvent("CURSOR_UPDATE")

initFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "PLAYER_LOGIN" then
        -- 1. First load the database and settings
        ns.InitDB()

        -- 2. Then create UI
        for _, unitID in ipairs(UNITS) do
            local anchor = FRAMES[unitID]
            if anchor then
                CreateRow(unitID, anchor)
                LoadRow(unitID)
                ns.CreateBuffRow(unitID)
            end
        end

        ns.RefreshLayout()
        ns.RefreshAllVisibility()
        
        -- Set the correct button mode on load
        ns.UpdateCastingBehavior()

        if SpellBookFrame then
            SpellBookFrame:SetMovable(true)
            SpellBookFrame:EnableMouse(true)
            SpellBookFrame:RegisterForDrag("LeftButton")
            SpellBookFrame:SetScript("OnDragStart", function(f) f:StartMoving() end)
            SpellBookFrame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
        end

    elseif event == "PARTY_MEMBERS_CHANGED" then
        RefreshRows()
        for _, unitID in ipairs(UNITS) do
            ns.UpdateBuffs(unitID)
        end

    elseif event == "SPELL_UPDATE_COOLDOWN" then
        if ns.IsActive() then UpdateCooldowns() end

    elseif event == "CURSOR_UPDATE" then
        if ns.IsActive() then ns.UpdateSlotsVisibility() end

    elseif event == "UNIT_AURA" then
        -- Call the buff update function
        -- It internally checks if this arg1 belongs to our group
        if ns.IsActive() then ns.UpdateBuffs(arg1) end
    end
end)