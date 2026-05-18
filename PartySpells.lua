-- PartySpells v0.4

local ADDON_NAME  = "PartySpells"
local SLOTS_COUNT = 3
local SLOT_SIZE   = 32
local SLOT_GAP    = 2
local OFFSET_X    = 8
local OFFSET_Y    = 0

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
    print("[PartySpells] SAVE unit=" .. unitID .. " slot=" .. slotIndex .. " name=" .. tostring(spellName))
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
        print("[PartySpells] FillSlot FAILED name=" .. tostring(spellName) .. " texture=" .. tostring(texture))
        return
    end
    slot.spellName = spellName
    slot.icon:SetTexture(texture)
    slot.icon:Show()

    -- secure attributes for casting
    slot:SetAttribute("type", "spell")
    slot:SetAttribute("spell", spellName)
    slot:SetAttribute("unit", slot.unitID)

    print("[PartySpells] FillSlot OK name=" .. spellName)
end

local function ClearSlot(slot)
    print("[PartySpells] ClearSlot unit=" .. slot.unitID .. " slot=" .. slot.slotIndex)
    slot.spellName = nil
    slot.icon:Hide()
    SaveSlot(slot.unitID, slot.slotIndex, nil)
end

-- -----------------------------------------------------------------------
-- Create one spell slot
-- -----------------------------------------------------------------------

local function CreateSpellSlot(parent, unitID, slotIndex)
    local slot = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
    slot:SetSize(SLOT_SIZE, SLOT_SIZE)
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
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    icon:Hide()
    slot.icon = icon

    local hl = slot:CreateTexture(nil, "HIGHLIGHT")
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetAllPoints(slot)
    hl:SetBlendMode("ADD")

    slot:EnableMouse(true)
    slot:RegisterForClicks("AnyUp")
    slot:RegisterForDrag("LeftButton")

    slot:SetScript("OnEnter", function(self)
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

    local function TryReceiveSpell(self)
        local infoType, id, subType = GetCursorInfo()
        print("[PartySpells] DRAG infoType=" .. tostring(infoType) .. " id=" .. tostring(id) .. " subType=" .. tostring(subType))

        if infoType == "spell" then
            local name, _, texture = GetSpellInfo(id, subType)
            print("[PartySpells] GetSpellInfo result: name=" .. tostring(name) .. " texture=" .. tostring(texture))

            if name and texture then
                -- swap logic
                local oldName = self.spellName

                FillSlot(self, name, texture)
                SaveSlot(self.unitID, self.slotIndex, name)
                ClearCursor()

                if oldName then
                    print("[PartySpells] SWAP put old spell back to cursor: " .. oldName)
                    PickupSpell(oldName)
                end
            else
                print("[PartySpells] ERROR: GetSpellInfo returned nil")
            end
        end
    end

    slot:SetScript("OnReceiveDrag", TryReceiveSpell)

    -- drag start (pick up spell from slot like action bar)
    slot:SetScript("OnDragStart", function(self)
        if self.spellName then
            print("[PartySpells] PICKUP " .. self.spellName)
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

    local row = CreateFrame("Frame", ADDON_NAME .. "Row_" .. unitID, UIParent)
    local totalWidth = SLOTS_COUNT * SLOT_SIZE + (SLOTS_COUNT - 1) * SLOT_GAP
    row:SetSize(totalWidth, SLOT_SIZE)
    row:SetPoint("LEFT", anchor, "RIGHT", OFFSET_X, OFFSET_Y)

    local slots = {}
    for i = 1, SLOTS_COUNT do
        local slot = CreateSpellSlot(row, unitID, i)
        if i == 1 then
            slot:SetPoint("LEFT", row, "LEFT", 0, 0)
        else
            slot:SetPoint("LEFT", slots[i-1], "RIGHT", SLOT_GAP, 0)
        end
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
    for i = 1, SLOTS_COUNT do
        local savedName = LoadSlot(unitID, i)
        if savedName then
            print("[PartySpells] LOAD unit=" .. unitID .. " slot=" .. i .. " name=" .. savedName)
            local texture = GetTextureByName(savedName)
            if texture then
                FillSlot(rows[unitID].slots[i], savedName, texture)
            else
                print("[PartySpells] LOAD FAILED: texture not found for '" .. savedName .. "'")
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Show / hide rows based on current party size
-- -----------------------------------------------------------------------

local function RefreshRows()
    local groupSize = GetNumPartyMembers()  -- excludes player, 0 if solo
    print("[PartySpells] RefreshRows groupSize=" .. groupSize)

    for i = 1, 4 do
        local unitID = "party" .. i
        if rows[unitID] then
            if i <= groupSize then
                rows[unitID].frame:Show()
                print("[PartySpells] Show row " .. unitID)
            else
                rows[unitID].frame:Hide()
                print("[PartySpells] Hide row " .. unitID)
            end
        end
    end
end

-- -----------------------------------------------------------------------
-- Init
-- -----------------------------------------------------------------------

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:RegisterEvent("PARTY_MEMBERS_CHANGED")

initFrame:SetScript("OnEvent", function(self, event)
    if event == "PLAYER_LOGIN" then
        print("[PartySpells] PLAYER_LOGIN")

        for _, unitID in ipairs(UNITS) do
            local anchor = FRAMES[unitID]
            if anchor then
                CreateRow(unitID, anchor)
                LoadRow(unitID)
            end
        end

        if SpellBookFrame then
            SpellBookFrame:SetMovable(true)
            SpellBookFrame:EnableMouse(true)
            SpellBookFrame:RegisterForDrag("LeftButton")
            SpellBookFrame:SetScript("OnDragStart", function(f) f:StartMoving() end)
            SpellBookFrame:SetScript("OnDragStop",  function(f) f:StopMovingOrSizing() end)
        end

        RefreshRows()
        print("[PartySpells] loaded, slots per member: " .. SLOTS_COUNT)
    end

    if event == "PARTY_MEMBERS_CHANGED" then
        print("[PartySpells] PARTY_MEMBERS_CHANGED")
        RefreshRows()
    end
end)
