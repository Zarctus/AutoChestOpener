--[[
    Auto Chest Opener - Core Module
    Automatically opens all types of containers, chests, bags, crates, lockboxes, gifts and more
    Version: 3.1.1
]]

local addonName, ACO = ...

-- ============================================================================
-- LOCAL UPVALUES (Performance Optimization)
-- ============================================================================

local pairs, ipairs, type = pairs, ipairs, type
local tonumber, tostring = tonumber, tostring
local format, lower, match, gmatch = string.format, string.lower, string.match, string.gmatch
local tinsert, tremove, wipe = table.insert, table.remove, wipe
local floor, max, min = math.floor, math.max, math.min
local time, date = time, date

-- WoW API globals that are frequently called
local GetTime = GetTime

-- WoW API upvalues
local C_Container = C_Container
local C_Item = C_Item
local C_Timer = C_Timer
local CreateFrame = CreateFrame
local InCombatLockdown = InCombatLockdown
local PlaySound = PlaySound
local GetCursorInfo = GetCursorInfo
local ClearCursor = ClearCursor
local CopyTable = CopyTable
local strsplit = strsplit
local GetMoney = GetMoney
local UnitName = UnitName
local Item = Item
local issecretvalue = issecretvalue

-- Retail 12.1 extends secret-value protections to more UI/API paths.
-- Auto Chest Opener does not consume aura/combat secrets, but tooltip and money
-- values are treated defensively so a future secret value is never coerced,
-- compared, concatenated, or used in arithmetic by insecure addon code.
local function IsAccessibleValue(value)
    if value == nil then return false end
    if issecretvalue and issecretvalue(value) then return false end
    return true
end

-- ============================================================================
-- SECURE ACTION BUTTON (Midnight 12.0+ compatibility)
-- UseContainerItem is now protected; we use SecureActionButtonTemplate
-- with type="item" to open containers via a programmatic secure click.
-- ============================================================================

local secureBtn = CreateFrame("Button", "ACOSecureOpenButton", UIParent, "SecureActionButtonTemplate")
secureBtn:SetSize(1, 1)
secureBtn:SetPoint("TOPLEFT", UIParent, "TOPLEFT", -100, 100)
secureBtn:Hide()
secureBtn:RegisterForClicks("AnyUp", "AnyDown")

-- ============================================================================
-- ADDON INITIALIZATION
-- ============================================================================

ACO.name = addonName
-- Try to read version from the AddOn TOC metadata (## Version:)
local tocVersion = (C_AddOns and C_AddOns.GetAddOnMetadata and C_AddOns.GetAddOnMetadata(addonName, "Version")) or nil
-- If packaged with a tool, the TOC can contain a placeholder like "@project-version@".
-- Treat it as invalid and fallback to the hardcoded version.
if tocVersion == "@project-version@" then
    tocVersion = nil
end
ACO.version = (tocVersion and tocVersion ~= "") and tocVersion or "3.1.1"
ACO.pendingItems = {}
ACO.itemQueue = {}
ACO.goldTracker = {
    isTracking = false,
    goldBefore = 0,
    pendingItemID = nil,
}
ACO.goldTrackerQueue = {} -- queue-based gold tracking for batch openings
ACO.lootTrackerQueue = {} -- queue-based loot tracking for content capture

-- Centralized open queue worker
ACO.openQueue = {}
ACO.queueTicker = nil
ACO.queueNextAllowedAt = 0
ACO.queueOpenInterval = 0.25 -- seconds between uses to avoid server/UI spam

-- Batch opening summary tracker
ACO.batchTracker = {
    active = false,
    count = 0,
    totalQueued = 0,
    goldBefore = 0,
    startTime = 0,
}
ACO.queuePaused = false
ACO.queueSessionOpened = 0
ACO.pendingVerifications = 0
ACO.queueGeneration = 0
ACO.queueSequence = 0
ACO.activeVerifications = {} -- [queueID] = entry currently awaiting confirmation
ACO.queueFailures = {}       -- session-only failures displayed in the queue center
ACO.assistedEntry = nil      -- queue entry currently prepared for a real hardware click
ACO.sessionOpenCounts = {}   -- [itemID] = confirmed opens during this login session

-- Combat deferral (itemID -> count)
ACO.combatQueue = {}

-- Item data async (évite de rater certains conteneurs si les données de l'objet ne sont pas encore en cache)
ACO.pendingItemLoads = {}      -- [itemID] = true si un callback de chargement est en cours
ACO.pendingContainerGains = {} -- [itemID] = { count=, link=, bag=, slot=, firstSeen=, lastSeen= }

-- UI / Interaction blockers (to prevent accidental selling/moving items instead of opening)
-- When any of these is true, the open queue worker pauses and resumes automatically.
ACO.blockers = {
    merchant = false,
    trade = false,
    auction = false,
    bank = false,
    mail = false,
    guildbank = false,
    voidstorage = false,
    loot = false,
    scrapping = false,
}

function ACO:SetBlocker(name, state)
    if not name then return end
    if not self.blockers then self.blockers = {} end
    local old = self.blockers[name]
    if old == state then return end
    self.blockers[name] = state and true or false

    if self.db and self.db.debugMode then
        self:Debug(("Blocker '%s' -> %s"):format(tostring(name), tostring(self.blockers[name])))
    end

    -- When something closes, try to resume quickly (ProcessQueueTick will still re-check blockers).
    if not self.blockers[name] then
        self.queueNextAllowedAt = 0
        self:StartQueueWorker()
    end
end

function ACO:IsOpeningBlocked()
    -- Combat first (hard block)
    if InCombatLockdown and InCombatLockdown() then
        return true, "COMBAT"
    end

    -- Cursor: if player has an item on cursor, using containers could interact
    if GetCursorInfo and GetCursorInfo() then
        return true, "CURSOR"
    end

    local b = self.blockers or {}

    -- Merchant: right-click/use can SELL items
    if b.merchant or (MerchantFrame and MerchantFrame:IsShown()) then
        return true, "MERCHANT"
    end

    -- Trade: right-click/use can MOVE items into trade window
    if b.trade or (TradeFrame and TradeFrame:IsShown()) then
        return true, "TRADE"
    end

    -- Auction House
    if b.auction or (AuctionHouseFrame and AuctionHouseFrame:IsShown()) then
        return true, "AUCTION"
    end

    -- Mail (+ TSM compatibility)
    local mailFrameVisible = MailFrame and MailFrame:IsShown()
    local tsmMailVisible = false
    -- Modern TSM exposes TSM_API.IsUIVisible; legacy TSM used a global frame
    local tsmAPI = rawget(_G, "TSM_API")
    if tsmAPI and tsmAPI.IsUIVisible then
        tsmMailVisible = tsmAPI.IsUIVisible("MAILING")
    else
        local tsmMail = rawget(_G, "TSM_MailingFrame")
        if tsmMail and tsmMail.IsShown then
            tsmMailVisible = tsmMail:IsShown()
        end
    end
    if mailFrameVisible or tsmMailVisible then
        return true, "MAIL"
    end
    -- Auto-clear stale mail blocker: if the flag was set but no mail frame is
    -- actually visible, TSM (or another addon) likely closed the mailbox
    -- without MAIL_CLOSED reaching us.  Clear it so items are not stuck.
    if b.mail then
        self:SetBlocker("mail", false)
        if self.db and self.db.debugMode then
            self:Debug("Auto-cleared stale 'mail' blocker (no mail frame visible)")
        end
    end

    -- Bank
    if b.bank or (BankFrame and BankFrame:IsShown()) then
        return true, "BANK"
    end

    -- Guild Bank (may not exist on all builds)
    local gbFrame = rawget(_G, "GuildBankFrame")
    if b.guildbank or (gbFrame and gbFrame.IsShown and gbFrame:IsShown()) then
        return true, "GUILDBANK"
    end

    -- Void Storage
    local vsFrame = rawget(_G, "VoidStorageFrame")
    if b.voidstorage or (vsFrame and vsFrame.IsShown and vsFrame:IsShown()) then
        return true, "VOIDSTORAGE"
    end

    -- Loot window
    if b.loot or (LootFrame and LootFrame:IsShown()) then
        return true, "LOOT"
    end

    -- Scrapping machine
    local scrappingFrame = rawget(_G, "ScrappingMachineFrame")
    if b.scrapping or (scrappingFrame and scrappingFrame.IsShown and scrappingFrame:IsShown()) then
        return true, "SCRAPPING"
    end

    return false, nil
end

-- Human-readable / localized reason for blockers (used in notifications)
function ACO:GetBlockReasonText(reason)
    if not reason then
        return ACO:Translate("BLOCK_REASON_UNKNOWN")
    end

    local map = {
        COMBAT = "BLOCK_REASON_COMBAT",
        CURSOR = "BLOCK_REASON_CURSOR",
        MERCHANT = "BLOCK_REASON_MERCHANT",
        TRADE = "BLOCK_REASON_TRADE",
        AUCTION = "BLOCK_REASON_AUCTION",
        MAIL = "BLOCK_REASON_MAIL",
        BANK = "BLOCK_REASON_BANK",
        GUILDBANK = "BLOCK_REASON_GUILDBANK",
        VOIDSTORAGE = "BLOCK_REASON_VOIDSTORAGE",
        LOOT = "BLOCK_REASON_LOOT",
        SCRAPPING = "BLOCK_REASON_SCRAPPING",
    }

    local key = map[reason]
    if key then
        return ACO:Translate(key)
    end

    return tostring(reason)
end

-- Incremental bag tracking (robust new-item detection + targeted scans)
ACO.dirtyBags = {}
ACO.scanScheduled = false
ACO.lastBagCountsByBag = {} -- [bagID] = { [itemID] = totalCountInBag }
ACO.bagSlotsByBag = {}      -- [bagID] = { [itemID] = { {slot=, hyperlink=}... } }

-- Default settings
ACO.DB_SCHEMA_VERSION = 4
ACO.SUPPORTED_INTERFACE = 120100

local defaults = {
    schemaVersion = ACO.DB_SCHEMA_VERSION,
    enabled = true,
    delay = 3, -- Delay in seconds before opening
    showNotifications = true,
    notificationSound = true,
    debugMode = false,
    containers = {},         -- User-added container IDs
    blacklist = {},          -- Items to never auto-open
    containerRules = {},     -- [itemID] = per-container opening policy
    containerStats = {},     -- [itemID] = success/failure diagnostics
    autoDiscovery = true,    -- Auto-detect containers when manually opened
    autoOpenOnLogin = false, -- Automatically open all tracked containers on login/reload
    minimap = {
        hide = false,
    },
    ui = {
        width = 940,
        height = 710,
        point = "CENTER",
        relativePoint = "CENTER",
        x = 0,
        y = 0,
        lastTab = "containers",
        search = "",
        listView = "tracked",
    },
    queue = {
        mode = "auto",       -- "auto" or "assisted" (real hardware click)
        interval = 0.30,
        verifyDelay = 1.50,
        retryDelay = 0.60,
        maxRetries = 2,
        maxLockedChecks = 4,
        stopOnError = false,
    },
    diagnostics = {
        failedOpenAttempts = 0,
        lastFailure = nil,
        lastFailureAt = nil,
        lastBlockReason = nil,
        failureHistory = {}, -- persistent last failures (bounded)
    },
    -- Statistics
    stats = {
        totalOpened = 0,        -- Confirmed container openings only
        totalOpenedSession = 0, -- Session counter (reset on login)
        failedOpened = 0,       -- Exhausted opening attempts
        itemsOpened = {},       -- {[itemID] = count}
        firstOpen = nil,        -- Timestamp of first ever open
        lastOpen = nil,         -- Timestamp of last open
        totalGold = 0,          -- Total gold earned (in copper)
        sessionGold = 0,        -- Session gold earned (in copper)
    },
    -- History (last 50 openings)
    history = {},
    historyMaxSize = 50,
    -- Loot summary per container type
    lootSummary = {}, -- [containerItemID] = { opened=N, gold=copper, items={[itemID]=count}, currencies={[currencyID]=count} }
}

local function DeepCopyValue(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for key, child in pairs(value) do
        copy[DeepCopyValue(key)] = DeepCopyValue(child)
    end
    return copy
end

local function MergeDefaults(target, template)
    if type(target) ~= "table" then target = {} end
    for key, value in pairs(template) do
        if target[key] == nil then
            target[key] = DeepCopyValue(value)
        elseif type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = DeepCopyValue(value)
            else
                target[key] = MergeDefaults(target[key], value)
            end
        end
    end
    return target
end

local function NormalizeNumericKeySet(tbl)
    if type(tbl) ~= "table" then return {} end
    local normalized = {}
    for key, value in pairs(tbl) do
        local numericKey = tonumber(key)
        if numericKey and value then
            normalized[numericKey] = value
        end
    end
    return normalized
end

function ACO:MigrateDatabase(db)
    if type(db) ~= "table" then db = {} end

    local previousSchema = tonumber(db.schemaVersion) or 0

    -- Legacy releases stored several set-like tables with string keys after
    -- import. Normalizing them avoids duplicate entries and lookup misses.
    db.containers = NormalizeNumericKeySet(db.containers)
    db.blacklist = NormalizeNumericKeySet(db.blacklist)
    db.containerRules = NormalizeNumericKeySet(db.containerRules)
    db.containerStats = NormalizeNumericKeySet(db.containerStats)

    db = MergeDefaults(db, defaults)

    -- Defensive cleanup for values that can make timers or frame sizing unsafe.
    db.delay = max(0, min(30, tonumber(db.delay) or defaults.delay))
    db.historyMaxSize = max(10, min(500, tonumber(db.historyMaxSize) or defaults.historyMaxSize))
    db.queue.interval = max(0.20, min(2.00, tonumber(db.queue.interval) or defaults.queue.interval))
    db.queue.verifyDelay = max(0.75, min(5.00, tonumber(db.queue.verifyDelay) or defaults.queue.verifyDelay))
    db.queue.retryDelay = max(0.25, min(5.00, tonumber(db.queue.retryDelay) or defaults.queue.retryDelay))
    db.queue.maxRetries = max(0, min(5, floor(tonumber(db.queue.maxRetries) or defaults.queue.maxRetries)))
    db.queue.maxLockedChecks = max(1, min(10, floor(tonumber(db.queue.maxLockedChecks) or defaults.queue.maxLockedChecks)))
    if db.queue.mode ~= "auto" and db.queue.mode ~= "assisted" then db.queue.mode = "auto" end
    db.queue.stopOnError = db.queue.stopOnError and true or false
    db.ui.width = max(820, min(1200, tonumber(db.ui.width) or defaults.ui.width))
    db.ui.height = max(680, min(950, tonumber(db.ui.height) or defaults.ui.height))

    local validPoints = {
        TOPLEFT = true, TOP = true, TOPRIGHT = true,
        LEFT = true, CENTER = true, RIGHT = true,
        BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
    }
    if not validPoints[db.ui.point] or not validPoints[db.ui.relativePoint] then
        db.ui.point, db.ui.relativePoint, db.ui.x, db.ui.y = "CENTER", "CENTER", 0, 0
    end
    local validTabs = { containers = true, stats = true, history = true, pending = true, loot = true }
    if not validTabs[db.ui.lastTab] then db.ui.lastTab = "containers" end
    if db.ui.listView ~= "tracked" and db.ui.listView ~= "blocked" then db.ui.listView = "tracked" end
    db.ui.search = tostring(db.ui.search or "")
    db.stats.itemsOpened = NormalizeNumericKeySet(db.stats.itemsOpened)
    db.lootSummary = NormalizeNumericKeySet(db.lootSummary)
    if type(db.diagnostics.failureHistory) ~= "table" then db.diagnostics.failureHistory = {} end

    -- Normalize arbitrary per-container data. Invalid values are clamped instead
    -- of being trusted, because timers and queue ordering consume them directly.
    for itemID, rule in pairs(db.containerRules) do
        if type(rule) ~= "table" then
            db.containerRules[itemID] = nil
        else
            if rule.autoOpen == nil then rule.autoOpen = true else rule.autoOpen = rule.autoOpen and true or false end
            local delay = tonumber(rule.delay)
            rule.delay = delay and max(0, min(30, delay)) or nil
            rule.maxPerSession = max(0, min(9999, floor(tonumber(rule.maxPerSession) or 0)))
            rule.priority = max(-10, min(10, floor(tonumber(rule.priority) or 0)))
            rule.temporaryBlockUntil = max(0, tonumber(rule.temporaryBlockUntil) or 0)
            rule.note = tostring(rule.note or ""):sub(1, 240)
            rule.source = tostring(rule.source or ""):sub(1, 80)
        end
    end
    for itemID, stat in pairs(db.containerStats) do
        if type(stat) ~= "table" then
            db.containerStats[itemID] = nil
        else
            stat.success = max(0, floor(tonumber(stat.success) or 0))
            stat.failed = max(0, floor(tonumber(stat.failed) or 0))
            stat.lastSuccess = tonumber(stat.lastSuccess)
            stat.lastFailure = tonumber(stat.lastFailure)
            stat.lastFailureReason = stat.lastFailureReason and tostring(stat.lastFailureReason) or nil
        end
    end
    while #db.diagnostics.failureHistory > 50 do tremove(db.diagnostics.failureHistory, 1) end

    if type(db.history) ~= "table" then db.history = {} end
    for _, entry in ipairs(db.history) do
        if type(entry) == "table" and entry.itemID then
            entry.itemID = tonumber(entry.itemID) or entry.itemID
        end
    end
    while #db.history > db.historyMaxSize do
        tremove(db.history, 1)
    end

    db.schemaVersion = ACO.DB_SCHEMA_VERSION
    self._migratedFromSchema = previousSchema
    return db
end

function ACO:ValidateRuntimeAPI()
    local missing = {}
    local optionalMissing = {}
    local function Require(path, value)
        if not value then tinsert(missing, path) end
    end
    local function Optional(path, value)
        if not value then tinsert(optionalMissing, path) end
    end

    -- Core inventory/opening path. Missing one of these means the addon cannot
    -- safely perform its primary job on this Retail build.
    Require("C_Container.GetContainerNumSlots", C_Container and C_Container.GetContainerNumSlots)
    Require("C_Container.GetContainerItemInfo", C_Container and C_Container.GetContainerItemInfo)
    Require("C_Container.UseContainerItem", C_Container and C_Container.UseContainerItem)
    Require("C_Item.GetItemInfo", C_Item and C_Item.GetItemInfo)
    Require("C_Item.GetItemInfoInstant", C_Item and C_Item.GetItemInfoInstant)
    Require("C_Item.GetItemNameByID", C_Item and C_Item.GetItemNameByID)
    Require("C_Item.GetItemSpell", C_Item and C_Item.GetItemSpell)
    Require("C_Timer.NewTicker", C_Timer and C_Timer.NewTicker)

    -- These have working fallbacks, but we still report them so /aco diag is a
    -- useful early warning when Blizzard changes a minor-patch API.
    Optional("C_Item.IsItemDataCachedByID", C_Item and C_Item.IsItemDataCachedByID)
    Optional("C_Item.RequestLoadItemDataByID", C_Item and C_Item.RequestLoadItemDataByID)
    Optional("C_TooltipInfo.GetItemByID", C_TooltipInfo and C_TooltipInfo.GetItemByID)
    Optional("C_AddOns.GetAddOnMetadata", C_AddOns and C_AddOns.GetAddOnMetadata)

    local version, build, buildDate, interfaceVersion = GetBuildInfo()
    self.runtimeVersion = version or "?"
    self.runtimeBuild = tostring(build or "?")
    self.runtimeBuildDate = buildDate or "?"
    self.runtimeInterface = tonumber(interfaceVersion) or 0
    self.missingRuntimeAPI = missing
    self.missingOptionalAPI = optionalMissing
    self.runtimeInterfaceMatches = self.runtimeInterface == self.SUPPORTED_INTERFACE
    return #missing == 0, missing
end


-- ============================================================================
-- PER-CONTAINER RULES / DIAGNOSTICS (3.1)
-- ============================================================================

ACO.DEFAULT_CONTAINER_RULE = {
    autoOpen = true,
    delay = nil,
    maxPerSession = 0,
    priority = 0,
    temporaryBlockUntil = 0,
    note = "",
    source = "",
}

local function CopyContainerRule(rule)
    return {
        autoOpen = rule.autoOpen ~= false,
        delay = rule.delay,
        maxPerSession = rule.maxPerSession or 0,
        priority = rule.priority or 0,
        temporaryBlockUntil = rule.temporaryBlockUntil or 0,
        note = rule.note or "",
        source = rule.source or "",
    }
end

function ACO:GetContainerRule(itemID, create)
    if not self.db or not itemID then return CopyContainerRule(self.DEFAULT_CONTAINER_RULE) end
    itemID = tonumber(itemID)
    local rule = self.db.containerRules[itemID]
    if not rule and create then
        rule = CopyContainerRule(self.DEFAULT_CONTAINER_RULE)
        self.db.containerRules[itemID] = rule
    end
    return rule or CopyContainerRule(self.DEFAULT_CONTAINER_RULE)
end

function ACO:RefreshQueuedEntriesForRule(itemID)
    if not itemID then return end
    local rule = self:GetContainerRule(itemID, false)
    local now = GetTime()
    for _, entry in ipairs(self.openQueue) do
        if entry.itemID == itemID then
            entry.priority = tonumber(rule.priority) or 0
            if self:IsAutomaticQueueSource(entry.origin or entry.source) and entry.status ~= "RETRYING" then
                if (rule.temporaryBlockUntil or 0) > time() then
                    entry.executeAt = now + ((rule.temporaryBlockUntil or time()) - time())
                    entry.status = "BLOCKED"
                    entry.statusReason = "TEMP_BLOCK"
                elseif rule.delay ~= nil then
                    entry.executeAt = now + rule.delay
                    entry.status = rule.delay > 0 and "DELAY" or "QUEUED"
                    entry.statusReason = nil
                end
            end
        end
    end
    if self.SortOpenQueue then self:SortOpenQueue() end
end

function ACO:SetContainerRule(itemID, values)
    if not self.db or not itemID or type(values) ~= "table" then return false end
    itemID = tonumber(itemID)
    local rule = self:GetContainerRule(itemID, true)
    if values.autoOpen ~= nil then rule.autoOpen = values.autoOpen and true or false end
    if values.delay ~= nil then
        local delay = tonumber(values.delay)
        rule.delay = delay and max(0, min(30, delay)) or nil
    elseif values.clearDelay then
        rule.delay = nil
    end
    if values.maxPerSession ~= nil then
        rule.maxPerSession = max(0, min(9999, floor(tonumber(values.maxPerSession) or 0)))
    end
    if values.priority ~= nil then
        rule.priority = max(-10, min(10, floor(tonumber(values.priority) or 0)))
    end
    if values.temporaryBlockUntil ~= nil then
        rule.temporaryBlockUntil = max(0, tonumber(values.temporaryBlockUntil) or 0)
    end
    if values.note ~= nil then rule.note = tostring(values.note):sub(1, 240) end
    if values.source ~= nil then rule.source = tostring(values.source):sub(1, 80) end
    self:RefreshQueuedEntriesForRule(itemID)
    if self.UI and self.UI.RefreshList then self.UI:RefreshList() end
    self:NotifyQueueChanged()
    return true
end

function ACO:ResetContainerRule(itemID)
    if not self.db or not itemID then return end
    itemID = tonumber(itemID)
    self.db.containerRules[itemID] = nil
    self:RefreshQueuedEntriesForRule(itemID)
    if self.UI and self.UI.RefreshList then self.UI:RefreshList() end
    self:NotifyQueueChanged()
end

function ACO:GetContainerDiagnostic(itemID, create)
    if not self.db or not itemID then return nil end
    itemID = tonumber(itemID)
    local stat = self.db.containerStats[itemID]
    if not stat and create then
        stat = { success = 0, failed = 0 }
        self.db.containerStats[itemID] = stat
    end
    return stat
end

function ACO:IsAutomaticQueueSource(source)
    return source == "AUTO" or source == "OPENALL" or source == "LOGIN" or source == "DISCOVERY"
end

function ACO:CanProcessByRule(itemID, source)
    local rule = self:GetContainerRule(itemID, false)
    if not self:IsAutomaticQueueSource(source) then return true end
    if rule.autoOpen == false then return false, "RULE_DISABLED" end
    if (rule.temporaryBlockUntil or 0) > time() then return false, "TEMP_BLOCK" end
    local limit = tonumber(rule.maxPerSession) or 0
    if limit > 0 and (self.sessionOpenCounts[itemID] or 0) >= limit then
        return false, "SESSION_LIMIT"
    end
    return true
end

function ACO:CanEnqueueByRule(itemID, source)
    local allowed, reason = self:CanProcessByRule(itemID, source)
    if not allowed then return false, reason end
    if not self:IsAutomaticQueueSource(source) then return true end

    local rule = self:GetContainerRule(itemID, false)
    local limit = tonumber(rule.maxPerSession) or 0
    if limit > 0 then
        local reserved = self.sessionOpenCounts[itemID] or 0
        for _, entry in ipairs(self.openQueue) do
            if entry.itemID == itemID and self:IsAutomaticQueueSource(entry.origin or entry.source) then
                reserved = reserved + 1
            end
        end
        for _, entry in pairs(self.activeVerifications) do
            if entry.itemID == itemID and self:IsAutomaticQueueSource(entry.origin or entry.source) then
                reserved = reserved + 1
            end
        end
        if reserved >= limit then return false, "SESSION_LIMIT" end
    end
    return true
end

function ACO:GetRuleDelay(itemID)
    local rule = self:GetContainerRule(itemID, false)
    if rule.delay ~= nil then return rule.delay end
    return (self.db and self.db.delay) or 0
end

function ACO:GetRulePriority(itemID)
    return tonumber(self:GetContainerRule(itemID, false).priority) or 0
end

function ACO:NextQueueID()
    self.queueSequence = (self.queueSequence or 0) + 1
    return self.queueSequence
end

function ACO:NotifyQueueChanged()
    if self.UI then
        if self.UI.RefreshKPI then self.UI:RefreshKPI() end
        if self.UI.RefreshPendingList then self.UI:RefreshPendingList() end
        if self.UI.UpdateQueueModeControls then self.UI:UpdateQueueModeControls() end
    end
end

function ACO:GetQueueMode()
    if not self.db or not self.db.queue then return "auto" end
    return self.db.queue.mode == "assisted" and "assisted" or "auto"
end

function ACO:GetQueueReasonText(reason)
    if not reason then return "" end
    local blockReasons = {
        COMBAT = true, CURSOR = true, MERCHANT = true, TRADE = true,
        AUCTION = true, MAIL = true, BANK = true, GUILDBANK = true,
        VOIDSTORAGE = true, LOOT = true, SCRAPPING = true,
    }
    if blockReasons[reason] then return self:GetBlockReasonText(reason) end
    local keys = {
        RULE_DISABLED = "QUEUE_REASON_RULE_DISABLED",
        TEMP_BLOCK = "QUEUE_REASON_TEMP_BLOCK",
        SESSION_LIMIT = "QUEUE_REASON_SESSION_LIMIT",
        NOT_CONSUMED = "QUEUE_REASON_NOT_CONSUMED",
        LOCKED = "QUEUE_REASON_LOCKED",
        LOCKED_TIMEOUT = "QUEUE_REASON_LOCKED_TIMEOUT",
        PROTECTED = "QUEUE_REASON_PROTECTED",
        MISSING = "QUEUE_REASON_MISSING",
    }
    return keys[reason] and self:Translate(keys[reason]) or tostring(reason)
end


function ACO:SetQueueMode(mode)
    if not self.db or not self.db.queue then return false end
    mode = mode == "assisted" and "assisted" or "auto"
    if self.db.queue.mode == mode then return true end
    self.db.queue.mode = mode
    self.assistedEntry = nil
    if self.UI and self.UI.ConfigureAssistedButtons then self.UI:ConfigureAssistedButtons(nil) end
    self.queueNextAllowedAt = 0
    self:StartQueueWorker()
    self:NotifyQueueChanged()
    return true
end

-- ============================================================================
-- COLORS & CONSTANTS
-- ============================================================================

ACO.colors = {
    -- Palette Midnight unifiée (Zayu / Zarctus)
    bg              = { r = 0.06, g = 0.06, b = 0.08, a = 0.97 },
    header          = { r = 0.10, g = 0.10, b = 0.13, a = 1 },
    row             = { r = 0.09, g = 0.09, b = 0.12, a = 0.92 },
    rowAlt          = { r = 0.06, g = 0.06, b = 0.09, a = 0.92 },
    rowHover        = { r = 0.14, g = 0.15, b = 0.22, a = 1 },
    border          = { r = 0.22, g = 0.22, b = 0.28, a = 1 },
    borderLight     = { r = 0.35, g = 0.35, b = 0.40, a = 1 },
    accent          = { r = 0.00, g = 0.70, b = 0.90, a = 1 },
    gold            = { r = 1.00, g = 0.82, b = 0.00, a = 1 },
    green           = { r = 0.30, g = 0.90, b = 0.30, a = 1 },
    red             = { r = 1.00, g = 0.30, b = 0.30, a = 1 },
    orange          = { r = 1.00, g = 0.60, b = 0.10, a = 1 },
    text            = { r = 0.95, g = 0.95, b = 0.95, a = 1 },
    textDim         = { r = 0.55, g = 0.55, b = 0.58, a = 1 },
    textHeader      = { r = 0.75, g = 0.75, b = 0.78, a = 1 },
    -- Rétrocompatibilité (Core.lua :Print, etc.)
    primary         = { r = 0.00, g = 0.70, b = 0.90 },
    secondary       = { r = 0.60, g = 0.40, b = 1.00 },
    success         = { r = 0.30, g = 0.90, b = 0.30 },
    error           = { r = 1.00, g = 0.30, b = 0.30 },
    background      = { r = 0.06, g = 0.06, b = 0.08 },
    backgroundLight = { r = 0.09, g = 0.09, b = 0.12 },
}

ACO.SOUNDS = {
    OPEN = SOUNDKIT.UI_BAG_SORTING_01 or 1221,
    ADD = SOUNDKIT.UI_PROFESSIONS_NEW_RECIPE_LEARNED or 1221,
    REMOVE = SOUNDKIT.UI_PROFESSION_TRACK_ABILITY or 1221,
    ERROR = SOUNDKIT.UI_GARRISON_TOAST or 1221,
}

-- ============================================================================
-- ZARCTUS_GOLD INTEGRATION
-- ============================================================================

-- Notify Zarctus_Gold before opening a chest to avoid double-counting
function ACO:NotifyZarctusGold(itemID, itemName)
    if Zarctus_Gold_API and Zarctus_Gold_API.PushChestContext then
        local name = itemName or ("Container #" .. itemID)
        Zarctus_Gold_API:PushChestContext(name)
        self:Debug("Notified Zarctus_Gold: " .. name)
    end
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

function ACO:Print(msg, isError)
    local color = isError and self.colors.error or self.colors.primary
    local prefix = format("|cff%02x%02x%02x[ACO]|r",
        floor(color.r * 255 + 0.5), floor(color.g * 255 + 0.5), floor(color.b * 255 + 0.5))
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

-- Cache pour les items vérifiés (évite les vérifications répétées)
ACO.containerCache = {}
ACO.containerCacheSize = 0
ACO.CONTAINER_CACHE_MAX = 500

function ACO:PruneContainerCache()
    if self.containerCacheSize <= self.CONTAINER_CACHE_MAX then return end
    wipe(self.containerCache)
    self.containerCacheSize = 0
    self:Debug("Container cache pruned")
end

-- ============================================================================
-- TEXT / ITEM-DATA HELPERS
-- ============================================================================

local function NormalizeText(s)
    if not s then return nil end
    -- string.lower() côté WoW est surtout ASCII, mais suffisant ici (les mots-clés sont en minuscules)
    s = lower(s)
    -- Normalise quelques variantes d'apostrophes (’ vs ' etc.)
    s = s:gsub("’", "'"):gsub("`", "'"):gsub("´", "'"):gsub("ʼ", "'")
    return s
end

local function ContainsAnyPlain(haystack, needles)
    if not haystack then return false end
    for _, n in ipairs(needles) do
        if n and n ~= "" and haystack:find(n, 1, true) then
            return true
        end
    end
    return false
end

-- Certaines infos (nom / spell "Use:") peuvent être nil si l'item n'est pas encore en cache.
-- On évite alors de "cacher = false" trop tôt, sinon certains conteneurs ne seront jamais reconnus.
function ACO:IsItemDataAvailable(itemID)
    if not itemID then return false end
    if C_Item.IsItemDataCachedByID then
        return C_Item.IsItemDataCachedByID(itemID)
    end
    if C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name then return true end
    end
    return false
end

-- Mots-clés (recherche "plain", pas de patterns Lua) pour détecter des objets ouvrables.
-- Couvre toutes les langues supportées par WoW pour un maximum de détection.
local OPEN_PATTERNS = {
    "open", -- EN: open, opens, opening
    "ouvr", -- FR: ouvrir, ouvrez, ouvrant, ouvre
    "öffn", -- DE: öffnen, öffnet
    "abr", -- ES: abrir, abre (also PT "abrir")
    "откр", -- RU: открыть, открывать
    "열", -- KR: 열기
    "打开", -- zhCN: 打开 (open)
    "打開", -- zhTW: 打開 (open)
    "apr", -- IT: aprire, apri
}

local OPEN_KEYWORDS = {
    -- EN
    "unwrap", "unpack", "reveal", "crack",
    "loot", "salvage", "disassemble",
    "click to open", "right click to open", "right-click to open",
    "use:", "contain",
    "rummage", "pillage", "plunder", "ransack",
    "unseal", "uncork", "unbox",
    -- FR
    "déballer", "utiliser", "utilisez",
    "piller", "récupér",
    "cliqu", "fouill",
    "ouvrir", "ouvre",
    -- DE
    "auspacken", "benutzen", "verwenden",
    "plünder",
    -- ES
    "desempaquetar", "usar", "utilizar",
    "saquear",
    -- PT
    "desembrulhar", "desembalar",
    -- IT
    "scartare", "usare",
    -- RU
    "использ", "распаков",
}

local CONTAINER_NAME_KEYWORDS = {
    -- Chests / Coffres
    "chest", "coffre", "coffret", "truhe", "cofre", "baú", "baul",
    "war chest", "treasure chest",
    -- Crates / Caisses
    "crate", "caisse", "kiste", "cajón", "caixa",
    -- Boxes / Boîtes
    "box", "boîte", "boite", "schachtel", "caja",
    -- Bags / Sacs (openable reward bags, not equippable)
    "bag of", "sac de", "sac d'",
    "supply bag", "reward bag",
    -- Sacks / Sacs
    "sack", "sac ", "sacoche",
    -- Satchels
    "satchel", "sacoche",
    -- Bundles
    "bundle", "lot", "bündel", "lote", "fardo",
    -- Pouches / Bourses
    "pouch", "bourse", "purse", "beutel", "bolsa",
    -- Parcels / Colis
    "parcel", "colis", "package", "paquet", "paket", "paquete",
    -- Lockboxes / Coffres-forts (PvP, rogue)
    "lockbox", "strongbox", "coffer",
    "battered ", "steel-bound",
    -- Treasure / Trésor
    "treasure", "trésor", "schatz", "tesoro",
    -- Salvage
    "salvage", "récupération", "bergung", "rescate",
    -- Cache (common WoW container)
    "cache",
    -- Hoards / Troves / Stash
    "hoard", "trove", "stash",
    -- Supply / Provisions
    "supply", "provisions", "vorrat", "suministro",
    -- Reward / Récompense
    "reward", "récompense", "belohnung", "recompensa",
    -- Gifts / Cadeaux (holiday)
    "gift", "cadeau", "present", "geschenk", "regalo",
    "wrapping", "emballage", "wrapped",
    "winter veil", "feast of winter",
    "lunar festival", "love is in the air",
    "noblegarden", "midsummer",
    "brewfest", "hallow", "pilgrim",
    -- Mystery / Bounty / Casket
    "mystery", "bounty", "casket", "mystère",
    -- War / PvP
    "war supply", "conquest", "honor",
    -- Capsule
    "capsule",
    -- Profession crates/bags
    "reagent", "recipe",
    -- Mission rewards
    "mission", "garrison", "shipment",
    -- Emissary / Calling / World quest containers
    "emissary", "calling", "émissaire",
    -- Delves / TWW containers
    "delve", "vault", "coalescing",
    "bountiful", "restored",
    -- WoD specific
    "follower", "champion",
    -- Misc
    "loot-filled", "plunder",
    "container", "conteneur",
    "piñata", "pinata",
    "egg", "oeuf",      -- Noblegarden eggs
    "clam", "palourde", -- Clams
    "token", "jeton",
    "kit",
    "envelope", "enveloppe",
    "grab bag",
    "care package",
    "spoils", "butin",
    "jackpot",
    "dispatch",
    "shipment", "livraison",
    "footlocker", "malle",
    "barrel", "tonneau", "fass",
    "urn", "urne",
    "jar", "jarre",
    "basket", "panier", "korb",
    "carton",
    -- Midnight / The War Within S2+ containers
    "voidstorm", "haranir", "sunwell", "silvermoon",
    "amani", "zul'aman", "quel'thalas",
    "nexus", "nightborne", "twilight",
    "earthen", "arathi", "awakening",
    "undermine", "venture",
}

-- ============================================================================
-- TOOLTIP-BASED CONTAINER DETECTION (Feature: tooltip scan)
-- ============================================================================

-- Hidden scanning tooltip (never shown to the player)
local scanTooltip = CreateFrame("GameTooltip", "ACOScanTooltip", nil, "GameTooltipTemplate")
scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")

local TOOLTIP_OPEN_KEYWORDS = {
    -- EN
    "right click to open",
    "right-click to open",
    "click to open",
    "<right click to open>",
    "open the",
    -- FR
    "clic droit pour ouvrir",
    "cliquez pour ouvrir",
    "<clic droit pour ouvrir>",
    -- DE
    "rechtsklick zum \195\182ffnen",
    "rechtsklicken zum \195\182ffnen",
    "<rechtsklick zum \195\182ffnen>",
    -- ES
    "clic derecho para abrir",
    "haz clic con el bot\195\179n derecho para abrir",
    "<clic derecho para abrir>",
    -- PT
    "clique com o bot\195\163o direito para abrir",
    "clique para abrir",
    -- IT
    "clic destro per aprire",
    "clicca per aprire",
    -- RU
    "\208\189\208\176\208\182\208\188\208\184\209\130\208\181 \208\191\209\128\208\176\208\178\209\131\209\142", -- нажмите правую
}

-- Modern tooltip API (C_TooltipInfo, available since 10.0.2)
-- Falls back to the old GameTooltip scanning if unavailable.
function ACO:HasOpenableTooltipModern(itemID)
    if not C_TooltipInfo or not C_TooltipInfo.GetItemByID then
        return false
    end

    local data = C_TooltipInfo.GetItemByID(itemID)
    if not data or not data.lines then return false end

    for _, lineData in ipairs(data.lines) do
        local text = lineData.leftText
        if IsAccessibleValue(text) then
            local normalized = NormalizeText(text)
            if normalized and ContainsAnyPlain(normalized, TOOLTIP_OPEN_KEYWORDS) then
                return true
            end

            -- 12.0+ TooltipDataLineType detection
            -- FlavorText lines sometimes describe openable items
            local lineType = lineData.type
            local lineTypes = Enum and Enum.TooltipDataLineType
            if lineType and lineTypes then
                -- Enum members can change between minor Retail builds. Compare only
                -- against members that exist instead of indexing them blindly.
                local isIgnored = (lineTypes.ItemQuality and lineType == lineTypes.ItemQuality)
                    or (lineTypes.UsageRequirement and lineType == lineTypes.UsageRequirement)
                    or (lineTypes.ErrorLine and lineType == lineTypes.ErrorLine)
                    or (lineTypes.DisabledLine and lineType == lineTypes.DisabledLine)
                if not isIgnored and lineTypes.FlavorText and lineType == lineTypes.FlavorText then
                    if normalized and (ContainsAnyPlain(normalized, OPEN_PATTERNS) or ContainsAnyPlain(normalized, OPEN_KEYWORDS)) then
                        return true
                    end
                end
            end

            -- Green "Use:" text lines (type 0, green color ~= {0, 1, 0})
            -- These indicate an active use effect
            if lineData.leftColor then
                local clr = lineData.leftColor
                local r, g, b = clr.r, clr.g, clr.b
                -- 12.1: never perform arithmetic/comparisons on secret values.
                if IsAccessibleValue(r) and IsAccessibleValue(g) and (b == nil or IsAccessibleValue(b)) then
                    -- Green text = Use: effect (r < 0.15, g > 0.85, b < 0.15)
                    if r < 0.15 and g > 0.85 and (b or 0) < 0.15 then
                        if normalized and (ContainsAnyPlain(normalized, OPEN_PATTERNS) or ContainsAnyPlain(normalized, OPEN_KEYWORDS)) then
                            return true
                        end
                    end
                end
            end
        end
    end
    return false
end

function ACO:HasOpenableTooltip(itemID)
    if not itemID then return false end
    if not self:IsItemDataAvailable(itemID) then return false end

    -- Try modern API first (more reliable, no hidden frame needed)
    if C_TooltipInfo and C_TooltipInfo.GetItemByID then
        return self:HasOpenableTooltipModern(itemID)
    end

    -- Fallback: old GameTooltip scanning
    scanTooltip:SetOwner(WorldFrame, "ANCHOR_NONE")
    scanTooltip:SetItemByID(itemID)

    for i = 1, scanTooltip:NumLines() do
        local line = _G["ACOScanTooltipTextLeft" .. i]
        if line then
            local text = line:GetText()
            if text then
                local normalized = NormalizeText(text)
                if normalized and ContainsAnyPlain(normalized, TOOLTIP_OPEN_KEYWORDS) then
                    scanTooltip:ClearLines()
                    return true
                end
            end
        end
    end

    scanTooltip:ClearLines()
    return false
end

function ACO:IsContainerItem(itemID)
    if not itemID then return false end

    -- Check user-defined containers (absolute priority)
    if self.db and self.db.containers[itemID] then
        return true
    end

    -- Cache (avoid costly checks during bag scans)
    if self.containerCache[itemID] ~= nil then
        return self.containerCache[itemID]
    end

    -- Get class/subclass/equipLoc via instant API (no cache required)
    local equipLoc, classID, subClassID
    if C_Item.GetItemInfoInstant then
        local _, _, _, eqLoc, _, cID, scID = C_Item.GetItemInfoInstant(itemID)
        equipLoc = eqLoc
        classID = cID
        subClassID = scID
    end

    -- Exclude equippable items (armor, weapons, real bags)
    if equipLoc and equipLoc ~= "" and equipLoc ~= "INVTYPE_NON_EQUIP" then
        self.containerCache[itemID] = false
        return false
    end

    -- Class 1 = Container (equippable bags), Class 11 = Quiver -> never auto-open
    if classID == 1 or classID == 11 then
        self.containerCache[itemID] = false
        return false
    end

    -- If item data not yet cached, don't cache false (will retry later)
    if not self:IsItemDataAvailable(itemID) then
        return false
    end

    local itemSpell = C_Item.GetItemSpell and C_Item.GetItemSpell(itemID) or nil
    local itemName = C_Item.GetItemNameByID and C_Item.GetItemNameByID(itemID) or nil

    self:Debug(format("Checking item %d: name='%s', spell='%s', class=%s/%s",
        itemID, itemName or "nil", itemSpell or "nil",
        tostring(classID), tostring(subClassID)))

    local isContainer = false

    -- 1) Priority: "Use:" spell text (most reliable when available)
    if itemSpell and itemSpell ~= "" then
        local spellLower = NormalizeText(itemSpell)
        if spellLower and (ContainsAnyPlain(spellLower, OPEN_PATTERNS) or ContainsAnyPlain(spellLower, OPEN_KEYWORDS)) then
            isContainer = true
        end
    end

    -- 2) Fallback: item name keywords
    if not isContainer and itemName and itemName ~= "" then
        local nameLower = NormalizeText(itemName)
        if nameLower and ContainsAnyPlain(nameLower, CONTAINER_NAME_KEYWORDS) then
            isContainer = true
        end
    end

    -- 3) Class-based heuristic: Miscellaneous (15) with any Use: spell
    --    Very common for openable containers (subclass 0/Junk, 3/Holiday, 4/Other)
    if not isContainer and classID == 15 and itemSpell and itemSpell ~= "" then
        -- Exclude companion pets (subclass 2), mounts (subclass 5), mount equipment (subclass 6)
        if subClassID ~= 2 and subClassID ~= 5 and subClassID ~= 6 then
            isContainer = true
        end
    end

    -- 3b) Consumable (0) subclass Other (8) with an open/use spell = openable container
    if not isContainer and classID == 0 and subClassID == 8 and itemSpell and itemSpell ~= "" then
        local spellLower = NormalizeText(itemSpell)
        if spellLower and (ContainsAnyPlain(spellLower, OPEN_PATTERNS) or ContainsAnyPlain(spellLower, OPEN_KEYWORDS)) then
            isContainer = true
        end
    end

    -- 3c) Consumable (0) subclass Generic (0) with open spell
    if not isContainer and classID == 0 and subClassID == 0 and itemSpell and itemSpell ~= "" then
        local spellLower = NormalizeText(itemSpell)
        if spellLower and (ContainsAnyPlain(spellLower, OPEN_PATTERNS) or ContainsAnyPlain(spellLower, OPEN_KEYWORDS)) then
            isContainer = true
        end
    end

    -- 4) Tooltip scan: "Right Click to Open" or green "Use:" text in tooltip
    if not isContainer then
        isContainer = self:HasOpenableTooltip(itemID)
    end

    -- 5) Additional: Quest items (class 12) with open spell text
    --    Some quest reward containers are class 12
    if not isContainer and classID == 12 and itemSpell and itemSpell ~= "" then
        local spellLower = NormalizeText(itemSpell)
        if spellLower and ContainsAnyPlain(spellLower, OPEN_PATTERNS) then
            isContainer = true
        end
    end

    self.containerCache[itemID] = isContainer
    self.containerCacheSize = (self.containerCacheSize or 0) + 1
    self:PruneContainerCache()
    return isContainer
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

-- Can we enqueue/open this item type? (no combat check)
function ACO:CanQueueContainerItem(itemID)
    if not itemID or not self.db then return false end
    if self.db.blacklist and self.db.blacklist[itemID] then
        return false
    end
    return self:IsContainerItem(itemID)
end

-- Tracked inventory bags (includes reagent bag when available)
function ACO:GetTrackedBags()
    if self._trackedBags then
        return self._trackedBags
    end

    local bags = { 0, 1, 2, 3, 4 }
    local reagentBag = (Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag) or 5
    local already = false
    for _, b in ipairs(bags) do
        if b == reagentBag then
            already = true
            break
        end
    end
    if reagentBag and not already then
        tinsert(bags, reagentBag)
    end

    self._trackedBags = bags
    -- Build a set for quick membership checks
    self._trackedBagSet = {}
    for _, b in ipairs(bags) do
        self._trackedBagSet[b] = true
    end
    return bags
end

-- ============================================================================
-- ITEM OPENING LOGIC
-- ============================================================================

function ACO:FindItemInBags(itemID)
    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                return bag, slot, info
            end
        end
    end
    return nil
end

function ACO:GetItemCountInBags(itemID)
    local total = 0
    local firstBag, firstSlot, firstInfo

    if not itemID then
        return 0, nil, nil, nil
    end

    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                total = total + (info.stackCount or 1)

                if not firstBag then
                    firstBag = bag
                    firstSlot = slot
                    firstInfo = info
                end
            end
        end
    end

    return total, firstBag, firstSlot, firstInfo
end

function ACO:CountItemInBags(itemID)
    local count = 0
    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                count = count + (info.stackCount or 1)
            end
        end
    end
    return count
end

-- Try to use an item from a specific bag/slot.
-- Returns: true on success, false + reason ("MISSING" | "LOCKED" | "MISMATCH")
function ACO:UseContainerFromBagSlot(itemID, bag, slot, itemLink)
    if not bag or not slot then
        return false, "MISSING"
    end

    local info = C_Container.GetContainerItemInfo(bag, slot)
    if not info then
        return false, "MISSING"
    end
    if info.itemID ~= itemID then
        return false, "MISMATCH"
    end
    if info.isLocked then
        return false, "LOCKED"
    end

    -- Notify integrations before the item disappears from the bag.
    local itemName = info.itemName
    if not itemName and info.hyperlink then
        itemName = info.hyperlink:match("%[(.-)%]")
    end
    self:NotifyZarctusGold(itemID, itemName)

    -- Snapshot before issuing the protected item action. The tracker is only
    -- committed after post-use verification confirms that one item was consumed.
    local lootTracker = self:StartLootTracking(itemID)

    local apiOk, apiErr = pcall(C_Container.UseContainerItem, bag, slot)
    local issued = apiOk
    if not apiOk then
        self:Debug("C_Container.UseContainerItem failed: " .. tostring(apiErr))
        issued = self:UseItemSecure(itemID, bag, slot)
    end

    if not issued then
        if lootTracker then lootTracker.cancelled = true end
        return false, "PROTECTED"
    end

    return true, nil, lootTracker, info
end

-- Best-effort secure button fallback.
-- Important: a programmatic Button:Click() is not a guaranteed replacement for a
-- real hardware click on modern clients. The post-use verifier decides whether
-- the item was actually consumed.
function ACO:UseItemSecure(itemID, bag, slot)
    if InCombatLockdown() then
        self:Print(ACO:Translate("SECURE_CLICK_COMBAT"), true)
        return false
    end
    local btn = secureBtn
    if bag and slot then
        btn:SetAttribute("type", "macro")
        btn:SetAttribute("macrotext", format("/use %d %d", bag, slot))
    else
        btn:SetAttribute("type", "item")
        btn:SetAttribute("item", "item:" .. itemID)
    end
    btn:Show()
    btn:Click()
    -- Delay Hide by one frame so the secure action has time to execute before
    -- the button is hidden (hiding synchronously can cancel the pending action).
    C_Timer.After(0, function() btn:Hide() end)
    return true
end

function ACO:StartQueueWorker()
    if self.queueTicker or #self.openQueue == 0 then return end

    if self.UI and self.UI.queueWidget then
        self.UI.queueWidget:Show()
    end

    local selfRef = self
    self.queueTicker = C_Timer.NewTicker(0.1, function()
        selfRef:ProcessQueueTick()
    end)
end

function ACO:FinalizeQueueCycle()
    if #self.openQueue > 0 or (self.pendingVerifications or 0) > 0 then
        return
    end

    if self.queueTicker then
        self.queueTicker:Cancel()
        self.queueTicker = nil
    end

    if self.batchTracker and self.batchTracker.active then
        self:PrintBatchSummary()
    end

    if self.UI and self.UI.queueWidget then
        self.UI.queueWidget:Hide()
    end

    self.queueSessionOpened = 0
end

function ACO:StopQueueWorker()
    if self.queueTicker then
        self.queueTicker:Cancel()
        self.queueTicker = nil
    end
    self:FinalizeQueueCycle()
end

function ACO:PrintBatchSummary()
    local bt = self.batchTracker
    if not bt or not bt.active then return end
    bt.active = false

    if bt.count == 0 then return end

    local goldAfter = GetMoney()
    local goldGained = goldAfter - bt.goldBefore
    local elapsed = GetTime() - bt.startTime

    local msg = format(ACO:Translate("BATCH_SUMMARY"), bt.count, bt.totalQueued)

    if goldGained > 0 then
        msg = msg .. " " .. format(ACO:Translate("BATCH_SUMMARY_GOLD"), self:FormatMoney(goldGained))
        if elapsed > 1 then
            local gph = floor(goldGained / elapsed * 3600)
            msg = msg .. format(ACO:Translate("BATCH_SUMMARY_GPH"), self:FormatMoneyShort(gph))
        end
    end

    msg = msg .. " " .. format(ACO:Translate("BATCH_SUMMARY_TIME"), format("%.1f", elapsed))
    self:Print(msg)
end

function ACO:PauseQueue()
    self.queuePaused = true
    self:NotifyQueueChanged()
end

function ACO:ResumeQueue()
    self.queuePaused = false
    self.queueNextAllowedAt = 0
    self:StartQueueWorker()
    self:NotifyQueueChanged()
end

function ACO:CancelQueue(clearFailures)
    wipe(self.openQueue)
    wipe(self.activeVerifications)
    wipe(self.combatQueue)
    self.pendingVerifications = 0
    self.assistedEntry = nil
    self.queuePaused = false
    self.queueGeneration = (self.queueGeneration or 0) + 1
    if clearFailures then wipe(self.queueFailures) end
    if self.batchTracker then self.batchTracker.active = false end
    if self.UI and self.UI.ConfigureAssistedButtons then self.UI:ConfigureAssistedButtons(nil) end
    self:StopQueueWorker()
    self:NotifyQueueChanged()
end

function ACO:ClearQueueFailures()
    wipe(self.queueFailures)
    self:NotifyQueueChanged()
end

function ACO:GetQueueEntryByID(queueID)
    if not queueID then return nil end
    for _, entry in ipairs(self.openQueue) do
        if entry.queueID == queueID then return entry end
    end
    return self.activeVerifications[queueID]
end

function ACO:RemoveQueueEntry(queueID)
    if not queueID then return false end
    for i = #self.openQueue, 1, -1 do
        if self.openQueue[i].queueID == queueID then
            tremove(self.openQueue, i)
            if self.assistedEntry and self.assistedEntry.queueID == queueID then
                self.assistedEntry = nil
                if self.UI and self.UI.ConfigureAssistedButtons then self.UI:ConfigureAssistedButtons(nil) end
            end
            self:FinalizeQueueCycle()
            self:NotifyQueueChanged()
            return true
        end
    end
    for i = #self.queueFailures, 1, -1 do
        if self.queueFailures[i].queueID == queueID then
            tremove(self.queueFailures, i)
            self:NotifyQueueChanged()
            return true
        end
    end
    return false
end

function ACO:RetryFailedQueueEntry(queueID)
    for i = #self.queueFailures, 1, -1 do
        local failure = self.queueFailures[i]
        if failure.queueID == queueID then
            tremove(self.queueFailures, i)
            local bag, slot, info = self:FindItemInBags(failure.itemID)
            if not bag then
                self:Print(ACO:Translate("QUEUE_ITEM_MISSING", self:FormatItemLink(failure.itemID)), true)
                self:NotifyQueueChanged()
                return false
            end
            local entry = {
                queueID = self:NextQueueID(),
                itemID = failure.itemID,
                bag = bag,
                slot = slot,
                link = (info and info.hyperlink) or failure.link,
                executeAt = GetTime(),
                source = "MANUAL",
                origin = failure.origin or "MANUAL",
                attempt = 0,
                lockTries = 0,
                generation = self.queueGeneration or 0,
                priority = self:GetRulePriority(failure.itemID),
                status = "RETRYING",
                statusReason = nil,
                queuedAt = GetTime(),
            }
            self:InsertOpenQueueEntry(entry)
            self:StartQueueWorker()
            self:NotifyQueueChanged()
            return true
        end
    end
    return false
end

-- Insert an entry into openQueue. Higher per-container priority is processed
-- first; equal priority remains sorted by execution time and FIFO order.
function ACO:SortOpenQueue()
    local now = GetTime()
    table.sort(self.openQueue, function(a, b)
        local ae, be = a.executeAt or 0, b.executeAt or 0
        local aDue, bDue = ae <= now, be <= now
        if aDue ~= bDue then return aDue end
        local ap, bp = tonumber(a.priority) or 0, tonumber(b.priority) or 0
        if aDue and ap ~= bp then return ap > bp end
        if ae ~= be then return ae < be end
        if ap ~= bp then return ap > bp end
        return (a.queuedAt or 0) < (b.queuedAt or 0)
    end)
end

function ACO:InsertOpenQueueEntry(entry)
    if not entry then return end
    tinsert(self.openQueue, entry)
    self:SortOpenQueue()
    self:NotifyQueueChanged()
end

function ACO:EnqueueOpen(itemID, bag, slot, itemLink, executeAt, source)
    if not itemID or not self.db then return false, "INVALID" end
    if not self:CanQueueContainerItem(itemID) then return false, "NOT_OPENABLE" end

    local sourceName = source or "AUTO"
    local allowed, ruleReason = self:CanEnqueueByRule(itemID, sourceName)
    if not allowed then
        self:Debug(format("Règle conteneur %d: %s", itemID, tostring(ruleReason)))
        return false, ruleReason
    end

    if InCombatLockdown() then
        self.combatQueue[itemID] = (self.combatQueue[itemID] or 0) + 1
        return false, "COMBAT"
    end

    local now = GetTime()
    local entry = {
        queueID = self:NextQueueID(),
        itemID = itemID,
        bag = bag,
        slot = slot,
        link = itemLink,
        executeAt = executeAt or now,
        source = sourceName,
        origin = sourceName,
        attempt = 0,
        lockTries = 0,
        generation = self.queueGeneration or 0,
        priority = self:GetRulePriority(itemID),
        status = ((executeAt or now) > now) and "DELAY" or "QUEUED",
        statusReason = nil,
        queuedAt = now,
    }
    self:InsertOpenQueueEntry(entry)
    self:StartQueueWorker()
    return true, nil, entry
end

function ACO:RecordOpenFailure(entry, reason)
    if not self.db or not entry or entry._failureRecorded then return end
    entry._failureRecorded = true
    reason = tostring(reason or "UNKNOWN")

    local stats = self.db.stats
    local diagnostics = self.db.diagnostics
    stats.failedOpened = (stats.failedOpened or 0) + 1
    diagnostics.failedOpenAttempts = (diagnostics.failedOpenAttempts or 0) + 1
    diagnostics.lastFailure = reason
    diagnostics.lastFailureAt = time()
    diagnostics.lastFailureItemID = entry.itemID

    local perItem = self:GetContainerDiagnostic(entry.itemID, true)
    perItem.failed = (perItem.failed or 0) + 1
    perItem.lastFailure = time()
    perItem.lastFailureReason = reason

    local failure = {
        queueID = entry.queueID or self:NextQueueID(),
        itemID = entry.itemID,
        link = entry.link,
        origin = entry.origin,
        attempt = entry.attempt or 0,
        reason = reason,
        status = "FAILED",
        failedAt = time(),
        priority = entry.priority or 0,
    }
    tinsert(self.queueFailures, 1, failure)
    while #self.queueFailures > 30 do tremove(self.queueFailures) end

    tinsert(diagnostics.failureHistory, {
        itemID = entry.itemID,
        reason = reason,
        timestamp = failure.failedAt,
    })
    while #diagnostics.failureHistory > 50 do tremove(diagnostics.failureHistory, 1) end

    entry.status = "FAILED"
    entry.statusReason = reason
    if self.db.queue.stopOnError then self.queuePaused = true end
    self:NotifyQueueChanged()
end

function ACO:ConfirmOpenSuccess(entry)
    if not entry or entry._confirmed then return end
    entry._confirmed = true
    entry.status = "DONE"

    if entry.lootTracker then entry.lootTracker.confirmed = true end

    self:RecordOpening(entry.itemID, entry.lootTracker and entry.lootTracker.goldBefore)
    self.queueSessionOpened = (self.queueSessionOpened or 0) + 1
    self.sessionOpenCounts[entry.itemID] = (self.sessionOpenCounts[entry.itemID] or 0) + 1

    local perItem = self:GetContainerDiagnostic(entry.itemID, true)
    perItem.success = (perItem.success or 0) + 1
    perItem.lastSuccess = time()

    if self.batchTracker.active and entry.origin == "OPENALL" then
        self.batchTracker.count = self.batchTracker.count + 1
    end

    if self.db and self.db.showNotifications and not self.batchTracker.active then
        local link = entry.link or self:FormatItemLink(entry.itemID)
        self:Print(ACO:Translate("OPENING", link))
    end

    if self.db and self.db.notificationSound then PlaySound(self.SOUNDS.OPEN) end

    self:ProcessLootTrackers()
    self:NotifyQueueChanged()
end

function ACO:FinishOpenVerification(entry)
    if entry and entry._verificationFinished then return end
    if entry then
        entry._verificationFinished = true
        if entry.queueID then self.activeVerifications[entry.queueID] = nil end
    end
    self.pendingVerifications = max(0, (self.pendingVerifications or 0) - 1)
    self:FinalizeQueueCycle()
    self:NotifyQueueChanged()
end

function ACO:ScheduleOpenVerification(entry, countBefore)
    local selfRef = self
    local verifyDelay = self.db.queue.verifyDelay or 1.5
    local maxRetries = self.db.queue.maxRetries or 2
    local maxLockedChecks = self.db.queue.maxLockedChecks or 4

    entry.status = "VERIFYING"
    entry.statusReason = nil
    entry.verifyStartedAt = GetTime()
    self.activeVerifications[entry.queueID] = entry
    self.pendingVerifications = (self.pendingVerifications or 0) + 1
    self:NotifyQueueChanged()

    local function Verify(lockCheck)
        if entry.generation ~= (selfRef.queueGeneration or 0) then
            if entry.lootTracker then entry.lootTracker.cancelled = true end
            selfRef:FinishOpenVerification(entry)
            return
        end

        if not selfRef.db or not selfRef.db.enabled then
            if entry.lootTracker then entry.lootTracker.cancelled = true end
            selfRef:FinishOpenVerification(entry)
            return
        end

        local countAfter, bag, slot, info = selfRef:GetItemCountInBags(entry.itemID)
        if countAfter < countBefore then
            selfRef:ConfirmOpenSuccess(entry)
            selfRef:FinishOpenVerification(entry)
            return
        end

        if info and info.isLocked and lockCheck < maxLockedChecks then
            entry.status = "VERIFYING"
            entry.statusReason = "LOCKED"
            selfRef:NotifyQueueChanged()
            C_Timer.After(0.75, function() Verify(lockCheck + 1) end)
            return
        end

        if entry.lootTracker then entry.lootTracker.cancelled = true end

        local attempt = entry.attempt or 0
        if attempt < maxRetries then
            local retryEntry = {
                queueID = entry.queueID,
                itemID = entry.itemID,
                bag = bag,
                slot = slot,
                link = (info and info.hyperlink) or entry.link,
                executeAt = GetTime() + (selfRef.db.queue.retryDelay or 0.6),
                source = "RETRY",
                origin = entry.origin,
                attempt = attempt + 1,
                lockTries = 0,
                generation = entry.generation,
                priority = entry.priority or selfRef:GetRulePriority(entry.itemID),
                status = "RETRYING",
                statusReason = "NOT_CONSUMED",
                queuedAt = entry.queuedAt or GetTime(),
            }
            selfRef:Debug(format("Item %d non consommé, tentative %d/%d", entry.itemID, retryEntry.attempt, maxRetries))
            selfRef:FinishOpenVerification(entry)
            selfRef:InsertOpenQueueEntry(retryEntry)
            selfRef:StartQueueWorker()
            return
        end

        selfRef:RecordOpenFailure(entry, "NOT_CONSUMED")
        local itemLink = (info and info.hyperlink) or selfRef:FormatItemLink(entry.itemID)
        if selfRef.db.blacklist and not (selfRef.db.containers and selfRef.db.containers[entry.itemID]) then
            selfRef.db.blacklist[entry.itemID] = true
            selfRef:Print(ACO:Translate("AUTO_BLACKLISTED", itemLink, entry.itemID), true)
        else
            selfRef:Print(ACO:Translate("OPEN_FAILED_RETRY", itemLink), true)
        end
        selfRef:FinishOpenVerification(entry)
    end

    C_Timer.After(verifyDelay, function() Verify(0) end)
end

function ACO:PrepareAssistedEntry(entry)
    if not entry or InCombatLockdown() then return false end
    local count, bag, slot, info = self:GetItemCountInBags(entry.itemID)
    if count <= 0 or not bag then return false end
    entry.bag, entry.slot = bag, slot
    entry.link = (info and info.hyperlink) or entry.link
    entry.status = "ASSISTED_READY"
    entry.statusReason = nil
    self.assistedEntry = entry
    if self.UI and self.UI.ConfigureAssistedButtons then self.UI:ConfigureAssistedButtons(entry) end
    self:NotifyQueueChanged()
    return true
end

function ACO:PrepareAssistedClick(queueID)
    local entry = self.assistedEntry
    if not entry or entry.queueID ~= queueID then return false end
    local count, bag, slot, info = self:GetItemCountInBags(entry.itemID)
    if count <= 0 or not bag then
        local selfRef = self
        C_Timer.After(0, function()
            for i = #selfRef.openQueue, 1, -1 do
                if selfRef.openQueue[i].queueID == queueID then tremove(selfRef.openQueue, i) break end
            end
            selfRef.assistedEntry = nil
            if selfRef.UI and selfRef.UI.ConfigureAssistedButtons then selfRef.UI:ConfigureAssistedButtons(nil) end
            selfRef:RecordOpenFailure(entry, "MISSING")
        end)
        return false
    end
    entry.bag, entry.slot = bag, slot
    entry.link = (info and info.hyperlink) or entry.link
    entry._assistedCountBefore = count
    entry.status = "OPENING"

    local itemName = info and info.itemName
    if not itemName and entry.link then itemName = entry.link:match("%[(.-)%]") end
    self:NotifyZarctusGold(entry.itemID, itemName)
    entry.lootTracker = self:StartLootTracking(entry.itemID)
    return true
end

function ACO:CompleteAssistedClick(queueID)
    local entry = self.assistedEntry
    if not entry or entry.queueID ~= queueID then return false end

    for i = #self.openQueue, 1, -1 do
        if self.openQueue[i].queueID == queueID then
            tremove(self.openQueue, i)
            break
        end
    end

    self.assistedEntry = nil
    if self.UI and self.UI.ConfigureAssistedButtons then self.UI:ConfigureAssistedButtons(nil) end
    local countBefore = entry._assistedCountBefore or self:CountItemInBags(entry.itemID)
    self.queueNextAllowedAt = GetTime() + (self.db.queue.interval or 0.30)
    self:ScheduleOpenVerification(entry, countBefore)
    self:StartQueueWorker()
    return true
end

function ACO:OpenNextQueueEntry()
    local entry = self.openQueue[1]
    if not entry then return false end
    entry.executeAt = GetTime()
    entry.status = "QUEUED"
    self.queuePaused = false
    self.queueNextAllowedAt = 0
    if self:GetQueueMode() == "assisted" then
        self.assistedEntry = nil
        self:PrepareAssistedEntry(entry)
    else
        self:StartQueueWorker()
    end
    self:NotifyQueueChanged()
    return true
end

function ACO:GetQueueSnapshot()
    local snapshot = {}
    local now = GetTime()
    local blocked, blockReason = self:IsOpeningBlocked()
    local cumulative = 0

    for index, entry in ipairs(self.openQueue) do
        local status = entry.status or "QUEUED"
        local reason = entry.statusReason
        local wait = max(0, (entry.executeAt or now) - now)
        if self.queuePaused then
            status = "PAUSED"
        elseif blocked and index == 1 then
            status = "BLOCKED"
            reason = blockReason
        elseif self.assistedEntry and self.assistedEntry.queueID == entry.queueID then
            status = "ASSISTED_READY"
        elseif wait > 0.05 and status ~= "RETRYING" and status ~= "BLOCKED" then
            status = "DELAY"
        elseif status == "DELAY" then
            status = "QUEUED"
        end
        cumulative = max(cumulative, wait)
        local entryETA = cumulative
        cumulative = cumulative + (self.db.queue.interval or 0.30)
        tinsert(snapshot, {
            queueID = entry.queueID,
            itemID = entry.itemID,
            link = entry.link,
            status = status,
            reason = reason,
            attempt = entry.attempt or 0,
            source = entry.origin or entry.source,
            priority = entry.priority or 0,
            eta = entryETA,
            failed = false,
        })
    end

    for _, entry in pairs(self.activeVerifications) do
        tinsert(snapshot, {
            queueID = entry.queueID,
            itemID = entry.itemID,
            link = entry.link,
            status = entry.status or "VERIFYING",
            reason = entry.statusReason,
            attempt = entry.attempt or 0,
            source = entry.origin or entry.source,
            priority = entry.priority or 0,
            eta = max(0, (entry.verifyStartedAt or now) + (self.db.queue.verifyDelay or 1.5) - now),
            active = true,
            failed = false,
        })
    end

    for _, failure in ipairs(self.queueFailures) do
        tinsert(snapshot, {
            queueID = failure.queueID,
            itemID = failure.itemID,
            link = failure.link,
            status = "FAILED",
            reason = failure.reason,
            attempt = failure.attempt or 0,
            source = failure.origin,
            priority = failure.priority or 0,
            eta = 0,
            failed = true,
        })
    end
    return snapshot
end

function ACO:ProcessAssistedQueueTick()
    if self.queuePaused or #self.openQueue == 0 then return end
    if self.assistedEntry then return end

    local now = GetTime()
    self:SortOpenQueue()
    local blocked, blockReason = self:IsOpeningBlocked()
    local entry = self.openQueue[1]
    local ruleAllowed, ruleReason = self:CanProcessByRule(entry.itemID, entry.origin or entry.source)
    if not ruleAllowed then
        if ruleReason == "TEMP_BLOCK" then
            entry.status = "BLOCKED"
            entry.statusReason = ruleReason
            entry.executeAt = max(entry.executeAt or now, self:GetContainerRule(entry.itemID, false).temporaryBlockUntil - time() + now)
            self:NotifyQueueChanged()
            return
        end
        tremove(self.openQueue, 1)
        self:NotifyQueueChanged()
        return
    end
    if blocked then
        entry.status = "BLOCKED"
        entry.statusReason = blockReason
        self.queueNextAllowedAt = now + 0.5
        self:NotifyQueueChanged()
        return
    end
    if now < (entry.executeAt or 0) then
        entry.status = entry.status == "RETRYING" and "RETRYING" or "DELAY"
        return
    end
    if not self:PrepareAssistedEntry(entry) then
        tremove(self.openQueue, 1)
        self:RecordOpenFailure(entry, "MISSING")
        self:NotifyQueueChanged()
    end
end

function ACO:ProcessQueueTick()
    if #self.openQueue == 0 then
        self:StopQueueWorker()
        return
    end

    if self.queuePaused then return end
    if self:GetQueueMode() == "assisted" then
        self:ProcessAssistedQueueTick()
        return
    end

    if self.assistedEntry then
        self.assistedEntry = nil
        if self.UI and self.UI.ConfigureAssistedButtons then self.UI:ConfigureAssistedButtons(nil) end
    end

    local now = GetTime()
    self:SortOpenQueue()
    local blocked, blockReason = self:IsOpeningBlocked()
    if blocked then
        if self.db and self.db.diagnostics then self.db.diagnostics.lastBlockReason = blockReason end
        local first = self.openQueue[1]
        if first then first.status, first.statusReason = "BLOCKED", blockReason end
        self.queueNextAllowedAt = now + 0.5
        self:NotifyQueueChanged()
        return
    end

    if now < (self.queueNextAllowedAt or 0) then return end

    local entry = self.openQueue[1]
    if entry.executeAt and now < entry.executeAt then
        if entry.status ~= "RETRYING" then entry.status = "DELAY" end
        return
    end
    tremove(self.openQueue, 1)

    if entry.generation ~= (self.queueGeneration or 0) then return end
    if not self:CanQueueContainerItem(entry.itemID) then return end
    local ruleAllowed, ruleReason = self:CanProcessByRule(entry.itemID, entry.origin or entry.source)
    if not ruleAllowed then
        if ruleReason == "TEMP_BLOCK" then
            entry.status = "BLOCKED"
            entry.statusReason = ruleReason
            local rule = self:GetContainerRule(entry.itemID, false)
            entry.executeAt = max(entry.executeAt or now, now + max(0.5, (rule.temporaryBlockUntil or time()) - time()))
            self:InsertOpenQueueEntry(entry)
            self:StartQueueWorker()
        else
            self:NotifyQueueChanged()
        end
        return
    end

    local countBefore, bag, slot, info = self:GetItemCountInBags(entry.itemID)
    if countBefore <= 0 then
        self:NotifyQueueChanged()
        return
    end

    if not entry.bag or not entry.slot then
        entry.bag, entry.slot = bag, slot
        entry.link = (info and info.hyperlink) or entry.link
    end

    entry.status = "OPENING"
    entry.statusReason = nil
    self:NotifyQueueChanged()
    local ok, reason, lootTracker = self:UseContainerFromBagSlot(entry.itemID, entry.bag, entry.slot, entry.link)
    if not ok and reason ~= "LOCKED" then
        local fallbackBag, fallbackSlot, fallbackInfo = self:FindItemInBags(entry.itemID)
        if fallbackBag then
            entry.bag, entry.slot = fallbackBag, fallbackSlot
            entry.link = (fallbackInfo and fallbackInfo.hyperlink) or entry.link
            countBefore = self:CountItemInBags(entry.itemID)
            ok, reason, lootTracker = self:UseContainerFromBagSlot(entry.itemID, fallbackBag, fallbackSlot, entry.link)
        end
    end

    if ok then
        entry.lootTracker = lootTracker
        self.queueNextAllowedAt = now + (self.db.queue.interval or self.queueOpenInterval or 0.30)
        self:ScheduleOpenVerification(entry, countBefore)
        return
    end

    if reason == "LOCKED" then
        entry.lockTries = (entry.lockTries or 0) + 1
        if entry.lockTries <= 25 then
            entry.status = "BLOCKED"
            entry.statusReason = "LOCKED"
            entry.executeAt = now + 0.4
            self:InsertOpenQueueEntry(entry)
            self:StartQueueWorker()
        else
            self:RecordOpenFailure(entry, "LOCKED_TIMEOUT")
        end
    else
        self:RecordOpenFailure(entry, reason or "PROTECTED")
    end
    self:NotifyQueueChanged()
end

-- Public: open one container ASAP (uses the queue worker for lock/backoff handling)
function ACO:OpenItem(itemID)
    if not itemID or not self.db then return false end
    self:EnqueueOpen(itemID, nil, nil, nil, GetTime(), "MANUAL")
    return true
end

-- Public: queue an item (optionally multiple times) after the user's delay
function ACO:QueueItem(itemID, itemLink, bag, slot, count, source)
    if not self.db or not self.db.enabled then return 0 end
    if not itemID then return 0 end
    if not self:CanQueueContainerItem(itemID) then
        self:Debug("CanQueueContainerItem returned false for: " .. itemID)
        return 0
    end

    source = source or "AUTO"
    local allowed, ruleReason = self:CanEnqueueByRule(itemID, source)
    if not allowed then
        self:Debug(format("Item %d ignoré par règle: %s", itemID, tostring(ruleReason)))
        return 0
    end

    count = max(1, tonumber(count) or 1)
    local delay = self:GetRuleDelay(itemID)
    local executeAt = GetTime() + delay

    if self.db.showNotifications then
        local blocked, reason = self:IsOpeningBlocked()
        local reasonText = blocked and self:GetBlockReasonText(reason) or nil
        local link = itemLink or self:FormatItemLink(itemID)
        local display = (count == 1) and link or (link .. " x" .. count)
        if blocked then
            self:Print(ACO:Translate("OPENING_IN_SECONDS_BLOCKED", display, delay, reasonText))
        else
            self:Print(ACO:Translate("OPENING_IN_SECONDS", display, delay))
        end
    end

    local queued = 0
    for _ = 1, count do
        local ok = self:EnqueueOpen(itemID, bag, slot, itemLink, executeAt, source)
        if ok then queued = queued + 1 end
    end
    return queued
end

-- ============================================================================
-- OPEN ALL CONTAINERS
-- ============================================================================

function ACO:OpenAllContainers()
    if not self.db then return 0 end

    local blocked, reason = self:IsOpeningBlocked()
    if blocked and self.db and self.db.showNotifications then
        self:Print(ACO:Translate("OPEN_ALL_DEFERRED", self:GetBlockReasonText(reason)))
    end

    local opened = 0
    local toOpen = {}
    local containers = self.db.containers

    -- Collect all containers in bags (tracked list + auto-detected openable items)
    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                -- Include items from tracked list OR auto-detected as openable
                if containers[info.itemID] or self:CanQueueContainerItem(info.itemID) then
                    local allowed = self:CanEnqueueByRule(info.itemID, "OPENALL")
                    if allowed then
                        local qty = max(1, tonumber(info.stackCount) or 1)
                        for _ = 1, qty do
                            tinsert(toOpen, { bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink })
                        end
                    end
                end
            end
        end
    end

    if #toOpen == 0 then
        self:Print(ACO:Translate("NO_CONTAINERS_FOUND"))
        return 0
    end

    -- Enqueue with rule-aware priority and a small cadence between equal priorities.
    local delayBetween = self.db.queue.interval or 0.30
    local startAt = GetTime()
    local queued = 0
    for i, data in ipairs(toOpen) do
        local ruleDelay = self:GetContainerRule(data.itemID, false).delay
        local executeAt = startAt + (ruleDelay ~= nil and ruleDelay or ((i - 1) * delayBetween))
        local ok = self:EnqueueOpen(data.itemID, data.bag, data.slot, data.link, executeAt, "OPENALL")
        if ok then queued = queued + 1 end
    end

    if self.db.showNotifications then
        self:Print(ACO:Translate("OPEN_ALL_RESULT", queued))
    end

    -- Start batch tracking for summary notification
    self.batchTracker.active = true
    self.batchTracker.count = 0
    self.batchTracker.totalQueued = queued
    self.batchTracker.goldBefore = GetMoney()
    self.batchTracker.startTime = GetTime()

    return queued
end

-- ============================================================================
-- PENDING CONTAINERS QUERY (used by UI)
-- ============================================================================

function ACO:GetPendingContainersInBags()
    local result = {}
    if not self.db then return result end

    local containers = self.db.containers
    local seen = {}

    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and containers[info.itemID] then
                local id = info.itemID
                if seen[id] then
                    seen[id].count = seen[id].count + (info.stackCount or 1)
                else
                    local entry = {
                        itemID = id,
                        link = info.hyperlink,
                        bag = bag,
                        slot = slot,
                        count = info.stackCount or 1,
                    }
                    seen[id] = entry
                    tinsert(result, entry)
                end
            end
        end
    end

    return result
end

-- ============================================================================
-- CONTAINER MANAGEMENT
-- ============================================================================

function ACO:AddContainer(itemID)
    if not itemID or itemID == 0 then return false end

    if self.db.containers[itemID] then
        self:Print(ACO:Translate("ITEM_ALREADY_LISTED"), true)
        return false
    end

    if self.db.blacklist then
        self.db.blacklist[itemID] = nil
    end

    self.db.containers[itemID] = true
    self:GetContainerRule(itemID, true)

    -- Clear cache for this item so it's recognized immediately
    self.containerCache[itemID] = nil

    local itemLink = self:FormatItemLink(itemID)
    self:Print(ACO:Translate("ADDED", itemLink))

    if self.db.notificationSound then
        PlaySound(self.SOUNDS.ADD)
    end

    -- Refresh UI if open
    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end

    -- Auto-queue existing items of this type in bags (if enabled)
    if self.db.enabled then
        self:QueueExistingContainers(itemID)
    end

    return true
end

-- Queue all existing containers of a specific itemID in bags for opening
function ACO:QueueExistingContainers(itemID)
    if not itemID then return 0 end

    local count = 0
    if not self:CanQueueContainerItem(itemID) then
        return 0
    end

    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID == itemID then
                local qty = info.stackCount or 1
                self:QueueItem(itemID, info.hyperlink, bag, slot, qty, "AUTO")
                count = count + qty
            end
        end
    end

    if count > 0 then
        self:Debug(format("Trouvé %d item(s) existant(s) pour ID %d", count, itemID))
    end

    return count
end

function ACO:RemoveContainer(itemID)
    if not itemID then return false end

    if not self.db.containers[itemID] then
        self:Print(ACO:Translate("ITEM_NOT_LISTED"), true)
        return false
    end

    self.db.containers[itemID] = nil
    if self.db.containerRules then self.db.containerRules[itemID] = nil end

    local itemLink = self:FormatItemLink(itemID)
    self:Print(ACO:Translate("REMOVED", itemLink))

    if self.db.notificationSound then
        PlaySound(self.SOUNDS.REMOVE)
    end

    -- Refresh UI if open
    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end

    return true
end

function ACO:RemoveAllContainers()
    if not self.db or not self.db.containers then return 0 end

    local count = 0
    for itemID in pairs(self.db.containers) do
        count = count + 1
    end

    if count == 0 then
        self:Print(ACO:Translate("NO_CONTAINERS_TO_REMOVE"))
        return 0
    end

    -- Clear all containers and their per-item rules
    wipe(self.db.containers)
    if self.db.containerRules then wipe(self.db.containerRules) end

    self:Print(ACO:Translate("REMOVED_COUNT", count))

    if self.db.notificationSound then
        PlaySound(self.SOUNDS.REMOVE)
    end

    -- Refresh UI if open
    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end

    return count
end

function ACO:AddToBlacklist(itemID)
    if not itemID then return false end

    self.db.blacklist[itemID] = true
    local itemLink = self:FormatItemLink(itemID)
    self:Print(ACO:Translate("BLACKLISTED", itemLink))

    return true
end

function ACO:ClearBlacklist()
    if not self.db then return end
    local count = 0
    for _ in pairs(self.db.blacklist) do count = count + 1 end
    wipe(self.db.blacklist)
    self:Print(ACO:Translate("BLACKLIST_CLEARED", count))
end

function ACO:RemoveFromBlacklist(itemID)
    if not itemID then return false end

    self.db.blacklist[itemID] = nil
    local itemLink = self:FormatItemLink(itemID)
    self:Print(ACO:Translate("REMOVED_FROM_BLACKLIST", itemLink))

    return true
end

-- ============================================================================
-- STATISTICS & HISTORY
-- ============================================================================

-- Record an opening event
function ACO:RecordOpening(itemID, goldBefore)
    if not self.db or not itemID then return end

    local stats = self.db.stats
    local currentTime = time()

    -- Update counters
    stats.totalOpened = (stats.totalOpened or 0) + 1
    stats.totalOpenedSession = (stats.totalOpenedSession or 0) + 1

    -- Track per-item stats
    stats.itemsOpened = stats.itemsOpened or {}
    stats.itemsOpened[itemID] = (stats.itemsOpened[itemID] or 0) + 1

    -- Update timestamps
    if not stats.firstOpen then
        stats.firstOpen = currentTime
    end
    stats.lastOpen = currentTime

    -- Add to history first (gold will be updated later via tracker)
    local historyEntry = self:AddToHistory(itemID, currentTime)

    -- Start gold tracking with direct reference to the history entry
    self:StartGoldTracking(itemID, historyEntry, goldBefore)

    -- Refresh UI if stats tab is visible
    if self.UI and self.UI.RefreshStats then
        self.UI:RefreshStats()
    end
end

-- Start tracking gold for a specific container opening.
-- Uses a queue so that rapid batch openings don't clobber each other.
function ACO:StartGoldTracking(itemID, historyEntry, goldBefore)
    local goldNow = tonumber(goldBefore) or GetMoney()

    -- Try to finalize any already-pending trackers whose gold has arrived
    self:ProcessGoldTrackers(goldNow)

    -- Push a new tracker for this opening
    local tracker = {
        goldBefore = goldNow,
        historyEntry = historyEntry,
        itemID = itemID,
        resolved = false,
        timestamp = GetTime(),
    }
    tinsert(self.goldTrackerQueue, tracker)

    -- Schedule delayed processing (server-lag resilience)
    local selfRef = self
    C_Timer.After(0.5, function() selfRef:ProcessGoldTrackers(GetMoney()) end)
    C_Timer.After(1.5, function() selfRef:ProcessGoldTrackers(GetMoney()) end)
    C_Timer.After(5.0, function() selfRef:CleanupGoldTrackers() end)
end

-- Walk the tracker queue and finalise every entry whose gold delta is known.
function ACO:ProcessGoldTrackers(goldNow)
    local queue = self.goldTrackerQueue
    local i = 1
    while i <= #queue do
        if queue[i].resolved then
            tremove(queue, i)
        else
            -- For tracker i the gold-after boundary is:
            --   * goldBefore of the NEXT tracker (if one exists), or
            --   * the current GetMoney() for the last (most recent) tracker.
            local goldAfter
            if queue[i + 1] then
                goldAfter = queue[i + 1].goldBefore
            else
                goldAfter = goldNow
            end

            local goldGained = goldAfter - queue[i].goldBefore
            if goldGained > 0 then
                self:FinalizeGoldTracker(queue[i], goldGained)
                tremove(queue, i)
            else
                i = i + 1
            end
        end
    end
end

-- Apply the gold result to a single tracker's history entry and stats.
function ACO:FinalizeGoldTracker(tracker, goldGained)
    if tracker.resolved then return end
    tracker.resolved  = true

    local stats       = self.db.stats
    stats.totalGold   = (stats.totalGold or 0) + goldGained
    stats.sessionGold = (stats.sessionGold or 0) + goldGained

    if tracker.historyEntry then
        tracker.historyEntry.goldGained = goldGained
    end

    self:Debug(format("Or gagn\195\169: %s", self:FormatMoney(goldGained)))

    if self.UI and self.UI.RefreshStats then
        self.UI:RefreshStats()
    end
    if self.UI and self.UI.RefreshHistory then
        self.UI:RefreshHistory()
    end
end

-- Safety net: discard trackers that never received gold after a long timeout.
function ACO:CleanupGoldTrackers()
    local queue = self.goldTrackerQueue
    self:ProcessGoldTrackers(GetMoney())

    -- Each opening schedules cleanup. Never wipe the whole queue here: a newer
    -- batch entry may have been appended after an older timer was created.
    local now = GetTime()
    for i = #queue, 1, -1 do
        local tracker = queue[i]
        if tracker.resolved or (now - (tracker.timestamp or now)) >= 5.0 then
            tremove(queue, i)
        end
    end
end

-- ============================================================================
-- LOOT TRACKING (captures items, gold, currencies from container openings)
-- ============================================================================

-- Take a full bag item snapshot (itemID -> {count, link}) across all tracked bags
function ACO:TakeBagItemSnapshot()
    local snapshot = {} -- [itemID] = { count=N, link="..." }
    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                local id = info.itemID
                local qty = info.stackCount or 1
                if snapshot[id] then
                    snapshot[id].count = snapshot[id].count + qty
                else
                    snapshot[id] = { count = qty, link = info.hyperlink }
                end
            end
        end
    end
    return snapshot
end

-- Called right BEFORE UseContainerItem to snapshot the current state.
function ACO:StartLootTracking(containerItemID)
    if not self.db then return end

    -- Process any already-pending trackers whose loot may have arrived
    self:ProcessLootTrackers()

    local tracker = {
        containerItemID = containerItemID,
        bagSnapshot     = self:TakeBagItemSnapshot(),
        goldBefore      = GetMoney(),
        currencies      = {}, -- filled by CHAT_MSG_CURRENCY
        lootItems       = {}, -- filled by CHAT_MSG_LOOT
        timestamp       = GetTime(),
        resolved        = false,
        confirmed       = false,
        cancelled       = false,
    }
    tinsert(self.lootTrackerQueue, tracker)

    -- Schedule delayed processing (must wait for server to send bag updates)
    local selfRef = self
    C_Timer.After(1.5, function() selfRef:ProcessLootTrackers() end)
    C_Timer.After(3.0, function() selfRef:ProcessLootTrackers() end)
    C_Timer.After(6.0, function() selfRef:CleanupLootTrackers() end)
    return tracker
end

function ACO:ProcessLootTrackers()
    local queue = self.lootTrackerQueue
    local i = 1
    while i <= #queue do
        if queue[i].resolved or queue[i].cancelled then
            tremove(queue, i)
        elseif not queue[i].confirmed then
            -- An issued action is not evidence of an opening. Wait until the
            -- queue verifier confirms that the container count decreased.
            i = i + 1
        else
            -- Boundary: use the next confirmed tracker. Cancelled or still
            -- unverified attempts must not split the loot window.
            local afterSnapshot, goldAfter
            local nextConfirmed
            for j = i + 1, #queue do
                local candidate = queue[j]
                if candidate.confirmed and not candidate.cancelled and not candidate.resolved then
                    nextConfirmed = candidate
                    break
                end
            end
            if nextConfirmed then
                afterSnapshot = nextConfirmed.bagSnapshot
                goldAfter = nextConfirmed.goldBefore
            else
                afterSnapshot = self:TakeBagItemSnapshot()
                goldAfter = GetMoney()
            end

            -- Diff items: find what was gained
            local gained = {} -- [itemID] = { count=N, link="..." }
            for itemID, newData in pairs(afterSnapshot) do
                local oldCount = 0
                if queue[i].bagSnapshot[itemID] then
                    oldCount = queue[i].bagSnapshot[itemID].count or 0
                end
                local newCount = newData.count or 0
                if newCount > oldCount then
                    -- Exclude the container itself (it was consumed)
                    if itemID ~= queue[i].containerItemID then
                        gained[itemID] = { count = newCount - oldCount, link = newData.link }
                    end
                end
            end

            -- Gold diff
            local goldGained = goldAfter - queue[i].goldBefore
            if goldGained < 0 then goldGained = 0 end

            -- Finalize when we have data or enough time has passed
            local elapsed = GetTime() - queue[i].timestamp
            if next(gained) or goldGained > 0 or next(queue[i].currencies) or elapsed > 2.5 then
                self:FinalizeLootTracker(queue[i], gained, goldGained)
                tremove(queue, i)
            else
                i = i + 1
            end
        end
    end
end

function ACO:FinalizeLootTracker(tracker, gained, goldGained)
    if tracker.resolved then return end
    tracker.resolved = true
    if not self.db then return end

    local containerID = tracker.containerItemID
    local summary = self.db.lootSummary

    if not summary[containerID] then
        summary[containerID] = {
            opened     = 0,
            gold       = 0,
            items      = {},
            currencies = {},
        }
    end

    local entry  = summary[containerID]
    entry.opened = (entry.opened or 0) + 1
    entry.gold   = (entry.gold or 0) + goldGained

    -- Merge chat-captured loot first; bag diffs remain the preferred source,
    -- but CHAT_MSG_LOOT fills timing gaps and must be persisted as well.
    if tracker.lootItems then
        for itemID, data in pairs(tracker.lootItems) do
            if not gained[itemID] then
                gained[itemID] = { count = data.count, link = data.link }
            elseif data.link and not gained[itemID].link then
                gained[itemID].link = data.link
            end
        end
    end

    -- Merge gained items into the persistent summary.
    for itemID, data in pairs(gained) do
        if not entry.items[itemID] then
            entry.items[itemID] = { count = 0 }
        end
        local it = entry.items[itemID]
        if type(it) == "number" then
            it = { count = it }
            entry.items[itemID] = it
        end
        it.count = (it.count or 0) + (data.count or data)
        if type(data) == "table" and data.link then
            it.link = data.link
        end
    end

    -- Merge currencies
    for currencyID, count in pairs(tracker.currencies) do
        entry.currencies[currencyID] = (entry.currencies[currencyID] or 0) + count
    end

    self:Debug(format("Loot tracked for container %d: %d item(s), %s gold, %d currency type(s)",
        containerID,
        self:CountTable(gained),
        self:FormatMoneyShort(goldGained),
        self:CountTable(tracker.currencies)))

    if self.UI and self.UI.RefreshLootSummary then
        self.UI:RefreshLootSummary()
    end
end

function ACO:CleanupLootTrackers()
    self:ProcessLootTrackers()
    local queue = self.lootTrackerQueue
    local now = GetTime()

    -- Clean only stale entries. A cleanup timer from an older opening must not
    -- erase trackers created later by a batch or retry.
    for i = #queue, 1, -1 do
        local tracker = queue[i]
        local age = now - (tracker.timestamp or now)
        if tracker.resolved or tracker.cancelled then
            tremove(queue, i)
        elseif tracker.confirmed and age >= 6.0 then
            self:FinalizeLootTracker(tracker, {}, 0)
            tremove(queue, i)
        elseif not tracker.confirmed and age >= 10.0 then
            tremove(queue, i)
        end
    end
end

-- Get formatted loot summary for UI (sorted by opened count desc)
function ACO:GetLootSummary()
    local result = {}
    if not self.db or not self.db.lootSummary then return result end

    for containerID, data in pairs(self.db.lootSummary) do
        local entry = {
            containerID = containerID,
            opened      = data.opened or 0,
            gold        = data.gold or 0,
            items       = {},
            currencies  = {},
        }

        -- Build sorted items list
        for itemID, itemData in pairs(data.items or {}) do
            -- Support legacy format (plain number) and new format ({count=, link=})
            local count, link
            if type(itemData) == "number" then
                count = itemData
                link = nil
            else
                count = itemData.count or 0
                link = itemData.link
            end
            tinsert(entry.items, { itemID = itemID, count = count, link = link })
        end
        table.sort(entry.items, function(a, b) return a.count > b.count end)

        -- Build sorted currencies list
        for currencyID, count in pairs(data.currencies or {}) do
            tinsert(entry.currencies, { currencyID = currencyID, count = count })
        end
        table.sort(entry.currencies, function(a, b) return a.count > b.count end)

        tinsert(result, entry)
    end

    table.sort(result, function(a, b) return a.opened > b.opened end)
    return result
end

-- ============================================================================
-- ROI / PROFITABILITY INTELLIGENCE
-- ============================================================================

-- Returns total vendor sell value (copper) of all items ever received from a container.
function ACO:GetContainerVendorValue(containerID)
    if not self.db or not self.db.lootSummary then return 0 end
    local data = self.db.lootSummary[containerID]
    if not data or not data.items then return 0 end
    local total = 0
    for itemID, itemData in pairs(data.items) do
        local count = type(itemData) == "number" and itemData or (itemData.count or 0)
        -- 12.1: C_Item.GetItemSellPrice is not part of the generated Retail API.
        -- C_Item.GetItemInfo returns sellPrice as its 11th result.
        local sellPrice = nil
        if C_Item and C_Item.GetItemInfo then
            sellPrice = select(11, C_Item.GetItemInfo(itemID))
        end
        if IsAccessibleValue(sellPrice) and sellPrice > 0 then
            total = total + sellPrice * count
        end
    end
    return total
end

-- Returns per-open ROI stats for a container based on loot history.
-- Returns nil if the container has never been opened.
function ACO:GetContainerAvgValue(containerID)
    if not self.db or not self.db.lootSummary then return nil end
    local data = self.db.lootSummary[containerID]
    if not data or (data.opened or 0) == 0 then return nil end
    local opens       = data.opened
    local goldTotal   = data.gold or 0
    local vendorTotal = self:GetContainerVendorValue(containerID)
    return {
        opens     = opens,
        avgGold   = floor(goldTotal / opens),
        avgVendor = floor(vendorTotal / opens),
        avgTotal  = floor((goldTotal + vendorTotal) / opens),
    }
end

-- Returns up to n containers sorted by average total value (gold + vendor) descending.
function ACO:GetTopContainersByROI(n)
    if not self.db or not self.db.lootSummary then return {} end
    n = n or 5
    local result = {}
    for containerID, data in pairs(self.db.lootSummary) do
        if (data.opened or 0) > 0 then
            local roi = self:GetContainerAvgValue(containerID)
            if roi then
                tinsert(result, { containerID = containerID, roi = roi })
            end
        end
    end
    table.sort(result, function(a, b)
        return a.roi.avgTotal > b.roi.avgTotal
    end)
    while #result > n do
        tremove(result)
    end
    return result
end

function ACO:ClearLootSummary()
    if not self.db then return end
    wipe(self.db.lootSummary)
    self:Print(ACO:Translate("LOOT_SUMMARY_CLEARED"))
    if self.UI and self.UI.RefreshLootSummary then
        self.UI:RefreshLootSummary()
    end
end

-- Format money (copper) to gold/silver/copper string
function ACO:FormatMoney(copper)
    if not copper or copper == 0 then return "0" end

    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)
    local copperRem = copper % 100

    local result = ""
    if gold > 0 then
        result = format("|cffffd700%d|r|TInterface\\MoneyFrame\\UI-GoldIcon:0|t ", gold)
    end
    if silver > 0 or gold > 0 then
        result = result .. format("|cffc7c7cf%d|r|TInterface\\MoneyFrame\\UI-SilverIcon:0|t ", silver)
    end
    result = result .. format("|cffeda55f%d|r|TInterface\\MoneyFrame\\UI-CopperIcon:0|t", copperRem)

    return result
end

-- Format money short (just numbers)
function ACO:FormatMoneyShort(copper)
    if not copper or copper == 0 then return "0g" end

    local gold = floor(copper / 10000)
    local silver = floor((copper % 10000) / 100)

    if gold > 0 then
        if silver > 0 then
            return format("%dg %ds", gold, silver)
        end
        return format("%dg", gold)
    elseif silver > 0 then
        return format("%ds", silver)
    else
        return format("%dc", copper)
    end
end

-- Add entry to history (FIFO, max 50 entries)
function ACO:AddToHistory(itemID, timestamp)
    local history = self.db.history
    local maxSize = self.db.historyMaxSize or 50

    -- Get item info
    local itemName, itemLink = C_Item.GetItemInfo(itemID)
    local itemIcon = C_Item.GetItemIconByID(itemID)

    -- Create history entry
    local entry = {
        itemID = itemID,
        itemName = itemName or "Unknown",
        itemIcon = itemIcon,
        timestamp = timestamp,
        character = UnitName("player"),
        goldGained = 0, -- Will be updated by CheckGoldGained
    }

    -- Insert at beginning (most recent first)
    tinsert(history, 1, entry)

    -- Trim to max size
    while #history > maxSize do
        tremove(history)
    end

    return entry
end

-- Get formatted statistics
function ACO:GetStats()
    local stats = self.db.stats
    return {
        totalOpened = stats.totalOpened or 0,
        sessionOpened = stats.totalOpenedSession or 0,
        uniqueItems = self:CountTable(stats.itemsOpened or {}),
        firstOpen = stats.firstOpen,
        lastOpen = stats.lastOpen,
        topItems = self:GetTopOpenedItems(5),
        totalGold = stats.totalGold or 0,
        sessionGold = stats.sessionGold or 0,
    }
end

-- Count entries in a table
function ACO:CountTable(t)
    local count = 0
    for _ in pairs(t) do
        count = count + 1
    end
    return count
end

-- Get top N most opened items
function ACO:GetTopOpenedItems(n)
    local items = {}
    local itemsOpened = self.db.stats.itemsOpened or {}

    for itemID, count in pairs(itemsOpened) do
        tinsert(items, { itemID = itemID, count = count })
    end

    -- Sort by count descending
    table.sort(items, function(a, b) return a.count > b.count end)

    -- Return top N
    local result = {}
    for i = 1, min(n, #items) do
        result[i] = items[i]
    end
    return result
end

-- Format timestamp to readable date
function ACO:FormatTimestamp(timestamp)
    if not timestamp then return self:Translate("TIME_NEVER") end
    return date("%d/%m/%Y %H:%M", timestamp)
end

-- Format relative time using locale keys
function ACO:FormatRelativeTime(timestamp)
    if not timestamp then return self:Translate("TIME_NEVER") end

    local diff = time() - timestamp

    if diff < 60 then
        return self:Translate("TIME_NOW")
    elseif diff < 3600 then
        local mins = floor(diff / 60)
        return self:Translate("TIME_MINUTES_AGO", mins)
    elseif diff < 86400 then
        local hours = floor(diff / 3600)
        return self:Translate("TIME_HOURS_AGO", hours)
    else
        local days = floor(diff / 86400)
        return self:Translate("TIME_DAYS_AGO", days, days > 1 and "s" or "")
    end
end

-- Get history entries
function ACO:GetHistory(limit)
    limit = limit or 50
    local result = {}
    local history = self.db.history or {}

    for i = 1, min(limit, #history) do
        result[i] = history[i]
    end
    return result
end

-- Clear statistics
function ACO:ClearStats()
    self.db.stats = {
        totalOpened = 0,
        totalOpenedSession = 0,
        itemsOpened = {},
        firstOpen = nil,
        lastOpen = nil,
        totalGold = 0,
        sessionGold = 0,
    }
    self:Print(ACO:Translate("STATS_CLEARED"))
    if self.UI and self.UI.RefreshStats then
        self.UI:RefreshStats()
    end
end

-- Clear history
function ACO:ClearHistory()
    wipe(self.db.history)
    self:Print(ACO:Translate("HISTORY_CLEARED"))
    if self.UI and self.UI.RefreshHistory then
        self.UI:RefreshHistory()
    end
end

-- Clear loot summary
function ACO:ClearLootSummaryData()
    self:ClearLootSummary()
end

-- ============================================================================
-- AUTO-DISCOVERY HOOK (Feature: detect containers on manual use)
-- ============================================================================

function ACO:SetupAutoDiscoveryHook()
    if self._autoDiscoveryHooked then return end
    self._autoDiscoveryHooked = true
    self._discoveredItems = {}

    -- IMPORTANT: The hooksecurefunc callback runs inside the SAME secure call
    -- stack as the ContainerFrameItemButton OnClick.  Any insecure work done
    -- here (tooltip scanning, table writes, sound playback, queue management)
    -- taints the entire call chain and, over time, makes bag buttons stop
    -- responding to clicks.
    --
    -- Fix: capture only the minimal data we need (bag, slot, itemID, hyperlink)
    -- and defer ALL processing to the NEXT frame via C_Timer.After(0, ...).
    -- This breaks the taint chain because the deferred callback runs in its
    -- own independent (insecure) execution path.
    hooksecurefunc(C_Container, "UseContainerItem", function(bag, slot)
        if not ACO.db or not ACO.db.enabled then return end
        if not ACO.db.autoDiscovery then return end

        -- Capture info NOW (the item may be gone by the time the timer fires)
        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info or not info.itemID then return end

        local itemID    = info.itemID
        local hyperlink = info.hyperlink

        -- Quick early-outs that don't touch any addon state
        if ACO.db.containers[itemID] then return end
        if ACO.db.blacklist and ACO.db.blacklist[itemID] then return end
        if ACO._discoveredItems and ACO._discoveredItems[itemID] then return end

        -- Defer everything else to break the secure call-chain
        C_Timer.After(0, function()
            ACO:ProcessAutoDiscovery(itemID, hyperlink)
        end)
    end)
end

-- Deferred auto-discovery processing (runs outside the secure call stack)
function ACO:ProcessAutoDiscovery(itemID, hyperlink)
    if not self.db or not self.db.enabled then return end
    if not self.db.autoDiscovery then return end

    -- Re-check (state may have changed between capture and now)
    if self.db.containers[itemID] then return end
    if self.db.blacklist and self.db.blacklist[itemID] then return end
    if self._discoveredItems[itemID] then return end

    -- Exclude equippable items / real bags
    if C_Item.GetItemInfoInstant then
        local _, _, _, eqLoc, _, classID = C_Item.GetItemInfoInstant(itemID)
        if eqLoc and eqLoc ~= "" and eqLoc ~= "INVTYPE_NON_EQUIP" then return end
        if classID == 1 or classID == 11 then return end
    end

    -- Use IsContainerItem which has all the improved detection logic
    self.containerCache[itemID] = nil
    local isContainer = self:IsContainerItem(itemID)

    if isContainer then
        self._discoveredItems[itemID] = true
        self.db.containers[itemID] = true
        self.containerCache[itemID] = nil

        local link = hyperlink or self:FormatItemLink(itemID)
        self:Print(format(ACO:Translate("AUTO_DISCOVER_PROMPT"), link, itemID))

        if self.db.notificationSound then
            PlaySound(self.SOUNDS.ADD)
        end

        if self.UI and self.UI.RefreshList then
            self.UI:RefreshList()
        end

        if self.db.enabled then
            self:QueueExistingContainers(itemID)
        end
    end
end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local EventFrame = CreateFrame("Frame")
ACO.EventFrame = EventFrame

local events = {}

events["ADDON_LOADED"] = function(self, addonLoaded)
    if addonLoaded ~= addonName then return end

    -- Initialize and migrate saved variables. This is a deep migration: nested
    -- settings added in later versions are restored without destroying user data.
    AutoChestOpenerDB = ACO:MigrateDatabase(AutoChestOpenerDB)
    ACO.db = AutoChestOpenerDB
    ACO.queueOpenInterval = ACO.db.queue.interval

    local apiOK, missing = ACO:ValidateRuntimeAPI()
    if not apiOK then
        ACO:Print("API Retail incomplète: " .. table.concat(missing, ", "), true)
    elseif ACO.runtimeInterface ~= ACO.SUPPORTED_INTERFACE then
        ACO:Debug(format("Interface client %d, addon ciblé %d", ACO.runtimeInterface, ACO.SUPPORTED_INTERFACE))
    end

    if ACO._migratedFromSchema and ACO._migratedFromSchema < ACO.DB_SCHEMA_VERSION then
        ACO:Debug(format("Base de données migrée du schéma %d vers %d", ACO._migratedFromSchema, ACO.DB_SCHEMA_VERSION))
    end

    -- Initialize bag state immediately to prevent false "new item" detections
    ACO.bagStateInitialized = false

    ACO:Print(ACO:Translate("ADDON_LOADED"))

    -- Initialize LDB DataBroker launcher
    ACO:InitLDB()

    -- Initialize UI after a short delay
    C_Timer.After(0.5, function()
        if ACO.InitUI then
            ACO:InitUI()
        end
    end)
end

events["PLAYER_ENTERING_WORLD"] = function(self, isInitialLogin, isReloadingUi)
    -- Reset session counters (sessionGold/totalOpenedSession live in SavedVariables
    -- but must restart from zero each login/reload).
    if ACO.db and ACO.db.stats then
        ACO.db.stats.sessionGold = 0
        ACO.db.stats.totalOpenedSession = 0
    end
    wipe(ACO.sessionOpenCounts)
    wipe(ACO.queueFailures)
    wipe(ACO.activeVerifications)
    ACO.pendingVerifications = 0
    ACO.assistedEntry = nil

    -- Setup auto-discovery hook
    ACO:SetupAutoDiscoveryHook()

    -- Initialize bag state after a short delay without triggering openings
    C_Timer.After(1, function()
        if ACO.db then
            ACO:Debug("Initialisation de l'état des sacs au chargement...")
            ACO:InitializeBagState()
            ACO.bagStateInitialized = true
            ACO:Debug("État des sacs prêt - détection des nouveaux items activée")

            -- Queue any containers already present in bags at startup/reload.
            -- InitializeBagState only snapshots the current state; without this,
            -- items that were in bags before login (or across a /reload) are never opened.
            if ACO.db.enabled then
                for itemID in pairs(ACO.db.containers) do
                    ACO:QueueExistingContainers(itemID)
                end
            end

            -- Auto-open on login: if enabled, open all tracked containers 3s after
            -- bags are ready (gives the UI time to fully settle after a login/reload).
            if ACO.db.enabled and ACO.db.autoOpenOnLogin then
                C_Timer.After(3, function()
                    if ACO.db and ACO.db.enabled then
                        ACO:OpenAllContainers()
                    end
                end)
            end
        end
    end)
end

events["BAG_UPDATE"] = function(self, bagID)
    if not ACO.bagStateInitialized then return end
    ACO:MarkBagDirty(bagID)
end

events["BAG_UPDATE_DELAYED"] = function(self)
    -- Only scan if bag state has been initialized (prevents false positives at login)
    if not ACO.bagStateInitialized then
        ACO:Debug("BAG_UPDATE_DELAYED ignoré - état des sacs non initialisé")
        return
    end
    -- Prefer targeted scan: if BAG_UPDATE already marked dirty bags, just ensure a scan happens.
    -- If nothing is dirty (some UI actions don't fire BAG_UPDATE consistently), fallback to full inventory.
    if next(ACO.dirtyBags) then
        ACO:ScheduleBagScan()
    else
        ACO:MarkAllBagsDirty()
    end
end

events["PLAYER_REGEN_ENABLED"] = function(self)
    -- Process queued items after leaving combat (preserves stack counts)
    if not ACO.db then return end
    for itemID, qty in pairs(ACO.combatQueue) do
        if qty and qty > 0 and ACO:CanQueueContainerItem(itemID) then
            ACO:QueueItem(itemID, nil, nil, nil, qty)
        end
    end
    wipe(ACO.combatQueue)
end

-- ============================================================================
-- BLOCKERS (combat/merchant/bank/mail/auction/trade)
-- These events let us pause opening so we never accidentally SELL / MAIL / BANK items.
-- ============================================================================

events["PLAYER_REGEN_DISABLED"] = function(self)
    -- Nothing to do: IsOpeningBlocked() already checks InCombatLockdown().
    -- We keep this for completeness / potential future UI feedback.
end

events["MERCHANT_SHOW"] = function(self)
    ACO:SetBlocker("merchant", true)
end
events["MERCHANT_CLOSED"] = function(self)
    ACO:SetBlocker("merchant", false)
end

events["TRADE_SHOW"] = function(self)
    ACO:SetBlocker("trade", true)
end
events["TRADE_CLOSED"] = function(self)
    ACO:SetBlocker("trade", false)
end

events["AUCTION_HOUSE_SHOW"] = function(self)
    ACO:SetBlocker("auction", true)
end
events["AUCTION_HOUSE_CLOSED"] = function(self)
    ACO:SetBlocker("auction", false)
end

events["BANKFRAME_OPENED"] = function(self)
    ACO:SetBlocker("bank", true)
end
events["BANKFRAME_CLOSED"] = function(self)
    ACO:SetBlocker("bank", false)
end

events["GUILDBANKFRAME_OPENED"] = function(self)
    ACO:SetBlocker("guildbank", true)
end
events["GUILDBANKFRAME_CLOSED"] = function(self)
    ACO:SetBlocker("guildbank", false)
end

events["MAIL_SHOW"] = function(self)
    ACO:SetBlocker("mail", true)
end
events["MAIL_CLOSED"] = function(self)
    ACO:SetBlocker("mail", false)
end

-- Void Storage (may not exist on all Retail builds; registered safely)
events["VOID_STORAGE_OPEN"] = function(self)
    ACO:SetBlocker("voidstorage", true)
end
events["VOID_STORAGE_CLOSE"] = function(self)
    ACO:SetBlocker("voidstorage", false)
end

-- Loot window (opening containers while looting can cause issues)
events["LOOT_OPENED"] = function(self)
    ACO:SetBlocker("loot", true)
end
events["LOOT_CLOSED"] = function(self)
    ACO:SetBlocker("loot", false)
end

-- Scrapping machine
events["SCRAPPING_MACHINE_SHOW"] = function(self)
    ACO:SetBlocker("scrapping", true)
end
events["SCRAPPING_MACHINE_CLOSE"] = function(self)
    ACO:SetBlocker("scrapping", false)
end

-- Item loot tracking (captures item gains during loot tracker window)
events["CHAT_MSG_LOOT"] = function(self, msg)
    if #ACO.lootTrackerQueue == 0 then return end
    if not msg then return end

    -- Parse item ID from hyperlink: |Hitem:XXXX:...|h
    local itemIDStr = msg:match("|Hitem:(%d+)")
    if not itemIDStr then return end
    local itemID = tonumber(itemIDStr)
    if not itemID then return end

    -- Parse count: "x5" at the end, or 1 if absent
    local count = tonumber(msg:match("x(%d+)")) or 1

    -- Extract full hyperlink
    local link = msg:match("|Hitem:[^|]+|h%[[^%]]+%]|h")

    -- Attribute to the most recent unresolved tracker
    local latest = ACO.lootTrackerQueue[#ACO.lootTrackerQueue]
    if latest and not latest.resolved then
        if not latest.lootItems then latest.lootItems = {} end
        if not latest.lootItems[itemID] then
            latest.lootItems[itemID] = { count = 0 }
        end
        latest.lootItems[itemID].count = latest.lootItems[itemID].count + count
        if link then latest.lootItems[itemID].link = link end
        ACO:Debug(format("Loot item captured via CHAT_MSG_LOOT: %d x%d", itemID, count))
    end
end

-- Currency tracking (captures currency gains during loot tracker window)
events["CHAT_MSG_CURRENCY"] = function(self, msg)
    if #ACO.lootTrackerQueue == 0 then return end
    if not msg then return end

    -- Parse currency ID from hyperlink: |Hcurrency:XXXX:0|h
    local currencyIDStr = msg:match("|Hcurrency:(%d+)")
    if not currencyIDStr then return end
    local currencyID = tonumber(currencyIDStr)
    if not currencyID then return end

    -- Parse count: "x5" at the end, or 1 if absent
    local count = tonumber(msg:match("x(%d+)")) or 1

    -- Attribute to the most recent unresolved tracker
    local latest = ACO.lootTrackerQueue[#ACO.lootTrackerQueue]
    if latest and not latest.resolved then
        latest.currencies[currencyID] = (latest.currencies[currencyID] or 0) + count
        ACO:Debug(format("Currency captured: %d x%d", currencyID, count))
    end
end

-- ============================================================================
-- BAG SCANNING (robust new-item detection, stack support, targeted scans)
-- ============================================================================

-- Snapshot one bag: counts per itemID (stack-aware) + slots list per itemID
function ACO:ScanBagSnapshot(bagID)
    local counts = {}
    local slotsByItem = {}

    local numSlots = C_Container.GetContainerNumSlots(bagID) or 0
    for slot = 1, numSlots do
        local info = C_Container.GetContainerItemInfo(bagID, slot)
        if info and info.itemID then
            local itemID = info.itemID
            local qty = info.stackCount or 1
            counts[itemID] = (counts[itemID] or 0) + qty
            slotsByItem[itemID] = slotsByItem[itemID] or {}
            tinsert(slotsByItem[itemID], {
                slot = slot,
                hyperlink = info.hyperlink,
                stackCount = qty,
                isLocked = info.isLocked,
            })
        end
    end

    return counts, slotsByItem
end

function ACO:InitializeBagState()
    if not self.db then return end

    wipe(self.dirtyBags)
    wipe(self.lastBagCountsByBag)
    wipe(self.bagSlotsByBag)

    local totalItems = 0
    for _, bag in ipairs(self:GetTrackedBags()) do
        local counts, slotsByItem = self:ScanBagSnapshot(bag)
        self.lastBagCountsByBag[bag] = counts
        self.bagSlotsByBag[bag] = slotsByItem
        for _, qty in pairs(counts) do
            totalItems = totalItems + qty
        end
    end
    self:Debug("État des sacs initialisé (quantités) : " .. totalItems)
end

function ACO:MarkBagDirty(bagID)
    if not bagID or type(bagID) ~= "number" then return end
    if bagID < 0 then return end
    if not self._trackedBagSet or not self._trackedBagSet[bagID] then return end
    self.dirtyBags[bagID] = true
    self:ScheduleBagScan()
end

function ACO:MarkAllBagsDirty()
    if not self.db then return end
    for _, bag in ipairs(self:GetTrackedBags()) do
        self.dirtyBags[bag] = true
    end
    self:ScheduleBagScan()
end

function ACO:ScheduleBagScan()
    if self.scanScheduled then return end
    self.scanScheduled = true

    local selfRef = self
    local throttle = self.scanThrottle or 0.25
    C_Timer.After(throttle, function()
        selfRef.scanScheduled = false
        selfRef:ProcessDirtyBags()
    end)
end

function ACO:DeferContainerClassification(itemID, delta, hint)
    if not itemID or not delta or delta <= 0 then return end
    if not self.db then return end

    local now = GetTime()

    -- Aggregate pending gains per itemID (stack-aware)
    local p = self.pendingContainerGains[itemID]
    if p then
        p.count = (p.count or 0) + delta
        p.lastSeen = now
        if hint then
            p.link = hint.link or p.link
            p.bag = hint.bag or p.bag
            p.slot = hint.slot or p.slot
        end
    else
        self.pendingContainerGains[itemID] = {
            count = delta,
            link = hint and hint.link or nil,
            bag = hint and hint.bag or nil,
            slot = hint and hint.slot or nil,
            firstSeen = now,
            lastSeen = now,
        }
    end

    -- One load request per itemID (avoid spam)
    if self.pendingItemLoads[itemID] then
        return
    end
    self.pendingItemLoads[itemID] = true

    self:Debug(format("Item %d: données non en cache -> recheck auto au chargement (x%d)", itemID, delta))

    local selfRef = self

    local function OnLoaded()
        selfRef.pendingItemLoads[itemID] = nil

        local pending = selfRef.pendingContainerGains[itemID]
        selfRef.pendingContainerGains[itemID] = nil

        -- Addon could be disabled in the meantime
        if not pending or not selfRef.db or not selfRef.db.enabled then
            return
        end

        -- Force recalculation (au cas où on aurait tenté avant)
        selfRef.containerCache[itemID] = nil

        if selfRef:CanQueueContainerItem(itemID) then
            selfRef:Debug(format("Item %d chargé -> queue ouverture x%d", itemID, pending.count or 1))
            selfRef:QueueItem(itemID, pending.link, pending.bag, pending.slot, pending.count or 1)
        else
            selfRef:Debug(format("Item %d chargé -> pas un conteneur (ou blacklisté)", itemID))
        end
    end

    -- Preferred: modern Item API
    if Item and Item.CreateFromItemID then
        local itemObj = Item:CreateFromItemID(itemID)
        if itemObj and itemObj.ContinueOnItemLoad then
            itemObj:ContinueOnItemLoad(OnLoaded)
            return
        end
    end

    -- Fallback: request + delayed retry
    if C_Item and C_Item.RequestLoadItemDataByID then
        C_Item.RequestLoadItemDataByID(itemID)
    end
    C_Timer.After(0.6, OnLoaded)
end

function ACO:ProcessDirtyBags()
    if not self.db then return end
    if not next(self.dirtyBags) then return end

    -- Aggregate diffs across all dirty bags (prevents false positives on moves/sorts)
    local netDelta = {}
    local slotHints = {}

    for bag in pairs(self.dirtyBags) do
        local oldCounts = self.lastBagCountsByBag[bag] or {}
        local newCounts, newSlotsByItem = self:ScanBagSnapshot(bag)

        self.lastBagCountsByBag[bag] = newCounts
        self.bagSlotsByBag[bag] = newSlotsByItem

        -- old -> new
        for itemID, oldQty in pairs(oldCounts) do
            local newQty = newCounts[itemID] or 0
            if newQty ~= oldQty then
                netDelta[itemID] = (netDelta[itemID] or 0) + (newQty - oldQty)
            end
        end
        -- new keys not in old
        for itemID, newQty in pairs(newCounts) do
            if oldCounts[itemID] == nil then
                netDelta[itemID] = (netDelta[itemID] or 0) + newQty
            end
            if not slotHints[itemID] then
                local l = newSlotsByItem[itemID]
                if l and l[1] then
                    slotHints[itemID] = { bag = bag, slot = l[1].slot, link = l[1].hyperlink }
                end
            end
        end
    end

    wipe(self.dirtyBags)

    -- Queue only positive gains (stack-aware). If addon disabled, we still update state but don't queue.
    if not self.db.enabled then
        return
    end

    for itemID, delta in pairs(netDelta) do
        if delta and delta > 0 then
            if self:CanQueueContainerItem(itemID) then
                local hint = slotHints[itemID]
                self:Debug(format("Gain détecté: %d x%d", itemID, delta))
                self:QueueItem(itemID, hint and hint.link, hint and hint.bag, hint and hint.slot, delta)
            else
                -- Si l'item n'est pas encore en cache (nom/spell nil), on diffère la classification
                -- et on réessaie automatiquement dès que les données de l'item sont chargées.
                if not self:IsItemDataAvailable(itemID) then
                    local hint = slotHints[itemID]
                    self:DeferContainerClassification(itemID, delta, hint)
                end
            end
        end
    end
end

EventFrame:SetScript("OnEvent", function(self, event, ...)
    if events[event] then
        events[event](self, ...)
    end
end)

for event in pairs(events) do
    -- Some events can disappear/rename between expansions or be disabled on certain game modes.
    -- Register safely to avoid hard errors ("Attempt to register unknown event ...").
    local ok = pcall(EventFrame.RegisterEvent, EventFrame, event)
    if (not ok) and ACO and ACO.db and ACO.db.debugMode then
        ACO:Debug("Skipping unknown event: " .. tostring(event))
    end
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
            ACO:Print(ACO:Translate("USAGE_INFO"), true)
        end
    elseif cmd == "remove" and arg then
        local itemID = tonumber(arg)
        if itemID then
            ACO:RemoveContainer(itemID)
        else
            ACO:Print(ACO:Translate("USAGE_REMOVE"), true)
        end
    elseif cmd == "list" then
        ACO:Print(ACO:Translate("LIST_TITLE") .. ":")
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
        ACO:Print(ACO.db.enabled and ACO:Translate("ENABLED") or ACO:Translate("DISABLED"))
    elseif cmd == "delay" and arg then
        local delay = tonumber(arg)
        if delay and delay >= 0 and delay <= 30 then
            ACO.db.delay = delay
            ACO:Print(string.format(ACO:Translate("DELAY_SET"), delay))
        else
            ACO:Print(ACO:Translate("DELAY_INVALID"), true)
        end
    elseif cmd == "debug" then
        ACO.db.debugMode = not ACO.db.debugMode
        ACO:Print(string.format(ACO:Translate("DEBUG_MODE"), (ACO.db.debugMode and "on" or "off")))
    elseif cmd == "diag" or cmd == "diagnostics" then
        local blocked, reason = ACO:IsOpeningBlocked()
        local diagnostics = ACO.db.diagnostics or {}
        ACO:Print("--- Diagnostics 3.1.1 / Retail 12.1.0 ---")
        print(format("  Client: %s build %s (%s)", tostring(ACO.runtimeVersion or "?"), tostring(ACO.runtimeBuild or "?"), tostring(ACO.runtimeBuildDate or "?")))
        print(format("  Interface client: %d (cible: %d) %s", ACO.runtimeInterface or 0, ACO.SUPPORTED_INTERFACE, ACO.runtimeInterfaceMatches and "OK" or "MISMATCH"))
        print(format("  Schéma DB: %d", ACO.db.schemaVersion or 0))
        print(format("  Mode: %s", ACO:GetQueueMode()))
        print(format("  File: %d en attente + %d vérification(s) + %d échec(s)", #ACO.openQueue, ACO.pendingVerifications or 0, #ACO.queueFailures))
        print(format("  État: %s", ACO.queuePaused and "pause" or (blocked and ("bloqué: " .. ACO:GetBlockReasonText(reason)) or "prêt")))
        print(format("  Échecs confirmés: %d", diagnostics.failedOpenAttempts or 0))
        if diagnostics.lastFailure then
            print(format("  Dernier échec: %s (item %s)", diagnostics.lastFailure, tostring(diagnostics.lastFailureItemID or "?")))
        end
        if ACO.missingRuntimeAPI and #ACO.missingRuntimeAPI > 0 then
            print("  API critiques manquantes: " .. table.concat(ACO.missingRuntimeAPI, ", "))
        else
            print("  API critiques: OK")
        end
        if ACO.missingOptionalAPI and #ACO.missingOptionalAPI > 0 then
            print("  API optionnelles manquantes: " .. table.concat(ACO.missingOptionalAPI, ", "))
        else
            print("  API optionnelles: OK")
        end
    elseif cmd == "mode" then
        local mode = lower(tostring(arg or ""))
        if mode == "auto" or mode == "automatic" or mode == "automatique" then
            ACO:SetQueueMode("auto")
            ACO:Print("Mode d'ouverture: automatique")
        elseif mode == "assisted" or mode == "assiste" or mode == "assisté" then
            ACO:SetQueueMode("assisted")
            ACO:Print("Mode d'ouverture: assisté")
        else
            ACO:Print("Usage: /aco mode auto|assisted", true)
        end
    elseif cmd == "next" then
        if not ACO:OpenNextQueueEntry() then ACO:Print(ACO:Translate("QUEUE_EMPTY"), true) end
    elseif cmd == "queue" then
        local action = lower(tostring(arg or ""))
        if action == "clear" or action == "vider" then
            ACO:CancelQueue(false)
        elseif action == "failures" or action == "echecs" or action == "échecs" then
            ACO:ClearQueueFailures()
        elseif ACO.UI and ACO.UI.mainFrame then
            ACO.UI.mainFrame:Show()
            ACO.UI:SwitchTab("pending")
        end
    elseif cmd == "rules" or cmd == "regles" or cmd == "règles" then
        local itemID = tonumber(arg)
        if itemID and ACO.UI and ACO.UI.ShowRuleEditor then
            if ACO.UI.mainFrame then ACO.UI.mainFrame:Show() end
            ACO.UI:ShowRuleEditor(itemID)
        else
            ACO:Print("Usage: /aco rules <itemID>", true)
        end
    elseif cmd == "resetui" then
        local state = ACO.db.ui
        state.width, state.height = 940, 710
        state.point, state.relativePoint, state.x, state.y = "CENTER", "CENTER", 0, 0
        state.lastTab, state.search, state.listView = "containers", "", "tracked"
        if ACO.UI and ACO.UI.mainFrame then
            local frame = ACO.UI.mainFrame
            frame:ClearAllPoints()
            frame:SetSize(940, 710)
            frame:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
        end
        ACO:Print("Position et taille de l'interface réinitialisées.")
    elseif cmd == "openall" or cmd == "open" then
        local count = ACO:OpenAllContainers()
        if count > 0 then
            ACO:Print(string.format("Ouverture de %d conteneur(s)...", count))
        end
    elseif cmd == "stats" then
        local stats = ACO:GetStats()
        ACO:Print("--- Statistiques ---")
        print(format("  Total ouvert: |cff00ff00%d|r", stats.totalOpened))
        print(format("  Cette session: |cff00ccff%d|r", stats.sessionOpened))
        print(format("  Items uniques: |cffffff00%d|r", stats.uniqueItems))
        print(format("  Or total gagné: %s", ACO:FormatMoney(stats.totalGold)))
        print(format("  Or cette session: %s", ACO:FormatMoney(stats.sessionGold)))
        print(format("  Première ouverture: %s", ACO:FormatTimestamp(stats.firstOpen)))
        print(format("  Dernière ouverture: %s", ACO:FormatTimestamp(stats.lastOpen)))
        if #stats.topItems > 0 then
            print("  Top 5 items:")
            for i, item in ipairs(stats.topItems) do
                local link = ACO:FormatItemLink(item.itemID)
                print(format("    %d. %s (x%d)", i, link, item.count))
            end
        end
    elseif cmd == "history" then
        local history = ACO:GetHistory(10)
        if #history == 0 then
            ACO:Print("Aucun historique.")
        else
            ACO:Print("--- Historique récent ---")
            for i, entry in ipairs(history) do
                local link = ACO:FormatItemLink(entry.itemID)
                print(format("  %s - %s", ACO:FormatRelativeTime(entry.timestamp), link))
            end
        end
    elseif cmd == "clearstats" then
        ACO:ClearStats()
    elseif cmd == "clearhistory" then
        ACO:ClearHistory()
    elseif cmd == "info" and arg then
        -- Debug command to check item info
        local itemID = tonumber(arg)
        if itemID then
            local itemName = C_Item.GetItemNameByID(itemID)
            local itemSpell = C_Item.GetItemSpell(itemID)
            local dataCached = ACO:IsItemDataAvailable(itemID) and "Oui" or "Non"
            local isContainer = ACO:IsContainerItem(itemID)
            local canOpen = ACO:CanOpenItem(itemID)
            local inList = ACO.db.containers[itemID] and "Oui" or "Non"
            ACO:Print(format("--- Info Item %d ---", itemID))
            print(format("  Nom: %s", itemName or "Inconnu"))
            print(format("  Spell: %s", itemSpell or "Aucun"))
            print(format("  Données en cache: %s", dataCached))
            print(format("  Dans la liste: %s", inList))
            print(format("  Détecté comme container: %s", isContainer and "Oui" or "Non"))
            print(format("  Peut être ouvert: %s", canOpen and "Oui" or "Non"))
        else
            ACO:Print(ACO:Translate("USAGE_ADD"), true)
        end
    elseif cmd == "scan" then
        -- Force a bag scan
        ACO.containerCache = {} -- Clear cache
        wipe(ACO.lastBagCountsByBag)
        wipe(ACO.bagSlotsByBag)
        wipe(ACO.dirtyBags)
        for _, bag in ipairs(ACO:GetTrackedBags()) do
            ACO.dirtyBags[bag] = true
        end
        ACO:ProcessDirtyBags()
        ACO:Print(ACO:Translate("SCAN_DONE"))
    elseif cmd == "" or cmd == "config" or cmd == "options" then
        if ACO.UI and ACO.UI.Toggle then
            ACO.UI:Toggle()
        end
    elseif cmd == "export" then
        ACO:ShowExportFrame()
    elseif cmd == "import" then
        if arg and arg ~= "" then
            ACO:ImportContainers(arg, false)
        else
            ACO:ShowImportFrame()
        end
    elseif cmd == "clear" then
        wipe(ACO.db.containers)
        if ACO.db.containerRules then wipe(ACO.db.containerRules) end
        ACO:Print(ACO:Translate("LIST_CLEARED"))
        if ACO.UI and ACO.UI.RefreshList then
            ACO.UI:RefreshList()
        end
    else
        ACO:Print(ACO:Translate("COMMANDS_AVAILABLE"))
        print("  /aco - Ouvrir l'interface")
        print("  /aco add <itemID> - Ajouter un conteneur")
        print("  /aco remove <itemID> - Retirer un conteneur")
        print("  /aco list - Lister les conteneurs")
        print("  /aco openall - Ouvrir tous les conteneurs")
        print("  /aco mode auto|assisted - Choisir le mode d'ouverture")
        print("  /aco next - Préparer/ouvrir le prochain conteneur")
        print("  /aco queue [clear|failures] - Gérer la file")
        print("  /aco rules <itemID> - Modifier les règles d'un conteneur")
        print("  /aco toggle - Activer/Désactiver")
        print("  /aco delay <secondes> - Régler le délai")
        print("  /aco stats - Afficher les statistiques")
        print("  /aco history - Afficher l'historique")
        print("  /aco clearstats - Réinitialiser les stats")
        print("  /aco clearhistory - Effacer l'historique")
        print("  /aco info <itemID> - Info sur un item")
        print("  /aco scan - Forcer un scan des sacs")
        print("  /aco import - Importer des conteneurs")
        print("  /aco export - Exporter les conteneurs")
        print("  /aco clear - Vider la liste")
        print("  /aco diag - Afficher les diagnostics 120100")
        print("  /aco resetui - Réinitialiser la fenêtre")
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
        self:Print(ACO:Translate("IMPORT_EMPTY"), true)
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

    self:Print(string.format(ACO:Translate("IMPORTED_COUNT"), count))

    if ACO.UI and ACO.UI.RefreshList then
        ACO.UI:RefreshList()
    end

    return count
end

-- ========================================================================
-- LOOT EXPORT (CSV / JSON)
-- ========================================================================

function ACO:ExportLootCSV()
    local lootData = self:GetLootSummary()
    if #lootData == 0 then return "" end

    local lines = {}
    tinsert(lines, "container_id,container_name,opened,gold_copper,item_id,item_name,item_count,avg_per_open,type")

    for _, cd in ipairs(lootData) do
        local cName = C_Item.GetItemInfo(cd.containerID) or ("Item " .. cd.containerID)
        cName = cName:gsub('"', '""')

        if cd.gold > 0 then
            local avgGold = floor(cd.gold / max(1, cd.opened))
            tinsert(lines, format('"%d","%s","%d","%d","","gold","%d","%d","gold"',
                cd.containerID, cName, cd.opened, cd.gold, cd.gold, avgGold))
        end

        for _, it in ipairs(cd.items) do
            local iName = C_Item.GetItemInfo(it.itemID) or ("Item " .. it.itemID)
            iName = iName:gsub('"', '""')
            local avg = it.count / max(1, cd.opened)
            tinsert(lines, format('"%d","%s","%d","","%d","%s","%d","%.2f","item"',
                cd.containerID, cName, cd.opened, it.itemID, iName, it.count, avg))
        end

        for _, cu in ipairs(cd.currencies) do
            local cuName
            local currInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(cu.currencyID)
            cuName = currInfo and currInfo.name or ("Currency " .. cu.currencyID)
            cuName = cuName:gsub('"', '""')
            local avg = cu.count / max(1, cd.opened)
            tinsert(lines, format('"%d","%s","%d","","%d","%s","%d","%.2f","currency"',
                cd.containerID, cName, cd.opened, cu.currencyID, cuName, cu.count, avg))
        end
    end

    return table.concat(lines, "\n")
end

function ACO:ExportLootJSON()
    local lootData = self:GetLootSummary()
    if #lootData == 0 then return "[]" end

    local function jsonStr(s)
        s = tostring(s):gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n')
        return '"' .. s .. '"'
    end

    local containers = {}
    for _, cd in ipairs(lootData) do
        local cName = C_Item.GetItemInfo(cd.containerID) or ("Item " .. cd.containerID)
        local items = {}
        for _, it in ipairs(cd.items) do
            local iName = C_Item.GetItemInfo(it.itemID) or ("Item " .. it.itemID)
            local avg = it.count / max(1, cd.opened)
            tinsert(items, format('{"itemID":%d,"name":%s,"count":%d,"avgPerOpen":%.2f}',
                it.itemID, jsonStr(iName), it.count, avg))
        end
        local currencies = {}
        for _, cu in ipairs(cd.currencies) do
            local cuName
            local currInfo = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfo(cu.currencyID)
            cuName = currInfo and currInfo.name or ("Currency " .. cu.currencyID)
            local avg = cu.count / max(1, cd.opened)
            tinsert(currencies, format('{"currencyID":%d,"name":%s,"count":%d,"avgPerOpen":%.2f}',
                cu.currencyID, jsonStr(cuName), cu.count, avg))
        end
        local avgGold = floor(cd.gold / max(1, cd.opened))
        tinsert(containers,
            format(
                '{"containerID":%d,"name":%s,"opened":%d,"goldCopper":%d,"avgGoldCopper":%d,"items":[%s],"currencies":[%s]}',
                cd.containerID, jsonStr(cName), cd.opened, cd.gold, avgGold,
                table.concat(items, ","), table.concat(currencies, ",")))
    end

    return "[" .. table.concat(containers, ",") .. "]"
end

function ACO:ShowLootExportFrame(text, titleKey)
    if not self.ExportFrame then
        self:CreateImportExportFrame()
    end
    self.ExportFrame.editBox:SetText(text)
    self.ExportFrame.title:SetText("|cff00ccff" .. ACO:Translate(titleKey) .. "|r")
    self.ExportFrame.importBtn:Hide()
    self.ExportFrame.clearImportBtn:Hide()
    self.ExportFrame.helpText:Hide()
    self.ExportFrame:Show()
    self.ExportFrame.editBox:HighlightText()
    self.ExportFrame.editBox:SetFocus()
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

    -- Close button (parented to titleBar so it stays above it)
    local closeBtn = CreateFrame("Button", nil, titleBar)
    closeBtn:SetSize(24, 24)
    closeBtn:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -8, -8)
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
    importText:SetText(ACO:Translate("IMPORT_BTN"))
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
    clearImportText:SetText(ACO:Translate("LIST_CLEARED"))
    clearImportText:SetTextColor(1, 1, 1)

    clearImportBtn:SetScript("OnEnter", function(self)
        self:SetBackdropColor(0.7, 0.4, 0, 1)
        GameTooltip:SetOwner(self, "ANCHOR_TOP")
        GameTooltip:SetText(ACO:Translate("CLEAR_IMPORT_TOOLTIP"))
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
    helpText:SetText(ACO:Translate("IMPORT_HELP"))
    frame.helpText = helpText

    self.ExportFrame = frame
    table.insert(UISpecialFrames, "ACOImportExportFrame")
end

function ACO:ShowImportFrame()
    if not self.ExportFrame then
        self:CreateImportExportFrame()
    end
    self.ExportFrame.editBox:SetText("")
    self.ExportFrame.title:SetText("|cff00ff80" .. ACO:Translate("IMPORT_FRAME_TITLE") .. "|r")
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
        self:Print(ACO:Translate("EXPORT_NONE"))
        return
    end
    self.ExportFrame.editBox:SetText(exportStr)
    self.ExportFrame.title:SetText("|cff00ccff" .. ACO:Translate("EXPORT_FRAME_TITLE") .. "|r")
    self.ExportFrame.importBtn:Hide()
    self.ExportFrame.clearImportBtn:Hide()
    self.ExportFrame.helpText:Hide()
    self.ExportFrame:Show()
    self.ExportFrame.editBox:HighlightText()
    self.ExportFrame.editBox:SetFocus()
end

-- ============================================================================
-- LDB DATABROKER PLUGIN
-- ============================================================================

function ACO:InitLDB()
    local ldb = LibStub and LibStub:GetLibrary("LibDataBroker-1.1", true)
    if not ldb then return end

    self.ldbObject = ldb:NewDataObject("AutoChestOpener", {
        type = "data source",
        text = "ACO",
        icon = "Interface\\Icons\\INV_Misc_Bag_07",
        label = "Auto Chest Opener",

        OnClick = function(_, button)
            if button == "LeftButton" then
                if ACO.ToggleUI then ACO:ToggleUI() end
            elseif button == "RightButton" then
                if ACO.db then
                    ACO.db.enabled = not ACO.db.enabled
                    ACO:Print(ACO:Translate("DEBUG_MODE",
                        ACO.db.enabled and ACO:Translate("ENABLED") or ACO:Translate("DISABLED")))
                end
            end
        end,

        OnTooltipShow = function(tooltip)
            tooltip:AddLine("|cff00ccffAuto Chest Opener|r")
            local stats = ACO.db and ACO.db.stats
            if stats then
                tooltip:AddDoubleLine(ACO:Translate("STATS_TOTAL"), tostring(stats.totalOpened or 0), 1, 1, 1, 0, 1, 0)
                tooltip:AddDoubleLine(ACO:Translate("STATS_SESSION"), tostring(stats.totalOpenedSession or 0), 1, 1, 1, 0,
                    1, 0)
            end
            tooltip:AddLine(" ")
            tooltip:AddLine(ACO:Translate("MINIMAP_LEFT"), 0.6, 0.6, 0.6)
            tooltip:AddLine(ACO:Translate("MINIMAP_RIGHT"), 0.6, 0.6, 0.6)
        end,
    })
end
