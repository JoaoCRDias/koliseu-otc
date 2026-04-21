-- ============================================================
-- CHARM PROFILES - Business Logic & Data Layer
-- ============================================================
-- This module handles all profile state management, protocol
-- communication, CRUD operations, and cost calculations.
-- The UI layer (charms.lua) consumes this module and sets
-- callbacks for visual updates.
-- ============================================================

CharmProfile = CharmProfile or {}

-- ============================================================
-- STATE
-- ============================================================
local OPCODE = 245
local registered = false
local profilesList = {}
local profilesLoaded = false
local maxMajor = 0
local maxMinor = 0
local currentApplied = nil
local previewMajor = nil -- nil = use real server values
local previewMinor = nil
local pendingChargeCallback = nil
local cachedRemoveRuneCost = 0
local pendingSelectProfile = nil
local ignoreComboChange = false
local skipNextAutoSave = false

-- Charm data references (set by charms.lua via setCharmsData)
local charmsTable = nil
local charmCategoryTable = nil

-- Optional: charms.lua sets function() -> { { charmId, tier, raceId }, ... } for initial "Default" save
CharmProfile.getSaveCharmsSnapshot = nil

-- ============================================================
-- CALLBACKS (set by UI layer)
-- ============================================================
CharmProfile.callbacks = {
    onListReceived = nil,    -- function() - profile list was updated
    onApplied = nil,         -- function(name, message) - profile was applied
    onCostReceived = nil,    -- function(name, cost) - cost response for apply (opens confirm)
    onSwitchCost = nil,      -- function(name, cost, fullReset) - combo preview cost label
    onMessage = nil,         -- function(message) - display a game message
    onPreviewProfile = nil,  -- function(name) - preview a profile visually
    onNotAppliedUpdate = nil -- function() - update "not applied" label
}

CharmProfile.lastQuotedApplyCost = nil
CharmProfile.lastQuotedApplyName = nil

-- ============================================================
-- CHARM DATA INJECTION
-- ============================================================
function CharmProfile.setCharmsData(charms, categoryTable)
    charmsTable = charms
    charmCategoryTable = categoryTable
end

-- ============================================================
-- STATE ACCESSORS
-- ============================================================
function CharmProfile.getProfilesList()
    return profilesList
end

function CharmProfile.isLoaded()
    return profilesLoaded
end

function CharmProfile.getMaxMajor()
    return maxMajor
end

function CharmProfile.getMaxMinor()
    return maxMinor
end

--- Minor echo cap for a profile: server sends minorEchoBudget per profile (from majors in that preset).
function CharmProfile.getEffectiveMaxMinorForProfile(profileName)
    if not profileName then
        return maxMinor
    end
    local p = CharmProfile.getProfile(profileName)
    if p and type(p.minorEchoBudget) == "number" then
        return p.minorEchoBudget
    end
    return maxMinor
end

function CharmProfile.getCurrentApplied()
    return currentApplied
end

function CharmProfile.setCurrentApplied(name)
    currentApplied = name
end

function CharmProfile.getPreviewMajor()
    return previewMajor
end

function CharmProfile.getPreviewMinor()
    return previewMinor
end

function CharmProfile.setPreviewRemaining(major, minor)
    previewMajor = major
    previewMinor = minor
end

function CharmProfile.clearPreview()
    previewMajor = nil
    previewMinor = nil
end

function CharmProfile.getPendingSelectProfile()
    return pendingSelectProfile
end

function CharmProfile.setPendingSelectProfile(name)
    pendingSelectProfile = name
end

function CharmProfile.consumePendingSelectProfile()
    local name = pendingSelectProfile
    pendingSelectProfile = nil
    return name
end

function CharmProfile.getIgnoreComboChange()
    return ignoreComboChange
end

function CharmProfile.setIgnoreComboChange(value)
    ignoreComboChange = value
end

function CharmProfile.shouldSkipAutoSave()
    return skipNextAutoSave
end

-- ============================================================
-- CHARM POINTS HELPERS
-- ============================================================
function CharmProfile.getAvailableCharmPoints(resourceType)
    if previewMajor ~= nil and resourceType == ResourceTypes.CHARM then
        return previewMajor
    end
    if previewMinor ~= nil and resourceType == ResourceTypes.MINOR_CHARM then
        return previewMinor
    end
    local player = g_game.getLocalPlayer()
    return player and player:getResourceBalance(resourceType) or 0
end

function CharmProfile.getRemoveRuneCost()
    if cachedRemoveRuneCost > 0 then
        return cachedRemoveRuneCost
    end
    if Cyclopedia.formattedCharmsData then
        for _, cd in ipairs(Cyclopedia.formattedCharmsData) do
            if cd.removeRuneCost and cd.removeRuneCost > 0 then
                cachedRemoveRuneCost = cd.removeRuneCost
                return cd.removeRuneCost
            end
        end
    end
    return 0
end

function CharmProfile.setCachedRemoveRuneCost(cost)
    cachedRemoveRuneCost = cost
end

function CharmProfile.getCachedRemoveRuneCost()
    return cachedRemoveRuneCost
end

-- ============================================================
-- PROTOCOL
-- ============================================================
local function sendAction(action, data)
    data = data or {}
    data.action = action
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedJSONOpcode(OPCODE, data)
    end
end

-- Expose for UI layer (e.g., charge_remove, charge_reset)
CharmProfile.sendAction = sendAction

local function onOpcode(protocol, opcode, data)
    if not data or not data.action then return end
    local cb = CharmProfile.callbacks

    if data.action == "list" then
        profilesList = data.profiles or {}
        maxMajor = data.maxMajor or 0
        maxMinor = data.maxMinor or 0
        if data.removeRuneCost and data.removeRuneCost > 0 then
            cachedRemoveRuneCost = data.removeRuneCost
        end
        profilesLoaded = true
        if #profilesList == 0 then
            pendingSelectProfile = "Default"
            sendAction("save", { name = "Default", charms = {} })
            return
        end
        if data.activeProfile and data.activeProfile ~= "" then
            currentApplied = data.activeProfile
            if not pendingSelectProfile then
                pendingSelectProfile = data.activeProfile
            end
        else
            local defaultNamed = nil
            for _, p in ipairs(profilesList) do
                if p.name and p.name:lower() == "default" then
                    defaultNamed = p.name
                    break
                end
            end
            if defaultNamed then
                currentApplied = defaultNamed
            elseif #profilesList == 1 then
                currentApplied = profilesList[1].name
            end
        end
        if cb.onListReceived then cb.onListReceived() end

    elseif data.action == "saved" then
        if data.name then
            pendingSelectProfile = data.name
        end
        if cb.onMessage then
            cb.onMessage(string.format("Charm profile '%s' saved.", data.name or ""))
        end
        sendAction("list")

    elseif data.action == "cost" then
        CharmProfile.lastQuotedApplyName = data.name
        CharmProfile.lastQuotedApplyCost = data.cost or 0
        if data.preview and cb.onSwitchCost then
            cb.onSwitchCost(data.name, data.cost or 0, data.fullReset == true)
        elseif not data.preview and cb.onCostReceived then
            cb.onCostReceived(data.name, data.cost or 0)
        elseif data.preview and cb.onSwitchCost == nil and cb.onCostReceived then
            cb.onCostReceived(data.name, data.cost or 0)
        end

    elseif data.action == "applied" then
        skipNextAutoSave = false
        currentApplied = data.name or nil
        previewMajor = nil
        previewMinor = nil
        if cb.onMessage then
            cb.onMessage(data.message or "Profile applied.")
        end
        if cb.onApplied then cb.onApplied() end

    elseif data.action == "deleted" then
        if currentApplied == data.name then
            currentApplied = nil
        end
        if cb.onMessage then
            cb.onMessage(string.format("Charm profile '%s' deleted.", data.name or ""))
        end
        sendAction("list")

    elseif data.action == "renamed" then
        if currentApplied == data.oldName then
            currentApplied = data.newName
        end
        if cb.onMessage then
            cb.onMessage(string.format("Profile renamed from '%s' to '%s'.", data.oldName or "", data.newName or ""))
        end
        sendAction("list")

    elseif data.action == "charged" then
        if pendingChargeCallback then
            pendingChargeCallback()
            pendingChargeCallback = nil
        end

    elseif data.action == "error" then
        skipNextAutoSave = false
        pendingChargeCallback = nil
        if cb.onMessage then
            cb.onMessage(data.message or "An error occurred.")
        end
    end
end

-- ============================================================
-- INIT / TERMINATE
-- ============================================================
function CharmProfile.init()
    -- Always unregister first (pcall'd) to handle any stale state from
    -- partial module reloads between sessions, then re-register cleanly.
    pcall(function()
        ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    end)
    ProtocolGame.registerExtendedJSONOpcode(OPCODE, onOpcode)
    registered = true
end

function CharmProfile.terminate()
    pcall(function()
        ProtocolGame.unregisterExtendedJSONOpcode(OPCODE)
    end)
    registered = false
    profilesList = {}
    profilesLoaded = false
    currentApplied = nil
    previewMajor = nil
    previewMinor = nil
    pendingChargeCallback = nil
    cachedRemoveRuneCost = 0
    pendingSelectProfile = nil
    skipNextAutoSave = false
    CharmProfile.getSaveCharmsSnapshot = nil
    CharmProfile.lastQuotedApplyCost = nil
    CharmProfile.lastQuotedApplyName = nil
end

-- ============================================================
-- CRUD OPERATIONS
-- ============================================================
function CharmProfile.requestList()
    sendAction("list")
end

function CharmProfile.save(name, charms)
    if charms then
        sendAction("save", { name = name, charms = charms })
    else
        sendAction("save", { name = name })
    end
end

function CharmProfile.apply(name)
    skipNextAutoSave = true
    sendAction("apply", { name = name })
end

function CharmProfile.delete(name)
    sendAction("delete", { name = name })
end

function CharmProfile.rename(oldName, newName)
    sendAction("rename", { oldName = oldName, newName = newName })
end

function CharmProfile.requestCost(name, previewOnly)
    if not name then return end
    sendAction("cost", { name = name, preview = previewOnly and true or false })
end

-- ============================================================
-- PROFILE DATA ACCESS
-- ============================================================
function CharmProfile.getProfileNames()
    local names = {}
    for _, p in ipairs(profilesList) do
        table.insert(names, p.name)
    end
    return names
end

function CharmProfile.getProfile(profileName)
    for _, p in ipairs(profilesList) do
        if p.name == profileName then return p end
    end
    return nil
end

function CharmProfile.getProfileCharms(profileName)
    local profile = CharmProfile.getProfile(profileName)
    if not profile then return nil end
    return profile.charms or {}
end

-- Build a lookup table: charmId -> { tier, raceId } for a profile
function CharmProfile.buildCharmLookup(profileName)
    local profileCharms = CharmProfile.getProfileCharms(profileName)
    if not profileCharms then return nil end
    local lookup = {}
    for _, c in ipairs(profileCharms) do
        lookup[c.charmId] = c
    end
    return lookup
end

-- Get used charm points for a profile
function CharmProfile.getProfileUsedPoints(profileName)
    local profile = CharmProfile.getProfile(profileName)
    if not profile then return 0, 0 end
    return profile.majorUsed or 0, profile.minorUsed or 0
end

-- ============================================================
-- PREVIEWED PROFILE DETECTION
-- ============================================================
-- Returns the previewed profile name if a non-applied profile is selected.
-- `selectedName` must be provided by the UI layer (from combo box).
function CharmProfile.getPreviewedName(selectedName)
    if not selectedName then return nil end
    if currentApplied and selectedName:lower() == currentApplied:lower() then return nil end
    return selectedName
end

-- ============================================================
-- PENDING CHARGE CALLBACK
-- ============================================================
function CharmProfile.setPendingChargeCallback(callback)
    pendingChargeCallback = callback
end

function CharmProfile.clearPendingChargeCallback()
    pendingChargeCallback = nil
end

-- ============================================================
-- LOCAL PROFILE MANIPULATION
-- ============================================================
-- Minor echo budget from majors only (must match Canary data/scripts/charmProfile.lua).
local function minorEchoBudgetFromProfileCharms(charmsList)
    local total = 0
    if not charmsList or not charmsTable or not charmCategoryTable then
        return 0
    end
    for _, entry in ipairs(charmsList) do
        local tr = entry.tier or 0
        if tr > 0 then
            local ce = charmsTable[entry.charmId]
            if ce and ce.category == charmCategoryTable.CHARM_MAJOR then
                for t = 0, tr - 1 do
                    total = total + (25 * t * t + 25 * t + 50)
                end
            end
        end
    end
    return total
end

-- Updates a charm in a local profile (tier/raceId), recalculates costs,
-- auto-saves to server, and triggers preview callback.
function CharmProfile.updateLocalCharm(profileName, charmId, newTier, newRaceId)
    local profile = CharmProfile.getProfile(profileName)
    if not profile then return end
    if not charmsTable or not charmCategoryTable then return end
    if not profile.charms then
        profile.charms = {}
    end

    -- Update or insert the charm entry
    local found = false
    for _, c in ipairs(profile.charms) do
        if c.charmId == charmId then
            c.tier = newTier
            c.raceId = newRaceId
            found = true
            break
        end
    end
    if not found and newTier > 0 then
        table.insert(profile.charms, { charmId = charmId, tier = newTier, raceId = newRaceId })
    end

    -- Remove if tier dropped to 0
    if newTier <= 0 then
        for i, c in ipairs(profile.charms) do
            if c.charmId == charmId then
                table.remove(profile.charms, i)
                break
            end
        end
    end

    -- Recalculate used points
    local majorUsed = 0
    local minorUsed = 0
    for _, c in ipairs(profile.charms) do
        local charmEntry = charmsTable[c.charmId]
        if charmEntry and c.tier and c.tier > 0 then
            local cost = 0
            for t = 1, c.tier do
                cost = cost + (charmEntry.points[t] or 0)
            end
            if charmEntry.category == charmCategoryTable.CHARM_MAJOR then
                majorUsed = majorUsed + cost
            elseif charmEntry.category == charmCategoryTable.CHARM_MINOR then
                minorUsed = minorUsed + cost
            end
        end
    end
    profile.majorUsed = majorUsed
    profile.minorUsed = minorUsed
    profile.minorEchoBudget = minorEchoBudgetFromProfileCharms(profile.charms)

    -- Trigger UI preview
    local cb = CharmProfile.callbacks
    if cb.onPreviewProfile then
        cb.onPreviewProfile(profileName)
    end

    -- Auto-save to server
    sendAction("save", { name = profileName, charms = profile.charms })
end

-- Reset all charms in a local profile
function CharmProfile.resetLocalProfile(profileName)
    local profile = CharmProfile.getProfile(profileName)
    if not profile then return end

    profile.charms = {}
    profile.majorUsed = 0
    profile.minorUsed = 0
    profile.minorEchoBudget = 0

    local cb = CharmProfile.callbacks
    if cb.onPreviewProfile then
        cb.onPreviewProfile(profileName)
    end

    sendAction("save", { name = profileName, charms = profile.charms })
end

-- ============================================================
-- CHARM DESCRIPTION HELPER
-- ============================================================
function CharmProfile.getCharmDescription(charmId, tier)
    if not charmsTable then return "" end
    local charmEntry = charmsTable[charmId]
    if not charmEntry then return "" end

    local description = charmEntry.description
    if charmEntry.chance then
        local tierIndex = tier >= 1 and tier or 1
        local chanceValue = charmEntry.chance[tierIndex] or charmEntry.chance[1]
        description = string.format(description, chanceValue)
    end
    return description
end

-- ============================================================
-- LOCAL DEFAULT PROFILE (client-side fallback)
-- ============================================================
-- Creates/updates a "Default" profile locally from the server's charm data,
-- without requiring server-side opcode 245 support.
-- Called from Cyclopedia.loadCharms() every time the server sends charm data.
-- If the server later responds to opcode 245 "list", profilesLoaded becomes true
-- and this function becomes a no-op, letting server data take over.
function CharmProfile.ensureLocalDefault(charmsPayload)
    if profilesLoaded then return end  -- server is managing profiles, don't interfere

    -- Find or update the Default entry in our local list
    local found = false
    for _, p in ipairs(profilesList) do
        if p.name and p.name:lower() == "default" then
            if charmsPayload then
                p.charms = charmsPayload
            end
            found = true
            break
        end
    end
    if not found then
        table.insert(profilesList, {
            name = "Default",
            charms = charmsPayload or {},
            majorUsed = 0,
            minorUsed = 0
        })
    end

    if not currentApplied then
        currentApplied = "Default"
    end

    -- Do not call onListReceived here: it runs refreshProfileUI → loadCharms while loadCharms
    -- is still executing (profilesLoaded is still false), causing infinite recursion and a freeze.
    -- The combo refreshes when the real opcode 245 "list" arrives.
end

-- ============================================================
-- CHARGE ACTIONS (for preview mode gold costs)
-- ============================================================
function CharmProfile.chargeRemove()
    sendAction("charge_remove")
end

function CharmProfile.chargeReset()
    sendAction("charge_reset")
end
