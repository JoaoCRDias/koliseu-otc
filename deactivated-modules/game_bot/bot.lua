botWindow = nil
botButton = nil
contentsPanel = nil
editWindow = nil

-- Modal window variables
botModalWindow = nil
currentSection = "overview"  -- Default to overview section
botEnabled = false

local checkEvent = nil

local botStorage = {}
local botStorageFile = nil
local botWebSockets = {}
local botMessages = nil
local botTabs = nil
local botExecutor = nil

local configList = nil
local enableButton = nil
local executeEvent = nil
local statusLabel = nil

local configManagerUrl = "http://otclient.ovh/configs.php"

-- BTC Bot Menu Sections (nossa interface bonita)
local menuSections = {
  { id = "overview", name = "Overview", icon = "/images/btcbot/overview.png" },
  { id = "healing", name = "Healing", icon = "/images/btcbot/healing.png" },
  { id = "healfriend", name = "Heal Friend", icon = "/images/btcbot/healfriend.png" },
  { id = "mana", name = "Mana", icon = "/images/btcbot/mana.png" },
  { id = "attack", name = "Attack", icon = "/images/btcbot/attack.png" },
  { id = "cavebot", name = "CaveBot", icon = "/images/btcbot/cavebot.png" },
  { id = "tools", name = "Tools", icon = "/images/btcbot/tools.png" },
  { id = "equipment", name = "Ring/Amulet", icon = "/images/btcbot/equipment.png" },
  { id = "time", name = "Time", icon = "/images/btcbot/tools.png" },
  { id = "quiver", name = "Quiver", icon = "/images/btcbot/tools.png" },
  { id = "settings", name = "Settings", icon = "/images/btcbot/settings.png" },
}

-- BTC Bot Instance
BTCBot = nil
BTCHealing = nil
BTCHealFriend = nil
BTCMana = nil
BTCAttack = nil
BTCCaveBot = nil
BTCConfig = nil
BTCQuiver = nil

function init()
  dofile("executor")

  g_ui.importStyle("ui/basic.otui")
  g_ui.importStyle("ui/panels.otui")
  g_ui.importStyle("ui/config.otui")
  g_ui.importStyle("ui/icons.otui")
  g_ui.importStyle("ui/container.otui")
  g_ui.importStyle("botmodal.otui")

  -- Load BTC Bot modules
  dofile("btcbot/config")
  dofile("btcbot/healing")
  dofile("btcbot/healfriend")
  dofile("btcbot/mana")
  dofile("btcbot/attack")
  dofile("btcbot/targeting")
  dofile("btcbot/cavebot")
  dofile("btcbot/tools")
  dofile("btcbot/equipment")
  dofile("btcbot/time")
  dofile("btcbot/quiver")
  dofile("btcbot/icons")
  dofile("btcbot/btcbot")
  
  -- Initialize BTC Bot
  BTCConfig.init()
  BTCHealing.init()
  BTCHealFriend.init()
  BTCMana.init()
  BTCAttack.init()
  BTCTargeting.init()
  BTCCaveBot.init()
  BTCTools.init()
  BTCEquipment.init()
  BTCTime.init()
  BTCQuiver.init()
  BTCBot.init()  -- Inicia o loop principal (necessario para recording)

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  initCallbacks()

  -- Create toggle button that opens the modal
  botButton = modules.game_mainpanel.addSpecialToggleButton('botButton', tr('Bot'), '/images/options/bot', toggle, false, 100)
  botButton:setOn(false)
  botButton:show()
  botButton:setImageColor('#FFD700')

  -- Load original miniwindow (hidden, used internally for bot execution)
  botWindow = g_ui.loadUI('bot', modules.game_interface.getLeftPanel())
  botWindow:setup()
  botWindow:hide()

  contentsPanel = botWindow.contentsPanel
  configList = contentsPanel.config
  enableButton = contentsPanel.enableButton
  statusLabel = contentsPanel.statusLabel
  botMessages = contentsPanel.messages
  botTabs = contentsPanel.botTabs
  botTabs:setContentWidget(contentsPanel.botPanel)

  editWindow = g_ui.displayUI('edit')
  editWindow:hide()

  if g_game.isOnline() then
    clear()
    online()
  end
end

function terminate()
  save()
  clear()

  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  terminateCallbacks()
  editWindow:destroy()

  if botModalWindow then
    botModalWindow:destroy()
    botModalWindow = nil
  end

  botWindow:destroy()
  botButton:destroy()
end

function clear()
  botExecutor = nil
  removeEvent(checkEvent)

  if BTCBotIcons then
    BTCBotIcons.widgets = {}
  end

  -- optimization, callback is not used when not needed
  g_game.enableTileThingLuaCallback(false)

  botTabs:clearTabs()
  botTabs:setOn(false)

  botMessages:destroyChildren()
  botMessages:updateLayout()

  for i, socket in pairs(botWebSockets) do
    HTTP.cancel(i)
    botWebSockets[i] = nil
  end

  for i, widget in pairs(g_ui.getRootWidget():getChildren()) do
    if widget.botWidget then
      widget:destroy()
    end
  end
  for i, widget in pairs(modules.game_interface.gameMapPanel:getChildren()) do
    if widget.botWidget then
      widget:destroy()
    end
  end
  for _, widget in pairs({modules.game_interface.getRightPanel(), modules.game_interface.getLeftPanel()}) do
    for i, child in pairs(widget:getChildren()) do
      if child.botWidget then
        child:destroy()
      end
    end
  end

  local gameMapPanel = modules.game_interface.getMapPanel()
  if gameMapPanel then
    gameMapPanel:unlockVisibleFloor()
  end

  if g_sounds then
    g_sounds.getChannel(SoundChannels.Bot):stop()
  end
end

function refresh()
  if not g_game.isOnline() then return end
  save()
  clear()

  -- create bot dir
  if not g_resources.directoryExists("/bot") then
    g_resources.makeDir("/bot")
    if not g_resources.directoryExists("/bot") then
      return onError("Can't create bot directory in " .. g_resources.getWriteDir())
    end
  end

  -- get list of configs
  createDefaultConfigs()
  local configs = g_resources.listDirectoryFiles("/bot", false, false)

  -- clean
  configList.onOptionChange = nil
  enableButton.onClick = nil
  configList:clearOptions()

  -- select active config based on settings
  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  if settings[index] == nil then
    settings[index] = {
      enabled=false,
      config=""
    }
  end

  -- init list and buttons
  for i=1,#configs do
    configList:addOption(configs[i])
  end
  configList:setCurrentOption(settings[index].config)
  if configList:getCurrentOption().text ~= settings[index].config then
    settings[index].config = configList:getCurrentOption().text
    settings[index].enabled = false
  end

  enableButton:setOn(settings[index].enabled)

  configList.onOptionChange = function(widget)
    settings[index].config = widget:getCurrentOption().text
    g_settings.setNode('bot', settings)
    g_settings.save()
    refresh()
  end

  enableButton.onClick = function(widget)
    settings[index].enabled = not settings[index].enabled
    g_settings.setNode('bot', settings)
    g_settings.save()
    refresh()
  end

  if not g_game.isOnline() or not settings[index].enabled then
    statusLabel:setOn(true)
    statusLabel:setText("Status: disabled\nPress off button to enable")
    analyzerButton = modules.game_mainpanel.getButton("botAnalyzersButton")
    if analyzerButton then
      analyzerButton:destroy()
    end
    -- Update modal indicator
    updateBotIndicator()
    return
  end

  local configName = settings[index].config

  -- storage
  botStorage = {}

  local path = "/bot/" .. configName .. "/storage/"
  if not g_resources.directoryExists(path) then
    g_resources.makeDir(path)
  end

  botStorageFile = path.."profile_" .. g_settings.getNumber('profile') .. ".json"
  if g_resources.fileExists(botStorageFile) then
    local status, result = pcall(function()
      return json.decode(g_resources.readFileContents(botStorageFile))
    end)
    if not status then
      return onError("Error while reading storage (" .. botStorageFile .. "). To fix this problem you can delete storage.json. Details: " .. result)
    end
    botStorage = result
  end

  -- run script
  local status, result = pcall(function()
    return executeBot(configName, botStorage, botTabs, message, save, refresh, botWebSockets) end
  )
  if not status then
    updateBotIndicator()
    return onError(result)
  end

  statusLabel:setOn(false)
  botExecutor = result
  check()
  
  -- Update modal indicator
  updateBotIndicator()
end

function save()
  if not botExecutor then
    return
  end

  local settings = g_settings.getNode('bot') or {}
  local index = g_game.getCharacterName() .. "_" .. g_game.getClientVersion()
  if settings[index] == nil then
    return
  end

  local status, result = pcall(function()
    return json.encode(botStorage, 2)
  end)
  if not status then
    return onError("Error while saving bot storage. Storage won't be saved. Details: " .. result)
  end

  if result:len() > 100 * 1024 * 1024 then
    return onError("Storage file is too big, above 100MB, it won't be saved")
  end

  g_resources.writeFileContents(botStorageFile, result)
end

function onMiniWindowClose()
  botButton:setOn(false)
end

function toggle()
  if botModalWindow and botModalWindow:isVisible() then
    hideModal()
    botButton:setOn(false)
  else
    showModal()
    botButton:setOn(true)
  end
end

function showModal()
  if not botModalWindow then
    botModalWindow = g_ui.createWidget('BotModalWindow', rootWidget)
    if not botModalWindow then
      g_logger.error("[BOT] Failed to create BotModalWindow")
      return
    end
  end
  
  botModalWindow:show()
  botModalWindow:raise()
  botModalWindow:focus()
  
  -- Update toggle button state based on BTC Bot
  local toggleBtn = botModalWindow:recursiveGetChildById('toggleBotButton')
  if toggleBtn then
    toggleBtn:setOn(BTCBot and BTCBot.enabled or false)
  end
  
  -- Update indicator based on bot status
  updateBotIndicator()
  
  -- Verifica se trocou de personagem e recarrega configs
  if BTCConfig and BTCConfig.checkCharacterChange then
    if BTCConfig.checkCharacterChange() then
      -- Recarrega todos os modulos com as novas configs
      BTCHealing.init()
      BTCHealFriend.init()
      BTCMana.init()
      BTCAttack.init()
      BTCTargeting.init()
      BTCCaveBot.init()
      BTCTools.init()
      BTCEquipment.init()
      BTCTime.init()
    end
  end
  
  -- Sempre reseta para Overview quando abre o bot
  currentSection = "overview"
  
  -- Create menu with BTC Bot sections (agora currentSection ja e "overview")
  createModalMenu()
  
  -- Mostra a secao overview
  showSection(currentSection)
end

function hideModal()
  if botModalWindow then
    botModalWindow:hide()
  end
  botButton:setOn(false)
end

-- Get list of vBot tabs
function getBotTabs()
  local tabs = {}
  if not botTabs then return tabs end
  
  local tabButtons = botTabs:getTabs()
  if not tabButtons then return tabs end
  
  for _, tabBtn in ipairs(tabButtons) do
    local tabData = botTabs:getTabPanel(tabBtn)
    if tabData then
      table.insert(tabs, {
        name = tabBtn:getText(),
        button = tabBtn,
        panel = tabData
      })
    end
  end
  
  return tabs
end

function createModalMenu()
  if not botModalWindow then return end
  
  local menuContent = botModalWindow:recursiveGetChildById('menuContent')
  if not menuContent then return end
  
  menuContent:destroyChildren()
  
  -- Create menu buttons for BTC Bot sections
  local overviewBtn = nil
  local allButtons = {}
  
  for i, section in ipairs(menuSections) do
    local btn = g_ui.createWidget('BotMenuButton', menuContent)
    btn:setId('menuBtn_' .. section.id)
    btn:setText(section.name)
    btn.sectionId = section.id
    btn.sectionName = section.name
    
    -- Garantir que todos os botoes comecem desligados
    btn:setOn(false)
    
    -- Set icon if available
    if section.icon then
      btn:setIcon(section.icon)
    end
    
    btn.onClick = function(widget)
      selectMenuButton(widget)
      showSection(widget.sectionId)
    end
    
    -- Guarda referencia do botao overview
    if section.id == "overview" then
      overviewBtn = btn
    end
    
    table.insert(allButtons, btn)
  end
  
  -- Agora seleciona APENAS o botao da section atual (ou overview como padrao)
  local btnToSelect = nil
  for _, btn in ipairs(allButtons) do
    if btn.sectionId == currentSection then
      btnToSelect = btn
      break
    end
  end
  
  -- Se nao encontrou, usa overview como fallback
  if not btnToSelect then
    btnToSelect = overviewBtn or allButtons[1]
    if btnToSelect then
      currentSection = btnToSelect.sectionId
    end
  end
  
  -- Ativa apenas o botao selecionado
  if btnToSelect then
    btnToSelect:setOn(true)
  end
end

function selectMenuButton(selectedBtn)
  if not botModalWindow then return end
  
  local menuContent = botModalWindow:recursiveGetChildById('menuContent')
  if not menuContent then return end
  
  -- Deselect all buttons
  for _, child in ipairs(menuContent:getChildren()) do
    if child.sectionId then
      child:setOn(false)
    end
  end
  
  -- Select the clicked button
  selectedBtn:setOn(true)
  currentSection = selectedBtn.sectionId
end

-- Store original parent of moved content
local movedContent = nil
local movedContentOriginalParent = nil

-- Restore tab content back to original parent when closing modal or switching tabs
function restoreTabContent()
  if movedContent and movedContentOriginalParent then
    -- Move content back to original parent
    pcall(function()
      movedContent:setParent(movedContentOriginalParent)
    end)
    movedContent = nil
    movedContentOriginalParent = nil
  end
end

function showSection(sectionId)
  if not botModalWindow then return end
  
  local contentPanel = botModalWindow:recursiveGetChildById('contentPanel')
  local sectionTitle = botModalWindow:recursiveGetChildById('sectionTitle')
  local sectionToggleBtn = botModalWindow:recursiveGetChildById('sectionToggleBtn')
  
  if not contentPanel or not sectionTitle then return end
  
  -- Clear content panel
  contentPanel:destroyChildren()
  
  -- Find section name
  local sectionName = sectionId
  for _, section in ipairs(menuSections) do
    if section.id == sectionId then
      sectionName = section.name
      break
    end
  end
  
  -- Update title
  sectionTitle:setText(sectionName)
  
  -- Secoes que tem botao ON/OFF (modulos funcionais)
  local sectionsWithToggle = {
    healing = { module = "BTCHealing", configKey = "healingEnabled" },
    healfriend = { module = "BTCHealFriend", configKey = "healfriendEnabled" },
    mana = { module = "BTCMana", configKey = "manaEnabled" },
    attack = { module = "BTCAttack", configKey = "attackEnabled" },
    cavebot = { module = "BTCCaveBot", configKey = "cavebotEnabled" },
    tools = { module = "BTCTools", configKey = "toolsEnabled" },
    equipment = { module = "BTCEquipment", configKey = "equipmentEnabled" },
    time = { module = "BTCTime", configKey = "timeEnabled" },
    quiver = { module = "BTCQuiver", configKey = "quiverEnabled" },
  }
  
  -- Configura o botao ON/OFF da secao
  if sectionToggleBtn then
    local sectionInfo = sectionsWithToggle[sectionId]
    if sectionInfo then
      sectionToggleBtn:setVisible(true)
      
      -- Pega estado atual do modulo
      local isEnabled = false
      if sectionId == "cavebot" and BTCCaveBot and BTCCaveBot.config then
        isEnabled = BTCCaveBot.config.enabled or false
      elseif sectionId == "healing" and BTCHealing and BTCHealing.config then
        isEnabled = BTCHealing.config.enabled or false
      elseif sectionId == "healfriend" and BTCHealFriend and BTCHealFriend.config then
        isEnabled = BTCHealFriend.config.enabled or false
      elseif sectionId == "mana" and BTCMana and BTCMana.config then
        isEnabled = BTCMana.config.enabled or false
      elseif sectionId == "attack" and BTCAttack and BTCAttack.config then
        isEnabled = BTCAttack.config.enabled or false
      elseif sectionId == "tools" and BTCTools and BTCTools.config then
        isEnabled = BTCTools.config.enabled or false
      elseif sectionId == "equipment" and BTCEquipment and BTCEquipment.config then
        isEnabled = BTCEquipment.config.enabled or false
      elseif sectionId == "time" and BTCTime and BTCTime.config then
        isEnabled = BTCTime.config.enabled or false
      elseif sectionId == "quiver" and BTCQuiver and BTCQuiver.config then
        isEnabled = BTCQuiver.config.enabled or false
      else
        isEnabled = BTCConfig and BTCConfig.get(sectionInfo.configKey) or false
      end
      updateSectionToggleBtn(sectionToggleBtn, isEnabled)
      
      -- Configura callback
      sectionToggleBtn.onClick = function()
        local newState = false
        
        -- Toggle o estado do modulo
        if sectionId == "cavebot" and BTCCaveBot and BTCCaveBot.config then
          BTCCaveBot.config.enabled = not BTCCaveBot.config.enabled
          newState = BTCCaveBot.config.enabled
          -- Se ligou o CaveBot e Auto Record esta ON, desliga o Auto Record
          if newState and BTCCaveBot.recordingEnabled then
            BTCCaveBot.toggleRecording()
            if BTCCaveBot.autoRecordBtn then
              BTCCaveBot.autoRecordBtn:setText('Auto Record: OFF')
              BTCCaveBot.autoRecordBtn:setColor('#ff4444')
            end
            print("[CaveBot] Auto Record desligado automaticamente ao ligar CaveBot")
          end
          BTCCaveBot.saveConfig()
          if BTCCaveBot.refreshWaypointList then
            BTCCaveBot.refreshWaypointList()
          end
          print("[CaveBot] " .. (newState and "LIGADO" or "DESLIGADO"))
        elseif sectionId == "healing" and BTCHealing and BTCHealing.config then
          BTCHealing.config.enabled = not BTCHealing.config.enabled
          newState = BTCHealing.config.enabled
          BTCHealing.saveConfig()
        elseif sectionId == "healfriend" and BTCHealFriend and BTCHealFriend.config then
          BTCHealFriend.config.enabled = not BTCHealFriend.config.enabled
          newState = BTCHealFriend.config.enabled
          BTCHealFriend.saveConfig()
        elseif sectionId == "mana" and BTCMana and BTCMana.config then
          BTCMana.config.enabled = not BTCMana.config.enabled
          newState = BTCMana.config.enabled
          BTCMana.saveConfig()
        elseif sectionId == "attack" and BTCAttack and BTCAttack.config then
          BTCAttack.config.enabled = not BTCAttack.config.enabled
          newState = BTCAttack.config.enabled
          BTCAttack.saveConfig()
          -- Targeting acompanha o estado do Attack
          if BTCTargeting and BTCTargeting.config then
            BTCTargeting.config.enabled = newState
            BTCTargeting.saveConfig()
          end
        elseif sectionId == "tools" and BTCTools and BTCTools.config then
          BTCTools.config.enabled = not BTCTools.config.enabled
          newState = BTCTools.config.enabled
          BTCTools.saveConfig()
        elseif sectionId == "equipment" and BTCEquipment and BTCEquipment.config then
          BTCEquipment.config.enabled = not BTCEquipment.config.enabled
          newState = BTCEquipment.config.enabled
          BTCEquipment.saveConfig()
        elseif sectionId == "time" and BTCTime and BTCTime.config then
          BTCTime.config.enabled = not BTCTime.config.enabled
          newState = BTCTime.config.enabled
          BTCTime.saveConfig()
        elseif sectionId == "quiver" and BTCQuiver and BTCQuiver.config then
          BTCQuiver.config.enabled = not BTCQuiver.config.enabled
          newState = BTCQuiver.config.enabled
          BTCQuiver.saveConfig()
        else
          local currentState = BTCConfig and BTCConfig.get(sectionInfo.configKey) or false
          newState = not currentState
          if BTCConfig then
            BTCConfig.set(sectionInfo.configKey, newState)
          end
        end
        
        updateSectionToggleBtn(sectionToggleBtn, newState)
        if BTCBotIcons then
          BTCBotIcons.syncStates()
        end
      end
    else
      sectionToggleBtn:setVisible(false)
    end
  end
  
  -- Create content based on section
  if sectionId == "overview" then
    createOverviewUI(contentPanel)
  elseif sectionId == "healing" then
    createHealingUI(contentPanel)
  elseif sectionId == "healfriend" then
    createHealFriendUI(contentPanel)
  elseif sectionId == "mana" then
    createManaUI(contentPanel)
  elseif sectionId == "attack" then
    createAttackUI(contentPanel)
  elseif sectionId == "cavebot" then
    createCaveBotUI(contentPanel)
  elseif sectionId == "tools" then
    createToolsUI(contentPanel)
  elseif sectionId == "equipment" then
    createEquipmentUI(contentPanel)
  elseif sectionId == "time" then
    createTimeUI(contentPanel)
  elseif sectionId == "quiver" then
    createQuiverUI(contentPanel)
  elseif sectionId == "settings" then
    createSettingsUI(contentPanel)
  else
    local label = g_ui.createWidget('Label', contentPanel)
    label:setText('Seção não encontrada: ' .. sectionId)
    label:setColor('#ff4444')
    label:setHeight(20)
  end
end

-- ============================================
-- BTC BOT UI SECTIONS
-- ============================================

function createOverviewUI(parent)
  -- Title
  local title = g_ui.createWidget('Label', parent)
  title:setText('BTC Bot')
  title:setTextAlign(AlignCenter)
  title:setFont('verdana-11px-rounded')
  title:setColor('#00ff88')
  title:setHeight(25)
  title:setMarginBottom(10)
  
  -- Separator
  local sep1 = g_ui.createWidget('HorizontalSeparator', parent)
  sep1:setMarginBottom(10)
  
  -- Personagem atual
  local charTitle = g_ui.createWidget('Label', parent)
  charTitle:setText('Personagem Atual:')
  charTitle:setColor('#aaaaaa')
  charTitle:setMarginBottom(5)
  
  local charName = "Offline"
  if g_game.isOnline() and g_game.getLocalPlayer() then
    charName = g_game.getLocalPlayer():getName()
  end
  
  local charLabel = g_ui.createWidget('Label', parent)
  charLabel:setText('  ' .. charName)
  charLabel:setColor('#00ff88')
  charLabel:setFont('verdana-11px-rounded')
  charLabel:setMarginBottom(15)
  
  -- Separator
  local sep2 = g_ui.createWidget('HorizontalSeparator', parent)
  sep2:setMarginBottom(10)
  
  -- Personagens com config salva
  local savedTitle = g_ui.createWidget('Label', parent)
  savedTitle:setText('Configs Salvas:')
  savedTitle:setColor('#aaaaaa')
  savedTitle:setMarginBottom(5)
  
  if BTCConfig and BTCConfig.getSavedCharacters then
    local chars = BTCConfig.getSavedCharacters()
    if #chars > 0 then
      for _, name in ipairs(chars) do
        local cLabel = g_ui.createWidget('Label', parent)
        local prefix = (name == charName) and '> ' or '  '
        cLabel:setText(prefix .. name)
        cLabel:setColor((name == charName) and '#00ff88' or '#888888')
        cLabel:setHeight(18)
      end
    else
      local noLabel = g_ui.createWidget('Label', parent)
      noLabel:setText('  Nenhuma config salva ainda')
      noLabel:setColor('#666666')
    end
  end
  
  -- Separator
  local sep3 = g_ui.createWidget('HorizontalSeparator', parent)
  sep3:setMarginTop(15)
  sep3:setMarginBottom(10)
  
  -- Info
  local infoLabel = g_ui.createWidget('Label', parent)
  infoLabel:setText('Cada personagem tem suas proprias configs.')
  infoLabel:setColor('#666666')
  infoLabel:setMarginBottom(5)
  
  local infoLabel2 = g_ui.createWidget('Label', parent)
  infoLabel2:setText('Configure os modulos no menu ao lado.')
  infoLabel2:setColor('#666666')
  
  -- Version
  local versionLabel = g_ui.createWidget('Label', parent)
  versionLabel:setText('Versao: 1.0.0')
  versionLabel:setColor('#444444')
  versionLabel:setMarginTop(20)
end

function createHealingUI(parent)
  -- Use BTC Healing module to create UI
  if BTCHealing then
    BTCHealing.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Módulo de Healing não carregado')
    label:setColor('#ff4444')
  end
end

function createHealFriendUI(parent)
  -- Use BTC Heal Friend module to create UI
  if BTCHealFriend then
    BTCHealFriend.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Módulo de Heal Friend não carregado')
    label:setColor('#ff4444')
  end
end

function createManaUI(parent)
  -- Use BTC Mana module to create UI
  if BTCMana then
    BTCMana.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Modulo de Mana nao carregado')
    label:setColor('#ff4444')
  end
end

function createAttackUI(parent)
  -- Use BTC Attack module to create UI
  if BTCAttack then
    BTCAttack.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Modulo de Attack nao carregado')
    label:setColor('#ff4444')
  end
end

function createCaveBotUI(parent)
  -- Usa nosso modulo BTCCaveBot
  if BTCCaveBot and BTCCaveBot.createUI then
    BTCCaveBot.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('CaveBot')
    label:setTextAlign(AlignCenter)
    label:setColor('#ff0000')
    label:setMarginBottom(15)
    
    local infoLabel = g_ui.createWidget('Label', parent)
    infoLabel:setText('Erro: Modulo CaveBot nao carregado')
    infoLabel:setColor('#888888')
  end
end

function createToolsUI(parent)
  if BTCTools then
    BTCTools.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Erro: Modulo Tools nao carregado')
    label:setColor('#888888')
  end
end

function createEquipmentUI(parent)
  if BTCEquipment then
    BTCEquipment.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Erro: Modulo Equipment nao carregado')
    label:setColor('#888888')
  end
end

function createTimeUI(parent)
  if BTCTime then
    BTCTime.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Erro: Modulo Time nao carregado')
    label:setColor('#888888')
  end
end

function createQuiverUI(parent)
  if BTCQuiver then
    BTCQuiver.createUI(parent)
  else
    local label = g_ui.createWidget('Label', parent)
    label:setText('Erro: Modulo Quiver nao carregado')
    label:setColor('#888888')
  end
end

function createSettingsUI(parent)
  local label = g_ui.createWidget('Label', parent)
  label:setText('Settings')
  label:setTextAlign(AlignCenter)
  label:setColor('#00ff88')
  label:setMarginBottom(15)
  
  -- Info do personagem atual
  local charLabel = g_ui.createWidget('Label', parent)
  local charName = "Offline"
  if g_game.isOnline() and g_game.getLocalPlayer() then
    charName = g_game.getLocalPlayer():getName()
  end
  charLabel:setText('Personagem: ' .. charName)
  charLabel:setColor('#aaaaaa')
  charLabel:setMarginBottom(15)
  
  -- Reset config button
  local resetBtn = g_ui.createWidget('Button', parent)
  resetBtn:setText('Resetar Config deste Char')
  resetBtn:setWidth(180)
  resetBtn:setMarginBottom(10)
  resetBtn.onClick = function()
    if BTCConfig then
      BTCConfig.reset()
      BTCHealing.init()
      BTCHealFriend.init()
      BTCMana.init()
      BTCAttack.init()
      BTCTargeting.init()
      BTCCaveBot.init()
      BTCTools.init()
      BTCEquipment.init()
      BTCTime.init()
      BTCQuiver.init()
      displayMessage("Configs resetadas para " .. charName)
      showSection("overview")
    end
  end
  
  -- Lista de chars salvos
  local savedLabel = g_ui.createWidget('Label', parent)
  savedLabel:setText('Personagens com config salva:')
  savedLabel:setColor('#888888')
  savedLabel:setMarginTop(15)
  savedLabel:setMarginBottom(5)
  
  if BTCConfig and BTCConfig.getSavedCharacters then
    local chars = BTCConfig.getSavedCharacters()
    for _, name in ipairs(chars) do
      local cLabel = g_ui.createWidget('Label', parent)
      cLabel:setText('  - ' .. name)
      cLabel:setColor('#aaaaaa')
    end
  end
  
  -- Info
  local infoLabel = g_ui.createWidget('Label', parent)
  infoLabel:setText('Configs sao salvas automaticamente por personagem.')
  infoLabel:setColor('#666666')
  infoLabel:setMarginTop(15)
end

-- Display message to user
function displayMessage(msg)
  -- Could show in-game message or status
  print("[BTC Bot] " .. msg)
end

-- Atualiza visual do botao ON/OFF da secao
function updateSectionToggleBtn(btn, isEnabled)
  if not btn then return end
  if isEnabled then
    btn:setText('ON')
    btn:setColor('#00ff00')
  else
    btn:setText('OFF')
    btn:setColor('#ff4444')
  end
end

function updateBotIndicator()
  if not botModalWindow then return end
  
  -- Check if BTC Bot is enabled
  local isRunning = BTCBot and BTCBot.enabled
  
  -- Also update the toggle button
  local toggleBtn = botModalWindow:recursiveGetChildById('toggleBotButton')
  if toggleBtn then
    toggleBtn:setOn(isRunning)
  end
end

function applySettings()
  -- Save settings
  save()
  
  -- Show confirmation
  displayMessage('Settings applied!')
end

function toggleBotEnabled()
  if not g_game.isOnline() then
    displayMessage("Você precisa estar online!")
    return
  end
  
  -- Toggle BTC Bot
  if BTCBot then
    local newState = BTCBot.toggle()
    botEnabled = newState
    
    -- Update UI
    updateBotIndicator()
    
    displayMessage(newState and "Bot ATIVADO!" or "Bot DESATIVADO!")
  end
end

function online()
  botWindow:setupOnStart()
  -- Keep the miniwindow hidden, we use the modal now
  botWindow:hide()
  botButton:setOn(false)
  
  if not modules.client_profiles.ChangedProfile then
    scheduleEvent(refresh, 20)
  end
  
  -- Update modal info if open
  updateModalInfo()
end

function updateModalInfo()
  if not botModalWindow then return end
  if not botModalWindow:isVisible() then return end
  
  -- Update version label
  local versionLabel = botModalWindow:recursiveGetChildById('versionLabel')
  if versionLabel then
    versionLabel:setText('vBot 4.8 - BTC Bot')
  end
  
  -- Update indicator
  updateBotIndicator()
  
  -- Refresh menu to show current tabs
  createModalMenu()
end

function offline()
  save()
  clear()
  editWindow:hide()
  
  -- Hide modal when going offline
  if botModalWindow then
    botModalWindow:hide()
  end
  botButton:setOn(false)
end

function onError(message)
  statusLabel:setOn(true)
  statusLabel:setText("Error:\n" .. message)
  g_logger.error("[BOT] " .. message)
end

function edit()
  local configs = g_resources.listDirectoryFiles("/bot", false, false)
  editWindow.manager.upload.config:clearOptions()
  for i=1,#configs do
    editWindow.manager.upload.config:addOption(configs[i])
  end
  editWindow.manager.download.config:setText("")

  editWindow:show()
  editWindow:focus()
  editWindow:raise()
end

local function copyFilesRecursively(sourcePath, targetPath)
    local files = g_resources.listDirectoryFiles(sourcePath, true, false, false)
    for _, file in ipairs(files) do
        local baseName = file:split("/")
        baseName = baseName[#baseName]
        local targetFilePath = targetPath .. "/" .. baseName
        if g_resources.directoryExists(file) then
            g_resources.makeDir(targetFilePath)
            if not g_resources.directoryExists(targetFilePath) then
                return onError("Can't create directory: " .. targetFilePath)
            end
            copyFilesRecursively(file, targetFilePath)
        else
            local contents = g_resources.fileExists(file) and g_resources.readFileContents(file) or ""
            if contents:len() > 0 then
                g_resources.writeFileContents(targetFilePath, contents)
            end
        end
    end
end

function createDefaultConfigs()
    local defaultConfigFiles = g_resources.listDirectoryFiles("default_configs", false, false)
    for _, configName in ipairs(defaultConfigFiles) do
        local targetDir = "/bot/" .. configName
        if not g_resources.directoryExists(targetDir) then
            g_resources.makeDir(targetDir)
            if not g_resources.directoryExists(targetDir) then
                return onError("Can't create directory: " .. targetDir)
            end
            copyFilesRecursively("default_configs/" .. configName, targetDir)
        end
    end
end

function uploadConfig()
  local config = editWindow.manager.upload.config:getCurrentOption().text
  local archive = compressConfig(config)
  if not archive then
      return displayErrorBox(tr("Config upload failed"), tr("Config %s is invalid (can't be compressed)", config))
  end
  if archive:len() > 1024 * 1024 then
      return displayErrorBox(tr("Config upload failed"), tr("Config %s is too big, maximum size is 1024KB. Now it has %s KB.", config, math.floor(archive:len() / 1024)))
  end

  local infoBox = displayInfoBox(tr("Uploading config"), tr("Uploading config %s. Please wait.", config))

  HTTP.postJSON(configManagerUrl .. "?config=" .. config:gsub("%s+", "_"), archive, function(data, err)
    if infoBox then
      infoBox:destroy()
    end
    if err or data["error"] then
      return displayErrorBox(tr("Config upload failed"), tr("Error while upload config %s:\n%s", config, err or data["error"]))
    end
    displayInfoBox(tr("Succesful config upload"), tr("Config %s has been uploaded.\n%s", config, data["message"]))
  end)
end

function downloadConfig()
  local hash = editWindow.manager.download.config:getText()
  if hash:len() == 0 then
      return displayErrorBox(tr("Config download error"), tr("Enter correct config hash"))
  end
  local infoBox = displayInfoBox(tr("Downloading config"), tr("Downloading config with hash %s. Please wait.", hash))
  HTTP.download(configManagerUrl .. "?hash=" .. hash, hash .. ".zip", function(path, checksum, err)
    if infoBox then
      infoBox:destroy()
    end
    if err then
      return displayErrorBox(tr("Config download error"), tr("Config with hash %s cannot be downloaded", hash))
    end
    modules.client_textedit.show("", {
      title="Enter name for downloaded config",
      description="Config with hash " .. hash .. " has been downloaded. Enter name for new config.\nWarning: if config with same name already exist, it will be overwritten!",
      width=500
    }, function(configName)
      decompressConfig(configName, "/downloads/" .. path)
      refresh()
      edit()
    end)
  end)
end

function compressConfig(configName)
  if not g_resources.directoryExists("/bot/" .. configName) then
    return onError("Config " .. configName .. " doesn't exist")
  end
  local forArchive = {}
  for _, file in ipairs(g_resources.listDirectoryFiles("/bot/" .. configName)) do
    local fullPath = "/bot/" .. configName .. "/" .. file
    if g_resources.fileExists(fullPath) then -- regular file
        forArchive[file] = g_resources.readFileContents(fullPath)
    else -- dir
      for __, file2 in ipairs(g_resources.listDirectoryFiles(fullPath)) do
        local fullPath2 = fullPath .. "/" .. file2
        if g_resources.fileExists(fullPath2) then -- regular file
            forArchive[file .. "/" .. file2] = g_resources.readFileContents(fullPath2)
        end
      end
    end
  end
  return g_resources.createArchive(forArchive)
end

function decompressConfig(configName, archive)
  if g_resources.directoryExists("/bot/" .. configName) then
    g_resources.deleteFile("/bot/" .. configName) -- also delete dirs
  end
  local files = g_resources.decompressArchive(archive)
  g_resources.makeDir("/bot/" .. configName)
  if not g_resources.directoryExists("/bot/" .. configName) then
    return onError("Can't create /bot/" .. configName .. " directory in " .. g_resources.getWriteDir())
  end

  for file, contents in pairs(files) do
    local split = file:split("/")
    split[#split] = nil -- remove file name
    local dirPath = "/bot/" .. configName
    for _, s in ipairs(split) do
      dirPath = dirPath .. "/" .. s
      if not g_resources.directoryExists(dirPath) then
        g_resources.makeDir(dirPath)
        if not g_resources.directoryExists(dirPath) then
          return onError("Can't create " .. dirPath .. " directory in " .. g_resources.getWriteDir())
        end
      end
    end
    g_resources.writeFileContents("/bot/" .. configName .. file, contents)
  end
end

-- Executor
function message(category, msg)
  local widget = g_ui.createWidget('BotLabel', botMessages)
  widget.added = g_clock.millis()
  if category == 'error' then
    widget:setText(msg)
    widget:setColor("red")
    g_logger.error("[BOT] " .. msg)
  elseif category == 'warn' then
    widget:setText(msg)
    widget:setColor("yellow")
    g_logger.warning("[BOT] " .. msg)
  elseif category == 'info' then
    widget:setText(msg)
    widget:setColor("white")
    g_logger.info("[BOT] " .. msg)
  end

  if botMessages:getChildCount() > 5 then
    botMessages:getFirstChild():destroy()
  end
end

function check()
  removeEvent(checkEvent)
  if not botExecutor then
    return
  end

  checkEvent = scheduleEvent(check, 10)

  local status, result = pcall(function()
    return botExecutor.script()
  end)
  if not status then
    botExecutor = nil -- critical
    return onError(result)
  end

  -- remove old messages
  local widget = botMessages:getFirstChild()
  if widget and widget.added + 5000 < g_clock.millis() then
    widget:destroy()
  end
end

-- Callbacks
function initCallbacks()
  connect(rootWidget, {
    onKeyDown = botKeyDown,
    onKeyUp = botKeyUp,
    onKeyPress = botKeyPress
  })

  connect(g_game, {
    onTalk = botOnTalk,
    onTextMessage = botOnTextMessage,
    onLoginAdvice = botOnLoginAdvice,
    onUse = botOnUse,
    onUseWith = botOnUseWith,
    onChannelList = botChannelList,
    onOpenChannel = botOpenChannel,
    onCloseChannel = botCloseChannel,
    onChannelEvent = botChannelEvent,
    onImbuementWindow = botImbuementWindow,
    onModalDialog = botModalDialog,
    onAttackingCreatureChange = botAttackingCreatureChange,
    onAddItem = botContainerAddItem,
    onRemoveItem = botContainerRemoveItem,
    onEditText = botGameEditText,
    onSpellCooldown = botSpellCooldown,
    onSpellGroupCooldown = botGroupSpellCooldown
  })

  connect(Tile, {
    onAddThing = botAddThing,
    onRemoveThing = botRemoveThing
  })

  connect(Creature, {
    onAppear = botCreatureAppear,
    onDisappear = botCreatureDisappear,
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
  })

  connect(LocalPlayer, {
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
    onManaChange = botManaChange,
    onStatesChange = botStatesChange,
    onInventoryChange = botInventoryChange
  })

  connect(Container, {
    onOpen = botContainerOpen,
    onClose = botContainerClose,
    onUpdateItem = botContainerUpdateItem,
    onAddItem = botContainerAddItem,
    onRemoveItem = botContainerRemoveItem,
  })

  connect(g_map, {
    onMissle = botOnMissle,
    onAnimatedText = botOnAnimatedText,
    onStaticText = botOnStaticText
  })
end

function terminateCallbacks()
  disconnect(rootWidget, {
    onKeyDown = botKeyDown,
    onKeyUp = botKeyUp,
    onKeyPress = botKeyPress
  })

  disconnect(g_game, {
    onTalk = botOnTalk,
    onTextMessage = botOnTextMessage,
    onLoginAdvice = botOnLoginAdvice,
    onUse = botOnUse,
    onUseWith = botOnUseWith,
    onChannelList = botChannelList,
    onOpenChannel = botOpenChannel,
    onCloseChannel = botCloseChannel,
    onChannelEvent = botChannelEvent,
    onImbuementWindow = botImbuementWindow,
    onModalDialog = botModalDialog,
    onAttackingCreatureChange = botAttackingCreatureChange,
    onEditText = botGameEditText,
    onSpellCooldown = botSpellCooldown,
    onSpellGroupCooldown = botGroupSpellCooldown
  })

  disconnect(Tile, {
    onAddThing = botAddThing,
    onRemoveThing = botRemoveThing
  })

  disconnect(Creature, {
    onAppear = botCreatureAppear,
    onDisappear = botCreatureDisappear,
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
  })

  disconnect(LocalPlayer, {
    onPositionChange = botCreaturePositionChange,
    onHealthPercentChange = botCraetureHealthPercentChange,
    onTurn = botCreatureTurn,
    onWalk = botCreatureWalk,
    onManaChange = botManaChange,
    onStatesChange = botStatesChange,
    onInventoryChange = botInventoryChange
  })

  disconnect(Container, {
    onOpen = botContainerOpen,
    onClose = botContainerClose,
    onUpdateItem = botContainerUpdateItem,
    onAddItem = botContainerAddItem,
    onRemoveItem = botContainerRemoveItem
  })

  disconnect(g_map, {
    onMissle = botOnMissle,
    onAnimatedText = botOnAnimatedText,
    onStaticText = botOnStaticText
  })
end

function safeBotCall(func)
  local status, result = pcall(func)
  if not status then
    onError(result)
  end
end

function botKeyDown(widget, keyCode, keyboardModifiers)
  if botExecutor == nil then return false end
  if keyCode == KeyUnknown then return end
  safeBotCall(function() botExecutor.callbacks.onKeyDown(keyCode, keyboardModifiers) end)
end

function botKeyUp(widget, keyCode, keyboardModifiers)
  if botExecutor == nil then return false end
  if keyCode == KeyUnknown then return end
  safeBotCall(function() botExecutor.callbacks.onKeyUp(keyCode, keyboardModifiers) end)
end

function botKeyPress(widget, keyCode, keyboardModifiers, autoRepeatTicks)
  if botExecutor == nil then return false end
  if keyCode == KeyUnknown then return end
  safeBotCall(function() botExecutor.callbacks.onKeyPress(keyCode, keyboardModifiers, autoRepeatTicks) end)
end

function botOnTalk(name, level, mode, text, channelId, pos)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onTalk(name, level, mode, text, channelId, pos) end)
end

function botOnTextMessage(mode, text)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onTextMessage(mode, text) end)
end

function botOnLoginAdvice(message)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onLoginAdvice(message) end)
end

function botAddThing(tile, thing)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAddThing(tile, thing) end)
end

function botRemoveThing(tile, thing)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onRemoveThing(tile, thing) end)
end

function botCreatureAppear(creature)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreatureAppear(creature) end)
end

function botCreatureDisappear(creature)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreatureDisappear(creature) end)
end

function botCreaturePositionChange(creature, newPos, oldPos)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreaturePositionChange(creature, newPos, oldPos) end)
end

function botCraetureHealthPercentChange(creature, healthPercent)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCreatureHealthPercentChange(creature, healthPercent) end)
end

function botOnUse(pos, itemId, stackPos, subType)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onUse(pos, itemId, stackPos, subType) end)
end

function botOnUseWith(pos, itemId, target, subType)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onUseWith(pos, itemId, target, subType) end)
end

function botContainerOpen(container, previousContainer)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onContainerOpen(container, previousContainer) end)
end

function botContainerClose(container)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onContainerClose(container) end)
end

function botContainerUpdateItem(container, slot, item, oldItem)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onContainerUpdateItem(container, slot, item, oldItem) end)
end

function botOnMissle(missle)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onMissle(missle) end)
end

function botOnAnimatedText(thing, text)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAnimatedText(thing, text) end)
end

function botOnStaticText(thing, text)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onStaticText(thing, text) end)
end

function botChannelList(channels)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onChannelList(channels) end)
end

function botOpenChannel(channelId, name)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onOpenChannel(channelId, name) end)
end

function botCloseChannel(channelId)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onCloseChannel(channelId) end)
end

function botChannelEvent(channelId, name, event)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onChannelEvent(channelId, name, event) end)
end

function botCreatureTurn(creature, direction)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onTurn(creature, direction) end)
end

function botCreatureWalk(creature, oldPos, newPos)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onWalk(creature, oldPos, newPos) end)
end

function botImbuementWindow(itemId, slots, activeSlots, imbuements, needItems)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onImbuementWindow(itemId, slots, activeSlots, imbuements, needItems) end)
end

function botModalDialog(id, title, message, buttons, enterButton, escapeButton, choices, priority)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onModalDialog(id, title, message, buttons, enterButton, escapeButton, choices, priority) end)
end

function botGameEditText(id, itemId, maxLength, text, writer, time)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onGameEditText(id, itemId, maxLength, text, writer, time) end)
end

function botAttackingCreatureChange(creature, oldCreature)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAttackingCreatureChange(creature,oldCreature) end)
end

function botManaChange(player, mana, maxMana, oldMana, oldMaxMana)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onManaChange(player, mana, maxMana, oldMana, oldMaxMana) end)
end

function botStatesChange(player, states, oldStates)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onStatesChange(player, states, oldStates) end)
end

function botContainerAddItem(container, slot, item, oldItem)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onAddItem(container, slot, item, oldItem) end)
end

function botContainerRemoveItem(container, slot, item)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onRemoveItem(container, slot, item) end)
end

function botSpellCooldown(iconId, duration)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onSpellCooldown(iconId, duration) end)
end

function botGroupSpellCooldown(iconId, duration)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onGroupSpellCooldown(iconId, duration) end)
end

function botInventoryChange(player, slot, item, oldItem)
  if botExecutor == nil then return false end
  safeBotCall(function() botExecutor.callbacks.onInventoryChange(player, slot, item, oldItem) end)
end
