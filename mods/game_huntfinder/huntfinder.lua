HuntFinder = {
  widget = nil,
  searchInputBox = nil,
  teamSizeBox = nil,
  filterBox = nil,
  listPanel = nil,
  huntInfoPanel = nil,
  vocationFilter = nil,

  vocation = "Knight",
  teamSize = "Solo",
  level = 1,
  sortType = 1,
}

local HUNTFINDER_OPCODE = 252

local function onHuntFinderOpcode(protocol, opcode, buffer)
  local status, data = pcall(json.decode, buffer)
  if not status or not data then return end

  if data.action == "allMonsterInfo" and data.data then
    for name, info in pairs(data.data) do
      local combat = {}
      if info.elements then
        for k, v in pairs(info.elements) do
          combat[tonumber(k)] = v
        end
      end
      HuntInfo:updateMonsterData({
        name = name,
        id = info.raceId,
        maxHealth = info.health,
        experience = info.experience,
        speed = info.speed,
        armor = info.armor,
        mitigation = info.mitigation,
        combat = combat,
      })
    end
  elseif data.action == "itemIds" and data.data then
    for name, id in pairs(data.data) do
      HuntInfo:updateItemId(name, id)
    end
  end
end

function string.todivide(str, max)
    local new = ""
    local count = 0
    for word in string.gmatch(str, "%S+") do
        count = count + 1
        if count > max then
            new = new .. "\n"
            count = 1
        end
        new = new .. (count == 1 and "" or " ") .. word
    end
    return new
end

function HuntFinder.init()
  g_logger.info("[HuntFinder] init started")
  local ok, err = pcall(function()
    g_ui.importStyle('styles/huntfinder')
  end)
  if not ok then
    g_logger.error("[HuntFinder] importStyle failed: " .. tostring(err))
    return
  end
  g_logger.info("[HuntFinder] importStyle OK")

  HuntFinder.widget = g_ui.displayUI('styles/huntfinder')
  if not HuntFinder.widget then
    g_logger.error("[HuntFinder] displayUI returned nil — skipping init")
    return
  end
  g_logger.info("[HuntFinder] displayUI OK")
  HuntFinder.widget:hide()

  HuntFinder.searchInputBox = HuntFinder.widget:recursiveGetChildById('searchInputBox')
  HuntFinder.teamSizeBox = HuntFinder.widget:recursiveGetChildById('teamSizeBox')
  HuntFinder.filterBox = HuntFinder.widget:recursiveGetChildById('filterBox')

  HuntFinder.listPanel = HuntFinder.widget:recursiveGetChildById('listPanel')
  HuntFinder.huntInfoPanel = HuntFinder.widget:recursiveGetChildById('huntInfoPanel')
  HuntFinder.backButton = HuntFinder.widget:recursiveGetChildById('backButton')
  HuntFinder.vocationFilter = HuntFinder.widget:recursiveGetChildById('vocationBox')
  HuntFinder.searchText = HuntFinder.widget:recursiveGetChildById('searchText')
  HuntFinder.searchIcon = HuntFinder.widget:recursiveGetChildById('searchIcon')

  if HuntFinder.searchText then
    HuntFinder.searchText.onTextChange = function(widget, text)
      HuntFinder.searchQuery = text:len() > 0 and text:lower() or nil
      if HuntFinder.searchIcon then
        HuntFinder.searchIcon:setEnabled(text:len() > 0)
      end
      HuntFinder:showListPanel()
      ListPanel:displayHunts()
    end
  end

  HuntConfig:loadJson()
  connect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline,
  })

  ProtocolGame.registerExtendedOpcode(HUNTFINDER_OPCODE, onHuntFinderOpcode)

  HuntFinder.topMenuButton = modules.client_topmenu.addLeftGameButton('huntFinderButton', tr('Hunt Finder'), '/images/topbuttons/huntfinder-mini', toggle)
end

function toggle()
  if not HuntFinder.widget then return end
  if HuntFinder.widget:isVisible() then
    hide()
  else
    show()
  end
end

function HuntFinder.terminate()
  disconnect(g_game, {
    onGameStart = onGameStart,
    onGameEnd = offline,
  })

  ProtocolGame.unregisterExtendedOpcode(HUNTFINDER_OPCODE)

  if ListPanel then ListPanel:clear() end
  if MapFinder then MapFinder:clear() end
  if HuntInfo then HuntInfo:clear() end
  if HuntFinder.widget then
    HuntFinder.widget:destroy()
    HuntFinder.widget = nil
  end

  HuntFinder.searchInputBox = nil
  HuntFinder.teamSizeBox = nil
  HuntFinder.filterBox = nil
  HuntFinder.listPanel = nil
  HuntFinder.huntInfoPanel = nil
  HuntFinder.vocationFilter = nil

  if HuntFinder.topMenuButton then
    HuntFinder.topMenuButton:destroy()
    HuntFinder.topMenuButton = nil
  end
end

function HuntFinder:setVocation(vocation)
  HuntFinder.vocation = vocation
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:setTeamSize(teamSize)
  if teamSize ~= "Solo" and teamSize ~= "Duo" and teamSize ~= "Party x4" then
    teamSize = "Solo"
  end
  HuntFinder.teamSize = teamSize

  if HuntFinder.teamSizeBox then
    HuntFinder.teamSizeBox:setCurrentOption(teamSize)
  end

  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:setSortType(sortType)
  HuntFinder.sortType = sortType
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:onLevelEdit(newLevel)
  local level = tonumber(newLevel)
  if not level then
    return
  end
  HuntFinder.level = level
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
end

function HuntFinder:showListPanel()
  if not HuntFinder.widget then
    return
  end
  if HuntFinder.listPanel:isVisible() then
    return
  end
  HuntFinder.listPanel:setVisible(true)
  HuntFinder.huntInfoPanel:setVisible(false)
  HuntFinder.backButton:setVisible(false)
  HuntFinder.widget:setWidth(747)
end

function HuntFinder:showHuntInfo(hunt)
  if not HuntFinder.widget then
    return
  end
  if HuntFinder.huntInfoPanel:isVisible() then
    return
  end
  HuntFinder.listPanel:setVisible(false)
  HuntFinder.huntInfoPanel:setVisible(true)
  HuntFinder.backButton:setVisible(true)
  HuntFinder.widget:setWidth(920)
  HuntInfo:displayHunt(hunt)
end

function onGameStart()
  if not HuntFinder.widget then return end
  ListPanel.init()
  HuntInfo.init()
  MapFinder.init()
end

function offline()
  hide()
end

function show()
  if not HuntFinder.widget then return end
  HuntFinder.widget:show(true)
  HuntFinder.widget:raise()
  HuntFinder.widget:focus()
  HuntFinder:showListPanel()
  ListPanel:displayHunts()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(HuntFinder.widget)
  end

  HuntFinder.searchText:setText("")
  HuntFinder.searchQuery = nil
  if HuntFinder.searchIcon then
    HuntFinder.searchIcon:setEnabled(false)
  end

  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  HuntFinder.searchInputBox:setValue(HuntConfig:getPlayerFloorLevel(player:getLevel()))
  HuntFinder.vocationFilter:setCurrentOption(translateVocationName(player:getVocation()))
end

function hide()
  if not HuntFinder.widget then return end
  HuntFinder.widget:hide()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(nil)
  end
end

function HuntFinder.requestMonsterInfo(monsterNames)
  if not monsterNames or #monsterNames == 0 then return end
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  local msg = json.encode({action = "allMonsterInfo", monsters = monsterNames})
  protocol:sendExtendedOpcode(HUNTFINDER_OPCODE, msg)
end

function HuntFinder.requestItemIds(itemNames)
  if not itemNames or #itemNames == 0 then return end
  local protocol = g_game.getProtocolGame()
  if not protocol then return end
  local msg = json.encode({action = "itemIds", items = itemNames})
  protocol:sendExtendedOpcode(HUNTFINDER_OPCODE, msg)
end
