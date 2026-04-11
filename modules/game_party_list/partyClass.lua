if not PartyClass then
  PartyClass = {}
  PartyClass.__index = PartyClass
end


PartyClass.ageNumber = 1
PartyClass.window = nil
PartyClass.ages = {}
PartyClass.secondary = false
PartyClass.showFilters = true
PartyClass.panel = nil
PartyClass.filterPanel = nil
PartyClass.toggleFilterButton = nil
PartyClass.name = ""
PartyClass.sortType = {
  [1] = "byAgeAscending",
  [2] = "byAgeAscending",   -- ??
}
PartyClass.sortData = {}
PartyClass.spectators = {}
PartyClass.players = {}
PartyClass.partyButtons = {}
PartyClass.lastAge = 0
PartyClass.hideButtons = {}
PartyClass.knownPartyMembers = {} -- Cache de membros conhecidos da party (ID -> dados básicos)
PartyClass.partyListMenuCreature = nil -- Variável para marcar quando o menu é criado a partir do party list

function PartyClass:configure()
  PartyClass.ageNumber = 1
  PartyClass.window = nil
  PartyClass.ages = {}
  PartyClass.secondary = false
  PartyClass.showFilters = true
  PartyClass.panel = nil
  PartyClass.filterPanel = nil
  PartyClass.toggleFilterButton = nil
  PartyClass.name = ""
  PartyClass.players = {}
  PartyClass.sortType = {
    [1] = "byAgeAscending",
    [2] = "byAgeAscending",     -- ??
  }
  PartyClass.partyButtons = {}
  PartyClass.lastAge = 0
  PartyClass.hideButtons = {}
  PartyClass.knownPartyMembers = {}
  PartyClass.knownPartyMembers = {}
end

function PartyClass:setup(windowId, window)
  if not window then
    PartyClass.window = g_ui.createWidget('partyList', modules.game_interface.getContainerPanel())
    PartyClass.window:setId("PartyWindow_" .. windowId)
    PartyClass.window:close()
  else
    PartyClass.window = window
  end

  PartyClass.window.instance = windowId - 1
  PartyClass.window.bid = windowId
  local scrollbar = PartyClass.window:getChildById('miniwindowScrollBar')
  scrollbar:mergeStyle({ ['$!on'] = {} })
  
  -- Configurar scrollbar para começar apenas depois do separator
  local separator = PartyClass.window:getChildById('separator')
  if scrollbar and separator then
    scrollbar:breakAnchors()
    scrollbar:addAnchor(AnchorTop, separator:getId(), AnchorBottom)
    scrollbar:addAnchor(AnchorRight, 'parent', AnchorRight)
    scrollbar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
    scrollbar:setMarginTop(2)
    scrollbar:setMarginRight(3)
    scrollbar:setMarginBottom(3)
  end

  -- Configurar botão de contexto (options)
  local contextMenuButton = PartyClass.window:recursiveGetChildById('contextMenuButton')
  if contextMenuButton then
    contextMenuButton.onClick = function(widget, mousePos, mouseButton)
      return PartyClass:onFilterPopup(widget, mousePos, mouseButton)
    end
  end

  -- Configurar botão de toggle filter (esconder/mostrar ícones de filtro)
  local toggleFilterButton = PartyClass.window:recursiveGetChildById('toggleFilterButton')
  if toggleFilterButton then
    toggleFilterButton:setOn(true) -- Começa com filtros visíveis
    toggleFilterButton.onClick = function()
      modules.game_party_list.toggleFilterPanel(PartyClass.window)
      toggleFilterButton:setOn(PartyClass.showFilters)
    end
  end
  PartyClass.toggleFilterButton = toggleFilterButton

  -- Remover botão de nova janela (não faz sentido para partylist)
  local newWindowButton = PartyClass.window:recursiveGetChildById('newWindowButton')
  if newWindowButton then
    newWindowButton:destroy()
  end

  local partyPanel = PartyClass.window:recursiveGetChildById('partyPanel')
  partyPanel:setId("partyPanel_" .. windowId)
  partyPanel.createButton = function()
    local partyButton = g_ui.createWidget('PartyCreatureButton')
    partyButton:setHeight(26)

    -- Handler para hover (mostra borda branca ao passar o mouse)
    partyButton.onHoverChange = function(self, hovered)
      if self.creature then
        self.isHovered = hovered
        self:update()
      end
    end

    partyButton.onMouseRelease = function(self, mousePosition, mouseButton)
      if not self.creature then
        return false
      end

      if mouseButton == MouseLeftButton and not g_mouse.isPressed(MouseRightButton) then
        -- Left click performs LOOK on party members
        g_game.look(self.creature, true)
        return true
      elseif mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
        if self.creature then
          PartyClass.partyListMenuCreature = self.creature
          local success, result = pcall(function()
            modules.game_interface.createThingMenu(mousePosition, nil, nil, self.creature)
          end)
          if not success then
            -- Se createThingMenu falhou (ex: criatura sem posição), criar menu manualmente apenas com Exiva
            local menu = g_ui.createWidget('PopupMenu')
            menu:setGameMenu(true)
            local creatureName = nil
            if self.creature.getName then
              creatureName = self.creature:getName()
            end
            if not creatureName and self.creature.getId then
              local creatureId = self.creature:getId()
              if PartyClass.window and PartyClass.window.instance then
                local instance = PartyClass.window.instance
                if instance and instance.knownPartyMembers and instance.knownPartyMembers[creatureId] then
                  creatureName = instance.knownPartyMembers[creatureId].name
                end
              end
            end
            if creatureName then
              menu:addOption(tr('Exiva'), function()
                g_game.talk(string.format('exiva "%s"', creatureName))
              end)
            end
            menu:display(mousePosition)
          end
          PartyClass.partyListMenuCreature = nil
        end
        return true
      end
      return false
    end
    return partyButton
  end

  PartyClass.panel = partyPanel

  local _filterPanel = PartyClass.window:recursiveGetChildById('filterPanel')
  PartyClass.filterPanel = _filterPanel
  PartyClass.window:setContentMinimumHeight(56)
  
  -- Configurar botões de filtro
  if _filterPanel then
    PartyClass.hideButtons.showPlayers = _filterPanel:getChildById('showPlayers')
    PartyClass.hideButtons.showKnights = _filterPanel:getChildById('showKnights')
    PartyClass.hideButtons.showPaladins = _filterPanel:getChildById('showPaladins')
    PartyClass.hideButtons.showDruids = _filterPanel:getChildById('showDruids')
    PartyClass.hideButtons.showSorcerers = _filterPanel:getChildById('showSorcerers')
    PartyClass.hideButtons.showMonks = _filterPanel:getChildById('showMonks')
    PartyClass.hideButtons.showSummons = _filterPanel:getChildById('showSummons')
    
    -- Inicializa todos os botões como checked (mostrar todas as classes)
    if PartyClass.hideButtons.showPlayers then PartyClass.hideButtons.showPlayers:setChecked(false) end
    if PartyClass.hideButtons.showKnights then PartyClass.hideButtons.showKnights:setChecked(false) end
    if PartyClass.hideButtons.showPaladins then PartyClass.hideButtons.showPaladins:setChecked(false) end
    if PartyClass.hideButtons.showDruids then PartyClass.hideButtons.showDruids:setChecked(false) end
    if PartyClass.hideButtons.showSorcerers then PartyClass.hideButtons.showSorcerers:setChecked(false) end
    if PartyClass.hideButtons.showMonks then PartyClass.hideButtons.showMonks:setChecked(false) end
    if PartyClass.hideButtons.showSummons then PartyClass.hideButtons.showSummons:setChecked(false) end
  end

  PartyClass.window.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseRightButton and not g_mouse.isPressed(MouseLeftButton) then
      local child = widget:recursiveGetChildByPos(mousePos)

      -- Se clicar na creature não abre esse menu
      if child and child:getClassName() == "UIRealCreatureButton" then
        return
      end

      PartyClass:onFilterPopup(widget, mousePos, mouseButton)
    end
  end

  -- setup
  PartyClass.window:setup()

  -- Configurar handlers para minimize/maximize para esconder/mostrar filterPanel e separator
  local originalOnMinimize = PartyClass.window.onMinimize
  PartyClass.window.onMinimize = function(...)
    if originalOnMinimize then
      originalOnMinimize(...)
    end
    if PartyClass.filterPanel then
      PartyClass.filterPanel:hide()
    end
    local separator = PartyClass.window:getChildById('separator')
    if separator then
      separator:hide()
    end
  end

  local originalOnMaximize = PartyClass.window.onMaximize
  PartyClass.window.onMaximize = function(...)
    if originalOnMaximize then
      originalOnMaximize(...)
    end
    if PartyClass.filterPanel and PartyClass.showFilters then
      PartyClass.filterPanel:show()
    end
    local separator = PartyClass.window:getChildById('separator')
    if separator and PartyClass.showFilters then
      separator:show()
    end
  end

  -- Garantir que o nome esteja configurado no título
  if not self.name or self.name == '' then
    self.name = tr('Party List')
  end
  local titleLabel = PartyClass.window:recursiveGetChildById('miniwindowTitle')
  if titleLabel then
    titleLabel:setText(self.name)
  end
end

function PartyClass:getWindow()
  return PartyClass.window
end

function PartyClass:getButtons()
  return PartyClass.buttons
end

function PartyClass:getToggleFilterButton()
  return PartyClass.toggleFilterButton
end

function PartyClass:getFilterPanel()
  return PartyClass.filterPanel
end

-- Extra functions
function PartyClass:onFilterPopup(widget, mousePos, mouseButton)
  local menu = g_ui.createWidget('PopupMenu')
  menu:setGameMenu(true)
  menu:addOption(tr('Edit Name'), function() self:displayEditName() end)
  menu:addSeparator()
  menu:addCheckBox(tr('Sort Ascending by Display Time'), self.sortType[1] == 'byAgeAscending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byAgeAscending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Descending by Display Time'), self.sortType[1] == 'byAgeDescending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byAgeDescending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Ascending by Distance'), self.sortType[1] == 'byDistanceAscending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byDistanceAscending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Descending by Distance'), self.sortType[1] == 'byDistanceDescending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byDistanceDescending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Ascending by Hit Points'), self.sortType[1] == 'byHitpointsAscending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byHitpointsAscending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Descending by Hit Points'), self.sortType[1] == 'byHitpointsDescending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byHitpointsDescending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Ascending by Name'), self.sortType[1] == 'byNameAscending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byNameAscending'
        PartyClass:checkCreatures()
      end
    end)
  menu:addCheckBox(tr('Sort Descending by Name'), self.sortType[1] == 'byNameDescending',
    function(checkBox, checked)
      if checked then
        self.sortType[1] = 'byNameDescending'
        PartyClass:checkCreatures()
      end
    end)
  local menuPos = mousePos or g_window.getMousePosition()
  menu:display(menuPos)
  return true
end

function PartyClass:setName(newName)
  self.name = newName
  local titleLabel = self.window:recursiveGetChildById('miniwindowTitle')
  if titleLabel then
    if newName ~= '' then
      titleLabel:setText(newName)
    else
      titleLabel:setText(tr('Party List'))
    end
  end
end

function PartyClass:displayEditName()
  if editNameBattleWindow then
    editNameBattleWindow:destroy()
    editNameBattleWindow = nil
  end


  editNameBattleWindow = g_ui.displayUI("newName")


  local function cancel()
    editNameBattleWindow:hide()
    editNameBattleWindow:destroy()
    editNameBattleWindow = nil
  end
  local function okCallback()
    local text = editNameBattleWindow.contentPanel.newName:getText()
    self:setName(text)
    editNameBattleWindow:hide()
    editNameBattleWindow:destroy()
    editNameBattleWindow = nil
  end

  editNameBattleWindow.onEscape = cancel
  editNameBattleWindow.onEnter = okCallback
  editNameBattleWindow.contentPanel.newName:focus()
  editNameBattleWindow.contentPanel.newName:setText(self.name)

  editNameBattleWindow.contentPanel.cancel.onClick = cancel
  editNameBattleWindow.contentPanel.ok.onClick = okCallback
end

function PartyClass:registerInSideBars()
  -- O salvamento de posição é gerenciado automaticamente pelo CharMiniWindows
  -- quando &save: true está configurado no PartyListWindow (partyList.otui)
  -- A função restorePosition() do UIMiniWindow restaura a posição ao logar
end

function PartyClass.setFilter(self, filter, value)
  scheduleEvent(function()
    PartyClass:checkCreatures()
  end, 50)
end

function PartyClass:checkCreatures()
  if not self.panel or not g_game.isOnline() then
    return false
  end

  -- Remove todos os botões existentes primeiro
  self:removeAllCreatures()

  -- Reconstrói lista baseado nos membros conhecidos (aqueles com showStatus = true do servidor)
  for creatureId, cachedData in pairs(self.knownPartyMembers) do
    local creature = g_map.getCreatureById(creatureId)
    if creature then
      -- Verifica se a criatura passa nos filtros (vocation)
      if self:doCreatureFitFilters(creature, false) then
        self:addCreature(creature)
      end
    end
  end
end

function PartyClass:doCreatureFitFilters(creature, checkVisibility)
  if not creature then
    return false
  end

  -- Verificar se a criatura é um player e membro da party (não apenas showStatus do servidor)
  if not creature:isPlayer() or not creature:isPartyMember() then
    return false
  end

  if creature:isLocalPlayer() then
    return false
  end

  if creature:isDead() then
    return false
  end

  -- Aplicar filtros de classe (vocation)
  -- Quando o botão está checked (pressionado), ele esconde a classe correspondente
  if self.hideButtons then
    if self.hideButtons.showPlayers and self.hideButtons.showPlayers:isChecked() and creature:isPlayer() then
      return false
    end
    if self.hideButtons.showKnights and self.hideButtons.showKnights:isChecked() and creature:isKnight() then
      return false
    end
    if self.hideButtons.showPaladins and self.hideButtons.showPaladins:isChecked() and creature:isPaladin() then
      return false
    end
    if self.hideButtons.showDruids and self.hideButtons.showDruids:isChecked() and creature:isDruid() then
      return false
    end
    if self.hideButtons.showSorcerers and self.hideButtons.showSorcerers:isChecked() and creature:isSorcerer() then
      return false
    end
    if self.hideButtons.showMonks and self.hideButtons.showMonks:isChecked() and creature:isMonk() then
      return false
    end
    if self.hideButtons.showSummons and self.hideButtons.showSummons:isChecked() then
      local masterId = creature:getMasterId()
      if masterId and masterId > 0 then
        return false
      end
    end
  end

  return true
end

function getDistanceBetween(pos1, pos2)
  return math.max(math.abs(pos1.x - pos2.x), math.abs(pos1.y - pos2.y))
end

function PartyClass:addCreature(creature)
  local creatureId = creature:getId()
  local partyButton = self.partyButtons[creatureId]
  
  if partyButton then
    if partyButton.creature then
      partyButton:update()
      -- Atualiza barras de vida
      partyButton:setLifeBarPercent(creature:getHealthPercent())
      -- Atualiza shield
      if partyButton.updateShield then
        partyButton:updateShield(creature:getShield())
      end
      -- Atualiza cor do texto para normal (visível)
      local labelWidget = partyButton:getChildById('label')
      if labelWidget then
        labelWidget:setColor('#888888')
      end
    end
  else
    if creature:getPosition() == nil then
      return
    end
    
    partyButton = self.panel.createButton()
    if not partyButton then
      return
    end
    
    partyButton:setup(creature, true)
    partyButton:show()
    
    self.partyButtons[creatureId] = partyButton
    self.panel:addChild(partyButton)
    self.lastAge = self.lastAge + 1
  end
  
  if self.panel then
    self.panel:getLayout():update()
  end
end

function PartyClass:addCreatureInactive(creature, cachedData)
  local creatureId = creature:getId()
  local partyButton = self.partyButtons[creatureId]
  
  if partyButton then
    -- Atualiza botão existente para estado inativo
    partyButton:setLifeBarPercent(0)
    -- Texto cinza
    local labelWidget = partyButton:getChildById('label')
    if labelWidget then
      labelWidget:setColor('#666666')
    end
  else
    -- Cria novo botão para criatura inativa
    partyButton = self.panel.createButton()
    if not partyButton then
      return
    end
    
    partyButton:setup(creature, true)
    
    -- Define estado inativo (barras vazias, texto cinza)
    partyButton:setLifeBarPercent(0)
    local labelWidget = partyButton:getChildById('label')
    if labelWidget then
      labelWidget:setColor('#666666')
    end
    
    partyButton:show()
    
    self.partyButtons[creatureId] = partyButton
    self.panel:addChild(partyButton)
    self.lastAge = self.lastAge + 1
  end
  
  if self.panel then
    self.panel:getLayout():update()
  end
end

function PartyClass:removeAllCreatures()
  for creatureId, button in pairs(self.partyButtons) do
    if button and button:getParent() then
      button:getParent():removeChild(button)
    end
  end
  self.partyButtons = {}
end

-- Adiciona membro da party baseado no showStatus do servidor
function PartyClass:addPartyMember(creature)
  if not self.panel or not creature then
    return
  end

  local creatureId = creature:getId()

  -- Verifica se já existe
  if self.partyButtons[creatureId] then
    -- Apenas atualiza
    local button = self.partyButtons[creatureId]
    if button and button.creature then
      button:update()
      button:setLifeBarPercent(creature:getHealthPercent())
      button:setManaBarPercent(creature:getManaPercent())
    end
    return
  end

  -- Verifica filtros antes de adicionar
  if not self:doCreatureFitFilters(creature, false) then
    return
  end

  -- Cria novo botão
  local partyButton = self.panel.createButton()
  if not partyButton then
    return
  end

  partyButton:setup(creature, true)
  partyButton:show()

  self.partyButtons[creatureId] = partyButton
  self.panel:addChild(partyButton)
  self.lastAge = self.lastAge + 1

  -- Atualiza cache
  self.knownPartyMembers[creatureId] = {
    id = creatureId,
    name = creature:getName(),
    outfit = creature:getOutfit(),
    healthPercent = creature:getHealthPercent(),
    manaPercent = creature:getManaPercent(),
    visible = true
  }

  if self.panel then
    self.panel:getLayout():update()
  end
end

-- Remove membro da party baseado no showStatus do servidor
function PartyClass:removePartyMember(creature)
  if not creature then
    return
  end

  local creatureId = creature:getId()
  local button = self.partyButtons[creatureId]

  if button then
    if button:getParent() then
      button:getParent():removeChild(button)
    end
    self.partyButtons[creatureId] = nil
  end

  -- Remove do cache também
  self.knownPartyMembers[creatureId] = nil

  if self.panel then
    self.panel:getLayout():update()
  end
end

