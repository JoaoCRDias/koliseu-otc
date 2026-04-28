-- Tools Panel Module
-- Manages all tools functionality: Gold Change, Exercise Training, Auto Reconnect,
-- Quiver Refill (Paladin), Magic Shield (Sorcerer/Druid)
-- Based on the same pattern as equip_panel.lua

local tools = {}

-- Export module immediately so it's available for OTUI callbacks
modules.game_helper = modules.game_helper or {}
modules.game_helper.tools = tools

-- Local references
local toolsPanel = nil
local paladinPanel = nil
local magePanel = nil
local helper = nil

-- Exercise dummies IDs


-- Magic Shield constants
local MAGIC_SHIELD_SPELL_ID = 44         -- utamo vita
local CANCEL_MAGIC_SHIELD_SPELL_ID = 245 -- exana vita
local MAGIC_SHIELD_POTION_ID = 35563     -- magic shield potion

-- Local references for mouse grabber
local mouseGrabberWidget = nil

-- Quiver refill state
local isRefillingQuiver = false
local lastQuiverRefillTime = 0   -- Cooldown to prevent spam (in milliseconds)

-- Auto Follow state
local autoFollowLoopEvent = nil
local lastFollowId = 0
local isAutoFollowEnabled = false

-- Advertising channel state
local advertisingChannelTimerEvent = nil
local ADVERTISING_INTERVAL_MS = 10 * 60 * 1000

-- Anti AFK state
local antiAfkTimerEvent = nil
local ANTI_AFK_INTERVAL_MS = 10 * 60 * 1000

-- Item Timer state
local lastItemTimerUse = {}

-- Vender Loot state
local VENDOR_LOOT_INTERVAL_MS = 5 * 60 * 1000
local VENDOR_LOOT_ITEM_IDS = { 41088 }
local lastVendorLootUse = 0

-- Stamina Refill state
local staminaRefillIds = { 62215, 63171, 63425, 36725 }
local lastStaminaRefillUse = 0

-- AutoBoost Store state
local lastAutoBoostStoreAttemptMs = 0
local lastBoostsCategoryRequestMs = 0
local autoBoostStoreSuppressCheckChange = false
local XP_BOOST_PREFETCH_CATEGORIES = { "Boosts", "Extras" }

-- Imbuement Scroll state
local imbuementScrollAllowedIds = {
  51444, 51445, 51446, 51447, 51448, 51449, 51450, 51451, 51452, 51453, 51454, 51455, 51456, 51457, 51458, 51459,
  51460, 51461, 51462, 51463, 51464, 51465, 51466, 51467, 51724, 51725, 51726, 51727, 51728, 51729, 51730, 51731,
  51732, 51733, 51734, 51735, 51736, 51737, 51738, 51739, 51740, 51741, 51742, 51743, 51744, 51745, 51746, 51747,
}
local imbuementScrollBatchRunning = false
local imbuementScrollQueue = nil
local imbuementScrollLastAttempt = nil
local imbuementScrollBackoff = {}

-- Auto Party settings window
local autoPartySettingsWindow = nil

-- Imbuement Scroll settings window
local imbuementScrollSettingsWindow = nil


-- ============================================================
-- HELPER FUNCTIONS
-- ============================================================

local function getMouseGrabber()
  if mouseGrabberWidget then return mouseGrabberWidget end
  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)
  return mouseGrabberWidget
end

local function getPlayer()
  return g_game.getLocalPlayer()
end

local function getDistanceBetween(p1, p2)
  if g_helperCore and g_helperCore.getDistanceBetween then
    return g_helperCore.getDistanceBetween(p1, p2)
  end
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end

local function isCustomQuiverItem(itemId)
  if not itemId or itemId <= 0 or type(CustomQuiverItemIds) ~= "table" then
    return false
  end

  if CustomQuiverItemIds[itemId] ~= nil then
    return true
  end

  for _, customId in ipairs(CustomQuiverItemIds) do
    if customId == itemId then
      return true
    end
  end

  return false
end

-- Helper function to get toolsPanel (lazy initialization)
local function getToolsPanel()
  if toolsPanel then return toolsPanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
      if container then
        toolsPanel = container:recursiveGetChildById('toolsPanel')
      end
    end
  end
  return toolsPanel
end

-- Helper function to get paladinPanel
local function getPaladinPanel()
  if paladinPanel then return paladinPanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
      if container then
        paladinPanel = container:recursiveGetChildById('paladinPanel')
      end
    end
  end
  return paladinPanel
end

-- Helper function to get magePanel
local function getMagePanel()
  if magePanel then return magePanel end
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    local helperWindow = rootWidget:recursiveGetChildById('helperWindow')
    if helperWindow then
      local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
      if container then
        magePanel = container:recursiveGetChildById('magePanel')
      end
    end
  end
  return magePanel
end

local function getHelperWindow()
  local rootWidget = g_ui.getRootWidget()
  if rootWidget then
    return rootWidget:recursiveGetChildById('helperWindow')
  end
  return nil
end

-- Get player vocation ID (normalized to base vocation)
-- Client IDs: Knight=1, Paladin=2, Sorcerer=3, Druid=4, Monk=5
-- Promoted: EliteKnight=11, RoyalPaladin=12, MasterSorcerer=13, ElderDruid=14, ExaltedMonk=15
-- Returns normalized ID: Knight=1, Paladin=2, Sorcerer=3, Druid=4, Monk=5
local function getPlayerVocationId()
  local player = getPlayer()
  if not player then return 0 end
  local voc = player:getVocation()
  -- Normalize to base vocation (remove promotion)
  if voc == 1 or voc == 11 then return 1 end -- Knight / Elite Knight
  if voc == 2 or voc == 12 then return 2 end -- Paladin / Royal Paladin
  if voc == 3 or voc == 13 then return 3 end -- Sorcerer / Master Sorcerer
  if voc == 4 or voc == 14 then return 4 end -- Druid / Elder Druid
  if voc == 5 or voc == 15 then return 5 end -- Monk / Exalted Monk
  return voc
end

-- Check if player has magic shield state
local function hasMagicShield()
  local player = getPlayer()
  if not player then return false end
  local states = player:getStates()
  if not states then return false end
  -- Check both ManaShield (5) and NewManaShield (27)
  return bit.band(states, PlayerStates.ManaShield) ~= 0 or bit.band(states, PlayerStates.NewManaShield) ~= 0
end

-- Get spell cooldown from _Helper
local function getSpellCooldown(spellId)
  if _Helper and _Helper.getSpellCooldown then
    return _Helper.getSpellCooldown(spellId)
  end
  return 0
end

-- Get group spell cooldown from _Helper
local function getGroupSpellCooldown(groupId)
  if _Helper and _Helper.getGroupSpellCooldown then
    return _Helper.getGroupSpellCooldown(groupId)
  end
  return 0
end

local function isSpellOnCooldown(spellId)
  if g_helperCore and g_helperCore.isSpellOnCooldown then
    return g_helperCore.isSpellOnCooldown(spellId)
  end
  return getSpellCooldown(spellId) > g_clock.millis()
end

local function isGroupOnCooldown(groupId)
  if g_helperCore and g_helperCore.isGroupOnCooldown then
    return g_helperCore.isGroupOnCooldown(groupId)
  end
  return getGroupSpellCooldown(groupId) > g_clock.millis()
end

-- ============================================================
-- GOLD CHANGE FUNCTIONS
-- ============================================================

local pendingGoldChangeEvent = nil
local goldChangeLoopEvent = nil

-- Gold change speed constants
local GOLD_CHANGE_FAST_DELAY = 50    -- Fast mode: 50ms between uses
local GOLD_CHANGE_NORMAL_DELAY = 100 -- Normal mode: 100ms debounce
local GOLD_CHANGE_STACK_THRESHOLD = 5 -- Threshold to switch to fast mode

-- Find item with minimum count in containers
local function findItemWithMinCount(itemId, minCount)
  for _, container in pairs(g_game.getContainers()) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == itemId and item:getCount() >= minCount then
        return item
      end
    end
  end
  return nil
end

-- Count all stacks of 100 items and return first found
local function findAndCount100Stacks(itemId)
  local containers = g_game.getContainers()
  if not containers then
    return nil, 0
  end

  local hasContainer = false
  for _ in pairs(containers) do
    hasContainer = true
    break
  end
  if not hasContainer then
    return nil, 0
  end

  local count = 0
  local firstStack = nil
  local firstContainerId = nil
  local firstSlot = nil

  for containerId, container in pairs(containers) do
    local items = container:getItems()
    if items then
      for slot, item in pairs(items) do
        if item:getId() == itemId and item:getCount() == 100 then
          count = count + 1
          if not firstStack then
            firstStack = item
            firstContainerId = containerId
            firstSlot = slot
          end
        end
      end
    end
  end

  return firstStack, count, firstContainerId, firstSlot
end

-- Find any stack of 100 items
local function findAny100(itemId)
  local stack, count, containerId, slot = findAndCount100Stacks(itemId)
  return stack, containerId, slot, count
end

-- Internal function to change gold (returns stack count for speed control)
local function helper_changeGold()
  local goldId = 3031
  local platinumId = 3035

  local stack, _, _, count = findAny100(platinumId)
  if not stack then
    stack, _, _, count = findAny100(goldId)
  end
  if not stack then
    return 0
  end

  -- Tenta usar normalmente, se falhar, tenta useWith como fallback
  local used = g_game.use(stack)
  if used ~= true and g_game.useWith then
    g_game.useWith(stack, stack)
  end
  return count
end

-- Stop the fast change loop
local function stopGoldChangeLoop()
  if goldChangeLoopEvent then
    removeEvent(goldChangeLoopEvent)
    goldChangeLoopEvent = nil
  end
end

-- Fast change loop for when we have many stacks
local function goldChangeLoop()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local player = getPlayer()

  if not g_game.isOnline() or not player or not helperConfig or not helperConfig.autoChangeGold then
    stopGoldChangeLoop()
    return
  end

  safeDoThing(false)
  local stackCount = helper_changeGold()
  safeDoThing(true)

  -- Continue loop only if we still have 5+ stacks
  if stackCount >= GOLD_CHANGE_STACK_THRESHOLD then
    goldChangeLoopEvent = scheduleEvent(goldChangeLoop, GOLD_CHANGE_FAST_DELAY)
  else
    goldChangeLoopEvent = nil
  end
end

-- Toggle gold change feature
function tools.toggleChangeGold(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoChangeGold = checked
  end
  -- Save configuration
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Main auto change gold function
function tools.autoChangeGold()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local player = getPlayer()

  if not g_game.isOnline() or not player or not helperConfig or not helperConfig.autoChangeGold then
    return
  end

  -- Count stacks first to decide mode
  local goldId = 3031
  local platinumId = 3035
  local _, platCount = findAndCount100Stacks(platinumId)
  local _, goldCount = findAndCount100Stacks(goldId)
  local totalStacks = platCount + goldCount

  -- If 5+ stacks and no loop running, start fast loop
  if totalStacks >= GOLD_CHANGE_STACK_THRESHOLD and not goldChangeLoopEvent then
    goldChangeLoop()
  elseif totalStacks > 0 and not goldChangeLoopEvent then
    -- Normal single use
    safeDoThing(false)
    helper_changeGold()
    safeDoThing(true)
  end
end

-- Called when resources balance changes (reactive gold change)
function tools.onResourcesBalanceChange(value, oldValue, resourceType)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()

  -- React only to gold equipped changes (coins in inventory/containers)
  if resourceType ~= ResourceTypes.GOLD_EQUIPPED or not helperConfig or not helperConfig.autoChangeGold then
    return
  end

  -- If fast loop is already running, let it handle everything
  if goldChangeLoopEvent then
    return
  end

  -- Only execute if crossed a multiple of 100 (e.g.: 99->100, 199->200)
  local oldHundreds = math.floor(oldValue / 100)
  local newHundreds = math.floor(value / 100)
  if newHundreds > oldHundreds then
    -- Debounce: cancel previous event if exists
    if pendingGoldChangeEvent then
      removeEvent(pendingGoldChangeEvent)
    end
    pendingGoldChangeEvent = scheduleEvent(function()
      pendingGoldChangeEvent = nil
      tools.autoChangeGold()
    end, GOLD_CHANGE_NORMAL_DELAY)
  end
end

-- ============================================================
-- EXERCISE TRAINING FUNCTIONS
-- ============================================================
-- Now delegated to _Helper.ExerciseTraining class for state-driven logic
-- The class handles: PZ detection, idle tracking, automatic exercise selection,
-- and position-based retry logic.

-- Toggle exercise training (called from UI checkbox)
function tools.toggleExerciseTraining(checked)
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.toggle then
    _Helper.ExerciseTraining.toggle(checked)
  end
end

-- Check exercise event (legacy function for backwards compatibility)
-- Now delegates to the new state-driven class
function tools.checkExerciseEvent()
  -- The new class uses its own cycle event, but we keep this for eventTable compatibility
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.check then
    _Helper.ExerciseTraining.check()
  end
end

-- Get nearest exercise dummy in sight (kept for potential external use)
function tools.getExerciseDummy()
  local currentPlayer = getPlayer()
  if not currentPlayer then
    return nil
  end
  local playerPos = currentPlayer:getPosition()
  local itemList = {}
  for _, id in pairs(ExerciseDummies) do
    local items = g_map.findItemsById(id, 5)
    if items then
      for pos, ptr in pairs(items) do
        if pos.z == playerPos.z then
          itemList[#itemList + 1] = { position = pos, item = ptr }
        end
      end
    end
  end

  table.sort(itemList, function(a, b)
    return getDistanceBetween(playerPos, a.position) < getDistanceBetween(playerPos, b.position)
  end)

  for _, data in pairs(itemList) do
    if g_map.isSightClear(data.position, playerPos) then
      return data.item
    end
  end
  return nil
end

-- NOTE: Manual exercise item assignment functions removed.
-- Exercise items are now automatically selected from ExerciseIds in inventory.
-- The _Helper.ExerciseTraining class handles automatic selection.

-- ============================================================
-- QUIVER REFILL FUNCTIONS (Paladin Only)
-- ============================================================

-- Assign ammunition item to button
function tools.assignQuiverAmmo(button)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()

  if g_mouse and g_mouse.updateGrabber then
    g_mouse.updateGrabber(grabber, 'target')
  end
  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')
  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    tools.onAssignQuiverAmmo(self, mousePosition, mouseButton, button)
  end
end

-- Handle ammunition item assignment
function tools.onAssignQuiverAmmo(self, mousePosition, mouseButton, button)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()

  if g_mouse and g_mouse.updateGrabber then
    g_mouse.updateGrabber(grabber, 'target')
  end
  grabber:ungrabMouse()
  g_mouse.popCursor('target')
  grabber.onMouseRelease = nil
  if helperWindow then helperWindow:show() end

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local ammoId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      -- Check if item is ammunition
      local thingType = g_things.getThingType(item:getId(), ThingCategoryItem)
      if (thingType and thingType:isAmmo()) or isCustomQuiverItem(item:getId()) then
        ammoId = item:getId()
      end
    end
  end

  if ammoId > 0 then
    button:setImageSource('/images/ui/item')
    if not button:getChildById('ammoItem') then
      local itemWidget = g_ui.createWidget('PotionItem', button)
      if itemWidget then
        itemWidget:setId('ammoItem')
      end
    end
    local itemWidget = button:getChildById('ammoItem')
    if itemWidget then
      itemWidget:setItemId(ammoId)
    end
    -- Save to config
    local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
    if helperConfig then
      helperConfig.quiverRefill = helperConfig.quiverRefill or {}
      helperConfig.quiverRefill.itemId = ammoId
      if _Helper.saveSettings then
        _Helper.saveSettings()
      end
    end
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid ammunition item! Select an arrow, bolt or throwing item.'))
  end
end

-- Toggle quiver refill
function tools.toggleQuiverRefill(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.quiverRefill = helperConfig.quiverRefill or {}
    helperConfig.quiverRefill.enabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Setup numeric input validation for quiver min value (positive numbers only)
function tools.setupQuiverMinInput()
  local panel = getPaladinPanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('quiverMinValue')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      -- Allow only digits
      local numericText = text:gsub("[^%d]", "")
      if numericText ~= text then
        widget:setText(numericText)
      end

      -- Save value if valid
      local value = tonumber(numericText)
      if value and value > 0 then
        local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
        if helperConfig then
          helperConfig.quiverRefill = helperConfig.quiverRefill or {}
          helperConfig.quiverRefill.minValue = value
          if _Helper.saveSettings then
            _Helper.saveSettings()
          end
        end
      end

      isUpdating = false
    end
  end
end

-- Setup numeric input validation for quiver refill value (positive numbers only)
function tools.setupQuiverRefillInput()
  local panel = getPaladinPanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('quiverRefillValue')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      -- Allow only digits
      local numericText = text:gsub("[^%d]", "")
      if numericText ~= text then
        widget:setText(numericText)
      end

      -- Save value if valid
      local value = tonumber(numericText)
      if value and value > 0 then
        local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
        if helperConfig then
          helperConfig.quiverRefill = helperConfig.quiverRefill or {}
          helperConfig.quiverRefill.refillValue = value
          if _Helper.saveSettings then
            _Helper.saveSettings()
          end
        end
      end

      isUpdating = false
    end
  end
end

-- Check and refill quiver
function tools.checkQuiverRefill()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()

  if not helperConfig or not helperConfig.quiverRefill or not helperConfig.quiverRefill.enabled then
    isRefillingQuiver = false
    return
  end

  local player = getPlayer()
  if not player then return end

  local itemId = helperConfig.quiverRefill.itemId or 0
  if itemId == 0 then return end

  local minValue = helperConfig.quiverRefill.minValue or 50
  local refillValue = helperConfig.quiverRefill.refillValue or 100

  -- Get quiver item count from right slot (InventorySlotRight = 5)
  local rightItem = player:getInventoryItem(InventorySlotRight)
  if not rightItem then
    isRefillingQuiver = false
    return
  end

  -- Use getSubType for stackable items count or getContainerItemCount for containers
  local quiverCount = 0
  if rightItem:isContainer() then
    quiverCount = rightItem:getContainerItemCount()
  else
    quiverCount = rightItem:getCount()
  end

  -- Get available ammo count in inventory (excluding quiver)
  local availableAmmo = player:getInventoryCount(itemId, 0)

  -- Check if we need to start refilling
  if quiverCount < minValue and not isRefillingQuiver then
    isRefillingQuiver = true
  end

  -- Check if we should stop refilling
  if isRefillingQuiver and quiverCount >= refillValue then
    isRefillingQuiver = false
    return
  end

  -- If we're refilling, equip the ammunition
  if isRefillingQuiver then
    -- GUARD 1: No ammo available in inventory to move
    if availableAmmo == 0 then
      isRefillingQuiver = false
      return
    end

    -- GUARD 2: All available arrows are already in the quiver
    -- availableAmmo counts ALL arrows of this type (including those in quiver)
    -- quiverCount is the total items inside the quiver (via getContainerItemCount)
    -- If availableAmmo <= quiverCount, there are no arrows outside to move
    if availableAmmo <= quiverCount then
      isRefillingQuiver = false
      return
    end

    -- GUARD 3: Time-based cooldown to prevent spam (500ms between equip attempts)
    local currentTime = g_clock.millis()
    if currentTime - lastQuiverRefillTime < 500 then
      return
    end
    lastQuiverRefillTime = currentTime

    -- Equip the ammunition (use equipItemId to equip)
    safeDoThing(false)
    g_game.equipItemId(itemId, 0)
    safeDoThing(true)
  end
end

-- ============================================================
-- MAGIC SHIELD FUNCTIONS (Sorcerer/Druid Only)
-- ============================================================

-- Toggle utamo vita auto-cast
function tools.toggleUtamoVita(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShield = helperConfig.magicShield or {}
    helperConfig.magicShield.utamoEnabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Toggle exana vita auto-cast
function tools.toggleExanaVita(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShield = helperConfig.magicShield or {}
    helperConfig.magicShield.exanaEnabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Toggle magic shield potion
function tools.toggleMagicShieldPotion(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.magicShield = helperConfig.magicShield or {}
    helperConfig.magicShield.potionEnabled = checked
  end
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Setup numeric input validation for utamo HP percent (0-100)
function tools.setupUtamoHpInput()
  local panel = getMagePanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('utamoHpPercent')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      -- Allow only digits and clamp to max 100
      local numericText = text:gsub("[^%d]", "")
      local value = tonumber(numericText) or 0
      if value > 100 then
        numericText = "100"
      end
      if numericText ~= text then
        widget:setText(numericText)
      end

      -- Save value if valid
      if value > 0 and value <= 100 then
        local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
        if helperConfig then
          helperConfig.magicShield = helperConfig.magicShield or {}
          helperConfig.magicShield.utamoHpPercent = value
          if _Helper.saveSettings then
            _Helper.saveSettings()
          end
        end
      end

      isUpdating = false
    end
  end
end

-- Setup numeric input validation for exana HP percent (0-100)
function tools.setupExanaHpInput()
  local panel = getMagePanel()
  if not panel then return end

  local input = panel:recursiveGetChildById('exanaHpPercent')
  if input then
    local isUpdating = false
    input.onTextChange = function(widget, text)
      if isUpdating then return end
      isUpdating = true

      -- Allow only digits and clamp to max 100
      local numericText = text:gsub("[^%d]", "")
      local value = tonumber(numericText) or 0
      if value > 100 then
        numericText = "100"
      end
      if numericText ~= text then
        widget:setText(numericText)
      end

      -- Save value if valid
      if value > 0 and value <= 100 then
        local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
        if helperConfig then
          helperConfig.magicShield = helperConfig.magicShield or {}
          helperConfig.magicShield.exanaHpPercent = value
          if _Helper.saveSettings then
            _Helper.saveSettings()
          end
        end
      end

      isUpdating = false
    end
  end
end

-- Check and manage magic shield
-- Support group ID is 3
local SUPPORT_GROUP_ID = 3

function tools.checkMagicShield()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.magicShield then
    return
  end

  local player = getPlayer()
  if not player then return end

  local health = player:getHealth()
  local maxHealth = player:getMaxHealth()
  if maxHealth == 0 then return end

  local healthPercent = math.floor((health / maxHealth) * 100)
  local hasMShield = hasMagicShield()

  local utamoEnabled = helperConfig.magicShield.utamoEnabled
  local exanaEnabled = helperConfig.magicShield.exanaEnabled
  local potionEnabled = helperConfig.magicShield.potionEnabled
  local utamoHpPercent = helperConfig.magicShield.utamoHpPercent or 80
  local exanaHpPercent = helperConfig.magicShield.exanaHpPercent or 90

  -- Check if we should cast exana vita (cancel magic shield)
  -- HP is ABOVE threshold AND has magic shield active
  if exanaEnabled and healthPercent > exanaHpPercent and hasMShield then
    if not isGroupOnCooldown(SUPPORT_GROUP_ID) then
      safeDoThing(false)
      g_game.talk("exana vita")
      safeDoThing(true)
      return
    end
  end

  -- Check if we should cast utamo vita (enable magic shield)
  -- HP is BELOW threshold AND does NOT have magic shield active
  if utamoEnabled and healthPercent < utamoHpPercent and not hasMShield then
    if not isGroupOnCooldown(SUPPORT_GROUP_ID) then
      safeDoThing(false)
      g_game.talk("utamo vita")
      safeDoThing(true)
      return
    else
      -- Support group is on cooldown, check if we should use potion
      if potionEnabled and player:getInventoryCount(MAGIC_SHIELD_POTION_ID, 0) > 0 then
        safeDoThing(false)
        g_game.useInventoryItem(MAGIC_SHIELD_POTION_ID)
        safeDoThing(true)
        return
      end
    end
  end
end


-- ============================================================
-- AUTO FOLLOW FUNCTIONS
-- ============================================================

-- ============================================================
-- AUTO FOLLOW FUNCTIONS
-- ============================================================

local lastFollowAttemptTime = 0
local lastFollowDist = nil
local lastFollowDistChangeTime = 0

local function stopAutoFollowLoop()
  if autoFollowLoopEvent then
    removeEvent(autoFollowLoopEvent)
    autoFollowLoopEvent = nil
  end
end

-- Simple, robust loop that handles all states
local function autoFollowLoop()
  if not g_game.isOnline() or not isAutoFollowEnabled then
    stopAutoFollowLoop()
    return
  end
  
  local player = getPlayer()
  if not player then 
    stopAutoFollowLoop()
    return 
  end

  -- 1. Identify current state
  local followingCreature = g_game.getFollowingCreature()
  local targetCreature = nil

  -- 2. Update Target ID if we are manually following someone new
  if followingCreature then
    if followingCreature:getId() ~= lastFollowId then
      lastFollowId = followingCreature:getId()
      g_logger.info("AutoFollow: New target selected: " .. lastFollowId)
    end
  end

  -- 3. If we have a target ID, try to find the creature object
  if lastFollowId > 0 then
    targetCreature = g_map.getCreatureById(lastFollowId)
    
    -- Fallback: Scan spectators if not found in cache
    if not targetCreature then
        local spectators = g_map.getSpectators(player:getPosition(), false)
        for _, spec in ipairs(spectators) do
            if spec:getId() == lastFollowId then
                targetCreature = spec
                break
            end
        end
    end
  end

  -- 4. Decide action based on state
  if targetCreature then
      if targetCreature:isDead() then
          -- Target dead -> Stop everything
          if lastFollowId > 0 then
              g_logger.info("AutoFollow: Target dead. Auto Follow disabled for this target.")
              lastFollowId = 0
          end
      else
          -- Target is alive and visible. Are we following it?
          if followingCreature and followingCreature:getId() == lastFollowId then
              -- We ARE following. Check if we are stuck for long enough.
              local isWalking = player:isWalking() or player:isAutoWalking() or player:isServerWalking()
              
              local playerPos = player:getPosition()
              local targetPos = targetCreature:getPosition()
              
              if playerPos and targetPos then
                  local dist = math.max(math.abs(playerPos.x - targetPos.x),
                                        math.abs(playerPos.y - targetPos.y))

                  local now = g_clock.millis()
                  if lastFollowDist == nil or dist ~= lastFollowDist then
                      lastFollowDist = dist
                      lastFollowDistChangeTime = now
                  end

                  -- If not walking, far from target, and distance hasn't changed for a while, refresh follow.
                  if not isWalking and dist > 1 and (now - lastFollowDistChangeTime) > 450 then
                      if now - lastFollowAttemptTime > 350 then
                          g_game.follow(targetCreature)
                          if modules.game_helper and modules.game_helper.notifySmartFollowFollowTarget then
                            modules.game_helper.notifySmartFollowFollowTarget(targetCreature)
                          end
                          lastFollowAttemptTime = now
                          lastFollowDistChangeTime = now
                      end
                  end
          end -- Closes if playerPos and targetPos then
      else
          -- We are NOT following the target (or we just cancelled it).
          -- Action: FOLLOW (Start)
          local now = g_clock.millis()
          if now - lastFollowAttemptTime > 350 then
              g_game.follow(targetCreature)
              if modules.game_helper and modules.game_helper.notifySmartFollowFollowTarget then
                modules.game_helper.notifySmartFollowFollowTarget(targetCreature)
              end
              lastFollowAttemptTime = now
              lastFollowDist = nil
              lastFollowDistChangeTime = now
          end
      end
      end
  else
      -- Target not visible. We do nothing and wait for it to appear.
      -- The loop naturally covers "waiting" without extra checking.
  end

  autoFollowLoopEvent = scheduleEvent(autoFollowLoop, 150)
end

function tools.toggleAutoFollow(checked)
  isAutoFollowEnabled = checked
  
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoFollow = checked
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end

  if checked then
    local followCreature = g_game.getFollowingCreature()
    if followCreature then
      lastFollowId = followCreature:getId()
    end
    lastFollowAttemptTime = 0
    lastFollowDist = nil
    lastFollowDistChangeTime = 0

    if not autoFollowLoopEvent then
      autoFollowLoop()
    end
  else
    stopAutoFollowLoop()
    lastFollowId = 0
    lastFollowAttemptTime = 0
    lastFollowDist = nil
    lastFollowDistChangeTime = 0
  end
end

-- ============================================================
-- VOCATION PANEL VISIBILITY
-- ============================================================

-- Update panel visibility based on vocation
function tools.updateVocationPanels()
  local vocationId = getPlayerVocationId()
  local palPanel = getPaladinPanel()
  local magPanel = getMagePanel()

  if palPanel then
    palPanel:setVisible(vocationId == 2)
  end

  if magPanel then
    magPanel:setVisible(vocationId == 3 or vocationId == 4)
  end

  tools.adjustToolsHeight()
end

function tools.adjustToolsHeight()
  scheduleEvent(function()
    local helperWindow = getHelperWindow()
    if not helperWindow or not helperWindow:isVisible() then return end

    local container = helperWindow:recursiveGetChildById('toolsPanelContainer')
    if not container or not container:isVisible() then return end

    local tp = container:recursiveGetChildById('toolsPanel')
    if not tp then return end

    local neededH = tp:getHeight()
    local pp = container:recursiveGetChildById('paladinPanel')
    local mp = container:recursiveGetChildById('magePanel')

    if pp and pp:isVisible() then
      neededH = neededH + pp:getMarginTop() + pp:getHeight()
    elseif mp and mp:isVisible() then
      neededH = neededH + mp:getMarginTop() + mp:getHeight()
    end

    local containerH = container:getHeight()
    local diff = neededH - containerH
    if math.abs(diff) < 2 then return end

    local w = helperWindow:getWidth()
    local h = helperWindow:getHeight()
    helperWindow:setSize(tosize(w .. " " .. (h + diff)))
  end, 50)
end

-- ============================================================
-- VENDER LOOT
-- ============================================================

function tools.togglePouchSeller(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.pouchSeller = checked
    if checked then lastVendorLootUse = 0 end
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.checkVendorLoot()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.pouchSeller then return end
  local player = getPlayer()
  if not player or not g_game.isOnline() then return end
  local nowMs = g_clock.millis()
  if lastVendorLootUse ~= 0 and nowMs < lastVendorLootUse + VENDOR_LOOT_INTERVAL_MS then return end
  for _, id in ipairs(VENDOR_LOOT_ITEM_IDS) do
    local ok, count = pcall(function() return player:getInventoryCount(id, 0) end)
    if ok and count and count > 0 then
      pcall(function() g_game.useInventoryItem(id) end)
      lastVendorLootUse = nowMs
      return
    end
  end
end

function tools.loadVendorLootToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local check = panel:recursiveGetChildById("pouchSeller")
  if check then check:setChecked(helperConfig.pouchSeller or false) end
end

-- ============================================================
-- STAMINA REFILL
-- ============================================================

function tools.assignStaminaRefillItem(button)
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()
  if g_mouse and g_mouse.updateGrabber then g_mouse.updateGrabber(grabber, 'target') end
  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')
  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    grabber:ungrabMouse()
    g_mouse.popCursor('target')
    grabber.onMouseRelease = nil
    if helperWindow then helperWindow:show() end
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then return true end
    local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then return true end
    local itemId = 0
    if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
      local item = clickedWidget:getItem()
      if item and item.getId then itemId = item:getId() end
    end
    if itemId > 0 then
      button:setImageSource('/images/ui/item')
      if not button:getChildById('staminaItem') then
        local itemWidget = g_ui.createWidget('PotionItem', button)
        if itemWidget then itemWidget:setId('staminaItem') end
      end
      local itemWidget = button:getChildById('staminaItem')
      if itemWidget then itemWidget:setItemId(itemId) end
      local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
      if helperConfig then
        helperConfig.staminaRefillItemId = itemId
        if _Helper.saveSettings then _Helper.saveSettings() end
      end
    end
    return true
  end
end

function tools.toggleStaminaRefill(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.staminaRefillEnabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.updateStaminaRefillInterval(text)
  if not text then return end
  local minutes = tonumber(text:match("%d+")) or 10
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.staminaRefillIntervalMinutes = minutes
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.checkStaminaRefill()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.staminaRefillEnabled then return end
  local player = getPlayer()
  if not player or not g_game.isOnline() then return end
  local itemId = helperConfig.staminaRefillItemId or 0
  if itemId == 0 then return end
  local ok, count = pcall(function() return player:getInventoryCount(itemId, 0) end)
  if not ok or not count or count == 0 then return end
  if player.getStamina then
    local staminaMinutes = player:getStamina()
    local thresholdMinutes = 41 * 60 + 58
    if staminaMinutes >= thresholdMinutes then return end
  end
  local intervalMinutes = helperConfig.staminaRefillIntervalMinutes or 10
  local intervalMs = math.max(1, intervalMinutes) * 60 * 1000
  local nowMs = g_clock.millis()
  if nowMs < lastStaminaRefillUse + intervalMs then return end
  pcall(function() g_game.useInventoryItem(itemId) end)
  lastStaminaRefillUse = nowMs
end

function tools.loadStaminaRefillToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local check = panel:recursiveGetChildById("staminaRefillEnable")
  if check then check:setChecked(helperConfig.staminaRefillEnabled or false) end
  local btn = panel:recursiveGetChildById("staminaRefillItem")
  if btn and helperConfig.staminaRefillItemId and helperConfig.staminaRefillItemId > 0 then
    btn:setImageSource('/images/ui/item')
    if not btn:getChildById('staminaItem') then
      local itemWidget = g_ui.createWidget('PotionItem', btn)
      if itemWidget then itemWidget:setId('staminaItem') end
    end
    local itemWidget = btn:getChildById('staminaItem')
    if itemWidget then itemWidget:setItemId(helperConfig.staminaRefillItemId) end
  end
  local intervalCb = panel:recursiveGetChildById("staminaRefillInterval")
  if intervalCb then
    local minutes = helperConfig.staminaRefillIntervalMinutes or 10
    intervalCb:setCurrentOption(tostring(minutes) .. " min")
  end
end

-- ============================================================
-- AUTO PARTY
-- ============================================================

local function getCreatureByNameInRange(name, rangeX, rangeY)
  local player = getPlayer()
  if not player then return nil end
  local pos = player:getPosition()
  if not pos then return nil end
  local specs = g_map.getSpectatorsInRange(pos, false, rangeX, rangeY)
  if not specs then return nil end
  local nameLower = name:lower()
  for _, spec in ipairs(specs) do
    if spec and spec:isPlayer() and not spec:isLocalPlayer() and spec:getName():lower() == nameLower then
      return spec
    end
  end
  return nil
end

function tools.toggleAutoParty(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoPartyEnabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.toggleAutoPartyAccept(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoPartyAcceptEnabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
  if checked then
    scheduleEvent(function()
      tools.tryAcceptPendingPartyInvite()
    end, 200)
  end
end

function tools.tryAcceptPendingPartyInvite()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.autoPartyAcceptEnabled then return end
  local leader = (helperConfig.autoPartyAcceptLeader or ""):gsub("^%s+", ""):gsub("%s+$", "")
  if leader == "" then return end
  local player = getPlayer()
  if not player then return end
  local specs = g_map.getSpectators(player:getPosition(), false)
  if not specs then return end
  local nameLower = leader:lower()
  for _, spec in ipairs(specs) do
    if spec and spec ~= player and spec.getShield and spec.getName and spec.isPlayer and spec:isPlayer() then
      if spec:getName():lower() == nameLower and spec:getShield() == 1 then
        if g_game.partyJoin then
          scheduleEvent(function()
            if spec and not spec:isRemoved() then
              g_game.partyJoin(spec:getId())
            end
          end, 100)
        end
        break
      end
    end
  end
end

function tools.checkAutoParty()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.autoPartyEnabled then return end
  if not helperConfig.autoPartySendList or #helperConfig.autoPartySendList == 0 then return end
  local player = getPlayer()
  if not player then return end
  local myName = player:getName():lower()
  for i = 1, 4 do
    local name = (helperConfig.autoPartySendList[i] or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if name ~= "" and name:lower() ~= myName then
      local creature = getCreatureByNameInRange(name, 12, 12)
      if creature and creature:isPlayer() and not creature:isLocalPlayer() then
        local shield = creature:getShield()
        local alreadyInParty = (shield and shield > 0)
        if not alreadyInParty then
          pcall(function() g_game.partyInvite(creature:getId()) end)
          return
        end
      end
    end
  end
end

function tools.openAutoPartySettings()
  if autoPartySettingsWindow and not autoPartySettingsWindow:isDestroyed() then
    autoPartySettingsWindow:show()
    autoPartySettingsWindow:raise()
    autoPartySettingsWindow:focus()
    return
  end
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  autoPartySettingsWindow = g_ui.createWidget("MainWindow", g_ui.getRootWidget())
  autoPartySettingsWindow:setId("autoPartySettingsWindow")
  autoPartySettingsWindow:setText(tr("Auto Party - Send & Accept"))
  autoPartySettingsWindow:setSize({ width = 320, height = 300 })

  local sendLabel = g_ui.createWidget("Label", autoPartySettingsWindow)
  sendLabel:setText(tr("Send invite to (max 4 players):"))
  sendLabel:setFont("verdana-11px-antialised")
  sendLabel:setColor("#dfdfdf")
  sendLabel:addAnchor(AnchorTop, "parent", AnchorTop)
  sendLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
  sendLabel:setMarginTop(8)
  sendLabel:setMarginLeft(8)
  sendLabel:setTextAutoResize(true)

  for i = 1, 4 do
    local ed = g_ui.createWidget("TextEdit", autoPartySettingsWindow)
    ed:setId("autoPartySend" .. i)
    ed:addAnchor(AnchorTop, i == 1 and "parent" or ("autoPartySend" .. (i - 1)), i == 1 and AnchorTop or AnchorBottom)
    ed:addAnchor(AnchorLeft, "parent", AnchorLeft)
    ed:addAnchor(AnchorRight, "parent", AnchorRight)
    ed:setMarginTop(i == 1 and 28 or 4)
    ed:setMarginLeft(8)
    ed:setMarginRight(8)
    ed:setHeight(22)
    ed:setText(helperConfig and (helperConfig.autoPartySendList[i] or "") or "")
  end

  local acceptLabel = g_ui.createWidget("Label", autoPartySettingsWindow)
  acceptLabel:setId("autoPartyAcceptLabel")
  acceptLabel:setText(tr("Accept invite from leader:"))
  acceptLabel:setFont("verdana-11px-antialised")
  acceptLabel:setColor("#dfdfdf")
  acceptLabel:addAnchor(AnchorTop, "autoPartySend4", AnchorBottom)
  acceptLabel:addAnchor(AnchorLeft, "parent", AnchorLeft)
  acceptLabel:setMarginTop(14)
  acceptLabel:setMarginLeft(8)
  acceptLabel:setTextAutoResize(true)

  local acceptEdit = g_ui.createWidget("TextEdit", autoPartySettingsWindow)
  acceptEdit:setId("autoPartyAcceptEdit")
  acceptEdit:addAnchor(AnchorTop, "autoPartyAcceptLabel", AnchorBottom)
  acceptEdit:addAnchor(AnchorLeft, "parent", AnchorLeft)
  acceptEdit:addAnchor(AnchorRight, "parent", AnchorRight)
  acceptEdit:setMarginTop(4)
  acceptEdit:setMarginLeft(8)
  acceptEdit:setMarginRight(8)
  acceptEdit:setHeight(22)
  acceptEdit:setMarginBottom(44)
  acceptEdit:setText(helperConfig and (helperConfig.autoPartyAcceptLeader or "") or "")

  local function saveAndClose()
    for i = 1, 4 do
      local w = autoPartySettingsWindow:getChildById("autoPartySend" .. i)
      if w then helperConfig.autoPartySendList[i] = w:getText() and w:getText():gsub("^%s+", ""):gsub("%s+$", "") or "" end
    end
    local ae = autoPartySettingsWindow:getChildById("autoPartyAcceptEdit")
    if ae then helperConfig.autoPartyAcceptLeader = (ae:getText() or ""):gsub("^%s+", ""):gsub("%s+$", "") end
    if _Helper.saveSettings then _Helper.saveSettings() end
    scheduleEvent(function() tools.tryAcceptPendingPartyInvite() end, 200)
    autoPartySettingsWindow:hide()
  end

  local btnOk = g_ui.createWidget("Button", autoPartySettingsWindow)
  btnOk:setText(tr("OK"))
  btnOk:setSize({ width = 70, height = 24 })
  btnOk:addAnchor(AnchorBottom, "parent", AnchorBottom)
  btnOk:addAnchor(AnchorRight, "parent", AnchorHorizontalCenter)
  btnOk:setMarginBottom(10)
  btnOk:setMarginRight(6)
  btnOk.onClick = saveAndClose

  local btnCancel = g_ui.createWidget("Button", autoPartySettingsWindow)
  btnCancel:setText(tr("Cancel"))
  btnCancel:setSize({ width = 70, height = 24 })
  btnCancel:addAnchor(AnchorBottom, "parent", AnchorBottom)
  btnCancel:addAnchor(AnchorLeft, "parent", AnchorHorizontalCenter)
  btnCancel:setMarginBottom(10)
  btnCancel:setMarginLeft(6)
  btnCancel.onClick = function() autoPartySettingsWindow:hide() end

  autoPartySettingsWindow:show()
end

function tools.loadAutoPartyToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local enableCheck = panel:recursiveGetChildById("autoPartyEnable")
  if enableCheck then enableCheck:setChecked(helperConfig.autoPartyEnabled or false) end
  local acceptCheck = panel:recursiveGetChildById("autoPartyAcceptEnable")
  if acceptCheck then acceptCheck:setChecked(helperConfig.autoPartyAcceptEnabled or false) end
end

-- ============================================================
-- AUTOBOOST STORE
-- ============================================================

local function labelLooksLikeXpBoost(s)
  if not s or s == "" then return false end
  local n = s:lower()
  if n:find("xp boost", 1, true) or n:find("exp boost", 1, true) or n:find("experience boost", 1, true) then return true end
  if n:find("boost", 1, true) and (n:find("xp", 1, true) or n:find("exp", 1, true) or n:find("experience", 1, true)) then return true end
  return false
end

local xpBoostCache = {
  offerId = nil,
  price = nil,
  coinType = nil,
  disabled = nil,
  prefetchStep = nil,
  silentStoreOffersUpdate = false,
  skipNextPurchaseStatusUi = false,
}

local function resetXpBoostAutoCache()
  xpBoostCache.offerId = nil
  xpBoostCache.price = nil
  xpBoostCache.coinType = nil
  xpBoostCache.disabled = nil
  xpBoostCache.prefetchStep = nil
end

local function mergeXpBoostCacheFromOffers(offers)
  if not offers then return end
  for _, product in ipairs(offers) do
    local subs = product.subOffers or { product }
    for si = 1, #subs do
      local sub = subs[si]
      if sub and sub.id then
        local pname = product.name or ""
        local subname = sub.name or sub.title or ""
        if labelLooksLikeXpBoost(pname) or labelLooksLikeXpBoost(subname) then
          local nprice = tonumber(sub.price)
          if nprice == nil or nprice <= 0 then nprice = tonumber(product.price) or 0 end
          xpBoostCache.offerId = sub.id
          xpBoostCache.price = nprice
          xpBoostCache.coinType = sub.coinType or product.coinType
          xpBoostCache.disabled = sub.disabled == true
          return
        end
      end
    end
  end
end

local function prefetchXpBoostOfferCache()
  if not g_game.requestStoreOffers then return false end
  if xpBoostCache.offerId then
    xpBoostCache.silentStoreOffersUpdate = true
    g_game.requestStoreOffers(XP_BOOST_PREFETCH_CATEGORIES[1], "", 0, 1)
    return true
  end
  xpBoostCache.prefetchStep = 1
  xpBoostCache.silentStoreOffersUpdate = true
  g_game.requestStoreOffers(XP_BOOST_PREFETCH_CATEGORIES[1], "", 0, 1)
  return true
end

local function hasEnoughBalanceForXpBoost()
  if not xpBoostCache.offerId or not xpBoostCache.price then return false end
  local player = getPlayer()
  if not player then return false end
  local price = tonumber(xpBoostCache.price) or 0
  local normal = player:getResourceBalance(ResourceTypes.COIN_NORMAL) or 0
  local transfer = player:getResourceBalance(ResourceTypes.COIN_TRANSFERRABLE) or 0
  local total = normal + transfer
  if total > 0 then return total >= price end
  return true
end

local function tryBuyXpBoostAuto()
  if not xpBoostCache.offerId then return false end
  if xpBoostCache.disabled == true then return false end
  if not hasEnoughBalanceForXpBoost() then return false end
  xpBoostCache.skipNextPurchaseStatusUi = true
  pcall(function() g_game.buyStoreOffer(xpBoostCache.offerId, 0) end)
  return true
end

function tools.onStoreCreateProducts(storeProducts)
  if xpBoostCache.silentStoreOffersUpdate then
    xpBoostCache.silentStoreOffersUpdate = false
    if storeProducts and storeProducts.offers then
      mergeXpBoostCacheFromOffers(storeProducts.offers)
    end
    return true
  end
  return false
end

function tools.onStorePurchaseStatus()
  if xpBoostCache.skipNextPurchaseStatusUi then
    xpBoostCache.skipNextPurchaseStatusUi = false
    return true
  end
  return false
end

function tools.toggleAutoBoostStore(checked)
  if autoBoostStoreSuppressCheckChange then return end
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not checked then
    if helperConfig then helperConfig.autoBoostStoreEnabled = false end
    return
  end
  local panel = getToolsPanel()
  autoBoostStoreSuppressCheckChange = true
  if panel then
    local w = panel:recursiveGetChildById('autoBoostStore')
    if w then w:setChecked(false) end
  end
  autoBoostStoreSuppressCheckChange = false
  local confirmWindow = nil
  local cancel = function()
    if confirmWindow then confirmWindow:destroy() end
  end
  local confirm = function()
    if confirmWindow then confirmWindow:destroy() end
    if helperConfig then helperConfig.autoBoostStoreEnabled = true end
    lastAutoBoostStoreAttemptMs = 0
    lastBoostsCategoryRequestMs = 0
    resetXpBoostAutoCache()
    prefetchXpBoostOfferCache()
    autoBoostStoreSuppressCheckChange = true
    if panel then
      local w2 = panel:recursiveGetChildById('autoBoostStore')
      if w2 then w2:setChecked(true) end
    end
    autoBoostStoreSuppressCheckChange = false
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
  confirmWindow = displayGeneralBox(
    tr('AutoBoost Store'),
    tr('This will automatically buy XP Boost from the Store using Tibia Coins when your boost expires. Activate?'),
    { { text = tr('No'), callback = cancel }, { text = tr('Yes'), callback = confirm } },
    confirm,
    cancel
  )
end

function tools.checkAutoBoostStore()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.autoBoostStoreEnabled then return end
  local player = getPlayer()
  if not player then return end
  if player.getStoreExpBoostTime and player:getStoreExpBoostTime() > 0 then return end
  local now = g_clock.millis()
  local prefetchCooldown = (xpBoostCache.disabled == true) and 2000 or 8000
  if now - lastBoostsCategoryRequestMs > prefetchCooldown then
    lastBoostsCategoryRequestMs = now
    prefetchXpBoostOfferCache()
  end
  if not xpBoostCache.offerId then return end
  if xpBoostCache.disabled == true then return end
  if not hasEnoughBalanceForXpBoost() then return end
  if lastAutoBoostStoreAttemptMs > 0 and (now - lastAutoBoostStoreAttemptMs) < 45000 then return end
  local bought = tryBuyXpBoostAuto()
  if bought then lastAutoBoostStoreAttemptMs = now end
end

function tools.loadAutoBoostStoreToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local check = panel:recursiveGetChildById("autoBoostStore")
  if check then check:setChecked(helperConfig.autoBoostStoreEnabled or false) end
  if helperConfig.autoBoostStoreEnabled then
    resetXpBoostAutoCache()
    scheduleEvent(function()
      if helperConfig.autoBoostStoreEnabled then prefetchXpBoostOfferCache() end
    end, 400)
  end
end

-- ============================================================
-- IMBUEMENT SCROLL
-- ============================================================

local IMBUEMENT_SCROLL = {
  SLOT_MAP = { helmet = 1, armor = 4, weapon = 6, shield = 5, ammo = 10, backpack = 3, boots = 8 },
  ORDER = { 'helmet', 'armor', 'weapon', 'shield', 'ammo', 'backpack', 'boots' },
  STEP_MS = 400,
  PRESET_COUNT = 6,
  TRACKER_INV = { [1] = true, [3] = true, [4] = true, [5] = true, [6] = true, [8] = true, [10] = true },
}

local function squashImbuementLabel(text)
  local t = tostring(text or ''):lower()
  t = t:gsub('%b()', '')
  t = t:gsub('^[^:]+:%s*', '')
  t = t:gsub('powerful%s*', ''):gsub('intricate%s*', ''):gsub('basic%s*', ''):gsub('wondrous%s*', '')
  t = t:gsub('%s*scroll%s*$', ''):gsub('^%s+', ''):gsub('%s+$', '')
  return t
end

local function imbuementScrollLabelKey(scrollId)
  if not g_things or not scrollId then return nil end
  local tt = g_things.getThingType(scrollId, ThingCategoryItem)
  if not tt or not tt.getName then return nil end
  local ok, name = pcall(function() return tt:getName() end)
  if not ok or not name or name == '' then return nil end
  return squashImbuementLabel(name)
end

local function getImbuementTrackerItems()
  local m = modules.game_imbuementtracker
  if m and m.getLastImbuementTrackerItems then
    return m.getLastImbuementTrackerItems()
  end
  return nil
end

local function buildImbuementScrollQueue()
  local queue = {}
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local player = getPlayer()
  if not player or not helperConfig or not helperConfig.imbuementScrollEnabled then return queue end
  local items = getImbuementTrackerItems()
  if not items or type(items) ~= 'table' then return queue end
  local trackerByInvSlot = {}
  for _, it in ipairs(items) do
    local inv = it and it.slot
    if type(inv) == 'number' and IMBUEMENT_SCROLL.TRACKER_INV[inv] then
      trackerByInvSlot[inv] = it
    end
  end
  local ids = helperConfig.imbuementScrollIds or {}
  for i = 1, IMBUEMENT_SCROLL.PRESET_COUNT do
    local scrollId = ids[i]
    if type(scrollId) == 'number' and scrollId > 0 and table.contains(imbuementScrollAllowedIds, scrollId) then
      local ok, count = pcall(function() return player:getInventoryCount(scrollId, 0) end)
      if ok and count and count > 0 then
        local slotCfg = (helperConfig.imbuementScrollSlots or {})[i]
        if type(slotCfg) == 'table' then
          for _, slotName in ipairs(IMBUEMENT_SCROLL.ORDER) do
            if slotCfg[slotName] then
              local invSlot = IMBUEMENT_SCROLL.SLOT_MAP[slotName]
              local tr = invSlot and trackerByInvSlot[invSlot]
              if tr then
                local totalSlots = tonumber(tr.totalSlots) or 0
                local hasEmpty = false
                local hasMatch = false
                local sk = imbuementScrollLabelKey(scrollId)
                for idx = 1, totalSlots do
                  local s = tr.slots and tr.slots[idx]
                  if not s or type(s) ~= 'table' or (tonumber(s.duration) or 0) <= 0 then
                    hasEmpty = true
                  elseif sk and sk ~= '' then
                    local nk = squashImbuementLabel(s.name)
                    if nk ~= '' and (nk:find(sk, 1, true) or sk:find(nk, 1, true)) then
                      hasMatch = true
                    end
                  end
                end
                if hasEmpty and not hasMatch then
                  local bkey = scrollId .. ":" .. invSlot
                  local untilMs = imbuementScrollBackoff[bkey]
                  if type(untilMs) ~= "number" or g_clock.millis() >= untilMs then
                    queue[#queue + 1] = { scrollId = scrollId, slotId = invSlot }
                  end
                end
              end
            end
          end
        end
      end
    end
  end
  return queue
end

local function imbuementScrollStep()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not g_game.isOnline() or not helperConfig or not helperConfig.imbuementScrollEnabled then
    imbuementScrollBatchRunning = false
    imbuementScrollQueue = nil
    return
  end
  local player = getPlayer()
  if not player then
    imbuementScrollBatchRunning = false
    imbuementScrollQueue = nil
    return
  end
  local queue = buildImbuementScrollQueue()
  if #queue == 0 then
    imbuementScrollBatchRunning = false
    imbuementScrollQueue = nil
    return
  end
  imbuementScrollQueue = queue
  local a = queue[1]
  if type(a.scrollId) == 'number' and a.scrollId > 0 then
    local ok, count = pcall(function() return player:getInventoryCount(a.scrollId, 0) end)
    if ok and count and count > 0 then
      local slotItem = player:getInventoryItem(a.slotId)
      if slotItem and slotItem.getId and slotItem:getId() and slotItem:getId() > 0 then
        imbuementScrollLastAttempt = { scrollId = a.scrollId, slotId = a.slotId, t = g_clock.millis() }
        pcall(function() g_game.useInventoryItemWith(a.scrollId, slotItem) end)
      end
    end
  end
  scheduleEvent(imbuementScrollStep, IMBUEMENT_SCROLL.STEP_MS)
end

function tools.toggleImbuementScroll(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.imbuementScrollEnabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.checkImbuementScroll()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.imbuementScrollEnabled then return end
  if imbuementScrollBatchRunning then return end
  if not getImbuementTrackerItems() then return end
  local queue = buildImbuementScrollQueue()
  if #queue == 0 then return end
  imbuementScrollBatchRunning = true
  imbuementScrollQueue = queue
  scheduleEvent(imbuementScrollStep, 0)
end

function tools.onImbuementScrollTextMessage(messageMode, message)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.imbuementScrollEnabled then return end
  local text = tostring(message or ""):lower()
  if text:find("successfully imbued the object", 1, true) then
    imbuementScrollLastAttempt = nil
    return
  end
  local last = imbuementScrollLastAttempt
  if type(last) ~= "table" or not last.t or not last.scrollId or not last.slotId then return end
  if g_clock.millis() - last.t > 6000 then return end
  local snippets = {
    "not imbuable", "pick up the item", "invalid slot", "don't have a valid imbuement",
    "cannot apply the same imbuement", "don't have an imbuement scroll", "don't have a valid tier",
    "failed to consume imbuement scroll", "item is not imbuable",
  }
  for i = 1, #snippets do
    if text:find(snippets[i], 1, true) then
      imbuementScrollBackoff[last.scrollId .. ":" .. last.slotId] = g_clock.millis() + 120000
      imbuementScrollLastAttempt = nil
      return
    end
  end
end

function tools.openImbuementScrollSettings()
  if not imbuementScrollSettingsWindow or imbuementScrollSettingsWindow:isDestroyed() then
    imbuementScrollSettingsWindow = g_ui.createWidget('ImbuementScrollSettingsWindow', g_ui.getRootWidget())
  end
  if not imbuementScrollSettingsWindow then return end
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  local ids = helperConfig.imbuementScrollIds or { 0, 0, 0, 0, 0, 0 }
  for i = 0, IMBUEMENT_SCROLL.PRESET_COUNT - 1 do
    local btn = imbuementScrollSettingsWindow:recursiveGetChildById('imbuementScrollGearButton' .. i)
    if btn then
      local itemId = ids[i + 1] and ids[i + 1] > 0 and ids[i + 1] or 0
      if itemId > 0 then
        btn:setImageSource('/images/ui/item')
        local existing = btn:getChildById('scrollItem')
        if existing then existing:destroy() end
        local itemWidget = g_ui.createWidget('PotionItem', btn)
        if itemWidget then
          itemWidget:setId('scrollItem')
          itemWidget:setItemId(itemId)
        end
      else
        btn:setImageSource('/images/game/actionbar/actionbarslot')
        local existing = btn:getChildById('scrollItem')
        if existing then existing:destroy() end
      end
    end
  end
  local slotsArray = helperConfig.imbuementScrollSlots or {}
  local slotNames = { 'Helmet', 'Armor', 'Weapon', 'Shield', 'Ammo', 'Backpack', 'Boots' }
  for scrollIdx = 0, IMBUEMENT_SCROLL.PRESET_COUNT - 1 do
    local slotCfg = (type(slotsArray[scrollIdx + 1]) == 'table') and slotsArray[scrollIdx + 1] or {}
    for _, name in ipairs(slotNames) do
      local key = name:lower()
      local w = imbuementScrollSettingsWindow:recursiveGetChildById('imbuementScroll' .. scrollIdx .. key)
      if w then w:setChecked(slotCfg[key] == true) end
    end
  end
  imbuementScrollSettingsWindow:show(true)
  imbuementScrollSettingsWindow:raise()
  imbuementScrollSettingsWindow:focus()
end

function tools.assignImbuementScrollItem(slotIndex)
  if not imbuementScrollSettingsWindow then return end
  local button = imbuementScrollSettingsWindow:recursiveGetChildById('imbuementScrollGearButton' .. slotIndex)
  if not button then return end
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()
  if g_mouse and g_mouse.updateGrabber then g_mouse.updateGrabber(grabber, 'target') end
  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')
  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    grabber:ungrabMouse()
    g_mouse.popCursor('target')
    grabber.onMouseRelease = nil
    if helperWindow then helperWindow:show() end
    local rootWidget = g_ui.getRootWidget()
    if not rootWidget then return true end
    local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
    if not clickedWidget then return true end
    local itemId = 0
    if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
      local item = clickedWidget:getItem()
      if item and item.getId then itemId = item:getId() end
    end
    if itemId > 0 then
      local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
      if helperConfig then
        helperConfig.imbuementScrollIds = helperConfig.imbuementScrollIds or { 0, 0, 0, 0, 0, 0 }
        helperConfig.imbuementScrollIds[slotIndex + 1] = itemId
        if _Helper.saveSettings then _Helper.saveSettings() end
      end
      button:setImageSource('/images/ui/item')
      local existing = button:getChildById('scrollItem')
      if existing then existing:destroy() end
      local itemWidget = g_ui.createWidget('PotionItem', button)
      if itemWidget then itemWidget:setId('scrollItem'); itemWidget:setItemId(itemId) end
    end
    return true
  end
end

function tools.imbuementScrollSettingsOnSave()
  if not imbuementScrollSettingsWindow then return end
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  local slotNames = { 'Helmet', 'Armor', 'Weapon', 'Shield', 'Ammo', 'Backpack', 'Boots' }
  helperConfig.imbuementScrollSlots = {}
  for scrollIdx = 0, IMBUEMENT_SCROLL.PRESET_COUNT - 1 do
    helperConfig.imbuementScrollSlots[scrollIdx + 1] = { helmet = false, armor = false, weapon = false, shield = false, ammo = false, backpack = false, boots = false }
    for _, name in ipairs(slotNames) do
      local key = name:lower()
      local w = imbuementScrollSettingsWindow:recursiveGetChildById('imbuementScroll' .. scrollIdx .. key)
      if w then helperConfig.imbuementScrollSlots[scrollIdx + 1][key] = w:isChecked() end
    end
  end
  if _Helper.saveSettings then _Helper.saveSettings() end
  imbuementScrollSettingsWindow:hide()
end

function tools.removeImbuementScrollItem(slotIndex)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  helperConfig.imbuementScrollIds = helperConfig.imbuementScrollIds or { 0, 0, 0, 0, 0, 0 }
  helperConfig.imbuementScrollIds[slotIndex + 1] = 0
  if _Helper.saveSettings then _Helper.saveSettings() end
  if imbuementScrollSettingsWindow then
    local button = imbuementScrollSettingsWindow:recursiveGetChildById('imbuementScrollGearButton' .. slotIndex)
    if button then
      button:setImageSource('/images/game/actionbar/actionbarslot')
      local existing = button:getChildById('scrollItem')
      if existing then existing:destroy() end
    end
  end
end

function tools.loadImbuementScrollToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local check = panel:recursiveGetChildById("imbuementScrollCheck")
  if check then check:setChecked(helperConfig.imbuementScrollEnabled or false) end
end

-- ============================================================
-- UI LOADING & RESET
-- ============================================================

-- Load gold change checkbox state
function tools.loadChangeGoldToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end

  local changeGold = panel:recursiveGetChildById("changeGold")
  if changeGold then
    changeGold:setChecked(helperConfig.autoChangeGold or false)
  end
end

-- Load exercise training UI state
function tools.loadExerciseTrainingToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end

  local config = helperConfig.exerciseTraining or {}

  -- Load enabled state checkbox
  local checkBox = panel:recursiveGetChildById("autoTrainingCheck")
  if checkBox then
    checkBox:setChecked(config.enabled or false)
  end

  -- Also delegate to the class for any additional UI loading
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.loadToUI then
    _Helper.ExerciseTraining.loadToUI()
  end
end

-- Load quiver refill UI state
function tools.loadQuiverRefillToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getPaladinPanel()
  if not helperConfig or not panel then return end

  -- Reset quiver refill state variables on load (important for relog)
  isRefillingQuiver = false
  lastQuiverRefillTime = 0

  local config = helperConfig.quiverRefill or {}

  -- Load item
  if config.itemId and config.itemId > 0 then
    local button = panel:recursiveGetChildById("quiverAmmoItem")
    if button then
      button:setImageSource('/images/ui/item')
      if not button:getChildById('ammoItem') then
        local itemWidget = g_ui.createWidget('PotionItem', button)
        if itemWidget then
          itemWidget:setId('ammoItem')
        end
      end
      local itemWidget = button:getChildById('ammoItem')
      if itemWidget then
        itemWidget:setItemId(config.itemId)
      end
    end
  end

  -- Load values
  local minEdit = panel:recursiveGetChildById("quiverMinValue")
  if minEdit then
    minEdit:setText(tostring(config.minValue or 50))
  end

  local refillEdit = panel:recursiveGetChildById("quiverRefillValue")
  if refillEdit then
    refillEdit:setText(tostring(config.refillValue or 100))
  end

  -- Load enabled state
  local enableCheck = panel:recursiveGetChildById("enableQuiverRefill")
  if enableCheck then
    enableCheck:setChecked(config.enabled or false)
  end

  -- Setup numeric input validation
  tools.setupQuiverMinInput()
  tools.setupQuiverRefillInput()
end

-- Load magic shield UI state
function tools.loadMagicShieldToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getMagePanel()
  if not helperConfig or not panel then return end

  local config = helperConfig.magicShield or {}

  -- Load utamo vita settings
  local utamoCheck = panel:recursiveGetChildById("enableUtamoVita")
  if utamoCheck then
    utamoCheck:setChecked(config.utamoEnabled or false)
  end

  local utamoHp = panel:recursiveGetChildById("utamoHpPercent")
  if utamoHp then
    utamoHp:setText(tostring(config.utamoHpPercent or 80))
  end

  -- Load exana vita settings
  local exanaCheck = panel:recursiveGetChildById("enableExanaVita")
  if exanaCheck then
    exanaCheck:setChecked(config.exanaEnabled or false)
  end

  local exanaHp = panel:recursiveGetChildById("exanaHpPercent")
  if exanaHp then
    exanaHp:setText(tostring(config.exanaHpPercent or 90))
  end

  -- Load potion settings
  local potionCheck = panel:recursiveGetChildById("enableMagicShieldPotion")
  if potionCheck then
    potionCheck:setChecked(config.potionEnabled or false)
  end

  -- Setup numeric input validation
  tools.setupUtamoHpInput()
  tools.setupExanaHpInput()
end

-- Load Auto Follow UI state
function tools.loadAutoFollowToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  
  local autoFollowCheck = panel:recursiveGetChildById("autoFollow")
  if autoFollowCheck then
    autoFollowCheck:setChecked(helperConfig.autoFollow or false)
  end
end

-- Toggle Auto Bless
function tools.toggleAutoBless(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoBless = checked
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end
end

local function stopAntiAfkTimer()
  if antiAfkTimerEvent then
    removeEvent(antiAfkTimerEvent)
    antiAfkTimerEvent = nil
  end
end

local function doAntiAfkTurn()
  local player = getPlayer()
  if not player or not g_game.isOnline() then return end
  local currentDir = player:getDirection()
  local nextDir = (currentDir % 4 + 1) % 4
  if g_game.turn then
    g_game.turn(nextDir)
  end
end

local function scheduleNextAntiAfk()
  stopAntiAfkTimer()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.antiAfk then return end
  antiAfkTimerEvent = scheduleEvent(function()
    antiAfkTimerEvent = nil
    doAntiAfkTurn()
    scheduleNextAntiAfk()
  end, ANTI_AFK_INTERVAL_MS)
end

function tools.toggleAntiAfk(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.antiAfk = checked
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end
  if checked then
    scheduleNextAntiAfk()
  else
    stopAntiAfkTimer()
  end
end

function tools.loadAntiAfkToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local check = panel:recursiveGetChildById("antiAfk")
  if check then
    check:setChecked(helperConfig.antiAfk or false)
  end
  if helperConfig.antiAfk then
    if not antiAfkTimerEvent then
      scheduleNextAntiAfk()
    end
  else
    stopAntiAfkTimer()
  end
end

-- Load Auto Bless UI state
function tools.loadAutoBlessToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  
  local autoBlessCheck = panel:recursiveGetChildById("autoBless")
  if autoBlessCheck then
    autoBlessCheck:setChecked(helperConfig.autoBless or false)
  end
end

local function stopAdvertisingChannelTimer()
  if advertisingChannelTimerEvent then
    removeEvent(advertisingChannelTimerEvent)
    advertisingChannelTimerEvent = nil
  end
end

local function trySendAdvertisingMessage()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.advertisingChannel or not helperConfig.advertisingText or helperConfig.advertisingText:match("^%s*$") then
    return
  end
  local console = modules.game_console
  if not console or not console.getChannelIdByName then return end
  local channelId = console.getChannelIdByName("Advertising")
  if not channelId then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Advertising channel is not open. Open the channel first."))
    end
    return
  end
  if MessageModes and g_game and g_game.talkChannel then
    g_game.talkChannel(MessageModes.Channel, channelId, helperConfig.advertisingText)
  end
end

local function scheduleNextAdvertising()
  stopAdvertisingChannelTimer()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.advertisingChannel then return end
  advertisingChannelTimerEvent = scheduleEvent(function()
    advertisingChannelTimerEvent = nil
    trySendAdvertisingMessage()
    scheduleNextAdvertising()
  end, ADVERTISING_INTERVAL_MS)
end

function tools.toggleAdvertisingChannel(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.advertisingChannel = checked
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end
  if checked then
    -- Send first message after 2 seconds to ensure stability, then schedule next
    scheduleEvent(function()
      if helperConfig.advertisingChannel then
        trySendAdvertisingMessage()
        scheduleNextAdvertising()
      end
    end, 2000)
  else
    stopAdvertisingChannelTimer()
  end
end

function tools.setAdvertisingChannelText(text)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.advertisingText = text and text:gsub("^%s*(.-)%s*$", "%1") or ""
    if _Helper.saveSettings then
      _Helper.saveSettings()
    end
  end
end

function tools.loadAdvertisingChannelToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local check = panel:recursiveGetChildById("advertisingChannel")
  if check then
    check:setChecked(helperConfig.advertisingChannel or false)
  end
  local textEdit = panel:recursiveGetChildById("advertisingChannelText")
  if textEdit then
    textEdit:setText(helperConfig.advertisingText or "")
  end
  if helperConfig.advertisingChannel then
    -- If already enabled, just make sure timer is running
    -- Note: trySendAdvertisingMessage is NOT called here to avoid spamming on login/relog
    -- unless it's the very first time being enabled in the session.
    if not advertisingChannelTimerEvent then
      scheduleNextAdvertising()
    end
  else
    stopAdvertisingChannelTimer()
  end
end

-- ============================================================
-- ITEM TIMER
-- ============================================================

function tools.assignItemTimerItem(button, slotIndex)
  slotIndex = slotIndex or 0
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()
  if g_mouse and g_mouse.updateGrabber then
    g_mouse.updateGrabber(grabber, 'target')
  end
  grabber:grabMouse()
  if helperWindow then helperWindow:hide() end
  g_mouse.pushCursor('target')
  grabber.onMouseRelease = function(self, mousePosition, mouseButton)
    tools.onAssignItemTimerItem(self, mousePosition, mouseButton, button, slotIndex)
  end
end

function tools.onAssignItemTimerItem(self, mousePosition, mouseButton, button, slotIndex)
  slotIndex = slotIndex or 0
  local grabber = getMouseGrabber()
  local helperWindow = getHelperWindow()
  if g_mouse and g_mouse.updateGrabber then
    g_mouse.updateGrabber(grabber, 'target')
  end
  grabber:ungrabMouse()
  g_mouse.popCursor('target')
  grabber.onMouseRelease = nil
  if helperWindow then helperWindow:show() end
  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then return true end
  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then return true end
  local itemId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item and item.getId then
      itemId = item:getId()
    end
  end
  if itemId > 0 then
    button:setImageSource('/images/ui/item')
    if not button:getChildById('timerItem') then
      local itemWidget = g_ui.createWidget('PotionItem', button)
      if itemWidget then itemWidget:setId('timerItem') end
    end
    local itemWidget = button:getChildById('timerItem')
    if itemWidget then itemWidget:setItemId(itemId) end
    local panel = getToolsPanel()
    if panel then
      local countdown = panel:recursiveGetChildById("itemTimerCountdown" .. slotIndex)
      if countdown and button.raiseChild then button:raiseChild(countdown) end
    end
    local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
    if helperConfig then
      helperConfig.itemTimer = helperConfig.itemTimer or {}
      if not helperConfig.itemTimer[slotIndex + 1] then
        helperConfig.itemTimer[slotIndex + 1] = { itemId = 0, intervalSeconds = 60, enabled = false }
      end
      helperConfig.itemTimer[slotIndex + 1].itemId = itemId
      if _Helper.saveSettings then _Helper.saveSettings() end
    end
  else
    modules.game_textmessage.displayFailureMessage(tr('Select a valid item.'))
  end
  return true
end

function tools.toggleItemTimer(slotIndex, checked)
  slotIndex = slotIndex or 0
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.itemTimer = helperConfig.itemTimer or {}
    if not helperConfig.itemTimer[slotIndex + 1] then
      helperConfig.itemTimer[slotIndex + 1] = { itemId = 0, intervalSeconds = 60, enabled = false }
    end
    helperConfig.itemTimer[slotIndex + 1].enabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

local function updateItemTimerCountdowns()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not helperConfig.itemTimer or not panel then return end
  local now = g_clock.millis()
  for i = 1, 2 do
    local cfg = helperConfig.itemTimer[i]
    local label = panel:recursiveGetChildById("itemTimerCountdown" .. (i - 1))
    if not label then goto continue end
    if not cfg or not cfg.enabled or not cfg.itemId or cfg.itemId <= 0 then
      label:setText("")
      label:setVisible(false)
    else
      local intervalSec = tonumber(cfg.intervalSeconds) or 60
      if intervalSec <= 0 then
        label:setText("")
        label:setVisible(false)
      else
        local lastUse = lastItemTimerUse[i] or 0
        local elapsedSec = (now - lastUse) / 1000
        local remaining = math.ceil(intervalSec - elapsedSec)
        if remaining <= 0 then
          label:setText("")
          label:setVisible(false)
        else
          label:setText(remaining > 60 and (math.floor(remaining / 60) .. ":" .. string.format("%02d", remaining % 60)) or tostring(remaining))
          label:setVisible(true)
          local btn = panel:recursiveGetChildById("itemTimerButton" .. (i - 1))
          if btn and btn.raiseChild then btn:raiseChild(label) end
        end
      end
    end
    ::continue::
  end
end

function tools.checkItemTimer()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.itemTimer then return end
  local now = g_clock.millis()
  local player = getPlayer()
  for i = 1, 2 do
    local cfg = helperConfig.itemTimer[i]
    if cfg and cfg.enabled then
      local itemId = tonumber(cfg.itemId) or 0
      if itemId > 0 then
        local count = 0
        if player and player.getInventoryCount then
          local ok, n = pcall(function() return player:getInventoryCount(itemId, 0) end)
          if ok and type(n) == "number" then count = n end
        end
        if count == 0 then
          if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
            modules.game_textmessage.displayFailureMessage(tr("Item timer: item not found, disabling."))
          end
          cfg.enabled = false
          local panel = getToolsPanel()
          if panel then
            local enableCheck = panel:recursiveGetChildById("enableItemTimer" .. (i - 1))
            if enableCheck then enableCheck:setChecked(false) end
          end
          if _Helper and _Helper.saveSettings then _Helper.saveSettings() end
        else
          local intervalSec = tonumber(cfg.intervalSeconds) or 60
          if intervalSec > 0 then
            local lastUse = lastItemTimerUse[i] or 0
            if now - lastUse >= intervalSec * 1000 then
              if g_game and g_game.useInventoryItem then
                pcall(function() g_game.useInventoryItem(itemId) end)
                lastItemTimerUse[i] = now
              end
            end
          end
        end
      end
    end
  end
  updateItemTimerCountdowns()
end

function tools.setItemTimerInterval(slotIndex, text)
  slotIndex = slotIndex or 0
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  local n = tonumber(text and text:match("%d+") or "60")
  if n and n > 0 then
    helperConfig.itemTimer = helperConfig.itemTimer or {}
    if not helperConfig.itemTimer[slotIndex + 1] then
      helperConfig.itemTimer[slotIndex + 1] = { itemId = 0, intervalSeconds = 60, enabled = false }
    end
    helperConfig.itemTimer[slotIndex + 1].intervalSeconds = math.min(3600, n)
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

local function loadItemTimerSlot(panel, slotIndex, cfg)
  local btn = panel:recursiveGetChildById("itemTimerButton" .. slotIndex)
  if btn then
    if cfg and cfg.itemId and cfg.itemId > 0 then
      btn:setImageSource('/images/ui/item')
      if not btn:getChildById('timerItem') then
        local itemWidget = g_ui.createWidget('PotionItem', btn)
        if itemWidget then itemWidget:setId('timerItem') end
      end
      local itemWidget = btn:getChildById('timerItem')
      if itemWidget then itemWidget:setItemId(cfg.itemId) end
      local countdown = panel:recursiveGetChildById("itemTimerCountdown" .. slotIndex)
      if countdown and btn.raiseChild then btn:raiseChild(countdown) end
    else
      btn:setImageSource("/images/game/actionbar/actionbarslot")
      local timerItem = btn:getChildById("timerItem")
      if timerItem then timerItem:destroy() end
    end
  end
  local intervalEdit = panel:recursiveGetChildById("itemTimerInterval" .. slotIndex)
  if intervalEdit then intervalEdit:setText(tostring(cfg and cfg.intervalSeconds or 60)) end
  local enableCheck = panel:recursiveGetChildById("enableItemTimer" .. slotIndex)
  if enableCheck then enableCheck:setChecked(cfg and cfg.enabled or false) end
end

function tools.loadItemTimerToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  helperConfig.itemTimer = helperConfig.itemTimer or {}
  for i = 0, 1 do
    local cfg = helperConfig.itemTimer[i + 1] or { itemId = 0, intervalSeconds = 60, enabled = false }
    loadItemTimerSlot(panel, i, cfg)
  end
end

-- ============================================================
-- EXETA RES (cast when >= X creatures around, respects spell cooldown)
-- ============================================================
local lastExetaResCast = 0
local EXETA_RES_MIN_DELAY_MS = 10000

function tools.toggleExetaRes(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    if not helperConfig.exetaRes or not helperConfig.exetaRes[1] then
      helperConfig.exetaRes = { { id = 0, minCreatures = 1, creatureName = "", enabled = false } }
    end
    helperConfig.exetaRes[1].enabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

local function countCreaturesAround()
  local player = getPlayer()
  if not player or not g_map then return 0 end
  local pos = player:getPosition()
  if not pos then return 0 end
  local spectators = (g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(pos, false, 1, 1)) or g_map.getSpectators(pos, false) or {}
  local count = 0
  for _, creature in ipairs(spectators) do
    if creature and creature ~= player and creature.getType then
      local ctype = creature:getType()
      if ctype == (CreatureTypeMonster or 1) then
        count = count + 1
      end
    end
  end
  return count
end

function tools.checkExetaRes()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.exetaRes or not helperConfig.exetaRes[1] then return end
  local cfg = helperConfig.exetaRes[1]
  if not cfg.enabled or not cfg.id or cfg.id == 0 then return end
  local minCreatures = math.max(1, tonumber(cfg.minCreatures) or 1)
  local count = countCreaturesAround()
  if count < minCreatures then return end
  local now = g_clock.millis()
  if now - lastExetaResCast < EXETA_RES_MIN_DELAY_MS then return end
  local getSpellCooldown = _Helper.getSpellCooldown and _Helper.getSpellCooldown
  if getSpellCooldown and getSpellCooldown(cfg.id) > now then return end
  local getSpellDataById = _Helper.getSpellDataById and _Helper.getSpellDataById
  if not getSpellDataById then return end
  local spell = getSpellDataById(cfg.id)
  if not spell or not spell.words then return end
  local safeDoThing = _Helper.safeDoThing and _Helper.safeDoThing
  if safeDoThing then safeDoThing(false) end
  pcall(function() g_game.talk(spell.words, true) end)
  if safeDoThing then safeDoThing(true) end
  lastExetaResCast = now
end

function tools.setExetaResMinCreatures(text)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  if not helperConfig.exetaRes or not helperConfig.exetaRes[1] then return end
  local n = tonumber(text and text:match("%d+") or "1")
  if n and n >= 0 then
    helperConfig.exetaRes[1].minCreatures = math.min(99, math.max(0, n))
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.loadExetaResToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local cfg = (helperConfig.exetaRes and helperConfig.exetaRes[1]) or {}
  local minC = cfg.minCreatures
  if minC == nil and cfg.intervalSeconds then minC = 1 end
  local minCreaturesEdit = panel:recursiveGetChildById("exetaResMinCreatures")
  if minCreaturesEdit then minCreaturesEdit:setText(tostring(minC or 1)) end
  local enableCheck = panel:recursiveGetChildById("enableExetaRes")
  if enableCheck then enableCheck:setChecked(cfg.enabled or false) end
  local btn = panel:recursiveGetChildById("exetaResButton0")
  if btn and cfg.id and cfg.id > 0 and _Helper.getSpellDataById and _Helper.getSpellIconSource and _Helper.getSpellIconClip then
    local spell = _Helper.getSpellDataById(cfg.id)
    if spell and spell.words then
      btn:setImageSource(_Helper.getSpellIconSource())
      btn:setImageClip(_Helper.getSpellIconClip(cfg.id))
      btn:setBorderWidth(1)
      btn:setTooltip("Words: " .. (spell.words or ""))
    end
  end
end

-- ============================================================
-- AUTO AMP RES (8 sqm, 10s cooldown; Knight=Chivalrous Challenge 237, Paladin=Divine Dazzle 238)
-- ============================================================
local lastAmpResCast = 0
local AMP_RES_COOLDOWN_MS = 10000
local AMP_RES_RANGE = 8

local function countCreaturesAroundAmpRes()
  local player = getPlayer()
  if not player or not g_map then return 0 end
  local pos = player:getPosition()
  if not pos then return 0 end
  local spectators = (g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(pos, false, AMP_RES_RANGE, AMP_RES_RANGE)) or g_map.getSpectators(pos, false) or {}
  local count = 0
  for _, creature in ipairs(spectators) do
    if creature and creature ~= player and creature.getType then
      local ctype = creature:getType()
      if ctype == (CreatureTypeMonster or 1) then
        count = count + 1
      end
    end
  end
  return count
end

function tools.toggleAmpRes(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    if not helperConfig.ampRes or not helperConfig.ampRes[1] then
      helperConfig.ampRes = { { id = 0, minCreatures = 1, enabled = false } }
    end
    helperConfig.ampRes[1].enabled = checked
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.checkAmpRes()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.ampRes or not helperConfig.ampRes[1] then return end
  local cfg = helperConfig.ampRes[1]
  if not cfg.enabled or not cfg.id or cfg.id == 0 then return end
  local player = getPlayer()
  if not player then return end
  local vocationId = (player.getVocation and player:getVocation()) or 0
  local allowedId = HelperSpellData and HelperSpellData.getAmpResSpellForVocation and HelperSpellData.getAmpResSpellForVocation(vocationId)
  if not allowedId or cfg.id ~= allowedId then return end
  local minCreatures = math.max(1, tonumber(cfg.minCreatures) or 1)
  local count = countCreaturesAroundAmpRes()
  if count < minCreatures then return end
  local now = g_clock.millis()
  if now - lastAmpResCast < AMP_RES_COOLDOWN_MS then return end
  local getSpellCooldown = _Helper.getSpellCooldown and _Helper.getSpellCooldown
  if getSpellCooldown and getSpellCooldown(cfg.id) > now then return end
  local getSpellDataById = _Helper.getSpellDataById and _Helper.getSpellDataById
  if not getSpellDataById then return end
  local spell = getSpellDataById(cfg.id)
  if not spell or not spell.words then return end
  local safeDoThing = _Helper.safeDoThing and _Helper.safeDoThing
  if safeDoThing then safeDoThing(false) end
  pcall(function() g_game.talk(spell.words, true) end)
  if safeDoThing then safeDoThing(true) end
  lastAmpResCast = now
end

function tools.setAmpResMinCreatures(text)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  if not helperConfig.ampRes or not helperConfig.ampRes[1] then return end
  local n = tonumber(text and text:match("%d+") or "1")
  if n and n >= 0 then
    helperConfig.ampRes[1].minCreatures = math.min(99, math.max(0, n))
    if _Helper.saveSettings then _Helper.saveSettings() end
  end
end

function tools.loadAmpResToUI()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local panel = getToolsPanel()
  if not helperConfig or not panel then return end
  local cfg = (helperConfig.ampRes and helperConfig.ampRes[1]) or {}
  local minCreaturesEdit = panel:recursiveGetChildById("ampResMinCreatures")
  if minCreaturesEdit then minCreaturesEdit:setText(tostring(cfg.minCreatures or 1)) end
  local enableCheck = panel:recursiveGetChildById("enableAmpRes")
  if enableCheck then enableCheck:setChecked(cfg.enabled or false) end
  local btn = panel:recursiveGetChildById("ampResButton0")
  if btn and cfg.id and cfg.id > 0 and _Helper.getSpellDataById and _Helper.getSpellIconSource and _Helper.getSpellIconClip then
    local spell = _Helper.getSpellDataById(cfg.id)
    if spell and spell.words then
      btn:setImageSource(_Helper.getSpellIconSource())
      btn:setImageClip(_Helper.getSpellIconClip(cfg.id))
      btn:setBorderWidth(1)
      btn:setTooltip("Words: " .. (spell.words or ""))
    end
  end
end

-- Called on login to send !bless if enabled
function tools.onLogin()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig and helperConfig.autoBless then
    -- No delay here, hook in helper.lua already provides delay
    if g_game.isOnline() then
      g_game.talk("!bless")
    end
  end
end

-- Reset all tools UI elements
function tools.resetUI()
  local panel = getToolsPanel()
  if not panel then return end

  -- Reset gold change
  local changeGold = panel:recursiveGetChildById("changeGold")
  if changeGold then
    changeGold:setChecked(false)
  end

  -- Reset exercise training
  local autoTrainingCheck = panel:recursiveGetChildById("autoTrainingCheck")
  if autoTrainingCheck then
    autoTrainingCheck:setChecked(false)
  end

  -- Stop exercise training cycle if running
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.toggle then
    _Helper.ExerciseTraining.toggle(false)
  end

  -- Reset paladin panel
  local palPanel = getPaladinPanel()
  if palPanel then
    local enableQuiver = palPanel:recursiveGetChildById("enableQuiverRefill")
    if enableQuiver then
      enableQuiver:setChecked(false)
    end
    local ammoButton = palPanel:recursiveGetChildById("quiverAmmoItem")
    if ammoButton then
      ammoButton:setImageSource('/images/game/actionbar/actionbarslot')
      local ammoItem = ammoButton:getChildById('ammoItem')
      if ammoItem then
        ammoItem:destroy()
      end
    end
  end

  -- Reset mage panel
  local magPanel = getMagePanel()
  if magPanel then
    local utamoCheck = magPanel:recursiveGetChildById("enableUtamoVita")
    if utamoCheck then utamoCheck:setChecked(false) end
    local exanaCheck = magPanel:recursiveGetChildById("enableExanaVita")
    if exanaCheck then exanaCheck:setChecked(false) end
    local potionCheck = magPanel:recursiveGetChildById("enableMagicShieldPotion")
    if potionCheck then potionCheck:setChecked(false) end
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig and helperConfig.itemTimer then
    for i = 1, 2 do
      helperConfig.itemTimer[i] = { itemId = 0, intervalSeconds = 60, enabled = false }
    end
  end
  for i = 0, 1 do
    local enableItemTimer = panel:recursiveGetChildById("enableItemTimer" .. i)
    if enableItemTimer then enableItemTimer:setChecked(false) end
    local itemTimerBtn = panel:recursiveGetChildById("itemTimerButton" .. i)
    if itemTimerBtn then
      itemTimerBtn:setImageSource("/images/game/actionbar/actionbarslot")
      local timerItem = itemTimerBtn:getChildById("timerItem")
      if timerItem then timerItem:destroy() end
    end
  end

  -- Reset Exeta Res
  if helperConfig and helperConfig.exetaRes and helperConfig.exetaRes[1] then
    helperConfig.exetaRes[1].id = 0
    helperConfig.exetaRes[1].enabled = false
  end
  local enableExetaRes = panel:recursiveGetChildById("enableExetaRes")
  if enableExetaRes then enableExetaRes:setChecked(false) end
  local exetaResBtn = panel:recursiveGetChildById("exetaResButton0")
  if exetaResBtn then
    exetaResBtn:setImageSource("/images/game/actionbar/actionbarslot")
    exetaResBtn:setImageClip("0 0 34 34")
    exetaResBtn:setBorderWidth(0)
    exetaResBtn:setTooltip("")
  end

  if helperConfig and helperConfig.ampRes and helperConfig.ampRes[1] then
    helperConfig.ampRes[1].id = 0
    helperConfig.ampRes[1].enabled = false
  end
  local enableAmpRes = panel:recursiveGetChildById("enableAmpRes")
  if enableAmpRes then enableAmpRes:setChecked(false) end
  local ampResBtn = panel:recursiveGetChildById("ampResButton0")
  if ampResBtn then
    ampResBtn:setImageSource("/images/game/actionbar/actionbarslot")
    ampResBtn:setImageClip("0 0 34 34")
    ampResBtn:setBorderWidth(0)
    ampResBtn:setTooltip("")
  end

  -- Reset Auto Follow
  local autoFollowCheck = panel:recursiveGetChildById("autoFollow")
  if autoFollowCheck then
    autoFollowCheck:setChecked(false)
  end
  isAutoFollowEnabled = false
  lastFollowId = 0
  stopAutoFollowLoop()

  -- Reset Auto Bless
  local autoBlessCheck = panel:recursiveGetChildById("autoBless")
  if autoBlessCheck then
    autoBlessCheck:setChecked(false)
  end

  stopAntiAfkTimer()
  local antiAfkCheck = panel:recursiveGetChildById("antiAfk")
  if antiAfkCheck then
    antiAfkCheck:setChecked(false)
  end

  stopAdvertisingChannelTimer()
  local advertisingCheck = panel:recursiveGetChildById("advertisingChannel")
  if advertisingCheck then
    advertisingCheck:setChecked(false)
  end
  local advertisingText = panel:recursiveGetChildById("advertisingChannelText")
  if advertisingText then
    advertisingText:setText("")
  end

  -- Reset refilling state
  isRefillingQuiver = false
  lastQuiverRefillTime = 0

  -- Reset Vender Loot
  lastVendorLootUse = 0
  local pouchSellerCheck = panel:recursiveGetChildById("pouchSeller")
  if pouchSellerCheck then pouchSellerCheck:setChecked(false) end

  -- Reset Stamina Refill
  lastStaminaRefillUse = 0
  local staminaRefillCheck = panel:recursiveGetChildById("staminaRefillEnable")
  if staminaRefillCheck then staminaRefillCheck:setChecked(false) end
  local staminaRefillBtn = panel:recursiveGetChildById("staminaRefillItem")
  if staminaRefillBtn then
    staminaRefillBtn:setImageSource("/images/game/actionbar/actionbarslot")
    local staminaItem = staminaRefillBtn:getChildById("staminaItem")
    if staminaItem then staminaItem:destroy() end
  end

  -- Reset Auto Party
  local autoPartyEnable = panel:recursiveGetChildById("autoPartyEnable")
  if autoPartyEnable then autoPartyEnable:setChecked(false) end
  local autoPartyAccept = panel:recursiveGetChildById("autoPartyAcceptEnable")
  if autoPartyAccept then autoPartyAccept:setChecked(false) end

  -- Reset AutoBoost Store
  lastAutoBoostStoreAttemptMs = 0
  lastBoostsCategoryRequestMs = 0
  resetXpBoostAutoCache()
  local autoBoostStoreCheck = panel:recursiveGetChildById("autoBoostStore")
  if autoBoostStoreCheck then autoBoostStoreCheck:setChecked(false) end

  -- Reset Imbuement Scroll
  imbuementScrollBatchRunning = false
  imbuementScrollQueue = nil
  imbuementScrollLastAttempt = nil
  imbuementScrollBackoff = {}
  local imbuementScrollCheck = panel:recursiveGetChildById("imbuementScrollCheck")
  if imbuementScrollCheck then imbuementScrollCheck:setChecked(false) end
end

-- Load all tools states to UI
function tools.loadToUI()
  local panel = getToolsPanel()
  if not panel then return end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end

  local reconnect = panel:recursiveGetChildById("reconnect")
  if reconnect then reconnect:setChecked(helperConfig.autoReconnect or false) end

  tools.loadChangeGoldToUI()
  tools.loadExerciseTrainingToUI()
  tools.loadQuiverRefillToUI()
  tools.loadMagicShieldToUI()
  tools.loadAutoFollowToUI()
  tools.loadAutoBlessToUI()
  tools.loadAntiAfkToUI()
  tools.loadAdvertisingChannelToUI()
  tools.loadItemTimerToUI()
  tools.loadExetaResToUI()
  tools.loadAmpResToUI()
  tools.loadVendorLootToUI()
  tools.loadStaminaRefillToUI()
  tools.loadAutoPartyToUI()
  tools.loadAutoBoostStoreToUI()
  tools.loadImbuementScrollToUI()
  tools.updateVocationPanels()

  -- AutoFood and AutoHaste are handled by their own modules
  if _Helper.AutoFood and _Helper.AutoFood.loadToUI then
    _Helper.AutoFood.loadToUI()
  end
  if _Helper.AutoHaste and _Helper.AutoHaste.loadToUI then
    _Helper.AutoHaste.loadToUI()
  end
  if _Helper.ManaTraining and _Helper.ManaTraining.loadToUI then
    _Helper.ManaTraining.loadToUI()
  end
  if _Helper.SmartFollow and _Helper.SmartFollow.loadToUI then
    _Helper.SmartFollow.loadToUI()
  end
end

-- ============================================================
-- GETTERS
-- ============================================================

-- Getter for exercise dummies
function tools.getExerciseDummies()
  return exerciseDummies
end

-- Getter for exercise items
function tools.getExercises()
  return exercises
end

-- Getter for toolsPanel
function tools.getPanel()
  return getToolsPanel()
end

-- Getter for paladinPanel
function tools.getPaladinPanel()
  return getPaladinPanel()
end

-- Getter for magePanel
function tools.getMagePanel()
  return getMagePanel()
end

-- ============================================================
-- INITIALIZATION & TERMINATION
-- ============================================================

function tools.init(helperWindow)
  helper = helperWindow
  if helper and helper.contentPanel then
    local container = helper.contentPanel:getChildById('toolsPanelContainer')
    if container then
      toolsPanel = container:recursiveGetChildById('toolsPanel')
      paladinPanel = container:recursiveGetChildById('paladinPanel')
      magePanel = container:recursiveGetChildById('magePanel')
    end
  end
end

function tools.terminate()
  toolsPanel = nil
  paladinPanel = nil
  magePanel = nil
  helper = nil
  isRefillingQuiver = false
  lastQuiverRefillTime = 0
  if pendingGoldChangeEvent then
    removeEvent(pendingGoldChangeEvent)
    pendingGoldChangeEvent = nil
  end
  if goldChangeLoopEvent then
    removeEvent(goldChangeLoopEvent)
    goldChangeLoopEvent = nil
  end
  if autoFollowLoopEvent then
    removeEvent(autoFollowLoopEvent)
    autoFollowLoopEvent = nil
  end
  stopAntiAfkTimer()
  stopAdvertisingChannelTimer()
  if autoPartySettingsWindow and not autoPartySettingsWindow:isDestroyed() then
    autoPartySettingsWindow:destroy()
    autoPartySettingsWindow = nil
  end
  if imbuementScrollSettingsWindow and not imbuementScrollSettingsWindow:isDestroyed() then
    imbuementScrollSettingsWindow:destroy()
    imbuementScrollSettingsWindow = nil
  end
  imbuementScrollBatchRunning = false
  imbuementScrollQueue = nil
  imbuementScrollLastAttempt = nil
  lastVendorLootUse = 0
  lastStaminaRefillUse = 0
  lastAutoBoostStoreAttemptMs = 0
  lastBoostsCategoryRequestMs = 0
  resetXpBoostAutoCache()
  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end
end

return tools
