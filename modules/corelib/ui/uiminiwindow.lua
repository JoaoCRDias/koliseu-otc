-- @docclass
UIMiniWindow = extends(UIWindow, 'UIMiniWindow')

function UIMiniWindow.create()
    local miniwindow = UIMiniWindow.internalCreate()
    miniwindow.UIMiniWindowContainer = true
    return miniwindow
end

function UIMiniWindow:open(dontSave)
    self:setVisible(true)
    if not dontSave then
        self:setSettings({
            closed = false
        })
    end
    signalcall(self.onOpen, self)
end

function UIMiniWindow:close(dontSave)
    if not self:isExplicitlyVisible() then
        return
    end
    self:setVisible(false)

    if not dontSave then
        self:setSettings({
            closed = true
        })
    end

    signalcall(self.onClose, self)
end

function UIMiniWindow:minimize(dontSave)
    self:setOn(true)
    self:getChildById('contentsPanel'):hide()
    self:getChildById('miniwindowScrollBar'):hide()
    self:getChildById('bottomResizeBorder'):hide()
    self:getChildById('minimizeButton'):setOn(true)
    self.maximizedHeight = self:getHeight()
    self:setHeight(self.minimizedHeight)

    -- Hide miniborder when minimizing
    local miniborder = self:recursiveGetChildById('miniborder')
    if miniborder then
        miniborder:setVisible(false)
    end

    if not dontSave then
        self:setSettings({
            minimized = true
        })
    end

    signalcall(self.onMinimize, self)
end

function UIMiniWindow:maximize(dontSave)
    self:setOn(false)
    self:getChildById('contentsPanel'):show()
    self:getChildById('miniwindowScrollBar'):show()
    self:getChildById('bottomResizeBorder'):show()
    self:getChildById('minimizeButton'):setOn(false)
    self:setHeight(self:getSettings('height') or self.maximizedHeight)

    -- Show miniborder when maximizing
    local miniborder = self:recursiveGetChildById('miniborder')
    if miniborder then
        miniborder:setVisible(true)
    end

    if not dontSave then
        self:setSettings({
            minimized = false
        })
    end

    local parent = self:getParent()
    if parent and parent:getClassName() == 'UIMiniWindowContainer' then
        parent:fitAll(self)
    end

    signalcall(self.onMaximize, self)
end

function UIMiniWindow:setup()
    self:getChildById('closeButton').onClick = function()
        self:close()
    end

    self:getChildById('minimizeButton').onClick = function()
        if self:isOn() then
            self:maximize()
        else
            self:minimize()
        end
    end

    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton.onClick = function()
            if self:isDraggable() then
                self:lock()
            else
                self:unlock()
            end
        end
    end

    self:getChildById('miniwindowTopBar').onDoubleClick = function()
        if self:isOn() then
            self:maximize()
        else
            self:minimize()
        end
    end
end

function UIMiniWindow:setupOnStart()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local oldParent = self:getParent()
    local newParentSet = false
    local settings = g_settings.getNode('CharMiniWindows')

    if not settings then
        settings = {
            [char] = {}
        }
    elseif not settings[char] then
        -- if there are no settings for this character, we'll copy the settings from
        -- another one, so we'll have something better than all the windows randomly positioned
        for k, v in pairs(settings) do
            settings[char] = v
            g_settings.setNode('CharMiniWindows', settings)
            break
        end
    end

    local selfSettings = settings[char][self:getId()]
    if selfSettings then
        if selfSettings.parentId then
            local parent = rootWidget:recursiveGetChildById(selfSettings.parentId)
            if parent then
                local isVisible = parent:isVisible()
                local isOn = parent.isOn and parent:isOn() or true  -- Default to true if isOn doesn't exist

                if parent:getClassName() == 'UIMiniWindowContainer' and selfSettings.index then
                    -- For docked widgets in UIMiniWindowContainer
                    if isVisible and isOn then
                        self.miniIndex = selfSettings.index
                        parent:scheduleInsert(self, selfSettings.index)
                        newParentSet = true
                    elseif isVisible or isOn then
                        -- Try to insert even if not fully visible/on (panel might become visible later)
                        self.miniIndex = selfSettings.index
                        local currentParent = self:getParent()
                        if currentParent and currentParent ~= parent then
                            currentParent:removeChild(self)
                        end
                        parent:insertChild(selfSettings.index, self)
                        newParentSet = true
                    end
                elseif selfSettings.position then
                    self:setParent(parent, true)
                    self:setPosition(topoint(selfSettings.position))
                    newParentSet = true
                end
            end
        end

        if selfSettings.minimized then
            self:minimize(true)
        elseif selfSettings.height then
            if self:isResizeable() then
                self:setHeight(selfSettings.height)
            else
                self:eraseSettings({
                    height = true
                })
            end
        end

        if selfSettings.closed then
            self:close(true)
        else
            self:open(true)
        end

        if selfSettings.locked then
            self:lock(true)
        end
    else
        if self:getId() == "battleWindow" then
            self:open(true)
        end
    end

    local newParent = self:getParent()

    if not oldParent and not newParentSet then
        oldParent = modules.game_interface.getRightPanel()
        self:setParent(oldParent)
    end

    self.miniLoaded = true

    if self.save then
        if oldParent and oldParent:getClassName() == 'UIMiniWindowContainer' then
            addEvent(function()
                oldParent:order()
            end)
        end
        if newParent and newParent:getClassName() == 'UIMiniWindowContainer' and newParent ~= oldParent then
            addEvent(function()
                newParent:order()
            end)
        end
    end

    self:fitOnParent()
    if self:getId() == "botWindow" then
        local parent = self:getParent()
        local parentId = parent:getId()

        if parentId == "gameLeftPanel" or parentId == "gameLeftExtraPanel" or
            parentId == "gameLeftExtraPanel2" or parentId == "gameLeftExtraPanel3" or
            parentId == "gameRightExtraPanel" or parentId == "gameRightExtraPanel2" or
            parentId == "gameRightExtraPanel3" then
            if parent:isVisible() then
                parent:setWidth(190)
            end
        end
    end
end

function UIMiniWindow:onVisibilityChange(visible)
    self:fitOnParent()
end

function UIMiniWindow:onDragEnter(mousePos)
    local parent = self:getParent()
    if not parent then
        return false
    end

    if parent:getClassName() == 'UIMiniWindowContainer' then
        self.oldParentDrag = parent
        self.oldParentDragIndex = parent:getChildIndex(self)
        local containerParent = parent:getParent()
        parent:removeChild(self)
        containerParent:addChild(self)
        parent:saveChildren()
    end

    local oldPos = self:getPosition()
    self.movingReference = {
        x = mousePos.x - oldPos.x,
        y = mousePos.y - oldPos.y
    }
    self:setPosition(oldPos)
    self.free = true

    self.dragStarted = true
    self.highlightedPanel = nil -- Track which panel is currently highlighted
    return true
end

local function isInArray(table, value)
    for v = 1, #table do
        if table[v] == value then
            return true
        end
    end
    return false
end

function UIMiniWindow:onDragLeave(droppedWidget, mousePos)
    -- Clear any highlighted panel border
    if self.highlightedPanel then
        self.highlightedPanel:setBorderWidth(0)
        self.highlightedPanel = nil
    end

    local lockButton = self:getChildById('lockButton')
    if lockButton and lockButton:isOn() then
        return false
    end

    if not self.dragStarted then
        return false
    end

    self.dragStarted = false

    -- Normal drag & drop flow - clean up moved widget state
    if self.movedWidget then
        self.setMovedChildMargin(self.movedOldMargin or 0)
        self.movedWidget = nil
        self.setMovedChildMargin = nil
        self.movedOldMargin = nil
        self.movedIndex = nil
    end

    -- Handle height adjustment for horizontal panels
    local currentParent = self:getParent()
    if currentParent and isInArray({ "horizontalLeftPanel", "horizontalRightPanel" }, currentParent:getId()) then
        currentParent:setHeight(currentParent:getHeight() - 5)
    end

    UIWindow:onDragLeave(self, droppedWidget, mousePos)

    local finalParent = self:getParent()
    local finalParentId = finalParent and finalParent:getId() or "nil"
    local finalParentClass = finalParent and finalParent:getClassName() or "nil"

    -- Check if widget should return to original parent:
    -- 1. If it ended up outside a valid MiniWindowContainer
    -- 2. If it has moveOnlyToMain and ended up outside gameMainRightPanel
    local shouldReturn = false
    if finalParentClass ~= "UIMiniWindowContainer" then
        shouldReturn = true
    elseif self.moveOnlyToMain and finalParentId ~= "gameMainRightPanel"
        and finalParentId ~= "horizontalLeftPanel" and finalParentId ~= "horizontalRightPanel" then
        shouldReturn = true
    end

    if shouldReturn and self.oldParentDrag then
        self.oldParentDrag:insertChild(self.oldParentDragIndex or 1, self)
        finalParent = self.oldParentDrag
        finalParentId = finalParent:getId()
    end

    if finalParent and isInArray({ "horizontalLeftPanel", "horizontalRightPanel" }, finalParentId) then
        finalParent:setHeight(finalParent:getHeight() + 5)
    end

    if finalParent and self:getHeight() > finalParent:getHeight() then
        self:setHeight(finalParent:getHeight() - 5)
    end

    -- Auto-fit old parent height if widget moved to a different panel
    local oldParentDrag = self.oldParentDrag
    if oldParentDrag and oldParentDrag ~= finalParent then
        scheduleEvent(function()
            if oldParentDrag and oldParentDrag.fitAllChildren then
                oldParentDrag:fitAllChildren()
            end
        end, 50)
    end

    -- Auto-fit new parent height
    if finalParent and finalParent.fitAllChildren and finalParent:getId() == "gameMainRightPanel" then
        scheduleEvent(function()
            if finalParent and finalParent.fitAllChildren then
                finalParent:fitAllChildren()
            end
        end, 50)
    end

    self.oldParentDrag = nil
    self.oldParentDragIndex = nil
end

function UIMiniWindow:onDragMove(mousePos, mouseMoved)
    local oldMousePosY = mousePos.y - mouseMoved.y
    -- Mesmo critério que UIManager::updateDraggingWidget (onDrop): evita borda branca num painel e soltar outro
    local children = rootWidget:recursiveGetChildrenByPos(mousePos)
    local overAnyWidget = false
    local widgetId = self:getId()

    -- Define valid drop target panels
    local availablePanels = { "gameLeftPanel", "gameRightPanel", "gameLeftExtraPanel", "gameLeftExtraPanel2",
        "gameLeftExtraPanel3", "gameRightExtraPanel", "gameRightExtraPanel2", "gameRightExtraPanel3", "rightPanel2",
        "rightPanel3", "rightPanel4", "leftPanel1",
        "leftPanel2", "leftPanel3", "leftPanel4", "horizontalLeftPanel", "horizontalRightPanel" }

    -- Faixas horizontais: escolher pela posição do rato (evita destacar/soltar na faixa errada).
    local hl, hr = nil, nil
    for i = 1, #children do
        local child = children[i]
        local childId = child:getId()
        if childId == "horizontalLeftPanel" then
            hl = child
        elseif childId == "horizontalRightPanel" then
            hr = child
        end
    end
    local targetPanel = nil
    if hl and hr then
        if hl:containsPoint(mousePos) then
            targetPanel = hl
        elseif hr:containsPoint(mousePos) then
            targetPanel = hr
        else
            local mid = mousePos.x
            if rootWidget then
                mid = rootWidget:getX() + rootWidget:getWidth() / 2
            end
            targetPanel = mousePos.x < mid and hl or hr
        end
    elseif hl then
        targetPanel = hl
    elseif hr then
        targetPanel = hr
    end
    if not targetPanel then
        for i = 1, #children do
            local child = children[i]
            local childId = child:getId()
            if isInArray(availablePanels, childId) then
                targetPanel = child
                break
            end
        end
    end

    -- Update visual border feedback
    if targetPanel ~= self.highlightedPanel then
        -- Remove border from previous panel
        if self.highlightedPanel then
            self.highlightedPanel:setBorderWidth(0)
        end
        -- Add border to new panel
        if targetPanel then
            targetPanel:setBorderColor('#ffffff')
            targetPanel:setBorderWidth(2)
        end
        self.highlightedPanel = targetPanel
    end

    -- Handle widget margin adjustments for insertion preview
    for i = 1, #children do
        local child = children[i]
        if child:getParent():getClassName() == 'UIMiniWindowContainer' then
            overAnyWidget = true

            local childCenterY = child:getY() + child:getHeight() / 2
            if child == self.movedWidget and mousePos.y < childCenterY and oldMousePosY < childCenterY then
                break
            end

            if self.movedWidget then
                self.setMovedChildMargin(self.movedOldMargin or 0)
                self.setMovedChildMargin = nil
            end

            if mousePos.y < childCenterY then
                self.movedOldMargin = child:getMarginTop()
                self.setMovedChildMargin = function(v)
                    child:setMarginTop(v)
                end
                self.movedIndex = 0
            else
                self.movedOldMargin = child:getMarginBottom()
                self.setMovedChildMargin = function(v)
                    child:setMarginBottom(v)
                end
                self.movedIndex = 1
            end

            self.movedWidget = child
            self.setMovedChildMargin(self:getHeight())
            break
        end
    end

    if not overAnyWidget and self.movedWidget then
        self.setMovedChildMargin(self.movedOldMargin or 0)
        self.movedWidget = nil
        self.setMovedChildMargin = nil
        self.movedOldMargin = nil
        self.movedIndex = nil
    end

    return UIWindow.onDragMove(self, mousePos, mouseMoved)
end

function UIMiniWindow:onMousePress()
    local parent = self:getParent()
    if not parent then
        return false
    end
    if parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:raise()
        return true
    end
end

function UIMiniWindow:onFocusChange(focused)
    if not focused then
        return
    end
    local parent = self:getParent()
    if parent and parent:getClassName() ~= 'UIMiniWindowContainer' then
        self:raise()
    end
end

function UIMiniWindow:onHeightChange(height)
    if not self:isOn() then
        self:setSettings({
            height = height
        })
    end
    self:fitOnParent()
end

function UIMiniWindow:getSettings(name)
    if not self.save then
        return nil
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return nil
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if settings then
        if settings[char] then
            local selfSettings = settings[char][self:getId()]
            if selfSettings then
                return selfSettings[name]
            end
        end
    end

    return nil
end

function UIMiniWindow:setSettings(data)
    if not self.save then
        return
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings then
        settings = {}
    end
    if not settings[char] then
        settings[char] = {}
    end

    local id = self:getId()
    if not settings[char][id] then
        settings[char][id] = {}
    end

    for key, value in pairs(data) do
        settings[char][id][key] = value
    end

    g_settings.setNode('CharMiniWindows', settings)
end

function UIMiniWindow:eraseSettings(data)
    if not self.save then
        return
    end
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings then
        settings = {}
    end
    if not settings[char] then
        settings[char] = {}
    end

    local id = self:getId()
    if not settings[char][id] then
        settings[char][id] = {}
    end

    for key, value in pairs(data) do
        settings[char][id][key] = nil
    end

    g_settings.setNode('CharMiniWindows', settings)
end

function UIMiniWindow:saveParent(parent)
    local parent = self:getParent()
    if parent then
        if parent:getClassName() == 'UIMiniWindowContainer' then
            parent:saveChildren()
        else
            self:saveParentPosition(parent:getId(), self:getPosition())
        end
    end
end

function UIMiniWindow:saveParentPosition(parentId, position)
    local selfSettings = {}
    selfSettings.parentId = parentId
    selfSettings.position = pointtostring(position)
    self:setSettings(selfSettings)
end

function UIMiniWindow:saveParentIndex(parentId, index)
    local selfSettings = {}
    selfSettings.parentId = parentId
    selfSettings.index = index
    selfSettings.height = self:getHeight()
    selfSettings.minimized = self.minimized or false
    selfSettings.locked = self.isLocked and self:isLocked() or false
    selfSettings.closed = not self:isVisible()
    self:setSettings(selfSettings)
    self.miniIndex = index
end

function UIMiniWindow:disableResize()
    self:getChildById('bottomResizeBorder'):disable()
end

function UIMiniWindow:enableResize()
    self:getChildById('bottomResizeBorder'):enable()
end

function UIMiniWindow:fitOnParent()
    local parent = self:getParent()
    if self:isVisible() and parent and parent:getClassName() == 'UIMiniWindowContainer' then
        parent:fitAll(self)
    end
end

function UIMiniWindow:setParent(parent, dontsave)
    UIWidget.setParent(self, parent)
    if not dontsave then
        self:saveParent(parent)
    end
    self:fitOnParent()
end

function UIMiniWindow:setHeight(height)
    UIWidget.setHeight(self, height)
    signalcall(self.onHeightChange, self, height)
end

function UIMiniWindow:setContentHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setParentSize(minHeight + height)
end

function UIMiniWindow:setContentMinimumHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setMinimum(minHeight + height)
end

function UIMiniWindow:setContentMaximumHeight(height)
    local contentsPanel = self:getChildById('contentsPanel')
    local minHeight = contentsPanel:getMarginTop() + contentsPanel:getMarginBottom() + contentsPanel:getPaddingTop() +
        contentsPanel:getPaddingBottom()

    local resizeBorder = self:getChildById('bottomResizeBorder')
    resizeBorder:setMaximum(minHeight + height)
end

function UIMiniWindow:getMinimumHeight()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    if not resizeBorder then
        -- Fallback for widgets without resize border (like minimap)
        return 100
    end
    return resizeBorder:getMinimum()
end

function UIMiniWindow:getMaximumHeight()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    if not resizeBorder then
        -- Fallback for widgets without resize border (like minimap)
        return 9999
    end
    return resizeBorder:getMaximum()
end

function UIMiniWindow:modifyMaximumHeight(height)
    local resizeBorder = self:getChildById('bottomResizeBorder')
    if not resizeBorder then
        -- Widgets without resize border cannot have maximum height modified
        return
    end
    local newHeight = resizeBorder:getMaximum() + height
    local curHeight = self:getHeight()
    resizeBorder:setMaximum(newHeight)
    if newHeight < curHeight or newHeight - height == curHeight then
        self:setHeight(newHeight)
    end
end

function UIMiniWindow:isResizeable()
    local resizeBorder = self:getChildById('bottomResizeBorder')
    if not resizeBorder then
        return false
    end
    return resizeBorder:isExplicitlyVisible() and resizeBorder:isEnabled()
end

function UIMiniWindow:lock(dontSave)
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton:setOn(true)
    end
    self:setDraggable(false)
    self:setBorderWidth(1)
    self:setBorderColor('#ff0000')
    local header = self:getChildById('miniwindowHeader')
    if header then
        header:setBorderWidthTop(1)
        header:setBorderWidthLeft(1)
        header:setBorderWidthRight(1)
        header:setBorderColor('#ff0000')
    end
    if not dontSave then
        self:setSettings({
            locked = true
        })
    end

    signalcall(self.onLockChange, self)
end

function UIMiniWindow:unlock(dontSave)
    local lockButton = self:getChildById('lockButton')
    if lockButton then
        lockButton:setOn(false)
    end
    self:setDraggable(true)
    self:setBorderWidth(0)
    local header = self:getChildById('miniwindowHeader')
    if header then
        header:setBorderWidthTop(0)
        header:setBorderWidthLeft(0)
        header:setBorderWidthRight(0)
    end
    if not dontSave then
        self:setSettings({
            locked = false
        })
    end
    signalcall(self.onLockChange, self)
end

-- Restore widget position from saved settings (more robust than setupOnStart)
function UIMiniWindow:restorePosition()
    if not self.save then
        return false
    end

    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return false
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings or not settings[char] then
        return false
    end

    local selfSettings = settings[char][self:getId()]
    if not selfSettings or not selfSettings.parentId then
        return false
    end

    local targetPanel = rootWidget:recursiveGetChildById(selfSettings.parentId)
    if not targetPanel then
        return false
    end

    if targetPanel:getId() == 'horizontalRightPanel' and modules.client_options and not modules.client_options.getOption('showHorizontalRightPanel') then
        return false
    end

    local currentParent = self:getParent()

    -- Skip if already in correct panel
    if currentParent == targetPanel then
        -- Just restore height and state
        if selfSettings.height and self:isResizeable() then
            self:setHeight(selfSettings.height)
        end
        if selfSettings.minimized then
            self:minimize(true)
        end
        return true
    end

    -- Remove from current parent
    if currentParent then
        currentParent:removeChild(self)
        if currentParent.fitAllChildren then
            currentParent:fitAllChildren()
        end
    end

    -- Handle horizontal panels specially
    local panelId = targetPanel:getId()
    if panelId == 'horizontalLeftPanel' or panelId == 'horizontalRightPanel' then
        targetPanel:addChild(self)
        targetPanel:setPhantom(false)

        if panelId == 'horizontalLeftPanel' then
            if modules.game_interface and modules.game_interface.showLeftHorizontalPanel then
                modules.game_interface.showLeftHorizontalPanel(true)
            end
        else
            if modules.game_interface and modules.game_interface.showRightHorizontalPanel then
                modules.game_interface.showRightHorizontalPanel(true)
            end
        end

        -- Resize for horizontal panel
        addEvent(function()
            if self and targetPanel then
                self:setWidth(targetPanel:getWidth())
                self:setHeight(targetPanel:getHeight())
            end
        end)
    else
        -- Normal panel - insert at saved index
        local index = selfSettings.index or 1
        if index > targetPanel:getChildCount() + 1 then
            index = targetPanel:getChildCount() + 1
        end
        targetPanel:insertChild(index, self)

        -- Restore height
        if selfSettings.height and self:isResizeable() then
            self:setHeight(selfSettings.height)
        end
    end

    -- Restore minimized state
    if selfSettings.minimized then
        self:minimize(true)
    end

    -- Restore locked state
    if selfSettings.locked then
        self:lock(true)
    end

    -- Restore open/closed state
    if selfSettings.closed then
        self:close(true)
    else
        self:open(true)
    end

    return true
end
