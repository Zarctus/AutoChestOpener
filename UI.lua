--[[
    Auto Chest Opener - UI Module
    Midnight-style interface (palette unifiée Zayu / Zarctus)
    Version: 3.1.0
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

local FRAME_WIDTH = 940
local FRAME_HEIGHT = 710
local FRAME_MIN_WIDTH = 820
local FRAME_MIN_HEIGHT = 680
local FRAME_MAX_WIDTH = 1200
local FRAME_MAX_HEIGHT = 950
local HEADER_HEIGHT = 54
local TAB_HEIGHT = 38
local KPI_HEIGHT = 82
local LEFT_COLUMN_WIDTH = 300
local BUTTON_HEIGHT = 30
local LIST_ITEM_HEIGHT = 48
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
    frame:SetSize(270, 26)

    local checkbox = CreateFrame("CheckButton", nil, frame, "BackdropTemplate")
    checkbox:SetSize(38, 20)
    checkbox:SetPoint("RIGHT", frame, "RIGHT", 0, 0)
    ApplyBackdrop(checkbox, C.bg, C.border)

    local knob = CreateFrame("Frame", nil, checkbox, "BackdropTemplate")
    knob:SetSize(14, 14)
    ApplyBackdrop(knob, C.textDim, C.borderLight)

    local function UpdateVisual(self)
        knob:ClearAllPoints()
        if self:GetChecked() then
            self:SetBackdropColor(C.accent.r * 0.35, C.accent.g * 0.35, C.accent.b * 0.35, 1)
            self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
            knob:SetPoint("RIGHT", -3, 0)
            knob:SetBackdropColor(C.accent.r, C.accent.g, C.accent.b, 1)
        else
            self:SetBackdropColor(C.bg.r, C.bg.g, C.bg.b, 1)
            self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            knob:SetPoint("LEFT", 3, 0)
            knob:SetBackdropColor(C.textDim.r, C.textDim.g, C.textDim.b, 1)
        end
    end

    local originalSetChecked = checkbox.SetChecked
    checkbox.SetChecked = function(self, checked)
        originalSetChecked(self, checked and true or false)
        UpdateVisual(self)
    end

    checkbox:SetScript("OnClick", function(self)
        UpdateVisual(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        if self.callback then self.callback(self:GetChecked()) end
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
        UpdateVisual(self)
        GameTooltip:Hide()
    end)

    local text = MakeText(frame, label, 11, C.text)
    text:SetPoint("LEFT", 0, 0)
    text:SetPoint("RIGHT", checkbox, "LEFT", -8, 0)
    text:SetJustifyH("LEFT")

    frame.checkbox = checkbox
    frame.label = text
    frame.UpdateVisual = UpdateVisual
    UpdateVisual(checkbox)
    return frame
end

-- ============================================================================
-- MODERN SLIDER CREATION (Midnight style)
-- ============================================================================

local function CreateModernSlider(parent, label, minVal, maxVal, step, tooltip)
    local C = ACO.colors
    local frame = CreateFrame("Frame", nil, parent)
    frame:SetSize(270, 56)

    local text = MakeText(frame, label, 11, C.text)
    text:SetPoint("TOPLEFT", 0, -2)

    local valueBox = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
    valueBox:SetSize(48, 22)
    valueBox:SetPoint("TOPRIGHT", -14, 0)
    ApplyBackdrop(valueBox, C.bg, C.border)
    valueBox:SetFontObject("GameFontHighlightSmall")
    valueBox:SetJustifyH("CENTER")
    valueBox:SetAutoFocus(false)
    valueBox:SetMaxLetters(4)

    local suffix = MakeText(frame, "s", 10, C.textDim)
    suffix:SetPoint("LEFT", valueBox, "RIGHT", 4, 0)

    local track = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    track:SetPoint("TOPLEFT", 0, -31)
    track:SetPoint("TOPRIGHT", 0, -31)
    track:SetHeight(7)
    ApplyBackdrop(track, C.bg, C.border)
    track:EnableMouse(true)

    local fill = track:CreateTexture(nil, "ARTWORK")
    fill:SetPoint("LEFT", 2, 0)
    fill:SetHeight(3)
    fill:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)

    local thumb = CreateFrame("Button", nil, track, "BackdropTemplate")
    thumb:SetSize(13, 15)
    ApplyBackdrop(thumb, C.accent, C.borderLight)
    thumb:EnableMouse(true)
    thumb:RegisterForDrag("LeftButton")

    local minText = MakeText(frame, tostring(minVal) .. "s", 8, C.textDim)
    minText:SetPoint("TOPLEFT", track, "BOTTOMLEFT", 0, -3)
    local maxText = MakeText(frame, tostring(maxVal) .. "s", 8, C.textDim)
    maxText:SetPoint("TOPRIGHT", track, "BOTTOMRIGHT", 0, -3)

    local updatingText = false
    local committingValue = false
    local function FormatValue(value)
        if value == floor(value) then
            return format("%d", value)
        end
        return format("%.1f", value)
    end

    local function UpdateSlider(value, suppressCallback)
        value = tonumber(value) or minVal
        value = max(minVal, min(maxVal, value))
        if step then
            value = floor(value / step + 0.5) * step
        end

        local percent = (value - minVal) / (maxVal - minVal)
        local trackWidth = max(1, track:GetWidth() - thumb:GetWidth())

        thumb:ClearAllPoints()
        thumb:SetPoint("LEFT", track, "LEFT", percent * trackWidth, 0)
        fill:SetWidth(max(1, percent * trackWidth))

        updatingText = true
        valueBox:SetText(FormatValue(value))
        updatingText = false

        frame.value = value
        if frame.callback and not suppressCallback then frame.callback(value) end
    end

    local function CommitValue()
        if updatingText or committingValue then return end
        committingValue = true
        local value = tonumber(valueBox:GetText())
        if value then
            UpdateSlider(value)
        else
            UpdateSlider(frame.value or minVal, true)
        end
        valueBox:ClearFocus()
        committingValue = false
    end

    valueBox:SetScript("OnEnterPressed", CommitValue)
    valueBox:SetScript("OnEscapePressed", function(self)
        UpdateSlider(frame.value or minVal, true)
        self:ClearFocus()
    end)
    valueBox:SetScript("OnEditFocusLost", function()
        if not updatingText then CommitValue() end
    end)

    thumb:SetScript("OnDragStart", function(self) self.isDragging = true end)
    thumb:SetScript("OnDragStop", function(self) self.isDragging = false end)

    local function SetFromCursor(self)
        local x = select(1, GetCursorPosition()) / self:GetEffectiveScale()
        local left = self:GetLeft()
        local width = max(1, self:GetWidth() - thumb:GetWidth())
        local percent = max(0, min(1, (x - left - thumb:GetWidth() / 2) / width))
        UpdateSlider(minVal + percent * (maxVal - minVal))
    end

    track:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then SetFromCursor(self) end
    end)
    track:SetScript("OnUpdate", function(self)
        if thumb.isDragging then SetFromCursor(self) end
    end)

    if tooltip then
        frame:EnableMouse(true)
        frame:SetScript("OnEnter", function(self)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetText(tooltip, 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        frame:SetScript("OnLeave", function() GameTooltip:Hide() end)
    end

    frame.UpdateSlider = UpdateSlider
    frame.valueText = valueBox
    frame.valueBox = valueBox
    frame.SetValue = function(self, val)
        if track:GetWidth() > 0 then
            UpdateSlider(val, true)
        else
            self.pendingValue = val
        end
    end
    frame:SetScript("OnShow", function()
        C_Timer.After(0.05, function()
            if frame.pendingValue ~= nil then
                UpdateSlider(frame.pendingValue, true)
                frame.pendingValue = nil
            end
        end)
    end)

    return frame
end

-- ============================================================================
-- MAIN FRAME CREATION
-- ============================================================================

function ACO:InitUI()
    local C = self.colors

    -- Main Frame
    local MainFrame = CreateFrame("Frame", "AutoChestOpenerFrame", UIParent, "BackdropTemplate")
    local uiState = ACO.db.ui or {}
    MainFrame:SetSize(uiState.width or FRAME_WIDTH, uiState.height or FRAME_HEIGHT)
    MainFrame:SetPoint(uiState.point or "CENTER", UIParent, uiState.relativePoint or "CENTER", uiState.x or 0, uiState.y or 0)
    MainFrame:SetMovable(true)
    MainFrame:EnableMouse(true)
    MainFrame:RegisterForDrag("LeftButton")

    local function SaveFrameState()
        if not ACO.db or not ACO.db.ui then return end
        local point, _, relativePoint, x, y = MainFrame:GetPoint(1)
        ACO.db.ui.point = point or "CENTER"
        ACO.db.ui.relativePoint = relativePoint or point or "CENTER"
        ACO.db.ui.x = floor((x or 0) + 0.5)
        ACO.db.ui.y = floor((y or 0) + 0.5)
        ACO.db.ui.width = floor(MainFrame:GetWidth() + 0.5)
        ACO.db.ui.height = floor(MainFrame:GetHeight() + 0.5)
    end

    MainFrame:SetScript("OnDragStart", MainFrame.StartMoving)
    MainFrame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        SaveFrameState()
    end)
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
        SaveFrameState()
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
    Icon:SetSize(36, 36)
    Icon:SetPoint("LEFT", PADDING + 2, 0)
    Icon:SetAtlas("VignetteLootChest")

    -- Title (styled like MidnightWeekly: first word cyan, rest text color)
    local Title = MakeText(Header, nil, 18, nil)
    Title:SetPoint("TOPLEFT", Icon, "TOPRIGHT", 10, -2)
    Title:SetText("|cff00ccffAuto|r|cff" .. format("%02x%02x%02x",
        floor(C.text.r*255), floor(C.text.g*255), floor(C.text.b*255))
        .. "ChestOpener|r")

    -- Version
    local Version = MakeText(Header, "v" .. ACO.version .. "  •  Retail 120007", 10, C.textDim)
    Version:SetPoint("TOPLEFT", Title, "BOTTOMLEFT", 0, -3)

    -- Theme marker: intentionally text-only so it reads as metadata, not a button.
    local RuntimeBadge = CreateFrame("Frame", nil, Header)
    RuntimeBadge:SetSize(118, 24)
    RuntimeBadge:SetPoint("RIGHT", -44, 0)
    local RuntimeText = MakeText(RuntimeBadge, "MIDNIGHT 2.0", 9, C.textDim)
    RuntimeText:SetPoint("CENTER")
    local runtimeLine = RuntimeBadge:CreateTexture(nil, "ARTWORK")
    runtimeLine:SetHeight(1)
    runtimeLine:SetPoint("BOTTOMLEFT", 14, 2)
    runtimeLine:SetPoint("BOTTOMRIGHT", -14, 2)
    runtimeLine:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 0.55)

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

    -- ========================================================================
    -- KPI STRIP (Concept 1: session gold / confirmed opens / pending queue)
    -- ========================================================================

    local KPIFrame = CreateFrame("Frame", nil, MainFrame, "BackdropTemplate")
    KPIFrame:SetHeight(KPI_HEIGHT)
    KPIFrame:SetPoint("TOPLEFT", TabContainer, "BOTTOMLEFT", PADDING, -PADDING)
    KPIFrame:SetPoint("TOPRIGHT", TabContainer, "BOTTOMRIGHT", -PADDING, -PADDING)
    ApplyBackdrop(KPIFrame, C.header, C.border)

    local function CreateKPICard(parent, iconSource, label, useTexture)
        local card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
        ApplyBackdrop(card, C.rowAlt, C.border)
        -- KPI text used to be chained label -> value -> detail. Font metrics and
        -- UI scale could then push the detail line below the card. Every line now
        -- owns an explicit bounded region inside the card instead.
        if card.SetClipsChildren then
            card:SetClipsChildren(true)
        end

        local icon = card:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30)
        icon:SetPoint("LEFT", 14, 0)
        if useTexture then
            icon:SetTexture(iconSource)
        else
            icon:SetAtlas(iconSource)
            icon:SetVertexColor(C.accent.r, C.accent.g, C.accent.b)
        end

        local textLeft = 56

        local labelText = MakeText(card, label, 9, C.textDim, "LEFT")
        labelText:SetPoint("TOPLEFT", card, "TOPLEFT", textLeft, -6)
        labelText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -6)
        labelText:SetHeight(10)
        labelText:SetJustifyV("MIDDLE")
        if labelText.SetWordWrap then labelText:SetWordWrap(false) end
        if labelText.SetMaxLines then labelText:SetMaxLines(1) end

        local valueText = MakeText(card, "0", 20, C.text, "LEFT")
        valueText:SetPoint("TOPLEFT", card, "TOPLEFT", textLeft, -17)
        valueText:SetPoint("TOPRIGHT", card, "TOPRIGHT", -10, -17)
        valueText:SetHeight(24)
        valueText:SetJustifyV("MIDDLE")
        if valueText.SetWordWrap then valueText:SetWordWrap(false) end
        if valueText.SetMaxLines then valueText:SetMaxLines(1) end

        local detailText = MakeText(card, "", 9, C.textDim, "LEFT")
        detailText:SetPoint("BOTTOMLEFT", card, "BOTTOMLEFT", textLeft, 6)
        detailText:SetPoint("BOTTOMRIGHT", card, "BOTTOMRIGHT", -10, 6)
        detailText:SetHeight(10)
        detailText:SetJustifyV("MIDDLE")
        if detailText.SetWordWrap then detailText:SetWordWrap(false) end
        if detailText.SetMaxLines then detailText:SetMaxLines(1) end

        card.icon = icon
        card.valueText = valueText
        card.detailText = detailText
        return card
    end

    local GoldKPI = CreateKPICard(KPIFrame, "Interface\\MoneyFrame\\UI-GoldIcon", ACO:Translate("KPI_SESSION_GOLD"), true)
    local OpenedKPI = CreateKPICard(KPIFrame, "VignetteLootChest", ACO:Translate("KPI_OPENED_SESSION"))
    local QueueKPI = CreateKPICard(KPIFrame, "QuestNormal", ACO:Translate("KPI_PENDING_QUEUE"))

    local function LayoutKPIs()
        local available = max(300, KPIFrame:GetWidth() - 24)
        local width = floor((available - 16) / 3)
        GoldKPI:ClearAllPoints()
        GoldKPI:SetPoint("TOPLEFT", 12, -9)
        GoldKPI:SetSize(width, KPI_HEIGHT - 18)
        OpenedKPI:ClearAllPoints()
        OpenedKPI:SetPoint("LEFT", GoldKPI, "RIGHT", 8, 0)
        OpenedKPI:SetSize(width, KPI_HEIGHT - 18)
        QueueKPI:ClearAllPoints()
        QueueKPI:SetPoint("LEFT", OpenedKPI, "RIGHT", 8, 0)
        QueueKPI:SetSize(width, KPI_HEIGHT - 18)
    end
    KPIFrame:SetScript("OnSizeChanged", LayoutKPIs)
    C_Timer.After(0, LayoutKPIs)

    UI.kpiGold = GoldKPI
    UI.kpiOpened = OpenedKPI
    UI.kpiQueue = QueueKPI

    function UI:RefreshKPI()
        if not ACO.db or not ACO.db.stats then return end
        local stats = ACO.db.stats
        GoldKPI.valueText:SetText(ACO:FormatMoneyShort(stats.sessionGold or 0))
        GoldKPI.detailText:SetText(ACO:Translate("KPI_THIS_SESSION"))
        OpenedKPI.valueText:SetText(tostring(stats.totalOpenedSession or 0))
        OpenedKPI.detailText:SetText(format(ACO:Translate("KPI_LIFETIME_FORMAT"), stats.totalOpened or 0))

        local pending = #(ACO.openQueue or {}) + (ACO.pendingVerifications or 0)
        QueueKPI.valueText:SetText(tostring(pending))
        local blocked, reason = ACO:IsOpeningBlocked()
        if ACO.queuePaused then
            QueueKPI.detailText:SetText(ACO:Translate("QUEUE_PAUSED"))
            QueueKPI.detailText:SetTextColor(C.orange.r, C.orange.g, C.orange.b)
        elseif blocked then
            QueueKPI.detailText:SetText(ACO:GetBlockReasonText(reason))
            QueueKPI.detailText:SetTextColor(C.red.r, C.red.g, C.red.b)
        elseif ACO.assistedEntry then
            QueueKPI.detailText:SetText(ACO:Translate("QUEUE_STATUS_ASSISTED_READY"))
            QueueKPI.detailText:SetTextColor(C.green.r, C.green.g, C.green.b)
        else
            QueueKPI.detailText:SetText(ACO:Translate("KPI_READY"))
            QueueKPI.detailText:SetTextColor(C.green.r, C.green.g, C.green.b)
        end
    end

    -- Content frames for each tab
    local ContainersContent = CreateFrame("Frame", nil, MainFrame)
    ContainersContent:SetPoint("TOPLEFT", KPIFrame, "BOTTOMLEFT", -PADDING, -PADDING)
    ContainersContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)

    local StatsContent = CreateFrame("Frame", nil, MainFrame)
    StatsContent:SetPoint("TOPLEFT", KPIFrame, "BOTTOMLEFT", -PADDING, -PADDING)
    StatsContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    StatsContent:Hide()

    local HistoryContent = CreateFrame("Frame", nil, MainFrame)
    HistoryContent:SetPoint("TOPLEFT", KPIFrame, "BOTTOMLEFT", -PADDING, -PADDING)
    HistoryContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    HistoryContent:Hide()

    local PendingContent = CreateFrame("Frame", nil, MainFrame)
    PendingContent:SetPoint("TOPLEFT", KPIFrame, "BOTTOMLEFT", -PADDING, -PADDING)
    PendingContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    PendingContent:Hide()

    local LootContent = CreateFrame("Frame", nil, MainFrame)
    LootContent:SetPoint("TOPLEFT", KPIFrame, "BOTTOMLEFT", -PADDING, -PADDING)
    LootContent:SetPoint("BOTTOMRIGHT", MainFrame, "BOTTOMRIGHT", 0, 0)
    LootContent:Hide()

    UI.tabs = {}
    UI.tabOrder = {}
    UI.currentTab = (ACO.db.ui and ACO.db.ui.lastTab) or "containers"

    local function CreateTab(parent, text, icon, tabKey, xOffset)
        local tab = CreateFrame("Button", nil, parent, "BackdropTemplate")
        tab:SetSize(120, TAB_HEIGHT)
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
        tinsert(UI.tabOrder, tab)

        return tab
    end

    local containersTab = CreateTab(TabContainer, ACO:Translate("TAB_CONTAINERS"), "BonusLoot-Chest", "containers", PADDING)
    local statsTab = CreateTab(TabContainer, ACO:Translate("TAB_STATS"), "communities-icon-notification", "stats", PADDING + 108)
    local historyTab = CreateTab(TabContainer, ACO:Translate("TAB_HISTORY"), "lorewalking-map-icon", "history", PADDING + 216)
    local pendingTab = CreateTab(TabContainer, ACO:Translate("TAB_PENDING"), "QuestNormal", "pending", PADDING + 324)
    local lootTab = CreateTab(TabContainer, ACO:Translate("TAB_LOOT"), "Auctioneer", "loot", PADDING + 432)

    local function LayoutTabs()
        local width = max(100, floor((TabContainer:GetWidth() - (PADDING * 2)) / #UI.tabOrder))
        for index, tab in ipairs(UI.tabOrder) do
            tab:ClearAllPoints()
            tab:SetSize(width, TAB_HEIGHT)
            tab:SetPoint("LEFT", TabContainer, "LEFT", PADDING + ((index - 1) * width), 0)
        end
    end
    TabContainer:SetScript("OnSizeChanged", LayoutTabs)
    C_Timer.After(0, LayoutTabs)

    function UI:SwitchTab(tabKey)
        if not self.tabs[tabKey] then tabKey = "containers" end
        self.currentTab = tabKey
        if ACO.db and ACO.db.ui then ACO.db.ui.lastTab = tabKey end

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

    -- Initialize persisted tab as active
    local initialTab = UI.tabs[UI.currentTab] or containersTab
    initialTab.isActive = true
    initialTab:UpdateAppearance()

    -- ========================================================================
    -- OPTIONS SECTION (inside ContainersContent)
    -- ========================================================================

    local OptionsSection = CreateFrame("Frame", nil, ContainersContent, "BackdropTemplate")
    OptionsSection:SetSize(LEFT_COLUMN_WIDTH, 286)
    OptionsSection:SetPoint("TOPLEFT", PADDING, -PADDING)
    ApplyBackdrop(OptionsSection, C.row, C.border)

    local OptionsIcon = OptionsSection:CreateTexture(nil, "ARTWORK")
    OptionsIcon:SetSize(16, 16)
    OptionsIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    OptionsIcon:SetAtlas("options")

    local OptionsTitle = MakeText(OptionsSection, ACO:Translate("OPTIONS_TITLE"), 12, C.accent)
    OptionsTitle:SetPoint("LEFT", OptionsIcon, "RIGHT", 6, 0)

    -- Enable checkbox
    local EnableCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("ENABLE_AUTO_OPEN"), ACO:Translate("ENABLE_TOOLTIP"))
    EnableCheck:SetPoint("TOPLEFT", OptionsSection, "TOPLEFT", PADDING, -42)
    EnableCheck:SetPoint("TOPRIGHT", OptionsSection, "TOPRIGHT", -PADDING, -42)
    EnableCheck.checkbox:SetChecked(ACO.db.enabled)
    EnableCheck.checkbox.callback = function(checked)
        ACO.db.enabled = checked
    end

    -- Notifications checkbox
    local NotifyCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("SHOW_NOTIFICATIONS"), ACO:Translate("SHOW_NOTIFICATIONS_TOOLTIP"))
    NotifyCheck:SetPoint("TOPLEFT", EnableCheck, "BOTTOMLEFT", 0, -5)
    NotifyCheck:SetPoint("TOPRIGHT", EnableCheck, "BOTTOMRIGHT", 0, -5)
    NotifyCheck.checkbox:SetChecked(ACO.db.showNotifications)
    NotifyCheck.checkbox.callback = function(checked)
        ACO.db.showNotifications = checked
    end

    -- Sound checkbox
    local SoundCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("PLAY_SOUNDS"), ACO:Translate("PLAY_SOUNDS_TOOLTIP"))
    SoundCheck:SetPoint("TOPLEFT", NotifyCheck, "BOTTOMLEFT", 0, -6)
    SoundCheck:SetPoint("TOPRIGHT", NotifyCheck, "BOTTOMRIGHT", 0, -6)
    SoundCheck.checkbox:SetChecked(ACO.db.notificationSound)
    SoundCheck.checkbox.callback = function(checked)
        ACO.db.notificationSound = checked
    end

    -- Auto-discovery checkbox
    local AutoDiscoverCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("ENABLE_AUTO_DISCOVER"), ACO:Translate("ENABLE_AUTO_DISCOVER_TOOLTIP"))
    AutoDiscoverCheck:SetPoint("TOPLEFT", SoundCheck, "BOTTOMLEFT", 0, -6)
    AutoDiscoverCheck:SetPoint("TOPRIGHT", SoundCheck, "BOTTOMRIGHT", 0, -6)
    AutoDiscoverCheck.checkbox:SetChecked(ACO.db.autoDiscovery ~= false)
    AutoDiscoverCheck.checkbox.callback = function(checked)
        ACO.db.autoDiscovery = checked
    end

    -- Auto-open on login checkbox
    local AutoOpenLoginCheck = CreateModernCheckbox(OptionsSection, ACO:Translate("AUTO_OPEN_LOGIN"), ACO:Translate("AUTO_OPEN_LOGIN_TOOLTIP"))
    AutoOpenLoginCheck:SetPoint("TOPLEFT", AutoDiscoverCheck, "BOTTOMLEFT", 0, -6)
    AutoOpenLoginCheck:SetPoint("TOPRIGHT", AutoDiscoverCheck, "BOTTOMRIGHT", 0, -6)
    AutoOpenLoginCheck.checkbox:SetChecked(ACO.db.autoOpenOnLogin == true)
    AutoOpenLoginCheck.checkbox.callback = function(checked)
        ACO.db.autoOpenOnLogin = checked
    end

    -- Delay slider
    local DelaySlider = CreateModernSlider(OptionsSection, ACO:Translate("DELAY_SLIDER_LABEL"), 0, 10, 0.5, ACO:Translate("DELAY_TOOLTIP"))
    DelaySlider:SetPoint("TOPLEFT", AutoOpenLoginCheck, "BOTTOMLEFT", 0, -9)
    DelaySlider:SetPoint("TOPRIGHT", AutoOpenLoginCheck, "BOTTOMRIGHT", 0, -9)
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

    -- ========================================================================
    -- ADD ITEM SECTION (inside ContainersContent)
    -- ========================================================================

    local AddSection = CreateFrame("Frame", nil, ContainersContent, "BackdropTemplate")
    AddSection:SetSize(LEFT_COLUMN_WIDTH, 166)
    AddSection:SetPoint("TOPLEFT", OptionsSection, "BOTTOMLEFT", 0, -PADDING)
    ApplyBackdrop(AddSection, C.row, C.border)

    local AddIcon = AddSection:CreateTexture(nil, "ARTWORK")
    AddIcon:SetSize(16, 16)
    AddIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    AddIcon:SetAtlas("communities-icon-addgroupplus")

    local AddTitle = MakeText(AddSection, ACO:Translate("ADD_TITLE"), 12, C.green)
    AddTitle:SetPoint("LEFT", AddIcon, "RIGHT", 6, 0)

    -- Drop zone
    local DropZone = CreateFrame("Button", nil, AddSection, "BackdropTemplate")
    DropZone:SetSize(LEFT_COLUMN_WIDTH - (PADDING * 2), 64)
    DropZone:SetPoint("TOPLEFT", PADDING, -38)
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
    IDInput:SetHeight(34)
    IDInput:SetPoint("TOPLEFT", DropZone, "BOTTOMLEFT", 0, -10)
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
    local AddBtn = CreateModernButton(AddSection, ACO:Translate("ADD_BTN"), 88, 34, true)
    AddBtn:SetPoint("TOPRIGHT", DropZone, "BOTTOMRIGHT", 0, -10)
    IDInput:SetPoint("RIGHT", AddBtn, "LEFT", -10, 0)
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
    ListSection:SetPoint("TOPLEFT", OptionsSection, "TOPRIGHT", PADDING, 0)
    ListSection:SetPoint("TOPRIGHT", ContainersContent, "TOPRIGHT", -PADDING, -PADDING)
    ListSection:SetPoint("BOTTOMRIGHT", ContainersContent, "BOTTOMRIGHT", -PADDING, PADDING)
    ApplyBackdrop(ListSection, C.row, C.border)

    local ListIcon = ListSection:CreateTexture(nil, "ARTWORK")
    ListIcon:SetSize(16, 16)
    ListIcon:SetPoint("TOPLEFT", PADDING, -PADDING)
    ListIcon:SetAtlas("VignetteLootChest")

    local ListTitle = MakeText(ListSection, ACO:Translate("LIST_TITLE"), 12, C.gold)
    ListTitle:SetPoint("LEFT", ListIcon, "RIGHT", 6, 0)

    -- Count
    local ListCount = MakeText(ListSection, "", 10, C.textDim)
    ListCount:SetPoint("TOPRIGHT", -PADDING - 100, -PADDING)
    UI.listCount = ListCount

    -- Open All Button
    local OpenAllBtn = CreateModernButton(ListSection, ACO:Translate("OPEN_ALL"), 124, 30, true)
    OpenAllBtn:SetPoint("BOTTOMLEFT", PADDING, PADDING)
    local openAllIcon = OpenAllBtn:CreateTexture(nil, "ARTWORK")
    openAllIcon:SetSize(16, 16)
    openAllIcon:SetPoint("LEFT", 12, 0)
    openAllIcon:SetAtlas("BonusLoot-Chest")
    openAllIcon:SetVertexColor(C.accent.r, C.accent.g, C.accent.b)
    OpenAllBtn.text:ClearAllPoints()
    OpenAllBtn.text:SetPoint("CENTER", 10, 0)
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
    local ImportBtn = CreateModernButton(ListSection, ACO:Translate("IMPORT_BTN"), 72, 30, false)
    ImportBtn:SetPoint("LEFT", OpenAllBtn, "RIGHT", 8, 0)
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
    local ExportBtn = CreateModernButton(ListSection, ACO:Translate("EXPORT_BTN"), 72, 30, false)
    ExportBtn:SetPoint("LEFT", ImportBtn, "RIGHT", 8, 0)
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
    local RemoveAllBtn = CreateModernButton(ListSection, ACO:Translate("REMOVE_ALL_BTN"), 88, 30, false)
    RemoveAllBtn:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
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

    -- View toggle: Tracked | Blocked
    UI.listView = (ACO.db.ui and ACO.db.ui.listView) or "tracked"

    local TrackedBtn = CreateModernButton(ListSection, ACO:Translate("SHOW_TRACKED"), 78, 26, true)
    TrackedBtn:SetPoint("TOPLEFT", PADDING, -38)
    local BlockedBtn = CreateModernButton(ListSection, ACO:Translate("SHOW_BLOCKED"), 78, 26, false)
    BlockedBtn:SetPoint("LEFT", TrackedBtn, "RIGHT", 6, 0)

    -- Search bar: flexible width, built-in icon and explicit clear action.
    local SearchBox = CreateFrame("EditBox", nil, ListSection, "BackdropTemplate")
    SearchBox:SetHeight(26)
    SearchBox:SetPoint("LEFT", BlockedBtn, "RIGHT", 10, 0)
    SearchBox:SetPoint("RIGHT", ListSection, "RIGHT", -PADDING, 0)
    ApplyBackdrop(SearchBox, C.bg, C.border)
    SearchBox:SetFontObject("GameFontHighlight")
    SearchBox:SetTextInsets(28, 28, 0, 0)
    SearchBox:SetAutoFocus(false)
    SearchBox:SetMaxLetters(80)
    UI.searchFilterText = (ACO.db.ui and ACO.db.ui.search or ""):lower()

    local searchIcon = SearchBox:CreateTexture(nil, "ARTWORK")
    searchIcon:SetSize(14, 14)
    searchIcon:SetPoint("LEFT", 8, 0)
    searchIcon:SetTexture("Interface\\Common\\UI-Searchbox-Icon")
    searchIcon:SetVertexColor(C.textDim.r, C.textDim.g, C.textDim.b)

    local SearchPlaceholder = MakeText(SearchBox, ACO:Translate("SEARCH_PLACEHOLDER"), 11, C.textDim)
    SearchPlaceholder:SetPoint("LEFT", 28, 0)

    local SearchClear = CreateFrame("Button", nil, SearchBox)
    SearchClear:SetSize(18, 18)
    SearchClear:SetPoint("RIGHT", -5, 0)
    local searchClearTex = SearchClear:CreateTexture(nil, "ARTWORK")
    searchClearTex:SetAllPoints()
    searchClearTex:SetAtlas("common-search-clearbutton", true)
    searchClearTex:SetVertexColor(C.textDim.r, C.textDim.g, C.textDim.b)
    SearchClear:Hide()
    SearchClear:SetScript("OnEnter", function()
        searchClearTex:SetVertexColor(C.text.r, C.text.g, C.text.b)
        GameTooltip:SetOwner(SearchClear, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("SEARCH_CLEAR_TOOLTIP"))
        GameTooltip:Show()
    end)
    SearchClear:SetScript("OnLeave", function()
        searchClearTex:SetVertexColor(C.textDim.r, C.textDim.g, C.textDim.b)
        GameTooltip:Hide()
    end)
    SearchClear:SetScript("OnClick", function()
        SearchBox:SetText("")
        SearchBox:ClearFocus()
    end)

    SearchBox:SetScript("OnTextChanged", function(box)
        local txt = box:GetText()
        UI.searchFilterText = txt:lower()
        if ACO.db and ACO.db.ui then ACO.db.ui.search = txt end
        if txt ~= "" then
            SearchPlaceholder:Hide()
            SearchClear:Show()
        else
            SearchPlaceholder:Show()
            SearchClear:Hide()
        end
        UI:RefreshList()
    end)
    SearchBox:SetScript("OnEscapePressed", function(box)
        box:SetText("")
        box:ClearFocus()
    end)

    if ACO.db.ui and ACO.db.ui.search and ACO.db.ui.search ~= "" then
        SearchBox:SetText(ACO.db.ui.search)
        SearchPlaceholder:Hide()
        SearchClear:Show()
    end

    local function UpdateViewButtons()
        local C2 = ACO.colors
        if UI.listView == "tracked" then
            TrackedBtn:SetBackdropColor(C2.accent.r * 0.25, C2.accent.g * 0.25, C2.accent.b * 0.25, 0.9)
            TrackedBtn:SetBackdropBorderColor(C2.accent.r, C2.accent.g, C2.accent.b, 1)
            BlockedBtn:SetBackdropColor(C2.row.r, C2.row.g, C2.row.b, C2.row.a)
            BlockedBtn:SetBackdropBorderColor(C2.border.r, C2.border.g, C2.border.b, 1)
        else
            BlockedBtn:SetBackdropColor(C2.accent.r * 0.25, C2.accent.g * 0.25, C2.accent.b * 0.25, 0.9)
            BlockedBtn:SetBackdropBorderColor(C2.accent.r, C2.accent.g, C2.accent.b, 1)
            TrackedBtn:SetBackdropColor(C2.row.r, C2.row.g, C2.row.b, C2.row.a)
            TrackedBtn:SetBackdropBorderColor(C2.border.r, C2.border.g, C2.border.b, 1)
        end
    end
    UpdateViewButtons()

    local ClearBlacklistBtn = CreateModernButton(ListSection, ACO:Translate("CLEAR_BLACKLIST_BTN"), 88, 26, false)
    ClearBlacklistBtn:SetPoint("LEFT", BlockedBtn, "RIGHT", 10, 0)
    ClearBlacklistBtn:SetScript("OnClick", function()
        StaticPopup_Show("ACO_CLEAR_BLACKLIST")
    end)
    ClearBlacklistBtn:SetScript("OnEnter", function(btn)
        btn:SetBackdropColor(C.red.r * 0.3, C.red.g * 0.3, C.red.b * 0.3, 1)
        btn:SetBackdropBorderColor(C.red.r, C.red.g, C.red.b, 1)
        btn.text:SetTextColor(1, 1, 1)
        GameTooltip:SetOwner(btn, "ANCHOR_TOP")
        GameTooltip:AddLine(ACO:Translate("CLEAR_BLACKLIST_T1"), 1, 0.3, 0.3)
        GameTooltip:AddLine(ACO:Translate("CLEAR_BLACKLIST_T2"), 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    ClearBlacklistBtn:SetScript("OnLeave", function(btn)
        btn:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
        btn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
        btn.text:SetTextColor(C.text.r, C.text.g, C.text.b)
        GameTooltip:Hide()
    end)
    ClearBlacklistBtn:Hide()

    TrackedBtn:SetScript("OnClick", function()
        UI.listView = "tracked"
        if ACO.db and ACO.db.ui then ACO.db.ui.listView = "tracked" end
        ClearBlacklistBtn:Hide()
        SearchBox:ClearAllPoints()
        SearchBox:SetPoint("LEFT", BlockedBtn, "RIGHT", 10, 0)
        SearchBox:SetPoint("RIGHT", ListSection, "RIGHT", -PADDING, 0)
        UpdateViewButtons()
        UI:RefreshList()
    end)
    BlockedBtn:SetScript("OnClick", function()
        UI.listView = "blocked"
        if ACO.db and ACO.db.ui then ACO.db.ui.listView = "blocked" end
        ClearBlacklistBtn:Show()
        SearchBox:ClearAllPoints()
        SearchBox:SetPoint("LEFT", ClearBlacklistBtn, "RIGHT", 10, 0)
        SearchBox:SetPoint("RIGHT", ListSection, "RIGHT", -PADDING, 0)
        UpdateViewButtons()
        UI:RefreshList()
    end)

    if UI.listView == "blocked" then
        ClearBlacklistBtn:Show()
        SearchBox:ClearAllPoints()
        SearchBox:SetPoint("LEFT", ClearBlacklistBtn, "RIGHT", 10, 0)
        SearchBox:SetPoint("RIGHT", ListSection, "RIGHT", -PADDING, 0)
    else
        ClearBlacklistBtn:Hide()
        SearchBox:ClearAllPoints()
        SearchBox:SetPoint("LEFT", BlockedBtn, "RIGHT", 10, 0)
        SearchBox:SetPoint("RIGHT", ListSection, "RIGHT", -PADDING, 0)
    end
    UpdateViewButtons()

    -- Column header keeps quantities and estimates out of the item-name area.
    local ColumnHeader = CreateFrame("Frame", nil, ListSection, "BackdropTemplate")
    ColumnHeader:SetHeight(20)
    ColumnHeader:SetPoint("TOPLEFT", PADDING, -70)
    ColumnHeader:SetPoint("TOPRIGHT", -PADDING - 20, -70)
    ApplyBackdrop(ColumnHeader, C.bg, C.border)

    local ContainerHeader = MakeText(ColumnHeader, ACO:Translate("LIST_COL_CONTAINER"), 9, C.textDim)
    ContainerHeader:SetPoint("LEFT", 8, 0)

    local ValueHeader = MakeText(ColumnHeader, ACO:Translate("LIST_COL_AVG_VALUE"), 9, C.textDim)
    ValueHeader:SetWidth(90)
    ValueHeader:SetPoint("RIGHT", -50, 0)
    ValueHeader:SetJustifyH("RIGHT")

    local CountHeader = MakeText(ColumnHeader, ACO:Translate("LIST_COL_IN_BAGS"), 9, C.textDim)
    CountHeader:SetWidth(58)
    CountHeader:SetPoint("RIGHT", ValueHeader, "LEFT", -10, 0)
    CountHeader:SetJustifyH("RIGHT")

    -- Scroll frame
    local ScrollFrame = CreateFrame("ScrollFrame", nil, ListSection, "UIPanelScrollFrameTemplate")
    ScrollFrame:SetPoint("TOPLEFT", PADDING, -94)
    ScrollFrame:SetPoint("BOTTOMRIGHT", -PADDING - 20, 56)

    local ScrollChild = CreateFrame("Frame", nil, ScrollFrame)
    ScrollChild:SetSize(ScrollFrame:GetWidth(), 1)
    ScrollFrame:SetScrollChild(ScrollChild)

    UI.scrollChild = ScrollChild
    UI.listItems = {}

    -- ========================================================================
    -- PER-CONTAINER RULE EDITOR (3.1)
    -- ========================================================================

    local RuleEditor
    function UI:ShowRuleEditor(itemID)
        itemID = tonumber(itemID)
        if not itemID then return end

        if not RuleEditor then
            RuleEditor = CreateFrame("Frame", "ACORuleEditor", MainFrame, "BackdropTemplate")
            RuleEditor:SetSize(500, 430)
            RuleEditor:SetPoint("CENTER", MainFrame, "CENTER", 0, 0)
            RuleEditor:SetFrameLevel(MainFrame:GetFrameLevel() + 40)
            RuleEditor:EnableMouse(true)
            RuleEditor:SetClampedToScreen(true)
            ApplyBackdrop(RuleEditor, C.bg, C.accent)

            local accent = RuleEditor:CreateTexture(nil, "OVERLAY")
            accent:SetHeight(2)
            accent:SetPoint("TOPLEFT", 1, -1)
            accent:SetPoint("TOPRIGHT", -1, -1)
            accent:SetColorTexture(C.accent.r, C.accent.g, C.accent.b, 1)

            local title = MakeText(RuleEditor, ACO:Translate("RULES_TITLE"), 15, C.text)
            title:SetPoint("TOPLEFT", 16, -14)
            RuleEditor.title = title

            local itemName = MakeText(RuleEditor, "", 11, C.accent)
            itemName:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -5)
            itemName:SetPoint("RIGHT", -46, 0)
            itemName:SetJustifyH("LEFT")
            RuleEditor.itemName = itemName

            local close = CreateFrame("Button", nil, RuleEditor)
            close:SetSize(20, 20)
            close:SetPoint("TOPRIGHT", -12, -12)
            local closeTex = close:CreateTexture(nil, "ARTWORK")
            closeTex:SetAllPoints()
            closeTex:SetAtlas("common-search-clearbutton", true)
            close:SetScript("OnClick", function() RuleEditor:Hide() end)

            local auto = CreateModernCheckbox(RuleEditor, ACO:Translate("RULES_AUTO_OPEN"), ACO:Translate("RULES_TOOLTIP"))
            auto:SetPoint("TOPLEFT", 16, -66)
            auto:SetPoint("RIGHT", RuleEditor, "RIGHT", -16, 0)
            RuleEditor.auto = auto.checkbox

            local function CreateRuleField(label, x, y, width, hint)
                local frame = CreateFrame("Frame", nil, RuleEditor)
                frame:SetSize(width, 54)
                frame:SetPoint("TOPLEFT", x, y)
                local labelText = MakeText(frame, label, 10, C.text)
                labelText:SetPoint("TOPLEFT", 0, 0)
                local edit = CreateFrame("EditBox", nil, frame, "BackdropTemplate")
                edit:SetHeight(24)
                edit:SetPoint("TOPLEFT", 0, -20)
                edit:SetPoint("TOPRIGHT", 0, -20)
                ApplyBackdrop(edit, C.row, C.border)
                edit:SetFontObject("GameFontHighlightSmall")
                edit:SetTextInsets(7, 7, 0, 0)
                edit:SetAutoFocus(false)
                edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
                edit:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
                if hint then
                    edit:SetScript("OnEnter", function(self)
                        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                        GameTooltip:SetText(hint, 1, 1, 1, 1, true)
                        GameTooltip:Show()
                    end)
                    edit:SetScript("OnLeave", function() GameTooltip:Hide() end)
                end
                return edit
            end

            RuleEditor.delay = CreateRuleField(ACO:Translate("RULES_DELAY"), 16, -104, 220, ACO:Translate("RULES_DELAY_HINT"))
            RuleEditor.maxSession = CreateRuleField(ACO:Translate("RULES_MAX_SESSION"), 264, -104, 220, ACO:Translate("RULES_MAX_SESSION_HINT"))
            RuleEditor.priority = CreateRuleField(ACO:Translate("RULES_PRIORITY"), 16, -166, 220, ACO:Translate("RULES_PRIORITY_HINT"))
            RuleEditor.tempBlock = CreateRuleField(ACO:Translate("RULES_TEMP_BLOCK"), 264, -166, 220, ACO:Translate("RULES_TEMP_BLOCK_HINT"))
            RuleEditor.source = CreateRuleField(ACO:Translate("RULES_SOURCE"), 16, -228, 468, nil)

            local noteLabel = MakeText(RuleEditor, ACO:Translate("RULES_NOTE"), 10, C.text)
            noteLabel:SetPoint("TOPLEFT", 16, -290)
            local noteBg = CreateFrame("Frame", nil, RuleEditor, "BackdropTemplate")
            noteBg:SetPoint("TOPLEFT", 16, -310)
            noteBg:SetPoint("TOPRIGHT", -16, -310)
            noteBg:SetHeight(54)
            ApplyBackdrop(noteBg, C.row, C.border)
            local note = CreateFrame("EditBox", nil, noteBg)
            note:SetMultiLine(true)
            note:SetFontObject("GameFontHighlightSmall")
            note:SetTextInsets(7, 7, 6, 6)
            note:SetPoint("TOPLEFT", 0, 0)
            note:SetPoint("BOTTOMRIGHT", 0, 0)
            note:SetAutoFocus(false)
            note:SetMaxLetters(240)
            note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
            RuleEditor.note = note

            local diagnostic = MakeText(RuleEditor, "", 9, C.textDim)
            diagnostic:SetPoint("BOTTOMLEFT", 16, 48)
            diagnostic:SetPoint("RIGHT", -16, 0)
            diagnostic:SetJustifyH("LEFT")
            RuleEditor.diagnostic = diagnostic

            local SaveBtn = CreateModernButton(RuleEditor, ACO:Translate("RULES_SAVE"), 104, 28, true)
            SaveBtn:SetPoint("BOTTOMRIGHT", -16, 14)
            local CancelBtn = CreateModernButton(RuleEditor, ACO:Translate("RULES_CANCEL"), 86, 28, false)
            CancelBtn:SetPoint("RIGHT", SaveBtn, "LEFT", -8, 0)
            local ResetBtn = CreateModernButton(RuleEditor, ACO:Translate("RULES_RESET"), 104, 28, false)
            ResetBtn:SetPoint("BOTTOMLEFT", 16, 14)
            local BlockBtn = CreateModernButton(RuleEditor, ACO:Translate("RULES_PERMANENT_BLOCK"), 128, 28, false)
            BlockBtn:SetPoint("LEFT", ResetBtn, "RIGHT", 8, 0)

            CancelBtn:SetScript("OnClick", function() RuleEditor:Hide() end)
            SaveBtn:SetScript("OnClick", function()
                local id = RuleEditor.currentItemID
                if not id then return end
                local delayText = RuleEditor.delay:GetText():match("^%s*(.-)%s*$")
                local tempMinutes = max(0, tonumber(RuleEditor.tempBlock:GetText()) or 0)
                local values = {
                    autoOpen = RuleEditor.auto:GetChecked(),
                    maxPerSession = tonumber(RuleEditor.maxSession:GetText()) or 0,
                    priority = tonumber(RuleEditor.priority:GetText()) or 0,
                    temporaryBlockUntil = tempMinutes > 0 and (time() + floor(tempMinutes * 60)) or 0,
                    source = RuleEditor.source:GetText() or "",
                    note = RuleEditor.note:GetText() or "",
                }
                if delayText == "" then values.clearDelay = true else values.delay = tonumber(delayText) end
                ACO:SetContainerRule(id, values)
                ACO:Print(ACO:Translate("RULES_SAVED", ACO:FormatItemLink(id)))
                RuleEditor:Hide()
            end)
            ResetBtn:SetScript("OnClick", function()
                local id = RuleEditor.currentItemID
                if not id then return end
                ACO:ResetContainerRule(id)
                ACO:Print(ACO:Translate("RULES_RESET_DONE", ACO:FormatItemLink(id)))
                RuleEditor:Hide()
            end)
            BlockBtn:SetScript("OnClick", function()
                local id = RuleEditor.currentItemID
                if not id then return end
                ACO:AddToBlacklist(id)
                ACO.db.containers[id] = nil
                ACO.db.containerRules[id] = nil
                RuleEditor:Hide()
                UI:RefreshList()
            end)
            RuleEditor:Hide()
        end

        local rule = ACO:GetContainerRule(itemID, true)
        RuleEditor.currentItemID = itemID
        local itemLabel = C_Item.GetItemInfo(itemID) or ("Item:" .. tostring(itemID))
        RuleEditor.itemName:SetText(itemLabel .. "  |cff777777(" .. tostring(itemID) .. ")|r")
        RuleEditor.auto:SetChecked(rule.autoOpen ~= false)
        RuleEditor.delay:SetText(rule.delay ~= nil and tostring(rule.delay) or "")
        RuleEditor.maxSession:SetText(tostring(rule.maxPerSession or 0))
        RuleEditor.priority:SetText(tostring(rule.priority or 0))
        local remaining = max(0, (rule.temporaryBlockUntil or 0) - time())
        RuleEditor.tempBlock:SetText(remaining > 0 and tostring(floor((remaining + 59) / 60)) or "0")
        RuleEditor.source:SetText(rule.source or "")
        RuleEditor.note:SetText(rule.note or "")
        local stat = ACO:GetContainerDiagnostic(itemID, false) or { success = 0, failed = 0 }
        local total = (stat.success or 0) + (stat.failed or 0)
        local rate = total > 0 and floor((stat.success or 0) / total * 100 + 0.5) or 0
        RuleEditor.diagnostic:SetText(format(ACO:Translate("RULES_DIAGNOSTIC_FORMAT"), stat.success or 0, stat.failed or 0, rate))
        RuleEditor:Show()
        RuleEditor:Raise()
    end

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
        icon:SetSize(30, 30)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        -- Item name
        local name = MakeText(item, nil, 11, C.text, "LEFT")
        name:SetPoint("LEFT", icon, "RIGHT", 10, 7)
        if name.SetWordWrap then name:SetWordWrap(false) end
        if name.SetNonSpaceWrap then name:SetNonSpaceWrap(false) end
        if name.SetMaxLines then name:SetMaxLines(1) end

        -- Item ID
        local idText = MakeText(item, format(ACO:Translate("ID_LABEL"), itemID), 9, C.textDim)
        idText:SetPoint("LEFT", icon, "RIGHT", 10, -9)
        local itemRule = ACO:GetContainerRule(itemID, false)
        local ruleTag
        if itemRule.autoOpen == false then
            ruleTag = ACO:Translate("RULES_TAG_DISABLED")
        elseif (itemRule.temporaryBlockUntil or 0) > time() then
            ruleTag = ACO:Translate("RULES_TAG_TEMP")
        elseif (itemRule.maxPerSession or 0) > 0 and (ACO.sessionOpenCounts[itemID] or 0) >= itemRule.maxPerSession then
            ruleTag = ACO:Translate("RULES_TAG_LIMIT")
        end
        if ruleTag then
            idText:SetText(format(ACO:Translate("ID_LABEL"), itemID) .. "  |cffffaa00· " .. ruleTag .. "|r")
        end

        -- Remove button
        local removeBtn = CreateFrame("Button", nil, item, "BackdropTemplate")
        removeBtn:SetSize(24, 24)
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

        -- Per-container rule button
        local ruleBtn = CreateFrame("Button", nil, item, "BackdropTemplate")
        ruleBtn:SetSize(24, 24)
        ruleBtn:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
        ApplyBackdrop(ruleBtn, C.row, C.border)
        local ruleIcon = ruleBtn:CreateTexture(nil, "ARTWORK")
        ruleIcon:SetSize(16, 16)
        ruleIcon:SetPoint("CENTER")
        ruleIcon:SetTexture("Interface\\Buttons\\UI-OptionsButton")
        ruleBtn:SetScript("OnClick", function() UI:ShowRuleEditor(itemID) end)
        ruleBtn:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, 1)
            self:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_TOP")
            GameTooltip:SetText(ACO:Translate("RULES_TOOLTIP"), 1, 1, 1, 1, true)
            GameTooltip:Show()
        end)
        ruleBtn:SetScript("OnLeave", function(self)
            self:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
            self:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            GameTooltip:Hide()
        end)

        -- ROI chip: shows average value per open from loot history
        local roiText = MakeText(item, "", 9, C.gold)
        roiText:SetPoint("RIGHT", ruleBtn, "LEFT", -8, 0)
        roiText:SetWidth(90)
        roiText:SetJustifyH("RIGHT")

        local roi = ACO:GetContainerAvgValue(itemID)
        if roi and roi.avgTotal > 0 then
            roiText:SetText(format(ACO:Translate("ROI_AVG"), ACO:FormatMoneyShort(roi.avgTotal)))
        else
            roiText:SetText("—")
            roiText:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        end

        local countText = MakeText(item, "", 12, C.accent)
        countText:SetPoint("RIGHT", roiText, "LEFT", -10, 0)
        countText:SetWidth(58)
        countText:SetJustifyH("RIGHT")
        local bagCount = ACO:CountItemInBags(itemID)
        countText:SetText(bagCount > 0 and ("x" .. bagCount) or "—")
        if bagCount > 0 then
            countText:SetTextColor(C.green.r, C.green.g, C.green.b)
            icon:SetAlpha(1)
        else
            countText:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
            icon:SetAlpha(0.55)
        end

        name:SetPoint("RIGHT", countText, "LEFT", -12, 7)
        idText:SetPoint("RIGHT", countText, "LEFT", -12, -9)
        idText:SetJustifyH("LEFT")

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
            local roiData = ACO:GetContainerAvgValue(itemID)
            if roiData then
                GameTooltip:AddLine(" ")
                GameTooltip:AddLine(ACO:Translate("ROI_TOOLTIP_TITLE"), 0, 0.8, 1)
                GameTooltip:AddLine(format(ACO:Translate("ROI_TOOLTIP_OPENS"), roiData.opens), 0.7, 0.7, 0.7)
                if roiData.avgGold > 0 then
                    GameTooltip:AddLine(format(ACO:Translate("ROI_TOOLTIP_GOLD"), ACO:FormatMoneyShort(roiData.avgGold)), 1, 0.82, 0)
                end
                if roiData.avgVendor > 0 then
                    GameTooltip:AddLine(format(ACO:Translate("ROI_TOOLTIP_VENDOR"), ACO:FormatMoneyShort(roiData.avgVendor)), 0.6, 0.9, 0.6)
                end
                if roiData.avgTotal > 0 then
                    GameTooltip:AddLine(format(ACO:Translate("ROI_TOOLTIP_TOTAL"), ACO:FormatMoneyShort(roiData.avgTotal)), 0, 1, 0.5)
                end
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

    -- ========================================================================
    -- BLACKLIST ITEM ROW
    -- ========================================================================

    local function CreateBlacklistItem(itemID, index)
        local item = CreateFrame("Frame", nil, ScrollChild, "BackdropTemplate")
        item:SetSize(ScrollFrame:GetWidth() - 10, LIST_ITEM_HEIGHT)
        item:SetPoint("TOPLEFT", 0, -(index - 1) * (LIST_ITEM_HEIGHT + 3))

        local isAlt = (index % 2 == 0)
        local rowBg = isAlt and C.rowAlt or C.row
        ApplyBackdrop(item, rowBg, C.border)
        item._isAlt = isAlt

        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(30, 30)
        icon:SetPoint("LEFT", 8, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

        local name = MakeText(item, nil, 11, C.text, "LEFT")
        name:SetPoint("LEFT", icon, "RIGHT", 10, 7)
        name:SetPoint("RIGHT", -48, 7)
        if name.SetWordWrap then name:SetWordWrap(false) end
        if name.SetNonSpaceWrap then name:SetNonSpaceWrap(false) end
        if name.SetMaxLines then name:SetMaxLines(1) end

        local idText = MakeText(item, format(ACO:Translate("ID_LABEL"), itemID), 9, C.textDim)
        idText:SetPoint("LEFT", icon, "RIGHT", 10, -9)

        -- "Auto-blocked" tag
        local tag = MakeText(item, "|cffff6666[Auto]|r", 9, C.text)
        tag:SetPoint("LEFT", idText, "RIGHT", 8, 0)

        -- Unblock button
        local unblockBtn = CreateFrame("Button", nil, item, "BackdropTemplate")
        unblockBtn:SetSize(24, 24)
        unblockBtn:SetPoint("RIGHT", -8, 0)
        ApplyBackdrop(unblockBtn, { r = 0.1, g = 0.3, b = 0.1, a = 0.8 }, C.border)

        local unblockIcon = unblockBtn:CreateTexture(nil, "OVERLAY")
        unblockIcon:SetSize(12, 12)
        unblockIcon:SetPoint("CENTER")
        unblockIcon:SetAtlas("common-icon-checkmark")

        unblockBtn:SetScript("OnEnter", function(btn)
            btn:SetBackdropColor(0.1, 0.5, 0.1, 1)
            btn:SetBackdropBorderColor(0.2, 0.8, 0.2, 1)
            GameTooltip:SetOwner(btn, "ANCHOR_TOP")
            GameTooltip:SetText(ACO:Translate("BLACKLIST_UNBLOCK_TOOLTIP"))
            GameTooltip:Show()
        end)
        unblockBtn:SetScript("OnLeave", function(btn)
            btn:SetBackdropColor(0.1, 0.3, 0.1, 0.8)
            btn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            GameTooltip:Hide()
        end)
        unblockBtn:SetScript("OnClick", function()
            ACO:RemoveFromBlacklist(itemID)
            UI:RefreshList()
        end)

        -- Load item info
        local itemInfo = C_Item.GetItemInfo(itemID)
        if itemInfo then
            name:SetText(itemInfo)
            local itemIcon = C_Item.GetItemIconByID(itemID)
            if itemIcon then icon:SetTexture(itemIcon) end
        else
            name:SetText(ACO:Translate("LOADING"))
            icon:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark")
            local item_obj = Item:CreateFromItemID(itemID)
            item_obj:ContinueOnItemLoad(function()
                local n = C_Item.GetItemInfo(itemID)
                local ic = C_Item.GetItemIconByID(itemID)
                if n then name:SetText(n) end
                if ic then icon:SetTexture(ic) end
            end)
        end

        item:SetScript("OnEnter", function(row)
            row:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            row:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
            GameTooltip:SetOwner(row, "ANCHOR_CURSOR")
            GameTooltip:SetHyperlink("item:" .. itemID)
            GameTooltip:Show()
        end)
        item:SetScript("OnLeave", function(row)
            local bg = row._isAlt and C.rowAlt or C.row
            row:SetBackdropColor(bg.r, bg.g, bg.b, bg.a)
            row:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            GameTooltip:Hide()
        end)

        return item
    end

    -- ========================================================================
    -- REFRESH LIST FUNCTION (handles Tracked / Blocked views + search filter)
    -- ========================================================================

    function UI:RefreshList()
        for _, item in ipairs(self.listItems) do
            item:Hide()
            item:SetParent(nil)
        end
        wipe(self.listItems)

        local isBlocked = (self.listView == "blocked")
        local source = isBlocked and ACO.db.blacklist or ACO.db.containers
        local filter = self.searchFilterText or ""

        local ids = {}
        for itemID in pairs(source) do
            tinsert(ids, tonumber(itemID) or itemID)
        end
        table.sort(ids, function(a, b)
            local nameA = C_Item.GetItemInfo(a) or tostring(a)
            local nameB = C_Item.GetItemInfo(b) or tostring(b)
            nameA, nameB = nameA:lower(), nameB:lower()
            if nameA == nameB then return tonumber(a) < tonumber(b) end
            return nameA < nameB
        end)

        local index = 1
        for _, itemID in ipairs(ids) do
            local show = true
            if filter ~= "" then
                local idStr = tostring(itemID)
                local itemName = (C_Item.GetItemInfo and C_Item.GetItemInfo(itemID) or ""):lower()
                if not itemName:find(filter, 1, true) and not idStr:find(filter, 1, true) then
                    show = false
                end
            end

            if show then
                local listItem = isBlocked and CreateBlacklistItem(itemID, index) or CreateListItem(itemID, index)
                tinsert(self.listItems, listItem)
                index = index + 1
            end
        end

        ScrollChild:SetHeight(max(1, (index - 1) * (LIST_ITEM_HEIGHT + 3)))

        local count = index - 1
        if isBlocked then
            self.listCount:SetText(format(ACO:Translate("LIST_BLOCKED_COUNT"), count))
        else
            local suffix = count > 1 and "s" or ""
            self.listCount:SetText(ACO:Translate("LIST_COUNT", count, suffix))
        end
    end

    -- ========================================================================
    -- PENDING / QUEUE CENTER TAB (3.1)
    -- ========================================================================

    local PendingSection = CreateFrame("Frame", nil, PendingContent, "BackdropTemplate")
    PendingSection:SetPoint("TOPLEFT", PADDING, -PADDING)
    PendingSection:SetPoint("BOTTOMRIGHT", -PADDING, PADDING)
    ApplyBackdrop(PendingSection, C.row, C.border)

    local PendingTitle = MakeText(PendingSection, ACO:Translate("QUEUE_CENTER_TITLE"), 14, C.text)
    PendingTitle:SetPoint("TOPLEFT", PADDING, -PADDING)

    local PendingHint = MakeText(PendingSection, ACO:Translate("QUEUE_CENTER_HINT"), 10, C.textDim)
    PendingHint:SetPoint("TOPLEFT", PendingTitle, "BOTTOMLEFT", 0, -4)
    PendingHint:SetPoint("RIGHT", PendingSection, "RIGHT", -PADDING, 0)
    PendingHint:SetJustifyH("LEFT")

    local ModeAutoBtn = CreateModernButton(PendingSection, ACO:Translate("QUEUE_MODE_AUTO"), 96, 26, true)
    ModeAutoBtn:SetPoint("TOPLEFT", PADDING, -52)
    local ModeAssistedBtn = CreateModernButton(PendingSection, ACO:Translate("QUEUE_MODE_ASSISTED"), 96, 26, false)
    ModeAssistedBtn:SetPoint("LEFT", ModeAutoBtn, "RIGHT", 6, 0)

    local PauseQueueBtn = CreateModernButton(PendingSection, ACO:Translate("QUEUE_PAUSE"), 84, 26, false)
    PauseQueueBtn:SetPoint("LEFT", ModeAssistedBtn, "RIGHT", 14, 0)

    local OpenNextBtn = CreateModernButton(PendingSection, ACO:Translate("QUEUE_OPEN_NEXT"), 116, 26, true)
    OpenNextBtn:SetPoint("LEFT", PauseQueueBtn, "RIGHT", 6, 0)

    local AssistedOpenBtn = CreateFrame("Button", "ACOAssistedOpenButton", PendingSection, "SecureActionButtonTemplate,BackdropTemplate")
    AssistedOpenBtn:SetSize(136, 26)
    AssistedOpenBtn:SetPoint("LEFT", PauseQueueBtn, "RIGHT", 6, 0)
    AssistedOpenBtn:RegisterForClicks("LeftButtonUp")
    ApplyBackdrop(AssistedOpenBtn, { r = C.accent.r * 0.30, g = C.accent.g * 0.30, b = C.accent.b * 0.30, a = 0.95 }, C.accent)
    local AssistedOpenText = MakeText(AssistedOpenBtn, ACO:Translate("QUEUE_OPEN_NEXT"), 11, C.text)
    AssistedOpenText:SetPoint("CENTER")
    AssistedOpenBtn.text = AssistedOpenText
    AssistedOpenBtn:Hide()

    local ClearQueueBtn = CreateModernButton(PendingSection, ACO:Translate("QUEUE_CLEAR"), 96, 26, false)
    ClearQueueBtn:SetPoint("TOPRIGHT", -PADDING, -52)
    local ClearFailuresBtn = CreateModernButton(PendingSection, ACO:Translate("QUEUE_CLEAR_FAILURES"), 110, 26, false)
    ClearFailuresBtn:SetPoint("RIGHT", ClearQueueBtn, "LEFT", -6, 0)

    local QueueStatusText = MakeText(PendingSection, "", 10, C.textDim)
    QueueStatusText:SetPoint("TOPLEFT", PADDING, -84)
    QueueStatusText:SetPoint("RIGHT", PendingSection, "RIGHT", -PADDING, 0)
    QueueStatusText:SetJustifyH("LEFT")

    local PendingHeader = CreateFrame("Frame", nil, PendingSection, "BackdropTemplate")
    PendingHeader:SetHeight(20)
    PendingHeader:SetPoint("TOPLEFT", PADDING, -104)
    PendingHeader:SetPoint("TOPRIGHT", -PADDING - 20, -104)
    ApplyBackdrop(PendingHeader, C.bg, C.border)
    local PendingHeaderName = MakeText(PendingHeader, ACO:Translate("LIST_COL_CONTAINER"), 9, C.textDim)
    PendingHeaderName:SetPoint("LEFT", 10, 0)
    local PendingHeaderStatus = MakeText(PendingHeader, ACO:Translate("QUEUE_STATUS_QUEUED"), 9, C.textDim)
    PendingHeaderStatus:SetPoint("RIGHT", -118, 0)

    local PendingScroll = CreateFrame("ScrollFrame", nil, PendingSection, "UIPanelScrollFrameTemplate")
    PendingScroll:SetPoint("TOPLEFT", PADDING, -128)
    PendingScroll:SetPoint("BOTTOMRIGHT", -PADDING - 20, PADDING)

    local PendingScrollChild = CreateFrame("Frame", nil, PendingScroll)
    PendingScrollChild:SetSize(PendingScroll:GetWidth(), 1)
    PendingScroll:SetScrollChild(PendingScrollChild)

    UI.pendingListItems = {}
    UI.assistedButtons = UI.assistedButtons or {}
    tinsert(UI.assistedButtons, AssistedOpenBtn)

    local function GetQueueStatusPresentation(status)
        local labels = {
            QUEUED = "QUEUE_STATUS_QUEUED",
            DELAY = "QUEUE_STATUS_DELAY",
            BLOCKED = "QUEUE_STATUS_BLOCKED",
            OPENING = "QUEUE_STATUS_OPENING",
            VERIFYING = "QUEUE_STATUS_VERIFYING",
            RETRYING = "QUEUE_STATUS_RETRYING",
            FAILED = "QUEUE_STATUS_FAILED",
            PAUSED = "QUEUE_STATUS_PAUSED",
            ASSISTED_READY = "QUEUE_STATUS_ASSISTED_READY",
            DONE = "QUEUE_STATUS_DONE",
        }
        local colors = {
            QUEUED = C.accent,
            DELAY = C.textDim,
            BLOCKED = C.red,
            OPENING = C.green,
            VERIFYING = C.gold,
            RETRYING = C.orange,
            FAILED = C.red,
            PAUSED = C.orange,
            ASSISTED_READY = C.green,
            DONE = C.green,
        }
        return ACO:Translate(labels[status] or "QUEUE_STATUS_QUEUED"), colors[status] or C.text
    end

    function UI:ConfigureAssistedButtons(entry)
        if not self.assistedButtons then return end
        for _, button in ipairs(self.assistedButtons) do
            if InCombatLockdown and InCombatLockdown() then
                button:Disable()
                button:SetAlpha(0.45)
            elseif entry and entry.itemID then
                button._acoQueueID = entry.queueID
                button:SetAttribute("type", "item")
                button:SetAttribute("item", "item:" .. tostring(entry.itemID))
                button:SetAttribute("macrotext", nil)
                button:Enable()
                button:SetAlpha(1)
                if button.text then button.text:SetText(ACO:Translate("QUEUE_OPEN_NEXT")) end
            else
                button._acoQueueID = nil
                button:SetAttribute("type", nil)
                button:SetAttribute("item", nil)
                button:SetAttribute("macrotext", nil)
                button:Disable()
                button:SetAlpha(0.45)
                if button.text then button.text:SetText(ACO:Translate("QUEUE_OPEN_NEXT")) end
            end
        end
    end

    AssistedOpenBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._acoPrepared = self._acoQueueID and ACO:PrepareAssistedClick(self._acoQueueID) or false
        end
    end)
    AssistedOpenBtn:SetScript("PostClick", function(self)
        local queueID = self._acoQueueID
        self:Disable()
        self:SetAlpha(0.45)
        if queueID and self._acoPrepared then
            C_Timer.After(0, function() ACO:CompleteAssistedClick(queueID) end)
        end
        self._acoPrepared = nil
    end)
    AssistedOpenBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.accent.r * 0.45, C.accent.g * 0.45, C.accent.b * 0.45, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("QUEUE_ASSISTED_HELP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    AssistedOpenBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.accent.r * 0.30, C.accent.g * 0.30, C.accent.b * 0.30, 0.95)
        GameTooltip:Hide()
    end)

    function UI:UpdateQueueModeControls()
        local assisted = ACO:GetQueueMode() == "assisted"
        if assisted then
            ModeAssistedBtn:SetBackdropColor(C.accent.r * 0.25, C.accent.g * 0.25, C.accent.b * 0.25, 0.9)
            ModeAssistedBtn:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
            ModeAutoBtn:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
            ModeAutoBtn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            OpenNextBtn:Hide()
            AssistedOpenBtn:Show()
            self:ConfigureAssistedButtons(ACO.assistedEntry)
        else
            ModeAutoBtn:SetBackdropColor(C.accent.r * 0.25, C.accent.g * 0.25, C.accent.b * 0.25, 0.9)
            ModeAutoBtn:SetBackdropBorderColor(C.accent.r, C.accent.g, C.accent.b, 1)
            ModeAssistedBtn:SetBackdropColor(C.row.r, C.row.g, C.row.b, C.row.a)
            ModeAssistedBtn:SetBackdropBorderColor(C.border.r, C.border.g, C.border.b, 1)
            AssistedOpenBtn:Hide()
            OpenNextBtn:Show()
        end
        PauseQueueBtn.text:SetText(ACO.queuePaused and ACO:Translate("QUEUE_RESUME") or ACO:Translate("QUEUE_PAUSE"))
    end

    ModeAutoBtn:SetScript("OnClick", function() ACO:SetQueueMode("auto") end)
    ModeAssistedBtn:SetScript("OnClick", function() ACO:SetQueueMode("assisted") end)
    ModeAutoBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("QUEUE_MODE_AUTO_TIP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ModeAutoBtn:SetScript("OnLeave", function() GameTooltip:Hide() UI:UpdateQueueModeControls() end)
    ModeAssistedBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("QUEUE_MODE_ASSISTED_TIP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    ModeAssistedBtn:SetScript("OnLeave", function() GameTooltip:Hide() UI:UpdateQueueModeControls() end)

    PauseQueueBtn:SetScript("OnClick", function()
        if ACO.queuePaused then ACO:ResumeQueue() else ACO:PauseQueue() end
        UI:UpdateQueueModeControls()
    end)
    OpenNextBtn:SetScript("OnClick", function() ACO:OpenNextQueueEntry() end)
    ClearQueueBtn:SetScript("OnClick", function() ACO:CancelQueue(false) end)
    ClearFailuresBtn:SetScript("OnClick", function() ACO:ClearQueueFailures() end)

    local function CreatePendingItem(entry, index)
        local rowHeight = 58
        local item = CreateFrame("Frame", nil, PendingScrollChild, "BackdropTemplate")
        item:SetHeight(rowHeight)
        item:SetPoint("TOPLEFT", 0, -(index - 1) * (rowHeight + 3))
        item:SetPoint("TOPRIGHT", -8, -(index - 1) * (rowHeight + 3))

        local isAlt = index % 2 == 0
        ApplyBackdrop(item, isAlt and C.rowAlt or C.row, C.border)
        item._isAlt = isAlt

        local icon = item:CreateTexture(nil, "ARTWORK")
        icon:SetSize(34, 34)
        icon:SetPoint("LEFT", 9, 0)
        icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)
        icon:SetTexture((C_Item.GetItemIconByID and C_Item.GetItemIconByID(entry.itemID)) or "Interface\\Icons\\INV_Misc_QuestionMark")

        local link = entry.link or ACO:FormatItemLink(entry.itemID)
        local itemName = link and link:match("%[(.-)%]")
        if not itemName and C_Item.GetItemNameByID then itemName = C_Item.GetItemNameByID(entry.itemID) end

        local name = MakeText(item, itemName or ("Item:" .. tostring(entry.itemID)), 11, C.text, "LEFT")
        name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 10, -4)
        name:SetPoint("RIGHT", item, "RIGHT", -230, 0)
        if name.SetWordWrap then name:SetWordWrap(false) end
        if name.SetMaxLines then name:SetMaxLines(1) end

        local statusLabel, statusColor = GetQueueStatusPresentation(entry.status)
        local eta = entry.eta and entry.eta > 0.05 and format("%.1fs", entry.eta) or "—"
        local detail = MakeText(item, format(ACO:Translate("QUEUE_STATUS_FORMAT"), statusLabel, entry.attempt or 0, eta), 9, C.textDim, "LEFT")
        detail:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 10, 4)
        detail:SetPoint("RIGHT", item, "RIGHT", -230, 0)
        if entry.reason then
            detail:SetText(detail:GetText() .. " · " .. ACO:GetQueueReasonText(entry.reason))
        end

        local status = MakeText(item, statusLabel, 10, statusColor, "RIGHT")
        status:SetWidth(102)
        status:SetPoint("RIGHT", item, "RIGHT", -112, 0)

        local removeBtn = CreateModernButton(item, ACO:Translate("QUEUE_REMOVE"), 74, 24, false)
        removeBtn:SetPoint("RIGHT", -8, 0)
        removeBtn:SetScript("OnClick", function() ACO:RemoveQueueEntry(entry.queueID) end)
        if entry.active then
            removeBtn:Disable()
            removeBtn:SetAlpha(0.4)
        end

        if entry.failed then
            local retryBtn = CreateModernButton(item, ACO:Translate("QUEUE_RETRY"), 72, 24, true)
            retryBtn:SetPoint("RIGHT", removeBtn, "LEFT", -6, 0)
            retryBtn:SetScript("OnClick", function() ACO:RetryFailedQueueEntry(entry.queueID) end)
            status:ClearAllPoints()
            status:SetPoint("RIGHT", retryBtn, "LEFT", -8, 0)
        end

        item:SetScript("OnEnter", function(self)
            self:SetBackdropColor(C.rowHover.r, C.rowHover.g, C.rowHover.b, C.rowHover.a)
            self:SetBackdropBorderColor(C.borderLight.r, C.borderLight.g, C.borderLight.b, 1)
            GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
            GameTooltip:SetHyperlink("item:" .. tostring(entry.itemID))
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

    local EmptyQueueText = MakeText(PendingScrollChild, ACO:Translate("QUEUE_EMPTY"), 11, C.textDim)
    EmptyQueueText:SetPoint("TOP", PendingScrollChild, "TOP", 0, -24)
    EmptyQueueText:Hide()

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

        local snapshot = ACO:GetQueueSnapshot()
        local index = 1
        for _, entry in ipairs(snapshot) do
            local listItem = CreatePendingItem(entry, index)
            tinsert(self.pendingListItems, listItem)
            index = index + 1
        end
        local count = index - 1
        EmptyQueueText:SetShown(count == 0)
        PendingScrollChild:SetHeight(max(1, count * 61))

        local blocked, reason = ACO:IsOpeningBlocked()
        local modeText = ACO:GetQueueMode() == "assisted" and ACO:Translate("QUEUE_MODE_ASSISTED") or ACO:Translate("QUEUE_MODE_AUTO")
        if ACO.queuePaused then
            QueueStatusText:SetText(modeText .. " · " .. ACO:Translate("QUEUE_STATUS_PAUSED"))
            QueueStatusText:SetTextColor(C.orange.r, C.orange.g, C.orange.b)
        elseif blocked then
            QueueStatusText:SetText(modeText .. " · " .. ACO:Translate("QUEUE_STATUS_BLOCKED") .. ": " .. ACO:GetBlockReasonText(reason))
            QueueStatusText:SetTextColor(C.red.r, C.red.g, C.red.b)
        elseif ACO.assistedEntry then
            QueueStatusText:SetText(modeText .. " · " .. ACO:Translate("QUEUE_ASSISTED_HELP"))
            QueueStatusText:SetTextColor(C.green.r, C.green.g, C.green.b)
        else
            QueueStatusText:SetText(modeText .. " · " .. tostring(#ACO.openQueue) .. " + " .. tostring(ACO.pendingVerifications or 0))
            QueueStatusText:SetTextColor(C.textDim.r, C.textDim.g, C.textDim.b)
        end
        self:UpdateQueueModeControls()
    end

    local pendingRefreshElapsed = 0
    PendingContent:SetScript("OnUpdate", function(_, elapsed)
        pendingRefreshElapsed = pendingRefreshElapsed + elapsed
        if pendingRefreshElapsed >= 0.75 then
            pendingRefreshElapsed = 0
            UI:RefreshPendingList()
        end
    end)
    UI:UpdateQueueModeControls()

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
        nameText:SetWidth(155)

        local countText = MakeText(itemFrame, nil, 11, C.green)
        countText:SetPoint("RIGHT", -10, 0)

        local valueText = MakeText(itemFrame, "", 10, C.gold)
        valueText:SetPoint("RIGHT", countText, "LEFT", -10, 0)

        itemFrame.rank = rankText
        itemFrame.icon = icon
        itemFrame.name = nameText
        itemFrame.count = countText
        itemFrame.value = valueText
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

                local roi = ACO:GetContainerAvgValue(item.itemID)
                if roi and roi.avgTotal > 0 then
                    frame.value:SetText(format(ACO:Translate("ROI_AVG"), ACO:FormatMoneyShort(roi.avgTotal)))
                else
                    frame.value:SetText("")
                end

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
                frame.value:SetText("")
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

    StaticPopupDialogs["ACO_CLEAR_BLACKLIST"] = {
        text = ACO:Translate("POPUP_CLEAR_BLACKLIST_TEXT"),
        button1 = ACO:Translate("POPUP_YES"),
        button2 = ACO:Translate("POPUP_NO"),
        OnAccept = function()
            ACO:ClearBlacklist()
            UI:RefreshList()
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
            self:RefreshKPI()
        end
    end

    function UI:Show()
        MainFrame:Show()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPEN)
        self:SwitchTab(self.currentTab or "containers")
        self:RefreshKPI()
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

    MainFrame:HookScript("OnHide", SaveFrameState)
    UI.kpiTicker = C_Timer.NewTicker(0.5, function()
        if MainFrame:IsShown() then
            UI:RefreshKPI()
        end
    end)

    -- ESC to close
    table.insert(UISpecialFrames, "AutoChestOpenerFrame")

    -- Initial refresh
    C_Timer.After(0.2, function()
        UI:SwitchTab(UI.currentTab or "containers")
        UI:RefreshList()
        UI:RefreshKPI()
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

    -- Position — radius adapts to the actual minimap size (supports 110%+ resized minimaps)
    local function GetMinimapRadius()
        local w = Minimap:GetWidth()
        return ((w and w > 0) and w or 140) / 2 + 5
    end

    local angle = math.rad(220)
    local radius = GetMinimapRadius()
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
            local r = GetMinimapRadius()
            local x = cos(a) * r
            local y = sin(a) * r

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

    -- Assisted mode uses a real visible SecureActionButton. It replaces the
    -- progress bar while a protected item is waiting for a hardware click.
    local qwAssistedBtn = CreateFrame("Button", "ACOQueueAssistedOpenButton", QueueWidget, "SecureActionButtonTemplate,BackdropTemplate")
    qwAssistedBtn:SetHeight(26)
    qwAssistedBtn:SetPoint("BOTTOMLEFT", 10, 8)
    qwAssistedBtn:SetPoint("BOTTOMRIGHT", -10, 8)
    qwAssistedBtn:RegisterForClicks("LeftButtonUp")
    ApplyBackdrop(qwAssistedBtn, { r = C.accent.r * 0.30, g = C.accent.g * 0.30, b = C.accent.b * 0.30, a = 0.95 }, C.accent)
    local qwAssistedText = MakeText(qwAssistedBtn, ACO:Translate("QUEUE_OPEN_NEXT"), 11, C.text)
    qwAssistedText:SetPoint("CENTER")
    qwAssistedBtn.text = qwAssistedText
    qwAssistedBtn:Hide()
    UI.assistedButtons = UI.assistedButtons or {}
    tinsert(UI.assistedButtons, qwAssistedBtn)

    qwAssistedBtn:SetScript("OnMouseDown", function(self, button)
        if button == "LeftButton" then
            self._acoPrepared = self._acoQueueID and ACO:PrepareAssistedClick(self._acoQueueID) or false
        end
    end)
    qwAssistedBtn:SetScript("PostClick", function(self)
        local queueID = self._acoQueueID
        self:Disable()
        self:SetAlpha(0.45)
        if queueID and self._acoPrepared then C_Timer.After(0, function() ACO:CompleteAssistedClick(queueID) end) end
        self._acoPrepared = nil
    end)
    qwAssistedBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(C.accent.r * 0.45, C.accent.g * 0.45, C.accent.b * 0.45, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("QUEUE_ASSISTED_HELP"), 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    qwAssistedBtn:SetScript("OnLeave", function(self)
        self:SetBackdropColor(C.accent.r * 0.30, C.accent.g * 0.30, C.accent.b * 0.30, 0.95)
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
        local assistedMode = ACO:GetQueueMode() == "assisted"
        if assistedMode then
            qwBarBg:Hide()
            qwAssistedBtn:Show()
            if UI.ConfigureAssistedButtons then UI:ConfigureAssistedButtons(ACO.assistedEntry) end
        else
            qwAssistedBtn:Hide()
            qwBarBg:Show()
        end

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
            elseif assistedMode and ACO.assistedEntry and ACO.assistedEntry.queueID == entry.queueID then
                qwTimer:SetText(ACO:Translate("QUEUE_STATUS_ASSISTED_READY"))
                qwTimer:SetTextColor(C.green.r, C.green.g, C.green.b)
            elseif waitTime > 0.1 then
                qwTimer:SetText(format("%.1fs", waitTime))
                qwTimer:SetTextColor(C.accent.r, C.accent.g, C.accent.b)
            else
                qwTimer:SetText(assistedMode and ACO:Translate("QUEUE_STATUS_QUEUED") or ACO:Translate("QUEUE_OPENING"))
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
