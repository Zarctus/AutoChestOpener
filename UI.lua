--[[
    Auto Chest Opener - UI Module
    Midnight-style interface (palette unifiée Zayu / Zarctus)
    Version: 2.1.0
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
local GetTime = GetTime

ACO.UI = {}
local UI = ACO.UI

-- ============================================================================
-- UI CONSTANTS
-- ============================================================================

local FRAME_WIDTH = 560
local FRAME_HEIGHT = 600
local FRAME_MIN_WIDTH = 420
local FRAME_MIN_HEIGHT = 500
local FRAME_MAX_WIDTH = 750
local FRAME_MAX_HEIGHT = 950
local HEADER_HEIGHT = 36
local TAB_HEIGHT = 30
local BUTTON_HEIGHT = 28
local LIST_ITEM_HEIGHT = 38
local PADDING = 12

-- ============================================================================
-- BACKDROP TEMPLATE (Midnight unified)
-- ============================================================================

local BD = {
    bgFile   = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets   = { left = 1, right = 1, top = 1, bottom = 1 },
}

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

local function ApplyBackdrop(frame, bg, bdr)
    if not frame.SetBackdrop then return end
    frame:SetBackdrop(BD)
    frame:SetBackdropColor(bg.r, bg.g, bg.b, bg.a or 1)
    if bdr then
        frame:SetBackdropBorderColor(bdr.r, bdr.g, bdr.b, bdr.a or 1)
    end
end

local function MakeText(parent, txt, size, color, justify)
    local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    local f, _, fl = GameFontNormal:GetFont()
    fs:SetFont(f, size or 12, fl or "")
    fs:SetText(txt or "")
    if color then fs:SetTextColor(color.r, color.g, color.b, color.a or 1) end
    if justify then fs:SetJustifyH(justify) end
    return fs
end

-- ============================================================================
-- MODERN BUTTON CREATION (Flat Midnight style)
-- ============================================================================

local function CreateModernButton(parent, text, width, height, isPrimary)
    local C = ACO.colors
    local button = CreateFrame("Button", nil, parent, "BackdropTemplate")
    button:SetSize(width or 120, height or BUTTON_HEIGHT)

    local bgColor, bdrColor
    if isPrimary then
        bgColor = { r = C.accent.r * 0.25, g = C.accent.g * 0.25, b = C.accent.b * 0.25, a = 0.9 }
        bdrColor = C.accent
    else
        bgColor = C.row
        bdrColor = C.border
    end

    ApplyBackdrop(button, bgColor, bdrColor)

    local fs = MakeText(button, text, 11, C.text)
    fs:SetPoint("CENTER")
    button.text = fs

    button:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
        fs:SetTextColor(1, 1, 1)
    end)

    button:SetScript("OnLeave", function(self)
        self:SetBackdropColor(bgColor.r, bgColor.g, bgColor.b, bgColor.a or 1)
        self:SetBackdropBorderColor(bdrColor.r, bdrColor.g, bdrColor.b, bdrColor.a or 1)
        fs:SetTextColor(C.text.r, C.text.g, C.text.b)
    end)

    button:SetScript("OnMouseDown", function(self)
        self:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 1)
    end)

    button:SetScript("OnMouseUp", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
    end)

    return button
end

-- ============================================================================
-- MODERN CHECKBOX CREATION (Midnight style)
-- ============================================================================

local function CreateModernCheckbox(parent, label, tooltip)
    local C = ACO.colors
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(200, 24)

    local checkbox = CreateFrame("CheckButton", nil, frame, "BackdropTemplate")
    checkbox:SetSize(18, 18)
    checkbox:SetPoint("LEFT")
    ApplyBackdrop(checkbox, C.row, C.border)

    local check = checkbox:CreateTexture(nil, "OVERLAY")
    check:SetSize(12, 12)
    check:SetPoint("CENTER")
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:SetVertexColor(C.accent.r, C.accent.g, C.accent.b)
    check:Hide()
    checkbox.check = check

    local originalSetChecked = checkbox.SetChecked
    checkbox.SetChecked = function(self, checked)
        originalSetChecked(self, checked)
        if checked then check:Show() else check:Hide() end
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
        if self.callback then self.callback(isChecked) end
    end)

    checkbox:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
        if tooltip then
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end
    end)

    checkbox:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        GameTooltip:Hide()
    end)

    local text = MakeText(frame, label, 11, C.text)
    text:SetPoint("LEFT", checkbox, "RIGHT", 8, 0)

    frame.checkbox = checkbox
    frame.label = text

    return frame
end

-- ============================================================================
-- MODERN SLIDER CREATION (Midnight style)
-- ============================================================================

local function CreateModernSlider(parent, label, minVal, maxVal, step, tooltip)
    local C = ACO.colors
    local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
    frame:SetSize(300, 50)

    local text = MakeText(frame, label, 11, C.text)
    text:SetPoint("TOPLEFT", 0, 0)

    local valueText = MakeText(frame, "", 11, C.accent)
    valueText:SetPoint("TOPRIGHT", 0, 0)

    local track = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    track:SetSize(280, 8)
    track:SetPoint("TOP", 0, -22)
    ApplyBackdrop(track, C.bg, C.border)

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", 2, 0)
    fill:SetHeight(4)
    fill:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)

    local thumb = CreateFrame("Button", nil, track, "BackdropTemplate")
    thumb:SetSize(14, 14)
    ApplyBackdrop(thumb, C.accent, C.borderLight)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local function UpdateSlider(value)
        value = max(minVal, min(maxVal, value))
        if step then
            value = floor(value / step + 0.5) * step
        end

        local percent = (value - minVal) / (maxVal - minVal)
        local trackWidth = track:GetWidth() - thumb:GetWidth()

        thumb:SetPoint("LEFT", track, "LEFT", percent * trackWidth, 0)
        fill:SetWidth(max(1, percent * trackWidth))

        if value == floor(value) then
            valueText:SetText(format("%d", value) .. "s")
        else
            valueText:SetText(format("%.1f", value) .. "s")
        end

        frame.value = value
        if frame.callback then frame.callback(value) end
    end

    thumb:SetScript("OnDragStart", function(self) self.isDragging = true end)
    thumb:SetScript("OnDragStop", function(self) self.isDragging = false end)

    track:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            local x = select(1, GetCursorPosition()) / self:GetEffectiveScale()
            local left = self:GetLeft()
            local width = self:GetWidth() - thumb:GetWidth()
            local percent = max(0, min(1, (x - left - thumb:GetWidth()/2) / width))
            UpdateSlider(minVal + percent * (maxVal - minVal))
        end
    end)

    track:SetScript("OnUpdate", function(self)
        if thumb.isDragging then
            local x = select(1, GetCursorPosition()) / self:GetEffectiveScale()
            local left = self:GetLeft()
            local width = self:GetWidth() - thumb:GetWidth()
            local percent = max(0, min(1, (x - left - thumb:GetWidth()/2) / width))
            UpdateSlider(minVal + percent * (maxVal - minVal))
        end
    end)

    frame.UpdateSlider = UpdateSlider
    frame.valueText = valueText

    frame:SetScript("OnShow", function()
        C_Timer.After(0.05, function()
            if frame.pendingValue then
                UpdateSlider(frame.pendingValue)
                frame.pendingValue = nil
            end
        end)
    end)

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
    local C = self.colors

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
    MainFrame:SetFrameLevel(100)
    MainFrame:SetResizable(true)
    MainFrame:SetResizeBounds(FRAME_MIN_WIDTH, FRAME_MIN_HEIGHT, FRAME_MAX_WIDTH, FRAME_MAX_HEIGHT)
    MainFrame:Hide()

    ApplyBackdrop(MainFrame, C.bg, C.border)

    -- ========================================================================
    -- RESIZE HANDLE
    -- ========================================================================

    local ResizeHandle = CreateFrame("Button", nil, MainFrame)
    ResizeHandle:SetSize(16, 16)
    ResizeHandle:SetPoint("BOTTOMRIGHT", -2, 2)
    ResizeHandle:SetFrameLevel(MainFrame:GetFrameLevel() + 10)
    ResizeHandle:EnableMouse(true)

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

    -- ========================================================================
    -- HEADER (Midnight style with accent line)
    -- ========================================================================

    local Header = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
    Header:SetHeight(HEADER_HEIGHT)
    Header:SetPoint("TOPLEFT", 1, -1)
    Header:SetPoint("TOPRIGHT", -1, -1)
    ApplyBackdrop(Header, C.header, C.border)

    -- Accent line under header (2px cyan)
    local accentLine = Header:CreateTexture(nil, "OVERLAY")
    accentLine:SetHeight(2)
    accentLine:SetPoint("BOTTOMLEFT", Header, "BOTTOMLEFT", 0, 0)
    accentLine:SetPoint("BOTTOMRIGHT", Header, "BOTTOMRIGHT", 0, 0)
    accentLine:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.85)

    -- Icon
    local Icon = Header:CreateTexture(nil, "ARTWORK")
    Icon:SetSize(28, 28)
    Icon:SetPoint("LEFT", PADDING, 0)
    Icon:SetAtlas("VignetteLootChest")

    -- Title (styled like MidnightWeekly: first word cyan, rest text color)
    local Title = MakeText(Header, nil, 14, nil)
    Title:SetPoint("LEFT", Icon, "RIGHT", 10, 0)
    Title:SetText("|cff00ccffAuto|r|cff" .. format("%02x%02x%02x",
        floor(C.text.r*255), floor(C.text.g*255), floor(C.text.b*255))
        .. "ChestOpener|r")

    -- Version
    local Version = MakeText(Header, "v" .. ACO.version, 10, C.textDim)
    Version:SetPoint("LEFT", Title, "RIGHT", 8, 0)

    -- Close button (common-search-clearbutton like MidnightWeekly)
    local CloseBtn = CreateFrame("Button", nil, Header)
    CloseBtn:SetSize(20, 20)
    CloseBtn:SetPoint("RIGHT", -PADDING, 0)

    local closeTex = CloseBtn:CreateTexture(nil, "ARTWORK")
    closeTex:SetAllPoints()
    closeTex:SetAtlas("common-search-clearbutton", true)
    closeTex:SetVertexColor(C.textDim.r, C.textDim.g, C.textDim.b)

    CloseBtn:SetScript("OnEnter", function()
        closeTex:SetVertexColor(C.red.r, C.red.g, C.red.b)
    end)
    CloseBtn:SetScript("OnLeave", function()
        closeTex:SetVertexColor(C.textDim.r, C.textDim.g, C.textDim.b)
    end)
    CloseBtn:SetScript("OnClick", function()
        MainFrame:Hide()
        PlaySound(SOUNDKIT.IG_MAINMENU_CLOSE)
    end)

    -- ========================================================================
    -- TAB SYSTEM (Midnight style with underline indicator)
    -- ========================================================================

    local TabContainer = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
    TabContainer:SetHeight(TAB_HEIGHT + 2)
    TabContainer:SetPoint("TOPLEFT", Header, "BOTTOMLEFT", 1, 0)
    TabContainer:SetPoint("TOPRIGHT", Header, "BOTTOMRIGHT", -1, 0)
    ApplyBackdrop(TabContainer, C.bg, C.border)

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

    local PendingContent = CreateFrame("Frame", nil, MainFrame)
    PendingContent:SetPoint("TOPLEFT", TabContainer, "BOTTOMLEFT", 0, 0)
    PendingContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    PendingContent:Hide()

    local LootContent = CreateFrame("Frame", nil, MainFrame)
    LootContent:SetPoint("TOPLEFT", TabContainer, "BOTTOMLEFT", 0, 0)
    LootContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    LootContent:Hide()

    UI.tabs = {}
    UI.currentTab = "containers"

    local function CreateTab(parent, text, icon, tabKey, xOffset)
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
        tab:SetSize(105, TAB_HEIGHT)
        tab:SetPoint("LEFT", xOffset, 0)
        ApplyBackdrop(tab, C.bg, { r = 0, g = 0, b = 0, a = 0 })

        local tabIcon = tab:CreateTexture(nil, "ARTWORK")
        tabIcon:SetSize(14, 14)
        tabIcon:SetPoint("LEFT", 10, 0)
        tabIcon:SetAtlas(icon)

        local tabText = MakeText(tab, text, 11, C.textDim)
        tabText:SetPoint("LEFT", tabIcon, "RIGHT", 6, 0)

        -- Active indicator (2px accent bar at bottom, like Zarctus_Gold)
        local indicator = tab:CreateTexture(nil, "OVERLAY")
        indicator:SetHeight(2)
        indicator:SetPoint("BOTTOMLEFT", tab, "BOTTOMLEFT", 2, 0)
        indicator:SetPoint("BOTTOMRIGHT", tab, "BOTTOMRIGHT", -2, 0)
        indicator:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)
        indicator:Hide()
        tab.indicator = indicator

        tab.isActive = false
        tab.tabKey = tabKey

        local function UpdateTabAppearance()
            if tab.isActive then
                tab:SetBackdropColor(C.header.r, C.header.g, C.header.b, 1)
                tab:SetBackdropBorderColor(0, 0, 0, 0)
                tabText:SetTextColor(C.text.r, C.text.g, C.text.b)
                tabIcon:SetVertexColor(1, 1, 1)
                indicator:Show()
            else
                tab:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, C.bg.a)
                tab:SetBackdropBorderColor(0, 0, 0, 0)
                tabText:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
                tabIcon:SetVertexColor(C.textDim.r, C.textDim.g, C.textDim.b)
                indicator:Hide()
            end
        end

        tab:SetScript("OnEnter", function(self)
            if not self.isActive then
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
                tabText:SetTextColor(C.text.r, C.text.g, C.text.b)
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

    local containersTab = CreateTab(TabContainer, ACO:Translate("TAB_CONTAINERS"), "BonusLoot-Chest", "containers", PADDING)
    local statsTab = CreateTab(TabContainer, ACO:Translate("TAB_STATS"), "communities-icon-notification", "stats", PADDING + 108)
    local historyTab = CreateTab(TabContainer, ACO:Translate("TAB_HISTORY"), "lorewalking-map-icon", "history", PADDING + 216)
    local pendingTab = CreateTab(TabContainer, ACO:Translate("TAB_PENDING"), "QuestNormal", "pending", PADDING + 324)
    local lootTab = CreateTab(TabContainer, ACO:Translate("TAB_LOOT"), "Auctioneer", "loot", PADDING + 432)

    function UI:SwitchTab(tabKey)
        self.currentTab = tabKey

        ContainersContent:Hide()
        StatsContent:Hide()
        HistoryContent:Hide()
        PendingContent:Hide()
        LootContent:Hide()

        for _, tab in pairs(self.tabs) do
            tab.isActive = false
            tab:UpdateAppearance()
        end

        self.tabs[tabKey].isActive = true
        self.tabs[tabKey]:UpdateAppearance()

        if tabKey == "containers" then
            ContainersContent:Show()
            self:RefreshList()
        elseif tabKey == "stats" then
            StatsContent:Show()
            self:RefreshStats()
        elseif tabKey == "history" then
            HistoryContent:Show()
            self:RefreshHistory()
        elseif tabKey == "pending" then
            PendingContent:Show()
            self:RefreshPendingList()
        elseif tabKey == "loot" then
            LootContent:Show()
            self:RefreshLootSummary()
        end
    end

    -- Initialize first tab as active
    containersTab.isActive = true
    containersTab:UpdateAppearance()

    -- ========================================================================
    -- OPTIONS SECTION (inside ContainersContent)
    -- ========================================================================

    local OptionsSection = CreateFrame("Frame", nil, ContainersContent, "BackdropTemplate")
    OptionsSection:SetHeight(170)
    OptionsSection:SetPoint("TOPLEFT", PADDING, -PADDING)
    OptionsSection:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    ApplyBackdrop(OptionsSection, C.row, C.border)

    local OptionsIcon = OptionsSection:CreateTexture(nil, "ARTWORK")
    OptionsIcon:SetSize(16, 16)
    OptionsIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    OptionsIcon:SetAtlas("options")

    local OptionsTitle = MakeText(OptionsSection, ACO:Translate("OPTIONS_TITLE"), 12, C.accent)
    OptionsTitle:SetPoint("LEFT", OptionsIcon, "RIGHT", 6, 0)

    -- Enable checkbox
    local EnableCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("ENABLE_AUTO_OPEN"), ACO:Translate("ENABLE_TOOLTIP"))
    EnableCheck:SetPoint("TOPLEFT", OptionsTitle, "BOTTOMLEFT", 0, -12)
    EnableCheck.checkbox:SetChecked(ACO.db.enabled)
    EnableCheck.checkbox.callback = function(checked)
        ACO.db.enabled = checked
    end

    -- Notifications checkbox
    local NotifyCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("SHOW_NOTIFICATIONS"), ACO:Translate("SHOW_NOTIFICATIONS_TOOLTIP"))
    NotifyCheck:SetPoint("TOPLEFT", EnableCheck, "BOTTOMLEFT", 0, -8)
    NotifyCheck.checkbox:SetChecked(ACO.db.showNotifications)
    NotifyCheck.checkbox.callback = function(checked)
        ACO.db.showNotifications = checked
    end

    -- Sound checkbox
    local SoundCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("PLAY_SOUNDS"), ACO:Translate("PLAY_SOUNDS_TOOLTIP"))
    SoundCheck:SetPoint("LEFT", NotifyCheck, "RIGHT", 80, 0)
    SoundCheck.checkbox:SetChecked(ACO.db.notificationSound)
    SoundCheck.checkbox.callback = function(checked)
        ACO.db.notificationSound = checked
    end

    -- Auto-discovery checkbox
    local AutoDiscoverCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("ENABLE_AUTO_DISCOVER"), ACO:Translate("ENABLE_AUTO_DISCOVER_TOOLTIP"))
    AutoDiscoverCheck:SetPoint("TOPLEFT", NotifyCheck, "BOTTOMLEFT", 0, -8)
    AutoDiscoverCheck.checkbox:SetChecked(ACO.db.autoDiscovery ~= false)
    AutoDiscoverCheck.checkbox.callback = function(checked)
        ACO.db.autoDiscovery = checked
    end

    -- Delay slider
    local DelaySlider = CreateModernSlider(OptionsSection, ACO:Translate("DELAY_SLIDER_LABEL"), 0, 10, 0.5, ACO:Translate("DELAY_TOOLTIP"))
    DelaySlider:SetPoint("TOPLEFT", AutoDiscoverCheck, "BOTTOMLEFT", 0, -12)
    DelaySlider.callback = function(value)
        ACO.db.delay = value
    end

    MainFrame:HookScript("OnShow", function()
        C_Timer.After(0.1, function()
            if DelaySlider.SetValue then
                DelaySlider:SetValue(ACO.db.delay)
            elseif DelaySlider.UpdateSlider then
                DelaySlider.UpdateSlider(ACO.db.delay)
            end
        end)
    end)

    C_Timer.After(0.5, function()
        if DelaySlider.valueText then
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
    ApplyBackdrop(AddSection, C.row, C.border)

    local AddIcon = AddSection:CreateTexture(nil, "ARTWORK")
    AddIcon:SetSize(16, 16)
    AddIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    AddIcon:SetAtlas("communities-icon-addgroupplus")

    local AddTitle = MakeText(AddSection, ACO:Translate("ADD_TITLE"), 12, C.green)
    AddTitle:SetPoint("LEFT", AddIcon, "RIGHT", 6, 0)

    -- Drop zone
    local DropZone = CreateFrame("Button", nil, AddSection, "BackdropTemplate")
    DropZone:SetSize(200, 40)
    DropZone:SetPoint("LEFT", PADDING, -8)
    ApplyBackdrop(DropZone, C.bg, C.border)

    local DropText = MakeText(DropZone, ACO:Translate("DROPZONE_EMPTY"), 11, C.textDim)
    DropText:SetPoint("CENTER")
    DropZone.text = DropText

    DropZone:SetScript("OnReceiveDrag", function(self)
        local infoType, itemID, itemLink = GetCursorInfo()
        if infoType == "item" then
            ClearCursor()
            if itemID then
                ACO:AddContainer(itemID)
                DropText:SetText(ACO:Translate("DROPZONE_ADDED"))
                C_Timer.After(1.5, function()
                    DropText:SetText(ACO:Translate("DROPZONE_EMPTY"))
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
                DropText:SetText(ACO:Translate("DROPZONE_ADDED"))
                C_Timer.After(1.5, function()
                    DropText:SetText(ACO:Translate("DROPZONE_EMPTY"))
                end)
            end
        end
    end)

    DropZone:SetScript("OnEnter", function(self)
        self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("DROPZONE_TOOLTIP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)

    DropZone:SetScript("OnLeave", function(self)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        GameTooltip:Hide()
    end)

    -- ID Input
    local IDInput = CreateFrame("EditBox", nil, AddSection, "BackdropTemplate")
    IDInput:SetSize(100, 40)
    IDInput:SetPoint("LEFT", DropZone, "RIGHT", 10, 0)
    ApplyBackdrop(IDInput, C.bg, C.border)
    IDInput:SetFontObject("GameFontHighlight")
    IDInput:SetTextInsets(10, 10, 0, 0)
    IDInput:SetAutoFocus(false)
    IDInput:SetNumeric(true)
    IDInput:SetMaxLetters(10)

    local IDPlaceholder = MakeText(IDInput, ACO:Translate("ID_PLACEHOLDER"), 11, C.textDim)
    IDPlaceholder:SetPoint("CENTER")

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
    local AddBtn = CreateModernButton(AddSection, ACO:Translate("ADD_BTN"), 80, 40, true)
    AddBtn:SetPoint("LEFT", IDInput, "RIGHT", 10, 0)
    AddBtn:SetScript("OnClick", function()
        local id = tonumber(IDInput:GetText())
        if id then
            ACO:AddContainer(id)
            IDInput:SetText("")
        else
            ACO:Print(ACO:Translate("INVALID_ID"), true)
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
    ApplyBackdrop(ListSection, C.row, C.border)

    local ListIcon = ListSection:CreateTexture(nil, "ARTWORK")
    ListIcon:SetSize(16, 16)
    ListIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    ListIcon:SetAtlas("VignetteLootChest")

    local ListTitle = MakeText(ListSection, ACO:Translate("LIST_TITLE"), 12, C.gold)
    ListTitle:SetPoint("LEFT", ListIcon, "RIGHT", -15, 0)

    -- Count
    local ListCount = MakeText(ListSection, "", 10, C.textDim)
    ListCount:SetPoint("TOPRIGHT", -PADDING - 100, -PADDING)
    UI.listCount = ListCount

    -- Open All Button
    local OpenAllBtn = CreateModernButton(ListSection, ACO:Translate("OPEN_ALL"), 90, 24, true)
    OpenAllBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING + 4)
    OpenAllBtn:SetScript("OnClick", function()
        local count = ACO:OpenAllContainers()
        if count > 0 then
            ACO:Print(ACO:Translate("OPEN_ALL_RESULT", count))
        end
    end)
    OpenAllBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ACO:Translate("OPEN_ALL_T1"))
        GameTooltip:AddLine(ACO:Translate("OPEN_ALL_T2"), 0.8, 0.8, 0.8)
        if ACO:Translate("OPEN_ALL_T3") ~= "" then
            GameTooltip:AddLine(ACO:Translate("OPEN_ALL_T3"), 0.8, 0.8, 0.8)
        end
        GameTooltip:Show()
    end)
    OpenAllBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.accent.r * 0.25, C.accent.g * 0.25, C.accent.b * 0.25, 0.9)
        self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
        self.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        GameTooltip:Hide()
    end)

    -- Import Button
    local ImportBtn = CreateModernButton(ListSection, ACO:Translate("IMPORT_BTN"), 60, 24, false)
    ImportBtn:SetPoint("RIGHT", OpenAllBtn, "LEFT", -8, 0)
    ImportBtn:SetScript("OnClick", function()
        ACO:ShowImportFrame()
    end)
    ImportBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ACO:Translate("IMPORT_T1"))
        GameTooltip:AddLine(ACO:Translate("IMPORT_T2"), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ImportBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        self.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        GameTooltip:Hide()
    end)

    -- Export Button
    local ExportBtn = CreateModernButton(ListSection, ACO:Translate("EXPORT_BTN"), 60, 24, false)
    ExportBtn:SetPoint("RIGHT", ImportBtn, "LEFT", -8, 0)
    ExportBtn:SetScript("OnClick", function()
        ACO:ShowExportFrame()
    end)
    ExportBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ACO:Translate("EXPORT_T1"))
        GameTooltip:AddLine(ACO:Translate("EXPORT_T2"), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ExportBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        self.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        GameTooltip:Hide()
    end)

    -- Remove All Button
    local RemoveAllBtn = CreateModernButton(ListSection, ACO:Translate("REMOVE_ALL_BTN"), 80, 24, false)
    RemoveAllBtn:SetPoint("RIGHT", ExportBtn, "LEFT", -8, 0)
    RemoveAllBtn:SetScript("OnClick", function()
        StaticPopup_Show("ACO_REMOVE_ALL_CONTAINERS")
    end)
    RemoveAllBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.red.r * 0.3, C.red.g * 0.3, C.red.b * 0.3, 1)
        self:SetBackdropBorderColor(C.red.r, C.red.g, C.red.b, 1)
        self.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:AddLine(ACO:Translate("REMOVE_ALL_T1"), 1, 0.3, 0.3)
        GameTooltip:AddLine(ACO:Translate("REMOVE_ALL_T2"), 0.8, 0.8, 0.8)
        GameTooltip:AddLine(ACO:Translate("REMOVE_ALL_T3"), 1, 0.5, 0)
        GameTooltip:Show()
    end)
    RemoveAllBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        self.text:SetTextColor(C.text.r, C.text.g, C.text.b)
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
        item:SetPoint("TOPLEFT", 0, -(index - 1) * (LIST_ITEM_HEIGHT + 3))

        local isAlt = (index % 2 == 0)
        local rowBg = isAlt and C.rowAlt or C.row
        ApplyBackdrop(item, rowBg, C.border)
        item._isAlt = isAlt

        -- Item icon
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Item name
        local name = MakeText(item, nil, 11, C.text, "LEFT")
        name:SetPoint("LEFT", icon, "RIGHT", 10, 6)
        name:SetWidth(260)

        -- Item ID
        local idText = MakeText(item, format(ACO:Translate("ID_LABEL"), itemID), 9, C.textDim)
        idText:SetPoint("LEFT", icon, "RIGHT", 10, -8)

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, item, "BackdropTemplate")
        removeBtn:SetSize(22, 22)
        removeBtn:SetPoint("RIGHT", -8, 0)
        ApplyBackdrop(removeBtn, { r = C.red.r * 0.2, g = C.red.g * 0.2, b = C.red.b * 0.2, a = 0.8 }, C.border)

        local removeIcon = removeBtn:CreateTexture(nil, "OVERLAY")
        removeIcon:SetSize(12, 12)
        removeIcon:SetPoint("CENTER")
        removeIcon:SetAtlas("common-icon-redx")

        removeBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.red.r * 0.4, C.red.g * 0.4, C.red.b * 0.4, 1)
            self:SetBackdropBorderColor(C.red.r, C.red.g, C.red.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ACO:Translate("REMOVE_TOOLTIP"))
            GameTooltip:Show()
        end)

        removeBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(C.red.r * 0.2, C.red.g * 0.2, C.red.b * 0.2, 0.8)
            self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
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
            name:SetText(ACO:Translate("LOADING"))
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")

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

        -- Hover effects (Midnight style: rowHover + borderLight)
        item:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink("item:" .. itemID)
            GameTooltip:Show()
        end)

        item:SetScript("OnLeave", function(self)
            local bg = self._isAlt and C.rowAlt or C.row
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            GameTooltip:Hide()
        end)

        return item
    end

    -- ========================================================================
    -- REFRESH LIST FUNCTION
    -- ========================================================================

    function UI:RefreshList()
        for _, item in ipairs(self.listItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self.listItems)

        local index = 1
        for itemID in pairs(ACO.db.containers) do
            local listItem = CreateListItem(itemID, index)
            table.insert(self.listItems, listItem)
            index = index + 1
        end

        ScrollChild:SetHeight(max(1, (index - 1) * (LIST_ITEM_HEIGHT + 3)))

        local count = index - 1
        local suffix = (count > 1) and "s" or ""
        self.listCount:SetText(ACO:Translate("LIST_COUNT", count, suffix))
    end

    -- ========================================================================
    -- PENDING TAB CONTENT
    -- ========================================================================

    local PendingSection = CreateFrame("Frame", nil, PendingContent, "BackdropTemplate")
    PendingSection:SetPoint("TOPLEFT", PADDING, -PADDING)
    PendingSection:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    PendingSection:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    ApplyBackdrop(PendingSection, C.row, C.border)

    local PendingTitle = MakeText(PendingSection, ACO:Translate("PENDING_TITLE"), 14, C.text)
    PendingTitle:SetPoint("TOPLEFT", PADDING, -PADDING)

    local PendingHint = MakeText(PendingSection, ACO:Translate("PENDING_HINT"), 10, C.textDim)
    PendingHint:SetPoint("TOPLEFT", PendingTitle, "BOTTOMLEFT", 0, -4)

    local PendingScroll = CreateFrame("ScrollFrame", nil, PendingSection, "UIPanelScrollFrameTemplate")
    PendingScroll:SetPoint("TOPLEFT", PADDING, -55)
    PendingScroll:SetPoint("BOTTOMRIGHT", -PADDING - 20, PADDING)

    local PendingScrollChild = CreateFrame("Frame", nil, PendingScroll)
    PendingScrollChild:SetSize(PendingScroll:GetWidth(), 1)
    PendingScroll:SetScrollChild(PendingScrollChild)

    UI.pendingListItems = {}

    local function CreatePendingItem(entry, index)
        local item = CreateFrame("Button", nil, PendingScrollChild, "BackdropTemplate")
        item:EnableMouse(true)
        if item.RegisterForClicks then
            item:RegisterForClicks("RightButtonUp")
        end
        item:SetSize(PendingScroll:GetWidth() - 10, LIST_ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -(index - 1) * (LIST_ITEM_HEIGHT + 3))

        local isAlt = (index % 2 == 0)
        local rowBg = isAlt and C.rowAlt or C.row
        ApplyBackdrop(item, rowBg, C.border)
        item._isAlt = isAlt

        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local name = MakeText(item, nil, 11, C.text, "LEFT")
        name:SetPoint("LEFT", icon, "RIGHT", 10, 0)
        name:SetWidth(320)

        local countText = MakeText(item, nil, 10, C.textDim)
        countText:SetPoint("RIGHT", -10, 0)

        local link = entry.link or ACO:FormatItemLink(entry.itemID)
        item._acoLink = link
        local itemName = link:match("%[(.-)%]") or ("Item:" .. tostring(entry.itemID))
        name:SetText(itemName)
        countText:SetText("x" .. tostring(entry.count or 1))

        local texture = C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.itemID)
        if texture then icon:SetTexture(texture) end

        item:SetScript("OnClick", function(self, button)
            if button ~= "RightButton" then
                return
            end
            local ok, reason = ACO:UseContainerFromBagSlot(entry.itemID, entry.bag, entry.slot, entry.link)
            if not ok then
                local link2 = entry.link or ACO:FormatItemLink(entry.itemID)
                ACO:Print(ACO:Translate("CANNOT_OPEN_AUTO") .. " " .. tostring(link2) .. (reason and (" ("..tostring(reason)..")") or ""))
            end
            C_Timer.After(0.15, function()
                if UI and UI.RefreshPendingList then
                    UI:RefreshPendingList()
                end
            end)
        end)

        item:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink(self._acoLink)
            GameTooltip:Show()
        end)
        item:SetScript("OnLeave", function(self)
            local bg = self._isAlt and C.rowAlt or C.row
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            GameTooltip:Hide()
        end)

        return item
    end

    function UI:RefreshPendingList()
        if not PendingContent or not PendingContent:IsShown() then return end
        if self.pendingListItems then
            for _, item in ipairs(self.pendingListItems) do
                item:Hide()
                item:SetParent(nil)
            end
            wipe(self.pendingListItems)
        else
            self.pendingListItems = {}
        end

        local pending = ACO:GetPendingContainersInBags()
        local index = 1
        for _, e in ipairs(pending) do
            local listItem = CreatePendingItem(e, index)
            table.insert(self.pendingListItems, listItem)
            index = index + 1
        end

        PendingScrollChild:SetHeight(max(1, (index - 1) * (LIST_ITEM_HEIGHT + 3)))
    end

    -- ========================================================================
    -- STATISTICS TAB CONTENT
    -- ========================================================================

    local StatsPanel = CreateFrame("Frame", nil, StatsContent, "BackdropTemplate")
    StatsPanel:SetPoint("TOPLEFT", PADDING, -PADDING)
    StatsPanel:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    ApplyBackdrop(StatsPanel, C.row, C.border)

    local StatsIcon = StatsPanel:CreateTexture(nil, "ARTWORK")
    StatsIcon:SetSize(20, 20)
    StatsIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    StatsIcon:SetAtlas("poi-workorders")

    local StatsTitle = MakeText(StatsPanel, ACO:Translate("STATS_TITLE"), 14, C.accent)
    StatsTitle:SetPoint("LEFT", StatsIcon, "RIGHT", 8, 0)

    -- Clear Stats Button
    local ClearStatsBtn = CreateModernButton(StatsPanel, ACO:Translate("CLEAR_STATS_BTN"), 100, 24, false)
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

        local labelText = MakeText(line, label, 11, C.text)
        labelText:SetPoint("LEFT", 0, 0)

        local valueText = MakeText(line, "", 11, C.gold)
        valueText:SetPoint("RIGHT", 0, 0)

        line.value = valueText
        return line
    end

    local statLines = {}
    statLines.total = CreateStatLine(StatsPanel, ACO:Translate("STATS_TOTAL"), -50)
    statLines.session = CreateStatLine(StatsPanel, ACO:Translate("STATS_SESSION"), -78)
    statLines.unique = CreateStatLine(StatsPanel, ACO:Translate("STATS_UNIQUE"), -106)
    statLines.totalGold = CreateStatLine(StatsPanel, ACO:Translate("STATS_TOTALGOLD"), -134)
    statLines.sessionGold = CreateStatLine(StatsPanel, ACO:Translate("STATS_SESSIONGOLD"), -162)
    statLines.firstOpen = CreateStatLine(StatsPanel, ACO:Translate("STATS_FIRST"), -190)
    statLines.lastOpen = CreateStatLine(StatsPanel, ACO:Translate("STATS_LAST"), -218)

    -- Top items section
    local TopItemsTitle = MakeText(StatsPanel, ACO:Translate("TOP_ITEMS_TITLE"), 12, C.accent)
    TopItemsTitle:SetPoint("TOPLEFT", PADDING, -256)

    UI.topItemsFrames = {}
    for i = 1, 5 do
        local itemFrame = CreateFrame("Frame", nil, StatsPanel, "BackdropTemplate")
        itemFrame:SetHeight(36)
        itemFrame:SetPoint("TOPLEFT", PADDING, -276 - (i-1) * 40)
        itemFrame:SetPoint("TOPRIGHT", -PADDING, -276 - (i-1) * 40)

        local isAlt = (i % 2 == 0)
        ApplyBackdrop(itemFrame, isAlt and C.rowAlt or C.row, C.border)

        local rankText = MakeText(itemFrame, format("#%d", i), 14, C.gold)
        rankText:SetPoint("LEFT", 10, 0)

        local icon = itemFrame:CreateTexture(nil, "ARTWORK")
        icon:SetSize(24, 24)
        icon:SetPoint("LEFT", 45, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local nameText = MakeText(itemFrame, nil, 11, C.text, "LEFT")
        nameText:SetPoint("LEFT", icon, "RIGHT", 8, 0)
        nameText:SetWidth(200)

        local countText = MakeText(itemFrame, nil, 11, C.green)
        countText:SetPoint("RIGHT", -10, 0)

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

        self.statLines.total.value:SetText(format("|cff%02x%02x%02x%d|r",
            floor(C.green.r*255), floor(C.green.g*255), floor(C.green.b*255), stats.totalOpened))
        self.statLines.session.value:SetText(format("|cff%02x%02x%02x%d|r",
            floor(C.accent.r*255), floor(C.accent.g*255), floor(C.accent.b*255), stats.sessionOpened))
        self.statLines.unique.value:SetText(format("|cff%02x%02x%02x%d|r",
            floor(C.gold.r*255), floor(C.gold.g*255), floor(C.gold.b*255), stats.uniqueItems))
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
    ApplyBackdrop(HistoryPanel, C.row, C.border)

    local HistoryIcon = HistoryPanel:CreateTexture(nil, "ARTWORK")
    HistoryIcon:SetSize(20, 20)
    HistoryIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    HistoryIcon:SetAtlas("communities-icon-clock")

    local HistoryTitle = MakeText(HistoryPanel, ACO:Translate("HISTORY_TITLE"), 14, C.accent)
    HistoryTitle:SetPoint("LEFT", HistoryIcon, "RIGHT", 8, 0)

    -- Clear History Button
    local ClearHistoryBtn = CreateModernButton(HistoryPanel, ACO:Translate("CLEAR_HISTORY_BTN"), 80, 24, false)
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
        item:SetPoint("TOPLEFT", 0, -(index - 1) * 47)

        local isAlt = (index % 2 == 0)
        local rowBg = isAlt and C.rowAlt or C.row
        ApplyBackdrop(item, rowBg, C.border)
        item._isAlt = isAlt

        -- Time
        local timeText = MakeText(item, ACO:FormatRelativeTime(entry.timestamp), 10, C.textDim)
        timeText:SetPoint("TOPLEFT", 10, -6)

        -- Full date
        local dateText = MakeText(item, tostring(date("%d/%m/%Y %H:%M", entry.timestamp)), 9,
            { r = C.textDim.r * 0.7, g = C.textDim.g * 0.7, b = C.textDim.b * 0.7 })
        dateText:SetPoint("TOPLEFT", 10, -20)

        -- Icon
        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(26, 26)
        icon:SetPoint("LEFT", 100, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        if entry.itemIcon then
            icon:SetTexture(entry.itemIcon)
        else
            local itemIcon = C_Item.GetItemIconByID(entry.itemID)
            icon:SetTexture(itemIcon or "Interface\\Icons\\INV_Misc_QuestionMark")
        end

        -- Item name
        local nameText = MakeText(item, nil, 11, C.text, "LEFT")
        nameText:SetPoint("LEFT", icon, "RIGHT", 10, 6)
        nameText:SetWidth(200)

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

        -- Gold gained
        if entry.goldGained and entry.goldGained > 0 then
            local goldText = MakeText(item, ACO:FormatMoney(entry.goldGained), 10, C.gold)
            goldText:SetPoint("LEFT", icon, "RIGHT", 10, -8)
        end

        -- Hover (Midnight style)
        item:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink("item:" .. entry.itemID)
            if entry.goldGained and entry.goldGained > 0 then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(string.format(ACO:Translate("HISTORY_GOLD_LINE"), ACO:FormatMoneyShort(entry.goldGained)), 1, 0.84, 0)
            end
            GameTooltip:Show()
        end)

        item:SetScript("OnLeave", function(self)
            local bg = self._isAlt and C.rowAlt or C.row
            self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            GameTooltip:Hide()
        end)

        return item
    end

    function UI:RefreshHistory()
        for _, item in ipairs(self.historyItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self.historyItems)

        local history = ACO:GetHistory(50)

        if #history == 0 then
            if not self.historyEmptyText then
                self.historyEmptyText = MakeText(HistoryScrollChild, ACO:Translate("HISTORY_EMPTY"), 11, C.textDim)
                self.historyEmptyText:SetPoint("CENTER", 0, 50)
            end
            self.historyEmptyText:Show()
            HistoryScrollChild:SetHeight(100)
        else
            if self.historyEmptyText then
                self.historyEmptyText:Hide()
            end

            for i, entry in ipairs(history) do
                local historyItem = CreateHistoryItem(entry, i)
                tinsert(self.historyItems, historyItem)
            end

            HistoryScrollChild:SetHeight(max(1, #history * 47))
        end
    end

    -- ========================================================================
    -- LOOT SUMMARY TAB CONTENT
    -- ========================================================================

    local LootPanel = CreateFrame("Frame", nil, LootContent, "BackdropTemplate")
    LootPanel:SetPoint("TOPLEFT", PADDING, -PADDING)
    LootPanel:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    ApplyBackdrop(LootPanel, C.row, C.border)

    local LootIcon = LootPanel:CreateTexture(nil, "ARTWORK")
    LootIcon:SetSize(20, 20)
    LootIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    LootIcon:SetAtlas("auctionhouse")

    local LootTitle = MakeText(LootPanel, ACO:Translate("LOOT_TITLE"), 14, C.accent)
    LootTitle:SetPoint("LEFT", LootIcon, "RIGHT", 8, 0)

    local LootHint = MakeText(LootPanel, ACO:Translate("LOOT_HINT"), 10, C.textDim)
    LootHint:SetPoint("TOPLEFT", LootTitle, "BOTTOMLEFT", 0, -2)

    -- Clear Loot Button
    local ClearLootBtn = CreateModernButton(LootPanel, ACO:Translate("CLEAR_LOOT_BTN"), 100, 24, false)
    ClearLootBtn:SetPoint("TOPRIGHT", -PADDING, -PADDING)
    ClearLootBtn:SetScript("OnClick", function()
        StaticPopup_Show("ACO_CLEAR_LOOT")
    end)

    -- Export CSV button
    local ExportCSVBtn = CreateModernButton(LootPanel, ACO:Translate("EXPORT_CSV_BTN"), 80, 24, false)
    ExportCSVBtn:SetPoint("RIGHT", ClearLootBtn, "LEFT", -6, 0)
    ExportCSVBtn:SetScript("OnClick", function()
        local csv = ACO:ExportLootCSV()
        if csv == "" then
            ACO:Print(ACO:Translate("EXPORT_LOOT_EMPTY"))
            return
        end
        ACO:ShowLootExportFrame(csv, "EXPORT_LOOT_CSV_TITLE")
    end)

    -- Export JSON button
    local ExportJSONBtn = CreateModernButton(LootPanel, ACO:Translate("EXPORT_JSON_BTN"), 80, 24, false)
    ExportJSONBtn:SetPoint("RIGHT", ExportCSVBtn, "LEFT", -6, 0)
    ExportJSONBtn:SetScript("OnClick", function()
        local json = ACO:ExportLootJSON()
        if json == "[]" then
            ACO:Print(ACO:Translate("EXPORT_LOOT_EMPTY"))
            return
        end
        ACO:ShowLootExportFrame(json, "EXPORT_LOOT_JSON_TITLE")
    end)

    -- Loot scroll frame
    local LootScrollFrame = CreateFrame("ScrollFrame", nil, LootPanel, "UIPanelScrollFrameTemplate")
    LootScrollFrame:SetPoint("TOPLEFT", PADDING, -60)
    LootScrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 20, PADDING)

    local LootScrollChild = CreateFrame("Frame", nil, LootScrollFrame)
    LootScrollChild:SetSize(LootScrollFrame:GetWidth(), 1)
    LootScrollFrame:SetScrollChild(LootScrollChild)

    UI.lootItems = {}
    UI.lootExpandedContainers = {}

    function UI:RefreshLootSummary()
        for _, item in ipairs(self.lootItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self.lootItems)

        local lootData = ACO:GetLootSummary()

        if #lootData == 0 then
            if not self.lootEmptyText then
                self.lootEmptyText = MakeText(LootScrollChild, ACO:Translate("LOOT_EMPTY"), 11, C.textDim)
                self.lootEmptyText:SetPoint("CENTER", 0, 50)
            end
            self.lootEmptyText:Show()
            LootScrollChild:SetHeight(100)
            return
        end

        if self.lootEmptyText then
            self.lootEmptyText:Hide()
        end

        local scrollWidth = LootScrollFrame:GetWidth() - 10
        local yOffset = 0

        for _, containerData in ipairs(lootData) do
            local cid = containerData.containerID
            local isExpanded = self.lootExpandedContainers[cid]

            -- Container header row (clickable accordion)
            local header = CreateFrame("Frame", nil, LootScrollChild, "BackdropTemplate")
            header:SetSize(scrollWidth, 48)
            header:SetPoint("TOPLEFT", 0, -yOffset)
            ApplyBackdrop(header, C.header, C.border)
            tinsert(self.lootItems, header)

            -- Expand/collapse indicator
            local arrow = header:CreateTexture(nil, "OVERLAY")
            arrow:SetSize(12, 12)
            arrow:SetPoint("LEFT", 6, 0)
            if isExpanded then
                arrow:SetAtlas("common-dropdown-icon-open")
            else
                arrow:SetAtlas("common-dropdown-icon-closed")
            end

            -- Container icon
            local hIcon = header:CreateTexture(nil, "ARTWORK")
            hIcon:SetSize(28, 28)
            hIcon:SetPoint("LEFT", 22, 0)
            hIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
            local containerIcon = C_Item.GetItemIconByID(containerData.containerID)
            hIcon:SetTexture(containerIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

            -- Container name
            local hName = MakeText(header, nil, 11, C.text, "LEFT")
            hName:SetPoint("LEFT", hIcon, "RIGHT", 10, 6)
            hName:SetWidth(190)

            local containerName = C_Item.GetItemInfo(containerData.containerID)
            if containerName then
                hName:SetText(containerName)
            else
                hName:SetText("|cff888888" .. ACO:Translate("LOADING") .. "|r")
                local itemObj = Item:CreateFromItemID(containerData.containerID)
                itemObj:ContinueOnItemLoad(function()
                    local loadedName = C_Item.GetItemInfo(containerData.containerID)
                    if loadedName then hName:SetText(loadedName) end
                end)
            end

            -- Opened count
            local hCount = MakeText(header, format(ACO:Translate("LOOT_OPENED_COUNT"), containerData.opened), 10, C.gold)
            hCount:SetPoint("LEFT", hIcon, "RIGHT", 10, -8)

            -- Gold total (right side)
            if containerData.gold > 0 then
                local hGold = MakeText(header, format(ACO:Translate("LOOT_GOLD_TOTAL"), ACO:FormatMoney(containerData.gold)), 10, C.gold)
                hGold:SetPoint("TOPRIGHT", -10, -8)

                local avgGold = floor(containerData.gold / max(1, containerData.opened))
                local hGoldAvg = MakeText(header, format(ACO:Translate("LOOT_GOLD_AVG"), ACO:FormatMoneyShort(avgGold)), 10, C.textDim)
                hGoldAvg:SetPoint("BOTTOMRIGHT", -10, 8)
            end

            -- Click to toggle + tooltip on header
            header:EnableMouse(true)
            header:SetScript("OnMouseDown", function()
                self.lootExpandedContainers[cid] = not self.lootExpandedContainers[cid]
                self:RefreshLootSummary()
            end)
            header:SetScript("OnEnter", function(self)
                self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
                self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
                GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                GameTooltip:SetHyperlink("item:" .. containerData.containerID)
                GameTooltip:Show()
            end)
            header:SetScript("OnLeave", function(self)
                self:SetBackdropColor(C.header.r, C.header.g, C.header.b, C.header.a)
                self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
                GameTooltip:Hide()
            end)

            yOffset = yOffset + 52

            -- Only show children when expanded
            if isExpanded then
                -- Loot item rows
                for ri, lootItem in ipairs(containerData.items) do
                    local row = CreateFrame("Frame", nil, LootScrollChild, "BackdropTemplate")
                    row:SetSize(scrollWidth, 30)
                    row:SetPoint("TOPLEFT", 0, -yOffset)

                    local isAltRow = (ri % 2 == 0)
                    ApplyBackdrop(row, isAltRow and C.rowAlt or C.row, C.border)
                    row._isAlt = isAltRow
                    tinsert(self.lootItems, row)

                    local rIcon = row:CreateTexture(nil, "ARTWORK")
                    rIcon:SetSize(20, 20)
                    rIcon:SetPoint("LEFT", 30, 0)
                    rIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
                    local lootIcon = C_Item.GetItemIconByID(lootItem.itemID)
                    rIcon:SetTexture(lootIcon or "Interface\\Icons\\INV_Misc_QuestionMark")

                    local rName = MakeText(row, nil, 10, C.text, "LEFT")
                    rName:SetPoint("LEFT", rIcon, "RIGHT", 8, 0)
                    rName:SetWidth(220)

                    local lootName = C_Item.GetItemInfo(lootItem.itemID)
                    if lootName then
                        rName:SetText(lootName)
                    else
                        rName:SetText("|cff888888...|r")
                        local itemObj = Item:CreateFromItemID(lootItem.itemID)
                        itemObj:ContinueOnItemLoad(function()
                            local loadedName = C_Item.GetItemInfo(lootItem.itemID)
                            if loadedName then rName:SetText(loadedName) end
                        end)
                    end

                    -- Total count
                    local rCount = MakeText(row, "x" .. lootItem.count, 10, C.green)
                    rCount:SetPoint("RIGHT", -90, 0)

                    -- Average per opening
                    local avg = lootItem.count / max(1, containerData.opened)
                    local rAvg = MakeText(row, format(ACO:Translate("LOOT_AVG_PER_OPEN"), avg), 10, C.textDim)
                    rAvg:SetPoint("RIGHT", -10, 0)

                    -- Tooltip
                    local tooltipLink = lootItem.link or ("item:" .. lootItem.itemID)
                    row:EnableMouse(true)
                    row:SetScript("OnEnter", function(self)
                        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
                        self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
                        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
                        GameTooltip:SetHyperlink(tooltipLink)
                        GameTooltip:Show()
                    end)
                    row:SetScript("OnLeave", function(self)
                        local bg = self._isAlt and C.rowAlt or C.row
                        self:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
                        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
                        GameTooltip:Hide()
                    end)

                    yOffset = yOffset + 33
                end

                -- Currency rows
                for _, currData in ipairs(containerData.currencies) do
                    local row = CreateFrame("Frame", nil, LootScrollChild, "BackdropTemplate")
                    row:SetSize(scrollWidth, 30)
                    row:SetPoint("TOPLEFT", 0, -yOffset)
                    ApplyBackdrop(row, C.rowAlt, C.border)
                    tinsert(self.lootItems, row)

                    local cIcon = row:CreateTexture(nil, "ARTWORK")
                    cIcon:SetSize(20, 20)
                    cIcon:SetPoint("LEFT", 30, 0)

                    local cName = MakeText(row, nil, 10, C.text, "LEFT")
                    cName:SetPoint("LEFT", cIcon, "RIGHT", 8, 0)
                    cName:SetWidth(220)

                    local currInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(currData.currencyID)
                    if currInfo then
                        cName:SetText(currInfo.name or ("Currency " .. currData.currencyID))
                        cIcon:SetTexture(currInfo.iconFileID or "Interface\\Icons\\INV_Misc_QuestionMark")
                    else
                        cName:SetText("Currency #" .. currData.currencyID)
                        cIcon:SetTexture("Interface\\Icons\\INV_Misc_Coin_01")
                    end

                    local cCount = MakeText(row, "x" .. currData.count, 10, C.accent)
                    cCount:SetPoint("RIGHT", -90, 0)

                    local avg = currData.count / max(1, containerData.opened)
                    local cAvg = MakeText(row, format(ACO:Translate("LOOT_AVG_PER_OPEN"), avg), 10, C.textDim)
                    cAvg:SetPoint("RIGHT", -10, 0)

                    yOffset = yOffset + 33
                end
            end -- end isExpanded

            yOffset = yOffset + 8
        end

        LootScrollChild:SetHeight(max(1, yOffset))
    end

    -- ========================================================================
    -- CONFIRMATION POPUPS
    -- ========================================================================

    StaticPopupDialogs["ACO_CLEAR_STATS"] = {
        text = ACO:Translate("POPUP_CLEAR_STATS_TEXT"),
        button1 = ACO:Translate("POPUP_YES"),
        button2 = ACO:Translate("POPUP_NO"),
        OnAccept = function()
            ACO:ClearStats()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["ACO_CLEAR_HISTORY"] = {
        text = ACO:Translate("POPUP_CLEAR_HISTORY_TEXT"),
        button1 = ACO:Translate("POPUP_YES"),
        button2 = ACO:Translate("POPUP_NO"),
        OnAccept = function()
            ACO:ClearHistory()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["ACO_REMOVE_ALL_CONTAINERS"] = {
        text = ACO:Translate("POPUP_REMOVE_ALL_TEXT"),
        button1 = ACO:Translate("POPUP_YES"),
        button2 = ACO:Translate("POPUP_NO"),
        OnAccept = function()
            ACO:RemoveAllContainers()
        end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }

    StaticPopupDialogs["ACO_CLEAR_LOOT"] = {
        text = ACO:Translate("POPUP_CLEAR_LOOT_TEXT"),
        button1 = ACO:Translate("POPUP_YES"),
        button2 = ACO:Translate("POPUP_NO"),
        OnAccept = function()
            ACO:ClearLootSummary()
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
        C_Timer.After(0.01, function()
            if ScrollFrame:GetWidth() > 0 then
                ScrollChild:SetWidth(ScrollFrame:GetWidth())
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
    -- MINIMAP BUTTON (36x36, Midnight style)
    -- ========================================================================

    local MinimapButton = CreateFrame("Button", "AutoChestOpenerMinimapButton", Minimap)
    MinimapButton:SetSize(36, 36)
    MinimapButton:SetFrameStrata("MEDIUM")
    MinimapButton:SetFrameLevel(8)
    MinimapButton:EnableMouse(true)
    MinimapButton:SetMovable(true)
    MinimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    MinimapButton:RegisterForDrag("LeftButton")
    MinimapButton:SetClampedToScreen(true)

    -- Position
    local angle = math.rad(220)
    local radius = 80
    MinimapButton:SetPoint("CENTER", Minimap, "CENTER",
        radius * cos(angle), radius * sin(angle))

    -- Background (dark circle)
    local background = MinimapButton:CreateTexture(nil, "BACKGROUND")
    background:SetSize(31, 31)
    background:SetPoint("CENTER", 0, 0)
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetVertexColor(0, 0, 0, 0.6)

    -- Main icon
    local icon = MinimapButton:CreateTexture(nil, "ARTWORK")
    icon:SetSize(18, 18)
    icon:SetPoint("CENTER", 0, 0)
    icon:SetTexture("Interface\\AddOns\\AutoChestOpener\\textures\\treasure.tga")
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    -- Minimap border
    local border = MinimapButton:CreateTexture(nil, "OVERLAY")
    border:SetSize(54, 54)
    border:SetPoint("TOPLEFT", 0, 0)
    border:SetTexture(136430) -- Interface\Minimap\MiniMap-TrackingBorder

    -- Hover highlight
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

            local a = math.atan2(cy - my, cx - mx)
            local x = cos(a) * radius
            local y = sin(a) * radius

            self:ClearAllPoints()
            self:SetPoint("CENTER", Minimap, "CENTER", x, y)
        end
    end)

    MinimapButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then
            UI:Toggle()
        elseif button == "RightButton" then
            ACO.db.enabled = not ACO.db.enabled
            ACO:Print(ACO.db.enabled and ACO:Translate("ENABLED") or ACO:Translate("DISABLED"))
            EnableCheck.checkbox:SetChecked(ACO.db.enabled)
        end
    end)

    MinimapButton:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:AddLine("|cff00ccffAuto|r|cffffffffChestOpener|r")
        GameTooltip:AddLine(" ")
        GameTooltip:AddLine("|cffffffff" .. ACO:Translate("MINIMAP_LEFT") .. "|r", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffffffff" .. ACO:Translate("MINIMAP_RIGHT") .. "|r", 0.8, 0.8, 0.8)
        GameTooltip:AddLine(" ")
        local status = ACO.db.enabled
            and ("|cff" .. format("%02x%02x%02x", floor(C.green.r*255), floor(C.green.g*255), floor(C.green.b*255)) .. ACO:Translate("ENABLED") .. "|r")
            or  ("|cff" .. format("%02x%02x%02x", floor(C.red.r*255),   floor(C.red.g*255),   floor(C.red.b*255))   .. ACO:Translate("DISABLED") .. "|r")
        GameTooltip:AddLine(string.format(ACO:Translate("MINIMAP_STATUS"), status))
        GameTooltip:Show()
    end)

    MinimapButton:SetScript("OnLeave", function(self)
        GameTooltip:Hide()
    end)

    -- Respect user setting
    if ACO.db and ACO.db.minimap and ACO.db.minimap.hide then
        MinimapButton:Hide()
    else
        MinimapButton:Show()
    end

    UI.minimapButton = MinimapButton

    -- ========================================================================
    -- QUEUE WIDGET (Midnight style)
    -- ========================================================================

    local QueueWidget = CreateFrame("Frame", "ACOQueueWidget", UIParent, "BackdropTemplate")
    QueueWidget:SetSize(320, 85)
    QueueWidget:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 200)
    QueueWidget:SetMovable(true)
    QueueWidget:EnableMouse(true)
    QueueWidget:RegisterForDrag("LeftButton")
    QueueWidget:SetScript("OnDragStart", QueueWidget.StartMoving)
    QueueWidget:SetScript("OnDragStop", QueueWidget.StopMovingOrSizing)
    QueueWidget:SetClampedToScreen(true)
    QueueWidget:SetFrameStrata("HIGH")
    ApplyBackdrop(QueueWidget, C.bg, C.accent)
    QueueWidget:Hide()

    -- Accent line at top of queue widget
    local qwAccent = QueueWidget:CreateTexture(nil, "OVERLAY")
    qwAccent:SetHeight(2)
    qwAccent:SetPoint("TOPLEFT", QueueWidget, "TOPLEFT", 1, -1)
    qwAccent:SetPoint("TOPRIGHT", QueueWidget, "TOPRIGHT", -1, -1)
    qwAccent:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.85)

    -- Item icon
    local qwIcon = QueueWidget:CreateTexture(nil, "ARTWORK")
    qwIcon:SetSize(36, 36)
    qwIcon:SetPoint("TOPLEFT", 10, -10)
    qwIcon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
    qwIcon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    -- Item name
    local qwName = MakeText(QueueWidget, nil, 11, C.text, "LEFT")
    qwName:SetPoint("TOPLEFT", qwIcon, "TOPRIGHT", 8, -2)
    qwName:SetPoint("RIGHT", QueueWidget, "RIGHT", -68, 0)

    -- Timer countdown
    local qwTimer = MakeText(QueueWidget, nil, 14, C.accent)
    qwTimer:SetPoint("BOTTOMLEFT", qwIcon, "BOTTOMRIGHT", 8, 2)

    -- Progress count
    local qwProgress = MakeText(QueueWidget, nil, 11, C.gold)
    qwProgress:SetPoint("RIGHT", QueueWidget, "RIGHT", -68, 6)
    qwProgress:SetJustifyH("RIGHT")

    -- Progress bar background
    local qwBarBg = CreateFrame("Frame", nil, QueueWidget, "BackdropTemplate")
    qwBarBg:SetHeight(10)
    qwBarBg:SetPoint("BOTTOMLEFT", 10, 10)
    qwBarBg:SetPoint("BOTTOMRIGHT", -10, 10)
    ApplyBackdrop(qwBarBg, C.bg, C.border)

    -- Progress bar fill
    local qwBarFill = qwBarBg:CreateTexture(nil, "ARTWORK")
    qwBarFill:SetPoint("LEFT", 1, 0)
    qwBarFill:SetHeight(8)
    qwBarFill:SetWidth(1)
    qwBarFill:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)

    -- Percentage text on the bar
    local qwBarText = MakeText(qwBarBg, "", 9, { r = 1, g = 1, b = 1 })
    qwBarText:SetPoint("CENTER", qwBarBg, "CENTER", 0, 0)

    -- Pause button
    local qwPauseBtn = CreateFrame("Button", nil, QueueWidget, "BackdropTemplate")
    qwPauseBtn:SetSize(26, 26)
    qwPauseBtn:SetPoint("TOPRIGHT", -36, -8)
    ApplyBackdrop(qwPauseBtn, { r = C.orange.r * 0.25, g = C.orange.g * 0.25, b = C.orange.b * 0.25, a = 0.9 }, C.border)

    local qwPauseText = MakeText(qwPauseBtn, "II", 11, { r = 1, g = 1, b = 1 })
    qwPauseText:SetPoint("CENTER")

    qwPauseBtn:SetScript("OnClick", function()
        if ACO.queuePaused then
            ACO:ResumeQueue()
            qwPauseText:SetText("II")
        else
            ACO:PauseQueue()
            qwPauseText:SetText(">")
        end
    end)
    qwPauseBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
        self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO.queuePaused and ACO:Translate("QUEUE_RESUME") or ACO:Translate("QUEUE_PAUSE"))
        GameTooltip:Show()
    end)
    qwPauseBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.orange.r * 0.25, C.orange.g * 0.25, C.orange.b * 0.25, 0.9)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        GameTooltip:Hide()
    end)

    -- Cancel button
    local qwCancelBtn = CreateFrame("Button", nil, QueueWidget, "BackdropTemplate")
    qwCancelBtn:SetSize(26, 26)
    qwCancelBtn:SetPoint("TOPRIGHT", -6, -8)
    ApplyBackdrop(qwCancelBtn, { r = C.red.r * 0.25, g = C.red.g * 0.25, b = C.red.b * 0.25, a = 0.9 }, C.border)

    local qwCancelIcon = qwCancelBtn:CreateTexture(nil, "OVERLAY")
    qwCancelIcon:SetSize(14, 14)
    qwCancelIcon:SetPoint("CENTER")
    qwCancelIcon:SetAtlas("common-icon-redx")

    qwCancelBtn:SetScript("OnClick", function()
        ACO:CancelQueue()
    end)
    qwCancelBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.red.r * 0.4, C.red.g * 0.4, C.red.b * 0.4, 1)
        self:SetBackdropBorderColor(C.red.r, C.red.g, C.red.b, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("QUEUE_CANCEL"))
        GameTooltip:Show()
    end)
    qwCancelBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.red.r * 0.25, C.red.g * 0.25, C.red.b * 0.25, 0.9)
        self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        GameTooltip:Hide()
    end)

    -- Track initial queue size
    QueueWidget._initialTotal = 0
    QueueWidget._hideAt = 0

    QueueWidget:SetScript("OnShow", function(self)
        self._initialTotal = #ACO.openQueue + (ACO.queueSessionOpened or 0)
        self._hideAt = 0
    end)

    -- OnUpdate: refresh widget state
    local qwUpdateElapsed = 0
    QueueWidget:SetScript("OnUpdate", function(self, elapsed)
        qwUpdateElapsed = qwUpdateElapsed + elapsed
        if qwUpdateElapsed < 0.05 then return end
        qwUpdateElapsed = 0

        local now = GetTime()
        local queueSize = #ACO.openQueue

        -- Queue empty: show 100% briefly before hiding
        if queueSize == 0 then
            if self._hideAt == 0 then
                self._hideAt = now + 1.5
                qwTimer:SetText("")
                qwProgress:SetText(format("%d/%d", self._initialTotal or 1, self._initialTotal or 1))
                local barWidth = qwBarBg:GetWidth() - 2
                if barWidth > 0 then
                    qwBarFill:SetWidth(barWidth)
                end
                qwBarText:SetText("100%")
                qwBarFill:SetColorTexture(C.green.r, C.green.g, C.green.b, 1)
            elseif now >= self._hideAt then
                self._hideAt = 0
                qwBarFill:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)
                self:Hide()
            end
            return
        end

        -- Reset hide timer if items reappear
        self._hideAt = 0

        -- Show current item
        local entry = ACO.openQueue[1]
        if entry then
            local iconTex = C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.itemID)
            qwIcon:SetTexture(iconTex or "Interface\\Icons\\INV_Misc_QuestionMark")

            local itemName = entry.link and entry.link:match("%[(.-)%]")
            if not itemName then
                itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(entry.itemID)
            end
            qwName:SetText(itemName or ("Item:" .. (entry.itemID or "?")))

            -- Timer countdown
            local waitTime = (entry.executeAt or 0) - now
            if ACO.queuePaused then
                qwTimer:SetText(ACO:Translate("QUEUE_PAUSED"))
                qwTimer:SetTextColor(C.orange.r, C.orange.g, C.orange.b)
            elseif waitTime > 0.1 then
                qwTimer:SetText(format("%.1fs", waitTime))
                qwTimer:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
            else
                qwTimer:SetText(ACO:Translate("QUEUE_OPENING"))
                qwTimer:SetTextColor(C.green.r, C.green.g, C.green.b)
            end
        end

        -- Progress
        local bt = ACO.batchTracker
        local completedItems, totalItems
        if bt and bt.active and bt.totalQueued > 0 then
            completedItems = bt.count
            totalItems = bt.totalQueued
        else
            completedItems = ACO.queueSessionOpened or 0
            totalItems = max(self._initialTotal or 0, completedItems + queueSize)
        end

        -- Current item timer progress
        local currentItemPct = 0
        if entry then
            local delay = ACO.db and ACO.db.delay or 3
            if delay > 0 then
                local waitTime = (entry.executeAt or 0) - now
                currentItemPct = 1 - max(0, min(1, waitTime / delay))
            else
                currentItemPct = 1
            end
        end

        -- Overall progress
        local pct = 0
        if totalItems > 0 then
            pct = (completedItems + currentItemPct) / totalItems
            pct = max(0, min(1, pct))
        end

        -- Remaining count
        qwProgress:SetText(format("%d/%d", completedItems, totalItems))

        -- Progress bar fill (smooth)
        local barWidth = qwBarBg:GetWidth() - 2
        if barWidth > 0 then
            qwBarFill:SetWidth(max(1, pct * barWidth))
            qwBarFill:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)
        end
        qwBarText:SetText(format("%d%%", floor(pct * 100)))

        -- Update pause button icon
        if ACO.queuePaused then
            qwPauseText:SetText(">")
        else
            qwPauseText:SetText("II")
        end
    end)

    UI.queueWidget = QueueWidget

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
