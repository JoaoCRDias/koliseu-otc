-- Auto Explore - Exploração Automática do Mapa
-- Quando ativado, o bot explora automaticamente o mapa ao redor,
-- caminhando em direção a áreas não exploradas (tiles não vistos).

setDefaultTab("Cave")

UI.Separator()
UI.Label("-- [[ Auto Explorar ]] --")

-- Configuração de armazenamento
if not storage.autoExplore then
  storage.autoExplore = {
    radius = 30,
    minStepDist = 5
  }
end

local settings = storage.autoExplore
local exploring = false
local currentTarget = nil
local stuckCounter = 0
local lastPosition = nil
local lastPositionTime = 0
local visitedPositions = {}
local visitedCleanTime = 0

-- Direções adjacentes (8 direções)
local ADJACENT_DIRS = {
  {-1, -1}, {0, -1}, {1, -1},
  {-1,  0},          {1,  0},
  {-1,  1}, {0,  1}, {1,  1}
}

-- Converte posição para string de chave
local function posKey(x, y, z)
  return x .. "," .. y .. "," .. z
end

-- Verifica se um tile adjacente é desconhecido (não visto)
local function countUnseenNeighbors(px, py, pz)
  local count = 0
  for _, dir in ipairs(ADJACENT_DIRS) do
    local nx, ny = px + dir[1], py + dir[2]
    local tile = g_map.getTile({x = nx, y = ny, z = pz})
    if not tile then
      count = count + 1
    end
  end
  return count
end

-- Verifica se a posição já foi visitada recentemente
local function isRecentlyVisited(px, py, pz)
  local key = posKey(px, py, pz)
  local visitTime = visitedPositions[key]
  if visitTime and (now - visitTime) < 30000 then -- 30 segundos
    return true
  end
  return false
end

-- Marca posição como visitada
local function markVisited(px, py, pz)
  local key = posKey(px, py, pz)
  visitedPositions[key] = now
end

-- Limpa posições visitadas antigas
local function cleanVisited()
  if now - visitedCleanTime < 10000 then return end
  visitedCleanTime = now

  local toRemove = {}
  for key, time in pairs(visitedPositions) do
    if (now - time) > 60000 then -- limpa depois de 60 segundos
      table.insert(toRemove, key)
    end
  end
  for _, key in ipairs(toRemove) do
    visitedPositions[key] = nil
  end
end

-- Encontrar o melhor tile de fronteira para explorar
local function findExplorationTarget()
  local playerPos = player:getPosition()
  local pz = playerPos.z
  local radius = settings.radius or 30
  local minDist = settings.minStepDist or 5

  -- Usar findAllPaths para obter todos os tiles alcançáveis
  local params = {
    ignoreCreatures = true,
    ignoreNonPathable = true,
    allowUnseen = false,
    allowOnlyVisibleTiles = true
  }

  local paths = findAllPaths(playerPos, radius, params)
  if not paths then return nil end

  local bestTarget = nil
  local bestScore = -1

  for posStr, pathData in pairs(paths) do
    local coords = posStr:split(",")
    if #coords == 3 then
      local tx = tonumber(coords[1])
      local ty = tonumber(coords[2])
      local tz = tonumber(coords[3])

      if tz == pz then
        local dist = pathData[1] -- custo do caminho
        local unseen = countUnseenNeighbors(tx, ty, tz)

        -- Só considerar tiles que fazem fronteira com áreas não exploradas
        if unseen > 0 and dist >= minDist then
          -- Pontuar: mais vizinhos não vistos = melhor, preferir distância moderada
          local visited = isRecentlyVisited(tx, ty, tz) and 0.2 or 1.0
          local score = (unseen * 10) * visited

          -- Penalizar tiles muito perto ou muito longe
          if dist < minDist then
            score = score * 0.1
          elseif dist > radius * 0.8 then
            score = score * 0.7
          end

          -- Verificar se o tile é walkable
          local tile = g_map.getTile({x = tx, y = ty, z = tz})
          if tile and tile:isWalkable(true) then
            if score > bestScore then
              bestScore = score
              bestTarget = {x = tx, y = ty, z = tz}
            end
          end
        end
      end
    end
  end

  -- Se nenhum tile de fronteira encontrado, tenta andar para o tile mais distante
  -- (pode ter tiles inexplorados além do alcance atual)
  if not bestTarget then
    local farthestDist = 0
    for posStr, pathData in pairs(paths) do
      local coords = posStr:split(",")
      if #coords == 3 then
        local tx = tonumber(coords[1])
        local ty = tonumber(coords[2])
        local tz = tonumber(coords[3])

        if tz == pz and pathData[1] > farthestDist then
          local tile = g_map.getTile({x = tx, y = ty, z = tz})
          if tile and tile:isWalkable(true) and not isRecentlyVisited(tx, ty, tz) then
            farthestDist = pathData[1]
            bestTarget = {x = tx, y = ty, z = tz}
          end
        end
      end
    end
  end

  return bestTarget
end

-- Verificar se estamos presos (posição não muda)
local function checkStuck()
  local playerPos = player:getPosition()
  if lastPosition then
    if playerPos.x == lastPosition.x and playerPos.y == lastPosition.y and playerPos.z == lastPosition.z then
      if (now - lastPositionTime) > 5000 then
        stuckCounter = stuckCounter + 1
        lastPositionTime = now
        return true
      end
    else
      stuckCounter = 0
      lastPositionTime = now
    end
  end
  lastPosition = {x = playerPos.x, y = playerPos.y, z = playerPos.z}
  if lastPositionTime == 0 then
    lastPositionTime = now
  end
  return false
end

-- Andar em direção aleatória quando preso
local function walkRandom()
  local playerPos = player:getPosition()
  local dirs = {
    {x = 0, y = -1}, {x = 1, y = 0}, {x = 0, y = 1}, {x = -1, y = 0},
    {x = 1, y = -1}, {x = 1, y = 1}, {x = -1, y = 1}, {x = -1, y = -1}
  }
  -- Embaralhar direções
  for i = #dirs, 2, -1 do
    local j = math.random(1, i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end

  for _, d in ipairs(dirs) do
    local targetPos = {x = playerPos.x + d.x, y = playerPos.y + d.y, z = playerPos.z}
    local tile = g_map.getTile(targetPos)
    if tile and tile:isWalkable(false) then
      autoWalk({targetPos.x > playerPos.x and 1 or targetPos.x < playerPos.x and 3 or (targetPos.y < playerPos.y and 0 or 2)})
      return true
    end
  end
  return false
end

-- Widget de raio
UI.Label("Raio de Exploração:")
local radiusEdit = UI.TextEdit(tostring(settings.radius or 30), function(widget, text)
  local val = tonumber(text)
  if val and val >= 5 and val <= 100 then
    settings.radius = val
  end
end)

-- Widget de distância mínima
UI.Label("Distância Mínima por Passo:")
local minDistEdit = UI.TextEdit(tostring(settings.minStepDist or 5), function(widget, text)
  local val = tonumber(text)
  if val and val >= 1 and val <= 30 then
    settings.minStepDist = val
  end
end)

UI.Separator()

-- Macro principal do Auto Explore
local autoExploreMacro = macro(500, "Auto Explorar", function()
  -- Não explorar se o TargetBot estiver atacando algo
  if TargetBot and TargetBot.isActive and TargetBot.isActive() then
    if g_game.getAttackingCreature() then
      delay(1000)
      return
    end
  end

  -- Não explorar se CaveBot já estiver com ações configuradas
  if CaveBot and CaveBot.isOn and CaveBot.isOn() then
    local actions = CaveBot.actionList and CaveBot.actionList:getChildCount() or 0
    if actions > 0 then
      delay(2000)
      return
    end
  end

  -- Limpa visitados antigos
  cleanVisited()

  -- Verifica se está preso
  if checkStuck() then
    if stuckCounter >= 3 then
      -- Reset de posições visitadas se muito preso
      visitedPositions = {}
      stuckCounter = 0
      statusMessage("Auto Explore: Resetando posições visitadas...")
    end
    walkRandom()
    delay(1000)
    return
  end

  -- Marcar posição atual como visitada
  local playerPos = player:getPosition()
  markVisited(playerPos.x, playerPos.y, playerPos.z)

  -- Verificar se chegou no destino
  if currentTarget then
    local dx = math.abs(playerPos.x - currentTarget.x)
    local dy = math.abs(playerPos.y - currentTarget.y)
    if dx <= 2 and dy <= 2 and playerPos.z == currentTarget.z then
      currentTarget = nil -- Chegou, buscar novo alvo
    end
  end

  -- Encontrar novo alvo se necessário
  if not currentTarget then
    currentTarget = findExplorationTarget()
    if not currentTarget then
      statusMessage("Auto Explore: Nenhuma área inexplorada encontrada nas proximidades.")
      delay(5000) -- Esperar 5 segundos antes de tentar novamente
      return
    end
  end

  -- Caminhar até o alvo
  local walked = autoWalk(currentTarget, settings.radius or 30, {
    ignoreNonPathable = true,
    ignoreCreatures = true,
    allowUnseen = false,
    allowOnlyVisibleTiles = true
  })

  if not walked then
    -- Não conseguiu caminhar, marcar como visitado e limpar
    if currentTarget then
      markVisited(currentTarget.x, currentTarget.y, currentTarget.z)
    end
    currentTarget = nil
    delay(500)
    return
  end

  delay(300 + player:getStepDuration(false, 0))
end)

-- Callback quando o macro for ligado/desligado
local originalSetOn = autoExploreMacro.setOn
autoExploreMacro.setOn = function(val)
  originalSetOn(val)
  if autoExploreMacro.isOn() then
    exploring = true
    currentTarget = nil
    stuckCounter = 0
    lastPosition = nil
    lastPositionTime = 0
    visitedPositions = {}
    statusMessage("Auto Explore: Iniciando exploração automática!")
  else
    exploring = false
    currentTarget = nil
    statusMessage("Auto Explore: Exploração desativada.")
  end
end

local originalSetOff = autoExploreMacro.setOff
autoExploreMacro.setOff = function(val)
  originalSetOff(val)
  exploring = false
  currentTarget = nil
end

UI.Label("Ative para explorar o mapa\nautomaticamente.")
