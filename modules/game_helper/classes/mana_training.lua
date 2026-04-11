-- ===== HELPER MANA TRAINING =====
-- Modulo separado para gerenciar o Mana Training do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.ManaTraining = {}

-- ===== FUNCOES DO MANA TRAINING =====

-- Toggle para habilitar/desabilitar o Mana Training
_Helper.ManaTraining.toggle = function(buttonId, checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.training then return false end

  local slotIndex = tonumber(buttonId:match("%d+"))
  local trainingConfig = helperConfig.training[slotIndex + 1]
  if not trainingConfig then return false end

  -- GUARD: Cannot enable Mana Training without a spell selected
  if checked and trainingConfig.id == 0 then
    -- No spell selected, reject the enable and show message
    modules.game_textmessage.displayFailureMessage(tr("Select a training spell first!"))
    -- Uncheck the checkbox in UI
    local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
    if toolsPanel then
      local enableTraining = toolsPanel:recursiveGetChildById("enableTraining" .. slotIndex)
      if enableTraining then
        enableTraining:setChecked(false)
      end
    end
    -- Sync shortcut panel to unchecked (only slot 0)
    if slotIndex == 0 and _Helper.Shortcut and _Helper.Shortcut.syncButton then
      _Helper.Shortcut.syncButton('shortcutTraining', false)
    end
    return false
  end

  trainingConfig.enabled = checked

  -- Sincronizar com shortcut panel (apenas slot 0)
  if slotIndex == 0 and _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutTraining', checked)
  end

  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
  return true
end

-- Atualiza o percentual minimo de mana para training
_Helper.ManaTraining.updatePercent = function(buttonId, newPercent)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.training then return end

  local buttonIndex = string.match(buttonId, "%d+")
  buttonIndex = tonumber(buttonIndex)
  local trainingConfig = helperConfig.training[buttonIndex + 1]
  if trainingConfig and trainingConfig.percent then
    trainingConfig.percent = tonumber(newPercent)
  end
end

-- Verifica e casta a spell de training
_Helper.ManaTraining.check = function(mana, maxMana)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.training then
    return false
  end

  local trainingSpell = helperConfig.training[1]
  if not trainingSpell or not trainingSpell.enabled then
    return false
  end

  -- Prioridade: Auto Haste tem prioridade sobre Mana Training
  -- Se o Auto Haste esta habilitado e o player nao tem haste, nao casta training
  -- EXCETO se o player esta em PZ e o PZ CAST esta desabilitado (nesse caso o haste nao vai castar)
  if helperConfig.haste and helperConfig.haste[1] and helperConfig.haste[1].enabled and helperConfig.haste[1].id ~= 0 then
    local localPlayer = g_game.getLocalPlayer()
    if localPlayer and (not localPlayer.hasState or not localPlayer:hasState(PlayerStates.Haste)) then
      -- Verificar se o Auto Haste realmente vai poder castar
      -- Se esta em PZ e safecast (PZ CAST) esta desabilitado, o haste nao vai castar
      local isInPz = localPlayer:isInProtectionZone()
      local canHasteCast = not isInPz or helperConfig.haste[1].safecast

      if canHasteCast then
        -- Player sem haste e Auto Haste habilitado e pode castar - deixa o haste ter prioridade
        return false
      end
      -- Se nao pode castar haste (em PZ sem PZ CAST), permite o training
    end
  end

  local manaPercent = (mana / maxMana) * 100
  if manaPercent < tonumber(trainingSpell.percent) then
    return false
  end

  -- Usar castHealingSpell do helper
  local castHealingSpell = _Helper.castHealingSpell
  if castHealingSpell then
    castHealingSpell(trainingSpell)
  end
end

-- Reset do training button no UI
_Helper.ManaTraining.resetButton = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  local trainingButton = toolsPanel:recursiveGetChildById("spellTrainingButton0")
  if trainingButton then
    trainingButton:setImageSource("/images/game/actionbar/actionbarslot")
    trainingButton:setImageClip("0 0 34 34")
    trainingButton:setBorderWidth(0)
    trainingButton:setTooltip("")
  end

  local trainingPercent = toolsPanel:recursiveGetChildById("spellTrainingPercent0")
  if trainingPercent then
    trainingPercent:setText("0%")
  end

  local enableTraining = toolsPanel:recursiveGetChildById("enableTraining0")
  if enableTraining then
    enableTraining:setChecked(false)
  end
end

-- Remove a acao de training (limpa configuracao)
_Helper.ManaTraining.removeAction = function(button)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  local slotIndex = tonumber(button:getId():match("%d+"))
  helperConfig.training[slotIndex + 1].id = 0
  helperConfig.training[slotIndex + 1].percent = 0
  helperConfig.training[slotIndex + 1].enabled = false

  local trainingButton = toolsPanel:recursiveGetChildById("spellTrainingButton" .. slotIndex)
  if trainingButton then
    trainingButton:setImageSource("/images/game/actionbar/actionbarslot")
    trainingButton:setImageClip("0 0 34 34")
    trainingButton:setBorderWidth(0)
    trainingButton:setTooltip("")
  end

  local percentOption = toolsPanel:recursiveGetChildById("spellTrainingPercent" .. slotIndex)
  if percentOption then
    percentOption:setCurrentOption("100%")
  end

  local enableTraining = toolsPanel:recursiveGetChildById("enableTraining" .. slotIndex)
  if enableTraining then
    enableTraining:setChecked(false)
  end
end

-- Carrega os dados de training do config para o UI
_Helper.ManaTraining.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel or not helperConfig.training then return end

  for k, v in pairs(helperConfig.training) do
    if v.id ~= 0 then
      local button = toolsPanel:recursiveGetChildById("spellTrainingButton" .. k - 1)
      local spell = Spells and Spells.getSpellDataById and Spells.getSpellDataById(v.id)
      if spell and button then
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
    -- Sempre atualizar checkboxes e percent, mesmo se id == 0
    local percentOption = toolsPanel:recursiveGetChildById("spellTrainingPercent" .. k - 1)
    if percentOption then
      -- Ensure percent is valid (10-100 in steps of 10), default to 100 if invalid
      local percent = tonumber(v.percent) or 100
      if percent < 10 or percent > 100 then
        percent = 100
      end
      -- Round to nearest 10
      percent = math.floor((percent + 5) / 10) * 10
      percentOption:setCurrentOption(tostring(percent) .. "%")
    end
    local enableTraining = toolsPanel:recursiveGetChildById("enableTraining" .. k - 1)
    if enableTraining then
      enableTraining:setChecked(v.enabled or false)
    end
  end
end

-- Salva os estados de training antes de reset e restaura depois
_Helper.ManaTraining.saveAndRestoreStates = function(savedEnabled)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.training then return end

  for k, v in pairs(helperConfig.training) do
    v.enabled = savedEnabled[k]
  end
end

-- Coleta os estados atuais para salvar
_Helper.ManaTraining.collectStates = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.training then
    return {}
  end

  local savedEnabled = {}
  for k, v in pairs(helperConfig.training) do
    savedEnabled[k] = v.enabled
  end
  return savedEnabled
end

-- ===== FIM HELPER MANA TRAINING =====
