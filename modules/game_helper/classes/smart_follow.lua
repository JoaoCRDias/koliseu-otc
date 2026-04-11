-- ===== HELPER SMART FOLLOW =====
-- Follow inteligente baseado em autoWalk via onCreaturePositionChange
-- Nao usa g_game.follow() (que e cancelado por g_game.attack())
-- Usa autoWalk(adjPos) para seguir no mesmo andar (para 1 sqm do target)
-- Usa autoWalk(oldPos) para seguir entre andares (escada/hole)
-- Usa autoWalk(lastKnownTargetPos) quando perde de vista
-- Cancela walk em progresso para redirecionar imediatamente
-- Alvo: qualquer criatura em follow (sem exigir party)
-- Estado mantido apenas em memoria (nao persiste em arquivo)
-- Hotkey persiste via helperConfig em helper.json

if not _Helper then
  _Helper = {}
end

_Helper.SmartFollow = {}

-- Debug no terminal: _Helper.SmartFollow.setDebugLog(true) na consola Lua (por defeito desligado)
local smartFollowLog = { enabled = false }
local logThrottle = {}

local function slog(fmt, ...)
  if not smartFollowLog.enabled or not g_logger then
    return
  end
  local ok, msg = pcall(string.format, fmt, ...)
  if ok then
    g_logger.info("[smart_follow] " .. msg)
  else
    g_logger.info("[smart_follow] " .. tostring(fmt))
  end
end

local function slogEvery(key, intervalMs, fmt, ...)
  if not smartFollowLog.enabled or not g_logger then
    return
  end
  local now = g_clock.millis()
  if (logThrottle[key] or 0) + intervalMs > now then
    return
  end
  logThrottle[key] = now
  slog(fmt, ...)
end

-- ===== ESTADO EM MEMORIA =====

local enabled = false
local targetCreature = nil     -- referencia direta ao creature
local targetCreatureId = nil   -- id do servidor (mais fiavel que nome)
local targetCreatureName = nil -- nome para fallback (busca por nome)
local lastKnownTargetPos = nil -- ultima posicao conhecida do target
local targetVisible = false    -- flag para detectar transicao visivel -> perdeu de vista
local isLoadingUI = false
local cycleEvt = nil
local CYCLE_INTERVAL = 100       -- ciclo de fallback (ms)
local VISIBLE_CYCLE_COOLDOWN = 300 -- cooldown do ciclo quando target visivel (ms)
local LOST_SIGHT_COOLDOWN = 500    -- cooldown para autowalk quando perdeu de vista (ms)
local lastCycleWalkAttempt = 0     -- timestamp da ultima tentativa de autowalk (ciclo, target visivel)
local lastAutoWalkAttempt = 0      -- timestamp da ultima tentativa de autowalk (lost-sight)

-- ===== FUNCOES INTERNAS =====

local MAX_EXTRA_DISTANCE = 3  -- tenta ate +3 sqm alem do adjacente (1..4 sqm do target)
local PATHFIND_MAX_COMPLEXITY = 40000
-- NotSeen(1)+Creatures(2)+NonPathable(4)+IgnoreCreatures(16): sem 16 o findPath falha
-- quando o tile objectivo tem criatura (comum ao seguir junto a mobs/players).
local PATHFIND_FLAGS = 23
if PathFindFlags then
  local ig = PathFindFlags.IgnoreCreatures or 16
  PATHFIND_FLAGS = PathFindFlags.AllowNullTiles + PathFindFlags.AllowCreatures + PathFindFlags.AllowNonPathable + ig
end

-- 8 direcoes ao redor do target (N, E, S, W, NE, SE, SW, NW)
local DIR_OFFSETS = {
  {0,-1}, {1,0}, {0,1}, {-1,0},
  {1,-1}, {1,1}, {-1,1}, {-1,-1}
}

-- Tenta autoWalk para posicao proxima ao target
-- Para cada distancia (1..4 sqm), testa TODAS as 8 direcoes ao redor do target
-- Ordena por proximidade ao player e usa g_map.findPath sincrono para validar
-- So chama autoWalk na primeira posicao com path valido (evita "There is no way.")
local function tryAutoWalkToTarget(localPlayer, targetPos, playerPos, reason)
  local currentDist = math.max(math.abs(playerPos.x - targetPos.x), math.abs(playerPos.y - targetPos.y))
  if currentDist <= 1 then
    slogEvery("walk_adjacent", 2000, "tryAutoWalk: ja adjacente (dist=%d) [%s]", currentDist, reason or "?")
    return true
  end

  local maxDist = math.min(1 + MAX_EXTRA_DISTANCE, currentDist - 1)
  for dist = 1, maxDist do
    -- Gera candidatos em todas as 8 direcoes a 'dist' sqm do target
    local candidates = {}
    for _, off in ipairs(DIR_OFFSETS) do
      local cx = targetPos.x + off[1] * dist
      local cy = targetPos.y + off[2] * dist
      local pdist = math.max(math.abs(playerPos.x - cx), math.abs(playerPos.y - cy))
      candidates[#candidates + 1] = { x = cx, y = cy, pdist = pdist }
    end
    -- Prioriza posicoes mais proximas do player (path mais curto)
    table.sort(candidates, function(a, b) return a.pdist < b.pdist end)

    for _, c in ipairs(candidates) do
      local pos = { x = c.x, y = c.y, z = targetPos.z }
      -- Rejeita tiles com floor-change (escada/hole)
      local tile = g_map.getTile(pos)
      if tile and not tile:hasFloorChange() then
        local ok, dirs = pcall(g_map.findPath, playerPos, pos, PATHFIND_MAX_COMPLEXITY, PATHFIND_FLAGS)
        if ok and dirs and #dirs > 0 then
          slog("tryAutoWalk OK [%s] -> dest %d,%d,%d steps=%d flags=%d", reason or "?", pos.x, pos.y, pos.z, #dirs, PATHFIND_FLAGS)
          localPlayer:autoWalk(pos, false, false)
          return true
        elseif not ok then
          slogEvery("findpath_err", 1000, "findPath pcall falhou [%s]: %s", reason or "?", tostring(dirs))
        end
      elseif tile and tile:hasFloorChange() then
        slogEvery("skip_floor", 1500, "candidato ignorado (floorChange) %d,%d,%d [%s]", pos.x, pos.y, pos.z, reason or "?")
      end
    end
  end
  slogEvery("walk_fail", 800, "tryAutoWalk SEM caminho [%s] player %d,%d,%d -> target %d,%d,%d maxDist=%d flags=%d",
    reason or "?",
    playerPos.x, playerPos.y, playerPos.z,
    targetPos.x, targetPos.y, targetPos.z,
    maxDist,
    PATHFIND_FLAGS)
  return false
end

-- Busca creature por nome nos spectators visiveis
local function findCreatureByName(name)
  if not name or name == "" then return nil end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return nil end

  local spectators = g_map.getSpectators(localPlayer:getPosition(), false)
  if not spectators then return nil end

  for _, creature in ipairs(spectators) do
    if creature:getName() == name and not creature:isLocalPlayer() then
      return creature
    end
  end
  return nil
end

local function resolveTargetCreature()
  if targetCreatureId and targetCreatureId ~= 0 then
    local byId = g_map.getCreatureById(targetCreatureId)
    if byId and not byId:isLocalPlayer() then
      return byId
    end
  end
  if targetCreatureName and targetCreatureName ~= "" then
    return findCreatureByName(targetCreatureName)
  end
  return nil
end

local function isOurFollowTarget(creature)
  if not creature or creature:isLocalPlayer() then return false end
  if targetCreatureId and targetCreatureId ~= 0 and creature:getId() == targetCreatureId then
    return true
  end
  if targetCreatureName and creature:getName() == targetCreatureName then
    return true
  end
  return false
end

-- Pisar no sqm do lider: so em portal/escada/teleport-item, ou quando o follow nativo ja caiu (ir atras do ultimo sqm)
local function tileWantsStepOnto(pos)
  if not pos then return false end
  local tile = g_map.getTile(pos)
  if not tile then return false end
  if tile:hasFloorChange() then return true end
  local okEl, elevated = pcall(function() return tile:hasElevation(3) end)
  if okEl and elevated then return true end
  local items = tile:getItems()
  if items then
    for _, item in ipairs(items) do
      if item.getTeleportDestination then
        local okD, dest = pcall(function() return item:getTeleportDestination() end)
        if okD and dest and dest.x and dest.y and dest.z ~= nil then
          return true
        end
      end
    end
  end
  return false
end

local function nativeFollowingOurTarget()
  local f = g_game.getFollowingCreature()
  return f and not f:isLocalPlayer() and isOurFollowTarget(f)
end

-- Forward declaration
local smartFollowCheck

-- Inicia o ciclo periodico
local function startCycle()
  if cycleEvt then return end
  cycleEvt = cycleEvent(smartFollowCheck, CYCLE_INTERVAL)
  slog("startCycle interval=%dms", CYCLE_INTERVAL)
end

-- Para o ciclo periodico
local function stopCycle()
  if cycleEvt then
    removeEvent(cycleEvt)
    cycleEvt = nil
    slog("stopCycle")
  end
end

-- Ciclo periodico
smartFollowCheck = function()
  if not enabled then
    slogEvery("cycle_disabled", 3000, "cycle: ignorado (smart follow desligado)")
    return
  end
  if not g_game.isOnline() then
    slogEvery("cycle_offline", 3000, "cycle: ignorado (offline)")
    return
  end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    slogEvery("cycle_noplayer", 3000, "cycle: sem LocalPlayer")
    return
  end
  local playerPos = localPlayer:getPosition()
  if not playerPos then
    slogEvery("cycle_nopos", 3000, "cycle: sem posicao do jogador")
    return
  end

  -- Segue o alvo nativo do cliente (g_game.follow) se mudou
  local following = g_game.getFollowingCreature()
  if following and not following:isLocalPlayer() then
    local fid = following:getId()
    local fname = following:getName()
    if fname and fname ~= "" then
      if not targetCreatureId or fid ~= targetCreatureId or fname ~= targetCreatureName then
        slog("cycle: sync getFollowingCreature id=%d name=%s", fid, fname)
        _Helper.SmartFollow.setTarget(following)
      end
    end
  else
    slogEvery("cycle_nofollowing", 2000, "cycle: getFollowingCreature()=nil (follow nativo pode nao estar activo)")
  end

  if (not targetCreatureName or targetCreatureName == "") and (not targetCreatureId or targetCreatureId == 0) then
    slogEvery("cycle_notarget", 1200, "cycle: sem alvo interno (define alvo com follow ou Set Key)")
    return
  end

  -- Target visivel? Sempre atualizar posicao, independente de estar andando
  local found = resolveTargetCreature()
  if found then
    targetVisible = true
    targetCreature = found
    local targetPos = found:getPosition()
    if targetPos then
      lastKnownTargetPos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
    end
    -- autoWalk com cooldown no ciclo (evento ja reage imediato)
    local now = g_clock.millis()
    if now - lastCycleWalkAttempt >= VISIBLE_CYCLE_COOLDOWN and targetPos and playerPos.z == targetPos.z then
      local dx = math.abs(playerPos.x - targetPos.x)
      local dy = math.abs(playerPos.y - targetPos.y)
      if dx == 0 and dy == 0 then
        -- ja no sqm do alvo
      elseif dx <= 1 and dy <= 1 then
        local stepOnto = not nativeFollowingOurTarget() or tileWantsStepOnto(targetPos)
        if stepOnto then
          lastCycleWalkAttempt = now
          slogEvery("cycle_adj_tile", 800, "cycle: adjacente -> autoWalk tile alvo %d,%d,%d", targetPos.x, targetPos.y, targetPos.z)
          localPlayer:autoWalk(targetPos, false, false)
        end
      else
        lastCycleWalkAttempt = now
        tryAutoWalkToTarget(localPlayer, targetPos, playerPos, "cycle")
      end
    end
    return
  end

  -- Target nao visivel - detectar transicao
  if targetVisible then
    targetVisible = false
    slog("alvo perdeu-se da vista; lastKnown=%s", lastKnownTargetPos and string.format("%d,%d,%d", lastKnownTargetPos.x, lastKnownTargetPos.y, lastKnownTargetPos.z) or "nil")
  end

  -- autowalk ate a ultima posicao conhecida (teleporte / sumiu antes de tu chegares)
  if lastKnownTargetPos then
    local now = g_clock.millis()
    if now - lastAutoWalkAttempt >= LOST_SIGHT_COOLDOWN then
      lastAutoWalkAttempt = now
      local lx, ly, lz = lastKnownTargetPos.x, lastKnownTargetPos.y, lastKnownTargetPos.z
      if playerPos.z ~= lz then
        slog("lostSight autoWalk (outro andar) -> %d,%d,%d", lx, ly, lz)
        localPlayer:autoWalk(lastKnownTargetPos, false, false)
      else
        local dx = math.abs(playerPos.x - lx)
        local dy = math.abs(playerPos.y - ly)
        if dx == 0 and dy == 0 then
          -- ja no ultimo sqm conhecido
        elseif dx <= 1 and dy <= 1 then
          -- adjacente ao portal/ultimo passo: entrar no tile exacto
          slog("lostSight autoWalk tile exact (adjacente) -> %d,%d,%d", lx, ly, lz)
          localPlayer:autoWalk(lastKnownTargetPos, false, false)
        elseif tryAutoWalkToTarget(localPlayer, lastKnownTargetPos, playerPos, "lostSight") then
          slog("lostSight tryAutoWalkToTarget OK -> %d,%d,%d", lx, ly, lz)
        else
          slog("lostSight autoWalk tile exact (fallback) -> %d,%d,%d", lx, ly, lz)
          localPlayer:autoWalk(lastKnownTargetPos, false, false)
        end
      end
    end
  end
end

-- ===== FUNCOES PUBLICAS =====

-- Executa o toggle real do smart follow
local function doSmartFollowToggle(checked)
  -- Bloqueio mútuo: ao ligar smart follow, desligar cavebot
  if checked then
    if modules.game_helper and modules.game_helper.cavebot then
      if modules.game_helper.cavebot.isEnabled() then
        modules.game_helper.cavebot.doToggle(false)
      end
    end
  end

  enabled = checked
  slog("toggle enabled=%s PATHFIND_FLAGS=%d", tostring(checked), PATHFIND_FLAGS)

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    pcall(function()
      protocolGame:sendExtendedOpcode(ExtendedIds.SmartFollow, checked and "1" or "0")
    end)
  end

  -- Sync shortcut panel button
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutFollow', checked)
  end

  if not checked then
    _Helper.SmartFollow.clearTarget()
  else
    lastAutoWalkAttempt = 0
    startCycle()
    smartFollowCheck()
  end
end

-- Toggle para habilitar/desabilitar o smart follow
_Helper.SmartFollow.toggle = function(checked)
  if isLoadingUI then
    slog("toggle ignorado (isLoadingUI)")
    return
  end

  -- Ao ativar, mostra aviso de checagem (se ainda não foi ocultado)
  if checked and _Helper.showToolWarning then
    slog("toggle: a abrir showToolWarning (confirmar para activar)")
    _Helper.showToolWarning(
      function()
        doSmartFollowToggle(checked)
      end,
      function()
        slog("toggle: utilizador cancelou o aviso do tools")
        -- Cancelou: reverter checkbox para desmarcado
        isLoadingUI = true
        local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
        if toolsPanel then
          local cb = toolsPanel:recursiveGetChildById("smartFollow")
          if cb then cb:setChecked(false) end
        end
        isLoadingUI = false
      end
    )
  else
    doSmartFollowToggle(checked)
  end
end

-- Retorna se esta habilitado
_Helper.SmartFollow.isEnabled = function()
  return enabled
end

_Helper.SmartFollow.setDebugLog = function(on)
  smartFollowLog.enabled = on and true or false
  if g_logger then
    g_logger.info("[smart_follow] debug log " .. (smartFollowLog.enabled and "ON" or "OFF"))
  end
end

_Helper.SmartFollow.isDebugLogEnabled = function()
  return smartFollowLog.enabled
end

-- Captura o creature alvo quando o player usa follow
-- Sempre captura, independente de enabled (player pode ativar depois)
_Helper.SmartFollow.setTarget = function(creature)
  if not creature or creature:isLocalPlayer() then
    slog("setTarget ignorado (nil ou local player)")
    return
  end

  targetCreature = creature
  targetCreatureId = creature:getId()
  targetCreatureName = creature:getName()
  targetVisible = true
  local pos = creature:getPosition()
  if pos then
    lastKnownTargetPos = { x = pos.x, y = pos.y, z = pos.z }
  end
  lastAutoWalkAttempt = 0

  slog("setTarget id=%d name=%s pos=%s enabled=%s", targetCreatureId, tostring(targetCreatureName),
    pos and string.format("%d,%d,%d", pos.x, pos.y, pos.z) or "nil", tostring(enabled))

  if enabled then
    startCycle()
  end
end

-- Follow nativo cancelado (teleporte / sumiu da tela): mantem id, nome e ultima posicao para ir ao ultimo sqm
_Helper.SmartFollow.onNativeFollowLost = function()
  if not enabled then
    _Helper.SmartFollow.clearTarget()
    return
  end
  slog("onNativeFollowLost: mantem lastKnown=%s id=%s name=%s",
    lastKnownTargetPos and string.format("%d,%d,%d", lastKnownTargetPos.x, lastKnownTargetPos.y, lastKnownTargetPos.z) or "nil",
    targetCreatureId and tostring(targetCreatureId) or "nil",
    targetCreatureName and tostring(targetCreatureName) or "nil")
  targetCreature = nil
  targetVisible = false
  lastAutoWalkAttempt = 0
  startCycle()
end

-- Limpa o target (smart follow OFF, logout, load UI, reset checkbox)
_Helper.SmartFollow.clearTarget = function()
  slog("clearTarget")
  stopCycle()
  targetCreature = nil
  targetCreatureId = nil
  targetCreatureName = nil
  targetVisible = false
  lastKnownTargetPos = nil
end

-- Retorna o creature alvo atual
_Helper.SmartFollow.getTarget = function()
  return targetCreature
end

-- Retorna o nome do creature alvo atual
_Helper.SmartFollow.getTargetName = function()
  return targetCreatureName
end

-- ===== EVENTO PRINCIPAL: onCreaturePositionChange =====
-- Conectado ao Creature (todas as criaturas) - filtra pelo target
-- Mesmo andar: autoWalk IMEDIATO para posicao adjacente ao target
-- Mudou de andar: autoWalk(oldPos) IMEDIATO (redirecionamento para escada)
_Helper.SmartFollow.onCreaturePositionChange = function(creature, newPos, oldPos)
  if not enabled then return end
  if (not targetCreatureName or targetCreatureName == "") and (not targetCreatureId or targetCreatureId == 0) then
    return
  end
  if not creature or creature:isLocalPlayer() then return end
  if not newPos or not oldPos then return end
  if not isOurFollowTarget(creature) then return end
  if not g_game.isOnline() then return end

  slog("onCreaturePositionChange id=%d %d,%d,%d -> %d,%d,%d", creature:getId(), oldPos.x, oldPos.y, oldPos.z, newPos.x, newPos.y, newPos.z)

  targetCreature = creature
  targetVisible = true
  -- Ultimo quadrado onde o alvo esta (newPos); oldPos e so para autoWalk a escadas/teleport no mesmo passo
  lastKnownTargetPos = { x = newPos.x, y = newPos.y, z = newPos.z }

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  local playerPos = localPlayer:getPosition()
  if not playerPos then return end

  if newPos.z ~= oldPos.z then
    -- MUDOU DE ANDAR: autoWalk ate oldPos (escada/hole) - IMEDIATO
    if playerPos.z == oldPos.z then
      lastAutoWalkAttempt = g_clock.millis()
      slog("floor change: autoWalk oldPos %d,%d,%d", oldPos.x, oldPos.y, oldPos.z)
      localPlayer:autoWalk(oldPos, false, false)
    else
      slog("floor change: player z=%d != old z=%d (sem autoWalk oldPos)", playerPos.z, oldPos.z)
    end
  else
    -- MESMO ANDAR: autoWalk IMEDIATO para posicao adjacente ao target
    -- Se nao conseguir 1 sqm, tenta +1, +2... ate achar path
    if playerPos.z == newPos.z then
      local dx = math.abs(playerPos.x - newPos.x)
      local dy = math.abs(playerPos.y - newPos.y)
      if dx == 0 and dy == 0 then
        -- mesmo sqm
      elseif dx <= 1 and dy <= 1 then
        local stepOnto = not nativeFollowingOurTarget() or tileWantsStepOnto(newPos)
        if stepOnto then
          slog("onCreaturePositionChange: adjacente -> autoWalk tile alvo %d,%d,%d", newPos.x, newPos.y, newPos.z)
          localPlayer:autoWalk(newPos, false, false)
        else
          slogEvery("pos_same_floor_close", 1500, "onCreaturePositionChange: ja perto (dx=%d dy=%d)", dx, dy)
        end
      else
        tryAutoWalkToTarget(localPlayer, newPos, playerPos, "creatureMove")
      end
    else
      slog("onCreaturePositionChange: z jogador %d != z alvo %d", playerPos.z, newPos.z)
    end
  end
end

-- Chamada quando o LOCAL PLAYER muda de posicao
-- Apos mudar de andar, reset cooldown e check imediato
_Helper.SmartFollow.onLocalPlayerPositionChange = function(creature, newPos, oldPos)
  if not enabled then return end
  if (not targetCreatureName or targetCreatureName == "") and (not targetCreatureId or targetCreatureId == 0) then
    return
  end
  if not newPos or not oldPos then return end
  if not g_game.isOnline() then return end

  if newPos.z ~= oldPos.z then
    slog("localPlayer mudou de andar %d,%d,%d -> %d,%d,%d", oldPos.x, oldPos.y, oldPos.z, newPos.x, newPos.y, newPos.z)
    lastAutoWalkAttempt = 0
    scheduleEvent(function()
      if not enabled then return end
      if not g_game.isOnline() then return end
      smartFollowCheck()
    end, 300)
  end
end

-- Reset do checkbox no UI
_Helper.SmartFollow.resetCheckbox = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  isLoadingUI = true
  local checkbox = toolsPanel:recursiveGetChildById("smartFollow")
  if checkbox then
    checkbox:setChecked(false)
  end
  isLoadingUI = false

  _Helper.SmartFollow.clearTarget()
  enabled = false

  -- Sync shortcut panel button
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutFollow', false)
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    pcall(function()
      protocolGame:sendExtendedOpcode(ExtendedIds.SmartFollow, "0")
    end)
  end
end

-- Carrega estado no UI (como nao persiste, so reseta)
_Helper.SmartFollow.loadToUI = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  isLoadingUI = true
  local checkbox = toolsPanel:recursiveGetChildById("smartFollow")
  if checkbox then
    checkbox:setChecked(false)
  end
  isLoadingUI = false

  _Helper.SmartFollow.clearTarget()
  enabled = false
end

-- Cleanup ao deslogar
_Helper.SmartFollow.onLogout = function()
  stopCycle()
  enabled = false
  targetCreature = nil
  targetCreatureId = nil
  targetCreatureName = nil
  targetVisible = false
  lastKnownTargetPos = nil
  lastAutoWalkAttempt = 0
end

-- ===== FIM HELPER SMART FOLLOW =====
