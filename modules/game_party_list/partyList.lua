partyList = nil
editNameBattleWindow = nil
partyButton = nil
partyListOnline = false -- Flag para evitar chamadas duplicadas de online/offline

-- Minimap party markers
partyMinimapMarkers = {}

-- Modo de exibição: 'normal' (partymember/partyleader) ou 'vocation' (ícones de vocação)
partyDisplayMode = 'vocation'

-- Mapeamento de vocação para imagem
local vocationImages = {
  [0] = '/images/game/minimap/rookie',    -- None
  [1] = '/images/game/minimap/knight',    -- Knight
  [2] = '/images/game/minimap/paladin',   -- Paladin
  [3] = '/images/game/minimap/sorcerer',  -- Sorcerer
  [4] = '/images/game/minimap/druid',     -- Druid
  [5] = '/images/game/minimap/monk',      -- Monk
  [11] = '/images/game/minimap/knight',   -- Elite Knight
  [12] = '/images/game/minimap/paladin',  -- Royal Paladin
  [13] = '/images/game/minimap/sorcerer', -- Master Sorcerer
  [14] = '/images/game/minimap/druid',    -- Elder Druid
  [15] = '/images/game/minimap/monk',     -- Exalted Monk
}

local function getVocationImage(vocationId)
  return vocationImages[vocationId] or vocationImages[0]
end

local function getPartyMarkerImage(creature)
  if partyDisplayMode == 'vocation' then
    return getVocationImage(creature:getVocation())
  else
    -- Modo normal: partyleader para líder, partymember para membros
    if creature:isPartyLeader() then
      return '/images/game/minimap/partyleader'
    else
      return '/images/game/minimap/partymember'
    end
  end
end

local function onPartyMemberPositionChange(creature, newPos, oldPos)
  if not creature or not newPos then
    return
  end

  if newPos.x == 65535 then
    return
  end

  local creatureId = creature:getId()
  local markerData = partyMinimapMarkers[creatureId]

  if not markerData or not markerData.widget then
    return
  end

  local minimapWidget = modules.game_minimap.getMiniMapUi()
  if not minimapWidget then
    return
  end

  if not markerData.widget:isVisible() then
    markerData.widget:setVisible(true)
  end

  minimapWidget:centerInPosition(markerData.widget, newPos)
end

function addPartyMemberToMinimap(creature)
  if not creature then
    return
  end

  -- Só adicionar marcadores para players que são membros da party
  if not creature:isPlayer() or not creature:isPartyMember() then
    return
  end

  -- Não adicionar marcador para o player local (ele já tem o cross)
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer and creature:getId() == localPlayer:getId() then
    return
  end

  local creatureId = creature:getId()
  local position = creature:getPosition()

  local minimapWidget = modules.game_minimap.getMiniMapUi()
  if not minimapWidget then
    return
  end

  -- Remover marcador existente se houver
  removePartyMemberFromMinimap(creatureId)

  -- Criar widget de marcador
  local marker = g_ui.createWidget('UIWidget', minimapWidget)
  marker:setId('partyMarker_' .. creatureId)
  marker:setSize({ width = 31, height = 31 })
  marker:setImageSource(getPartyMarkerImage(creature))
  marker:setPhantom(true)

  -- Posicionar no minimap apenas se a posição for válida
  if position and position.x ~= 65535 then
    minimapWidget:centerInPosition(marker, position)
  else
    marker:setVisible(false)
  end

  -- Armazenar referência
  partyMinimapMarkers[creatureId] = {
    widget = marker,
    creature = creature
  }

  -- Conectar ao evento de movimento da creature
  connect(creature, {
    onPositionChange = onPartyMemberPositionChange
  })

  -- Atualizar indicador de party no minimap
  updatePartyIndicator()
end

function removePartyMemberFromMinimap(creatureId)
  local markerData = partyMinimapMarkers[creatureId]
  if markerData then
    if markerData.creature then
      disconnect(markerData.creature, {
        onPositionChange = onPartyMemberPositionChange
      })
    end

    if markerData.widget then
      markerData.widget:destroy()
    end

    partyMinimapMarkers[creatureId] = nil

    -- Atualizar indicador de party no minimap
    updatePartyIndicator()
  end
end

function updatePartyMemberMinimapPosition(creature)
  if not creature then
    return
  end

  -- Ignorar o player local (ele já tem o cross gerenciado pelo minimap)
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer and creature:getId() == localPlayer:getId() then
    return
  end

  -- Verificar se a criatura é um player e membro da party
  if not creature:isPlayer() or not creature:isPartyMember() then
    return
  end

  local creatureId = creature:getId()
  local markerData = partyMinimapMarkers[creatureId]

  if not markerData or not markerData.widget then
    addPartyMemberToMinimap(creature)
    return
  end

  local minimapWidget = modules.game_minimap.getMiniMapUi()
  if not minimapWidget then
    return
  end

  local position = creature:getPosition()
  if position and position.x ~= 65535 then
    if not markerData.widget:isVisible() then
      markerData.widget:setVisible(true)
    end
    minimapWidget:centerInPosition(markerData.widget, position)
  end
end

function clearAllPartyMinimapMarkers()
  for creatureId, _ in pairs(partyMinimapMarkers) do
    removePartyMemberFromMinimap(creatureId)
  end
  partyMinimapMarkers = {}

  -- Atualizar indicador de party no minimap
  updatePartyIndicator()
end

function updatePartyIndicator()
  local minimapWindow = modules.game_minimap.getMinimapWindow()
  if not minimapWindow then
    return
  end

  local partyIndicator = minimapWindow:recursiveGetChildById('partyIndicator')
  if not partyIndicator then
    return
  end

  -- Mostrar indicador se houver membros na party
  local hasPartyMembers = next(partyMinimapMarkers) ~= nil
  partyIndicator:setVisible(hasPartyMembers)

  -- Atualizar imagem e tooltip do indicador baseado no modo atual
  if partyDisplayMode == 'vocation' then
    partyIndicator:setImageSource('/images/game/minimap/party-vocation-color')
    partyIndicator:setTooltip('Party Colors by Vocation')
  else
    partyIndicator:setImageSource('/images/game/minimap/party-normal-color')
    partyIndicator:setTooltip('Party Default Colors')
  end
end

function togglePartyDisplayMode()
  -- Alternar entre os modos
  if partyDisplayMode == 'normal' then
    partyDisplayMode = 'vocation'
  else
    partyDisplayMode = 'normal'
  end

  -- Atualizar todos os marcadores existentes
  refreshAllPartyMarkers()

  -- Atualizar o indicador
  updatePartyIndicator()
end

function refreshAllPartyMarkers()
  for creatureId, markerData in pairs(partyMinimapMarkers) do
    if markerData.widget and markerData.creature then
      markerData.widget:setImageSource(getPartyMarkerImage(markerData.creature))
    end
  end
end

function init()
  g_ui.importStyle('partyList')

  partyButton = modules.game_mainpanel.addToggleButton('partyListButton', tr('Party List'),
    '/images/options/partyWidget', toggle, false, 20)
  partyButton:setOn(false)

  partyList = g_ui.createWidget('PartyListWindow', modules.game_interface.getContainerPanel())
  partyList:setup()
  partyList:close()
  partyList:setId('PartyWindow')

  PartyClass:configure()
  PartyClass:setup(1, partyList)

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyMemberManaChange = onPartyMemberManaChange,
    onPartyMemberHealthChange = onPartyMemberHealthChange,
    onPartyMemberShowStatusChange = onPartyMemberShowStatusChange,
  })

  connect(Creature, {
    onShieldChange = onCreatureShieldChange,
  })

  -- Não precisa mais escutar onAppear/onDisappear das criaturas
  -- O servidor envia showStatus para controlar quem aparece na party list

  -- Se já estiver online durante o init, chamar online() manualmente
  if g_game.isOnline() then
    scheduleEvent(function()
      online()
    end, 150)
  end
end

function terminate()
  -- Limpar marcadores do minimap
  clearAllPartyMinimapMarkers()

  if partyList then
    partyList:destroy()
    partyList = nil
  end

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
    onPartyMemberManaChange = onPartyMemberManaChange,
    onPartyMemberHealthChange = onPartyMemberHealthChange,
    onPartyMemberShowStatusChange = onPartyMemberShowStatusChange,
  })

  disconnect(Creature, {
    onShieldChange = onCreatureShieldChange,
  })


  if PartyClass then
    PartyClass:removeAllCreatures()
  end
end

function online()
  -- Evitar chamadas duplicadas
  if partyListOnline then
    return
  end
  partyListOnline = true

  -- Carregar e aplicar configurações salvas
  local config = loadPartyListSettings()
  applyPartyListSettings(config)

  -- Usar setupOnStart para restaurar posição (como o VIPList faz)
  scheduleEvent(function()
    if partyList then
      partyList:setupOnStart()
    end
  end, 150)
end

function applyPartyListSettings(config)
  if not partyList or not config then
    return
  end

  -- Aplicar nome
  if config.name then
    PartyClass:setName(config.name)
  end

  -- Aplicar filtros
  if config.battleListFilters then
    for _, value in pairs(config.battleListFilters) do
      if value == "hidePlayers" or value == "hideKnights" or value == "hidePaladins" or
          value == "hideDruids" or value == "hideSorcerers" or value == "hideMonks" or value == "hideSummons" then
        local showValue = value:gsub("hide", "show")
        local filterPanel = partyList:recursiveGetChildById('filterPanel')
        if filterPanel then
          local button = filterPanel:getChildById(showValue)
          if button then
            button:setChecked(true)
          end
        end
      end
    end
  end

  -- Aplicar sort order
  if config.battleListSortOrder and config.battleListSortOrder[1] then
    PartyClass.sortType[1] = config.battleListSortOrder[1]
  end

  -- Aplicar estado maximizado/minimizado
  if config.contentMaximized then
    partyList:maximize()
  else
    partyList:minimize()
  end

  -- Aplicar altura
  if config.contentHeight and config.contentHeight >= partyList:getMinimumHeight() then
    partyList:setHeight(config.contentHeight)
  end

  -- Aplicar visibilidade do painel de filtros
  scheduleEvent(function()
    if config.showFilters == false then
      hideFilterPanel()
    else
      showFilterPanel()
    end
  end, 100)

  partyList:setup()
end

function offline()
  -- Evitar chamadas duplicadas
  if not partyListOnline then
    -- Ainda precisamos limpar o minimap/party ao deslogar ou trocar de personagem.
  end
  partyListOnline = false

  -- Salvar configurações antes de sair
  savePartyListSettings()

  -- Limpar marcadores do minimap
  clearAllPartyMinimapMarkers()

  if PartyClass then
    PartyClass:removeAllCreatures()
    PartyClass.knownPartyMembers = {}
  end
  if partyList then
    partyList:close()
  end
end

function savePartyListSettings()
  if not partyList then
    return
  end

  local settings = {}
  settings['name'] = PartyClass.name or "Party List"
  settings['contentHeight'] = partyList:getHeight()
  settings['showFilters'] = PartyClass.showFilters
  settings['contentMaximized'] = not partyList.minimized
  settings['battleListSortOrder'] = PartyClass.sortType or { [1] = "byAgeAscending", [2] = "byAgeAscending" }

  -- Salvar filtros ativos
  local battleListFilters = {}
  if PartyClass.hideButtons then
    if PartyClass.hideButtons.showPlayers and PartyClass.hideButtons.showPlayers:isChecked() then
      table.insert(battleListFilters, "hidePlayers")
    end
    if PartyClass.hideButtons.showKnights and PartyClass.hideButtons.showKnights:isChecked() then
      table.insert(battleListFilters, "hideKnights")
    end
    if PartyClass.hideButtons.showPaladins and PartyClass.hideButtons.showPaladins:isChecked() then
      table.insert(battleListFilters, "hidePaladins")
    end
    if PartyClass.hideButtons.showDruids and PartyClass.hideButtons.showDruids:isChecked() then
      table.insert(battleListFilters, "hideDruids")
    end
    if PartyClass.hideButtons.showSorcerers and PartyClass.hideButtons.showSorcerers:isChecked() then
      table.insert(battleListFilters, "hideSorcerers")
    end
    if PartyClass.hideButtons.showMonks and PartyClass.hideButtons.showMonks:isChecked() then
      table.insert(battleListFilters, "hideMonks")
    end
    if PartyClass.hideButtons.showSummons and PartyClass.hideButtons.showSummons:isChecked() then
      table.insert(battleListFilters, "hideSummons")
    end
  end
  settings['battleListFilters'] = battleListFilters

  g_settings.mergeNode('PartyList', settings)
end

function loadPartyListSettings()
  local settings = g_settings.getNode('PartyList')

  if not settings or table.empty(settings) then
    settings = {
      ["name"] = "Party List",
      ["contentHeight"] = 0,
      ["showFilters"] = true,
      ["contentMaximized"] = true,
      ["battleListFilters"] = {},
      ["battleListSortOrder"] = {
        [1] = "byAgeAscending",
        [2] = "byAgeAscending",
      }
    }
  end

  return settings
end

function toggle()
  if not partyList then
    return
  end

  if partyList:isVisible() then
    partyList:close()
    if partyButton then
      partyButton:setOn(false)
    end
  else
    partyList:open()
    partyList:setup()
    local panel = modules.game_interface.findContentPanelAvailable(partyList, partyList:getMinimumHeight())
    if panel then
      if not panel:hasChild(partyList) then
        panel:addChild(partyList)
      end
      if partyButton then
        partyButton:setOn(true)
      end
    end
  end
end

function hide()
  partyList:close()
end

function show()
  partyList:open()
  partyList:setup()
end

function filterPopUp()
  -- Esta função é chamada pelo @onBattleExtra, mas o botão correto é o contextMenuButton
  -- que é configurado no PartyClass:setup()
end

function onMiniWindowOpen()
  if partyButton then
    partyButton:setOn(true)
  end
end

function onMiniWindowClose()
  if partyButton then
    partyButton:setOn(false)
  end
end

function setHidingFilters(state)
  settings = {}
  settings['hidingFilters'] = state
  g_settings.mergeNode('BattleList', settings)
end

function hideFilterPanel(id)
  local filterPanel = partyList:recursiveGetChildById('filterPanel')
  if not filterPanel then
    return
  end

  local battleWindow = partyList
  PartyClass.showFilters = false
  filterPanel.originalHeight = 22
  filterPanel:setHeight(0)
  setHidingFilters(true)
  filterPanel:setVisible(false)
  battleWindow:setContentMinimumHeight(56)
end

function showFilterPanel(id)
  local filterPanel = partyList:recursiveGetChildById('filterPanel')
  if not filterPanel then
    return
  end

  local battleWindow = partyList
  PartyClass.showFilters = true
  filterPanel:setHeight(22)
  setHidingFilters(false)
  filterPanel:setVisible(true)

  if battleWindow:getHeight() < 66 then
    battleWindow:setHeight(66)
  end

  battleWindow:setContentMinimumHeight(66)
end

function toggleFilterPanel(self)
  local filterPanel = PartyClass:getFilterPanel()
  if not filterPanel then
    return
  end

  if filterPanel:isVisible() then
    hideFilterPanel()
    self:getChildById('separator'):setVisible(false)
  else
    showFilterPanel()
    self:getChildById('separator'):setVisible(true)
  end

  -- Atualizar estado do botão toggleFilterButton
  if PartyClass.toggleFilterButton then
    PartyClass.toggleFilterButton:setOn(PartyClass.showFilters)
  end
end

function onPlayerLoad(config)
  -- Se não receber config externo, carrega das configurações salvas
  if not config or table.empty(config) then
    config = loadPartyListSettings()
  end

  -- Aplicar configurações
  applyPartyListSettings(config)

  -- Atualizar lista após carregar configuração
  scheduleEvent(function()
    if PartyClass and PartyClass.panel then
      PartyClass:checkCreatures()
    end
  end, 300)

  local panel = modules.game_interface.findContentPanelAvailable(partyList, partyList:getMinimumHeight())
  if panel then
    if not panel:hasChild(partyList) then
      panel:addChild(partyList)
    end

    partyList:getParent():moveChildToIndex(partyList, #partyList:getParent():getChildren())
  end

  scheduleEvent(function() setupPartyPanel(config.showFilters) end, 2000, "setupParty")
end

function onPlayerUnload()
  -- Salvar configurações quando o jogador deslogar
  savePartyListSettings()

  -- Garantir que nÃ£o fique marcador de party no minimap ao trocar de personagem.
  clearAllPartyMinimapMarkers()
  if PartyClass then
    PartyClass:removeAllCreatures()
    PartyClass.knownPartyMembers = {}
  end

  if PartyClass and PartyClass.window and PartyClass.window:isOpened() then
    PartyClass:registerInSideBars()
  end
end

function setupPartyPanel(showFilters)
  local filterPanel = partyList:recursiveGetChildById('filterPanel')
  if not filterPanel then
    return
  end
  if not showFilters then
    if not filterPanel:isVisible() then
      return
    end
    hideFilterPanel()
  else
    if filterPanel:isVisible() then
      return
    end
    showFilterPanel()
  end
end

function move(panel, height, minimized)
  partyList:setParent(panel)
  partyList:open()
  partyList:maximize()
  partyList:setHeight(height)

  return partyList
end

function getUpcomingPartyMembers()
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return {}
  end

  local players = {}
  local spectators = g_map.getSpectators(localPlayer:getPosition(), false)
  for _, creature in ipairs(spectators) do
    if creature:isPlayer() and creature:isPartyMember() then
      local creaturePosition = creature:getPosition() or { x = 0xFFFF, y = 0xFFFF, z = 0 }
      if Position.distance(creaturePosition, localPlayer:getPosition()) <= 9 then
        table.insert(players, creature)
      end
    end
  end
  return players
end

function getPartyMembers()
  if not PartyClass or not PartyClass.panel then
    return {}
  end

  local members = {}
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    local spectators = g_map.getSpectators(localPlayer:getPosition(), false)
    for _, creature in ipairs(spectators) do
      if creature:isPlayer() and creature:isPartyMember() then
        table.insert(members, creature)
      end
    end
  end
  return members
end

function onPartyMemberManaChange(creature, manaPercent)
  if not creature then
    return
  end

  -- Verificar se a criatura é um player e membro da party
  if not creature:isPlayer() or not creature:isPartyMember() then
    return
  end

  if not PartyClass or not PartyClass.partyButtons then
    return
  end

  local creatureId = creature:getId()
  local button = PartyClass.partyButtons[creatureId]
  if button then
    button:setManaBarPercent(manaPercent)
  end

  -- Atualizar posição do marcador no minimap (para membros fora da tela)
  updatePartyMemberMinimapPosition(creature)
end

function onPartyMemberHealthChange(creature, healthPercent)
  if not creature then
    return
  end

  -- Verificar se a criatura é um player e membro da party
  if not creature:isPlayer() or not creature:isPartyMember() then
    return
  end

  if not PartyClass or not PartyClass.partyButtons then
    return
  end

  local creatureId = creature:getId()
  local button = PartyClass.partyButtons[creatureId]
  if button then
    button:setLifeBarPercent(healthPercent)
  end

  -- Atualizar posição do marcador no minimap (para membros fora da tela)
  updatePartyMemberMinimapPosition(creature)
end

function onCreatureShieldChange(creature, shieldId)
  if not creature then
    return
  end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    return
  end

  -- Se o player local saiu da party, limpar todos os marcadores
  if creature:getId() == localPlayer:getId() then
    if not creature:isPartyMember() then
      clearAllPartyMinimapMarkers()
      if PartyClass then
        PartyClass:removeAllCreatures()
        PartyClass.knownPartyMembers = {}
      end
    end
    return
  end

  -- Se um membro rastreado saiu da party, remover o marcador dele
  local creatureId = creature:getId()
  if partyMinimapMarkers[creatureId] and not creature:isPartyMember() then
    removePartyMemberFromMinimap(creatureId)
  end
end

function onPartyMemberShowStatusChange(creature, showStatus)
  if not creature then
    return
  end

  if not PartyClass or not PartyClass.panel then
    return
  end

  if showStatus then
    -- Verificar se a criatura é um player e membro da party
    if creature:isPlayer() and creature:isPartyMember() then
      PartyClass:addPartyMember(creature)
      -- Adicionar marcador no minimap
      addPartyMemberToMinimap(creature)
    end
  else
    PartyClass:removePartyMember(creature)
    -- Remover marcador do minimap
    removePartyMemberFromMinimap(creature:getId())
  end
end
