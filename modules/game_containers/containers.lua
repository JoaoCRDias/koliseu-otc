containerSettings = nil
openContainerInstances = {} -- Track open container instances for saving

-- Debounce variables for container updates (prevents lag when receiving many items at once)
local containerUpdateEvents = {}      -- Per-container debounce events for item updates
local containerSizeChangeEvents = {}  -- Per-container debounce events for size changes
local pendingContainerUpdates = {}    -- Track pending slot updates per container for batching
local containerUpdateDebounceMs = 100 -- Delay in ms before refreshing container (lower since we batch properly now)
local pendingContainerRefresh = {}    -- Per-container debounce for container re-opens (loot batch optimization)


function init()
    g_ui.importStyle('container')

    -- Initialize container settings
    containerSettings = g_settings.getNode('containers')
    if not containerSettings then
        containerSettings = {}
        -- Set useManualSortMode as default
        containerSettings['useManualSortMode'] = 1
        -- Set default sorting mode to none
        containerSettings['currentSortMode'] = 'none'
        -- Initialize sorting options
        containerSettings['sortContainersFirst'] = 0
        containerSettings['sortNestedContainers'] = 0
        g_settings.setNode('containers', containerSettings)
    end

    -- Ensure all required settings exist
    if containerSettings['sortNestedContainers'] == nil then
        containerSettings['sortNestedContainers'] = 0
    end
    if containerSettings['sortContainersFirst'] == nil then
        containerSettings['sortContainersFirst'] = 0
    end

    connect(Container, {
        onOpen = onContainerOpen,
        onClose = onContainerClose,
        onSizeChange = onContainerChangeSize,
        onUpdateItem = onContainerUpdateItem
    })
    connect(g_game, {
        onGameEnd = clean
    })

    reloadContainers()
end

function terminate()
    disconnect(Container, {
        onOpen = onContainerOpen,
        onClose = onContainerClose,
        onSizeChange = onContainerChangeSize,
        onUpdateItem = onContainerUpdateItem
    })
    disconnect(g_game, {
        onGameEnd = clean
    })
end

function reloadContainers()
    clean()
    for _, container in pairs(g_game.getContainers()) do
        onContainerOpen(container)
    end
end

function clean()
    -- Notify sidebars to save BEFORE destroying containers (RubinOT approach).
    -- This guarantees sidebars can walk panels and read live widget state.
    if modules.game_sidebars and modules.game_sidebars.onContainersAboutToClose then
        modules.game_sidebars.onContainersAboutToClose()
    else
        g_logger.warning("[Containers] clean() - game_sidebars.onContainersAboutToClose NOT available!")
    end

    -- Cancel any pending container refresh events
    for _, pending in pairs(pendingContainerRefresh) do
        if pending.event then
            removeEvent(pending.event)
        end
    end
    pendingContainerRefresh = {}

    for containerid, container in pairs(g_game.getContainers()) do
        destroy(container)
    end
    -- Reset open instances tracking on logout/disconnect
    openContainerInstances = {}
end

function destroy(container)
    if container.window then
        container.window:destroy()
        container.window = nil
        container.itemsPanel = nil
    end
end

function showContainersContextMenu(widget, mousePos, mouseButton)
    local menu = g_ui.createWidget('ContainersSubMenu')
    if not menu then
        return false
    end
    menu:setGameMenu(true)
    for _, choice in ipairs(menu:getChildren()) do
        local choiceId = choice:getId()
        if choiceId and choiceId ~= 'HorizontalSeparator' then
            local widgetClass = choice:getClassName()
            local isSortingAction = choiceId:find('sortAsc') or choiceId:find('sortDesc')
            local isActionButton = isSortingAction or choiceId == 'moveToObtainContainers'
            if isActionButton then
                choice.onClick = function()
                    onContainersMenuAction(choiceId)
                    menu:destroy()
                end
                choice.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseLeftButton then
                        onContainersMenuAction(choiceId)
                        menu:destroy()
                        return true
                    end
                    return false
                end
                if isSortingAction then
                    local currentSortMode = containerSettings and containerSettings['currentSortMode'] or 'none'
                    local isActive = (currentSortMode == choiceId)
                    local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
                    if isManualSortEnabled then
                        choice:setEnabled(false)
                        choice:setColor('#808080')
                    else
                        choice:setEnabled(true)
                        if isActive then
                            choice:setColor('#ffff00')
                        else
                            choice:setColor('$var-text-cip-color-white')
                        end
                    end
                else
                    choice:setEnabled(true)
                    choice:setColor('$var-text-cip-color-white')
                end
            else
                local currentState = getContainerOptionState(choiceId)
                choice:setChecked(currentState)
                local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
                if isManualSortEnabled and (choiceId == 'sortContainersFirst' or choiceId == 'sortNestedContainers') then
                    choice:setEnabled(false)
                    choice:setColor('#808080')
                else
                    choice:setEnabled(true)
                    choice:setColor('$var-text-cip-color-white')
                end
                choice.onCheckChange = function()
                    onContainersMenuAction(choiceId)
                    menu:destroy()
                end
            end
        end
    end
    local buttonPos = widget:getPosition()
    local buttonSize = widget:getSize()
    local menuWidth = menu:getWidth()
    local buttonCenterX = buttonPos.x + buttonSize.width / 2
    local buttonCenterY = buttonPos.y + buttonSize.height / 2
    local menuX = buttonCenterX - menuWidth
    local menuY = buttonCenterY
    menu:display({ x = menuX, y = menuY })
    return true
end

function getContainerOptionState(optionId)
    -- Return the current state of container options
    -- These are stored in settings similar to skills module
    if not containerSettings then
        return false
    end

    if optionId == 'sortContainersFirst' then
        return containerSettings['sortContainersFirst'] == 1
    elseif optionId == 'sortNestedContainers' then
        return containerSettings['sortNestedContainers'] == 1
    elseif optionId == 'useManualSortMode' then
        return containerSettings['useManualSortMode'] == 1
    elseif optionId == 'moveNestedContainers' then
        return containerSettings['moveNestedContainers'] == 1
    end
    return false
end

function sortContainerItems(container, sortMode)
    if not container or not container.itemsPanel then
        return
    end

    -- Don't sort if manual sort mode is enabled
    local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
    if isManualSortEnabled then
        return
    end

    -- Check if Sort Nested Containers is enabled when manual sort mode is disabled
    local sortNestedContainers = containerSettings and containerSettings['sortNestedContainers'] == 1
    if sortNestedContainers then
    end

    -- Get all items with their slot information (only non-nil items)
    local items = {}
    local totalCapacity = container:getCapacity()

    for slot = 0, totalCapacity - 1 do
        local item = container:getItem(slot)
        if item and item:getId() > 0 then -- Check for valid item
            table.insert(items, {
                slot = slot,
                item = item,
                widget = container.itemsPanel:getChildById('item' .. slot)
            })
        end
    end

    -- Only sort if we have items
    if #items == 0 then
        return
    end

    -- Check if Sort Containers First and Sort Nested Containers are enabled
    local sortContainersFirst = containerSettings and containerSettings['sortContainersFirst'] == 1
    local sortNestedContainers = containerSettings and containerSettings['sortNestedContainers'] == 1

    -- Helper function to check if an item is a container
    local function isContainer(item)
        local success, result = pcall(function()
            if item.isContainer and type(item.isContainer) == "function" then
                return item:isContainer()
            end
            return false
        end)
        return success and result
    end

    -- Helper function to check if a container has items inside (is nested)
    local function isNestedContainer(item)
        if not isContainer(item) then
            return false
        end

        local success, result = pcall(function()
            -- Try to get the container's item count
            if item.getItemsCount and type(item.getItemsCount) == "function" then
                local itemCount = item:getItemsCount()
                return itemCount and itemCount > 0
            end

            -- Alternative: Check if container has capacity and items
            if item.getCapacity and type(item.getCapacity) == "function" then
                local capacity = item:getCapacity()
                if capacity and capacity > 0 then
                    -- Check if any slot has an item
                    for slot = 0, capacity - 1 do
                        if item.getItem and type(item.getItem) == "function" then
                            local slotItem = item:getItem(slot)
                            if slotItem and slotItem:getId() > 0 then
                                return true
                            end
                        end
                    end
                end
            end

            return false
        end)

        if not success then
            return false
        end

        return result
    end

    -- Helper function for container-first sorting with nested container support
    local function sortWithContainersFirst(items, compareFn)
        local sortContainersFirst = containerSettings and containerSettings['sortContainersFirst'] == 1
        local sortNestedContainers = containerSettings and containerSettings['sortNestedContainers'] == 1

        -- Sort Nested Containers feature:
        -- When enabled, containers that have items inside them are prioritized at the top,
        -- followed by empty containers (if Sort Containers First is also enabled),
        -- and finally non-container items.
        --
        -- Priority order when both options are enabled:
        -- 1. Nested containers (containers with items inside) - HIGHEST PRIORITY
        -- 2. Empty containers (only if Sort Containers First is enabled)
        -- 3. Non-container items - LOWEST PRIORITY
        --
        -- This feature can work together with Sort Containers First but not with Manual Sort Mode.

        -- If neither option is enabled, just sort normally
        if not sortContainersFirst and not sortNestedContainers then
            table.sort(items, compareFn)
            return
        end

        -- Separate items into categories
        local nestedContainers = {} -- Containers with items inside
        local emptyContainers = {}  -- Empty containers
        local nonContainers = {}    -- Non-container items

        for _, itemData in ipairs(items) do
            if isContainer(itemData.item) then
                if sortNestedContainers and isNestedContainer(itemData.item) then
                    table.insert(nestedContainers, itemData)
                else
                    table.insert(emptyContainers, itemData)
                end
            else
                table.insert(nonContainers, itemData)
            end
        end

        -- Sort each group separately
        table.sort(nestedContainers, compareFn)
        table.sort(emptyContainers, compareFn)
        table.sort(nonContainers, compareFn)

        -- Merge groups based on enabled options with proper priority order
        local sortedItems = {}

        -- Priority 1: Nested containers (if Sort Nested Containers is enabled)
        if sortNestedContainers then
            for _, itemData in ipairs(nestedContainers) do
                table.insert(sortedItems, itemData)
            end
        end

        -- Priority 2: Empty containers (if Sort Containers First is enabled)
        -- Note: This comes after nested containers even if both options are enabled
        if sortContainersFirst then
            for _, itemData in ipairs(emptyContainers) do
                table.insert(sortedItems, itemData)
            end

            -- Add nested containers here only if sortNestedContainers is not enabled
            if not sortNestedContainers then
                for _, itemData in ipairs(nestedContainers) do
                    table.insert(sortedItems, itemData)
                end
            end
        else
            -- If sortContainersFirst is disabled but sortNestedContainers is disabled too,
            -- add all containers together after nested containers
            if not sortNestedContainers then
                for _, itemData in ipairs(nestedContainers) do
                    table.insert(sortedItems, itemData)
                end
            end

            -- Add empty containers without priority
            for _, itemData in ipairs(emptyContainers) do
                table.insert(sortedItems, itemData)
            end
        end

        -- Priority 3 (Last): Non-container items
        for _, itemData in ipairs(nonContainers) do
            table.insert(sortedItems, itemData)
        end

        -- Replace original items array
        for i = 1, #items do
            items[i] = sortedItems[i]
        end
    end

    -- Sort the items based on the sort mode
    if sortMode == 'sortAscByName' then
        sortWithContainersFirst(items, function(a, b)
            if not a or not a.item or not b or not b.item then
                return false
            end

            local nameA = ""
            local nameB = ""

            -- Use pcall for extra safety and try getName from the item
            local success, result = pcall(function()
                if a.item.getName and type(a.item.getName) == "function" then
                    return a.item:getName() or ""
                end
                -- Try getting name from the item type if direct getName fails
                local itemType = g_things.getThingType(a.item:getId(), ThingCategoryItem)
                if itemType and itemType.getName and type(itemType.getName) == "function" then
                    return itemType:getName() or ""
                end
                return ""
            end)
            if success then nameA = result end

            success, result = pcall(function()
                if b.item.getName and type(b.item.getName) == "function" then
                    return b.item:getName() or ""
                end
                -- Try getting name from the item type if direct getName fails
                local itemType = g_things.getThingType(b.item:getId(), ThingCategoryItem)
                if itemType and itemType.getName and type(itemType.getName) == "function" then
                    return itemType:getName() or ""
                end
                return ""
            end)
            if success then nameB = result end

            return nameA:lower() < nameB:lower()
        end)
    elseif sortMode == 'sortDescByName' then
        sortWithContainersFirst(items, function(a, b)
            if not a or not a.item or not b or not b.item then
                return false
            end

            local nameA = ""
            local nameB = ""

            -- Use pcall for extra safety and try getName from the item
            local success, result = pcall(function()
                if a.item.getName and type(a.item.getName) == "function" then
                    return a.item:getName() or ""
                end
                -- Try getting name from the item type if direct getName fails
                local itemType = g_things.getThingType(a.item:getId(), ThingCategoryItem)
                if itemType and itemType.getName and type(itemType.getName) == "function" then
                    return itemType:getName() or ""
                end
                return ""
            end)
            if success then nameA = result end

            success, result = pcall(function()
                if b.item.getName and type(b.item.getName) == "function" then
                    return b.item:getName() or ""
                end
                -- Try getting name from the item type if direct getName fails
                local itemType = g_things.getThingType(b.item:getId(), ThingCategoryItem)
                if itemType and itemType.getName and type(itemType.getName) == "function" then
                    return itemType:getName() or ""
                end
                return ""
            end)
            if success then nameB = result end

            return nameA:lower() > nameB:lower()
        end)
    elseif sortMode == 'sortAscByWeight' then
        -- TODO: Implement functionality to retrieve item weights and sort accordingly
        return
    elseif sortMode == 'sortDescByWeight' then
        -- TODO: Implement weight-based sorting (descending)
        return
    elseif sortMode == 'sortAscByExpiry' then
        sortWithContainersFirst(items, function(a, b)
            if not a or not a.item or not b or not b.item then return false end

            local aExpiry = 0
            local bExpiry = 0

            -- Use getDurationTime() for expiry - this exists on Item objects
            local success, result = pcall(function()
                if a.item.getDurationTime and type(a.item.getDurationTime) == "function" then
                    return a.item:getDurationTime() or 0
                end
                return 0
            end)
            if success then aExpiry = result end

            success, result = pcall(function()
                if b.item.getDurationTime and type(b.item.getDurationTime) == "function" then
                    return b.item:getDurationTime() or 0
                end
                return 0
            end)
            if success then bExpiry = result end

            return aExpiry < bExpiry
        end)
    elseif sortMode == 'sortDescByExpiry' then
        sortWithContainersFirst(items, function(a, b)
            if not a or not a.item or not b or not b.item then return false end

            local aExpiry = 0
            local bExpiry = 0

            -- Use getDurationTime() for expiry - this exists on Item objects
            local success, result = pcall(function()
                if a.item.getDurationTime and type(a.item.getDurationTime) == "function" then
                    return a.item:getDurationTime() or 0
                end
                return 0
            end)
            if success then aExpiry = result end

            success, result = pcall(function()
                if b.item.getDurationTime and type(b.item.getDurationTime) == "function" then
                    return b.item:getDurationTime() or 0
                end
                return 0
            end)
            if success then bExpiry = result end

            return aExpiry > bExpiry
        end)
    elseif sortMode == 'sortAscByStackSize' then
        sortWithContainersFirst(items, function(a, b)
            if not a or not a.item or not b or not b.item then return false end

            local countA = 1
            local countB = 1
            local chargesA = 0
            local chargesB = 0

            -- Use getCount() - this exists on Item objects
            local success, result = pcall(function()
                if a.item.getCount and type(a.item.getCount) == "function" then
                    return a.item:getCount() or 1
                end
                return 1
            end)
            if success then countA = result end

            success, result = pcall(function()
                if b.item.getCount and type(b.item.getCount) == "function" then
                    return b.item:getCount() or 1
                end
                return 1
            end)
            if success then countB = result end

            -- Get charges
            success, result = pcall(function()
                if a.item.getCharges and type(a.item.getCharges) == "function" then
                    return a.item:getCharges() or 0
                end
                return 0
            end)
            if success then chargesA = result end

            success, result = pcall(function()
                if b.item.getCharges and type(b.item.getCharges) == "function" then
                    return b.item:getCharges() or 0
                end
                return 0
            end)
            if success then chargesB = result end

            -- Use charges if available, otherwise use count
            local valueA = chargesA > 0 and chargesA or countA
            local valueB = chargesB > 0 and chargesB or countB

            return valueA < valueB
        end)
    elseif sortMode == 'sortDescByStackSize' then
        sortWithContainersFirst(items, function(a, b)
            if not a or not a.item or not b or not b.item then return false end

            local countA = 1
            local countB = 1
            local chargesA = 0
            local chargesB = 0

            -- Use getCount() - this exists on Item objects
            local success, result = pcall(function()
                if a.item.getCount and type(a.item.getCount) == "function" then
                    return a.item:getCount() or 1
                end
                return 1
            end)
            if success then countA = result end

            success, result = pcall(function()
                if b.item.getCount and type(b.item.getCount) == "function" then
                    return b.item:getCount() or 1
                end
                return 1
            end)
            if success then countB = result end

            -- Get charges
            success, result = pcall(function()
                if a.item.getCharges and type(a.item.getCharges) == "function" then
                    return a.item:getCharges() or 0
                end
                return 0
            end)
            if success then chargesA = result end

            success, result = pcall(function()
                if b.item.getCharges and type(b.item.getCharges) == "function" then
                    return b.item:getCharges() or 0
                end
                return 0
            end)
            if success then chargesB = result end

            -- Use charges if available, otherwise use count
            local valueA = chargesA > 0 and chargesA or countA
            local valueB = chargesB > 0 and chargesB or countB

            return valueA > valueB
        end)
    else
        -- No sorting or unknown mode
        return
    end

    -- Clear all item widgets first
    for slot = 0, totalCapacity - 1 do
        local itemWidget = container.itemsPanel:getChildById('item' .. slot)
        if itemWidget then
            itemWidget:setItem(nil)
            -- Clear rarity, tier, charges and duration images when removing item
            ItemsDatabase.clearRarityItem(itemWidget)
        end
    end

    -- Place sorted items back into the container display starting from slot 0
    for i, itemData in ipairs(items) do
        local targetSlot = i - 1 -- Convert to 0-based index

        if targetSlot < totalCapacity then
            local itemWidget = container.itemsPanel:getChildById('item' .. targetSlot)
            if itemWidget then
                -- Set the visual item (this doesn't change the actual container data)
                itemWidget:setItem(itemData.item)
                -- Preserve the original slot position for drag-and-drop operations
                itemWidget.position = container:getSlotPosition(itemData.slot)

                ItemsDatabase.setRarityItem(itemWidget, itemData.item)
                ItemsDatabase.setTier(itemWidget, itemData.item)
                if modules.client_options.getOption('showExpiryInContainers') then
                    ItemsDatabase.setCharges(itemWidget, itemData.item)
                    ItemsDatabase.setDuration(itemWidget, itemData.item)
                end

                local itemName = "unnamed"
                local success, result = pcall(function()
                    if itemData.item.getName and type(itemData.item.getName) == "function" then
                        return itemData.item:getName() or "unnamed"
                    end
                    -- Try getting name from the item type if direct getName fails
                    local itemType = g_things.getThingType(itemData.item:getId(), ThingCategoryItem)
                    if itemType and itemType.getName and type(itemType.getName) == "function" then
                        return itemType:getName() or "unnamed"
                    end
                    return "unnamed"
                end)
                if success then itemName = result end
            else
            end
        else
        end
    end
end

-- Function to determine quick loot category for an item

function onContainersMenuAction(actionId)
    local isToggleOption = actionId == 'sortContainersFirst' or actionId == 'sortNestedContainers' or
        actionId == 'useManualSortMode' or actionId == 'moveNestedContainers'
    local isActionButton = actionId == 'moveToObtainContainers' or actionId:find('sortAsc') or actionId:find('sortDesc')
    if isActionButton then
        -- Handle action buttons (non-toggle actions)
        if actionId == 'moveToObtainContainers' then
            -- TODO: Need to create function to use quickloot sorting.
            return
        elseif actionId:find('sortAsc') or actionId:find('sortDesc') then
            -- When a sorting action is selected, automatically disable manual sort mode
            local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
            if isManualSortEnabled then
                containerSettings['useManualSortMode'] = 0
            end

            -- Sorting actions - these are mutually exclusive
            containerSettings['currentSortMode'] = actionId
            g_settings.setNode('containers', containerSettings)

            -- Apply sorting to all open containers
            for _, container in pairs(g_game.getContainers()) do
                if container.window and container.window:isVisible() then
                    sortContainerItems(container, actionId)
                end
            end
            return
        end
    end

    if isToggleOption then
        -- Toggle options
        local currentState = getContainerOptionState(actionId)
        local newState = not currentState

        -- Special handling for useManualSortMode
        if actionId == 'useManualSortMode' then
            if newState then
                -- When enabling manual sort mode, clear any active sorting mode and disable other sorting options
                containerSettings['currentSortMode'] = 'none'
                containerSettings['sortContainersFirst'] = 0
                containerSettings['sortNestedContainers'] = 0
            else
                -- When disabling manual sort mode, sorting options become available again
            end
        elseif actionId == 'sortContainersFirst' then
            -- Prevent enabling if manual sort mode is active
            local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
            if newState and isManualSortEnabled then
                return -- Don't change the setting
            end

            -- When Sort Containers First is toggled, re-apply current sorting if active
            local currentSortMode = containerSettings and containerSettings['currentSortMode']
            if currentSortMode and currentSortMode ~= 'none' then
                -- Apply sorting to all open containers after toggling
                scheduleEvent(function()
                    for _, container in pairs(g_game.getContainers()) do
                        if container.window and container.window:isVisible() then
                            sortContainerItems(container, currentSortMode)
                        end
                    end
                end, 50) -- Small delay to ensure setting is saved first
            end
        elseif actionId == 'sortNestedContainers' then
            -- Prevent enabling if manual sort mode is active
            local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
            if newState and isManualSortEnabled then
                return -- Don't change the setting
            end

            -- When Sort Nested Containers is toggled, re-apply current sorting if active
            local currentSortMode = containerSettings and containerSettings['currentSortMode']
            if currentSortMode and currentSortMode ~= 'none' then
                -- Apply sorting to all open containers after toggling
                scheduleEvent(function()
                    for _, container in pairs(g_game.getContainers()) do
                        if container.window and container.window:isVisible() then
                            sortContainerItems(container, currentSortMode)
                        end
                    end
                end, 50) -- Small delay to ensure setting is saved first
            end
        elseif actionId == 'moveNestedContainers' then
            -- TODO: Implement functionality to automatically move nested containers (containers with items inside)
            -- to specific locations or positions within containers. This feature should work in conjunction
            -- with container sorting and could help organize containers by moving filled containers to
            -- preferred positions (e.g., top of container, specific slots, etc.).
            -- Implementation should consider:
            -- 1. Identify containers that have items inside (nested containers)
            -- 2. Define target positions/rules for where to move them
            -- 3. Handle conflicts with existing sorting modes
            -- 4. Respect manual sort mode settings
            -- 5. Provide user feedback on move operations

            -- For now, just toggle the setting - actual move functionality to be implemented
        end

        -- Save the new state to settings
        containerSettings[actionId] = newState and 1 or 0
        g_settings.setNode('containers', containerSettings)
    end
end

function refreshContainerItems(container)
    if not container or not container.itemsPanel then return end

    local capacity = container:getCapacity()

    -- Check if we should preserve sorting during refresh
    local currentSortMode = containerSettings and containerSettings['currentSortMode']
    local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
    local shouldSort = currentSortMode and currentSortMode ~= 'none' and not isManualSortEnabled

    -- Disable layout updates during batch item refresh for better performance
    local layout = container.itemsPanel:getLayout()
    if layout then
        layout:disableUpdates()
    end

    for slot = 0, capacity - 1 do
        local itemWidget = container.itemsPanel:getChildById('item' .. slot)
        local item = container:getItem(slot)
        itemWidget:setItem(item)
        ItemsDatabase.setRarityItem(itemWidget, item)
        ItemsDatabase.setTier(itemWidget, item)
        if ItemsDatabase.updateQuickLootFlags then ItemsDatabase.updateQuickLootFlags(itemWidget, item) end
        if modules.client_options.getOption('showExpiryInContainers') then
            ItemsDatabase.setCharges(itemWidget, item)
            ItemsDatabase.setDuration(itemWidget, item)
        end
    end

    -- Re-enable layout updates and trigger single update
    if layout then
        layout:enableUpdates()
        layout:update()
    end

    if container:hasPages() then
        refreshContainerPages(container)
    end

    -- Apply current sorting if one is set and manual sort mode is disabled
    if shouldSort then
        sortContainerItems(container, currentSortMode)
    end
end

function toggleContainerPages(containerWindow, pages)
    local scrollbar = containerWindow:getChildById('miniwindowScrollBar')
    local pagePanel = containerWindow:getChildById('pagePanel')
    local separator = containerWindow:getChildById('separator')
    local contentsPanel = containerWindow:getChildById('contentsPanel')
    local upButton = containerWindow:getChildById('upButton')
    local contextMenuButton = containerWindow:recursiveGetChildById('contextMenuButton')
    local lockButton = containerWindow:recursiveGetChildById('lockButton')
    local minimizeButton = containerWindow:recursiveGetChildById('minimizeButton')

    if pages then
        -- When pages are visible, anchor scrollbar to close button bottom and separator top
        scrollbar:breakAnchors()
        scrollbar:addAnchor(AnchorTop, 'closeButton', AnchorBottom)
        scrollbar:addAnchor(AnchorRight, 'parent', AnchorRight)
        scrollbar:addAnchor(AnchorBottom, 'separator', AnchorTop)
        scrollbar:setMarginTop(2) -- Small margin from close button
        scrollbar:setMarginRight(3)
        scrollbar:setMarginBottom(2)

        -- Content panel anchors to separator when pages are visible
        contentsPanel:breakAnchors()
        contentsPanel:addAnchor(AnchorTop, 'miniwindowTopBar', AnchorBottom)
        contentsPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        contentsPanel:addAnchor(AnchorRight, 'miniwindowScrollBar', AnchorLeft)
        contentsPanel:addAnchor(AnchorBottom, 'separator', AnchorTop)
        contentsPanel:setMarginLeft(3)
        contentsPanel:setMarginBottom(1)
        contentsPanel:setMarginTop(-2)
        contentsPanel:setMarginRight(1)

        -- When pages are active, move upButton to toggleFilterButton position if it's visible
        if upButton and upButton:isVisible() and contextMenuButton and minimizeButton then
            -- Position upButton where toggleFilterButton was
            upButton:breakAnchors()
            upButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
            upButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
            upButton:setMarginRight(7)
            upButton:setMarginTop(0)

            -- Move contextMenuButton to the left of upButton
            contextMenuButton:breakAnchors()
            contextMenuButton:addAnchor(AnchorTop, upButton:getId(), AnchorTop)
            contextMenuButton:addAnchor(AnchorRight, upButton:getId(), AnchorLeft)
            contextMenuButton:setMarginRight(2)
            contextMenuButton:setMarginTop(0)

            -- Position lockButton to the left of contextMenu
            if lockButton then
                lockButton:breakAnchors()
                lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
                lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
                lockButton:setMarginRight(2)
                lockButton:setMarginTop(0)
            end
        end
    else
        -- When pages are hidden, use normal bottom anchor
        scrollbar:breakAnchors()
        scrollbar:addAnchor(AnchorTop, 'parent', AnchorTop)
        scrollbar:addAnchor(AnchorRight, 'parent', AnchorRight)
        scrollbar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        scrollbar:setMarginTop(16)
        scrollbar:setMarginRight(3)
        scrollbar:setMarginBottom(3)

        -- Content panel extends to bottom when pages are hidden
        contentsPanel:breakAnchors()
        contentsPanel:addAnchor(AnchorTop, 'miniwindowTopBar', AnchorBottom)
        contentsPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
        contentsPanel:addAnchor(AnchorRight, 'miniwindowScrollBar', AnchorLeft)
        contentsPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        contentsPanel:setMarginLeft(3)
        contentsPanel:setMarginBottom(3)
        contentsPanel:setMarginTop(-2)
        contentsPanel:setMarginRight(1)

        -- When pages are not active, reset button positions based on upButton visibility
        if upButton and contextMenuButton and minimizeButton then
            if upButton:isVisible() then
                -- Reset upButton to original position
                upButton:breakAnchors()
                upButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
                upButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
                upButton:setMarginRight(3)
                upButton:setMarginTop(0)

                -- Position contextMenuButton to the left of upButton
                contextMenuButton:breakAnchors()
                contextMenuButton:addAnchor(AnchorTop, upButton:getId(), AnchorTop)
                contextMenuButton:addAnchor(AnchorRight, upButton:getId(), AnchorLeft)
                contextMenuButton:setMarginRight(2)
                contextMenuButton:setMarginTop(0)
            else
                -- Position contextMenuButton where toggleFilterButton was
                contextMenuButton:breakAnchors()
                contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
                contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
                contextMenuButton:setMarginRight(7)
                contextMenuButton:setMarginTop(0)
            end

            -- Position lockButton to the left of contextMenu
            if lockButton then
                lockButton:breakAnchors()
                lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
                lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
                lockButton:setMarginRight(2)
                lockButton:setMarginTop(0)
            end
        end
    end

    pagePanel:setVisible(pages)
    separator:setVisible(pages)
end

function refreshContainerPages(container)
    if not container.window then return end

    local currentPage = 1 + math.floor(container:getFirstIndex() / container:getCapacity())
    local pages = 1 + math.floor(math.max(0, (container:getSize() - 1)) / container:getCapacity())
    container.window:recursiveGetChildById('pageLabel'):setText(string.format('Page %i of %i', currentPage, pages))

    local prevPageButton = container.window:recursiveGetChildById('prevPageButton')
    local nextPageButton = container.window:recursiveGetChildById('nextPageButton')

    -- If there's only one page, hide both navigation buttons
    if pages == 1 then
        prevPageButton:setVisible(false)
        nextPageButton:setVisible(false)
    else
        -- Multiple pages logic
        if currentPage == 1 then
            -- Hide the back button when on the first page of multiple pages
            prevPageButton:setVisible(false)
        else
            prevPageButton:setVisible(true)
            prevPageButton:setEnabled(true)
            prevPageButton.onClick = function()
                if not container.window then return end
                -- Store current height before page change
                local currentHeight = container.window:getHeight()
                container.window.preservedHeight = currentHeight
                g_game.seekInContainer(container:getId(), container:getFirstIndex() - container:getCapacity())
            end
        end

        if currentPage >= pages then
            nextPageButton:setVisible(false)
        else
            nextPageButton:setVisible(true)
            nextPageButton:setEnabled(true)
            nextPageButton.onClick = function()
                if not container.window then return end
                -- Store current height before page change
                local currentHeight = container.window:getHeight()
                container.window.preservedHeight = currentHeight
                g_game.seekInContainer(container:getId(), container:getFirstIndex() + container:getCapacity())
            end
        end
    end
end

function onContainerOpen(container, previousContainer)
    local containerId = container:getId()
    local containerWindow = nil

    -- [LootPerf] Check if there's a pending (debounced) refresh from a previous rapid re-open
    if pendingContainerRefresh[containerId] then
        local pending = pendingContainerRefresh[containerId]
        removeEvent(pending.event)
        containerWindow = pending.window
        pendingContainerRefresh[containerId] = nil

        if previousContainer then
            previousContainer.window = nil
            previousContainer.itemsPanel = nil
        end

        g_logger.debug(string.format("[LootPerf] Container %d: rapid re-open, cancelled previous pending refresh",
            containerId))
    elseif previousContainer then
        containerWindow = previousContainer.window
        previousContainer.window = nil
        previousContainer.itemsPanel = nil
    end

    -- [LootPerf] If we have an existing window (container re-open/refresh),
    -- debounce the heavy item refresh instead of doing a full widget rebuild.
    -- This prevents freezing when multiple loot updates arrive in rapid succession.
    -- BUT only if the container type is the same (same name and capacity).
    -- If a different container is opened in the same slot (e.g., opening a sub-container),
    -- we must do the full rebuild to update title, capacity, buttons, etc.
    local reusingWindow = false
    if containerWindow then
        local containerPanel = containerWindow:getChildById('contentsPanel')
        local oldName = (containerWindow.containerName or ""):lower()
        local newRawName = container:getName() or ""
        local newName = #newRawName > 0 and (newRawName:sub(1, 1):upper() .. newRawName:sub(2)) or ""
        local oldCapacity = containerPanel and containerPanel:getChildCount() or 0
        local newCapacity = container:getCapacity()

        if newName:lower() == oldName and newCapacity == oldCapacity then
            -- Same container type: debounce the refresh
            container.window = containerWindow
            container.itemsPanel = containerPanel
            containerWindow.instance = containerId
            openContainerInstances[containerId] = containerWindow

            -- Schedule debounced item refresh (coalesces multiple rapid re-opens into one)
            pendingContainerRefresh[containerId] = {
                window = containerWindow,
                event = scheduleEvent(function()
                    pendingContainerRefresh[containerId] = nil

                    if not container.window or not container.itemsPanel then
                        return
                    end

                    g_logger.debug(string.format("[LootPerf] Container %d: executing debounced item refresh", containerId))
                    refreshContainerItems(container)

                    if container:hasPages() then
                        refreshContainerPages(container)
                    end
                end, containerUpdateDebounceMs)
            }
            return
        else
            -- Different container type in same slot (e.g., sub-container): need full rebuild
            reusingWindow = true
        end
    end

    -- First open or different container in same slot: do full initialization
    if not containerWindow then
        containerWindow = g_ui.createWidget('ContainerWindow')
    end
    containerWindow:setId('container' .. containerId)
    containerWindow.instance = containerId -- Store instance for saving
    containerWindow.UIMiniWindowContainer = true -- Garantir dock/drop como MiniWindow (createWidget pode não repetir UIMiniWindow.create)
    containerWindow.type = 'container'     -- Mark as container type
    containerWindow.isOpen = true          -- Prevent fitAll() from evicting container windows
    local containerPanel = containerWindow:getChildById('contentsPanel')
    local containerItemWidget = containerWindow:getChildById('containerItemWidget')
    containerWindow.onClose = function()
        g_game.close(container)
        containerWindow:hide()
    end

    -- this disables scrollbar auto hiding
    local scrollbar = containerWindow:getChildById('miniwindowScrollBar')
    scrollbar:mergeStyle({
        ['$!on'] = {}
    })

    -- Scrollbar positioning will be handled by toggleContainerPages function

    local upButton = containerWindow:getChildById('upButton')
    upButton.onClick = function()
        g_game.openParent(container)
    end
    upButton:setVisible(container:hasParent())

    -- Show search button for depot containers with search icon
    if container.showSearchIcon and container:showSearchIcon() then
        local searchBtn = containerWindow:recursiveGetChildById('searchButton')
        if searchBtn then
            searchBtn:setVisible(true)
            searchBtn.onClick = function()
                if modules.game_search_locker then
                    modules.game_search_locker.onRequestSearch()
                end
            end
        end
    end

    -- Add minimize/maximize event handlers to manage pagePanel visibility
    containerWindow.onMinimize = function()
        local pagePanel = containerWindow:getChildById('pagePanel')
        if pagePanel and pagePanel:isVisible() then
            pagePanel.wasVisibleBeforeMinimize = true
            pagePanel:setVisible(false)
        end
    end

    containerWindow.onMaximize = function()
        local pagePanel = containerWindow:getChildById('pagePanel')
        if pagePanel and pagePanel.wasVisibleBeforeMinimize then
            pagePanel:setVisible(true)
            pagePanel.wasVisibleBeforeMinimize = nil
        end
    end

    -- Hide toggleFilterButton and adjust button positioning
    local toggleFilterButton = containerWindow:recursiveGetChildById('toggleFilterButton')
    if toggleFilterButton then
        toggleFilterButton:setVisible(false)
        toggleFilterButton:setOn(false)
    end

    -- Hide newWindowButton
    local newWindowButton = containerWindow:recursiveGetChildById('newWindowButton')
    if newWindowButton then
        newWindowButton:setVisible(false)
    end

    local contextMenuButton = containerWindow:recursiveGetChildById('contextMenuButton')
    local lockButton = containerWindow:recursiveGetChildById('lockButton')
    local minimizeButton = containerWindow:recursiveGetChildById('minimizeButton')

    -- Make sure contextMenuButton is visible
    if contextMenuButton then
        contextMenuButton:setVisible(true)
    end

    if contextMenuButton and minimizeButton then
        if container:hasParent() then
            -- When upButton is visible, position contextMenuButton to its left
            contextMenuButton:breakAnchors()
            contextMenuButton:addAnchor(AnchorTop, upButton:getId(), AnchorTop)
            contextMenuButton:addAnchor(AnchorRight, upButton:getId(), AnchorLeft)
            contextMenuButton:setMarginRight(2)
            contextMenuButton:setMarginTop(0)
        else
            -- When upButton is not visible, position contextMenuButton where toggleFilterButton was
            contextMenuButton:breakAnchors()
            contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
            contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
            contextMenuButton:setMarginRight(7)
            contextMenuButton:setMarginTop(0)
        end

        -- Position lockButton to the left of contextMenu
        if lockButton then
            lockButton:breakAnchors()
            lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
            lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
            lockButton:setMarginRight(2)
            lockButton:setMarginTop(0)
        end

        -- Add onClick handler for context menu
        contextMenuButton.onClick = function(widget, mousePos, mouseButton)
            return showContainersContextMenu(widget, mousePos, mouseButton)
        end
    end

    local fullName = container:getName()
    fullName = fullName:sub(1, 1):upper() .. fullName:sub(2)

    -- Store the full name for config matching (before truncation)
    containerWindow.containerName = fullName

    -- Truncate for display
    local displayName = fullName
    if displayName:len() > 14 then
        displayName = displayName:sub(1, 14) .. "..."
    end

    -- Set the title in the new miniwindowTitle element
    local titleWidget = containerWindow:getChildById('miniwindowTitle')
    if titleWidget then
        titleWidget:setText(displayName)
    else
        -- Fallback to old method if miniwindowTitle doesn't exist
        containerWindow:setText(displayName)
    end

    containerItemWidget:setItem(container:getContainerItem())
    containerItemWidget:setPhantom(true)

    containerPanel:destroyChildren()
    for slot = 0, container:getCapacity() - 1 do
        local itemWidget = g_ui.createWidget('Item', containerPanel)
        itemWidget:setId('item' .. slot)
        itemWidget:setItem(container:getItem(slot))
        ItemsDatabase.setRarityItem(itemWidget, container:getItem(slot))
        ItemsDatabase.setTier(itemWidget, container:getItem(slot))
        if ItemsDatabase.updateQuickLootFlags then ItemsDatabase.updateQuickLootFlags(itemWidget, container:getItem(slot)) end
        if modules.client_options.getOption('showExpiryInContainers') then
            ItemsDatabase.setCharges(itemWidget, container:getItem(slot))
            ItemsDatabase.setDuration(itemWidget, container:getItem(slot))
        end
        itemWidget:setMargin(0)
        itemWidget.position = container:getSlotPosition(slot)

        if not container:isUnlocked() then
            itemWidget:setBorderColor('red')
        end
    end

    container.window = containerWindow
    container.itemsPanel = containerPanel

    toggleContainerPages(containerWindow, container:hasPages())
    refreshContainerPages(container)

    local layout = containerPanel:getLayout()
    local cellSize = layout:getCellSize()
    local hasPages = container:hasPages()
    local pagePanelOffset = hasPages and 44 or 0
    containerWindow:setContentMinimumHeight(cellSize.height + pagePanelOffset)

    -- Set maximum height based on whether pages are active
    local maxHeightOffset = container:hasPages() and 65 or 30
    containerWindow:setContentMaximumHeight(cellSize.height * layout:getNumLines() + maxHeightOffset)

    -- Define resize restriction function
    local function restrictResize()
        containerWindow.onResize = function()
            local minHeight = cellSize.height + 30
            if container:hasPages() then
                minHeight = minHeight + 25
            end
            if containerWindow:getHeight() < minHeight then
                containerWindow:setHeight(minHeight)
            end
        end
    end
    restrictResize()

    -- Remove resize restriction on minimize, restore on maximize
    containerWindow.onMinimize = function()
        local pagePanel = containerWindow:getChildById('pagePanel')
        if pagePanel and pagePanel:isVisible() then
            pagePanel.wasVisibleBeforeMinimize = true
            pagePanel:setVisible(false)
        end
        containerWindow.onResize = nil
    end

    containerWindow.onMaximize = function()
        local pagePanel = containerWindow:getChildById('pagePanel')
        if pagePanel and pagePanel.wasVisibleBeforeMinimize then
            pagePanel:setVisible(true)
            pagePanel.wasVisibleBeforeMinimize = nil
        end
        restrictResize()
    end

    if not previousContainer and not reusingWindow then
        -- Check saved config first: if we know where this container was last session,
        -- add directly to the saved panel to avoid a fitAll on the wrong panel that
        -- would close saved widgets (e.g., Skills) unnecessarily.
        local savedPanel = nil
        local configLoaded = modules.game_sidebars and modules.game_sidebars.isConfigLoaded
            and modules.game_sidebars.isConfigLoaded()

        -- When config is not yet loaded, suppress fitAll on panels receiving containers.
        -- Without this, containers fill gameRightPanel, then panel resize (when config loads
        -- and enables extra panels) causes a cascade of fitAll that shuffles containers
        -- chaotically between panels. restoreOpenContainers() will move them to saved
        -- positions once config loads, and clearStartupIgnoreFitAll() will re-enable fitAll.
        if not configLoaded then
            local panelsList = modules.game_interface and modules.game_interface.panelsList
            if panelsList then
                for _, entry in ipairs(panelsList) do
                    if not entry.panel._startupIgnoreFitAll then
                        entry.panel._startupIgnoreFitAll = true
                        entry.panel.ignoreFillAll = true
                    end
                end
            end
        end

        if configLoaded and modules.game_sidebars.getContainerConfig
            and modules.game_sidebars.resolvePanelById then
            -- Calculate nameIndex early (same logic as below)
            local containerNameLower = fullName:lower()
            local earlyNameIndex = 1
            for otherInstance, otherWidget in pairs(openContainerInstances) do
                if otherWidget and otherWidget.containerName
                    and otherWidget.containerName:lower() == containerNameLower then
                    if otherInstance < containerId then
                        earlyNameIndex = earlyNameIndex + 1
                    end
                end
            end
            local savedConfig = modules.game_sidebars.getContainerConfig(fullName, earlyNameIndex)
            if savedConfig and savedConfig.parentId then
                local resolved = modules.game_sidebars.resolvePanelById(savedConfig.parentId)
                if resolved and resolved:isVisible() then
                    savedPanel = resolved
                    -- Store config to apply height/minimized/locked after addChild
                    containerWindow._earlySavedConfig = savedConfig
                end
            end
        end

        local panel
        local usedSavedPanel = false
        if savedPanel then
            panel = savedPanel
            usedSavedPanel = true
        else
            panel = modules.game_interface.findContentPanelAvailable(containerWindow, cellSize.height)
            -- If the chosen panel can't fit the container without overflow, check if
            -- any other panel has more space. Containers are important enough to accept
            -- overflow as a last resort, but we prefer a panel that actually has room.
            if panel and panel:fits(containerWindow, cellSize.height, 0) < 0 then
                local bestPanel = nil
                local bestSpace = -1
                local panelsList = modules.game_interface.panelsList
                if panelsList then
                    for _, entry in ipairs(panelsList) do
                        if entry.panel:isVisible() and entry.panel ~= panel then
                            local space = entry.panel:fits(containerWindow, 0, 0)
                            if space > bestSpace then
                                bestSpace = space
                                bestPanel = entry.panel
                            end
                        end
                    end
                end
                if bestPanel and bestSpace > (panel:fits(containerWindow, 0, 0) or -1) then
                    panel = bestPanel
                end
            end
        end

        panel:addChild(containerWindow)

        -- If we placed directly into the saved panel, apply saved state and mark
        -- as restored so the synchronous restore block below won't do a redundant
        -- remove+insert cycle that would trigger another fitAll.
        if usedSavedPanel and containerWindow._earlySavedConfig then
            local sc = containerWindow._earlySavedConfig
            if sc.height then
                containerWindow:setHeight(sc.height)
            end
            if sc.minimized and containerWindow.minimize then
                containerWindow:minimize()
            end
            if sc.locked and containerWindow.lock then
                scheduleEvent(function()
                    if containerWindow and containerWindow:getParent() then
                        containerWindow:lock(true)
                    end
                end, 100)
            end
            containerWindow._earlySavedConfig = nil
            containerWindow.containerRestored = true
        end

        -- Only set the content height for new containers, not when changing pages
        local minRows = 1
        local contentH
        if modules.client_options.getOption('openMaximized') then
            local numLines = math.max(layout:getNumLines(), minRows)
            contentH = cellSize.height * numLines + pagePanelOffset
        else
            local filledLines = math.max(math.ceil(container:getItemsCount() / layout:getNumColumns()), minRows)
            contentH = filledLines * cellSize.height + pagePanelOffset
        end

        containerWindow:setContentHeight(contentH)
    end

    -- Enforce minimum window height for paged containers
    -- This runs for both new containers and reused windows (previousContainer)
    if hasPages then
        local minWindowHeight = cellSize.height + 55
        if containerWindow:getHeight() < minWindowHeight then
            containerWindow:setHeight(minWindowHeight)
        end
        scheduleEvent(function()
            if containerWindow and containerWindow:getParent() then
                if containerWindow:getHeight() < minWindowHeight then
                    containerWindow:setHeight(minWindowHeight)
                end
            end
        end, 50)
    end

    containerWindow:setup()

    -- Track open container instance
    openContainerInstances[containerId] = containerWindow

    -- containerWindow.containerName was already set above with the full (non-truncated) name

    -- Calculate nameIndex for this container (which "backpack" is this? 1st, 2nd, etc.)
    -- nameIndex is calculated based on instance order, not open order
    -- We'll recalculate this properly at save/restore time based on instance sorting
    local containerNameLower = fullName:lower()
    local currentNameIndex = 1

    -- Count how many containers with the same name have lower instance IDs
    for otherInstance, otherWidget in pairs(openContainerInstances) do
        if otherWidget and otherWidget.containerName and otherWidget.containerName:lower() == containerNameLower then
            if otherInstance < containerId then
                currentNameIndex = currentNameIndex + 1
            end
        end
    end

    containerWindow.nameIndex = currentNameIndex

    -- Synchronous restore: move container to saved panel if config is loaded (RubinOT style).
    -- Uses sidebars module's resolvePanelById and moveContainerToPanel utilities.
    local configLoaded = modules.game_sidebars and modules.game_sidebars.isConfigLoaded and
    modules.game_sidebars.isConfigLoaded()

    if configLoaded then
        if modules.game_sidebars.getContainerConfig then
            local savedConfig = modules.game_sidebars.getContainerConfig(containerId, fullName, currentNameIndex)
            local currentParent = containerWindow:getParent()
            local currentParentId = currentParent and currentParent:getId() or "unknown"

            if savedConfig and savedConfig.parentId then
                if currentParentId ~= savedConfig.parentId then
                    local targetPanel = modules.game_sidebars.resolvePanelById(savedConfig.parentId)
                    if targetPanel then
                        modules.game_sidebars.moveContainerToPanel(containerWindow, targetPanel, savedConfig)
                    else
                        g_logger.warning("[Containers]   -> target panel " .. savedConfig.parentId .. " NOT FOUND!")
                    end
                else
                    -- Same panel: still apply saved height, minimized, locked state and position
                    modules.game_sidebars.moveContainerToPanel(containerWindow, currentParent, savedConfig)
                end
            end
        end
    end

    -- Apply current sorting mode if one is active and manual sort mode is disabled
    local currentSortMode = containerSettings and containerSettings['currentSortMode']
    local isManualSortEnabled = containerSettings and containerSettings['useManualSortMode'] == 1
    if currentSortMode and currentSortMode ~= 'none' and not isManualSortEnabled then
        sortContainerItems(container, currentSortMode)
    end
end

function onContainerClose(container)
    local containerId = container:getId()
    -- Clean up any pending debounce events for this container
    if containerUpdateEvents[containerId] then
        removeEvent(containerUpdateEvents[containerId])
        containerUpdateEvents[containerId] = nil
    end
    if containerSizeChangeEvents[containerId] then
        removeEvent(containerSizeChangeEvents[containerId])
        containerSizeChangeEvents[containerId] = nil
    end
    pendingContainerUpdates[containerId] = nil

    -- [LootPerf] If this container was replaced (window transferred to new container),
    -- don't clear openContainerInstances or destroy the window since the new container owns it
    if not container.window then
        return
    end

    -- True close: clean up pending refresh and destroy
    if pendingContainerRefresh[containerId] then
        removeEvent(pendingContainerRefresh[containerId].event)
        pendingContainerRefresh[containerId] = nil
    end

    -- Clear saved panel position so the container uses default placement when reopened
    local containerWindow = container.window
    if containerWindow and containerWindow.containerName and modules.game_sidebars and modules.game_sidebars.removeContainerConfig then
        modules.game_sidebars.removeContainerConfig(containerWindow.containerName, containerWindow.nameIndex)
    end

    openContainerInstances[containerId] = nil
    destroy(container)
end

function onContainerChangeSize(container, size)
    if not container.window then
        return
    end

    local containerId = container:getId()

    -- Store height info for later use
    local preservedHeight = container.window.preservedHeight
    local parent = container.window:getParent()

    -- Only schedule ONE event per container - don't cancel/reschedule during burst
    if not containerSizeChangeEvents[containerId] then
        containerSizeChangeEvents[containerId] = scheduleEvent(function()
            containerSizeChangeEvents[containerId] = nil

            if not container.window then
                return
            end

            -- If we have a preserved height (from page switching), disable fitAll during the entire refresh
            if preservedHeight and parent then
                parent.ignoreFillAll = true
            end

            refreshContainerItems(container)

            -- Restore the preserved height if it exists (from page switching)
            if preservedHeight then
                container.window:setHeight(preservedHeight)
                container.window.preservedHeight = nil -- Clear the preserved height

                -- Re-enable fitAll after a small delay to ensure any pending addEvent calls are blocked
                if parent then
                    scheduleEvent(function()
                        if parent then
                            parent.ignoreFillAll = nil
                        end
                    end, 50)
                end
            end
        end, containerUpdateDebounceMs)
    end
end

function onContainerUpdateItem(container, slot, item)
    if not container.window then
        return
    end

    local containerId = container:getId()

    -- Track this slot as needing update (just accumulate, no visual update here)
    if not pendingContainerUpdates[containerId] then
        pendingContainerUpdates[containerId] = {}
    end
    pendingContainerUpdates[containerId][slot] = { item = item }

    -- Only schedule ONE event per container - don't cancel/reschedule during burst
    -- This is key: we let the scheduled event run after all sync updates finish
    if not containerUpdateEvents[containerId] then
        containerUpdateEvents[containerId] = scheduleEvent(function()
            containerUpdateEvents[containerId] = nil

            -- Process all pending updates for this container
            local updates = pendingContainerUpdates[containerId]
            pendingContainerUpdates[containerId] = nil

            if not updates or not container.window or not container.itemsPanel then
                return
            end

            -- Disable layout updates during batch
            local layout = container.itemsPanel:getLayout()
            if layout then
                layout:disableUpdates()
            end

            -- Apply all pending slot updates
            for updateSlot, updateData in pairs(updates) do
                local itemWidget = container.itemsPanel:getChildById('item' .. updateSlot)
                if itemWidget then
                    itemWidget:setItem(updateData.item)
                    ItemsDatabase.setRarityItem(itemWidget, updateData.item)
                    ItemsDatabase.setTier(itemWidget, updateData.item)
                    if ItemsDatabase.updateQuickLootFlags then ItemsDatabase.updateQuickLootFlags(itemWidget, updateData.item) end
                    if modules.client_options.getOption('showExpiryInContainers') then
                        ItemsDatabase.setCharges(itemWidget, updateData.item)
                        ItemsDatabase.setDuration(itemWidget, updateData.item)
                    end
                end
            end

            -- Re-enable layout and trigger single update
            if layout then
                layout:enableUpdates()
                layout:update()
            end
        end, containerUpdateDebounceMs)
    end
end

-- Get all open containers for saving
-- Restore a container to a specific panel (RubinOT style).
-- Parameters match RubinOT's containers.move(instance, panel, height, index, minimized, locked)
function move(instance, panel, height, index, minimized, locked)
    local containerWidgetId = 'container' .. instance
    local widget = rootWidget:recursiveGetChildById(containerWidgetId)

    if not widget or not panel then
        return nil
    end

    widget:setParent(panel)
    widget:open()

    if minimized then
        widget:setHeight(height)
        if widget.minimize then
            widget:minimize()
        end
    else
        if widget.maximize then
            widget:maximize()
        end
        widget:setHeight(height)
    end

    if locked and widget.lock then
        scheduleEvent(function()
            if not widget then return end
            widget:lock(true)
        end, 100)
    end

    return widget
end
