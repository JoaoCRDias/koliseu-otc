-- Timer Panel Logic
-- Handles the timer UI and rule list management
-- Business logic is in classes/timer.lua (_Helper.Timer)

local timerPanel = {}

local timerPanelWidget = nil
local formPanel = nil
local rulesListPanel = nil
local rulesList = nil
local selectedItemId = nil
local selectedItemName = nil
local editingRuleKey = nil -- nil = ADD mode, "rule_123" = UPDATE mode

function timerPanel.init(panel)
  timerPanelWidget = panel
  if not timerPanelWidget then return end

  formPanel = timerPanelWidget:recursiveGetChildById('formPanel')
  rulesListPanel = timerPanelWidget:recursiveGetChildById('rulesListPanel')

  if rulesListPanel then
    rulesList = rulesListPanel:getChildById('rulesList')
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then
      addButton.onClick = function()
        timerPanel.addRule()
      end
    end
  end

  -- Setup form elements
  timerPanel.setupForm()

  -- Setup enable timer checkbox
  timerPanel.setupEnableTimer()
end

function timerPanel.setupEnableTimer()
  if not timerPanelWidget then return end

  local enableTimerPanel = timerPanelWidget:recursiveGetChildById('enableTimerPanel')
  if not enableTimerPanel then return end

  local enableTimerCheckbox = enableTimerPanel:getChildById('enableTimer')
  if not enableTimerCheckbox then return end

  -- Sync with current config
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    -- Default to true if not set
    if helperConfig.timerEnabled == nil then
      helperConfig.timerEnabled = true
    end
    enableTimerCheckbox:setChecked(helperConfig.timerEnabled)
  end

  -- Handle checkbox change
  enableTimerCheckbox.onCheckChange = function(widget)
    local config = _Helper.getHelperConfig and _Helper.getHelperConfig()
    if config then
      config.timerEnabled = widget:isChecked()
      if _Helper.saveSettings then
        _Helper.saveSettings()
      end
      -- Sync with shortcut panel
      if _Helper.Shortcut and _Helper.Shortcut.syncButton then
        _Helper.Shortcut.syncButton('shortcutTimer', config.timerEnabled)
      end
    end
  end
end

function timerPanel.syncEnableTimer()
  if not timerPanelWidget then return end

  local enableTimerPanel = timerPanelWidget:recursiveGetChildById('enableTimerPanel')
  if not enableTimerPanel then return end

  local enableTimerCheckbox = enableTimerPanel:getChildById('enableTimer')
  if not enableTimerCheckbox then return end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    enableTimerCheckbox:setChecked(helperConfig.timerEnabled ~= false)
  end
end

function timerPanel.setupForm()
  if not formPanel then return end

  local wordsRow = formPanel:getChildById('wordsRow')
  local itemRow = formPanel:getChildById('itemRow')
  local forceItemRow = formPanel:getChildById('forceItemRow')
  local conditionsRow = formPanel:getChildById('conditionsRow')

  if not wordsRow or not itemRow or not forceItemRow then return end

  local wordsRadio = wordsRow:getChildById('wordsRadio')
  local itemRadio = itemRow:getChildById('itemRadio')
  local forceItemCheck = forceItemRow:getChildById('forceItemCheck')
  local itemButton = itemRow:getChildById('itemButton')

  if wordsRadio and itemRadio and forceItemCheck then
    -- Set words as default selected
    wordsRadio:setChecked(true)
    itemRadio:setChecked(false)
    forceItemCheck:setEnabled(false)

    -- Words radio check change handler
    wordsRadio.onCheckChange = function(widget)
      if widget:isChecked() then
        itemRadio:setChecked(false)
        forceItemCheck:setEnabled(false)
        forceItemCheck:setChecked(false)
      else
        -- Prevent unchecking if it's the only one selected
        if not itemRadio:isChecked() then
          widget:setChecked(true)
        end
      end
    end

    -- Item radio check change handler
    itemRadio.onCheckChange = function(widget)
      if widget:isChecked() then
        wordsRadio:setChecked(false)
        forceItemCheck:setEnabled(true)
      else
        -- Prevent unchecking if it's the only one selected
        if not wordsRadio:isChecked() then
          widget:setChecked(true)
        end
      end
    end
  end

  -- Setup item button click handler
  if itemButton then
    itemButton.onClick = function()
      timerPanel.selectItem()
    end
  end

  -- Setup PZ and Targeting mutual exclusivity
  if conditionsRow then
    local pzCheck = conditionsRow:getChildById('pzCheck')
    local targetingMonsterCheck = conditionsRow:getChildById('targetingMonsterCheck')

    if pzCheck and targetingMonsterCheck then
      -- PZ and Targeting are mutually exclusive (can't attack in PZ)
      pzCheck.onCheckChange = function(widget)
        if widget:isChecked() then
          targetingMonsterCheck:setChecked(false)
        end
      end

      targetingMonsterCheck.onCheckChange = function(widget)
        if widget:isChecked() then
          pzCheck:setChecked(false)
        end
      end
    end
  end
end

function timerPanel.selectItem()
  if not timerPanelWidget then return end

  local mouseGrabber = modules.game_helper.getMouseGrabber and modules.game_helper.getMouseGrabber()
  local isTemporaryGrabber = false
  if not mouseGrabber then
    -- Create a simple mouse grabber if not available
    mouseGrabber = g_ui.createWidget('UIWidget')
    mouseGrabber:setVisible(false)
    mouseGrabber:setFocusable(false)
    isTemporaryGrabber = true
  end

  mouseGrabber:grabMouse()
  g_mouse.pushCursor('target')

  mouseGrabber.onMouseRelease = function(self, mousePosition, mouseButton)
    timerPanel.onItemSelected(self, mousePosition, mouseButton, isTemporaryGrabber)
  end
end

function timerPanel.onItemSelected(self, mousePosition, mouseButton, isTemporaryGrabber)
  local mouseGrabber = modules.game_helper.getMouseGrabber and modules.game_helper.getMouseGrabber() or self

  mouseGrabber:ungrabMouse()
  g_mouse.popCursor('target')
  mouseGrabber.onMouseRelease = nil

  -- Destroy temporary grabber to prevent widget leak
  if isTemporaryGrabber and self then
    self:destroy()
  end

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return true end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then return true end

  local itemId = 0
  local item = nil

  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    item = clickedWidget:getItem()
    if item then
      itemId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        itemId = topUseThing:getId()
        item = topUseThing
      end
    end
  end

  if itemId == 0 then
    return true
  end

  -- Validate item: must not be multi-use
  local thingType = g_things.getThingType(itemId, ThingCategoryItem)
  if not thingType then
    return true
  end

  if thingType:isMultiUse() then
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tr('Item cannot be multi-use (crosshair)!'))
    end
    return true
  end

  -- Store selected item
  selectedItemId = itemId
  selectedItemName = thingType:getName() or ('Item ' .. itemId)

  -- Update UI
  timerPanel.updateItemButton()

  -- Auto-select item radio if words radio is selected
  timerPanel.autoSelectItemRadio()

  return true
end

function timerPanel.autoSelectItemRadio()
  if not formPanel then return end

  local wordsRow = formPanel:getChildById('wordsRow')
  local itemRow = formPanel:getChildById('itemRow')
  local forceItemRow = formPanel:getChildById('forceItemRow')

  if not wordsRow or not itemRow or not forceItemRow then return end

  local wordsRadio = wordsRow:getChildById('wordsRadio')
  local itemRadio = itemRow:getChildById('itemRadio')
  local forceItemCheck = forceItemRow:getChildById('forceItemCheck')

  if wordsRadio and itemRadio and wordsRadio:isChecked() then
    wordsRadio:setChecked(false)
    itemRadio:setChecked(true)
    if forceItemCheck then
      forceItemCheck:setEnabled(true)
    end
  end
end

function timerPanel.updateItemButton()
  if not formPanel then return end

  local itemRow = formPanel:getChildById('itemRow')
  if not itemRow then return end

  local itemButton = itemRow:getChildById('itemButton')
  local itemNameLabel = itemRow:getChildById('itemNameLabel')

  if itemButton and selectedItemId then
    -- Create or get UIItem child
    local itemWidget = itemButton:getChildById('timerItemWidget')
    if not itemWidget then
      itemWidget = g_ui.createWidget('UIItem', itemButton)
      itemWidget:setId('timerItemWidget')
      itemWidget:setSize({ width = 32, height = 32 })
      itemWidget:setPhantom(true)
      itemWidget:fill('parent')
      itemWidget:setVirtual(true)
    end
    itemWidget:setItemId(selectedItemId)
  end

  if itemNameLabel then
    if selectedItemName then
      itemNameLabel:setText(selectedItemName)
      itemNameLabel:setColor('$var-text-color')
    else
      itemNameLabel:setText('(select item)')
      itemNameLabel:setColor('#888888')
    end
  end
end

-- Clear form and exit edit mode
function timerPanel.clearForm()
  editingRuleKey = nil

  -- Update button text
  if rulesListPanel then
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then addButton:setText("Add") end
  end

  timerPanel.resetForm()
  timerPanel.refreshRulesListBackground()
end

function timerPanel.resetForm()
  if not formPanel then return end

  local wordsRow = formPanel:getChildById('wordsRow')
  local itemRow = formPanel:getChildById('itemRow')
  local cooldownRow = formPanel:getChildById('cooldownRow')
  local forceItemRow = formPanel:getChildById('forceItemRow')
  local conditionsRow = formPanel:getChildById('conditionsRow')

  if wordsRow then
    local wordsRadio = wordsRow:getChildById('wordsRadio')
    local wordsInput = wordsRow:getChildById('wordsInput')
    if wordsRadio then wordsRadio:setChecked(true) end
    if wordsInput then wordsInput:setText('') end
  end

  if itemRow then
    local itemRadio = itemRow:getChildById('itemRadio')
    local itemButton = itemRow:getChildById('itemButton')
    local itemNameLabel = itemRow:getChildById('itemNameLabel')
    if itemRadio then itemRadio:setChecked(false) end
    if itemButton then
      local itemWidget = itemButton:getChildById('timerItemWidget')
      if itemWidget then itemWidget:destroy() end
    end
    if itemNameLabel then
      itemNameLabel:setText('(select item)')
      itemNameLabel:setColor('#888888')
    end
  end

  if cooldownRow then
    local cooldownInput = cooldownRow:getChildById('cooldownInput')
    local cooldownUnit = cooldownRow:getChildById('cooldownUnit')
    if cooldownInput then cooldownInput:setText('1') end
    if cooldownUnit then cooldownUnit:setCurrentOption('min') end
  end

  if forceItemRow then
    local forceItemCheck = forceItemRow:getChildById('forceItemCheck')
    if forceItemCheck then
      forceItemCheck:setChecked(false)
      forceItemCheck:setEnabled(false)
    end
  end

  if conditionsRow then
    local pzCheck = conditionsRow:getChildById('pzCheck')
    local nonPzCheck = conditionsRow:getChildById('nonPzCheck')
    local targetingMonsterCheck = conditionsRow:getChildById('targetingMonsterCheck')
    if pzCheck then pzCheck:setChecked(false) end
    if nonPzCheck then nonPzCheck:setChecked(false) end
    if targetingMonsterCheck then targetingMonsterCheck:setChecked(false) end
  end

  -- Reset selected item
  selectedItemId = nil
  selectedItemName = nil
end

-- Click on rule to edit
function timerPanel.onRuleClick(ruleKey)
  local rule = _Helper.Timer and _Helper.Timer.getRule(ruleKey)
  if not rule then return end

  editingRuleKey = ruleKey

  -- Update button text
  if rulesListPanel then
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then addButton:setText("Update") end
  end

  -- Populate form with rule data
  timerPanel.populateForm(rule)

  -- Refresh background colors
  timerPanel.refreshRulesListBackground()
end

function timerPanel.populateForm(rule)
  if not formPanel or not rule then return end

  local wordsRow = formPanel:getChildById('wordsRow')
  local itemRow = formPanel:getChildById('itemRow')
  local cooldownRow = formPanel:getChildById('cooldownRow')
  local forceItemRow = formPanel:getChildById('forceItemRow')
  local conditionsRow = formPanel:getChildById('conditionsRow')

  if wordsRow then
    local wordsRadio = wordsRow:getChildById('wordsRadio')
    local wordsInput = wordsRow:getChildById('wordsInput')
    if rule.type == 'words' then
      if wordsRadio then wordsRadio:setChecked(true) end
      if wordsInput then wordsInput:setText(rule.value or '') end
    else
      if wordsRadio then wordsRadio:setChecked(false) end
      if wordsInput then wordsInput:setText('') end
    end
  end

  if itemRow then
    local itemRadio = itemRow:getChildById('itemRadio')
    local itemButton = itemRow:getChildById('itemButton')
    local itemNameLabel = itemRow:getChildById('itemNameLabel')
    if rule.type == 'item' then
      if itemRadio then itemRadio:setChecked(true) end
      selectedItemId = rule.itemId
      selectedItemName = rule.value
      timerPanel.updateItemButton()
    else
      if itemRadio then itemRadio:setChecked(false) end
      selectedItemId = nil
      selectedItemName = nil
      if itemButton then
        local itemWidget = itemButton:getChildById('timerItemWidget')
        if itemWidget then itemWidget:destroy() end
      end
      if itemNameLabel then
        itemNameLabel:setText('(select item)')
        itemNameLabel:setColor('#888888')
      end
    end
  end

  if cooldownRow then
    local cooldownInput = cooldownRow:getChildById('cooldownInput')
    local cooldownUnit = cooldownRow:getChildById('cooldownUnit')
    if cooldownInput then cooldownInput:setText(tostring(rule.cooldown or 1)) end
    if cooldownUnit then cooldownUnit:setCurrentOption(rule.unit or 'min') end
  end

  if forceItemRow then
    local forceItemCheck = forceItemRow:getChildById('forceItemCheck')
    if forceItemCheck then
      forceItemCheck:setEnabled(rule.type == 'item')
      forceItemCheck:setChecked(rule.forceDecrease or false)
    end
  end

  if conditionsRow then
    local pzCheck = conditionsRow:getChildById('pzCheck')
    local nonPzCheck = conditionsRow:getChildById('nonPzCheck')
    local targetingMonsterCheck = conditionsRow:getChildById('targetingMonsterCheck')
    if pzCheck then pzCheck:setChecked(rule.inPz or false) end
    if nonPzCheck then nonPzCheck:setChecked(rule.inNonPz or false) end
    if targetingMonsterCheck then targetingMonsterCheck:setChecked(rule.targetingMonster or false) end
  end
end

function timerPanel.addRule()
  if not formPanel then
    return
  end

  -- Get values from form
  local wordsRow = formPanel:getChildById('wordsRow')
  local itemRow = formPanel:getChildById('itemRow')
  local cooldownRow = formPanel:getChildById('cooldownRow')
  local forceItemRow = formPanel:getChildById('forceItemRow')
  local conditionsRow = formPanel:getChildById('conditionsRow')

  if not wordsRow or not itemRow or not cooldownRow or not forceItemRow or not conditionsRow then
    return
  end

  local wordsRadio = wordsRow:getChildById('wordsRadio')
  local wordsInput = wordsRow:getChildById('wordsInput')
  local itemRadio = itemRow:getChildById('itemRadio')
  local cooldownInput = cooldownRow:getChildById('cooldownInput')
  local cooldownUnit = cooldownRow:getChildById('cooldownUnit')
  local forceItemCheck = forceItemRow:getChildById('forceItemCheck')
  local pzCheck = conditionsRow:getChildById('pzCheck')
  local nonPzCheck = conditionsRow:getChildById('nonPzCheck')
  local targetingMonsterCheck = conditionsRow:getChildById('targetingMonsterCheck')

  if not wordsRadio or not wordsInput or not itemRadio or
      not cooldownInput or not cooldownUnit or not forceItemCheck or
      not pzCheck or not nonPzCheck or not targetingMonsterCheck then
    return
  end

  local isWords = wordsRadio:isChecked()
  local value, itemId

  if isWords then
    value = wordsInput:getText()
    if value == '' then
      return
    end
  else
    if not selectedItemId then
      return
    end
    value = selectedItemName or ('Item ' .. selectedItemId)
    itemId = selectedItemId
  end

  local cooldownText = cooldownInput:getText()
  local cooldown = tonumber(cooldownText)

  -- Validate cooldown: must be a positive integer
  if not cooldown or cooldown < 1 or cooldown ~= math.floor(cooldown) then
    if modules.game_textmessage then
      modules.game_textmessage.displayFailureMessage(tr('Cooldown must be a positive integer!'))
    end
    return
  end

  local unit = cooldownUnit:getCurrentOption().text
  local forceDecrease = forceItemCheck:isChecked()
  local inPz = pzCheck:isChecked()
  local inNonPz = nonPzCheck:isChecked()
  local targetingMonster = targetingMonsterCheck:isChecked()

  local ruleData = {
    type = isWords and 'words' or 'item',
    value = value,
    itemId = itemId,
    cooldown = cooldown,
    unit = unit,
    forceDecrease = forceDecrease,
    inPz = inPz,
    inNonPz = inNonPz,
    targetingMonster = targetingMonster
  }

  if editingRuleKey then
    -- UPDATE mode - update existing rule
    if _Helper.Timer and _Helper.Timer.updateRule then
      _Helper.Timer.updateRule(editingRuleKey, ruleData)
      -- Update the widget in the list
      local rule = _Helper.Timer.getRule(editingRuleKey)
      if rule then
        timerPanel.updateRuleWidget(editingRuleKey, rule)
      end
    end
  else
    -- ADD mode - create new rule
    if _Helper.Timer and _Helper.Timer.addRule then
      local ruleKey, rule = _Helper.Timer.addRule(ruleData)
      if ruleKey and rule then
        timerPanel.addRuleToList(rule)
        if _RuleList and rulesList then
          _RuleList.updateArrowButtonStates(rulesList)
        end
      end
    end
  end

  -- Clear form and exit edit mode
  timerPanel.clearForm()
end

-- Helper function to format rule display text
local function formatRuleDisplayText(ruleData)
  local typePrefix = ruleData.type == 'words' and '[W] ' or '[I] '
  local conditions = {}

  -- Add PZ/non-PZ condition indicator (both checked = execute anywhere = no indicator)
  if ruleData.inPz and not ruleData.inNonPz then
    table.insert(conditions, 'PZ')
  elseif ruleData.inNonPz and not ruleData.inPz then
    table.insert(conditions, 'non-PZ')
  end

  -- Add targeting monster condition indicator
  if ruleData.targetingMonster then
    table.insert(conditions, 'targeting')
  end

  -- Add force decrease indicator (only for items)
  if ruleData.type == 'item' and ruleData.forceDecrease then
    table.insert(conditions, 'force')
  end

  local conditionSuffix = ''
  if #conditions > 0 then
    conditionSuffix = ' (' .. table.concat(conditions, ', ') .. ')'
  end

  return typePrefix .. ruleData.value .. ' - ' .. ruleData.cooldown .. ' ' .. ruleData.unit .. conditionSuffix
end

function timerPanel.updateRuleWidget(ruleKey, ruleData)
  if not rulesList then return end

  local children = rulesList:getChildren()
  for _, child in ipairs(children) do
    if child.ruleKey == ruleKey then
      -- Update rule name display
      local ruleName = child:getChildById('ruleName')
      if ruleName then
        ruleName:setText(formatRuleDisplayText(ruleData))
      end
      break
    end
  end
end

function timerPanel.addRuleToList(ruleData)
  if not rulesList then
    return
  end

  local ruleWidget = g_ui.createWidget('TimerRuleItem', rulesList)
  if not ruleWidget then
    return
  end

  ruleWidget.ruleKey = ruleData.key

  -- Set rule name display
  local ruleName = ruleWidget:getChildById('ruleName')
  if ruleName then
    ruleName:setText(formatRuleDisplayText(ruleData))
  end

  -- Setup enable checkbox
  local enableCheck = ruleWidget:getChildById('enableCheck')
  if enableCheck then
    enableCheck:setChecked(ruleData.enabled)
    enableCheck.onCheckChange = function(widget)
      timerPanel.toggleRuleEnabled(ruleWidget.ruleKey, widget:isChecked())
    end
  end

  -- Setup move buttons
  local moveUpButton = ruleWidget:getChildById('moveUpButton')
  if moveUpButton then
    moveUpButton.onClick = function()
      timerPanel.moveRuleUp(ruleWidget.ruleKey)
    end
  end

  local moveDownButton = ruleWidget:getChildById('moveDownButton')
  if moveDownButton then
    moveDownButton.onClick = function()
      timerPanel.moveRuleDown(ruleWidget.ruleKey)
    end
  end

  -- Setup remove button
  local removeButton = ruleWidget:getChildById('removeButton')
  if removeButton then
    removeButton.onClick = function()
      timerPanel.removeRule(ruleWidget.ruleKey)
    end
  end

  if _RuleList then
    _RuleList.setupDoubleClickToggle(ruleWidget)
  end

  -- Click on rule to edit (left click on any area except checkbox/buttons)
  -- Right click to show context menu
  local capturedRuleKey = ruleData.key
  local capturedRuleName = ruleData.value or ruleData.key
  ruleWidget.onMouseRelease = function(widget, mousePos, mouseButton)
    if mouseButton == MouseLeftButton then
      local clickedChild = widget:getChildByPos(mousePos)
      if clickedChild then
        local childId = clickedChild:getId()
        if childId == 'enableCheck' or childId == 'removeButton'
            or childId == 'moveUpButton' or childId == 'moveDownButton' then
          return false
        end
      end
      timerPanel.onRuleClick(capturedRuleKey)
      return true
    elseif mouseButton == MouseRightButton then
      timerPanel.showRuleContextMenu(capturedRuleKey, capturedRuleName, mousePos)
      return true
    end
    return false
  end

  -- Apply disabled background color if rule is disabled
  if not ruleData.enabled then
    ruleWidget:setBackgroundColor('#6a3a3a88')
  end
end

function timerPanel.toggleRuleEnabled(ruleKey, enabled)
  if _Helper.Timer and _Helper.Timer.toggleRule then
    _Helper.Timer.toggleRule(ruleKey, enabled)
  end
  timerPanel.refreshRulesListBackground()
end

function timerPanel.showRuleContextMenu(ruleKey, ruleName, position)
  local menu = g_ui.createWidget('PopupMenu')

  menu:addOption(tr('Edit'), function()
    timerPanel.onRuleClick(ruleKey)
  end)

  menu:addSeparator()

  menu:addOption(tr('Move Up'), function()
    timerPanel.moveRuleUp(ruleKey)
  end)

  menu:addOption(tr('Move Down'), function()
    timerPanel.moveRuleDown(ruleKey)
  end)

  menu:addSeparator()

  menu:addOption(tr('Delete'), function()
    timerPanel.removeRule(ruleKey)
  end)

  menu:display(position)
end

local function findRuleIndexByKey(ruleKey)
  local rules = _Helper.Timer and _Helper.Timer.getRules() or {}
  for i, rule in ipairs(rules) do
    if rule.key == ruleKey then
      return i, rules
    end
  end
  return nil, rules
end

function timerPanel.moveRuleUp(ruleKey)
  if not rulesList or not _RuleList then return end
  local index, rules = findRuleIndexByKey(ruleKey)
  if index and _RuleList.swapRule(rulesList, rules, index, -1) then
    _RuleList.updateArrowButtonStates(rulesList)
  end
end

function timerPanel.moveRuleDown(ruleKey)
  if not rulesList or not _RuleList then return end
  local index, rules = findRuleIndexByKey(ruleKey)
  if index and _RuleList.swapRule(rulesList, rules, index, 1) then
    _RuleList.updateArrowButtonStates(rulesList)
  end
end

function timerPanel.removeRule(ruleKey)
  local rule = _Helper.Timer and _Helper.Timer.getRule(ruleKey)
  local ruleName = rule and rule.value or "this rule"

  _RuleList.confirmRemove(ruleName, function()
    if _Helper.Timer and _Helper.Timer.removeRule then
      _Helper.Timer.removeRule(ruleKey)
    end

    if rulesList then
      local children = rulesList:getChildren()
      for _, child in ipairs(children) do
        if child.ruleKey == ruleKey then
          child:destroy()
          break
        end
      end
    end

    if _RuleList then
      _RuleList.updateArrowButtonStates(rulesList)
    end

    if editingRuleKey == ruleKey then
      timerPanel.clearForm()
    end
  end)
end

function timerPanel.refreshRulesListBackground()
  if not rulesList then return end

  local children = rulesList:getChildren()
  for _, child in ipairs(children) do
    local ruleKey = child.ruleKey
    local rule = _Helper.Timer and _Helper.Timer.getRule and _Helper.Timer.getRule(ruleKey)
    local isSelected = (ruleKey == editingRuleKey)
    local isEnabled = rule and rule.enabled

    if isSelected then
      child:setBackgroundColor('#3a6a3a88') -- Green for selected
    elseif not isEnabled then
      child:setBackgroundColor('#6a3a3a88') -- Red for disabled
    else
      child:setBackgroundColor('#00000022') -- Default
    end
  end
end

function timerPanel.getRules()
  return _Helper.Timer and _Helper.Timer.getRules() or {}
end

function timerPanel.clearRules()
  if _Helper.Timer and _Helper.Timer.clearRules then
    _Helper.Timer.clearRules()
  end
  editingRuleKey = nil
  if rulesList then
    rulesList:destroyChildren()
  end
end

-- Rebuild the rules list UI from loaded rules
function timerPanel.rebuildRulesList()
  if not rulesList then return end

  -- Clear existing UI
  rulesList:destroyChildren()
  editingRuleKey = nil

  -- Get rules from _Helper.Timer (ordered array)
  local rules = _Helper.Timer and _Helper.Timer.getRules() or {}

  -- Add each rule to the UI (ipairs preserves order)
  for _, rule in ipairs(rules) do
    timerPanel.addRuleToList(rule)
  end

  if _RuleList then
    _RuleList.updateArrowButtonStates(rulesList)
  end

  -- Update button text
  if rulesListPanel then
    local addButton = rulesListPanel:getChildById('addButton')
    if addButton then addButton:setText("Add") end
  end
end

-- Expose pure helpers for tests (and any external caller that needs them).
timerPanel.formatRuleDisplayText = formatRuleDisplayText

-- Export module
_G.modules = _G.modules or {}
_G.modules.game_helper = _G.modules.game_helper or {}
_G.modules.game_helper.timerPanel = timerPanel

return timerPanel
