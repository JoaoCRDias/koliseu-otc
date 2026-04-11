local UI = nil

Cyclopedia.Bestiary = Cyclopedia.Bestiary or {}

-- Cleanup function to be called before tab switch
function Cyclopedia.Bestiary.cleanup()
    -- Reset charm focus state before leaving
    if UI and UI.ListBase and UI.ListBase.CreatureInfo then
        local charmBase = UI.ListBase.CreatureInfo.CharmBase
        local charmBase2 = UI.ListBase.CreatureInfo.CharmBase2
        if charmBase and charmBase.charmFocusBorder then
            charmBase.charmFocusBorder:setBorderWidth(0)
        end
        if charmBase2 and charmBase2.charmFocusBorder then
            charmBase2.charmFocusBorder:setBorderWidth(0)
        end
    end

    -- Disconnect keyboard binding
    if UI and UI.SearchEdit then
        pcall(function()
            g_keyboard.unbindKeyDown('Enter', UI.SearchEdit)
        end)
    end

    -- Clear UI reference
    UI = nil
end

local STAGES = {
    CREATURES = 2,
    SEARCH = 4,
    CATEGORY = 1,
    CREATURE = 3
}

local storedRaceIDs = {}
-- Move tracker data to global Cyclopedia namespace to persist across module reloads
Cyclopedia.storedTrackerData = Cyclopedia.storedTrackerData or nil
Cyclopedia.storedBosstiaryTrackerData = Cyclopedia.storedBosstiaryTrackerData or nil
-- Store charms data globally
Cyclopedia.charmsData = Cyclopedia.charmsData or nil
-- Store current selected creature data
Cyclopedia.currentCreatureData = Cyclopedia.currentCreatureData or nil
local animusMasteryPoints = 0

-- Charm categories
local CHARM_CATEGORY = {
    MAJOR = 1,
    MINOR = 2
}

function Cyclopedia.loadBestiaryOverview(name, creatures, animusMasteryPoints)
    if name == "" and #creatures > 0 then
        if #creatures == 1 then
            g_game.requestBestiarySearch(creatures[1].id)
            Cyclopedia.ShowBestiaryCreature()
        else
            Cyclopedia.loadBestiarySearchCreatures(creatures)
        end
    else
        Cyclopedia.loadBestiaryCreatures(creatures)
    end

    if animusMasteryPoints and animusMasteryPoints > 0 then
        animusMasteryPoints = animusMasteryPoints
    end
end

function showBestiary()
    UI = g_ui.loadUI("bestiary", contentContainer)
    UI:show()

    -- Clear any discovery highlight when bestiary is opened
    Cyclopedia.clearBestiaryDiscoveryHighlight()

    -- Check if we should go directly to a creature (from tracker click or discovery notification)
    -- Priority: pendingCreatureRaceId (tracker click) > pendingDiscoveryRaceId (new discovery)
    local pendingRaceId = Cyclopedia.pendingCreatureRaceId or Cyclopedia.pendingDiscoveryRaceId
    Cyclopedia.pendingCreatureRaceId = nil -- Clear it immediately
    Cyclopedia.pendingDiscoveryRaceId = nil -- Clear discovery raceId as well

    if pendingRaceId then
        -- Go directly to creature view
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(true)
        Cyclopedia.Bestiary.Stage = STAGES.CREATURE

        -- Set up back button to go to category view
        UI.BackPageButton:setEnabled(true)
        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
            Cyclopedia.onStageChange()
            g_game.requestBestiary()
        end
    else
        -- Normal bestiary open - show category list
        UI.ListBase.CategoryList:setVisible(true)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(false)
        Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
    end

    controllerCyclopedia.ui.CharmsBase:setVisible(true)
    controllerCyclopedia.ui.GoldBase:setVisible(true)
    controllerCyclopedia.ui.BestiaryTrackerButton:setVisible(true)

    -- Update Charm values
    local player = g_game.getLocalPlayer()
    if player then
        if g_game.getClientVersion() >= 1410 then
            controllerCyclopedia.ui.CharmsBase1410:setVisible(true)
            -- Update Minor Charm Echoes value
            local minorCharm = player:getResourceBalance(ResourceTypes.MINOR_CHARM) or 0
            local maxMinorCharm = player:getResourceBalance(ResourceTypes.MAX_MINOR_CHARM) or 0
            controllerCyclopedia.ui.CharmsBase1410.Value:setText(string.format("%d/%d", minorCharm, maxMinorCharm))
            -- Update Charm value
            local charm = player:getResourceBalance(ResourceTypes.CHARM) or 0
            local maxCharm = player:getResourceBalance(ResourceTypes.MAX_CHARM) or 0
            controllerCyclopedia.ui.CharmsBase.Value:setText(string.format("%d/%d", charm, maxCharm))
        end
    end

    -- Initialize tracker data and storedRaceIDs when bestiary is opened
    -- This ensures Track Kills status is properly loaded from cache
    Cyclopedia.initializeTrackerData()
    Cyclopedia.ensureStoredRaceIDsPopulated()

    -- Bind Enter key to search when SearchEdit is focused
    g_keyboard.bindKeyDown('Enter', function()
        if UI and UI:isVisible() and UI.SearchEdit:getText() ~= "" then
            Cyclopedia.BestiarySearch()
        end
    end, UI.SearchEdit)

    -- Request creature data if we have a pending creature, otherwise request bestiary categories
    if pendingRaceId then
        g_game.requestBestiarySearch(pendingRaceId)
    else
        g_game.requestBestiary()
    end

    -- Request again after a short delay to ensure charms data is loaded
    -- The server sends charms data as a separate packet
    scheduleEvent(function()
        if not Cyclopedia.formattedCharmsData or #Cyclopedia.formattedCharmsData == 0 then
            g_game.requestBestiary()
        end
    end, 500)
end

Cyclopedia.Bestiary = {}
Cyclopedia.Bestiary.Stage = STAGES.CATEGORY

function Cyclopedia.SetBestiaryProgress(fit, firstBar, secondBar, thirdBar, killCount, firstGoal, secondGoal, thirdGoal)
    local function calculatePercent(value, max)
        if max <= 0 then return 0 end
        return math.min(math.floor((value / max) * 100), 100)
    end

    local function calculateWidth(value, max)
        return math.min(math.floor((value / max) * fit), fit)
    end

    local function setBarProgress(bar, percent, isBestiaryCompleted, maxWidth)
        -- Calculate width based on percentage
        local width = math.floor((percent / 100) * maxWidth)

        if percent > 0 then
            bar:setWidth(width)
            if isBestiaryCompleted then
                -- Use green progress image when entire bestiary is completed
                bar:setImageSource("/images/game/cyclopedia/bestiary/progress-green")
            else
                -- Use golden progress image for normal progress
                bar:setImageSource("/images/game/cyclopedia/bestiary/progress")
            end
        else
            -- No progress, hide bar
            bar:setWidth(0)
        end
    end

    -- Check if bestiary is completed (reached final goal)
    local isCompleted = killCount >= thirdGoal

    -- First bar progress
    local firstPercent = calculatePercent(math.min(killCount, firstGoal), firstGoal)
    setBarProgress(firstBar, firstPercent, isCompleted, fit)

    -- Second bar progress
    local secondPercent = 0
    if killCount > firstGoal then
        secondPercent = calculatePercent(math.min(killCount - firstGoal, secondGoal - firstGoal), secondGoal - firstGoal)
    end
    setBarProgress(secondBar, secondPercent, isCompleted, fit)

    -- Third bar progress
    local thirdPercent = 0
    if killCount > secondGoal then
        thirdPercent = calculatePercent(math.min(killCount - secondGoal, thirdGoal - secondGoal), thirdGoal - secondGoal)
    end
    setBarProgress(thirdBar, thirdPercent, isCompleted, fit)
end

function Cyclopedia.SetBestiaryStars(value)
    UI.ListBase.CreatureInfo.StarFill:setWidth(value * 9)
end

function Cyclopedia.SetBestiaryDiamonds(value)
    UI.ListBase.CreatureInfo.DiamondFill:setWidth(value * 9)
end

local function getRarityTitle(index, isFirstRow)
    local titles = {
        [0] = "Common",
        [1] = "Uncommon",
        [2] = "Semi-Rare",
        [3] = "Rare",
        [4] = "Very Rare"
    }
    local title = tr(titles[index] or "Very Rare")
    if isFirstRow then
        return title .. ":"
    else
        return ""
    end
end

function Cyclopedia.CreateCreatureItems(data)
    UI.ListBase.CreatureInfo.ItemsBase.Itemlist:destroyChildren()

    local maxItemsPerRow = 15
    local widgetIndex = 0

    for index, items in pairs(data) do
        local totalItems = #items
        local rowCount = math.ceil(totalItems / maxItemsPerRow)

        for row = 1, rowCount do
            local widget = g_ui.createWidget("BestiaryItemGroup", UI.ListBase.CreatureInfo.ItemsBase.Itemlist)
            local widgetId = string.format("%d_%d", index, row)
            widget:setId(widgetId)

            local isFirstRow = (row == 1)
            widget.Title:setText(getRarityTitle(index, isFirstRow))

            if not isFirstRow then
                widget:setMarginTop(-10)
            end

            for i = 1, maxItemsPerRow do
                local item = g_ui.createWidget("BestiaryItem", widget.Items)
                item:setId(i)
            end

            local startIndex = (row - 1) * maxItemsPerRow + 1
            local endIndex = math.min(row * maxItemsPerRow, totalItems)

            for i = startIndex, endIndex do
                local itemData = items[i]
                local slotIndex = i - startIndex + 1
                local itemWidget = widget.Items[slotIndex]

                if not itemWidget then
                    break
                end

                local thing = g_things.getThingType(itemData.id, ThingCategoryItem)
                itemWidget:setItemId(itemData.id)
                itemWidget.id = itemData.id
                itemWidget.classification = thing:getClassification()

                if itemData.id == 0 then
                    itemWidget.undefinedItem:setVisible(true)
                end

                if itemData.id > 0 then
                    if itemData.stackable then
                        itemWidget.Stackable:setText("1+")
                    else
                        itemWidget.Stackable:setText("1")
                    end
                end

                ItemsDatabase.setRarityItem(itemWidget, itemWidget:getItem())

                itemWidget.onMouseRelease = onAddLootClick
            end

            widgetIndex = widgetIndex + 1
        end
    end
end

-- Function to reset creature info visuals before showing (prevents flicker)
function Cyclopedia.resetCreatureInfoVisuals()
    if not UI or not UI.ListBase or not UI.ListBase.CreatureInfo then
        return
    end

    local creatureInfo = UI.ListBase.CreatureInfo
    creatureInfo:setText("")
    -- Hide sprite instead of setting empty outfit (which causes error with invalid thing type)
    creatureInfo.LeftBase.Sprite:setVisible(false)
    creatureInfo.ProgressValue:setText("")
    creatureInfo.Value1:setText("")
    creatureInfo.Value2:setText("")
    creatureInfo.Value3:setText("")
    creatureInfo.Value4:setText("")
    creatureInfo.Value5:setText("")
    creatureInfo.BonusValue:setText("")
    creatureInfo.LocationField.Textlist.Text:setText("")

    -- Reset progress bars
    creatureInfo.ProgressBack:setWidth(0)
    creatureInfo.ProgressBack33:setWidth(0)
    creatureInfo.ProgressBack55:setWidth(0)

    -- Reset charm bases
    if creatureInfo.CharmBase then
        creatureInfo.CharmBase:setOpacity(0.5)
        creatureInfo.CharmBase.charmImage:setVisible(false)
        creatureInfo.CharmBase.charmBorder:setVisible(false)
        creatureInfo.CharmBase.charmFocusBorder:setBorderWidth(0)
    end
    if creatureInfo.CharmBase2 then
        creatureInfo.CharmBase2:setOpacity(0.5)
        creatureInfo.CharmBase2.charmImage:setVisible(false)
        creatureInfo.CharmBase2.charmBorder:setVisible(false)
        creatureInfo.CharmBase2.charmFocusBorder:setBorderWidth(0)
    end

    -- Reset loot items
    if creatureInfo.ItemsBase and creatureInfo.ItemsBase.ItemList then
        creatureInfo.ItemsBase.ItemList:destroyChildren()
    end
end

function Cyclopedia.loadBestiarySelectedCreature(data)
    -- Skip if UI is not initialized (happens during Task Hunting)
    if not UI or not UI.ListBase or not UI.ListBase.CreatureInfo then
        return
    end

    local occurence = {
        [0] = 1,
        2,
        3,
        4
    }

    -- Safe call to getRaceData
    local success, raceData = pcall(function()
        return g_things.getRaceData(data.id)
    end)

    if not success or not raceData then
        return
    end

    local raceData = g_things.getRaceData(data.id)
    local formattedName = raceData.name:gsub("(%l)(%w*)", function(first, rest)
        return first:upper() .. rest
    end)

    UI.ListBase.CreatureInfo:setText(formattedName)
    Cyclopedia.SetBestiaryDiamonds(occurence[data.ocorrence])
    Cyclopedia.SetBestiaryStars(data.difficulty)
    UI.ListBase.CreatureInfo.LeftBase.Sprite:setOutfit(raceData.outfit)
    UI.ListBase.CreatureInfo.LeftBase.Sprite:setVisible(true)
    UI.ListBase.CreatureInfo.LeftBase.Sprite:getCreature():setStaticWalking(1000)

    -- Goals should be in ascending order: firstGoal < secondGoal < thirdGoal
    local goals = { data.thirdDifficulty, data.secondUnlock, data.lastProgressKillCount }
    table.sort(goals)

    Cyclopedia.SetBestiaryProgress(61, UI.ListBase.CreatureInfo.ProgressBack, UI.ListBase.CreatureInfo.ProgressBack33,
        UI.ListBase.CreatureInfo.ProgressBack55, data.killCounter, goals[1], goals[2], goals[3])

    UI.ListBase.CreatureInfo.ProgressValue:setText(data.killCounter)

    local fullText = ""
    if data.killCounter >= data.lastProgressKillCount then
        fullText = "(fully unlocked)"
    end

    UI.ListBase.CreatureInfo.ProgressBorder1:setTooltip(string.format(" %d / %d %s", data.killCounter,
        data.thirdDifficulty, fullText))
    UI.ListBase.CreatureInfo.ProgressBorder2:setTooltip(string.format(" %d / %d %s", data.killCounter,
        data.secondUnlock, fullText))
    UI.ListBase.CreatureInfo.ProgressBorder3:setTooltip(string.format(" %d / %d %s", data.killCounter,
        data.lastProgressKillCount, fullText))
    UI.ListBase.CreatureInfo.LeftBase.TrackCheck.raceId = data.id

    -- TODO investigate when it can be track-- idk when
    --[[     if data.currentLevel == 1 then
        UI.ListBase.CreatureInfo.LeftBase.TrackCheck:enable()
    else
        UI.ListBase.CreatureInfo.LeftBase.TrackCheck:disable()
    end ]]

    -- Ensure storedRaceIDs is populated from cached tracker data before checking
    Cyclopedia.ensureStoredRaceIDsPopulated()

    if table.find(storedRaceIDs, data.id) then
        UI.ListBase.CreatureInfo.LeftBase.TrackCheck:setChecked(true)
    else
        UI.ListBase.CreatureInfo.LeftBase.TrackCheck:setChecked(false)
    end

    if data.currentLevel > 1 then
        UI.ListBase.CreatureInfo.Value1:setText(data.maxHealth)
        UI.ListBase.CreatureInfo.Value2:setText(data.experience)
        UI.ListBase.CreatureInfo.Value3:setText(data.speed)
        UI.ListBase.CreatureInfo.Value4:setText(data.armor)
        local parsedMitigation = math.floor(data.mitigation * 100) / 100
        UI.ListBase.CreatureInfo.Value5:setText(parsedMitigation .. "%")
        UI.ListBase.CreatureInfo.BonusValue:setText(data.charmValue)
    else
        UI.ListBase.CreatureInfo.Value1:setText("?")
        UI.ListBase.CreatureInfo.Value2:setText("?")
        UI.ListBase.CreatureInfo.Value3:setText("?")
        UI.ListBase.CreatureInfo.Value4:setText("?")
        UI.ListBase.CreatureInfo.Value5:setText("?")
        UI.ListBase.CreatureInfo.BonusValue:setText("?")
    end

    if data.attackMode == 1 then
        local rect = {
            height = 9,
            x = 18,
            y = 0,
            width = 18
        }

        UI.ListBase.CreatureInfo.SubTextLabel:setImageSource("/images/icons/icons-skills")
        UI.ListBase.CreatureInfo.SubTextLabel:setImageClip(rect)
        UI.ListBase.CreatureInfo.SubTextLabel:setSize("18 9")
    else
        local rect = {
            height = 9,
            x = 0,
            y = 0,
            width = 18
        }
        UI.ListBase.CreatureInfo.SubTextLabel:setImageSource("/images/icons/icons-skills")
        UI.ListBase.CreatureInfo.SubTextLabel:setImageClip(rect)
        UI.ListBase.CreatureInfo.SubTextLabel:setSize("18 9")
    end

    local resists = { "PhysicalProgress", "FireProgress", "EarthProgress", "EnergyProgress", "IceProgress",
        "HolyProgress", "DeathProgress", "HealingProgress" }

    if not table.empty(data.combat) then
        for i = 1, 8 do
            local combat = Cyclopedia.calculateCombatValues(data.combat[i])
            UI.ListBase.CreatureInfo[resists[i]].Fill:setMarginRight(combat.margin)
            UI.ListBase.CreatureInfo[resists[i]].Fill:setBackgroundColor(combat.color)
            UI.ListBase.CreatureInfo[resists[i]]:setTooltip(string.format("Sensitive to %s : %s", string.gsub(
                resists[i], "Progress", ""):lower(), combat.tooltip))
        end
    else
        for i = 1, 8 do
            UI.ListBase.CreatureInfo[resists[i]].Fill:setMarginRight(65)
        end
    end

    local lootData = {}
    for _, value in ipairs(data.loot) do
        local loot = {
            name = value.name,
            id = value.itemId,
            type = value.type,
            difficulty = value.diffculty,
            stackable = value.stackable == 1 and true or false
        }

        if not lootData[value.diffculty] then
            lootData[value.diffculty] = {}
        end

        table.insert(lootData[value.diffculty], loot)
    end

    Cyclopedia.CreateCreatureItems(lootData)
    UI.ListBase.CreatureInfo.LocationField.Textlist.Text:setText(data.location)

    if data.AnimusMasteryPoints and data.AnimusMasteryPoints > 1 then
        UI.ListBase.CreatureInfo.AnimusMastery:setTooltip(
            "The Animus Mastery for this creature is unlocked.\nIt yields " ..
            (data.AnimusMasteryBonus / 10) ..
            "% bonus experience points, plus an additional 0.1% for every 10 Animus Masteries unlocked, up to a maximum of 4%.\nYou currently benefit from " ..
            (data.AnimusMasteryBonus / 10) ..
            "% bonus experience points due to having unlocked " .. data.AnimusMasteryPoints .. " Animus Masteries.")
        UI.ListBase.CreatureInfo.AnimusMastery:setVisible(true)
    else
        UI.ListBase.CreatureInfo.AnimusMastery:removeTooltip()
        UI.ListBase.CreatureInfo.AnimusMastery:setVisible(false)
    end

    -- Store current creature data for charm selection
    Cyclopedia.currentCreatureData = data

    -- Setup CharmBase click handlers and enable/disable based on currentLevel
    Cyclopedia.setupBestiaryCharmBases(data)
end

-- Helper function to set charm image based on charm ID
function Cyclopedia.setCharmImage(charmImageWidget, charmId)
    if charmId and charmId >= 0 then
        charmImageWidget:setImageSource("/game_cyclopedia/images/charms/monster-bonus-effects")
        charmImageWidget:setImageClip(string.format("%d 0 32 32", charmId * 32))
        charmImageWidget:setVisible(true)
    else
        charmImageWidget:setImageSource("")
        charmImageWidget:setVisible(false)
    end
end

-- Helper function to set charm tier border
function Cyclopedia.setCharmTierBorder(charmBase, tier)
    local charmBorderWidget = charmBase.charmBorder
    if tier and tier >= 1 and tier <= 3 then
        charmBorderWidget:setImageSource(string.format("/images/game/cyclopedia/ui/backdrop_charmgrade%d", tier))
        charmBorderWidget:setVisible(true)
        charmBase.hasTierBorder = true
    else
        charmBorderWidget:setImageSource("")
        charmBorderWidget:setVisible(false)
        charmBase.hasTierBorder = false
    end
end

-- Helper function to update charm focus border visibility
function Cyclopedia.updateCharmFocusBorder(charmBase, focused)
    local focusBorder = charmBase.charmFocusBorder
    if focused then
        focusBorder:setBorderWidth(1)
    else
        focusBorder:setBorderWidth(0)
    end
end

-- Function to setup CharmBase click handlers and populate ComboBox
function Cyclopedia.setupBestiaryCharmBases(data)
    local charmBase = UI.ListBase.CreatureInfo.CharmBase
    local charmBase2 = UI.ListBase.CreatureInfo.CharmBase2
    local charmSelector = UI.ListBase.CreatureInfo.CharmSelector
    local charmControlPanel = UI.ListBase.CreatureInfo.CharmControlPanel
    local selectAssignButton = charmControlPanel.SelectAssignButton
    local selectClearButton = charmControlPanel.SelectClearButton
    local coinCostPanel = charmControlPanel.CoinCostPanel

    -- Reset charm bases
    charmBase:setOpacity(0.5)
    charmBase2:setOpacity(0.5)

    -- Reset charm images
    charmBase.charmImage:setImageSource("")
    charmBase.charmImage:setVisible(false)
    charmBase2.charmImage:setImageSource("")
    charmBase2.charmImage:setVisible(false)

    -- Reset charm tier borders and focus border width
    Cyclopedia.setCharmTierBorder(charmBase, nil)
    Cyclopedia.setCharmTierBorder(charmBase2, nil)

    -- Reset focus state
    charmBase:setFocusable(false)
    charmBase:setFocusable(true)
    charmBase2:setFocusable(false)
    charmBase2:setFocusable(true)
    Cyclopedia.updateCharmFocusBorder(charmBase, false)
    Cyclopedia.updateCharmFocusBorder(charmBase2, false)

    -- Reset buttons and panels
    selectAssignButton:setEnabled(false)
    selectAssignButton:setVisible(true)
    selectClearButton:setEnabled(false)
    selectClearButton:setVisible(false)
    coinCostPanel:setVisible(false)

    charmSelector:setEnabled(false)
    charmSelector:clearOptions()
    charmSelector:addOption("Select a charm...")

    -- Store the currently selected charm type (nil = none, 1 = major, 2 = minor)
    Cyclopedia.selectedCharmType = nil
    -- Store the currently selected charm data for clear operation
    Cyclopedia.selectedCharmForClear = nil

    -- Check if there are charms assigned to this creature and display their images
    local creatureRaceId = data.id
    if Cyclopedia.formattedCharmsData and creatureRaceId then
        for _, charmData in ipairs(Cyclopedia.formattedCharmsData) do
            if charmData.asignedStatus and charmData.raceId == creatureRaceId then
                if charmData.category == CHARM_CATEGORY.MAJOR then
                    Cyclopedia.setCharmImage(charmBase.charmImage, charmData.id)
                    Cyclopedia.setCharmTierBorder(charmBase, charmData.tier)
                    charmBase:setOpacity(1.0)
                elseif charmData.category == CHARM_CATEGORY.MINOR then
                    Cyclopedia.setCharmImage(charmBase2.charmImage, charmData.id)
                    Cyclopedia.setCharmTierBorder(charmBase2, charmData.tier)
                    charmBase2:setOpacity(1.0)
                end
            end
        end
    end

    -- Setup Assign Charm button click handler
    selectAssignButton.onClick = function()
        Cyclopedia.onAssignCharmClick()
    end

    -- Setup Clear Charm button click handler
    selectClearButton.onClick = function()
        Cyclopedia.onClearCharmClick()
    end

    -- Setup focus handlers for charm bases
    charmBase.onFocusChange = function(widget, focused)
        Cyclopedia.updateCharmFocusBorder(widget, focused)
    end
    charmBase2.onFocusChange = function(widget, focused)
        Cyclopedia.updateCharmFocusBorder(widget, focused)
    end

    -- Major Charms (CharmBase) - enabled when currentLevel > 3 (fully unlocked bestiary)
    if data.currentLevel > 3 then
        charmBase:setOpacity(1.0)
        charmBase.onMouseRelease = function(widget, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                Cyclopedia.onCharmBaseClick(CHARM_CATEGORY.MAJOR)
                return true
            end
            return false
        end
    else
        charmBase.onMouseRelease = nil
    end

    -- Minor Charms (CharmBase2) - enabled when currentLevel > 1
    if data.currentLevel > 1 then
        charmBase2:setOpacity(1.0)
        charmBase2.onMouseRelease = function(widget, mousePos, mouseButton)
            if mouseButton == MouseLeftButton then
                Cyclopedia.onCharmBaseClick(CHARM_CATEGORY.MINOR)
                return true
            end
            return false
        end
    else
        charmBase2.onMouseRelease = nil
    end
end

-- Function called when a CharmBase is clicked
function Cyclopedia.onCharmBaseClick(charmCategory)
    if not Cyclopedia.formattedCharmsData or #Cyclopedia.formattedCharmsData == 0 then
        -- Charms data not loaded yet - request it
        g_game.requestBestiary()
        return
    end

    local charmSelector = UI.ListBase.CreatureInfo.CharmSelector
    local charmBase = UI.ListBase.CreatureInfo.CharmBase
    local charmBase2 = UI.ListBase.CreatureInfo.CharmBase2
    local charmControlPanel = UI.ListBase.CreatureInfo.CharmControlPanel
    local selectAssignButton = charmControlPanel.SelectAssignButton
    local selectClearButton = charmControlPanel.SelectClearButton
    local coinCostPanel = charmControlPanel.CoinCostPanel

    -- Visual feedback for selected charm base
    if charmCategory == CHARM_CATEGORY.MAJOR then
        charmBase:setBorderWidth(1)
        charmBase:setBorderColor("#FFFFFF")
        charmBase2:setBorderWidth(0)
    else
        charmBase2:setBorderWidth(1)
        charmBase2:setBorderColor("#FFFFFF")
        charmBase:setBorderWidth(0)
    end

    Cyclopedia.selectedCharmType = charmCategory

    -- Get current creature's race ID
    local creatureRaceId = Cyclopedia.currentCreatureData and Cyclopedia.currentCreatureData.id

    -- Check if there's a charm already assigned to this creature for this category
    local assignedCharm = nil
    for _, charmData in ipairs(Cyclopedia.formattedCharmsData) do
        if charmData.category == charmCategory and charmData.asignedStatus and charmData.raceId == creatureRaceId then
            assignedCharm = charmData
            break
        end
    end

    -- Clear and populate the ComboBox with charms of the selected category
    charmSelector:clearOptions()

    if assignedCharm then
        -- There's a charm assigned to this creature - show Clear button
        Cyclopedia.selectedCharmForClear = assignedCharm

        charmSelector:addOption(assignedCharm.name, assignedCharm.id)
        charmSelector:setEnabled(false)

        selectAssignButton:setVisible(false)
        selectClearButton:setVisible(true)
        selectClearButton:setEnabled(true)

        -- Show the cost panel with remove cost
        coinCostPanel:setVisible(true)
        local coinCostLabel = coinCostPanel.CoinCost
        coinCostLabel:setText(Cyclopedia.formatGold(assignedCharm.removeRuneCost or 0))
    else
        -- No charm assigned - show Assign button and available charms
        Cyclopedia.selectedCharmForClear = nil

        local availableCharms = {}
        for _, charmData in ipairs(Cyclopedia.formattedCharmsData) do
            -- Check if charm is unlocked (or has tier > 0) AND is not assigned to another creature
            local isUnlocked = charmData.unlocked or (charmData.tier and charmData.tier > 0)
            local isFree = not charmData.asignedStatus
            if charmData.category == charmCategory and isUnlocked and isFree then
                table.insert(availableCharms, {
                    id = charmData.id,
                    name = charmData.name or ("Charm " .. charmData.id),
                    tier = charmData.tier or 0
                })
            end
        end

        -- Sort by tier (descending) then name
        table.sort(availableCharms, function(a, b)
            if a.tier ~= b.tier then
                return a.tier > b.tier
            end
            return a.name:lower() < b.name:lower()
        end)

        -- Show Assign button, hide Clear button
        selectAssignButton:setVisible(true)
        selectClearButton:setVisible(false)
        coinCostPanel:setVisible(false)

        -- Add charms to ComboBox or show "no charms" message
        if #availableCharms > 0 then
            for _, charm in ipairs(availableCharms) do
                charmSelector:addOption(charm.name, charm.id)
            end
            charmSelector:setEnabled(true)
            selectAssignButton:setEnabled(true)
        else
            local noCharmsMsg = charmCategory == CHARM_CATEGORY.MAJOR and "No Major Charms usable" or
                "No Minor Charms usable"
            charmSelector:addOption(noCharmsMsg)
            charmSelector:setEnabled(false)
            selectAssignButton:setEnabled(false)
        end
    end
end

-- Function called when "Assign Charm" button is clicked
function Cyclopedia.onAssignCharmClick()
    local charmSelector = UI.ListBase.CreatureInfo.CharmSelector
    local selectedCharmName = charmSelector:getCurrentOption().text
    local selectedCharmId = charmSelector:getCurrentOption().data

    -- Don't proceed if no valid charm is selected
    if not selectedCharmId then
        return
    end

    -- Get the current creature's race ID
    local creatureRaceId = Cyclopedia.currentCreatureData and Cyclopedia.currentCreatureData.id
    if not creatureRaceId then
        return
    end

    local confirmWindow = nil

    -- Hide the main Cyclopedia window while showing the confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    local noCallback = function()
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        -- Show the main Cyclopedia window again
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    local yesCallback = function()
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        -- Show the main Cyclopedia window again
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
        -- Send the charm assignment request to the server
        -- Action 1 = Select/Assign charm to creature
        g_game.BuyCharmRune(selectedCharmId, 1, creatureRaceId)

        -- Refresh creature details after charm assignment
        if Cyclopedia.currentCreatureData and Cyclopedia.currentCreatureData.id then
            g_game.requestBestiarySearch(Cyclopedia.currentCreatureData.id)
        end
    end

    confirmWindow = displayGeneralBox(
        tr('Assign Charm'),
        string.format('Do you want to use the Charm %s for this creature?', selectedCharmName),
        {
            { text = tr('No'),  callback = noCallback },
            { text = tr('Yes'), callback = yesCallback },
        },
        yesCallback,
        noCallback
    )
end

-- Function called when "Clear Charm" button is clicked
function Cyclopedia.onClearCharmClick()
    local charmData = Cyclopedia.selectedCharmForClear
    if not charmData then
        return
    end

    local confirmWindow = nil

    -- Hide the main Cyclopedia window while showing the confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    local noCallback = function()
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        -- Show the main Cyclopedia window again
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
    end

    local yesCallback = function()
        -- Send the charm removal request to the server
        -- Action 2 = Remove charm from creature
        g_game.BuyCharmRune(charmData.id, 2)
        if confirmWindow then
            confirmWindow:destroy()
            confirmWindow = nil
        end
        -- Show the main Cyclopedia window again
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
        -- Set redirect so charms tab knows which charm to focus
        Cyclopedia.Charms.redirect = charmData.id

        -- Refresh creature details after charm removal
        if Cyclopedia.currentCreatureData and Cyclopedia.currentCreatureData.id then
            g_game.requestBestiarySearch(Cyclopedia.currentCreatureData.id)
        end
    end

    if not confirmWindow then
        confirmWindow = displayGeneralBox(
            tr('Confirm Charm Removal'),
            tr('Do you want to remove the Charm %s from this creature? This will cost you %s gold pieces.',
                charmData.name, comma_value(charmData.removeRuneCost or 0)),
            {
                { text = tr('No'),  callback = noCallback },
                { text = tr('Yes'), callback = yesCallback },
            },
            yesCallback,
            noCallback
        )
    end
end

function Cyclopedia.ShowBestiaryCreature()
    Cyclopedia.Bestiary.Stage = STAGES.CREATURE
    Cyclopedia.onStageChange()
end

function Cyclopedia.ShowBestiaryCreatures(Category)
    UI.ListBase.CreatureList:destroyChildren()
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
    g_game.requestBestiaryOverview(Category, false, {})
end

function Cyclopedia.CreateBestiaryCategoryItem(Data)
    UI.BackPageButton:setEnabled(false)

    local widget = g_ui.createWidget("BestiaryCategory", UI.ListBase.CategoryList)
    widget:setText(Data.name)
    widget.ClassIcon:setImageSource("/game_cyclopedia/images/bestiary/creatures/" .. Data.name:lower():gsub(" ", "_"))
    widget.Category = Data.name
    widget:setColor("#C0C0C0")
    widget.TotalValue:setText(string.format("Total: %d", Data.amount))
    widget.KnownValue:setText(string.format("Known: %d", Data.know))

    function widget.ClassBase:onClick()
        UI.BackPageButton:setEnabled(true)
        Cyclopedia.ShowBestiaryCreatures(self:getParent().Category)
        Cyclopedia.Bestiary.Stage = STAGES.CREATURES
        Cyclopedia.onStageChange()
    end
end

function Cyclopedia.loadBestiarySearchCreatures(data)
    UI.ListBase.CategoryList:setVisible(false)
    UI.ListBase.CreatureInfo:setVisible(false)
    UI.ListBase.CreatureList:setVisible(true)
    UI.BackPageButton:setEnabled(true)

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    Cyclopedia.onStageChange()
    Cyclopedia.Bestiary.Search = {}
    Cyclopedia.Bestiary.Page = 1

    local maxCategoriesPerPage = 15
    Cyclopedia.Bestiary.TotalSearchPages = math.ceil(#data / maxCategoriesPerPage)

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalSearchPages))

    local page = 1
    Cyclopedia.Bestiary.Search[page] = {}

    for i = 1, #data do
        if (i - 1) % maxCategoriesPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Search[page] = {}
        end
        local creature = {
            id = data[i].id,
            currentLevel = data[i].currentLevel,
            AnimusMasteryBonus = data[i].creatureAnimusMasteryBonus or 0,
        }

        table.insert(Cyclopedia.Bestiary.Search[page], creature)
    end

    Cyclopedia.Bestiary.Stage = STAGES.SEARCH
    Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, true)
    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.loadBestiaryCreatures(data)
    Cyclopedia.Bestiary.Creatures = {}
    Cyclopedia.Bestiary.Page = 1

    local maxCategoriesPerPage = 15
    Cyclopedia.Bestiary.TotalCreaturesPages = math.ceil(#data / maxCategoriesPerPage)

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalCreaturesPages))

    local page = 1
    Cyclopedia.Bestiary.Creatures[page] = {}

    for i = 1, #data do
        if (i - 1) % maxCategoriesPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Creatures[page] = {}
        end

        local creature = {
            id = data[i].id,
            currentLevel = data[i].currentLevel,
            AnimusMasteryBonus = data[i].creatureAnimusMasteryBonus,

        }

        table.insert(Cyclopedia.Bestiary.Creatures[page], creature)
    end

    Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, false)
    Cyclopedia.verifyBestiaryButtons()
end

-- note: this one needs refactor
-- expected result:
-- when a string is entered
-- the list should generate client-side
-- the list of search results that match the search string
-- looks identical to category view
function Cyclopedia.BestiarySearch()
    local text = UI.SearchEdit:getText()
    local raceList = g_things.getRacesByName(text)

    local list = {}
    for _, race in pairs(raceList) do
        list[#list + 1] = race.raceId
    end

    g_game.requestBestiaryOverview("Result", true, list)

    UI.SearchEdit:setText("")
end

function Cyclopedia.BestiarySearchText(text)
    if text ~= "" then
        UI.SearchButton:enable(true)
    else
        UI.SearchButton:disable(false)
    end
end

function Cyclopedia.CreateBestiaryCreaturesItem(data)
    local raceData = g_things.getRaceData(data.id)

    local function verify(name)
        if #name > 18 then
            return name:sub(1, 15) .. "..."
        else
            return name
        end
    end

    local widget = g_ui.createWidget("BestiaryCreature", UI.ListBase.CreatureList)
    widget:setId(data.id)

    local formattedName = raceData.name:gsub("(%l)(%w*)", function(first, rest)
        return first:upper() .. rest
    end)

    widget.Name:setText(verify(formattedName))
    widget.Sprite:setOutfit(raceData.outfit)
    widget.Sprite:getCreature():setStaticWalking(1000)

    if data.AnimusMasteryBonus > 0 then
        widget.AnimusMastery:setTooltip("The Animus Mastery for this creature is unlocked.\nIt yields " ..
            data.AnimusMasteryBonus ..
            "% bonus experience points, plus an additional 0.1% for every 10 Animus Masteries unlocked, up to a maximum of 4%.\nYou currently benefit from " ..
            data.AnimusMasteryBonus ..
            "% bonus experience points due to having unlocked " .. animusMasteryPoints .. " Animus Masteries.")
        widget.AnimusMastery:setVisible(true)
    else
        widget.AnimusMastery:removeTooltip()
        widget.AnimusMastery:setVisible(false)
    end

    if data.currentLevel > 3 then
        widget.Finalized:setVisible(true)
        widget.KillsLabel:setVisible(false)
        widget.Sprite:getCreature():setShader("")
    else
        if data.currentLevel < 1 then
            widget.KillsLabel:setText("?")
            widget.Sprite:getCreature():setShader("Outfit - cyclopedia-black")
            widget.Name:setText("Unknown")
            widget.AnimusMastery:setVisible(false)
        else
            widget.KillsLabel:setText(string.format("%d / 3", data.currentLevel - 1))
        end
    end

    function widget.ClassBase:onClick()
        if data.currentLevel < 1 then
            return
        end

        UI.BackPageButton:setEnabled(true)
        g_game.requestBestiarySearch(widget:getId())
        Cyclopedia.ShowBestiaryCreature()
    end
end

function Cyclopedia.loadBestiaryCreature(page, search)
    local state = "Creatures"
    if search then
        state = "Search"
    end

    if not Cyclopedia.Bestiary[state][page] then
        return
    end

    UI.ListBase.CreatureList:destroyChildren()

    for _, data in ipairs(Cyclopedia.Bestiary[state][page]) do
        Cyclopedia.CreateBestiaryCreaturesItem(data)
    end
end

function Cyclopedia.loadBestiaryCategories(data)
    Cyclopedia.Bestiary.Categories = {}
    Cyclopedia.Bestiary.Page = 1

    local maxCategoriesPerPage = 15
    Cyclopedia.Bestiary.TotalCategoriesPages = math.ceil(#data / maxCategoriesPerPage)

    if UI == nil or UI.PageValue == nil then -- I know, don't change it
        return
    end

    UI.PageValue:setText(string.format("%d / %d", Cyclopedia.Bestiary.Page, Cyclopedia.Bestiary.TotalCategoriesPages))

    local page = 1
    Cyclopedia.Bestiary.Categories[page] = {}

    for i = 1, #data do
        if (i - 1) % maxCategoriesPerPage == 0 and i > 1 then
            page = page + 1
            Cyclopedia.Bestiary.Categories[page] = {}
        end

        local category = {
            name = data[i].bestClass,
            amount = data[i].count,
            know = data[i].unlockedCount,
            AnimusMasteryBonus = data[i].AnimusMasteryBonus,
        }

        table.insert(Cyclopedia.Bestiary.Categories[page], category)
    end

    Cyclopedia.loadBestiaryCategory(Cyclopedia.Bestiary.Page)
    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.loadBestiaryCategory(page)
    if not Cyclopedia.Bestiary.Categories[page] then
        return
    end

    UI.ListBase.CategoryList:destroyChildren()

    for _, data in ipairs(Cyclopedia.Bestiary.Categories[page]) do
        Cyclopedia.CreateBestiaryCategoryItem(data)
    end
end

function Cyclopedia.onStageChange()
    Cyclopedia.Bestiary.Page = 1

    if Cyclopedia.Bestiary.Stage == STAGES.CATEGORY then
        UI.BackPageButton:setEnabled(false)
        UI.ListBase.CategoryList:setVisible(true)
        UI.ListBase.CreatureList:setVisible(false)
        UI.ListBase.CreatureInfo:setVisible(false)
    end

    if Cyclopedia.Bestiary.Stage == STAGES.CREATURES then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(true)
        UI.ListBase.CreatureInfo:setVisible(false)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
            Cyclopedia.onStageChange()
        end
    end

    if Cyclopedia.Bestiary.Stage == STAGES.SEARCH then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(true)
        UI.ListBase.CreatureInfo:setVisible(false)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CATEGORY
            Cyclopedia.onStageChange()
        end
    end

    if Cyclopedia.Bestiary.Stage == STAGES.CREATURE then
        UI.BackPageButton:setEnabled(true)
        UI.ListBase.CategoryList:setVisible(false)
        UI.ListBase.CreatureList:setVisible(false)

        -- Reset creature info before showing to prevent flicker
        Cyclopedia.resetCreatureInfoVisuals()

        UI.ListBase.CreatureInfo:setVisible(true)

        function UI.BackPageButton.onClick()
            Cyclopedia.Bestiary.Stage = STAGES.CREATURES
            Cyclopedia.onStageChange()
        end
    end

    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.changeBestiaryPage(prev, next)
    if next then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page + 1
    end

    if prev then
        Cyclopedia.Bestiary.Page = Cyclopedia.Bestiary.Page - 1
    end

    local stage = Cyclopedia.Bestiary.Stage
    if stage == STAGES.CATEGORY then
        Cyclopedia.loadBestiaryCategory(Cyclopedia.Bestiary.Page)
    elseif stage == STAGES.CREATURES then
        Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, false)
    elseif stage == STAGES.SEARCH then
        Cyclopedia.loadBestiaryCreature(Cyclopedia.Bestiary.Page, true)
    end

    Cyclopedia.verifyBestiaryButtons()
end

function Cyclopedia.verifyBestiaryButtons()
    local function updateButtonState(button, condition)
        if condition then
            button:enable()
        else
            button:disable()
        end
    end

    local function updatePageValue(currentPage, totalPages)
        UI.PageValue:setText(string.format("%d / %d", currentPage, totalPages))
    end

    updateButtonState(UI.SearchButton, UI.SearchEdit:getText() ~= "")

    local stage = Cyclopedia.Bestiary.Stage
    local totalSearchPages = Cyclopedia.Bestiary.TotalSearchPages
    local page = Cyclopedia.Bestiary.Page
    if stage == STAGES.SEARCH and totalSearchPages then
        local totalPages = totalSearchPages
        updateButtonState(UI.PrevPageButton, page > 1)
        updateButtonState(UI.NextPageButton, page < totalPages)
        updatePageValue(page, totalPages)
        return
    end

    if stage == STAGES.CREATURE then
        UI.PrevPageButton:disable()
        UI.NextPageButton:disable()
        updatePageValue(1, 1)
        return
    end

    local totalCategoriesPages = Cyclopedia.Bestiary.TotalCategoriesPages
    local totalCreaturesPages = Cyclopedia.Bestiary.TotalCreaturesPages
    if stage == STAGES.CATEGORY and totalCategoriesPages or stage == STAGES.CREATURES and totalCreaturesPages then
        local totalPages = stage == STAGES.CATEGORY and totalCategoriesPages or totalCreaturesPages
        updateButtonState(UI.PrevPageButton, page > 1)
        updateButtonState(UI.NextPageButton, page < totalPages)
        updatePageValue(page, totalPages)
    end
end

--[[
===================================================
=                     Tracker                     =
===================================================
]]

function Cyclopedia.refreshBestiaryTracker()
    -- First check if we have a character
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    -- Ensure tracker data is initialized
    if not Cyclopedia.storedTrackerData then
        Cyclopedia.initializeTrackerData()
    end

    -- Always try to load cached data for immediate display
    local cachedData = Cyclopedia.loadTrackerData("bestiary")
    if cachedData and #cachedData > 0 then
        Cyclopedia.storedTrackerData = cachedData
        -- Immediately populate if we have tracker window
        if trackerMiniWindow then
            Cyclopedia.onParseCyclopediaTracker(0, Cyclopedia.storedTrackerData)
        end
    end

    -- Always request fresh data from server
    g_game.requestBestiary()
end

function Cyclopedia.refreshBosstiaryTracker()
    -- First check if we have a character
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    -- Ensure tracker data is initialized
    if not Cyclopedia.storedBosstiaryTrackerData then
        Cyclopedia.initializeTrackerData()
    end

    -- Always try to load cached data for immediate display
    local cachedData = Cyclopedia.loadTrackerData("bosstiary")
    if cachedData and #cachedData > 0 then
        Cyclopedia.storedBosstiaryTrackerData = cachedData
        -- Immediately populate if we have tracker window
        if trackerMiniWindowBosstiary then
            Cyclopedia.onParseCyclopediaTracker(1, Cyclopedia.storedBosstiaryTrackerData)
        end
    end

    -- Always request fresh data from server
    g_game.requestBestiary()
end

function Cyclopedia.refreshAllVisibleTrackers()
    -- Refresh bestiary tracker if it's visible
    if trackerMiniWindow and trackerMiniWindow:isVisible() then
        Cyclopedia.refreshBestiaryTracker()
    end

    -- Refresh bosstiary tracker if it's visible
    if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary:isVisible() then
        Cyclopedia.refreshBosstiaryTracker()
    end
end

-- Force refresh function that can be called manually to reload data
function Cyclopedia.forceRefreshTrackers()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        print("Debug: No character name available")
        return
    end

    print("Debug: Force refreshing trackers for character: " .. char)

    -- Clear stored data to force reload
    Cyclopedia.storedTrackerData = {}
    Cyclopedia.storedBosstiaryTrackerData = {}

    -- Initialize and load fresh data
    Cyclopedia.initializeTrackerData()

    -- Request fresh data from server
    g_game.requestBestiary()

    -- Refresh all visible trackers
    scheduleEvent(function()
        Cyclopedia.refreshAllVisibleTrackers()
    end, 100)
end

-- Debug function to check tracker state
function Cyclopedia.debugTrackerState()
    local char = g_game.getCharacterName()
    print("=== Tracker Debug Info ===")
    print("Character: " .. (char or "nil"))
    print("Bestiary data count: " .. (Cyclopedia.storedTrackerData and #Cyclopedia.storedTrackerData or "nil"))
    print("Bosstiary data count: " ..
        (Cyclopedia.storedBosstiaryTrackerData and #Cyclopedia.storedBosstiaryTrackerData or "nil"))
    print("Bestiary window visible: " .. tostring(trackerMiniWindow and trackerMiniWindow:isVisible()))
    print("Bosstiary window visible: " .. tostring(trackerMiniWindowBosstiary and trackerMiniWindowBosstiary:isVisible()))
    if trackerMiniWindow then
        print("Bestiary panel children: " .. trackerMiniWindow.contentsPanel:getChildCount())
    end
    if trackerMiniWindowBosstiary then
        print("Bosstiary panel children: " .. trackerMiniWindowBosstiary.contentsPanel:getChildCount())
    end
    print("========================")
end

function Cyclopedia.toggleBestiaryTracker()
    if not trackerMiniWindow then
        return
    end

    if trackerButton:isOn() then
        trackerMiniWindow:close()
        trackerButton:setOn(false)
    else
        if not trackerMiniWindow:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(trackerMiniWindow,
                trackerMiniWindow:getMinimumHeight())
            if not panel then
                return
            end
            panel:addChild(trackerMiniWindow)
        end

        -- Ensure data is loaded before opening
        local char = g_game.getCharacterName()
        if char and #char > 0 then
            Cyclopedia.initializeTrackerData()
            -- Try to load immediately if we have cached data
            if Cyclopedia.storedTrackerData and #Cyclopedia.storedTrackerData > 0 then
                Cyclopedia.onParseCyclopediaTracker(0, Cyclopedia.storedTrackerData)
            end
        end

        trackerMiniWindow:open()

        -- Multiple fallback attempts
        scheduleEvent(function()
            if trackerMiniWindow:isVisible() then
                if trackerMiniWindow.contentsPanel:getChildCount() == 0 then
                    Cyclopedia.refreshBestiaryTracker()
                end

                -- Another fallback check
                scheduleEvent(function()
                    if trackerMiniWindow:isVisible() and trackerMiniWindow.contentsPanel:getChildCount() == 0 then
                        -- Force request fresh data if still empty
                        g_game.requestBestiary()
                        scheduleEvent(function()
                            Cyclopedia.refreshBestiaryTracker()
                        end, 1000)
                    end
                end, 500)
            end
        end, 100)
    end
end

function Cyclopedia.toggleBosstiaryTracker()
    if not trackerMiniWindowBosstiary then
        return
    end

    if trackerButtonBosstiary:isOn() then
        trackerMiniWindowBosstiary:close()
        trackerButtonBosstiary:setOn(false)
    else
        if not trackerMiniWindowBosstiary:getParent() then
            local panel = modules.game_interface.findContentPanelAvailable(trackerMiniWindowBosstiary,
                trackerMiniWindowBosstiary:getMinimumHeight())
            if not panel then
                return
            end
            panel:addChild(trackerMiniWindowBosstiary)
        end

        -- Ensure data is loaded before opening
        local char = g_game.getCharacterName()
        if char and #char > 0 then
            Cyclopedia.initializeTrackerData()
            -- Try to load immediately if we have cached data
            if Cyclopedia.storedBosstiaryTrackerData and #Cyclopedia.storedBosstiaryTrackerData > 0 then
                Cyclopedia.onParseCyclopediaTracker(1, Cyclopedia.storedBosstiaryTrackerData)
            end
        end

        trackerMiniWindowBosstiary:open()

        -- Multiple fallback attempts
        scheduleEvent(function()
            if trackerMiniWindowBosstiary:isVisible() then
                if trackerMiniWindowBosstiary.contentsPanel:getChildCount() == 0 then
                    Cyclopedia.refreshBosstiaryTracker()
                end

                -- Another fallback check
                scheduleEvent(function()
                    if trackerMiniWindowBosstiary:isVisible() and trackerMiniWindowBosstiary.contentsPanel:getChildCount() == 0 then
                        -- Force request fresh data if still empty
                        g_game.requestBestiary()
                        scheduleEvent(function()
                            Cyclopedia.refreshBosstiaryTracker()
                        end, 1000)
                    end
                end, 500)
            end
        end, 100)
    end
end

function Cyclopedia.onTrackerClose(temp)
    -- Button states are now handled by onClose callbacks
    -- This function can be removed or kept for backwards compatibility
end

function Cyclopedia.setBarPercent(widget, percent)
    if percent > 92 then
        widget.killsBar:setBackgroundColor("#00BC00")
    elseif percent > 60 then
        widget.killsBar:setBackgroundColor("#50A150")
    elseif percent > 30 then
        widget.killsBar:setBackgroundColor("#A1A100")
    elseif percent > 8 then
        widget.killsBar:setBackgroundColor("#BF0A0A")
    elseif percent > 3 then
        widget.killsBar:setBackgroundColor("#910F0F")
    else
        widget.killsBar:setBackgroundColor("#850C0C")
    end

    widget.killsBar:setPercent(percent)
end

function Cyclopedia.onParseCyclopediaTracker(trackerType, data)
    if not data then
        return
    end

    -- If server returns empty data, don't clear existing cached data
    if #data == 0 then
        return
    end

    local isBoss = trackerType == 1
    local window = isBoss and trackerMiniWindowBosstiary or trackerMiniWindow

    -- Store the original data for re-sorting
    if isBoss then
        Cyclopedia.storedBosstiaryTrackerData = data
        -- Save to persistent storage
        Cyclopedia.saveTrackerData("bosstiary", data)
    else
        Cyclopedia.storedTrackerData = data
        -- Save to persistent storage
        Cyclopedia.saveTrackerData("bestiary", data)

        -- Clear and repopulate storedRaceIDs only for bestiary tracker
        storedRaceIDs = {}
    end

    -- Sort the data for both trackers
    local trackerTypeStr = isBoss and "bosstiary" or "bestiary"
    data = Cyclopedia.sortTrackerData(data, trackerTypeStr)

    -- Build a set of current raceIds in the new data
    local newRaceIds = {}
    for i, entry in ipairs(data) do
        local raceId = entry[1]
        newRaceIds[raceId] = i -- Store the expected order
    end

    -- Check if we need to reorder (compare current order with expected order)
    local needsReorder = false
    local children = window.contentsPanel:getChildren()
    if #children ~= #data then
        needsReorder = true
    else
        for i, child in ipairs(children) do
            local childId = tonumber(child:getId())
            if not childId or newRaceIds[childId] ~= i then
                needsReorder = true
                break
            end
        end
    end

    -- If order changed, destroy all and recreate
    if needsReorder then
        window.contentsPanel:destroyChildren()
        children = {}
    else
        -- Remove widgets that are no longer in the data
        for _, child in ipairs(children) do
            local childId = tonumber(child:getId())
            if childId and not newRaceIds[childId] then
                child:destroy()
            end
        end
    end

    for _, entry in ipairs(data) do
        local raceId, kills, uno, dos, maxKills = unpack(entry)

        -- Only add to storedRaceIDs for bestiary tracker
        if not isBoss then
            table.insert(storedRaceIDs, raceId)
        end

        local raceData = g_things.getRaceData(raceId)
        local name = raceData.name

        -- Try to find existing widget (only if we didn't destroy all)
        local widget = not needsReorder and window.contentsPanel:getChildById(raceId) or nil

        if widget then
            -- Update existing widget (no flick)
            widget.kills:setText(kills)
            widget:setTooltip(kills .. "/" .. maxKills)
            Cyclopedia.SetBestiaryProgress(45, widget.killsBar2, widget.ProgressBack33, widget.ProgressBack55, kills, uno,
                dos, maxKills)
        else
            -- Create new widget only if it doesn't exist
            widget = g_ui.createWidget("TrackerButton", window.contentsPanel)
            widget:setId(raceId)
            widget.creature:setOutfit(raceData.outfit)
            widget.label:setText(name:len() > 18 and name:sub(1, 15) .. "..." or name)
            widget.kills:setText(kills)
            widget.onMouseRelease = onTrackerClick
            widget:setTooltip(kills .. "/" .. maxKills)
            Cyclopedia.SetBestiaryProgress(45, widget.killsBar2, widget.ProgressBack33, widget.ProgressBack55, kills, uno,
                dos, maxKills)
        end

        -- Update hourglass icon for bosstiary tracker
        if isBoss and widget.hourglassIcon then
            local bossCooldownModule = modules.game_analyser and modules.game_analyser.BossCooldown
            if bossCooldownModule and bossCooldownModule.hasCooldown then
                local _, cooldownTime = bossCooldownModule:hasCooldown(raceId)
                if cooldownTime and cooldownTime > os.time() then
                    local resttime = cooldownTime - os.time()
                    local tooltipText = Cyclopedia.formatCooldownTooltip(resttime)
                    widget.hourglassIcon:setImageSource('/images/game/cyclopedia/bosstiary/hourglass-red')
                    widget.hourglassIcon:setTooltip(tooltipText)
                    widget.hourglassIcon:setVisible(true)
                elseif cooldownTime and cooldownTime >= 0 then
                    widget.hourglassIcon:setImageSource('/images/game/cyclopedia/bosstiary/hourglass')
                    widget.hourglassIcon:setTooltip("No Cooldown")
                    widget.hourglassIcon:setVisible(true)
                else
                    widget.hourglassIcon:setVisible(false)
                end
            else
                widget.hourglassIcon:setVisible(false)
            end
        end
    end
end

-- Helper function to format cooldown time for tooltip
function Cyclopedia.formatCooldownTooltip(resttime)
    if resttime <= 0 then
        return "No Cooldown"
    elseif resttime <= 60 then
        return resttime .. "s"
    else
        local days = math.floor(resttime / 86400)
        local hours = math.floor((resttime % 86400) / 3600)
        local minutes = math.floor((resttime % 3600) / 60)
        if days > 0 then
            return string.format("%dd %02dh %02dmin", days, hours, minutes)
        else
            return string.format("%02dh %02dmin", hours, minutes)
        end
    end
end

-- Function to update hourglass icons in bosstiary tracker when cooldown data is received
function Cyclopedia.updateBosstiaryTrackerCooldownIcons()
    if not trackerMiniWindowBosstiary or not trackerMiniWindowBosstiary.contentsPanel then
        return
    end

    local bossCooldownModule = modules.game_analyser and modules.game_analyser.BossCooldown
    if not bossCooldownModule or not bossCooldownModule.hasCooldown then
        return
    end

    local children = trackerMiniWindowBosstiary.contentsPanel:getChildren()
    for _, widget in ipairs(children) do
        local raceId = tonumber(widget:getId())
        if widget.hourglassIcon and raceId then
            local _, cooldownTime = bossCooldownModule:hasCooldown(raceId)
            if cooldownTime and cooldownTime > os.time() then
                local resttime = cooldownTime - os.time()
                local tooltipText = Cyclopedia.formatCooldownTooltip(resttime)
                widget.hourglassIcon:setImageSource('/images/game/cyclopedia/bosstiary/hourglass-red')
                widget.hourglassIcon:setTooltip(tooltipText)
                widget.hourglassIcon:setVisible(true)
            elseif cooldownTime and cooldownTime >= 0 then
                widget.hourglassIcon:setImageSource('/images/game/cyclopedia/bosstiary/hourglass')
                widget.hourglassIcon:setTooltip("No Cooldown")
                widget.hourglassIcon:setVisible(true)
            else
                widget.hourglassIcon:setVisible(false)
            end
        end
    end
end

local BESTIATYTRACKER_FILTERS = {
    ["sortByName"] = false,
    ["ShortByPercentage"] = false,
    ["sortByKills"] = true,
    ["sortByAscending"] = true,
    ["sortByDescending"] = false
}

local BOSSTIARYTRACKER_FILTERS = {
    ["sortByName"] = false,
    ["ShortByPercentage"] = false,
    ["sortByKills"] = true,
    ["sortByAscending"] = true,
    ["sortByDescending"] = false
}

function Cyclopedia.loadTrackerFilters(trackerType)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        local defaultFilters = trackerType == "bosstiary" and BOSSTIARYTRACKER_FILTERS or BESTIATYTRACKER_FILTERS
        return defaultFilters
    end

    local filterKey = trackerType == "bosstiary" and "bosstiaryTracker" or "bestiaryTracker"
    local charFilterKey = string.format("%s_%s", filterKey, char)
    local defaultFilters = trackerType == "bosstiary" and BOSSTIARYTRACKER_FILTERS or BESTIATYTRACKER_FILTERS

    local settings = g_settings.getNode(charFilterKey)
    if not settings or not settings['filters'] then
        -- Save default filters for first time use
        g_settings.mergeNode(charFilterKey, {
            ['filters'] = defaultFilters,
            ['character'] = char
        })
        return defaultFilters
    end
    return settings['filters']
end

function Cyclopedia.saveTrackerFilters(trackerType)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local filterKey = trackerType == "bosstiary" and "bosstiaryTracker" or "bestiaryTracker"
    local charFilterKey = string.format("%s_%s", filterKey, char)

    g_settings.mergeNode(charFilterKey, {
        ['filters'] = Cyclopedia.loadTrackerFilters(trackerType),
        ['character'] = char
    })
end

-- New functions to save/load tracker data (character-specific)
function Cyclopedia.saveTrackerData(trackerType, data)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local dataKey = trackerType == "bosstiary" and "bosstiaryTrackerData" or "bestiaryTrackerData"
    local charDataKey = string.format("%s_%s", dataKey, char)

    g_settings.mergeNode(charDataKey, {
        ['data'] = data,
        ['timestamp'] = os.time(),
        ['character'] = char
    })
end

function Cyclopedia.loadTrackerData(trackerType)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return nil
    end

    local dataKey = trackerType == "bosstiary" and "bosstiaryTrackerData" or "bestiaryTrackerData"
    local charDataKey = string.format("%s_%s", dataKey, char)

    local settings = g_settings.getNode(charDataKey)
    if settings and settings['data'] and settings['character'] == char then
        -- Check if data is not too old (older than 1 hour = stale)
        local timestamp = settings['timestamp'] or 0
        local currentTime = os.time()
        if currentTime - timestamp < 3600 then -- 1 hour in seconds
            return settings['data']
        end
    end
    return nil
end

function Cyclopedia.initializeTrackerData()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        -- Character name not available yet, skip initialization
        return
    end

    -- Only initialize if we don't already have data loaded for this character
    if not Cyclopedia.storedTrackerData then
        Cyclopedia.storedTrackerData = {}
    end
    if not Cyclopedia.storedBosstiaryTrackerData then
        Cyclopedia.storedBosstiaryTrackerData = {}
    end

    -- Load cached bestiary tracker data for current character (only if not already loaded)
    if #Cyclopedia.storedTrackerData == 0 then
        local cachedBestiaryData = Cyclopedia.loadTrackerData("bestiary")
        if cachedBestiaryData and #cachedBestiaryData > 0 then
            Cyclopedia.storedTrackerData = cachedBestiaryData
        end
    end

    -- Load cached bosstiary tracker data for current character (only if not already loaded)
    if #Cyclopedia.storedBosstiaryTrackerData == 0 then
        local cachedBosstiaryData = Cyclopedia.loadTrackerData("bosstiary")
        if cachedBosstiaryData and #cachedBosstiaryData > 0 then
            Cyclopedia.storedBosstiaryTrackerData = cachedBosstiaryData
        end
    end
end

-- Function to ensure storedRaceIDs is populated from cached tracker data
function Cyclopedia.ensureStoredRaceIDsPopulated()
    -- If storedRaceIDs is already populated, don't need to do anything
    if storedRaceIDs and #storedRaceIDs > 0 then
        return
    end

    -- Initialize tracker data if not already done
    Cyclopedia.initializeTrackerData()

    -- Populate storedRaceIDs from cached bestiary tracker data
    if Cyclopedia.storedTrackerData and #Cyclopedia.storedTrackerData > 0 then
        storedRaceIDs = {}
        for _, entry in ipairs(Cyclopedia.storedTrackerData) do
            local raceId = entry[1] -- First element is the race ID
            table.insert(storedRaceIDs, raceId)
        end
    end
end

-- Function to clear tracker data when character changes
function Cyclopedia.clearTrackerDataForCharacterChange()
    -- Clear in-memory data
    Cyclopedia.storedTrackerData = {}
    Cyclopedia.storedBosstiaryTrackerData = {}

    -- Clear visual tracker displays
    if trackerMiniWindow and trackerMiniWindow.contentsPanel then
        trackerMiniWindow.contentsPanel:destroyChildren()
    end
    if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary.contentsPanel then
        trackerMiniWindowBosstiary.contentsPanel:destroyChildren()
    end

    -- Clear stored race IDs
    storedRaceIDs = {}
end

-- Function to clean up old character data (optional maintenance function)
function Cyclopedia.clearTrackerDataForCharacterChange()
    -- Clear in-memory data
    Cyclopedia.storedTrackerData = {}
    Cyclopedia.storedBosstiaryTrackerData = {}

    -- Clear visual tracker displays
    if trackerMiniWindow and trackerMiniWindow.contentsPanel then
        trackerMiniWindow.contentsPanel:destroyChildren()
    end
    if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary.contentsPanel then
        trackerMiniWindowBosstiary.contentsPanel:destroyChildren()
    end

    -- Clear stored race IDs
    storedRaceIDs = {}
end

-- Function to clean up old character data (optional maintenance function)
function Cyclopedia.cleanupOldTrackerData(daysOld)
    daysOld = daysOld or 30 -- Default: clean data older than 30 days
    local cutoffTime = os.time() - (daysOld * 24 * 60 * 60)

    -- Get all settings and find tracker-related keys
    local allSettings = g_settings.getSettings()
    for key, value in pairs(allSettings) do
        if string.match(key, "^bestiaryTrackerData_") or
            string.match(key, "^bosstiaryTrackerData_") or
            string.match(key, "^bestiaryTracker_") or
            string.match(key, "^bosstiaryTracker_") then
            if value.timestamp and value.timestamp < cutoffTime then
                g_settings.remove(key)
            end
        end
    end
end

-- New function to populate visible trackers with cached data
function Cyclopedia.populateVisibleTrackersWithCachedData()
    -- Check if we have a valid character
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    -- Ensure tracker data is initialized for this character (but don't force reload if data exists)
    Cyclopedia.initializeTrackerData()

    -- Populate bestiary tracker if it's visible and has cached data
    if trackerMiniWindow and trackerMiniWindow:isVisible() then
        if Cyclopedia.storedTrackerData and #Cyclopedia.storedTrackerData > 0 then
            Cyclopedia.onParseCyclopediaTracker(0, Cyclopedia.storedTrackerData)
        else
            -- Try to load cached data and populate
            Cyclopedia.refreshBestiaryTracker()
        end
    end

    -- Populate bosstiary tracker if it's visible and has cached data
    if trackerMiniWindowBosstiary and trackerMiniWindowBosstiary:isVisible() then
        if Cyclopedia.storedBosstiaryTrackerData and #Cyclopedia.storedBosstiaryTrackerData > 0 then
            Cyclopedia.onParseCyclopediaTracker(1, Cyclopedia.storedBosstiaryTrackerData)
        else
            -- Try to load cached data and populate
            Cyclopedia.refreshBosstiaryTracker()
        end
    end
end

function Cyclopedia.getTrackerFilter(trackerType, filter)
    return Cyclopedia.loadTrackerFilters(trackerType)[filter] or false
end

function Cyclopedia.setTrackerFilter(trackerType, filter, value)
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local filterKey = trackerType == "bosstiary" and "bosstiaryTracker" or "bestiaryTracker"
    local charFilterKey = string.format("%s_%s", filterKey, char)
    local filters = Cyclopedia.loadTrackerFilters(trackerType)

    -- Handle mutual exclusion for sorting methods
    if filter == "sortByName" or filter == "ShortByPercentage" or filter == "sortByKills" then
        filters["sortByName"] = false
        filters["ShortByPercentage"] = false
        filters["sortByKills"] = false
        filters[filter] = true
        -- Handle mutual exclusion for sorting direction
    elseif filter == "sortByAscending" or filter == "sortByDescending" then
        filters["sortByAscending"] = false
        filters["sortByDescending"] = false
        filters[filter] = true
    else
        filters[filter] = value
    end

    g_settings.mergeNode(charFilterKey, {
        ['filters'] = filters,
        ['character'] = char
    })

    -- Refresh the tracker display
    Cyclopedia.refreshTracker(trackerType)
end

function Cyclopedia.refreshTracker(trackerType)
    if trackerType == "bosstiary" then
        if trackerMiniWindowBosstiary and Cyclopedia.storedBosstiaryTrackerData then
            Cyclopedia.onParseCyclopediaTracker(1, Cyclopedia.storedBosstiaryTrackerData)
        end
    else
        if trackerMiniWindow and Cyclopedia.storedTrackerData then
            Cyclopedia.onParseCyclopediaTracker(0, Cyclopedia.storedTrackerData)
        end
    end
end

function Cyclopedia.sortTrackerData(data, trackerType)
    local filters = Cyclopedia.loadTrackerFilters(trackerType)
    local isDescending = filters.sortByDescending

    -- Create a copy of the data to avoid modifying the original
    local sortedData = {}
    for i, v in ipairs(data) do
        sortedData[i] = v
    end

    if filters.sortByName then
        table.sort(sortedData, function(a, b)
            local nameA = g_things.getRaceData(a[1]).name:lower()
            local nameB = g_things.getRaceData(b[1]).name:lower()
            if isDescending then
                return nameA > nameB
            else
                return nameA < nameB
            end
        end)
    elseif filters.ShortByPercentage then
        table.sort(sortedData, function(a, b)
            local raceIdA, killsA, _, _, maxKillsA = unpack(a)
            local raceIdB, killsB, _, _, maxKillsB = unpack(b)
            local percentA = maxKillsA > 0 and (killsA / maxKillsA * 100) or 0
            local percentB = maxKillsB > 0 and (killsB / maxKillsB * 100) or 0
            if isDescending then
                return percentA > percentB
            else
                return percentA < percentB
            end
        end)
    elseif filters.sortByKills then
        table.sort(sortedData, function(a, b)
            local remainingA = a[5] - a[2] -- maxKills - kills
            local remainingB = b[5] - b[2] -- maxKills - kills
            if isDescending then
                return remainingA > remainingB
            else
                return remainingA < remainingB
            end
        end)
    end

    return sortedData
end

-- Shared function to create tracker context menu
function Cyclopedia.createTrackerContextMenu(trackerType, mousePos)
    local menu = g_ui.createWidget('bestiaryTrackerMenu')
    menu:setGameMenu(true)
    local shortCreature = UIRadioGroup.create()
    local shortAlphabets = UIRadioGroup.create()

    for i, choice in ipairs(menu:getChildren()) do
        if i >= 1 and i <= 3 then
            shortCreature:addWidget(choice)
        elseif i == 5 or i == 6 then
            shortAlphabets:addWidget(choice)
        end
    end

    -- Set default selections
    local filters = Cyclopedia.loadTrackerFilters(trackerType)

    -- Set sorting method (default: sortByKills)
    if filters.sortByName then
        menu:getChildById('sortByName'):setChecked(true)
    elseif filters.ShortByPercentage then
        menu:getChildById('ShortByPercentage'):setChecked(true)
    elseif filters.sortByKills then
        menu:getChildById('sortByKills'):setChecked(true)
    else
        menu:getChildById('sortByKills'):setChecked(true)
    end

    -- Set sorting direction (default: ascending)
    if filters.sortByDescending then
        menu:getChildById('sortByDescending'):setChecked(true)
    else
        menu:getChildById('sortByAscending'):setChecked(true)
    end

    -- Add click handlers for menu options
    menu:getChildById('sortByName').onClick = function()
        Cyclopedia.setTrackerFilter(trackerType, 'sortByName', true); menu:destroy()
    end
    menu:getChildById('ShortByPercentage').onClick = function()
        Cyclopedia.setTrackerFilter(trackerType, 'ShortByPercentage', true); menu:destroy()
    end
    menu:getChildById('sortByKills').onClick = function()
        Cyclopedia.setTrackerFilter(trackerType, 'sortByKills', true); menu:destroy()
    end
    menu:getChildById('sortByAscending').onClick = function()
        Cyclopedia.setTrackerFilter(trackerType, 'sortByAscending', true); menu:destroy()
    end
    menu:getChildById('sortByDescending').onClick = function()
        Cyclopedia.setTrackerFilter(trackerType, 'sortByDescending', true); menu:destroy()
    end

    menu:display(mousePos)
    return true
end

-- Legacy functions for backwards compatibility
function Cyclopedia.loadBestiaryTrackerFilters()
    return Cyclopedia.loadTrackerFilters("bestiary")
end

function Cyclopedia.saveBestiaryTrackerFilters()
    return Cyclopedia.saveTrackerFilters("bestiary")
end

function Cyclopedia.getBestiaryTrackerFilter(filter)
    return Cyclopedia.getTrackerFilter("bestiary", filter)
end

function Cyclopedia.setBestiaryTrackerFilter(filter, value)
    return Cyclopedia.setTrackerFilter("bestiary", filter, value)
end

-- trackerMiniWindow.contentsPanel:moveChildToIndex(battleButton, index)
-- TODO Add sort by name, kills, percentage, ascending, descending
function test(index)
    trackerMiniWindow.contentsPanel:moveChildToIndex(trackerMiniWindow.contentsPanel:getLastChild(), index)
end

function onTrackerClick(widget, mousePosition, mouseButton)
    local taskId = tonumber(widget:getId())

    -- Determine if this is a bestiary tracker (not bosstiary)
    local parentPanel = widget:getParent()
    local isBestiaryTracker = parentPanel and trackerMiniWindow and parentPanel == trackerMiniWindow.contentsPanel

    if mouseButton == MouseLeftButton and isBestiaryTracker then
        -- Left-click on bestiary tracker: Open bestiary and select this creature
        Cyclopedia.openBestiaryWithCreature(taskId)
    elseif mouseButton == MouseLeftButton and not isBestiaryTracker then
        -- Left-click on bosstiary tracker: Open bosstiary
        toggle("bosstiary")
    elseif mouseButton == MouseRightButton then
        local menu = g_ui.createWidget("PopupMenu")

        menu:setGameMenu(true)
        menu:addOption("Stop Tracking " .. widget.label:getText(), function()
            g_game.sendStatusTrackerBestiary(taskId, false)
        end)
        menu:display(menuPosition)
    end
    return true
end

-- Stores the raceId to show when bestiary opens (used for direct creature navigation)
Cyclopedia.pendingCreatureRaceId = nil

-- Opens the Bestiary directly to a specific creature by its raceId
-- Used by the tracker to allow quick navigation to creature details
function Cyclopedia.openBestiaryWithCreature(raceId)
    if not raceId then return end

    -- Check if bestiary UI is fully loaded and visible (means we're on bestiary tab)
    -- We need to verify UI and its key components exist before using them directly
    local bestiaryTabActive = UI and UI:isVisible() and UI.BackPageButton and UI.ListBase

    if bestiaryTabActive then
        -- Bestiary tab already active, just request the creature and show it
        g_game.requestBestiarySearch(raceId)
        Cyclopedia.ShowBestiaryCreature()
    else
        -- Store the raceId to be loaded when bestiary opens
        Cyclopedia.pendingCreatureRaceId = raceId

        -- Use show() to open/switch to bestiary tab
        -- show() calls SelectWindow internally which properly handles tab switching
        show("bestiary")
    end
end

function onAddLootClick(widget, mousePosition, mouseButton)
    local itemId = widget:getItemId()
    local quickLoot = modules.game_quickloot.QuickLoot
    local lootFilterValue = quickLoot.data.filter
    local menu = g_ui.createWidget("PopupMenu")

    menu:setGameMenu(true)

    if not quickLoot.lootExists(itemId, lootFilterValue) then
        menu:addOption("Add to Loot List",
            function()
                quickLoot.addLootList(itemId, lootFilterValue)
            end)
    else
        menu:addOption("Remove from Loot List",
            function()
                quickLoot.removeLootList(itemId, lootFilterValue)
            end)
    end

    if not modules.game_npctrade.inWhiteList(itemId) then
        menu:addOption(tr('Add to Quick Sell BlackList'),
            function() modules.game_npctrade.addToWhitelist(itemId) end)
    else
        menu:addOption(tr('Remove from Quick Sell BlackList'),
            function() modules.game_npctrade.removeItemInList(itemId) end)
    end

    menu:display(menuPosition)

    return true
end
