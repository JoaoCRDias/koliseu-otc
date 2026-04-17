preyWindow = nil
preyButton = nil
preyWindowButton = nil

local timeLeftRerrol = {}

local creatureList = {}
local onWildcardValueChange = nil
local itemListMin = {}
local itemListMax = {}
local itemSize = {}
local maxFitItems = {}
local poolSize = {}
local itemsPool = {}
local currentRaces = {}
local currentSearchRaces = {}
local lastSelectedLabel = {}
local selectedMonster = {}

local updateRerollEvent = nil
local supportWindow = nil
local monsterList
local bankGold = 0
local inventoryGold = 0
local rerollPrice = 0
local bonusRerolls = 0

local PREY_BONUS_DAMAGE_BOOST = 0
local PREY_BONUS_DAMAGE_REDUCTION = 1
local PREY_BONUS_XP_BONUS = 2
local PREY_BONUS_IMPROVED_LOOT = 3
local PREY_BONUS_NONE = 4

local PREY_ACTION_LISTREROLL = 0
local PREY_ACTION_BONUSREROLL = 1
local PREY_ACTION_MONSTERSELECTION = 2
local PREY_ACTION_REQUEST_ALL_MONSTERS = 3
local PREY_ACTION_CHANGE_FROM_ALL = 4
local PREY_ACTION_LOCK_PREY = 5

local SLOT_STATE_LOCKED = 0
local SLOT_STATE_INACTIVE = 1
local SLOT_STATE_ACTIVE = 2
local SLOT_STATE_SELECTION = 3
local SLOT_STATE_WILDCARD = 4

local WILDCARD_LABEL_HEIGHT = 16
local WILDCARD_VISIBLE_LABELS = 11

local preyDescription = {}
local searchFilterText = ''

function bonusDescription(bonusType, bonusValue, bonusGrade)
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return "Damage bonus (" .. bonusGrade .. "/10)"
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return "Damage reduction bonus (" .. bonusGrade .. "/10)"
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return "XP bonus (" .. bonusGrade .. "/10)"
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return "Loot bonus (" .. bonusGrade .. "/10)"
    elseif bonusType == PREY_BONUS_DAMAGE_BOOST then
        return "-"
    end
    return "Uknown bonus"
end

function bonusTypeTranslate(bonusType)
    return Tracker.Prey.bonusTypeTranslate(bonusType)
end

function bonusTypeTranslateText(bonusType, percent)
    return Tracker.Prey.bonusTypeTranslateText(bonusType, percent)
end

function timeleftTranslation(timeleft)
    return Tracker.Prey.timeleftTranslation(timeleft)
end

function init()
    connect(g_game, {
        onGameStart = check,
        onGameEnd = hide,
        onResourcesBalanceChange = onResourceBalance,
        onPreyFreeRolls = onPreyFreeRolls,
        onPreyTimeLeft = onPreyTimeLeft,
        onPreyRerollPrice = onPreyPrice,
        onPreyLocked = onPreyLocked,
        onPreyListSelection = onPreyWildcard,
        onPreyInactive = onPreyInactive,
        onPreyActive = onPreyActive,
        onPreySelection = onPreySelection,
        onPreySelectionChangeMonster = onPreySelection,
    })

    preyWindow = g_ui.displayUI('prey')
    UIModalOverlay.register(preyWindow) -- Gerenciamento automático de overlay
    preyWindow:hide()

    preyWindowButton = preyWindow:recursiveGetChildById("preyWindowButton")

    if g_game.isOnline() then
        check()
    end

    Keybind.new("Dialogs", "Open Prey Window", "Ctrl+Y", "")
    Keybind.bind("Dialogs", "Open Prey Window", {
        {
            type = KEY_DOWN,
            callback = function()
                if not preyWindow:isVisible() then
                    show()
                end
            end,
        }
    })
end

local descriptionTable = {
    ["shopPermButton"] =
    "Go to the Store to purchase the Permanent Prey Slot. Once you have completed the purchase, you can activate a prey here, no matter if your character is on a free or a Premium account.",
    ["preyWindow"] = "",
    ["noBonusIcon"] =
    "This prey is not available for your character yet.\nCheck the large blue button(s) to learn how to unlock this prey slot",
    ["selectPrey"] =
    "Click here to get a bonus with a higher value. The bonus for your prey will be selected randomly from one of the following: damage boost, damage reduction, bonus XP, improved loot. Your prey will be active for 2 hours hunting time again. Your prey creature will stay the same.",
    ["pickSpecificPrey"] =
    "If you like to select another prey creature, click here to choose from all available creatures.\nThe newly selected prey will be active for 2 hours hunting time again.",
    ["rerollButton"] =
    "If you like to select another prey crature, click here to get a new list with 9 creatures to choose from.\nThe newly selected prey will be active for 2 hours hunting time again.",
    ["rerollButtonBonus"] =
    "If you like to select another prey crature, click here to get a new list with 9 creatures to choose from.\nThe newly selected prey will be active for 2 hours hunting time again.",
    ["preyCandidate"] = "Select a new prey creature for the next 2 hours hunting time.",
    ["choosePreyButton"] =
    "Click on this button to confirm selected monsters as your prey creature for the next 2 hours hunting time.",
    ["choosePreyButtonBonus"] =
    "Click on this button to confirm %s as your prey creature for the next 2 hours hunting time. You will benefit from the following bonus: %s",
    ["selectionList"] =
    "Select a new prey creature for the next 2 hours hunting time. You will benefit from the following bonus:",
    ["rerollBonus"] =
    "Click here to get a bonus with a higher value. The bonus for your prey will be selected randomly from one of the following: damage boost, damage reduction, bonus XP, improved loot. Your prey will be active for 2 hours hunting time again. Your prey creature will stay the same.",
    ["autoRerollCheck"] =
    "If you tick this option, you will automatically roll for a new prey bonus whenever your prey is about to expire. This will also extend the hunting time of your active prey creature for another 2 hours.",
    ["lockPreyCheck"] =
    "If you tick this option, you will lock your prey creature and prey bonus. This means whenever your prey is about to expire its hunting time is simply extended by another 2 hours.",
    ["time"] = "You will get your next Free List Reroll in %s.\nYou get a Free List Reroll every 20 hours for each slot.",
    ["time_free"] = "Your next List Reroll is free of charge.\nYou get a Free List Reroll every 20 hours for each slot."
}

function onHover(widget)
    if type(widget) == "string" then
        return preyWindow.description:setText(descriptionTable[widget])
    elseif type(widget) == "number" then
        local preySlot = preyWindow["slot" .. (widget + 1)]
        local creatureAndBonus = preySlot.active.creatureAndBonus
        local preyName = preySlot.title:getText()
        local timeleft = timeleftTranslation(preySlot.timeLeft)
        local typeDesc = bonusTypeTranslate(preySlot.bonusType)
        local bonusDescription = bonusTypeTranslateText(preySlot.bonusType, preySlot.bonusValue)
        local starBonus = ""
        for i = 1, 10 do
            if i <= preySlot.bonusGrade then
                starBonus = starBonus .. "^"
            else
                starBonus = starBonus .. ";"
            end
        end

        local text = tr("Creature: %s\nDuration: %s\nValue: %s\nType: %s\n%s", preyName, timeleft, starBonus, typeDesc,
            bonusDescription)
        return preyWindow.description:setText(text)
    end

    if not widget:isVisible() then
        return false
    end

    local id = widget:getId()
    local desc = descriptionTable[id]
    if not desc then
        return
    end

    if id == "choosePreyButton" and widget:getActionId() > 0 then
        local preySlot = preyWindow["slot" .. widget:getActionId()]
        local bonusType = preySlot.bonusType
        local bonusValue = preySlot.bonusValue
        if bonusType and bonusType > 0 then
            -- wildcard
            if preySlot.wildcard:isVisible() and preySlot.wildcard.monsterList:getFocusedChild() then
                local name = preySlot.wildcard.monsterList:getFocusedChild():getText()
                local bonusDesc = tr("+%s%s %s", bonusValue, "%", getBonusDescription(bonusType))
                desc = tr(descriptionTable["choosePreyButtonBonus"], name, bonusDesc)
            elseif preySlot.select:isVisible() then
                local focusedChild = preySlot.select.list:getFocusedChild()
                if not focusedChild then
                    focusedChild = preySlot.select.list:getFirstChild()
                end
                if focusedChild then
                    local bonusDesc = tr("+%s%s %s", bonusValue, "%", getBonusDescription(bonusType))
                    desc = tr(descriptionTable["choosePreyButtonBonus"], focusedChild.creature:getTooltip(), bonusDesc)
                end
            end
        end
    elseif id == "time" then
        local widgetText = widget:getText()
        if widgetText == "Free" then
            desc = descriptionTable["time_free"]
        else
            desc = tr(desc, widget:getText())
        end
    end

    preyWindow.description:setText(desc)
end

function onSpecialHover(widget, bonusType, bonusValue)
    local message = descriptionTable[widget]
    if bonusType == nil or bonusValue == nil then
        return preyWindow.description:setText(message)
    end
    if widget == "selectionList" then
        if bonusType == PREY_BONUS_NONE then
            preyWindow.description:setText(descriptionTable["selectPrey"])
        else
            message = tr("%s +%s%s %s", message, bonusValue, "%", getBonusDescription(bonusType))
            preyWindow.description:setText(message)
        end
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = check,
        onGameEnd = hide,
        onResourcesBalanceChange = onResourceBalance,
        onPreyFreeRolls = onPreyFreeRolls,
        onPreyTimeLeft = onPreyTimeLeft,
        onPreyRerollPrice = onPreyPrice,
        onPreyLocked = onPreyLocked,
        onPreyListSelection = onPreyWildcard,
        onPreyInactive = onPreyInactive,
        onPreyActive = onPreyActive,
        onPreySelection = onPreySelection,
        onPreySelectionChangeMonster = onPreySelection,
    })

    Keybind.delete("Dialogs", "Open Prey Window")

    -- Destruir overlay modal
    UIModalOverlay.destroy(preyWindow)

    if preyButton then
        preyButton:destroy()
    end
    preyWindow:destroy()
    if supportWindow then
        supportWindow:destroy()
        supportWindow = nil
    end
end

function setUnsupportedSettings()
    local t = { "slot1", "slot2", "slot3" }
    for i, slot in pairs(t) do
        local panel = preyWindow[slot]
        for j, state in pairs({ panel.active, panel.inactive, panel.select }) do
            state.buttonsPanel.select.price.text:setText("5")
            state:recursiveGetChildById("pickSpecificPrey"):setOn(true)
            state.buttonsPanel.select.price.text:setColor("$var-text-cip-color")
            if bonusRerolls < 5 then
                state.buttonsPanel.select.price.text:setColor("$var-text-cip-store-red")
                state:recursiveGetChildById("pickSpecificPrey"):setOn(false)
            end

            state:recursiveGetChildById("pickSpecificPrey").onClick = function()
                if not state:recursiveGetChildById("pickSpecificPrey"):isOn() then
                    return
                end

                if bonusRerolls - 5 < 0 then
                    return
                end
                onConfirmUsingWildcard(i - 1, 5, PREY_ACTION_REQUEST_ALL_MONSTERS)
            end

            state.buttonsPanel.reroll.button.rerollButton:setOn(true)
            state.buttonsPanel.reroll.price.text:setColor("$var-text-cip-color")
            local progressBar = state.buttonsPanel.reroll.button.time
            if (bankGold + inventoryGold < rerollPrice and progressBar:getText() ~= "Free") then
                state.buttonsPanel.reroll.price.text:setColor("$var-text-cip-store-red")
                state.buttonsPanel.reroll.button.rerollButton:setOn(false)
            end
            -- hotfix
            progressBar:setPercent(progressBar:getPercent())
        end

        for k, state in pairs({ panel.active, panel.inactive }) do
            state.buttonsPanel.choose.price.text:setText("1")
            state.buttonsPanel.choose.price.text:setColor("$var-text-cip-color")
            state:recursiveGetChildById("rerollBonus"):setOn(true)
            state:recursiveGetChildById("rerollBonus").onClick = function()
                if not state:recursiveGetChildById("rerollBonus"):isOn() then
                    return
                end
                onConfirmUsingWildcard(i - 1, 1, PREY_ACTION_BONUSREROLL)
            end

            if bonusRerolls < 1 then
                state.buttonsPanel.choose.price.text:setColor("$var-text-cip-store-red")
                state:recursiveGetChildById("rerollBonus"):setOn(false)
            end

            state.buttonsPanel.autoRerollPrice.text:setText("1")
            state.buttonsPanel.autoRerollPrice.text:setColor("$var-text-cip-color")
            if bonusRerolls < 1 then
                state.buttonsPanel.autoRerollPrice.text:setColor("$var-text-cip-store-red")
            end

            state.buttonsPanel.lockPreyPrice.text:setText("5")
            state.buttonsPanel.lockPreyPrice.text:setColor("$var-text-cip-color")
            if bonusRerolls < 5 then
                state.buttonsPanel.lockPreyPrice.text:setColor("$var-text-cip-store-red")
            end

            state.buttonsPanel.autoReroll.autoRerollCheck.onClick = function()
                if state.buttonsPanel.autoReroll.autoRerollCheck:isChecked() then
                    g_game.preyAction(i - 1, PREY_ACTION_LOCK_PREY, 0)
                else
                    onEnableAutoReroll(i - 1)
                end
            end

            state.buttonsPanel.lockPrey.lockPreyCheck.onClick = function()
                if state.buttonsPanel.lockPrey.lockPreyCheck:isChecked() then
                    g_game.preyAction(i - 1, PREY_ACTION_LOCK_PREY, 0)
                else
                    onEnableLockPrey(i - 1)
                end
            end

            state.buttonsPanel.autoReroll.autoRerollCheck:setChecked(false)
            state.buttonsPanel.lockPrey.lockPreyCheck:setChecked(false)
            if panel.lockType == 1 then
                state.buttonsPanel.autoReroll.autoRerollCheck:setChecked(true)
            elseif panel.lockType == 2 then
                state.buttonsPanel.lockPrey.lockPreyCheck:setChecked(true)
            end
        end
    end
end

function check()
    if g_game.getFeature(GamePrey) then
        if not preyButton then
            preyButton = modules.game_mainpanel.addToggleButton('preyButton', tr('Prey Dialog'),
                '/images/options/button_preydialog', toggle, false, 8)
        end
    elseif preyButton then
        preyButton:destroy()
        preyButton = nil
    end
end

function toggleTracker()
    Tracker.Prey.toggle()
end

function hide(ignoreTracker)
    creatureList = nil
    preyWindow:hide() -- UIModalOverlay gerenciado automaticamente
    if not ignoreTracker then
        Tracker.Prey.hide()
    end
    -- g_client.setInputLockWidget(nil)
    preyWindowButton:setChecked(false)
    if preyButton then
        preyButton:setOn(false)
    end
    if supportWindow then
        supportWindow:destroy()
        supportWindow = nil
    end


    if updateRerollEvent then
        removeEvent(updateRerollEvent)
        updateRerollEvent = nil
    end
end

function show(position)
    if not g_game.getFeature(GamePrey) then
        return hide()
    end
    preyWindowButton:setChecked(true)
    if preyButton then
        preyButton:setOn(true)
    end
    setUnsupportedSettings()
    preyWindow:show(true) -- UIModalOverlay gerenciado automaticamente
    preyWindow:raise()
    preyWindow:focus()
    -- g_client.setInputLockWidget(preyWindow)
    if position ~= nil then
        preyWindow:setPosition(position)
    end

    if g_game and g_game.preyRequest then
        g_game.preyRequest()
    end

    local localPlayer = g_game.getLocalPlayer()
    onResourceBalance(localPlayer:getResourceBalance(ResourceTypes.BANK_BALANCE), nil, ResourceTypes.BANK_BALANCE)
    onResourceBalance(localPlayer:getResourceBalance(ResourceTypes.GOLD_EQUIPPED), nil, ResourceTypes.GOLD_EQUIPPED)
    onResourceBalance(localPlayer:getResourceBalance(ResourceTypes.PREY_WILDCARDS), nil, ResourceTypes.PREY_WILDCARDS)

    if creatureList == nil then
        -- creatureList = g_things.getMonsterList()
    end
    updateWildCardWindow()

    updateRerollEvent = cycleEvent(function() updateRerollTime() end, 1000)
end

function toggle()
    if preyWindow:isVisible() then
        return hide(true)
    end
    show()
end

function onPreyFreeRolls(slot, timeleft)
    local prey = preyWindow["slot" .. (slot + 1)]
    local percent = (timeleft / (20 * 60)) * 100
    local desc = timeleftTranslation(timeleft * 60)
    if not prey then return end
    for i, panel in pairs({ prey.active, prey.inactive }) do
        local progressBar = panel.reroll.button.time
        local price = panel.reroll.price.text
        progressBar:setText(desc)
        if timeleft == 0 then
            price:setText("Free")
        end
        progressBar:setPercent(percent)
    end
end

function onPreyTimeLeft(slot, timeLeft)
    -- description
    preyDescription[slot] = preyDescription[slot] or { one = "", two = "" }
    local text = preyDescription[slot].one .. timeleftTranslation(timeLeft) .. preyDescription[slot].two
    -- tracker
    Tracker.Prey.updateTimeLeft(slot, timeLeft)

    local percent = (timeLeft / (2 * 60 * 60)) * 100
    local slotId = "slot" .. (slot + 1)
    local preyTracker = Tracker.Prey.getWidget()
    local tracker = preyTracker.contentsPanel[slotId]
    for i, element in pairs({ tracker.creatureName, tracker.creature, tracker.preyType, tracker.time }) do
        element:setTooltip(text)
        element.onClick = function()
            show()
        end
    end
    -- main window
    local prey = preyWindow[slotId]
    if not prey then return end
    local progressbar = prey.active.creatureAndBonus.timeLeft
    local textLabel = prey.active.creatureAndBonus.textLabel
    local desc = timeleftTranslation(timeLeft, true)
    textLabel:setText(desc)
    progressbar:setPercent(percent)
end

function onPreyPrice(price, wildcard, directly)
    rerollPrice = price
    local t = { "slot1", "slot2", "slot3" }
    for i, slot in pairs(t) do
        local panel = preyWindow[slot]
        for j, state in pairs({ panel.active, panel.inactive, panel.select }) do
            local priceWidget = state.buttonsPanel.reroll.price.text
            local progressBar = state.buttonsPanel.reroll.button.time
            if progressBar:getText() ~= "Free" then
                local formatedPrice = price < 100000 and comma_value(price) or math.ceil(price / 1000) .. "  k"
                priceWidget:setText(formatedPrice)
                state.buttonsPanel.reroll.price.textOff:setVisible(false)
            else
                priceWidget:setText(0)
                state.buttonsPanel.reroll.price.textOff:setText(math.ceil(price / 1000) .. " k")
                state.buttonsPanel.reroll.price.textOff:setVisible(true)
                progressBar:setPercent(0)
            end
        end
    end

    setUnsupportedSettings()
end

function setTimeUntilFreeReroll(slot, timeUntilFreeReroll) -- minutes
    timeLeftRerrol[slot] = { minutesLeft = timeUntilFreeReroll, startTime = os.time() }

    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then return end
    local percent = (timeUntilFreeReroll / (20 * 60)) * 100
    local desc = timeleftTranslation(timeUntilFreeReroll)
    for i, panel in pairs({ prey.active, prey.inactive, prey.select }) do
        local reroll = panel.buttonsPanel.reroll.button.time
        reroll:setPercent(percent)
        reroll:setText(desc)
        local price = panel.buttonsPanel.reroll.price.text
        if timeUntilFreeReroll > 0 then
            local formatedPrice = rerollPrice < 100000 and comma_value(rerollPrice) or
                math.ceil(rerollPrice / 1000) .. "  k"
            price:setText(formatedPrice)
            panel.buttonsPanel.reroll.price.textOff:setVisible(false)
        else
            price:setText(0)
            panel.buttonsPanel.reroll.price.textOff:setText(math.ceil(rerollPrice / 1000) .. " k")
            panel.buttonsPanel.reroll.price.textOff:setVisible(true)
        end

        panel.buttonsPanel.reroll.button.rerollButton.onClick = function()
            if not panel.buttonsPanel.reroll.button.rerollButton:isOn() then
                return
            end
            onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
        end
    end
end

function setBonusGradeStars(slot, grade)
    local prey = preyWindow["slot" .. (slot + 1)]
    local gradePanel = prey.active.creatureAndBonus.bonus.grade

    gradePanel:destroyChildren()
    for i = 1, 10 do
        if i <= grade then
            local widget = g_ui.createWidget("Star", gradePanel)
            widget.onHoverChange = function(widget, hovered)
                onHover(slot)
            end
        else
            local widget = g_ui.createWidget("NoStar", gradePanel)
            widget.onHoverChange = function(widget, hovered)
                onHover(slot)
            end
        end
    end
end

function getBigIconPath(bonusType)
    local path = "/images/game/prey/"
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return path .. "prey_bigdamage"
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return path .. "prey_bigdefense"
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return path .. "prey_bigxp"
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return path .. "prey_bigloot"
    end
end

function getSmallIconPath(bonusType)
    return Tracker.Prey.getSmallIconPath(bonusType)
end

function getExtendIcon(lockType)
    return Tracker.Prey.getExtendIcon(lockType)
end

function getBonusDescription(bonusType)
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return "Damage Boost"
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return "Damage Reduction"
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return "XP Bonus"
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return "Improved Loot"
    end
    return "None"
end

function getTooltipBonusDescription(bonusType, bonusValue)
    if bonusType == PREY_BONUS_DAMAGE_BOOST then
        return "You deal +" .. bonusValue .. "% extra damage against your prey creature."
    elseif bonusType == PREY_BONUS_DAMAGE_REDUCTION then
        return "You take " .. bonusValue .. "% less damage from your prey creature."
    elseif bonusType == PREY_BONUS_XP_BONUS then
        return "Killing your prey creature rewards +" .. bonusValue .. "% extra XP."
    elseif bonusType == PREY_BONUS_IMPROVED_LOOT then
        return "Your creature has a +" .. bonusValue .. "% chance to drop additional loot."
    end
end

function capitalFormatStr(str)
    local formatted = ""
    str = string.split(str, " ")
    for i, word in ipairs(str) do
        formatted = formatted .. " " .. (string.gsub(word, "^%l", string.upper))
    end
    return formatted:trim()
end

function onItemBoxChecked(widget, lastWidget, slot)
    if not widget then
        return
    end

    if lastWidget and lastWidget.highlight then
        lastWidget.highlight:setBackgroundColor("alpha")
        lastWidget:setBorderWidth(0)
        lastWidget:setBorderColor("alpha")
    end

    if widget.creature then
        local name = tr("Selected: %s", widget.creature:getTooltip())
        preyWindow["slot" .. slot].title:setText(short_text(name, 28))
        preyWindow["slot" .. slot].select:recursiveGetChildById('choosePreyButton'):setOn(true)
        preyWindow["slot" .. slot].select:recursiveGetChildById('choosePreyButton'):setActionId(slot)
    end

    if widget.highlight then
        widget.highlight:setBackgroundColor("white")
        widget:setChecked(true)
    end

    widget:setBorderWidth(1)
    widget:setBorderColor("white")
end

function onResourceBalance(balance, oldBalance, resourceType)
    if resourceType == ResourceTypes.BANK_BALANCE then       -- bank gold
        bankGold = balance
    elseif resourceType == ResourceTypes.GOLD_EQUIPPED then  -- inventory gold
        inventoryGold = balance
    elseif resourceType == ResourceTypes.PREY_WILDCARDS then -- bonus rerolls
        bonusRerolls = balance
        preyWindow.wildCards.text:setText(bonusRerolls)
    end

    setUnsupportedSettings()
    if resourceType == ResourceTypes.BANK_BALANCE or resourceType == ResourceTypes.GOLD_EQUIPPED then
        preyWindow.gold.text:setText(comma_value(bankGold + inventoryGold))
    end
end

-- Handler de clique direto no WildcardLabel
function onWildcardLabelClick(prey, widget, slot)
    local raceId = tonumber(widget:getId())

    if not raceId then
        return
    end

    -- Desmarca o anterior
    if lastSelectedLabel[slot] then
        lastSelectedLabel[slot]:setBackgroundColor(lastSelectedLabel[slot].background)
        lastSelectedLabel[slot]:setColor("$var-text-cip-color")
    end

    -- Marca o novo
    widget:setBackgroundColor("$var-textlist-selected")
    widget:setColor("$var-text-cip-color-highlight")
    lastSelectedLabel[slot] = widget
    selectedMonster[slot] = raceId

    -- Atualiza o botão de escolha
    prey.wildcard.choose.button.choosePreyButton:setOn(true)
    prey.wildcard.choose.button.choosePreyButton:setActionId(tonumber(string.match(prey:getId(), "%d+$")) or 0)

    -- Atualiza o título e a criatura
    local creature = g_things.getRaceData(raceId)
    if creature then
        prey.title:setText("Selected: " .. short_text(creature.name, 18))
        prey.wildcard.panel.creature:setOutfit(creature.outfit)
    end
end

function onWildcardChange(prey, selected, lastSelected, slot)
    if not prey then return end

    if not selected then
        prey.wildcard.choose.button.choosePreyButton:setOn(false)
        prey.wildcard.choose.button.choosePreyButton:setActionId(0)
        lastSelectedLabel[slot] = nil
        selectedMonster[slot] = nil
        prey.title:setText("Select your prey creature")
        prey.wildcard.panel.creature:setOutfit({})
        return
    end

    -- Verifica se o widget já tem um raceId válido definido
    local selectedId = selected:getId()
    local raceId = tonumber(selectedId)

    -- Se o selected é o próprio monsterList, ignora
    if selectedId == "monsterList" then
        return
    end

    if not raceId then
        return
    end

    prey.wildcard.choose.button.choosePreyButton:setOn(true)
    prey.wildcard.choose.button.choosePreyButton:setActionId(tonumber(string.match(prey:getId(), "%d+$")) or 0)
    selected:setBackgroundColor("$var-textlist-selected")
    if lastSelected then
        lastSelected:setBackgroundColor(lastSelected.background)
    end

    if lastSelectedLabel[slot] then
        lastSelectedLabel[slot]:setBackgroundColor(lastSelectedLabel[slot].background)
        lastSelectedLabel[slot]:setColor("$var-text-cip-color")
    end

    lastSelectedLabel[slot] = selected
    selectedMonster[slot] = raceId
    local creature = g_things.getRaceData(selectedMonster[slot])
    if not creature then return end
    prey.title:setText("Selected: " .. short_text(creature.name, 18))
    prey.wildcard.panel.creature:setOutfit({
        type = creature[2],
        auxType = creature[3],
        head = creature[4],
        body =
            creature[5],
        legs = creature[6],
        feet = creature[7],
        addons = creature[8]
    })
end

function onTextEdit(widget)
    searchFilterText = widget:getText()
    updateSearchWildcard(widget:getParent():getParent())
end

function move(panel, height, minimized)
    return Tracker.Prey.move(panel, height, minimized)
end

function updatePreyWidget(slot, state, currentHolderOutfit)
    local preySlot = preyWindow["slot" .. (slot + 1)]
    Tracker.Prey.updateWidget(slot, state, currentHolderOutfit, preySlot, show)
end

function onRerollButtonAction(slot, freeReroll)
    if supportWindow then
        return
    end

    -- g_client.setInputLockWidget(nil)
    local okFunc = function()
        g_game.preyAction(slot, PREY_ACTION_LISTREROLL, 0)
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local cancelFunc = function()
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local confirmText = "Are you sure you want to use the Free List Reroll?"
    if not freeReroll then
        confirmText = tr(
            "Do you want to spend %s gold for a List Reroll?\nYou currently have %s gold available for the purchase.",
            comma_value(rerollPrice), (comma_value(bankGold + inventoryGold)))
    end

    supportWindow = displayGeneralBox(tr("Confirm of Using List Reroll"), confirmText,
        { { text = tr('Yes'), callback = okFunc },
            { text = tr('No'),  callback = cancelFunc }
        }, okFunc, cancelFunc, preyWindow)
end

function onConfirmUsingWildcard(slot, price, action)
    if supportWindow then
        return
    end

    -- g_client.setInputLockWidget(nil)
    local okFunc = function()
        g_game.preyAction(slot, action, 0)
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local cancelFunc = function()
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local confirmText = tr("Are you sure you want to use %s of your remaining %s Prey Wildcards?", price, bonusRerolls)
    supportWindow = displayGeneralBox(tr("Confirmation of Using Prey Wildcards"), confirmText,
        { { text = tr('Yes'), callback = okFunc },
            { text = tr('No'),  callback = cancelFunc }
        }, okFunc, cancelFunc, preyWindow)
end

function onEnableAutoReroll(slot)
    if supportWindow then
        return
    end

    -- g_client.setInputLockWidget(nil)
    local okFunc = function()
        g_game.preyAction(slot, PREY_ACTION_LOCK_PREY, 1)
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local cancelFunc = function()
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local confirmText = tr(
        "Do you want to enable the Automatic Bonus Reroll?\nEach time the Automatic Bonus Reroll is triggered, 1 of your Prey Wildcards will be consumed.")
    supportWindow = displayGeneralBox(tr("Confirmation of Using Prey Wildcards"), confirmText,
        { { text = tr('Yes'), callback = okFunc },
            { text = tr('No'),  callback = cancelFunc }
        }, okFunc, cancelFunc, preyWindow)
end

function onEnableLockPrey(slot)
    if supportWindow then
        return
    end

    -- g_client.setInputLockWidget(nil)
    local okFunc = function()
        g_game.preyAction(slot, PREY_ACTION_LOCK_PREY, 2)
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local cancelFunc = function()
        supportWindow:destroy()
        supportWindow = nil
        -- g_client.setInputLockWidget(preyWindow)
    end

    local confirmText = tr(
        "Do you want to enable the Lock Prey?\nEach time the Lock Prey is triggered, 5 of your Prey Wildcards will be consumed.")
    supportWindow = displayGeneralBox(tr("Confirmation of Using Prey Wildcards"), confirmText,
        { { text = tr('Yes'), callback = okFunc },
            { text = tr('No'),  callback = cancelFunc }
        }, okFunc, cancelFunc, preyWindow)
end

function onPreyActive(slot, currentHolderName, currentHolderOutfit, bonusType, bonusValue, bonusGrade, timeLeft,
                      timeUntilFreeReroll, wildcards, lockType)
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then
        return
    end

    timeUntilFreeReroll = timeUntilFreeReroll > 72000 and 0 or timeUntilFreeReroll

    local percent = (timeLeft / (2 * 60 * 60)) * 100
    prey.inactive:hide()
    prey.locked:hide()
    prey.wildcard:hide()
    prey.select:hide()
    prey.active:show()
    prey.title:setText(capitalFormatStr(currentHolderName))
    local creatureAndBonus = prey.active.creatureAndBonus
    creatureAndBonus.creature:setOutfit(currentHolderOutfit)
    setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
    creatureAndBonus.bonus.icon:setImageSource(getBigIconPath(bonusType))

    creatureAndBonus.bonus.icon.onHoverChange = function(widget, hovered)
        onHover(slot)
    end

    creatureAndBonus.creature.onHoverChange = function(widget, hovered)
        onHover(slot)
    end

    creatureAndBonus.panel.onHoverChange = function(widget, hovered)
        onHover(slot)
    end

    setBonusGradeStars(slot, bonusGrade)
    creatureAndBonus.timeLeft:setPercent(percent)
    creatureAndBonus.textLabel:setText(timeleftTranslation(timeLeft))

    prey.active.buttonsPanel.reroll.button.rerollButton.onClick = function()
        if not prey.active.buttonsPanel.reroll.button.rerollButton:isOn() then
            return
        end
        onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
    end

    prey.bonusType = bonusType
    prey.bonusValue = bonusValue
    prey.bonusGrade = bonusGrade
    prey.lockType = lockType
    prey.timeLeft = timeLeft
    setUnsupportedSettings()
    updatePreyWidget(slot, SLOT_STATE_ACTIVE, currentHolderOutfit)
end

-- (slot, names, outfits, timeUntilFreeReroll, wildcards)
function onPreySelection(slot, names, outfits, a, b, c, d, e)
    -- Compatibilidade: aceita formato antigo e novo
    local bonusType, bonusValue, bonusGrade, timeUntilFreeReroll, lockType
    -- onPreySelectionChangeMonster
    if type(a) == "number" and type(b) == "number" and type(c) == "number" then
        bonusType, bonusValue, bonusGrade, timeUntilFreeReroll, lockType = a, b, c, d, e
    else
        timeUntilFreeReroll, lockType = a, b
        bonusType, bonusValue, bonusGrade = 0, 0, 0
    end
    -- Protege contra nil
    bonusType = bonusType or 0
    bonusValue = bonusValue or 0
    bonusGrade = bonusGrade or 0
    timeUntilFreeReroll = timeUntilFreeReroll or 0
    lockType = lockType or 0
    timeUntilFreeReroll = timeUntilFreeReroll > 72000 and 0 or timeUntilFreeReroll
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then
        return
    end

    prey.active:hide()
    prey.locked:hide()
    prey.wildcard:hide()
    prey.inactive:hide()
    prey.select:show()
    prey.title:setText(tr("Select your prey creature"))

    local list = prey.select.list
    list:destroyChildren()

    prey.select.buttonsPanel.choose.button.choosePreyButton:setOn(false)
    prey.select.buttonsPanel.choose.button.choosePreyButton:setActionId(slot + 1)

    -- Build items array with name+outfit pairs
    local selectionItems = {}
    for i, name in ipairs(names) do
        table.insert(selectionItems, { name = name, outfit = outfits[i] })
    end

    BatchLoader.create({
        container = list,
        items = selectionItems,
        createWidget = function(item, i)
            local box = g_ui.createWidget("PreyCreatureBox", list)
            box.onHoverChange = function(box, hovered) onSpecialHover("selectionList", bonusType, bonusValue) end
            local formattedName = capitalFormatStr(item.name)
            box.creature:setTooltip(formattedName)
            box.creature:setOutfit(item.outfit)
            if i == 1 then
                onItemBoxChecked(box, nil, slot + 1)
            end
        end
    })

    list.onChildFocusChange = function(list, selected, lastSelected)
        if not lastSelected then
            lastSelected = list:getFirstChild()
        end
        onItemBoxChecked(selected, lastSelected, slot + 1)
    end

    prey.select.buttonsPanel.choose.button.choosePreyButton.onClick = function()
        if not prey.select.buttonsPanel.choose.button.choosePreyButton:isOn() then
            return true
        end

        g_game.preyAction(slot, PREY_ACTION_MONSTERSELECTION, list:getChildIndex(list:getFocusedChild()) - 1)
    end

    prey.select.buttonsPanel.reroll.button.rerollButton.onClick = function()
        if not prey.select.buttonsPanel.reroll.button.rerollButton:isOn() then
            return
        end
        onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
    end

    prey.lockType = lockType
    prey.bonusType = bonusType
    prey.bonusValue = bonusValue
    setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
    setUnsupportedSettings()
    updatePreyWidget(slot, SLOT_STATE_SELECTION)
end

function updateSearchWildcard(prey)
    prey.wildcard.monsterList:focusChild(nil)
    if searchFilterText == '' then
        updateWildCardWindow()
        return
    end

    local slot = tonumber(prey:getId():match("%d+")) - 1
    currentSearchRaces[slot] = {}
    for _, raceId in pairs(currentRaces[slot]) do
        local creature = g_things.getRaceData(raceId)
        local searchFilterTextEscaped = string.searchEscape(searchFilterText:lower())
        if string.find(creature.name:lower(), searchFilterTextEscaped) then
            table.insert(currentSearchRaces[slot], raceId)
        end
    end

    for i, monsterLabel in ipairs(itemsPool[slot]) do
        if i > #currentSearchRaces[slot] then
            monsterLabel:setBackgroundColor("alpha")
            monsterLabel:setText('')
            monsterLabel.icon:setVisible(false)
            monsterLabel:setFocusable(false)
            goto continue
        end

        local monsterInfo = currentSearchRaces[slot][i]
        local color = ((i % 2 == 0) and '$var-textlist-odd' or '$var-textlist-even')
        monsterLabel:setFocusable(true)
        monsterLabel:setBackgroundColor(color)
        monsterLabel.background = color
        monsterLabel:setId(tostring(monsterInfo))
        monsterLabel:setColor('$var-text-cip-color')
        local creature = g_things.getRaceData(monsterInfo)
        if creature then
            monsterLabel:setText(string.capitalize(creature.name))
        end

        monsterLabel.icon:setVisible(false)
        monsterLabel:setTextOffset("0 0")
        :: continue ::
    end

    local scrollbar = prey.wildcard:recursiveGetChildById('monsterListScrollBar')
    scrollbar:setMinimum(itemListMin[slot])
    scrollbar:setMaximum(#currentSearchRaces[slot])
    scrollbar.onValueChange = function(self, value, delta) onSearchValueChange(self, value, delta, slot) end
end

function onSearchValueChange(scrollbar, value, delta, slot)
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then return end
    local startItem = math.max(itemListMin[slot], value)
    local endItem = startItem + maxFitItems[slot] - 1

    if endItem > #currentSearchRaces[slot] then
        endItem = #currentSearchRaces[slot]
        startItem = endItem - maxFitItems[slot] + 1
    end

    for i, monsterLabel in ipairs(itemsPool[slot]) do
        local itemId = value > 0 and (startItem + i - 1) or (startItem + i)
        local monsterInfo = currentSearchRaces[slot][itemId]

        local color = ((itemId % 2 == 0) and '$var-textlist-odd' or '$var-textlist-even')
        monsterLabel:setBackgroundColor(color)
        monsterLabel.background = color
        monsterLabel:setId(tostring(monsterInfo))
        monsterLabel:setColor('$var-text-cip-color')
        local creature = g_things.getRaceData(monsterInfo)
        if not creature then
            goto continue
        end

        if creature then
            monsterLabel:setText(string.capitalize(creature.name))
        end

        if selectedMonster[slot] == monsterInfo then
            prey.wildcard.monsterList:focusChild(monsterLabel)
            monsterLabel:setBackgroundColor('$var-textlist-selected')
            monsterLabel:setColor('$var-text-cip-color-highlight')
            lastSelectedLabel[slot] = monsterLabel
        end

        monsterLabel.icon:setVisible(false)
        monsterLabel:setTextOffset("0 0")
        :: continue ::
    end
end

function onWildcardValueChange(scrollbar, value, delta, slot)
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then return end
    local startItem = math.max(itemListMin[slot], value)
    local endItem = startItem + maxFitItems[slot] - 1

    if endItem > itemListMax[slot] then
        endItem = itemListMax[slot]
        startItem = endItem - maxFitItems[slot] + 1
    end

    for i, monsterLabel in ipairs(itemsPool[slot]) do
        local itemId = value > 0 and (startItem + i - 1) or (startItem + i)
        local monsterInfo = currentRaces[slot][itemId]

        local color = ((itemId % 2 == 0) and '$var-textlist-odd' or '$var-textlist-even')
        monsterLabel:setBackgroundColor(color)
        monsterLabel.background = color
        monsterLabel:setId(tostring(monsterInfo))
        monsterLabel:setColor('$var-text-cip-color')
        local creature = g_things.getRaceData(monsterInfo)
        if creature then
            monsterLabel:setText(string.capitalize(creature.name))
        end

        if selectedMonster[slot] == monsterInfo then
            prey.wildcard.monsterList:focusChild(monsterLabel)
            monsterLabel:setBackgroundColor('$var-textlist-selected')
            monsterLabel:setColor('$var-text-cip-color-highlight')
            lastSelectedLabel[slot] = monsterLabel
        end

        monsterLabel.icon:setVisible(false)
        monsterLabel:setTextOffset("0 0")
    end
end

function updateWildCardWindow(forceSlot)
    for i = 0, 2 do
        local prey = preyWindow["slot" .. i + 1]

        -- Pula se não tem prey, ou se não é visível E não é o slot forçado
        if not prey or (not prey.wildcard:isVisible() and forceSlot ~= i) then
            goto continue
        end

        -- Também pula se não tem dados configurados
        if not poolSize[i] or not currentRaces[i] then
            goto continue
        end

        table.sort(currentRaces[i], function(a, b)
            local creatureA = g_things.getRaceData(a)
            local creatureB = g_things.getRaceData(b)
            return creatureA.name < creatureB.name
        end)

        itemsPool[i] = {}
        prey.wildcard.monsterList:destroyChildren()

        -- Build items list for batch loading
        local wildcardItems = {}
        for k = 1, poolSize[i] do
            local monsterInfo = currentRaces[i][k]
            if monsterInfo == nil then
                break
            end
            table.insert(wildcardItems, monsterInfo)
        end

        local slotIndex = i
        BatchLoader.create({
            container = prey.wildcard.monsterList,
            items = wildcardItems,
            createWidget = function(monsterInfo, idx)
                local monster = g_ui.createWidget("WildcardLabel", prey.wildcard.monsterList)
                monster:setId(tostring(monsterInfo))
                monster:setActionId(slotIndex + 1)
                monster:setTextAlign(AlignLeft)
                monster:setFocusable(true)
                local color = ((idx % 2 == 0) and '$var-textlist-odd' or '$var-textlist-even')
                monster:setBackgroundColor(color)
                monster.background = color
                local creature = g_things.getRaceData(monsterInfo)
                if creature then
                    monster:setText(string.capitalize(creature.name))
                end
                local isInHunting = false
                monster.icon:setVisible(isInHunting)
                monster:setTextOffset(isInHunting and "21 0" or "0 0")
                monster.onHoverChange = function(monster, hovered) onSpecialHover("selectionList", bonusType, bonusValue) end

                monster.onClick = function(self)
                    onWildcardLabelClick(prey, self, slotIndex)
                end

                table.insert(itemsPool[slotIndex], monster)
            end,
            onFinish = function()
                prey.wildcard:recursiveGetChildById('monsterListScrollBar'):setValue(0)
                maxFitItems[slotIndex] = math.floor(prey.wildcard.monsterList:getHeight() / itemSize[slotIndex])
                local scrollbar = prey.wildcard:recursiveGetChildById('monsterListScrollBar')
                scrollbar:setMinimum(itemListMin[slotIndex])
                scrollbar:setMaximum(itemListMax[slotIndex] - maxFitItems[slotIndex])
                scrollbar.onValueChange = function(self, value, delta) onWildcardValueChange(self, value, delta, slotIndex) end

                local function handleMouseWheel(widget, mousePos, direction)
                    local currentValue = scrollbar:getValue()
                    local newValue = currentValue - direction
                    newValue = math.max(scrollbar:getMinimum(), math.min(scrollbar:getMaximum(), newValue))
                    if newValue ~= currentValue then
                        scrollbar:setValue(newValue)
                    end
                    return true
                end

                for _, monster in ipairs(itemsPool[slotIndex]) do
                    monster.onMouseWheel = handleMouseWheel
                end

                prey.wildcard.monsterList.onMouseWheel = handleMouseWheel
            end
        })
        :: continue ::
    end
end

function onPreyWildcard(slot, races, timeUntilFreeReroll, lockType, bonusType, bonusValue, bonusGrade)
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then
        return
    end

    itemListMin[slot] = 0
    itemListMax[slot] = #races
    currentRaces[slot] = races
    currentSearchRaces[slot] = {}
    itemSize[slot] = WILDCARD_LABEL_HEIGHT
    maxFitItems[slot] = 0
    poolSize[slot] = WILDCARD_VISIBLE_LABELS
    itemsPool[slot] = {}

    prey.title:setText("Select your prey creature")
    prey.inactive:hide()
    prey.active:hide()
    prey.locked:hide()
    prey.select:hide()
    prey.wildcard:show()

    prey.wildcard.monsterList:focusChild(nil)
    prey.wildcard.monsterList:destroyChildren()

    prey.wildcard:recursiveGetChildById("searchText"):clearText(true)

    local preyPanel = prey.wildcard.panel
    preyPanel.onHoverChange = function(preyPanel, hovered) onSpecialHover("selectionList", bonusType, bonusValue) end

    monsterList = prey.wildcard.monsterList
    prey.wildcard.choose.button.choosePreyButton:setActionId(slot + 1)
    prey.wildcard.choose.button.choosePreyButton.onClick = function()
        return g_game.preyAction(slot, 4, selectedMonster[slot])
    end

    prey.lockType = lockType
    prey.bonusValue = bonusValue
    prey.bonusType = bonusType
    setUnsupportedSettings()
    updatePreyWidget(slot, SLOT_STATE_WILDCARD)
    updateWildCardWindow(slot) -- Passa o slot para forçar a atualização mesmo se isVisible() retornar false

    -- Não precisamos mais do onChildFocusChange, usamos onClick diretamente nos WildcardLabels
end

function onPreyLocked(slot)
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then
        return
    end

    prey.title:setText("Locked")
    prey.inactive:hide()
    prey.active:hide()
    prey.select:hide()
    prey.locked:show()
    setUnsupportedSettings()
    updatePreyWidget(slot, SLOT_STATE_LOCKED)
end

function onPreyInactive(slot, timeUntilFreeReroll, lockType)
    local prey = preyWindow["slot" .. (slot + 1)]
    if not prey then
        return
    end

    prey.title:setText("Inactive")
    setTimeUntilFreeReroll(slot, timeUntilFreeReroll)
    prey.active:hide()
    prey.locked:hide()
    prey.wildcard:hide()
    prey.select:hide()
    prey.inactive:show()

    prey.inactive.buttonsPanel.reroll.button.rerollButton.onClick = function()
        if not prey.inactive.buttonsPanel.reroll.button.rerollButton:isOn() then
            return
        end
        onRerollButtonAction(slot, timeUntilFreeReroll <= 0)
    end

    setUnsupportedSettings()
    prey.lockType = lockType
    updatePreyWidget(slot, SLOT_STATE_INACTIVE)
end

function focusPrevWildcardLabel(list)
    local c = list:getFocusedChild()
    if not c then return end
    local cIndex = list:getChildIndex(c)

    if cIndex > 1 then
        list:focusPreviousChild(KeyboardFocusReason)
    else
        local scrollbar = list:getParent():recursiveGetChildById('monsterListScrollBar')
        scrollbar:setValue(scrollbar:getValue() - 1)
        if cIndex == 1 then
            list:focusPreviousChild(KeyboardFocusReason)
        end
    end
end

function focusNextWildcardLabel(list)
    local c = list:getFocusedChild()
    local cIndex = list:getChildIndex(c)
    local cCount = list:getChildCount()
    if cIndex < cCount then
        list:focusNextChild(KeyboardFocusReason)
    else
        local scrollbar = list:getParent():recursiveGetChildById('monsterListScrollBar')
        scrollbar:setValue(scrollbar:getValue() + 1)
        if cIndex == cCount then
            list:focusNextChild(KeyboardFocusReason)
        end
    end
end

function updateRerollTime()
    if not g_game.isOnline() or not preyWindow:isVisible() then
        removeEvent(updateRerollEvent)
        updateRerollEvent = nil
        return
    end

    for slot, data in pairs(timeLeftRerrol) do
        local startTime = data.startTime
        local currentTime = os.time()
        local elapsedTime = currentTime - startTime
        local elapsedMinutes = math.round(elapsedTime / 60)
        if elapsedMinutes > 0 then
            setTimeUntilFreeReroll(slot, math.max(0, data.minutesLeft - elapsedMinutes))
        end
    end
end
