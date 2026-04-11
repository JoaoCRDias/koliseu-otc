-- Preset Manager Module
-- Shared preset UI operations (add, rename, duplicate, remove, toggle, load)
-- Used by Magic Shooter and Equipment presets

local presetManager = {}

modules.game_helper = modules.game_helper or {}
modules.game_helper.presetManager = presetManager

local window = nil

local MAX_DISPLAY_LEN = 20

-- Stored contexts for access from hotkey callbacks
local shooterCtx = nil
local equipCtx = nil

local function trim(s)
  return s:match("^%s*(.-)%s*$") or s
end

function presetManager.truncateName(name)
  if not name then return "" end
  if name:len() > MAX_DISPLAY_LEN then
    return name:sub(1, MAX_DISPLAY_LEN) .. "."
  end
  return name
end

-- Generic validation: receives profiles table instead of hardcoded shooterProfiles
local function invalidPresetName(name, profiles, excludeName)
  if not profiles then return true, "Config not available." end

  if profiles[name] and name ~= excludeName then
    return true, "There is already a preset with this name."
  elseif name:len() == 0 then
    return true, "The name cannot be empty."
  elseif name:len() > 20 then
    return true, "The name cannot be longer than 20 characters."
  end
  return false
end

-- Stored context for supply presets
local supplyCtx = nil

-- Context getters/setters
function presetManager.getShooterContext() return shooterCtx end
function presetManager.setShooterContext(ctx) shooterCtx = ctx end
function presetManager.getEquipContext() return equipCtx end
function presetManager.setEquipContext(ctx) equipCtx = ctx end
function presetManager.getSupplyContext() return supplyCtx end
function presetManager.setSupplyContext(ctx) supplyCtx = ctx end

-- Context builders
-- context = { profiles, selectedKey, presetsPanel, getDefault, getProfileCount,
--             label, hotkeyLabel, onLoadProfile, onAfterToggle, _isLoadingUI }

-- Helper: always fetch profiles fresh from helperConfig (survives helperConfig = result reassignment)
local function getProfiles(profilesKey)
  local hc = _Helper.getHelperConfig()
  return hc and hc[profilesKey]
end

function presetManager.buildShooterContext()
  if not _Helper.getHelperConfig() then return nil end
  return {
    profilesKey = "shooterProfiles",
    selectedKey = "selectedShooterProfile",
    presetsPanel = nil, -- set by caller at init
    getDefault = function() return _Helper.defaultShooterProfile end,
    getProfileCount = function()
      local profiles = getProfiles("shooterProfiles")
      if not profiles then return 0 end
      local count = 0
      for _ in pairs(profiles) do count = count + 1 end
      return count
    end,
    label = "shooter",
    hotkeyLabel = "Change Shooter Preset",
    onLoadProfile = function(name)
      _Helper.MagicShooter.loadProfileByName(name)
    end,
    onAfterToggle = function()
      if _Helper.MagicShooter.rebuildCache then
        _Helper.MagicShooter.rebuildCache()
      end
    end,
    _isLoadingUI = false,
  }
end

function presetManager.buildEquipContext()
  if not _Helper.getHelperConfig() then return nil end
  return {
    profilesKey = "equipProfiles",
    selectedKey = "selectedEquipProfile",
    presetsPanel = nil, -- set by caller at init
    getDefault = function() return { rules = {}, enabled = true } end,
    getProfileCount = function()
      local profiles = getProfiles("equipProfiles")
      if not profiles then return 0 end
      local count = 0
      for _ in pairs(profiles) do count = count + 1 end
      return count
    end,
    label = "equipment",
    hotkeyLabel = "Change Equipment Preset",
    onLoadProfile = function(name)
      if modules.game_helper and modules.game_helper.equip then
        modules.game_helper.equip.loadProfileByName(name)
      end
    end,
    _isLoadingUI = false,
  }
end

function presetManager.buildSupplyContext()
  if not _Helper.getHelperConfig() then return nil end
  return {
    profilesKey = "supplyProfiles",
    selectedKey = "selectedSupplyProfile",
    presetsPanel = nil, -- set by caller (openSettings)
    getDefault = function() return { rules = {} } end,
    getProfileCount = function()
      local profiles = getProfiles("supplyProfiles")
      if not profiles then return 0 end
      local count = 0
      for _ in pairs(profiles) do count = count + 1 end
      return count
    end,
    label = "supply alert",
    hotkeyLabel = "Change Supply Preset",
    onLoadProfile = function(name)
      _Helper.LowSupplyAlarm.loadProfileByName(name)
    end,
    onAfterToggle = function()
      _Helper.LowSupplyAlarm.updateRulesList()
    end,
    _isLoadingUI = false,
  }
end

-- ============================================================
-- GENERIC PRESET UI OPERATIONS
-- ============================================================

-- Populate ComboBox from profiles
function presetManager.loadProfileOptions(ctx)
  if not ctx or not ctx.presetsPanel then return end

  local helperConfig = _Helper.getHelperConfig()
  local profiles = getProfiles(ctx.profilesKey)
  if not helperConfig or not profiles then return end

  local presets = ctx.presetsPanel:recursiveGetChildById('presets')
  if not presets then return end

  ctx._isLoadingUI = true
  presets:clearOptions()

  local profileNames = {}
  for profileName, _ in pairs(profiles) do
    table.insert(profileNames, profileName)
  end
  table.sort(profileNames)

  for _, profileName in ipairs(profileNames) do
    local display = presetManager.truncateName(profileName)
    presets:addOption(display, profileName)
  end

  local selected = helperConfig[ctx.selectedKey] or "Default"
  local selectedDisplay = presetManager.truncateName(selected)
  presets:setCurrentOption(selectedDisplay)
  presets:setTextAlign(AlignLeftCenter)

  ctx._isLoadingUI = false
end

-- ComboBox onOptionChange handler
function presetManager.onPresetChange(ctx, widget)
  if not ctx or ctx._isLoadingUI then return end
  presetManager.togglePreset(ctx, widget, false)
  if widget then widget:setTextAlign(AlignLeftCenter) end
end

-- Toggle/cycle preset (with widget = combobox selection, nil = hotkey cycle)
function presetManager.togglePreset(ctx, widget, hideMessage)
  if not ctx or ctx._isLoadingUI then return end

  local helperConfig = _Helper.getHelperConfig()
  local profiles = getProfiles(ctx.profilesKey)
  if not helperConfig or not profiles then return end

  local option = ""

  if widget then
    local currentOpt = widget:getCurrentOption()
    option = currentOpt and currentOpt.data or (currentOpt and currentOpt.text or "")
    if profiles[option] then
      ctx.onLoadProfile(option)
    end
  else
    -- Cycle to next preset (hotkey press)
    local sorted = {}
    for name, _ in pairs(profiles) do
      table.insert(sorted, name)
    end
    table.sort(sorted)

    local amount = #sorted
    if amount == 0 then return end

    local i = 1
    for j, name in ipairs(sorted) do
      if name == helperConfig[ctx.selectedKey] then
        i = j
        break
      end
    end

    local nextIndex = i % amount + 1
    option = sorted[nextIndex] or sorted[1]
    ctx.onLoadProfile(option)

    -- Update combobox if presetsPanel is open
    if ctx.presetsPanel then
      widget = ctx.presetsPanel:recursiveGetChildById("presets")
      if widget then
        local display = presetManager.truncateName(option)
        widget:setCurrentOption(display, true)
        widget:setTextAlign(AlignLeftCenter)
      end
    end
  end

  if not hideMessage then
    local capLabel = ctx.label:sub(1, 1):upper() .. ctx.label:sub(2)
    modules.game_textmessage.displayGameMessage(
      string.format("%s profile changed to %s.", capLabel, option))
  end

  if ctx.onAfterToggle then ctx.onAfterToggle() end
end

-- Remove preset with confirm dialog
function presetManager.removeProfile(ctx)
  if not ctx or not ctx.presetsPanel then return end

  local helperConfig = _Helper.getHelperConfig()
  if not helperConfig then return end

  local presets = ctx.presetsPanel:recursiveGetChildById('presets')
  if not presets then return end

  local confirmWindow = nil

  local cancel = function()
    if confirmWindow then confirmWindow:destroy() end
  end

  local confirm = function()
    if confirmWindow then confirmWindow:destroy() end
    if ctx.getProfileCount and ctx.getProfileCount() <= 1 then
      modules.game_textmessage.displayGameMessage("You can't delete your only preset.")
      return
    end
    local currentProfileName = helperConfig[ctx.selectedKey]
    presetManager.togglePreset(ctx, nil, true)
    local p = getProfiles(ctx.profilesKey)
    if p then p[currentProfileName] = nil end
    presets:removeOption(presetManager.truncateName(currentProfileName))
    local newDisplay = presetManager.truncateName(helperConfig[ctx.selectedKey])
    presets:setCurrentOption(newDisplay, true)
    modules.game_textmessage.displayGameMessage(
      string.format("Preset %s deleted.", currentProfileName))
  end

  confirmWindow = displayGeneralBox('Delete Preset',
    string.format("Are you sure you want to delete preset %s?", helperConfig[ctx.selectedKey]),
    { { text = tr('Yes'), callback = confirm }, { text = tr('No'), callback = cancel } },
    confirm, cancel)
end

-- Generic rename/add window
local function _sendRenameOrAddWindow(isRename, ctx)
  local helperConfig = _Helper.getHelperConfig()
  local helper = _Helper.getHelperWindow()

  if not helperConfig or not ctx or not ctx.presetsPanel or not helper then return end

  local profiles = getProfiles(ctx.profilesKey)
  if not profiles then return end
  local selectedKey = ctx.selectedKey
  local label = ctx.label or "preset"

  window = g_ui.loadUI('styles/shooterPreset', g_ui.getRootWidget())
  if not window then
    return true
  end

  if isRename then
    window:setText("Rename " .. label .. " preset")
    window.contentPanel.target:setText(helperConfig[selectedKey])
  else
    window:setText("Add " .. label .. " preset")
    window.contentPanel.target:setText("")
  end

  local options = ctx.presetsPanel:recursiveGetChildById('presets')

  window:show(true)
  window:raise()
  window:focus()
  window.contentPanel.target:focus()
  helper:hide()

  local onWrite = function()
    local warning = window.contentPanel.warning
    local text = trim(window.contentPanel.target:getText())
    local excludeName = isRename and helperConfig[selectedKey] or nil
    local invalid, message = invalidPresetName(text, profiles, excludeName)
    if invalid then
      warning:setVisible(true)
      warning:setTooltip(message)
    elseif not invalid and warning:isVisible() then
      warning:setVisible(false)
      warning:setTooltip('')
    end
  end

  local renameConfirm = function()
    local input = trim(window.contentPanel.target:getText())
    local oldProfileName = helperConfig[selectedKey]

    if input == oldProfileName then
      helper:show()
      window:destroy()
      return
    end

    if invalidPresetName(input, profiles, oldProfileName) then
      return
    end

    local profileConfig = profiles[oldProfileName]
    if profileConfig then
      profiles[input] = profileConfig
      helperConfig[selectedKey] = input
      local truncated = presetManager.truncateName(input)
      options:addOption(truncated, input)
      options:setCurrentOption(truncated)
      profiles[oldProfileName] = nil
      options:removeOption(presetManager.truncateName(oldProfileName))
    end

    helper:show()
    window:destroy()
  end

  local addConfirm = function()
    local input = trim(window.contentPanel.target:getText())

    if invalidPresetName(input, profiles) then
      return
    end

    local default = _Helper.deepCopy(ctx.getDefault())
    profiles[input] = default

    local truncated = presetManager.truncateName(input)
    options:addOption(truncated, input)
    options:setCurrentOption(truncated)

    helper:show()
    window:destroy()
  end

  local cancel = function()
    helper:show()
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    window:destroy()
  end

  window.contentPanel.cancelButton.onClick = cancel
  window.onEscape = cancel
  window.contentPanel.target.onTextChange = function() onWrite() end
  if isRename then
    window.contentPanel.okButton.onClick = function() renameConfirm() end
    window.onEnter = function() renameConfirm() end
  else
    window.contentPanel.okButton.onClick = function() addConfirm() end
    window.onEnter = function() addConfirm() end
  end
end

-- Generic duplicate window
local function _duplicateProfile(ctx)
  local helperConfig = _Helper.getHelperConfig()
  local helper = _Helper.getHelperWindow()

  if not helperConfig or not ctx or not ctx.presetsPanel or not helper then return end

  local profiles = getProfiles(ctx.profilesKey)
  if not profiles then return end
  local selectedKey = ctx.selectedKey
  local label = ctx.label or "preset"

  window = g_ui.loadUI('styles/shooterPreset', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:setText("Duplicate " .. label .. " preset")
  window.contentPanel.target:setText("")

  local options = ctx.presetsPanel:recursiveGetChildById('presets')

  window:show(true)
  window:raise()
  window:focus()
  window.contentPanel.target:focus()
  helper:hide()

  local onWrite = function()
    local warning = window.contentPanel.warning
    local text = trim(window.contentPanel.target:getText())
    local invalid, message = invalidPresetName(text, profiles)
    if invalid then
      warning:setVisible(true)
      warning:setTooltip(message)
    elseif not invalid and warning:isVisible() then
      warning:setVisible(false)
      warning:setTooltip('')
    end
  end

  local duplicateConfirm = function()
    local input = trim(window.contentPanel.target:getText())

    if invalidPresetName(input, profiles) then
      return
    end

    local currentProfile = profiles[helperConfig[selectedKey]]
    local copy = currentProfile and _Helper.deepCopy(currentProfile) or
        _Helper.deepCopy(ctx.getDefault())
    profiles[input] = copy

    local truncated = presetManager.truncateName(input)
    options:addOption(truncated, input)
    options:setCurrentOption(truncated)

    helper:show()
    window:destroy()
  end

  local cancel = function()
    helper:show()
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    window:destroy()
  end

  window.contentPanel.cancelButton.onClick = cancel
  window.onEscape = cancel
  window.contentPanel.target.onTextChange = function() onWrite() end
  window.contentPanel.okButton.onClick = function() duplicateConfirm() end
  window.onEnter = function() duplicateConfirm() end
end

-- Wire all preset callbacks on a presetsSection widget
function presetManager.initPresets(ctx)
  if not ctx or not ctx.presetsPanel then return end

  local section = ctx.presetsPanel
  local presets = section:recursiveGetChildById('presets')
  local rmvBtn = section:recursiveGetChildById('rmvPresetButton')
  local setKeyBtn = section:recursiveGetChildById('setKeyPresetButton')
  local renameBtn = section:recursiveGetChildById('renameButton')
  local dupBtn = section:recursiveGetChildById('duplicateButton')
  local newBtn = section:recursiveGetChildById('newPresetButton')

  if presets then
    presets.onOptionChange = function(widget)
      presetManager.onPresetChange(ctx, widget)
    end
  end

  if rmvBtn then
    rmvBtn.onClick = function()
      presetManager.removeProfile(ctx)
    end
  end

  if setKeyBtn then
    setKeyBtn.onClick = function()
      manageHotkeys(ctx.hotkeyLabel)
    end
  end

  if renameBtn then
    renameBtn.onClick = function()
      _sendRenameOrAddWindow(true, ctx)
    end
  end

  if dupBtn then
    dupBtn.onClick = function()
      _duplicateProfile(ctx)
    end
  end

  if newBtn then
    newBtn.onClick = function()
      _sendRenameOrAddWindow(false, ctx)
    end
  end
end

-- Shooter globals (backward compat stubs)
function sendShooterRenameOrAddWindow(isRename)
  _sendRenameOrAddWindow(isRename, shooterCtx or presetManager.buildShooterContext())
end

function duplicateShooterProfile()
  _duplicateProfile(shooterCtx or presetManager.buildShooterContext())
end

function removeShooterProfile()
  presetManager.removeProfile(shooterCtx or presetManager.buildShooterContext())
end

-- Equipment globals (backward compat stubs)
function sendEquipRenameOrAddWindow(isRename)
  _sendRenameOrAddWindow(isRename, equipCtx or presetManager.buildEquipContext())
end

function duplicateEquipProfile()
  _duplicateProfile(equipCtx or presetManager.buildEquipContext())
end

function removeEquipProfile()
  presetManager.removeProfile(equipCtx or presetManager.buildEquipContext())
end

return presetManager
