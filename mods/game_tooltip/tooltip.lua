local tooltipRoot = nil  
local tooltipName = nil  
local tooltipText = nil  
local tooltipVocation = nil  
local tooltipLevel = nil  
local tooltipIcon = nil  
local SendItemOpcode = 251  
local currentHoveredItem = nil  
local tooltipDelayEvent = nil  
  
local function updateTooltipText(data)  
  local lines = {}  
  
  local function addLine(label, value, suffix)  
    if value ~= nil then  
      if type(value) == "number" then  
        if value > 0.1 then  
          if math.floor(value) == value then  
            table.insert(lines, string.format("%s: %d%s", label, value, suffix or ""))  
          else  
            table.insert(lines, string.format("%s: %.1f%s", label, value, suffix or ""))  
          end  
        end  
      elseif type(value) == "string" and value ~= "" then  
        table.insert(lines, string.format("%s: %s%s", label, value, suffix or ""))  
      end  
    end  
  end  
  
  addLine("Atk", data.attack)  
  addLine("Def", data.defense)  
  addLine("Chance", data.hitchance, "%")  
  addLine("Range", data.range)  
  addLine("Speed", data.speed)  
  addLine("SpeedAttack", data.speedAttack)  
  addLine("Arm", data.armor)  
  addLine("Vol.", data.containerSize)  
  addLine("Weight", data.weight, " oz")  
  
  if #lines > 0 then  
    tooltipText:setText(table.concat(lines, "\n"))  
    tooltipText:setVisible(true)  
    return true  
  else  
    tooltipText:setVisible(false)  
    return false  
  end  
end  
  
function onExtendedOpcode(protocol, opcode, buffer)  
  if opcode ~= SendItemOpcode or not currentHoveredItem or not tooltipRoot then return end  
  
  local success, data = pcall(json.decode, buffer)  
  if not success or not data or not data.clientId or data.clientId ~= currentHoveredItem:getId() then return end  
    
  tooltipRoot:hide()  
  updateTooltipText(data)  
  tooltipName:setText(data.name or "")  
  setLabelText(tooltipVocation, data.vocation)  
  setLabelText(tooltipLevel, data.level and ("Level: " .. data.level) or 1)  
  if tooltipIcon then tooltipIcon:setItemId(data.clientId) end  
  
  tooltipRoot:show()  
  tooltipRoot:raise()  
  tooltipRoot:focus()  
  
  local mousePos = g_window.getMousePosition()  
  local tooltipSize = tooltipRoot:getSize()  
  local windowSize = g_window.getSize()  
  local x = mousePos.x + 15  
  local y = mousePos.y + 5  
    
  if x + tooltipSize.width > windowSize.width then  
    x = mousePos.x - tooltipSize.width - 5  
  end  
  if y + tooltipSize.height > windowSize.height then  
    y = mousePos.y - tooltipSize.height - 5  
  end  
  
  tooltipRoot:setPosition({x = x, y = y})  
end  
  
function init()  
  tooltipRoot = g_ui.displayUI("tooltip")  
  tooltipName = tooltipRoot:getChildById("tooltipName")  
  tooltipText = tooltipRoot:getChildById("tooltipText")  
  tooltipVocation = tooltipRoot:getChildById("tooltipVocation")  
  tooltipLevel = tooltipRoot:getChildById("tooltipLevel")  
  tooltipIcon = tooltipRoot:getChildById("tooltipIcon")  
  tooltipRoot:hide()  
  
  ProtocolGame.registerExtendedOpcode(SendItemOpcode, onExtendedOpcode)  
end  
  
function terminate()  
  if tooltipRoot then  
    tooltipRoot:destroy()  
    tooltipRoot = nil  
  end  
  tooltipName = nil  
  tooltipText = nil  
  tooltipVocation = nil  
  tooltipLevel = nil  
  tooltipIcon = nil  
end  
  
function setLabelText(label, text)  
  if label then  
    if text and text ~= "" then  
      label:setText(text)  
      label:setVisible(true)  
    else  
      label:setVisible(false)  
    end  
  end  
end  
  
function UIItem:onHoverChange(hovered)  
  UIWidget.onHoverChange(self, hovered)  
  if tooltipDelayEvent then  
    removeEvent(tooltipDelayEvent)  
    tooltipDelayEvent = nil  
  end  
  
  if hovered then  
    local item = self:getItem()  
    if not item then return end  
    currentHoveredItem = item  
  
    tooltipDelayEvent = scheduleEvent(function()  
      if currentHoveredItem then  
        local protocolGame = g_game.getProtocolGame()  
        if protocolGame then  
          protocolGame:sendExtendedOpcode(SendItemOpcode, tostring(currentHoveredItem:getId()))  
        end  
        tooltipRoot:show()  
        tooltipText:setText("")  
        g_effects.fadeIn(tooltipRoot, 350)  
      end  
    end, 710)  
  else  
    currentHoveredItem = nil  
    tooltipRoot:hide()  
  end  
end