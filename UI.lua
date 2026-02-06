--[[
    Auto Chest Opener - UI Module
    Modern and elegant interface inspired by WoW's new UI style
    Version: 1.3.0
]]

local addonName, ACO = ...

-- ============================================================================
-- LOCAL UPVALUES (Performance Optimization)
-- ============================================================================

local pairs, ipairs, type = pairs, ipairs, type
local tonumber, tostring = tonumber, tostring
local format = string.format
local floor, max, min, cos, sin, atan2, deg = math.floor, math.max, math.min, math.cos, math.sin, math.atan2, math.deg
local tinsert, wipe = table.insert, wipe
local date = date

-- WoW API upvalues
local CreateFrame = CreateFrame
local CreateColor = CreateColor
local PlaySound = PlaySound
local GameTooltip = GameTooltip
local GetCursorPosition = GetCursorPosition
local GetCursorInfo = GetCursorInfo
local ClearCursor = ClearCursor
local IsAltKeyDown = IsAltKeyDown
local C_Item = C_Item
local C_Timer = C_Timer
local Item = Item
local SOUNDKIT = SOUNDKIT

ACO.UI = {}
local UI = ACO.UI

-- ============================================================================
-- UI CONSTANTS
-- ============================================================================

local FRAME_WIDTH = 500
local FRAME_HEIGHT = 600
local FRAME_MIN_WIDTH = 420
local FRAME_MIN_HEIGHT = 500
local FRAME_MAX_WIDTH = 750
local FRAME_MAX_HEIGHT = 950
local HEADER_HEIGHT = 50
local TAB_HEIGHT = 32
local BUTTON_HEIGHT = 32
local LIST_ITEM_HEIGHT = 40
local PADDING = 12
local CORNER_RADIUS = 8

-- ============================================================================
-- BACKDROP TEMPLATES
-- ============================================================================

local MainBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

local CardBackdrop = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function CreateGradientTexture(frame, direction, r1, g1, b1, a1, r2, g2, b2, a2)
    local tex = frame:CreateTexture(nil, "BACKGROUND")
    tex:SetAllPoints()
    tex:SetColorTexture(1, 1, 1, 1)
    
    if direction == "VERTICAL" then
        tex:SetGradient("VERTICAL", 
            CreateColor(r1, g1, b1, a1), 
            CreateColor(r2, g2, b2, a2))
    else
        tex:SetGradient("HORIZONTAL", 
            CreateColor(r1, g1, b1, a1), 
            CreateColor(r2, g2, b2, a2))
    end
    
    return tex
end

local function ApplyGlowEffect(frame, r, g, b)
    if frame.glowTextures then
        for _, tex in ipairs(frame.glowTextures) do
            tex:SetVertexColor(r, g, b, 0.3)
        end
        return
    end
    
    frame.glowTextures = {}
    
    -- Create subtle glow around the frame
    local glowSize = 3
    local alpha = 0.3
    
    local positions = {
        {"TOPLEFT", -glowSize, glowSize},
        {"TOPRIGHT", glowSize, glowSize},
        {"BOTTOMLEFT", -glowSize, -glowSize},
        {"BOTTOMRIGHT", glowSize, -glowSize},
    }
    
    for _, pos in ipairs(positions) do
        local glow = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
        glow:SetPoint(pos[1], pos[2], pos[3])
        glow:SetSize(glowSize * 2, glowSize * 2)
        glow:SetColorTexture(r, g, b, alpha)
        glow:SetBlendMode("ADD")
        table.insert(frame.glowTextures, glow)
    end
end

-- ============================================================================
-- MODERN BUTTON CREATION
-- ============================================================================

local function CreateModernButton(parent, text, width, height, isPrimary)
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or BUTTON_HEIGHT)
    button:SetBackdrop(CardBackdrop)
    
    local c = ACO.colors
    local bgR, bgG, bgB = c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b
    local borderR, borderG, borderB = c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5
    
    if isPrimary then
        bgR, bgG, bgB = c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3
        borderR, borderG, borderB = c.primary.r, c.primary.g, c.primary.b
    end
    
    button:SetBackdropColor(bgR, bgG, bgB, 0.9)
    button:SetBackdropBorderColor(borderR, borderG, borderB, 0.8)
    
    -- Create gradient overlay
    local gradient = button:CreateTexture(nil, "BORDER")
    gradient:SetAllPoints()
    gradient:SetColorTexture(1, 1, 1, 1)
    gradient:SetGradient("VERTICAL", 
        CreateColor(1, 1, 1, 0), 
        CreateColor(1, 1, 1, 0.05))
    
    -- Text
    local fontString = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fontString:SetPoint("CENTER")
    fontString:SetText(text)
    fontString:SetTextColor(c.text.r, c.text.g, c.text.b)
    button.text = fontString
    
    -- Hover effects
    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(c.primary.r * 0.4, c.primary.g * 0.4, c.primary.b * 0.4, 1)
        self:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 1)
        fontString:SetTextColor(1, 1, 1)
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
    end)
    
    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(bgR, bgG, bgB, 0.9)
        self:SetBackdropBorderColor(borderR, borderG, borderB, 0.8)
        fontString:SetTextColor(c.text.r, c.text.g, c.text.b)
    end)
    
    button:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(c.primary.r * 0.2, c.primary.g * 0.2, c.primary.b * 0.2, 1)
    end)
    
    button:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(c.primary.r * 0.4, c.primary.g * 0.4, c.primary.b * 0.4, 1)
    end)
    
    return button
end

-- ============================================================================
-- MODERN CHECKBOX CREATION
-- ============================================================================

local function CreateModernCheckbox(parent, label, tooltip)
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(200, 24)
    
    local c = ACO.colors
    
    -- Checkbox button
    local checkbox = CreateFrame("CheckButton", nil, frame, "BackdropTemplate")
    checkbox:SetSize(20, 20)
    checkbox:SetPoint("LEFT")
    checkbox:SetBackdrop(CardBackdrop)
    checkbox:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.9)
    checkbox:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
    
    -- Checkmark
    local check = checkbox:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("CENTER")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetVertexColor(c.primary.r, c.primary.g, c.primary.b)
    check:Hide()
    checkbox.check = check
    
    -- Override SetChecked to also update the visual
    local originalSetChecked = checkbox.SetChecked
    checkbox.SetChecked = function(self, checked)
        originalSetChecked(self, checked)
        if checked then
            check:Show()
        else
            check:Hide()
        end
    end
    
    checkbox:SetScript("OnClick", function(self)
        local isChecked = self:GetChecked()
        if isChecked then
            check:Show()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        else
            check:Hide()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end
        if self.callback then
            self.callback(isChecked)
        end
    end)
    
    checkbox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, nil, nil, nil, nil, true)
            GameTooltip:Show()
        end
    end)
    
    checkbox:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
        GameTooltip:Hide()
    end)
    
    -- Label
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)
    text:SetText(label)
    text:SetTextColor(c.text.r, c.text.g, c.text.b)
    
    frame.checkbox = checkbox
    frame.label = text
    
    return frame
end

-- ============================================================================
-- MODERN SLIDER CREATION
-- ============================================================================

local function CreateModernSlider(parent, label, minVal, maxVal, step, tooltip)
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(300, 50)
    
    local c = ACO.colors
    
    -- Label
    local text = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    text:SetPoint("TOPLEFT", 0, 0)
    text:SetText(label)
    text:SetTextColor(c.text.r, c.text.g, c.text.b)
    
    -- Value display
    local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueText:SetPoint("TOPRIGHT", 0, 0)
    valueText:SetTextColor(c.primary.r, c.primary.g, c.primary.b)
    
    -- Slider track
    local track = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    track:SetSize(280, 8)
    track:SetPoint("TOP", 0, -22)
    track:SetBackdrop(CardBackdrop)
    track:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 1)
    track:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 1)
    
    -- Slider fill
    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", 2, 0)
    fill:SetHeight(4)
    fill:SetColorTexture(c.primary.r, c.primary.g, c.primary.b, 1)
    
    -- Slider thumb
    local thumb = CreateFrame("Button", nil, track, "BackdropTemplate")
    thumb:SetSize(16, 16)
    thumb:SetBackdrop(CardBackdrop)
    thumb:SetBackdropColor(c.primary.r, c.primary.g, c.primary.b, 1)
    thumb:SetBackdropBorderColor(1, 1, 1, 0.5)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")
    
    local function UpdateSlider(value)
        value = math.max(minVal, math.min(maxVal, value))
        if step then
            value = math.floor(value / step + 0.5) * step
        end
        
        local percent = (value - minVal) / (maxVal - minVal)
        local trackWidth = track:GetWidth() - thumb:GetWidth()
        
        thumb:SetPoint("LEFT", track, "LEFT", percent * trackWidth, 0)
        fill:SetWidth(math.max(1, percent * trackWidth))
        
        -- Format: afficher sans décimale si c'est un entier
        if value == floor(value) then
            valueText:SetText(format("%d", value) .. "s")
        else
            valueText:SetText(format("%.1f", value) .. "s")
        end
        
        frame.value = value
        
        if frame.callback then
            frame.callback(value)
        end
    end
    
    thumb:SetScript("OnDragStart", function(self)
        self.isDragging = true
    end)
    
    thumb:SetScript("OnDragStop", function(self)
        self.isDragging = false
    end)
    
    track:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local x = select(1, GetCursorPosition()) / self:GetEffectiveScale()
            local left = self:GetLeft()
            local width = self:GetWidth() - thumb:GetWidth()
            local percent = math.max(0, math.min(1, (x - left - thumb:GetWidth()/2) / width))
            local value = minVal + percent * (maxVal - minVal)
            UpdateSlider(value)
        end
    end)
    
    track:SetScript("OnUpdate", function(self)
        if thumb.isDragging then
            local x = select(1, GetCursorPosition()) / self:GetEffectiveScale()
            local left = self:GetLeft()
            local width = self:GetWidth() - thumb:GetWidth()
            local percent = math.max(0, math.min(1, (x - left - thumb:GetWidth()/2) / width))
            local value = minVal + percent * (maxVal - minVal)
            UpdateSlider(value)
        end
    end)
    
    frame.UpdateSlider = UpdateSlider
    frame.valueText = valueText
    
    -- Initialiser avec une valeur par défaut après que le frame soit affiché
    frame:SetScript("OnShow", function()
        C_Timer.After(0.05, function()
            if frame.pendingValue then
                UpdateSlider(frame.pendingValue)
                frame.pendingValue = nil
            end
        end)
    end)
    
    -- Méthode pour définir la valeur (avec gestion du timing)
    frame.SetValue = function(self, val)
        if track:GetWidth() > 0 then
            UpdateSlider(val)
        else
            self.pendingValue = val
        end
    end
    
    return frame
end

-- ============================================================================
-- MAIN FRAME CREATION
-- ============================================================================

function ACO:InitUI()
    local c = self.colors
    
    -- Main Frame
    local MainFrame = CreateFrame("Frame", "AutoChestOpenerFrame", UIParent, "BackdropTemplate")
    MainFrame:SetSize(FRAME_WIDTH, FRAME_HEIGHT)
    MainFrame:SetPoint("CENTER")
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")
    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", MainFrame.StopMovingOrSizing)
    MainFrame:SetClampedToScreen(true)
    MainFrame:SetFrameStrata("HIGH")
    MainFrame:SetResizable(true)
    MainFrame:SetResizeBounds(FRAME_MIN_WIDTH, FRAME_MIN_HEIGHT, FRAME_MAX_WIDTH, FRAME_MAX_HEIGHT)
    MainFrame:Hide()
    
    -- Main backdrop with gradient
    MainFrame:SetBackdrop(MainBackdrop)
    MainFrame:SetBackdropColor(c.background.r, c.background.g, c.background.b, 0.95)
    MainFrame:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 0.6)
    
    -- Gradient overlay for depth
    local gradientOverlay = MainFrame:CreateTexture(nil, "BORDER")
    gradientOverlay:SetAllPoints()
    gradientOverlay:SetColorTexture(1, 1, 1, 1)
    gradientOverlay:SetGradient("VERTICAL", 
        CreateColor(0.05, 0.05, 0.1, 0), 
        CreateColor(0.1, 0.15, 0.2, 0.3))
    
    -- ========================================================================
    -- RESIZE HANDLE
    -- ========================================================================
    
    local ResizeHandle = CreateFrame("Button", nil, MainFrame)
    ResizeHandle:SetSize(16, 16)
    ResizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    ResizeHandle:SetFrameLevel(MainFrame:GetFrameLevel() + 10)
    ResizeHandle:EnableMouse(true)
    
    -- Resize handle texture (diagonal lines)
    local resizeTex = ResizeHandle:CreateTexture(nil, "OVERLAY")
    resizeTex:SetAllPoints()
    resizeTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    
    ResizeHandle:SetScript("OnEnter", function(self)
        resizeTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    end)
    
    ResizeHandle:SetScript("OnLeave", function(self)
        resizeTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    end)
    
    ResizeHandle:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            resizeTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
            MainFrame:StartSizing("BOTTOMRIGHT")
        end
    end)
    
    ResizeHandle:SetScript("OnMouseUp", function(self, button)
        resizeTex:SetTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
        MainFrame:StopMovingOrSizing()
    end)
    
    -- Header
    local Header = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
    Header:SetHeight(HEADER_HEIGHT)
    Header:SetPoint("TOPLEFT", 1, -1)
    Header:SetPoint("TOPRIGHT", -1, -1)
    Header:SetBackdrop(CardBackdrop)
    Header:SetBackdropColor(c.primary.r * 0.15, c.primary.g * 0.15, c.primary.b * 0.15, 1)
    Header:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- Icon (using Atlas)
    local Icon = Header:CreateTexture(nil, "ARTWORK")
    Icon:SetSize(32, 32)
    Icon:SetPoint("LEFT", PADDING, 0)
    Icon:SetAtlas("VignetteLootChest")
    
    -- Title
    local Title = Header:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    Title:SetPoint("LEFT", Icon, "RIGHT", 10, 0)
    Title:SetText("|cff00ccffAuto Chest Opener|r")
    
    -- Version
    local Version = Header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    Version:SetPoint("LEFT", Title, "RIGHT", 8, 0)
    Version:SetText("v" .. ACO.version)
    Version:SetTextColor(c.textDim.r, c.textDim.g, c.textDim.b)
    
    -- Close button
    local CloseBtn = CreateFrame("Button", nil, Header)
    CloseBtn:SetSize(24, 24)
    CloseBtn:SetPoint("RIGHT", -PADDING, 0)
    
    local closeTex = CloseBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetAtlas("common-icon-redx")
    
    CloseBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(c.error.r, c.error.g, c.error.b)
    end)
    CloseBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(c.textDim.r, c.textDim.g, c.textDim.b)
    end)
    CloseBtn:SetScript("OnClick", function()
        MainFrame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)
    
    -- ========================================================================
    -- TAB SYSTEM
    -- ========================================================================
    
    local TabContainer = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
    TabContainer:SetHeight(TAB_HEIGHT + 4)
    TabContainer:SetPoint("TOPLEFT", Header, "BOTTOMLEFT", 1, 0)
    TabContainer:SetPoint("TOPRIGHT", Header, "BOTTOMRIGHT", -1, 0)
    TabContainer:SetBackdrop(CardBackdrop)
    TabContainer:SetBackdropColor(c.background.r, c.background.g, c.background.b, 0.9)
    TabContainer:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- Content frames for each tab
    local ContainersContent = CreateFrame("Frame", nil, MainFrame)
    ContainersContent:SetPoint("TOPLEFT", TabContainer, "BOTTOMLEFT", 0, 0)
    ContainersContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    
    local StatsContent = CreateFrame("Frame", nil, MainFrame)
    StatsContent:SetPoint("TOPLEFT", TabContainer, "BOTTOMLEFT", 0, 0)
    StatsContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    StatsContent:Hide()
    
    local HistoryContent = CreateFrame("Frame", nil, MainFrame)
    HistoryContent:SetPoint("TOPLEFT", TabContainer, "BOTTOMLEFT", 0, 0)
    HistoryContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    HistoryContent:Hide()
    
    UI.tabs = {}
    UI.currentTab = "containers"
    
    local function CreateTab(parent, text, icon, tabKey, xOffset)
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
        tab:SetSize(130, TAB_HEIGHT)
        tab:SetPoint("LEFT", xOffset, 0)
        tab:SetBackdrop(CardBackdrop)
        
        local tabIcon = tab:CreateTexture(nil, "ARTWORK")
        tabIcon:SetSize(14, 14)
        tabIcon:SetPoint("LEFT", 10, 0)
        tabIcon:SetAtlas(icon)
        
        local tabText = tab:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        tabText:SetPoint("LEFT", tabIcon, "RIGHT", 6, 0)
        tabText:SetText(text)
        
        tab.isActive = false
        tab.tabKey = tabKey
        
        local function UpdateTabAppearance()
            if tab.isActive then
                tab:SetBackdropColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 1)
                tab:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 1)
                tabText:SetTextColor(1, 1, 1)
                tabIcon:SetVertexColor(c.primary.r, c.primary.g, c.primary.b)
            else
                tab:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.5)
                tab:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
                tabText:SetTextColor(c.textDim.r, c.textDim.g, c.textDim.b)
                tabIcon:SetVertexColor(c.textDim.r, c.textDim.g, c.textDim.b)
            end
        end
        
        tab:SetScript("OnEnter", function(self)
            if not self.isActive then
                self:SetBackdropColor(c.primary.r * 0.2, c.primary.g * 0.2, c.primary.b * 0.2, 0.8)
                tabText:SetTextColor(c.text.r, c.text.g, c.text.b)
            end
        end)
        
        tab:SetScript("OnLeave", function(self)
            UpdateTabAppearance()
        end)
        
        tab:SetScript("OnClick", function(self)
            UI:SwitchTab(self.tabKey)
            PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        end)
        
        tab.UpdateAppearance = UpdateTabAppearance
        UI.tabs[tabKey] = tab
        
        return tab
    end
    
    local containersTab = CreateTab(TabContainer, "Conteneurs", "VignetteLootChest", "containers", PADDING)
    local statsTab = CreateTab(TabContainer, "Statistiques", "poi-workorders", "stats", PADDING + 134)
    local historyTab = CreateTab(TabContainer, "Historique", "communities-icon-clock", "history", PADDING + 268)
    
    function UI:SwitchTab(tabKey)
        self.currentTab = tabKey
        
        -- Hide all content
        ContainersContent:Hide()
        StatsContent:Hide()
        HistoryContent:Hide()
        
        -- Deactivate all tabs
        for _, tab in pairs(self.tabs) do
            tab.isActive = false
            tab:UpdateAppearance()
        end
        
        -- Activate selected tab
        self.tabs[tabKey].isActive = true
        self.tabs[tabKey]:UpdateAppearance()
        
        -- Show corresponding content
        if tabKey == "containers" then
            ContainersContent:Show()
            self:RefreshList()
        elseif tabKey == "stats" then
            StatsContent:Show()
            self:RefreshStats()
        elseif tabKey == "history" then
            HistoryContent:Show()
            self:RefreshHistory()
        end
    end
    
    -- Initialize first tab as active
    containersTab.isActive = true
    containersTab:UpdateAppearance()
    
    -- ========================================================================
    -- OPTIONS SECTION (inside ContainersContent)
    -- ========================================================================
    
    local OptionsSection = CreateFrame("Frame", nil, ContainersContent, "BackdropTemplate")
    OptionsSection:SetHeight(140)
    OptionsSection:SetPoint("TOPLEFT", PADDING, -PADDING)
    OptionsSection:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    OptionsSection:SetBackdrop(CardBackdrop)
    OptionsSection:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.5)
    OptionsSection:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- Section title with icon
    local OptionsIcon = OptionsSection:CreateTexture(nil, "ARTWORK")
    OptionsIcon:SetSize(16, 16)
    OptionsIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    OptionsIcon:SetAtlas("options")
    
    local OptionsTitle = OptionsSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    OptionsTitle:SetPoint("LEFT", OptionsIcon, "RIGHT", 6, 0)
    OptionsTitle:SetText("Paramètres")
    OptionsTitle:SetTextColor(c.primary.r, c.primary.g, c.primary.b)
    
    -- Enable checkbox
    local EnableCheck = CreateModernCheckbox(OptionsSection, "Activer l'ouverture automatique", "Active ou désactive l'addon")
    EnableCheck:SetPoint("TOPLEFT", OptionsTitle, "BOTTOMLEFT", 0, -12)
    EnableCheck.checkbox:SetChecked(ACO.db.enabled)
    EnableCheck.checkbox.callback = function(checked)
        ACO.db.enabled = checked
    end
    
    -- Notifications checkbox
    local NotifyCheck = CreateModernCheckbox(OptionsSection, "Afficher les notifications", "Affiche les messages dans le chat")
    NotifyCheck:SetPoint("TOPLEFT", EnableCheck, "BOTTOMLEFT", 0, -8)
    NotifyCheck.checkbox:SetChecked(ACO.db.showNotifications)
    NotifyCheck.checkbox.callback = function(checked)
        ACO.db.showNotifications = checked
    end
    
    -- Sound checkbox
    local SoundCheck = CreateModernCheckbox(OptionsSection, "Jouer les sons", "Joue un son lors de l'ouverture")
    SoundCheck:SetPoint("LEFT", NotifyCheck, "RIGHT", 80, 0)
    SoundCheck.checkbox:SetChecked(ACO.db.notificationSound)
    SoundCheck.checkbox.callback = function(checked)
        ACO.db.notificationSound = checked
    end
    
    -- Delay slider
    local DelaySlider = CreateModernSlider(OptionsSection, "Délai avant ouverture:", 0, 10, 0.5, "Temps d'attente avant l'ouverture automatique")
    DelaySlider:SetPoint("TOPLEFT", NotifyCheck, "BOTTOMLEFT", 0, -12)
    DelaySlider.callback = function(value)
        ACO.db.delay = value
    end
    
    -- Initialiser le slider après que le frame soit visible
    MainFrame:HookScript("OnShow", function()
        C_Timer.After(0.1, function()
            if DelaySlider.SetValue then
                DelaySlider:SetValue(ACO.db.delay)
            elseif DelaySlider.UpdateSlider then
                DelaySlider:UpdateSlider(ACO.db.delay)
            end
        end)
    end)
    
    -- Aussi initialiser au chargement
    C_Timer.After(0.5, function()
        if DelaySlider.valueText then
            -- Afficher la valeur même si le slider n'est pas visible
            local val = ACO.db.delay
            if val == floor(val) then
                DelaySlider.valueText:SetText(format("%d", val) .. "s")
            else
                DelaySlider.valueText:SetText(format("%.1f", val) .. "s")
            end
        end
    end)
    
    -- ========================================================================
    -- ADD ITEM SECTION (inside ContainersContent)
    -- ========================================================================
    
    local AddSection = CreateFrame("Frame", nil, ContainersContent, "BackdropTemplate")
    AddSection:SetHeight(90)
    AddSection:SetPoint("TOPLEFT", OptionsSection, "BOTTOMLEFT", 0, -PADDING)
    AddSection:SetPoint("TOPRIGHT", OptionsSection, "BOTTOMRIGHT", 0, -PADDING)
    AddSection:SetBackdrop(CardBackdrop)
    AddSection:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.5)
    AddSection:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- Section title with icon
    local AddIcon = AddSection:CreateTexture(nil, "ARTWORK")
    AddIcon:SetSize(16, 16)
    AddIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    AddIcon:SetAtlas("communities-icon-addgroupplus")
    
    local AddTitle = AddSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    AddTitle:SetPoint("LEFT", AddIcon, "RIGHT", 6, 0)
    AddTitle:SetText("Ajouter un conteneur")
    AddTitle:SetTextColor(c.success.r, c.success.g, c.success.b)
    
    -- Drop zone / Input
    local DropZone = CreateFrame("Button", nil, AddSection, "BackdropTemplate")
    DropZone:SetSize(200, 40)
    DropZone:SetPoint("LEFT", PADDING, -8)
    DropZone:SetBackdrop(CardBackdrop)
    DropZone:SetBackdropColor(0.1, 0.1, 0.15, 1)
    DropZone:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
    
    local DropText = DropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    DropText:SetPoint("CENTER")
    DropText:SetText("|cff888888Glissez un item ici|r")
    DropZone.text = DropText
    
    -- Handle item drop
    DropZone:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" then
            ClearCursor()
            if itemID then
                ACO:AddContainer(itemID)
                DropText:SetText("|cff00ff80Item ajouté!|r")
                C_Timer.After(1.5, function()
                    DropText:SetText("|cff888888Glissez un item ici|r")
                end)
            end
        end
    end)
    
    DropZone:SetScript("OnClick", function(self)
        local infoType, itemID = GetCursorInfo()
        if infoType == "item" then
            ClearCursor()
            if itemID then
                ACO:AddContainer(itemID)
                DropText:SetText("|cff00ff80Item ajouté!|r")
                C_Timer.After(1.5, function()
                    DropText:SetText("|cff888888Glissez un item ici|r")
                end)
            end
        end
    end)
    
    DropZone:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText("Glissez un coffre, sac ou conteneur ici pour l'ajouter à la liste", nil, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    
    DropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
        GameTooltip:Hide()
    end)
    
    -- ID Input
    local IDInput = CreateFrame("EditBox", nil, AddSection, "BackdropTemplate")
    IDInput:SetSize(100, 40)
    IDInput:SetPoint("LEFT", DropZone, "RIGHT", 10, 0)
    IDInput:SetBackdrop(CardBackdrop)
    IDInput:SetBackdropColor(0.1, 0.1, 0.15, 1)
    IDInput:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
    IDInput:SetFontObject("GameFontHighlight")
    IDInput:SetTextInsets(10, 10, 0, 0)
    IDInput:SetAutoFocus(false)
    IDInput:SetNumeric(true)
    IDInput:SetMaxLetters(10)
    
    local IDPlaceholder = IDInput:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    IDPlaceholder:SetPoint("CENTER")
    IDPlaceholder:SetText("|cff666666Item ID|r")
    
    IDInput:SetScript("OnTextChanged", function(self)
        if self:GetText() ~= "" then
            IDPlaceholder:Hide()
        else
            IDPlaceholder:Show()
        end
    end)
    
    IDInput:SetScript("OnEnterPressed", function(self)
        local id = tonumber(self:GetText())
        if id then
            ACO:AddContainer(id)
            self:SetText("")
        end
        self:ClearFocus()
    end)
    
    IDInput:SetScript("OnEscapePressed", function(self)
        self:SetText("")
        self:ClearFocus()
    end)
    
    -- Add button
    local AddBtn = CreateModernButton(AddSection, "Ajouter", 80, 40, true)
    AddBtn:SetPoint("LEFT", IDInput, "RIGHT", 10, 0)
    AddBtn:SetScript("OnClick", function()
        local id = tonumber(IDInput:GetText())
        if id then
            ACO:AddContainer(id)
            IDInput:SetText("")
        else
            ACO:Print("Veuillez entrer un ID valide.", true)
        end
    end)
    
    -- ========================================================================
    -- CONTAINER LIST SECTION (inside ContainersContent)
    -- ========================================================================
    
    local ListSection = CreateFrame("Frame", nil, ContainersContent, "BackdropTemplate")
    ListSection:SetPoint("TOPLEFT", AddSection, "BOTTOMLEFT", 0, -PADDING)
    ListSection:SetPoint("TOPRIGHT", AddSection, "BOTTOMRIGHT", 0, -PADDING)
    ListSection:SetPoint("BOTTOMLEFT", ContainersContent, "BOTTOMLEFT", 0, PADDING)
    ListSection:SetPoint("BOTTOMRIGHT", ContainersContent, "BOTTOMRIGHT", 0, PADDING)
    ListSection:SetBackdrop(CardBackdrop)
    ListSection:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.5)
    ListSection:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- Section title with icon
    local ListIcon = ListSection:CreateTexture(nil, "ARTWORK")
    ListIcon:SetSize(16, 16)
    ListIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    ListIcon:SetAtlas("VignetteLootChest")
    
    local ListTitle = ListSection:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    ListTitle:SetPoint("LEFT", ListIcon, "RIGHT", 6, 0)
    ListTitle:SetText("Conteneurs enregistrés")
    ListTitle:SetTextColor(c.accent.r, c.accent.g, c.accent.b)
    
    -- Count
    local ListCount = ListSection:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    ListCount:SetPoint("TOPRIGHT", -PADDING - 100, -PADDING)
    ListCount:SetTextColor(c.textDim.r, c.textDim.g, c.textDim.b)
    UI.listCount = ListCount
    
    -- Open All Button
    local OpenAllBtn = CreateModernButton(ListSection, "Ouvrir tout", 90, 24, true)
    OpenAllBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING + 4)
    OpenAllBtn:SetScript("OnClick", function()
        local count = ACO:OpenAllContainers()
        if count > 0 then
            ACO:Print(string.format("Ouverture de %d conteneur(s)...", count))
        end
    end)
    OpenAllBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(c.primary.r * 0.4, c.primary.g * 0.4, c.primary.b * 0.4, 1)
        self:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Ouvrir tous les conteneurs")
        GameTooltip:AddLine("Ouvre immédiatement tous les conteneurs", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("référencés présents dans votre inventaire.", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    OpenAllBtn:SetScript("OnLeave", function(self)
        local bgR, bgG, bgB = c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3
        local borderR, borderG, borderB = c.primary.r, c.primary.g, c.primary.b
        self:SetBackdropColor(bgR, bgG, bgB, 0.9)
        self:SetBackdropBorderColor(borderR, borderG, borderB, 0.8)
        self.text:SetTextColor(c.text.r, c.text.g, c.text.b)
        GameTooltip:Hide()
    end)

    -- Import Button
    local ImportBtn = CreateModernButton(ListSection, "Import", 60, 24, false)
    ImportBtn:SetPoint("RIGHT", OpenAllBtn, "LEFT", -8, 0)
    ImportBtn:SetScript("OnClick", function()
        ACO:ShowImportFrame()
    end)
    ImportBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(c.success.r * 0.4, c.success.g * 0.4, c.success.b * 0.4, 1)
        self:SetBackdropBorderColor(c.success.r, c.success.g, c.success.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Importer des conteneurs")
        GameTooltip:AddLine("Collez une liste d'IDs depuis Wowhead", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ImportBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.9)
        self:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
        self.text:SetTextColor(c.text.r, c.text.g, c.text.b)
        GameTooltip:Hide()
    end)

    -- Export Button
    local ExportBtn = CreateModernButton(ListSection, "Export", 60, 24, false)
    ExportBtn:SetPoint("RIGHT", ImportBtn, "LEFT", -8, 0)
    ExportBtn:SetScript("OnClick", function()
        ACO:ShowExportFrame()
    end)
    ExportBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(c.primary.r * 0.4, c.primary.g * 0.4, c.primary.b * 0.4, 1)
        self:SetBackdropBorderColor(c.primary.r, c.primary.g, c.primary.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Exporter les conteneurs")
        GameTooltip:AddLine("Copiez la liste pour la sauvegarder", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ExportBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.9)
        self:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
        self.text:SetTextColor(c.text.r, c.text.g, c.text.b)
        GameTooltip:Hide()
    end)
    
    -- Remove All Button
    local RemoveAllBtn = CreateModernButton(ListSection, "Retirer tout", 80, 24, false)
    RemoveAllBtn:SetPoint("RIGHT", ExportBtn, "LEFT", -8, 0)
    RemoveAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("ACO_REMOVE_ALL_CONTAINERS")
    end)
    RemoveAllBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(c.error.r * 0.4, c.error.g * 0.4, c.error.b * 0.4, 1)
        self:SetBackdropBorderColor(c.error.r, c.error.g, c.error.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine("Retirer tous les conteneurs", 1, 0.3, 0.3)
        GameTooltip:AddLine("Retire TOUS les conteneurs de la liste.", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffff8800Cette action est définitive !|r", 1, 0.5, 0)
        GameTooltip:Show()
    end)
    RemoveAllBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.9)
        self:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
        self.text:SetTextColor(c.text.r, c.text.g, c.text.b)
        GameTooltip:Hide()
    end)
    
    -- Scroll frame
    local ScrollFrame = CreateFrame("ScrollFrame", nil, ListSection, "UIPanelScrollFrameTemplate")
    ScrollFrame:SetPoint("TOPLEFT", PADDING, -35)
    ScrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 20, PADDING)
    
    local ScrollChild = CreateFrame("Frame", nil, ScrollFrame)
    ScrollChild:SetSize(ScrollFrame:GetWidth(), 1)
    ScrollFrame:SetScrollChild(ScrollChild)
    
    UI.scrollChild = ScrollChild
    UI.listItems = {}
    
    -- ========================================================================
    -- LIST ITEM CREATION
    -- ========================================================================
    
    local function CreateListItem(itemID, index)
        local item = CreateFrame("Frame", nil, ScrollChild, "BackdropTemplate")
        item:SetSize(ScrollFrame:GetWidth() - 10, LIST_ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -(index - 1) * (LIST_ITEM_HEIGHT + 4))
        item:SetBackdrop(CardBackdrop)
        item:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        item:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
        
        -- Item icon
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", 8, 0)
        
        -- Item name
        local name = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        name:SetPoint("LEFT", icon, "RIGHT", 10, 6)
        name:SetWidth(260)
        name:SetJustifyH("LEFT")
        name:SetTextColor(c.text.r, c.text.g, c.text.b)
        
        -- Item ID
        local idText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        idText:SetPoint("LEFT", icon, "RIGHT", 10, -8)
        idText:SetText("ID: " .. itemID)
        idText:SetTextColor(c.textDim.r, c.textDim.g, c.textDim.b)
        
        -- Remove button
        local removeBtn = CreateFrame("Button", nil, item, "BackdropTemplate")
        removeBtn:SetSize(24, 24)
        removeBtn:SetPoint("RIGHT", -8, 0)
        removeBtn:SetBackdrop(CardBackdrop)
        removeBtn:SetBackdropColor(c.error.r * 0.3, c.error.g * 0.3, c.error.b * 0.3, 0.8)
        removeBtn:SetBackdropBorderColor(c.error.r * 0.5, c.error.g * 0.5, c.error.b * 0.5, 0.8)
        
        local removeIcon = removeBtn:CreateTexture(nil, "OVERLAY")
        removeIcon:SetSize(12, 12)
        removeIcon:SetPoint("CENTER")
        removeIcon:SetAtlas("common-icon-redx")
        
        removeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(c.error.r * 0.5, c.error.g * 0.5, c.error.b * 0.5, 1)
            self:SetBackdropBorderColor(c.error.r, c.error.g, c.error.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText("Retirer de la liste")
            GameTooltip:Show()
        end)
        
        removeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(c.error.r * 0.3, c.error.g * 0.3, c.error.b * 0.3, 0.8)
            self:SetBackdropBorderColor(c.error.r * 0.5, c.error.g * 0.5, c.error.b * 0.5, 0.8)
            GameTooltip:Hide()
        end)
        
        removeBtn:SetScript("OnClick", function()
            ACO:RemoveContainer(itemID)
        end)
        
        -- Load item info
        local itemInfo = C_Item.GetItemInfo(itemID)
        if itemInfo then
            name:SetText(itemInfo)
            local itemIcon = C_Item.GetItemIconByID(itemID)
            if itemIcon then
                icon:SetTexture(itemIcon)
            end
        else
            name:SetText("|cff888888Chargement...|r")
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            
            -- Request item info and update when available
            local item_obj = Item:CreateFromItemID(itemID)
            item_obj:ContinueOnItemLoad(function()
                local loadedName = C_Item.GetItemInfo(itemID)
                local loadedIcon = C_Item.GetItemIconByID(itemID)
                if loadedName then
                    name:SetText(loadedName)
                end
                if loadedIcon then
                    icon:SetTexture(loadedIcon)
                end
            end)
        end
        
        -- Hover effects
        item:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.12, 0.12, 0.18, 1)
            self:SetBackdropBorderColor(c.primary.r * 0.5, c.primary.g * 0.5, c.primary.b * 0.5, 0.8)
            
            -- Show item tooltip
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink("item:" .. itemID)
            GameTooltip:Show()
        end)
        
        item:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
            self:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
            GameTooltip:Hide()
        end)
        
        return item
    end
    
    -- ========================================================================
    -- REFRESH LIST FUNCTION
    -- ========================================================================
    
    function UI:RefreshList()
        -- Clear existing items
        for _, item in ipairs(self.listItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self.listItems)
        
        -- Create new items
        local index = 1
        for itemID in pairs(ACO.db.containers) do
            local listItem = CreateListItem(itemID, index)
            table.insert(self.listItems, listItem)
            index = index + 1
        end
        
        -- Update scroll child height
        ScrollChild:SetHeight(max(1, (index - 1) * (LIST_ITEM_HEIGHT + 4)))
        
        -- Update count
        local count = index - 1
        self.listCount:SetText(count .. " item" .. (count > 1 and "s" or ""))
    end
    
    -- ========================================================================
    -- STATISTICS TAB CONTENT
    -- ========================================================================
    
    local StatsPanel = CreateFrame("Frame", nil, StatsContent, "BackdropTemplate")
    StatsPanel:SetPoint("TOPLEFT", PADDING, -PADDING)
    StatsPanel:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    StatsPanel:SetBackdrop(CardBackdrop)
    StatsPanel:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.5)
    StatsPanel:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- Stats title
    local StatsIcon = StatsPanel:CreateTexture(nil, "ARTWORK")
    StatsIcon:SetSize(20, 20)
    StatsIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    StatsIcon:SetAtlas("poi-workorders")
    
    local StatsTitle = StatsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    StatsTitle:SetPoint("LEFT", StatsIcon, "RIGHT", 8, 0)
    StatsTitle:SetText("Statistiques")
    StatsTitle:SetTextColor(c.primary.r, c.primary.g, c.primary.b)
    
    -- Clear Stats Button
    local ClearStatsBtn = CreateModernButton(StatsPanel, "Réinitialiser", 100, 24, false)
    ClearStatsBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    ClearStatsBtn:SetScript("OnClick", function()
        StaticPopup_Show("ACO_CLEAR_STATS")
    end)
    
    -- Create stat line helper
    local function CreateStatLine(parent, label, yOffset)
        local line = CreateFrame("Frame", nil, parent)
        line:SetHeight(28)
        line:SetPoint("TOPLEFT", PADDING, yOffset)
        line:SetPoint("TOPRIGHT", -PADDING, yOffset)
        
        local labelText = line:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        labelText:SetPoint("LEFT", 0, 0)
        labelText:SetText(label)
        labelText:SetTextColor(c.text.r, c.text.g, c.text.b)
        
        local valueText = line:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        valueText:SetPoint("RIGHT", 0, 0)
        valueText:SetTextColor(c.accent.r, c.accent.g, c.accent.b)
        
        line.value = valueText
        return line
    end
    
    local statLines = {}
    statLines.total = CreateStatLine(StatsPanel, "Total ouvert (tous temps):", -50)
    statLines.session = CreateStatLine(StatsPanel, "Ouvert cette session:", -78)
    statLines.unique = CreateStatLine(StatsPanel, "Items uniques ouverts:", -106)
    statLines.totalGold = CreateStatLine(StatsPanel, "Or total gagné:", -134)
    statLines.sessionGold = CreateStatLine(StatsPanel, "Or cette session:", -162)
    statLines.firstOpen = CreateStatLine(StatsPanel, "Première ouverture:", -190)
    statLines.lastOpen = CreateStatLine(StatsPanel, "Dernière ouverture:", -218)
    
    -- Top items section
    local TopItemsTitle = StatsPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    TopItemsTitle:SetPoint("TOPLEFT", PADDING, -256)
    TopItemsTitle:SetText("Top 5 des items les plus ouverts:")
    TopItemsTitle:SetTextColor(c.secondary.r, c.secondary.g, c.secondary.b)
    
    UI.topItemsFrames = {}
    for i = 1, 5 do
        local itemFrame = CreateFrame("Frame", nil, StatsPanel, "BackdropTemplate")
        itemFrame:SetHeight(36)
        itemFrame:SetPoint("TOPLEFT", PADDING, -276 - (i-1) * 40)
        itemFrame:SetPoint("TOPRIGHT", -PADDING, -276 - (i-1) * 40)
        itemFrame:SetBackdrop(CardBackdrop)
        itemFrame:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        itemFrame:SetBackdropBorderColor(c.primary.r * 0.2, c.primary.g * 0.2, c.primary.b * 0.2, 0.5)
        
        local rankText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        rankText:SetPoint("LEFT", 10, 0)
        rankText:SetText(format("#%d", i))
        rankText:SetTextColor(c.accent.r, c.accent.g, c.accent.b)
        
        local icon = itemFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 45, 0)
        
        local nameText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameText:SetWidth(200)
        nameText:SetJustifyH("LEFT")
        
        local countText = itemFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        countText:SetPoint("RIGHT", -10, 0)
        countText:SetTextColor(c.success.r, c.success.g, c.success.b)
        
        itemFrame.rank = rankText
        itemFrame.icon = icon
        itemFrame.name = nameText
        itemFrame.count = countText
        itemFrame:Hide()
        
        UI.topItemsFrames[i] = itemFrame
    end
    
    UI.statLines = statLines
    
    function UI:RefreshStats()
        local stats = ACO:GetStats()
        
        self.statLines.total.value:SetText(format("|cff00ff00%d|r", stats.totalOpened))
        self.statLines.session.value:SetText(format("|cff00ccff%d|r", stats.sessionOpened))
        self.statLines.unique.value:SetText(format("|cffffff00%d|r", stats.uniqueItems))
        self.statLines.totalGold.value:SetText(ACO:FormatMoney(stats.totalGold))
        self.statLines.sessionGold.value:SetText(ACO:FormatMoney(stats.sessionGold))
        self.statLines.firstOpen.value:SetText(ACO:FormatTimestamp(stats.firstOpen))
        self.statLines.lastOpen.value:SetText(ACO:FormatRelativeTime(stats.lastOpen))
        
        -- Update top items
        for i, frame in ipairs(self.topItemsFrames) do
            local item = stats.topItems[i]
            if item then
                frame:Show()
                frame.count:SetText(format("x%d", item.count))
                
                -- Load item info
                local itemInfo = C_Item.GetItemInfo(item.itemID)
                local itemIcon = C_Item.GetItemIconByID(item.itemID)
                
                if itemInfo then
                    frame.name:SetText(itemInfo)
                else
                    frame.name:SetText("|cff888888Chargement...|r")
                    local itemObj = Item:CreateFromItemID(item.itemID)
                    itemObj:ContinueOnItemLoad(function()
                        local loadedName = C_Item.GetItemInfo(item.itemID)
                        if loadedName then
                            frame.name:SetText(loadedName)
                        end
                    end)
                end
                
                if itemIcon then
                    frame.icon:SetTexture(itemIcon)
                else
                    frame.icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
                end
            else
                frame:Hide()
            end
        end
    end
    
    -- ========================================================================
    -- HISTORY TAB CONTENT
    -- ========================================================================
    
    local HistoryPanel = CreateFrame("Frame", nil, HistoryContent, "BackdropTemplate")
    HistoryPanel:SetPoint("TOPLEFT", PADDING, -PADDING)
    HistoryPanel:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    HistoryPanel:SetBackdrop(CardBackdrop)
    HistoryPanel:SetBackdropColor(c.backgroundLight.r, c.backgroundLight.g, c.backgroundLight.b, 0.5)
    HistoryPanel:SetBackdropBorderColor(c.primary.r * 0.3, c.primary.g * 0.3, c.primary.b * 0.3, 0.5)
    
    -- History title
    local HistoryIcon = HistoryPanel:CreateTexture(nil, "ARTWORK")
    HistoryIcon:SetSize(20, 20)
    HistoryIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    HistoryIcon:SetAtlas("communities-icon-clock")
    
    local HistoryTitle = HistoryPanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    HistoryTitle:SetPoint("LEFT", HistoryIcon, "RIGHT", 8, 0)
    HistoryTitle:SetText("Historique des ouvertures")
    HistoryTitle:SetTextColor(c.primary.r, c.primary.g, c.primary.b)
    
    -- Clear History Button
    local ClearHistoryBtn = CreateModernButton(HistoryPanel, "Effacer", 80, 24, false)
    ClearHistoryBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    ClearHistoryBtn:SetScript("OnClick", function()
        StaticPopup_Show("ACO_CLEAR_HISTORY")
    end)
    
    -- History scroll frame
    local HistoryScrollFrame = CreateFrame("ScrollFrame", nil, HistoryPanel, "UIPanelScrollFrameTemplate")
    HistoryScrollFrame:SetPoint("TOPLEFT", PADDING, -50)
    HistoryScrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 20, PADDING)
    
    local HistoryScrollChild = CreateFrame("Frame", nil, HistoryScrollFrame)
    HistoryScrollChild:SetSize(HistoryScrollFrame:GetWidth(), 1)
    HistoryScrollFrame:SetScrollChild(HistoryScrollChild)
    
    UI.historyItems = {}
    
    local function CreateHistoryItem(entry, index)
        local item = CreateFrame("Frame", nil, HistoryScrollChild, "BackdropTemplate")
        item:SetSize(HistoryScrollFrame:GetWidth() - 10, 44)
        item:SetPoint("TOPLEFT", 0, -(index - 1) * 48)
        item:SetBackdrop(CardBackdrop)
        item:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
        item:SetBackdropBorderColor(c.primary.r * 0.2, c.primary.g * 0.2, c.primary.b * 0.2, 0.5)
        
        -- Time
        local timeText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        timeText:SetPoint("TOPLEFT", 10, -6)
        timeText:SetText(ACO:FormatRelativeTime(entry.timestamp))
        timeText:SetTextColor(c.textDim.r, c.textDim.g, c.textDim.b)
        
        -- Full date on second line
        local dateText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        dateText:SetPoint("TOPLEFT", 10, -20)
        dateText:SetText(date("%d/%m/%Y %H:%M", entry.timestamp))
        dateText:SetTextColor(c.textDim.r * 0.7, c.textDim.g * 0.7, c.textDim.b * 0.7)
        
        -- Icon
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(28, 28)
        icon:SetPoint("LEFT", 100, 0)
        if entry.itemIcon then
            icon:SetTexture(entry.itemIcon)
        else
            local itemIcon = C_Item.GetItemIconByID(entry.itemID)
            icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        end
        
        -- Item name
        local nameText = item:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        nameText:SetPoint("LEFT", icon, "RIGHT", 10, 6)
        nameText:SetWidth(200)
        nameText:SetJustifyH("LEFT")
        
        local itemInfo = C_Item.GetItemInfo(entry.itemID)
        if itemInfo then
            nameText:SetText(itemInfo)
        else
            nameText:SetText(entry.itemName or "|cff888888Chargement...|r")
            local itemObj = Item:CreateFromItemID(entry.itemID)
            itemObj:ContinueOnItemLoad(function()
                local loadedName = C_Item.GetItemInfo(entry.itemID)
                if loadedName then
                    nameText:SetText(loadedName)
                end
            end)
        end
        
        -- Gold gained (if any)
        if entry.goldGained and entry.goldGained > 0 then
            local goldText = item:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
            goldText:SetPoint("LEFT", icon, "RIGHT", 10, -8)
            goldText:SetText(ACO:FormatMoney(entry.goldGained))
        end
        
        -- Hover
        item:SetScript("OnEnter", function(self)
            self:SetBackdropColor(0.12, 0.12, 0.18, 1)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink("item:" .. entry.itemID)
            if entry.goldGained and entry.goldGained > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine("Or obtenu: " .. ACO:FormatMoneyShort(entry.goldGained), 1, 0.84, 0)
            end
            GameTooltip:Show()
        end)
        
        item:SetScript("OnLeave", function(self)
            self:SetBackdropColor(0.08, 0.08, 0.12, 0.8)
            GameTooltip:Hide()
        end)
        
        return item
    end
    
    function UI:RefreshHistory()
        -- Clear existing items
        for _, item in ipairs(self.historyItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self.historyItems)
        
        -- Get history
        local history = ACO:GetHistory(50)
        
        if #history == 0 then
            -- Show empty message
            if not self.historyEmptyText then
                self.historyEmptyText = HistoryScrollChild:CreateFontString(nil, "OVERLAY", "GameFontNormal")
                self.historyEmptyText:SetPoint("CENTER", 0, 50)
                self.historyEmptyText:SetText("|cff666666Aucune ouverture enregistrée|r")
            end
            self.historyEmptyText:Show()
            HistoryScrollChild:SetHeight(100)
        else
            if self.historyEmptyText then
                self.historyEmptyText:Hide()
            end
            
            -- Create history items
            for i, entry in ipairs(history) do
                local historyItem = CreateHistoryItem(entry, i)
                tinsert(self.historyItems, historyItem)
            end
            
            -- Update scroll child height
            HistoryScrollChild:SetHeight(max(1, #history * 48))
        end
    end
    
    -- ========================================================================
    -- CONFIRMATION POPUPS
    -- ========================================================================
    
    StaticPopupDialogs["ACO_CLEAR_STATS"] = {
        text = "Voulez-vous réinitialiser toutes les statistiques ?",
        button1 = "Oui",
        button2 = "Non",
        OnAccept = function()
            ACO:ClearStats()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopupDialogs["ACO_CLEAR_HISTORY"] = {
        text = "Voulez-vous effacer tout l'historique ?",
        button1 = "Oui",
        button2 = "Non",
        OnAccept = function()
            ACO:ClearHistory()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    StaticPopupDialogs["ACO_REMOVE_ALL_CONTAINERS"] = {
        text = "|cffff8800ATTENTION !|r\n\nCette action va retirer TOUS les conteneurs de la liste.\n\nVoulez-vous continuer ?",
        button1 = "Oui, retirer tout",
        button2 = "Annuler",
        OnAccept = function()
            ACO:RemoveAllContainers()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
    
    -- ========================================================================
    -- TOGGLE FUNCTION
    -- ========================================================================
    
    function UI:Toggle()
        if MainFrame:IsShown() then
            MainFrame:Hide()
            PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
        else
            MainFrame:Show()
            PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
            self:SwitchTab(self.currentTab or "containers")
        end
    end
    
    function UI:Show()
        MainFrame:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        self:SwitchTab(self.currentTab or "containers")
    end
    
    function UI:Hide()
        MainFrame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end
    
    -- ========================================================================
    -- RESIZE HANDLER
    -- ========================================================================
    
    MainFrame:SetScript("OnSizeChanged", function(self, width, height)
        -- Update ScrollChild width to match ScrollFrame
        C_Timer.After(0.01, function()
            if ScrollFrame:GetWidth() > 0 then
                ScrollChild:SetWidth(ScrollFrame:GetWidth())
                -- Update list items width
                for _, item in ipairs(UI.listItems) do
                    item:SetWidth(ScrollFrame:GetWidth() - 10)
                end
            end
        end)
    end)
    
    UI.mainFrame = MainFrame
    
    -- ESC to close
    table.insert(UISpecialFrames, "AutoChestOpenerFrame")
    
    -- Initial refresh
    C_Timer.After(0.2, function()
        UI:RefreshList()
    end)
    
    -- ========================================================================
    -- MINIMAP BUTTON
    -- ========================================================================
    
    local MinimapButton = CreateFrame("Button", "AutoChestOpenerMinimapButton", Minimap)
    MinimapButton:SetSize(32, 32)
    MinimapButton:SetFrameStrata("MEDIUM")
    MinimapButton:SetFrameLevel(8)
    MinimapButton:EnableMouse(true)
    MinimapButton:SetMovable(true)
    MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    MinimapButton:RegisterForDrag("LeftButton")
    MinimapButton:SetClampedToScreen(true)
    
    -- Position
    local angle = 220
    local radius = 80
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER", 
        radius * cos(angle), radius * sin(angle))
    
    -- Background (cercle noir semi-transparent)
    local background = MinimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetSize(27, 27)
    background:SetPoint("CENTER", 0, 0)
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetVertexColor(0, 0, 0, 0.6)
    
    -- Icône principale (coffre)
    local icon = MinimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture(132594) -- Interface\Icons\INV_Box_02 (coffre)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    
    -- Bordure style minimap (avec offset correct TOPLEFT)
    local border = MinimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder
    
    -- Highlight au survol
    local highlight = MinimapButton:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetSize(24, 24)
    highlight:SetPoint("CENTER", 0, 0)
    highlight:SetTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
    highlight:SetBlendMode("ADD")
    
    -- Dragging
    MinimapButton:SetScript("OnDragStart", function(self)
        self.isDragging = true
    end)
    
    MinimapButton:SetScript("OnDragStop", function(self)
        self.isDragging = false
    end)
    
    MinimapButton:SetScript("OnUpdate", function(self)
        if self.isDragging then
            local mx, my = Minimap:GetCenter()
            local cx, cy = GetCursorPosition()
            local scale = Minimap:GetEffectiveScale()
            cx, cy = cx / scale, cy / scale
            
            local angle = math.atan2(cy - my, cx - mx)
            local x = cos(math.deg(angle)) * radius
            local y = sin(math.deg(angle)) * radius
            
            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", x, y)
        end
    end)
    
    MinimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            UI:Toggle()
        elseif button == "RightButton" then
            ACO.db.enabled = not ACO.db.enabled
            ACO:Print(ACO.db.enabled and "Activé" or "Désactivé")
            EnableCheck.checkbox:SetChecked(ACO.db.enabled)
        end
    end)
    
    MinimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ccffAuto Chest Opener|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffffffClic gauche:|r Ouvrir les options", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffffClic droit:|r Activer/Désactiver", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        local status = ACO.db.enabled and "|cff00ff00Activé|r" or "|cffff0000Désactivé|r"
        GameTooltip:AddLine("Statut: " .. status)
        GameTooltip:Show()
    end)
    
    MinimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)
    
    UI.minimapButton = MinimapButton
end

-- Register to add containers via item links in chat
hooksecurefunc("SetItemRef", function(link, text, button)
    if IsAltKeyDown() and button == "LeftButton" then
        local itemID = tonumber(link:match("item:(%d+)"))
        if itemID then
            ACO:AddContainer(itemID)
        end
    end
end)
