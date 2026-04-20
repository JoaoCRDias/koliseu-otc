local UI = nil
local TypeCharmRadioGroup = nil
local isModernUI = false
local loadCharmsRecursionDepth = 0
Cyclopedia.Charms = Cyclopedia.Charms or {}

-- Server often omits GameServerBestiaryCharmsData (216) right after BuyCharmRune; re-request bestiary
-- so Cyclopedia.loadCharms runs with fresh tiers/points without relogging.
local function scheduleRefreshCharmsFromServer()
    scheduleEvent(function()
        if g_game.isOnline() then
            g_game.requestBestiary()
        end
    end, 50)
end

-- ============================================================
-- LOCAL HELPERS (delegate to CharmProfile)
-- ============================================================
local function getAvailableCharmPoints(resourceType)
    return CharmProfile.getAvailableCharmPoints(resourceType)
end

local function getRemoveRuneCost()
    return CharmProfile.getRemoveRuneCost()
end

local function getSelectedComboName()
    if not UI or not isModernUI then return nil end
    local combo = UI:recursiveGetChildById('charmProfilesCombo')
    if not combo then return nil end
    local currentOpt = combo:getCurrentOption()
    return currentOpt and currentOpt.data or nil
end

local function getPreviewedProfileName()
    return CharmProfile.getPreviewedName(getSelectedComboName())
end

-- ============================================================
-- PROFILE UI FUNCTIONS
-- ============================================================
local function updateNotAppliedLabel()
    if not UI or not isModernUI then return end
    local label = UI:recursiveGetChildById('charmProfileNotAppliedLabel')
    if not label then return end
    local selectedName = getSelectedComboName()
    local currentApplied = CharmProfile.getCurrentApplied()
    if not selectedName or not currentApplied or currentApplied == "" then
        label:setVisible(false)
        return
    end
    label:setVisible(selectedName:lower() ~= currentApplied:lower())
end

local function updateCharmProfileApplyCostLabel(cost, fullReset)
    if not UI or not isModernUI then return end
    local w = UI:recursiveGetChildById('charmProfileApplyCostLabel')
    if not w then return end
    local extra = fullReset and tr(" (uses reset all)") or ""
    w:setText(tr("Apply cost: %s gold%s", comma_value(cost or 0), extra))
end

function Cyclopedia.Charms.refreshProfileUI()
    if not UI or not isModernUI then return end
    local profilesCombo = UI:recursiveGetChildById('charmProfilesCombo')
    if not profilesCombo then return end
    local previousSelection = profilesCombo:getCurrentOption()
    local previousName = previousSelection and previousSelection.data or nil
    CharmProfile.setIgnoreComboChange(true)
    profilesCombo:clearOptions()
    local names = CharmProfile.getProfileNames()
    table.sort(names)
    for _, name in ipairs(names) do
        local display = #name > 20 and name:sub(1, 20) .. "." or name
        profilesCombo:addOption(display, name)
    end
    local targetName = CharmProfile.consumePendingSelectProfile() or previousName or CharmProfile.getCurrentApplied()
    local matched = false
    if targetName then
        for _, name in ipairs(names) do
            if name == targetName then
                local display = #name > 20 and name:sub(1, 20) .. "." or name
                profilesCombo:setCurrentOption(display)
                matched = true
                break
            end
        end
    end
    CharmProfile.setIgnoreComboChange(false)
    profilesCombo:setTextAlign(AlignLeftCenter)
    local currentOpt = profilesCombo:getCurrentOption()
    local currentName = currentOpt and currentOpt.data or nil
    if currentName and currentName ~= "" then
        if CharmProfile.getPreviewedName(currentName) then
            Cyclopedia.Charms.previewProfile(currentName)
        elseif Cyclopedia.charmsData and loadCharmsRecursionDepth == 0 then
            Cyclopedia.loadCharms(Cyclopedia.charmsData)
        else
            Cyclopedia.Charms.previewProfile(currentName)
        end
        CharmProfile.requestCost(currentName, true)
    end
    local hasProfiles = #names > 0
    local deleteBtn = UI:recursiveGetChildById('charmProfileDeleteBtn')
    local renameBtn = UI:recursiveGetChildById('charmProfileRenameBtn')
    if deleteBtn then deleteBtn:setEnabled(#names > 1) end
    if renameBtn then renameBtn:setEnabled(hasProfiles) end
    updateNotAppliedLabel()
end

function Cyclopedia.Charms.previewProfile(profileName)
    if not UI or not isModernUI then return end
    local CharmList = UI.mainPanelCharmsType and UI.mainPanelCharmsType.panelCharmList and
        UI.mainPanelCharmsType.panelCharmList.CharmList
    if not CharmList then return end

    -- Preset: tier + raceId come from the profile JSON; prices/metadata from last server payload.
    if not Cyclopedia.formattedCharmsData then return end
    CharmProfile.clearPreview()

    local profileLookup = CharmProfile.buildCharmLookup(profileName) or {}
    local profileCharmsList = CharmProfile.getProfileCharms(profileName)
    local isEmptyPreset = not profileCharmsList or #profileCharmsList == 0
    local fdById = {}
    for _, c in ipairs(Cyclopedia.formattedCharmsData) do
        if c.id ~= nil then fdById[c.id] = c end
    end
    local lookup = {}
    for id, c in pairs(fdById) do
        local pe = profileLookup[id]
        local pTier, pRaceId
        if pe then
            pTier = pe.tier or 0
            pRaceId = pe.raceId or 0
        elseif isEmptyPreset then
            -- Perfil novo sem nenhuma runa gravada: folha em branco (não copiar o último snapshot/aplicado).
            pTier = 0
            pRaceId = 0
        else
            -- Preset com dados: runas sem linha no JSON espelham o último pacote do servidor.
            pTier = c.tier or 0
            pRaceId = c.raceId or 0
        end
        lookup[id] = {
            tier = pTier,
            raceId = pRaceId,
            unlocked = pTier > 0,
            removeRuneCost = c.removeRuneCost,
            unlockPrice = c.unlockPrice,
        }
    end

    local function computeUsedFromCharmLookup(lk)
        local majorUsed, minorUsed = 0, 0
        for charmId, row in pairs(lk) do
            local t = row.tier or 0
            if t > 0 then
                local charmEntry = charms[charmId]
                if charmEntry and charmEntry.points then
                    local cost = 0
                    for ti = 1, t do
                        cost = cost + (charmEntry.points[ti] or 0)
                    end
                    if charmEntry.category == 1 then -- charmCategory_t.CHARM_MAJOR
                        majorUsed = majorUsed + cost
                    elseif charmEntry.category == 2 then -- charmCategory_t.CHARM_MINOR
                        minorUsed = minorUsed + cost
                    end
                end
            end
        end
        return majorUsed, minorUsed
    end

    for _, widget in ipairs(CharmList:getChildren()) do
        if widget.data and widget.data.id ~= nil then
            local charmId = widget.data.id
            local entry = lookup[charmId]
            local pTier = entry and entry.tier or 0
            local pRaceId = entry and entry.raceId or 0
            local isUnlocked = pTier > 0
            widget.data.tier = pTier
            widget.data.raceId = pRaceId
            widget.data.asignedStatus = pRaceId > 0
            if pRaceId > 0 and (not widget.data.removeRuneCost or widget.data.removeRuneCost == 0) then
                widget.data.removeRuneCost = (entry and entry.removeRuneCost) or getRemoveRuneCost()
            end
            widget.data.unlocked = isUnlocked
            if pTier > 0 then
                widget.charmBase.border:setImageSource(
                    "/game_cyclopedia/images/charms/border/backdrop_charmgrade" .. pTier)
                widget.charmBase.lockedMask:setVisible(false)
            else
                widget.charmBase.border:setImageSource("")
                widget.charmBase.lockedMask:setVisible(true)
            end
            widget.icon = isUnlocked and 1 or 0
            if pRaceId > 0 and widget.InfoBase and widget.InfoBase.Sprite then
                local raceData = g_things.getRaceData(pRaceId)
                widget.InfoBase.Sprite:setOutfit(raceData.outfit)
                widget.InfoBase.Sprite:getCreature():setStaticWalking(1000)
                widget.InfoBase.Sprite:setVisible(true)
            elseif widget.InfoBase and widget.InfoBase.Sprite then
                widget.InfoBase.Sprite:setVisible(false)
            end
            if isUnlocked then
                widget.PriceBase.Value:setText(pRaceId > 0 and comma_value(widget.data.removeRuneCost or 0) or "0")
            else
                widget.PriceBase.Value:setText(comma_value(widget.data.unlockPrice or 0))
            end
        end
    end

    local player = g_game.getLocalPlayer()
    local pMaxMajor = CharmProfile.getMaxMajor()
    local pMaxMinor = CharmProfile.getEffectiveMaxMinorForProfile(profileName)
    if pMaxMajor <= 0 and player then
        pMaxMajor = player:getResourceBalance(ResourceTypes.MAX_CHARM)
    end
    if pMaxMinor <= 0 and player then
        pMaxMinor = player:getResourceBalance(ResourceTypes.MAX_MINOR_CHARM)
    end
    local usedM, usedN = computeUsedFromCharmLookup(lookup)
    local remM = math.max(0, pMaxMajor - usedM)
    local remN = math.max(0, pMaxMinor - usedN)
    CharmProfile.setPreviewRemaining(remM, remN)
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui.CharmsBase.Value:setText(string.format("%d/%d", remM, pMaxMajor))
        controllerCyclopedia.ui.CharmsBase1410.Value:setText(string.format("%d/%d", remN, pMaxMinor))
    end

    local hasUnlockedInProfile = false
    for _, row in pairs(lookup) do
        if (row.tier or 0) > 0 then hasUnlockedInProfile = true; break end
    end
    if UI and UI.anotherPanel and UI.anotherPanel.ResetAllCharmsButton then
        UI.anotherPanel.ResetAllCharmsButton:setEnabled(hasUnlockedInProfile)
    end
    local children = CharmList:getChildren()
    local sorted = {}
    for _, w in ipairs(children) do table.insert(sorted, w) end
    table.sort(sorted, function(a, b)
        local tierA = (a.data and a.data.tier) or 0
        local tierB = (b.data and b.data.tier) or 0
        if tierA ~= tierB then return tierA > tierB end
        local nameA = (a.data and a.data.name) or ""
        local nameB = (b.data and b.data.name) or ""
        return nameA:lower() < nameB:lower()
    end)
    for i, w in ipairs(sorted) do CharmList:moveChildToIndex(w, i) end
    CharmList:getLayout():update()
    local targetWidget = nil
    local selectedId = Cyclopedia.Charms.currentSelectedId
    if selectedId then
        for _, widget in ipairs(CharmList:getChildren()) do
            if widget:isVisible() and widget.data and widget.data.id == selectedId then
                targetWidget = widget
                break
            end
        end
    end
    if not targetWidget then
        for _, widget in ipairs(CharmList:getChildren()) do
            if widget:isVisible() then targetWidget = widget; break end
        end
    end
    if targetWidget then
        Cyclopedia.selectCharm(targetWidget, targetWidget:isChecked())
    end
end

function Cyclopedia.Charms.showApplyConfirmation(profileName, cost)
    if not profileName or profileName == "" then return end
    local confirmWindow = nil
    local function yesCallback()
        CharmProfile.apply(profileName)
        if confirmWindow then confirmWindow:destroy(); confirmWindow = nil end
    end
    local function noCallback()
        if confirmWindow then confirmWindow:destroy(); confirmWindow = nil end
    end
    local message = tr("Apply profile '%s'?\n\nThis will cost %s gold.", profileName, comma_value(cost))
    confirmWindow = displayGeneralBox(tr("Apply Charm Profile"), message, {
        { text = tr("Yes"), callback = yesCallback },
        { text = tr("No"),  callback = noCallback },
        anchor = AnchorHorizontalCenter
    }, yesCallback, noCallback, controllerCyclopedia.ui)
end

-- Cleanup function to be called before tab switch
function Cyclopedia.Charms.cleanup()
    if TypeCharmRadioGroup then
        pcall(function()
            disconnect(TypeCharmRadioGroup, { onSelectionChange = onTypeCharmRadioGroup })
            TypeCharmRadioGroup:destroy()
        end)
        TypeCharmRadioGroup = nil
    end
    UI = nil
end

-- ============================================================
-- PROFILE CALLBACKS SETUP
-- ============================================================
local function setupProfileCallbacks()
    CharmProfile.callbacks.onListReceived = function()
        Cyclopedia.Charms.refreshProfileUI()
    end
    CharmProfile.callbacks.onApplied = function()
        Cyclopedia.Charms.refreshProfileUI()
        g_game.requestBestiary()
        updateNotAppliedLabel()
    end
    CharmProfile.callbacks.onCostReceived = function(name, cost)
        Cyclopedia.Charms.showApplyConfirmation(name, cost)
    end
    CharmProfile.callbacks.onSwitchCost = function(name, cost, fullReset)
        updateCharmProfileApplyCostLabel(cost, fullReset)
    end
    CharmProfile.callbacks.onMessage = function(message)
        modules.game_textmessage.displayGameMessage(message)
    end
    CharmProfile.callbacks.onPreviewProfile = function(name)
        Cyclopedia.Charms.previewProfile(name)
    end
    CharmProfile.callbacks.onNotAppliedUpdate = function()
        updateNotAppliedLabel()
    end
end

local charmCategory_t = {
    CHARM_ALL = 0,
    CHARM_MAJOR = 1,
    CHARM_MINOR = 2
};

local charm_t = {
    CHARM_UNDEFINED = 0,
    CHARM_OFFENSIVE = 1,
    CHARM_DEFENSIVE = 2,
    CHARM_PASSIVE = 3
};
local charmRune_t = {
    CHARM_WOUND = 0,
    CHARM_ENFLAME = 1,
    CHARM_POISON = 2,
    CHARM_FREEZE = 3,
    CHARM_ZAP = 4,
    CHARM_CURSE = 5,
    CHARM_CRIPPLE = 6,
    CHARM_PARRY = 7,
    CHARM_DODGE = 8,
    CHARM_ADRENALINE = 9,
    CHARM_NUMB = 10,
    CHARM_CLEANSE = 11,
    CHARM_BLESS = 12,
    CHARM_SCAVENGE = 13,
    CHARM_GUT = 14,
    CHARM_LOW = 15,
    CHARM_DIVINE = 16,
    CHARM_VAMP = 17,
    CHARM_VOID = 18,
    CHARM_SAVAGE = 19,
    CHARM_FATAL = 20,
    CHARM_VOIDINVERSION = 21,
    CHARM_CARNAGE = 22,
    CHARM_OVERPOWER = 23,
    CHARM_OVERFLUX = 24
}

local charms = {
    [charmRune_t.CHARM_WOUND] = {
        name = "Wound",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as physical damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 240, 360, 1200 }
    },
    [charmRune_t.CHARM_ENFLAME] = {
        name = "Enflame",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as fire damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 400, 600, 2000 }
    },
    [charmRune_t.CHARM_POISON] = {
        name = "Poison",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as earth damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 240, 360, 1200 }
    },
    [charmRune_t.CHARM_FREEZE] = {
        name = "Freeze",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as ice damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 320, 480, 1600 }
    },
    [charmRune_t.CHARM_ZAP] = {
        name = "Zap",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as energy damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 320, 480, 1600 }
    },
    [charmRune_t.CHARM_CURSE] = {
        name = "Curse",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as death damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 360, 540, 1800 }
    },
    [charmRune_t.CHARM_CRIPPLE] = {
        name = "Cripple",
        description = "Cripples the creature with a %s%% chance and paralyzes it for 10 seconds.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_OFFENSIVE,
        chance = { 6, 9, 12 },
        messageCancel = "You crippled a monster. (cripple charm)",
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_PARRY] = {
        name = "Parry",
        description = "Reflects incoming damage back to the aggressor with a %s%% chance.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_DEFENSIVE,
        chance = { 5, 10, 11 },
        messageCancel = "You parried an attack. (parry charm)",
        points = { 400, 600, 2000 }
    },
    [charmRune_t.CHARM_DODGE] = {
        name = "Dodge",
        description = "Dodges an attack with a %s%% chance, avoiding all damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_DEFENSIVE,
        chance = { 5, 10, 11 },
        messageCancel = "You dodged an attack. (dodge charm)",
        points = { 240, 360, 1200 }
    },
    [charmRune_t.CHARM_ADRENALINE] = {
        name = "Adrenaline Burst",
        description = "Boosts movement speed for 10 seconds after being hit with a %s%% chance.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_DEFENSIVE,
        chance = { 6, 9, 12 },
        messageCancel = "Your movements where bursted. (adrenaline burst charm)",
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_NUMB] = {
        name = "Numb",
        description = "Numbs the creature with a %s%% chance and paralyzes it for 10 seconds.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_DEFENSIVE,
        chance = { 6, 9, 12 },
        messageCancel = "You numbed a monster. (numb charm)",
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_CLEANSE] = {
        name = "Cleanse",
        description = "Removes a negative status effect with a %s%% chance and grants temporary immunity.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_DEFENSIVE,
        chance = { 6, 9, 12 },
        messageCancel = "You purified an attack. (cleanse charm)",
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_BLESS] = {
        name = "Bless",
        description = "Reduces skill and XP loss by %s%% when killed by the chosen creature.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        percent = 10,
        chance = { 6, 9, 12 },
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_SCAVENGE] = {
        name = "Scavenge",
        description = "Enhances chances to successfully skin or dust a creature by %s%%.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 60, 90, 120 },
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_GUT] = {
        name = "Gut",
        description = "Increases creature product yields by %s%%.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 6, 9, 12 },
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_LOW] = {
        name = "Low Blow",
        description = "Adds %s%% critical hit chance to attacks with critical hit weapons.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 4, 8, 9 },
        points = { 800, 1200, 4000 }
    },
    [charmRune_t.CHARM_DIVINE] = {
        name = "Divine Wrath",
        description = "Triggers on a creature with a %s%% chance to deal 5%% of its initial HP as holy damage.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 600, 900, 3000 }
    },
    [charmRune_t.CHARM_VAMP] = {
        name = "Vampiric Embrace",
        description = "Adds %s%% life leech to attacks if using life-leeching equipment.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 1.6, 2.4, 3.2 },
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_VOID] = {
        name = "Void's Call",
        description = "Adds %s%% mana leech to attacks if using mana-leeching equipment.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 0.8, 1.2, 1.6 },
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_SAVAGE] = {
        name = "Savage Blow",
        description = "Adds %s%% extra critical damage to attacks with critical hit weapons.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 20, 40, 44 },
        points = { 800, 1200, 4000 }
    },
    [charmRune_t.CHARM_FATAL] = {
        name = "Fatal Hold",
        description = "Prevents creatures from fleeing due to low health for 30 seconds with a %s%% chance.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 30, 45, 60 },
        messageCancel = "Your enemy is not able to flee now for 30 seconds. (fatal hold charm)",
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_VOIDINVERSION] = {
        name = "Void Inversion",
        description = "%s%% chance to gain mana instead of losing it when taking Mana Drain damage.",
        category = charmCategory_t.CHARM_MINOR,
        type = charm_t.CHARM_PASSIVE,
        chance = { 20, 30, 40 },
        points = { 100, 150, 225 }
    },
    [charmRune_t.CHARM_CARNAGE] = {
        name = "Carnage",
        description = "Killing a monster has a %s%% chance to deal physical damage to others nearby.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 15,
        chance = { 10, 20, 22 },
        points = { 600, 900, 3000 }
    },
    [charmRune_t.CHARM_OVERPOWER] = {
        name = "Overpower",
        description = "Deals physical damage based on your maximum health with a %s%% chance.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 5,
        chance = { 5, 10, 11 },
        points = { 600, 900, 3000 }
    },
    [charmRune_t.CHARM_OVERFLUX] = {
        name = "Overflux",
        description = "Deals physical damage based on your maximum mana with a %s%% chance.",
        category = charmCategory_t.CHARM_MAJOR,
        type = charm_t.CHARM_OFFENSIVE,
        percent = 2.5,
        chance = { 5, 10, 11 },
        points = { 600, 900, 3000 }
    }
}

-- Inject charm data into the profile module
CharmProfile.setCharmsData(charms, charmCategory_t)

-- Setup profile callbacks now that UI functions are defined
setupProfileCallbacks()

local function mergeCharmsDataWithProfile(serverData, profileName)
    if not serverData or not serverData.charms then
        return serverData
    end
    local lookup = CharmProfile.buildCharmLookup(profileName)
    local merged = {
        charms = {},
        finishedMonsters = serverData.finishedMonsters,
        resetAllCharmsCost = serverData.resetAllCharmsCost,
        points = serverData.points
    }
    for _, ch in pairs(serverData.charms) do
        local c = {}
        for k, v in pairs(ch) do
            c[k] = v
        end
        if lookup and c.id and lookup[c.id] then
            local p = lookup[c.id]
            c.tier = p.tier
            c.raceId = p.raceId
            c.asignedStatus = (p.raceId and p.raceId > 0) == true
        end
        table.insert(merged.charms, c)
    end
    return merged
end

local function getCharmProfileComboSelectedName()
    if not isModernUI or not UI then
        return nil
    end
    local combo = UI:recursiveGetChildById("charmProfilesCombo")
    local opt = combo and combo:getCurrentOption()
    return opt and (opt.data or opt.text) or nil
end

local function isCharmProfilePreviewMode()
    local n = getCharmProfileComboSelectedName()
    return n ~= nil and CharmProfile.getPreviewedName(n) ~= nil
end

local function cloneProfileCharmsTable(profile)
    if not profile or not profile.charms then
        return nil
    end
    local copy = {}
    for _, c in ipairs(profile.charms) do
        table.insert(copy, {
            charmId = c.charmId,
            tier = c.tier or 0,
            raceId = c.raceId or 0
        })
    end
    return copy
end

local function buildCharmsPayloadForSave()
    local arr = {}
    local seen = {}
    local function addEntry(tid, tier, raceId)
        if not tid or not tier or tier < 1 then
            return
        end
        if seen[tid] then
            return
        end
        seen[tid] = true
        table.insert(arr, {
            charmId = tid,
            tier = tier,
            raceId = raceId or 0
        })
    end
    if isCharmProfilePreviewMode() and UI and isModernUI and UI.mainPanelCharmsType then
        local CharmList = UI.mainPanelCharmsType.panelCharmList.CharmList
        for _, w in ipairs(CharmList:getChildren()) do
            local d = w.data
            if d then
                addEntry(d.internalId or d.id, d.tier or 0, d.raceId)
            end
        end
    end
    if #arr == 0 and Cyclopedia.formattedCharmsData then
        for _, c in ipairs(Cyclopedia.formattedCharmsData) do
            addEntry(c.internalId or c.id, c.tier or 0, c.raceId)
        end
    end
    if #arr == 0 and UI and isModernUI and UI.mainPanelCharmsType then
        local CharmList = UI.mainPanelCharmsType.panelCharmList.CharmList
        for _, w in ipairs(CharmList:getChildren()) do
            local d = w.data
            if d then
                addEntry(d.internalId or d.id, d.tier or 0, d.raceId)
            end
        end
    end
    if #arr == 0 and Cyclopedia.charmsData and Cyclopedia.charmsData.charms then
        for _, ch in pairs(Cyclopedia.charmsData.charms) do
            addEntry(ch.id, ch.tier or 0, ch.raceId)
        end
    end
    return arr
end

local function getCharmDescription(charmId, tier)
    return CharmProfile.getCharmDescription(charmId, tier)
end

function showCharms()
    isModernUI = g_game.getClientVersion() >= 1410
    local UIUX = isModernUI and "charms1410" or "charms"
    UI = g_ui.loadUI(UIUX, contentContainer)
    UI:show()
    g_game.requestBestiary()
    controllerCyclopedia.ui.CharmsBase:setVisible(true)
    controllerCyclopedia.ui.GoldBase:setVisible(true)
    controllerCyclopedia.ui.BestiaryTrackerButton:setVisible(false)
    if isModernUI then
        controllerCyclopedia.ui.CharmsBase1410:setVisible(true)
        TypeCharmRadioGroup = UIRadioGroup.create()
        TypeCharmRadioGroup:addWidget(UI.mainPanelCharmsType.typeCharmPanel.MajorCharms)
        TypeCharmRadioGroup:addWidget(UI.mainPanelCharmsType.typeCharmPanel.MinorCharms)
        TypeCharmRadioGroup:selectWidget(TypeCharmRadioGroup:getFirstWidget())
        connect(TypeCharmRadioGroup, {
            onSelectionChange = onTypeCharmRadioGroup
        })

        -- Initialize charm profiles
        CharmProfile.init()
        CharmProfile.getSaveCharmsSnapshot = function()
            return buildCharmsPayloadForSave()
        end
        Cyclopedia.Charms.setupProfileButtons()
        CharmProfile.requestList()

        -- If charm data was already received before the cyclopedia was opened
        -- (happens when the user opens the tab after login), ensure the local
        -- Default profile exists and populates the combo immediately.
        -- If the server responds to requestList() with real profiles, they will
        -- override this via onListReceived callback.
        CharmProfile.ensureLocalDefault(buildCharmsPayloadForSave())
    end
end

function onTerminateCharm()
    if TypeCharmRadioGroup then
        disconnect(TypeCharmRadioGroup, {
            onSelectionChange = onTypeCharmRadioGroup
        })
        TypeCharmRadioGroup:destroy()
        TypeCharmRadioGroup = nil
    end
    CharmProfile.terminate()
end

function Cyclopedia.CreateCharmItem(data)
    local CharmList = isModernUI and UI.mainPanelCharmsType.panelCharmList.CharmList or UI.CharmList
    local widget = g_ui.createWidget("CharmItem", CharmList)
    local value = widget.PriceBase.Value

    widget:setId(data.id)
    widget.charmBase.image:setImageSource("/game_cyclopedia/images/charms/monster-bonus-effects")

    if data.id ~= nil then
        widget.charmBase.image:setImageClip((data.id * 32) .. ' 0 32 32')
    else
        g_logger.error(string.format("Cyclopedia.CreateCharmItem - charm %s is nil", data.id))
        return
    end

    local charmData = charms[data.id]
    widget:setText(isModernUI and charmData.name or data.name)
    widget.data = data

    if data.asignedStatus then
        if data.raceId then
            local raceData = g_things.getRaceData(data.raceId)
            widget.InfoBase.Sprite:setOutfit(raceData.outfit)
            widget.InfoBase.Sprite:getCreature():setStaticWalking(1000)
        else
            g_logger.error("Cyclopedia.CreateCharmItem - no race id provided")
        end
    end

    local isUnlocked = data.tier > 0 or data.unlocked
    if not isModernUI then
        widget.PriceBase.Charm:setVisible(not isUnlocked)
        widget.PriceBase.Gold:setVisible(isUnlocked)
    end
    widget.charmBase.lockedMask:setVisible(not isUnlocked)
    widget.icon = isUnlocked and 1 or 0

    if isUnlocked then
        widget.PriceBase.Value:setText(data.asignedStatus and comma_value(data.removeRuneCost) or 0)
    else
        widget.PriceBase.Value:setText(comma_value(data.unlockPrice))
    end



    if widget.icon == 1 then
        local removeRuneCost = data.removeRuneCost or 0
        local canAfford = removeRuneCost <= Cyclopedia.getPlayerTotalGold()
        -- Color logic: 0 -> gray, can't afford -> red, can afford -> normal
        local textColor = "#C0C0C0"
        if removeRuneCost == 0 then
            textColor = "#707070"
        elseif not canAfford then
            textColor = "#D33C3C"
        end
        value:setColor(textColor)
    elseif widget.icon == 0 then
        local canAfford = data.unlockPrice <= UI.CharmsPoints
        value:setColor(canAfford and "#C0C0C0" or "#D33C3C")
    end

    widget.category = charmData.category

    if isModernUI and data.tier > 0 then
        widget.charmBase.border:setImageSource("/game_cyclopedia/images/charms/border/backdrop_charmgrade" .. data.tier)
    end
end

function Cyclopedia.loadCharms(charmsData)
    loadCharmsRecursionDepth = loadCharmsRecursionDepth + 1
    local function finishLoadCharms()
        loadCharmsRecursionDepth = loadCharmsRecursionDepth - 1
    end

    -- Store charms data globally for bestiary tab (even if UI is not open)
    Cyclopedia.charmsData = charmsData

    -- Always create widgets from the server's charm data.
    -- Profile-specific creature assignments are overlaid by previewProfile()
    -- at the end of this function, after widgets are built.
    CharmProfile.clearPreview()
    local uiData = charmsData

    -- Process and store formatted charms data with category info
    local formattedDataForStorage = {}
    for _, charmData in pairs(charmsData.charms) do
        local internalId = charmData.id
        if internalId and charms[internalId] then
            local charm = charms[internalId]
            local formattedCharm = {
                id = charmData.id,
                name = charmData.name ~= "" and charmData.name or charm.name,
                description = charmData.description ~= "" and charmData.description or charm.description,
                internalId = internalId,
                typePriority = charm.type,
                category = charm.category,
                unlocked = charmData.unlocked,
                tier = charmData.tier or 0,
                unlockPrice = charmData.unlockPrice,
                removeRuneCost = charmData.removeRuneCost,
                asignedStatus = charmData.asignedStatus,
                raceId = charmData.raceId
            }
            table.insert(formattedDataForStorage, formattedCharm)
        end
    end
    Cyclopedia.formattedCharmsData = formattedDataForStorage

    -- DEBUG: Print all charm data received from server
    -- print("=== CHARMS DATA FROM SERVER ===")
    -- print(string.format("Total charms: %d", #formattedDataForStorage))
    -- for i, charm in ipairs(formattedDataForStorage) do
    --     print(string.format(
    --         "[%d] id=%d, name=%s, category=%s, tier=%d, unlocked=%s, asignedStatus=%s, raceId=%s, removeRuneCost=%s, unlockPrice=%s",
    --         i,
    --         charm.id or -1,
    --         charm.name or "nil",
    --         charm.category == 1 and "MAJOR" or (charm.category == 2 and "MINOR" or tostring(charm.category)),
    --         charm.tier or 0,
    --         tostring(charm.unlocked),
    --         tostring(charm.asignedStatus),
    --         tostring(charm.raceId or "nil"),
    --         tostring(charm.removeRuneCost or "nil"),
    --         tostring(charm.unlockPrice or "nil")
    --     ))
    -- end
    -- print("=== END CHARMS DATA ===")

    if not UI then
        finishLoadCharms()
        return
    end
    if isModernUI and not UI.mainPanelCharmsType then
        finishLoadCharms()
        return
    end
    local CharmList = isModernUI and UI.mainPanelCharmsType.panelCharmList.CharmList or UI.CharmList
    local player = g_game.getLocalPlayer()
    if not CharmList then
        finishLoadCharms()
        return
    end
    if isModernUI then
        local formatResourceBalance = function(resourceType, maxResourceType)
            local cur = CharmProfile.getAvailableCharmPoints(resourceType)
            local max = player:getResourceBalance(maxResourceType)
            return string.format("%d/%d", cur, max)
        end

        controllerCyclopedia.ui.CharmsBase.Value:setText(formatResourceBalance(ResourceTypes.CHARM,
            ResourceTypes.MAX_CHARM))
        controllerCyclopedia.ui.CharmsBase1410.Value:setText(
            formatResourceBalance(ResourceTypes.MINOR_CHARM, ResourceTypes.MAX_MINOR_CHARM))

        -- Setup Reset All Charms button and cost display
        -- Check if player has at least one unlocked charm
        local hasUnlockedCharm = false
        for _, charmData in pairs(uiData.charms) do
            if charmData.unlocked or (charmData.tier and charmData.tier > 0) then
                hasUnlockedCharm = true
                break
            end
        end

        local resetAllCharmsCost = charmsData.resetAllCharmsCost or 0
        local canAffordResetAll = resetAllCharmsCost <= Cyclopedia.getPlayerTotalGold()
        local canResetAll = hasUnlockedCharm and canAffordResetAll

        -- Set the cost value (anotherPanel is directly under UI, not under mainPanelCharmsType)
        local formattedCost = comma_value(resetAllCharmsCost)
        local resetAllCharmsWidget = UI.anotherPanel.ResetAllCharms
        local valueWidget = resetAllCharmsWidget and resetAllCharmsWidget.Value
        if valueWidget then
            valueWidget:setText(tostring(formattedCost))
            -- Color logic:
            -- No charm to reset -> gray (#707070)
            -- Has charm but can't afford -> red (#D33C3C)
            -- Can reset -> normal (#C0C0C0)
            local textColor = "#C0C0C0"
            if not hasUnlockedCharm then
                textColor = "#707070"
            elseif not canAffordResetAll then
                textColor = "#D33C3C"
            end
            valueWidget:setColor(textColor)
            valueWidget:setVisible(true)
            valueWidget:resizeToText()
        end

        -- Enable/disable the button (only if has unlocked charm AND can afford)
        UI.anotherPanel.ResetAllCharmsButton:setEnabled(canResetAll)
    else
        controllerCyclopedia.ui.CharmsBase.Value:setText(Cyclopedia.formatGold(charmsData.points))
    end

    UI.CharmsPoints = charmsData.points

    Cyclopedia.Charms.Monsters = {}
    local raceIdNamePairs = {}

    for _, raceId in ipairs(charmsData.finishedMonsters) do
        local raceData = g_things.getRaceData(raceId)
        local raceName = raceData.name ~= "" and raceData.name or string.format("unnamed_%d", raceId)
        table.insert(raceIdNamePairs, {
            raceId = raceId,
            name = raceName
        })
    end

    table.sort(raceIdNamePairs, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    for _, pair in ipairs(raceIdNamePairs) do
        table.insert(Cyclopedia.Charms.Monsters, pair.raceId)
    end

    CharmList:destroyChildren()

    local formattedData = {}
    for _, charmData in pairs(uiData.charms) do
        local internalId = charmData.id
        if internalId and charms[internalId] then
            local charm = charms[internalId]
            local copy = {}
            for k, v in pairs(charmData) do copy[k] = v end
            copy.name = copy.name ~= "" and copy.name or charm.name
            copy.description = copy.description ~= "" and copy.description or charm.description
            copy.internalId = internalId
            copy.typePriority = charm.type
            copy.category = charm.category
            table.insert(formattedData, copy)
        end
    end

    if isModernUI then
        table.sort(formattedData, function(a, b)
            local tierA, tierB = a.tier or 0, b.tier or 0
            if tierA ~= tierB then
                return tierA > tierB
            end
            return a.name:lower() < b.name:lower()
        end)
    else
        table.sort(formattedData, function(a, b)
            if a.unlocked ~= b.unlocked then
                return a.unlocked and not b.unlocked
            end
            return a.name:lower() < b.name:lower()
        end)
    end

    for _, value in ipairs(formattedData) do
        if value and value.name and value.description and value.internalId and value.typePriority then
            local success, error = pcall(Cyclopedia.CreateCharmItem, value)
            if not success then
                g_logger.error(string.format("Error creating charm item: %s for charm ID: %s (%s)", error,
                    tostring(value.internalId), tostring(value.name)))
            end
        else
            g_logger.error(string.format("Incomplete charm data: ID: %s",
                value and tostring(value.internalId or "unknown") or "nil"))
        end
    end

    if isModernUI then
        local selectedWidget = TypeCharmRadioGroup:getSelectedWidget()
        if selectedWidget then
            local charmCategory = selectedWidget:getId() == "MajorCharms" and charmCategory_t.CHARM_MAJOR or
                charmCategory_t.CHARM_MINOR

            for _, widget in ipairs(CharmList:getChildren()) do
                widget:setVisible(widget.category == charmCategory)
            end

            CharmList:getLayout():update()
        end
    end

    local firstCharm = Cyclopedia.Charms.redirect and CharmList:getChildById(Cyclopedia.Charms.redirect) or
        CharmList:getChildByIndex(1)

    if firstCharm then
        Cyclopedia.selectCharm(firstCharm, firstCharm:isChecked())
        Cyclopedia.Charms.redirect = nil
    end

    if isModernUI then
        -- Client-side Default profile fallback (no-op when server supports opcode 245).
        CharmProfile.ensureLocalDefault(buildCharmsPayloadForSave())
        -- Overlay only for non-applied profile selection; applied profile must keep server raceIds.
        if CharmProfile.isLoaded() then
            local sel = getCharmProfileComboSelectedName()
            if sel and CharmProfile.getPreviewedName(sel) then
                Cyclopedia.Charms.previewProfile(sel)
            end
        end
    end

    finishLoadCharms()
end

local function getUIBase()
    if isModernUI then
        return {
            CreatureList = UI.InformationBase.PanelCreatureList.CreaturesBase.CreatureList,
            InfoBase = UI.InformationBase.panelSelectCreature.InfoBase,
            TextBase = UI.InformationBase.TextBase,
            ItemBase = UI.InformationBase.ItemBase,
            PriceBase = UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseGold,
            UnlockButton = UI.InformationBase.verticalPanelUnLockClearChram.UnlockButton,
            ClearCharmButton = UI.InformationBase.verticalPanelUnLockClearChram.check,
            SearchEdit = UI.InformationBase.PanelCreatureList.SearchEdit.SearchEdit,
            SearchLabel = UI.InformationBase.SearchLabel,
            CreaturesBase = UI.InformationBase.PanelCreatureList.CreaturesBase,
            CreaturesLabel = UI.InformationBase.panelSelectCreature.CreaturesLabel
        }
    else
        return {
            CreatureList = UI.InformationBase.CreaturesBase.CreatureList,
            InfoBase = UI.InformationBase.InfoBase,
            TextBase = UI.InformationBase.TextBase,
            ItemBase = UI.InformationBase.ItemBase,
            PriceBase = UI.InformationBase.PriceBase,
            UnlockButton = UI.InformationBase.UnlockButton,
            ClearCharmButton = nil,
            SearchEdit = UI.InformationBase.SearchEdit,
            SearchLabel = UI.InformationBase.SearchLabel,
            CreaturesBase = UI.InformationBase.CreaturesBase,
            CreaturesLabel = UI.InformationBase.CreaturesLabel
        }
    end
end

local function formatCreatureName(text)
    local capitalizedText = text:gsub("(%l)(%w*)", function(first, rest)
        return first:upper() .. rest
    end)
    return #capitalizedText > 19 and capitalizedText:sub(1, 16) .. "..." or capitalizedText
end

local function updateUIColors(widget, UI_BASE)
    local player = g_game.getLocalPlayer()
    local priceValue = UI_BASE.PriceBase.Value
    if isModernUI then
        local charmEntry = charms[widget.data.id]
        if charmEntry and charmEntry.points and charmEntry.points[widget.data.tier + 1] then
            local selectedWidget = TypeCharmRadioGroup:getSelectedWidget()
            if selectedWidget then
                local charmCategory = selectedWidget:getId() == "MajorCharms" and ResourceTypes.CHARM or
                    ResourceTypes.MINOR_CHARM
                local pointsValue = charmEntry.points[widget.data.tier + 1]
                local canAfford = pointsValue <= CharmProfile.getAvailableCharmPoints(charmCategory)
                UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Value:setColor(
                    canAfford and "#C0C0C0" or "#D33C3C")
                UI.InformationBase.verticalPanelUnLockClearChram.UnlockButton:setEnabled(canAfford)
            end
        else
            UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Value:setColor("#C0C0C0")
            UI.InformationBase.verticalPanelUnLockClearChram.UnlockButton:setEnabled(false)
        end
        if not widget.data.asignedStatus then
            priceValue:setText(0)
        end
    else
        if widget.icon == 1 then
            local canAfford = widget.data.removeRuneCost <= Cyclopedia.getPlayerTotalGold()
            priceValue:setColor(canAfford and "#C0C0C0" or "#D33C3C")
            UI_BASE.UnlockButton:setEnabled(canAfford)

            local priceText = (widget.data.unlocked and not widget.data.asignedStatus) and 0 or
                comma_value(widget.data.removeRuneCost)
            priceValue:setText(priceText)
        elseif widget.icon == 0 then
            local canAfford = widget.data.unlockPrice <= UI.CharmsPoints
            priceValue:setColor(canAfford and "#C0C0C0" or "#D33C3C")
            UI_BASE.UnlockButton:setEnabled(canAfford)
            priceValue:setText(widget.data.unlockPrice)
        end
    end
end

-- Helper function to get raceIds that are already assigned to charms
-- If category is provided, only returns assigned raceIds for charms of that category
-- This ensures Minor and Major charm lists are filtered independently
local function getAssignedRaceIds(category)
    local assignedRaceIds = {}
    if isCharmProfilePreviewMode() and UI and UI.mainPanelCharmsType then
        local CharmList = UI.mainPanelCharmsType.panelCharmList.CharmList
        for _, w in ipairs(CharmList:getChildren()) do
            if w.data and w.data.asignedStatus and w.data.raceId then
                if category == nil or w.data.category == category then
                    assignedRaceIds[w.data.raceId] = true
                end
            end
        end
        return assignedRaceIds
    end
    if Cyclopedia.formattedCharmsData then
        for _, charmData in ipairs(Cyclopedia.formattedCharmsData) do
            if charmData.asignedStatus and charmData.raceId then
                if category == nil or charmData.category == category then
                    assignedRaceIds[charmData.raceId] = true
                end
            end
        end
    end
    return assignedRaceIds
end

local function setupCreatureList(widget, UI_BASE)
    local isUnlocked = widget.data.unlocked or (widget.data.tier and widget.data.tier > 0)
    if (isUnlocked and not widget.data.asignedStatus) then
        UI_BASE.UnlockButton:setText("Select")

        -- Get the category of the currently selected charm to filter independently
        local charmCategory = widget.data.category
        local assignedRaceIds = getAssignedRaceIds(charmCategory)
        local color = "#484848"
        local index = 1
        for _, raceId in ipairs(Cyclopedia.Charms.Monsters) do
            -- Skip creatures that are already assigned to another charm of the same category
            if not assignedRaceIds[raceId] then
                local creatureWidget = g_ui.createWidget("CharmCreatureName", UI_BASE.CreatureList)
                creatureWidget:setId(index)
                creatureWidget:setText(formatCreatureName(g_things.getRaceData(raceId).name))
                creatureWidget.raceId = raceId
                creatureWidget:setBackgroundColor(color)
                creatureWidget.color = color
                color = color == "#484848" and "#414141" or "#484848"
                index = index + 1
            end
        end

        UI_BASE.UnlockButton:setEnabled(false)
        UI_BASE.SearchEdit:setEnabled(true)
        if UI_BASE.SearchLabel then
            UI_BASE.SearchLabel:setEnabled(true)
        end
        UI_BASE.CreaturesLabel:setEnabled(true)
        UI_BASE.SearchEdit:clearText()
        UI_BASE.SearchEdit:focus()
    end
end

local function setupModernVersionUpgrade(widget, UI_BASE)
    if not isModernUI then
        return
    end

    local charmId = widget.data.id
    local tier = widget.data.tier or 0
    local unlocked = widget.data.unlocked
    local charmEntry = charms[charmId]
    local player = g_game.getLocalPlayer()

    if charmEntry and charmEntry.points then
        local buttonText
        local pointsValue
        local canAfford = false

        -- Use tier as primary indicator: tier >= 1 means unlocked
        -- Server sends tier=1 after unlock even if unlocked=false
        local isUnlocked = unlocked or tier >= 1

        -- Determine charm category resource type
        local selectedWidget = TypeCharmRadioGroup:getSelectedWidget()
        local charmResourceType = selectedWidget and selectedWidget:getId() == "MajorCharms" and ResourceTypes.CHARM or
            ResourceTypes.MINOR_CHARM

        if not isUnlocked then
            -- Not unlocked yet - show "Unlock" with first tier cost
            buttonText = "Unlock"
            pointsValue = charmEntry.points[1]
            canAfford = pointsValue <= CharmProfile.getAvailableCharmPoints(charmResourceType)
        elseif tier >= 3 then
            -- Fully upgraded
            buttonText = "Fully Unlocked"
            pointsValue = 0
            canAfford = false
        else
            -- Unlocked but can upgrade - show upgrade to next tier
            -- tier 1 -> upgrade to tier 2 uses points[2], chance[2]
            -- tier 2 -> upgrade to tier 3 uses points[3], chance[3]
            local nextChance = charmEntry.chance and charmEntry.chance[tier + 1] or 0
            buttonText = string.format("Upgrade to %d%%", nextChance)
            pointsValue = charmEntry.points[tier + 1] or 0
            canAfford = pointsValue > 0 and pointsValue <= CharmProfile.getAvailableCharmPoints(charmResourceType)
        end

        UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Value:setText(comma_value(pointsValue))
        UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Value:setColor(canAfford and "#C0C0C0" or
            "#D33C3C")
        UI_BASE.UnlockButton:setText(buttonText)
        UI_BASE.UnlockButton:setEnabled(canAfford)
        UI_BASE.UnlockButton:getParent().data = widget.data
    else
        UI_BASE.UnlockButton:setText("Fully Unlocked")
        UI_BASE.UnlockButton:setEnabled(false)
        UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Value:setText(comma_value(0))
    end
end

function Cyclopedia.selectCharm(widget, isChecked)
    local UI_BASE = getUIBase()
    UI_BASE.CreatureList:destroyChildren()

    -- Reset Clear Charm button to disabled by default (will be enabled if charm is assigned and can afford)
    if UI_BASE.ClearCharmButton then
        UI_BASE.ClearCharmButton:setEnabled(false)
    end

    local parent = widget:getParent()
    UI.InformationBase.data = widget.data
    for i = 1, parent:getChildCount() do
        local internalWidget = parent:getChildByIndex(i)
        if internalWidget:isChecked() and widget:getId() ~= internalWidget:getId() then
            internalWidget:setChecked(false)
        end
    end

    if not isChecked then
        widget:setChecked(true)
    end

    Cyclopedia.Charms.currentSelectedId = widget.data.id

    UI_BASE.TextBase:setText(getCharmDescription(widget.data.id, widget.data.tier or 0))
    UI_BASE.ItemBase.image:setImageSource(widget.charmBase.image:getImageSource())
    UI_BASE.ItemBase.image:setImageClip(widget.charmBase.image:getImageClip())

    if isModernUI then
        UI.InformationBase:setText(widget:getText())
        if widget.data.tier > 0 then
            UI_BASE.ItemBase.border:setImageSource("/game_cyclopedia/images/charms/border/backdrop_charmgrade" ..
                widget.data.tier)
            UI_BASE.ItemBase.lockedMask:setVisible(false)
        else
            UI_BASE.ItemBase.lockedMask:setVisible(true)
            UI_BASE.ItemBase.border:setImageSource("")
        end
    end

    if widget.data.asignedStatus then
        local sprite = UI_BASE.InfoBase.sprite
        sprite:setVisible(true)
        sprite:setOutfit(g_things.getRaceData(widget.data.raceId).outfit)
        sprite:getCreature():setStaticWalking(1000)
        sprite:setOpacity(1)
    else
        UI_BASE.InfoBase.sprite:setVisible(false)
    end

    if not isModernUI then
        UI_BASE.PriceBase.Gold:setVisible(widget.icon == 1)
        UI_BASE.PriceBase.Charm:setVisible(widget.icon == 0)
    end

    updateUIColors(widget, UI_BASE)

    setupCreatureList(widget, UI_BASE)

    if widget.data.asignedStatus then
        -- Check if player can afford the removal cost
        local removeRuneCost = widget.data.removeRuneCost or 0
        local canAffordRemoval = removeRuneCost <= Cyclopedia.getPlayerTotalGold()

        -- For non-modern UI, use the UnlockButton as Remove button
        -- For modern UI, the Clear Charm button handles removal, so UnlockButton stays as Upgrade
        if not isModernUI then
            UI_BASE.UnlockButton:setText("Remove")
            UI_BASE.UnlockButton:getParent().data = widget.data
            UI_BASE.UnlockButton:setEnabled(canAffordRemoval)
        end

        -- Enable/disable the Clear Charm button based on gold (modern UI only)
        if UI_BASE.ClearCharmButton then
            UI_BASE.ClearCharmButton:setEnabled(canAffordRemoval)
        end

        -- Set the removal cost in the gold price display (not charm points)
        if isModernUI then
            UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseGold.Value:setText(comma_value(removeRuneCost))
            -- Color logic for Clear Charm:
            -- Value is 0 -> gray (#707070)
            -- Can't afford -> red (#D33C3C)
            -- Can afford -> normal (#C0C0C0)
            local clearCharmColor = "#C0C0C0"
            if removeRuneCost == 0 then
                clearCharmColor = "#707070"
            elseif not canAffordRemoval then
                clearCharmColor = "#D33C3C"
            end
            UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseGold.Value:setColor(clearCharmColor)
        end

        local creatureWidget = g_ui.createWidget("CharmCreatureName", UI_BASE.CreatureList)
        creatureWidget:setText(formatCreatureName(g_things.getRaceData(widget.data.raceId).name))
        creatureWidget:setEnabled(false)
        creatureWidget:setColor("#707070")

        UI_BASE.SearchEdit:setEnabled(false)
        if UI_BASE.SearchLabel then
            UI_BASE.SearchLabel:setEnabled(false)
        end
        UI_BASE.CreaturesLabel:setEnabled(false)
    end

    local isUnlocked = widget.data.unlocked or (widget.data.tier and widget.data.tier > 0)
    if not isUnlocked then
        UI_BASE.UnlockButton:setText("Unlock")
        UI_BASE.SearchEdit:setEnabled(false)
        if UI_BASE.SearchLabel then
            UI_BASE.SearchLabel:setEnabled(false)
        end
        if not isModernUI then
            UI_BASE.CreaturesLabel:setEnabled(false)
        end
    end

    setupModernVersionUpgrade(widget, UI_BASE)
end

function Cyclopedia.selectCreatureCharm(widget, isChecked)
    local UI_BASE = {}

    if isModernUI then
        UI_BASE.InfoBase = UI.InformationBase.panelSelectCreature.InfoBase
        UI_BASE.UnlockButton = UI.InformationBase.verticalPanelUnLockClearChram.UnlockButton
    else
        UI_BASE.InfoBase = UI.InformationBase.InfoBase
        UI_BASE.UnlockButton = UI.InformationBase.UnlockButton
    end
    local parent = widget:getParent()

    for i = 1, parent:getChildCount() do
        local internalWidget = parent:getChildByIndex(i)

        if internalWidget:isChecked() and widget:getId() ~= internalWidget:getId() then
            internalWidget:setChecked(false)
            internalWidget:setBackgroundColor(internalWidget.color)
        end
    end

    if not isChecked then
        widget:setChecked(true)
    end

    UI_BASE.InfoBase.sprite:setVisible(true)
    UI_BASE.InfoBase.sprite:setOutfit(g_things.getRaceData(widget.raceId).outfit)
    UI_BASE.InfoBase.sprite:getCreature():setStaticWalking(1000)
    UI_BASE.InfoBase.sprite:setOpacity(0.5)
    UI_BASE.UnlockButton:setEnabled(true)

    Cyclopedia.Charms.SelectedCreature = widget.raceId
end

function Cyclopedia.searchCharmMonster(text)
    local UI_BASE = {}

    if isModernUI then
        UI_BASE.CreaturesBase = UI.InformationBase.PanelCreatureList.CreaturesBase
    else
        UI_BASE.CreaturesBase = UI.InformationBase.CreaturesBase
    end

    UI_BASE.CreaturesBase.CreatureList:destroyChildren()

    local function format(string)
        local capitalizedText = string:gsub("(%l)(%w*)", function(first, rest)
            return first:upper() .. rest
        end)

        if #capitalizedText > 19 then
            return capitalizedText:sub(1, 16) .. "..."
        else
            return capitalizedText
        end
    end

    local function getColor(currentColor)
        return currentColor == "#484848" and "#414141" or "#484848"
    end

    -- Get the category of the currently selected charm to filter independently
    local charmCategory = UI.InformationBase.data and UI.InformationBase.data.category or nil
    local assignedRaceIds = getAssignedRaceIds(charmCategory)
    local searchedMonsters = {}

    if text ~= "" then
        for _, raceId in ipairs(Cyclopedia.Charms.Monsters) do
            -- Skip creatures that are already assigned to another charm of the same category
            if not assignedRaceIds[raceId] then
                local name = g_things.getRaceData(raceId).name
                if string.find(name:lower(), text:lower()) then
                    table.insert(searchedMonsters, raceId)
                end
            end
        end
    else
        -- Filter out creatures assigned to charms of the same category
        for _, raceId in ipairs(Cyclopedia.Charms.Monsters) do
            if not assignedRaceIds[raceId] then
                table.insert(searchedMonsters, raceId)
            end
        end
    end

    local color = "#484848"

    for _, raceId in ipairs(searchedMonsters) do
        local internalWidget = g_ui.createWidget("CharmCreatureName", UI_BASE.CreaturesBase.CreatureList)
        internalWidget:setId(raceId)
        internalWidget:setText(format(g_things.getRaceData(raceId).name))
        internalWidget.raceId = raceId
        internalWidget:setBackgroundColor(color)
        internalWidget.color = color
        color = getColor(color)
    end
end

function Cyclopedia.actionCharmButton(widget)
    local confirmWindow
    local type = widget:getText()
    local data = widget:getParent().data
    local previewProfile = isCharmProfilePreviewMode() and getCharmProfileComboSelectedName() or nil

    -- Hide the main Cyclopedia window while showing the confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    if type == "Unlock" then
        local function yesCallback()
            -- Unlocking a charm tier is a global server operation (spends charm points
            -- shared across all profiles). Never do this locally/per-profile.
            if isModernUI then
                g_game.BuyCharmRune(data.id, 0, 0)
            else
                g_game.BuyCharmRune(data.id)
            end
            scheduleRefreshCharmsFromServer()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end

            Cyclopedia.Charms.redirect = data.id
        end

        local function noCallback()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
        end

        -- Get the unlock cost from charms table (points[1] for first tier)
        local charmEntry = charms[data.id]
        local unlockCost = charmEntry and charmEntry.points and charmEntry.points[1] or data.unlockPrice

        if not confirmWindow then
            confirmWindow = displayGeneralBox(tr("Confirm Unlocking of Charm"), tr(
                    "Do you want to unlock the Charm %s? This will cost you %d Charm Points?", data.name,
                    unlockCost),
                {
                    {
                        text = tr("Yes"),
                        callback = yesCallback
                    },
                    {
                        text = tr("No"),
                        callback = noCallback
                    },
                    anchor = AnchorHorizontalCenter
                }, yesCallback, noCallback)
        end
    end
    if type == "Select" or type == "Select Creature" then
        local function yesCallback()
            if previewProfile then
                local t = data.tier or 1
                if t < 1 then
                    t = 1
                end
                CharmProfile.updateLocalCharm(previewProfile, data.id, t, Cyclopedia.Charms.SelectedCreature or 0)
            elseif isModernUI then
                g_game.BuyCharmRune(data.id, 1, Cyclopedia.Charms.SelectedCreature)
                scheduleRefreshCharmsFromServer()
            else
                g_game.BuyCharmRune(data.id, 1, Cyclopedia.Charms.SelectedCreature)
                scheduleRefreshCharmsFromServer()
            end
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
            Cyclopedia.Charms.redirect = data.id
        end

        local function noCallback()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
        end

        if not confirmWindow then
            confirmWindow = displayGeneralBox(tr("Confirm Selected Charm"),
                tr("Do you want to use the Charm %s for this creature?", data.name), {
                    {
                        text = tr("Yes"),
                        callback = yesCallback
                    },
                    {
                        text = tr("No"),
                        callback = noCallback
                    },
                    anchor = AnchorHorizontalCenter
                }, yesCallback, noCallback)
        end
    end

    if type == "Remove" then
        local removeCharmCost = data.removeRuneCost or 0

        local function yesCallback()
            if previewProfile then
                local function doRemove()
                    CharmProfile.updateLocalCharm(previewProfile, data.id, data.tier or 1, 0)
                end
                if removeCharmCost > 0 then
                    CharmProfile.setPendingChargeCallback(doRemove)
                    CharmProfile.chargeRemove()
                else
                    doRemove()
                end
            else
                g_game.BuyCharmRune(data.id, 2)
                scheduleRefreshCharmsFromServer()
                local newBalance = Cyclopedia.getPlayerTotalGold() - removeCharmCost
                Cyclopedia.onResourcesBalanceChange(newBalance, nil, ResourceTypes.BANK_BALANCE)
            end
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
            Cyclopedia.Charms.redirect = data.id
        end

        local function noCallback()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
        end

        if not confirmWindow then
            confirmWindow = displayGeneralBox(tr("Confirm Charm Removal"),
                tr("Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.",
                    data.name, comma_value(removeCharmCost)), {
                    {
                        text = tr("Yes"),
                        callback = yesCallback
                    },
                    {
                        text = tr("No"),
                        callback = noCallback
                    },
                    anchor = AnchorHorizontalCenter
                }, yesCallback, noCallback)
        end
    end
    if isModernUI and type:match("^Upgrade") then
        local function yesCallback()
            -- Upgrading a charm tier is a global server operation (spends charm points
            -- shared across all profiles). Never do this locally/per-profile.
            g_game.BuyCharmRune(data.id, 0, 0)
            scheduleRefreshCharmsFromServer()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
            Cyclopedia.Charms.redirect = data.id
        end

        local function noCallback()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
        end

        -- Get the upgrade cost from charms table (points[tier+1] for next tier)
        -- tier 1 -> upgrade to tier 2 uses points[2]
        -- tier 2 -> upgrade to tier 3 uses points[3]
        local charmEntry = charms[data.id]
        local tier = data.tier or 0
        local upgradeCost = charmEntry and charmEntry.points and charmEntry.points[tier + 1] or data.unlockPrice

        if not confirmWindow then
            confirmWindow = displayGeneralBox(tr("Confirm Upgrading of Charm"), tr(
                    "Do you want to upgrade the Charm %s? This will cost you %d Charm Points?", data.name,
                    upgradeCost),
                {
                    {
                        text = tr("No"),
                        callback = noCallback
                    },
                    {
                        text = tr("Yes"),
                        callback = yesCallback
                    },
                    anchor = AnchorHorizontalCenter
                }, yesCallback, noCallback)
        end
    end
end

function onTypeCharmRadioGroup(radioGroup, selectedWidget)
    local charmCategory = selectedWidget:getId() == "MajorCharms" and charmCategory_t.CHARM_MAJOR or
        charmCategory_t.CHARM_MINOR
    local CharmList = UI.mainPanelCharmsType.panelCharmList.CharmList
    if charmCategory == charmCategory_t.CHARM_MAJOR then
        UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Charm:setImageSource(
            "/game_cyclopedia/images/monster-icon-bonuspoints")
    else
        UI.InformationBase.verticalPanelUnLockClearChram.PriceBaseCharm.Charm:setImageSource(
            "/game_cyclopedia/images/minor-charm-echoes")
    end
    for _, widget in ipairs(CharmList:getChildren()) do
        if widget.category == charmCategory then
            widget:setVisible(true)
        else
            widget:setVisible(false)
        end
    end

    CharmList:getLayout():update()

    local firstVisible = nil
    for _, w in ipairs(CharmList:getChildren()) do
        if w:isVisible() then
            firstVisible = w
            break
        end
    end
    if firstVisible then
        Cyclopedia.selectCharm(firstVisible, firstVisible:isChecked())
    end
end

function Cyclopedia.actionSelectCharmButton(widget)
    local confirmWindow
    local type = widget:getText()
    local data = UI.InformationBase.data
    local previewProfile = isCharmProfilePreviewMode() and getCharmProfileComboSelectedName() or nil

    -- Hide the main Cyclopedia window while showing the confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    if type == "Select" or type == "Select Creature" then
        local function yesCallback()
            if previewProfile then
                local t = data.tier or 1
                if t < 1 then
                    t = 1
                end
                CharmProfile.updateLocalCharm(previewProfile, data.id, t, Cyclopedia.Charms.SelectedCreature or 0)
            elseif isModernUI then
                g_game.BuyCharmRune(data.id, 1, Cyclopedia.Charms.SelectedCreature)
                scheduleRefreshCharmsFromServer()
            else
                g_game.BuyCharmRune(data.id, 1, Cyclopedia.Charms.SelectedCreature)
                scheduleRefreshCharmsFromServer()
            end
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
            Cyclopedia.Charms.redirect = data.id
        end

        local function noCallback()
            if confirmWindow then
                confirmWindow:destroy()
                confirmWindow = nil
            end
            -- Show the main Cyclopedia window again
            if controllerCyclopedia and controllerCyclopedia.ui then
                controllerCyclopedia.ui:show()
            end
        end

        if not confirmWindow then
            confirmWindow = displayGeneralBox(tr("Confirm Selected Charm"),
                tr("Do you want to use the Charm %s for this creature?", data.name), {
                    {
                        text = tr("Yes"),
                        callback = yesCallback
                    },
                    {
                        text = tr("No"),
                        callback = noCallback
                    },
                    anchor = AnchorHorizontalCenter
                }, yesCallback, noCallback)
        end
    end
end

function Cyclopedia.actionClearCharmButton(widget)
    local confirmWindow
    local data = UI.InformationBase.data
    local previewProfile = isCharmProfilePreviewMode() and getCharmProfileComboSelectedName() or nil

    if not data or not data.asignedStatus then
        return
    end

    local clearCharmCost = data.removeRuneCost or 0

    -- Hide the main Cyclopedia window while showing the confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    local function yesCallback()
        if previewProfile then
            local function doClear()
                CharmProfile.updateLocalCharm(previewProfile, data.id, data.tier or 1, 0)
            end
            if clearCharmCost > 0 then
                CharmProfile.setPendingChargeCallback(doClear)
                CharmProfile.chargeRemove()
            else
                doClear()
            end
        else
            g_game.BuyCharmRune(data.id, 2)
            scheduleRefreshCharmsFromServer()
            local newBalance = Cyclopedia.getPlayerTotalGold() - clearCharmCost
            Cyclopedia.onResourcesBalanceChange(newBalance, nil, ResourceTypes.BANK_BALANCE)
        end
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
        Cyclopedia.Charms.redirect = data.id
    end

    local function noCallback()
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        -- Show the main Cyclopedia window again
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    if not confirmWindow then
        confirmWindow = displayGeneralBox(tr("Confirm Charm Removal"),
            tr("Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.",
                data.name, comma_value(clearCharmCost)), {
                {
                    text = tr("Yes"),
                    callback = yesCallback
                },
                {
                    text = tr("No"),
                    callback = noCallback
                },
                anchor = AnchorHorizontalCenter
            }, yesCallback, noCallback)
    end
end

function Cyclopedia.actionResetAllCharms()
    local confirmWindow = nil
    local resetAllCharmsCost = Cyclopedia.charmsData and Cyclopedia.charmsData.resetAllCharmsCost or 0
    local previewProfile = isCharmProfilePreviewMode() and getCharmProfileComboSelectedName() or nil

    -- Hide the main Cyclopedia window while showing the confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    local function yesCallback()
        if previewProfile then
            local function doReset()
                CharmProfile.resetLocalProfile(previewProfile)
            end
            if resetAllCharmsCost > 0 then
                CharmProfile.setPendingChargeCallback(doReset)
                CharmProfile.chargeReset()
            else
                doReset()
            end
        else
            g_game.BuyCharmRune(0, 3, 0)
            scheduleRefreshCharmsFromServer()
            local newBalance = Cyclopedia.getPlayerTotalGold() - resetAllCharmsCost
            Cyclopedia.onResourcesBalanceChange(newBalance, nil, ResourceTypes.BANK_BALANCE)
        end
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    local function noCallback()
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        -- Show the main Cyclopedia window again
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    if not confirmWindow then
        confirmWindow = displayGeneralBox(tr("Confirm Reset All Charms"),
            tr("Do you want to reset all charms? This will cost you %s gold pieces and remove all charm assignments.",
                comma_value(resetAllCharmsCost)), {
                {
                    text = tr("Yes"),
                    callback = yesCallback
                },
                {
                    text = tr("No"),
                    callback = noCallback
                },
                anchor = AnchorHorizontalCenter
            }, yesCallback, noCallback)
    end
end

local function showProfileNameDialog(title, defaultText, onConfirm)
    local root = g_ui.getRootWidget()
    local dialogWindow = g_ui.loadUI("charm_profile_dialog", root)
    if not dialogWindow then
        dialogWindow = g_ui.loadUI("/game_cyclopedia/tab/charms/charm_profile_dialog", root)
    end
    if not dialogWindow then
        return
    end

    dialogWindow:setText(title)

    local input = dialogWindow:recursiveGetChildById('profileNameInput')
    if input and defaultText and defaultText ~= "" then
        input:setText(defaultText)
    end

    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    dialogWindow:show(true)
    dialogWindow:raise()
    dialogWindow:focus()
    if input then input:focus() end

    local function validateInput()
        local warning = dialogWindow:recursiveGetChildById('warning')
        if not input or not warning then return end
        local text = input:getText():match("^%s*(.-)%s*$") or ""
        if #text == 0 then
            warning:setVisible(true)
            warning:setTooltip("The name cannot be empty.")
        elseif #text > 20 then
            warning:setVisible(true)
            warning:setTooltip("The name cannot be longer than 20 characters.")
        else
            local names = CharmProfile.getProfileNames()
            local isDuplicate = false
            for _, n in ipairs(names) do
                if n:lower() == text:lower() and (not defaultText or n:lower() ~= defaultText:lower()) then
                    isDuplicate = true
                    break
                end
            end
            if isDuplicate then
                warning:setVisible(true)
                warning:setTooltip("A profile with this name already exists.")
            else
                warning:setVisible(false)
                warning:setTooltip("")
            end
        end
    end

    local function confirm()
        if not input then return end
        local text = input:getText():match("^%s*(.-)%s*$") or ""
        if #text == 0 or #text > 20 then return end
        local names = CharmProfile.getProfileNames()
        for _, n in ipairs(names) do
            if n:lower() == text:lower() and (not defaultText or n:lower() ~= defaultText:lower()) then
                return
            end
        end
        onConfirm(text)
        dialogWindow:destroy()
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    local function cancel()
        dialogWindow:destroy()
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    local okBtn = dialogWindow:recursiveGetChildById('okButton')
    local cancelBtn = dialogWindow:recursiveGetChildById('cancelButton')
    if okBtn then
        connect(okBtn, { onClick = confirm })
    end
    if cancelBtn then
        connect(cancelBtn, { onClick = cancel })
    end
    dialogWindow.onEnter = confirm
    dialogWindow.onEscape = cancel
    if input then input.onTextChange = function() validateInput() end end
end

function Cyclopedia.Charms.setupProfileButtons()
    if not UI or not isModernUI then return end

    local profilePanel = UI:recursiveGetChildById('charmProfilesPanel')
    if not profilePanel then return end

    local combo = profilePanel:recursiveGetChildById('charmProfilesCombo')
    local applyBtn = profilePanel:recursiveGetChildById('charmProfileApplyBtn')
    local newBtn = profilePanel:recursiveGetChildById('charmProfileNewBtn')
    local deleteBtn = profilePanel:recursiveGetChildById('charmProfileDeleteBtn')
    local renameBtn = profilePanel:recursiveGetChildById('charmProfileRenameBtn')

    if combo then
        combo.onOptionChange = function(self, text, data)
            if CharmProfile.getIgnoreComboChange() then return end
            if not data or data == "" then return end
            if CharmProfile.getPreviewedName(data) then
                Cyclopedia.Charms.previewProfile(data)
            elseif Cyclopedia.charmsData and loadCharmsRecursionDepth == 0 then
                Cyclopedia.loadCharms(Cyclopedia.charmsData)
            else
                Cyclopedia.Charms.previewProfile(data)
            end
            CharmProfile.requestCost(data, true)
            updateNotAppliedLabel()
        end
    end

    if applyBtn then
        connect(applyBtn, {
            onClick = function()
                if not combo then return end
                local currentOpt = combo:getCurrentOption()
                local profileName = currentOpt and currentOpt.data or nil
                if not profileName or profileName == "" then return end
                CharmProfile.requestCost(profileName, false)
            end
        })
    end

    if newBtn then
        connect(newBtn, {
            onClick = function()
                showProfileNameDialog(tr("New Charm Profile"), "", function(name)
                    CharmProfile.setPendingSelectProfile(name)
                    CharmProfile.save(name, {})
                end)
            end
        })
    end

    if deleteBtn then
        connect(deleteBtn, {
            onClick = function()
                if not combo then return end
                local currentOpt = combo:getCurrentOption()
                local profileName = currentOpt and currentOpt.data or nil
                if not profileName or profileName == "" then
                    modules.game_textmessage.displayGameMessage("Select a profile to delete.")
                    return
                end
                local names = CharmProfile.getProfileNames()
                if #names <= 1 then
                    modules.game_textmessage.displayGameMessage("You must have at least one charm profile.")
                    return
                end
                local confirmWindow = nil
                local function yesCallback()
                    CharmProfile.delete(profileName)
                    if confirmWindow then confirmWindow:destroy(); confirmWindow = nil end
                end
                local function noCallback()
                    if confirmWindow then confirmWindow:destroy(); confirmWindow = nil end
                end
                confirmWindow = displayGeneralBox(tr("Delete Charm Profile"),
                    tr("Are you sure you want to delete profile '%s'?", profileName), {
                        { text = tr("Yes"), callback = yesCallback },
                        { text = tr("No"),  callback = noCallback },
                        anchor = AnchorHorizontalCenter
                    }, yesCallback, noCallback, controllerCyclopedia.ui)
            end
        })
    end

    if renameBtn then
        connect(renameBtn, {
            onClick = function()
                if not combo then return end
                local currentOpt = combo:getCurrentOption()
                local oldName = currentOpt and currentOpt.data or nil
                if not oldName or oldName == "" then
                    modules.game_textmessage.displayGameMessage("Select a profile to rename.")
                    return
                end
                showProfileNameDialog(tr("Rename Charm Profile"), oldName, function(newName)
                    if newName:lower() ~= oldName:lower() then
                        CharmProfile.rename(oldName, newName)
                    end
                end)
            end
        })
    end
end

