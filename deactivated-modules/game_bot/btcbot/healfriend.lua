--[[
  BTC Bot - Sistema de Healing Friends
  
  Cura automatica de outros jogadores (party members ou lista customizada)
  
  Spells de cura em outros:
  - exura sio "NOME" (Heal Friend - Druid apenas)
  - exura gran mas res (Mass Healing - Druid, cura todos na area)
]]

BTCHealFriend = BTCHealFriend or {}

-- Configuracao padrao
BTCHealFriend.defaultConfig = {
  enabled = false,
  healParty = true,           -- Curar membros da party automaticamente
  healFriendList = {},        -- Lista de nomes para curar (alem da party)
  slot1 = {
    enabled = true,
    spell = "exura sio",
    hpPercent = 70,
    operator = "<=",
    priority = 1
  },
  slot2 = {
    enabled = true,
    spell = "exura sio",
    hpPercent = 40,
    operator = "<=",
    priority = 2
  },
  slot3 = {
    enabled = false,
    spell = "exura gran mas res",
    hpPercent = 60,
    operator = "<=",
    minFriendsInRange = 2
  }
}

-- Spells de cura em outros jogadores
BTCHealFriend.healSpells = {
  -- Druid
  { words = "exura sio", mana = 120, level = 18, voc = {4,14}, needTarget = true, range = 7 },
  { words = "exura gran sio", mana = 210, level = 60, voc = {4,14}, needTarget = true, range = 7 },  -- Salvation (cura forte)
  { words = "exura gran mas res", mana = 150, level = 36, voc = {4,14}, needTarget = false, range = 5, aoe = true },
  -- Monk
  { words = "exura mas nia", mana = 250, level = 150, voc = {5,15}, needTarget = false, range = 5, aoe = true },
}

-- Popup de edicao
BTCHealFriend.friendListPopup = nil

-- Variaveis de controle
BTCHealFriend.config = nil
BTCHealFriend.lastHealTime = 0
BTCHealFriend.healCooldown = 1000  -- 1 segundo entre curas

-- Inicializa o modulo
function BTCHealFriend.init()
  BTCHealFriend.config = BTCHealFriend.loadConfig()
end

-- Carrega configuracao salva ou usa padrao
function BTCHealFriend.loadConfig()
  local saved = BTCConfig.get("healfriend")
  if saved then
    return saved
  end
  return BTCHealFriend.defaultConfig
end

-- Salva configuracao
function BTCHealFriend.saveConfig()
  BTCConfig.set("healfriend", BTCHealFriend.config)
end

-- Obtem configuracao de um slot
function BTCHealFriend.getSlotConfig(slotNum)
  local key = "slot" .. slotNum
  if BTCHealFriend.config and BTCHealFriend.config[key] then
    return BTCHealFriend.config[key]
  end
  return BTCHealFriend.defaultConfig["slot" .. slotNum]
end

-- Atualiza configuracao de um slot
function BTCHealFriend.setSlotConfig(slotNum, config)
  local key = "slot" .. slotNum
  BTCHealFriend.config[key] = config
  BTCHealFriend.saveConfig()
end

-- Retorna vocacao do player (ou 0 se nao conseguir)
function BTCHealFriend.getPlayerVocation()
  if not g_game.isOnline() then return 0 end
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  return player:getVocation() or 0
end

-- Retorna lista de spells filtrada pela vocacao atual
function BTCHealFriend.getAvailableSpells()
  local voc = BTCHealFriend.getPlayerVocation()
  local available = {}
  
  for _, spell in ipairs(BTCHealFriend.healSpells) do
    if voc == 0 then
      table.insert(available, spell)
    else
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

-- Verifica se pode curar (cooldown)
function BTCHealFriend.canHeal()
  local now = g_clock.millis()
  return (now - BTCHealFriend.lastHealTime) >= BTCHealFriend.healCooldown
end

-- Obtem info da spell
function BTCHealFriend.getSpellInfo(spellWords)
  for _, spell in ipairs(BTCHealFriend.healSpells) do
    if spell.words == spellWords then
      return spell
    end
  end
  return nil
end

-- Verifica se e membro da party
function BTCHealFriend.isPartyMember(creature)
  if not creature then return false end
  if creature:isLocalPlayer() then return false end
  if not creature:isPlayer() then return false end
  
  -- Verifica se tem icone de party
  local shield = creature:getShield()
  -- Party shields: 2-9 sao icones de party
  -- 2 = Host, 3 = Host Shared Exp, 4 = Member, 5 = Member Shared Exp, etc
  if shield and shield >= 2 and shield <= 9 then
    return true
  end
  
  return false
end

-- Verifica se esta na lista de amigos
function BTCHealFriend.isInFriendList(creature)
  if not creature then return false end
  if not BTCHealFriend.config.healFriendList then return false end
  
  local name = creature:getName():lower()
  
  for _, friendName in ipairs(BTCHealFriend.config.healFriendList) do
    if friendName:lower() == name then
      return true
    end
  end
  
  return false
end

-- Verifica se deve curar a criatura
function BTCHealFriend.shouldHeal(creature)
  if not creature then return false end
  if creature:isLocalPlayer() then return false end
  if not creature:isPlayer() then return false end
  if creature:isDead() then return false end
  
  -- Verifica se e da party ou da lista de amigos
  local isParty = BTCHealFriend.isPartyMember(creature)
  local isFriend = BTCHealFriend.isInFriendList(creature)
  
  if BTCHealFriend.config.healParty and isParty then
    return true
  end
  
  if isFriend then
    return true
  end
  
  return false
end

-- Calcula distancia entre posicoes
function BTCHealFriend.getDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Encontra amigos que precisam de cura
function BTCHealFriend.findFriendsNeedingHeal(maxHpPercent, maxRange, operator)
  if not g_game.isOnline() then return {} end

  local player = g_game.getLocalPlayer()
  if not player then return {} end

  local playerPos = player:getPosition()
  if not playerPos then return {} end

  local mapPanel = modules.game_interface.getMapPanel()
  if not mapPanel then return {} end

  local spectators = mapPanel:getSpectators()
  if not spectators then return {} end

  local op = operator or "<="
  local friendsNeedHeal = {}

  for _, creature in ipairs(spectators) do
    if BTCHealFriend.shouldHeal(creature) then
      local creaturePos = creature:getPosition()
      if creaturePos and creaturePos.z == playerPos.z then
        local distance = BTCHealFriend.getDistance(playerPos, creaturePos)

        if distance <= maxRange then
          local hp = creature:getHealthPercent()
          if hp then
            local condMet = (op == ">=") and (hp >= maxHpPercent) or (hp <= maxHpPercent)
            if condMet then
              table.insert(friendsNeedHeal, {
                creature = creature,
                hp = hp,
                distance = distance,
                name = creature:getName()
              })
            end
          end
        end
      end
    end
  end
  
  -- Ordena por HP (menor primeiro) e depois por distancia
  table.sort(friendsNeedHeal, function(a, b)
    if a.hp ~= b.hp then
      return a.hp < b.hp
    end
    return a.distance < b.distance
  end)
  
  return friendsNeedHeal
end

-- Usa spell de cura em alvo especifico
function BTCHealFriend.castHealOnTarget(spellWords, targetName)
  if not g_game.isOnline() then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  local spellInfo = BTCHealFriend.getSpellInfo(spellWords)
  if not spellInfo then return false end
  
  -- Verifica mana
  local mana = player:getMana()
  if mana < spellInfo.mana then
    return false
  end
  
  -- Spell com target (exura sio)
  if spellInfo.needTarget then
    g_game.talk(spellWords .. ' "' .. targetName)
  else
    -- Spell AoE (exura gran mas res)
    g_game.talk(spellWords)
  end
  
  BTCHealFriend.lastHealTime = g_clock.millis()
  return true
end

-- Funcao principal de execucao
function BTCHealFriend.execute()
  if not g_game.isOnline() then return end
  
  -- Verifica se o modulo esta ativo
  if not BTCHealFriend.config or not BTCHealFriend.config.enabled then return end
  
  if not BTCHealFriend.canHeal() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  -- Processa slots em ordem de prioridade (slot1 = emergencia, slot3 = AoE)
  
  -- Slot 1 e 2: Heal Friend individual
  for slotNum = 1, 2 do
    local slot = BTCHealFriend.getSlotConfig(slotNum)
    
    if slot.enabled and slot.spell and slot.spell ~= "" then
      local spellInfo = BTCHealFriend.getSpellInfo(slot.spell)
      if spellInfo then
        local friends = BTCHealFriend.findFriendsNeedingHeal(slot.hpPercent, spellInfo.range or 7, slot.operator)
        
        if #friends > 0 then
          -- Cura o amigo com menor HP
          local target = friends[1]
          if BTCHealFriend.castHealOnTarget(slot.spell, target.name) then
            return
          end
        end
      end
    end
  end
  
  -- Slot 3: Mass Healing (AoE)
  local slot3 = BTCHealFriend.getSlotConfig(3)
  
  if slot3.enabled and slot3.spell and slot3.spell ~= "" then
    local spellInfo = BTCHealFriend.getSpellInfo(slot3.spell)
    if spellInfo and spellInfo.aoe then
      local friends = BTCHealFriend.findFriendsNeedingHeal(slot3.hpPercent, spellInfo.range or 5, slot3.operator)
      
      if #friends >= (slot3.minFriendsInRange or 2) then
        if BTCHealFriend.castHealOnTarget(slot3.spell, "") then
          return
        end
      end
    end
  end
end

-- Fecha popup se existir
function BTCHealFriend.closePopup()
  if BTCHealFriend.friendListPopup then
    BTCHealFriend.friendListPopup:destroy()
    BTCHealFriend.friendListPopup = nil
  end
end

-- Mostra popup para adicionar amigo
function BTCHealFriend.showAddFriendPopup(listPanel, updateCallback)
  BTCHealFriend.closePopup()
  
  local popup = g_ui.createWidget("Panel", rootWidget)
  popup:setId("addFriendPopup")
  BTCHealFriend.friendListPopup = popup
  
  popup:setBackgroundColor("#333333")
  popup:setWidth(250)
  popup:setHeight(80)
  popup:setBorderWidth(1)
  popup:setBorderColor("#666666")
  popup:setPaddingLeft(10)
  popup:setPaddingRight(10)
  popup:setPaddingTop(10)
  popup:setPaddingBottom(10)
  
  -- Centraliza na tela
  local screenWidth = g_window.getWidth()
  local screenHeight = g_window.getHeight()
  popup:setPosition({x = (screenWidth - 250) / 2, y = (screenHeight - 80) / 2})
  
  -- Label
  local label = g_ui.createWidget("Label", popup)
  label:setText("Nome do jogador:")
  label:setColor("#ffffff")
  label:setWidth(230)
  label:setHeight(16)
  label:addAnchor(AnchorTop, 'parent', AnchorTop)
  label:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  
  -- TextEdit
  local textEdit = g_ui.createWidget("TextEdit", popup)
  textEdit:setWidth(230)
  textEdit:setHeight(22)
  textEdit:addAnchor(AnchorTop, 'prev', AnchorBottom)
  textEdit:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  textEdit:setMarginTop(5)
  textEdit:focus()
  
  -- Botoes
  local btnPanel = g_ui.createWidget("Panel", popup)
  btnPanel:setWidth(230)
  btnPanel:setHeight(24)
  btnPanel:addAnchor(AnchorTop, 'prev', AnchorBottom)
  btnPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  btnPanel:setMarginTop(8)
  
  local addBtn = g_ui.createWidget("Button", btnPanel)
  addBtn:setText("Adicionar")
  addBtn:setWidth(80)
  addBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  addBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local cancelBtn = g_ui.createWidget("Button", btnPanel)
  cancelBtn:setText("Cancelar")
  cancelBtn:setWidth(80)
  cancelBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
  cancelBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  addBtn.onClick = function()
    local name = textEdit:getText()
    if name and name ~= "" then
      -- Adiciona a lista
      if not BTCHealFriend.config.healFriendList then
        BTCHealFriend.config.healFriendList = {}
      end
      
      -- Verifica se ja existe
      local exists = false
      for _, n in ipairs(BTCHealFriend.config.healFriendList) do
        if n:lower() == name:lower() then
          exists = true
          break
        end
      end
      
      if not exists then
        table.insert(BTCHealFriend.config.healFriendList, name)
        BTCHealFriend.saveConfig()
        if updateCallback then
          updateCallback()
        end
      end
    end
    BTCHealFriend.closePopup()
  end
  
  cancelBtn.onClick = function()
    BTCHealFriend.closePopup()
  end
  
  -- Enter para confirmar
  textEdit.onKeyPress = function(widget, keyCode, keyboardModifiers)
    if keyCode == KeyEnter or keyCode == KeyNumpadEnter then
      addBtn.onClick()
      return true
    end
    return false
  end
  
  popup:raise()
  popup:focus()
end

-- Remove amigo da lista
function BTCHealFriend.removeFriend(name)
  if not BTCHealFriend.config.healFriendList then return end
  
  for i, n in ipairs(BTCHealFriend.config.healFriendList) do
    if n:lower() == name:lower() then
      table.remove(BTCHealFriend.config.healFriendList, i)
      BTCHealFriend.saveConfig()
      return
    end
  end
end

-- Cria a interface de configuracao do Heal Friend
function BTCHealFriend.createUI(parent)
  parent:destroyChildren()
  
  -- Checkbox: Heal Party Members
  local partyCheck = g_ui.createWidget('CheckBox', parent)
  partyCheck:setText(' Curar membros da Party')
  partyCheck:setChecked(BTCHealFriend.config.healParty)
  partyCheck:setMarginTop(5)
  
  partyCheck.onCheckChange = function(widget, checked)
    BTCHealFriend.config.healParty = checked
    BTCHealFriend.saveConfig()
  end
  
  -- Separador
  local sep1 = g_ui.createWidget('HorizontalSeparator', parent)
  sep1:setMarginTop(8)
  sep1:setMarginBottom(8)
  
  -- Lista de amigos
  local listLabel = g_ui.createWidget('Label', parent)
  listLabel:setText('Lista de Amigos:')
  listLabel:setColor('#aaaaaa')
  listLabel:setHeight(16)
  
  -- Container para lista de amigos (menor)
  local listContainer = g_ui.createWidget('Panel', parent)
  listContainer:setId('friendListContainer')
  listContainer:setHeight(60)
  listContainer:setMarginTop(3)
  listContainer:setBackgroundColor('#1a1a1a')
  listContainer:setBorderWidth(1)
  listContainer:setBorderColor('#444444')
  listContainer:setPaddingTop(3)
  listContainer:setPaddingBottom(3)
  listContainer:setPaddingLeft(5)
  listContainer:setPaddingRight(5)
  
  -- Funcao para atualizar lista visual
  local function updateFriendList()
    listContainer:destroyChildren()
    
    local yPos = 0
    for i, name in ipairs(BTCHealFriend.config.healFriendList or {}) do
      local friendRow = g_ui.createWidget('Panel', listContainer)
      friendRow:setHeight(18)
      friendRow:addAnchor(AnchorTop, 'parent', AnchorTop)
      friendRow:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      friendRow:addAnchor(AnchorRight, 'parent', AnchorRight)
      friendRow:setMarginTop(yPos)
      
      local nameLabel = g_ui.createWidget('Label', friendRow)
      nameLabel:setText(name)
      nameLabel:setColor('#00ff88')
      nameLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
      nameLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      
      local removeBtn = g_ui.createWidget('Button', friendRow)
      removeBtn:setText('X')
      removeBtn:setWidth(18)
      removeBtn:setHeight(16)
      removeBtn:setColor('#ff4444')
      removeBtn:addAnchor(AnchorRight, 'parent', AnchorRight)
      removeBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
      
      removeBtn.onClick = function()
        BTCHealFriend.removeFriend(name)
        updateFriendList()
      end
      
      yPos = yPos + 20
    end
  end
  updateFriendList()
  
  -- Botao adicionar amigo
  local addBtn = g_ui.createWidget('Button', parent)
  addBtn:setText('+ Adicionar Amigo')
  addBtn:setHeight(22)
  addBtn:setMarginTop(3)
  
  addBtn.onClick = function()
    BTCHealFriend.showAddFriendPopup(listContainer, updateFriendList)
  end
  
  -- Separador
  local sep2 = g_ui.createWidget('HorizontalSeparator', parent)
  sep2:setMarginTop(8)
  sep2:setMarginBottom(5)
  
  -- Slots de cura (mais compacto)
  local slotsLabel = g_ui.createWidget('Label', parent)
  slotsLabel:setText('Slots de Cura:')
  slotsLabel:setColor('#aaaaaa')
  slotsLabel:setHeight(16)
  
  -- Cria UI para cada slot
  for i = 1, 3 do
    BTCHealFriend.createSlotUI(parent, i)
  end
end

-- Cria UI de um slot individual (compacto)
function BTCHealFriend.createSlotUI(parent, slotNum)
  local config = BTCHealFriend.getSlotConfig(slotNum)
  
  -- Container do slot
  local slotPanel = g_ui.createWidget('Panel', parent)
  slotPanel:setHeight(50)
  slotPanel:setMarginTop(5)
  slotPanel:setBackgroundColor('#222222')
  slotPanel:setPaddingLeft(5)
  slotPanel:setPaddingRight(5)
  slotPanel:setPaddingTop(3)
  
  -- Linha 1: ON/OFF + Label + Spell
  local row1 = g_ui.createWidget('Panel', slotPanel)
  row1:setHeight(22)
  row1:addAnchor(AnchorTop, 'parent', AnchorTop)
  row1:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  row1:addAnchor(AnchorRight, 'parent', AnchorRight)
  
  local toggleBtn = g_ui.createWidget('Button', row1)
  toggleBtn:setWidth(32)
  toggleBtn:setHeight(20)
  toggleBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  toggleBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local function updateToggle()
    if config.enabled then
      toggleBtn:setText('ON')
      toggleBtn:setColor('#00ff00')
    else
      toggleBtn:setText('OFF')
      toggleBtn:setColor('#ff4444')
    end
  end
  updateToggle()
  
  toggleBtn.onClick = function()
    config.enabled = not config.enabled
    updateToggle()
    BTCHealFriend.setSlotConfig(slotNum, config)
  end
  
  -- Label do slot
  local slotLabel = g_ui.createWidget('Label', row1)
  if slotNum <= 2 then
    slotLabel:setText('Slot ' .. slotNum)
  else
    slotLabel:setText('AoE')
  end
  slotLabel:setColor('#888888')
  slotLabel:setWidth(35)
  slotLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  slotLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  slotLabel:setMarginLeft(5)
  
  -- ComboBox de spell
  local spellCombo = g_ui.createWidget('ComboBox', row1)
  spellCombo:setWidth(140)
  spellCombo:addAnchor(AnchorRight, 'parent', AnchorRight)
  spellCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local availableSpells = BTCHealFriend.getAvailableSpells()
  for _, spell in ipairs(availableSpells) do
    spellCombo:addOption(spell.words)
  end
  
  if config.spell and config.spell ~= "" then
    pcall(function() spellCombo:setCurrentOption(config.spell) end)
  end
  
  spellCombo.onOptionChange = function(widget, option)
    config.spell = option
    BTCHealFriend.setSlotConfig(slotNum, config)
  end
  
  -- Linha 2: HP%
  local row2 = g_ui.createWidget('Panel', slotPanel)
  row2:setHeight(20)
  row2:addAnchor(AnchorTop, 'prev', AnchorBottom)
  row2:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  row2:addAnchor(AnchorRight, 'parent', AnchorRight)
  row2:setMarginTop(3)
  
  local hpLabel = g_ui.createWidget('Label', row2)
  hpLabel:setText('HP')
  hpLabel:setColor('#aaaaaa')
  hpLabel:setWidth(22)
  hpLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  hpLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local opCombo = g_ui.createWidget('ComboBox', row2)
  opCombo:setWidth(45)
  opCombo:addOption('<=')
  opCombo:addOption('>=')
  opCombo:setCurrentOption(config.operator == ">=" and ">=" or "<=")
  opCombo:addAnchor(AnchorLeft, 'prev', AnchorRight)
  opCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  opCombo:setMarginLeft(3)
  opCombo.onOptionChange = function(widget, option)
    config.operator = option
    BTCHealFriend.setSlotConfig(slotNum, config)
  end

  local minusBtn = g_ui.createWidget('Button', row2)
  minusBtn:setText('-')
  minusBtn:setWidth(18)
  minusBtn:setHeight(18)
  minusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  minusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local hpValue = g_ui.createWidget('Label', row2)
  hpValue:setText(config.hpPercent .. '%')
  hpValue:setColor('#00ff88')
  hpValue:setTextAlign(AlignCenter)
  hpValue:setWidth(40)
  hpValue:addAnchor(AnchorLeft, 'prev', AnchorRight)
  hpValue:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local plusBtn = g_ui.createWidget('Button', row2)
  plusBtn:setText('+')
  plusBtn:setWidth(18)
  plusBtn:setHeight(18)
  plusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  plusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  minusBtn.onClick = function()
    if config.hpPercent > 5 then
      config.hpPercent = config.hpPercent - 5
      hpValue:setText(config.hpPercent .. '%')
      BTCHealFriend.setSlotConfig(slotNum, config)
    end
  end
  
  plusBtn.onClick = function()
    if config.hpPercent < 100 then
      config.hpPercent = config.hpPercent + 5
      hpValue:setText(config.hpPercent .. '%')
      BTCHealFriend.setSlotConfig(slotNum, config)
    end
  end
  
  -- Slot 3 (AoE): minimo de amigos na mesma linha
  if slotNum == 3 then
    local minLabel = g_ui.createWidget('Label', row2)
    minLabel:setText('Min:')
    minLabel:setColor('#aaaaaa')
    minLabel:setWidth(28)
    minLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
    minLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    minLabel:setMarginLeft(10)
    
    local minusBtn2 = g_ui.createWidget('Button', row2)
    minusBtn2:setText('-')
    minusBtn2:setWidth(18)
    minusBtn2:setHeight(18)
    minusBtn2:addAnchor(AnchorLeft, 'prev', AnchorRight)
    minusBtn2:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    
    local minValue = g_ui.createWidget('Label', row2)
    minValue:setText(tostring(config.minFriendsInRange or 2))
    minValue:setColor('#00ff88')
    minValue:setTextAlign(AlignCenter)
    minValue:setWidth(20)
    minValue:addAnchor(AnchorLeft, 'prev', AnchorRight)
    minValue:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    
    local plusBtn2 = g_ui.createWidget('Button', row2)
    plusBtn2:setText('+')
    plusBtn2:setWidth(18)
    plusBtn2:setHeight(18)
    plusBtn2:addAnchor(AnchorLeft, 'prev', AnchorRight)
    plusBtn2:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    
    minusBtn2.onClick = function()
      if (config.minFriendsInRange or 2) > 1 then
        config.minFriendsInRange = (config.minFriendsInRange or 2) - 1
        minValue:setText(tostring(config.minFriendsInRange))
        BTCHealFriend.setSlotConfig(slotNum, config)
      end
    end
    
    plusBtn2.onClick = function()
      if (config.minFriendsInRange or 2) < 10 then
        config.minFriendsInRange = (config.minFriendsInRange or 2) + 1
        minValue:setText(tostring(config.minFriendsInRange))
        BTCHealFriend.setSlotConfig(slotNum, config)
      end
    end
  end
end

return BTCHealFriend
