-- Minimap Module
minimapWidget = nil
minimapWindow = nil

local otmm = true
local fullmapView = false
local oldZoom = nil
local oldPos = nil

-- Store original/default panel for minimap restoration
local defaultMinimapPanel = nil
local defaultMinimapIndex = nil

-- Esquerda (Balrog): vazio => phantom true. Direita: mantém faixa interactiva se opção ligada e altura > 0.
local function updateHorizontalStripPhantomIfNowEmpty(panel)
  if not panel or not panel.getId then
    return
  end
  local pid = panel:getId()
  if pid == "horizontalLeftPanel" then
    if panel:getChildCount() == 0 then
      panel:setPhantom(true)
    end
    return
  end
  if pid ~= "horizontalRightPanel" then
    return
  end
  if panel:getChildCount() > 0 then
    return
  end
  local shown = panel:getHeight() > 0
  if modules.client_options then
    shown = shown and modules.client_options.getOption('showHorizontalRightPanel')
  end
  if shown then
    panel:setPhantom(false)
  else
    panel:setPhantom(true)
  end
end

-- Helper function to calculate time display position
local function checkXByHour(x)
  local y0 = 62
  local incremento = y0 / 12
  local result = math.floor(y0 + (x * incremento))
  if result > 124 then
    result = result - 124
  end
  return result
end

-- Update floor indicator image
local function updateFloorImage(posZ)
  if minimapWindow and minimapWindow.floorPosition then
    minimapWindow.floorPosition:setImageClip((posZ) * 14 .. " 0 14 67")
  end
end

-- Position change callback
local function onPositionChange(creature, newPos, oldPos)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  local pos = player:getPosition()
  if not pos then
    return
  end

  if not minimapWidget or minimapWidget:isDragging() then
    return
  end

  if not fullmapView then
    minimapWidget:setCameraPosition(pos)
  end

  minimapWidget:setCrossPosition(pos)

  if newPos and oldPos and newPos.z ~= oldPos.z then
    updateFloorImage(pos.z)
  end
end

-- Server time callback
local function onServerTime(hours, minutes)
  if not minimapWindow or not minimapWindow.centerMap then
    return
  end
  minimapWindow.centerMap:setImageClip(checkXByHour(hours) .. " 0 31 31")
end

-- Controller setup
mapController = Controller:new()
mapController:setUI('minimap', modules.game_interface.getMainRightPanel())

function mapController:onInit()
  minimapWindow = self.ui
  minimapWidget = minimapWindow:recursiveGetChildById('minimap')

  -- Allow minimap to be placed in main right panel (and other panels)
  minimapWindow.allowInMainRightPanel = true

  -- Hide built-in minimap buttons (we use custom ones from OTUI)
  local floorUpButton = minimapWidget:getChildById('floorUpButton')
  local floorDownButton = minimapWidget:getChildById('floorDownButton')
  local zoomInButton = minimapWidget:getChildById('zoomInButton')
  local zoomOutButton = minimapWidget:getChildById('zoomOutButton')
  local resetButton = minimapWidget:getChildById('resetButton')

  if floorUpButton then floorUpButton:hide() end
  if floorDownButton then floorDownButton:hide() end
  if zoomInButton then zoomInButton:hide() end
  if zoomOutButton then zoomOutButton:hide() end
  if resetButton then resetButton:hide() end

  -- Setup minimap window (skip if no close/minimize buttons)
  local closeButton = self.ui:getChildById('closeButton')
  local minimizeButton = self.ui:getChildById('minimizeButton')
  if closeButton and minimizeButton then
    self.ui:setup()
  end

  -- Setup mouse wheel on floor position widget for floor change
  if minimapWindow.floorPosition then
    minimapWindow.floorPosition.onMouseWheel = function(widget, mousePos, direction)
      if direction == MouseWheelUp then
        minimapWidget:floorUp(1)
      elseif direction == MouseWheelDown then
        minimapWidget:floorDown(1)
      end
      updateFloorImage(minimapWidget:getCameraPosition().z)
      return true
    end
  end

  -- Save default position after UI is initialized
  addEvent(function()
    saveMinimapDefaultPosition()
  end, 100)
end

function mapController:onGameStart()
  mapController:registerEvents(g_game, {
    onServerTime = onServerTime
  })

  mapController:registerEvents(LocalPlayer, {
    onPositionChange = onPositionChange
  }):execute()

  -- Restore minimap position from saved settings (with delay to ensure panels are ready)
  scheduleEvent(function()
    if minimapWindow then
      restoreMinimapPosition()

      -- Additional check after restore to ensure minimap is visible
      scheduleEvent(function()
        ensureMinimapVisible()
      end, 100)
    end
  end, 150)

  -- Load Map
  g_minimap.clean()

  local minimapFile = '/minimap'
  local defaultMinimapFile = '/data/minimap'

  if otmm then
    minimapFile = minimapFile .. '.otmm'
    defaultMinimapFile = defaultMinimapFile .. '.otmm'

    -- If user minimap doesn't exist but default exists, load default minimap (first use)
    if not g_resources.fileExists(minimapFile) and g_resources.fileExists(defaultMinimapFile) then
      g_minimap.loadOtmm(defaultMinimapFile)
      -- Save it to user directory so it persists
      g_minimap.saveOtmm(minimapFile)
    elseif g_resources.fileExists(minimapFile) then
      g_minimap.loadOtmm(minimapFile)
    end
  else
    minimapFile = minimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'
    defaultMinimapFile = defaultMinimapFile .. '_' .. g_game.getClientVersion() .. '.otcm'

    -- If user minimap doesn't exist but default exists, load default minimap (first use)
    if not g_resources.fileExists(minimapFile) and g_resources.fileExists(defaultMinimapFile) then
      g_map.loadOtcm(defaultMinimapFile)
      g_map.saveOtcm(minimapFile)
    elseif g_resources.fileExists(minimapFile) then
      g_map.loadOtcm(minimapFile)
    end
  end

  minimapWidget:load()
end

function mapController:onGameEnd()
  -- Save Map
  if otmm then
    g_minimap.saveOtmm('/minimap.otmm')
  else
    g_map.saveOtcm('/minimap_' .. g_game.getClientVersion() .. '.otcm')
  end

  minimapWidget:save()
end

function mapController:onTerminate()
  -- Cleanup if needed
end

-- Public functions called from OTUI

function zoom(zoomIn)
  if not minimapWidget then return end
  if zoomIn then
    minimapWidget:zoomIn()
  else
    minimapWidget:zoomOut()
  end
end

function floor(floorUp)
  if not minimapWidget then return end
  if floorUp then
    minimapWidget:floorUp(1)
  else
    minimapWidget:floorDown(1)
  end
  updateFloorImage(minimapWidget:getCameraPosition().z)
end

function center()
  if not minimapWidget then return end
  minimapWidget:reset()
end

function compassMove(direction)
  if not minimapWidget then return end

  local moveAmount = 10
  if direction == 'north' then
    minimapWidget:move(0, moveAmount)
  elseif direction == 'south' then
    minimapWidget:move(0, -moveAmount)
  elseif direction == 'east' then
    minimapWidget:move(-moveAmount, 0)
  elseif direction == 'west' then
    minimapWidget:move(moveAmount, 0)
  elseif direction == 'northeast' then
    minimapWidget:move(-moveAmount, moveAmount)
  elseif direction == 'northwest' then
    minimapWidget:move(moveAmount, moveAmount)
  elseif direction == 'southeast' then
    minimapWidget:move(-moveAmount, -moveAmount)
  elseif direction == 'southwest' then
    minimapWidget:move(moveAmount, -moveAmount)
  end
end

function onClose()
  -- Called when minimap window is closed
end

-- Accessor functions

function getMiniMapUi()
  return minimapWidget
end

function getMinimapWindow()
  return minimapWindow
end

-- Panel management functions

function restoreMinimapToDefault()
  if not minimapWindow then
    return false
  end

  local targetPanel = defaultMinimapPanel or modules.game_interface.getMainRightPanel()
  if not targetPanel then
    return false
  end

  local currentParent = minimapWindow:getParent()
  if currentParent == targetPanel then
    return true
  end

  if currentParent then
    currentParent:removeChild(minimapWindow)

    local currentParentId = currentParent:getId()
    if currentParentId == "horizontalLeftPanel" or currentParentId == "horizontalRightPanel" then
      updateHorizontalStripPhantomIfNowEmpty(currentParent)
    end

    -- Auto-fit old parent height
    if currentParent.fitAllChildren then
      currentParent:fitAllChildren()
    end
  end

  minimapWindow:setWidth(minimapWindow.defaultWidth or 178)
  minimapWindow:setHeight(minimapWindow.defaultHeight or 178)

  local insertIndex = defaultMinimapIndex or 1
  targetPanel:insertChild(insertIndex, minimapWindow)

  return true
end

function saveMinimapDefaultPosition()
  if not minimapWindow then
    return
  end

  local parent = minimapWindow:getParent()
  if parent and parent:getClassName() == 'UIMiniWindowContainer' then
    defaultMinimapPanel = parent
    defaultMinimapIndex = parent:getChildIndex(minimapWindow)
  end
end

function moveMinimapToPanel(panel, height, index)
  if not minimapWindow or not panel then
    return nil
  end

  local oldParent = minimapWindow:getParent()
  local panelId = panel:getId()

  if string.find(panelId, "horizontal") then
    addEvent(function()
      minimapWindow:setParent(panel)
      if height then
        minimapWindow:setHeight(height)
      end
      expandMinimapForHorizontalPanel(panel)

      -- Auto-fit old parent height
      if oldParent and oldParent.fitAllChildren then
        oldParent:fitAllChildren()
      end
    end)
  else
    minimapWindow:setParent(panel)
    if height then
      minimapWindow:setHeight(height)
    end

    -- Auto-fit old parent height
    if oldParent and oldParent.fitAllChildren then
      oldParent:fitAllChildren()
    end
  end

  minimapWindow:open()

  return minimapWindow
end

--- Com a opção ativa, coloca o minimapa na faixa horizontal (direita: sai do gameMainRightPanel).
function tryAutoPlaceMinimapForHorizontalPanels()
  if not minimapWindow or not modules.client_options or not modules.game_interface then
    return
  end

  local parent = minimapWindow:getParent()
  local pid = parent and parent:getId() or ''

  if modules.client_options.getOption('showHorizontalRightPanel') then
    local hp = modules.game_interface.getHorizontalRightPanel and modules.game_interface.getHorizontalRightPanel()
    if hp and hp:getHeight() > 0 and pid == 'gameMainRightPanel' then
      moveMinimapToPanel(hp, nil, nil)
      return
    end
  end
end

function expandMinimapForHorizontalPanel(panel)
  if not minimapWindow or not panel then
    return
  end

  -- Use addEvent to ensure the resize happens after the widget is fully placed
  addEvent(function()
    if not minimapWindow or not panel then
      return
    end

    local panelWidth = panel:getWidth()
    local panelId = panel:getId()

    if panelId == 'horizontalLeftPanel' then
      minimapWindow:setWidth(panelWidth)
      minimapWindow:setHeight(panel:getHeight())
    else
      minimapWindow:setWidth(panelWidth)
    end

    panel:setPhantom(false)
  end)
end

-- Restore minimap position from saved settings
function restoreMinimapPosition()
  if not minimapWindow then
    return false
  end

  local char = g_game.getCharacterName()
  if not char or #char == 0 then
    -- No character name, ensure minimap is in a valid position
    ensureMinimapVisible()
    return false
  end

  local settings = g_settings.getNode('CharMiniWindows')
  if not settings or not settings[char] then
    -- No saved settings, ensure minimap is in a valid position
    ensureMinimapVisible()
    return false
  end

  local minimapSettings = settings[char]['minimapWindow']
  if not minimapSettings or not minimapSettings.parentId then
    -- No minimap settings saved, ensure minimap is in a valid position
    ensureMinimapVisible()
    return false
  end

  local targetPanel = rootWidget:recursiveGetChildById(minimapSettings.parentId)
  if not targetPanel then
    -- Panel not found, move to first available panel
    moveMinimapToFirstAvailablePanel()
    return false
  end

  local currentParent = minimapWindow:getParent()

  -- Skip if already in correct panel
  if currentParent == targetPanel then
    -- Just restore height if needed
    if minimapSettings.height and not string.find(targetPanel:getId(), "horizontal") then
      minimapWindow:setHeight(minimapSettings.height)
    end
    return true
  end

  -- Remove from current parent
  if currentParent then
    currentParent:removeChild(minimapWindow)
    if currentParent.fitAllChildren then
      currentParent:fitAllChildren()
    end
  end

  -- Handle horizontal panels specially
  local panelId = targetPanel:getId()
  if panelId == 'horizontalLeftPanel' or panelId == 'horizontalRightPanel' then
    if panelId == 'horizontalRightPanel' and modules.client_options and not modules.client_options.getOption('showHorizontalRightPanel') then
      moveMinimapToFirstAvailablePanel()
      return false
    end

    targetPanel:addChild(minimapWindow)
    targetPanel:setPhantom(false)

    if panelId == 'horizontalLeftPanel' then
      modules.game_interface.showLeftHorizontalPanel(true)
    else
      modules.game_interface.showRightHorizontalPanel(true)
    end

    expandMinimapForHorizontalPanel(targetPanel)
  else
    -- Normal panel - insert at saved index
    local index = minimapSettings.index or 1
    if index > targetPanel:getChildCount() + 1 then
      index = targetPanel:getChildCount() + 1
    end
    targetPanel:insertChild(index, minimapWindow)

    -- Restore height
    if minimapSettings.height then
      minimapWindow:setHeight(minimapSettings.height)
    end
  end

  -- Restore minimized state
  if minimapSettings.minimized then
    minimapWindow:minimize(true)
  end

  return true
end

-- Move minimap to first available panel (fallback when current panel is invalid/closed)
function moveMinimapToFirstAvailablePanel()
  if not minimapWindow then
    return false
  end

  -- Try default panel first (gameMainRightPanel)
  local mainRightPanel = modules.game_interface.getMainRightPanel()
  if mainRightPanel and mainRightPanel:isVisible() then
    local currentParent = minimapWindow:getParent()
    if currentParent and currentParent ~= mainRightPanel then
      local currentParentId = currentParent:getId()
      currentParent:removeChild(minimapWindow)

      if currentParentId == "horizontalLeftPanel" or currentParentId == "horizontalRightPanel" then
        updateHorizontalStripPhantomIfNowEmpty(currentParent)
      end

      -- Auto-fit old parent height
      if currentParent.fitAllChildren then
        currentParent:fitAllChildren()
      end
    end

    -- Restore default size
    minimapWindow:setWidth(minimapWindow.defaultWidth or 178)
    minimapWindow:setHeight(minimapWindow.defaultHeight or 178)

    -- Insert at beginning (only if not already this panel's child — avoids duplicate insertChild warning)
    if minimapWindow:getParent() ~= mainRightPanel then
      mainRightPanel:insertChild(1, minimapWindow)
    end
    minimapWindow:open()

    -- Auto-fit new parent height
    if mainRightPanel.fitAllChildren then
      mainRightPanel:fitAllChildren()
    end

    return true
  end

  -- Try other panels in order of preference
  local panelsToTry = {
    modules.game_interface.getRightPanel(),
    modules.game_interface.getLeftPanel(),
    modules.game_interface.getRightExtraPanel3 and modules.game_interface.getRightExtraPanel3(),
    modules.game_interface.getRightExtraPanel2 and modules.game_interface.getRightExtraPanel2(),
    modules.game_interface.getRightExtraPanel(),
    modules.game_interface.getLeftExtraPanel2 and modules.game_interface.getLeftExtraPanel2(),
    modules.game_interface.getLeftExtraPanel3 and modules.game_interface.getLeftExtraPanel3(),
    modules.game_interface.getLeftExtraPanel()
  }

  for _, panel in ipairs(panelsToTry) do
    if panel and panel:isVisible() and panel:isOn() then
      local currentParent = minimapWindow:getParent()
      if currentParent and currentParent ~= panel then
        local currentParentId = currentParent:getId()
        currentParent:removeChild(minimapWindow)

        if currentParentId == "horizontalLeftPanel" or currentParentId == "horizontalRightPanel" then
          updateHorizontalStripPhantomIfNowEmpty(currentParent)
        end

        -- Auto-fit old parent height
        if currentParent.fitAllChildren then
          currentParent:fitAllChildren()
        end
      end

      -- Restore default size
      minimapWindow:setWidth(minimapWindow.defaultWidth or 178)
      minimapWindow:setHeight(minimapWindow.defaultHeight or 178)

      -- Insert at beginning (only if not already this panel's child)
      if minimapWindow:getParent() ~= panel then
        panel:insertChild(1, minimapWindow)
      end
      minimapWindow:open()

      -- Auto-fit new parent height
      if panel.fitAllChildren then
        panel:fitAllChildren()
      end

      return true
    end
  end

  return false
end

-- Check if minimap is visible and in a valid position
function ensureMinimapVisible()
  if not minimapWindow then
    return
  end

  local parent = minimapWindow:getParent()

  -- Check if minimap has no parent or parent is invalid
  if not parent then
    moveMinimapToFirstAvailablePanel()
    return
  end

  local parentId = parent:getId()

  -- Check if minimap is in a horizontal panel that has 0 height (hidden)
  if parentId == "horizontalLeftPanel" or parentId == "horizontalRightPanel" then
    if parent:getHeight() == 0 or parent:getWidth() == 0 then
      moveMinimapToFirstAvailablePanel()
      return
    end
  end

  -- Check if minimap window itself is not visible
  if not minimapWindow:isVisible() then
    minimapWindow:open()
  end

  -- Check if parent is not visible
  if not parent:isVisible() then
    moveMinimapToFirstAvailablePanel()
    return
  end
end

-- Path tracking functions for huntfinder integration
local trackedPathWidgets = {}
local trackedRouteWidgets = {}

function setPath(coordinates)
  clearPath()
  if not minimapWidget or not coordinates then return end

  local function addPathPointsRecursive(tbl)
    for k, v in pairs(tbl) do
      if type(v) == 'table' then
        if v.x and v.y and v.z then
          local widget = g_ui.createWidget('UIWidget', minimapWidget)
          widget:setSize({width = 11, height = 11})
          widget:setIcon('/images/game/minimap/waypoint')
          widget.pos = v
          widget.type = "pathWaypoint"
          widget:setPhantom(true)
          minimapWidget:centerInPosition(widget, v)
          table.insert(trackedPathWidgets, widget)
        else
          addPathPointsRecursive(v)
        end
      end
    end
  end

  addPathPointsRecursive(coordinates)
end

function clearPath()
  for _, w in ipairs(trackedPathWidgets) do
    if w and w.destroy then w:destroy() end
  end
  trackedPathWidgets = {}
end

function setRoutePath(points)
  clearRoutePath()
  if not minimapWidget or not points then return end

  for _, pos in ipairs(points) do
    if pos.x and pos.y and pos.z then
      local widget = g_ui.createWidget('UIWidget', minimapWidget)
      widget:setSize({width = 3, height = 3})
      widget:setBackgroundColor("#FFFF00")
      widget.pos = pos
      widget.type = "routePoint"
      widget:setPhantom(true)
      minimapWidget:centerInPosition(widget, pos)
      table.insert(trackedRouteWidgets, widget)
    end
  end
end

function clearRoutePath()
  for _, w in ipairs(trackedRouteWidgets) do
    if w and w.destroy then w:destroy() end
  end
  trackedRouteWidgets = {}
end

function loadMarks()
  local file = '/mods/game_realminimap/markers.lua'
  if g_resources.fileExists(file) then
    local content = g_resources.readFileContents(file)
    local chunk = loadstring(content)
    if chunk then
      chunk()
      return markers
    end
  end
  return {}
end
