-- ===== HELPER TIMER =====
-- Modulo separado para gerenciar o Timer do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.Timer = {}

-- Variaveis locais
local rules = {} -- Array ordenado de regras
local ruleCounter = 0
local timerEnabled = false
local timerCycleEvent = nil
local TIMER_CYCLE_INTERVAL = 100 -- ms

-- ===== FUNCOES UTILITARIAS =====

-- Encontra o indice de uma regra pelo key
local function findRuleIndex(ruleKey)
  for i, rule in ipairs(rules) do
    if rule.key == ruleKey then
      return i
    end
  end
  return nil
end

-- Encontra uma regra pelo key
local function findRule(ruleKey)
  local index = findRuleIndex(ruleKey)
  if index then
    return rules[index]
  end
  return nil
end

-- Converte cooldown para milliseconds
_Helper.Timer.cooldownToMs = function(cooldown, unit)
  local value = tonumber(cooldown) or 1
  if unit == 'sec' then
    return value * 1000
  elseif unit == 'min' then
    return value * 60 * 1000
  elseif unit == 'hr' then
    return value * 60 * 60 * 1000
  end
  return value * 60 * 1000 -- default to minutes
end

-- Verifica se o player esta em PZ
_Helper.Timer.isPlayerInPz = function()
  local player = g_game.getLocalPlayer()
  if not player then return false end

  return player:isInProtectionZone()
end

-- Verifica se o player esta atacando um monstro
_Helper.Timer.isPlayerTargetingMonster = function()
  local target = g_game.getAttackingCreature()
  if not target then return false end

  -- Verifica se o target é um monstro
  return target:isMonster()
end

-- Verifica se as condições da regra são atendidas
_Helper.Timer.checkConditions = function(rule)
  -- Verifica condição "Cast if targeting monster" - só executa se estiver atacando
  if rule.targetingMonster and not _Helper.Timer.isPlayerTargetingMonster() then
    return false
  end

  local inPz = _Helper.Timer.isPlayerInPz()

  -- Se nenhuma condição PZ está definida, ignora verificação de PZ
  if not rule.inPz and not rule.inNonPz then
    return true
  end

  -- Verifica condição PZ
  if rule.inPz and inPz then
    return true
  end

  -- Verifica condição non-PZ
  if rule.inNonPz and not inPz then
    return true
  end

  return false
end

-- Verifica se o cooldown passou
_Helper.Timer.checkCooldown = function(rule)
  local now = g_clock.millis()
  local cooldownMs = _Helper.Timer.cooldownToMs(rule.cooldown, rule.unit)

  if not rule.lastExecuted then
    return true
  end

  return (now - rule.lastExecuted) >= cooldownMs
end

-- Conta itens no inventario (funciona com containers fechados)
_Helper.Timer.getItemCount = function(itemId)
  local player = g_game.getLocalPlayer()
  if not player then return 0 end

  -- getInventoryCount funciona com containers fechados (igual potions/runes)
  return player:getInventoryCount(itemId, 0) or 0
end

-- ===== FUNCOES DE EXECUCAO =====

-- Executa regra de words
_Helper.Timer.executeWords = function(rule)
  if not rule.value or rule.value == '' then return false end

  local player = g_game.getLocalPlayer()
  if not player then return false end

  g_game.talk(rule.value)
  return true
end

-- Executa regra de item
_Helper.Timer.executeItem = function(rule)
  if not rule.itemId then return false end

  local player = g_game.getLocalPlayer()
  if not player then return false end

  -- Verifica se count > 0
  local count = _Helper.Timer.getItemCount(rule.itemId)
  if count <= 0 then
    return false
  end

  -- Armazena count antes do uso (para forceDecrease check)
  rule.lastItemCount = count

  -- Usa o item do inventario
  g_game.useInventoryItem(rule.itemId)
  return true
end

-- Executa uma regra
local FORCE_DECREASE_RETRY_INTERVAL = 1000 -- 1 segundo entre tentativas

_Helper.Timer.executeRule = function(rule)
  if not rule or not rule.enabled then return false end

  -- Verifica condições (PZ/non-PZ)
  if not _Helper.Timer.checkConditions(rule) then
    return false
  end

  -- Para regras de item com forceDecrease, verifica se estamos aguardando confirmação
  if rule.type == 'item' and rule.forceDecrease and rule.pendingForceDecrease then
    local currentCount = _Helper.Timer.getItemCount(rule.itemId)
    if currentCount < rule.lastItemCount then
      -- Count diminuiu! Ação foi confirmada, agora definimos lastExecuted
      rule.lastExecuted = g_clock.millis()
      rule.pendingForceDecrease = false
      rule.lastItemCount = nil
      rule.lastRetryTime = nil
      return true
    else
      -- Ainda aguardando count diminuir, tenta usar novamente a cada 1 segundo
      local now = g_clock.millis()
      if not rule.lastRetryTime or (now - rule.lastRetryTime) >= FORCE_DECREASE_RETRY_INTERVAL then
        rule.lastRetryTime = now
        -- Tenta usar o item novamente
        _Helper.Timer.executeItem(rule)
      end
      return false
    end
  end

  -- Verifica cooldown (somente se não estamos aguardando forceDecrease)
  if not _Helper.Timer.checkCooldown(rule) then
    return false
  end

  local success = false

  if rule.type == 'words' then
    success = _Helper.Timer.executeWords(rule)
    if success then
      rule.lastExecuted = g_clock.millis()
    end
  elseif rule.type == 'item' then
    success = _Helper.Timer.executeItem(rule)
    if success then
      if rule.forceDecrease then
        -- Com forceDecrease, não define lastExecuted agora
        -- Aguarda confirmação de que o count diminuiu
        rule.pendingForceDecrease = true
        rule.lastRetryTime = g_clock.millis()
      else
        -- Sem forceDecrease, define lastExecuted imediatamente
        rule.lastExecuted = g_clock.millis()
      end
    end
  end

  return success
end

-- ===== CYCLE EVENT SYSTEM =====

-- Funcao do cycle event
local function timerCycleFunction()
  -- Verifica se helper esta habilitado
  local helperEnabled = _Helper.isHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled()
  if not helperEnabled then
    return
  end

  -- Verifica se timer esta habilitado (shortcut toggle)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig and helperConfig.timerEnabled == false then
    return
  end

  -- Verifica se player esta conectado
  if not g_game.isOnline() then
    return
  end

  -- Executa todas as regras habilitadas (em ordem)
  for _, rule in ipairs(rules) do
    if rule.enabled then
      _Helper.Timer.executeRule(rule)
    end
  end
end

-- Para o cycle event
_Helper.Timer.stopCycle = function()
  if timerCycleEvent then
    removeEvent(timerCycleEvent)
    timerCycleEvent = nil
  end
  timerEnabled = false
end

-- Inicia o cycle event
_Helper.Timer.startCycle = function()
  -- Ja esta rodando
  if timerCycleEvent then return end

  timerEnabled = true
  timerCycleEvent = cycleEvent(timerCycleFunction, TIMER_CYCLE_INTERVAL)
end

-- ===== GERENCIAMENTO DE REGRAS =====

-- Adiciona uma regra
_Helper.Timer.addRule = function(ruleData)
  ruleCounter = ruleCounter + 1
  local ruleKey = 'rule_' .. ruleCounter

  local rule = {
    key = ruleKey,
    type = ruleData.type,
    value = ruleData.value,
    itemId = ruleData.itemId,
    cooldown = ruleData.cooldown,
    unit = ruleData.unit,
    forceDecrease = ruleData.forceDecrease,
    inPz = ruleData.inPz,
    inNonPz = ruleData.inNonPz,
    targetingMonster = ruleData.targetingMonster,
    enabled = true,
    lastExecuted = nil,
    lastItemCount = nil
  }

  table.insert(rules, rule)
  return ruleKey, rule
end

-- Atualiza uma regra existente
_Helper.Timer.updateRule = function(ruleKey, ruleData)
  local rule = findRule(ruleKey)
  if not rule then return false end

  rule.type = ruleData.type
  rule.value = ruleData.value
  rule.itemId = ruleData.itemId
  rule.cooldown = ruleData.cooldown
  rule.unit = ruleData.unit
  rule.forceDecrease = ruleData.forceDecrease
  rule.inPz = ruleData.inPz
  rule.inNonPz = ruleData.inNonPz
  rule.targetingMonster = ruleData.targetingMonster

  return true
end

-- Remove uma regra
_Helper.Timer.removeRule = function(ruleKey)
  local index = findRuleIndex(ruleKey)
  if index then
    table.remove(rules, index)
    return true
  end
  return false
end

-- Habilita/desabilita uma regra
_Helper.Timer.toggleRule = function(ruleKey, enabled)
  local rule = findRule(ruleKey)
  if rule then
    rule.enabled = enabled
    return true
  end
  return false
end

-- Retorna uma regra
_Helper.Timer.getRule = function(ruleKey)
  return findRule(ruleKey)
end

-- Retorna todas as regras (array ordenado)
_Helper.Timer.getRules = function()
  return rules
end

-- Limpa todas as regras
_Helper.Timer.clearRules = function()
  rules = {}
  ruleCounter = 0
end

-- Move uma regra para cima
_Helper.Timer.moveRuleUp = function(ruleKey)
  local index = findRuleIndex(ruleKey)
  if index and index > 1 then
    rules[index], rules[index - 1] = rules[index - 1], rules[index]
    return true
  end
  return false
end

-- Move uma regra para baixo
_Helper.Timer.moveRuleDown = function(ruleKey)
  local index = findRuleIndex(ruleKey)
  if index and index < #rules then
    rules[index], rules[index + 1] = rules[index + 1], rules[index]
    return true
  end
  return false
end

-- ===== LIFECYCLE =====

-- Chamado no login
_Helper.Timer.onLogin = function()
  _Helper.Timer.startCycle()
end

-- Chamado no logout
_Helper.Timer.onLogout = function()
  _Helper.Timer.stopCycle()
end

-- Verifica se o timer esta ativo
_Helper.Timer.isEnabled = function()
  return timerEnabled
end

-- Toggle do timer
_Helper.Timer.toggle = function()
  if timerEnabled then
    _Helper.Timer.stopCycle()
  else
    _Helper.Timer.startCycle()
  end
  return timerEnabled
end

-- ===== PERSISTENCIA =====

-- Salva configuracao para ser armazenada (mantendo ordem)
_Helper.Timer.saveConfig = function()
  local savedRules = {}

  for _, rule in ipairs(rules) do
    table.insert(savedRules, {
      key = rule.key,
      type = rule.type,
      value = rule.value,
      itemId = rule.itemId,
      cooldown = rule.cooldown,
      unit = rule.unit,
      forceDecrease = rule.forceDecrease,
      inPz = rule.inPz,
      inNonPz = rule.inNonPz,
      targetingMonster = rule.targetingMonster,
      enabled = rule.enabled
    })
  end

  return {
    rules = savedRules,
    ruleCounter = ruleCounter
  }
end

-- Mirror into the shared `modules` namespace so test code (running outside
-- this sandbox) can reach and optionally stub dispatched helpers.
modules.game_helper = modules.game_helper or {}
modules.game_helper.timer = _Helper.Timer

-- Carrega configuracao salva
_Helper.Timer.loadConfig = function(savedConfig)
  if not savedConfig then return end

  -- Limpa regras atuais
  rules = {}
  ruleCounter = savedConfig.ruleCounter or 0

  -- Carrega regras salvas (mantendo ordem)
  if savedConfig.rules then
    for _, savedRule in ipairs(savedConfig.rules) do
      local rule = {
        key = savedRule.key,
        type = savedRule.type,
        value = savedRule.value,
        itemId = savedRule.itemId,
        cooldown = savedRule.cooldown,
        unit = savedRule.unit,
        forceDecrease = savedRule.forceDecrease,
        inPz = savedRule.inPz,
        inNonPz = savedRule.inNonPz,
        targetingMonster = savedRule.targetingMonster,
        enabled = savedRule.enabled ~= false, -- default true
        lastExecuted = nil,
        lastItemCount = nil
      }
      table.insert(rules, rule)
    end
  end
end
