--[[
  BTC Bot - Sistema de Equipment (Ring/Amulet)
  
  Equipa automaticamente rings e amulets baseado em HP/MP:
  - Quando HP/MP <= threshold% -> EQUIPA o item
  - Quando HP/MP > threshold% -> REMOVE o item (move para backpack)
  
  Exemplo: threshold = 80%
  - HP cai para 75% -> Equipa Energy Ring
  - HP sobe para 85% -> Remove Energy Ring
]]

BTCEquipment = BTCEquipment or {}

-- Configuracao padrao
BTCEquipment.defaultConfig = {
  enabled = false,
  slots = {
    {
      enabled = false,
      itemId = 0,
      type = "ring",
      condition = "life",
      operator = "<=",
      threshold = 80,
    },
    {
      enabled = false,
      itemId = 0,
      type = "ring",
      condition = "life",
      operator = "<=",
      threshold = 50,
    },
    {
      enabled = false,
      itemId = 0,
      type = "amulet",
      condition = "life",
      operator = "<=",
      threshold = 80,
    },
    {
      enabled = false,
      itemId = 0,
      type = "amulet",
      condition = "mana",
      operator = "<=",
      threshold = 50,
    },
  }
}

-- Slots do inventario (InventorySlot enum)
BTCEquipment.SLOT_HEAD = 1
BTCEquipment.SLOT_NECKLACE = 2      -- AMULET slot correto
BTCEquipment.SLOT_BACKPACK = 3
BTCEquipment.SLOT_ARMOR = 4
BTCEquipment.SLOT_RIGHT = 5
BTCEquipment.SLOT_LEFT = 6
BTCEquipment.SLOT_LEGS = 7
BTCEquipment.SLOT_FEET = 8
BTCEquipment.SLOT_FINGER = 9        -- RING slot correto
BTCEquipment.SLOT_AMMO = 10

-- Variaveis de controle
BTCEquipment.config = nil
BTCEquipment.lastActionTime = {}
BTCEquipment.actionCooldown = 500   -- Cooldown entre acoes (equip/unequip)

-- Inicializa o modulo
function BTCEquipment.init()
  BTCEquipment.config = BTCEquipment.loadConfig()
end

-- Carrega configuracao
function BTCEquipment.loadConfig()
  local saved = BTCConfig.get("equipment")
  if saved then
    return saved
  end
  return table.copy(BTCEquipment.defaultConfig)
end

-- Salva configuracao
function BTCEquipment.saveConfig()
  BTCConfig.set("equipment", BTCEquipment.config)
end

-- Retorna porcentagem de vida
function BTCEquipment.getHealthPercent()
  if not g_game.isOnline() then return 100 end
  local player = g_game.getLocalPlayer()
  if not player then return 100 end
  
  local health = player:getHealth()
  local maxHealth = player:getMaxHealth()
  if maxHealth == 0 then return 100 end
  
  return math.floor((health / maxHealth) * 100)
end

-- Retorna porcentagem de mana
function BTCEquipment.getManaPercent()
  if not g_game.isOnline() then return 100 end
  local player = g_game.getLocalPlayer()
  if not player then return 100 end
  
  local mana = player:getMana()
  local maxMana = player:getMaxMana()
  if maxMana == 0 then return 100 end
  
  return math.floor((mana / maxMana) * 100)
end

-- Retorna o valor atual da condicao (life ou mana)
function BTCEquipment.getCurrentValue(condition)
  if condition == "life" then
    return BTCEquipment.getHealthPercent()
  elseif condition == "mana" then
    return BTCEquipment.getManaPercent()
  end
  return 100
end

-- Verifica cooldown para acao
function BTCEquipment.canAct(slotIndex)
  local now = g_clock.millis()
  local lastAction = BTCEquipment.lastActionTime[slotIndex] or 0
  return (now - lastAction) >= BTCEquipment.actionCooldown
end

-- Atualiza cooldown
function BTCEquipment.updateCooldown(slotIndex)
  BTCEquipment.lastActionTime[slotIndex] = g_clock.millis()
end

-- Retorna o slot de inventario correto para o tipo
function BTCEquipment.getInventorySlot(slotType)
  if slotType == "ring" then
    return BTCEquipment.SLOT_FINGER
  elseif slotType == "amulet" then
    return BTCEquipment.SLOT_NECKLACE
  end
  return nil
end

-- Procura item nos containers (backpacks)
function BTCEquipment.findItemInContainers(itemId)
  if not itemId or itemId == 0 then return nil, nil end
  
  local containers = g_game.getContainers()
  for _, container in pairs(containers) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == itemId then
        return item, container
      end
    end
  end
  
  return nil, nil
end

-- Encontra o primeiro container aberto (para mover item para la)
function BTCEquipment.findOpenContainer()
  local containers = g_game.getContainers()
  for _, container in pairs(containers) do
    if container:getItemsCount() < container:getCapacity() then
      return container
    end
  end
  -- Se todos estao cheios, retorna o primeiro mesmo
  for _, container in pairs(containers) do
    return container
  end
  return nil
end

-- Retorna o item equipado no slot especificado
function BTCEquipment.getEquippedItem(slotType)
  if not g_game.isOnline() then return nil end
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  
  local inventorySlot = BTCEquipment.getInventorySlot(slotType)
  if not inventorySlot then return nil end
  
  return player:getInventoryItem(inventorySlot)
end

-- Verifica se o item especificado esta equipado
function BTCEquipment.isItemEquipped(itemId, slotType)
  local equippedItem = BTCEquipment.getEquippedItem(slotType)
  return equippedItem and equippedItem:getId() == itemId
end

-- EQUIPA um item da backpack para o slot
function BTCEquipment.equipItem(slotIndex, slot)
  if not g_game.isOnline() then return false end
  if not BTCEquipment.canAct(slotIndex) then return false end
  
  -- Ja esta equipado?
  if BTCEquipment.isItemEquipped(slot.itemId, slot.type) then
    return false
  end
  
  -- Procura o item na backpack
  local item, container = BTCEquipment.findItemInContainers(slot.itemId)
  if not item then
    return false
  end
  
  -- Move para o slot de equipamento
  local inventorySlot = BTCEquipment.getInventorySlot(slot.type)
  if not inventorySlot then return false end
  
  local destPos = {x = 65535, y = inventorySlot, z = 0}
  g_game.move(item, destPos, 1)
  
  BTCEquipment.updateCooldown(slotIndex)
  return true
end

-- REMOVE um item equipado e move para a backpack
function BTCEquipment.unequipItem(slotIndex, slot)
  if not g_game.isOnline() then return false end
  if not BTCEquipment.canAct(slotIndex) then return false end
  
  -- Verifica se o item esta equipado
  if not BTCEquipment.isItemEquipped(slot.itemId, slot.type) then
    return false
  end
  
  local equippedItem = BTCEquipment.getEquippedItem(slot.type)
  if not equippedItem then return false end
  
  -- Encontra um container para mover
  local container = BTCEquipment.findOpenContainer()
  if not container then
    return false
  end
  
  -- Move o item para o container
  local destPos = container:getSlotPosition(container:getItemsCount())
  g_game.move(equippedItem, destPos, 1)
  
  BTCEquipment.updateCooldown(slotIndex)
  return true
end

-- Funcao principal de execucao
function BTCEquipment.execute()
  if not g_game.isOnline() then return end
  if not BTCEquipment.config or not BTCEquipment.config.enabled then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  for i, slot in ipairs(BTCEquipment.config.slots) do
    if slot.enabled and slot.itemId and slot.itemId > 0 then
      local currentValue = BTCEquipment.getCurrentValue(slot.condition)
      local threshold = slot.threshold or 80
      local op = slot.operator or "<="
      local condMet = (op == ">=") and (currentValue >= threshold) or (currentValue <= threshold)
      
      if condMet then
        BTCEquipment.equipItem(i, slot)
      else
        BTCEquipment.unequipItem(i, slot)
      end
    end
  end
end

-- Cria a interface
function BTCEquipment.createUI(parent)
  parent:destroyChildren()
  
  local titleLabel = g_ui.createWidget('Label', parent)
  titleLabel:setText('Auto Ring/Amulet - Equipa quando HP/MP baixo')
  titleLabel:setColor('#00ff88')
  titleLabel:setHeight(20)
  titleLabel:setMarginBottom(3)
  
  local descLabel = g_ui.createWidget('Label', parent)
  descLabel:setText('Equipa quando condicao atendida, remove quando nao.')
  descLabel:setColor('#888888')
  descLabel:setHeight(16)
  descLabel:setMarginBottom(8)
  
  for i = 1, 4 do
    BTCEquipment.createSlotUI(parent, i)
  end
end

-- Cria UI de um slot
function BTCEquipment.createSlotUI(parent, slotIndex)
  local slot = BTCEquipment.config.slots[slotIndex]
  if not slot then return end
  
  -- Container do slot
  local slotPanel = g_ui.createWidget('Panel', parent)
  slotPanel:setLayout(UIVerticalLayout.create(slotPanel))
  slotPanel:setHeight(60)
  slotPanel:setMarginTop(5)
  slotPanel:setBackgroundColor('#1a1a1a')
  slotPanel:setPadding(5)
  
  -- Linha 1: Checkbox + Tipo + Item Icon
  local row1 = g_ui.createWidget('Panel', slotPanel)
  row1:setLayout(UIHorizontalLayout.create(row1))
  row1:setHeight(26)
  
  local enableCheck = g_ui.createWidget('CheckBox', row1)
  enableCheck:setText('Slot ' .. slotIndex)
  enableCheck:setChecked(slot.enabled)
  enableCheck:setWidth(65)
  
  enableCheck.onCheckChange = function(widget, checked)
    BTCEquipment.config.slots[slotIndex].enabled = checked
    BTCEquipment.saveConfig()
  end
  
  local typeCombo = g_ui.createWidget('ComboBox', row1)
  typeCombo:setWidth(75)
  typeCombo:addOption('Ring')
  typeCombo:addOption('Amulet')
  typeCombo:setCurrentOption(slot.type == "ring" and "Ring" or "Amulet")
  typeCombo:setMarginLeft(10)
  
  typeCombo.onOptionChange = function(widget, option)
    BTCEquipment.config.slots[slotIndex].type = option:lower()
    BTCEquipment.saveConfig()
  end

  local itemPreview = g_ui.createWidget('UIItem', row1)
  itemPreview:setSize({width = 34, height = 34})
  itemPreview:setMarginLeft(10)
  itemPreview:setVirtual(true)
  if slot.itemId and slot.itemId > 0 then
    itemPreview:setItemId(slot.itemId)
  end

  local selectBtn = g_ui.createWidget('Button', row1)
  selectBtn:setText('...')
  selectBtn:setWidth(26)
  selectBtn:setTooltip('Selecionar item')
  selectBtn.onClick = function()
    BTCItemSelector.start(function(itemId)
      BTCEquipment.config.slots[slotIndex].itemId = itemId
      BTCEquipment.saveConfig()
      itemPreview:setItemId(itemId)
    end)
  end
  
  -- Linha 2: Condicao
  local row2 = g_ui.createWidget('Panel', slotPanel)
  row2:setLayout(UIHorizontalLayout.create(row2))
  row2:setHeight(22)
  row2:setMarginTop(3)
  
  local whenLabel = g_ui.createWidget('Label', row2)
  whenLabel:setText('Equipar quando')
  whenLabel:setColor('#888888')
  whenLabel:setWidth(95)
  
  local condCombo = g_ui.createWidget('ComboBox', row2)
  condCombo:setWidth(60)
  condCombo:addOption('Life')
  condCombo:addOption('Mana')
  condCombo:setCurrentOption(slot.condition == "life" and "Life" or "Mana")
  condCombo:setMarginLeft(5)
  
  condCombo.onOptionChange = function(widget, option)
    BTCEquipment.config.slots[slotIndex].condition = option:lower()
    BTCEquipment.saveConfig()
  end
  
  local opCombo = g_ui.createWidget('ComboBox', row2)
  opCombo:setWidth(45)
  opCombo:addOption('<=')
  opCombo:addOption('>=')
  opCombo:setCurrentOption(slot.operator == ">=" and ">=" or "<=")
  opCombo:setMarginLeft(5)
  opCombo.onOptionChange = function(widget, option)
    BTCEquipment.config.slots[slotIndex].operator = option
    BTCEquipment.saveConfig()
  end

  local thresholdInput = g_ui.createWidget('TextEdit', row2)
  thresholdInput:setWidth(40)
  thresholdInput:setText(tostring(slot.threshold or 80))
  thresholdInput:setMarginLeft(5)

  local percentLabel = g_ui.createWidget('Label', row2)
  percentLabel:setText('%')
  percentLabel:setColor('#888888')
  percentLabel:setWidth(20)
  percentLabel:setMarginLeft(2)

  thresholdInput.onTextChange = function(widget, text)
    local value = tonumber(text) or 80
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    BTCEquipment.config.slots[slotIndex].threshold = value
    BTCEquipment.saveConfig()
  end
end

return BTCEquipment
