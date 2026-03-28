--[[
    Auto Chest Opener - Core Module
    Automatically opens all types of containers, chests, bags, crates, lockboxes, gifts and more
    Version: 2.1.0
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
ACO.version = (tocVersion and tocVersion ~= "" ) and tocVersion or "2.1.0"
ACO.pendingItems = {}
ACO.itemQueue = {}
ACO.goldTracker = {
    isTracking = false,
    goldBefore = 0,
    pendingItemID = nil,
}
ACO.goldTrackerQueue = {}  -- queue-based gold tracking for batch openings
ACO.lootTrackerQueue = {}  -- queue-based loot tracking for content capture

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
    autoDiscovery = true,   -- Auto-detect containers when manually opened
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
    -- Loot summary per container type
    lootSummary = {},  -- [containerItemID] = { opened=N, gold=copper, items={[itemID]=count}, currencies={[currencyID]=count} }
}

-- ============================================================================
-- COLORS & CONSTANTS
-- ============================================================================

ACO.colors = {
    -- Palette Midnight unifiée (Zayu / Zarctus)
    bg          = { r = 0.06, g = 0.06, b = 0.08, a = 0.97 },
    header      = { r = 0.10, g = 0.10, b = 0.13, a = 1    },
    row         = { r = 0.09, g = 0.09, b = 0.12, a = 0.92 },
    rowAlt      = { r = 0.06, g = 0.06, b = 0.09, a = 0.92 },
    rowHover    = { r = 0.14, g = 0.15, b = 0.22, a = 1    },
    border      = { r = 0.22, g = 0.22, b = 0.28, a = 1    },
    borderLight = { r = 0.35, g = 0.35, b = 0.40, a = 1    },
    accent      = { r = 0.00, g = 0.70, b = 0.90, a = 1    },
    gold        = { r = 1.00, g = 0.82, b = 0.00, a = 1    },
    green       = { r = 0.30, g = 0.90, b = 0.30, a = 1    },
    red         = { r = 1.00, g = 0.30, b = 0.30, a = 1    },
    orange      = { r = 1.00, g = 0.60, b = 0.10, a = 1    },
    text        = { r = 0.95, g = 0.95, b = 0.95, a = 1    },
    textDim     = { r = 0.55, g = 0.55, b = 0.58, a = 1    },
    textHeader  = { r = 0.75, g = 0.75, b = 0.78, a = 1    },
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
    "open",      -- EN: open, opens, opening
    "ouvr",      -- FR: ouvrir, ouvrez, ouvrant, ouvre
    "öffn",      -- DE: öffnen, öffnet
    "abr",       -- ES: abrir, abre (also PT "abrir")
    "откр",      -- RU: открыть, открывать
    "열",        -- KR: 열기
    "打开",      -- zhCN: 打开 (open)
    "打開",      -- zhTW: 打開 (open)
    "apr",       -- IT: aprire, apri
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
    "egg", "oeuf", -- Noblegarden eggs
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
        if text then
            local normalized = NormalizeText(text)
            if normalized and ContainsAnyPlain(normalized, TOOLTIP_OPEN_KEYWORDS) then
                return true
            end
            -- Green "Use:" text lines (type 0, green color ~= {0, 1, 0})
            -- These indicate an active use effect
            if lineData.leftColor then
                local clr = lineData.leftColor
                -- Green text = Use: effect (r < 0.1, g > 0.9, b < 0.1)
                if clr.r and clr.g and clr.r < 0.15 and clr.g > 0.85 and (clr.b or 0) < 0.15 then
                    if normalized and (ContainsAnyPlain(normalized, OPEN_PATTERNS) or ContainsAnyPlain(normalized, OPEN_KEYWORDS)) then
                        return true
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

    -- Snapshot bags BEFORE using the item (for loot tracking)
    self:StartLootTracking(itemID)

    C_Container.UseContainerItem(bag, slot)
    self:RecordOpening(itemID)

    if self.db and self.db.showNotifications and not self.batchTracker.active then
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

    -- Show queue widget
    if self.UI and self.UI.queueWidget then
        self.UI.queueWidget:Show()
    end

    local selfRef = self
    self.queueTicker = C_Timer.NewTicker(0.1, function()
        selfRef:ProcessQueueTick()
    end)
end

function ACO:StopQueueWorker()
    if self.queueTicker then
        self.queueTicker:Cancel()
        self.queueTicker = nil
    end

    -- Print batch summary if active
    if self.batchTracker and self.batchTracker.active then
        self:PrintBatchSummary()
    end

    -- Hide queue widget
    if self.UI and self.UI.queueWidget then
        self.UI.queueWidget:Hide()
    end

    -- Reset session counter
    self.queueSessionOpened = 0
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
    end

    msg = msg .. " " .. format(ACO:Translate("BATCH_SUMMARY_TIME"), format("%.1f", elapsed))

    self:Print(msg)
end

function ACO:PauseQueue()
    self.queuePaused = true
end

function ACO:ResumeQueue()
    self.queuePaused = false
    self:StartQueueWorker()
end

function ACO:CancelQueue()
    wipe(self.openQueue)
    self.queuePaused = false
    if self.batchTracker then
        self.batchTracker.active = false
    end
    self:StopQueueWorker()
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

    if self.queuePaused then return end

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
        self.queueSessionOpened = (self.queueSessionOpened or 0) + 1
        if self.batchTracker.active and entry.source == "OPENALL" then
            self.batchTracker.count = self.batchTracker.count + 1
        end
        self.queueNextAllowedAt = now + (self.queueOpenInterval or 0.25)

        -- Post-use verification: C_Container.UseContainerItem is fire-and-forget.
        -- The server can silently reject the call (GCD active, player is casting,
        -- server-side item restrictions, etc.) without any Lua error.
        -- 1.5s after the call, check whether the item is still in bags.
        -- If it is, the use failed → re-queue up to 2 more times before giving up.
        local verifyRound = entry.verifyRound or 0
        local selfRef    = self
        local verifyID   = entry.itemID
        local verifyLink = entry.link
        C_Timer.After(1.5, function()
            if not selfRef.db or not selfRef.db.enabled then return end
            local fb, fs, fi = selfRef:FindItemInBags(verifyID)
            if not fb then return end  -- item was consumed – all good

            if verifyRound < 2 then
                -- Still present: queue another attempt
                selfRef:Debug(format("Item %d toujours en sac après UseContainerItem (vérification %d) – nouvel essai", verifyID, verifyRound + 1))
                local retryEntry = {
                    itemID      = verifyID,
                    bag         = fb,
                    slot        = fs,
                    link        = (fi and fi.hyperlink) or verifyLink,
                    executeAt   = GetTime() + 0.5,
                    source      = "RETRY",
                    tries       = 0,
                    verifyRound = verifyRound + 1,
                }
                selfRef:InsertOpenQueueEntry(retryEntry)
                selfRef:StartQueueWorker()
            else
                -- All retries exhausted and item is still present.
                local ilink = (fi and fi.hyperlink) or selfRef:FormatItemLink(verifyID)
                selfRef:Print(ACO:Translate("OPEN_FAILED_RETRY", ilink), true)
            end
        end)
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
    
    -- Collect all containers in bags (tracked list + auto-detected openable items)
    for _, bag in ipairs(self:GetTrackedBags()) do
        local numSlots = C_Container.GetContainerNumSlots(bag) or 0
        for slot = 1, numSlots do
            local info = C_Container.GetContainerItemInfo(bag, slot)
            if info and info.itemID then
                -- Include items from tracked list OR auto-detected as openable
                if containers[info.itemID] or self:CanQueueContainerItem(info.itemID) then
                    tinsert(toOpen, {bag = bag, slot = slot, itemID = info.itemID, link = info.hyperlink})
                end
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

    -- Start batch tracking for summary notification
    self.batchTracker.active = true
    self.batchTracker.count = 0
    self.batchTracker.totalQueued = #toOpen
    self.batchTracker.goldBefore = GetMoney()
    self.batchTracker.startTime = GetTime()

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
    
    -- Add to history first (gold will be updated later via tracker)
    local historyEntry = self:AddToHistory(itemID, currentTime)
    
    -- Start gold tracking with direct reference to the history entry
    self:StartGoldTracking(itemID, historyEntry)
    
    -- Refresh UI if stats tab is visible
    if self.UI and self.UI.RefreshStats then
        self.UI:RefreshStats()
    end
end

-- Start tracking gold for a specific container opening.
-- Uses a queue so that rapid batch openings don't clobber each other.
function ACO:StartGoldTracking(itemID, historyEntry)
    local goldNow = GetMoney()

    -- Try to finalize any already-pending trackers whose gold has arrived
    self:ProcessGoldTrackers(goldNow)

    -- Push a new tracker for this opening
    local tracker = {
        goldBefore = goldNow,
        historyEntry = historyEntry,
        itemID = itemID,
        resolved = false,
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
    tracker.resolved = true

    local stats = self.db.stats
    stats.totalGold  = (stats.totalGold  or 0) + goldGained
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
    -- Final attempt with current gold
    self:ProcessGoldTrackers(GetMoney())
    -- Any remaining unresolved trackers are containers that gave no gold – discard them.
    wipe(queue)
end

-- ============================================================================
-- LOOT TRACKING (captures items, gold, currencies from container openings)
-- ============================================================================

-- Take a full bag item snapshot (itemID -> {count, link}) across all tracked bags
function ACO:TakeBagItemSnapshot()
    local snapshot = {}  -- [itemID] = { count=N, link="..." }
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
        currencies      = {},  -- filled by CHAT_MSG_CURRENCY
        lootItems       = {},  -- filled by CHAT_MSG_LOOT
        timestamp       = GetTime(),
        resolved        = false,
    }
    tinsert(self.lootTrackerQueue, tracker)

    -- Schedule delayed processing (must wait for server to send bag updates)
    local selfRef = self
    C_Timer.After(1.5, function() selfRef:ProcessLootTrackers() end)
    C_Timer.After(3.0, function() selfRef:ProcessLootTrackers() end)
    C_Timer.After(6.0, function() selfRef:CleanupLootTrackers() end)
end

function ACO:ProcessLootTrackers()
    local queue = self.lootTrackerQueue
    local i = 1
    while i <= #queue do
        if queue[i].resolved then
            tremove(queue, i)
        else
            -- Boundary: use next tracker's snapshot/gold, or current state for the last one
            local afterSnapshot, goldAfter
            if queue[i + 1] then
                afterSnapshot = queue[i + 1].bagSnapshot
                goldAfter     = queue[i + 1].goldBefore
            else
                afterSnapshot = self:TakeBagItemSnapshot()
                goldAfter     = GetMoney()
            end

            -- Diff items: find what was gained
            local gained = {}  -- [itemID] = { count=N, link="..." }
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

    local entry = summary[containerID]
    entry.opened = (entry.opened or 0) + 1
    entry.gold   = (entry.gold or 0) + goldGained

    -- Merge gained items
    for itemID, data in pairs(gained) do
        if not entry.items[itemID] then
            entry.items[itemID] = { count = 0 }
        end
        local it = entry.items[itemID]
        -- Support legacy format (plain number)
        if type(it) == "number" then
            it = { count = it }
            entry.items[itemID] = it
        end
        it.count = (it.count or 0) + (data.count or data)
        -- Always keep the latest hyperlink (most up-to-date modifiers)
        if type(data) == "table" and data.link then
            it.link = data.link
        end
    end

    -- Merge items captured via CHAT_MSG_LOOT (fallback quand le diff de sac rate des items par timing)
    if tracker.lootItems then
        for itemID, data in pairs(tracker.lootItems) do
            if not gained[itemID] then
                gained[itemID] = { count = data.count, link = data.link }
            end
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
    -- Finalize any remaining unresolved trackers (containers that gave nothing visible)
    local queue = self.lootTrackerQueue
    for i = #queue, 1, -1 do
        if not queue[i].resolved then
            self:FinalizeLootTracker(queue[i], {}, 0)
        end
    end
    wipe(queue)
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

        local itemID   = info.itemID
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
        tinsert(containers, format('{"containerID":%d,"name":%s,"opened":%d,"goldCopper":%d,"avgGoldCopper":%d,"items":[%s],"currencies":[%s]}',
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
