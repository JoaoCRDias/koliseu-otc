dailyRewardWindow = nil
confirmRewardWindow = nil
selectRewardWindow = nil

local instantTokens
local jokerTokens
local rewardAmount = 0
local totalOz = 0
local freeCap = 0
local globalMessage
local gameFromShrine

function init()
  dailyRewardWindow = g_ui.displayUI('dailyreward')
  UIModalOverlay.register(dailyRewardWindow)
  dailyRewardWindow:hide()

  g_ui.importStyle('selectreward')

  connect(g_game, {
    onGameEnd = offline,
    onDailyReward = onDailyReward,
    onOpenRewardWall = onOpenRewardWall,
    onRewardHistory = onDailyRewardHistory,
    onResourcesBalanceChange = onResourceBalance,
  })

  connect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
  })
end

function terminate()
  disconnect(g_game, {
    onGameEnd = offline,
    onDailyReward = onDailyReward,
    onOpenRewardWall = onOpenRewardWall,
    onRewardHistory = onDailyRewardHistory,
    onResourcesBalanceChange = onResourceBalance,
  })

  disconnect(LocalPlayer, {
    onFreeCapacityChange = onFreeCapacityChange,
  })

  UIModalOverlay.destroy(dailyRewardWindow)
  dailyRewardWindow:destroy()

  if dailyRewardHistory then
    dailyRewardHistory:destroy()
    dailyRewardHistory = nil
  end

  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end
  if confirmRewardWindow then
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
  end
end

function closeSelectReward()
  selectRewardWindow:destroy()
  selectRewardWindow = nil
  dailyRewardWindow:show(true)
  dailyRewardWindow:focus()
end

function closeDaily()
  dailyRewardWindow:hide()
  if selectRewardWindow then
    selectRewardWindow:hide()
  end
  if confirmRewardWindow then
    confirmRewardWindow:hide()
  end
  if dailyRewardHistory then
    dailyRewardHistory:destroy()
    dailyRewardHistory = nil
  end
end

function show()
  g_game.openDailyReward()
end

function requestHistory()
  closeDaily()
  g_game.requestOpenRewardHistory()
end

function offline()
  dailyRewardWindow:hide()
  if confirmRewardWindow then
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
  end
  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end
end

function onDailyReward(data)
  DailyReward:onDailyReward(data.freeRewards, data.premiumRewards, data.bonuses)
end

function onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, dailyState, message, jokerToken, serverSave,
                          dayStreakLevel)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  dailyRewardWindow:focus()
  dailyRewardWindow.miniWindowBonuses.jokerInfo.streakWidget:setText(dayStreakLevel)

  if dailyState == 1 then
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setVisible(false)
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("")
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(true)
  else
    local currentTime = os.time()
    local targetTime = nextRewardTime
    if targetTime < currentTime then
      local serverSaveCycle = 25 * 60 * 60
      local timePassed = currentTime - targetTime
      local cyclesPassed = math.floor(timePassed / serverSaveCycle) + 1
      targetTime = targetTime + (cyclesPassed * serverSaveCycle)
    end

    local time = targetTime - currentTime
    time = time < 0 and 0 or time
    local hours = math.floor(time / 3600)
    local minutes = math.floor((time % 3600) / 60)
    local formattedTime = string.format("%02d:%02d", hours, minutes)
    local maxTime = 25 * 60 * 60

    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setVisible(true)
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setText(formattedTime)
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:setValue(time, 0, maxTime)
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakProgress:updateBackground()
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakLabel:setText("")
    dailyRewardWindow.miniWindowBonuses.jokerInfo.timerStreakPanel.timerStreakCheck:setVisible(false)
  end

  local jokerBalance = player:getResourceBalance(ResourceTypes.DAILYREWARD_JOKERS)
  jokerTokens = jokerBalance
  local text = jokerToken > 3 and ">3" or jokerToken
  dailyRewardWindow.miniWindowBonuses.jokerInfo.jokers.jokerInfoLabel:setText(text)

  local textColor = jokerToken > jokerBalance and "$var-text-cip-store-red" or "$var-text-cip-color"
  dailyRewardWindow.miniWindowBonuses.jokerInfo.jokers.jokerInfoLabel:setColor(textColor)

  dailyRewardWindow.jokers.jokersLabel:setText(math.min(3, jokerBalance))
  if dailyState == 1 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setText("You already claimed your daily reward.")
  elseif dailyState == 0 then
    dailyRewardWindow.miniWindowBonuses.bonusLabel:setText(
      "Claim your daily reward before server save.\nIf you don't claim your reward now, your streak will be reset.")
  end

  globalMessage = message
  dailyRewardWindow.miniWindowBonuses.bonusLabel.onHoverChange = function(_, hovered)
    setupBonusLabelDesc(hovered, dailyState, jokerToken)
  end

  gameFromShrine = fromShrine

  for i = 0, 6 do
    local buttonWidget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyButton_" .. i)
    if buttonWidget then
      if i == currentIndex and dailyState == 0 then
        buttonWidget:setImageSource("/images/game/dailyreward/buttonbg")
        local style = {}
        style["$pressed"] = {
          ["icon-offset"] = "1 1",
          ["image-clip"] = "0 66 66 66"
        }
        buttonWidget:mergeStyle(style)
        buttonWidget.onClick = onClaimReward
        buttonWidget.blocked:setImageSource("")
      else
        buttonWidget:setImageSource("/images/game/dailyreward/nextbg")
        buttonWidget.blocked:setImageSource(i > currentIndex and "/images/ui/ditherpattern64" or "")
        if i > currentIndex then
          buttonWidget.blocked:setMargin(1)
        end
        local style = {}
        style["$pressed"] = {
          ["image-clip"] = "0 0 66 66"
        }
        buttonWidget:mergeStyle(style)
        buttonWidget.onClick = function() end
      end
    end

    local panelWidget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyPanel_" .. i)
    if panelWidget then
      panelWidget.dailyPanelProgress:setVisible(false)
      panelWidget.dailyBlocked:setVisible(false)
      panelWidget.dailyPanelLabel:setVisible(false)
      panelWidget.dailyIconLabel:setVisible(false)

      if i < currentIndex then
        panelWidget.dailyPanelLabel:setVisible(true)
        panelWidget.dailyPanelLabel:setText(" ")
        panelWidget.dailyPanelLabel:setIcon("/images/game/dailyreward/icon-checkmark")
      elseif i == currentIndex then
        if dailyState == 0 then
          panelWidget.dailyIconLabel:setVisible(true)
        else
          local currentTime = os.time()
          local targetTime = nextRewardTime
          if targetTime < currentTime then
            local serverSaveCycle = 25 * 60 * 60
            local timePassed = currentTime - targetTime
            local cyclesPassed = math.floor(timePassed / serverSaveCycle) + 1
            targetTime = targetTime + (cyclesPassed * serverSaveCycle)
          end

          local time = targetTime - currentTime
          time = time < 0 and 0 or time
          local hours = math.floor(time / 3600)
          local minutes = math.floor((time % 3600) / 60)
          local formattedTime = string.format("%02d:%02d", hours, minutes)

          panelWidget.dailyPanelProgress:setVisible(true)
          panelWidget.dailyPanelProgress:setText(formattedTime)
          local maxTime = 25 * 60 * 60
          panelWidget.dailyPanelProgress:setValue(time, 0, maxTime)
          panelWidget.dailyPanelProgress:updateBackground()
        end
      else
        panelWidget.dailyBlocked:setVisible(true)
      end
    end

    local arrowWidget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("processArrow_" .. i)
    if arrowWidget and i < currentIndex then
      arrowWidget:setText(" ")
      arrowWidget:setIcon("/images/game/dailyreward/icon-rewardarrow-active")
    end
  end

  for i = 0, 5 do
    local bonusBox = dailyRewardWindow.miniWindowBonuses.preyBonus:recursiveGetChildById("bonusBox_" .. i)
    if bonusBox then
      local bonusStreak = bonusBox:getChildById("bonusStreak_" .. i)
      if bonusStreak then
        local existingDither = bonusStreak:getChildById("bonusDither_" .. i)
        if existingDither then
          existingDither:destroy()
        end
        local existingBanner = bonusStreak:getChildById("bonusBanner_" .. i)
        if existingBanner then
          existingBanner:destroy()
        end
        local existingNumber = bonusStreak:getChildById("bonusNumber_" .. i)
        if existingNumber then
          existingNumber:destroy()
        end

        local requiredStreak = i + 2
        if dayStreakLevel < requiredStreak then
          local ditherWidget = g_ui.createWidget("UIWidget", bonusStreak)
          ditherWidget:setId("bonusDither_" .. i)
          ditherWidget:setImageSource("/images/ui/ditherpattern")
          ditherWidget:fill("parent")
          ditherWidget:setPhantom(true)

          local bannerWidget = g_ui.createWidget("UIWidget", bonusStreak)
          bannerWidget:setId("bonusBanner_" .. i)
          bannerWidget:setImageSource("/images/game/dailyreward/icon-banner-days")
          bannerWidget:setImageAutoResize(false)
          bannerWidget:addAnchor(AnchorBottom, "parent", AnchorBottom)
          bannerWidget:addAnchor(AnchorRight, "parent", AnchorRight)
          bannerWidget:setPhantom(true)

          local numberLabel = g_ui.createWidget("UILabel", bonusStreak)
          numberLabel:setId("bonusNumber_" .. i)
          numberLabel:setText(tostring(requiredStreak))
          numberLabel:setFont("$var-cip-font-mono-rounded")
          numberLabel:setColor("$var-text-cip-color-white")
          numberLabel:addAnchor(AnchorBottom, "parent", AnchorBottom)
          numberLabel:addAnchor(AnchorRight, "parent", AnchorRight)
          numberLabel:setMarginBottom(2)
          numberLabel:setMarginRight(12)
          numberLabel:setPhantom(true)
        end
      end
    end
  end

  if DailyReward.freeRewards and #DailyReward.freeRewards > 0 then
    DailyReward:configureRewardDescriptions()
  end

  dailyRewardWindow:show(true)
end

function setupBonusLabelDesc(hovered, dailyState, jokerToken)
  if not hovered then
    dailyRewardWindow.Description.tooltipTodo:setText("")
    return
  end

  local text = ""
  if dailyState == 1 then
    text =
    "Congratulations! You claimed your daily reward in time. Come back after\nthe next regular server save for more rewards.\nRaise your reward streak to benefit from bonuses in resting areas."
  elseif dailyState == 0 then
    if jokerToken > 0 then
      text = string.format(
        "Hurry! Claim your daily reward before the next regular server save to raise\nyour reward streak by one.\nTo prevent a reset of your reward streak, %d Daily Reward Jokers will be used.\nRaise your reward streak to benefit from bonuses in resting areas.",
        jokerToken)
    else
      text =
      "Hurry! Claim your daily reward before the next regular server save to raise\nyour reward streak by one.\nRaise your reward streak to benefit from bonuses in resting areas."
    end
  end
  dailyRewardWindow.Description.tooltipTodo:setText(text)
end

function onClaimReward(widget)
  local player = g_game.getLocalPlayer()
  if not player then
    return
  end

  if selectRewardWindow then
    selectRewardWindow:destroy()
    selectRewardWindow = nil
  end

  selectedAmount = 0
  selectItems = {}

  local reward = player:isPremium() and widget.premiumRewards or widget.freeRewards

  if not reward then
    return
  end

  if reward.redeemMode == 1 then
    dailyRewardWindow:hide()
    selectRewardWindow = g_ui.createWidget('MainWindowSelect', modules.game_interface.getRootPanel())
    UIModalOverlay.register(selectRewardWindow)
    UIModalOverlay.show(selectRewardWindow)

    for c, item in pairs(reward.selectableItems) do
      local w = g_ui.createWidget("RewardSelectLabel", selectRewardWindow.itemPanel)
      if w then
        w.item:setItemId(item.itemId)
        w.name:setText(item.name)
        w.oz:setText("0.00 oz")
        w.ozNumber = item.weight
        w.leftSkipPlus.onClick = onClickAmount
        w.leftSkip.onClick = onClickAmount
        w.rightSkip.onClick = onClickAmount
        w.rightSkipPlus.onClick = onClickAmount
        w.leftSkipPlus.window = w
        w.leftSkip.window = w
        w.rightSkip.window = w
        w.rightSkipPlus.window = w
        w:setBackgroundColor((c % 2 ~= 0 and "$var-textlist-odd" or "$var-textlist-even"))
      end
    end

    selectRewardWindow.freeCapacityLabel:setText(string.format("Free Capacity: %d oz", freeCap))
    local m = {}
    setStringColor(m, "You have selected ", "$var-text-cip-color")
    setStringColor(m, "0", "$var-text-cip-color-light-red")
    totalOz = 0
    rewardAmount = reward.itemsToSelect
    setStringColor(m, string.format(" of %d reward items.", reward.itemsToSelect), "$var-text-cip-color")
    selectRewardWindow.selectLabel:setColoredText(m)

    selectRewardWindow.closeButton.onClick = function()
      selectRewardWindow:destroy()
      selectRewardWindow = nil
      dailyRewardWindow:show(true)
      dailyRewardWindow:focus()
    end
  else
    onClickConfirm(widget)
  end
end

function onFreeCapacityChange(localPlayer, freeCapacity)
  freeCap = freeCapacity
end

function onClickAmount(widget)
  local id = widget:getId()

  local value = widget.window.countEdit:getText()
  if not tonumber(value) then
    value = 0
  end

  value = tonumber(value) or 0

  if id == "leftSkipPlus" then
    selectedAmount = selectedAmount - value
    widget.window.countEdit:setText('0')
  elseif id == "leftSkip" then
    if value > 0 then
      selectedAmount = selectedAmount - 1
      widget.window.countEdit:setText(tostring(value - 1))
    end
  elseif id == "rightSkip" then
    if selectedAmount < rewardAmount then
      selectedAmount = selectedAmount + 1
      widget.window.countEdit:setText(value + 1)
    end
  elseif id == "rightSkipPlus" then
    if selectedAmount < rewardAmount then
      local remaining = rewardAmount - selectedAmount
      widget.window.countEdit:setText(value + remaining)
      selectedAmount = rewardAmount
    end
  end

  local value = tonumber(widget.window.countEdit:getText()) or 0
  totalOz = (value * widget.window.ozNumber)
  widget.window.oz:setText(string.format("%.2f oz", (widget.window.ozNumber * value) / 100))
  selectRewardWindow.totalWeightLabel:setText(string.format('Total Weight:        %.2f oz', totalOz / 100))

  if selectedAmount < rewardAmount then
    for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
      child.rightSkipPlus:setIcon("/images/game/dailyreward/icon-arrowskipright")
      child.rightSkip:setIcon("/images/game/dailyreward/icon-arrowright")
    end
  else
    for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
      child.rightSkipPlus:setIcon("/images/game/dailyreward/icon-arrowskipright-disabled")
      child.rightSkip:setIcon("/images/game/dailyreward/icon-arrowright-disabled")
    end
  end

  for i, child in pairs(selectRewardWindow.itemPanel:getChildren()) do
    if tonumber(child.countEdit:getText()) > 0 then
      child.leftSkipPlus:setIcon("/images/game/dailyreward/icon-arrowskip")
      child.leftSkip:setIcon("/images/game/dailyreward/icon-arrow")
    else
      child.leftSkipPlus:setIcon("/images/game/dailyreward/icon-arrowskip-disabled")
      child.leftSkip:setIcon("/images/game/dailyreward/icon-arrow-disabled")
    end
  end

  local m = {}
  setStringColor(m, "You have selected ", "$var-text-cip-color")
  if selectedAmount < rewardAmount then
    setStringColor(m, string.format("%d", selectedAmount), "$var-text-cip-color-light-red")
  else
    setStringColor(m, string.format("%d", selectedAmount), "#0B8A0A")
  end
  setStringColor(m, string.format(" of %d reward items.", rewardAmount), "$var-text-cip-color")
  selectRewardWindow.selectLabel:setColoredText(m)

  if selectedAmount == rewardAmount then
    selectRewardWindow.ok:setEnabled(true)
    selectRewardWindow.ok.onClick = onClickConfirm
  else
    selectRewardWindow.ok:setEnabled(false)
  end
end

function onClickConfirm(widget)
  if confirmRewardWindow then
    return
  end

  if selectRewardWindow then
    selectRewardWindow:hide()
  end

  dailyRewardWindow:hide()

  local yesCallback = function()
    if confirmRewardWindow then
      confirmRewardWindow:destroy()
      confirmRewardWindow = nil
      dailyRewardWindow:show()
      dailyRewardWindow:focus()
    end

    local items = {}
    local totalOz = 0
    if selectRewardWindow then
      local childrens = selectRewardWindow.itemPanel:getChildren()
      for i, child in pairs(childrens) do
        if child and child.item and tonumber(child.countEdit:getText()) and tonumber(child.countEdit:getText()) > 0 then
          local count = tonumber(child.countEdit:getText())
          items[child.item:getItemId()] = count
          totalOz = totalOz + (count * child.ozNumber)
        end
      end
    end

    if (totalOz / 100) > freeCap then
      return
    end

    local bonusShrine = gameFromShrine == 1 and 0 or 1
    g_game.requestGetRewardDaily(bonusShrine, items)
  end

  local noCallback = function()
    confirmRewardWindow:destroy()
    confirmRewardWindow = nil
    if selectRewardWindow then
      selectRewardWindow:show(true)
      selectRewardWindow:focus()
    else
      dailyRewardWindow:show()
      dailyRewardWindow:focus()
    end
  end

  local displayMessage = globalMessage
  if string.empty(displayMessage) then
    displayMessage = "Are you sure you want to claim this reward?"
  end

  local callbacks
  if string.empty(globalMessage) then
    callbacks = {
      { text = tr('Yes'), callback = yesCallback },
      { text = tr('No'),  callback = noCallback },
    }
  else
    callbacks = {
      { text = tr('Back'), callback = noCallback, },
    }
  end

  confirmRewardWindow = displayGeneralBox(tr('Warning'), tr(displayMessage), callbacks, yesCallback, noCallback)

  g_keyboard.bindKeyPress("Y", yesCallback, confirmRewardWindow)
  g_keyboard.bindKeyPress("N", noCallback, confirmRewardWindow)
end

function onTextChange(widget)
  local text = widget:getText()
  if not tonumber(text) then
    widget:setText('0')
    return false
  end

  return true
end

function onResourceBalance(value, oldVale, type)
  if type == ResourceTypes.DAILYREWARD_STREAK then
    instantTokens = value
    dailyRewardWindow.instantAcess.instantLabel:setText(value)
  end
end

function closeHistory()
  closeDaily()
end

function backHistory()
  closeDaily()
  dailyRewardWindow:show(true)
end

function onDailyRewardHistory(dailyRewardHistories)
  dailyRewardHistory = g_ui.displayUI('history')
  UIModalOverlay.register(dailyRewardHistory)
  UIModalOverlay.show(dailyRewardHistory)
  dailyRewardHistory:focus()

  dailyRewardHistory.instantAcess.instantLabel:setText(instantTokens)
  dailyRewardHistory.jokers.jokersLabel:setText(jokerTokens)
  for i, info in pairs(dailyRewardHistories) do
    local widget = g_ui.createWidget('HistoryDescription', dailyRewardHistory.historyPanel.historyListPanel)
    widget.date:setText(os.date("%Y.%m.%d, %X", info[1]))
    widget.streak:setText(info[4])
    widget.description:setText(info[3])
    widget:setBackgroundColor(i % 2 == 0 and "$var-textlist-even" or "$var-textlist-odd")
  end
end
