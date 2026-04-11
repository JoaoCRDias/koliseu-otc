# HowTo: Implementar o CaveBot do BTCBot no Helper

> **Fonte:** `mods/game_bot/btcbot/cavebot.lua` (1600+ linhas)
> **Destino:** `mods/game_helper/helper.lua` (4080 linhas)
> **Objetivo:** Portar o sistema de waypoints/navegação do BTCBot para o Helper, integrando com o ciclo de eventos `helperCycleEvent`.

---

## Índice

1. [Visão Geral da Arquitetura](#1-visão-geral-da-arquitetura)
2. [Estrutura de Dados a Adicionar](#2-estrutura-de-dados-a-adicionar)
3. [Constantes e Variáveis de Controle](#3-constantes-e-variáveis-de-controle)
4. [Passo 1 — Adicionar config ao helperConfig](#passo-1--adicionar-config-ao-helperconfig)
5. [Passo 2 — Adicionar evento ao eventTable](#passo-2--adicionar-evento-ao-eventtable)
6. [Passo 3 — Funções utilitárias de mapa](#passo-3--funções-utilitárias-de-mapa)
7. [Passo 4 — Gerenciamento de waypoints](#passo-4--gerenciamento-de-waypoints)
8. [Passo 5 — Executores de waypoint (WALK, USE, ROPE, SHOVEL, STAIRS, STAND, LABEL)](#passo-5--executores-de-waypoint)
9. [Passo 6 — Sistema de detecção de stuck](#passo-6--sistema-de-detecção-de-stuck)
10. [Passo 7 — Pausa por monstros (shouldStopForMonsters)](#passo-7--pausa-por-monstros)
11. [Passo 8 — Função principal checkCaveBot](#passo-8--função-principal-checkcavebot)
12. [Passo 9 — Sistema de gravação (Recording)](#passo-9--sistema-de-gravação-recording)
13. [Passo 10 — Sistema de Emplacement](#passo-10--sistema-de-emplacement)
14. [Passo 11 — Integração com init() / terminate()](#passo-11--integração-com-init--terminate)
15. [Passo 12 — Persistência de configuração](#passo-12--persistência-de-configuração)
16. [Passo 13 — UI mínima (sem .otui)](#passo-13--ui-mínima-sem-otui)
17. [Diagrama de fluxo de execução](#diagrama-de-fluxo-de-execução)
18. [Checklist de verificação](#checklist-de-verificação)

---

## 1. Visão Geral da Arquitetura

### Como o CaveBot funciona no BTCBot

```
BTCBot.execute() → BTCCaveBot.execute() → shouldStopForMonsters()
                                        → executeCurrentWaypoint()
                                            → executeWalk / executeUse / executeRope
                                              executeStairs / executeShovel / executeStand
                                              executeLabel
```

- Intervalo: **100ms** (tick do BTCBot)
- Cada `executeXxx()` retorna `true` (concluído), `false` (falhou/pule) ou `"retry"` (aguardando)
- Quando `true`: avança `currentIndex`; quando `false`: também avança (skip); quando `"retry"`: aguarda o próximo tick

### Como vai funcionar no Helper

```
helperCycleEvent() (50ms)
  → checkCaveBot event (interval = 100ms)
      → HelperCaveBot.execute()
          → shouldStopForMonsters()
          → executeCurrentWaypoint()
              → executeWalk / executeUse / executeRope / ...
```

O Helper usa um ciclo de 50ms com acumuladores de intervalo por evento. Bastá registrar `checkCaveBot` na `eventTable` com `interval = 100`.

---

## 2. Estrutura de Dados a Adicionar

### Tipos de Waypoint

```lua
local CaveBotWaypointTypes = {
  WALK   = "walk",    -- Andar até posição (pathfinding)
  USE    = "use",     -- Usar objeto (escada, buraco, lever)
  USEWITH= "usewith", -- Usar item em objeto (não implementado no básico)
  LABEL  = "label",   -- Marcador de posição (não executa nada)
  STAND  = "stand",   -- Ficar parado exatamente na posição
  ROPE   = "rope",    -- Usar rope em rope spot (sobe de andar)
  SHOVEL = "shovel",  -- Usar shovel em buraco (desce de andar)
  STAIRS = "stairs",  -- Pisar na escada para mudar de andar
}
```

### Config padrão do CaveBot

```lua
local defaultCaveBotConfig = {
  enabled          = false,
  walkDelay        = 100,        -- ms entre ações de caminhada
  waypoints        = {},         -- lista de waypoints
  currentIndex     = 1,          -- waypoint sendo executado agora
  loopEnabled      = true,       -- loop ao terminar lista
  minMonstersToStop = 1,         -- 0 = nunca para; N = para se N+ monstros por perto
}
```

### Estrutura de um waypoint

```lua
-- Um waypoint é uma tabela simples:
local waypoint = {
  type  = "walk",   -- um de CaveBotWaypointTypes
  x     = 1000,
  y     = 1000,
  z     = 7,
  extra = "",       -- usado por LABEL (nome) e USEWITH (itemId)
}
```

---

## 3. Constantes e Variáveis de Controle

Adicionar **antes** do `helperConfig` global em `helper.lua`:

```lua
-- === CAVEBOT CONSTANTS ===
local CAVEBOT_ROPE_ID  = 3003
local CAVEBOT_SHOVEL_ID = 3457

-- Estado de execução (não persistido)
local caveBotState = {
  walkCooldown       = 200,   -- ms entre walks
  lastWalkTime       = 0,
  lastPosition       = nil,   -- para detecção de stuck
  samePositionCount  = 0,     -- ticks na mesma posição
  useRetryCount      = 0,     -- tentativas no waypoint USE
  stairsStartZ       = nil,   -- Z inicial para STAIRS
  stairsAttempts     = 0,
  scrollOffset       = 0,     -- scroll da lista de UI
  selectedIndex      = 1,     -- índice selecionado para edição
  lastRecordedPos    = nil,   -- gravação de rota
  lastKnownPos       = nil,   -- última posição conhecida
  recordingEnabled   = false,
  monsterStuckTime   = nil,   -- timer de monstros inalcançáveis
}

-- Emplacement types
local CaveBotEmplacement = {
  CENTER    = "center",
  NORTH     = "north",
  SOUTH     = "south",
  EAST      = "east",
  WEST      = "west",
  NORTHEAST = "northeast",
  NORTHWEST = "northwest",
  SOUTHEAST = "southeast",
  SOUTHWEST = "southwest",
}
local currentEmplacement = CaveBotEmplacement.CENTER

-- Waypoint types
local CaveBotWaypointTypes = {
  WALK    = "walk",
  USE     = "use",
  USEWITH = "usewith",
  LABEL   = "label",
  STAND   = "stand",
  ROPE    = "rope",
  SHOVEL  = "shovel",
  STAIRS  = "stairs",
}
```

---

## Passo 1 — Adicionar config ao helperConfig

Em `helperConfig` (linha ~134 de helper.lua), adicionar o campo `cavebot`:

```lua
helperConfig = {
  -- ... campos existentes (spells, potions, training, haste, etc.) ...

  -- NOVO: CaveBot
  cavebot = {
    enabled           = false,
    walkDelay         = 100,
    waypoints         = {},
    currentIndex      = 1,
    loopEnabled       = true,
    minMonstersToStop = 1,
  },
}
```

---

## Passo 2 — Adicionar evento ao eventTable

Em `eventTable` (linha ~71), adicionar:

```lua
local eventTable = {
  checkHealthHealing  = { interval = 250,   action = nil },
  checkMana           = { interval = 100,   action = nil },
  routineChecks       = { interval = 1000,  action = nil },
  checkFriendHealing  = { interval = 250,   action = nil },
  checkAutoHaste      = { interval = 500,   action = nil },
  checkMagicShooter   = { interval = 100,   action = nil },
  checkAutoTarget     = { interval = 250,   action = nil },
  checkExerciseEvent  = { interval = 10000, action = nil },

  -- NOVO
  checkCaveBot        = { interval = 100,   action = nil },
}
```

E em `timers` (linha ~60):

```lua
local timers = {
  -- ... existentes ...
  checkCaveBot = 0,  -- NOVO
}
```

---

## Passo 3 — Funções utilitárias de mapa

Adicionar estas funções antes de `checkCaveBot`:

```lua
-- Distância Chebyshev (igual ao BTCBot)
local function caveBotDistance(pos1, pos2)
  if not pos1 or not pos2 then return 999 end
  if pos1.z ~= pos2.z then return 999 end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Verifica se tile é walkável (ignora criaturas)
local function caveBotIsWalkable(pos)
  if not pos then return false end
  local tile = g_map.getTile(pos)
  if not tile then return false end
  return tile:isWalkable(true)  -- true = ignora criaturas
end

-- Posição do player
local function caveBotGetPlayerPos()
  if not g_game.isOnline() then return nil end
  local p = g_game.getLocalPlayer()
  if not p then return nil end
  return p:getPosition()
end

-- Verifica cooldown de caminhada
local function caveBotCanWalk()
  return (g_clock.millis() - caveBotState.lastWalkTime) >= caveBotState.walkCooldown
end

-- Calcula nova posição na direção
local function caveBotGetPosInDir(pos, dir)
  local np = {x = pos.x, y = pos.y, z = pos.z}
  if     dir == North     then np.y = np.y - 1
  elseif dir == NorthEast then np.x = np.x + 1; np.y = np.y - 1
  elseif dir == East      then np.x = np.x + 1
  elseif dir == SouthEast then np.x = np.x + 1; np.y = np.y + 1
  elseif dir == South     then np.y = np.y + 1
  elseif dir == SouthWest then np.x = np.x - 1; np.y = np.y + 1
  elseif dir == West      then np.x = np.x - 1
  elseif dir == NorthWest then np.x = np.x - 1; np.y = np.y - 1
  end
  return np
end

-- Direção exata entre dois tiles adjacentes
local function caveBotGetDirectionTo(fromPos, toPos)
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  if     dx ==  0 and dy == -1 then return North
  elseif dx ==  1 and dy == -1 then return NorthEast
  elseif dx ==  1 and dy ==  0 then return East
  elseif dx ==  1 and dy ==  1 then return SouthEast
  elseif dx ==  0 and dy ==  1 then return South
  elseif dx == -1 and dy ==  1 then return SouthWest
  elseif dx == -1 and dy ==  0 then return West
  elseif dx == -1 and dy == -1 then return NorthWest
  end
  return nil
end

-- Encontra item usável no tile (escada, buraco, lever, ground)
local function caveBotFindUsableItem(pos)
  local tile = g_map.getTile(pos)
  if not tile then return nil end
  local topUse = tile:getTopUseThing()
  if topUse then return topUse end
  local topMulti = tile:getTopMultiUseThing()
  if topMulti then return topMulti end
  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      if item:isUsable() or item:isMultiUse() then return item end
    end
  end
  return tile:getGround()
end

-- Walk alternativo quando stuck (testa todas as 8 direções priorizando aproximação)
local function caveBotTryAlternativeWalk(playerPos, destPos)
  local allDirs = {North, NorthEast, East, SouthEast, South, SouthWest, West, NorthWest}
  local candidates = {}
  for _, dir in ipairs(allDirs) do
    local np = caveBotGetPosInDir(playerPos, dir)
    if caveBotIsWalkable(np) then
      local newDist = caveBotDistance(np, destPos)
      local curDist = caveBotDistance(playerPos, destPos)
      table.insert(candidates, {dir = dir, priority = curDist - newDist})
    end
  end
  table.sort(candidates, function(a, b) return a.priority > b.priority end)
  if #candidates > 0 then
    g_game.walk(candidates[1].dir)
    caveBotState.lastWalkTime = g_clock.millis()
    return true
  end
  return false
end

-- Walk direto (passo a passo) para o destino
local function caveBotTryDirectWalk(playerPos, destPos)
  local dx = destPos.x - playerPos.x
  local dy = destPos.y - playerPos.y
  local dirs = {}
  if math.abs(dx) >= math.abs(dy) then
    if dx > 0 then table.insert(dirs, East) elseif dx < 0 then table.insert(dirs, West) end
    if dy > 0 then table.insert(dirs, South) elseif dy < 0 then table.insert(dirs, North) end
  else
    if dy > 0 then table.insert(dirs, South) elseif dy < 0 then table.insert(dirs, North) end
    if dx > 0 then table.insert(dirs, East) elseif dx < 0 then table.insert(dirs, West) end
  end
  for _, dir in ipairs(dirs) do
    local np = caveBotGetPosInDir(playerPos, dir)
    if caveBotIsWalkable(np) then
      g_game.walk(dir)
      caveBotState.lastWalkTime = g_clock.millis()
      return true
    end
  end
  return false
end
```

---

## Passo 4 — Gerenciamento de waypoints

```lua
function caveBotAddWaypoint(wpType, x, y, z, extra)
  local wp = { type = wpType, x = x, y = y, z = z, extra = extra or "" }
  table.insert(helperConfig.cavebot.waypoints, wp)
  saveSettings()
  -- caveBotRefreshUI()  -- adicionar quando tiver UI
  return wp
end

function caveBotRemoveWaypoint(index)
  local wps = helperConfig.cavebot.waypoints
  if index >= 1 and index <= #wps then
    table.remove(wps, index)
    if helperConfig.cavebot.currentIndex > #wps then
      helperConfig.cavebot.currentIndex = math.max(1, #wps)
    end
    if caveBotState.selectedIndex > #wps then
      caveBotState.selectedIndex = math.max(1, #wps)
    end
    saveSettings()
  end
end

function caveBotMoveWaypointUp(index)
  local wps = helperConfig.cavebot.waypoints
  if index > 1 and index <= #wps then
    wps[index], wps[index - 1] = wps[index - 1], wps[index]
    caveBotState.selectedIndex = index - 1
    saveSettings()
  end
end

function caveBotMoveWaypointDown(index)
  local wps = helperConfig.cavebot.waypoints
  if index >= 1 and index < #wps then
    wps[index], wps[index + 1] = wps[index + 1], wps[index]
    caveBotState.selectedIndex = index + 1
    saveSettings()
  end
end

function caveBotClearWaypoints()
  helperConfig.cavebot.waypoints = {}
  helperConfig.cavebot.currentIndex = 1
  saveSettings()
end

-- Adiciona waypoint na posição atual (com emplacement)
function caveBotAddCurrentPosition(wpType, extra)
  local pos = caveBotGetPlayerPos()
  if not pos then return end
  local offset = caveBotGetEmplacementOffset()
  caveBotAddWaypoint(wpType, pos.x + offset.x, pos.y + offset.y, pos.z, extra)
end

-- Ir para label por nome
function caveBotGotoLabel(labelName)
  labelName = labelName:lower()
  for i, wp in ipairs(helperConfig.cavebot.waypoints) do
    if wp.type == CaveBotWaypointTypes.LABEL and wp.extra and wp.extra:lower() == labelName then
      helperConfig.cavebot.currentIndex = i
      return true
    end
  end
  return false
end
```

---

## Passo 5 — Executores de Waypoint

### 5.1 — WALK

```lua
-- Retorna: true=chegou, false=falhou, "retry"=aguardando
local function caveBotExecuteWalk(waypoint)
  local p = g_game.getLocalPlayer()
  if not p then return false end
  local playerPos = p:getPosition()
  if not playerPos then return false end

  local destPos = {x = waypoint.x, y = waypoint.y, z = waypoint.z}
  local distance = caveBotDistance(playerPos, destPos)

  -- Chegou (tolerância 1 tile)
  if distance <= 1 then
    caveBotState.lastPosition = nil
    caveBotState.samePositionCount = 0
    return true
  end

  -- Detecção de stuck REAL
  if caveBotState.lastPosition then
    if playerPos.x == caveBotState.lastPosition.x and
       playerPos.y == caveBotState.lastPosition.y and
       playerPos.z == caveBotState.lastPosition.z then
      caveBotState.samePositionCount = caveBotState.samePositionCount + 1

      if caveBotState.samePositionCount >= 15 then
        -- Cancela autowalk se estiver em andamento
        if p:isAutoWalking() then g_game.stop() end
        caveBotTryAlternativeWalk(playerPos, destPos)

        -- Após 25 ticks stuck → pula waypoint
        if caveBotState.samePositionCount >= 25 then
          caveBotState.samePositionCount = 0
          caveBotState.lastPosition = nil
          return false
        end
        return "retry"
      end
    else
      caveBotState.samePositionCount = 0
    end
  end
  caveBotState.lastPosition = {x = playerPos.x, y = playerPos.y, z = playerPos.z}

  if not caveBotCanWalk() then return "retry" end
  if p:isWalking() then return "retry" end

  -- Autowalk em andamento mas sem mover → cancela
  if p:isAutoWalking() and caveBotState.samePositionCount > 5 then
    g_game.stop()
    caveBotState.lastWalkTime = g_clock.millis()
    return "retry"
  end

  -- Autowalk se movendo → aguarda
  if p:isAutoWalking() then return "retry" end

  -- Pathfinding via g_map.findPath
  local path = g_map.findPath(playerPos, destPos, 50, 0)
  if path and #path > 0 then
    g_game.autoWalk(path, playerPos)
    caveBotState.lastWalkTime = g_clock.millis()
    return "retry"
  end

  -- Fallback: andar passo a passo
  caveBotTryDirectWalk(playerPos, destPos)
  return "retry"
end
```

### 5.2 — USE (escada, buraco, lever)

```lua
local function caveBotExecuteUse(waypoint)
  local p = g_game.getLocalPlayer()
  if not p then return false end
  local playerPos = p:getPosition()
  if not playerPos then return false end

  local usePos = {x = waypoint.x, y = waypoint.y, z = waypoint.z}
  local distance = caveBotDistance(playerPos, usePos)

  -- Se mudou de andar → sucesso
  if playerPos.x == usePos.x and playerPos.y == usePos.y and playerPos.z ~= usePos.z then
    return true
  end

  -- Se está longe → anda primeiro
  if distance > 1 then
    if p:isWalking() or p:isAutoWalking() then return "retry" end
    return caveBotExecuteWalk(waypoint)
  end

  if not caveBotCanWalk() then return "retry" end

  caveBotState.useRetryCount = (caveBotState.useRetryCount or 0) + 1

  local useItem = caveBotFindUsableItem(usePos)
  if useItem then
    g_game.use(useItem)
    caveBotState.lastWalkTime = g_clock.millis()
    caveBotState.walkCooldown = 600
    scheduleEvent(function() caveBotState.walkCooldown = 200 end, 700)
    return "retry"
  end

  -- Fallback: pisar no tile (para escadas que precisam de step)
  if (caveBotState.useRetryCount or 0) >= 3 and distance == 1 then
    local dir = caveBotGetDirectionTo(playerPos, usePos)
    if dir then
      g_game.walk(dir, false)
      caveBotState.lastWalkTime = g_clock.millis()
      caveBotState.walkCooldown = 400
      return "retry"
    end
  end

  return "retry"
end
```

### 5.3 — ROPE

```lua
local function caveBotExecuteRope(waypoint)
  local p = g_game.getLocalPlayer()
  if not p then return false end
  local playerPos = p:getPosition()

  local ropePos = {x = waypoint.x, y = waypoint.y, z = waypoint.z}

  -- Subiu de andar → sucesso
  if playerPos.z < ropePos.z then return true end

  local distance = caveBotDistance(playerPos, ropePos)
  if distance > 1 then
    if p:isWalking() or p:isAutoWalking() then return "retry" end
    return caveBotExecuteWalk(waypoint)
  end

  if not caveBotCanWalk() then return "retry" end

  local targetItem = caveBotFindUsableItem(ropePos)
  if targetItem then
    local rope = g_game.findPlayerItem(CAVEBOT_ROPE_ID, -1)
    if rope then
      g_game.useWith(rope, targetItem)
    else
      g_game.useInventoryItemWith(CAVEBOT_ROPE_ID, targetItem, 0)
    end
    caveBotState.lastWalkTime = g_clock.millis()
    caveBotState.walkCooldown = 600
    scheduleEvent(function() caveBotState.walkCooldown = 200 end, 700)
    return "retry"
  end

  return false
end
```

### 5.4 — SHOVEL

```lua
local function caveBotExecuteShovel(waypoint)
  local p = g_game.getLocalPlayer()
  if not p then return false end
  local playerPos = p:getPosition()

  local shovelPos = {x = waypoint.x, y = waypoint.y, z = waypoint.z}

  -- Desceu de andar → sucesso
  if playerPos.z > shovelPos.z then return true end

  local distance = caveBotDistance(playerPos, shovelPos)
  if distance > 1 then
    if p:isWalking() or p:isAutoWalking() then return "retry" end
    return caveBotExecuteWalk(waypoint)
  end

  if not caveBotCanWalk() then return "retry" end

  local targetItem = caveBotFindUsableItem(shovelPos)
  if targetItem then
    local shovel = g_game.findPlayerItem(CAVEBOT_SHOVEL_ID, -1)
    if shovel then
      g_game.useWith(shovel, targetItem)
    else
      g_game.useInventoryItemWith(CAVEBOT_SHOVEL_ID, targetItem, 0)
    end
    caveBotState.lastWalkTime = g_clock.millis()
    caveBotState.walkCooldown = 600
    scheduleEvent(function() caveBotState.walkCooldown = 200 end, 700)
    return "retry"
  end

  return false
end
```

### 5.5 — STAND

```lua
local function caveBotExecuteStand(waypoint)
  local playerPos = caveBotGetPlayerPos()
  if not playerPos then return false end
  local standPos = {x = waypoint.x, y = waypoint.y, z = waypoint.z}
  -- Precisa estar EXATAMENTE na posição
  if playerPos.x == standPos.x and playerPos.y == standPos.y and playerPos.z == standPos.z then
    return true
  end
  return caveBotExecuteWalk(waypoint)
end
```

### 5.6 — LABEL

```lua
local function caveBotExecuteLabel(waypoint)
  return true  -- Marcador: não executa nada, apenas avança
end
```

### 5.7 — STAIRS (pisar na escada para mudar de andar)

```lua
local function caveBotExecuteStairs(waypoint)
  local p = g_game.getLocalPlayer()
  if not p then return false end
  local playerPos = p:getPosition()

  local stairsPos = {x = waypoint.x, y = waypoint.y, z = waypoint.z}
  local distance = caveBotDistance(playerPos, stairsPos)

  -- Inicializa estado de escada
  if not caveBotState.stairsStartZ then
    caveBotState.stairsStartZ = playerPos.z
    caveBotState.stairsAttempts = 0
  end

  -- Mudou de andar → sucesso
  if playerPos.z ~= caveBotState.stairsStartZ then
    caveBotState.stairsStartZ = nil
    caveBotState.stairsAttempts = nil
    return true
  end

  if p:isWalking() or p:isAutoWalking() then return "retry" end
  if not caveBotCanWalk() then return "retry" end

  caveBotState.stairsAttempts = (caveBotState.stairsAttempts or 0) + 1

  -- No tile da escada → tenta andar em direções para ativar
  if distance == 0 then
    local allDirs = {North, East, South, West, NorthEast, NorthWest, SouthEast, SouthWest}
    local dirIndex = ((caveBotState.stairsAttempts - 1) % #allDirs) + 1
    g_game.walk(allDirs[dirIndex], false)
    caveBotState.lastWalkTime = g_clock.millis()
    caveBotState.walkCooldown = 400
    return "retry"
  end

  -- A 1 tile → anda diretamente na escada
  if distance == 1 then
    local dir = caveBotGetDirectionTo(playerPos, stairsPos)
    if dir then
      g_game.walk(dir, false)
      caveBotState.lastWalkTime = g_clock.millis()
      caveBotState.walkCooldown = 400
      return "retry"
    end
  end

  -- Longe → usa autoWalk para se aproximar
  if distance > 1 then
    local dx = math.max(-1, math.min(1, stairsPos.x - playerPos.x))
    local dy = math.max(-1, math.min(1, stairsPos.y - playerPos.y))
    local targetPos = {x = playerPos.x + dx, y = playerPos.y + dy, z = playerPos.z}
    local tile = g_map.getTile(targetPos)
    if tile and tile:isWalkable() then
      local dir = caveBotGetDirectionTo(playerPos, targetPos)
      if dir then
        g_game.walk(dir, false)
        caveBotState.lastWalkTime = g_clock.millis()
        caveBotState.walkCooldown = 300
        return "retry"
      end
    end
    -- Fallback autoWalk
    g_game.autoWalk(stairsPos, {}, 50000)
    caveBotState.lastWalkTime = g_clock.millis()
    return "retry"
  end

  -- Fallback: USE após muitas tentativas
  if caveBotState.stairsAttempts > 5 then
    local useItem = caveBotFindUsableItem(stairsPos)
    if useItem then
      g_game.use(useItem)
      caveBotState.lastWalkTime = g_clock.millis()
      caveBotState.walkCooldown = 600
      return "retry"
    end
  end

  -- Reset após muitas tentativas
  if caveBotState.stairsAttempts > 20 then
    caveBotState.stairsStartZ = nil
    caveBotState.stairsAttempts = nil
  end

  return "retry"
end
```

---

## Passo 6 — Sistema de detecção de stuck

O stuck já está integrado em `caveBotExecuteWalk` acima. Resumo da lógica:

| Contador `samePositionCount` | Ação |
|------------------------------|------|
| 0–14 ticks (0–1.4s) | Normal, aguarda |
| 15+ ticks (1.5s+) | `tryAlternativeWalk` (8 direções priorizadas) |
| 25+ ticks (2.5s+) | `return false` → pula waypoint |

O counter reseta a `0` quando o player se move.

---

## Passo 7 — Pausa por monstros

```lua
local function caveBotCountMonstersNearby()
  local playerPos = caveBotGetPlayerPos()
  if not playerPos then return 0 end
  local specs = g_map.getSpectators(playerPos, false)
  if not specs then return 0 end
  local count = 0
  for _, creature in ipairs(specs) do
    if creature:isMonster() and not creature:isDead() then
      local cp = creature:getPosition()
      if cp and cp.z == playerPos.z then
        local dist = math.max(math.abs(cp.x - playerPos.x), math.abs(cp.y - playerPos.y))
        if dist <= 8 then count = count + 1 end
      end
    end
  end
  return count
end

local function caveBotShouldStopForMonsters()
  local minM = helperConfig.cavebot.minMonstersToStop or 1
  if minM <= 0 then return false end

  local count = caveBotCountMonstersNearby()
  if count < minM then
    caveBotState.monsterStuckTime = nil
    return false
  end

  -- Tem monstros → verifica se está atacando
  if g_game.getAttackingCreature() then
    caveBotState.monsterStuckTime = nil
    return true  -- Para → deixa atacar
  end

  -- Tem monstros mas não está atacando → timer de 3s
  local now = g_clock.millis()
  if not caveBotState.monsterStuckTime then
    caveBotState.monsterStuckTime = now
  end
  if (now - caveBotState.monsterStuckTime) > 3000 then
    return false  -- Monstros inalcançáveis → continua navegando
  end
  return true
end
```

**Por que 3 segundos?** Evita que o CaveBot fique parado indefinidamente quando há monstros visíveis mas que não podem ser atingidos (ex: outro andar, parede de vidro).

---

## Passo 8 — Função principal checkCaveBot

```lua
local function caveBotExecuteCurrentWaypoint()
  local cfg = helperConfig.cavebot
  if not cfg.enabled then return end
  if #cfg.waypoints == 0 then return end

  -- Garante que o índice é válido
  local index = cfg.currentIndex
  if index < 1 or index > #cfg.waypoints then
    cfg.currentIndex = 1
    index = 1
  end

  local waypoint = cfg.waypoints[index]
  if not waypoint then return end

  local p = g_game.getLocalPlayer()
  if not p then return end
  local playerPos = p:getPosition()
  if not playerPos then return end

  -- Waypoints que mudam de andar: se Z já é diferente → considera concluído
  local floorTypes = {
    [CaveBotWaypointTypes.USE]    = true,
    [CaveBotWaypointTypes.ROPE]   = true,
    [CaveBotWaypointTypes.SHOVEL] = true,
    [CaveBotWaypointTypes.STAIRS] = true,
  }
  if floorTypes[waypoint.type] and playerPos.z ~= waypoint.z then
    caveBotState.useRetryCount = 0
    caveBotAdvanceWaypoint(cfg)
    return
  end

  -- Dispatch para executor correto
  local result
  if     waypoint.type == CaveBotWaypointTypes.WALK   then result = caveBotExecuteWalk(waypoint)
  elseif waypoint.type == CaveBotWaypointTypes.USE    then result = caveBotExecuteUse(waypoint)
  elseif waypoint.type == CaveBotWaypointTypes.ROPE   then result = caveBotExecuteRope(waypoint)
  elseif waypoint.type == CaveBotWaypointTypes.SHOVEL then result = caveBotExecuteShovel(waypoint)
  elseif waypoint.type == CaveBotWaypointTypes.STAND  then result = caveBotExecuteStand(waypoint)
  elseif waypoint.type == CaveBotWaypointTypes.LABEL  then result = caveBotExecuteLabel(waypoint)
  elseif waypoint.type == CaveBotWaypointTypes.STAIRS then result = caveBotExecuteStairs(waypoint)
  else result = true  -- tipo desconhecido → pula
  end

  -- Processa resultado
  if result == true then
    -- Concluído: limpa estado e avança
    caveBotState.samePositionCount = 0
    caveBotState.lastPosition = nil
    caveBotState.useRetryCount = 0
    caveBotAdvanceWaypoint(cfg)
  elseif result == false then
    -- Falhou: pula para o próximo
    caveBotState.samePositionCount = 0
    caveBotState.lastPosition = nil
    caveBotState.useRetryCount = 0
    caveBotAdvanceWaypoint(cfg)
  end
  -- "retry": não faz nada, aguarda próximo tick
end

-- Avança currentIndex com suporte a loop
function caveBotAdvanceWaypoint(cfg)
  cfg.currentIndex = cfg.currentIndex + 1
  if cfg.currentIndex > #cfg.waypoints then
    if cfg.loopEnabled then
      cfg.currentIndex = 1
      cfg.enabled = true
    else
      cfg.enabled = false
      cfg.currentIndex = 1
    end
  end
  saveSettings()
end

-- Função registrada no eventTable
function checkCaveBot()
  if not hotkeyHelperStatus then return end
  if not helperConfig.cavebot.enabled then return end
  if caveBotShouldStopForMonsters() then return end
  caveBotExecuteCurrentWaypoint()
end

-- Registro no eventTable (adicionar após a declaração da função)
eventTable.checkCaveBot.action = checkCaveBot
```

---

## Passo 9 — Sistema de gravação (Recording)

O recording captura o movimento do player e gera waypoints automaticamente. No BTCBot ele é chamado via `onCreaturePositionChange`. No Helper, o mesmo efeito pode ser obtido com um callback de `Creature` ou polling na `routineChecks`.

### Opção A — Polling (mais simples, adapta ao Helper)

Adicionar à `checkCaveBot` ou criar um evento separado `checkCaveBotRecording` (interval = 100ms):

```lua
function caveBotCheckRecording()
  if not caveBotState.recordingEnabled then return end
  if not g_game.isOnline() then return end

  local currentPos = caveBotGetPlayerPos()
  if not currentPos then return end

  -- Primeira posição
  if not caveBotState.lastRecordedPos then
    caveBotState.lastRecordedPos = currentPos
    caveBotState.lastKnownPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    caveBotAddWaypoint(CaveBotWaypointTypes.WALK, currentPos.x, currentPos.y, currentPos.z)
    return
  end

  -- Mudou de andar (escada/buraco detectada)
  local lastZ = caveBotState.lastKnownPos and caveBotState.lastKnownPos.z or caveBotState.lastRecordedPos.z
  if currentPos.z ~= lastZ then
    local stairPos = caveBotState.lastKnownPos or caveBotState.lastRecordedPos
    -- Se distou >= 2 tiles do último gravado, adiciona WALK intermediário
    local distFromLastRec = caveBotDistance(stairPos, caveBotState.lastRecordedPos)
    if distFromLastRec >= 2 then
      caveBotAddWaypoint(CaveBotWaypointTypes.WALK, stairPos.x, stairPos.y, stairPos.z)
    end
    -- Adiciona STAIRS (posição exata da escada)
    caveBotAddWaypoint(CaveBotWaypointTypes.STAIRS, stairPos.x, stairPos.y, stairPos.z)
    -- Adiciona posição pós-escada como WALK
    caveBotAddWaypoint(CaveBotWaypointTypes.WALK, currentPos.x, currentPos.y, currentPos.z)
    caveBotState.lastRecordedPos = currentPos
    caveBotState.lastKnownPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}
    return
  end

  -- Atualiza posição conhecida a cada tick
  caveBotState.lastKnownPos = {x = currentPos.x, y = currentPos.y, z = currentPos.z}

  -- Grava WALK a cada 3+ tiles de distância do último ponto gravado
  local distance = caveBotDistance(currentPos, caveBotState.lastRecordedPos)
  if distance >= 3 then
    caveBotAddWaypoint(CaveBotWaypointTypes.WALK, currentPos.x, currentPos.y, currentPos.z)
    caveBotState.lastRecordedPos = currentPos
  end
end

function caveBotToggleRecording()
  caveBotState.recordingEnabled = not caveBotState.recordingEnabled
  if caveBotState.recordingEnabled then
    caveBotState.lastRecordedPos = nil
    caveBotState.lastKnownPos = nil
  end
  return caveBotState.recordingEnabled
end
```

Adicionar ao `eventTable`:

```lua
eventTable.checkCaveBotRecording = { interval = 100, action = caveBotCheckRecording }
-- e em timers:
timers.checkCaveBotRecording = 0
```

---

## Passo 10 — Sistema de Emplacement

O Emplacement permite adicionar um waypoint ligeiramente deslocado da posição atual (ex: "N" = 1 tile ao norte).

```lua
local function caveBotGetEmplacementOffset()
  local offsets = {
    [CaveBotEmplacement.CENTER]    = {x =  0, y =  0},
    [CaveBotEmplacement.NORTH]     = {x =  0, y = -1},
    [CaveBotEmplacement.SOUTH]     = {x =  0, y =  1},
    [CaveBotEmplacement.EAST]      = {x =  1, y =  0},
    [CaveBotEmplacement.WEST]      = {x = -1, y =  0},
    [CaveBotEmplacement.NORTHEAST] = {x =  1, y = -1},
    [CaveBotEmplacement.NORTHWEST] = {x = -1, y = -1},
    [CaveBotEmplacement.SOUTHEAST] = {x =  1, y =  1},
    [CaveBotEmplacement.SOUTHWEST] = {x = -1, y =  1},
  }
  return offsets[currentEmplacement] or {x = 0, y = 0}
end

function caveBotSetEmplacement(emplType)
  currentEmplacement = emplType
  -- Atualizar label de UI aqui quando implementada
end
```

---

## Passo 11 — Integração com init() / terminate()

### Em `init()` (linha ~291):

```lua
function init()
  -- ... código existente ...

  -- CaveBot: inicializa estado
  caveBotState.recordingEnabled = false
  caveBotState.lastPosition = nil
  caveBotState.samePositionCount = 0

  -- ... resto do init ...
end
```

### Em `online()` (linha ~501):

```lua
function online()
  -- ... código existente ...

  -- CaveBot: garante que não está habilitado ao entrar no jogo
  if helperConfig.cavebot then
    helperConfig.cavebot.enabled = false
    helperConfig.cavebot.currentIndex = 1
  end

  -- ... resto do online ...
end
```

### Em `offline()` (linha ~517):

```lua
function offline()
  -- ... código existente ...

  -- CaveBot: desabilita e para tudo
  if helperConfig.cavebot then
    helperConfig.cavebot.enabled = false
  end
  caveBotState.recordingEnabled = false
  caveBotState.lastPosition = nil

  -- ... resto do offline ...
end
```

---

## Passo 12 — Persistência de configuração

O Helper já tem `saveSettings()` e `loadSettings()`. O `helperConfig.cavebot` será salvo automaticamente junto com o resto do helperConfig, desde que a lógica de serialização inclua todos os campos.

**Atenção:** No `loadConfig()` / `online()`, sempre resetar:
```lua
helperConfig.cavebot.enabled = false      -- nunca carrega ligado
helperConfig.cavebot.currentIndex = 1     -- começa do início
```

**Os waypoints SÃO preservados entre sessões** (apenas o estado de execução é resetado).

---

## Passo 13 — UI mínima (sem .otui)

Para uma UI básica funcional criada via código Lua (sem editar arquivos .otui), adicionar uma aba "cavebot" ao helper existente:

```lua
function caveBotCreateMinimalUI(parent)
  -- Botão Enable/Disable CaveBot
  local enableBtn = g_ui.createWidget('CheckBox', parent)
  enableBtn:setId('enableCaveBot')
  enableBtn:setText('Enable CaveBot')
  enableBtn:setChecked(helperConfig.cavebot.enabled)
  enableBtn.onCheckChange = function(widget, checked)
    helperConfig.cavebot.enabled = checked
    if checked then
      helperConfig.cavebot.currentIndex = 1
    end
    saveSettings()
  end

  -- Botão de Recording
  local recBtn = g_ui.createWidget('Button', parent)
  recBtn:setId('caveBotRecordBtn')
  recBtn:setText('Auto Record: OFF')
  recBtn.onClick = function()
    local isRec = caveBotToggleRecording()
    recBtn:setText(isRec and 'Auto Record: ON' or 'Auto Record: OFF')
  end

  -- Botões de adicionar waypoints
  local addWalkBtn = g_ui.createWidget('Button', parent)
  addWalkBtn:setText('Add WALK')
  addWalkBtn.onClick = function()
    caveBotAddCurrentPosition(CaveBotWaypointTypes.WALK)
  end

  local addUseBtn = g_ui.createWidget('Button', parent)
  addUseBtn:setText('Add USE')
  addUseBtn.onClick = function()
    caveBotAddCurrentPosition(CaveBotWaypointTypes.USE)
  end

  local addLabelBtn = g_ui.createWidget('Button', parent)
  addLabelBtn:setText('Add LABEL')
  addLabelBtn.onClick = function()
    -- Pedir nome via input dialog ou texto fixo
    caveBotAddCurrentPosition(CaveBotWaypointTypes.LABEL, "label1")
  end

  local clearBtn = g_ui.createWidget('Button', parent)
  clearBtn:setText('Clear All')
  clearBtn.onClick = function()
    caveBotClearWaypoints()
  end

  -- Loop toggle
  local loopBtn = g_ui.createWidget('CheckBox', parent)
  loopBtn:setText('Loop')
  loopBtn:setChecked(helperConfig.cavebot.loopEnabled)
  loopBtn.onCheckChange = function(widget, checked)
    helperConfig.cavebot.loopEnabled = checked
    saveSettings()
  end
end
```

---

## Diagrama de fluxo de execução

```
helperCycleEvent() → 50ms tick
│
├── [timer checkCaveBot += 50]
│   └── se timer >= 100ms:
│       └── checkCaveBot()
│           │
│           ├── hotkeyHelperStatus? NÃO → return
│           ├── cavebot.enabled?    NÃO → return
│           ├── shouldStopForMonsters()?
│           │   ├── minMonsters=0          → false (nunca para)
│           │   ├── count < minMonsters    → false (poucos monstros)
│           │   ├── atacando alguém        → TRUE (para)
│           │   └── 3s sem atacar          → false (inalcançáveis)
│           │
│           └── executeCurrentWaypoint()
│               │
│               ├── index válido? (1..#waypoints)
│               ├── floorTypes e Z diferente → avançar (já mudou de andar)
│               │
│               └── dispatch por waypoint.type:
│                   ├── WALK   → executeWalk()
│                   │   ├── dist<=1? → TRUE (chegou)
│                   │   ├── stuck 15 ticks → tryAlternativeWalk
│                   │   ├── stuck 25 ticks → FALSE (pula)
│                   │   ├── autoWalk via g_map.findPath
│                   │   └── tryDirectWalk (fallback)
│                   │
│                   ├── USE    → executeUse()
│                   │   ├── Z diferente → TRUE
│                   │   ├── longe → executeWalk (recursivo)
│                   │   └── findUsableItem → g_game.use
│                   │
│                   ├── ROPE   → executeRope()
│                   │   └── useInventoryItemWith(ROPE_ID, item)
│                   │
│                   ├── SHOVEL → executeShovel()
│                   │   └── useInventoryItemWith(SHOVEL_ID, item)
│                   │
│                   ├── STAND  → executeStand() (precisa posição exata)
│                   ├── LABEL  → TRUE imediatamente
│                   └── STAIRS → executeStairs()
│                       ├── Z diferente → TRUE
│                       ├── dist==0 → tenta andar em 8 dirs
│                       ├── dist==1 → walk direto na escada
│                       └── dist>1  → autoWalk para se aproximar

Resultado TRUE  → avançar currentIndex (+ loop/stop)
Resultado FALSE → avançar currentIndex (skip)
Resultado retry → aguarda próximo tick (100ms)
```

---

## Checklist de verificação

Antes de considerar a implementação completa, verificar:

- [ ] `CaveBotWaypointTypes` declarado antes do `helperConfig`
- [ ] `caveBotState` declarado com todos os campos
- [ ] `helperConfig.cavebot` adicionado com estrutura correta
- [ ] `eventTable.checkCaveBot` e `timers.checkCaveBot` adicionados
- [ ] `eventTable.checkCaveBot.action = checkCaveBot` após declaração da função
- [ ] Todas as funções `caveBotExecuteXxx` declaradas antes de `caveBotExecuteCurrentWaypoint`
- [ ] `caveBotAdvanceWaypoint` declarado antes de ser chamado
- [ ] Recording event adicionado ao `eventTable` e `timers`
- [ ] `init()` inicializa estado do cavebot
- [ ] `online()` reseta `enabled` e `currentIndex`
- [ ] `offline()` desabilita o cavebot
- [ ] `saveSettings()` serializa `helperConfig.cavebot.waypoints`
- [ ] `loadSettings()` desserializa e reseta estado de execução
- [ ] ROPE_ID (3003) e SHOVEL_ID (3457) no inventário para testar esses waypoints
- [ ] Testar: WALK entre dois pontos na mesma superfície
- [ ] Testar: STAIRS em uma escada real (andar para cima e para baixo)
- [ ] Testar: ROPE em rope spot
- [ ] Testar: LABEL (deve ser pulado instantaneamente)
- [ ] Testar: Loop (volta ao waypoint 1 ao terminar)
- [ ] Testar: Stop (desliga ao terminar quando loop=false)
- [ ] Testar: Stuck detection (bloquear o caminho por 2.5s → deve pular waypoint)
- [ ] Testar: minMonstersToStop=1 (para quando atacando, retoma quando termina)
- [ ] Testar: Recording (andar e verificar waypoints gravados automaticamente)
