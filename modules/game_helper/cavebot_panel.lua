local cavebot = {}

modules.game_helper = modules.game_helper or {}
modules.game_helper.cavebot = cavebot

local cavebotPanel = nil
-- Helper window reference from init
local helperWindow = nil

local listPanel = nil
local waypointList = nil
local waypoints = {}
local mapTexts = {}
local waypointFlags = {} -- Armazena referências aos widgets de flag no minimap
local walkEvent = nil

local oldUse = nil
local oldUseWith = nil

-- Forward declaration para doClearWaypoints (definida mais abaixo)
local doClearWaypoints

-- ============================================================================
-- WAYPOINT_TYPE - Enum para tipos de waypoint (evita strings hardcoded)
-- ============================================================================
local WAYPOINT_TYPE = {
  NODE = "Node",     -- Waypoint de passagem (usa nodeDistance)
  STAND = "Stand",   -- Waypoint exato (precisa estar no sqm)
  WALK = "Walk",     -- Waypoint de caminhada simples
  USE = "Use",       -- Usar item/objeto no tile
  ROPE = "Rope",     -- Usar rope no tile
  SHOVEL = "Shovel", -- Usar shovel no tile
  ACTION = "Action", -- Executa script ao chegar
}

-- Mapeamento de tipo para iconId (usado no minimap)
local WAYPOINT_ICON = {
  [WAYPOINT_TYPE.WALK] = 11,
  [WAYPOINT_TYPE.NODE] = 11,
  [WAYPOINT_TYPE.STAND] = 12,
  [WAYPOINT_TYPE.USE] = 14,
  [WAYPOINT_TYPE.ROPE] = 15,
  [WAYPOINT_TYPE.SHOVEL] = 16,
  [WAYPOINT_TYPE.ACTION] = 13,
}

-- ============================================================================
-- MACHINE_STATE - Estado centralizado do Cavebot (inspirado no ZeroBot)
-- ============================================================================
local MACHINE_STATE = {
  isRunning = false, -- Bot ligado/desligado
  currentIndex = 1,  -- Índice do waypoint atual

  -- Controle de Pausa
  pausedByMonsters = false,     -- Pausado por limite de monstros (killing box)
  justExitedKillingBox = false, -- True após sair do killing box (para disparar autoloot 1x)

  -- Detecção de Stuck/Freeze
  lastFreeze = 0,     -- Timestamp quando ficou parado
  lastMove = 0,       -- Timestamp do último movimento real
  lastPosition = nil, -- Última posição conhecida
  isStuck = false,    -- Flag de stuck ativo

  -- Configurações de Timeout
  stuckMaxTime = 15,  -- Segundos máximo parado antes de skip
  freezeMaxTime = 30, -- Segundos máximo freeze antes de reset

  -- Contadores de Tentativas (como ZeroBot)
  walkAttempts = {
    pathfind = 0,    -- Tentativas de pathfinding
    autoWalk = 0,    -- Tentativas de autoWalk
    maxPathfind = 3, -- Máximo antes de tentar autoWalk
    maxAutoWalk = 2, -- Máximo antes de skip waypoint
  },

  -- Fallback para keyboard quando autoWalk falha
  autoWalkFailed = false,
  autoWalkFailedAt = 0,  -- os.clock() de quando autoWalk falhou (cooldown de 2s antes de re-tentar)
  autoWalkSentCount = 0, -- Tentativas de autoWalk enviadas sem movimento real

  -- Status para HUD
  lastStatus = "Idle",

  -- Controle de ações que precisam de delay (Use/Rope/Shovel/mudança de floor)
  actionWaitUntil = 0, -- os.clock() até quando deve esperar

  -- Controle de timeout para wait lure
  lureWaitStart = 0,   -- Timestamp quando começou a esperar monstros
  lureWaitMaxTime = 2, -- Segundos máximo esperando monstros (2s)

  -- Espera após disparar autoloot ao sair do killing box (os.clock() até quando esperar)
  autolootWaitUntil = 0,

  -- Autoloot por morte: cooldown para não disparar em excesso (os.clock() da última morte)
  lastAutolootDeathAt = 0,

  -- Script do waypoint Action ainda em execução (wait pendentes); não reentrar
  actionScriptRunning = false,
}

-- ============================================================================
-- MACHINE_TIMERS - Controle de tempos para delay dinâmico
-- ============================================================================
local MACHINE_TIMERS = {
  lastWalk = 0,      -- Timestamp (os.clock) do último passo
  walkInterval = 50, -- Intervalo base do walker (ms)

  -- Delay dinâmico calculado
  currentDelay = 0, -- Delay atual em ms
  baseDelay = 50,   -- Delay base mínimo
  maxDelay = 500,   -- Delay máximo
}

-- ============================================================================
-- MACHINE_UTILS - Utilidades e dados em tempo real
-- ============================================================================
local MACHINE_UTILS = {
  monsterCount = 0,   -- Contagem atual de monstros
  monsters = {},      -- Lista de monstros detectados
  lifePercentage = 0, -- Vida média dos monstros (%)

  -- Cache de ping
  lastPing = 50,      -- Último ping conhecido
  pingUpdateTime = 0, -- Quando atualizou o ping
}

local AUTOLOOT_DEATH_COOLDOWN = 0.45
local AUTOLOOT_DEATH_RANGE = 2

-- Funções auxiliares (definidas após a tabela para poder referenciá-la)
function MACHINE_UTILS.getPing()
  local now = os.time()
  -- Atualiza ping a cada 2 segundos
  if now - MACHINE_UTILS.pingUpdateTime >= 2 then
    MACHINE_UTILS.pingUpdateTime = now
    if g_game and g_game.getPing then
      local ping = g_game.getPing()
      if ping and ping > 0 then
        MACHINE_UTILS.lastPing = ping
      end
    end
  end
  return MACHINE_UTILS.lastPing
end

local DIR_OFFSETS = {
  [North]     = { x = 0, y = -1 },
  [East]      = { x = 1, y = 0 },
  [South]     = { x = 0, y = 1 },
  [West]      = { x = -1, y = 0 },
  [NorthEast] = { x = 1, y = -1 },
  [SouthEast] = { x = 1, y = 1 },
  [SouthWest] = { x = -1, y = 1 },
  [NorthWest] = { x = -1, y = -1 },
}

local function applyDirection(pos, dir)
  local off = DIR_OFFSETS[dir]
  if not off then return pos end
  return { x = pos.x + off.x, y = pos.y + off.y, z = pos.z }
end

local function hasCreatureBlocking(pos)
  local tile = g_map.getTile(pos)
  if not tile then return false end
  local creatures = tile:getCreatures()
  if not creatures then return false end
  for _, c in ipairs(creatures) do
    if c and not c:isLocalPlayer() and not c:isDead() then
      return true
    end
  end
  return false
end

-- Minimap icon constants
local cavebotMap = nil
local editingIndex = nil
local currentTab = 'waypoints'
local sessionList = {}
local defaultConfig = {
  monsterLimit = 2,
  resumeLimit = 0,
  minMonstersToWait = 2,
  avoidTrap = 4,
  useAutolootAfterKill = false,
  walkMethod = 'Map Click',
  walkDelay = 0,
  recordType = WAYPOINT_TYPE.NODE,
  recordDist = 3,
  nodeDistance = 1,
  autoExplorer = false,
}

-- Auto Explorer: raio de busca interno (sem UI); múltiplas passagens para cobrir a hunt inteira
local EXPLORE_PATH_RADII = { 100, 150, 200 }
local EXPLORE_MIN_STEP = 1

-- Estado do Auto Explorer (#waypoints == 0 e autoExplorer)
local EXPLORE_STATE = {
  currentTarget = nil,
  visited = {},
  visitedCleanAt = 0,
  lastPos = nil,
  lastPosAt = 0,
  stuckCount = 0,
  noTargetUntil = 0,
  homePos = nil,
  phase = 'explore',
  emptyFrontierStreak = 0,
  pickCounter = 0,
  forceLongJump = false,
}

local ADJACENT_EXPLORE8 = {
  { -1, -1 }, { 0, -1 }, { 1, -1 },
  { -1, 0 }, { 1, 0 },
  { -1, 1 }, { 0, 1 }, { 1, 1 },
}

local function normalizeFindEveryPathParams(params)
  local p = {}
  for k, v in pairs(params or {}) do
    if v == nil or v == false then
      p[k] = '0'
    elseif v == true then
      p[k] = '1'
    else
      p[k] = tostring(v)
    end
  end
  return p
end

local function explorePosKey(x, y, z)
  return x .. ',' .. y .. ',' .. z
end

local function exploreCountUnseenNeighbors(px, py, pz)
  local c = 0
  for _, d in ipairs(ADJACENT_EXPLORE8) do
    local t = g_map.getTile({ x = px + d[1], y = py + d[2], z = pz })
    if not t then
      c = c + 1
    end
  end
  return c
end

local function exploreIsRecentlyVisited(x, y, z)
  local t = EXPLORE_STATE.visited[explorePosKey(x, y, z)]
  return t and (os.clock() - t) < 18
end

local function exploreMarkVisited(x, y, z)
  EXPLORE_STATE.visited[explorePosKey(x, y, z)] = os.clock()
end

local function exploreCleanVisited()
  local now = os.clock()
  if now - EXPLORE_STATE.visitedCleanAt < 10 then
    return
  end
  EXPLORE_STATE.visitedCleanAt = now
  local rem = {}
  for k, tm in pairs(EXPLORE_STATE.visited) do
    if now - tm > 60 then
      table.insert(rem, k)
    end
  end
  for _, k in ipairs(rem) do
    EXPLORE_STATE.visited[k] = nil
  end
end

local function exploreGatherCandidates(playerPos, radius, minDist)
  local params = normalizeFindEveryPathParams({
    ignoreCreatures = true,
    ignoreNonPathable = true,
    allowUnseen = false,
    allowOnlyVisibleTiles = true,
  })
  local ok, paths = pcall(function()
    return g_map.findEveryPath(playerPos, radius, params)
  end)
  if not ok or not paths or type(paths) ~= 'table' then
    return {}
  end

  local pz = playerPos.z
  local list = {}
  local minD = minDist or EXPLORE_MIN_STEP

  for posStr, pathData in pairs(paths) do
    if type(posStr) == 'string' and type(pathData) == 'table' then
      local coords = posStr:split(',')
      if #coords >= 3 then
        local tx = tonumber(coords[1])
        local ty = tonumber(coords[2])
        local tz = tonumber(coords[3])
        if tx and ty and tz and tz == pz then
          local dist = tonumber(pathData[2]) or tonumber(pathData[1]) or 0
          if dist >= minD then
            local unseen = exploreCountUnseenNeighbors(tx, ty, tz)
            if unseen > 0 then
              local visitedW = exploreIsRecentlyVisited(tx, ty, tz) and 0.35 or 1.0
              local score = unseen * 12 + dist * 0.15
              score = score * visitedW
              if EXPLORE_STATE.forceLongJump and dist < 12 then
                score = score * 0.15
              end
              score = score * (0.88 + math.random() * 0.26)
              local tile = g_map.getTile({ x = tx, y = ty, z = tz })
              if tile and tile:isWalkable(true) then
                table.insert(list, { x = tx, y = ty, z = tz, score = score, dist = dist })
              end
            end
          end
        end
      end
    end
  end

  return list, paths
end

local function explorePickFromCandidates(list)
  if not list or #list == 0 then
    return nil
  end
  table.sort(list, function(a, b)
    return a.score > b.score
  end)
  EXPLORE_STATE.pickCounter = (EXPLORE_STATE.pickCounter or 0) + 1
  if EXPLORE_STATE.pickCounter % 6 == 0 then
    local n = math.min(8, #list)
    return list[math.random(1, n)]
  end
  return list[1]
end

local function exploreFarthestWalkable(playerPos, paths, minDistFromPlayer)
  if not paths then
    return nil
  end
  local pz = playerPos.z
  local best, bestD = nil, 0
  local minD = minDistFromPlayer or 8
  for posStr, pathData in pairs(paths) do
    if type(posStr) == 'string' and type(pathData) == 'table' then
      local coords = posStr:split(',')
      if #coords >= 3 then
        local tx = tonumber(coords[1])
        local ty = tonumber(coords[2])
        local tz = tonumber(coords[3])
        if tx and ty and tz and tz == pz then
          local dist = tonumber(pathData[2]) or tonumber(pathData[1]) or 0
          if dist >= minD and dist > bestD and not exploreIsRecentlyVisited(tx, ty, tz) then
            local tile = g_map.getTile({ x = tx, y = ty, z = tz })
            if tile and tile:isWalkable(true) then
              bestD = dist
              best = { x = tx, y = ty, z = tz }
            end
          end
        end
      end
    end
  end
  return best
end

local function exploreFindTarget(playerPos)
  EXPLORE_STATE.forceLongJump = false
  local byKey = {}
  local lastPaths = nil
  for _, rad in ipairs(EXPLORE_PATH_RADII) do
    local batch, paths = exploreGatherCandidates(playerPos, rad, EXPLORE_MIN_STEP)
    if paths then
      lastPaths = paths
    end
    for _, c in ipairs(batch) do
      local k = explorePosKey(c.x, c.y, c.z)
      if not byKey[k] or byKey[k].score < c.score then
        byKey[k] = c
      end
    end
  end
  local merged = {}
  for _, c in pairs(byKey) do
    table.insert(merged, c)
  end
  local picked = explorePickFromCandidates(merged)
  if picked then
    return { x = picked.x, y = picked.y, z = picked.z }
  end
  if lastPaths then
    local escape = exploreFarthestWalkable(playerPos, lastPaths, 10)
    if escape then
      return escape
    end
    return exploreFarthestWalkable(playerPos, lastPaths, 6)
  end
  return nil
end

local function exploreFindTargetBreakout(playerPos)
  EXPLORE_STATE.forceLongJump = true
  local byKey = {}
  local lastPaths = nil
  for _, rad in ipairs(EXPLORE_PATH_RADII) do
    local batch, paths = exploreGatherCandidates(playerPos, rad, EXPLORE_MIN_STEP)
    if paths then
      lastPaths = paths
    end
    for _, c in ipairs(batch) do
      local k = explorePosKey(c.x, c.y, c.z)
      if not byKey[k] or byKey[k].score < c.score then
        byKey[k] = c
      end
    end
  end
  local merged = {}
  for _, c in pairs(byKey) do
    table.insert(merged, c)
  end
  local picked = explorePickFromCandidates(merged)
  EXPLORE_STATE.forceLongJump = false
  if picked then
    return { x = picked.x, y = picked.y, z = picked.z }
  end
  if lastPaths then
    return exploreFarthestWalkable(playerPos, lastPaths, 14)
  end
  return nil
end

local function exploreWalkRandom(player)
  local playerPos = player:getPosition()
  local dirs = {
    { x = 0, y = -1 }, { x = 1, y = 0 }, { x = 0, y = 1 }, { x = -1, y = 0 },
    { x = 1, y = -1 }, { x = 1, y = 1 }, { x = -1, y = 1 }, { x = -1, y = -1 },
  }
  for i = #dirs, 2, -1 do
    local j = math.random(i)
    dirs[i], dirs[j] = dirs[j], dirs[i]
  end
  for _, d in ipairs(dirs) do
    local tp = { x = playerPos.x + d.x, y = playerPos.y + d.y, z = playerPos.z }
    local tile = g_map.getTile(tp)
    if tile and tile:isWalkable(false) then
      if player.canWalk and not player:canWalk() then
        return false
      end
      local pathFlags = 7
      local ok, path = pcall(function()
        return g_map.findPath(playerPos, tp, 40000, pathFlags)
      end)
      if ok and path and #path > 0 then
        g_game.walk(path[1])
        cavebot.registerWalkStep()
        return true
      end
      if player.autoWalk then
        player:autoWalk(tp)
      else
        g_game.autoWalk(tp)
      end
      return true
    end
  end
  return false
end

-- Reseta percurso do explorer; mantém homePos se ainda estiver com autoExplorer ligado
local function resetExploreRunState()
  EXPLORE_STATE.currentTarget = nil
  EXPLORE_STATE.visited = {}
  EXPLORE_STATE.visitedCleanAt = 0
  EXPLORE_STATE.lastPos = nil
  EXPLORE_STATE.lastPosAt = 0
  EXPLORE_STATE.stuckCount = 0
  EXPLORE_STATE.noTargetUntil = 0
  EXPLORE_STATE.emptyFrontierStreak = 0
  EXPLORE_STATE.pickCounter = 0
  EXPLORE_STATE.forceLongJump = false
  EXPLORE_STATE.phase = 'explore'
end

local function resetExploreStateFull()
  resetExploreRunState()
  EXPLORE_STATE.homePos = nil
end

function cavebot.setAutoExplorerEnabled(checked)
  defaultConfig.autoExplorer = checked and true or false
  if not defaultConfig.autoExplorer then
    EXPLORE_STATE.homePos = nil
    EXPLORE_STATE.phase = 'explore'
    EXPLORE_STATE.currentTarget = nil
    EXPLORE_STATE.emptyFrontierStreak = 0
    return
  end
  local player = g_game.getLocalPlayer()
  if player then
    local pos = player:getPosition()
    if pos then
      EXPLORE_STATE.homePos = { x = pos.x, y = pos.y, z = pos.z }
    end
  end
  EXPLORE_STATE.phase = 'explore'
  EXPLORE_STATE.currentTarget = nil
  EXPLORE_STATE.emptyFrontierStreak = 0
end

local function onCreatureDisappearForAutoloot(creature)
  if not defaultConfig or not defaultConfig.useAutolootAfterKill or not MACHINE_STATE.isRunning then return end
  if not creature or not creature.isMonster or not creature:isMonster() then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  local playerPos = player:getPosition()
  if not playerPos then return end
  local cPos = creature:getPosition()
  if not cPos or cPos.z ~= playerPos.z then return end
  local dist = math.max(math.abs(playerPos.x - cPos.x), math.abs(playerPos.y - cPos.y))
  local deathRange = (g_helperCore and g_helperCore.getCavebotAutolootDeathRange and g_helperCore.getCavebotAutolootDeathRange()) or AUTOLOOT_DEATH_RANGE
  local deathCooldown = (g_helperCore and g_helperCore.getCavebotAutolootDeathCooldown and g_helperCore.getCavebotAutolootDeathCooldown()) or AUTOLOOT_DEATH_COOLDOWN
  if dist > deathRange then return end
  local now = os.clock()
  if MACHINE_STATE.lastAutolootDeathAt > 0 and (now - MACHINE_STATE.lastAutolootDeathAt) < deathCooldown then return end
  MACHINE_STATE.lastAutolootDeathAt = now
  if g_game.sendQuickLoot then
    scheduleEvent(function()
      pcall(function() g_game.sendQuickLoot(2) end)
    end, 200)
    MACHINE_STATE.autolootWaitUntil = os.clock() + 1.0
  end
end

local settingsWindow = nil
local actionScriptEditorWindow = nil
local actionScriptEditingIndex = nil
local recordingEvent = nil
local lastRecordPos = nil
local currentDirection = 'dirC'
local directionOffsets = {
  dirNW = { x = -1, y = -1 },
  dirN  = { x = 0, y = -1 },
  dirNE = { x = 1, y = -1 },
  dirW  = { x = -1, y = 0 },
  dirC  = { x = 0, y = 0 },
  dirE  = { x = 1, y = 0 },
  dirSW = { x = -1, y = 1 },
  dirS  = { x = 0, y = 1 },
  dirSE = { x = 1, y = 1 }
}
local ropes = { 3003, 646, 9594, 9596, 9598 }
local shovels = { 3457, 5710, 9594, 9596, 9598 }

-- UI Widgets
local ui = {}

function cavebot.init(helper)
  -- Grab UI references
  helperWindow = helper
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      cavebotPanel = helperWindow:recursiveGetChildById('cavebotPanel')
      if cavebotPanel then
        -- Map
        cavebotMap = cavebotPanel:recursiveGetChildById('cavebotMap')
        if cavebotMap then
          local player = g_game.getLocalPlayer()
          if player then
            cavebotMap:setCameraPosition(player:getPosition())
            cavebotMap:setCrossPosition(player:getPosition())
          end

          cavebotMap.onMouseRelease = function(widget, mousePos, mouseButton)
            return cavebot.onMapClick(widget, mousePos, mouseButton)
          end
        end

        -- Widgets lookup
        ui.waypointList = cavebotPanel:recursiveGetChildById('waypointList')
        ui.waypointsContent = cavebotPanel:recursiveGetChildById('waypointsContent')
        ui.configContent = cavebotPanel:recursiveGetChildById('configContent')
        ui.stopLimit = cavebotPanel:recursiveGetChildById('stopLimit')
        ui.resumeLimit = cavebotPanel:recursiveGetChildById('resumeLimit')
        ui.editingLabel = cavebotPanel:recursiveGetChildById('editingLabel')
        ui.sessionsList = cavebotPanel:recursiveGetChildById('sessionsList')
        ui.sessionName = cavebotPanel:recursiveGetChildById('sessionName')
        ui.toggleButton = cavebotPanel:recursiveGetChildById('toggleButton')
        ui.recordButton = cavebotPanel:recursiveGetChildById('recordButton')
        ui.deleteSessionButton = cavebotPanel:recursiveGetChildById('deleteSessionButton')
        ui.saveSessionButton = cavebotPanel:recursiveGetChildById('saveSessionButton')

        -- Disable delete and save buttons by default
        if ui.deleteSessionButton then
          ui.deleteSessionButton:setEnabled(false)
        end
        if ui.saveSessionButton then
          ui.saveSessionButton:setEnabled(false)
        end

        -- Enable save button only when sessionName has 2+ characters AND waypoints > 0
        if ui.sessionName then
          ui.sessionName.onTextChange = function(widget, text)
            if ui.saveSessionButton then
              ui.saveSessionButton:setEnabled(text and #text >= 2 and #waypoints > 0)
            end
          end
        end

        -- Initialize UI state
        cavebot.loadSessionList()
        cavebot.refreshList()
        cavebot.selectTab('waypoints')

        if ui.toggleButton then
          cavebot.toggle(false)
        end
      end
    end
  end

  if not cavebot.connected then
    connect(LocalPlayer, {
      onPositionChange = function(creature, newPos, oldPos)
        -- Player se moveu: reseta contadores de tentativas de walk
        -- NOTA: NÃO reseta autoWalkFailed aqui — ele tem cooldown próprio (2s)
        -- para evitar re-tentar autoWalk a cada passo quando o caminho tem fire/fields
        if MACHINE_STATE.isRunning and oldPos and newPos then
          MACHINE_STATE.walkAttempts.pathfind = 0
          MACHINE_STATE.walkAttempts.autoWalk = 0
          MACHINE_STATE.autoWalkSentCount = 0
        end

        if cavebotMap and not cavebotMap:isDragging() then
          cavebotMap:setCameraPosition(newPos)
          cavebotMap:setCrossPosition(newPos)
        end

        if recordingEvent and oldPos and newPos and oldPos.z ~= newPos.z then
          cavebot.addWaypoint(WAYPOINT_TYPE.STAND, oldPos)
          cavebot.addWaypoint(WAYPOINT_TYPE.NODE, newPos)
          lastRecordPos = { x = newPos.x, y = newPos.y, z = newPos.z }
        end
      end,
      onAutoWalkFail = function(player, status)
        -- AutoWalk falhou, marca para usar keyboard com cooldown de 2s
        if MACHINE_STATE.isRunning then
          MACHINE_STATE.autoWalkFailed = true
          MACHINE_STATE.autoWalkFailedAt = os.clock()
        end
      end
    })
    cavebot.connected = true
  end

  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  if not cavebot.creatureAutolootConnected and Creature then
    connect(Creature, { onDisappear = onCreatureDisappearForAutoloot })
    cavebot.creatureAutolootConnected = true
  end

  if g_game.isOnline() then
    onGameStart()
  end

  -- Hooking Game Actions for Auto-Recording
  if not oldUse then
    oldUse = g_game.use
    g_game.use = function(thing)
      if not MACHINE_STATE.isRunning and recordingEvent and thing and thing.isItem and thing:isItem() then
        local pos = thing:getPosition()
        if pos and pos.x < 65535 then
          cavebot.addWaypoint(WAYPOINT_TYPE.USE, pos)
        end
      end
      return oldUse(thing)
    end
  end

  if not oldUseWith then
    oldUseWith = g_game.useWith
    g_game.useWith = function(item, target)
      if not MACHINE_STATE.isRunning and recordingEvent and item and target then
        local pos = nil
        if target.getPosition then
          pos = target:getPosition()
        elseif target.x then
          pos = target
        end

        if pos and pos.x < 65535 then
          local itemId = item:getId()
          local isRope = false
          for _, id in ipairs(ropes) do
            if id == itemId then
              isRope = true
              break
            end
          end

          local isShovel = false
          for _, id in ipairs(shovels) do
            if id == itemId then
              isShovel = true
              break
            end
          end

          if isRope then
            cavebot.addWaypoint(WAYPOINT_TYPE.ROPE, pos)
          elseif isShovel then
            cavebot.addWaypoint(WAYPOINT_TYPE.SHOVEL, pos)
          end
        end
      end
      return oldUseWith(item, target)
    end
  end
end

function cavebot.terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = onGameEnd
  })

  if cavebot.creatureAutolootConnected and Creature then
    disconnect(Creature, { onDisappear = onCreatureDisappearForAutoloot })
    cavebot.creatureAutolootConnected = nil
  end

  cavebot.stopWalking()
  cavebot.closeActionScriptEditor()
  resetExploreStateFull()

  if LocalPlayer then
    -- Remove position change listener (handled by closure above, actually hard to disconnect generically)
    -- But module reload usually handles re-init.
  end

  -- Remove waypoint flag widgets
  for _, flagData in ipairs(waypointFlags) do
    if flagData.globalFlag and not flagData.globalFlag:isDestroyed() then
      flagData.globalFlag:destroy()
    end
    if flagData.cavebotFlag and not flagData.cavebotFlag:isDestroyed() then
      flagData.cavebotFlag:destroy()
    end
  end
  waypointFlags = {}

  -- Clear map texts
  if g_map then
    for _, text in ipairs(mapTexts) do
      g_map.removeThing(text)
    end
  end
  mapTexts = {}

  -- Restore original game functions
  if oldUse then
    g_game.use = oldUse
    oldUse = nil
  end
  if oldUseWith then
    g_game.useWith = oldUseWith
    oldUseWith = nil
  end

  if cavebotPanel then
    cavebotPanel:destroy()
    cavebotPanel = nil
  end
end

function onGameStart()
  local player = g_game.getLocalPlayer()

  if player and cavebotMap then
    local pos = player:getPosition()
    if pos then
      cavebotMap:setCameraPosition(pos)
      cavebotMap:setCrossPosition(pos)
    end
  end
end

function onGameEnd()
  cavebot.stopWalking()
  sessionList = {}
  selectedSession = nil
  if ui.sessionName then ui.sessionName:setText('') end
  if recordingEvent then
    removeEvent(recordingEvent)
    recordingEvent = nil
  end
  if ui.recordButton then
    ui.recordButton:setText(tr('Not Recording'))
    ui.recordButton:setColor('#FFFFFF')
    ui.recordButton:setBackgroundColor('#AA3333')
  end
  cavebot.refreshSessionList()
end

function cavebot.findRope()
  for _, container in pairs(g_game.getContainers()) do
    for i, item in ipairs(container:getItems()) do
      for _, id in ipairs(ropes) do
        if item:getId() == id then return item end
      end
    end
  end
  return nil
end

function cavebot.findShovel()
  for _, container in pairs(g_game.getContainers()) do
    for i, item in ipairs(container:getItems()) do
      for _, id in ipairs(shovels) do
        if item:getId() == id then return item end
      end
    end
  end
  return nil
end

function cavebot.stopRecording()
  if recordingEvent then
    removeEvent(recordingEvent)
    recordingEvent = nil
    local btn = ui.recordButton
    if btn then
      btn:setText(tr('Not Recording'))
      btn:setColor('#FFFFFF')
      btn:setBackgroundColor('#AA3333')
    end
    modules.game_textmessage.displayStatusMessage(tr('Cavebot recording stopped.'))
    cavebot.updateMinimapProgress()
  end
end

function cavebot.isRecording()
  return recordingEvent ~= nil
end

function cavebot.toggleRecording()
  local btn = ui.recordButton
  if recordingEvent then
    cavebot.stopRecording()
  else
    if btn then
      btn:setText(tr('Recording'))
      btn:setColor('#FFFFFF')
      btn:setBackgroundColor('#33AA33')
    end
    modules.game_textmessage.displayStatusMessage(tr('Cavebot recording started.'))
    cavebot.autoRecord()
  end
end

function cavebot.autoRecord()
  local player = g_game.getLocalPlayer()
  if not player then
    recordingEvent = scheduleEvent(cavebot.autoRecord, 1000)
    return
  end

  local pos = player:getPosition()

  local shouldRecord = false
  local floorChanged = false

  if not lastRecordPos then
    shouldRecord = true
  else
    local dist = math.max(math.abs(pos.x - lastRecordPos.x), math.abs(pos.y - lastRecordPos.y))
    if pos.z ~= lastRecordPos.z then
      -- Mudança de andar - sempre grava como Stand
      shouldRecord = true
      floorChanged = true
    elseif dist >= (defaultConfig.recordDist or 3) then
      shouldRecord = true
    end
  end

  -- Check against last waypoint in list to avoid duplicates at same spot
  if shouldRecord and #waypoints > 0 then
    local lastWp = waypoints[#waypoints]
    if lastWp.x == pos.x and lastWp.y == pos.y and lastWp.z == pos.z then
      shouldRecord = false
    end
  end

  if shouldRecord then
    lastRecordPos = { x = pos.x, y = pos.y, z = pos.z }
    -- Mudança de andar sempre usa Stand, caso contrário usa o tipo configurado
    local waypointType = floorChanged and WAYPOINT_TYPE.STAND or (defaultConfig.recordType or WAYPOINT_TYPE.NODE)
    cavebot.addWaypoint(waypointType, pos)
  end

  -- Define recordingEvent antes de atualizar o minimap
  local isFirstRun = (recordingEvent == nil)
  recordingEvent = scheduleEvent(cavebot.autoRecord, 500)

  -- Atualiza minimap na primeira execução
  if isFirstRun then
    cavebot.updateMinimapProgress()
  end
end

function cavebot.toggleButtonPress()
  cavebot.toggle(not MACHINE_STATE.isRunning)
end

function cavebot.selectTab(tab)
  currentTab = tab

  -- Salva posição do scroll antes de mudar de aba
  local scrollPos = 0
  local scrollBar = cavebotPanel and cavebotPanel:recursiveGetChildById('listScrollbar')
  if scrollBar then
    scrollPos = scrollBar:getValue()
  end

  if ui.waypointsContent then ui.waypointsContent:setVisible(tab == 'waypoints') end
  if ui.configContent then ui.configContent:setVisible(tab == 'config') end

  if tab == 'config' then
    cavebot.updateConfigEditor()
  end

  -- Restaura posição do scroll após mudar de aba
  if tab == 'waypoints' and scrollBar then
    scrollBar:setValue(scrollPos)
  end
end

function cavebot.updateDirection(widget)
  if not widget:isChecked() then
    if currentDirection == widget:getId() then
      widget:setChecked(true)
    end
    return
  end

  currentDirection = widget:getId()
  local parent = widget:getParent()
  local children = parent:getChildren()
  for _, child in pairs(children) do
    if child ~= widget and child:isChecked() then
      child:setChecked(false)
    end
  end
end

-- Cria um flag de waypoint customizado com comportamento de seleção e deleção
function cavebot.createWaypointFlag(minimapWidget, pos, iconId, waypointIndex)
  if not minimapWidget then return nil end

  local flag = g_ui.createWidget('MinimapFlag')
  minimapWidget:insertChild(1, flag)
  flag.pos = pos
  flag.description = "Waypoint " .. waypointIndex
  flag.icon = iconId
  flag.waypointIndex = waypointIndex
  flag.isCavebotFlag = true

  if type(tonumber(iconId)) == 'number' then
    flag:setIcon('/images/game/minimap/flag' .. iconId)
  end
  flag:setTooltip("Waypoint " .. waypointIndex)

  -- Handler de clique customizado
  flag.onMouseRelease = function(widget, mousePos, button)
    if button == MouseLeftButton then
      -- Clique esquerdo: seleciona o waypoint
      cavebot.selectWaypoint(widget.waypointIndex)
      return true
    elseif button == MouseRightButton then
      -- Clique direito: menu de contexto
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      menu:addOption(tr('Delete mark'), function()
        -- Deleta o waypoint correspondente
        cavebot.deleteWaypoint(widget.waypointIndex)
      end)
      menu:display(mousePos)
      return true
    end
    return false
  end

  -- Centraliza o flag na posição
  minimapWidget:centerInPosition(flag, pos)

  return flag
end

-- Atualiza o visual do flag selecionado (fundo amarelo semi-transparente) e remove dos outros
function cavebot.updateFlagSelection()
  for i, flagData in ipairs(waypointFlags) do
    if flagData.globalFlag and not flagData.globalFlag:isDestroyed() then
      if i == editingIndex then
        flagData.globalFlag:setBackgroundColor('#FFFF0088') -- Amarelo semi-transparente
      else
        flagData.globalFlag:setBackgroundColor('#00000000') -- Transparente
      end
    end
    if flagData.cavebotFlag and not flagData.cavebotFlag:isDestroyed() then
      if i == editingIndex then
        flagData.cavebotFlag:setBackgroundColor('#FFFF0088') -- Amarelo semi-transparente
      else
        flagData.cavebotFlag:setBackgroundColor('#00000000') -- Transparente
      end
    end
  end
end

function cavebot.addWaypoint(arg1, arg2)
  local player = g_game.getLocalPlayer()
  if not player then return end

  local action = WAYPOINT_TYPE.WALK
  local pos = nil

  if type(arg1) == "string" then
    action = arg1
    pos = arg2
  else
    pos = arg1
  end

  if not pos then
    pos = player:getPosition()
    local offset = directionOffsets[currentDirection]
    if offset then
      pos.x = pos.x + offset.x
      pos.y = pos.y + offset.y
    end
  end

  local iconId = WAYPOINT_ICON[action] or WAYPOINT_ICON[WAYPOINT_TYPE.WALK]

  local waypoint = {
    x = pos.x,
    y = pos.y,
    z = pos.z,
    action = action,
    iconId = iconId,
    monsterLimit = defaultConfig
        .monsterLimit,
    resumeLimit = defaultConfig.resumeLimit
  }
  if action == WAYPOINT_TYPE.ACTION then
    waypoint.actionScript = ""
  end
  table.insert(waypoints, waypoint)

  local waypointIndex = #waypoints
  local flagData = { globalFlag = nil, cavebotFlag = nil }

  -- Add to global minimap com flag customizado
  if modules.game_minimap and modules.game_minimap.minimapWidget then
    flagData.globalFlag = cavebot.createWaypointFlag(
      modules.game_minimap.minimapWidget, pos, iconId, waypointIndex)
  end

  if cavebotMap and not cavebotMap:isDestroyed() then
    flagData.cavebotFlag = cavebot.createWaypointFlag(
      cavebotMap, pos, iconId, waypointIndex)
  end

  table.insert(waypointFlags, flagData)

  -- Add to World Map (StaticText)
  if g_map then
    local text = StaticText.create()
    text:setText(string.format("Waypoint %d", waypointIndex))
    text:setColor("white")
    g_map.addThing(text, pos, -1)
    table.insert(mapTexts, text)
  end

  cavebot.refreshList()
end

-- Função interna que realmente limpa os waypoints
function doClearWaypoints()
  -- Desliga o cavebot se estiver ligado
  if MACHINE_STATE.isRunning then
    cavebot.toggle(false)
  end

  -- Desliga o recorder se estiver ligado
  if cavebot.isRecording() then
    cavebot.stopRecording()
  end

  -- Remove waypoint flag widgets (customizados)
  for _, flagData in ipairs(waypointFlags) do
    if flagData.globalFlag and not flagData.globalFlag:isDestroyed() then
      flagData.globalFlag:destroy()
    end
    if flagData.cavebotFlag and not flagData.cavebotFlag:isDestroyed() then
      flagData.cavebotFlag:destroy()
    end
  end
  waypointFlags = {}

  -- Remove StaticText do mapa
  if mapTexts then
    for _, text in ipairs(mapTexts) do
      g_map.removeThing(text)
    end
    mapTexts = {}
  end

  waypoints = {}
  MACHINE_STATE.currentIndex = 1
  editingIndex = nil
  cavebot.refreshList()
end

function cavebot.clearWaypoints()
  -- Se não há waypoints, não faz nada
  if #waypoints == 0 then
    return
  end

  -- Modal de confirmação usando displayGeneralBox
  local messageBox
  local yesCallback = function()
    doClearWaypoints()
    if messageBox then messageBox:destroy() end
  end
  local noCallback = function()
    if messageBox then messageBox:destroy() end
  end

  messageBox = displayGeneralBox(tr('Clear Waypoints'),
    tr('Are you sure you want to clear all waypoints?'),
    {
      { text = tr('Yes'), callback = yesCallback },
      { text = tr('No'),  callback = noCallback },
      anchor = AnchorHorizontalCenter
    },
    yesCallback, noCallback)
end

function cavebot.selectWaypoint(index)
  editingIndex = index
  -- Usa updateListColors() em vez de refreshList() para preservar scroll
  cavebot.updateListColors()
  -- Atualiza borda amarela no flag do minimap
  cavebot.updateFlagSelection()
  -- Centraliza o minimap na posição do waypoint selecionado
  cavebot.centerMapOnWaypoint(index)
  -- Faz scroll da lista até o waypoint selecionado
  cavebot.scrollToWaypoint(index)
  -- If currently on config tab, update editor
  if currentTab == 'config' then
    cavebot.updateConfigEditor()
  end
end

function cavebot.gotoid(id)
  if not waypoints or #waypoints == 0 then return false end
  local idx = tonumber(id)
  if not idx or idx < 1 then return false end
  if idx > #waypoints then idx = #waypoints end
  MACHINE_STATE.currentIndex = idx
  MACHINE_STATE.lastFreeze = 0
  cavebot.updateListColors()
  cavebot.updateFlagSelection()
  if cavebot.updateMinimapProgress then cavebot.updateMinimapProgress() end
  return true
end

-- Centraliza o minimap do cavebot e o minimap global na posição do waypoint
function cavebot.centerMapOnWaypoint(index)
  if not index or not waypoints[index] then return end

  local wp = waypoints[index]
  local pos = { x = tonumber(wp.x), y = tonumber(wp.y), z = tonumber(wp.z) }

  if cavebotMap and not cavebotMap:isDestroyed() and cavebotMap.setCameraPosition then
    cavebotMap:setCameraPosition(pos)
  end

  -- Centraliza o minimap global
  if modules.game_minimap and modules.game_minimap.minimapWidget then
    modules.game_minimap.minimapWidget:setCameraPosition(pos)
  end
end

-- Faz scroll da lista de waypoints até o waypoint especificado
function cavebot.scrollToWaypoint(index)
  if not index or not ui.waypointList or ui.waypointList:isDestroyed() then return end
  if not cavebotPanel or cavebotPanel:isDestroyed() then return end

  local scrollBar = cavebotPanel:recursiveGetChildById('listScrollbar')
  if not scrollBar or scrollBar:isDestroyed() then return end

  -- Cada item tem altura de 14 + margem de 2 = 16 pixels
  local itemHeight = 16
  local targetScrollPos = (index - 1) * itemHeight

  -- Obtém a altura visível da lista
  local listHeight = ui.waypointList:getHeight()

  -- Centraliza o item na área visível (coloca no meio da lista)
  local centeredPos = targetScrollPos - (listHeight / 2) + (itemHeight / 2)

  -- Clamp entre 0 e o máximo do scrollbar
  local maxAllowed = math.max(0, scrollBar:getMaximum())
  centeredPos = math.max(0, math.min(centeredPos, maxAllowed))

  -- Define a posição do scroll
  scrollBar:setValue(centeredPos)
end

function cavebot.updateConfigEditor()
  if not editingIndex or not waypoints[editingIndex] then
    if ui.editingLabel and not ui.editingLabel:isDestroyed() then
      ui.editingLabel:setText(tr("Default Settings"))
    end
    if ui.stopLimit and not ui.stopLimit:isDestroyed() then
      ui.stopLimit:setEnabled(true)
      ui.stopLimit:setText(tostring(defaultConfig.monsterLimit))
    end
    if ui.resumeLimit and not ui.resumeLimit:isDestroyed() then
      ui.resumeLimit:setEnabled(true)
      ui.resumeLimit:setText(tostring(defaultConfig.resumeLimit))
    end
    return
  end

  local wp = waypoints[editingIndex]
  if ui.editingLabel and not ui.editingLabel:isDestroyed() then
    ui.editingLabel:setText(tr("Editing Waypoint: #") .. editingIndex)
  end
  if ui.stopLimit and not ui.stopLimit:isDestroyed() then
    ui.stopLimit:setEnabled(true)
    ui.stopLimit:setText(tostring(wp.monsterLimit or 0))
  end
  if ui.resumeLimit and not ui.resumeLimit:isDestroyed() then
    ui.resumeLimit:setEnabled(true)
    ui.resumeLimit:setText(tostring(wp.resumeLimit or 0))
  end
end

function cavebot.onSettingChange(key, value)
  local val = tonumber(value) or 0

  -- Global settings (always go to defaultConfig)
  if key == 'walkMethod' then
    defaultConfig[key] = value
    return
  end

  if key == 'walkDelay' or key == 'minMonstersToWait' or key == 'avoidTrap' then
    defaultConfig[key] = val
    return
  end

  -- Per-waypoint settings
  if not editingIndex or not waypoints[editingIndex] then
    defaultConfig[key] = val
    return
  end
  waypoints[editingIndex][key] = val
  cavebot.refreshList() -- Logic update
end

function cavebot.onRecordTypeChange(value)
  defaultConfig.recordType = value or WAYPOINT_TYPE.NODE
end

function cavebot.onRecordDistChange(value)
  local val = tonumber(value) or 3
  if val < 1 then val = 1 end
  if val > 8 then val = 8 end
  defaultConfig.recordDist = val
end

function cavebot.onNodeDistanceChange(value)
  local val = tonumber(value) or 1
  if val < 1 then val = 1 end
  if val > 5 then val = 5 end
  defaultConfig.nodeDistance = val
end

function cavebot.openSettings()
  if settingsWindow and not settingsWindow:isDestroyed() then
    settingsWindow:destroy()
    settingsWindow = nil
  end

  local root = g_ui.getRootWidget()
  if not root then return end

  settingsWindow = g_ui.createWidget('CavebotSettingsWindow', root)
  if not settingsWindow then
    return
  end

  local function settingsGuard()
    return settingsWindow and not settingsWindow:isDestroyed()
  end

  -- Auto Recorder Settings
  local recorderDistance = settingsWindow:recursiveGetChildById('recorderDistance')
  if recorderDistance then
    recorderDistance:setValue(defaultConfig.recordDist or 3)
    recorderDistance.onValueChange = function(widget, value)
      if not settingsGuard() then return end
      cavebot.onRecordDistChange(value)
    end
  end

  local typeStand = settingsWindow:recursiveGetChildById('typeStand')
  local typeNode = settingsWindow:recursiveGetChildById('typeNode')

  if typeStand and typeNode then
    -- Set initial state
    if defaultConfig.recordType == WAYPOINT_TYPE.STAND then
      typeStand:setChecked(true)
      typeNode:setChecked(false)
    else
      typeStand:setChecked(false)
      typeNode:setChecked(true)
    end

    -- Radio button behavior - sempre deve ter um selecionado
    typeStand.onCheckChange = function(widget, checked)
      if not settingsGuard() then return end
      if checked then
        typeNode:setChecked(false)
        cavebot.onRecordTypeChange(WAYPOINT_TYPE.STAND)
      else
        if not typeNode:isChecked() then
          widget:setChecked(true)
        end
      end
    end

    typeNode.onCheckChange = function(widget, checked)
      if not settingsGuard() then return end
      if checked then
        typeStand:setChecked(false)
        cavebot.onRecordTypeChange(WAYPOINT_TYPE.NODE)
      else
        if not typeStand:isChecked() then
          widget:setChecked(true)
        end
      end
    end
  end

  -- Node Settings
  local nodeDistance = settingsWindow:recursiveGetChildById('nodeDistance')
  if nodeDistance then
    nodeDistance:setValue(defaultConfig.nodeDistance or 1)
    nodeDistance.onValueChange = function(widget, value)
      if not settingsGuard() then return end
      cavebot.onNodeDistanceChange(value)
    end
  end

  -- Safety Lure Settings
  local minMonstersToWait = settingsWindow:recursiveGetChildById('minMonstersToWait')
  if minMonstersToWait then
    minMonstersToWait:setValue(defaultConfig.minMonstersToWait or 2)
    minMonstersToWait.onValueChange = function(widget, value)
      if not settingsGuard() then return end
      cavebot.onSettingChange('minMonstersToWait', tostring(value))
    end
  end

  local avoidTrap = settingsWindow:recursiveGetChildById('avoidTrap')
  if avoidTrap then
    avoidTrap:setValue(defaultConfig.avoidTrap or 4)
    avoidTrap.onValueChange = function(widget, value)
      if not settingsGuard() then return end
      cavebot.onSettingChange('avoidTrap', tostring(value))
    end
  end

  local useAutolootAfterKill = settingsWindow:recursiveGetChildById('useAutolootAfterKill')
  if useAutolootAfterKill then
    useAutolootAfterKill:setChecked(defaultConfig.useAutolootAfterKill or false)
    useAutolootAfterKill.onCheckChange = function(widget, checked)
      if not settingsGuard() then return end
      defaultConfig.useAutolootAfterKill = checked
    end
  end

  local autoExplorerEnable = settingsWindow:recursiveGetChildById('autoExplorerEnable')
  if autoExplorerEnable then
    autoExplorerEnable:setChecked(defaultConfig.autoExplorer or false)
    autoExplorerEnable.onCheckChange = function(widget, checked)
      if not settingsGuard() then return end
      cavebot.setAutoExplorerEnabled(checked)
    end
  end

  -- Walking Settings
  local walkMapWalk = settingsWindow:recursiveGetChildById('walkMapWalk')
  local walkArrowKeys = settingsWindow:recursiveGetChildById('walkArrowKeys')

  if walkMapWalk and walkArrowKeys then
    -- Set initial state
    if defaultConfig.walkMethod == 'Keyboard' then
      walkMapWalk:setChecked(false)
      walkArrowKeys:setChecked(true)
    else
      walkMapWalk:setChecked(true)
      walkArrowKeys:setChecked(false)
    end

    walkMapWalk.onCheckChange = function(widget, checked)
      if not settingsGuard() then return end
      if checked then
        walkArrowKeys:setChecked(false)
        cavebot.onSettingChange('walkMethod', 'Map Click')
      else
        if not walkArrowKeys:isChecked() then
          widget:setChecked(true)
        end
      end
    end

    walkArrowKeys.onCheckChange = function(widget, checked)
      if not settingsGuard() then return end
      if checked then
        walkMapWalk:setChecked(false)
        cavebot.onSettingChange('walkMethod', 'Keyboard')
      else
        if not walkMapWalk:isChecked() then
          widget:setChecked(true)
        end
      end
    end
  end

  local walkDelay = settingsWindow:recursiveGetChildById('walkDelay')
  if walkDelay then
    walkDelay:setText(tostring(defaultConfig.walkDelay or 0))
    walkDelay.onTextChange = function(widget, text)
      if not settingsGuard() then return end
      local numericOnly = text:gsub('[^0-9]', '')
      if numericOnly ~= text then
        widget:setText(numericOnly)
        return
      end
      local val = tonumber(numericOnly) or 0
      widget:setText(tostring(val))
      cavebot.onSettingChange('walkDelay', tostring(val))
    end
  end

  local closeButton = settingsWindow:recursiveGetChildById('closeButton')
  if closeButton then
    closeButton.onClick = function()
      if settingsWindow and not settingsWindow:isDestroyed() then
        settingsWindow:destroy()
        settingsWindow = nil
      end
    end
  end

  settingsWindow:show()
  settingsWindow:raise()
  settingsWindow:focus()
end

function cavebot.hideSettingsWindow()
  if settingsWindow and not settingsWindow:isDestroyed() then
    settingsWindow:hide()
  end
end

function cavebot.showSettingsWindow()
  if settingsWindow and not settingsWindow:isDestroyed() then
    settingsWindow:show()
    settingsWindow:raise()
    settingsWindow:focus()
  end
end

function cavebot.closeSettingsWindow()
  if settingsWindow and not settingsWindow:isDestroyed() then
    settingsWindow:destroy()
    settingsWindow = nil
  end
end

function cavebot.applyToAllNode()
  local template = defaultConfig
  if editingIndex and waypoints[editingIndex] then
    template = waypoints[editingIndex]
  end

  local count = 0
  for _, wp in ipairs(waypoints) do
    if wp.action == WAYPOINT_TYPE.NODE then
      wp.monsterLimit = template.monsterLimit
      wp.resumeLimit = template.resumeLimit
      count = count + 1
    end
  end
  modules.game_textmessage.displayStatusMessage(tr('Settings applied to ' .. count .. ' Node waypoints.'))
end

function cavebot.applyToAllStand()
  local template = defaultConfig
  if editingIndex and waypoints[editingIndex] then
    template = waypoints[editingIndex]
  end

  local count = 0
  for _, wp in ipairs(waypoints) do
    if wp.action == WAYPOINT_TYPE.STAND then
      wp.monsterLimit = template.monsterLimit
      wp.resumeLimit = template.resumeLimit
      count = count + 1
    end
  end
  modules.game_textmessage.displayStatusMessage(tr('Settings applied to ' .. count .. ' Stand waypoints.'))
end

function cavebot.applyToAll()
  local template = defaultConfig
  if editingIndex and waypoints[editingIndex] then
    template = waypoints[editingIndex]
  end

  local doApply = function()
    for _, wp in ipairs(waypoints) do
      wp.monsterLimit = template.monsterLimit
      wp.resumeLimit = template.resumeLimit
    end
    modules.game_textmessage.displayStatusMessage(tr('Settings applied to all waypoints.'))
  end

  -- Modal de confirmação
  local messageBox
  local yesCallback = function()
    doApply()
    if messageBox then messageBox:destroy() end
  end
  local noCallback = function()
    if messageBox then messageBox:destroy() end
  end

  messageBox = displayGeneralBox(tr('Apply to All'),
    tr('Are you sure you want to apply settings to all waypoints?'),
    {
      { text = tr('Yes'), callback = yesCallback },
      { text = tr('No'),  callback = noCallback },
      anchor = AnchorHorizontalCenter
    },
    yesCallback, noCallback)
end

function cavebot.removeAllFlags()
  -- Remove todos os widgets de flag customizados
  for _, flagData in ipairs(waypointFlags) do
    if flagData.globalFlag and not flagData.globalFlag:isDestroyed() then
      flagData.globalFlag:destroy()
    end
    if flagData.cavebotFlag and not flagData.cavebotFlag:isDestroyed() then
      flagData.cavebotFlag:destroy()
    end
  end
  waypointFlags = {}

  -- Remove StaticText do mapa
  if mapTexts then
    for _, text in ipairs(mapTexts) do
      g_map.removeThing(text)
    end
    mapTexts = {}
  end
end

function cavebot.addAllFlags()
  -- Recria todos os flags com índices atualizados
  for i, wp in ipairs(waypoints) do
    local pos = { x = wp.x, y = wp.y, z = wp.z }
    local iconId = wp.iconId or 11
    local flagData = { globalFlag = nil, cavebotFlag = nil }

    -- Add to global minimap
    if modules.game_minimap and modules.game_minimap.minimapWidget then
      flagData.globalFlag = cavebot.createWaypointFlag(
        modules.game_minimap.minimapWidget, pos, iconId, i)
    end

    if cavebotMap and not cavebotMap:isDestroyed() then
      flagData.cavebotFlag = cavebot.createWaypointFlag(
        cavebotMap, pos, iconId, i)
    end

    table.insert(waypointFlags, flagData)

    -- Add to World Map (StaticText)
    if g_map then
      local text = StaticText.create()
      text:setText(string.format("Waypoint %d", i))
      text:setColor("white")
      g_map.addThing(text, pos, -1)
      table.insert(mapTexts, text)
    end
  end

  -- Atualiza seleção visual
  cavebot.updateFlagSelection()
end

function cavebot.deleteWaypoint(index)
  if index < 1 or index > #waypoints then return end

  cavebot.removeAllFlags()
  table.remove(waypoints, index)

  -- Atualiza editingIndex se necessário
  if editingIndex then
    if editingIndex == index then
      editingIndex = nil
    elseif editingIndex > index then
      editingIndex = editingIndex - 1
    end
  end

  cavebot.addAllFlags()
  cavebot.refreshList()
end

function cavebot.changeWaypointType(index, newType)
  cavebot.removeAllFlags()
  local wp = waypoints[index]
  if wp then
    wp.action = newType
    wp.iconId = WAYPOINT_ICON[newType] or WAYPOINT_ICON[WAYPOINT_TYPE.WALK]
    if newType == WAYPOINT_TYPE.ACTION and wp.actionScript == nil then
      wp.actionScript = ""
    end
  end
  cavebot.addAllFlags()
  cavebot.refreshList()
end

function cavebot.onWaypointMenu(index, pos, button)
  if button ~= MouseRightButton then return end
  if not index or not waypoints[index] then return end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  menu:addOption(tr('Delete'), function() cavebot.deleteWaypoint(index) end)
  menu:addSeparator()
  menu:addOption(tr('Type: Walk'), function() cavebot.changeWaypointType(index, WAYPOINT_TYPE.WALK) end)
  menu:addOption(tr('Type: Stand'), function() cavebot.changeWaypointType(index, WAYPOINT_TYPE.STAND) end)
  menu:addOption(tr('Type: Action'), function() cavebot.changeWaypointType(index, WAYPOINT_TYPE.ACTION) end)
  menu:addOption(tr('Type: Use'), function() cavebot.changeWaypointType(index, WAYPOINT_TYPE.USE) end)
  menu:addOption(tr('Type: Rope'), function() cavebot.changeWaypointType(index, WAYPOINT_TYPE.ROPE) end)
  menu:addOption(tr('Type: Shovel'), function() cavebot.changeWaypointType(index, WAYPOINT_TYPE.SHOVEL) end)
  if waypoints[index].action == WAYPOINT_TYPE.ACTION then
    menu:addSeparator()
    menu:addOption(tr('Edit script'), function() cavebot.openActionScriptEditor(index) end)
  end

  menu:display(pos)
end

function cavebot.onMapClick(widget, mousePos, mouseButton)
  local mapPos = widget:getTilePosition(mousePos)
  if not mapPos then return end

  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)

  menu:addOption(tr('Add Walk'), function() cavebot.addWaypoint(WAYPOINT_TYPE.WALK, mapPos) end)
  menu:addOption(tr('Add Node'), function() cavebot.addWaypoint(WAYPOINT_TYPE.NODE, mapPos) end)
  menu:addOption(tr('Add Stand'), function() cavebot.addWaypoint(WAYPOINT_TYPE.STAND, mapPos) end)
  menu:addOption(tr('Add Action'), function() cavebot.addWaypoint(WAYPOINT_TYPE.ACTION, mapPos) end)
  menu:addSeparator()
  menu:addOption(tr('Add Use'), function() cavebot.addWaypoint(WAYPOINT_TYPE.USE, mapPos) end)
  menu:addOption(tr('Add Rope'), function() cavebot.addWaypoint(WAYPOINT_TYPE.ROPE, mapPos) end)
  menu:addOption(tr('Add Shovel'), function() cavebot.addWaypoint(WAYPOINT_TYPE.SHOVEL, mapPos) end)

  menu:display(mousePos)

  return true
end

function cavebot.openActionScriptEditor(index)
  if not index or not waypoints[index] or waypoints[index].action ~= WAYPOINT_TYPE.ACTION then return end
  local root = g_ui.getRootWidget()
  if not root then return end
  if actionScriptEditorWindow and not actionScriptEditorWindow:isDestroyed() then
    actionScriptEditorWindow:destroy()
    actionScriptEditorWindow = nil
  end
  actionScriptEditorWindow = g_ui.createWidget('CavebotActionScriptWindow', root)
  if not actionScriptEditorWindow then return end
  actionScriptEditingIndex = index
  local codeEdit = actionScriptEditorWindow:recursiveGetChildById('actionScriptCode')
  local saveBtn = actionScriptEditorWindow:recursiveGetChildById('actionScriptSaveButton')
  local closeBtn = actionScriptEditorWindow:recursiveGetChildById('actionScriptCloseButton')
  if codeEdit then codeEdit:setText(waypoints[index].actionScript or "") end
  if saveBtn then
    saveBtn.onClick = function()
      if actionScriptEditingIndex and waypoints[actionScriptEditingIndex] and codeEdit then
        waypoints[actionScriptEditingIndex].actionScript = codeEdit:getText() or ""
      end
      cavebot.closeActionScriptEditor()
    end
  end
  if closeBtn then closeBtn.onClick = function() cavebot.closeActionScriptEditor() end end
  actionScriptEditorWindow:show()
  actionScriptEditorWindow:raise()
  actionScriptEditorWindow:focus()
end

function cavebot.closeActionScriptEditor()
  if actionScriptEditorWindow and not actionScriptEditorWindow:isDestroyed() then
    actionScriptEditorWindow:destroy()
    actionScriptEditorWindow = nil
  end
  actionScriptEditingIndex = nil
end

function cavebot.refreshList()
  if not ui.waypointList or ui.waypointList:isDestroyed() then return end

  ui.waypointList:destroyChildren()

  for i, wp in ipairs(waypoints) do
    local item = g_ui.createWidget('UIWidget', ui.waypointList)
    item:setHeight(14)
    item:setMarginTop(2)
    item.id = i
    item.onMouseRelease = function(widget, mousePos, mouseButton)
      cavebot.onWaypointMenu(i, mousePos, mouseButton)
    end

    local idLabel = g_ui.createWidget('Label', item)
    idLabel:setText(string.format("%03d", i))
    idLabel:setWidth(30)
    idLabel:setTextAlign(AlignCenter)
    idLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
    idLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    idLabel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    idLabel:setPhantom(true)

    local typeName = wp.action or WAYPOINT_TYPE.WALK
    local typeLabel = g_ui.createWidget('Label', item)
    typeLabel:setText(typeName)
    typeLabel:setWidth(50)
    typeLabel:setTextAlign(AlignCenter)
    typeLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
    typeLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    typeLabel:setMarginLeft(30)
    typeLabel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    typeLabel:setPhantom(true)

    local coordText = string.format("x:%d, y:%d, z:%d", wp.x, wp.y, wp.z)
    if wp.monsterLimit and wp.monsterLimit > 0 then
      coordText = coordText .. string.format(" [M:%d]", wp.monsterLimit)
    end

    local coordLabel = g_ui.createWidget('Label', item)
    coordLabel:setText(coordText)
    coordLabel:setTextAlign(AlignCenter)
    coordLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
    coordLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    coordLabel:setMarginLeft(80)
    coordLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
    coordLabel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    coordLabel:setPhantom(true)

    local isWalkingCurrent = (MACHINE_STATE.isRunning and i == MACHINE_STATE.currentIndex)
    local isEditing = (i == editingIndex)

    local color = "white"
    if isWalkingCurrent then
      color = "green"
    elseif isEditing then
      color = "yellow"
    end

    idLabel:setColor(color)
    typeLabel:setColor(color)
    coordLabel:setColor(color)

    item.onClick = function()
      cavebot.selectWaypoint(i)
      -- Não muda automaticamente para aba config - usuário decide quando ir
    end
    item.onDoubleClick = function()
      if wp.action == WAYPOINT_TYPE.ACTION then
        cavebot.openActionScriptEditor(i)
      end
    end
  end

  cavebot.updateMinimapProgress()

  if ui.saveSessionButton and not ui.saveSessionButton:isDestroyed() and
     ui.sessionName and not ui.sessionName:isDestroyed() then
    local text = ui.sessionName:getText() or ''
    ui.saveSessionButton:setEnabled(#text >= 2 and #waypoints > 0)
  end
end

-- Função leve para atualizar apenas as cores dos waypoints (sem reconstruir UI)
function cavebot.updateListColors()
  if not ui.waypointList or ui.waypointList:isDestroyed() then return end

  local children = ui.waypointList:getChildren()
  for i, item in ipairs(children) do
    if item:isDestroyed() then break end
    local isWalkingCurrent = (MACHINE_STATE.isRunning and i == MACHINE_STATE.currentIndex)
    local isEditing = (i == editingIndex)

    local color = "white"
    if isWalkingCurrent then
      color = "green"
    elseif isEditing then
      color = "yellow"
    end

    local itemChildren = item:getChildren()
    for _, label in ipairs(itemChildren) do
      if label and not label:isDestroyed() and label.setColor then
        label:setColor(color)
      end
    end
  end

  -- Atualiza progresso no minimap
  cavebot.updateMinimapProgress()
end

-- JSON Persistence Helpers
-- Pasta compartilhada para todos os personagens da conta
function cavebot.getProfileDir()
  return "/cavebots"
end

function cavebot.ensureProfileDir()
  local profileDir = cavebot.getProfileDir()
  if not g_resources.directoryExists(profileDir) then
    g_resources.makeDir(profileDir)
  end
end

-- Migra scripts antigos de /characterdata/{player_id}/ para /cavebots/
function cavebot.migrateOldScripts()
  cavebot.ensureProfileDir()

  local targetDir = cavebot.getProfileDir()
  local migratedCount = 0
  local writeDir = g_resources.getWriteDir()

  -- Verifica se a pasta characterdata existe
  local charDataExists = g_resources.directoryExists("/characterdata")

  if not charDataExists then
    return 0
  end

  -- Lista todas as pastas de personagens
  local dirs = g_resources.listDirectoryFiles("/characterdata")

  if not dirs or #dirs == 0 then
    return 0
  end

  for _, dir in ipairs(dirs) do
    local charPath = "/characterdata/" .. dir

    -- Lista arquivos de cavebot nessa pasta
    local files = g_resources.listDirectoryFiles(charPath)

    if files and #files > 0 then
      for _, file in ipairs(files) do
        if file:match("^cavebot_.*%.json$") then
          local sourceRealPath = writeDir .. charPath .. "/" .. file
          local targetRealPath = writeDir .. targetDir .. "/" .. file

          -- Verifica se arquivo fonte existe
          local sourceFile = io.open(sourceRealPath, "r")
          if sourceFile then
            -- Verifica se já existe no destino
            local targetFile = io.open(targetRealPath, "r")
            if targetFile then
              targetFile:close()
              sourceFile:close()
            else
              -- Lê conteúdo
              local content = sourceFile:read("*all")
              sourceFile:close()

              if content and #content > 0 then
                -- Escreve no destino
                local outFile = io.open(targetRealPath, "w")
                if outFile then
                  outFile:write(content)
                  outFile:close()
                  -- Remove arquivo original (cut, não copy)
                  os.remove(sourceRealPath)
                  migratedCount = migratedCount + 1
                end
              end
            end
          end
        end
      end
    end
  end

  if migratedCount > 0 then
    modules.game_textmessage.displayStatusMessage(tr('Migrated ' .. migratedCount .. ' cavebot scripts to shared folder.'))
  end

  return migratedCount
end

function cavebot.saveFile(filename, data)
  cavebot.ensureProfileDir()

  local fullPath = filename
  if not filename:find("^/") then
    fullPath = filename
  end

  local content = json.encode(data, 2)
  if g_resources.writeFileContents then
    return g_resources.writeFileContents(fullPath, content)
  else
    -- Fallback to IO
    local realPath = g_resources.getWriteDir() .. fullPath
    local file = io.open(realPath, "w")
    if file then
      file:write(content)
      file:close()
      return true
    end
  end
  return false
end

function cavebot.readFile(filename)
  if g_resources.readFileContents then
    if g_resources.fileExists(filename) then
      local content = g_resources.readFileContents(filename)
      return json.decode(content)
    else
    end
  else
    -- Fallback to IO
    local realPath = g_resources.getWriteDir() .. filename
    local file = io.open(realPath, "r")
    if file then
      local content = file:read("*all")
      file:close()
      return json.decode(content)
    else
    end
  end
  return nil
end

function cavebot.refreshSessionList()
  if not ui.sessionsList then return end
  local scrollBar = ui.sessionsList:getParent() and ui.sessionsList:getParent():getChildById('sessionsScrollBar')
  local scrollValue = scrollBar and scrollBar:getValue() or 0
  ui.sessionsList:destroyChildren()

  for _, name in ipairs(sessionList) do
    local label = g_ui.createWidget('Label', ui.sessionsList)
    label:setText(name)
    label:setMarginTop(2)
    label:setPhantom(false) -- Clickable

    if name == selectedSession then
      label:setColor('yellow')
      label:setFont('verdana-11px-rounded')
    else
      label:setColor('white')
      label:setFont('verdana-11px-antialised')
    end

    label.onClick = function()
      if ui.sessionName then ui.sessionName:setText(name) end
      selectedSession = name
      -- Enable delete button when a session is selected
      if ui.deleteSessionButton then
        ui.deleteSessionButton:setEnabled(true)
      end
      cavebot.refreshSessionList()
    end
  end

  -- Disable delete button if no session is selected
  if not selectedSession or selectedSession == '' then
    if ui.deleteSessionButton then
      ui.deleteSessionButton:setEnabled(false)
    end
  end

  -- Restore scroll position after rebuilding the list
  if scrollBar and scrollValue > 0 then
    scrollBar:setValue(scrollValue)
  end
end

function cavebot.saveSession()
  local name = "default"
  if ui.sessionName then name = ui.sessionName:getText() end
  -- Trim spaces
  name = name:match("^%s*(.-)%s*$")

  -- Strip "ID: " or "Global: " prefix if present (copying from other/global)
  local foreignId, foreignName = name:match("^(%d+):%s*(.+)")
  if foreignId and foreignName then
    name = foreignName
  else
    local globalName = name:match("^Global:%s*(.+)")
    if globalName then
      name = globalName
    end
  end

  if name ~= ui.sessionName:getText() then
    if ui.sessionName then ui.sessionName:setText(name) end
  end

  if name == "" then name = "default" end

  local config = { waypoints = waypoints, settings = defaultConfig }
  local filename = "cavebot_" .. name .. ".json"
  local relativePath = cavebot.getProfileDir() .. "/" .. filename

  if cavebot.saveFile(relativePath, config) then
    -- Refresh list to include new file
    cavebot.loadSessionList()

    selectedSession = name
    cavebot.refreshSessionList()
    modules.game_textmessage.displayStatusMessage(tr('Session saved: ' .. name))

    -- Clear the input after saving
    if ui.sessionName then
      ui.sessionName:setText('')
    end
    -- Disable save button since input is now empty
    if ui.saveSessionButton then
      ui.saveSessionButton:setEnabled(false)
    end
  else
    modules.game_textmessage.displayStatusMessage(tr('Failed to save session to ' .. relativePath))
  end
end

-- Função interna que realmente deleta a sessão
local function doDeleteSession()
  local name = "default"
  if ui.sessionName then name = ui.sessionName:getText() end
  name = name:match("^%s*(.-)%s*$")

  if name == "" then return end

  local filename = "cavebot_" .. name .. ".json"
  local relativePath = cavebot.getProfileDir() .. "/" .. filename

  if g_resources.fileExists(relativePath) then
    local success = false
    if g_resources.deleteFile then
      success = g_resources.deleteFile(relativePath)
    else
      -- Fallback
      local realPath = g_resources.getWriteDir() .. relativePath
      success = os.remove(realPath)
    end

    if success then
      modules.game_textmessage.displayStatusMessage(tr('Script deleted: ' .. name))
      ui.sessionName:setText('')
      selectedSession = nil
      -- Disable delete button after deletion
      if ui.deleteSessionButton then
        ui.deleteSessionButton:setEnabled(false)
      end
      cavebot.loadSessionList()
      cavebot.refreshSessionList()
    else
      modules.game_textmessage.displayStatusMessage(tr('Failed to delete script.'))
    end
  else
    modules.game_textmessage.displayStatusMessage(tr('File not found: ' .. relativePath))
  end
end

function cavebot.deleteSession()
  local name = "default"
  if ui.sessionName then name = ui.sessionName:getText() end
  name = name:match("^%s*(.-)%s*$")

  -- Se não há nome selecionado, não faz nada
  if name == "" then
    return
  end

  -- Modal de confirmação usando displayGeneralBox
  local messageBox
  local yesCallback = function()
    doDeleteSession()
    if messageBox then messageBox:destroy() end
  end
  local noCallback = function()
    if messageBox then messageBox:destroy() end
  end

  messageBox = displayGeneralBox(tr('Delete Script'),
    tr('Are you sure you want to delete the script "' .. name .. '"?'),
    {
      { text = tr('Yes'), callback = yesCallback },
      { text = tr('No'),  callback = noCallback },
      anchor = AnchorHorizontalCenter
    },
    yesCallback, noCallback)
end

function cavebot.loadSessionList()
  if not g_game.isOnline() then return end

  sessionList = {}
  local profileDir = cavebot.getProfileDir()

  -- Garante que a pasta existe
  cavebot.ensureProfileDir()

  local files = g_resources.listDirectoryFiles(profileDir)
  if files then
    for _, file in ipairs(files) do
      -- Filter only files starting with cavebot_ and ending in .json
      if file:match("^cavebot_.*%.json$") then
        -- Extract name: cavebot_NAME.json -> NAME
        local name = file:match("^cavebot_(.+)%.json$")
        if name then
          table.insert(sessionList, name)
        end
      end
    end
  end

  cavebot.refreshSessionList()
end

function cavebot.loadSession()
  local name = "default"
  if ui.sessionName then name = ui.sessionName:getText() end
  -- Trim spaces
  name = name:match("^%s*(.-)%s*$")
  if name == "" then
    -- If name is empty, refresh the list instead of erroring
    cavebot.loadSessionList()
    modules.game_textmessage.displayStatusMessage(tr('Script list refreshed.'))
    return
  end

  local filename = "cavebot_" .. name .. ".json"
  local relativePath = cavebot.getProfileDir() .. "/" .. filename

  local config = cavebot.readFile(relativePath)

  if config and config.waypoints then
    doClearWaypoints() -- Clear current sem pedir confirmação

    local loadedParams = config.waypoints
    if config.settings then
      if config.settings.walkMethod then defaultConfig.walkMethod = config.settings.walkMethod end
      if config.settings.monsterLimit then defaultConfig.monsterLimit = config.settings.monsterLimit end
      if config.settings.resumeLimit then defaultConfig.resumeLimit = config.settings.resumeLimit end
      if config.settings.minMonstersToWait then defaultConfig.minMonstersToWait = config.settings.minMonstersToWait end
      if config.settings.avoidTrap then defaultConfig.avoidTrap = config.settings.avoidTrap end
      if config.settings.useAutolootAfterKill ~= nil then
        defaultConfig.useAutolootAfterKill = config.settings
            .useAutolootAfterKill
      end
      if config.settings.walkDelay then defaultConfig.walkDelay = config.settings.walkDelay end
      if config.settings.recordType then defaultConfig.recordType = config.settings.recordType end
      if config.settings.recordDist then defaultConfig.recordDist = config.settings.recordDist end
      if config.settings.nodeDistance then defaultConfig.nodeDistance = config.settings.nodeDistance end
      if config.settings.autoExplorer ~= nil then defaultConfig.autoExplorer = config.settings.autoExplorer end
    end

    local newWaypoints = {}

    -- Reconstruct waypoints list
    for k, v in pairs(loadedParams) do
      if v and v.x and v.y and v.z then
        if type(k) == 'number' then
          newWaypoints[k] = v
        else
          table.insert(newWaypoints, v)
        end
      end
    end

    -- Sort / Reindex
    waypoints = {}
    local keys = {}
    for k in pairs(newWaypoints) do table.insert(keys, k) end
    table.sort(keys)

    for _, k in ipairs(keys) do
      table.insert(waypoints, newWaypoints[k])
    end


    -- Re-add flags usando o novo sistema customizado
    cavebot.addAllFlags()

    cavebot.refreshList()
    cavebot.updateConfigEditor() -- Atualiza a UI da tab config
    modules.game_textmessage.displayStatusMessage(tr('Script loaded: ' .. name .. ' (' .. #waypoints .. ' WPs)'))
  else
    modules.game_textmessage.displayStatusMessage(tr('Script not found: ' .. name))
  end
end

-- Walking Logic
function cavebot.toggle(state)
  -- Desliga o recorder se estiver ligado ao mudar status do cavebot
  if cavebot.isRecording() then
    cavebot.stopRecording()
  end

  MACHINE_STATE.isRunning = state

  local btn = nil
  if helperWindow then
    btn = helperWindow:recursiveGetChildById('cavebotToggleButton')
  end
  if btn then
    if MACHINE_STATE.isRunning then
      btn:setText(tr('On'))
      btn:setColor('#AAFFAA') -- Greenish
    else
      btn:setText(tr('Off'))
      btn:setColor('#FFAAAA') -- Reddish
    end
  end

  -- Sincronizar com shortcut panel
  if _Helper and _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutCavebot', MACHINE_STATE.isRunning)
  end

  cavebot.updateListColors()
  if MACHINE_STATE.isRunning then
    cavebot.resetState()
    -- Encontra o waypoint mais próximo ao iniciar
    MACHINE_STATE.currentIndex = cavebot.findNearestWaypoint()
    cavebot.updateListColors()
    cavebot.updateMinimapProgress()
    if defaultConfig.autoExplorer and #waypoints == 0 then
      local p = g_game.getLocalPlayer()
      if p then
        local pos = p:getPosition()
        if pos then
          EXPLORE_STATE.homePos = { x = pos.x, y = pos.y, z = pos.z }
        end
      end
      EXPLORE_STATE.phase = 'explore'
      modules.game_textmessage.displayStatusMessage(tr('Cavebot: Auto Explorer; ponto inicial é esta posição.'))
    end
    cavebot.startWalking()
  else
    cavebot.stopWalking()
    cavebot.updateMinimapProgress()
  end
end

-- Alias para compatibilidade
local function isEnabled()
  return MACHINE_STATE.isRunning
end

-- ============================================================================
-- FUNÇÕES DE CONTROLE DE ESTADO
-- ============================================================================

-- Encontra o waypoint mais próximo do player
function cavebot.findNearestWaypoint()
  if #waypoints == 0 then return 1 end

  local player = g_game.getLocalPlayer()
  if not player then return 1 end

  local playerPos = player:getPosition()
  local nearestIndex = 1
  local nearestDist = 999999

  for i, wpt in ipairs(waypoints) do
    local wptPos = {
      x = tonumber(wpt.x),
      y = tonumber(wpt.y),
      z = tonumber(wpt.z)
    }

    -- Só considera waypoints no mesmo floor
    if wptPos.z == playerPos.z then
      local dist = cavebot.getDistance(playerPos, wptPos)
      if dist < nearestDist then
        nearestDist = dist
        nearestIndex = i
      end
    end
  end

  -- Se não achou nenhum no mesmo floor, procura em qualquer floor
  if nearestDist == 999999 then
    for i, wpt in ipairs(waypoints) do
      local wptPos = {
        x = tonumber(wpt.x),
        y = tonumber(wpt.y),
        z = tonumber(wpt.z)
      }
      local dist = cavebot.getDistance(playerPos, wptPos)
      if dist < nearestDist then
        nearestDist = dist
        nearestIndex = i
      end
    end
  end

  return nearestIndex
end

-- Reseta o estado da máquina (ao iniciar/reiniciar)
function cavebot.resetState()
  MACHINE_STATE.pausedByMonsters = false
  MACHINE_STATE.justExitedKillingBox = false
  MACHINE_STATE.actionScriptRunning = false
  MACHINE_STATE.lastFreeze = 0
  MACHINE_STATE.lastMove = 0
  MACHINE_STATE.lastPosition = nil
  MACHINE_STATE.isStuck = false
  MACHINE_STATE.lastStatus = "Starting"
  MACHINE_STATE.walkAttempts.pathfind = 0
  MACHINE_STATE.walkAttempts.autoWalk = 0
  MACHINE_STATE.autoWalkFailed = false
  MACHINE_STATE.actionWaitUntil = 0
  MACHINE_STATE.autolootWaitUntil = 0
  MACHINE_STATE.lastAutolootDeathAt = 0

  MACHINE_TIMERS.lastWalk = 0
  MACHINE_TIMERS.currentDelay = MACHINE_TIMERS.baseDelay

  MACHINE_UTILS.monsterCount = 0
  MACHINE_UTILS.monsters = {}
  MACHINE_UTILS.lifePercentage = 0

  resetExploreRunState()
end

-- Atualiza dados de monstros (como getMonstersData do ZeroBot)
function cavebot.updateMonstersData(playerPos, range)
  range = range or 7
  local specs = g_map.getSpectators(playerPos, false) or {}
  local monsters = {}
  local totalLife = 0

  -- Try to get ignore table from helper
  local ignoreTable = {}
  if _Helper and _Helper.getIgnoreMonsterTable then
    ignoreTable = _Helper.getIgnoreMonsterTable() or {}
  end

  for _, creature in ipairs(specs) do
    if creature:isMonster() and not creature:isDead() then
      local cPos = creature:getPosition()

      if cPos and cPos.z == playerPos.z then
        local name = creature:getName()
        if not (name and ignoreTable[name:lower()]) then
          local dist = math.max(math.abs(playerPos.x - cPos.x), math.abs(playerPos.y - cPos.y))
          if dist <= range then
            if g_map.isSightClear(playerPos, cPos) then
              local hp = creature:getHealthPercent() or 100
              table.insert(monsters, {
                creature = creature,
                position = cPos,
                distance = dist,
                life = hp,
                name = name
              })
              totalLife = totalLife + hp
            end
          end
        end
      end
    end
  end

  MACHINE_UTILS.monsters = monsters
  MACHINE_UTILS.monsterCount = #monsters
  MACHINE_UTILS.lifePercentage = #monsters > 0 and (totalLife / #monsters) or 0

  return #monsters
end

-- ============================================================================
-- SISTEMA DE DELAY DINÂMICO (inspirado no canWalkAgain do ZeroBot)
-- ============================================================================

-- Calcula delay baseado em ping, velocidade, monstros e método de walk
function cavebot.calculateWalkDelay(isMapClick)
  local ping = MACHINE_UTILS.getPing()
  local monsterCount = MACHINE_UTILS.monsterCount

  local tileSpeed = 100
  local player = g_game.getLocalPlayer()
  if player and player.getStepDuration then
    tileSpeed = player:getStepDuration() or 100
  end

  local walkDelay = defaultConfig.walkDelay or 0
  local minMonstersToWait = defaultConfig.minMonstersToWait or 2

  local delay
  if g_helperCore and g_helperCore.getCavebotWalkDelay then
    delay = g_helperCore.getCavebotWalkDelay(ping, monsterCount, tileSpeed, isMapClick, walkDelay, minMonstersToWait)
  else
    if isMapClick then
      if monsterCount == 0 then
        delay = math.max(ping, 20)
      else
        delay = math.max(ping, 50)
        local monsterDelay = math.min(monsterCount * 20, 100)
        delay = delay + monsterDelay
      end
    else
      if monsterCount == 0 then
        delay = tileSpeed
      else
        delay = math.max(ping, tileSpeed)
        local monsterDelay = math.min(monsterCount * 30, 150)
        delay = delay + monsterDelay
        delay = math.min(delay, MACHINE_TIMERS.maxDelay)
      end
    end
    if walkDelay > 0 and monsterCount >= minMonstersToWait then
      delay = delay + walkDelay
    end
    local maxAllowedDelay = math.max(2000, walkDelay + 500)
    delay = math.min(delay, maxAllowedDelay)
  end

  MACHINE_TIMERS.currentDelay = delay
  return delay
end

-- Verifica se pode andar novamente (como canWalkAgain do ZeroBot)
function cavebot.canWalkAgain()
  local now = os.clock()
  -- Usa o método de walk configurado para calcular delay correto
  local isMapClick = (defaultConfig.walkMethod == 'Map Click')
  local delay = cavebot.calculateWalkDelay(isMapClick)
  local elapsed = (now - MACHINE_TIMERS.lastWalk) * 1000 -- Converter para ms

  return elapsed >= delay
end

-- Registra que um passo foi dado
function cavebot.registerWalkStep()
  MACHINE_TIMERS.lastWalk = os.clock()
  MACHINE_STATE.walkAttempts.pathfind = 0
  MACHINE_STATE.walkAttempts.autoWalk = 0
  MACHINE_STATE.autoWalkSentCount = 0
end

local function executeWalkMovement(player, playerPos, effectiveTarget)
  if player.canWalk and not player:canWalk() then
    return
  end
  if not cavebot.canWalkAgain() then
    return
  end

  local walkMethod = defaultConfig.walkMethod or 'Map Click'
  local walkDelay = defaultConfig.walkDelay or 0
  local minMonstersToWait = defaultConfig.minMonstersToWait or 2
  local forceKeyboardForDelay = (walkDelay > 0 and MACHINE_UTILS.monsterCount >= minMonstersToWait)

  if MACHINE_STATE.autoWalkFailed and MACHINE_STATE.autoWalkFailedAt > 0 then
    local elapsed = os.clock() - MACHINE_STATE.autoWalkFailedAt
    if elapsed >= 2.0 then
      MACHINE_STATE.autoWalkFailed = false
      MACHINE_STATE.autoWalkFailedAt = 0
      MACHINE_STATE.autoWalkSentCount = 0
    end
  end

  local useKeyboard = (walkMethod == 'Keyboard') or MACHINE_STATE.autoWalkFailed or forceKeyboardForDelay

  local pathFlags = 53

  if useKeyboard then
    local strictFlags = bit.band(pathFlags, bit.bnot(16))
    local dir = nil

    local success, path = pcall(function()
      return g_map.findPath(playerPos, effectiveTarget, 1000, strictFlags)
    end)
    if success and path and #path > 0 then
      dir = path[1]
    end

    if not dir then
      success, path = pcall(function()
        return g_map.findPath(playerPos, effectiveTarget, 40000, pathFlags)
      end)
      if success and path and #path > 0 then
        local nextPos = applyDirection(playerPos, path[1])
        if not hasCreatureBlocking(nextPos) then
          dir = path[1]
        end
      end
    end

    if dir then
      g_game.walk(dir)
      cavebot.registerWalkStep()
    end
    return
  else
    local isWalking = player.isAutoWalking and player:isAutoWalking()

    local creatureInPath = false
    local success, path = pcall(function()
      return g_map.findPath(playerPos, effectiveTarget, 40000, pathFlags)
    end)
    if success and path and #path > 0 then
      local checkPos = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
      local maxCheck = math.min(#path, 3)
      for step = 1, maxCheck do
        checkPos = applyDirection(checkPos, path[step])
        if hasCreatureBlocking(checkPos) then
          creatureInPath = true
          break
        end
      end
    end

    if not isWalking or creatureInPath then
      if creatureInPath and isWalking then
        player:stopAutoWalk()
      end

      if player.autoWalk then
        player:autoWalk(effectiveTarget, false, false, pathFlags)
      else
        g_game.autoWalk(effectiveTarget)
      end
    end

    MACHINE_TIMERS.lastWalk = os.clock()
    return
  end
end

local function exploreApplyNeighborRetarget(playerPos, goalPos)
  local effectiveTarget = { x = goalPos.x, y = goalPos.y, z = goalPos.z }
  local tile = g_map.getTile(effectiveTarget)
  local isBlocked = false
  if not tile or not tile:isWalkable() then
    isBlocked = true
  else
    local creatures = tile:getCreatures()
    if creatures and #creatures > 0 then
      for _, c in ipairs(creatures) do
        if c:isMonster() and not c:isDead() then
          isBlocked = true
          break
        end
      end
    end
  end
  if isBlocked then
    local neighbors = {
      { x = 0, y = -1 }, { x = 1, y = -1 }, { x = 1, y = 0 }, { x = 1, y = 1 },
      { x = 0, y = 1 }, { x = -1, y = 1 }, { x = -1, y = 0 }, { x = -1, y = -1 },
    }
    local bestDist = 99999
    local bestPos = nil
    for _, n in ipairs(neighbors) do
      local candidate = { x = effectiveTarget.x + n.x, y = effectiveTarget.y + n.y, z = effectiveTarget.z }
      local cTile = g_map.getTile(candidate)
      if cTile and cTile:isWalkable() then
        local d = cavebot.getDistance(playerPos, candidate)
        if d < bestDist then
          bestDist = d
          bestPos = candidate
        end
      end
    end
    if bestPos then
      effectiveTarget = bestPos
    end
  end
  return effectiveTarget
end

function cavebot.explorerWalkerTick()
  if not MACHINE_STATE.isRunning or not defaultConfig.autoExplorer then
    return
  end
  if #waypoints > 0 then
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  if MACHINE_STATE.actionWaitUntil > 0 then
    if os.clock() < MACHINE_STATE.actionWaitUntil then
      return
    end
    MACHINE_STATE.actionWaitUntil = 0
  end

  if MACHINE_STATE.autolootWaitUntil > 0 then
    if os.clock() < MACHINE_STATE.autolootWaitUntil then
      MACHINE_STATE.lastStatus = 'Looting'
      player:stopAutoWalk()
      return
    end
    MACHINE_STATE.autolootWaitUntil = 0
  end

  local att = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if att and not att:isDead() then
    MACHINE_STATE.lastStatus = 'Explore (combat)'
    return
  end

  local playerPos = player:getPosition()

  if EXPLORE_STATE.phase == 'finished' then
    MACHINE_STATE.lastStatus = 'Explore (done)'
    return
  end

  cavebot.updateMonstersData(playerPos, 7)
  exploreCleanVisited()

  -- Safety Lure (mesma lógica do cavebot em waypoint com killing box; aqui aplica sempre aos settings globais)
  local minMonstersToWait = defaultConfig.minMonstersToWait or 2
  local avoidTrap = defaultConfig.avoidTrap or 4
  if minMonstersToWait > 0 and cavebot.avoidLostInMonsters(playerPos, MACHINE_UTILS.monsters, minMonstersToWait, avoidTrap) then
    local nowLure = os.clock()
    if MACHINE_STATE.lureWaitStart == 0 then
      MACHINE_STATE.lureWaitStart = nowLure
    end
    local lureMax = (g_helperCore and g_helperCore.getCavebotLureWaitMaxTime and g_helperCore.getCavebotLureWaitMaxTime()) or MACHINE_STATE.lureWaitMaxTime
    if (nowLure - MACHINE_STATE.lureWaitStart) < lureMax then
      MACHINE_STATE.lastStatus = 'Waiting monsters'
      player:stopAutoWalk()
      return
    end
    MACHINE_STATE.lureWaitStart = 0
  else
    MACHINE_STATE.lureWaitStart = 0
  end

  if not EXPLORE_STATE.homePos then
    EXPLORE_STATE.homePos = { x = playerPos.x, y = playerPos.y, z = playerPos.z }
  end

  local nowClock = os.clock()

  if EXPLORE_STATE.phase == 'return_home' then
    local h = EXPLORE_STATE.homePos
    if not h then
      EXPLORE_STATE.phase = 'finished'
      return
    end
    local dx = math.abs(playerPos.x - h.x)
    local dy = math.abs(playerPos.y - h.y)
    if dx <= 1 and dy <= 1 and playerPos.z == h.z then
      EXPLORE_STATE.phase = 'finished'
      EXPLORE_STATE.currentTarget = nil
      modules.game_textmessage.displayStatusMessage(tr('Auto Explorer: de volta ao ponto inicial.'))
      return
    end
    local effectiveTarget = exploreApplyNeighborRetarget(playerPos, h)
    MACHINE_STATE.lastStatus = 'Returning'
    executeWalkMovement(player, playerPos, effectiveTarget)
    return
  end

  if EXPLORE_STATE.lastPos then
    if playerPos.x == EXPLORE_STATE.lastPos.x and playerPos.y == EXPLORE_STATE.lastPos.y and playerPos.z == EXPLORE_STATE.lastPos.z then
      if EXPLORE_STATE.lastPosAt > 0 and (nowClock - EXPLORE_STATE.lastPosAt) > 5 then
        EXPLORE_STATE.stuckCount = EXPLORE_STATE.stuckCount + 1
        EXPLORE_STATE.lastPosAt = nowClock
        if EXPLORE_STATE.stuckCount >= 3 then
          EXPLORE_STATE.visited = {}
          EXPLORE_STATE.stuckCount = 0
          local br = exploreFindTargetBreakout(playerPos)
          if br then
            EXPLORE_STATE.currentTarget = br
            local effectiveTarget = exploreApplyNeighborRetarget(playerPos, br)
            if MACHINE_UTILS.monsterCount > 0 then
              MACHINE_STATE.lastStatus = 'Explore (kiting)'
            else
              MACHINE_STATE.lastStatus = 'Exploring'
            end
            executeWalkMovement(player, playerPos, effectiveTarget)
            return
          end
          exploreWalkRandom(player)
          return
        end
        exploreWalkRandom(player)
        return
      end
    else
      EXPLORE_STATE.stuckCount = 0
      EXPLORE_STATE.lastPosAt = nowClock
    end
  else
    EXPLORE_STATE.lastPosAt = nowClock
  end
  EXPLORE_STATE.lastPos = { x = playerPos.x, y = playerPos.y, z = playerPos.z }

  exploreMarkVisited(playerPos.x, playerPos.y, playerPos.z)

  local ct = EXPLORE_STATE.currentTarget
  if ct then
    local dx = math.abs(playerPos.x - ct.x)
    local dy = math.abs(playerPos.y - ct.y)
    if dx <= 2 and dy <= 2 and playerPos.z == ct.z then
      EXPLORE_STATE.currentTarget = nil
    end
  end

  if not EXPLORE_STATE.currentTarget then
    if nowClock < EXPLORE_STATE.noTargetUntil then
      return
    end
    EXPLORE_STATE.currentTarget = exploreFindTarget(playerPos)
    if not EXPLORE_STATE.currentTarget then
      EXPLORE_STATE.emptyFrontierStreak = (EXPLORE_STATE.emptyFrontierStreak or 0) + 1
      if EXPLORE_STATE.emptyFrontierStreak >= 3 and EXPLORE_STATE.homePos then
        EXPLORE_STATE.phase = 'return_home'
        EXPLORE_STATE.currentTarget = nil
        EXPLORE_STATE.emptyFrontierStreak = 0
        modules.game_textmessage.displayStatusMessage(tr('Auto Explorer: área explorada; voltando ao início.'))
        return
      end
      if EXPLORE_STATE.emptyFrontierStreak >= 6 then
        EXPLORE_STATE.emptyFrontierStreak = 0
        exploreWalkRandom(player)
      end
      EXPLORE_STATE.noTargetUntil = nowClock + 2.5
      MACHINE_STATE.lastStatus = 'Explore (search)'
      return
    end
    EXPLORE_STATE.emptyFrontierStreak = 0
  end

  local goal = EXPLORE_STATE.currentTarget
  local effectiveTarget = exploreApplyNeighborRetarget(playerPos, goal)

  if MACHINE_UTILS.monsterCount > 0 then
    MACHINE_STATE.lastStatus = 'Explore (kiting)'
  else
    MACHINE_STATE.lastStatus = 'Exploring'
  end

  executeWalkMovement(player, playerPos, effectiveTarget)
end

-- ============================================================================
-- SISTEMA DE DETECÇÃO DE FREEZE/STUCK (inspirado no HandleFreeze do ZeroBot)
-- ============================================================================

-- Atualiza estado de freeze/stuck
-- IMPORTANTE: Freeze só é detectado quando:
-- 1. O player está em um andar diferente do waypoint atual, OU
-- 2. O player pode andar (tem tiles livres) mas não está andando
-- Se o player não consegue ir do ponto A ao B por estar trapado, NÃO é freeze
function cavebot.updateFreezeState(currentPos, targetPos)
  local now = os.time()

  -- Se não tem posição anterior, inicializa
  if not MACHINE_STATE.lastPosition then
    MACHINE_STATE.lastPosition = currentPos
    MACHINE_STATE.lastMove = now
    MACHINE_STATE.lastFreeze = 0
    return false
  end

  -- Verifica se moveu
  local moved = (currentPos.x ~= MACHINE_STATE.lastPosition.x or
    currentPos.y ~= MACHINE_STATE.lastPosition.y or
    currentPos.z ~= MACHINE_STATE.lastPosition.z)

  if moved then
    -- Moveu! Reseta timers
    MACHINE_STATE.lastPosition = currentPos
    MACHINE_STATE.lastMove = now
    MACHINE_STATE.lastFreeze = 0
    MACHINE_STATE.isStuck = false
    return false
  end

  -- Não moveu - verifica se devemos considerar freeze
  local player = g_game.getLocalPlayer()
  if not player then return false end

  -- CASO 1: Player está em andar diferente do waypoint - SEMPRE é freeze
  local wrongFloor = targetPos and currentPos.z ~= targetPos.z

  -- CASO 2: Player pode andar mas não está andando
  local canMove = cavebot.canPlayerMove(player)

  -- Se trapado (não pode andar), reseta contadores mas ainda conta o tempo
  -- Isso evita que o script fique preso, mas dá mais tempo antes de considerar stuck
  if not canMove and not wrongFloor then
    -- Reseta contadores de tentativas para não travar o script
    MACHINE_STATE.walkAttempts.pathfind = 0
    MACHINE_STATE.walkAttempts.autoWalk = 0
  end

  -- Conta o tempo parado
  if MACHINE_STATE.lastFreeze == 0 then
    MACHINE_STATE.lastFreeze = now
  end

  local freezeTime = now - MACHINE_STATE.lastFreeze

  if wrongFloor then
    if freezeTime >= 5 then
      MACHINE_STATE.isStuck = true
      return true, "wrong_floor"
    elseif freezeTime >= 2 then
      return true, "floor_change"
    end
  end

  if canMove then
    if freezeTime >= MACHINE_STATE.stuckMaxTime then
      MACHINE_STATE.isStuck = true
      return true, "stuck"
    elseif freezeTime >= 5 then
      return true, "freezing"
    elseif freezeTime >= 2 then
      return true, "slow"
    end
  else
    if freezeTime >= 30 then
      MACHINE_STATE.isStuck = true
      return true, "trapped_timeout"
    end
  end

  return false
end

-- Trata situação de stuck
-- Retorna: "wait", "retry", "alternate", "restart"
-- NOTA: Esta função só é chamada quando updateFreezeState já confirmou que é um freeze real
-- (player pode andar mas não está andando, ou está em andar errado)
function cavebot.handleStuck(freezeLevel)
  -- Se está parado por killing box ou esperando monstros, não é stuck real
  if MACHINE_STATE.pausedByMonsters then
    return "wait"
  end

  -- Tratamento para andar errado
  if freezeLevel == "floor_change" then
    -- 2-5s em andar errado - tenta encontrar caminho
    MACHINE_STATE.lastStatus = "Wrong floor, finding path..."
    return "retry"
  elseif freezeLevel == "wrong_floor" then
    -- 5s+ em andar errado - reinicia script para encontrar waypoint mais próximo
    MACHINE_STATE.lastStatus = "Stuck on wrong floor! Restarting..."
    cavebot.restartScript()
    return "restart"
  end

  -- Nível 1 (2-5s): Incrementa tentativas
  if freezeLevel == "slow" then
    MACHINE_STATE.walkAttempts.pathfind = MACHINE_STATE.walkAttempts.pathfind + 1
    MACHINE_STATE.lastStatus = "Retrying..."
    return "retry"
  end

  -- Nível 2 (5-15s): Tenta autoWalk
  if freezeLevel == "freezing" then
    MACHINE_STATE.walkAttempts.autoWalk = MACHINE_STATE.walkAttempts.autoWalk + 1
    MACHINE_STATE.lastStatus = "Trying alternate path..."
    return "alternate"
  end

  -- Nível 3 (15s+): Reinicia script
  if freezeLevel == "stuck" then
    MACHINE_STATE.lastStatus = "Stuck! Restarting..."
    cavebot.restartScript()
    return "restart"
  end

  -- Timeout de trapado (30s+): Força restart
  if freezeLevel == "trapped_timeout" then
    MACHINE_STATE.lastStatus = "Trapped too long! Restarting..."
    cavebot.restartScript()
    return "restart"
  end

  return "wait"
end

-- Verifica se o player pode se mover (não está trapado por monstros ou paredes)
-- Retorna true se existe pelo menos 1 direção onde o player pode andar
-- IMPORTANTE: Verifica as 8 direções (N, NE, E, SE, S, SW, W, NW), não apenas as 4 cardinais.
-- Player só é considerado "trapado" se TODAS as 8 posições ao redor estiverem bloqueadas.
function cavebot.canPlayerMove(player)
  if not player then return false end

  local playerPos = player:getPosition()
  if not playerPos then return false end

  -- Lista de offsets para as 8 direções (não usar directionOffsets que é um hash)
  local directions = {
    { x = 0,  y = -1 }, -- Norte
    { x = 1,  y = -1 }, -- Nordeste
    { x = 1,  y = 0 },  -- Leste
    { x = 1,  y = 1 },  -- Sudeste
    { x = 0,  y = 1 },  -- Sul
    { x = -1, y = 1 },  -- Sudoeste
    { x = -1, y = 0 },  -- Oeste
    { x = -1, y = -1 }, -- Noroeste
  }

  for _, dir in ipairs(directions) do
    local checkPos = { x = playerPos.x + dir.x, y = playerPos.y + dir.y, z = playerPos.z }
    local tile = g_map.getTile(checkPos)
    if tile then
      -- Verifica se o tile é walkable (já considera paredes, itens bloqueadores, etc)
      if tile:isWalkable() then
        -- Verifica se não há criaturas bloqueando
        local creatures = tile:getCreatures()
        local blocked = false
        if creatures then
          for _, creature in ipairs(creatures) do
            -- Qualquer criatura (exceto o próprio player) bloqueia
            if creature ~= player then
              blocked = true
              break
            end
          end
        end
        if not blocked then
          return true
        end
      end
    end
  end

  return false
end

-- Reinicia o script (toggle off/on) para que findNearest encontre o waypoint mais próximo
function cavebot.restartScript()
  -- Para o script
  cavebot.toggle(false)

  -- Pequeno delay e reinicia
  scheduleEvent(function()
    if #waypoints > 0 then
      cavebot.toggle(true)
    end
  end, 500)
end

-- ============================================================================
-- WALKER HELPERS
-- ============================================================================
function cavebot.getDistance(pos1, pos2)
  if not pos1 or not pos2 then return 99999 end
  if g_helperCore and g_helperCore.getDistanceBetween then
    return g_helperCore.getDistanceBetween(pos1, pos2)
  end
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

-- Conta tiles ao redor do player que são ACESSÍVEIS por monstros
-- Um tile é considerado acessível se:
-- 1. É walkable (ignora criaturas atuais)
-- 2. Tem pelo menos uma entrada livre (não bloqueada por monstros nas diagonais)
--
-- Exemplo: Se um monstro está em x+1,y-1 e outro em x+1,y+1, o tile x+1,y está
-- bloqueado porque monstros não conseguem passar entre dois monstros diagonais
function cavebot.countFreeTiles(pos)
  if not pos then return 0 end

  -- Primeiro, mapeia onde estão os monstros adjacentes (distância 1-2)
  local monsterPositions = {}
  local specs = g_map.getSpectators(pos, false) or {}

  for _, creature in ipairs(specs) do
    if creature:isMonster() and not creature:isDead() then
      local cPos = creature:getPosition()
      if cPos.z == pos.z then
        local dist = math.max(math.abs(pos.x - cPos.x), math.abs(pos.y - cPos.y))
        if dist <= 2 then
          -- Usa string como chave para facilitar lookup
          local key = cPos.x .. "," .. cPos.y
          monsterPositions[key] = true
        end
      end
    end
  end

  -- Função auxiliar para verificar se há monstro numa posição
  local function hasMonster(x, y)
    return monsterPositions[x .. "," .. y] == true
  end

  -- Define os 8 tiles adjacentes e suas "entradas" possíveis
  -- Para um monstro entrar num tile adjacente ao player, ele precisa vir de fora
  -- Se as duas posições que dão acesso a esse tile têm monstros, está bloqueado
  local adjacentTiles = {
    -- Norte (y-1): entrada por NW(x-1,y-1), N(x,y-2), NE(x+1,y-1)
    { x = 0,  y = -1, entries = { { -1, -1 }, { 0, -2 }, { 1, -1 } } },
    -- Nordeste (x+1,y-1): entrada por N(x,y-1), NE(x+1,y-2), E(x+1,y), ou diagonal externa
    { x = 1,  y = -1, entries = { { 0, -1 }, { 1, -2 }, { 2, -1 }, { 1, 0 } } },
    -- Leste (x+1): entrada por NE(x+1,y-1), E(x+2,y), SE(x+1,y+1)
    { x = 1,  y = 0,  entries = { { 1, -1 }, { 2, 0 }, { 1, 1 } } },
    -- Sudeste (x+1,y+1): entrada por E(x+1,y), SE(x+2,y+1), S(x,y+1), ou diagonal externa
    { x = 1,  y = 1,  entries = { { 1, 0 }, { 2, 1 }, { 1, 2 }, { 0, 1 } } },
    -- Sul (y+1): entrada por SE(x+1,y+1), S(x,y+2), SW(x-1,y+1)
    { x = 0,  y = 1,  entries = { { 1, 1 }, { 0, 2 }, { -1, 1 } } },
    -- Sudoeste (x-1,y+1): entrada por S(x,y+1), SW(x-2,y+1), W(x-1,y), ou diagonal externa
    { x = -1, y = 1,  entries = { { 0, 1 }, { -2, 1 }, { -1, 2 }, { -1, 0 } } },
    -- Oeste (x-1): entrada por SW(x-1,y+1), W(x-2,y), NW(x-1,y-1)
    { x = -1, y = 0,  entries = { { -1, 1 }, { -2, 0 }, { -1, -1 } } },
    -- Noroeste (x-1,y-1): entrada por W(x-1,y), NW(x-2,y-1), N(x,y-1), ou diagonal externa
    { x = -1, y = -1, entries = { { -1, 0 }, { -2, -1 }, { -1, -2 }, { 0, -1 } } },
  }

  local count = 0

  for _, adj in ipairs(adjacentTiles) do
    local checkPos = { x = pos.x + adj.x, y = pos.y + adj.y, z = pos.z }
    local tile = g_map.getTile(checkPos)

    -- Primeiro verifica se o tile é walkable (ignora criaturas)
    if tile and tile:isWalkable(true) then
      -- Agora verifica se pelo menos uma entrada está livre
      local hasAccessibleEntry = false

      for _, entry in ipairs(adj.entries) do
        local entryX = pos.x + entry[1]
        local entryY = pos.y + entry[2]

        -- Verifica se a entrada está livre de monstros
        if not hasMonster(entryX, entryY) then
          -- Verifica também se o tile de entrada é walkable
          local entryPos = { x = entryX, y = entryY, z = pos.z }
          local entryTile = g_map.getTile(entryPos)
          if entryTile and entryTile:isWalkable(true) then
            hasAccessibleEntry = true
            break
          end
        end
      end

      if hasAccessibleEntry then
        count = count + 1
      end
    end
  end

  return count
end

-- Verifica se monstros estão ficando para trás e precisa esperar
-- Retorna true se deve parar de andar e esperar os monstros
function cavebot.avoidLostInMonsters(playerPos, monsters, minMonsters, avoidTrap)
  local safeMonsters = monsters or {}
  local safeMinMonsters = minMonsters or 2
  local safeAvoidTrap = avoidTrap or 4 -- monstros próximos suficientes para não precisar esperar

  -- Se minMonsters é 0 ou menor, desativa o avoidLost
  if safeMinMonsters <= 0 then
    return false
  end

  -- Se tem menos monstros que o mínimo, não precisa esperar
  if #safeMonsters < safeMinMonsters then
    return false
  end

  local player = g_game.getLocalPlayer()
  if not player then return false end

  local nearMonsters = 0
  local nearWalls = 0
  local lostMonsters = {}

  -- Conta monstros próximos e paredes ao redor
  for _, monster in ipairs(safeMonsters) do
    local monsterPos = monster.position
    if monsterPos and g_map.isSightClear(playerPos, monsterPos) then
      local dist = cavebot.getDistance(playerPos, monsterPos)

      -- Monstro próximo (distância <= 2)
      if dist <= 2 then
        nearMonsters = nearMonsters + 1
      end

      -- Verifica se monstro está ficando para trás baseado na direção do player
      local playerDir = player:getDirection()
      local distY = monsterPos.y - playerPos.y
      local distX = monsterPos.x - playerPos.x

      local isLost
      if g_helperCore and g_helperCore.isMonsterLost then
        isLost = g_helperCore.isMonsterLost(playerDir, distX, distY)
      else
        isLost = false
        if playerDir == North then if distY >= 4 then isLost = true end
        elseif playerDir == East then if distX <= -6 then isLost = true end
        elseif playerDir == South then if distY <= -4 then isLost = true end
        elseif playerDir == West then if distX >= 6 then isLost = true end
        end
      end

      if isLost then
        table.insert(lostMonsters, monster)
      end
    end
  end

  -- Conta paredes/tiles não walkable ao redor
  local neighbors = {
    { x = -1, y = -1 }, { x = 0, y = -1 }, { x = 1, y = -1 },
    { x = -1, y = 0 }, { x = 1, y = 0 },
    { x = -1, y = 1 }, { x = 0, y = 1 }, { x = 1, y = 1 }
  }

  for _, offset in ipairs(neighbors) do
    local checkPos = { x = playerPos.x + offset.x, y = playerPos.y + offset.y, z = playerPos.z }
    local tile = g_map.getTile(checkPos)
    if not tile or not tile:isWalkable(true) then
      nearWalls = nearWalls + 0.5
    end
  end

  -- Se já tem monstros suficientes perto, não precisa esperar
  if nearMonsters >= safeAvoidTrap then
    return false
  end

  -- Se tem muitas paredes e pelo menos um monstro perto, não precisa esperar
  if nearWalls >= safeAvoidTrap and nearMonsters > 0 then
    return false
  end

  -- Se tem monstros ficando para trás, deve esperar
  return #lostMonsters > 0
end

-- NOTA: countMonsters foi substituída por updateMonstersData() que atualiza MACHINE_UTILS
-- Mantida como wrapper para compatibilidade externa
function cavebot.countMonsters(playerPos, range)
  cavebot.updateMonstersData(playerPos, range)
  return MACHINE_UTILS.monsterCount
end

function cavebot.findNearestPosition(from, positions, extras)
  extras = extras or {}
  if g_helperCore and g_helperCore.findNearestPosition then
    local idx, dist = g_helperCore.findNearestPosition(from, positions, extras)
    local nextPath = (idx and idx > 0) and positions[idx] or nil
    return idx or 0, nextPath, dist or 999999
  end

  local prop = extras.prop or nil
  local retries = tonumber(extras.retries) or 0
  local shortestDistance = 999999
  local nextPath = nil
  local index = 0

  for i, point in ipairs(positions) do
    local currentPoint = point
    if prop ~= nil then
      currentPoint = point[prop]
    end

    local posZ = tonumber(currentPoint.z)

    if from.z == posZ then
      local p = { x = tonumber(currentPoint.x), y = tonumber(currentPoint.y), z = posZ }
      local distance = cavebot.getDistance(from, p)
      if distance < shortestDistance then
        shortestDistance = distance
        nextPath = point
        index = i

        if retries > 0 then
          return index, nextPath, distance
        end
      end
    end
  end

  return index, nextPath, shortestDistance
end

-- Função principal do walker - roda como cycleEvent a cada 25ms
function cavebot.walkerTick()
  -- ========================================================================
  -- FASE 1: VERIFICAÇÕES BÁSICAS
  -- ========================================================================

  -- Verificações básicas de estado
  if not MACHINE_STATE.isRunning then return end
  if #waypoints == 0 then
    cavebot.explorerWalkerTick()
    return
  end

  local player = g_game.getLocalPlayer()
  if not player then return end

  -- Verifica se está aguardando uma ação (Use/Rope/Shovel/mudança de floor)
  if MACHINE_STATE.actionWaitUntil > 0 then
    if os.clock() < MACHINE_STATE.actionWaitUntil then
      return                          -- Ainda esperando
    end
    MACHINE_STATE.actionWaitUntil = 0 -- Tempo esgotou, continua
  end

  -- Garante índice válido
  if MACHINE_STATE.currentIndex > #waypoints then MACHINE_STATE.currentIndex = 1 end

  local target = waypoints[MACHINE_STATE.currentIndex]
  target.x = tonumber(target.x)
  target.y = tonumber(target.y)
  target.z = tonumber(target.z)

  local playerPos = player:getPosition()

  -- ========================================================================
  -- FASE 2: ATUALIZAR DADOS DE MONSTROS (como getMonstersData do ZeroBot)
  -- ========================================================================
  cavebot.updateMonstersData(playerPos, 7)

  -- NOTA: canWalkAgain() removido daqui - delay só é aplicado na FASE 9 ao andar

  -- ========================================================================
  -- FASE 2.5: DETECTAR MUDANÇA DE FLOOR (antes do freeze detection)
  -- Isso evita que o sistema detecte "wrong_floor" logo após mudar de andar
  -- ========================================================================
  if MACHINE_STATE.lastPosition and MACHINE_STATE.lastPosition.z ~= playerPos.z then
    local nextIndex = MACHINE_STATE.currentIndex + 1
    if nextIndex > #waypoints then nextIndex = 1 end

    local nextWp = waypoints[nextIndex]
    local shouldAdvance = false

    if nextWp then
      local nextZ = tonumber(nextWp.z)
      -- Só avança se o próximo waypoint está no floor atual do player
      if nextZ == playerPos.z then
        shouldAdvance = true
      end
    end

    if shouldAdvance then
      MACHINE_STATE.currentIndex = nextIndex
      cavebot.updateListColors()
      -- Atualiza target para o novo waypoint
      target = waypoints[MACHINE_STATE.currentIndex]
      target.x = tonumber(target.x)
      target.y = tonumber(target.y)
      target.z = tonumber(target.z)
    end

    -- Reseta o freeze e atualiza posição ao mudar de floor
    MACHINE_STATE.lastFreeze = 0
    MACHINE_STATE.lastPosition = playerPos
    -- Continua sem delay - não faz return, deixa o tick continuar normalmente
  end

  -- ========================================================================
  -- FASE 3: DETECÇÃO DE FREEZE/STUCK (como HandleFreeze do ZeroBot)
  -- Passa targetPos para verificar se está em andar diferente
  -- ========================================================================
  local targetPos = { x = target.x, y = target.y, z = target.z }
  local isFrozen, freezeLevel = cavebot.updateFreezeState(playerPos, targetPos)

  if isFrozen then
    local stuckAction = cavebot.handleStuck(freezeLevel)

    if stuckAction == "restart" then
      -- Script reiniciado, próximo tick continua
      return
    elseif stuckAction == "alternate" then
      -- Tenta método alternativo (autoWalk em vez de pathfind)
      MACHINE_STATE.walkAttempts.pathfind = MACHINE_STATE.walkAttempts.maxPathfind + 1
    end
    -- "retry" e "wait" continuam normalmente
  end

  -- ========================================================================
  -- FASE 4: PROXIMITY SKIP (Anti-Backtrack) - DESATIVADO
  -- Esta lógica foi desativada porque causava problemas ao entrar em salas:
  -- Se a rota passa por uma sala (entra e sai), o sistema detectava que o
  -- player estava próximo do waypoint de saída e pulava os waypoints internos,
  -- fazendo o bot nunca entrar na sala.
  --
  -- Para reativar com segurança, seria necessário verificar se os waypoints
  -- intermediários estão "no caminho" (mesma direção geral) e não em áreas
  -- separadas como salas laterais.
  -- ========================================================================
  -- CÓDIGO ORIGINAL COMENTADO:
  --[[
  if #waypoints > 1 and MACHINE_STATE.currentIndex > 1 then
    for i = 1, 3 do
      local checkIndex = MACHINE_STATE.currentIndex + i
      -- Não permite wrap-around para o início durante proximity skip
      if checkIndex > #waypoints then
        break
      end

      local checkWpt = waypoints[checkIndex]
      local checkPos = { x = tonumber(checkWpt.x), y = tonumber(checkWpt.y), z = tonumber(checkWpt.z) }

      if checkPos.z == playerPos.z then
        local dist = cavebot.getDistance(playerPos, checkPos)
        if dist <= 3 then
          MACHINE_STATE.currentIndex = checkIndex
          MACHINE_STATE.lastFreeze = 0 -- Reset freeze ao pular
          cavebot.updateListColors()
          target = waypoints[MACHINE_STATE.currentIndex]
          target.x = tonumber(target.x)
          target.y = tonumber(target.y)
          target.z = tonumber(target.z)
          break
        end
      end
    end
  end
  --]]

  -- ========================================================================
  -- FASE 5: LÓGICA DE KILLING BOX (como killingBox do ZeroBot)
  -- ========================================================================
  if target.monsterLimit and target.monsterLimit > 0 then
    local pauseLimit = target.monsterLimit
    local resumeLimit = target.resumeLimit or 0

    -- Calcula distância ao waypoint para verificar proximidade
    local targetDx = math.abs(playerPos.x - target.x)
    local targetDy = math.abs(playerPos.y - target.y)
    local targetDz = math.abs(playerPos.z - target.z)

    -- Distância necessária para ativar killing box (mesmo critério de chegada)
    local killboxDist = 1
    if target.action == WAYPOINT_TYPE.STAND or target.action == WAYPOINT_TYPE.ACTION then
      killboxDist = 0
    elseif target.action == WAYPOINT_TYPE.NODE then
      killboxDist = defaultConfig.nodeDistance or 1
    end

    -- Só ativa killing box se estiver próximo do waypoint
    local isNearTarget = targetDx <= killboxDist and targetDy <= killboxDist and targetDz == 0

    -- Entrar no killing box
    if not MACHINE_STATE.pausedByMonsters then
      if isNearTarget and MACHINE_UTILS.monsterCount >= pauseLimit then
        -- Se monsterLimit >= 8, precisa ter 8 tiles livres ao redor para parar
        local canStop = true
        if pauseLimit >= 8 then
          local freeTiles = cavebot.countFreeTiles(playerPos)
          if freeTiles < 8 then
            canStop = false
            MACHINE_STATE.lastStatus = "Finding safe spot (" .. freeTiles .. "/8)"
            -- Não tem espaço suficiente: continua andando (vai para FASE 8)
            -- NÃO avança o index - deixa o walker continuar no mesmo waypoint
          end
        end

        if canStop then
          MACHINE_STATE.pausedByMonsters = true
          MACHINE_STATE.justExitedKillingBox = false
          MACHINE_STATE.lastStatus = "Killing Box"
          MACHINE_STATE.lastFreeze = 0 -- Reset freeze enquanto mata
          player:stopAutoWalk()
        end
      end
    else
      -- Sair do killing box
      if MACHINE_UTILS.monsterCount <= resumeLimit then
        if defaultConfig.useAutolootAfterKill and not MACHINE_STATE.justExitedKillingBox then
          if g_game.sendQuickLoot then
            scheduleEvent(function()
              pcall(function() g_game.sendQuickLoot(2) end)
            end, 200)
            MACHINE_STATE.autolootWaitUntil = os.clock() + 1.5
          end
          MACHINE_STATE.justExitedKillingBox = true
        end
        MACHINE_STATE.pausedByMonsters = false
        MACHINE_STATE.lastStatus = "Walking"
      end
    end

    if MACHINE_STATE.pausedByMonsters then
      -- No killing box: não anda, só espera (próximo tick verifica de novo)
      return
    end
  end

  if MACHINE_STATE.autolootWaitUntil > 0 then
    if os.clock() < MACHINE_STATE.autolootWaitUntil then
      MACHINE_STATE.lastStatus = "Looting"
      player:stopAutoWalk()
      return
    end
    MACHINE_STATE.autolootWaitUntil = 0
  end

  -- ========================================================================
  -- FASE 6: AVOID LOST IN MONSTERS
  -- Verifica se monstros estão ficando para trás e precisa esperar
  -- ========================================================================
  if target.monsterLimit and target.monsterLimit > 0 then
    local minMonstersToWait = defaultConfig.minMonstersToWait or 2
    local avoidTrap = defaultConfig.avoidTrap or 4
    if cavebot.avoidLostInMonsters(playerPos, MACHINE_UTILS.monsters, minMonstersToWait, avoidTrap) then
      local now = os.clock()

      -- Inicia contagem se ainda não estava esperando
      if MACHINE_STATE.lureWaitStart == 0 then
        MACHINE_STATE.lureWaitStart = now
      end

      local lureMax = (g_helperCore and g_helperCore.getCavebotLureWaitMaxTime and g_helperCore.getCavebotLureWaitMaxTime()) or MACHINE_STATE.lureWaitMaxTime
      local waitTime = now - MACHINE_STATE.lureWaitStart
      if waitTime < lureMax then
        MACHINE_STATE.lastStatus = "Waiting monsters"
        player:stopAutoWalk()
        return
      end
      -- Timeout atingido, continua andando
      MACHINE_STATE.lureWaitStart = 0
    else
      -- Não precisa esperar, reseta o contador
      MACHINE_STATE.lureWaitStart = 0
    end
  end

  -- ========================================================================
  -- FASE 7: VERIFICAR SE CHEGOU NO WAYPOINT (como isNearToContinue do ZeroBot)
  -- NOTA: Detecção de mudança de floor foi movida para FASE 2.5
  -- ========================================================================
  local dx = math.abs(playerPos.x - target.x)
  local dy = math.abs(playerPos.y - target.y)
  local dz = math.abs(playerPos.z - target.z)

  -- Distância necessária para "chegar" no waypoint
  -- STAND/ACTION: precisa estar exatamente no sqm (distância 0)
  -- NODE: usa nodeDistance configurável (padrão 1)
  -- WALK/outros: pode estar adjacente (distância 1)
  local reachDist = 1
  if target.action == WAYPOINT_TYPE.STAND or target.action == WAYPOINT_TYPE.ACTION then
    reachDist = 0
  elseif target.action == WAYPOINT_TYPE.NODE then
    reachDist = defaultConfig.nodeDistance or 1
  end

  if dx <= reachDist and dy <= reachDist and dz == 0 then
    -- CHEGOU no waypoint!
    local reachedAction = target.action

    -- ACTION: só avança o índice depois que o script terminar (feito no bloco ACTION abaixo)
    if reachedAction ~= WAYPOINT_TYPE.ACTION then
      MACHINE_STATE.currentIndex = MACHINE_STATE.currentIndex + 1
      if MACHINE_STATE.currentIndex > #waypoints then
        MACHINE_STATE.currentIndex = 1
      end
      MACHINE_STATE.lastFreeze = 0
      cavebot.updateListColors()
    end

    -- Executa ação do waypoint que acabou de chegar
    -- Node/Walk: continua direto para FASE 8 (sem return)
    -- Stand: pequeno delay
    -- Use/Rope/Shovel: delay maior para esperar ação
    -- Action: executa o script até o fim, depois avança e segue

    if reachedAction == WAYPOINT_TYPE.USE then
      if g_map then
        local tPos = { x = target.x, y = target.y, z = target.z }
        local tile = g_map.getTile(tPos)
        if tile then
          local thing = tile:getTopUseThing()
          if thing then
            g_game.use(thing)
          end
        end
      end
      MACHINE_STATE.actionWaitUntil = os.clock() + 1.0 -- Espera 1000ms
      return
    end

    if reachedAction == WAYPOINT_TYPE.ROPE then
      if g_map then
        local tPos = { x = target.x, y = target.y, z = target.z }
        local tile = g_map.getTile(tPos)
        if tile then
          local rope = cavebot.findRope()
          if rope then
            g_game.useWith(rope, tile:getTopUseThing() or tile:getTopThing() or tile)
          end
        end
      end
      MACHINE_STATE.actionWaitUntil = os.clock() + 1.0 -- Espera 1000ms
      return
    end

    if reachedAction == WAYPOINT_TYPE.SHOVEL then
      if g_map then
        local tPos = { x = target.x, y = target.y, z = target.z }
        local tile = g_map.getTile(tPos)
        if tile then
          local shovel = cavebot.findShovel()
          if shovel then
            g_game.useWith(shovel, tile:getTopUseThing() or tile:getTopThing() or tile)
          end
        end
      end
      MACHINE_STATE.actionWaitUntil = os.clock() + 1.0 -- Espera 1000ms
      return
    end

    if reachedAction == WAYPOINT_TYPE.ACTION then
      if MACHINE_STATE.actionScriptRunning then
        return
      end
      local code = target.actionScript or ""
      if code ~= "" and modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.executeScript then
        MACHINE_STATE.actionScriptRunning = true
        local scriptOk
        pcall(function()
          scriptOk = modules.game_helper.scripts.executeScript(code, function()
            MACHINE_STATE.actionScriptRunning = false
            MACHINE_STATE.currentIndex = MACHINE_STATE.currentIndex + 1
            if MACHINE_STATE.currentIndex > #waypoints then
              MACHINE_STATE.currentIndex = 1
            end
            MACHINE_STATE.lastFreeze = 0
            cavebot.updateListColors()
            MACHINE_STATE.actionWaitUntil = os.clock() + 0.5
          end)
        end)
        if scriptOk == false then
          MACHINE_STATE.actionScriptRunning = false
        end
        return
      end
      MACHINE_STATE.currentIndex = MACHINE_STATE.currentIndex + 1
      if MACHINE_STATE.currentIndex > #waypoints then
        MACHINE_STATE.currentIndex = 1
      end
      MACHINE_STATE.lastFreeze = 0
      cavebot.updateListColors()
      MACHINE_STATE.actionWaitUntil = os.clock() + 0.5
      return
    end

    -- Stand e outros: sem delay, continua direto
    -- Node e Walk: continua direto para FASE 8

    -- Node e Walk: continua direto para FASE 8 sem delay
    -- Atualiza o target para o novo waypoint
    target = waypoints[MACHINE_STATE.currentIndex]
    target.x = tonumber(target.x)
    target.y = tonumber(target.y)
    target.z = tonumber(target.z)
  end

  -- ========================================================================
  -- FASE 8: MOVIMENTAÇÃO (com sistema de tentativas como ZeroBot)
  -- ========================================================================
  target = waypoints[MACHINE_STATE.currentIndex]
  local targetPos = { x = tonumber(target.x), y = tonumber(target.y), z = tonumber(target.z) }

  -- Atualiza status
  if MACHINE_UTILS.monsterCount > 0 then
    MACHINE_STATE.lastStatus = "Kiting"
  else
    MACHINE_STATE.lastStatus = "Walking"
  end

  -- Smart Retargeting para NODE bloqueado
  local effectiveTarget = targetPos
  if target.action == WAYPOINT_TYPE.NODE then
    local tile = g_map.getTile(targetPos)
    local isBlocked = false

    if not tile or not tile:isWalkable() or tile:hasFloorChange() then
      isBlocked = true
    else
      local creatures = tile:getCreatures()
      if creatures and #creatures > 0 then
        for _, c in ipairs(creatures) do
          if c:isMonster() and not c:isDead() then
            isBlocked = true
            break
          end
        end
      end
    end

    if isBlocked then
      local neighbors = {
        { x = 0, y = -1 }, { x = 1, y = -1 }, { x = 1, y = 0 }, { x = 1, y = 1 },
        { x = 0, y = 1 }, { x = -1, y = 1 }, { x = -1, y = 0 }, { x = -1, y = -1 }
      }
      local bestDist = 99999
      local bestPos = nil

      for _, n in ipairs(neighbors) do
        local candidate = { x = targetPos.x + n.x, y = targetPos.y + n.y, z = targetPos.z }
        local cTile = g_map.getTile(candidate)
        if cTile and cTile:isWalkable() and not cTile:hasFloorChange() then
          local d = cavebot.getDistance(playerPos, candidate)
          if d < bestDist then
            bestDist = d
            bestPos = candidate
          end
        end
      end

      if bestPos then
        effectiveTarget = bestPos
      end
    end
  end

  executeWalkMovement(player, playerPos, effectiveTarget)
end

-- Inicia o walker como cycleEvent
function cavebot.startWalking()
  if walkEvent then
    removeEvent(walkEvent)
    walkEvent = nil
  end
  walkEvent = cycleEvent(cavebot.walkerTick, cavebot.getTickInterval())
end

function cavebot.getTickInterval()
  return 10
end

function cavebot.stopWalking()
  if walkEvent then
    removeEvent(walkEvent)
    walkEvent = nil
  end
  local player = g_game.getLocalPlayer()
  if player then
    player:stopAutoWalk()
  end
  g_game.stop()

  -- Reseta estados do MACHINE_STATE
  MACHINE_STATE.pausedByMonsters = false
  MACHINE_STATE.lastFreeze = 0
  MACHINE_STATE.isStuck = false
  MACHINE_STATE.autoWalkFailed = false
  MACHINE_STATE.autoWalkFailedAt = 0
  MACHINE_STATE.autoWalkSentCount = 0
  MACHINE_STATE.lastStatus = "Stopped"
end

-- ============================================================================
-- FUNÇÕES DE ACESSO PARA COMPATIBILIDADE E UI
-- ============================================================================

-- Retorna se o cavebot está habilitado
function cavebot.isEnabled()
  return MACHINE_STATE.isRunning
end

-- Retorna o índice atual
function cavebot.getCurrentIndex()
  return MACHINE_STATE.currentIndex
end

-- Retorna o status atual
function cavebot.getStatus()
  return MACHINE_STATE.lastStatus
end

-- Retorna dados de monstros
function cavebot.getMonsterData()
  return {
    count = MACHINE_UTILS.monsterCount,
    lifePercentage = MACHINE_UTILS.lifePercentage,
    monsters = MACHINE_UTILS.monsters
  }
end

-- Retorna dados de delay
function cavebot.getDelayInfo()
  local player = g_game.getLocalPlayer()
  local stepDuration = 100
  if player and player.getStepDuration then
    stepDuration = player:getStepDuration() or 100
  end
  return {
    currentDelay = MACHINE_TIMERS.currentDelay,
    ping = MACHINE_UTILS.getPing(),
    stepDuration = stepDuration
  }
end

-- Atualiza o progresso do cavebot no minimap
function cavebot.updateMinimapProgress()
  local minimapWindow = modules.game_minimap and modules.game_minimap.getMinimapWindow and
      modules.game_minimap.getMinimapWindow()
  if not minimapWindow then
    local root = g_ui.getRootWidget()
    if root then
      minimapWindow = root:recursiveGetChildById('minimapWindow')
    end
  end
  if not minimapWindow or minimapWindow:isDestroyed() then return end

  local progressLabel = minimapWindow:recursiveGetChildById('cavebotProgress')
  local minimapWidget = minimapWindow:recursiveGetChildById('minimap')
  if not minimapWidget or minimapWidget:isDestroyed() then
    if progressLabel and not progressLabel:isDestroyed() then
      progressLabel:hide()
    end
    return
  end
  local waypointMarker = minimapWidget:getChildById('currentWaypointMarker')

  if cavebot.isRecording() then
    -- Mostra "Recording" quando estiver gravando
    if progressLabel then
      progressLabel:setText(tr('Recording'))
      progressLabel:show()
    end
    if waypointMarker then
      waypointMarker:hide()
    end
  elseif MACHINE_STATE.isRunning and #waypoints > 0 then
    -- Atualiza label de progresso
    if progressLabel then
      progressLabel:setText(string.format("%d/%d", MACHINE_STATE.currentIndex, #waypoints))
      progressLabel:show()
    end

    -- Atualiza marcador do waypoint atual
    if waypointMarker and minimapWidget and minimapWidget.centerInPosition then
      local currentWp = waypoints[MACHINE_STATE.currentIndex]
      if currentWp then
        local pos = {
          x = tonumber(currentWp.x),
          y = tonumber(currentWp.y),
          z = tonumber(currentWp.z)
        }
        minimapWidget:centerInPosition(waypointMarker, pos)
        waypointMarker:show()
      else
        waypointMarker:hide()
      end
    end
  else
    if progressLabel then
      progressLabel:hide()
    end
    if waypointMarker then
      waypointMarker:hide()
    end
  end
end
