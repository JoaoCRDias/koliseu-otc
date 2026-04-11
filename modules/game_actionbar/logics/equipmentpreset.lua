local presetWindow = nil
local selectIconWindow = nil
local radioIconGroup = nil
local currentButton = nil

PresetSlotStyles = {
    [InventorySlotHead] = "Slot1",
    [InventorySlotNeck] = "Slot2",
    [InventorySlotBack] = "Slot3",
    [InventorySlotBody] = "Slot4",
    [InventorySlotRight] = "Slot5",
    [InventorySlotLeft] = "Slot6",
    [InventorySlotLeg] = "Slot7",
    [InventorySlotFeet] = "Slot8",
    [InventorySlotFinger] = "Slot9",
    [InventorySlotAmmo] = "Slot10"
}

local function slotDataDefault()
    return { itemId = 0, tier = 0, identifier = "", smartMode = false }
end

local DynamicItems = {
    [3086] = 3049, [3087] = 3050, [3088] = 3051, [3089] = 3052,
    [3090] = 3053, [3094] = 3091, [3095] = 3092, [3096] = 3093,
    [3099] = 3097, [3100] = 3098, [3549] = 6529, [6300] = 6299,
    [9018] = 9019, [9392] = 9393, [16264] = 16114, [22134] = 22061,
    [23476] = 23477, [23530] = 23529, [23532] = 23531, [23534] = 23533,
    [23526] = 23542, [23527] = 23543, [23528] = 23544, [30343] = 30342,
    [30345] = 30344, [30402] = 30403, [31616] = 31557, [32635] = 32621,
    [39178] = 39177, [39181] = 39180, [39184] = 39183, [39187] = 39186,
    [39234] = 39233, [50148] = 50147, [50151] = 50150, [50153] = 50152,
    [50155] = 50154, [23475] = 23474
}

local function getCurrentItemId(itemPtr)
    if not itemPtr then
        return 0
    end
    local inventoryItemId = itemPtr:getId()
    if DynamicItems[inventoryItemId] then
        inventoryItemId = DynamicItems[inventoryItemId]
    end
    return inventoryItemId
end

--- Aplica o preset na ordem dos slots (par itemId, tier). Envia um equip por vez (protocolo padrão).
function executeEquipmentPreset(itemData)
    if not itemData or #itemData == 0 then
        return
    end
    for i = 1, #itemData, 2 do
        local itemId = tonumber(itemData[i]) or 0
        local tier = tonumber(itemData[i + 1]) or 0
        if itemId > 0 then
            g_game.equipItemId(itemId, tier)
        end
    end
end

function isPresetWindowVisible()
    return presetWindow and presetWindow:isVisible()
end

function closePresetWindow()
    if presetWindow then
        presetWindow:hide()
        presetWindow:destroy()
        presetWindow = nil
    end
end

function assignEquipment(button)
    if presetWindow then
        presetWindow:destroy()
    end

    presetWindow = g_ui.loadUI('/modules/game_actionbar/otui/equippreset', g_ui.getRootWidget())
    presetWindow:show()
    presetWindow:raise()

    scheduleEvent(function()
        presetWindow:focus()
    end, 50)

    currentButton = button
    if not button.cache.equipmentPreset then
        button.cache.equipmentPreset = {}
    end

    local playerInv = g_game.getLocalPlayer()
    local backpackItem = playerInv and playerInv:getInventoryItem(InventorySlotBack)
    local presetBackpack = presetWindow.contentPanel:recursiveGetChildById("equipSlot3")
    local backpackId = backpackItem and backpackItem:getId() or 0
    presetBackpack:setItemId(backpackId)
    presetBackpack:setStyle(backpackId > 0 and 'PresetEmptyItem' or PresetSlotStyles[3])

    for k, v in pairs(button.cache.equipmentPreset) do
        local widget = presetWindow:recursiveGetChildById(k)
        if widget then
            local slot = tonumber(string.match(k, "%d+"))
            local itemId = tonumber(v.itemId) or 0
            local tier = tonumber(v.tier) or 0
            if itemId > 0 then
                local presetItem = Item.create(itemId)
                presetItem:setTier(tier)
                widget:setStyle('PresetEmptyItem')
                widget:setItem(presetItem)
                ItemsDatabase.setTier(widget, tier)
            else
                widget:setItemId(0)
                if slot then
                    widget:setStyle(PresetSlotStyles[slot])
                end
            end
        end
    end

    local iconSource = presetWindow:recursiveGetChildById("imageContainer")
    local currentIcon = button.cache.equipmentPresetIcon
    if currentIcon and not string.empty(currentIcon) then
        iconSource:setImageSource("/images/game/actionbar/equip-preset/" .. currentIcon)
    end

    presetWindow.contentPanel.apply:setEnabled(currentIcon and not string.empty(currentIcon))
    presetWindow.contentPanel.missingIcon:setVisible(not currentIcon or string.empty(currentIcon))

    presetWindow.contentPanel.apply.onClick = function()
        iconSource = presetWindow:recursiveGetChildById("imageContainer")
        local filename = string.match(iconSource:getImageSource(), "([^/]+)$")

        local equippedCount = 0
        for _, slotId in pairs(EquipmentPresetSlots) do
            local w = presetWindow:recursiveGetChildById(string.format("equipSlot%d", slotId))
            local item = w and w:getItem() or nil
            if w then
                local slotKey = w:getId()
                if not button.cache.equipmentPreset[slotKey] then
                    button.cache.equipmentPreset[slotKey] = slotDataDefault()
                end
                local itemId = item and item:getId() or 0
                local itemTier = item and item:getTier() or 0
                local itemHash = item and "" or ""
                button.cache.equipmentPreset[slotKey].itemId = itemId
                button.cache.equipmentPreset[slotKey].tier = itemTier
                button.cache.equipmentPreset[slotKey].identifier = itemHash
                if itemId > 0 then
                    equippedCount = equippedCount + 1
                end
            end
        end

        if equippedCount == 0 then
            button.cache.equipmentPreset = {}
            button.cache.equipmentPresetIcon = ""
            local barID0, buttonID0 = string.match(button:getId(), "(.*)%.(.*)")
            ApiJson.removeAction(tonumber(barID0), tonumber(buttonID0))
            updateButton(button)
            presetWindow:hide()
            presetWindow:destroy()
            presetWindow = nil
            return true
        end

        local barID, buttonID = string.match(button:getId(), "(.*)%.(.*)")
        ApiJson.createOrUpdatePreset(tonumber(barID), tonumber(buttonID), button.cache.equipmentPreset, filename)
        updateButton(button)

        presetWindow:hide()
        presetWindow:destroy()
        presetWindow = nil
    end

    presetWindow.contentPanel.close.onClick = function()
        presetWindow:hide()
        presetWindow:destroy()
        presetWindow = nil
    end
end

function assignItemPreset(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton and widget:getItemId() == 0 then
        selectPresetItem(widget)
        return
    end

    if mouseButton ~= MouseRightButton then
        return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    if widget:getItemId() == 0 then
        menu:addOption(tr('Select Item'), function() selectPresetItem(widget) end)
    else
        menu:addOption(tr('Edit Item'), function() selectPresetItem(widget) end)
        if DynamicItems[widget:getItemId()] then
            menu:addCheckBoxOption(tr('Smart Mode'), function() onEditSmartMode(widget) end, nil, smartModeEnabled(widget))
        end
        menu:addOption(tr('Remove Item'), function() onRemovePresetItem(widget) end)
    end

    menu:display(mousePos)
end

local function restoreGrabberCursor()
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.restoreMouseCursor()
    else
        g_mouse.popCursor('target')
    end
end

function selectPresetItem(widget)
    local grabber = modules.game_actionbar.getGrabberWidget()
    grabber:grabMouse()
    if modules.client_options and modules.client_options.getOption('nativeCursor') then
        g_window.setSystemCursor('cross')
    else
        g_mouse.pushCursor('target')
    end
    grabber.onMouseRelease = function(self, mousePosition, mouseButton) onSelectPresetItem(self, mousePosition, mouseButton, widget) end
end

function onSelectPresetItem(self, mousePosition, mouseButton, widget)
    local grabber = modules.game_actionbar.getGrabberWidget()
    local rootPanel = modules.game_actionbar.getRootPanel()

    grabber:ungrabMouse()
    restoreGrabberCursor()
    grabber.onMouseRelease = modules.game_actionbar.onDropActionButton

    local clickedWidget = rootPanel:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then
        return true
    end

    local item = nil
    if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() and clickedWidget:getItem() then
        item = clickedWidget:getItem()
    elseif clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            item = tile:getTopUseThing()
        end
    end

    if not item then
        return
    end

    if not item:isPickupable() then
        modules.game_textmessage.displayFailureMessage('This item can\'t be assigned to this slot.')
        return true
    end

    local slot = tonumber(string.match(widget:getId(), "%d+"))
    local canEquip, message = isValidEquipSlot(item, slot)
    if not canEquip then
        modules.game_textmessage.displayFailureMessage(message)
        return
    end

    local newItemId = getCurrentItemId(item)
    if newItemId == 0 then
        return
    end

    local newItem = Item.create(newItemId)
    newItem:setTier(item:getTier())

    widget:setStyle('PresetEmptyItem')
    widget:setItem(newItem)
    ItemsDatabase.setTier(widget, item:getTier())
end

function onDropPresetItem(widget, item)
    local slotId = tonumber(widget:getId():match("%d+"))
    if not isValidEquipSlot(item, slotId) then
        return
    end

    local newItemId = getCurrentItemId(item)
    if newItemId == 0 then
        return
    end

    local newItem = Item.create(newItemId)
    newItem:setTier(item:getTier())

    widget:setStyle("PresetEmptyItem")
    widget:setItem(newItem)
    ItemsDatabase.setTier(widget, item:getTier())
end

function assignPlayerEquipments()
    if not presetWindow or not presetWindow:isVisible() then
        return
    end

    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local slotIdToInventorySlot = {
        [1] = InventorySlotHead, [2] = InventorySlotNeck, [4] = InventorySlotBody,
        [5] = InventorySlotRight, [6] = InventorySlotLeft, [7] = InventorySlotLeg,
        [8] = InventorySlotFeet, [9] = InventorySlotFinger, [10] = InventorySlotAmmo
    }

    for _, slotId in pairs(EquipmentPresetSlots) do
        local w = presetWindow:recursiveGetChildById(string.format("equipSlot%d", slotId))
        local invSlot = slotIdToInventorySlot[slotId]
        if w and invSlot then
            local invItem = player:getInventoryItem(invSlot)
            if invItem and not isValidEquipSlot(invItem, slotId) then
                -- mantém o slot do preset como está
            elseif invItem then
                local inventoryItemId = getCurrentItemId(invItem)
                local inventoryTier = invItem:getTier() or 0
                if inventoryItemId > 0 then
                    local presetItem = Item.create(inventoryItemId)
                    presetItem:setTier(inventoryTier)
                    w:setStyle('PresetEmptyItem')
                    w:setItem(presetItem)
                    ItemsDatabase.setTier(w, inventoryTier)
                else
                    w:setItemId(0)
                    w:setStyle(PresetSlotStyles[slotId])
                end
            else
                w:setItemId(0)
                w:setStyle(PresetSlotStyles[slotId])
            end
        end
    end
end

function onRemovePresetItem(widget)
    local slot = tonumber(string.match(widget:getId(), "%d+"))
    widget:setItem(nil)
    widget:setStyle(PresetSlotStyles[slot])
end

function editPresetIcon(widget, mousePos, mouseButton)
    presetWindow:hide()

    selectIconWindow = g_ui.createWidget("SelectEquipPresetIcon", g_ui.getRootWidget())
    if not selectIconWindow then
        presetWindow:show()
        return
    end

    UIModalOverlay.register(selectIconWindow)

    local iconList = selectIconWindow:recursiveGetChildById("selectEquipPresetPanel")
    radioIconGroup = UIRadioGroup.create()

    for _, w in pairs(iconList:getChildren()) do
        radioIconGroup:addWidget(w)
    end

    radioIconGroup.onSelectionChange = function(w, currentWidget, prevWidget)
        if prevWidget then
            prevWidget:recursiveGetChildById("selectedFrame"):setVisible(false)
        end
        currentWidget:recursiveGetChildById("selectedFrame"):setVisible(true)
        selectIconWindow:recursiveGetChildById("selectButton"):setEnabled(true)
    end
end

function onCloseSelectPresetIcon()
    if selectIconWindow then
        selectIconWindow:hide()
        selectIconWindow:destroy()
        if radioIconGroup then
            radioIconGroup:destroy()
        end
        selectIconWindow = nil
        radioIconGroup = nil
    end
    if presetWindow and not presetWindow:isDestroyed() then
        presetWindow:show()
    end
end

function onSelectPresetIcon()
    local selectedWidget = radioIconGroup and radioIconGroup:getSelectedWidget()
    if selectedWidget and presetWindow and not presetWindow:isDestroyed() then
        presetWindow:recursiveGetChildById("imageContainer"):setImageSource(selectedWidget.imageContainer:getImageSource())
    end

    onCloseSelectPresetIcon()
    if presetWindow and not presetWindow:isDestroyed() and presetWindow.contentPanel then
        presetWindow.contentPanel.apply:setEnabled(true)
        presetWindow.contentPanel.missingIcon:setVisible(false)
    end
end

function isValidEquipSlot(item, slotId)
    if not presetWindow or not presetWindow:isVisible() then
        return false
    end

    local cloth = item:getClothSlot()
    local isTwoHanded = cloth == 0 and item:getClassification() > 0

    if (slotId ~= cloth and not (isTwoHanded and slotId == 6)) or (cloth == 0 and not isTwoHanded) then
        return false, "You cannot dress this object there"
    end

    local itemType = g_things.getThingType(item:getId(), ThingCategoryItem)
    local marketData = itemType:getMarketData()

    if item:getId() == 28494 then
        marketData.category = MarketCategory.Shields
    end

    if slotId == 5 then
        local leftWidget = presetWindow:recursiveGetChildById("equipSlot6")
        local leftItemId = leftWidget:getItemId()
        if leftItemId > 0 then
            local leftType = g_things.getThingType(leftItemId, ThingCategoryItem)
            local leftMarket = leftType:getMarketData()
            local leftIsTwoHanded = leftType:getClothSlot() == 0 and (
                leftMarket.category == MarketCategory.Shields or
                leftType:getClassification() > 0
            )
            if marketData.category == MarketCategory.Shields and leftIsTwoHanded then
                return false, "Both hands need to be free"
            end
        end
    end

    if slotId == 6 then
        local rightWidget = presetWindow:recursiveGetChildById("equipSlot5")
        local rightItemId = rightWidget:getItemId()
        if rightItemId > 0 then
            local rightType = g_things.getThingType(rightItemId, ThingCategoryItem)
            local rightMarket = rightType:getMarketData()
            if rightMarket.category == MarketCategory.Shields and itemType:getClothSlot() == 0 then
                return false, "Both hands need to be free"
            end
        end
    end

    local charges = item.getCharges and item:getCharges() or 0
    if (slotId == 2 or slotId == 9) and item:hasWearout() and charges > 0 then
        return false, "Items with charges are not allowed"
    end

    local player = g_game.getLocalPlayer()
    local playerVocation = translateWheelVocation(player:getVocation())

    local itemVocation = tonumber(marketData.restrictVocation) or 0
    if itemVocation > 0 then
        local demotedVoc = playerVocation > 10 and (playerVocation - 10) or playerVocation
        local vocBitMask = Bit.bit(tonumber(demotedVoc))
        if not Bit.hasBit(itemVocation, vocBitMask) then
            return false, "You don't have the required profession"
        end
    end

    if marketData.requiredLevel > player:getLevel() then
        return false, "You do not have enough level"
    end
    return true
end

function offLineEvents()
    if selectIconWindow then
        selectIconWindow:hide()
        selectIconWindow:destroy()
        if radioIconGroup then
            radioIconGroup:destroy()
        end
        selectIconWindow = nil
        radioIconGroup = nil
    end

    if presetWindow then
        presetWindow:hide()
        presetWindow:destroy()
        presetWindow = nil
    end

    currentButton = nil
end

function onEditSmartMode(widget)
    if not currentButton.cache.equipmentPreset[widget:getId()] then
        currentButton.cache.equipmentPreset[widget:getId()] = { itemId = 0, tier = 0, identifier = "", smartMode = true }
        return
    end

    local currentState = currentButton.cache.equipmentPreset[widget:getId()].smartMode
    currentButton.cache.equipmentPreset[widget:getId()].smartMode = not currentState
end

function smartModeEnabled(widget)
    if not currentButton.cache.equipmentPreset[widget:getId()] then
        return false
    end

    return currentButton.cache.equipmentPreset[widget:getId()].smartMode
end
