--[[
    Auto Chest Opener - Core Module
    Automatically opens chests, bags and containers after receiving them
    Version: 1.0.0
]]

local addonName, ACO = ...

-- ============================================================================
-- ADDON INITIALIZATION
-- ============================================================================

ACO.name = addonName
ACO.version = "1.0.0"
ACO.pendingItems = {}
ACO.itemQueue = {}

-- Default settings
local defaults = {
    enabled = true,
    delay = 3,              -- Delay in seconds before opening
    showNotifications = true,
    notificationSound = true,
    debugMode = false,
    containers = {},        -- User-added container IDs
    blacklist = {},         -- Items to never auto-open
    minimap = {
        hide = false,
    },
}

-- ============================================================================
-- COLORS & CONSTANTS
-- ============================================================================

ACO.colors = {
    primary = { r = 0.00, g = 0.80, b = 1.00 },     -- Cyan
    secondary = { r = 0.60, g = 0.40, b = 1.00 },   -- Purple
    accent = { r = 1.00, g = 0.80, b = 0.00 },      -- Gold
    success = { r = 0.00, g = 1.00, b = 0.50 },     -- Green
    error = { r = 1.00, g = 0.30, b = 0.30 },       -- Red
    text = { r = 0.90, g = 0.90, b = 0.90 },        -- Light grey
    textDim = { r = 0.60, g = 0.60, b = 0.60 },     -- Dim grey
    background = { r = 0.05, g = 0.05, b = 0.10 },  -- Dark blue-black
    backgroundLight = { r = 0.10, g = 0.10, b = 0.15 },
}

ACO.SOUNDS = {
    OPEN = SOUNDKIT.UI_BAG_SORTING_01 or 1221,
    ADD = SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED or 1221,
    REMOVE = SOUNDKIT.UI_PROFESSION_TRACK_ABILITY or 1221,
    ERROR = SOUNDKIT.UI_GARRISON_TOAST or 1221,
}

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function ACO:Print(msg, isError)
    local color = isError and ACO.colors.error or ACO.colors.primary
    local prefix = string.format("|cff%02x%02x%02x[ACO]|r", 
        color.r * 255, color.g * 255, color.b * 255)
    DEFAULT_CHAT_FRAME:AddMessage(prefix .. " " .. msg)
end

function ACO:Debug(msg)
    if self.db and self.db.debugMode then
        self:Print("|cff888888[Debug]|r " .. msg)
    end
end

function ACO:FormatItemLink(itemID)
    local itemName, itemLink = C_Item.GetItemInfo(itemID)
    return itemLink or ("|cffffffff[Item:" .. itemID .. "]|r")
end

function ACO:IsContainerItem(itemID)
    if not itemID then return false end
    
    -- Check user-defined containers
    if self.db and self.db.containers[itemID] then
        return true
    end
    
    -- Check if item has "Open" as a spell (can be opened)
    local itemSpell, spellID = C_Item.GetItemSpell(itemID)
    if itemSpell then
        local spellName = string.lower(itemSpell)
        -- Common opening spell names
        if spellName == "open" or spellName == "ouvrir" or 
           spellName == "öffnen" or spellName == "abrir" then
            return true
        end
    end
    
    return false
end

function ACO:CanOpenItem(itemID)
    if not itemID then return false end
    
    -- Check blacklist
    if self.db and self.db.blacklist[itemID] then
        return false
    end
    
    -- Check if in combat
    if InCombatLockdown() then
        return false
    end
    
    return self:IsContainerItem(itemID)
end

-- ============================================================================
-- ITEM OPENING LOGIC
-- ============================================================================

function ACO:FindItemInBags(itemID)
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                return bag, slot, info
            end
        end
    end
    return nil
end

function ACO:OpenItem(itemID)
    if InCombatLockdown() then
        self:Debug("Cannot open item in combat, queuing...")
        table.insert(self.itemQueue, itemID)
        return false
    end
    
    local bag, slot, info = self:FindItemInBags(itemID)
    if not bag then
        self:Debug("Item not found in bags: " .. itemID)
        return false
    end
    
    -- Use the item
    C_Container.UseContainerItem(bag, slot)
    
    if self.db.showNotifications then
        local itemLink = self:FormatItemLink(itemID)
        self:Print(string.format("Ouverture de %s...", itemLink))
    end
    
    if self.db.notificationSound then
        PlaySound(self.SOUNDS.OPEN)
    end
    
    return true
end

function ACO:QueueItem(itemID, itemLink)
    if not self.db.enabled then return end
    if not self:CanOpenItem(itemID) then return end
    
    -- Don't queue if already pending
    if self.pendingItems[itemID] then
        self:Debug("Item already pending: " .. itemID)
        return
    end
    
    self.pendingItems[itemID] = true
    
    if self.db.showNotifications then
        local link = itemLink or self:FormatItemLink(itemID)
        self:Print(string.format("Ouverture de %s dans %d secondes...", 
            link, self.db.delay))
    end
    
    -- Schedule opening
    C_Timer.After(self.db.delay, function()
        self.pendingItems[itemID] = nil
        if self:CanOpenItem(itemID) then
            self:OpenItem(itemID)
        end
    end)
end

-- ============================================================================
-- OPEN ALL CONTAINERS
-- ============================================================================

function ACO:OpenAllContainers()
    if InCombatLockdown() then
        self:Print("Impossible d'ouvrir en combat!", true)
        return 0
    end
    
    local opened = 0
    local toOpen = {}
    
    -- Collect all containers in bags
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                if self.db.containers[info.itemID] then
                    table.insert(toOpen, {bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink})
                end
            end
        end
    end
    
    if #toOpen == 0 then
        self:Print("Aucun conteneur référencé trouvé dans l'inventaire.")
        return 0
    end
    
    -- Open with delay between each
    local delay = 0.5
    for i, data in ipairs(toOpen) do
        C_Timer.After((i - 1) * delay, function()
            if not InCombatLockdown() then
                C_Container.UseContainerItem(data.bag, data.slot)
                opened = opened + 1
                if self.db.showNotifications then
                    self:Print(string.format("Ouverture de %s (%d/%d)", 
                        data.link or self:FormatItemLink(data.itemID), i, #toOpen))
                end
            end
        end)
    end
    
    if self.db.notificationSound then
        PlaySound(self.SOUNDS.OPEN)
    end
    
    return #toOpen
end

-- ============================================================================
-- CONTAINER MANAGEMENT
-- ============================================================================

function ACO:AddContainer(itemID)
    if not itemID or itemID == 0 then return false end
    
    if self.db.containers[itemID] then
        self:Print("Cet item est déjà dans la liste.", true)
        return false
    end
    
    self.db.containers[itemID] = true
    
    local itemLink = self:FormatItemLink(itemID)
    self:Print(string.format("Ajouté: %s", itemLink))
    
    if self.db.notificationSound then
        PlaySound(self.SOUNDS.ADD)
    end
    
    -- Refresh UI if open
    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end
    
    return true
end

function ACO:RemoveContainer(itemID)
    if not itemID then return false end
    
    if not self.db.containers[itemID] then
        self:Print("Cet item n'est pas dans la liste.", true)
        return false
    end
    
    self.db.containers[itemID] = nil
    
    local itemLink = self:FormatItemLink(itemID)
    self:Print(string.format("Retiré: %s", itemLink))
    
    if self.db.notificationSound then
        PlaySound(self.SOUNDS.REMOVE)
    end
    
    -- Refresh UI if open
    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end
    
    return true
end

function ACO:AddToBlacklist(itemID)
    if not itemID then return false end
    
    self.db.blacklist[itemID] = true
    local itemLink = self:FormatItemLink(itemID)
    self:Print(string.format("Blacklisté: %s", itemLink))
    
    return true
end

function ACO:RemoveFromBlacklist(itemID)
    if not itemID then return false end
    
    self.db.blacklist[itemID] = nil
    local itemLink = self:FormatItemLink(itemID)
    self:Print(string.format("Retiré de la blacklist: %s", itemLink))
    
    return true
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local EventFrame = CreateFrame("Frame")
ACO.EventFrame = EventFrame

local events = {}

events["ADDON_LOADED"] = function(self, addonLoaded)
    if addonLoaded ~= addonName then return end
    
    -- Initialize saved variables
    if not AutoChestOpenerDB then
        AutoChestOpenerDB = CopyTable(defaults)
    end
    
    -- Merge defaults for new settings
    for key, value in pairs(defaults) do
        if AutoChestOpenerDB[key] == nil then
            AutoChestOpenerDB[key] = value
        end
    end
    
    ACO.db = AutoChestOpenerDB
    
    ACO:Print("Addon chargé! Tapez |cff00ccff/aco|r pour ouvrir les options.")
    
    -- Initialize UI after a short delay
    C_Timer.After(0.5, function()
        if ACO.InitUI then
            ACO:InitUI()
        end
    end)
end

events["BAG_UPDATE_DELAYED"] = function(self)
    -- Check for new items in bags
    ACO:ScanBagsForContainers()
end

events["PLAYER_REGEN_ENABLED"] = function(self)
    -- Process queued items after leaving combat
    for _, itemID in ipairs(ACO.itemQueue) do
        if ACO:CanOpenItem(itemID) then
            ACO:QueueItem(itemID)
        end
    end
    wipe(ACO.itemQueue)
end

-- Track recently seen items to detect new ones
ACO.lastBagState = {}

function ACO:ScanBagsForContainers()
    if not self.db or not self.db.enabled then return end
    
    local currentBagState = {}
    
    for bag = 0, 4 do
        local numSlots = C_Container.GetContainerNumSlots(bag)
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local key = bag .. "-" .. slot
                currentBagState[key] = info.itemID
                
                -- Check if this is a new item
                if not self.lastBagState[key] or self.lastBagState[key] ~= info.itemID then
                    -- New item detected
                    if self:IsContainerItem(info.itemID) and not self.pendingItems[info.itemID] then
                        self:Debug("Nouvel item détecté: " .. info.itemID)
                        self:QueueItem(info.itemID, info.hyperlink)
                    end
                end
            end
        end
    end
    
    self.lastBagState = currentBagState
end

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if events[event] then
        events[event](self, ...)
    end
end)

for event in pairs(events) do
    EventFrame:RegisterEvent(event)
end

-- ============================================================================
-- SLASH COMMANDS
-- ============================================================================

SLASH_AUTOCHESTOPENER1 = "/aco"
SLASH_AUTOCHESTOPENER2 = "/autochestopener"

SlashCmdList["AUTOCHESTOPENER"] = function(msg)
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = string.lower(cmd or "")
    
    if cmd == "add" and arg then
        local itemID = tonumber(arg)
        if itemID then
            ACO:AddContainer(itemID)
        else
            ACO:Print("Usage: /aco add <itemID>", true)
        end
    elseif cmd == "remove" and arg then
        local itemID = tonumber(arg)
        if itemID then
            ACO:RemoveContainer(itemID)
        else
            ACO:Print("Usage: /aco remove <itemID>", true)
        end
    elseif cmd == "list" then
        ACO:Print("Conteneurs enregistrés:")
        local count = 0
        for itemID in pairs(ACO.db.containers) do
            local itemLink = ACO:FormatItemLink(itemID)
            print("  - " .. itemLink .. " (ID: " .. itemID .. ")")
            count = count + 1
        end
        if count == 0 then
            print("  (aucun)")
        end
    elseif cmd == "toggle" then
        ACO.db.enabled = not ACO.db.enabled
        ACO:Print(ACO.db.enabled and "Activé" or "Désactivé")
    elseif cmd == "delay" and arg then
        local delay = tonumber(arg)
        if delay and delay >= 0 and delay <= 30 then
            ACO.db.delay = delay
            ACO:Print("Délai réglé à " .. delay .. " secondes")
        else
            ACO:Print("Le délai doit être entre 0 et 30 secondes", true)
        end
    elseif cmd == "debug" then
        ACO.db.debugMode = not ACO.db.debugMode
        ACO:Print("Mode debug: " .. (ACO.db.debugMode and "activé" or "désactivé"))
    elseif cmd == "openall" or cmd == "open" then
        local count = ACO:OpenAllContainers()
        if count > 0 then
            ACO:Print(string.format("Ouverture de %d conteneur(s)...", count))
        end
    elseif cmd == "" or cmd == "config" or cmd == "options" then
        if ACO.UI and ACO.UI.Toggle then
            ACO.UI:Toggle()
        end
    else
        ACO:Print("Commandes disponibles:")
        print("  /aco - Ouvrir l'interface")
        print("  /aco add <itemID> - Ajouter un conteneur")
        print("  /aco remove <itemID> - Retirer un conteneur")
        print("  /aco list - Lister les conteneurs")
        print("  /aco openall - Ouvrir tous les conteneurs")
        print("  /aco toggle - Activer/Désactiver")
        print("  /aco delay <secondes> - Régler le délai")
        print("  /aco debug - Mode debug")
    end
end

-- Export addon table
_G["AutoChestOpener"] = ACO

-- ============================================================================
-- IMPORT/EXPORT FUNCTIONS
-- ============================================================================

function ACO:ExportContainers()
    local ids = {}
    for itemID in pairs(self.db.containers) do
        table.insert(ids, itemID)
    end
    table.sort(ids)
    return table.concat(ids, ",")
end

function ACO:ImportContainers(importString, clearExisting)
    if not importString or importString == "" then
        self:Print("Chaîne d'import vide.", true)
        return 0
    end
    
    if clearExisting then
        wipe(self.db.containers)
    end
    
    local count = 0
    for id in string.gmatch(importString, "(%d+)") do
        local itemID = tonumber(id)
        if itemID and itemID > 0 then
            self.db.containers[itemID] = true
            count = count + 1
        end
    end
    
    self:Print(string.format("Importé %d conteneur(s)!", count))
    
    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end
    
    return count
end

-- Add import/export slash commands
local originalSlashHandler = SlashCmdList["AUTOCHESTOPENER"]
SlashCmdList["AUTOCHESTOPENER"] = function(msg)
    local cmd, arg = strsplit(" ", msg, 2)
    cmd = string.lower(cmd or "")
    
    if cmd == "export" then
        ACO:ShowExportFrame()
    elseif cmd == "import" then
        if arg and arg ~= "" then
            ACO:ImportContainers(arg, false)
        else
            ACO:ShowImportFrame()
        end
    elseif cmd == "clear" then
        wipe(ACO.db.containers)
        ACO:Print("Liste des conteneurs vidée.")
        if ACO.UI and ACO.UI.RefreshList then
            ACO.UI:RefreshList()
        end
    else
        originalSlashHandler(msg)
    end
end

function ACO:CreateImportExportFrame()
    local c = self.colors
    
    local MIN_WIDTH = 400
    local MIN_HEIGHT = 200
    local MAX_WIDTH = 800
    local MAX_HEIGHT = 600

    local frame = CreateFrame("Frame", "ACOImportExportFrame", UIParent, "BackdropTemplate")
    frame:SetSize(550, 350)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:SetResizeBounds(MIN_WIDTH, MIN_HEIGHT, MAX_WIDTH, MAX_HEIGHT)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 2,
    })
    frame:SetBackdropColor(0.05, 0.05, 0.1, 0.98)
    frame:SetBackdropBorderColor(0, 0.8, 1, 0.9)
    frame:Hide()

    -- Title bar for dragging
    local titleBar = CreateFrame("Frame", nil, frame)
    titleBar:SetPoint("TOPLEFT", 0, 0)
    titleBar:SetPoint("TOPRIGHT", 0, 0)
    titleBar:SetHeight(40)
    titleBar:EnableMouse(true)
    titleBar:RegisterForDrag("LeftButton")
    titleBar:SetScript("OnDragStart", function() frame:StartMoving() end)
    titleBar:SetScript("OnDragStop", function() frame:StopMovingOrSizing() end)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", 0, -12)
    frame.title = title

    -- Scroll frame with edit box
    local scrollFrame = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    scrollFrame:SetPoint("TOPLEFT", 15, -45)
    scrollFrame:SetPoint("BOTTOMRIGHT", -35, 55)
    frame.scrollFrame = scrollFrame

    local editBox = CreateFrame("EditBox", nil, scrollFrame)
    editBox:SetMultiLine(true)
    editBox:SetAutoFocus(false)
    editBox:SetFontObject("GameFontHighlight")
    editBox:SetTextInsets(5, 5, 5, 5)
    editBox:SetScript("OnEscapePressed", function() frame:Hide() end)
    scrollFrame:SetScrollChild(editBox)
    frame.editBox = editBox

    -- Background for edit area
    local editBg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    editBg:SetPoint("TOPLEFT", scrollFrame, -5, 5)
    editBg:SetPoint("BOTTOMRIGHT", scrollFrame, 20, -5)
    editBg:SetFrameLevel(frame:GetFrameLevel())
    editBg:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    editBg:SetBackdropColor(0.1, 0.1, 0.15, 1)
    editBg:SetBackdropBorderColor(0.3, 0.3, 0.4, 1)

    -- Update editBox width on resize
    local function UpdateEditBoxWidth()
        local width = scrollFrame:GetWidth() - 10
        if width > 0 then
            editBox:SetWidth(width)
        end
    end
    
    frame:SetScript("OnSizeChanged", function(self, width, height)
        UpdateEditBoxWidth()
    end)
    
    frame:HookScript("OnShow", function()
        C_Timer.After(0.05, UpdateEditBoxWidth)
    end)

    -- Close button
    local closeBtn = CreateFrame("Button", nil, frame)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", -8, -8)
    local closeTex = closeBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetAtlas("common-icon-redx")
    closeBtn:SetScript("OnClick", function() frame:Hide() end)
    closeBtn:SetScript("OnEnter", function() closeTex:SetVertexColor(1, 0.3, 0.3) end)
    closeBtn:SetScript("OnLeave", function() closeTex:SetVertexColor(1, 1, 1) end)

    -- Resize handle
    local resizeBtn = CreateFrame("Button", nil, frame)
    resizeBtn:SetSize(16, 16)
    resizeBtn:SetPoint("BOTTOMRIGHT", -4, 4)
    resizeBtn:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    resizeBtn:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    resizeBtn:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    
    resizeBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)
    
    resizeBtn:SetScript("OnMouseUp", function(self, button)
        frame:StopMovingOrSizing()
        UpdateEditBoxWidth()
    end)

    -- Import button
    local importBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    importBtn:SetSize(140, 30)
    importBtn:SetPoint("BOTTOM", -80, 12)
    importBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    importBtn:SetBackdropColor(0, 0.5, 0.3, 0.9)
    importBtn:SetBackdropBorderColor(0, 0.8, 0.5, 1)
    
    local importText = importBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    importText:SetPoint("CENTER")
    importText:SetText("Importer")
    importText:SetTextColor(1, 1, 1)
    
    importBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0, 0.7, 0.4, 1)
    end)
    importBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0, 0.5, 0.3, 0.9)
    end)
    importBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        local count = ACO:ImportContainers(text, false)
        if count > 0 then
            frame:Hide()
        end
    end)
    frame.importBtn = importBtn

    -- Clear & Import button
    local clearImportBtn = CreateFrame("Button", nil, frame, "BackdropTemplate")
    clearImportBtn:SetSize(140, 30)
    clearImportBtn:SetPoint("BOTTOM", 80, 12)
    clearImportBtn:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8x8",
        edgeFile = "Interface\\Buttons\\WHITE8x8",
        edgeSize = 1,
    })
    clearImportBtn:SetBackdropColor(0.5, 0.3, 0, 0.9)
    clearImportBtn:SetBackdropBorderColor(0.8, 0.5, 0, 1)
    
    local clearImportText = clearImportBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    clearImportText:SetPoint("CENTER")
    clearImportText:SetText("Remplacer tout")
    clearImportText:SetTextColor(1, 1, 1)
    
    clearImportBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.7, 0.4, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Efface la liste actuelle et importe")
        GameTooltip:Show()
    end)
    clearImportBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(0.5, 0.3, 0, 0.9)
        GameTooltip:Hide()
    end)
    clearImportBtn:SetScript("OnClick", function()
        local text = editBox:GetText()
        local count = ACO:ImportContainers(text, true)
        if count > 0 then
            frame:Hide()
        end
    end)
    frame.clearImportBtn = clearImportBtn

    -- Helper text
    local helpText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    helpText:SetPoint("BOTTOMLEFT", 15, 15)
    helpText:SetTextColor(0.6, 0.6, 0.6)
    helpText:SetText("Format: IDs séparés par des virgules (ex: 12345,67890)")
    frame.helpText = helpText

    self.ExportFrame = frame
    table.insert(UISpecialFrames, "ACOImportExportFrame")
end

function ACO:ShowImportFrame()
    if not self.ExportFrame then
        self:CreateImportExportFrame()
    end
    self.ExportFrame.editBox:SetText("")
    self.ExportFrame.title:SetText("|cff00ff80Importer des conteneurs|r")
    self.ExportFrame.importBtn:Show()
    self.ExportFrame.clearImportBtn:Show()
    self.ExportFrame.helpText:Show()
    self.ExportFrame:Show()
    self.ExportFrame.editBox:SetFocus()
end

function ACO:ShowExportFrame()
    if not self.ExportFrame then
        self:CreateImportExportFrame()
    end
    local exportStr = self:ExportContainers()
    if exportStr == "" then
        self:Print("Aucun conteneur à exporter.")
        return
    end
    self.ExportFrame.editBox:SetText(exportStr)
    self.ExportFrame.title:SetText("|cff00ccffExporter les conteneurs|r")
    self.ExportFrame.importBtn:Hide()
    self.ExportFrame.clearImportBtn:Hide()
    self.ExportFrame.helpText:Hide()
    self.ExportFrame:Show()
    self.ExportFrame.editBox:HighlightText()
    self.ExportFrame.editBox:SetFocus()
end
