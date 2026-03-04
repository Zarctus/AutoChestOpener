--[[
    Auto Chest Opener - Core Module
    Automatically opens chests, bags and containers after receiving them
    Version: 1.3.5
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
local GetItemInfoInstant = GetItemInfoInstant

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

-- ============================================================================
-- ADDON INITIALIZATION
-- ============================================================================

ACO.name = addonName
-- Try to read version from the AddOn TOC metadata (## Version:)
local tocVersion = (GetAddOnMetadata and GetAddOnMetadata(addonName, "Version")) or nil
-- If packaged with a tool, the TOC can contain a placeholder like "@project-version@".
-- Treat it as invalid and fallback to the hardcoded version.
if tocVersion == "@project-version@" then
    tocVersion = nil
end
ACO.version = (tocVersion and tocVersion ~= "" ) and tocVersion or "1.3.5"
ACO.pendingItems = {}
ACO.itemQueue = {}
ACO.goldTracker = {
    isTracking = false,
    goldBefore = 0,
    pendingItemID = nil,
}

-- Centralized open queue worker
ACO.openQueue = {}
ACO.queueTicker = nil
ACO.queueNextAllowedAt = 0
ACO.queueOpenInterval = 0.25 -- seconds between uses to avoid server/UI spam

-- Combat deferral (itemID -> count)
ACO.combatQueue = {}

-- Item data async (évite de rater certains conteneurs si les données de l'objet ne sont pas encore en cache)
ACO.pendingItemLoads = {}        -- [itemID] = true si un callback de chargement est en cours
ACO.pendingContainerGains = {}   -- [itemID] = { count=, link=, bag=, slot=, firstSeen=, lastSeen= }

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
}

function ACO:SetBlocker(name, state)
    if not name then return end
    if not self.blockers then self.blockers = {} end
    local old = self.blockers[name]
    if old == state then return end
    self.blockers[name] = state and true or false

    -- Affichage debug systématique pour le blocage 'mail'
    if name == "mail" then
        self:Print("[DEBUG] Blocage mail : " .. tostring(self.blockers[name]))
    end
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

    -- Merchant: right-click/use can SELL items when the merchant frame is open.
    if (self.blockers and self.blockers.merchant) or (MerchantFrame and MerchantFrame.IsShown and MerchantFrame:IsShown()) then
        return true, "MERCHANT"
    end

    -- Trade: right-click/use can MOVE items into trade window.
    if (self.blockers and self.blockers.trade) or (TradeFrame and TradeFrame.IsShown and TradeFrame:IsShown()) then
        return true, "TRADE"
    end

    -- Auction House: right-click/use can list/drag items or behave unexpectedly.
    if (self.blockers and self.blockers.auction) or (AuctionHouseFrame and AuctionHouseFrame.IsShown and AuctionHouseFrame:IsShown()) then
        return true, "AUCTION"
    end

    -- Mail: right-click/use can attach items to mail.
    -- Ajout compatibilité TSM : vérifie aussi TSM_MailingFrame
    local tsmMailOpen = false
    if TSM_MailingFrame and TSM_MailingFrame.IsShown and TSM_MailingFrame:IsShown() then
        tsmMailOpen = true
    end
    if (self.blockers and self.blockers.mail) or (MailFrame and MailFrame.IsShown and MailFrame:IsShown()) or tsmMailOpen then
        return true, "MAIL"
    end

    -- Bank / Guild Bank: right-click/use can deposit items instead of opening.
    if (self.blockers and self.blockers.bank) or (BankFrame and BankFrame.IsShown and BankFrame:IsShown()) then
        return true, "BANK"
    end
    if (self.blockers and self.blockers.guildbank) or (GuildBankFrame and GuildBankFrame.IsShown and GuildBankFrame:IsShown()) then
        return true, "GUILDBANK"
    end

    -- Void storage (rare but safe to guard)
    if (self.blockers and self.blockers.voidstorage) or (VoidStorageFrame and VoidStorageFrame.IsShown and VoidStorageFrame:IsShown()) then
        return true, "VOIDSTORAGE"
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
        MERCHANT = "BLOCK_REASON_MERCHANT",
        TRADE = "BLOCK_REASON_TRADE",
        AUCTION = "BLOCK_REASON_AUCTION",
        MAIL = "BLOCK_REASON_MAIL",
        BANK = "BLOCK_REASON_BANK",
        GUILDBANK = "BLOCK_REASON_GUILDBANK",
        VOIDSTORAGE = "BLOCK_REASON_VOIDSTORAGE",
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
ACO.lastBagCountsByBag = {}   -- [bagID] = { [itemID] = totalCountInBag }
ACO.bagSlotsByBag = {}        -- [bagID] = { [itemID] = { {slot=, hyperlink=}... } }

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
    -- Statistics
    stats = {
        totalOpened = 0,            -- Total containers opened
        totalOpenedSession = 0,     -- Session counter (reset on login)
        itemsOpened = {},           -- {[itemID] = count}
        firstOpen = nil,            -- Timestamp of first ever open
        lastOpen = nil,             -- Timestamp of last open
        totalGold = 0,              -- Total gold earned (in copper)
        sessionGold = 0,            -- Session gold earned (in copper)
    },
    -- History (last 50 openings)
    history = {},
    historyMaxSize = 50,
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

-- Cache pour les items vérifiés (évite les vérifications répétées)
ACO.containerCache = {}


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
    if C_Item and C_Item.IsItemDataCachedByID then
        return C_Item.IsItemDataCachedByID(itemID)
    end
    if C_Item and C_Item.GetItemNameByID then
        local name = C_Item.GetItemNameByID(itemID)
        if name then return true end
    end
    if GetItemInfo then
        local name = GetItemInfo(itemID)
        if name then return true end
    end
    return false
end


-- Mots-clés (recherche "plain", pas de patterns Lua) pour détecter des objets ouvrables.
-- Note: On reste volontairement assez conservateur pour éviter les faux positifs.
local OPEN_PATTERNS = {
    "open",      -- EN: open, opens, opening
    "ouvr",      -- FR: ouvrir, ouvrez, ouvrant, ouvre
    "öffn",      -- DE: öffnen, öffnet
    "abr",       -- ES: abrir, abre
    "откр",      -- RU: открыть, открывать
    "열",        -- KR: 열기
}

local OPEN_KEYWORDS = {
    "unwrap", "déballer", "auspacken",  -- wrapped items
    "use", "utiliser", "utilisez",      -- some containers use "use"
    "loot", "piller",                   -- loot keywords
    "salvage", "récupér",               -- salvage crates
    "click", "cliqu",                   -- click to open
}

local CONTAINER_NAME_KEYWORDS = {
    "cache", "coffre", "coffret", "chest", "crate", "caisse",
    "sack", "sac", "sacoche",
    "bag", "box", "boîte", "bundle", "lot",
    "satchel",                           -- "Satchel of ..."
    "treasure", "trésor", "salvage", "récupération",
    "parcel", "colis", "package", "paquet",
    "pouch", "bourse", "purse",
}


function ACO:IsContainerItem(itemID)
    if not itemID then return false end

    -- Check user-defined containers (priorité absolue)
    if self.db and self.db.containers[itemID] then
        return true
    end

    -- Cache (évite des checks coûteux pendant les scans)
    if self.containerCache[itemID] ~= nil then
        return self.containerCache[itemID]
    end

    -- Exclure les items équipables (sacs/armures/armes) pour éviter les faux positifs
    local equipLoc
    if GetItemInfoInstant then
        equipLoc = select(9, GetItemInfoInstant(itemID))
    end
    if not equipLoc then
        equipLoc = select(9, GetItemInfo(itemID))
    end
    if equipLoc and equipLoc ~= "" then
        self.containerCache[itemID] = false
        return false
    end

    -- IMPORTANT: si l'item n'est pas encore en cache, certains appels (nom/spell) retournent nil.
    -- Dans ce cas, on NE "cache" PAS false, sinon l'item ne sera jamais reconnu.
    if not self:IsItemDataAvailable(itemID) then
        return false
    end

    local itemSpell = (C_Item and C_Item.GetItemSpell) and C_Item.GetItemSpell(itemID) or nil
    local itemName = (C_Item and C_Item.GetItemNameByID) and C_Item.GetItemNameByID(itemID) or nil

    self:Debug(format("Checking item %d: name='%s', spell='%s'",
        itemID, itemName or "nil", itemSpell or "nil"))

    local isContainer = false

    -- 1) Priorité au spell "Use:" (le plus fiable quand dispo)
    if itemSpell and itemSpell ~= "" then
        local spellLower = NormalizeText(itemSpell)
        if spellLower and (ContainsAnyPlain(spellLower, OPEN_PATTERNS) or ContainsAnyPlain(spellLower, OPEN_KEYWORDS)) then
            isContainer = true
        end
    end

    -- 2) Fallback sur le nom de l'item (moins fiable, mais utile)
    if not isContainer and itemName and itemName ~= "" then
        local nameLower = NormalizeText(itemName)
        if nameLower and ContainsAnyPlain(nameLower, CONTAINER_NAME_KEYWORDS) then
            isContainer = true
        end
    end

    self.containerCache[itemID] = isContainer
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

    local bags = {0, 1, 2, 3, 4}
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

    -- Notify Zarctus_Gold before opening (for proper gold tracking)
    local itemName = info.itemName
    if not itemName and info.hyperlink then
        itemName = info.hyperlink:match("%[(.-)%]")
    end
    self:NotifyZarctusGold(itemID, itemName)

    C_Container.UseContainerItem(bag, slot)
    self:RecordOpening(itemID)

    if self.db and self.db.showNotifications then
        local link = itemLink or info.hyperlink or self:FormatItemLink(itemID)
        self:Print(ACO:Translate("OPENING", link))
    end

    if self.db and self.db.notificationSound then
        PlaySound(self.SOUNDS.OPEN)
    end

    return true
end

function ACO:StartQueueWorker()
    if self.queueTicker then return end

    local selfRef = self
    self.queueTicker = C_Timer.NewTicker(0.1, function()
        selfRef:ProcessQueueTick()
    end)

    function ACO:UseBagSlotViaMacro(bag, slot)
        if not bag or not slot then
            return false, "MISSING"
        end

        local info = C_Container.GetContainerItemInfo(bag, slot)
        if not info or not info.itemID then
            return false, "MISSING"
        end

        return self:UseContainerFromBagSlot(info.itemID, bag, slot, info.hyperlink)
    end
end

function ACO:StopQueueWorker()
    if self.queueTicker then
        self.queueTicker:Cancel()
        self.queueTicker = nil
    end
end

-- Add an open request to the centralized queue

-- Insert an entry into openQueue sorted by executeAt (avoid "later" items blocking "soon" items)
function ACO:InsertOpenQueueEntry(entry)
    if not entry then return end
    local q = self.openQueue
    local t = entry.executeAt or 0

    local n = #q
    for i = 1, n do
        local e = q[i]
        local et = (e and e.executeAt) or 0
        if t < et then
            tinsert(q, i, entry)
            return
        end
    end

    tinsert(q, entry)
end

function ACO:EnqueueOpen(itemID, bag, slot, itemLink, executeAt, source)
    if not itemID or not self.db then return end
    if not self:CanQueueContainerItem(itemID) then return end

    -- In combat: defer
    if InCombatLockdown() then
        self.combatQueue[itemID] = (self.combatQueue[itemID] or 0) + 1
        return
    end

    local now = GetTime()
    local entry = {
        itemID = itemID,
        bag = bag,
        slot = slot,
        link = itemLink,
        executeAt = executeAt or now,
        source = source or "AUTO",
        tries = 0,
    }
    self:InsertOpenQueueEntry(entry)
    self:StartQueueWorker()
end

function ACO:ProcessQueueTick()
    if #self.openQueue == 0 then
        self:StopQueueWorker()
        return
    end

    local now = GetTime()

    local blocked, blockReason = self:IsOpeningBlocked()
    if blocked then
        -- Prevent accidental selling/moving items while certain frames are open.
        -- Keep entries in queue; we will resume automatically once unblocked.
        self.queueNextAllowedAt = now + 0.5
        return
    end
    if now < (self.queueNextAllowedAt or 0) then
        return
    end

    local entry = self.openQueue[1]
    if entry.executeAt and now < entry.executeAt then
        return
    end

    -- Pop the entry
    tremove(self.openQueue, 1)

    -- Validate still openable (blacklist can change)
    if not self:CanQueueContainerItem(entry.itemID) then
        return
    end

    -- Try preferred slot first, then fallback find
    local ok, reason = self:UseContainerFromBagSlot(entry.itemID, entry.bag, entry.slot, entry.link)
    if not ok then
        local bag, slot, info = self:FindItemInBags(entry.itemID)
        if bag then
            entry.bag, entry.slot = bag, slot
            entry.link = info and info.hyperlink or entry.link
            ok, reason = self:UseContainerFromBagSlot(entry.itemID, bag, slot, entry.link)
        end
    end

    if ok then
        self.queueNextAllowedAt = now + (self.queueOpenInterval or 0.25)
        return
    end

    -- LOCKED -> retry later (quick backoff). Missing/mismatch -> drop.
    if reason == "LOCKED" then
        entry.tries = (entry.tries or 0) + 1
        if entry.tries <= 25 then
            entry.executeAt = now + 0.4
            self:InsertOpenQueueEntry(entry)
            self:StartQueueWorker()
        end
    end
end

-- Public: open one container ASAP (uses the queue worker for lock/backoff handling)
function ACO:OpenItem(itemID)
    if not itemID or not self.db then return false end
    self:EnqueueOpen(itemID, nil, nil, nil, GetTime(), "MANUAL")
    return true
end

-- Public: queue an item (optionally multiple times) after the user's delay
function ACO:QueueItem(itemID, itemLink, bag, slot, count)
    if not self.db or not self.db.enabled then return end
    if not itemID then return end
    if not self:CanQueueContainerItem(itemID) then
        self:Debug("CanQueueContainerItem returned false for: " .. itemID)
        return
    end

    count = max(1, tonumber(count) or 1)
    local delay = self.db.delay or 0
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

    for i = 1, count do
        self:EnqueueOpen(itemID, bag, slot, itemLink, executeAt, "AUTO")
    end
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
    
    -- Collect all containers in bags (tracked list + reagent bag)
    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID and containers[info.itemID] then
                tinsert(toOpen, {bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink})
            end
        end
    end
    
    if #toOpen == 0 then
        self:Print(ACO:Translate("NO_CONTAINERS_FOUND"))
        return 0
    end
    
    -- Enqueue with delay between each to avoid spam
    local delayBetween = 0.35
    local startAt = GetTime()

    for i, data in ipairs(toOpen) do
        self:EnqueueOpen(data.itemID, data.bag, data.slot, data.link, startAt + (i - 1) * delayBetween, "OPENALL")
    end

    if self.db.showNotifications then
        self:Print(ACO:Translate("OPEN_ALL_RESULT", #toOpen))
    end

    return #toOpen
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
    
    self.db.containers[itemID] = true
    
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
                self:QueueItem(itemID, info.hyperlink, bag, slot, qty)
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
    
    -- Clear all containers
    wipe(self.db.containers)
    
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
function ACO:RecordOpening(itemID)
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
    
    -- Start gold tracking
    self:StartGoldTracking(itemID)
    
    -- Add to history (gold will be updated later)
    self:AddToHistory(itemID, currentTime)
    
    -- Refresh UI if stats tab is visible
    if self.UI and self.UI.RefreshStats then
        self.UI:RefreshStats()
    end
end

-- Start tracking gold before container opens
function ACO:StartGoldTracking(itemID)
    self.goldTracker.isTracking = true
    self.goldTracker.goldBefore = GetMoney()
    self.goldTracker.pendingItemID = itemID
    self.goldTracker.startTime = time()
    
    -- Check for gold change after a short delay (loot processing time)
    C_Timer.After(0.5, function()
        self:CheckGoldGained()
    end)
end

-- Check if gold was gained from container
function ACO:CheckGoldGained()
    if not self.goldTracker.isTracking then return end
    
    local goldAfter = GetMoney()
    local goldGained = goldAfter - self.goldTracker.goldBefore
    
    if goldGained > 0 then
        local stats = self.db.stats
        stats.totalGold = (stats.totalGold or 0) + goldGained
        stats.sessionGold = (stats.sessionGold or 0) + goldGained
        
        -- Update the most recent history entry with gold info
        if self.db.history and #self.db.history > 0 then
            self.db.history[1].goldGained = goldGained
        end
        
        self:Debug(format("Or gagn\195\169: %s", self:FormatMoney(goldGained)))
        
        -- Refresh UI
        if self.UI and self.UI.RefreshStats then
            self.UI:RefreshStats()
        end
        if self.UI and self.UI.RefreshHistory then
            self.UI:RefreshHistory()
        end
    end
    
    self.goldTracker.isTracking = false
    self.goldTracker.pendingItemID = nil
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
        tinsert(items, {itemID = itemID, count = count})
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
    if not timestamp then return "Jamais" end
    return date("%d/%m/%Y %H:%M", timestamp)
end

-- Format relative time (e.g., "il y a 5 minutes")
function ACO:FormatRelativeTime(timestamp)
    if not timestamp then return "Jamais" end
    
    local diff = time() - timestamp
    
    if diff < 60 then
        return "À l'instant"
    elseif diff < 3600 then
        local mins = floor(diff / 60)
        return format("Il y a %d min", mins)
    elseif diff < 86400 then
        local hours = floor(diff / 3600)
        return format("Il y a %dh", hours)
    else
        local days = floor(diff / 86400)
        return format("Il y a %d jour%s", days, days > 1 and "s" or "")
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
    
    -- Initialize bag state immediately to prevent false "new item" detections
    ACO.bagStateInitialized = false
    
    ACO:Print(ACO:Translate("ADDON_LOADED"))
    
    -- Initialize UI after a short delay
    C_Timer.After(0.5, function()
        if ACO.InitUI then
            ACO:InitUI()
        end
    end)
end

events["PLAYER_ENTERING_WORLD"] = function(self, isInitialLogin, isReloadingUi)
    -- Initialize bag state after a short delay without triggering openings
    C_Timer.After(1, function()
        if ACO.db then
            ACO:Debug("Initialisation de l'état des sacs au chargement...")
            ACO:InitializeBagState()
            ACO.bagStateInitialized = true
            ACO:Debug("État des sacs prêt - détection des nouveaux items activée")
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
        ACO:Debug("Skipping unknown event:", tostring(event))
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
    else
        ACO:Print(ACO:Translate("COMMANDS_AVAILABLE"))
        print("  /aco - Ouvrir l'interface")
        print("  /aco add <itemID> - Ajouter un conteneur")
        print("  /aco remove <itemID> - Retirer un conteneur")
        print("  /aco list - Lister les conteneurs")
        print("  /aco openall - Ouvrir tous les conteneurs")
        print("  /aco toggle - Activer/Désactiver")
        print("  /aco delay <secondes> - Régler le délai")
        print("  /aco stats - Afficher les statistiques")
        print("  /aco history - Afficher l'historique")
        print("  /aco clearstats - Réinitialiser les stats")
        print("  /aco clearhistory - Effacer l'historique")
        print("  /aco info <itemID> - Info sur un item")
        print("  /aco scan - Forcer un scan des sacs")
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
        ACO:Print(ACO:Translate("LIST_CLEARED"))
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
