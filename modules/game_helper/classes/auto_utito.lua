-- ===== HELPER AUTO UTITO =====
-- Modulo separado para gerenciar o Auto Utito do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.AutoUtito = {}

-- Variavel local para controle do ultimo cast de utito
local lastUtito = 0

-- Cycle event para tentar castar utito
local utitoCycleEvent = nil
local UTITO_CYCLE_INTERVAL = 500 -- ms

-- ===== FUNCOES DO AUTO UTITO =====

-- Toggle para habilitar/desabilitar o Auto Utito
_Helper.AutoUtito.toggle = function(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.utito or not helperConfig.utito[1] then
    return false
  end

  -- GUARD: Cannot enable Auto Utito without a spell selected
  if checked and helperConfig.utito[1].id == 0 then
    -- No spell selected, reject the enable and show message
    modules.game_textmessage.displayFailureMessage(tr("Select a utito spell first!"))
    -- Uncheck the checkbox in UI
    local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
    if toolsPanel then
      local enableUtito = toolsPanel:recursiveGetChildById("enableUtito0")
      if enableUtito then
        enableUtito:setChecked(false)
      end
    end
    -- Sync shortcut panel to unchecked
    if _Helper.Shortcut and _Helper.Shortcut.syncButton then
      _Helper.Shortcut.syncButton('shortcutUtito', false)
    end
    return false
  end

  helperConfig.utito[1].enabled = checked

  -- Sincronizar com shortcut panel
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutUtito', checked)
  end
  -- Iniciar ou parar o cycle event baseado no estado
  if checked then
    -- Ligou: iniciar o cycle
    _Helper.AutoUtito.startCycle()
  else
    -- Desligou: parar o cycle
    _Helper.AutoUtito.stopCycle()
  end
  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
  return true
end

-- Toggle para habilitar/desabilitar cast em PZ
_Helper.AutoUtito.togglePz = function(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig and helperConfig.utito and helperConfig.utito[1] then
    helperConfig.utito[1].safecast = checked
  end

  -- Verificar se precisa iniciar/parar o cycle baseado no estado de PZ
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local isInPz = localPlayer:isInProtectionZone()
  local isEnabled = helperConfig and helperConfig.utito and helperConfig.utito[1] and helperConfig.utito[1].enabled

  if checked and isInPz and isEnabled then
    -- Ligou PZ Cast, esta em PZ, auto utito habilitado: iniciar cycle
    _Helper.AutoUtito.startCycle()
  elseif not checked and isInPz then
    -- Desligou PZ Cast e esta em PZ: parar cycle (nao pode castar em PZ)
    _Helper.AutoUtito.stopCycle()
  end
end

-- Funcao principal que verifica e executa o auto utito
_Helper.AutoUtito.check = function()
  local helperAutomaticFunctionsEnabled = _Helper.isHelperAutomaticFunctionsEnabled and _Helper.isHelperAutomaticFunctionsEnabled()
  if not helperAutomaticFunctionsEnabled then
    return
  end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return true
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.utito or not helperConfig.utito[1] then
    return true
  end

  if helperConfig.utito[1].id == 0 then
    return true
  end

  if not helperConfig.utito[1].enabled then
    return true
  end

  if not helperConfig.utito[1].safecast and localPlayer:isInProtectionZone() then
    return true
  end

  local spellId = helperConfig.utito[1].id
  local getSpellDataById = _Helper.getSpellDataById and _Helper.getSpellDataById
  local spell = getSpellDataById and getSpellDataById(spellId)
  if not spell or not spell.words then
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

  -- Verificar se ainda esta em cooldown (spell ativa)
  if currentMillis < cooldown then
    return
  end

  -- Verificar tempo minimo desde o ultimo cast baseado na duracao da spell
  -- Utito spells (Blood Rage, Sharpshooter) tem duracao de 10 segundos
  local SPELL_DURATION = 10000 -- 10 segundos em ms
  if lastUtito > 0 and (currentMillis - lastUtito) < SPELL_DURATION then
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

  lastUtito = currentMillis
end

-- Getter para o ultimo utito
_Helper.AutoUtito.getLastUtito = function()
  return lastUtito
end

-- Setter para o ultimo utito
_Helper.AutoUtito.setLastUtito = function(value)
  lastUtito = value
end

-- Reset do utito button no UI
_Helper.AutoUtito.resetButton = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  local utitoButton = toolsPanel:recursiveGetChildById("utitoButton0")
  if utitoButton then
    utitoButton:setImageSource("/images/game/actionbar/actionbarslot")
    utitoButton:setImageClip("0 0 34 34")
    utitoButton:setBorderWidth(0)
    utitoButton:setTooltip("")
  end

  local enableUtito = toolsPanel:recursiveGetChildById("enableUtito0")
  if enableUtito then
    enableUtito:setChecked(false)
  end

  local castOnPzUtito = toolsPanel:recursiveGetChildById("castOnPzUtito")
  if castOnPzUtito then
    castOnPzUtito:setChecked(false)
  end
end

-- Remove a acao de utito (limpa configuracao)
_Helper.AutoUtito.removeAction = function(button)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  local slotIndex = tonumber(button:getId():match("%d+"))
  helperConfig.utito[slotIndex + 1].id = 0
  helperConfig.utito[slotIndex + 1].enabled = false
  helperConfig.utito[slotIndex + 1].safecast = false

  local utitoButton = toolsPanel:recursiveGetChildById("utitoButton" .. slotIndex)
  utitoButton:setImageSource("/images/game/actionbar/actionbarslot")
  utitoButton:setImageClip("0 0 34 34")
  utitoButton:setBorderWidth(0)
  utitoButton:setTooltip("")

  toolsPanel:recursiveGetChildById("enableUtito" .. slotIndex):setChecked(false)
  toolsPanel:recursiveGetChildById("castOnPzUtito"):setChecked(false)
end

-- Carrega os dados de utito do config para o UI
_Helper.AutoUtito.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  if type(helperConfig.utito) ~= "table" then
    helperConfig.utito = { { id = 0, enabled = false, safecast = false } }
  end

  for k, v in pairs(helperConfig.utito) do
    if v.id ~= 0 then
      local button = toolsPanel:recursiveGetChildById("utitoButton" .. k - 1)
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
    local enableUtito = toolsPanel:recursiveGetChildById("enableUtito" .. k - 1)
    if enableUtito then
      enableUtito:setChecked(v.enabled or false)
    end
    local castOnPzUtito = toolsPanel:recursiveGetChildById("castOnPzUtito")
    if castOnPzUtito then
      castOnPzUtito:setChecked(v.safecast or false)
    end
  end
end

-- Salva os estados de utito antes de reset e restaura depois
_Helper.AutoUtito.saveAndRestoreStates = function(savedEnabled, savedSafecast)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.utito then return end

  for k, v in pairs(helperConfig.utito) do
    v.enabled = savedEnabled[k]
    v.safecast = savedSafecast[k]
  end
end

-- Coleta os estados atuais para salvar
_Helper.AutoUtito.collectStates = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.utito then
    return {}, {}
  end

  local savedEnabled = {}
  local savedSafecast = {}
  for k, v in pairs(helperConfig.utito) do
    savedEnabled[k] = v.enabled
    savedSafecast[k] = v.safecast
  end
  return savedEnabled, savedSafecast
end

-- Configura o drop de spell no botao de utito
_Helper.AutoUtito.onSetupDropSupport = function(widget, spellData)
  local player = g_game.getLocalPlayer()
  if not player then return end

  local translateVocation = _Helper.translateVocation or translateVocation
  local playerVocation = translateVocation(player:getVocation())
  local utitoWhiteList = HelperSpellData.getUtitoWhiteList()

  -- Verificar se a spell e uma spell de utito valida
  if not table.contains(utitoWhiteList[playerVocation] or {}, spellData.id) then
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

    helperConfig.utito[1].id = tonumber(spellData.id)

    -- Save settings
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end
end

-- ===== CYCLE EVENT SYSTEM =====

-- Para o cycle event
_Helper.AutoUtito.stopCycle = function()
  if utitoCycleEvent then
    removeEvent(utitoCycleEvent)
    utitoCycleEvent = nil
  end
end

-- Funcao interna do cycle event
local function utitoCycleFunction()
  -- Tenta castar - a funcao check() ja tem todas as validacoes necessarias
  _Helper.AutoUtito.check()
end

-- Inicia o cycle event temporario
_Helper.AutoUtito.startCycle = function()
  -- Ja esta rodando
  if utitoCycleEvent then return end

  -- Verifica se auto utito esta habilitado
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.utito or not helperConfig.utito[1] then return end
  if not helperConfig.utito[1].enabled then return end
  if helperConfig.utito[1].id == 0 then return end

  utitoCycleEvent = cycleEvent(utitoCycleFunction, UTITO_CYCLE_INTERVAL)
end

-- Chamado no login para verificar estado inicial
_Helper.AutoUtito.onLogin = function()
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  -- Inicia cycle se habilitado
  _Helper.AutoUtito.startCycle()
end

-- Chamado no logout para limpar
_Helper.AutoUtito.onLogout = function()
  _Helper.AutoUtito.stopCycle()
end

-- Verifica se o cycle esta ativo
_Helper.AutoUtito.isCycleActive = function()
  return utitoCycleEvent ~= nil
end

-- ===== FIM HELPER AUTO UTITO =====
