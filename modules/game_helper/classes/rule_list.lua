-- Shared rule list helpers for modules that use ordered rule lists
-- with move up/down buttons (equipment, magic_shooter, etc.)

if not _RuleList then
  _RuleList = {}
end

-- Disable move-up on first item, move-down on last item
function _RuleList.updateArrowButtonStates(rulesList)
  if not rulesList then return end
  local children = rulesList:getChildren()
  local count = #children
  for i, child in ipairs(children) do
    local upBtn = child:getChildById('moveUpButton')
    local downBtn = child:getChildById('moveDownButton')
    if upBtn then
      upBtn:setEnabled(i > 1)
    end
    if downBtn then
      downBtn:setEnabled(i < count)
    end
  end
end

-- Swap rule at ruleIndex with adjacent rule in the list.
-- direction: -1 for up, +1 for down
-- Returns true if swapped, false if at boundary.
function _RuleList.swapRule(rulesList, rulesArray, ruleIndex, direction)
  local targetIndex = ruleIndex + direction
  if targetIndex < 1 or targetIndex > #rulesArray then
    return false
  end

  -- Swap in data array
  rulesArray[ruleIndex], rulesArray[targetIndex] = rulesArray[targetIndex], rulesArray[ruleIndex]

  -- Swap widget in list
  if rulesList then
    local children = rulesList:getChildren()
    local widget = children[ruleIndex]
    if widget then
      rulesList:moveChildToIndex(widget, targetIndex)
    end
  end

  return true
end

-- Toggle enable/disable on double-click anywhere on the rule widget
function _RuleList.setupDoubleClickToggle(ruleWidget)
  ruleWidget.onDoubleClick = function(widget)
    local enableCheck = widget:getChildById('enableCheck')
    if enableCheck then
      enableCheck:setChecked(not enableCheck:isChecked())
      return true
    end
    return false
  end
end

-- Show a confirmation dialog for removing a rule.
-- ruleName: display name for the dialog message
-- onConfirm: callback to execute when user confirms removal
function _RuleList.confirmRemove(ruleName, onConfirm)
  local confirmWindow = nil

  local confirmCallback = function()
    if confirmWindow then
      confirmWindow:destroy()
    end
    if onConfirm then
      onConfirm()
    end
  end

  local cancelCallback = function()
    if confirmWindow then
      confirmWindow:destroy()
    end
  end

  -- First button anchors to right, second to left of first
  -- Visual order: [No] [Yes]
  confirmWindow = displayGeneralBox(
    tr('Confirm Removal'),
    tr('Are you sure you want to remove "%s"?', ruleName),
    {
      { text = tr('Yes'), callback = confirmCallback },
      { text = tr('No'),  callback = cancelCallback },
    },
    confirmCallback, cancelCallback
  )
end
