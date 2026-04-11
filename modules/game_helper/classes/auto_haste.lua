-- ===== HELPER AUTO HASTE =====
-- Modulo separado para gerenciar o Auto Haste do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.AutoHaste = {}

-- Variavel local para controle do ultimo cast de haste
local lastHaste = 0

-- Cycle event para tentar castar haste
local hasteCycleEvent = nil
local HASTE_CYCLE_INTERVAL = 500 -- ms

-- ===== FUNCOES DO AUTO HASTE =====

-- Toggle para habilitar/desabilitar o Auto Haste
_Helper.AutoHaste.toggle = function(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.haste or not helperConfig.haste[1] then
    return false
  end

  -- GUARD: Cannot enable Auto Haste without a spell selected
  if checked and helperConfig.haste[1].id == 0 then
    -- No spell selected, reject the enable and show message
    modules.game_textmessage.displayFailureMessage(tr("Select a haste spell first!"))
    -- Uncheck the checkbox in UI
    local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
    if toolsPanel then
      local enableHaste = toolsPanel:recursiveGetChildById("enableHaste0")
      if enableHaste then
        enableHaste:setChecked(false)
      end
    end
    -- Sync shortcut panel to unchecked
    if _Helper.Shortcut and _Helper.Shortcut.syncButton then
      _Helper.Shortcut.syncButton('shortcutHaste', false)
    end
    return false
  end

  helperConfig.haste[1].enabled = checked

  -- Sincronizar com shortcut panel
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutHaste', checked)
  end
  -- Iniciar ou parar o cycle event baseado no estado
  if checked then
    -- Ligou: verificar se precisa iniciar o cycle
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and (not localPlayer.hasState or not localPlayer:hasState(PlayerStates.Haste)) then
      _Helper.AutoHaste.startCycle()
    end
  else
    -- Desligou: parar o cycle
    _Helper.AutoHaste.stopCycle()
  end
  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
  return true
end

-- Toggle para habilitar/desabilitar cast em PZ
_Helper.AutoHaste.togglePz = function(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig and helperConfig.haste and helperConfig.haste[1] then
    helperConfig.haste[1].safecast = checked
  end

  -- Verificar se precisa iniciar/parar o cycle baseado no estado de PZ
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local isInPz = localPlayer:isInProtectionZone()
  local hasHaste = localPlayer.hasState and localPlayer:hasState(PlayerStates.Haste)
  local isEnabled = helperConfig and helperConfig.haste and helperConfig.haste[1] and helperConfig.haste[1].enabled

  if checked and isInPz and isEnabled and not hasHaste then
    -- Ligou PZ Cast, esta em PZ, auto haste habilitado e sem haste: iniciar cycle
    _Helper.AutoHaste.startCycle()
  elseif not checked and isInPz then
    -- Desligou PZ Cast e esta em PZ: parar cycle (nao pode castar em PZ)
    _Helper.AutoHaste.stopCycle()
  end
end

-- Funcao principal que verifica e executa o auto haste
_Helper.AutoHaste.check = function()
  local helperAutomaticFunctionsEnabled = _Helper.isHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled()
  if not helperAutomaticFunctionsEnabled then
    return
  end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return true
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.haste or not helperConfig.haste[1] then
    return true
  end

  if helperConfig.haste[1].id == 0 then
    return true
  end

  if not helperConfig.haste[1].enabled then
    return true
  end

  if not helperConfig.haste[1].safecast and localPlayer:isInProtectionZone() then
    return true
  end

  local spellId = helperConfig.haste[1].id
  local getSpellDataById = _Helper.getSpellDataById and _Helper.getSpellDataById
  local spell = getSpellDataById and getSpellDataById(spellId)
  if not spell or not spell.words then
    return
  end

  -- Verificar se ja esta com haste ativa
  if localPlayer.hasState and localPlayer:hasState(PlayerStates.Haste) then
    return
  end

  -- Verificar prioridade de cura
  local checkHealthPriority = _Helper.checkHealthPriority and _Helper.checkHealthPriority
  if checkHealthPriority and not checkHealthPriority() then
    return
  end

  local currentMillis = g_clock.millis()
  local getSpellCooldown = _Helper.getSpellCooldown and _Helper.getSpellCooldown
  local cooldown = getSpellCooldown and getSpellCooldown(spellId) or 0

  if currentMillis < cooldown then
    return
  end

  local safeDoThing = _Helper.safeDoThing and _Helper.safeDoThing
  if safeDoThing then
    safeDoThing(false)
  end
  g_game.talk(spell.words, true)
  if safeDoThing then
    safeDoThing(true)
  end

  lastHaste = currentMillis
end

-- Getter para o ultimo haste
_Helper.AutoHaste.getLastHaste = function()
  return lastHaste
end

-- Setter para o ultimo haste
_Helper.AutoHaste.setLastHaste = function(value)
  lastHaste = value
end

-- Reset do haste button no UI
_Helper.AutoHaste.resetButton = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  local hasteButton = toolsPanel:recursiveGetChildById("hasteButton0")
  if hasteButton then
    hasteButton:setImageSource("/images/game/actionbar/actionbarslot")
    hasteButton:setImageClip("0 0 34 34")
    hasteButton:setBorderWidth(0)
    hasteButton:setTooltip("")
  end

  local enableHaste = toolsPanel:recursiveGetChildById("enableHaste0")
  if enableHaste then
    enableHaste:setChecked(false)
  end

  local castOnPz = toolsPanel:recursiveGetChildById("castOnPz")
  if castOnPz then
    castOnPz:setChecked(false)
  end
end

-- Remove a acao de haste (limpa configuracao)
_Helper.AutoHaste.removeAction = function(button)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  local slotIndex = tonumber(button:getId():match("%d+"))
  helperConfig.haste[slotIndex + 1].id = 0
  helperConfig.haste[slotIndex + 1].enabled = false
  helperConfig.haste[slotIndex + 1].safecast = false

  local hasteButton = toolsPanel:recursiveGetChildById("hasteButton" .. slotIndex)
  hasteButton:setImageSource("/images/game/actionbar/actionbarslot")
  hasteButton:setImageClip("0 0 34 34")
  hasteButton:setBorderWidth(0)
  hasteButton:setTooltip("")

  toolsPanel:recursiveGetChildById("enableHaste" .. slotIndex):setChecked(false)
  toolsPanel:recursiveGetChildById("castOnPz"):setChecked(false)
end

-- Carrega os dados de haste do config para o UI
_Helper.AutoHaste.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  for k, v in pairs(helperConfig.haste) do
    if v.id ~= 0 then
      local button = toolsPanel:recursiveGetChildById("hasteButton" .. k - 1)
      local spell = Spells and Spells.getSpellDataById and Spells.getSpellDataById(v.id)
      if spell then
        local spellName = Spells.getSpellNameByWords(spell.words)
        _Helper.setSpellIcon(button, spell.id)
        button:setBorderColorTop("#1b1b1b")
        button:setBorderColorLeft("#1b1b1b")
        button:setBorderColorRight("#757575")
        button:setBorderColorBottom("#757575")
        button:setBorderWidth(1)
        button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spell.words)
      end
    end
    -- Sempre atualizar checkboxes, mesmo se id == 0
    local enableHaste = toolsPanel:recursiveGetChildById("enableHaste" .. k - 1)
    if enableHaste then
      enableHaste:setChecked(v.enabled or false)
    end
    local castOnPz = toolsPanel:recursiveGetChildById("castOnPz")
    if castOnPz then
      castOnPz:setChecked(v.safecast or false)
    end
  end
end

-- Salva os estados de haste antes de reset e restaura depois
_Helper.AutoHaste.saveAndRestoreStates = function(savedEnabled, savedSafecast)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.haste then return end

  for k, v in pairs(helperConfig.haste) do
    v.enabled = savedEnabled[k]
    v.safecast = savedSafecast[k]
  end
end

-- Coleta os estados atuais para salvar
_Helper.AutoHaste.collectStates = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.haste then
    return {}, {}
  end

  local savedEnabled = {}
  local savedSafecast = {}
  for k, v in pairs(helperConfig.haste) do
    savedEnabled[k] = v.enabled
    savedSafecast[k] = v.safecast
  end
  return savedEnabled, savedSafecast
end

-- Configura o drop de spell no botao de haste
_Helper.AutoHaste.onSetupDropSupport = function(widget, spellData)
  local player = g_game.getLocalPlayer()
  if not player then return end

  local translateVocation = _Helper.translateVocation or translateVocation
  local playerVocation = translateVocation(player:getVocation())
  local hasteWhiteList = HelperSpellData.getHasteWhiteList()

  -- Verificar se a spell e uma spell de haste valida
  if not table.contains(hasteWhiteList[playerVocation] or {}, spellData.id) then
    return
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end

  if table.contains(spellData.vocations, playerVocation) then
    _Helper.setSpellIcon(widget, spellData.id)
    widget:setBorderColorTop("#1b1b1b")
    widget:setBorderColorLeft("#1b1b1b")
    widget:setBorderColorRight("#757575")
    widget:setBorderColorBottom("#757575")
    widget:setBorderWidth(1)
    widget:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    helperConfig.haste[1].id = tonumber(spellData.id)

    -- Save settings
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end
end

-- ===== CYCLE EVENT SYSTEM =====

-- Para o cycle event
_Helper.AutoHaste.stopCycle = function()
  if hasteCycleEvent then
    removeEvent(hasteCycleEvent)
    hasteCycleEvent = nil
  end
end

-- Funcao interna do cycle event
local function hasteCycleFunction()
  local localPlayer = g_game.getLocalPlayer()

  -- Se conseguiu ter haste, para o cycle
  if localPlayer and localPlayer.hasState and localPlayer:hasState(PlayerStates.Haste) then
    _Helper.AutoHaste.stopCycle()
    return
  end

  -- Tenta castar
  _Helper.AutoHaste.check()
end

-- Inicia o cycle event temporario
_Helper.AutoHaste.startCycle = function()
  -- Ja esta rodando
  if hasteCycleEvent then return end

  -- Verifica se auto haste esta habilitado
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.haste or not helperConfig.haste[1] then return end
  if not helperConfig.haste[1].enabled then return end
  if helperConfig.haste[1].id == 0 then return end

  hasteCycleEvent = cycleEvent(hasteCycleFunction, HASTE_CYCLE_INTERVAL)
end

-- Chamado pelo onStatesChange quando haste e removido
_Helper.AutoHaste.onHasteLost = function()
  _Helper.AutoHaste.startCycle()
end

-- Chamado no login para verificar estado inicial
_Helper.AutoHaste.onLogin = function()
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  -- Se nao tem haste no login, inicia cycle
  if not localPlayer.hasState or not localPlayer:hasState(PlayerStates.Haste) then
    _Helper.AutoHaste.startCycle()
  end
end

-- Chamado no logout para limpar
_Helper.AutoHaste.onLogout = function()
  _Helper.AutoHaste.stopCycle()
end

-- Verifica se o cycle esta ativo
_Helper.AutoHaste.isCycleActive = function()
  return hasteCycleEvent ~= nil
end

-- ===== FIM HELPER AUTO HASTE =====
