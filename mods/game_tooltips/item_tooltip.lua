local CODE_TOOLTIPS = 251

local tooltipWindow = nil
local itemSprite = nil
local itemWeightLabel = nil
local labels = nil
local currentHoveredItem = nil
local currentHoveredWidget = nil
local tooltipDelayEvent = nil

local BASE_WIDTH = 170
local BASE_HEIGHT = 0

local tooltipWidth = 0
local tooltipWidthBase = BASE_WIDTH
local tooltipHeight = BASE_HEIGHT
local longestString = 0

local Colors = {
  Default = "#ffffff",
  ItemLevel = "#abface",
  Description = "#8080ff",
  Implicit = "#ffbb22",
  Attribute = "#2266ff",
  Vocation = "#ff9999",
  Extra = "#aaaaff",
  Imbuement = "#55ff55",
  Tier = "#ffcc00",
  Augment = "#ff88ff"
}

local implicits = {
  ["ca"] = "Critical Damage",
  ["cc"] = "Critical Chance",
  ["la"] = "Life Leech",
  ["lc"] = "Life Leech Chance",
  ["ma"] = "Mana Leech",
  ["mc"] = "Mana Leech Chance",
  ["speed"] = "Movement Speed",
  ["fist"] = "Fist Fighting",
  ["sword"] = "Sword Fighting",
  ["club"] = "Club Fighting",
  ["axe"] = "Axe Fighting",
  ["dist"] = "Distance Fighting",
  ["shield"] = "Shielding",
  ["fish"] = "Fishing",
  ["mag"] = "Magic Level",
  ["a_phys"] = "Physical Protection",
  ["a_ene"] = "Energy Protection",
  ["a_earth"] = "Earth Protection",
  ["a_fire"] = "Fire Protection",
  ["a_ldrain"] = "Lifedrain Protection",
  ["a_mdrain"] = "Manadrain Protection",
  ["a_heal"] = "Healing Protection",
  ["a_drown"] = "Drown Protection",
  ["a_ice"] = "Ice Protection",
  ["a_holy"] = "Holy Protection",
  ["a_death"] = "Death Protection",
  ["a_all"] = "Protection All"
}

local impPercent = {
  ["ca"] = true,
  ["cc"] = true,
  ["la"] = true,
  ["lc"] = true,
  ["ma"] = true,
  ["mc"] = true,
  ["a_phys"] = true,
  ["a_ene"] = true,
  ["a_earth"] = true,
  ["a_fire"] = true,
  ["a_ldrain"] = true,
  ["a_mdrain"] = true,
  ["a_heal"] = true,
  ["a_drown"] = true,
  ["a_ice"] = true,
  ["a_holy"] = true,
  ["a_death"] = true,
  ["a_all"] = true
}

function init()
  connect(UIItem, { onHoverChange = onHoverChange })
  connect(g_game, { onGameEnd = resetData })

  ProtocolGame.registerExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  tooltipWindow = g_ui.displayUI("item_tooltip")
  tooltipWindow:hide()

  labels = tooltipWindow:getChildById("labels")
  itemWeightLabel = tooltipWindow:getChildById("itemWeightLabel")
  itemSprite = tooltipWindow:getChildById("itemSprite")
end

function terminate()
  disconnect(UIItem, { onHoverChange = onHoverChange })
  disconnect(g_game, { onGameEnd = resetData })

  ProtocolGame.unregisterExtendedOpcode(CODE_TOOLTIPS, onExtendedOpcode)

  if tooltipDelayEvent then
    removeEvent(tooltipDelayEvent)
    tooltipDelayEvent = nil
  end

  if tooltipWindow then
    currentHoveredItem = nil
    currentHoveredWidget = nil
    itemWeightLabel = nil
    itemSprite = nil
    labels = nil
    tooltipWindow:destroy()
    tooltipWindow = nil
  end
end

function onExtendedOpcode(protocol, code, buffer)
  local json_status, json_data = pcall(function()
    return json.decode(buffer)
  end)

  if not json_status then
    return
  end

  local action = json_data.action
  local data = json_data.data
  if not action or not data then
    return
  end
  if action == "new" then
    newTooltip(data)
  end
end

function newTooltip(data)
  if not currentHoveredItem or not data.clientId then return end
  if data.clientId ~= currentHoveredItem:getId() then return end

  local itemData = {
    id = currentHoveredItem:getId(),
    count = currentHoveredItem:getCount(),
    name = data.itemName or "",
    desc = data.desc,
    imp = data.imp,
    type = data.itemType or "",
    attack = data.attack or 0,
    defense = data.defense or 0,
    extraDefense = data.extraDefense or 0,
    armor = data.armor or 0,
    hitChance = data.hitChance or 0,
    shootRange = data.shootRange or 0,
    weight = data.weight or 0,
    reqLvl = data.reqLvl or 0,
    vocation = data.vocation,
    tier = data.tier or 0,
    tierDescription = data.tierDescription or "0",
    classification = data.classification or 0,
    augments = data.augments,
    imbuementSlots = data.imbuementSlots or 0,
    imbuements = data.imbuements,
    containerSize = data.containerSize
  }

  buildItemTooltip(itemData)
end

function resetData()
  currentHoveredItem = nil
  currentHoveredWidget = nil
  if tooltipDelayEvent then
    removeEvent(tooltipDelayEvent)
    tooltipDelayEvent = nil
  end
  if tooltipWindow then
    tooltipWindow:hide()
  end
end

function onHoverChange(widget, hovered)
  if tooltipDelayEvent then
    removeEvent(tooltipDelayEvent)
    tooltipDelayEvent = nil
  end

  if not hovered then
    currentHoveredItem = nil
    currentHoveredWidget = nil
    tooltipWindow:hide()
    return
  end

  if modules.client_options and not modules.client_options.getOption('showItemTooltips') then
    return
  end

  local item = widget:getItem()
  if not item then
    return
  end

  currentHoveredItem = item
  currentHoveredWidget = widget

  tooltipDelayEvent = scheduleEvent(function()
    if currentHoveredItem then
      local protocol = g_game.getProtocolGame()
      if protocol then
        local request = {
          clientId = currentHoveredItem:getId(),
          source = "inventory",
          slotIndex = 0,
          containerId = 0
        }

        local parent = currentHoveredWidget:getParent()
        if parent then
          local parentId = parent:getId()
          if parentId == "inventory" then
            local slotIndex = tonumber(currentHoveredWidget:getId():match("(%d+)"))
            if slotIndex then
              request.source = "inventory"
              request.slotIndex = slotIndex
            end
          elseif parentId:find("container") or parentId:find("Container") then
            request.source = "container"
            local containerPanel = parent
            while containerPanel do
              local cid = containerPanel:getChildById("containerId")
              if cid then
                request.containerId = tonumber(cid:getText()) or 0
                break
              end
              containerPanel = containerPanel:getParent()
            end
            local slotIdx = tonumber(currentHoveredWidget:getId():match("(%d+)"))
            if slotIdx then
              request.slotIndex = slotIdx
            end
          end
        end

        protocol:sendExtendedOpcode(CODE_TOOLTIPS, json.encode(request))
      end
    end
  end, 710)
end

function buildItemTooltip(item)
  tooltipWidth = 0
  longestString = 0
  tooltipWidthBase = BASE_WIDTH
  tooltipHeight = BASE_HEIGHT
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  labels:destroyChildren()

  local id = item.id
  local name = item.name
  local desc = item.desc
  local reqLvl = item.reqLvl or 0
  local itemTypeStr = item.type
  local attack = item.attack
  local defense = item.defense
  local extraDefense = item.extraDefense
  local armor = item.armor
  local hitChance = item.hitChance
  local shootRange = item.shootRange
  local weight = item.weight
  local tier = item.tier or 0
  local tierDescription = item.tierDescription or "0"
  local classification = item.classification or 0
  local augments = item.augments
  local imbuementSlots = item.imbuementSlots or 0
  local imbuements = item.imbuements
  local containerSize = item.containerSize
  local isEquipment = itemTypeStr ~= ""

  itemWeightLabel:setText(formatWeight(weight))

  itemSprite:setItemId(id)
  if item.count then
    itemSprite:setItemCount(item.count)
  end

  if tier and tier > 0 then
    if ItemsDatabase and ItemsDatabase.setTier then
      ItemsDatabase.setTier(itemSprite, tier, false)
    end
  else
    local tierWidget = itemSprite.tier
    if tierWidget then tierWidget:setVisible(false) end
  end

  name = name:gsub("(%a)(%a+)", function(a, b)
    return string.upper(a) .. string.lower(b)
  end)

  addString(name, "#ffffff")

  if item.vocation and item.vocation ~= "" and item.vocation ~= "All" then
    addString("Vocation: " .. item.vocation, Colors.Vocation)
  end

  if reqLvl > 0 then
    addString("Required Level " .. reqLvl, Colors.ItemLevel)
  end

  local hasStats = false

  if itemTypeStr == "Sword" or itemTypeStr == "Club" or itemTypeStr == "Axe" or itemTypeStr == "Fist" then
    if attack > 0 or defense > 0 or extraDefense > 0 then
      addSeparator()
      addEmpty(5)
      hasStats = true
      if attack > 0 then addString("Attack: " .. attack, Colors.Default) end
      if defense > 0 then addString("Defense: " .. defense, Colors.Default) end
      if extraDefense > 0 then addString("Extra-Defense: +" .. extraDefense, Colors.Default) end
    end
  elseif itemTypeStr == "Distance" then
    if attack > 0 or hitChance > 0 or shootRange > 0 then
      addSeparator()
      addEmpty(5)
      hasStats = true
      if attack > 0 then addString("Attack: " .. attack, Colors.Default) end
      if hitChance > 0 then addString("Hit Chance: +" .. hitChance .. "%", Colors.Default) end
      if shootRange > 0 then addString("Shoot Range: " .. shootRange, Colors.Default) end
    end
  elseif itemTypeStr == "Ammunition" then
    if attack > 0 then
      addSeparator()
      addEmpty(5)
      hasStats = true
      addString("Attack: " .. attack, Colors.Default)
    end
  elseif itemTypeStr == "Shield" then
    if defense > 0 then
      addSeparator()
      addEmpty(5)
      hasStats = true
      addString("Defense: " .. defense, Colors.Default)
    end
  elseif itemTypeStr == "Wand" then
    if attack > 0 then
      addSeparator()
      addEmpty(5)
      hasStats = true
      addString("Attack: " .. attack, Colors.Default)
    end
  elseif itemTypeStr == "Armor" then
    if armor > 0 or defense > 0 then
      addSeparator()
      addEmpty(5)
      hasStats = true
      if armor > 0 then addString("Armor: " .. armor, Colors.Default) end
      if defense > 0 then addString("Defense: " .. defense, Colors.Default) end
    end
  end

  local extraLines = {}
  if item.charge and item.charge > 0 then
    table.insert(extraLines, "Charges: " .. item.charge)
  end
  if containerSize and containerSize > 0 then
    table.insert(extraLines, "Volume: " .. containerSize)
  end

  if #extraLines > 0 then
    if hasStats then
      addEmpty(3)
    else
      addSeparator()
      addEmpty(5)
      hasStats = true
    end
    for _, line in ipairs(extraLines) do
      addString(line, Colors.Extra)
    end
  end

  if item.imp then
    local hasImpContent = false
    for _ in pairs(item.imp) do
      hasImpContent = true
      break
    end
    if hasImpContent then
      addSeparator()
      addEmpty(5)
      for key, value in pairs(item.imp) do
        local impText
        if not implicits[key] then
          impText = tostring(value)
        else
          impText = implicits[key] .. " " .. (value > 0 and "+" or "") .. value .. (impPercent[key] and "%" or "")
        end
        addString(impText, Colors.Implicit)
      end
    end
  end

  if imbuementSlots > 0 and imbuements then
    addSeparator()
    addEmpty(5)
    local imbParts = {}
    for _, slotData in ipairs(imbuements) do
      if slotData.name == "Empty Slot" then
        table.insert(imbParts, "(Empty Slot)")
      else
        local txt = slotData.name
        if slotData.duration and slotData.duration > 0 then
          local minutes = math.floor(slotData.duration / 60)
          local hours = math.floor(minutes / 60)
          local mins = minutes % 60
          txt = txt .. string.format(" (%02d:%02dh)", hours, mins)
        end
        table.insert(imbParts, txt)
      end
    end
    addString("Imbuements: " .. table.concat(imbParts, ", "), Colors.Imbuement)
  end

  if classification > 0 then
    addSeparator()
    addEmpty(5)
    addString("Classification: " .. classification .. " Tier: " .. tierDescription, Colors.Tier)
  end

  if augments and type(augments) == "string" and augments ~= "" then
    addString("Augments: (" .. augments .. ")", Colors.Augment)
  end

  if not isEquipment then
    if desc and desc:len() > 0 then
      addEmpty(5)
      addString(desc, Colors.Description, true)
    end
  end

  shrinkSeparators()
  showItemTooltip()
end

function addString(text, color, resize)
  local label = g_ui.createWidget("TooltipLabel", labels)
  label:setColor(color)

  if resize then
    tooltipWindow:setWidth(tooltipWidth)
    label:setTextWrap(true)
    label:setTextAutoResize(true)
    label:setText(text)
    tooltipHeight = tooltipHeight + label:getTextSize().height + 4
  else
    label:setText(text)
    local textSize = label:getTextSize()
    if longestString == 0 then
      longestString = textSize.width + itemWeightLabel:getWidth()
      tooltipWidth = tooltipWidthBase + longestString
      label:addAnchor(AnchorTop, "parent", AnchorTop)
    elseif textSize.width > longestString then
      longestString = textSize.width
      tooltipWidth = tooltipWidthBase + longestString
    end
    tooltipHeight = tooltipHeight + textSize.height
  end
end

function shrinkSeparators()
  local children = labels:getChildren()
  local m = math.max(60, math.floor(tooltipWidth / 4))
  for _, child in ipairs(children) do
    if child:getStyleName() == "TooltipSeparator" then
      child:setMarginLeft(m)
      child:setMarginRight(m)
    end
  end
end

function addSeparator()
  local sep = g_ui.createWidget("TooltipSeparator", labels)
  tooltipHeight = tooltipHeight + sep:getHeight() + sep:getMarginTop() + sep:getMarginBottom()
end

function addEmpty(height)
  local empty = g_ui.createWidget("TooltipEmpty", labels)
  empty:setHeight(height)
  tooltipHeight = tooltipHeight + height
end

function showItemTooltip()
  local mousePos = g_window.getMousePosition()
  tooltipHeight = math.max(tooltipHeight, 40)
  tooltipWindow:setWidth(tooltipWidth)
  tooltipWindow:setHeight(tooltipHeight)

  local windowSize = g_window.getSize()
  if mousePos.x > windowSize.width / 2 then
    tooltipWindow:move(mousePos.x - (tooltipWidth + 2), math.min(windowSize.height - tooltipHeight, mousePos.y + 5))
  else
    tooltipWindow:move(mousePos.x + 5, mousePos.y + 10)
  end
  tooltipWindow:raise()
  tooltipWindow:show()
  g_effects.fadeIn(tooltipWindow, 100)
end

function formatWeight(weight)
  if not weight then return "0.00 oz." end
  return string.format("%.2f oz.", weight)
end
