--[[
  BTC Bot - Sistema de Targeting
  
  Controla comportamento de movimento em relacao ao alvo:
  - Approach (ir para cima do monstro) - para Knights
  - Stand Still (ficar parado)
]]

BTCTargeting = BTCTargeting or {}

-- Configuracao padrao
BTCTargeting.defaultConfig = {
  enabled = false,
  -- Modo de movimento: "approach", "stand", "kiting"
  moveMode = "stand",
  -- Apenas quando atacando
  onlyWhenAttacking = true,
  -- Diagonal permitido
  allowDiagonal = true,
  -- Distancia para kiting (manter longe dos monstros)
  kitingDistance = 3,
}

-- Variaveis de controle
BTCTargeting.config = nil
BTCTargeting.lastMoveTime = 0
BTCTargeting.moveCooldown = 200  -- ms entre movimentos (mais rapido)

-- Inicializa o modulo
function BTCTargeting.init()
  BTCTargeting.config = BTCTargeting.loadConfig()
end

-- Carrega configuracao salva ou usa padrao
function BTCTargeting.loadConfig()
  local saved = BTCConfig.get("targeting")
  if saved then
    if saved.moveMode == nil then saved.moveMode = "stand" end
    if saved.onlyWhenAttacking == nil then saved.onlyWhenAttacking = true end
    if saved.allowDiagonal == nil then saved.allowDiagonal = true end
    if saved.kitingDistance == nil then saved.kitingDistance = 3 end
    if saved.moveMode == "keepDistance" then saved.moveMode = "stand" end
    return saved
  end
  return table.copy(BTCTargeting.defaultConfig)
end

-- Salva configuracao
function BTCTargeting.saveConfig()
  BTCConfig.set("targeting", BTCTargeting.config)
end

-- Calcula distancia entre duas posicoes
function BTCTargeting.getDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  local dx = math.abs(pos1.x - pos2.x)
  local dy = math.abs(pos1.y - pos2.y)
  return math.max(dx, dy)
end

-- Verifica se pode mover
function BTCTargeting.canMove()
  local now = g_clock.millis()
  return (now - BTCTargeting.lastMoveTime) >= BTCTargeting.moveCooldown
end

-- Encontra posicao para ir para cima do monstro (com alternativas)
function BTCTargeting.findApproachPosition(playerPos, targetPos)
  if not playerPos or not targetPos then return nil end
  
  local currentDist = BTCTargeting.getDistance(playerPos, targetPos)
  
  -- Ja esta adjacente
  if currentDist <= 1 then return nil end
  
  -- Calcula direcao principal
  local dx = targetPos.x - playerPos.x
  local dy = targetPos.y - playerPos.y
  
  local moveX = 0
  local moveY = 0
  
  if dx > 0 then moveX = 1
  elseif dx < 0 then moveX = -1 end
  
  if dy > 0 then moveY = 1
  elseif dy < 0 then moveY = -1 end
  
  -- Lista de posicoes para tentar (em ordem de prioridade)
  local positions = {}
  
  -- 1. Diagonal direta (se ambos moveX e moveY != 0)
  if moveX ~= 0 and moveY ~= 0 then
    table.insert(positions, {x = playerPos.x + moveX, y = playerPos.y + moveY, z = playerPos.z})
  end
  
  -- 2. Horizontal direto
  if moveX ~= 0 then
    table.insert(positions, {x = playerPos.x + moveX, y = playerPos.y, z = playerPos.z})
  end
  
  -- 3. Vertical direto
  if moveY ~= 0 then
    table.insert(positions, {x = playerPos.x, y = playerPos.y + moveY, z = playerPos.z})
  end
  
  -- 4. Diagonais alternativas (para contornar obstaculos)
  if moveX ~= 0 then
    table.insert(positions, {x = playerPos.x + moveX, y = playerPos.y + 1, z = playerPos.z})
    table.insert(positions, {x = playerPos.x + moveX, y = playerPos.y - 1, z = playerPos.z})
  end
  if moveY ~= 0 then
    table.insert(positions, {x = playerPos.x + 1, y = playerPos.y + moveY, z = playerPos.z})
    table.insert(positions, {x = playerPos.x - 1, y = playerPos.y + moveY, z = playerPos.z})
  end
  
  -- Retorna a primeira posicao walkable
  for _, pos in ipairs(positions) do
    if BTCTargeting.isWalkable(pos) then
      return pos
    end
  end
  
  -- Se nenhuma posicao foi walkable, tenta a direcao principal mesmo assim
  -- O jogo vai bloquear se nao for possivel
  if moveX ~= 0 or moveY ~= 0 then
    return {x = playerPos.x + moveX, y = playerPos.y + moveY, z = playerPos.z}
  end
  
  return nil
end

-- Encontra posicao para manter distancia dos monstros (kiting)
function BTCTargeting.findKitingPosition(playerPos)
  local desiredDist = BTCTargeting.config.kitingDistance or 3
  local player = g_game.getLocalPlayer()
  if not player then return nil end

  local specs = g_map.getSpectators(playerPos, false)
  if not specs then return nil end

  -- Coleta monstros proximos no mesmo andar
  local monsters = {}
  for _, c in ipairs(specs) do
    if c:isMonster() and not c:isDead() then
      local cPos = c:getPosition()
      if cPos and cPos.z == playerPos.z then
        local d = BTCTargeting.getDistance(playerPos, cPos)
        if d <= desiredDist + 2 then
          table.insert(monsters, cPos)
        end
      end
    end
  end

  if #monsters == 0 then return nil end

  -- Encontra monstro mais proximo
  local closestDist = 999
  local closestPos = nil
  for _, mPos in ipairs(monsters) do
    local d = BTCTargeting.getDistance(playerPos, mPos)
    if d < closestDist then
      closestDist = d
      closestPos = mPos
    end
  end

  if closestDist >= desiredDist then return nil end

  -- Precisa fugir: calcula direcao oposta ao monstro mais proximo
  local dx = playerPos.x - closestPos.x
  local dy = playerPos.y - closestPos.y

  local moveX = 0
  local moveY = 0
  if dx > 0 then moveX = 1 elseif dx < 0 then moveX = -1 end
  if dy > 0 then moveY = 1 elseif dy < 0 then moveY = -1 end
  if moveX == 0 and moveY == 0 then moveX = 1 end

  local candidates = {}

  -- Diagonal principal (foge em linha reta oposta)
  if moveX ~= 0 and moveY ~= 0 then
    table.insert(candidates, {x = playerPos.x + moveX, y = playerPos.y + moveY, z = playerPos.z})
  end
  -- Cardinais
  if moveX ~= 0 then
    table.insert(candidates, {x = playerPos.x + moveX, y = playerPos.y, z = playerPos.z})
  end
  if moveY ~= 0 then
    table.insert(candidates, {x = playerPos.x, y = playerPos.y + moveY, z = playerPos.z})
  end
  -- Alternativas diagonais
  if moveX ~= 0 then
    table.insert(candidates, {x = playerPos.x + moveX, y = playerPos.y + 1, z = playerPos.z})
    table.insert(candidates, {x = playerPos.x + moveX, y = playerPos.y - 1, z = playerPos.z})
  end
  if moveY ~= 0 then
    table.insert(candidates, {x = playerPos.x + 1, y = playerPos.y + moveY, z = playerPos.z})
    table.insert(candidates, {x = playerPos.x - 1, y = playerPos.y + moveY, z = playerPos.z})
  end

  for _, pos in ipairs(candidates) do
    if BTCTargeting.isWalkable(pos) then
      return pos
    end
  end

  -- Fallback
  if moveX ~= 0 or moveY ~= 0 then
    return {x = playerPos.x + moveX, y = playerPos.y + moveY, z = playerPos.z}
  end

  return nil
end

-- Verifica se tile e walkable
function BTCTargeting.isWalkable(pos)
  if not pos then return false end
  
  local tile = g_map.getTile(pos)
  if not tile then return true end  -- Se nao tem tile carregado, assume que pode andar
  
  -- Verifica se o tile base eh walkable (ignora criaturas)
  return tile:isWalkable(true)
end

-- Move para posicao usando direcao
function BTCTargeting.moveTo(pos)
  if not pos then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  -- Verifica se player esta andando
  if player:isWalking() then return false end
  
  local playerPos = player:getPosition()
  if not playerPos then return false end
  
  -- Calcula direcao
  local dx = pos.x - playerPos.x
  local dy = pos.y - playerPos.y
  
  local dir = nil
  
  if dx == 0 and dy == -1 then dir = North
  elseif dx == 1 and dy == -1 then dir = NorthEast
  elseif dx == 1 and dy == 0 then dir = East
  elseif dx == 1 and dy == 1 then dir = SouthEast
  elseif dx == 0 and dy == 1 then dir = South
  elseif dx == -1 and dy == 1 then dir = SouthWest
  elseif dx == -1 and dy == 0 then dir = West
  elseif dx == -1 and dy == -1 then dir = NorthWest
  end
  
  if dir then
    -- Se nao permite diagonal, converte para cardinal
    if not BTCTargeting.config.allowDiagonal then
      if dir == NorthEast then 
        dir = math.abs(dx) >= math.abs(dy) and East or North
      elseif dir == NorthWest then 
        dir = math.abs(dx) >= math.abs(dy) and West or North
      elseif dir == SouthEast then 
        dir = math.abs(dx) >= math.abs(dy) and East or South
      elseif dir == SouthWest then 
        dir = math.abs(dx) >= math.abs(dy) and West or South
      end
    end
    
    g_game.walk(dir)
    BTCTargeting.lastMoveTime = g_clock.millis()
    return true
  end
  
  return false
end

-- Funcao principal de execucao
function BTCTargeting.execute()
  if not g_game.isOnline() then return end
  -- Targeting funciona quando Attack esta ON (nao precisa de enabled proprio)
  if not BTCTargeting.config then return end
  if BTCTargeting.config.moveMode == "stand" then return end
  -- Verifica se Attack esta ativo
  if not BTCAttack or not BTCAttack.config or not BTCAttack.config.enabled then return end
  if not BTCTargeting.canMove() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  -- Nao move se ja esta andando
  if player:isWalking() then return end
  
  -- IMPORTANTE: Se o CaveBot esta ativo e NAO esta parado para monstros,
  -- o Targeting NAO deve interferir no movimento!
  if BTCCaveBot and BTCCaveBot.config and BTCCaveBot.config.enabled then
    if not BTCCaveBot.shouldStopForMonsters() then
      -- CaveBot esta andando, nao interfere
      return
    end
  end
  
  -- Verifica se esta atacando (se configurado)
  local target = g_game.getAttackingCreature()
  if BTCTargeting.config.onlyWhenAttacking and not target then return end
  
  if not target then return end
  if target:isDead() then return end
  
  local playerPos = player:getPosition()
  local targetPos = target:getPosition()
  
  if not playerPos or not targetPos then return end
  if playerPos.z ~= targetPos.z then return end
  
  local newPos = nil

  if BTCTargeting.config.moveMode == "approach" then
    newPos = BTCTargeting.findApproachPosition(playerPos, targetPos)
  elseif BTCTargeting.config.moveMode == "kiting" then
    newPos = BTCTargeting.findKitingPosition(playerPos)
  end

  if newPos then
    BTCTargeting.moveTo(newPos)
  end
end

-- Cria a UI do modulo
function BTCTargeting.createUI(container)
  if not container then return end
  
  container:destroyChildren()
  
  -- Titulo
  local title = g_ui.createWidget("Label", container)
  title:setText("Targeting & Movement")
  title:setTextAlign(AlignCenter)
  title:setFont("verdana-11px-rounded")
  title:setColor("#9B59B6")
  title:setHeight(20)
  title:setMarginBottom(10)
  
  -- === MODO DE MOVIMENTO ===
  local modeLabel = g_ui.createWidget("Label", container)
  modeLabel:setText("Modo de Movimento:")
  modeLabel:setColor("#ffffff")
  modeLabel:setMarginBottom(5)
  
  -- Botoes de modo (horizontais)
  local modeRow = g_ui.createWidget("Panel", container)
  modeRow:setHeight(30)
  modeRow:setMarginBottom(10)
  
  local modeLayout = UIHorizontalLayout.create(modeRow)
  modeLayout:setSpacing(5)
  modeRow:setLayout(modeLayout)
  
  -- Funcao para atualizar visual dos botoes
  local modeButtons = {}
  local function updateModeButtons()
    for mode, btn in pairs(modeButtons) do
      if BTCTargeting.config.moveMode == mode then
        btn:setColor('#00ff00')
      else
        btn:setColor('#888888')
      end
    end
  end
  
  -- Botao STAND (parado)
  local standBtn = g_ui.createWidget("Button", modeRow)
  standBtn:setText("Parado")
  standBtn:setWidth(60)
  standBtn:setHeight(26)
  modeButtons["stand"] = standBtn
  
  standBtn.onClick = function()
    BTCTargeting.config.moveMode = "stand"
    BTCTargeting.saveConfig()
    updateModeButtons()
  end
  
  -- Botao APPROACH (ir para cima - Knight)
  local approachBtn = g_ui.createWidget("Button", modeRow)
  approachBtn:setText("Approach")
  approachBtn:setWidth(70)
  approachBtn:setHeight(26)
  approachBtn:setTooltip("Ir para cima do monstro (Knight)")
  modeButtons["approach"] = approachBtn
  
  approachBtn.onClick = function()
    BTCTargeting.config.moveMode = "approach"
    BTCTargeting.saveConfig()
    updateModeButtons()
  end

  -- Botao KITING (manter distancia)
  local kitingBtn = g_ui.createWidget("Button", modeRow)
  kitingBtn:setText("Kiting")
  kitingBtn:setWidth(55)
  kitingBtn:setHeight(26)
  kitingBtn:setTooltip("Manter distancia dos monstros (Mage/RP)")
  modeButtons["kiting"] = kitingBtn

  kitingBtn.onClick = function()
    BTCTargeting.config.moveMode = "kiting"
    BTCTargeting.saveConfig()
    updateModeButtons()
  end

  updateModeButtons()

  -- === KITING DISTANCE ===
  local kitDistRow = g_ui.createWidget("Panel", container)
  kitDistRow:setHeight(26)
  kitDistRow:setMarginBottom(5)

  local kitDistLabel = g_ui.createWidget("Label", kitDistRow)
  kitDistLabel:setText("Kiting Dist:")
  kitDistLabel:setColor("#aaaaaa")
  kitDistLabel:setWidth(70)
  kitDistLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  kitDistLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local kitMinusBtn = g_ui.createWidget("Button", kitDistRow)
  kitMinusBtn:setText("-")
  kitMinusBtn:setWidth(24)
  kitMinusBtn:setHeight(22)
  kitMinusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitMinusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitMinusBtn:setMarginLeft(5)

  local kitValueLabel = g_ui.createWidget("Label", kitDistRow)
  kitValueLabel:setText(tostring(BTCTargeting.config.kitingDistance or 3))
  kitValueLabel:setColor("#00ff00")
  kitValueLabel:setTextAlign(AlignCenter)
  kitValueLabel:setWidth(24)
  kitValueLabel:setHeight(22)
  kitValueLabel:setBackgroundColor("#333333")
  kitValueLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitValueLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitValueLabel:setMarginLeft(3)

  local kitPlusBtn = g_ui.createWidget("Button", kitDistRow)
  kitPlusBtn:setText("+")
  kitPlusBtn:setWidth(24)
  kitPlusBtn:setHeight(22)
  kitPlusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitPlusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitPlusBtn:setMarginLeft(3)

  local kitInfoLabel = g_ui.createWidget("Label", kitDistRow)
  kitInfoLabel:setText("tiles")
  kitInfoLabel:setColor("#888888")
  kitInfoLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitInfoLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitInfoLabel:setMarginLeft(5)

  kitMinusBtn.onClick = function()
    local v = math.max(1, (BTCTargeting.config.kitingDistance or 3) - 1)
    BTCTargeting.config.kitingDistance = v
    kitValueLabel:setText(tostring(v))
    BTCTargeting.saveConfig()
  end

  kitPlusBtn.onClick = function()
    local v = math.min(7, (BTCTargeting.config.kitingDistance or 3) + 1)
    BTCTargeting.config.kitingDistance = v
    kitValueLabel:setText(tostring(v))
    BTCTargeting.saveConfig()
  end

  -- Separador
  local sep1 = g_ui.createWidget("HorizontalSeparator", container)
  sep1:setMarginTop(5)
  sep1:setMarginBottom(10)

  -- === OPCOES ===
  local optTitle = g_ui.createWidget("Label", container)
  optTitle:setText("Opcoes:")
  optTitle:setColor("#aaaaaa")
  optTitle:setMarginBottom(8)
  
  -- Checkbox: Apenas quando atacando
  local onlyAttackRow = g_ui.createWidget("Panel", container)
  onlyAttackRow:setHeight(26)
  onlyAttackRow:setMarginBottom(5)
  
  local onlyAttackBtn = g_ui.createWidget("Button", onlyAttackRow)
  onlyAttackBtn:setText(BTCTargeting.config.onlyWhenAttacking and "[X]" or "[ ]")
  onlyAttackBtn:setWidth(28)
  onlyAttackBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  onlyAttackBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local onlyAttackLabel = g_ui.createWidget("Label", onlyAttackRow)
  onlyAttackLabel:setText("Apenas quando atacando")
  onlyAttackLabel:setColor("#cccccc")
  onlyAttackLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  onlyAttackLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  onlyAttackLabel:setMarginLeft(5)
  
  onlyAttackBtn.onClick = function()
    BTCTargeting.config.onlyWhenAttacking = not BTCTargeting.config.onlyWhenAttacking
    onlyAttackBtn:setText(BTCTargeting.config.onlyWhenAttacking and "[X]" or "[ ]")
    BTCTargeting.saveConfig()
  end
  
  -- Checkbox: Permitir diagonal
  local diagRow = g_ui.createWidget("Panel", container)
  diagRow:setHeight(26)
  diagRow:setMarginBottom(5)
  
  local diagBtn = g_ui.createWidget("Button", diagRow)
  diagBtn:setText(BTCTargeting.config.allowDiagonal and "[X]" or "[ ]")
  diagBtn:setWidth(28)
  diagBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  diagBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local diagLabel = g_ui.createWidget("Label", diagRow)
  diagLabel:setText("Permitir movimento diagonal")
  diagLabel:setColor("#cccccc")
  diagLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  diagLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  diagLabel:setMarginLeft(5)
  
  diagBtn.onClick = function()
    BTCTargeting.config.allowDiagonal = not BTCTargeting.config.allowDiagonal
    diagBtn:setText(BTCTargeting.config.allowDiagonal and "[X]" or "[ ]")
    BTCTargeting.saveConfig()
  end
  
  -- Info
  local infoLabel = g_ui.createWidget("Label", container)
  infoLabel:setMarginTop(15)
  infoLabel:setText("Parado = Nao move\nApproach = Vai para cima\nKiting = Mantem distancia")
  infoLabel:setColor("#666666")
  infoLabel:setFont("verdana-11px-rounded")
end

-- Retorna status do modulo
function BTCTargeting.getStatus()
  if not BTCTargeting.config then
    return "OFF"
  end
  local modes = {
    stand = "Parado",
    approach = "Approach",
    kiting = "Kiting"
  }
  return modes[BTCTargeting.config.moveMode] or "ON"
end

-- Inicializa
BTCTargeting.init()
