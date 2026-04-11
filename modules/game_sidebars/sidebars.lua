-- game_sidebars module
-- Saves and restores sidebar widget positions per character using JSON

local SideBars = {
    sidebarWidgetsConfig = {},
    horizontalLeftConfig = {},
    horizontalRightConfig = {},
    openAnalysers = {},
    openContainers = {},
}

local configLoaded = false
local pendingContainerRestores = {} -- Containers that opened before config was loaded

function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })
end

function onGameStart()
    configLoaded = false
    pendingContainerRestores = {} -- Clear pending containers from previous session
    resetContainerConfigs() -- Reset used container configs for new session
    loadConfigJson()
end

function onGameEnd()
    -- Save config when player logs out
    saveConfigJson()
    configLoaded = false
end

function getCharacterDataPath()
    local player = g_game.getLocalPlayer()
    if not player then
        return nil
    end

    local playerId = player:getId()
    if not playerId then
        return nil
    end

    return "/characterdata/" .. playerId
end

function loadConfigJson()
    local charPath = getCharacterDataPath()
    if not charPath then
        return false
    end

    local file = charPath .. "/sidebars.json"
    if not g_resources.fileExists(file) then
        return false
    end

    local status, result = pcall(function()
        return json.decode(g_resources.readFileContents(file))
    end)

    if not status or not result then
        g_logger.warning("Failed to load sidebars config: " .. tostring(result))
        return false
    end

    -- Validate the loaded data structure
    if type(result) ~= "table" then
        g_logger.warning("Invalid sidebars config format")
        return false
    end

    -- Only load horizontal panel configs, ignore normal panel configs
    -- Normal panels use the existing CharMiniWindows system
    SideBars.horizontalLeftConfig = result.horizontalLeftConfig or {}
    SideBars.horizontalRightConfig = result.horizontalRightConfig or {}
    SideBars.openAnalysers = result.openAnalysers or {} -- Load saved analyser widgets
    SideBars.openContainers = result.openContainers or {} -- Load saved container widgets
    SideBars.sidebarWidgetsConfig = {} -- Don't restore normal panel configs

    configLoaded = true

    -- Process containers that opened before config was loaded
    processPendingContainers()

    -- Restore widgets with a single delay to ensure all panels are ready
    scheduleEvent(function()
        restoreAllWidgets()
    end, 500)

    return true
end

-- Check if config was loaded
function isConfigLoaded()
    return configLoaded
end

function saveConfigJson()
    local charPath = getCharacterDataPath()
    if not charPath then
        return false
    end

    -- Ensure directory exists
    pcall(function() g_resources.makeDir("/characterdata") end)
    pcall(function() g_resources.makeDir(charPath) end)

    -- Collect all widget configurations
    collectAllWidgetConfigs()

    local file = charPath .. "/sidebars.json"
    local status, result = pcall(function()
        return json.encode(SideBars, 2)
    end)

    if not status then
        g_logger.error("Error encoding sidebars config: " .. tostring(result))
        return false
    end

    -- Safety check for file size
    if result:len() > 10 * 1024 * 1024 then
        g_logger.error("Sidebars config too large, not saving")
        return false
    end

    -- Safely attempt to write the file
    local writeStatus, writeError = pcall(function()
        return g_resources.writeFileContents(file, result)
    end)

    if not writeStatus then
        g_logger.error("Could not save sidebars config: " .. tostring(writeError))
        return false
    end

    return true
end


-- Collect configurations from horizontal panels and analyser widgets
function collectAllWidgetConfigs()
    SideBars.sidebarWidgetsConfig = {}
    SideBars.horizontalLeftConfig = {}
    SideBars.horizontalRightConfig = {}
    SideBars.openAnalysers = {} -- Store open analyser widgets
    SideBars.openContainers = {} -- Store open container widgets

    local m_interface = modules.game_interface
    if not m_interface then
        return
    end

    -- Collect from horizontal panels
    local horizontalLeft = m_interface.getHorizontalLeftPanel and m_interface.getHorizontalLeftPanel()
    local horizontalRight = m_interface.getHorizontalRightPanel and m_interface.getHorizontalRightPanel()

    if horizontalLeft and horizontalLeft:getChildCount() > 0 then
        SideBars.horizontalLeftConfig.height = horizontalLeft:getHeight()
        SideBars.horizontalLeftConfig.widgets = {}
        for childIndex, widget in ipairs(horizontalLeft:getChildren()) do
            local widgetConfig = collectWidgetConfig(widget, childIndex)
            if widgetConfig then
                table.insert(SideBars.horizontalLeftConfig.widgets, widgetConfig)
            end
        end
    end

    if horizontalRight and horizontalRight:getChildCount() > 0 then
        SideBars.horizontalRightConfig.height = horizontalRight:getHeight()
        SideBars.horizontalRightConfig.widgets = {}
        for childIndex, widget in ipairs(horizontalRight:getChildren()) do
            local widgetConfig = collectWidgetConfig(widget, childIndex)
            if widgetConfig then
                table.insert(SideBars.horizontalRightConfig.widgets, widgetConfig)
            end
        end
    end

    -- Collect open analyser widgets
    if modules.game_analyser and modules.game_analyser.getOpenAnalysers then
        local openAnalysers = modules.game_analyser.getOpenAnalysers()
        for _, analyserInfo in ipairs(openAnalysers) do
            table.insert(SideBars.openAnalysers, {
                type = analyserInfo.type,
                height = analyserInfo.height,
                minimized = analyserInfo.minimized,
                parentId = analyserInfo.parentId
            })
        end
    end

    -- Collect open container widgets
    if modules.game_containers and modules.game_containers.getOpenContainers then
        local openContainers = modules.game_containers.getOpenContainers()
        for _, containerInfo in ipairs(openContainers) do
            table.insert(SideBars.openContainers, {
                type = containerInfo.type,
                instance = containerInfo.instance,
                name = containerInfo.name,
                nameIndex = containerInfo.nameIndex,
                height = containerInfo.height,
                minimized = containerInfo.minimized,
                locked = containerInfo.locked,
                parentId = containerInfo.parentId
            })
        end
    end
end

-- Collect config for a single widget
function collectWidgetConfig(widget, index)
    if not widget then
        return nil
    end

    local widgetId = widget:getId()
    local widgetType = widget.type or widgetId

    -- Skip certain widgets
    if not widgetId or widgetId == "" then
        return nil
    end

    local config = {
        id = widgetId,
        type = widgetType,
        index = index,
        height = widget:getHeight(),
        width = widget:getWidth(),
        minimized = widget.minimized or false,
        closed = not widget:isVisible(),
        locked = widget.isLocked and widget:isLocked() or false,
    }

    -- For minimized widgets, store the maximized height
    if widget.minimized and widget.maximizedHeight then
        config.height = widget.maximizedHeight
    end

    return config
end

-- Restore all widgets from saved config
-- ONLY restores widgets to horizontal panels, not to normal panels
-- Normal panel order is handled by the existing CharMiniWindows system
function restoreAllWidgets()
    local m_interface = modules.game_interface
    if not m_interface then
        return
    end

    -- Restore horizontal left panel
    if SideBars.horizontalLeftConfig and SideBars.horizontalLeftConfig.widgets then
        local panel = m_interface.getHorizontalLeftPanel and m_interface.getHorizontalLeftPanel()
        if panel and #SideBars.horizontalLeftConfig.widgets > 0 then
            for _, widgetConfig in ipairs(SideBars.horizontalLeftConfig.widgets) do
                restoreWidgetToHorizontalPanel(widgetConfig, panel)
            end
            m_interface.showLeftHorizontalPanel(true)
        end
    end

    -- Restore horizontal right panel (só se a opção da interface estiver ligada)
    if modules.client_options and modules.client_options.getOption('showHorizontalRightPanel') then
        if SideBars.horizontalRightConfig and SideBars.horizontalRightConfig.widgets then
            local panel = m_interface.getHorizontalRightPanel and m_interface.getHorizontalRightPanel()
            if panel and #SideBars.horizontalRightConfig.widgets > 0 then
                for _, widgetConfig in ipairs(SideBars.horizontalRightConfig.widgets) do
                    restoreWidgetToHorizontalPanel(widgetConfig, panel)
                end
                m_interface.showRightHorizontalPanel(true)
            end
        end
    end

    -- Restore open analyser widgets
    if SideBars.openAnalysers and #SideBars.openAnalysers > 0 then
        for _, analyserConfig in ipairs(SideBars.openAnalysers) do
            restoreAnalyserWidget(analyserConfig)
        end
    end

    -- Restore containers that are already open (they may have opened before config was loaded)
    -- Try immediately first, then with delays because the server may close and reopen containers during login
    if SideBars.openContainers and #SideBars.openContainers > 0 then
        restoreOpenContainers()
        scheduleEvent(function()
            restoreOpenContainers()
        end, 500)
        scheduleEvent(function()
            restoreOpenContainers()
        end, 1500)
    end
end

-- Restore containers that are already open when config is loaded
function restoreOpenContainers()
    if not modules.game_containers then
        return
    end

    local openInstances = modules.game_containers.openContainerInstances
    if not openInstances then
        return
    end

    -- Build sorted list of containers with their names from the widget
    local sortedInstances = {}
    for instance, widget in pairs(openInstances) do
        if widget and widget.containerName then
            table.insert(sortedInstances, {
                instance = instance,
                widget = widget,
                containerName = widget.containerName
            })
        end
    end
    table.sort(sortedInstances, function(a, b) return a.instance < b.instance end)

    -- Recalculate nameIndex based on current open containers (order by instance)
    local currentNameCounts = {}
    for _, data in ipairs(sortedInstances) do
        local nameLower = data.containerName:lower()
        currentNameCounts[nameLower] = (currentNameCounts[nameLower] or 0) + 1
        data.nameIndex = currentNameCounts[nameLower]
        data.widget.nameIndex = data.nameIndex
    end

    for _, data in ipairs(sortedInstances) do
        local savedConfig = getContainerConfig(data.instance, data.containerName, data.nameIndex)
        if savedConfig and savedConfig.parentId then
            local capturedInstance = data.instance
            local capturedConfig = savedConfig
            scheduleEvent(function()
                if modules.game_containers and modules.game_containers.move then
                    modules.game_containers.move(capturedInstance, nil, capturedConfig.height, capturedConfig.minimized, capturedConfig.locked, capturedConfig.parentId)
                end
            end, 100)
        end
    end
end

-- Restore a single analyser widget using the game_analyser module
function restoreAnalyserWidget(analyserConfig)
    if not analyserConfig or not analyserConfig.type then
        return false
    end

    -- Get the target panel
    local m_interface = modules.game_interface
    if not m_interface then
        return false
    end

    local panel = nil
    local parentId = analyserConfig.parentId

    if parentId == "horizontalLeftPanel" then
        panel = m_interface.getHorizontalLeftPanel and m_interface.getHorizontalLeftPanel()
    elseif parentId == "horizontalRightPanel" then
        panel = m_interface.getHorizontalRightPanel and m_interface.getHorizontalRightPanel()
    elseif parentId == "gameLeftPanel" then
        panel = m_interface.getLeftPanel and m_interface.getLeftPanel()
    elseif parentId == "gameRightPanel" then
        panel = m_interface.getRightPanel and m_interface.getRightPanel()
    elseif parentId == "gameLeftExtraPanel" then
        panel = m_interface.getLeftExtraPanel and m_interface.getLeftExtraPanel()
    elseif parentId == "gameLeftExtraPanel2" then
        panel = m_interface.getLeftExtraPanel2 and m_interface.getLeftExtraPanel2()
    elseif parentId == "gameLeftExtraPanel3" then
        panel = m_interface.getLeftExtraPanel3 and m_interface.getLeftExtraPanel3()
    elseif parentId == "gameRightExtraPanel" then
        panel = m_interface.getRightExtraPanel and m_interface.getRightExtraPanel()
    elseif parentId == "gameRightExtraPanel2" then
        panel = m_interface.getRightExtraPanel2 and m_interface.getRightExtraPanel2()
    elseif parentId == "gameRightExtraPanel3" then
        panel = m_interface.getRightExtraPanel3 and m_interface.getRightExtraPanel3()
    elseif parentId == "gameMainRightPanel" then
        panel = m_interface.getMainRightPanel and m_interface.getMainRightPanel()
    else
        -- Try to find panel by ID
        panel = rootWidget:recursiveGetChildById(parentId)
    end

    if not panel then
        -- Use default panel
        panel = m_interface.getRightPanel and m_interface.getRightPanel()
    end

    if not panel then
        return false
    end

    -- Use the game_analyser module to restore the widget
    if modules.game_analyser and modules.game_analyser.moveChildAnalyser then
        local height = analyserConfig.height or 200
        local minimized = analyserConfig.minimized or false
        local widget = modules.game_analyser.moveChildAnalyser(analyserConfig.type, panel, height, minimized)
        return widget ~= nil
    end

    return false
end

-- Restore a single container widget using the game_containers module
function restoreContainerWidget(containerConfig)
    if not containerConfig or not containerConfig.instance then
        return false
    end

    local m_interface = modules.game_interface
    if not m_interface then
        return false
    end

    local panel = nil
    local parentId = containerConfig.parentId

    if parentId == "horizontalLeftPanel" then
        panel = m_interface.getHorizontalLeftPanel and m_interface.getHorizontalLeftPanel()
    elseif parentId == "horizontalRightPanel" then
        panel = m_interface.getHorizontalRightPanel and m_interface.getHorizontalRightPanel()
    elseif parentId == "gameLeftPanel" then
        panel = m_interface.getLeftPanel and m_interface.getLeftPanel()
    elseif parentId == "gameRightPanel" then
        panel = m_interface.getRightPanel and m_interface.getRightPanel()
    elseif parentId == "gameLeftExtraPanel" then
        panel = m_interface.getLeftExtraPanel and m_interface.getLeftExtraPanel()
    elseif parentId == "gameLeftExtraPanel2" then
        panel = m_interface.getLeftExtraPanel2 and m_interface.getLeftExtraPanel2()
    elseif parentId == "gameLeftExtraPanel3" then
        panel = m_interface.getLeftExtraPanel3 and m_interface.getLeftExtraPanel3()
    elseif parentId == "gameRightExtraPanel" then
        panel = m_interface.getRightExtraPanel and m_interface.getRightExtraPanel()
    elseif parentId == "gameRightExtraPanel2" then
        panel = m_interface.getRightExtraPanel2 and m_interface.getRightExtraPanel2()
    elseif parentId == "gameRightExtraPanel3" then
        panel = m_interface.getRightExtraPanel3 and m_interface.getRightExtraPanel3()
    elseif parentId == "gameMainRightPanel" then
        panel = m_interface.getMainRightPanel and m_interface.getMainRightPanel()
    else
        panel = rootWidget:recursiveGetChildById(parentId)
    end

    if not panel then
        panel = m_interface.getRightPanel and m_interface.getRightPanel()
    end

    if not panel then
        return false
    end

    if modules.game_containers and modules.game_containers.move then
        local height = containerConfig.height or 200
        local minimized = containerConfig.minimized or false
        local locked = containerConfig.locked or false
        local widget = modules.game_containers.move(containerConfig.instance, panel, height, minimized, locked)
        return widget ~= nil
    end

    return false
end

-- Restore a widget specifically to a horizontal panel
function restoreWidgetToHorizontalPanel(widgetConfig, targetPanel)
    if not widgetConfig or not widgetConfig.id or not targetPanel then
        return false
    end

    local widget = rootWidget:recursiveGetChildById(widgetConfig.id)
    if not widget then
        return false
    end

    local currentParent = widget:getParent()

    -- Skip if already in correct panel
    if currentParent == targetPanel then
        return true
    end

    -- Skip if widget is not visible (closed)
    if not widget:isVisible() then
        return false
    end

    -- Remove from current parent
    if currentParent then
        currentParent:removeChild(widget)
        if currentParent.fitAllChildren then
            currentParent:fitAllChildren()
        end
    end

    -- Add to horizontal panel
    targetPanel:addChild(widget)
    targetPanel:setPhantom(false)

    -- Resize for horizontal panel
    addEvent(function()
        if widget and targetPanel then
            widget:setWidth(targetPanel:getWidth())
            widget:setHeight(targetPanel:getHeight())
        end
    end)

    return true
end

-- Restore a single widget to a panel
function restoreWidget(widgetConfig, targetPanel, isHorizontal)
    if not widgetConfig or not widgetConfig.id or not targetPanel then
        return false
    end

    local widget = rootWidget:recursiveGetChildById(widgetConfig.id)
    if not widget then
        return false
    end

    local currentParent = widget:getParent()

    -- Skip if already in correct panel
    if currentParent == targetPanel then
        -- Just restore state
        if widgetConfig.height and widget.setHeight then
            widget:setHeight(widgetConfig.height)
        end
        if widgetConfig.minimized and widget.minimize then
            widget:minimize(true)
        end
        -- Restore open/closed state
        if widgetConfig.closed then
            if widget.close then
                widget:close(true)
            end
        else
            if widget.open then
                widget:open(true)
            end
        end
        return true
    end

    -- Remove from current parent
    if currentParent then
        currentParent:removeChild(widget)
        if currentParent.fitAllChildren then
            currentParent:fitAllChildren()
        end
    end

    -- Add to target panel
    if isHorizontal then
        targetPanel:addChild(widget)
        targetPanel:setPhantom(false)

        -- Resize for horizontal panel
        addEvent(function()
            if widget and targetPanel then
                widget:setWidth(targetPanel:getWidth())
                widget:setHeight(targetPanel:getHeight())
            end
        end)
    else
        -- Normal panel - insert at saved index
        local index = widgetConfig.index or 1
        if index > targetPanel:getChildCount() + 1 then
            index = targetPanel:getChildCount() + 1
        end
        targetPanel:insertChild(index, widget)

        -- Restore height
        if widgetConfig.height and widget.setHeight then
            widget:setHeight(widgetConfig.height)
        end
    end

    -- Restore states
    if widgetConfig.minimized and widget.minimize then
        widget:minimize(true)
    end

    if widgetConfig.locked and widget.lock then
        widget:lock(true)
    end

    if widgetConfig.closed then
        if widget.close then
            widget:close(true)
        end
    else
        if widget.open then
            widget:open(true)
        end
    end

    return true
end

-- Public API for other modules
function getConfig()
    return SideBars
end

function setConfig(config)
    SideBars = config
end

function resetConfig()
    SideBars = {
        sidebarWidgetsConfig = {},
        horizontalLeftConfig = {},
        horizontalRightConfig = {},
        openAnalysers = {},
        openContainers = {},
    }
end

-- Track which configs have been used this session (to handle multiple containers with same name)
local usedContainerConfigs = {}

-- Reset used configs on game start
function resetContainerConfigs()
    usedContainerConfigs = {}
end

-- Register a container that opened before config was loaded
function registerPendingContainer(containerId, containerName, nameIndex, containerWindow)
    if configLoaded then
        return false
    end
    table.insert(pendingContainerRestores, {
        containerId = containerId,
        containerName = containerName,
        nameIndex = nameIndex,
        containerWindow = containerWindow
    })
    return true
end

-- Process containers that opened before config was loaded
function processPendingContainers()
    if #pendingContainerRestores == 0 then
        return
    end

    for _, pending in ipairs(pendingContainerRestores) do
        local savedConfig = getContainerConfig(pending.containerId, pending.containerName, pending.nameIndex)
        if savedConfig and savedConfig.parentId and pending.containerWindow and pending.containerWindow:getParent() then
            local currentParentId = pending.containerWindow:getParent():getId()
            if currentParentId ~= savedConfig.parentId then
                if modules.game_containers and modules.game_containers.move then
                    modules.game_containers.move(pending.containerId, nil, savedConfig.height, savedConfig.minimized, savedConfig.locked, savedConfig.parentId)
                end
            end
        end
    end

    pendingContainerRestores = {}
end

-- Get saved container config by container name and nameIndex
-- The containerId changes between sessions, but the name (e.g., "backpack") stays the same
-- nameIndex helps distinguish between multiple containers with the same name
-- Note: We don't mark configs as "used" anymore because the server may close and reopen containers
function getContainerConfig(containerId, containerName, nameIndex)
    if not configLoaded or not SideBars.openContainers then
        return nil
    end

    -- Search by name (case-insensitive) and nameIndex since IDs change between sessions
    if containerName then
        local searchName = containerName:lower()
        for _, containerConfig in ipairs(SideBars.openContainers) do
            local configNameLower = containerConfig.name and containerConfig.name:lower() or ""
            if containerConfig.name and configNameLower == searchName then
                if nameIndex and containerConfig.nameIndex and containerConfig.nameIndex == nameIndex then
                    return containerConfig
                elseif not nameIndex then
                    return containerConfig
                end
            end
        end
    end

    return nil
end

-- Restore a specific widget by ID (called by individual modules when they initialize)
-- Only restores to horizontal panels - normal panel positioning uses CharMiniWindows
function restoreWidgetById(widgetId)
    if not configLoaded or not widgetId then
        return false
    end

    local widget = rootWidget:recursiveGetChildById(widgetId)
    if not widget then
        return false
    end

    local m_interface = modules.game_interface
    if not m_interface then
        return false
    end

    -- Check if widget is in horizontal left config
    if SideBars.horizontalLeftConfig and SideBars.horizontalLeftConfig.widgets then
        for _, widgetConfig in ipairs(SideBars.horizontalLeftConfig.widgets) do
            if widgetConfig.id == widgetId then
                local panel = m_interface.getHorizontalLeftPanel and m_interface.getHorizontalLeftPanel()
                if panel then
                    restoreWidgetToHorizontalPanel(widgetConfig, panel)
                    m_interface.showLeftHorizontalPanel(true)
                    return true
                end
            end
        end
    end

    if modules.client_options and modules.client_options.getOption('showHorizontalRightPanel') then
        if SideBars.horizontalRightConfig and SideBars.horizontalRightConfig.widgets then
            for _, widgetConfig in ipairs(SideBars.horizontalRightConfig.widgets) do
                if widgetConfig.id == widgetId then
                    local panel = m_interface.getHorizontalRightPanel and m_interface.getHorizontalRightPanel()
                    if panel then
                        restoreWidgetToHorizontalPanel(widgetConfig, panel)
                        m_interface.showRightHorizontalPanel(true)
                        return true
                    end
                end
            end
        end
    end

    -- For normal panels, don't move the widget - let CharMiniWindows handle it
    return false
end

-- Get widget config by ID
function getWidgetConfig(widgetId)
    if not configLoaded or not widgetId then
        return nil
    end

    -- Check horizontal left
    if SideBars.horizontalLeftConfig and SideBars.horizontalLeftConfig.widgets then
        for _, widgetConfig in ipairs(SideBars.horizontalLeftConfig.widgets) do
            if widgetConfig.id == widgetId then
                return widgetConfig, "horizontalLeft"
            end
        end
    end

    -- Check horizontal right
    if SideBars.horizontalRightConfig and SideBars.horizontalRightConfig.widgets then
        for _, widgetConfig in ipairs(SideBars.horizontalRightConfig.widgets) do
            if widgetConfig.id == widgetId then
                return widgetConfig, "horizontalRight"
            end
        end
    end

    -- Check normal panels
    if SideBars.sidebarWidgetsConfig then
        for panelId, widgets in pairs(SideBars.sidebarWidgetsConfig) do
            for _, widgetConfig in ipairs(widgets) do
                if widgetConfig.id == widgetId then
                    return widgetConfig, panelId
                end
            end
        end
    end

    return nil
end

-- Called by game_containers before destroying container windows.
-- Ensures sidebar state is saved while widgets are still alive.
function onContainersAboutToClose()
    saveConfigJson()
end
