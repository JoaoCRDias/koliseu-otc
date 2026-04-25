--[[
  BTC Bot - Sistema de Mana
  
  3 slots de mana configuraveis
  Usa mana potions para recuperar MP
  Interface com icones das potions
]]

BTCMana = BTCMana or {}

-- Configuracao padrao dos 3 slots de mana
BTCMana.defaultConfig = {
  enabled = true,  -- Modulo ativo por padrao
  slot1 = {
    enabled = true,
    itemId = 268,
    mpPercent = 80,
    operator = "<=",
  },
  slot2 = {
    enabled = false,
    itemId = 238,
    mpPercent = 60,
    operator = "<=",
  },
  slot3 = {
    enabled = false,
    itemId = 23373,
    mpPercent = 40,
    operator = "<=",
  }
}

-- Lista de mana potions
BTCMana.manaPotions = {
  { id = 268,   name = "Mana Potion" },
  { id = 237,   name = "Strong Mana Potion" },
  { id = 238,   name = "Great Mana Potion" },
  { id = 23373, name = "Ultimate Mana Potion" },
  -- Spirit Potions (Paladin - recuperam HP e Mana)
  { id = 7642,  name = "Great Spirit Potion" },
  { id = 23374, name = "Ultimate Spirit Potion" },
  -- Eternal Potions (infinitas)
  { id = 51972, name = "Eternal Ultimate Mana Potion" },
  { id = 51973, name = "Eternal Ultimate Spirit Potion" },
}

-- Popup de selecao de potion
BTCMana.potionPopup = nil

-- Variaveis de controle
BTCMana.config = nil
BTCMana.lastManaTime = 0
BTCMana.manaCooldown = 1000

-- Inicializa o modulo
function BTCMana.init()
  BTCMana.config = BTCMana.loadConfig()
end

-- Carrega configuracao salva ou usa padrao
function BTCMana.loadConfig()
  local saved = BTCConfig.get("mana")
  if saved then
    return saved
  end
  return BTCMana.defaultConfig
end

-- Salva configuracao
function BTCMana.saveConfig()
  BTCConfig.set("mana", BTCMana.config)
end

-- Obtem configuracao de um slot
function BTCMana.getSlotConfig(slotNum)
  local key = "slot" .. slotNum
  if BTCMana.config and BTCMana.config[key] then
    return BTCMana.config[key]
  end
  return BTCMana.defaultConfig["slot" .. slotNum]
end

-- Atualiza configuracao de um slot
function BTCMana.setSlotConfig(slotNum, config)
  local key = "slot" .. slotNum
  BTCMana.config[key] = config
  BTCMana.saveConfig()
end

-- Verifica se pode usar potion (cooldown)
function BTCMana.canUseMana()
  local now = g_clock.millis()
  return (now - BTCMana.lastManaTime) >= BTCMana.manaCooldown
end

-- Executa uso de mana potion
function BTCMana.useManaPotion(itemId)
  if not g_game.isOnline() then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  g_game.useInventoryItemWith(itemId, player, 0)
  BTCMana.lastManaTime = g_clock.millis()
  return true
end

-- Funcao principal de execucao
function BTCMana.execute()
  if not g_game.isOnline() then return end
  
  -- Verifica se o modulo de mana esta ativo
  if not BTCMana.config or not BTCMana.config.enabled then return end
  
  if not BTCMana.canUseMana() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  local mana = player:getMana()
  local maxMana = player:getMaxMana()
  
  if maxMana == 0 then return end
  
  local manaPercent = (mana / maxMana) * 100
  
  -- Verifica cada slot (prioridade: slot1 > slot2 > slot3)
  for i = 1, 3 do
    local slotConfig = BTCMana.getSlotConfig(i)
    
    local op = slotConfig.operator or "<="
    local condMet = (op == ">=") and (manaPercent >= slotConfig.mpPercent) or (manaPercent <= slotConfig.mpPercent)
    if slotConfig.enabled and condMet then
      if slotConfig.itemId and slotConfig.itemId > 0 then
        if BTCMana.useManaPotion(slotConfig.itemId) then
          return
        end
      end
    end
  end
end

-- Cria a UI do modulo
function BTCMana.createUI(container)
  if not container then return end
  
  container:destroyChildren()
  
  -- Titulo do modulo
  local title = g_ui.createWidget("Label", container)
  title:setText("Mana Potions")
  title:setTextAlign(AlignCenter)
  title:setFont("verdana-11px-rounded")
  title:setColor("#00BFFF")
  title:setHeight(20)
  title:setMarginBottom(5)
  
  -- Cria 3 slots (separador ja esta dentro de createSlotUI)
  for i = 1, 3 do
    BTCMana.createSlotUI(container, i)
  end
end

-- Fecha popup se existir
function BTCMana.closePopup()
  if BTCMana.potionPopup then
    BTCMana.potionPopup:destroy()
    BTCMana.potionPopup = nil
  end
end

-- Cria popup de selecao de potion com icones
function BTCMana.showPotionPopup(itemBox, slotNum, slotConfig, onSelect)
  BTCMana.closePopup()
  
  local potionCount = #BTCMana.manaPotions
  local itemSize = 42
  local spacing = 5
  local padding = 8
  local popupWidth = (itemSize * potionCount) + (spacing * (potionCount - 1)) + (padding * 2)
  local popupHeight = itemSize + (padding * 2)
  
  -- Cria popup panel
  local popup = g_ui.createWidget("Panel", rootWidget)
  popup:setId("manaPotionPopup")
  BTCMana.potionPopup = popup
  
  -- Estilo do popup - sem borda externa
  popup:setBackgroundColor("#2a2a2a")
  popup:setWidth(popupWidth)
  popup:setHeight(popupHeight)
  
  -- Layout horizontal para os icones
  popup:setLayout(UIHorizontalLayout.create(popup))
  popup:getLayout():setSpacing(spacing)
  popup:setPaddingLeft(padding)
  popup:setPaddingRight(padding)
  popup:setPaddingTop(padding)
  popup:setPaddingBottom(padding)
  
  -- Adiciona cada potion em seu proprio quadrado
  for _, potion in ipairs(BTCMana.manaPotions) do
    -- Container individual para cada potion (quadrado)
    local potionBox = g_ui.createWidget("Button", popup)
    potionBox:setSize({width = itemSize, height = itemSize})
    potionBox:setText("")
    
    -- Visual diferente se selecionado
    if slotConfig.itemId == potion.id then
      potionBox:setBackgroundColor("#004455")
      potionBox:setBorderWidth(2)
      potionBox:setBorderColor("#00FFFF")
    end
    
    -- Icone do item centralizado com anchors
    local itemWidget = g_ui.createWidget("UIItem", potionBox)
    itemWidget:setSize({width = 32, height = 32})
    itemWidget:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    itemWidget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemWidget:setVirtual(true)
    itemWidget:setPhantom(true)
    itemWidget:setItemId(potion.id)
    
    -- Tooltip no container
    potionBox:setTooltip(potion.name)
    
    -- Clique no quadrado seleciona a potion
    potionBox.onClick = function()
      slotConfig.itemId = potion.id
      BTCMana.setSlotConfig(slotNum, slotConfig)
      if onSelect then
        onSelect(potion.id)
      end
      BTCMana.closePopup()
    end
  end
  
  -- Posiciona o popup perto do itemBox
  local pos = itemBox:getPosition()
  popup:setPosition({x = pos.x - 20, y = pos.y + 44})
  
  -- Fecha ao clicar fora
  popup:raise()
  popup:focus()
  
  -- Timer para fechar se clicar fora
  popup.onFocusChange = function(widget, focused)
    if not focused then
      scheduleEvent(function()
        BTCMana.closePopup()
      end, 100)
    end
  end
end

-- Cria UI de um slot (mesmo layout do Healing)
function BTCMana.createSlotUI(parent, slotNum)
  local slotConfig = BTCMana.getSlotConfig(slotNum)
  
  -- Linha 1: ON/OFF
  local row1 = g_ui.createWidget('Panel', parent)
  row1:setHeight(26)
  row1:setMarginTop(5)
  
  local enabledBtn = g_ui.createWidget('Button', row1)
  enabledBtn:setText(slotConfig.enabled and 'ON' or 'OFF')
  enabledBtn:setColor(slotConfig.enabled and '#00ff00' or '#ff4444')
  enabledBtn:setWidth(40)
  enabledBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  enabledBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  enabledBtn.onClick = function()
    slotConfig.enabled = not slotConfig.enabled
    enabledBtn:setText(slotConfig.enabled and 'ON' or 'OFF')
    enabledBtn:setColor(slotConfig.enabled and '#00ff00' or '#ff4444')
    BTCMana.setSlotConfig(slotNum, slotConfig)
  end
  
  -- Linha 2: Potion (Icone + Nome)
  local row2 = g_ui.createWidget('Panel', parent)
  row2:setHeight(36)
  row2:setMarginTop(5)
  
  local potionLabel = g_ui.createWidget('Label', row2)
  potionLabel:setText('Potion:')
  potionLabel:setColor('#aaaaaa')
  potionLabel:setWidth(50)
  potionLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  potionLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local itemPreview = g_ui.createWidget("UIItem", row2)
  itemPreview:setSize({width = 34, height = 34})
  itemPreview:addAnchor(AnchorLeft, 'prev', AnchorRight)
  itemPreview:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  itemPreview:setMarginLeft(5)
  itemPreview:setVirtual(true)
  if slotConfig.itemId and slotConfig.itemId > 0 then
    itemPreview:setItemId(slotConfig.itemId)
  end

  local selectBtn = g_ui.createWidget('Button', row2)
  selectBtn:setText('...')
  selectBtn:setWidth(26)
  selectBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  selectBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  selectBtn:setMarginLeft(3)
  selectBtn:setTooltip('Selecionar item')
  selectBtn.onClick = function()
    BTCItemSelector.start(function(itemId)
      slotConfig.itemId = itemId
      BTCMana.setSlotConfig(slotNum, slotConfig)
      itemPreview:setItemId(itemId)
    end)
  end
  
  -- Linha 3: MP%
  local row3 = g_ui.createWidget('Panel', parent)
  row3:setHeight(22)
  row3:setMarginTop(3)
  row3:setMarginBottom(10)
  
  local mpLabel = g_ui.createWidget('Label', row3)
  mpLabel:setText('MP')
  mpLabel:setColor('#aaaaaa')
  mpLabel:setWidth(22)
  mpLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  mpLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local opCombo = g_ui.createWidget('ComboBox', row3)
  opCombo:setWidth(45)
  opCombo:addOption('<=')
  opCombo:addOption('>=')
  opCombo:setCurrentOption(slotConfig.operator == ">=" and ">=" or "<=")
  opCombo:addAnchor(AnchorLeft, 'prev', AnchorRight)
  opCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  opCombo:setMarginLeft(3)
  opCombo.onOptionChange = function(widget, option)
    slotConfig.operator = option
    BTCMana.setSlotConfig(slotNum, slotConfig)
  end

  local minusBtn = g_ui.createWidget('Button', row3)
  minusBtn:setText('-')
  minusBtn:setWidth(20)
  minusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  minusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  minusBtn:setMarginLeft(5)
  
  local mpValue = g_ui.createWidget('Label', row3)
  mpValue:setText(slotConfig.mpPercent .. '%')
  mpValue:setColor('#00BFFF')
  mpValue:setTextAlign(AlignCenter)
  mpValue:setWidth(45)
  mpValue:addAnchor(AnchorLeft, 'prev', AnchorRight)
  mpValue:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local plusBtn = g_ui.createWidget('Button', row3)
  plusBtn:setText('+')
  plusBtn:setWidth(20)
  plusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  plusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  minusBtn.onClick = function()
    if slotConfig.mpPercent > 5 then
      slotConfig.mpPercent = slotConfig.mpPercent - 5
      mpValue:setText(slotConfig.mpPercent .. '%')
      BTCMana.setSlotConfig(slotNum, slotConfig)
    end
  end
  
  plusBtn.onClick = function()
    if slotConfig.mpPercent < 100 then
      slotConfig.mpPercent = slotConfig.mpPercent + 5
      mpValue:setText(slotConfig.mpPercent .. '%')
      BTCMana.setSlotConfig(slotNum, slotConfig)
    end
  end
  
  -- Separador entre slots
  if slotNum < 3 then
    local sep = g_ui.createWidget('HorizontalSeparator', parent)
    sep:setMarginTop(5)
    sep:setMarginBottom(5)
  end
end

-- Retorna status do modulo
function BTCMana.getStatus()
  local enabled = BTCMana.config and BTCMana.config.enabled
  return enabled and "ON" or "OFF"
end

-- Inicializa
BTCMana.init()
