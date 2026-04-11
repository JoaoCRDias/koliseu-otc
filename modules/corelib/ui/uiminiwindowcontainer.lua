-- @docclass
UIMiniWindowContainer = extends(UIWidget, 'UIMiniWindowContainer')

function UIMiniWindowContainer.create()
    local container = UIMiniWindowContainer.internalCreate()
    container.scheduledWidgets = {}
    container:setFocusable(false)
    container:setPhantom(true)
    return container
end

-- Alinhado ao Balrog: resize síncrono, minimizar irmãos, realocar sem save, e não expulsar
-- widgets com save (ex.: containers) para dar lugar a janelas sem save.
function UIMiniWindowContainer:fitAll(noRemoveChild)
    if not self:isVisible() then
        return
    end

    if self.ignoreFillAll then
        return
    end

    -- Evita fitAll -> resize -> onHeightChange -> fitOnParent -> fitAll
    if self._fittingAll then
        return
    end
    self._fittingAll = true

    if not noRemoveChild then
        local children = self:getChildren()
        if #children > 0 then
            noRemoveChild = children[#children]
        else
            self._fittingAll = nil
            return
        end
    end

    local sumHeight = 0
    local children = self:getChildren()
    for i = 1, #children do
        if children[i]:isVisible() then
            sumHeight = sumHeight + children[i]:getHeight()
        end
    end

    local selfHeight = self:getHeight() - (self:getPaddingTop() + self:getPaddingBottom())
    if sumHeight <= selfHeight then
        self._fittingAll = nil
        return
    end

    local removeChildren = {}

    local maximumHeight = selfHeight - (sumHeight - noRemoveChild:getHeight())
    if noRemoveChild:isResizeable() and noRemoveChild:getMinimumHeight() <= maximumHeight then
        sumHeight = sumHeight - noRemoveChild:getHeight() + maximumHeight
        noRemoveChild.fitAllResize = true
        noRemoveChild:setHeight(maximumHeight)
        addEvent(function()
            noRemoveChild.fitAllResize = nil
        end)
    end

    if sumHeight <= selfHeight then
        self._fittingAll = nil
        return
    end

    if not noRemoveChild.save and modules.game_interface
        and modules.game_interface.findContentPanelAvailable then
        local betterPanel = modules.game_interface.findContentPanelAvailable(
            noRemoveChild, noRemoveChild:getMinimumHeight())
        if betterPanel and betterPanel ~= self and betterPanel:isVisible() then
            local fitsResult = betterPanel:fits(noRemoveChild, noRemoveChild:getMinimumHeight(), 0)
            if fitsResult >= 0 then
                sumHeight = sumHeight - noRemoveChild:getHeight()
                self:removeChild(noRemoveChild)
                betterPanel:addChild(noRemoveChild)
                self._fittingAll = nil
                return
            end
        end
    end

    for i = #children, 1, -1 do
        if sumHeight <= selfHeight then
            break
        end
        local child = children[i]
        if child ~= noRemoveChild and child:isVisible() and not child.minimized
            and child.minimize and child.minimizedHeight then
            local gained = child:getHeight() - child.minimizedHeight
            if gained > 0 then
                sumHeight = sumHeight - gained
                child:minimize(true)
            end
        end
    end

    if sumHeight <= selfHeight then
        self._fittingAll = nil
        return
    end

    for i = #children, 1, -1 do
        if sumHeight <= selfHeight then
            break
        end

        local child = children[i]
        if child ~= noRemoveChild and not child.save and not child.isOpen then
            local childHeight = child:getHeight()
            sumHeight = sumHeight - childHeight
            table.insert(removeChildren, child)
        end
    end

    if noRemoveChild.save then
        for i = #children, 1, -1 do
            if sumHeight <= selfHeight then
                break
            end

            local child = children[i]
            if child ~= noRemoveChild and child:isVisible() and child.type ~= 'container' then
                local childHeight = child:getHeight()
                sumHeight = sumHeight - childHeight
                table.insert(removeChildren, child)
            end
        end
    end

    for i = 1, #removeChildren do
        local child = removeChildren[i]
        if child.close then
            child:close()
        else
            child:hide()
        end
    end

    self._fittingAll = nil
end

function UIMiniWindowContainer:fits(child, minContentHeight, maxContentHeight)
    if self.ignoreFillAll then
        return 0
    end

    local containerPanel = child:getChildById('contentsPanel')
    local indispensableHeight = 0
    if containerPanel then
        indispensableHeight = containerPanel:getMarginTop() + containerPanel:getMarginBottom() +
            containerPanel:getPaddingTop() + containerPanel:getPaddingBottom()
    end

    local totalHeight = 0
    local children = self:getChildren()
    for i = 1, #children do
        if children[i]:isVisible() then
            totalHeight = totalHeight + children[i]:getHeight()
        end
    end

    local available = self:getHeight() - (self:getPaddingTop() + self:getPaddingBottom()) - totalHeight

    if maxContentHeight > 0 and available >= (maxContentHeight + indispensableHeight) then
        return maxContentHeight + indispensableHeight
    elseif available >= (minContentHeight + indispensableHeight) then
        return available
    else
        return -1
    end
end

function UIMiniWindowContainer:onDrop(widget, mousePos)
    if widget.UIMiniWindowContainer then
        local widgetId = widget:getId()
        local targetPanelId = self:getId()

        -- Block widgets that are not allowed in gameMainRightPanel
        -- Only widgets with moveOnlyToMain or allowInMainRightPanel can be placed there
        if targetPanelId == "gameMainRightPanel" and not widget.moveOnlyToMain and not widget.allowInMainRightPanel then
            local alternativePanel = modules.game_interface.findContentPanelAvailable(widget, widget:getMinimumHeight())
            if alternativePanel and alternativePanel ~= self then
                alternativePanel:onDrop(widget, mousePos)
                return true
            else
                return false
            end
        end

        -- Faixa esquerda (Balrog v3): um único filho; faixa direita: minimapa não conta para o “slot” extra.
        if targetPanelId == "horizontalLeftPanel" or targetPanelId == "horizontalRightPanel" then
            local existingChildren = self:getChildren()
            local hasOtherWidget = false
            if targetPanelId == "horizontalLeftPanel" then
                for i = 1, #existingChildren do
                    if existingChildren[i] ~= widget then
                        hasOtherWidget = true
                        break
                    end
                end
            else
                for i = 1, #existingChildren do
                    local c = existingChildren[i]
                    if c ~= widget and c:isExplicitlyVisible() and c:getId() ~= 'minimapWindow' then
                        hasOtherWidget = true
                        break
                    end
                end
            end

            if hasOtherWidget then
                if widget.oldParentDrag then
                    if widget.movedWidget then
                        if widget.setMovedChildMargin then
                            widget.setMovedChildMargin(widget.movedOldMargin or 0)
                        end
                        widget.movedWidget = nil
                        widget.setMovedChildMargin = nil
                        widget.movedOldMargin = nil
                        widget.movedIndex = nil
                    end

                    widget.oldParentDrag:insertChild(widget.oldParentDragIndex or 1, widget)
                    widget.oldParentDrag:saveChildren()
                    self:saveChildren()

                    widget.oldParentDrag = nil
                    widget.oldParentDragIndex = nil
                    return true
                end
                return false
            end
        end

        local oldParent = widget:getParent()
        if oldParent == self then
            return true
        end

        -- Restore minimap size and layout when leaving horizontal panel
        if widgetId == "minimapWindow" and oldParent and (oldParent:getId() == "horizontalLeftPanel" or oldParent:getId() == "horizontalRightPanel") then
            widget:setWidth(widget.defaultWidth or 178)
            widget:setHeight(widget.defaultHeight or 178)
        end

        if oldParent then
            local oldParentId = oldParent:getId()

            oldParent:removeChild(widget)

            if oldParentId == "horizontalLeftPanel" then
                if oldParent:getChildCount() == 0 then
                    oldParent:setPhantom(true)
                end
            elseif oldParentId == "horizontalRightPanel" then
                if oldParent:getChildCount() == 0 then
                    local stripShown = oldParent:getHeight() > 0
                    if modules.client_options then
                        stripShown = stripShown and modules.client_options.getOption('showHorizontalRightPanel')
                    end
                    if not stripShown then
                        oldParent:setPhantom(true)
                    else
                        oldParent:setPhantom(false)
                    end
                end
            end

            -- Update layout of old parent panel to remove empty space
            if oldParent.updateLayout then
                oldParent:updateLayout()
            end

            -- Auto-fit old parent height
            if oldParent.fitAllChildren then
                oldParent:fitAllChildren()
            end
        end

        -- Clean up any temporary margins applied during drag
        if widget.movedWidget then
            if widget.setMovedChildMargin then
                widget.setMovedChildMargin(widget.movedOldMargin or 0)
            end
            local index = self:getChildIndex(widget.movedWidget)
            self:insertChild(index + widget.movedIndex, widget)
            widget.movedWidget = nil
            widget.setMovedChildMargin = nil
            widget.movedOldMargin = nil
            widget.movedIndex = nil
        else
            self:addChild(widget)
        end

        if widget:getId() == "botWindow" and
            (widget:getParent():getId() == "gameLeftPanel" or widget:getParent():getId() == "gameLeftExtraPanel" or
                widget:getParent():getId() == "gameLeftExtraPanel2" or widget:getParent():getId() == "gameLeftExtraPanel3" or
                widget:getParent():getId() == "gameRightExtraPanel" or widget:getParent():getId() == "gameRightExtraPanel2" or
                widget:getParent():getId() == "gameRightExtraPanel3") then
            widget:getParent():setWidth(190)
        end

        if targetPanelId == "horizontalLeftPanel" or targetPanelId == "horizontalRightPanel" then
            self:setPhantom(false)
            if widgetId == "minimapWindow" and modules.game_minimap and modules.game_minimap.expandMinimapForHorizontalPanel then
                modules.game_minimap.expandMinimapForHorizontalPanel(self)
            elseif targetPanelId == "horizontalLeftPanel" then
                local panel = self
                addEvent(function()
                    if not widget or widget:isDestroyed() or not panel or panel:isDestroyed() then
                        return
                    end
                    local panelWidth = panel:getWidth()
                    local panelHeight = panel:getHeight()
                    if panelWidth > 0 and panelHeight > 0 then
                        widget:setWidth(panelWidth)
                        widget:setHeight(panelHeight)
                    end
                end)
            else
                local panel = self
                addEvent(function()
                    if not widget or widget:isDestroyed() or not panel or panel:isDestroyed() then
                        return
                    end
                    local panelWidth = panel:getWidth()
                    local panelHeight = panel:getHeight()
                    if panelWidth > 0 and panelHeight > 0 then
                        widget:setWidth(panelWidth)
                        widget:setHeight(math.max(1, panelHeight - 5))
                    end
                end)
            end
        end

        self:fitAll(widget)

        -- Auto-fit altura da coluna principal (espelho esquerda/direita)
        if self.fitAllChildren then
            local sid = self:getId()
            if sid == "gameMainRightPanel" or sid == "gameLeftPanel" then
                self:fitAllChildren()
            end
        end

        -- Save children positions (including horizontal panels)
        self:saveChildren()

        return true
    end
end

function UIMiniWindowContainer:swapInsert(widget, index)
    local oldParent = widget:getParent()
    local oldIndex = self:getChildIndex(widget)

    if oldParent == self and oldIndex ~= index then
        local oldWidget = self:getChildByIndex(index)
        if oldWidget then
            self:removeChild(oldWidget)
            self:insertChild(oldIndex, oldWidget)
        end
        self:removeChild(widget)
        self:insertChild(index, widget)
    end
end

function UIMiniWindowContainer:scheduleInsert(widget, index)
    if index - 1 > self:getChildCount() then
        if self.scheduledWidgets[index] then
            pdebug('replacing scheduled widget id ' .. widget:getId())
        end
        self.scheduledWidgets[index] = widget
    else
        local oldParent = widget:getParent()
        if oldParent ~= self then
            if oldParent then
                oldParent:removeChild(widget)
            end
            self:insertChild(index, widget)

            while true do
                local placed = false
                for nIndex, nWidget in pairs(self.scheduledWidgets) do
                    if nIndex - 1 <= self:getChildCount() then
                        -- Check if widget is already a child before inserting
                        local nWidgetParent = nWidget:getParent()
                        if nWidgetParent ~= self then
                            if nWidgetParent then
                                nWidgetParent:removeChild(nWidget)
                            end
                            self:insertChild(nIndex, nWidget)
                        end
                        self.scheduledWidgets[nIndex] = nil
                        placed = true
                        break
                    end
                end
                if not placed then
                    break
                end
            end
        end
    end
end

function UIMiniWindowContainer:order()
    local children = self:getChildren()
    for i = 1, #children do
        if not children[i].miniLoaded then
            return
        end
    end

    for i = 1, #children do
        if children[i].miniIndex then
            self:swapInsert(children[i], children[i].miniIndex)
        end
    end
end

function UIMiniWindowContainer:saveChildren()
    local children = self:getChildren()
    local ignoreIndex = 0
    for i = 1, #children do
        if children[i].save then
            children[i]:saveParentIndex(self:getId(), i - ignoreIndex)
        else
            ignoreIndex = ignoreIndex + 1
        end
    end

    -- Note: JSON configuration is saved only on logout (onGameEnd)
end

function UIMiniWindowContainer:fitAllChildren()
    local panelId = self:getId()

    -- Skip horizontal panels - they have fixed height
    if panelId == "horizontalLeftPanel" or panelId == "horizontalRightPanel" then
        return
    end

    local children = self:getChildren()
    local totalHeight = 0
    local layout = self:getLayout()
    local spacing = 0

    if layout and layout.getSpacing then
        spacing = layout:getSpacing()
    end

    local visibleCount = 0
    for i = 1, #children do
        local child = children[i]
        if child:isVisible() and child:getHeight() > 0 then
            totalHeight = totalHeight + child:getHeight() + child:getMarginTop() + child:getMarginBottom()
            visibleCount = visibleCount + 1
        end
    end

    if visibleCount > 1 then
        totalHeight = totalHeight + (spacing * (visibleCount - 1))
    end

    totalHeight = totalHeight + self:getPaddingTop() + self:getPaddingBottom()

    self:setHeight(math.max(0, totalHeight))
end
