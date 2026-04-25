--[[
  BTC Bot - Sistema de Healing
  
  3 slots de cura configuraveis
  Cada slot pode ser Spell ou Potion
]]

BTCHealing = BTCHealing or {}

-- Configuracao padrao dos 3 slots de healing
BTCHealing.defaultConfig = {
  enabled = true,  -- Modulo ativo por padrao
  slot1 = {
    enabled = true,
    type = "spell",
    spell = "exura gran",
    itemId = 0,
    hpPercent = 70,
    operator = "<=",
  },
  slot2 = {
    enabled = true,
    type = "spell",
    spell = "exura vita",
    itemId = 0,
    hpPercent = 50,
    operator = "<=",
  },
  slot3 = {
    enabled = true,
    type = "potion",
    spell = "",
    itemId = 7643,
    hpPercent = 30,
    operator = "<=",
  }
}

-- Lista de potions de vida
BTCHealing.healthPotions = {
  { id = 266,   name = "Health Potion" },
  { id = 236,   name = "Strong Health Potion" },
  { id = 239,   name = "Great Health Potion" },
  { id = 7643,  name = "Ultimate Health Potion" },
  { id = 23375, name = "Supreme Health Potion" },
  -- Spirit Potions (Paladin - recuperam HP e Mana)
  { id = 7642,  name = "Great Spirit Potion" },
  { id = 23374, name = "Ultimate Spirit Potion" },
  -- Eternal Potions (infinitas)
  { id = 51971, name = "Eternal Supreme Health Potion" },
  { id = 51973, name = "Eternal Ultimate Spirit Potion" },
}

-- Popup de selecao de potion
BTCHealing.potionPopup = nil

-- Lista de spells de cura (AUTO HEAL - apenas para si mesmo)
-- Vocacoes OTClient: 1=Knight, 2=Paladin, 3=Sorcerer, 4=Druid, 5=Monk
--                   11=EK, 12=RP, 13=MS, 14=ED, 15=Exalted Monk
BTCHealing.healSpells = {
  -- Sorcerer / Druid / Paladin (basicas)
  { words = "exura infir", mana = 6, level = 1, voc = {2,3,4,12,13,14} },       -- Magic Patch
  { words = "exura", mana = 20, level = 8, voc = {2,3,4,12,13,14} },            -- Light Healing
  -- Sorcerer / Druid / Paladin / Monk
  { words = "exura gran", mana = 70, level = 20, voc = {2,3,4,5,12,13,14,15} }, -- Intense Healing
  -- Sorcerer / Druid apenas
  { words = "exura vita", mana = 160, level = 30, voc = {3,4,13,14} },         -- Ultimate Healing
  { words = "exura max vita", mana = 260, level = 300, voc = {3,4,13,14} },    -- Restoration
  -- Paladin
  { words = "exura san", mana = 160, level = 35, voc = {2,12} },              -- Divine Healing
  { words = "exura gran san", mana = 210, level = 60, voc = {2,12} },         -- Salvation
  -- Knight
  { words = "exura infir ico", mana = 10, level = 1, voc = {1,11} },          -- Bruise Bane
  { words = "exura ico", mana = 40, level = 8, voc = {1,11} },                -- Wound Cleansing
  { words = "exura gran ico", mana = 200, level = 80, voc = {1,11} },         -- Intense Wound Cleansing (10min CD)
  { words = "exura med ico", mana = 90, level = 300, voc = {1,11} },          -- Fair Wound Cleansing
  -- Monk (curas exclusivas)
  { words = "exura gran tio", mana = 210, level = 80, voc = {5,15} },        -- Spirit Mend
  { words = "exura mas nia", mana = 250, level = 150, voc = {5,15} },        -- Mass Spirit Mend (AoE)
  -- Regeneracao (Knight / Paladin apenas)
  { words = "utura", mana = 75, level = 50, voc = {1,2,11,12} },               -- Recovery
  { words = "utura gran", mana = 165, level = 100, voc = {1,2,11,12} },        -- Intense Recovery
}

-- Retorna vocacao do player (ou 0 se nao conseguir)
function BTCHealing.getPlayerVocation()
  if not g_game.isOnline() then return 0 end
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  return player:getVocation() or 0
end

-- Retorna lista de spells filtrada pela vocacao atual
function BTCHealing.getAvailableSpells()
  local voc = BTCHealing.getPlayerVocation()
  local available = {}
  
  for _, spell in ipairs(BTCHealing.healSpells) do
    -- Se voc = 0, mostra todas (nao logado)
    if voc == 0 then
      table.insert(available, spell)
    else
      -- Verifica se a spell e para essa vocacao
      for _, v in ipairs(spell.voc) do
        if v == voc then
          table.insert(available, spell)
          break
        end
      end
    end
  end
  
  return available
end

-- Variaveis de controle
BTCHealing.config = nil
BTCHealing.lastHealTime = 0
BTCHealing.healCooldown = 1000

-- Inicializa o modulo
function BTCHealing.init()
  BTCHealing.config = BTCHealing.loadConfig()
end

-- Carrega configuracao salva ou usa padrao
function BTCHealing.loadConfig()
  local saved = BTCConfig.get("healing")
  if saved then
    return saved
  end
  return BTCHealing.defaultConfig
end

-- Salva configuracao
function BTCHealing.saveConfig()
  BTCConfig.set("healing", BTCHealing.config)
end

-- Obtem configuracao de um slot
function BTCHealing.getSlotConfig(slotNum)
  local key = "slot" .. slotNum
  if BTCHealing.config and BTCHealing.config[key] then
    return BTCHealing.config[key]
  end
  return BTCHealing.defaultConfig["slot" .. slotNum]
end

-- Atualiza configuracao de um slot
function BTCHealing.setSlotConfig(slotNum, config)
  local key = "slot" .. slotNum
  BTCHealing.config[key] = config
  BTCHealing.saveConfig()
end

-- Verifica se pode curar (cooldown)
function BTCHealing.canHeal()
  local now = g_clock.millis()
  return (now - BTCHealing.lastHealTime) >= BTCHealing.healCooldown
end

-- Executa cura com spell
function BTCHealing.castHealSpell(spell)
  if not g_game.isOnline() then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  local mana = player:getMana()
  local spellInfo = nil
  
  for _, s in ipairs(BTCHealing.healSpells) do
    if s.words == spell then
      spellInfo = s
      break
    end
  end
  
  if spellInfo and mana < spellInfo.mana then
    return false
  end
  
  g_game.talk(spell)
  BTCHealing.lastHealTime = g_clock.millis()
  return true
end

-- Executa cura com potion
function BTCHealing.useHealthPotion(itemId)
  if not g_game.isOnline() then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  g_game.useInventoryItemWith(itemId, player, 0)
  BTCHealing.lastHealTime = g_clock.millis()
  return true
end

-- Funcao principal de execucao
function BTCHealing.execute()
  if not g_game.isOnline() then return end
  
  -- Verifica se o modulo de healing esta ativo
  if not BTCHealing.config or not BTCHealing.config.enabled then return end
  
  if not BTCHealing.canHeal() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  local health = player:getHealth()
  local maxHealth = player:getMaxHealth()
  local hpPercent = (health / maxHealth) * 100
  
  local slots = {
    BTCHealing.getSlotConfig(1),
    BTCHealing.getSlotConfig(2),
    BTCHealing.getSlotConfig(3)
  }
  
  table.sort(slots, function(a, b)
    return a.hpPercent < b.hpPercent
  end)
  
  for _, slot in ipairs(slots) do
    local op = slot.operator or "<="
    local condMet = (op == ">=") and (hpPercent >= slot.hpPercent) or (hpPercent <= slot.hpPercent)
    if slot.enabled and condMet then
      if slot.type == "spell" and slot.spell ~= "" then
        if BTCHealing.castHealSpell(slot.spell) then
          return
        end
      elseif slot.type == "potion" and slot.itemId > 0 then
        if BTCHealing.useHealthPotion(slot.itemId) then
          return
        end
      end
    end
  end
end

-- Cria a interface de configuracao do Healing
function BTCHealing.createUI(parent)
  parent:destroyChildren()
  
  for i = 1, 3 do
    BTCHealing.createSlotUI(parent, i)
  end
end

-- Fecha popup se existir
function BTCHealing.closePopup()
  if BTCHealing.potionPopup then
    BTCHealing.potionPopup:destroy()
    BTCHealing.potionPopup = nil
  end
end

-- Cria popup de selecao de potion com icones
function BTCHealing.showPotionPopup(itemContainer, slotNum, config, onSelect)
  BTCHealing.closePopup()
  
  local potionCount = #BTCHealing.healthPotions
  local itemSize = 42
  local spacing = 5
  local padding = 8
  local popupWidth = (itemSize * potionCount) + (spacing * (potionCount - 1)) + (padding * 2)
  local popupHeight = itemSize + (padding * 2)
  
  -- Cria popup panel
  local popup = g_ui.createWidget("Panel", rootWidget)
  popup:setId("healingPotionPopup")
  BTCHealing.potionPopup = popup
  
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
  for _, potion in ipairs(BTCHealing.healthPotions) do
    -- Container individual para cada potion (quadrado)
    local potionBox = g_ui.createWidget("Button", popup)
    potionBox:setSize({width = itemSize, height = itemSize})
    potionBox:setText("")
    
    -- Visual diferente se selecionado
    if config.itemId == potion.id then
      potionBox:setBackgroundColor("#004422")
      potionBox:setBorderWidth(2)
      potionBox:setBorderColor("#00FF88")
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
      config.itemId = potion.id
      BTCHealing.setSlotConfig(slotNum, config)
      if onSelect then
        onSelect(potion.id)
      end
      BTCHealing.closePopup()
    end
  end
  
  -- Posiciona o popup perto do itemContainer
  local pos = itemContainer:getPosition()
  popup:setPosition({x = pos.x - 20, y = pos.y + 44})
  
  -- Fecha ao clicar fora
  popup:raise()
  popup:focus()
  
  -- Timer para fechar se clicar fora
  popup.onFocusChange = function(widget, focused)
    if not focused then
      scheduleEvent(function()
        BTCHealing.closePopup()
      end, 100)
    end
  end
end

-- Cria UI de um slot individual
function BTCHealing.createSlotUI(parent, slotNum)
  local config = BTCHealing.getSlotConfig(slotNum)
  
  -- Separador entre slots (exceto primeiro)
  if slotNum > 1 then
    local sep = g_ui.createWidget('HorizontalSeparator', parent)
    sep:setMarginTop(10)
    sep:setMarginBottom(10)
  end
  
  -- Linha 1: Botao ON/OFF + Tipo (Spell/Potion)
  local row1 = g_ui.createWidget('Panel', parent)
  row1:setHeight(22)
  if slotNum == 1 then
    row1:setMarginTop(0)
  else
    row1:setMarginTop(3)
  end
  
  local toggleBtn = g_ui.createWidget('Button', row1)
  toggleBtn:setWidth(35)
  toggleBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  toggleBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  -- Funcao para atualizar visual do botao
  local function updateToggleBtn()
    if config.enabled then
      toggleBtn:setText('ON')
      toggleBtn:setColor('#00ff00')
    else
      toggleBtn:setText('OFF')
      toggleBtn:setColor('#ff4444')
    end
  end
  updateToggleBtn()
  
  toggleBtn.onClick = function()
    config.enabled = not config.enabled
    updateToggleBtn()
    pcall(function()
      BTCHealing.setSlotConfig(slotNum, config)
    end)
  end
  
  local typeCombo = g_ui.createWidget('ComboBox', row1)
  typeCombo:setWidth(80)
  typeCombo:addAnchor(AnchorRight, 'parent', AnchorRight)
  typeCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  typeCombo:addOption('Spell')
  typeCombo:addOption('Potion')
  typeCombo:setCurrentOption(config.type == "spell" and "Spell" or "Potion")
  typeCombo.onOptionChange = function(widget, option)
    config.type = option == "Spell" and "spell" or "potion"
    pcall(function() BTCHealing.setSlotConfig(slotNum, config) end)
    BTCHealing.createUI(parent)
  end
  
  -- Linha 2: Spell (ComboBox) ou Potion (Icone)
  local row2 = g_ui.createWidget('Panel', parent)
  row2:setHeight(36)
  row2:setMarginTop(5)
  
  if config.type == "spell" then
    -- SPELL: usa ComboBox normal
    local selectLabel = g_ui.createWidget('Label', row2)
    selectLabel:setText('Spell:')
    selectLabel:setColor('#aaaaaa')
    selectLabel:setWidth(45)
    selectLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    selectLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    
    local selectCombo = g_ui.createWidget('ComboBox', row2)
    selectCombo:setWidth(180)
    selectCombo:addAnchor(AnchorLeft, 'prev', AnchorRight)
    selectCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    selectCombo:setMarginLeft(5)
    
    local spells = BTCHealing.getAvailableSpells()
    for _, spell in ipairs(spells) do
      selectCombo:addOption(spell.words)
    end
    if config.spell ~= "" then
      pcall(function() selectCombo:setCurrentOption(config.spell) end)
    end
    selectCombo.onOptionChange = function(widget, option)
      config.spell = option
      pcall(function() BTCHealing.setSlotConfig(slotNum, config) end)
    end
  else
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
    if config.itemId and config.itemId > 0 then
      itemPreview:setItemId(config.itemId)
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
        config.itemId = itemId
        BTCHealing.setSlotConfig(slotNum, config)
        itemPreview:setItemId(itemId)
      end)
    end
  end
  
  -- Linha 3: HP%
  local row3 = g_ui.createWidget('Panel', parent)
  row3:setHeight(22)
  row3:setMarginTop(3)
  row3:setMarginBottom(10)
  
  local hpLabel = g_ui.createWidget('Label', row3)
  hpLabel:setText('HP')
  hpLabel:setColor('#aaaaaa')
  hpLabel:setWidth(22)
  hpLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  hpLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local opCombo = g_ui.createWidget('ComboBox', row3)
  opCombo:setWidth(45)
  opCombo:addOption('<=')
  opCombo:addOption('>=')
  opCombo:setCurrentOption(config.operator == ">=" and ">=" or "<=")
  opCombo:addAnchor(AnchorLeft, 'prev', AnchorRight)
  opCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  opCombo:setMarginLeft(3)
  opCombo.onOptionChange = function(widget, option)
    config.operator = option
    BTCHealing.setSlotConfig(slotNum, config)
  end

  local minusBtn = g_ui.createWidget('Button', row3)
  minusBtn:setText('-')
  minusBtn:setWidth(20)
  minusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  minusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  minusBtn:setMarginLeft(5)
  
  local hpValue = g_ui.createWidget('Label', row3)
  hpValue:setText(config.hpPercent .. '%')
  hpValue:setColor('#00ff88')
  hpValue:setTextAlign(AlignCenter)
  hpValue:setWidth(45)
  hpValue:addAnchor(AnchorLeft, 'prev', AnchorRight)
  hpValue:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local plusBtn = g_ui.createWidget('Button', row3)
  plusBtn:setText('+')
  plusBtn:setWidth(20)
  plusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  plusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  minusBtn.onClick = function()
    if config.hpPercent > 5 then
      config.hpPercent = config.hpPercent - 5
      hpValue:setText(config.hpPercent .. '%')
      pcall(function() BTCHealing.setSlotConfig(slotNum, config) end)
    end
  end
  
  plusBtn.onClick = function()
    if config.hpPercent < 100 then
      config.hpPercent = config.hpPercent + 5
      hpValue:setText(config.hpPercent .. '%')
      pcall(function() BTCHealing.setSlotConfig(slotNum, config) end)
    end
  end
  
  -- Separador entre slots
  if slotNum < 3 then
    local sep = g_ui.createWidget('HorizontalSeparator', parent)
    sep:setMarginTop(5)
    sep:setMarginBottom(5)
  end
end

return BTCHealing
