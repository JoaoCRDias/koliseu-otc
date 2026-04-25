--[[
  BTC Bot - Icones no Mapa

  Mostra icones BotIcon sobre o gameMapPanel para cada modulo do BTC Bot.
  Cada icone exibe o item representativo, nome e status ON/OFF.
  Clique alterna o estado do modulo correspondente.
  Ctrl+Drag reposiciona o icone.
]]

BTCBotIcons = BTCBotIcons or {}
BTCBotIcons.widgets = {}

BTCBotIcons.iconDefs = {
  { id = "healing",    itemId = 7643,  text = "Healing" },
  { id = "healfriend", itemId = 266,   text = "HealFriend" },
  { id = "mana",       itemId = 23373, text = "Mana" },
  { id = "attack",     itemId = 3155,  text = "Attack" },
  { id = "targeting",  itemId = 3079,  text = "Targeting" },
  { id = "cavebot",    itemId = 3003,  text = "CaveBot" },
  { id = "tools",      itemId = 3059,  text = "Tools" },
  { id = "equipment",  itemId = 3098,  text = "Equip" },
  { id = "time",       itemId = 3046,  text = "Time" },
  { id = "quiver",     itemId = 3447,  text = "Quiver" },
}

local moduleMap = {
  healing    = function() return BTCHealing end,
  healfriend = function() return BTCHealFriend end,
  mana       = function() return BTCMana end,
  attack     = function() return BTCAttack end,
  targeting  = function() return BTCTargeting end,
  cavebot    = function() return BTCCaveBot end,
  tools      = function() return BTCTools end,
  equipment  = function() return BTCEquipment end,
  time       = function() return BTCTime end,
  quiver     = function() return BTCQuiver end,
}

local function getModuleEnabled(id)
  local mod = moduleMap[id] and moduleMap[id]()
  if mod and mod.config then
    return mod.config.enabled or false
  end
  return false
end

local function setModuleEnabled(id, val)
  local mod = moduleMap[id] and moduleMap[id]()
  if not mod or not mod.config then return end

  mod.config.enabled = val

  if id == "attack" and BTCTargeting and BTCTargeting.config then
    BTCTargeting.config.enabled = val
    if BTCTargeting.saveConfig then BTCTargeting.saveConfig() end
  end

  if mod.saveConfig then mod.saveConfig() end
end

local function getSavedPositions()
  if BTCConfig and BTCConfig.get then
    return BTCConfig.get("iconPositions") or {}
  end
  return {}
end

local function savePositions(positions)
  if BTCConfig and BTCConfig.set then
    BTCConfig.set("iconPositions", positions)
  end
end

local function defaultPosition(index)
  local col = math.floor((index - 1) / 5)
  local row = (index - 1) % 5
  return 0.01 + col * 0.08, 0.05 + row * 0.15
end

local function applyPosition(widget, posX, posY)
  local parent = widget:getParent()
  if not parent then return end
  local parentRect = parent:getRect()
  local width  = parentRect.width  - widget:getWidth()
  local height = parentRect.height - widget:getHeight()
  widget:setMarginTop(math.max(height * (-0.5) - parent:getMarginTop(), height * (-0.5 + posY)))
  widget:setMarginLeft(width * (-0.5 + posX))
end

local function updateIconVisual(widget, enabled)
  widget.status:setOn(enabled)
  if enabled then
    widget.text:setColor('green')
  else
    widget.text:setColor('red')
  end
end

function BTCBotIcons.createAll()
  BTCBotIcons.destroyAll()

  local panel = modules.game_interface and modules.game_interface.gameMapPanel
  if not panel then return end

  local positions = getSavedPositions()

  for i, def in ipairs(BTCBotIcons.iconDefs) do
    local widget = g_ui.createWidget("BotIcon", panel)
    widget.botWidget = true
    widget.btcBotIcon = true

    widget.item:setItemId(def.itemId)
    widget.item:setShowCount(false)

    widget.hotkey:hide()

    widget.text:setText(def.text)

    local enabled = getModuleEnabled(def.id)
    updateIconVisual(widget, enabled)

    local posX, posY
    if positions[def.id] then
      posX = positions[def.id].x
      posY = positions[def.id].y
    else
      posX, posY = defaultPosition(i)
    end
    widget._posX = posX
    widget._posY = posY
    widget._defId = def.id

    widget.setOn = function(val)
      widget.status:setOn(val)
      if widget.status:isOn() then
        widget.text:setColor('green')
      else
        widget.text:setColor('red')
      end
    end

    widget.onClick = function(w)
      local newState = not getModuleEnabled(def.id)
      setModuleEnabled(def.id, newState)
      updateIconVisual(w, newState)
    end

    widget.onDragEnter = function(w, mousePos)
      if not g_keyboard.isCtrlPressed() then
        return false
      end
      w:breakAnchors()
      w.movingReference = { x = mousePos.x - w:getX(), y = mousePos.y - w:getY() }
      return true
    end

    widget.onDragMove = function(w, mousePos, moved)
      local parentRect = w:getParent():getRect()
      local x = math.min(math.max(parentRect.x, mousePos.x - w.movingReference.x), parentRect.x + parentRect.width - w:getWidth())
      local y = math.min(math.max(parentRect.y - w:getParent():getMarginTop(), mousePos.y - w.movingReference.y), parentRect.y + parentRect.height - w:getHeight())
      w:move(x, y)
      return true
    end

    widget.onDragLeave = function(w, pos)
      local parent = w:getParent()
      local parentRect = parent:getRect()
      local lx = w:getX() - parentRect.x
      local ly = w:getY() - parentRect.y
      local width  = parentRect.width  - w:getWidth()
      local height = parentRect.height - w:getHeight()

      local nx = math.min(1, math.max(0, lx / width))
      local ny = math.min(1, math.max(0, ly / height))
      w._posX = nx
      w._posY = ny

      local saved = getSavedPositions()
      saved[def.id] = { x = nx, y = ny }
      savePositions(saved)

      w:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
      w:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      applyPosition(w, nx, ny)
      return true
    end

    widget.onGeometryChange = function(w)
      if w:isDragging() then return end
      applyPosition(w, w._posX, w._posY)
    end

    widget.onMouseRelease = function()
      return true
    end

    BTCBotIcons.widgets[def.id] = widget
  end
end

function BTCBotIcons.destroyAll()
  for id, widget in pairs(BTCBotIcons.widgets) do
    if widget and not widget:isDestroyed() then
      widget:destroy()
    end
  end
  BTCBotIcons.widgets = {}
end

function BTCBotIcons.syncStates()
  for id, widget in pairs(BTCBotIcons.widgets) do
    if widget and not widget:isDestroyed() then
      local enabled = getModuleEnabled(id)
      updateIconVisual(widget, enabled)
    end
  end
end
