local inspectorButton = nil
local inspectorLabel = nil
local lastWidget = nil
local enabled = false
local mouseMoveConnected = false
local highlightedWidget = nil
local highlightedBorder = nil

local KEYBIND_GROUP = 'Debug'
local KEYBIND_NAME = 'Toggle UI Inspector'
local HIGHLIGHT_COLOR = '#ffd24dff'
local HIGHLIGHT_WIDTH = 1

local function captureBorder(widget)
    return {
        topWidth = widget:getBorderTopWidth(),
        rightWidth = widget:getBorderRightWidth(),
        bottomWidth = widget:getBorderBottomWidth(),
        leftWidth = widget:getBorderLeftWidth(),
        topColor = colortostring(widget:getBorderTopColor()),
        rightColor = colortostring(widget:getBorderRightColor()),
        bottomColor = colortostring(widget:getBorderBottomColor()),
        leftColor = colortostring(widget:getBorderLeftColor()),
    }
end

local function restoreBorder(widget, border)
    if not widget or not border or widget:isDestroyed() then
        return
    end

    widget:setBorderWidthTop(border.topWidth)
    widget:setBorderWidthRight(border.rightWidth)
    widget:setBorderWidthBottom(border.bottomWidth)
    widget:setBorderWidthLeft(border.leftWidth)

    widget:setBorderColorTop(tocolor(border.topColor))
    widget:setBorderColorRight(tocolor(border.rightColor))
    widget:setBorderColorBottom(tocolor(border.bottomColor))
    widget:setBorderColorLeft(tocolor(border.leftColor))
end

local function clearHighlight()
    restoreBorder(highlightedWidget, highlightedBorder)
    highlightedWidget = nil
    highlightedBorder = nil
end

local function applyHighlight(widget)
    if not widget then
        return
    end

    if widget == highlightedWidget then
        return
    end

    clearHighlight()
    highlightedWidget = widget
    highlightedBorder = captureBorder(widget)
    widget:setBorderWidth(HIGHLIGHT_WIDTH)
    widget:setBorderColor(HIGHLIGHT_COLOR)
end

local function getWidgetName(widget)
    if not widget then
        return ''
    end

    local name = widget:getStyleName()
    if not name or name == '' then
        if widget.getClassName then
            name = widget:getClassName()
        end
    end

    if not name or name == '' then
        name = 'UIWidget'
    end

    return name
end

local function buildWidgetPath(widget)
    local parts = {}
    local current = widget
    while current and current ~= rootWidget do
        local name = getWidgetName(current)
        if name ~= '' then
            table.insert(parts, 1, name)
        end
        current = current:getParent()
    end

    return table.concat(parts, ' > ')
end

local function buildInspectorText(widget)
    local path = buildWidgetPath(widget)
    local id = widget:getId()
    if not id or id == '' then
        id = '<none>'
    end
    return path .. '\n' .. 'id: ' .. id
end

local function moveTooltip(mousePos)
    if not inspectorLabel or not inspectorLabel:isVisible() then
        return
    end

    if not mousePos then
        mousePos = g_window.getMousePosition()
    end

    local pos = { x = mousePos.x + 1, y = mousePos.y + 1 }
    local windowSize = g_window.getSize()
    local labelSize = inspectorLabel:getSize()

    if windowSize.width - (pos.x + labelSize.width) < 10 then
        pos.x = pos.x - labelSize.width - 3
    else
        pos.x = pos.x + 10
    end

    if windowSize.height - (pos.y + labelSize.height) < 10 then
        pos.y = pos.y - labelSize.height - 3
    else
        pos.y = pos.y + 10
    end

    inspectorLabel:setPosition(pos)
end

local function hideTooltip()
    if inspectorLabel then
        inspectorLabel:hide()
    end
end

local function isIgnoredWidget(widget)
    if not widget then
        return true
    end
    if widget == inspectorLabel then
        return true
    end
    local id = widget:getId()
    if id == 'uiInspectorTooltip' or id == 'toolTip' or id == 'toolTipWidget' then
        return true
    end
    return false
end

local function showTooltip(widget, mousePos)
    local text = buildInspectorText(widget)
    inspectorLabel:setText(text)
    inspectorLabel:resizeToText()
    inspectorLabel:resize(inspectorLabel:getWidth() + 4, inspectorLabel:getHeight() + 4)
    inspectorLabel:show()
    inspectorLabel:raise()
    inspectorLabel:enable()
    moveTooltip(mousePos)
end

local function onMouseMove(widget, mousePos, mouseMoved)
    if not enabled then
        return
    end

    local widget = rootWidget:recursiveGetChildByPos(mousePos, false)
    if not widget or widget == rootWidget or isIgnoredWidget(widget) then
        lastWidget = nil
        clearHighlight()
        hideTooltip()
        return
    end

    if widget ~= lastWidget then
        lastWidget = widget
        applyHighlight(widget)
        showTooltip(widget, mousePos)
        return
    end

    moveTooltip(mousePos)
end

local function setEnabled(state)
    if enabled == state then
        return
    end

    enabled = state
    lastWidget = nil

    if inspectorButton then
        inspectorButton:setOn(enabled)
    end

    if enabled and not mouseMoveConnected then
        connect(rootWidget, {
            onMouseMove = onMouseMove
        })
        mouseMoveConnected = true
    elseif not enabled and mouseMoveConnected then
        disconnect(rootWidget, {
            onMouseMove = onMouseMove
        })
        mouseMoveConnected = false
        clearHighlight()
        hideTooltip()
    end
end

function toggle()
    setEnabled(not enabled)
end

function init()
    inspectorButton = modules.client_topmenu.addTopRightToggleButton(
        'uiInspectorButton',
        tr('UI Inspector'),
        '/images/topbuttons/debug',
        toggle
    )
    inspectorButton:setOn(false)

    inspectorLabel = g_ui.createWidget('UILabel', rootWidget)
    inspectorLabel:setId('uiInspectorTooltip')
    inspectorLabel:setBackgroundColor('#c0c0c0ff')
    inspectorLabel:setTextAlign(AlignLeft)
    inspectorLabel:setColor('#3f3f3fff')
    inspectorLabel:setBorderColor('#4c4c4cff')
    inspectorLabel:setBorderWidth(1)
    inspectorLabel:setTextOffset(topoint('5 3'))
    inspectorLabel:setPhantom(true)
    inspectorLabel:hide()

    Keybind.new(KEYBIND_GROUP, KEYBIND_NAME, 'Ctrl+Alt+I', '')
    Keybind.bind(KEYBIND_GROUP, KEYBIND_NAME, {
        {
            type = KEY_DOWN,
            callback = toggle,
        }
    })
end

function terminate()
    setEnabled(false)

    if inspectorLabel then
        inspectorLabel:destroy()
        inspectorLabel = nil
    end

    if inspectorButton then
        inspectorButton:destroy()
        inspectorButton = nil
    end

    Keybind.delete(KEYBIND_GROUP, KEYBIND_NAME)
end
