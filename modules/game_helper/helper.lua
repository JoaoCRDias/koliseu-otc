-- Função de log desabilitada
local function safeLog(level, message)
end

-- Tabela global para organizar submódulos do Helper
-- Não sobrescreve se já existir (shortcut_panel.lua pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

-- Resolve custom rune: if area is a table (custom definition) but empty, replace with SpellAreas.AREA_CIRCLE3X3
function _Helper.resolveCustomRuneArea(runeSpell)
  if runeSpell and runeSpell.area then
    if type(runeSpell.area) == "table" and #runeSpell.area == 0 then
      runeSpell.area = SpellAreas.AREA_CIRCLE3X3
    elseif runeSpell.area == true then
      runeSpell.area = SpellAreas.AREA_CIRCLE3X3
    end
  end
  return runeSpell
end

-- Configura um TextEdit para aceitar apenas números, com limites opcionais.
function _Helper.setupNumericInput(widget, minValue, maxValue)
  if not widget then return end
  local isUpdating = false
  widget.onTextChange = function(w, text)
    if isUpdating then return end
    isUpdating = true
    local numericText = text:gsub("[^%d]", "")
    if maxValue then
      local value = tonumber(numericText) or 0
      if value > maxValue then
        numericText = tostring(maxValue)
      end
    end
    if numericText ~= text then
      w:setText(numericText)
    end
    isUpdating = false
  end
  if minValue then
    widget.onFocusChange = function(w, focused)
      if not focused then
        if isUpdating then return end
        isUpdating = true
        local value = tonumber(w:getText()) or 0
        if value < minValue then
          w:setText(tostring(minValue))
        end
        isUpdating = false
      end
    end
  end
end

local player = nil
local healingPanel = nil
local toolsPanel = nil
local toolsPanelContainer = nil
local equipPanelContainer = nil
local scriptsPanelContainer = nil
local cavebotPanel = nil
local shooterPanel = nil
local healPanel = nil
local mouseGrabberWidget = nil
local helper = nil
local helperRules = nil
local friendListWidget = nil
local granListWidget = nil
local hotkeyHelperStatus = false
local btcHelperWidget = nil
local afkTime = 180
local helperAutomaticFunctionsEnabled = true
local lastActiveMenu = 'healingMenu'
local healingActiveBuffs = {}
local isTransitioningPlayer = false
local smartFollowCreatureHooked = false

-- fallback for LoadedPlayer when not provided by server-side module
if not LoadedPlayer then
  LoadedPlayer = g_game.getLocalPlayer()
end

if not translateVocation then
  function translateVocation(id)
    if g_helperCore and g_helperCore.translateVocation then
      return g_helperCore.translateVocation(id)
    end
    return 0
  end
end

local function containsAnyGroup(groups, targetGroups)
  local g = groups or {}
  local tg = targetGroups or {}
  for _, group in pairs(tg) do
    if type(group) ~= "number" then goto continue end
    for _, gid in pairs(g) do
      if type(gid) == "number" and gid == group then return true end
    end
    ::continue::
  end
  return false
end

-- fallback for SpellIcons
if not SpellIcons then
  SpellIcons = {}
end

-- Helper function to get spell icon clip using spell.id and iconIndex from SpellInfo.Default
-- This is the centralized function that all modules should use for spell icons
-- @param spellId: The spell ID (spell.id from SpellInfo.Default)
-- @param profile: Optional profile name (default: 'Default')
-- @return: Icon clip string in format "x y width height"
_Helper.getSpellIconClip = function(spellId, profile)
  if not spellId then
    return "0 0 32 32"
  end
  if Spells and Spells.getImageClip then
    local success, clip = pcall(function() return Spells.getImageClip(spellId, profile or 'Default') end)
    if success and clip then
      return clip
    end
  end
  -- Fallback: return default clip
  return "0 0 32 32"
end

-- Helper function to get spell icon source
-- @param profile: Optional profile name (default: 'Default')
-- @return: Icon source path
_Helper.getSpellIconSource = function(profile)
  profile = profile or 'Default'
  if SpelllistSettings and SpelllistSettings[profile] and SpelllistSettings[profile].iconFile then
    return SpelllistSettings[profile].iconFile
  end
  return '/images/game/spells/spell-icons-32x32'
end

-- Convenience function to set spell icon on a widget
-- @param widget: The widget to set the icon on (must have setImageSource and setImageClip methods)
-- @param spellId: The spell ID
-- @param profile: Optional profile name (default: 'Default')
_Helper.setSpellIcon = function(widget, spellId, profile)
  if not widget then return end
  local source = _Helper.getSpellIconSource(profile)
  local clip = _Helper.getSpellIconClip(spellId, profile)
  widget:setImageSource(source)
  widget:setImageClip(clip)
end

-- Helper function to safely call g_game.doThing
local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end

-- Helper function to safely get harmony count
local function getHarmonyCountSafe(p)
  if p and type(p.getHarmony) == 'function' then
    local ok, value = pcall(function() return p:getHarmony() end)
    if ok and type(value) == 'number' then
      return value
    end
  end
  return 0
end

local function canUseByServerVoc(spellVocations, serverVocId)
  if not serverVocId then return false end
  if not g_helperCore or not g_helperCore.canUseByServerVoc then return false end
  if type(spellVocations) ~= "table" then return false end
  local clean = {}
  for _, v in ipairs(spellVocations) do
    local n = tonumber(v)
    if n and math.floor(n) == n then
      clean[#clean + 1] = math.floor(n)
    end
  end
  if #clean == 0 then return false end
  return g_helperCore.canUseByServerVoc(clean, serverVocId)
end

-- Helper function to get spell by client ID
local function getSpellByClientId(clientId)
  if Spells and Spells.getSpellByClientId then
    local success, spell = pcall(function() return Spells.getSpellByClientId(clientId) end)
    if success and spell then
      return spell
    end
  end
  -- Fallback: try to find spell in SpellInfo by clientId
  if SpellInfo and SpellInfo.Default then
    for spellName, spellData in pairs(SpellInfo.Default) do
      if spellData.clientId == clientId then
        return spellData
      end
    end
  end
  return nil
end

-- Helper function to get spell data by ID
local function getSpellDataById(spellId)
  if not spellId or spellId == 0 then
    return nil
  end
  -- First try SpellInfo.Default (most reliable)
  if SpellInfo and SpellInfo.Default then
    for spellName, spellData in pairs(SpellInfo.Default) do
      if spellData.id == spellId then
        return spellData
      end
    end
  end
  -- Then try Spells.getSpellDataById if available
  if Spells and Spells.getSpellDataById then
    local success, spell = pcall(function() return Spells.getSpellDataById(spellId) end)
    if success and spell then
      return spell
    end
  end
  return nil
end

local autoTargetOnHold = false
local afkTime = 180
local autoTargetModes = {
  ["A"] = 1,
  ["B"] = 2,
  ["C"] = 3,
  ["D"] = 4,
  ["E"] = 5,
  ["F"] = 6,
  ["G"] = 7,
  ["H"] = 8
}

local function deepCopy(original)
  local copy = {}
  for k, v in pairs(original) do
    if type(v) == "table" then
      copy[k] = deepCopy(v)
    else
      copy[k] = v
    end
  end
  return copy
end

_Helper.deepCopy = deepCopy

local function newVocHealingConfig()
  return {
    knight = { enabled = false, percent = 90, priority = 5 },
    paladin = { enabled = false, percent = 90, priority = 4 },
    sorcerer = { enabled = false, percent = 90, priority = 3 },
    druid = { enabled = false, percent = 90, priority = 2 },
    monk = { enabled = false, percent = 90, priority = 1 },
  }
end

local function newMasResHealingConfig()
  local t = newVocHealingConfig()
  t.extended = false
  return t
end

local defaultShooterProfile = {
  spells = {
    { id = 0, percent = 0, creatures = 1, priority = 1, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 2, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 3, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 4, forceCast = false, selfCast = false },
    { id = 0, percent = 0, creatures = 1, priority = 5, forceCast = false, selfCast = false },
  },
  runes = {
    { id = 0, creatures = 1, priority = 6, forceCast = false },
    { id = 0, creatures = 1, priority = 7, forceCast = false },
  },
  autoTargetMode = (g_helperCore and g_helperCore.getAutoTargetModeId and g_helperCore.getAutoTargetModeId('F')) or 6
}

local potionConfig = { id = "potion", exhaustion = 1000 }
local specialFoodConfig = { id = "specialfood", exhaustion = 1000 }
local specialFoodLocalCooldowns = {}
local specialFoodsWindow = nil

local auxiliadorPreCooldown = 200

local function safeDoThing(flag)
  if g_game and type(g_game.doThing) == "function" then
    g_game.doThing(flag)
  end
end


local helperEvents = {
  helperCycleEvent = nil,
  helperCycleTimer = 50
}

local timers = {
  checkHealthHealing = 0,
  checkMana = 0,
  routineChecks = 0,
  checkFriendHealing = 0,
  -- checkAutoHaste removido: agora usa onStatesChange + cycle event temporario
  checkMagicShooter = 0,
  checkAutoTarget = 0,
  checkExerciseEvent = 0,
  updatePartyHealth = 0,
  checkEquipItems = 0,
  checkQuiverRefill = 0,
  checkMagicShield = 0,
  checkItemTimer = 0,
  checkExetaRes = 0,
  checkAmpRes = 0,
  checkKeepWay = 0,
  checkAvoidWaves = 0
}

-- PZ (Protection Zone) state tracking for auto_target and magic_shooter
local pzState = {
  wasInPZ = false,                -- Track previous PZ status for edge detection
  wasAutoTargetEnabled = false,   -- Auto target state before PZ entry
  wasMagicShooterEnabled = false, -- Magic shooter state before PZ entry
}

local eventTable = {
  -- Intervalos maiores pois onHealthChange/onManaChange fornecem reação instantânea
  checkHealthHealing = { interval = 500, action = nil },  -- Backup polling (era 250)
  checkMana = { interval = 500, action = nil },           -- Backup polling (era 100)
  routineChecks = { interval = 2500, action = nil },      -- Aumentado: autoChangeGold agora é reativo via onResourcesBalanceChange
  checkFriendHealing = { interval = 1000, action = nil }, -- Backup polling (era 250) - agora usa onPartyMemberHealthChange
  -- checkAutoHaste removido: agora usa onStatesChange + cycle event temporario
  checkMagicShooter = { interval = 100, action = nil },
  checkAutoTarget = { interval = 750, action = nil },
  checkExerciseEvent = { interval = 10000, action = nil },
  updatePartyHealth = { interval = 250, action = nil },
  checkEquipItems = { interval = 250, action = nil },   -- Check and equip rings/amulets based on health
  checkQuiverRefill = { interval = 500, action = nil }, -- Check and refill quiver for paladins
  checkMagicShield = { interval = 250, action = nil },   -- Check and manage magic shield for mages
  checkItemTimer = { interval = 1000, action = nil },    -- Use item on timer
  checkExetaRes = { interval = 500, action = nil },      -- Exeta Res by time + creature
  checkAmpRes = { interval = 500, action = nil },        -- Amp Res: 8 sqm, 10s cooldown
  checkKeepWay = { interval = 150, action = nil },       -- Keep Way: mantém distância do alvo
  checkAvoidWaves = { interval = 150, action = nil }     -- Avoid Waves: evita ficar de frente para criatura
}

local spellsCooldown = {}
local function getSpellCooldown(spellId)
  if g_helperCore and g_helperCore.getSpellCooldown then
    return g_helperCore.getSpellCooldown(spellId)
  end
  return spellsCooldown[spellId] or 0
end

local groupsCooldown = {}
local function getGroupSpellCooldown(groupId)
  if g_helperCore and g_helperCore.getGroupCooldown then
    return g_helperCore.getGroupCooldown(groupId)
  end
  return groupsCooldown[groupId] or 0
end

-- Optimization Caches
local cachedPrioritizedSpells = {}
local cachedPrioritizedHealthPotions = {}
local cachedPrioritizedManaPotions = {}

-- Forward declaration
local rebuildHealingCache


local function getDistanceBetween(p1, p2)
  if g_helperCore and g_helperCore.getDistanceBetween then
    return g_helperCore.getDistanceBetween(p1, p2)
  end
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function positionCompare(position1, position2)
  if not position1 or not position2 then return false end
  if g_helperCore and g_helperCore.positionCompare then
    return g_helperCore.positionCompare(position1, position2)
  end
  return position1.x == position2.x and position1.y == position2.y and position1.z == position2.z
end

local tempPos = { x = 0, y = 0, z = 0 }
local reusableCountedCreatures = {}

local function getDirectionTo(fromPos, toPos)
  if g_helperCore and g_helperCore.getDirectionTo then
    local d = g_helperCore.getDirectionTo(fromPos, toPos)
    if d < 0 then return nil end
    if d == 0 then return Directions.North end
    if d == 1 then return Directions.East end
    if d == 2 then return Directions.South end
    if d == 3 then return Directions.West end
    return nil
  end
  local dx = toPos.x - fromPos.x
  local dy = toPos.y - fromPos.y
  if dx == 0 and dy == 0 then return nil end
  if math.abs(dx) > math.abs(dy) then
    return dx > 0 and Directions.East or Directions.West
  end
  return dy > 0 and Directions.South or Directions.North
end

local function getPlayer()
  if not player then
    player = g_game.getLocalPlayer()
  end
  return player
end

local function getVocationKey(creature)
  if not creature then return nil end
  if creature:isKnight() then
    return "knight"
  elseif creature:isPaladin() then
    return "paladin"
  elseif creature:isSorcerer() then
    return "sorcerer"
  elseif creature:isDruid() then
    return "druid"
  elseif creature:isMonk() then
    return "monk"
  end
  return nil
end

local function playerHasSpell(player, spellId)
  -- getSpells() may not be available, so we'll assume the player has the spell
  -- if they meet the level and mana requirements (which are checked separately)
  -- This is a fallback - if getSpells is available, use it
  if player and player.getSpells then
    local success, spells = pcall(function() return player:getSpells() end)
    if success and spells then
      return table.contains(spells, spellId)
    end
  end
  -- If we can't check, assume the player has the spell
  -- The level/mana checks will filter out spells they can't use anyway
  return true
end

local function numberToOrdinal(n)
  if g_helperCore and g_helperCore.numberToOrdinal then
    return g_helperCore.numberToOrdinal(n)
  end
  local lastDigit = n % 10
  local lastTwoDigits = n % 100
  if lastTwoDigits >= 11 and lastTwoDigits <= 13 then return tostring(n) .. "th" end
  if lastDigit == 1 then return tostring(n) .. "st" end
  if lastDigit == 2 then return tostring(n) .. "nd" end
  if lastDigit == 3 then return tostring(n) .. "rd" end
  return tostring(n) .. "th"
end

local function isWithinReach(playerPos, targetPos)
  if type(targetPos) ~= "table" then return false end
  if g_helperCore and g_helperCore.isWithinReach then
    return g_helperCore.isWithinReach(playerPos, targetPos)
  end
  local deltaX = math.abs(playerPos.x - targetPos.x)
  local deltaY = math.abs(playerPos.y - targetPos.y)
  return deltaX <= 7 and deltaY <= 5 and playerPos.z == targetPos.z
end

local lastEngineSpectators = {}

-- Flag to prevent saving config during login/initialization
local skipSaveUntilLoaded = true


helperConfig = {
  spells = {
    { id = 0, percent = 80 },
    { id = 0, percent = 80 },
    { id = 0, percent = 80 }
  },
  potions = {
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 }
  },
  training = {
    { id = 0, percent = 0, enabled = false }
  },
  haste = {
    { id = 0, enabled = false, safecast = false }
  },
  utito = {
    { id = 0, enabled = false, safecast = false }
  },
  friendhealing = newVocHealingConfig(),
  gransiohealing = newVocHealingConfig(),
  masreshealing = newMasResHealingConfig(),

  healingTargetMode = "party",

  specialFoods = {
    hp = {
      { id = 11586, enabled = false, percent = 80, priority = 1 },
      { id = 9079,  enabled = false, percent = 80, priority = 2 },
      { id = 29414, enabled = false, percent = 80, priority = 3 },
      { id = 28485, enabled = false, percent = 80, priority = 4 },
    },
    mana = {
      { id = 29415, enabled = false, percent = 60, priority = 1 },
      { id = 28484, enabled = false, percent = 60, priority = 2 },
      { id = 9086,  enabled = false, percent = 60, priority = 3 },
    }
  },

  shooterProfiles = {
    ["Default"] = defaultShooterProfile
  },
  selectedShooterProfile = "Default",

  terms = false,
  autoEatFood = false,
  autoReconnect = false,
  autoChangeGold = false,
  magicShooterEnabled = false,
  magicShooterOnHold = false,
  disableInProtectZone   = true,
  disableShooterOnFollow = false,
  autoTargetEnabled      = false,
  autoTargetMode         = (g_helperCore and g_helperCore.getAutoTargetModeId and g_helperCore.getAutoTargetModeId('F')) or 6,
  currentLockedTargetId  = 0,
  keepWayDistance        = 0,
  avoidWaves             = false,
  autoFollow             = false,
  autoBless              = false,
  advertisingChannel     = false,
  advertisingText        = "",
  itemTimer              = {
    { itemId = 0, intervalSeconds = 60, enabled = false },
    { itemId = 0, intervalSeconds = 60, enabled = false }
  },
  exetaRes               = { { id = 0, minCreatures = 1, creatureName = "", enabled = false } },
  ampRes                 = { { id = 0, minCreatures = 1, enabled = false } },
  hotkeyCode             = nil, -- Armazena o código da hotkey
  hotkeyFunc = nil, -- Armazena a função da hotkey
  presetHotkeyEnabled = true,
  recordingHotkeyCode = nil, -- Armazena o código da hotkey de recording
  recordingHotkeyFunc = nil, -- Armazena a função da hotkey de recording
  scriptsStopAllHotkeyCode = nil,
  scriptsStopAllHotkeyFunc = nil,
  smartFollowHotkeyCode = nil,
  smartFollowHotkeyFunc = nil,
  scripts = {}
}

-- Forward declaration for preset hotkey UI refresher
local refreshPresetHotkeyButton

local function helperSmartFollowOnFollowingChange(creature, oldCreature)
  if _Helper.SmartFollow and _Helper.SmartFollow.isDebugLogEnabled and _Helper.SmartFollow.isDebugLogEnabled() and g_logger then
    if creature then
      local oid = oldCreature and oldCreature:getId() or nil
      g_logger.info(string.format("[smart_follow:hook] g_game.onFollowingCreatureChange newId=%d name=%s oldId=%s",
        creature:getId(), creature:getName(), oid and tostring(oid) or "nil"))
    else
      g_logger.info("[smart_follow:hook] g_game.onFollowingCreatureChange new=nil (follow cancelado)")
    end
  end
  if not _Helper.SmartFollow then
    return
  end
  if creature then
    if _Helper.SmartFollow.setTarget then
      _Helper.SmartFollow.setTarget(creature)
    end
  elseif _Helper.SmartFollow.isEnabled and _Helper.SmartFollow.isEnabled() and _Helper.SmartFollow.onNativeFollowLost then
    _Helper.SmartFollow.onNativeFollowLost()
  elseif _Helper.SmartFollow.clearTarget then
    _Helper.SmartFollow.clearTarget()
  end
end

local function helperSmartFollowOnCreaturePositionChange(creature, newPos, oldPos)
  if _Helper.SmartFollow and _Helper.SmartFollow.onCreaturePositionChange then
    _Helper.SmartFollow.onCreaturePositionChange(creature, newPos, oldPos)
  end
end

local function helperSmartFollowOnLocalPlayerPositionChange(creature, newPos, oldPos)
  if _Helper.SmartFollow and _Helper.SmartFollow.onLocalPlayerPositionChange then
    _Helper.SmartFollow.onLocalPlayerPositionChange(creature, newPos, oldPos)
  end
end

-- Resolve Creature: no modulo sandboxed, rawget(_G,"Creature") e' nil — a classe vem do __index para o ambiente global (como no Balrorg com `if Creature then`).
local function helperResolveCreatureClass()
  local ok, c = pcall(function()
    return Creature
  end)
  if ok then
    return c
  end
  return nil
end

-- Balrorg/Hylian: connect(Creature) no init; online() tenta de novo se falhou
local function smartFollowTryConnectCreature()
  if smartFollowCreatureHooked then
    return
  end
  local Cre = helperResolveCreatureClass()
  if Cre then
    connect(Cre, {
      onPositionChange = helperSmartFollowOnCreaturePositionChange,
    })
    smartFollowCreatureHooked = true
    if g_logger and _Helper.SmartFollow and _Helper.SmartFollow.isDebugLogEnabled and _Helper.SmartFollow.isDebugLogEnabled() then
      g_logger.info("[smart_follow:hook] connect(Creature.onPositionChange) OK")
    end
  elseif g_logger and _Helper.SmartFollow and _Helper.SmartFollow.isDebugLogEnabled and _Helper.SmartFollow.isDebugLogEnabled() then
    g_logger.warning("[smart_follow:hook] connect(Creature) FALHOU: classe Creature indisponivel (sandbox?)")
  end
end

-- spells that can be cast on both targets and self
local bothCastTypeSpells = {
  258
}


-- ignoredSpellsIds now loaded from spelldata.json via HelperSpellData module
-- Access via: HelperSpellData.getIgnoredSpellsIds()

-- Spell data now loaded from spelldata.json via HelperSpellData module
-- Access via: HelperSpellData.getIgnoredTrainingSpells()
--             HelperSpellData.getPotionWhitelist()
--             HelperSpellData.getHasteWhiteList()

function translateVocation(v)
  if g_helperCore and g_helperCore.translateVocation then
    return g_helperCore.translateVocation(v)
  end
  if type(v) == 'number' then return (v == 0 or (v >= 1 and v <= 5) or v == 9 or v == 11 or v == 12 or v == 13 or v == 14 or v == 15) and v or 0 end
  if type(v) == 'string' then return 0 end
  return 0
end

function getClientVocationsForServerVoc(serverVocId)
  if g_helperCore and g_helperCore.getClientVocationsForServerVoc then
    return g_helperCore.getClientVocationsForServerVoc(serverVocId)
  end
  return {}
end




function init()
  -- Carregar dados de spells do JSON (uma única vez)
  if not HelperSpellData.load() then
    g_logger.warning("[game_helper] Failed to load spell data from JSON, using fallback")
  end

  local success, err = pcall(function()
    if LocalPlayer then
      connect(LocalPlayer, {
        onPartyMembersChange = onPartyMembersChange,
        onHealthChange = onPlayerHealthChange,
        onManaChange = onPlayerManaChange,
        onStatesChange = onPlayerStatesChange,
        onPositionChange = helperSmartFollowOnLocalPlayerPositionChange,
        onVocationChange = function()
          scheduleEvent(function()
            if g_game.isOnline() then
              online()
            end
          end, 100)
        end,
      })
    end

    -- Smart Follow: onPositionChange em todas as criaturas (mesmo padrao Balrorg/Hylian)
    smartFollowTryConnectCreature()

    if g_game then
      connect(g_game, {
        onGameStart = online,
        onGameEnd = offline,
        onSpellCooldown = onSpellCooldown,
        onSpellGroupCooldown = onSpellGroupCooldown,
        onUpdateSpellArea = onUpdateSpellArea,
        onPartyDataUpdate = onPartyDataUpdate,
        onPartyDataClear = onPartyDataClear,
        onMultiUseCooldown = onMultiUseCooldown,
        onResourcesBalanceChange = onResourcesBalanceChange,
        onPartyMemberHealthChange = onPartyMemberHealthChangeHelper,
        onFollowingCreatureChange = helperSmartFollowOnFollowingChange,
      })
    end
    --safeLog("debug", "Helper: init() - Game events connected")
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error connecting events: %s", tostring(err)))
  end

  success, err = pcall(function()
    g_ui.importStyle('styles/helper')
    g_ui.importStyle('styles/tools_panel')
    g_ui.importStyle('styles/rule_list')
    g_ui.importStyle('styles/presets')
    g_ui.importStyle('styles/equip_panel')
    g_ui.importStyle('styles/shortcut_panel')
    g_ui.importStyle('styles/magic_shooter_panel')
    g_ui.importStyle('styles/cavebot_panel')
    g_ui.importStyle('styles/cavebot_settings')
    g_ui.importStyle('styles/btchelper')
    g_ui.importStyle('styles/scripts_panel')
    g_ui.importStyle('styles/script_editor_window')
    g_ui.importStyle('styles/scripts_doc_window')
    helper = g_ui.loadUI('helper_window', g_ui.getRootWidget())
    if helper then
      safeLog("debug", "Helper: init() - Helper window created")
    else
      safeLog("error", "Helper: init() - Failed to create helper window")
    end
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error creating UI: %s", tostring(err)))
  end

  success, err = pcall(function()
    local rootWidget = g_ui.getRootWidget()
    helperRules = g_ui.createWidget('HelperRules', rootWidget)
    if helperRules then
      helperRules:hide()
    end
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error creating rules: %s", tostring(err)))
  end

  player = g_game.getLocalPlayer()
  -- hide() moved after panel creation to avoid issues
  if helper and helper.contentPanel then
    healingPanel = helper.contentPanel:getChildById('healingPanel')
    toolsPanelContainer = helper.contentPanel:getChildById('toolsPanelContainer')
    if toolsPanelContainer then
      toolsPanel = toolsPanelContainer:getChildById('toolsPanel')
    end

    -- Log warning if panels don't exist, but continue initialization
    if not healingPanel or not toolsPanel then
      safeLog("error", "Helper: init() - Required panels not found, but continuing initialization")
    end

    if healingPanel then
      potionButton2 = healingPanel:recursiveGetChildById("potionButton2")
      rmvPotionPercentButton2 = healingPanel:recursiveGetChildById("rmvPotionPercentButton2")
      potionPercentBg2 = healingPanel:recursiveGetChildById("potionPercentBg2")
      addPotionPercentButton2 = healingPanel:recursiveGetChildById("addPotionPercentButton2")
      priority2 = healingPanel:recursiveGetChildById("priority2")
      friendHealingPanel = healingPanel:recursiveGetChildById("friendHealingPanel")
      granSioPanel = healingPanel:recursiveGetChildById("granSioPanel")
      masResPanel = healingPanel:recursiveGetChildById("masResPanel")
      healingTargetModePanel = healingPanel:recursiveGetChildById("healingTargetModePanel")
      if healingTargetModePanel then
        healingTargetModeRadio = UIRadioGroup.create()
        local screenBtn = healingTargetModePanel:recursiveGetChildById("targetModeScreen")
        local partyBtn = healingTargetModePanel:recursiveGetChildById("targetModeParty")
        if screenBtn and partyBtn then
          healingTargetModeRadio:addWidget(screenBtn)
          healingTargetModeRadio:addWidget(partyBtn)
          healingTargetModeRadio.onSelectionChange = function(_, selected)
            if selected then
              local mode = (selected:getId() == "targetModeScreen") and "screen" or "party"
              helperConfig.healingTargetMode = mode
            end
          end
          local mode = helperConfig.healingTargetMode or "party"
          if mode == "screen" then
            healingTargetModeRadio:selectWidget(screenBtn)
          else
            healingTargetModeRadio:selectWidget(partyBtn)
          end
        end
      end
      spellButton2 = healingPanel:recursiveGetChildById("spellButton2")
      rmvPercentButton2 = healingPanel:recursiveGetChildById("rmvPercentButton2")
      spellPercentBg2 = healingPanel:recursiveGetChildById("spellPercentBg2")
      addPercentButton2 = healingPanel:recursiveGetChildById("addPercentButton2")
      healPanel = healingPanel:getChildById('healingPanel')
      priorityButton1 = healingPanel:recursiveGetChildById("priority0")
      priorityButton2 = healingPanel:recursiveGetChildById("priority1")
      priorityButton3 = healingPanel:recursiveGetChildById("priority2")
      if toolsPanel then
        equipPanel = toolsPanel:recursiveGetChildById("equipPanel")
      end
      shooterPanel = helper.contentPanel:getChildById('shooterPanel')
      equipPanelContainer = helper.contentPanel:getChildById('equipPanelContainer')
      -- Initialize equip panel module
      if equipPanelContainer and modules.game_helper and modules.game_helper.equip then
        modules.game_helper.equip.init(helper)
      end
      if shooterPanel then
        -- New unified magic shooter panel
        local magicShooterContainer = shooterPanel:recursiveGetChildById("magicShooterPanelContainer")
        if magicShooterContainer then
          local magicShooterPanel = magicShooterContainer:recursiveGetChildById("magicShooterPanel")
          if magicShooterPanel then
            enableButtons = magicShooterPanel:recursiveGetChildById("enableButtonsPanel")
            presetsPanel = magicShooterPanel:recursiveGetChildById("presetsSection")
          end
        end
        -- Initialize magic shooter panel module
        if modules.game_helper and modules.game_helper.magicShooter then
          modules.game_helper.magicShooter.init(helper)
        end
      end
      friendListWidget = nil
      granListWidget = nil
      scriptsPanelContainer = helper.contentPanel:getChildById('scriptsPanelContainer')
      if scriptsPanelContainer and modules.game_helper and modules.game_helper.scripts then
        modules.game_helper.scripts.init(helper)
      end
      if helper.contentPanel.cavebotPanel then
        cavebotPanel = helper.contentPanel.cavebotPanel
        if modules.game_helper and modules.game_helper.cavebot then
          modules.game_helper.cavebot.init(helper)
        end
      end
    end
  end

  botStatus()

  -- Hide the window after everything is set up
  if helper then
    helper:hide()
  end

  mouseGrabberWidget = g_ui.createWidget('UIWidget')
  mouseGrabberWidget:setVisible(false)
  mouseGrabberWidget:setFocusable(false)

  -- Bind Ctrl+H to toggle helper window
  if g_keyboard then
    g_keyboard.bindKeyDown('Ctrl+H', toggle)
  end

  success, err = pcall(function()
    local attempts = 0
    local maxAttempts = 10

    local function tryInitialize()
      attempts = attempts + 1
      -- Verificar diretamente se o player existe (mais confiável que isOnline())
      if g_game and g_game.getLocalPlayer then
        local currentPlayer = g_game.getLocalPlayer()
        if currentPlayer then
          online()
          return true
        else
          safeLog("debug",
            string.format("Helper: init() - Player not available yet (attempt %d/%d)", attempts, maxAttempts))
          return false
        end
      else
        safeLog("debug",
          string.format("Helper: init() - g_game.getLocalPlayer not available yet (attempt %d/%d)", attempts, maxAttempts))
        return false
      end
    end

    -- Tentar inicializar imediatamente
    if not tryInitialize() then
      -- Se falhou, tentar novamente com intervalos progressivos
      if _G.scheduleEvent then
        safeLog("debug", "Helper: init() - Scheduling initialization retry attempts")
        local function retryAttempt()
          if helperEvents and helperEvents.helperCycleEvent then
            safeLog("info", "Helper: init() - CycleEvent already registered, stopping retries")
            return
          end
          if attempts >= maxAttempts then
            safeLog("debug",
              string.format("Helper: init() - Max initialization attempts reached (%d), will initialize on game start",
                maxAttempts))
            return
          end
          if tryInitialize() then
            --  safeLog("info", "Helper: init() - Initialization successful after retry")
          else
            -- Agendar próxima tentativa com intervalo maior
            local delay = math.min(500 + (attempts * 200), 2000)
            _G.scheduleEvent(retryAttempt, delay)
          end
        end
        _G.scheduleEvent(retryAttempt, 300)
      end
    end

    -- Monitor contínuo para detectar login de novo player quando o ciclo não está rodando
    local function monitorGameState()
      if g_game and g_game.isOnline and g_game.isOnline() then
        if not helperEvents or not helperEvents.helperCycleEvent then
          local currentPlayer = g_game.getLocalPlayer()
          if currentPlayer then
            online()
          end
        end
      end
      _G.scheduleEvent(monitorGameState, 1000)
    end
    _G.scheduleEvent(monitorGameState, 2000)
  end)

  if not success then
    safeLog("error", string.format("Helper: init() - Error checking online status: %s", tostring(err)))
  end

  --  safeLog("info", "Helper: init() - Initialization complete")

  -- Funções de teste removidas - não estão definidas

  -- Configurações são carregadas por personagem em loadSettings() quando o jogador faz login
end

function terminate()
  if specialFoodsWindow then
    specialFoodsWindow:destroy()
    specialFoodsWindow = nil
  end

  if LocalPlayer then
    disconnect(LocalPlayer, {
      onPartyMembersChange = onPartyMembersChange,
      onHealthChange = onPlayerHealthChange,
      onManaChange = onPlayerManaChange,
      onStatesChange = onPlayerStatesChange,
      onPositionChange = helperSmartFollowOnLocalPlayerPositionChange,
    })
  end

  if smartFollowCreatureHooked then
    local Cre = helperResolveCreatureClass()
    if Cre then
      disconnect(Cre, {
        onPositionChange = helperSmartFollowOnCreaturePositionChange,
      })
    end
    smartFollowCreatureHooked = false
  end

  if g_game then
    disconnect(g_game, {
      onGameStart = online,
      onGameEnd = offline,
      onSpellCooldown = onSpellCooldown,
      onSpellGroupCooldown = onSpellGroupCooldown,
      onUpdateSpellArea = onUpdateSpellArea,
      onPartyDataUpdate = onPartyDataUpdate,
      onPartyDataClear = onPartyDataClear,
      onMultiUseCooldown = onMultiUseCooldown,
      onResourcesBalanceChange = onResourcesBalanceChange,
      onPartyMemberHealthChange = onPartyMemberHealthChangeHelper,
      onFollowingCreatureChange = helperSmartFollowOnFollowingChange,
    })
  end

  -- safeLog("debug", "Helper: terminate() - Creature events skipped")

  if helper then
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, helper)
    helper:destroy()
    helper = nil
  end

  if modules.game_helper and modules.game_helper.cavebot and modules.game_helper.cavebot.terminate then
    modules.game_helper.cavebot.terminate()
  end

  -- Unbind Ctrl+H toggle helper window
  if g_keyboard then
    g_keyboard.unbindKeyDown('Ctrl+H', toggle)
  end

  if mouseGrabberWidget then
    mouseGrabberWidget:destroy()
    mouseGrabberWidget = nil
  end

  if helperRules then
    helperRules:destroy()
    helperRules = nil
  end

  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.terminate then
    modules.game_helper.equip.terminate()
  end
  if modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.terminate then
    modules.game_helper.scripts.terminate()
  end

  _Helper.Shortcut.destroyPanel()
end

function toggle()
  if helper and helper:isVisible() then
    helper:hide()
  else
    if helper then
      helper:show(true)
      helper:raise()
      helper:focus()
      g_keyboard.bindKeyPress('Tab', toggleNextWindow, helper)
      loadMenu(lastActiveMenu)
    end
  end
end

function hide()
  if helper then
    g_keyboard.unbindKeyPress('Tab', toggleNextWindow, helper)
    helper:hide()
  end
end

function show()
  if helper then
    helper:show(true)
    helper:raise()
    helper:focus()
    g_keyboard.bindKeyPress('Tab', toggleNextWindow, helper)
    loadMenu(lastActiveMenu)
  end
end

function onBTCHelperClick()
  toggle()
end

function createBTCHelperWidget()
  -- Evitar criar duplicado
  if btcHelperWidget then
    return
  end

  local mainRightPanel = modules.game_interface.getMainRightPanel()
  if not mainRightPanel then
    return
  end

  btcHelperWidget = g_ui.createWidget('BTCHelperWidget')
  if not btcHelperWidget then
    return
  end

  local insertIndex = 1
  local children = mainRightPanel:getChildren()
  for i, child in ipairs(children) do
    if child:getId() == 'minimapWindow' then
      insertIndex = i + 1
      break
    end
  end

  mainRightPanel:insertChild(insertIndex, btcHelperWidget)

  if mainRightPanel.fitAllChildren then
    mainRightPanel:fitAllChildren()
  end
end

function destroyBTCHelperWidget()
  if btcHelperWidget then
    btcHelperWidget:destroy()
    btcHelperWidget = nil
  end
end

function repositionBTCHelperBelowMinimap()
  if not btcHelperWidget then
    return
  end

  local mainRightPanel = modules.game_interface.getMainRightPanel()
  if not mainRightPanel then
    return
  end

  mainRightPanel:removeChild(btcHelperWidget)

  local insertIndex = 1
  local children = mainRightPanel:getChildren()
  for i, child in ipairs(children) do
    if child:getId() == 'minimapWindow' then
      insertIndex = i + 1
      break
    end
  end

  mainRightPanel:insertChild(insertIndex, btcHelperWidget)

  if mainRightPanel.fitAllChildren then
    mainRightPanel:fitAllChildren()
  end
end

function getBTCHelperWidget()
  return btcHelperWidget
end

local lastPlayerName = nil

function helperCycleEvent()
  -- Não executar durante transição de player
  if isTransitioningPlayer then
    return
  end

  -- Detectar mudança de player (login com outro personagem)
  local currentPlayer = g_game.getLocalPlayer()
  if currentPlayer then
    local currentName = currentPlayer:getName()
    if lastPlayerName and lastPlayerName ~= currentName then
      lastPlayerName = currentName
      player = currentPlayer
      -- Recarregar configurações do novo player
      scheduleEvent(function()
        if g_game.isOnline() then
          loadSettings()
          -- Registrar hotkeys salvas APÓS loadSettings() carregar os dados
          unregisterAllHelperHotkeys()
          registerSavedHotkeys()
          scheduleEvent(function()
            if healingPanel and toolsPanel and shooterPanel then
              onLoadHelperData()
            end
          end, 200)
        end
      end, 100)
      return
    elseif not lastPlayerName then
      lastPlayerName = currentName
    end
  end

  -- Centralizar captura de espectadores para otimização
  -- Limite de visão do player: 7 tiles horizontal (cada lado), 5 tiles vertical (cada lado)
  local spectatorsSnapshot = nil
  if currentPlayer then
    local pos = currentPlayer:getPosition()
    if pos then
      spectatorsSnapshot = g_map.getSpectatorsInRange(pos, false, 7, 5)
    end
  end
  lastEngineSpectators = spectatorsSnapshot or {}

  local debugHelper = false
  for eventName, eventData in pairs(eventTable) do
    timers[eventName] = timers[eventName] + helperEvents.helperCycleTimer
    if timers[eventName] >= eventData.interval then
      timers[eventName] = 0
      local func = eventData.action
      if func and type(func) == "function" then
        if debugHelper then print("[Helper] Executing event: " .. eventName) end
        -- Passar spectators para funções que podem se beneficiar
        if eventName == "updatePartyHealth" or eventName == "checkFriendHealing" then
          func(lastEngineSpectators)
        else
          func()
        end
      end
    end
  end
end

function isValidAutoTargetCreature(creature)
  return _Helper.AutoTarget.isValidCreature(creature)
end

function online()
  local benchmark = g_clock.millis()
  player = g_game.getLocalPlayer()

  smartFollowTryConnectCreature()

  -- bloqueia save até tudo carregar
  skipSaveUntilLoaded = true
  isTransitioningPlayer = true
  helperConfig.currentLockedTargetId = 0

  -- Carrega UI e configurações

  -- Carregar settings se houver arquivo salvo
  scheduleEvent(function()
    if g_game.isOnline() then
      loadSettings()

      -- Registrar hotkeys salvas APÓS loadSettings() carregar os dados
      unregisterAllHelperHotkeys()
      registerSavedHotkeys()

      -- Aplica dados salvos na UI (depois que painéis existem)
      scheduleEvent(function()
        if healingPanel and toolsPanel and shooterPanel then
          onLoadHelperData()
        end

        -- Libera salvamento e ações após carregar
        skipSaveUntilLoaded = false
        isTransitioningPlayer = false
      end, 200)
    end
  end, 500)

  -- Atualiza o status visual do helper após carregar config
  scheduleEvent(function()
    if helper then
      botStatus()
    end
  end, 100)

  helperConfig.currentLockedTargetId = 0
  if helperEvents.helperCycleEvent then
    removeEvent(helperEvents.helperCycleEvent)
    helperEvents.helperCycleEvent = nil
  end
  helperEvents.helperCycleEvent = cycleEvent(helperCycleEvent, helperEvents.helperCycleTimer)

  resetPartyPanel()
  loadMenu('toolsMenu')

  -- ===== ADICIONE AQUI =====
  -- scheduleEvent(function()
  -- local function syncPartyList()
  -- if modules.game_party_list and modules.game_party_list.getPartyMembers then
  -- local members = modules.game_party_list.getPartyMembers()
  -- if members and #members > 0 then
  -- onPartyDataUpdate(members)
  -- end
  -- end
  -- scheduleEvent(syncPartyList, 2000, "helperSyncParty")
  -- end
  -- syncPartyList()
  -- end, 3000)
  -- ===== FIM =====

  if helper then
    botStatus()
  end

  -- Criar o painel de atalhos do helper (shortcut panel) se estiver habilitado
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.Shortcut.isVisible() then
      _Helper.Shortcut.createPanel()
    end
    -- Sincronizar checkbox do helper com o valor carregado
    if helper and helper.contentPanel then
      local shortcutsCheckbox = helper.contentPanel:recursiveGetChildById('shortcuts')
      if shortcutsCheckbox then
        shortcutsCheckbox:setChecked(_Helper.Shortcut.isVisible())
      end
    end
  end, 1000)

  -- Iniciar Auto Haste se necessario (verifica se player nao tem haste no login)
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.AutoHaste and _Helper.AutoHaste.onLogin then
      _Helper.AutoHaste.onLogin()
    end
  end, 1500)

  -- Iniciar Auto Utito se necessario
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.AutoUtito and _Helper.AutoUtito.onLogin then
      _Helper.AutoUtito.onLogin()
    end
  end, 1500)

  -- Iniciar Exercise Training se necessario
  scheduleEvent(function()
    if g_game.isOnline() and _Helper.ExerciseTraining and _Helper.ExerciseTraining.onLogin then
      _Helper.ExerciseTraining.onLogin()
    end
  end, 1600)

  -- Iniciar Auto Bless se necessario
  scheduleEvent(function()
    if g_game.isOnline() and modules.game_helper.tools and modules.game_helper.tools.onLogin then
      modules.game_helper.tools.onLogin()
    end
  end, 2500)

  -- Criar BTCHelper widget no painel direito
  scheduleEvent(function()
    if g_game.isOnline() then
      createBTCHelperWidget()
    end
  end, 100)
end

function restoreHelperHotkey()
  if not helperConfig.hotkeyCode or not g_keyboard then
    return
  end

  local toggleFunc = function()
    helperAutomaticFunctionsEnabled = not helperAutomaticFunctionsEnabled
    if helper then
      botStatus()
    end
    _Helper.Shortcut.syncButton('shortcutHelper', helperAutomaticFunctionsEnabled)
  end

  helperConfig.hotkeyFunc = toggleFunc
  g_keyboard.bindKeyDown(helperConfig.hotkeyCode, toggleFunc)
end

function offline()
  -- Bloquear ações durante transição
  isTransitioningPlayer = true

  if smartFollowCreatureHooked then
    local Cre = helperResolveCreatureClass()
    if Cre then
      disconnect(Cre, {
        onPositionChange = helperSmartFollowOnCreaturePositionChange,
      })
    end
    smartFollowCreatureHooked = false
  end

  -- Parar ciclo de eventos PRIMEIRO para evitar usar dados antigos
  if helperEvents and helperEvents.helperCycleEvent then
    removeEvent(helperEvents.helperCycleEvent)
    helperEvents.helperCycleEvent = nil
  end

  -- Parar cycle event do Auto Haste
  if _Helper.AutoHaste and _Helper.AutoHaste.onLogout then
    _Helper.AutoHaste.onLogout()
  end

  if _Helper.AutoUtito and _Helper.AutoUtito.onLogout then
    _Helper.AutoUtito.onLogout()
  end

  -- Parar cycle event do Exercise Training
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.onLogout then
    _Helper.ExerciseTraining.onLogout()
  end

  if _Helper.SmartFollow and _Helper.SmartFollow.onLogout then
    _Helper.SmartFollow.onLogout()
  end

  -- Reset PZ state on logout
  if _Helper.resetPZState then
    _Helper.resetPZState()
  end

  -- Remover hotkeys antes de deslogar (serão re-registradas no próximo online())
  unregisterAllHelperHotkeys()

  -- Salvar antes de deslogar
  saveSettings()

  if presetsPanel then
    local presets = presetsPanel:recursiveGetChildById('presets')
    -- removeEvent("helperSyncParty")
    if presets then
      presets:clear()
    end
  end

  if g_helperCore and g_helperCore.clearCooldowns then
    g_helperCore.clearCooldowns()
  else
    for k in pairs(spellsCooldown) do spellsCooldown[k] = nil end
    for k in pairs(groupsCooldown) do groupsCooldown[k] = nil end
  end

  -- Limpar spectators cache
  for k in pairs(lastEngineSpectators) do lastEngineSpectators[k] = nil end

  -- Resetar timers para zero
  for k in pairs(timers) do timers[k] = 0 end

  -- Resetar player para nil
  player = nil
  lastPlayerName = nil

  -- Limpar widgets de party para evitar referências pendentes
  if friendListWidget then
    for _, widget in pairs(friendListWidget:getChildren()) do
      widget.creature = nil
    end
    friendListWidget:destroyChildren()
  end

  if granListWidget then
    for _, widget in pairs(granListWidget:getChildren()) do
      widget.creature = nil
    end
    granListWidget:destroyChildren()
  end

  if helper then
    hide()
  end

  -- Destruir o shortcut panel ao deslogar
  _Helper.Shortcut.destroyPanel()

  -- Destruir BTCHelper widget ao deslogar
  destroyBTCHelperWidget()

  -- Forçar coleta de lixo ao deslogar
  scheduleEvent(function()
    collectgarbage("collect")
  end, 500)
end

-- HELPER SHORTCUT PANEL: Funções movidas para classes/shortcut_panel.lua
-- Funções getter para acesso externo às variáveis locais (usadas por _Helper.Shortcut)

_Helper.getHelperWindow = function()
  return helper
end

_Helper.getToolsPanel = function()
  return toolsPanel
end

_Helper.getShooterPanel = function()
  return shooterPanel
end

_Helper.isHelperAutomaticFunctionsEnabled = function()
  return helperAutomaticFunctionsEnabled
end

_Helper.setHelperAutomaticFunctionsEnabled = function(value)
  helperAutomaticFunctionsEnabled = value
end

_Helper.saveSettings = saveSettings

-- HELPER AUTO HASTE: Funções getter/setter para acesso externo às variáveis locais (usadas por _Helper.AutoHaste)

_Helper.defaultShooterProfile = defaultShooterProfile

_Helper.getHelperConfig = function()
  return helperConfig
end

_Helper.getSpellDataById = function(spellId)
  return getSpellDataById(spellId)
end

_Helper.getSpellCooldown = function(spellId)
  return getSpellCooldown(spellId)
end

_Helper.getGroupSpellCooldown = function(groupId)
  return getGroupSpellCooldown(groupId)
end

_Helper.checkHealthPriority = function()
  return checkHealthPriority()
end

_Helper.safeDoThing = function(flag)
  return safeDoThing(flag)
end

_Helper.translateVocation = translateVocation

-- HELPER MANA TRAINING: Funcao getter para acesso externo (usada por _Helper.ManaTraining)
_Helper.castHealingSpell = function(spellData)
  return castHealingSpell(spellData)
end

-- HELPER AUTO FOOD: Funcao setter para acesso externo ao cooldown (usada por _Helper.AutoFood)
_Helper.setSpellCooldown = function(spellId, value)
  if g_helperCore and g_helperCore.setSpellCooldownEndTime then
    g_helperCore.setSpellCooldownEndTime(spellId, value)
  else
    spellsCooldown[spellId] = value
  end
end

-- HELPER AUTO TARGET: Funcoes getter/setter para acesso externo (usadas por _Helper.AutoTarget)
_Helper.getSpectators = function()
  return lastEngineSpectators
end

_Helper.getAutoTargetModes = function()
  if g_helperCore and g_helperCore.getAutoTargetModesTable then
    return g_helperCore.getAutoTargetModesTable()
  end
  return autoTargetModes
end

_Helper.getEnableButtons = function()
  return enableButtons
end

_Helper.getDistanceBetween = function(p1, p2)
  return getDistanceBetween(p1, p2)
end

_Helper.getDirectionTo = function(fromPos, toPos)
  return getDirectionTo(fromPos, toPos)
end

_Helper.isWithinReach = function(pos1, pos2)
  return isWithinReach(pos1, pos2)
end

_Helper.positionCompare = function(position1, position2)
  return positionCompare(position1, position2)
end

_Helper.getAfkTime = function()
  return afkTime
end

_Helper.setAutoTargetOnHold = function(value)
  autoTargetOnHold = value
end

_Helper.getAutoTargetOnHold = function()
  return autoTargetOnHold
end

-- ===== PZ (Protection Zone) Handler =====
-- Handles state transitions for auto_target and magic_shooter when entering/leaving PZ
-- Returns: true if system should continue, false if action should be blocked

-- Internal helper: disable a system permanently (used when disableInProtectZone == true)
local function pzDisableSystem(systemName, showMessage)
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not enableButtons then return end

  if systemName == "autoTarget" then
    local widget = enableButtons:recursiveGetChildById("enableAutoTarget")
    if widget and widget:isChecked() then
      widget:setChecked(false)
      if helperConfig then
        helperConfig.autoTargetEnabled = false
        helperConfig.currentLockedTargetId = 0
        g_game.cancelAttack()
      end
      if showMessage then
        modules.game_textmessage.displayGameMessage("Auto Target disabled (Protection Zone).")
      end
      if _Helper.Shortcut and _Helper.Shortcut.syncButton then
        _Helper.Shortcut.syncButton('shortcutAutoTarget', false)
      end
    end
  elseif systemName == "magicShooter" then
    local widget = enableButtons:recursiveGetChildById("enableMagicShooter")
    if widget and widget:isChecked() then
      widget:setChecked(false)
      if helperConfig then
        helperConfig.magicShooterEnabled = false
      end
      if showMessage then
        modules.game_textmessage.displayGameMessage("Magic Shooter disabled (Protection Zone).")
      end
      if _Helper.Shortcut and _Helper.Shortcut.syncButton then
        _Helper.Shortcut.syncButton('shortcutMagicShooter', false)
      end
    end
  end
end

-- Internal helper: suspend a system temporarily (used when disableInProtectZone == false)
-- For Case A2: We do NOT modify enabled flag, just cancel current attack and show message
local function pzSuspendSystem(systemName)
  if systemName == "autoTarget" then
    -- Cancel current attack but don't change enabled state
    if helperConfig then
      helperConfig.currentLockedTargetId = 0
    end
    g_game.cancelAttack()
    modules.game_textmessage.displayGameMessage("Auto Target paused (Protection Zone).")
  elseif systemName == "magicShooter" then
    modules.game_textmessage.displayGameMessage("Magic Shooter paused (Protection Zone).")
  end
end

-- Internal helper: notify restore after leaving PZ (for Case A2)
local function pzRestoreSystem(systemName)
  if systemName == "autoTarget" then
    modules.game_textmessage.displayGameMessage("Auto Target resumed (left Protection Zone).")
  elseif systemName == "magicShooter" then
    modules.game_textmessage.displayGameMessage("Magic Shooter resumed (left Protection Zone).")
  end
end

-- Main PZ handler - call from check functions
-- Returns: true if action should continue, false if blocked (in PZ)
_Helper.handlePZState = function()
  local player = g_game.getLocalPlayer()
  if not player then return false end

  local inPZ = player:isInProtectionZone()
  local wasInPZ = pzState.wasInPZ

  -- Detect PZ entry (edge: not in PZ -> in PZ)
  if inPZ and not wasInPZ then
    pzState.wasInPZ = true

    if helperConfig and helperConfig.disableInProtectZone then
      -- Case A1: Permanently disable both systems (updates UI and config)
      pzDisableSystem("autoTarget", true)
      pzDisableSystem("magicShooter", true)
      if saveSettings then
        saveSettings()
      end
    else
      -- Case A2: Just record which systems were enabled for restore notification
      -- DO NOT modify enabled flags - the PZ guard will block actions
      pzState.wasAutoTargetEnabled = helperConfig and helperConfig.autoTargetEnabled or false
      pzState.wasMagicShooterEnabled = helperConfig and helperConfig.magicShooterEnabled or false
      if pzState.wasAutoTargetEnabled then
        pzSuspendSystem("autoTarget")
      end
      if pzState.wasMagicShooterEnabled then
        pzSuspendSystem("magicShooter")
      end
    end
  end

  -- Detect PZ exit (edge: in PZ -> not in PZ)
  if not inPZ and wasInPZ then
    pzState.wasInPZ = false

    -- Only show restore message if disableInProtectZone is false (Case A2)
    -- and the system is still enabled (user didn't manually disable while in PZ)
    if helperConfig and not helperConfig.disableInProtectZone then
      if pzState.wasAutoTargetEnabled and helperConfig.autoTargetEnabled then
        pzRestoreSystem("autoTarget")
      end
      if pzState.wasMagicShooterEnabled and helperConfig.magicShooterEnabled then
        pzRestoreSystem("magicShooter")
      end
    end
    -- Reset saved states
    pzState.wasAutoTargetEnabled = false
    pzState.wasMagicShooterEnabled = false
  end

  -- GUARD: Always block actions while in PZ
  if inPZ then
    return false
  end

  return true
end

-- Getter for pzState (for debugging/testing)
_Helper.getPZState = function()
  return pzState
end

-- Reset PZ state (called on logout/character change)
_Helper.resetPZState = function()
  pzState.wasInPZ = false
  pzState.wasAutoTargetEnabled = false
  pzState.wasMagicShooterEnabled = false
end

-- NOTA: _Helper.getShooterProfile é definido mais abaixo, após a função getShooterProfile ser declarada

-- HELPER MAGIC SHOOTER: Funcoes getter/setter para acesso externo (usadas por _Helper.MagicShooter)
_Helper.getHelper = function()
  return helper
end

_Helper.getPresetsPanel = function()
  return presetsPanel
end

-- Legacy getter - returns nil since runePanel no longer exists
_Helper.getRunePanel = function()
  return nil
end

_Helper.getShooterProfileCount = function()
  return getShooterProfileCount()
end

_Helper.numberToOrdinal = function(n)
  return numberToOrdinal(n)
end

_Helper.removeAction = removeAction

_Helper.getHarmonyCountSafe = function(p)
  return getHarmonyCountSafe(p)
end

_Helper.canUseByServerVoc = function(spellVocations, serverVocId)
  return canUseByServerVoc(spellVocations, serverVocId)
end

_Helper.playerHasSpell = function(player, spellId)
  return playerHasSpell(player, spellId)
end

-- Retorna a tabela de monstros a ignorar (usado por auto_target e magic_shooter)
_Helper.getIgnoreMonsterTable = function()
  if modules.game_helper and modules.game_helper.magicShooter and modules.game_helper.magicShooter.getIgnoreMonsterTable then
    return modules.game_helper.magicShooter.getIgnoreMonsterTable()
  end
  return {}
end

-- NOTA: _Helper.getRelativePosition, _Helper.isSpellOnCooldown, _Helper.onSpellCooldown,
-- _Helper.onSpellGroupCooldown, _Helper.findBestTarget e _Helper.countAttackableCreatures
-- sao definidos mais abaixo no arquivo, apos as funcoes locais correspondentes serem declaradas.

-- Wrapper functions para compatibilidade com chamadas externas (OTUI e outros módulos)
function toggleShortcuts(checked)
  _Helper.Shortcut.toggle(checked)
end

function updateShortcutPanelPosition()
  _Helper.Shortcut.updatePosition()
end

function onShortcutButtonChange(button)
  _Helper.Shortcut.onButtonChange(button)
end

function onSpellCooldown(spellId, delay)
  if g_helperCore and g_helperCore.setSpellCooldown then
    g_helperCore.setSpellCooldown(spellId, delay)
  end
end

function onSpellGroupCooldown(groupId, delay)
  if g_helperCore and g_helperCore.setGroupCooldown then
    g_helperCore.setGroupCooldown(groupId, delay)
  end
end

function onMultiUseCooldown(time)
  if g_helperCore and g_helperCore.setMultiUseCooldown then
    g_helperCore.setMultiUseCooldown(time)
  end
end

function onUpdateSpellArea(energyWaveEnlarged)
  if energyWaveEnlarged then
    SpellInfo.Default["Energy Wave"].area = SpellAreas.AREA_SQUAREWAVE6
  else
    SpellInfo.Default["Energy Wave"].area = SpellAreas.AREA_SQUAREWAVE4
  end
end

function getShooterProfileCount()
  local i = 0
  for n, j in pairs(helperConfig.shooterProfiles) do
    i = i + 1
  end
  return i
end

function getShooterProfile()
  local profile = helperConfig.shooterProfiles[helperConfig.selectedShooterProfile]
  if not profile then
    return defaultShooterProfile
  end
  return profile
end

-- HELPER MAGIC SHOOTER: Getter definido apos a funcao getShooterProfile
_Helper.getShooterProfile = getShooterProfile

function loadMenu(menuId)
  if not helper or not helper.contentPanel then
    return
  end

  -- Init pode correr antes da árvore estar estável; re-resolver antes de mostrar painéis
  if not healingPanel then
    healingPanel = helper.contentPanel:getChildById('healingPanel')
  end
  if not shooterPanel then
    shooterPanel = helper.contentPanel:getChildById('shooterPanel')
  end
  if healingPanel then
    healPanel = healingPanel:getChildById('healingPanel')
  end

  local buttons = {
    healingMenu = 'healingMenu',
    toolsMenu = 'toolsMenu',
    scriptsMenu = 'scriptsMenu',
    shooterMenu = 'shooterMenu',
    equipMenu = "equipMenu",
    cavebotMenu = 'cavebotMenu',
  }

  for buttonName, buttonId in pairs(buttons) do
    local button = helper.contentPanel.optionsTabBar:getChildById(buttonId)
    if button then
      button:setChecked(false)
    end
  end

  -- Default hide Cavebot footer elements
  local cbLabel = helper:recursiveGetChildById('cavebotStatusLabel')
  local cbBtn = helper:recursiveGetChildById('cavebotToggleButton')
  if cbLabel then cbLabel:hide() end
  if cbBtn then cbBtn:hide() end

  lastActiveMenu = menuId

  local selectedButton = helper.contentPanel.optionsTabBar:getChildById(menuId)
  if selectedButton then
    selectedButton:setChecked(true)
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    -- Sem personagem: mostrar healing mesmo sem shooterPanel (antes bloqueava tudo)
    if healingPanel then
      healingPanel:setVisible(true)
      healingPanel:show(true)
      pcall(function()
        helper.contentPanel:raiseChild(healingPanel)
      end)
    end
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:hide() end
    if shooterPanel then shooterPanel:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    helper:setSize(tosize("295 240"))
    return
  end

  player = currentPlayer

  if menuId == 'healingMenu' then
    if not healingPanel then
      return
    end
    -- Atualizar referências aos widgets (evita nil se o init correu antes do OTUI estar completo)
    healPanel = healingPanel:getChildById('healingPanel')
    friendHealingPanel = healingPanel:recursiveGetChildById("friendHealingPanel")
    granSioPanel = healingPanel:recursiveGetChildById("granSioPanel")
    masResPanel = healingPanel:recursiveGetChildById("masResPanel")
    healingTargetModePanel = healingPanel:recursiveGetChildById("healingTargetModePanel")
    spellButton2 = healingPanel:recursiveGetChildById("spellButton2")
    rmvPercentButton2 = healingPanel:recursiveGetChildById("rmvPercentButton2")
    spellPercentBg2 = healingPanel:recursiveGetChildById("spellPercentBg2")
    addPercentButton2 = healingPanel:recursiveGetChildById("addPercentButton2")
    potionButton2 = healingPanel:recursiveGetChildById("potionButton2")
    rmvPotionPercentButton2 = healingPanel:recursiveGetChildById("rmvPotionPercentButton2")
    potionPercentBg2 = healingPanel:recursiveGetChildById("potionPercentBg2")
    addPotionPercentButton2 = healingPanel:recursiveGetChildById("addPotionPercentButton2")
    priority2 = healingPanel:recursiveGetChildById("priority2")
    priorityButton1 = healingPanel:recursiveGetChildById("priority0")
    priorityButton2 = healingPanel:recursiveGetChildById("priority1")
    priorityButton3 = healingPanel:recursiveGetChildById("priority2")
    healingPanel:setVisible(true)
    healingPanel:show(true)
    pcall(function()
      helper.contentPanel:raiseChild(healingPanel)
    end)
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:hide() end
    if shooterPanel then shooterPanel:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    local function vis(w, v)
      if w then w:setVisible(v) end
    end
    local function tip(w, t)
      if w then w:setTooltip(t) end
    end
    do
      local vocOk, vocErr = pcall(function()
    if currentPlayer:isKnight() then
      helper:setSize(tosize("295 309"))
      if healPanel then healPanel:setHeight(160) end
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      vis(friendHealingPanel, false)
      vis(granSioPanel, false)
      if masResPanel then masResPanel:setVisible(false) end
      vis(spellButton2, true)
      vis(rmvPercentButton2, true)
      vis(spellPercentBg2, true)
      vis(addPercentButton2, true)
      vis(potionButton2, true)
      vis(rmvPotionPercentButton2, true)
      vis(potionPercentBg2, true)
      vis(addPotionPercentButton2, true)
      vis(priority2, true)
      tip(priorityButton1,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      tip(priorityButton2,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      tip(priorityButton3,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif currentPlayer:isPaladin() then
      helper:setSize(tosize("295 309"))
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      vis(friendHealingPanel, false)
      vis(granSioPanel, false)
      if masResPanel then masResPanel:setVisible(false) end
      if healPanel then healPanel:setHeight(160) end
      vis(rmvPercentButton2, true)
      vis(spellPercentBg2, true)
      vis(addPercentButton2, true)
      vis(potionButton2, true)
      vis(rmvPotionPercentButton2, true)
      vis(potionPercentBg2, true)
      vis(addPotionPercentButton2, true)
      vis(priority2, true)
      tip(priorityButton1,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      tip(priorityButton2,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      tip(priorityButton3,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    elseif currentPlayer:isSorcerer() then
      helper:setSize(tosize("295 465"))
      if healPanel then healPanel:setHeight(120) end
      if healingTargetModePanel then healingTargetModePanel:setVisible(true) end
      vis(friendHealingPanel, true)
      vis(granSioPanel, false)
      if masResPanel then masResPanel:setVisible(false) end
      if friendHealingPanel then
        local friendTitleLabel = friendHealingPanel:recursiveGetChildById("friendTitle")
        if friendTitleLabel then friendTitleLabel:setText(tr("Ultimate Healing Rune Helper")) end
      end
      vis(rmvPercentButton2, false)
      vis(spellPercentBg2, false)
      vis(addPercentButton2, false)
      vis(potionButton2, false)
      vis(rmvPotionPercentButton2, false)
      vis(potionPercentBg2, false)
      vis(addPotionPercentButton2, false)
      vis(priority2, false)
      tip(priorityButton1,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      tip(priorityButton2,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif currentPlayer:isDruid() then
      helper:setSize(tosize("295 800"))
      if healPanel then healPanel:setHeight(120) end
      if healingTargetModePanel then healingTargetModePanel:setVisible(true) end
      vis(friendHealingPanel, true)
      vis(granSioPanel, true)
      if masResPanel then masResPanel:setVisible(true) end
      if friendHealingPanel then
        local friendTitleLabel = friendHealingPanel:recursiveGetChildById("friendTitle")
        if friendTitleLabel then friendTitleLabel:setText(tr("Heal Friend Helper")) end
      end
      vis(rmvPercentButton2, false)
      vis(spellPercentBg2, false)
      vis(addPercentButton2, false)
      vis(potionButton2, false)
      vis(rmvPotionPercentButton2, false)
      vis(potionPercentBg2, false)
      vis(addPotionPercentButton2, false)
      vis(priority2, false)
      tip(priorityButton1,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      tip(priorityButton2,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    elseif currentPlayer:isMonk() then
      helper:setSize(tosize("295 520"))
      if healPanel then healPanel:setHeight(160) end
      if healingTargetModePanel then healingTargetModePanel:setVisible(true) end
      vis(friendHealingPanel, true)
      vis(granSioPanel, false)
      if masResPanel then masResPanel:setVisible(false) end
      if friendHealingPanel then
        local friendTitleLabel = friendHealingPanel:recursiveGetChildById("friendTitle")
        if friendTitleLabel then friendTitleLabel:setText(tr("Restore Balance Helper")) end
      end
      vis(rmvPercentButton2, true)
      vis(spellPercentBg2, true)
      vis(addPercentButton2, true)
      vis(potionButton2, true)
      vis(rmvPotionPercentButton2, true)
      vis(potionPercentBg2, true)
      vis(addPotionPercentButton2, true)
      vis(priority2, true)
      tip(priorityButton1,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      tip(priorityButton2,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
      tip(priorityButton3,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nClick on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    else
      helper:setSize(tosize("295 271"))
      if healPanel then healPanel:setHeight(120) end
      if healingTargetModePanel then healingTargetModePanel:setVisible(false) end
      vis(friendHealingPanel, false)
      vis(granSioPanel, false)
      if masResPanel then masResPanel:setVisible(false) end
      vis(rmvPercentButton2, false)
      vis(spellPercentBg2, false)
      vis(addPercentButton2, false)
      vis(potionButton2, false)
      vis(rmvPotionPercentButton2, false)
      vis(potionPercentBg2, false)
      vis(addPotionPercentButton2, false)
      vis(priority2, false)
      tip(priorityButton1,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
      tip(priorityButton2,
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.")
    end
      end)
      if not vocOk and g_logger then
        g_logger.error("[game_helper] loadMenu healing (vocation UI): " .. tostring(vocErr))
      end
    end
  elseif menuId == 'toolsMenu' then
    if healingPanel then healingPanel:hide() end
    if shooterPanel then shooterPanel:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if toolsPanelContainer then toolsPanelContainer:show(true) end

    -- Update vocation-specific panels visibility
    if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.updateVocationPanels then
      modules.game_helper.tools.updateVocationPanels()
    end

    helper:setSize(tosize("450 560"))
  elseif menuId == 'scriptsMenu' then
    if healingPanel then healingPanel:hide() end
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if shooterPanel then shooterPanel:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:show(true) end
    if modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.loadToUI then
      modules.game_helper.scripts.loadToUI()
    end
    helper:setSize(tosize("450 560"))
  elseif menuId == 'shooterMenu' then
    if healingPanel then healingPanel:hide() end
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:hide() end
    if shooterPanel then shooterPanel:show(true) end
    helper:setSize(tosize("575 735"))
    -- Update rules list when switching to shooter menu
    if modules.game_helper and modules.game_helper.magicShooter then
      modules.game_helper.magicShooter.updateUI()
    end
  elseif menuId == 'equipMenu' then
    helper:setSize(tosize("350 550"))
    if healingPanel then healingPanel:hide() end
    if shooterPanel then shooterPanel:hide() end
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:hide() end
    if equipPanelContainer then
      equipPanelContainer:show(true)
    end
    if cavebotPanel then cavebotPanel:hide() end
  elseif menuId == 'cavebotMenu' then
    if healingPanel then healingPanel:hide() end
    if shooterPanel then shooterPanel:hide() end
    if toolsPanelContainer then toolsPanelContainer:hide() end
    if scriptsPanelContainer then scriptsPanelContainer:hide() end
    if equipPanelContainer then equipPanelContainer:hide() end
    if cavebotPanel then cavebotPanel:show(true) end
    if cbLabel then cbLabel:show() end
    if cbBtn then cbBtn:show() end
    helper:setSize(tosize("430 550"))
    -- Migra scripts antigos e carrega lista de sessões do cavebot ao abrir a aba
    if cavebot then
      if cavebot.migrateOldScripts then
        cavebot.migrateOldScripts()
      end
      if cavebot.loadSessionList then
        cavebot.loadSessionList()
      end
    end
  end
end

--[[ Events ]] --
function assignTrainingSpell(button, isHaste, isUtito, isExetaRes, isAmpRes)
  local window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(window)
  end
  helper:hide()

  local windowHeader = "Assign Training Spell"
  if isHaste then
    windowHeader = "Assign Haste Spell"
  elseif isUtito then
    windowHeader = "Assign Utito Spell"
  elseif isExetaRes then
    windowHeader = "Assign Exeta Res Spell"
  elseif isAmpRes then
    windowHeader = "Assign Auto Amp Res Spell"
  end
  window:setText(windowHeader)

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then
    window:destroy()
    helper:show()
    return
  end

  local playerVocation = translateVocation(localPlayer:getVocation())
  local spells = modules.gamelib.SpellInfo and modules.gamelib.SpellInfo['Default'] or {}

  -- Get spell data from centralized module
  local allowedHasteForVoc = HelperSpellData.getHasteSpellsForVocation(playerVocation)
  local allowedUtitoForVoc = HelperSpellData.getUtitoWhiteList()[playerVocation] or {}
  local trainingHealSpellsSet = HelperSpellData.getTrainingHealSpellsSet()
  local allowedTrainingSpells = trainingHealSpellsSet[playerVocation] or {}
  local allowedExetaResIds = {}
  if isExetaRes and HelperSpellData.getSpellFilterByVocation then
    local vocSpells = HelperSpellData.getSpellFilterByVocation()[playerVocation] or {}
    for _, sid in ipairs(vocSpells) do
      allowedExetaResIds[sid] = true
    end
  end
  local allowedAmpResIds = {}
  if isAmpRes and HelperSpellData.getAmpResSpellsForVocation then
    local ampList = HelperSpellData.getAmpResSpellsForVocation(localPlayer:getVocation()) or {}
    for _, sid in ipairs(ampList) do
      allowedAmpResIds[sid] = true
    end
  end

  -- Manual selection (avoid RadioGroup getY errors)
  local selectedWidget = nil

  local addedSpells = 0
  for spellName, spellData in pairs(spells) do
    if not spellData then goto continue end

    local spellId = spellData.id
    local groups = (Spells.getGroupIds and Spells.getGroupIds(spellData)) or {}
    local vocs = (spellData and spellData.vocations) or {}

    if isHaste then
      -- Haste: show ID 6 or whitelist for vocation
      if not (spellId == 6 or table.contains(allowedHasteForVoc, spellId)) then
        goto continue
      end
    elseif isUtito then
      -- Utito: only show spells in the whitelist for this vocation
      if not table.contains(allowedUtitoForVoc, spellId) then
        goto continue
      end
    elseif isExetaRes then
      -- Exeta Res: vocation filter + attack/support group (1, 3, 4, 8) – exeta res (Challenge) is group 3
      if not allowedExetaResIds[spellId] then
        goto continue
      end
      local groupIds = (Spells.getGroupIds and Spells.getGroupIds(spellData)) or {}
      local hasAllowedGroup = false
      for _, g in ipairs(groupIds) do
        if g == 1 or g == 3 or g == 4 or g == 8 then hasAllowedGroup = true break end
      end
      if not hasAllowedGroup then
        goto continue
      end
    elseif isAmpRes then
      if not allowedAmpResIds[spellId] then
        goto continue
      end
    else
      -- Training: only show spells in the whitelist for this vocation
      if not allowedTrainingSpells[spellId] then
        goto continue
      end
    end

    addedSpells = addedSpells + 1
    local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)

    widget:setId(spellId)
    widget:setText(spellName .. "\n" .. spellData.words)
    widget.voc = vocs

    widget.source = _Helper.getSpellIconSource()
    widget.clip = _Helper.getSpellIconClip(spellData.id)
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    -- Manual select behavior
    widget.onClick = function(clickedWidget)
      if selectedWidget and not selectedWidget:isDestroyed() then
        selectedWidget:setChecked(false)
      end
      clickedWidget:setChecked(true)
      selectedWidget = clickedWidget
      window.contentPanel.preview:setText(clickedWidget:getText())
      window.contentPanel.preview.image:setImageSource(clickedWidget.source)
      window.contentPanel.preview.image:setImageClip(clickedWidget.clip)
    end

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if localPlayer:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end

    ::continue::
  end

  -- Order the spell list
  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  -- Manual OK handler
  local okFunc = function(destroy)
    if not selectedWidget then
      return
    end

    local spellIcon = selectedWidget.source
    local spellClip = selectedWidget.clip
    local spellId = selectedWidget:getId()
    local spellName = selectedWidget:getText():match("^(.-)\n")
    local spellWords = selectedWidget:getText():match("\n(.+)")

    local slotID = tonumber(button:getId():match("%d+"))
    if isHaste then
      local helperConfigLocal = _Helper.getHelperConfig and _Helper.getHelperConfig() or helperConfig
      helperConfigLocal.haste[slotID + 1].id = tonumber(spellId)
    elseif isUtito then
      local helperConfigLocal = _Helper.getHelperConfig and _Helper.getHelperConfig() or helperConfig
      helperConfigLocal.utito[slotID + 1].id = tonumber(spellId)
    elseif isExetaRes then
      if not helperConfig.exetaRes or not helperConfig.exetaRes[1] then
        helperConfig.exetaRes = { { id = 0, minCreatures = 1, creatureName = "", enabled = false } }
      end
      helperConfig.exetaRes[1].id = tonumber(spellId)
    elseif isAmpRes then
      if not helperConfig.ampRes or not helperConfig.ampRes[1] then
        helperConfig.ampRes = { { id = 0, minCreatures = 1, enabled = false } }
      end
      helperConfig.ampRes[1].id = tonumber(spellId)
    else
      helperConfig.training[1].id = tonumber(spellId)
      if helperConfig.training[1].percent == 0 then
        helperConfig.training[1].percent = 100
        updateTrainingPercent('spellTrainingButton0', helperConfig.training[1].percent)
      end
    end

    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    button:setImageSource(spellIcon)
    button:setImageClip(spellClip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spellWords)



    if destroy then
      helper:show(true)
      -- Limpar referências antes de destruir
      local spellListWidgets = window.contentPanel.spellList:getChildren()
      for _, w in ipairs(spellListWidgets) do
        w.onClick = nil
        w.source = nil
        w.clip = nil
        w.voc = nil
      end
      selectedWidget = nil
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show(true)
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    -- Limpar referências antes de destruir
    local spellListWidgets = window.contentPanel.spellList:getChildren()
    for _, w in ipairs(spellListWidgets) do
      w.onClick = nil
      w.source = nil
      w.clip = nil
      w.voc = nil
    end
    selectedWidget = nil
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

local PRESET_NAME_MAX_LEN = 7
local function invalidPresetName(name, excludeName)
  if helperConfig.shooterProfiles[name] and name ~= excludeName then
    return true, "There is already a preset with this name."
  end
  if g_helperCore and g_helperCore.validatePresetNameRules then
    local invalid, msg = g_helperCore.validatePresetNameRules(name, PRESET_NAME_MAX_LEN)
    if invalid then return true, msg end
  else
    if name:len() == 0 then return true, "The name cannot be empty." end
    if name:len() > PRESET_NAME_MAX_LEN then return true, "The name cannot be longer than 7 characters." end
    if name:match("[^%w]") then return true, "The name cannot contain special characters or spaces." end
  end
  return false
end

function sendRenameOrAddWindow(isRename)
  local radio = UIRadioGroup.create()
  window = g_ui.loadUI('styles/shooterPreset', g_ui.getRootWidget())
  if not window then
    return true
  end

  if isRename then
    window:setText("Rename shooter preset")
    window.contentPanel.target:setText(helperConfig.selectedShooterProfile)
  else
    window:setText("Add shooter preset")
    window.contentPanel.target:setText("")
  end


  local options = presetsPanel:recursiveGetChildById('presets')

  window:show(true)
  window:raise()
  window:focus()
  window.contentPanel.target:focus()
  helper:hide()

  local onWrite = function()
    local warning = window.contentPanel.warning
    local text = window.contentPanel.target:getText()
    -- When renaming, exclude current name from duplicate check
    local excludeName = isRename and helperConfig.selectedShooterProfile or nil
    local invalid, message = invalidPresetName(text, excludeName)
    if invalid then
      warning:setVisible(true)
      warning:setTooltip(message)
    elseif not invalid and warning:isVisible() then
      warning:setVisible(false)
      warning:setTooltip('')
    end
  end

  local renameConfirm = function()
    local input = window.contentPanel.target:getText()
    local oldProfileName = helperConfig.selectedShooterProfile

    -- No change needed
    if input == oldProfileName then
      helper:show()
      window:destroy()
      return
    end

    -- Validate new name (exclude current name from duplicate check)
    if invalidPresetName(input, oldProfileName) then
      return
    end

    local profileConfig = helperConfig.shooterProfiles[oldProfileName]
    if profileConfig then
      helperConfig.shooterProfiles[input] = profileConfig
      helperConfig.selectedShooterProfile = input
      options:addOption(input)
      options:setCurrentOption(input)
      helperConfig.shooterProfiles[oldProfileName] = nil
      options:removeOption(oldProfileName)
    end

    helper:show()
    window:destroy()
  end

  local addConfirm = function()
    local input = window.contentPanel.target:getText()

    -- Validate name (includes duplicate check)
    if invalidPresetName(input) then
      return
    end

    local default = deepCopy(defaultShooterProfile)
    helperConfig.shooterProfiles[input] = default

    options:addOption(input)
    options:setCurrentOption(input)

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
    window.contentPanel.onEnter = function() renameConfirm() end
  else
    window.contentPanel.okButton.onClick = function() addConfirm() end
    window.contentPanel.onEnter = function() addConfirm() end
  end
end

function assignSpell(button, groupName, groups, tableToAssign)
  local radio = UIRadioGroup.create()
  local window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(window)
  end
  helper:hide()

  window:setText("Assign " .. groupName .. " Spell")

  local profile = getShooterProfile()
  local playerVocation = translateVocation(player:getVocation())

  -- Get spell data from centralized module
  local spellFilterByVocation = HelperSpellData.getSpellFilterByVocation()
  local healingSpellFilter = HelperSpellData.getHealingSpellFilter()

  -- Detecta se é janela de healing (grupo 2)
  local isHealingWindow = false
  for _, group in ipairs(groups) do
    if group == 2 then
      isHealingWindow = true
      break
    end
  end

  -- Get allowed spell IDs for this vocation
  local allowedSpellIds = spellFilterByVocation[playerVocation] or {}
  local allowedSpellIdSet = {}

  if isHealingWindow then
    -- Para healing spells, usar o filtro específico de cura
    allowedSpellIdSet = HelperSpellData.getHealingSpellsForVocation(playerVocation)
  else
    -- Para attack spells, usar o filtro geral por vocação
    for _, id in ipairs(allowedSpellIds) do
      allowedSpellIdSet[id] = true
    end
  end

  -- Table to hold widgets before adding to radio group
  local spellWidgets = {}

  -- Get spells from SpellInfo
  local spells = modules.gamelib.SpellInfo['Default']
  for spellName, spellData in pairs(spells) do
    local groupIds = Spells.getGroupIds(spellData)

    -- Check if spell is in correct group
    if not containsAnyGroup(groupIds, groups) then
      goto continue_spell
    end

    -- Check if spell ID is allowed for this vocation
    if not allowedSpellIdSet[spellData.id] then
      goto continue_spell
    end

    if HelperSpellData.getIgnoredSpellsIds()[spellData.id] then
      goto continue_spell
    end

    -- Do not filter by level; show all and mark unmet level

    local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)

    -- Store widget for later, don't add to radio yet
    table.insert(spellWidgets, widget)
    widget:setId(spellData.id)
    widget:setText(spellName .. "\n" .. spellData.words)
    widget.voc = spellData.vocations

    widget.source = _Helper.getSpellIconSource()
    widget.clip = _Helper.getSpellIconClip(spellData.id)
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if player:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end

    ::continue_spell::
  end

  -- sort alphabetically
  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  -- Manual selection system instead of radio group to avoid getY() errors
  local selectedWidget = nil

  for _, widget in ipairs(spellWidgets) do
    if widget and not widget:isDestroyed() then
      widget.onClick = function(clickedWidget)
        -- Deselect previous
        if selectedWidget then
          selectedWidget:setChecked(false)
        end
        -- Select new
        clickedWidget:setChecked(true)
        selectedWidget = clickedWidget
        -- Update preview
        window.contentPanel.preview:setText(clickedWidget:getText())
        window.contentPanel.preview.image:setImageSource(clickedWidget.source)
        window.contentPanel.preview.image:setImageClip(clickedWidget.clip)
      end
    end
  end

  -- Don't use radio group at all to avoid errors

  window:recursiveGetChildById('tick'):setChecked(true)
  window:recursiveGetChildById('tick'):setEnabled(false)

  local okFunc = function(destroy, profile)
    if not selectedWidget then
      modules.game_textmessage.displayGameMessage("Please select a spell first!")
      return
    end

    local profile = getShooterProfile()
    local spellIcon = selectedWidget.source
    local spellClip = selectedWidget.clip
    local spellId = selectedWidget:getId()
    local spellName = selectedWidget:getText():match("^(.-)\n")
    local spellWords = selectedWidget:getText():match("\n(.+)")

    local slotID = tonumber(button:getId():match("%d+"))
    if button:getId():find("attackSpellButton") then
      profile.spells[slotID + 1].id = tonumber(spellId)
      profile.spells[slotID + 1].name = spellName
    else
      tableToAssign[slotID + 1].id = tonumber(spellId)
      tableToAssign[slotID + 1].name = spellName
    end

    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    button:setImageSource(spellIcon)
    button:setImageClip(spellClip)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellName .. "\nWords: " .. spellWords)

    if button:getId():find("attackSpellButton") then
      local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotID)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotID)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotID)
      local spell = Spells.getSpellByClientId(tonumber(spellId))
      if spell then
        if table.contains(bothCastTypeSpells, spell.id) then -- divine grenade self cast
          if not selfCast then
            selfCast = g_ui.createWidget('CheckBox', creaturesMin:getParent())
            local style = {
              ["width"] = 12,
              ["anchors.top"] = "countMinCreature" .. slotID .. ".top",
              ["anchors.left"] = "countMinCreature" .. slotID .. ".right",
              ["margin-top"] = 6,
              ["margin-left"] = 5
            }
            selfCast:mergeStyle(style)
            selfCast:setId('selfCast' .. slotID)
            selfCast:setTooltip('Cast on yourself')
            selfCast:setVisible(true)
            selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
          end
        end
        if selfCast and not table.contains(bothCastTypeSpells, spell.id) then
          profile.spells[slotID + 1].selfCast = false
          selfCast:destroy()
        end
        if (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
          profile.spells[slotID + 1].creatures = 1
          creaturesMin:setCurrentOption("1+")
          creaturesMin:disable()
          if forceCast then
            forceCast:setChecked(profile.spells[slotID + 1].forceCast)
            forceCast:setVisible(true)
          end
        else
          creaturesMin:enable()
          if forceCast then
            forceCast:setChecked(false)
            forceCast:setVisible(false)
            profile.spells[slotID + 1].forceCast = false
          end
        end
      end
    end
    -- Persist configuration after assignment

    if destroy then
      helper:show()
      -- Limpar referências antes de destruir
      for _, w in ipairs(spellWidgets) do
        w.onClick = nil
        w.source = nil
        w.clip = nil
        w.voc = nil
      end
      spellWidgets = {}
      selectedWidget = nil
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show()
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    -- Limpar referências antes de destruir
    for _, w in ipairs(spellWidgets) do
      w.onClick = nil
      w.source = nil
      w.clip = nil
      w.voc = nil
    end
    spellWidgets = {}
    selectedWidget = nil
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

function assignRune(button, groupName, groups, tableToAssign)
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignRune(self, mousePosition, mouseButton, button)
  end
end

function onAssignRune(self, mousePosition, mouseButton, button)
  mouseGrabberWidget:ungrabMouse()
  helper:show()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local runeId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      runeId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        runeId = topUseThing:getId()
      end
    end
  end

  local rune = Spells.getRuneSpellByItem(runeId)
  if not rune and CustomRuneIds then rune = CustomRuneIds[tonumber(runeId) or runeId] end
  if rune and rune.group == 1 then
    if rune.vocations and not canUseByServerVoc(rune.vocations, player:getVocation()) then
      modules.game_textmessage.displayFailureMessage(tr('Your vocation can not use this rune.'))
      return true
    end
    updateRuneButton(button, runeId, rune)
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid rune!'))
  end
end

-- Legacy function - kept for backward compatibility
-- New system uses magic_shooter_panel.lua
function updateRuneButton(button, runeId, rune)
  -- New unified panel doesn't use this function
  -- Just log and return
  safeLog("debug", "updateRuneButton called - legacy function, use magic_shooter_panel instead")
end

-- Function for Magic Shooter Panel to select spells
function assignSpellForMagicShooter(button, callback)
  local radio = UIRadioGroup.create()
  local window = g_ui.loadUI('styles/spell', g_ui.getRootWidget())
  if not window then
    return true
  end

  window:show(true)
  window:raise()
  window:focus()
  if g_client and g_client.setInputLockWidget then
    g_client.setInputLockWidget(window)
  end
  helper:hide()

  window:setText("Select Attack Spell")

  local profile = getShooterProfile()
  local playerVocation = translateVocation(player:getVocation())
  local groups = { 1, 4, 8 } -- Attack groups

  local spellFilterByVocation = HelperSpellData.getSpellFilterByVocation()
  local allowedSpellIds = spellFilterByVocation[playerVocation] or {}
  local allowedSpellIdSet = {}
  for _, id in ipairs(allowedSpellIds) do
    allowedSpellIdSet[id] = true
  end

  local spellWidgets = {}
  local spells = modules.gamelib.SpellInfo['Default']
  for spellName, spellData in pairs(spells) do
    local groupIds = Spells.getGroupIds(spellData)
    local isAttackGroup = containsAnyGroup(groupIds, groups)
    local isSupportAllowed = HelperSpellData.isSupportSpellAllowed(spellData.id, playerVocation)

    -- Deve estar em grupo de ataque OU na whitelist de suporte
    if not isAttackGroup and not isSupportAllowed then
      goto continue_spell
    end
    if not allowedSpellIdSet[spellData.id] then
      goto continue_spell
    end
    if HelperSpellData.getIgnoredSpellsIds()[spellData.id] then
      goto continue_spell
    end

    local widget = g_ui.createWidget('SpellPreview', window.contentPanel.spellList)
    table.insert(spellWidgets, widget)
    widget:setId(spellData.id)
    widget:setText(spellName .. "\n" .. spellData.words)
    widget.voc = spellData.vocations

    widget.source = _Helper.getSpellIconSource()
    widget.clip = _Helper.getSpellIconClip(spellData.id)
    widget.image:setImageSource(widget.source)
    widget.image:setImageClip(widget.clip)

    if spellData.level then
      widget.levelLabel:setVisible(true)
      widget.levelLabel:setText(string.format("Level: %d", spellData.level))
      if player:getLevel() < spellData.level then
        widget.image.gray:setVisible(true)
      end
    end

    local primaryGroup = Spells.getPrimaryGroup(spellData)
    if primaryGroup ~= -1 then
      local offSet = 1
      if primaryGroup == 2 then
        offSet = (23 * (primaryGroup - 1))
      elseif primaryGroup == 3 then
        offSet = (23 * (primaryGroup - 1)) - 1
      end
      widget.imageGroup:setImageClip(offSet .. " 25 20 20")
      widget.imageGroup:setVisible(true)
    end

    ::continue_spell::
  end

  local widgets = window.contentPanel.spellList:getChildren()
  table.sort(widgets, function(a, b) return a:getText() < b:getText() end)
  for i, widget in ipairs(widgets) do
    window.contentPanel.spellList:moveChildToIndex(widget, i)
  end

  local selectedWidget = nil
  for _, widget in ipairs(spellWidgets) do
    if widget and not widget:isDestroyed() then
      widget.onClick = function(clickedWidget)
        if selectedWidget then
          selectedWidget:setChecked(false)
        end
        clickedWidget:setChecked(true)
        selectedWidget = clickedWidget
        window.contentPanel.preview:setText(clickedWidget:getText())
        window.contentPanel.preview.image:setImageSource(clickedWidget.source)
        window.contentPanel.preview.image:setImageClip(clickedWidget.clip)
      end
    end
  end

  window:recursiveGetChildById('tick'):setChecked(true)
  window:recursiveGetChildById('tick'):setEnabled(false)

  local okFunc = function(destroy)
    if not selectedWidget then
      modules.game_textmessage.displayGameMessage("Please select a spell first!")
      return
    end

    local spellId = selectedWidget:getId()
    local spellName = selectedWidget:getText():match("^(.-)\n")
    local spellWords = selectedWidget:getText():match("\n(.+)")

    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end

    -- Call the callback with spell data
    if callback then
      callback({
        id = tonumber(spellId),
        name = spellName,
        words = spellWords,
        source = selectedWidget.source,
        clip = selectedWidget.clip
      })
    end

    if destroy then
      helper:show()
      for _, w in ipairs(spellWidgets) do
        w.onClick = nil
        w.source = nil
        w.clip = nil
        w.voc = nil
      end
      spellWidgets = {}
      selectedWidget = nil
      window:destroy()
    end
  end

  local cancelFunc = function()
    helper:show()
    if g_client and g_client.setInputLockWidget then
      g_client.setInputLockWidget(nil)
    end
    for _, w in ipairs(spellWidgets) do
      w.onClick = nil
      w.source = nil
      w.clip = nil
      w.voc = nil
    end
    spellWidgets = {}
    selectedWidget = nil
    window:destroy()
  end

  window.contentPanel.buttonOk.onClick = function() okFunc(true) end
  window.contentPanel.buttonApply.onClick = function() okFunc(false) end
  window.contentPanel.buttonClose.onClick = cancelFunc
  window.contentPanel.onEnter = function() okFunc(true) end
  window.onEscape = cancelFunc
end

function getPotionInfoById(itemId)
  local potionWhitelist = HelperSpellData.getPotionWhitelist()
  for _, potion in pairs(potionWhitelist) do
    if itemId == potion.id then
      return true, potion.name
    end
  end
  return false, "Unknown Potion"
end

function isHealthPotion(potionId)
  local potionWhitelist = HelperSpellData.getPotionWhitelist()
  for _, potion in ipairs(potionWhitelist) do
    if potion.id == potionId and potion.type == "health" then
      return true
    end
  end
  return false
end

function isManaPotion(potionId)
  local potionWhitelist = HelperSpellData.getPotionWhitelist()
  for _, potion in ipairs(potionWhitelist) do
    if potion.id == potionId and potion.type == "mana" then
      return true
    end
  end
  return false
end

function usePotion(potionId)
  local player = g_game.getLocalPlayer()
  if not player or not potionId or potionId == 0 then
    return false
  end

  local cooldown = getSpellCooldown(potionConfig.id)
  if cooldown > g_clock.millis() then
    return false
  end


  if g_helperCore and g_helperCore.isMultiUseOnCooldown and g_helperCore.isMultiUseOnCooldown() then
    return false
  end

  local potionCount = player:getInventoryCount(potionId, 0)
  if potionCount and potionCount > 0 then
    safeDoThing(false)
    g_game.useInventoryItemWith(potionId, player, 0, true)
    safeDoThing(true)
    if g_helperCore and g_helperCore.setSpellCooldown then
      g_helperCore.setSpellCooldown(potionConfig.id, potionConfig.exhaustion)
    else
      spellsCooldown[potionConfig.id] = g_clock.millis() + potionConfig.exhaustion
    end
    return true
  end

  return false
end

function assignPotionEvent(button)
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignPotion(self, mousePosition, mouseButton, button)
  end
end

function onAssignPotion(self, mousePosition, mouseButton, button)
  mouseGrabberWidget:ungrabMouse()
  helper:show()
  g_mouse.popCursor('target')
  mouseGrabberWidget.onMouseRelease = nil

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    return true
  end

  local clickedWidget = rootWidget:recursiveGetChildByPos(mousePosition, false)
  if not clickedWidget then
    return true
  end

  local potionId = 0
  if clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
    local item = clickedWidget:getItem()
    if item then
      potionId = item:getId()
    end
  elseif clickedWidget:getClassName() == 'UIGameMap' then
    local tile = clickedWidget:getTile(mousePosition)
    if tile then
      local topUseThing = tile:getTopUseThing()
      if topUseThing then
        potionId = topUseThing:getId()
      end
    end
  end

  local isPotion, potionName = getPotionInfoById(potionId)
  if isPotion then
    updatePotionButton(button, potionId, potionName)
  else
    modules.game_textmessage.displayFailureMessage(tr('Invalid potion!'))
  end
end

function updatePotionButton(button, potionId, potionName)
  button:setImageSource('/images/ui/item')

  if not button:getChildById('potionItem') then
    local itemWidget = g_ui.createWidget('PotionItem', button)
    itemWidget:setId('potionItem')
  end

  local itemWidget = button:getChildById('potionItem')
  itemWidget:setItemId(potionId)
  itemWidget:setTooltip(potionName)

  local buttonId = button:getId()
  local slotID = tonumber(buttonId:match("%d+"))
  helperConfig.potions[slotID + 1].id = potionId
  helperConfig.potions[slotID + 1].percent = helperConfig.potions[slotID + 1].percent

  local priorityButton = healingPanel:recursiveGetChildById("priority" .. slotID)

  if isManaPotion(potionId) then
    helperConfig.potions[slotID + 1].priority = 2
    priorityButton:setImageSource("/images/ui/checkboxcircle")
    priorityButton:setImageColor("#0066ff")
    priorityButton:setTooltip("This potion is healing mana...")
  elseif isHealthPotion(potionId) then
    helperConfig.potions[slotID + 1].priority = 1
    priorityButton:setImageSource("/images/ui/checkboxcircle")
    priorityButton:setImageColor("#d94a3a")
    priorityButton:setTooltip("This potion is healing health...")
  else
    helperConfig.potions[slotID + 1].priority = 0
    priorityButton:setImageSource("/images/ui/checkbox")
    priorityButton:setImageColor("#ffffff")
    priorityButton:setTooltip("No potion selected")
  end
  rebuildHealingCache()
end

function updateButton(button)
  local profile = getShooterProfile()
  local index = tonumber(button:getId():match("%d+"))
  local buttonId = button:getId()

  button.onMousePress = function(self, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
      local menu = g_ui.createWidget('PopupMenu')
      menu:setGameMenu(true)
      if buttonId:find("runeShooterButton") then
        if profile.runes[index + 1].id > 0 then
          menu:addOption(tr('Edit Rune'), function() assignRune(button) end)
          menu:addOption(tr('Remove'), function() removeAction("rune", button) end)
        else
          menu:addOption(tr('Assign Rune'), function() assignRune(button) end)
        end
      elseif buttonId:find("attackSpellButton") then
        if profile.spells[index + 1].id > 0 then
          menu:addOption(tr('Edit Spell'), function() assignSpell(button, "Aggressive", { 1, 4, 8 }, profile.spells) end)
          menu:addOption(tr('Remove'), function() removeAction("shooter", button) end)
        else
          menu:addOption(tr('Assign Spell'),
            function() assignSpell(button, "Aggressive", { 1, 4, 8 }, profile.spells) end)
        end
      elseif buttonId:find("spellButton") then
        if helperConfig.spells[index + 1].id > 0 then
          menu:addOption(tr('Edit Spell'), function() assignSpell(button, "Healing", { 2 }, helperConfig.spells) end)
          menu:addOption(tr('Remove'), function() removeAction("spell", button) end)
        else
          menu:addOption(tr('Assign Spell'), function() assignSpell(button, "Healing", { 2 }, helperConfig.spells) end)
        end
      elseif buttonId:find("potionButton") then
        if helperConfig.potions[index + 1].id > 0 then
          menu:addOption(tr('Edit Potion'), function() assignPotionEvent(button) end)
          menu:addOption(tr('Remove'), function() removeAction("potion", button) end)
        else
          menu:addOption(tr('Assign Potion'), function() assignPotionEvent(button) end)
        end
      elseif buttonId:find("spellTrainingButton") then
        if helperConfig.training[index + 1].id > 0 then
          menu:addOption(tr('Edit Training Spell'), function() assignTrainingSpell(button) end)
          menu:addOption(tr('Remove'), function() removeAction("training", button) end)
        else
          menu:addOption(tr('Assign Training Spell'), function() assignTrainingSpell(button) end)
        end
      elseif buttonId:find("hasteButton") then
        if helperConfig.haste[index + 1].id > 0 then
          menu:addOption(tr('Edit Haste Spell'), function() assignTrainingSpell(button, true) end)
          menu:addOption(tr('Remove'), function() removeAction("haste", button) end)
        else
          menu:addOption(tr('Assign Haste Spell'), function() assignTrainingSpell(button, true) end)
        end
      elseif buttonId:find("autoTrainingItem") then
        if not button.potionItem or button.potionItem:getItemId() == 0 then
          menu:addOption(tr('Select exercise weapon'), function() assignExerciseEvent(button) end)
        else
          menu:addOption(tr('Remove'), function() removeAction("exercise", button) end)
        end
      end

      menu:display(mousePos)
      return true
    end
    return false
  end
end

function onPartyMembersChange()
  -- This function is called when party members change
  -- We can update party healing settings here if needed
end

-- Vocation-based healing: sem listas de party na UI; lógica em onFriendHealing / onPartyMemberHealthChangeHelper
function updatePartyMembersHealth(cachedSpectators)
end

eventTable.updatePartyHealth.action = updatePartyMembersHealth

function onPartyDataClear()
end

function onPartyDataUpdate(members)
  -- A função updatePartyMembersHealth agora cuida de tudo
  -- Esta função é mantida para compatibilidade
  updatePartyMembersHealth()
end

function resetPartyPanel()
end

function onAddPartyMember(self)
  return true
end

function onAddPartyGranSioMember(self)
  return true
end

function manageSioSettings(activate, index)
end

function manageGranSioSettings(activate, index)
end

function onEnableSio(button, checked)
end

function onEnableGranSio(button, checked)
end

-- Wrapper function para OTUI (modulo sandboxed)
function onEnableTraining(buttonId, checked)
  _Helper.ManaTraining.toggle(buttonId, checked)
end

-- Bot functions
function updateHealingPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  buttonIndex = tonumber(buttonIndex)
  local config = helperConfig.spells[buttonIndex + 1]
  if string.find(buttonId, "add") then
    if config.percent + 1 > 99 then
      healingPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent + 1
    local label = healingPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  elseif string.find(buttonId, "rmv") then
    if config.percent - 1 < 1 then
      healingPanel:recursiveGetChildById("rmvPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("addPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent - 1
    local label = healingPanel:recursiveGetChildById("spellPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  end

  cachedSpells = table.copy(helperConfig.spells)
  table.sort(cachedSpells, function(a, b) return a.percent < b.percent end)

  if rebuildHealingCache then rebuildHealingCache() end
end

-- HELPER MAGIC SHOOTER: Wrapper functions para OTUI compatibilidade
function updateMagicShooterPercent(buttonId, newPercent)
  _Helper.MagicShooter.updatePercent(buttonId, newPercent)
end

function updateRuneShooterCreatures(name, index, creatures)
  _Helper.MagicShooter.updateRuneCreatures(name, index, creatures)
end

function updateRuneShooterPriority(index, priority)
  _Helper.MagicShooter.updateRunePriority(index, priority)
end

function updatePotionPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  if not buttonIndex then
    return
  end

  buttonIndex = tonumber(buttonIndex)
  local config = helperConfig.potions[buttonIndex + 1]
  if string.find(buttonId, "add") then
    if config.percent + 1 > 99 then
      healingPanel:recursiveGetChildById("addPotionPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("rmvPotionPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent + 1
    local label = healingPanel:recursiveGetChildById("potionPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  elseif string.find(buttonId, "rmv") then
    if config.percent - 1 < 1 then
      healingPanel:recursiveGetChildById("rmvPotionPercentButton" .. buttonIndex):setEnabled(false)
      return
    end

    healingPanel:recursiveGetChildById("addPotionPercentButton" .. buttonIndex):setEnabled(true)
    config.percent = config.percent - 1
    local label = healingPanel:recursiveGetChildById("potionPercentLabel" .. buttonIndex)
    label:setText(config.percent .. "%")
  end

  if rebuildHealingCache then rebuildHealingCache() end
end

function castHealingSpell(spellData)
  local spellId = spellData and spellData.id or 0
  if spellId == 0 then
    return false
  end

  -- Try to get spell by ID first (spell.id), then by clientId
  local spell = getSpellDataById(spellId)

  -- If not found by ID, try by clientId
  if not spell then
    spell = getSpellByClientId(tonumber(spellId))
  end

  if not spell then
    return false
  end

  -- Check if spell has words (required for casting)
  if not spell.words or spell.words == "" then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  local buffDuration = HelperSpellData.getBuffDuration and HelperSpellData.getBuffDuration(spell.id) or 0
  if buffDuration > 0 and healingActiveBuffs[spell.id] and healingActiveBuffs[spell.id] > g_clock.millis() then
    return false
  end

  local currentPlayer = getPlayer()
  if not currentPlayer then
    return false
  end

  -- Check if player has enough mana for the spell
  if spell.mana and spell.mana > 0 then
    local playerMana = currentPlayer:getMana()
    if playerMana < spell.mana then
      return false
    end
  end

  -- Check soul requirement
  if spell.soul and spell.soul > 0 then
    local playerSoul = currentPlayer:getSoul()
    if playerSoul < spell.soul then
      return false
    end

    if spell.source and not hasItemInBackpack(spell.source) then
      return false
    end
  end

  -- Execute the spell
  safeDoThing(false)
  g_game.talk(spell.words, true)
  safeDoThing(true)

  if buffDuration > 0 then
    healingActiveBuffs[spell.id] = g_clock.millis() + buffDuration
  end

  return true
end

-- Special foods (HP/mana consumables with separate cooldown from spells/potions)
function sortSpecialFoodsByPriority(foods)
  local groups = {}
  for _, food in ipairs(foods) do
    local p = food.priority or 99
    if not groups[p] then groups[p] = {} end
    table.insert(groups[p], food)
  end
  local priorities = {}
  for p, _ in pairs(groups) do
    table.insert(priorities, p)
  end
  table.sort(priorities)
  local result = {}
  for _, p in ipairs(priorities) do
    local group = groups[p]
    for i = #group, 2, -1 do
      local j = math.random(1, i)
      group[i], group[j] = group[j], group[i]
    end
    for _, food in ipairs(group) do
      table.insert(result, food)
    end
  end
  return result
end

function useSpecialFood(foodId)
  local pl = g_game.getLocalPlayer()
  if not pl or not foodId or foodId == 0 then
    return false
  end

  local cd = getSpellCooldown(specialFoodConfig.id)
  if cd > g_clock.millis() then
    return false
  end

  if g_helperCore and g_helperCore.isMultiUseOnCooldown and g_helperCore.isMultiUseOnCooldown() then
    return false
  end

  local foodCount = pl:getInventoryCount(foodId, 0)
  if foodCount and foodCount > 0 then
    safeDoThing(false)
    g_game.useInventoryItem(foodId)
    safeDoThing(true)
    local now = g_clock.millis()
    if g_helperCore and g_helperCore.setSpellCooldown then
      g_helperCore.setSpellCooldown(specialFoodConfig.id, specialFoodConfig.exhaustion)
    else
      spellsCooldown[specialFoodConfig.id] = now + specialFoodConfig.exhaustion
    end
    specialFoodLocalCooldowns[foodId] = now + (15 * 60 * 1000)
    return true
  end
  return false
end

function isSpecialFoodOnCooldown(foodId)
  local localExpires = specialFoodLocalCooldowns[foodId]
  if localExpires and g_clock.millis() < localExpires then
    return true
  end
  if TimersAnalyser and TimersAnalyser.timers then
    for _, timer in ipairs(TimersAnalyser.timers) do
      if timer.keyType == 1 and timer.key == foodId and timer.category == 3 then
        local elapsed = os.time() - (timer.receivedAt or 0)
        local remaining = (timer.remaining or 0) - elapsed
        if remaining > 0 then return true end
      end
    end
  end
  return false
end

function checkHealthHealing()
  local localPlayer = g_game.getLocalPlayer()
  if not helperAutomaticFunctionsEnabled or not localPlayer then
    return false
  end

  local health, maxHealth = localPlayer:getHealth(), localPlayer:getMaxHealth()
  local healthPercent = (health / maxHealth) * 100

  local usedSomething = false

  if helperConfig.specialFoods and helperConfig.specialFoods.hp then
    local sortedHpFoods = sortSpecialFoodsByPriority(helperConfig.specialFoods.hp)
    for _, food in ipairs(sortedHpFoods) do
      if food.enabled and food.id ~= 0 and healthPercent <= food.percent then
        if not isSpecialFoodOnCooldown(food.id) and hasItemInBackpack(food.id) then
          if useSpecialFood(food.id) then
            usedSomething = true
            break
          end
        end
      end
    end
  end

  health = localPlayer:getHealth()
  healthPercent = (health / maxHealth) * 100

  -- 1. Tentar usar spell primeiro (prioridade sobre potion)
  -- Use cached spells list
  for _, spell in ipairs(cachedPrioritizedSpells) do
    if HelperSpellData.getIgnoredSpellsIds()[spell.id] then
      goto skipSpell
    end

    if spell.id ~= 0 and healthPercent <= spell.percent then
      local success = castHealingSpell(spell)
      if success then
        usedSomething = true
        break -- Usou uma spell, para de tentar outras spells
      end
    end

    ::skipSpell::
  end

  -- 2. Tentar usar potion (cooldown independente da spell)
  -- Recalcular vida atual caso a spell tenha curado
  health = localPlayer:getHealth()
  healthPercent = (health / maxHealth) * 100

  -- Use cached health potions list
  for _, potion in ipairs(cachedPrioritizedHealthPotions) do
    local hasItem = hasItemInBackpack(potion.id)
    local shouldUse = healthPercent <= potion.percent
    if hasItem and shouldUse then
      local potionUsed = usePotion(potion.id)
      if potionUsed then
        usedSomething = true
        break -- Usou uma potion, para de tentar outras potions
      end
    end
  end

  return usedSomething
end

eventTable.checkHealthHealing.action = checkHealthHealing

--safeLog("info", "Helper: checkHealthHealing action assigned to eventTable")

function hasItemInBackpack(potionId)
  local currentPlayer = getPlayer()
  return currentPlayer and type(currentPlayer) == "userdata" and currentPlayer:getInventoryCount(potionId, 0) > 0
end

function checkManaHealing(mana, maxMana)
  if not helperAutomaticFunctionsEnabled then
    return
  end

  local manaPercent = (mana / maxMana) * 100

  local startHealthPotionPriority = false
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer then
    -- Quick check: if any health potion condition is met, we might need to prioritize health (skip mana for now?)
    -- The original logic seemed to check if a health potion *should* be used based on health,
    -- and if so, it skips mana check? That seems to be the intent of "healthPotionPriority".
    -- Let's use the cached health potions to check this efficiently.
    local currentHealthPercent = (localPlayer:getHealth() / localPlayer:getMaxHealth()) * 100
    for _, potion in ipairs(cachedPrioritizedHealthPotions) do
      -- Only check if we actually have it (optimization: maybe skip hasItem check here if we want pure speed?)
      -- Original code checked hasItemInBackpack.
      if hasItemInBackpack(potion.id) and currentHealthPercent <= potion.percent then
        startHealthPotionPriority = true
        break
      end
    end
  end

  if startHealthPotionPriority then
    return
  end

  if helperConfig.specialFoods and helperConfig.specialFoods.mana then
    local sortedManaFoods = sortSpecialFoodsByPriority(helperConfig.specialFoods.mana)
    for _, food in ipairs(sortedManaFoods) do
      if food.enabled and food.id ~= 0 and manaPercent <= food.percent then
        if not isSpecialFoodOnCooldown(food.id) and hasItemInBackpack(food.id) then
          if useSpecialFood(food.id) then
            return
          end
        end
      end
    end
  end

  -- Use cached mana potions list
  for _, potion in ipairs(cachedPrioritizedManaPotions) do
    local hasItem = hasItemInBackpack(potion.id)
    local shouldUse = manaPercent <= potion.percent
    if hasItem and shouldUse then
      usePotion(potion.id)
      return -- Exit after using one mana potion
    end
  end
end

-- Event handlers para reação instantânea a mudanças de vida/mana
function onPlayerHealthChange(player, health, maxHealth, oldHealth)
  if not helperAutomaticFunctionsEnabled then return end
  if isTransitioningPlayer then return end

  -- Só reagir quando a vida diminuir (tomou dano)
  if oldHealth and health < oldHealth then
    checkHealthHealing()
  end
end

function rebuildHealingCache()
  -- Rebuild Spells Cache
  cachedPrioritizedSpells = {}
  for _, spell in pairs(helperConfig.spells) do
    table.insert(cachedPrioritizedSpells, spell)
  end
  table.sort(cachedPrioritizedSpells, function(a, b)
    if a.percent == b.percent then
      return a.id < b.id
    else
      return a.percent < b.percent
    end
  end)

  -- Rebuild Potions Cache
  cachedPrioritizedHealthPotions = {}
  cachedPrioritizedManaPotions = {}

  -- Pre-sort potions list first to ensure consistent ordering when splitting
  local sortedPotions = {}
  for _, potion in pairs(helperConfig.potions) do
    if potion.id ~= 0 then
      table.insert(sortedPotions, potion)
    end
  end
  table.sort(sortedPotions, function(a, b)
    if a.percent == b.percent then
      return a.priority < b.priority
    else
      return a.percent < b.percent
    end
  end)

  for _, potion in ipairs(sortedPotions) do
    if potion.priority == 1 or isHealthPotion(potion.id) then
      table.insert(cachedPrioritizedHealthPotions, potion)
    end

    if potion.priority == 2 or isManaPotion(potion.id) then
      table.insert(cachedPrioritizedManaPotions, potion)
    end
  end

  -- Mana potions are also sorted by percent in original code
  table.sort(cachedPrioritizedManaPotions, function(a, b)
    return a.percent < b.percent
  end)
end

function onPlayerManaChange(player, mana, maxMana, oldMana)
  if not helperAutomaticFunctionsEnabled then return end
  if isTransitioningPlayer then return end

  -- Só reagir quando a mana diminuir (usou spell/foi drenado)
  if oldMana and mana < oldMana then
    checkManaHealing(mana, maxMana)
  end
end

-- Callback para mudanca de estados do player (usado pelo Auto Haste)
function onPlayerStatesChange(player, states, oldStates)
  if not helperAutomaticFunctionsEnabled then return end
  if isTransitioningPlayer then return end
  if not player then return end

  -- Verificar se perdeu o estado de Haste
  local hadHaste = oldStates and bit.band(oldStates, PlayerStates.Haste) ~= 0
  local hasHaste = states and bit.band(states, PlayerStates.Haste) ~= 0

  if hadHaste and not hasHaste then
    -- Perdeu haste, notificar o modulo AutoHaste
    if _Helper.AutoHaste and _Helper.AutoHaste.onHasteLost then
      _Helper.AutoHaste.onHasteLost()
    end
  end
end

function useAutoSio(target)
  local spellId = 84
  local spell = getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)
end

function useAutoGranSio(target)
  local spellId = 242
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)
end

function useAutoTioSio(target)
  local spellId = 297
  local spell = getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  safeDoThing(false)
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
  safeDoThing(true)
end

function useAutoUH(target)
  local runeId = 3160
  local rune = Spells.getRuneSpellByItem(runeId)
  if not rune and CustomRuneIds then rune = CustomRuneIds[tonumber(runeId) or runeId] end
  if not rune then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  helperConfig.magicShooterOnHold = true

  if hasItemInBackpack(runeId) then
    safeDoThing(false)
    g_game.useInventoryItemWith(runeId, target, 0, true)
    safeDoThing(true)
  end

  helperConfig.magicShooterOnHold = false
end

function useAutoMasRes()
  local spell = getSpellByClientId(82)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  if isSpellOnCooldown(spell) then
    return false
  end

  safeDoThing(false)
  g_game.talk(spell.words, true)
  safeDoThing(true)
end

-- toolMenu
-- Wrapper function para OTUI (modulo sandboxed)
function updateTrainingPercent(buttonId, newPercent)
  _Helper.ManaTraining.updatePercent(buttonId, newPercent)
end

-- Wrapper function que chama o modulo ManaTraining
function checkTrainingSpell(mana, maxMana)
  _Helper.ManaTraining.check(mana, maxMana)
end

-- Wrapper function para Auto Food (OTUI compatibilidade)
function toggleAutoEat(checked)
  _Helper.AutoFood.toggle(checked)
end

-- Wrapper para Smart Follow (tools_panel.otui chama global toggleSmartFollow)
function toggleSmartFollow(checked)
  if _Helper.SmartFollow and _Helper.SmartFollow.toggle then
    _Helper.SmartFollow.toggle(checked)
  end
end

--- Chamado apos g_game.follow (game_interface, etc.) — alinha Smart Follow ao Balrorg/Hylian; Set Key continua a usar o checkbox.
function notifySmartFollowFollowTarget(creature)
  if _Helper.SmartFollow and _Helper.SmartFollow.isDebugLogEnabled and _Helper.SmartFollow.isDebugLogEnabled() and g_logger then
    if creature then
      g_logger.info(string.format("[smart_follow:hook] notifySmartFollowFollowTarget id=%d name=%s", creature:getId(), creature:getName()))
    else
      g_logger.info("[smart_follow:hook] notifySmartFollowFollowTarget creature=nil")
    end
  end
  if _Helper.SmartFollow and _Helper.SmartFollow.setTarget then
    _Helper.SmartFollow.setTarget(creature)
  end
end

-- Wrapper functions para Auto Haste (OTUI compatibilidade)
function toggleAutoHaste(checked)
  _Helper.AutoHaste.toggle(checked)
end

function toggleAutoHastePz(checked)
  _Helper.AutoHaste.togglePz(checked)
end

-- Wrapper functions para Auto Utito (OTUI compatibilidade)
function toggleAutoUtito(checked)
  _Helper.AutoUtito.toggle(checked)
end

function toggleAutoUtitoPz(checked)
  _Helper.AutoUtito.togglePz(checked)
end

-- Wrapper function for Gold Change (OTUI compatibility)
function toogleChangeGold(checked)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.toggleChangeGold(checked)
  else
    helperConfig.autoChangeGold = checked
  end
end

-- Wrapper function for auto change gold
function autoChangeGold()
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.autoChangeGold()
  end
end

-- Wrapper function for Exercise Training (OTUI compatibility)
function toggleExerciseTraining(checked)
  if _Helper.ExerciseTraining and _Helper.ExerciseTraining.toggle then
    _Helper.ExerciseTraining.toggle(checked)
  elseif modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.toggleExerciseTraining(checked)
  end
end

-- Wrapper function for resources balance change
function onResourcesBalanceChange(value, oldValue, resourceType)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.onResourcesBalanceChange(value, oldValue, resourceType)
  end
end

function checkMana()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end
  local currentPlayer = getPlayer()
  if not currentPlayer then
    return
  end

  local mana = currentPlayer:getMana()
  local maxMana = currentPlayer:getMaxMana()
  checkManaHealing(mana, maxMana)
  checkTrainingSpell(mana, maxMana)
end

eventTable.checkMana.action = checkMana

function routineChecks()
  if not helperAutomaticFunctionsEnabled then return end
  local currentPlayer = getPlayer()
  if currentPlayer then
    if currentPlayer:getRegenerationTime() <= 500 then
      _Helper.AutoFood.check()
    end

    autoChangeGold()
  end
end

eventTable.routineChecks.action = routineChecks

function updateMagicShooterPriority(index, priority)
  _Helper.MagicShooter.updatePriority(index, priority)
end

function updateMagicShooterCreatures(name, index, creatures)
  _Helper.MagicShooter.updateCreatures(name, index, creatures)
end

function toggleSelfCast(index, checked)
  _Helper.MagicShooter.toggleSelfCast(index, checked)
end

function toggleForceCast(index, checked)
  _Helper.MagicShooter.toggleForceCast(index, checked)
end

function toggleForceRuneCast(index, checked)
  _Helper.MagicShooter.toggleForceRuneCast(index, checked)
end

function isMagicShooterActive()
  return _Helper.MagicShooter.isActive()
end

function toggleMagicShooter(widget, message)
  _Helper.MagicShooter.toggle(widget, message)
end

function holdMagicShooter()
  _Helper.MagicShooter.hold()
end

function releaseMagicShooter()
  _Helper.MagicShooter.release()
end

function toggleDisableInProtectZone(checked)
  if helperConfig then
    helperConfig.disableInProtectZone = checked
    saveSettings()
  end
end

-- HELPER AUTO TARGET: Funções movidas para classes/auto_target.lua
-- Wrapper functions para compatibilidade com OTUI e código existente

function isAutoTargetActive()
  return _Helper.AutoTarget.isActive()
end

function toggleAutoTarget(widget)
  _Helper.AutoTarget.toggle(widget)
end

function toggleShooterPreset(widget, hideMessage)
  _Helper.MagicShooter.togglePreset(widget, hideMessage)
end

function removeProfile()
  _Helper.MagicShooter.removeProfile()
end

function updateAutoTargetMode(mode)
  _Helper.AutoTarget.updateMode(mode)
end

function setKeepWayDistance(text)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  local val = tonumber(text)
  if val == nil or val < 0 then val = 0 end
  helperConfig.keepWayDistance = val
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

function setAvoidWaves(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig then return end
  helperConfig.avoidWaves = checked == true
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

function applyPriorityMonsterList()
  _Helper.AutoTarget.applyPriorityList()
end

local function printArea(area)
  -- Debug function disabled
end

local function rotateArea(area, direction)
  if not area or type(area) ~= "table" or #area == 0 or not area[1] or type(area[1]) ~= "table" then
    return area
  end

  local rotatedArea = {}
  local rows = #area
  local cols = #area[1]

  if direction == Directions.North then
    rotatedArea = area
  elseif direction == Directions.South then
    for y = 1, rows do
      rotatedArea[y] = {}
      for x = 1, cols do
        rotatedArea[y][x] = area[rows - y + 1][cols - x + 1]
      end
    end
  elseif direction == Directions.East then
    for x = 1, cols do
      rotatedArea[x] = {}
      for y = 1, rows do
        rotatedArea[x][y] = area[rows - y + 1][x]
      end
    end
  elseif direction == Directions.West then
    for x = 1, cols do
      rotatedArea[x] = {}
      for y = 1, rows do
        rotatedArea[x][y] = area[y][cols - x + 1]
      end
    end
  end

  return rotatedArea
end

local function findPlayerPosition(area)
  if not area or type(area) ~= "table" or #area == 0 then return nil, nil end
  for y, row in ipairs(area) do
    if type(row) ~= "table" then goto continue end
    for x, value in ipairs(row) do
      if value == 3 or value == 2 then
        return x, y
      end
    end
    ::continue::
  end
  return nil, nil
end

function getRelativePosition(targetPos)
  local player = g_game.getLocalPlayer()
  if not player then return targetPos end
  local playerPos = player:getPosition()

  local relativePos = { x = targetPos.x, y = targetPos.y, z = targetPos.z }
  if playerPos.x < targetPos.x and playerPos.y < targetPos.y then
    relativePos.x = relativePos.x - 1;
    relativePos.y = relativePos.y - 1;
  elseif (playerPos.x < targetPos.x and playerPos.y > targetPos.y) or playerPos.x < targetPos.x then
    relativePos.x = relativePos.x - 1;
  elseif (playerPos.x > targetPos.x and playerPos.y < targetPos.y) or playerPos.y < targetPos.y then
    relativePos.y = relativePos.y - 1;
  end
  return relativePos
end

-- HELPER MAGIC SHOOTER: Getter para getRelativePosition (definido aqui apos a funcao)
_Helper.getRelativePosition = function(targetPos)
  return getRelativePosition(targetPos)
end

local function countAttackableCreatures(casterPos, direction, area, creatureList, ranged)
  if direction == Directions.SouthEast or direction == Directions.NorthEast then
    direction = Directions.East
  elseif direction == Directions.SouthWest or direction == Directions.NorthWest then
    direction = Directions.West
  end

  local area = rotateArea(area, direction)
  local creatures = 0
  local playerX, playerY = findPlayerPosition(area)
  if not playerX or not playerY then
    return 0
  end

  -- Clear reusable table
  for k in pairs(reusableCountedCreatures) do reusableCountedCreatures[k] = nil end

  for yOffset, row in ipairs(area) do
    for xOffset, value in ipairs(row) do
      if value == 1 or (ranged and (value == 3 or value == 2)) then
        tempPos.x = casterPos.x + (xOffset - playerX)
        tempPos.y = casterPos.y + (yOffset - playerY)
        tempPos.z = casterPos.z

        for _, creatureData in ipairs(creatureList) do
          local creaturePos = creatureData.position
          if creaturePos and positionCompare(creaturePos, tempPos) and (g_map.isSightClear(casterPos, creaturePos)) then
            local creature = creatureData.creature
            local creatureId = creature and creature.getId and creature:getId() or
                tostring(creaturePos.x) .. "," .. tostring(creaturePos.y) .. "," .. tostring(creaturePos.z)
            if not reusableCountedCreatures[creatureId] then
              reusableCountedCreatures[creatureId] = true
              creatures = creatures + 1
              break
            end
          end
        end
      end
    end
  end
  -- Limpeza do pool de tabelas
  for k in pairs(reusableCountedCreatures) do reusableCountedCreatures[k] = nil end

  return creatures
end

-- HELPER AUTO TARGET: Getter para countAttackableCreatures (definido aqui apos a funcao local)
_Helper.countAttackableCreatures = function(casterPos, direction, area, creatureList, ranged)
  return countAttackableCreatures(casterPos, direction, area, creatureList, ranged)
end

-- Encontra a melhor direcao para castar um spell de area, maximizando o numero de criaturas atingidas
-- Retorna a melhor direcao e o numero de criaturas que serao atingidas
local function findBestDirectionForSpell(casterPos, area, creatureList, ranged)
  local cardinalDirections = {
    Directions.North,
    Directions.South,
    Directions.East,
    Directions.West
  }

  local bestDirection = Directions.North
  local maxCreatures = 0

  for _, dir in ipairs(cardinalDirections) do
    local creatures = countAttackableCreatures(casterPos, dir, area, creatureList, ranged)
    if creatures > maxCreatures then
      maxCreatures = creatures
      bestDirection = dir
    end
  end

  return bestDirection, maxCreatures
end

-- HELPER MAGIC SHOOTER: Getter para findBestDirectionForSpell
_Helper.findBestDirectionForSpell = function(casterPos, area, creatureList, ranged)
  return findBestDirectionForSpell(casterPos, area, creatureList, ranged)
end

-- HELPER MAGIC SHOOTER: Funcoes movidas para classes/magic_shooter.lua
-- sortMagicShooterByPriority e findBestTarget agora estao em _Helper.MagicShooter

local function sortMagicShooterByPriority(list)
  return _Helper.MagicShooter.sortByPriority(list)
end

local function findBestTarget(position, direction, area, creatureList, minCreatures)
  local bestTarget = nil
  local maxCreaturesHit = 0

  for _, creatureInfo in pairs(creatureList) do
    if isWithinReach(position, creatureInfo.position) and g_map.isSightClear(position, creatureInfo.position) then
      local creaturesHit = countAttackableCreatures(creatureInfo.position, direction, area, creatureList, true)
      if creaturesHit >= minCreatures then
        if creaturesHit > maxCreaturesHit then
          maxCreaturesHit = creaturesHit
          bestTarget = creatureInfo.creature
        end
      end
    end
  end

  return bestTarget, maxCreaturesHit
end

-- Converte a area da runa em offsets relativos ao centro (valor 3 ou 2)
-- Retorna uma lista de {x, y} offsets onde a runa causa dano
local function getOffsetsFromArea(area)
  if not area or type(area) ~= "table" then return {} end
  local centerX, centerY = findPlayerPosition(area)
  if not centerX or not centerY then return {} end

  local offsets = {}
  for y = 1, #area do
    for x = 1, #area[y] do
      -- Valor 1 = area de dano, 2/3 = centro
      if area[y][x] == 1 or area[y][x] == 2 or area[y][x] == 3 then
        table.insert(offsets, { x = x - centerX, y = y - centerY })
      end
    end
  end
  return offsets
end

-- Encontra o melhor tile para jogar a runa de area, maximizando o numero de criaturas atingidas
-- Usa logica de score: para cada criatura, calcula todos os tiles possiveis onde a runa
-- poderia ser jogada para atingi-la, acumulando score por posicao
-- Isso e mais eficiente que iterar sobre todos os tiles do mapa
local function findBestTileForRune(playerPos, direction, area, creatureList, minCreatures)
  local offsets = getOffsetsFromArea(area)
  if #offsets == 0 then return nil, 0 end

  -- Tabela para acumular score por posicao (key = "x,y")
  local scoreByPosition = {}
  -- Cache para evitar verificar o mesmo tile multiplas vezes
  local checkedTiles = {}

  -- Para cada criatura, calcular os tiles onde a runa poderia ser jogada para atingi-la
  for _, creatureData in ipairs(creatureList) do
    local creaturePos = creatureData.position
    if creaturePos and creaturePos.z == playerPos.z then
      -- Score base por criatura (pode ser ajustado para priorizar criaturas com menos vida)
      local score = 1

      -- Para cada offset da area, calcular onde a runa deveria ser jogada
      -- para que este offset atinja a criatura
      for _, offset in ipairs(offsets) do
        -- Se a runa for jogada em (goalX, goalY), o offset atinge (goalX + offset.x, goalY + offset.y)
        -- Queremos que atinja creaturePos, entao: goal = creaturePos - offset
        local goalPos = {
          x = creaturePos.x - offset.x,
          y = creaturePos.y - offset.y,
          z = creaturePos.z
        }

        local key = string.format("%d,%d", goalPos.x, goalPos.y)

        -- Verificar se ja validamos este tile antes
        if checkedTiles[key] == nil then
          -- Verificar apenas se o player tem visao clara para este tile (pode jogar runa la)
          -- isSightClear verifica se nao ha obstaculos bloqueando a visao/projetil
          if isWithinReach(playerPos, goalPos) and g_map.isSightClear(playerPos, goalPos) then
            checkedTiles[key] = true
          else
            checkedTiles[key] = false
          end
        end

        -- Só acumula score se o tile for valido
        if checkedTiles[key] then
          scoreByPosition[key] = (scoreByPosition[key] or 0) + score
        end
      end
    end
  end

  -- Encontrar a posicao com maior score
  local maxScore = 0
  local bestPos = nil

  for key, score in pairs(scoreByPosition) do
    if score >= minCreatures and score > maxScore then
      local x, y = key:match("(-?%d+),(-?%d+)")
      x, y = tonumber(x), tonumber(y)
      local tilePos = { x = x, y = y, z = playerPos.z }

      local tile = g_map.getTile(tilePos)
      if tile then
        local topThing = tile:getTopUseThing()
        if topThing then
          maxScore = score
          bestPos = { tile = topThing, position = tilePos }
        end
      end
    end
  end

  if bestPos then
    return bestPos.tile, maxScore, bestPos.position
  end

  return nil, 0, nil
end

function isSpellOnCooldown(spell)
  if getSpellCooldown(spell.id) >= g_clock.millis() then
    return true
  end

  if type(spell.group) == "table" then
    for group, _ in pairs(spell.group) do
      if getGroupSpellCooldown(group) >= g_clock.millis() then
        return true
      end
    end
  else
    if getGroupSpellCooldown(spell.group) >= g_clock.millis() then
      return true
    end
  end

  return false
end

-- HELPER MAGIC SHOOTER: Getters definidos apos as funcoes locais
_Helper.isSpellOnCooldown = function(spell)
  return isSpellOnCooldown(spell)
end

_Helper.onSpellCooldown = function(spellId, delay)
  onSpellCooldown(spellId, delay)
end

_Helper.onSpellGroupCooldown = function(groupId, delay)
  onSpellGroupCooldown(groupId, delay)
end

_Helper.findBestTarget = function(position, direction, area, creatureList, minCreatures)
  return findBestTarget(position, direction, area, creatureList, minCreatures)
end

_Helper.findBestTileForRune = function(playerPos, direction, area, creatureList, minCreatures)
  return findBestTileForRune(playerPos, direction, area, creatureList, minCreatures)
end

function checkMagicShooter()
  _Helper.MagicShooter.check()
end

eventTable.checkMagicShooter.action = checkMagicShooter

function checkAutoTarget()
  _Helper.AutoTarget.check()
end

eventTable.checkAutoTarget.action = checkAutoTarget

function checkKeepWay()
  if not helperConfig then return end
  local keepWay = tonumber(helperConfig.keepWayDistance) or 0
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if enableButtons then
    local w = enableButtons:recursiveGetChildById("keepWayDistance")
    if w and w.getText then
      local v = tonumber(w:getText())
      if v and v > 0 then keepWay = v end
    end
  end
  if keepWay <= 0 then return end
  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end
  local targetCreature = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if not targetCreature or targetCreature:isDead() then return end
  local myPos = myCharacter:getPosition()
  local targetPos = targetCreature:getPosition()
  if not myPos or not targetPos then return end
  _Helper.AutoTarget.checkKeepWay(myCharacter, myPos, targetCreature, keepWay)
end

eventTable.checkKeepWay.action = checkKeepWay

function checkAvoidWaves()
  if not helperConfig or not helperConfig.avoidWaves then return end
  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end
  local targetCreature = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if not targetCreature or targetCreature:isDead() then return end
  local myPos = myCharacter:getPosition()
  local targetPos = targetCreature:getPosition()
  if not myPos or not targetPos or myPos.z ~= targetPos.z then return end
  _Helper.AutoTarget.checkAvoidWaves(myCharacter, myPos, targetCreature)
end

eventTable.checkAvoidWaves.action = checkAvoidWaves

function checkFriendHealing(cachedSpectators)
  if not helperAutomaticFunctionsEnabled then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end
  local healingMode = helperConfig.healingTargetMode or "party"
  if healingMode == "screen" or localPlayer:isPartyMember() then
    onFriendHealing(localPlayer, cachedSpectators)
  end
end

eventTable.checkFriendHealing.action = checkFriendHealing

-- HELPER AUTO HASTE: Funções movidas para classes/auto_haste.lua
-- Agora usa onStatesChange + cycle event temporario em vez de eventTable polling

function checkHealthPriority()
  if not helperAutomaticFunctionsEnabled then return true end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return true end
  for _, spell in ipairs(helperConfig.spells) do
    local healthPercent = (localPlayer:getHealth() / localPlayer:getMaxHealth()) * 100
    if spell.id ~= 0 and healthPercent <= tonumber(spell.percent) then
      return false
    end
  end
  return true
end

local function castFriendHealOnMember(localPlayer, member)
  if localPlayer:isSorcerer() then
    useAutoUH(member)
  elseif localPlayer:isMonk() then
    useAutoTioSio(member)
  else
    useAutoSio(member)
  end
end

function onFriendHealing(localPlayer, cachedSpectators)
  if not helperAutomaticFunctionsEnabled then return end

  if not localPlayer then
    localPlayer = g_game.getLocalPlayer()
  end
  if not localPlayer then return end

  local success, position, localPlayerId = pcall(function()
    return localPlayer:getPosition(), localPlayer:getId()
  end)
  if not success or not position then return end

  local healingMode = helperConfig.healingTargetMode or "party"

  local spectators = cachedSpectators
  if not spectators then
    spectators = g_map.getSpectators(position, false)
  end
  if not spectators then return end

  local granSioSpell = getSpellByClientId(242)
  local granSioOnCooldown = not granSioSpell or granSioSpell.id == 0 or isSpellOnCooldown(granSioSpell)

  local masResSpell = getSpellByClientId(82)
  local masResOnCooldown = not masResSpell or masResSpell.id == 0 or isSpellOnCooldown(masResSpell)

  local masResExtended = helperConfig.masreshealing and helperConfig.masreshealing.extended
  local masResArea
  if masResExtended then
    masResArea = { [0] = 4, [1] = 4, [2] = 3, [3] = 2, [4] = 1 }
  else
    masResArea = { [0] = 3, [1] = 3, [2] = 2, [3] = 1 }
  end

  local granSioCandidates = {}
  local friendCandidates = {}
  local needMasRes = false

  for _, creature in pairs(spectators) do
    if creature and creature:isPlayer() and creature:getId() ~= localPlayerId then
      local isValidTarget = false
      if healingMode == "screen" then
        isValidTarget = true
      else
        local shield = creature:getShield()
        isValidTarget = (shield and shield > 0)
      end
      if isValidTarget then
        local vocKey = getVocationKey(creature)
        if vocKey then
          local memberPos = creature:getPosition()
          if memberPos and g_map.isSightClear(position, memberPos) and isWithinReach(position, memberPos) then
            local memberHealth = creature:getHealthPercent()

            if not granSioOnCooldown then
              local granSioCfg = helperConfig.gransiohealing and helperConfig.gransiohealing[vocKey]
              if granSioCfg and granSioCfg.enabled and memberHealth <= granSioCfg.percent then
                table.insert(granSioCandidates, {
                  creature = creature,
                  priority = granSioCfg.priority or 1,
                  health = memberHealth
                })
              end
            end

            local friendCfg = helperConfig.friendhealing and helperConfig.friendhealing[vocKey]
            if friendCfg and friendCfg.enabled and memberHealth <= friendCfg.percent then
              table.insert(friendCandidates, {
                creature = creature,
                priority = friendCfg.priority or 1,
                health = memberHealth
              })
            end

            if not masResOnCooldown then
              local masResCfg = helperConfig.masreshealing and helperConfig.masreshealing[vocKey]
              if masResCfg and masResCfg.enabled and memberHealth <= masResCfg.percent then
                local dx = math.abs(position.x - memberPos.x)
                local dy = math.abs(position.y - memberPos.y)
                local maxDx = masResArea[dy]
                if maxDx and dx <= maxDx and position.z == memberPos.z then
                  needMasRes = true
                end
              end
            end
          end
        end
      end
    end
  end

  local function sortByPriorityThenHealth(a, b)
    if a.priority ~= b.priority then
      return a.priority > b.priority
    end
    return a.health < b.health
  end

  if #granSioCandidates > 0 then
    table.sort(granSioCandidates, sortByPriorityThenHealth)
    useAutoGranSio(granSioCandidates[1].creature)
    return
  end

  if #friendCandidates > 0 then
    table.sort(friendCandidates, sortByPriorityThenHealth)
    castFriendHealOnMember(localPlayer, friendCandidates[1].creature)
    return
  end

  if needMasRes then
    useAutoMasRes()
  end
end

-- Event-driven friend healing: called directly when party member health changes
-- More efficient than polling - only processes when health actually changes
function onPartyMemberHealthChangeHelper(creature, healthPercent)
  if not helperAutomaticFunctionsEnabled then return end
  if not creature then return end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local healingMode = helperConfig.healingTargetMode or "party"
  if healingMode ~= "screen" and not localPlayer:isPartyMember() then return end

  local position = localPlayer:getPosition()
  if not position then return end

  local memberPos = creature:getPosition()
  if not memberPos then return end

  if not g_map.isSightClear(position, memberPos) then return end
  if not isWithinReach(position, memberPos) then return end

  local vocKey = getVocationKey(creature)
  if not vocKey then return end

  local masResCfg = helperConfig.masreshealing and helperConfig.masreshealing[vocKey]
  if masResCfg and masResCfg.enabled and healthPercent <= masResCfg.percent then
    useAutoMasRes()
    return
  end

  local granSioCfg = helperConfig.gransiohealing and helperConfig.gransiohealing[vocKey]
  if granSioCfg and granSioCfg.enabled and healthPercent <= granSioCfg.percent then
    useAutoGranSio(creature)
    return
  end

  local friendCfg = helperConfig.friendhealing and helperConfig.friendhealing[vocKey]
  if friendCfg and friendCfg.enabled and healthPercent <= friendCfg.percent then
    castFriendHealOnMember(localPlayer, creature)
  end
end

function reset()
  -- Safeguard: skip if panels not ready (avoids nil errors on early init)
  if not healingPanel or not shooterPanel or not toolsPanel then
    return
  end

  for i = 0, 2 do
    removeAction("spell", healingPanel:recursiveGetChildById("spellButton" .. i))
    removeAction("potion", healingPanel:recursiveGetChildById("potionButton" .. i))
  end

  removeAction("training", toolsPanel:recursiveGetChildById("spellTrainingButton0"))
  removeAction("haste", toolsPanel:recursiveGetChildById("hasteButton0"))

  -- Clear magic shooter rules using the new panel
  if modules.game_helper and modules.game_helper.magicShooter then
    modules.game_helper.magicShooter.clearForm()
  end
end

function removeAction(type, button, keepInfo)
  if not button then return end
  local slotIndex = tonumber(button:getId():match("%d+"))
  if type == "spell" then
    helperConfig.spells[slotIndex + 1].id = 0
    helperConfig.spells[slotIndex + 1].percent = 80
    local button = healingPanel:recursiveGetChildById("spellButton" .. slotIndex)
    local percent = healingPanel:recursiveGetChildById("spellPercentLabel" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    button:setImageClip("0 0 34 34")
    button:setBorderWidth(0)
    button:setTooltip("")
    percent:setText("80%")
  elseif type == "potion" then
    if not helperConfig.potions[slotIndex + 1] then
      helperConfig.potions[slotIndex + 1] = {}
    end

    if helperConfig.potions[slotIndex + 1].id == 7642 or helperConfig.potions[slotIndex + 1].id == 23374 then
      helperConfig.potions[slotIndex + 1].priority = 0
      local priorityButton = healingPanel:recursiveGetChildById("priority" .. slotIndex)
      priorityButton:setImageSource("/images/skin/show-gui-help-grey")
      priorityButton:setTooltip(
        "Uses a healing or mana potion when your health or\nmana reaches the defined percentage.\nPaladins can click on this button to change the potion priority:\n  - Icon: Blue (Mana Priority)\n  - Icon: Red  (Health Priority)")
    end

    helperConfig.potions[slotIndex + 1].id = 0
    helperConfig.potions[slotIndex + 1].percent = 50
    local button = healingPanel:recursiveGetChildById("potionButton" .. slotIndex)
    button:setImageSource("/images/game/actionbar/actionbarslot")
    local percent = healingPanel:recursiveGetChildById("potionPercentLabel" .. slotIndex)
    if button.potionItem then
      button.potionItem:destroy()
    end
    percent:setText("50%")
  elseif type == "training" then
    _Helper.ManaTraining.removeAction(button)
  elseif type == "haste" then
    _Helper.AutoHaste.removeAction(button)
  elseif type == "utito" then
    _Helper.AutoUtito.removeAction(button)
  elseif type == "exetaRes" then
    if helperConfig.exetaRes and helperConfig.exetaRes[1] then
      helperConfig.exetaRes[1].id = 0
      helperConfig.exetaRes[1].enabled = false
    end
    if toolsPanel then
      local btn = toolsPanel:recursiveGetChildById("exetaResButton0")
      if btn then
        btn:setImageSource("/images/game/actionbar/actionbarslot")
        btn:setImageClip("0 0 34 34")
        btn:setBorderWidth(0)
        btn:setTooltip("")
      end
      local enableExeta = toolsPanel:recursiveGetChildById("enableExetaRes")
      if enableExeta then enableExeta:setChecked(false) end
    end
  elseif type == "ampRes" then
    if helperConfig.ampRes and helperConfig.ampRes[1] then
      helperConfig.ampRes[1].id = 0
      helperConfig.ampRes[1].enabled = false
    end
    if toolsPanel then
      local btn = toolsPanel:recursiveGetChildById("ampResButton0")
      if btn then
        btn:setImageSource("/images/game/actionbar/actionbarslot")
        btn:setImageClip("0 0 34 34")
        btn:setBorderWidth(0)
        btn:setTooltip("")
      end
      local enableAmp = toolsPanel:recursiveGetChildById("enableAmpRes")
      if enableAmp then enableAmp:setChecked(false) end
    end
  elseif type == "itemTimer" then
    local slotIndex = (button and button.slotIndex) or 0
    if helperConfig.itemTimer and helperConfig.itemTimer[slotIndex + 1] then
      helperConfig.itemTimer[slotIndex + 1].itemId = 0
      helperConfig.itemTimer[slotIndex + 1].enabled = false
    end
    if toolsPanel then
      local btn = toolsPanel:recursiveGetChildById("itemTimerButton" .. slotIndex)
      if btn then
        btn:setImageSource("/images/game/actionbar/actionbarslot")
        btn:setImageClip("0 0 34 34")
        local timerItem = btn:getChildById("timerItem")
        if timerItem then timerItem:destroy() end
      end
      local enableItemTimer = toolsPanel:recursiveGetChildById("enableItemTimer" .. slotIndex)
      if enableItemTimer then enableItemTimer:setChecked(false) end
    end
  elseif type == "exercise" then
    local box = toolsPanel:recursiveGetChildById("autoTrainingItem")
    box:setImageSource("/images/game/actionbar/actionbarslot")
    if button.potionItem then
      button.potionItem:destroy()
    end
  end
  -- Persist configuration after removal
end

function loadProfileOptions()
  _Helper.MagicShooter.loadProfileOptions()
end

function loadShooterProfileByName(profileName)
  _Helper.MagicShooter.loadProfileByName(profileName)
end

function resetHelperUI()
  if not healingPanel or not toolsPanel then
    return
  end

  -- Reset spell buttons
  for i = 0, 2 do
    local button = healingPanel:recursiveGetChildById("spellButton" .. i)
    if button then
      button:setImageSource("/images/game/actionbar/actionbarslot")
      button:setImageClip("0 0 34 34")
      button:setBorderWidth(0)
      button:setTooltip("")
    end
    local percent = healingPanel:recursiveGetChildById("spellPercentLabel" .. i)
    if percent then
      percent:setText("80%")
    end
  end

  -- Reset potion buttons
  for i = 0, 2 do
    local button = healingPanel:recursiveGetChildById("potionButton" .. i)
    if button then
      button:setImageSource("/images/game/actionbar/actionbarslot")
      local oldWidget = button:getChildById('potionItem')
      if oldWidget then
        oldWidget:destroy()
      end
    end
    local percent = healingPanel:recursiveGetChildById("potionPercentLabel" .. i)
    if percent then
      percent:setText("50%")
    end
    local priority = healingPanel:recursiveGetChildById("priority" .. i)
    if priority then
      priority:setImageColor("#808080")
      priority:setTooltip("")
    end
  end

  -- Reset training button
  _Helper.ManaTraining.resetButton()

  -- Reset haste button
  _Helper.AutoHaste.resetButton()

  -- Reset utito button
  _Helper.AutoUtito.resetButton()

  -- Reset auto food checkbox
  _Helper.AutoFood.resetCheckbox()

  -- Reset auto target checkbox
  _Helper.AutoTarget.resetCheckbox()

  -- Reset other checkboxes
  local changeGold = toolsPanel:recursiveGetChildById("changeGold")
  if changeGold then changeGold:setChecked(false) end

  local autoFollow = toolsPanel:recursiveGetChildById("autoFollow")
  if autoFollow then autoFollow:setChecked(false) end

  local autoBless = toolsPanel:recursiveGetChildById("autoBless")
  if autoBless then autoBless:setChecked(false) end

  -- Reset shooter panel if available
  if shooterPanel and enableButtons then
    local enableMagicShooter = enableButtons:recursiveGetChildById("enableMagicShooter")
    if enableMagicShooter then enableMagicShooter:setChecked(false) end
  end
end

function onLoadHelperData()
  if not healingPanel or not toolsPanel then
    return
  end

  -- Salvar valores ANTES de resetHelperUI (callbacks podem sobrescrever)
  local savedHasteEnabled, savedHasteSafecast = _Helper.AutoHaste.collectStates()
  local savedTrainingEnabled = _Helper.ManaTraining.collectStates()
  local savedAutoEatFood = helperConfig.autoEatFood
  local savedAutoChangeGold = helperConfig.autoChangeGold
  local savedAutoTargetEnabled = helperConfig.autoTargetEnabled
  local savedMagicShooterEnabled = helperConfig.magicShooterEnabled

  -- Limpar UI antes de carregar novos dados
  resetHelperUI()

  -- Restaurar valores que foram sobrescritos pelo callback
  _Helper.AutoHaste.saveAndRestoreStates(savedHasteEnabled, savedHasteSafecast)
  _Helper.ManaTraining.saveAndRestoreStates(savedTrainingEnabled)
  helperConfig.autoEatFood = savedAutoEatFood
  helperConfig.autoChangeGold = savedAutoChangeGold
  helperConfig.autoTargetEnabled = savedAutoTargetEnabled
  helperConfig.magicShooterEnabled = savedMagicShooterEnabled

  for k, v in pairs(helperConfig.spells) do
    if v.id ~= 0 then
      local button = healingPanel:recursiveGetChildById("spellButton" .. k - 1)
      local spell = Spells.getSpellDataById(v.id)
      if spell then
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
    local percentOption = healingPanel:recursiveGetChildById("spellPercentLabel" .. k - 1)
    percentOption:setText(tostring(v.percent) .. "%")
  end

  -- Configurar evento de clique para botoes de spell healing
  for i = 0, 2 do
    local spellButton = healingPanel:recursiveGetChildById("spellButton" .. i)
    if spellButton then
      local index = i
      -- Clique esquerdo: abre seleção de spell
      spellButton.onClick = function()
        assignSpell(spellButton, "Healing", { 2 }, helperConfig.spells)
      end
      -- Clique direito: menu de contexto
      spellButton.onMousePress = function(self, mousePos, mouseButton)
        if mouseButton == MouseRightButton then
          local menu = g_ui.createWidget('PopupMenu')
          menu:setGameMenu(true)
          if helperConfig.spells[index + 1].id > 0 then
            menu:addOption(tr('Edit Spell'),
              function() assignSpell(spellButton, "Healing", { 2 }, helperConfig.spells) end)
            menu:addOption(tr('Remove'), function() removeAction("spell", spellButton) end)
          else
            menu:addOption(tr('Assign Spell'),
              function() assignSpell(spellButton, "Healing", { 2 }, helperConfig.spells) end)
          end
          menu:display(mousePos)
          return true
        end
        return false
      end
    end
  end

  for k, v in pairs(helperConfig.potions) do
    local button = healingPanel:recursiveGetChildById("potionButton" .. k - 1)

    if v.id ~= 0 then
      -- Remove widget antigo se existir
      local oldWidget = button:getChildById('potionItem')
      if oldWidget then
        oldWidget:destroy()
      end

      local itemWidget = g_ui.createWidget('PotionItem', button)
      itemWidget:setItemId(v.id)
      itemWidget:setId('potionItem')
    end

    -- Apply priority color for all potions (even if no potion assigned)
    local priorityButton = healingPanel:recursiveGetChildById("priority" .. k - 1)
    if priorityButton then
      local priority = v.priority or 0
      priorityButton:setImageSource("/images/ui/checkboxcircle")
      if priority == 1 then
        priorityButton:setImageColor("#d94a3a")
        priorityButton:setTooltip("This potion is healing health...")
      elseif priority == 2 then
        priorityButton:setImageColor("#3a8ad9")
        priorityButton:setTooltip("This potion is healing mana...")
      else
        priorityButton:setImageColor("#808080")
        priorityButton:setTooltip("")
      end
    end

    local percentOption = healingPanel:recursiveGetChildById("potionPercentLabel" .. k - 1)
    percentOption:setText(tostring(v.percent) .. "%")
  end

  -- Carregar training para UI
  _Helper.ManaTraining.loadToUI()

  -- Configurar evento de clique para botao de training
  local trainingButton = toolsPanel:recursiveGetChildById("spellTrainingButton0")
  if trainingButton then
    -- Clique esquerdo: abre seleção de spell
    trainingButton.onClick = function()
      assignTrainingSpell(trainingButton)
    end
    -- Clique direito: menu de contexto
    trainingButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.training[1].id > 0 then
          menu:addOption(tr('Edit Training Spell'), function() assignTrainingSpell(trainingButton) end)
          menu:addOption(tr('Remove'), function() removeAction("training", trainingButton) end)
        else
          menu:addOption(tr('Assign Training Spell'), function() assignTrainingSpell(trainingButton) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  -- Carregar haste para UI
  _Helper.AutoHaste.loadToUI()

  -- Carregar utito para UI
  _Helper.AutoUtito.loadToUI()

  -- Configurar evento de clique para botao de haste
  local hasteButton = toolsPanel:recursiveGetChildById("hasteButton0")
  if hasteButton then
    -- Clique esquerdo: abre seleção de spell
    hasteButton.onClick = function()
      assignTrainingSpell(hasteButton, true)
    end
    -- Clique direito: menu de contexto
    hasteButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.haste[1].id > 0 then
          menu:addOption(tr('Edit Haste Spell'), function() assignTrainingSpell(hasteButton, true) end)
          menu:addOption(tr('Remove'), function() removeAction("haste", hasteButton) end)
        else
          menu:addOption(tr('Assign Haste Spell'), function() assignTrainingSpell(hasteButton, true) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  -- Configurar evento de clique para botao de utito
  local utitoButton = toolsPanel:recursiveGetChildById("utitoButton0")
  if utitoButton then
    utitoButton.onClick = function()
      assignTrainingSpell(utitoButton, false, true)
    end
    utitoButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.utito[1].id > 0 then
          menu:addOption(tr('Edit Utito Spell'), function() assignTrainingSpell(utitoButton, false, true) end)
          menu:addOption(tr('Remove'), function() removeAction("utito", utitoButton) end)
        else
          menu:addOption(tr('Assign Utito Spell'), function() assignTrainingSpell(utitoButton, false, true) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  for itemSlot = 0, 1 do
    local itemTimerButton = toolsPanel:recursiveGetChildById("itemTimerButton" .. itemSlot)
    if itemTimerButton then
      itemTimerButton.slotIndex = itemSlot
      itemTimerButton.onClick = function()
        if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.assignItemTimerItem then
          modules.game_helper.tools.assignItemTimerItem(itemTimerButton, itemSlot)
        end
      end
      itemTimerButton.onMousePress = function(self, mousePos, mouseButton)
        if mouseButton == MouseRightButton then
          local menu = g_ui.createWidget('PopupMenu')
          menu:setGameMenu(true)
          menu:addOption(tr('Remove'), function() removeAction("itemTimer", itemTimerButton) end)
          menu:display(mousePos)
          return true
        end
        return false
      end
    end
  end

  local exetaResButton = toolsPanel:recursiveGetChildById("exetaResButton0")
  if exetaResButton then
    exetaResButton.onClick = function()
      assignTrainingSpell(exetaResButton, false, false, true, false)
    end
    exetaResButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.exetaRes and helperConfig.exetaRes[1] and helperConfig.exetaRes[1].id > 0 then
          menu:addOption(tr('Edit Exeta Res Spell'), function() assignTrainingSpell(exetaResButton, false, false, true, false) end)
          menu:addOption(tr('Remove'), function() removeAction("exetaRes", exetaResButton) end)
        else
          menu:addOption(tr('Assign Exeta Res Spell'), function() assignTrainingSpell(exetaResButton, false, false, true, false) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  local ampResButton = toolsPanel:recursiveGetChildById("ampResButton0")
  if ampResButton then
    ampResButton.onClick = function()
      assignTrainingSpell(ampResButton, false, false, false, true)
    end
    ampResButton.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        if helperConfig.ampRes and helperConfig.ampRes[1] and helperConfig.ampRes[1].id > 0 then
          menu:addOption(tr('Edit Auto Amp Res Spell'), function() assignTrainingSpell(ampResButton, false, false, false, true) end)
          menu:addOption(tr('Remove'), function() removeAction("ampRes", ampResButton) end)
        else
          menu:addOption(tr('Assign Auto Amp Res Spell'), function() assignTrainingSpell(ampResButton, false, false, false, true) end)
        end
        menu:display(mousePos)
        return true
      end
      return false
    end
  end

  -- Carregar auto food para UI
  _Helper.AutoFood.loadToUI()

  -- Carregar auto target para UI
  _Helper.AutoTarget.loadToUI()

  -- Populate presets combobox with saved profiles
  loadProfileOptions()

  loadShooterProfileByName(helperConfig.selectedShooterProfile)

  local reconnect = toolsPanel:recursiveGetChildById("reconnect")
  if reconnect then reconnect:setChecked(helperConfig.autoReconnect) end

  local changeGold = toolsPanel:recursiveGetChildById("changeGold")
  if changeGold then changeGold:setChecked(helperConfig.autoChangeGold) end

  -- Carregar paineis de vocação e automações (Exercise Training, Quiver Refill, Magic Shield, Auto Follow, Auto Bless)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.loadToUI()
  end

  local enableMagicShooter = enableButtons:recursiveGetChildById("enableMagicShooter")
  if enableMagicShooter then enableMagicShooter:setChecked(helperConfig.magicShooterEnabled) end

  local disableInProtectZone = enableButtons:recursiveGetChildById("disableInProtectZone")
  if disableInProtectZone then disableInProtectZone:setChecked(helperConfig.disableInProtectZone) end

  botStatus()

  -- Carregar configuração do equip panel
  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.loadConfig then
    if helperConfig.equipConfig then
      modules.game_helper.equip.loadConfig(helperConfig.equipConfig)
    end
  end

  if helperConfig.friendhealing then
    local sioPanel = healingPanel:recursiveGetChildById('friendHealingPanel')
    if sioPanel then
      local vocations = { "Knight", "Paladin", "Sorcerer", "Druid", "Monk" }
      for _, vocName in ipairs(vocations) do
        local vocKey = vocName:lower()
        local config = helperConfig.friendhealing[vocKey]
        if config then
          local enableCb = sioPanel:recursiveGetChildById("enableFriend" .. vocName)
          if enableCb then enableCb:setChecked(config.enabled or false) end
          local percentCb = sioPanel:recursiveGetChildById("friendPercent" .. vocName)
          if percentCb and config.percent then percentCb:setCurrentOption(tostring(config.percent) .. "%") end
          local prioCb = sioPanel:recursiveGetChildById("friendPriority" .. vocName)
          if prioCb and config.priority then prioCb:setCurrentOption(tostring(config.priority)) end
        end
      end
    end
  end

  if helperConfig.gransiohealing then
    local granPanel = healingPanel:recursiveGetChildById('granSioPanel')
    if granPanel then
      local vocations = { "Knight", "Paladin", "Sorcerer", "Druid", "Monk" }
      for _, vocName in ipairs(vocations) do
        local vocKey = vocName:lower()
        local config = helperConfig.gransiohealing[vocKey]
        if config then
          local enableCb = granPanel:recursiveGetChildById("enableGranSio" .. vocName)
          if enableCb then enableCb:setChecked(config.enabled or false) end
          local percentCb = granPanel:recursiveGetChildById("granSioPercent" .. vocName)
          if percentCb and config.percent then percentCb:setCurrentOption(tostring(config.percent) .. "%") end
          local prioCb = granPanel:recursiveGetChildById("granSioPriority" .. vocName)
          if prioCb and config.priority then prioCb:setCurrentOption(tostring(config.priority)) end
        end
      end
    end
  end

  if helperConfig.masreshealing then
    local masPanel = healingPanel:recursiveGetChildById('masResPanel')
    if masPanel then
      local vocations = { "Knight", "Paladin", "Sorcerer", "Druid", "Monk" }
      for _, vocName in ipairs(vocations) do
        local vocKey = vocName:lower()
        local config = helperConfig.masreshealing[vocKey]
        if config then
          local enableCb = masPanel:recursiveGetChildById("enableMasRes" .. vocName)
          if enableCb then enableCb:setChecked(config.enabled or false) end
          local percentCb = masPanel:recursiveGetChildById("masResPercent" .. vocName)
          if percentCb and config.percent then percentCb:setCurrentOption(tostring(config.percent) .. "%") end
          local prioCb = masPanel:recursiveGetChildById("masResPriority" .. vocName)
          if prioCb and config.priority then prioCb:setCurrentOption(tostring(config.priority)) end
        end
      end
      local extendedCb = masPanel:recursiveGetChildById("masResExtended")
      if extendedCb then extendedCb:setChecked(helperConfig.masreshealing.extended or false) end
    end
  end

  if healingTargetModePanel and healingTargetModeRadio then
    local mode = helperConfig.healingTargetMode or "party"
    local screenBtn = healingTargetModePanel:recursiveGetChildById("targetModeScreen")
    local partyBtn = healingTargetModePanel:recursiveGetChildById("targetModeParty")
    if mode == "screen" and screenBtn then
      healingTargetModeRadio:selectWidget(screenBtn)
    elseif partyBtn then
      healingTargetModeRadio:selectWidget(partyBtn)
    end
  end

  -- Sincronizar shortcut panel com os dados carregados
  _Helper.Shortcut.syncPanelState()

  -- Allow saving now that config is loaded
  skipSaveUntilLoaded = false

  -- Rebuild cache after loading all data
  rebuildHealingCache()
end

-- SAVE
function saveSettings()
  if skipSaveUntilLoaded then
    return
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return
  end

  local dir    = "/characterdata/" .. currentPlayer:getId()
  local folder = dir .. "/helper.json"

  g_resources.makeDir(dir)

  local cleanConfig = {}
  for k, v in pairs(helperConfig) do
    if type(v) ~= "function" then
      cleanConfig[k] = v
    end
  end

  -- Salvar estado do helper enabled
  cleanConfig.helperAutomaticFunctionsEnabled = helperAutomaticFunctionsEnabled

  -- Salvar configuração do equip panel
  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.saveConfig then
    cleanConfig.equipConfig = modules.game_helper.equip.saveConfig()
  end

  cleanConfig.shortcutsVisible = _Helper.Shortcut.isVisible()

  local status, result = pcall(function()
    return json.encode(cleanConfig, 2)
  end)
  if not status then
    return
  end

  if result:len() > 100 * 1024 * 1024 then
    return
  end

  -- Safely attempt to write the file
  local writeStatus, writeError = pcall(function()
    return g_resources.writeFileContents(folder, result)
  end)

  if not writeStatus then
    g_logger.debug("Could not save helper settings: " .. tostring(writeError))
  end
end

function saveHelperSettings()
  saveSettings()
  modules.game_textmessage.displayGameMessage("Helper configuration saved successfully!")
end

function loadSettings()
  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return false
  end

  -- mesmo caminho usado no saveSettings
  local folder = "/characterdata/" .. currentPlayer:getId() .. "/helper.json"

  if not g_resources.fileExists(folder) then
    local specialFoodsDefault = {
      hp = {
        { id = 11586, enabled = false, percent = 80, priority = 1 },
        { id = 9079,  enabled = false, percent = 80, priority = 2 },
        { id = 29414, enabled = false, percent = 80, priority = 3 },
        { id = 28485, enabled = false, percent = 80, priority = 4 },
      },
      mana = {
        { id = 29415, enabled = false, percent = 60, priority = 1 },
        { id = 28484, enabled = false, percent = 60, priority = 2 },
        { id = 9086,  enabled = false, percent = 60, priority = 3 },
      }
    }
    -- Preservar campos de hotkey antes de resetar
    local savedHotkeyCode = helperConfig.hotkeyCode
    local savedHotkeyFunc = helperConfig.hotkeyFunc
    local savedAutoTargetHotkeyCode = helperConfig.autoTargetHotkeyCode
    local savedAutoTargetHotkeyFunc = helperConfig.autoTargetHotkeyFunc
    local savedMagicShooterHotkeyCode = helperConfig.magicShooterHotkeyCode
    local savedMagicShooterHotkeyFunc = helperConfig.magicShooterHotkeyFunc
    local savedTargetMagicShooterHotkeyCode = helperConfig.targetMagicShooterHotkeyCode
    local savedTargetMagicShooterHotkeyFunc = helperConfig.targetMagicShooterHotkeyFunc
    local savedPresetHotkeyCode = helperConfig.presetHotkeyCode
    local savedPresetHotkeyFunc = helperConfig.presetHotkeyFunc
    local savedEquipmentHotkeyCode = helperConfig.equipmentHotkeyCode
    local savedEquipmentHotkeyFunc = helperConfig.equipmentHotkeyFunc
    local savedCavebotHotkeyCode = helperConfig.cavebotHotkeyCode
    local savedCavebotHotkeyFunc = helperConfig.cavebotHotkeyFunc
    local savedRecordingHotkeyCode = helperConfig.recordingHotkeyCode
    local savedRecordingHotkeyFunc = helperConfig.recordingHotkeyFunc
    local savedScriptsStopAllHotkeyCode = helperConfig.scriptsStopAllHotkeyCode
    local savedScriptsStopAllHotkeyFunc = helperConfig.scriptsStopAllHotkeyFunc
    local savedSmartFollowHotkeyCode = helperConfig.smartFollowHotkeyCode
    local savedSmartFollowHotkeyFunc = helperConfig.smartFollowHotkeyFunc

    -- Resetar helperConfig para defaults (file not exists)
    helperConfig = {
      spells                 = {
        { id = 0, percent = 80 },
        { id = 0, percent = 80 },
        { id = 0, percent = 80 }
      },
      potions                = {
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 }
      },
      training               = { { id = 0, percent = 0, enabled = false } },
      haste                  = { { id = 0, enabled = false, safecast = false } },
      itemTimer              = {
        { itemId = 0, intervalSeconds = 60, enabled = false },
        { itemId = 0, intervalSeconds = 60, enabled = false }
      },
      exetaRes               = { { id = 0, minCreatures = 1, creatureName = "", enabled = false } },
      ampRes                 = { { id = 0, minCreatures = 1, enabled = false } },
      friendhealing          = newVocHealingConfig(),
      gransiohealing         = newVocHealingConfig(),
      masreshealing          = newMasResHealingConfig(),
      shooterProfiles        = { ["Default"] = deepCopy(defaultShooterProfile) },
      selectedShooterProfile = "Default",
      autoEatFood            = false,
      autoReconnect          = false,
      autoChangeGold         = false,
      magicShooterEnabled    = false,
      magicShooterOnHold     = false,
      disableInProtectZone   = true,
      disableShooterOnFollow = false,
      autoTargetEnabled      = false,
      autoTargetMode         = (g_helperCore and g_helperCore.getAutoTargetModeId and g_helperCore.getAutoTargetModeId("F")) or 6,
      currentLockedTargetId  = 0,
      keepWayDistance        = 0,
      avoidWaves             = false,
      autoFollow             = false,
      autoBless              = false,
      advertisingChannel     = false,
      advertisingText        = "",
      ignoreMonsterList      = "",
      priorityMonsterList    = "",
      scripts                = {},
      healingTargetMode      = "party",
      specialFoods           = specialFoodsDefault
    }

    -- Restaurar campos de hotkey
    helperConfig.hotkeyCode = savedHotkeyCode
    helperConfig.hotkeyFunc = savedHotkeyFunc
    helperConfig.autoTargetHotkeyCode = savedAutoTargetHotkeyCode
    helperConfig.autoTargetHotkeyFunc = savedAutoTargetHotkeyFunc
    helperConfig.magicShooterHotkeyCode = savedMagicShooterHotkeyCode
    helperConfig.magicShooterHotkeyFunc = savedMagicShooterHotkeyFunc
    helperConfig.targetMagicShooterHotkeyCode = savedTargetMagicShooterHotkeyCode
    helperConfig.targetMagicShooterHotkeyFunc = savedTargetMagicShooterHotkeyFunc
    helperConfig.presetHotkeyCode = savedPresetHotkeyCode
    helperConfig.presetHotkeyFunc = savedPresetHotkeyFunc
    helperConfig.equipmentHotkeyCode = savedEquipmentHotkeyCode
    helperConfig.equipmentHotkeyFunc = savedEquipmentHotkeyFunc
    helperConfig.cavebotHotkeyCode = savedCavebotHotkeyCode
    helperConfig.cavebotHotkeyFunc = savedCavebotHotkeyFunc
    helperConfig.recordingHotkeyCode = savedRecordingHotkeyCode
    helperConfig.recordingHotkeyFunc = savedRecordingHotkeyFunc
    helperConfig.scriptsStopAllHotkeyCode = savedScriptsStopAllHotkeyCode
    helperConfig.scriptsStopAllHotkeyFunc = savedScriptsStopAllHotkeyFunc
    helperConfig.smartFollowHotkeyCode = savedSmartFollowHotkeyCode
    helperConfig.smartFollowHotkeyFunc = savedSmartFollowHotkeyFunc

    helperAutomaticFunctionsEnabled = true
    return false
  end

  local status, result = pcall(function()
    return json.decode(g_resources.readFileContents(folder))
  end)

  if not status or not result then
    local specialFoodsDefaultErr = {
      hp = {
        { id = 11586, enabled = false, percent = 80, priority = 1 },
        { id = 9079,  enabled = false, percent = 80, priority = 2 },
        { id = 29414, enabled = false, percent = 80, priority = 3 },
        { id = 28485, enabled = false, percent = 80, priority = 4 },
      },
      mana = {
        { id = 29415, enabled = false, percent = 60, priority = 1 },
        { id = 28484, enabled = false, percent = 60, priority = 2 },
        { id = 9086,  enabled = false, percent = 60, priority = 3 },
      }
    }
    -- Preservar campos de hotkey antes de resetar
    local savedHotkeyCode = helperConfig.hotkeyCode
    local savedHotkeyFunc = helperConfig.hotkeyFunc
    local savedAutoTargetHotkeyCode = helperConfig.autoTargetHotkeyCode
    local savedAutoTargetHotkeyFunc = helperConfig.autoTargetHotkeyFunc
    local savedMagicShooterHotkeyCode = helperConfig.magicShooterHotkeyCode
    local savedMagicShooterHotkeyFunc = helperConfig.magicShooterHotkeyFunc
    local savedTargetMagicShooterHotkeyCode = helperConfig.targetMagicShooterHotkeyCode
    local savedTargetMagicShooterHotkeyFunc = helperConfig.targetMagicShooterHotkeyFunc
    local savedPresetHotkeyCode = helperConfig.presetHotkeyCode
    local savedPresetHotkeyFunc = helperConfig.presetHotkeyFunc
    local savedEquipmentHotkeyCode = helperConfig.equipmentHotkeyCode
    local savedEquipmentHotkeyFunc = helperConfig.equipmentHotkeyFunc
    local savedCavebotHotkeyCode = helperConfig.cavebotHotkeyCode
    local savedCavebotHotkeyFunc = helperConfig.cavebotHotkeyFunc
    local savedRecordingHotkeyCode = helperConfig.recordingHotkeyCode
    local savedRecordingHotkeyFunc = helperConfig.recordingHotkeyFunc
    local savedScriptsStopAllHotkeyCode = helperConfig.scriptsStopAllHotkeyCode
    local savedScriptsStopAllHotkeyFunc = helperConfig.scriptsStopAllHotkeyFunc
    local savedSmartFollowHotkeyCode = helperConfig.smartFollowHotkeyCode
    local savedSmartFollowHotkeyFunc = helperConfig.smartFollowHotkeyFunc

    -- defaults (parsing error)
    helperConfig = {
      spells                 = {
        { id = 0, percent = 80 },
        { id = 0, percent = 80 },
        { id = 0, percent = 80 }
      },
      potions                = {
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 },
        { id = 0, percent = 50, priority = 0 }
      },
      training               = { { id = 0, percent = 0, enabled = false } },
      haste                  = { { id = 0, enabled = false, safecast = false } },
      itemTimer              = {
        { itemId = 0, intervalSeconds = 60, enabled = false },
        { itemId = 0, intervalSeconds = 60, enabled = false }
      },
      exetaRes               = { { id = 0, minCreatures = 1, creatureName = "", enabled = false } },
      ampRes                 = { { id = 0, minCreatures = 1, enabled = false } },
      friendhealing          = newVocHealingConfig(),
      gransiohealing         = newVocHealingConfig(),
      masreshealing          = newMasResHealingConfig(),
      shooterProfiles        = { ["Default"] = deepCopy(defaultShooterProfile) },
      selectedShooterProfile = "Default",
      autoEatFood            = false,
      autoReconnect          = false,
      autoChangeGold         = false,
      magicShooterEnabled    = false,
      magicShooterOnHold     = false,
      disableInProtectZone   = true,
      disableShooterOnFollow = false,
      autoTargetEnabled      = false,
      autoTargetMode         = (g_helperCore and g_helperCore.getAutoTargetModeId and g_helperCore.getAutoTargetModeId("F")) or 6,
      currentLockedTargetId  = 0,
      keepWayDistance        = 0,
      avoidWaves             = false,
      autoFollow             = false,
      autoBless              = false,
      advertisingChannel     = false,
      advertisingText        = "",
      ignoreMonsterList      = "",
      priorityMonsterList    = "",
      scripts                = {},
      healingTargetMode      = "party",
      specialFoods           = specialFoodsDefaultErr
    }

    -- Restaurar campos de hotkey
    helperConfig.hotkeyCode = savedHotkeyCode
    helperConfig.hotkeyFunc = savedHotkeyFunc
    helperConfig.autoTargetHotkeyCode = savedAutoTargetHotkeyCode
    helperConfig.autoTargetHotkeyFunc = savedAutoTargetHotkeyFunc
    helperConfig.magicShooterHotkeyCode = savedMagicShooterHotkeyCode
    helperConfig.magicShooterHotkeyFunc = savedMagicShooterHotkeyFunc
    helperConfig.targetMagicShooterHotkeyCode = savedTargetMagicShooterHotkeyCode
    helperConfig.targetMagicShooterHotkeyFunc = savedTargetMagicShooterHotkeyFunc
    helperConfig.presetHotkeyCode = savedPresetHotkeyCode
    helperConfig.presetHotkeyFunc = savedPresetHotkeyFunc
    helperConfig.equipmentHotkeyCode = savedEquipmentHotkeyCode
    helperConfig.equipmentHotkeyFunc = savedEquipmentHotkeyFunc
    helperConfig.cavebotHotkeyCode = savedCavebotHotkeyCode
    helperConfig.cavebotHotkeyFunc = savedCavebotHotkeyFunc
    helperConfig.recordingHotkeyCode = savedRecordingHotkeyCode
    helperConfig.recordingHotkeyFunc = savedRecordingHotkeyFunc
    helperConfig.scriptsStopAllHotkeyCode = savedScriptsStopAllHotkeyCode
    helperConfig.scriptsStopAllHotkeyFunc = savedScriptsStopAllHotkeyFunc
    helperConfig.smartFollowHotkeyCode = savedSmartFollowHotkeyCode
    helperConfig.smartFollowHotkeyFunc = savedSmartFollowHotkeyFunc

    return false
  end

  -- Preservar funções de hotkey (não são serializáveis, então não vêm do arquivo)
  local savedHotkeyFunc = helperConfig.hotkeyFunc
  local savedAutoTargetHotkeyFunc = helperConfig.autoTargetHotkeyFunc
  local savedMagicShooterHotkeyFunc = helperConfig.magicShooterHotkeyFunc
  local savedTargetMagicShooterHotkeyFunc = helperConfig.targetMagicShooterHotkeyFunc
  local savedPresetHotkeyFunc = helperConfig.presetHotkeyFunc
  local savedEquipmentHotkeyFunc = helperConfig.equipmentHotkeyFunc
  local savedCavebotHotkeyFunc = helperConfig.cavebotHotkeyFunc
  local savedRecordingHotkeyFunc = helperConfig.recordingHotkeyFunc
  local savedScriptsStopAllHotkeyFunc = helperConfig.scriptsStopAllHotkeyFunc
  local savedSmartFollowHotkeyFunc = helperConfig.smartFollowHotkeyFunc
  local codeDisableShooterOnFollow = helperConfig.disableShooterOnFollow

  helperConfig = result

  -- Restaurar apenas as funções de hotkey (os códigos vêm do arquivo)
  helperConfig.hotkeyFunc = savedHotkeyFunc
  helperConfig.autoTargetHotkeyFunc = savedAutoTargetHotkeyFunc
  helperConfig.magicShooterHotkeyFunc = savedMagicShooterHotkeyFunc
  helperConfig.targetMagicShooterHotkeyFunc = savedTargetMagicShooterHotkeyFunc
  helperConfig.presetHotkeyFunc = savedPresetHotkeyFunc
  helperConfig.equipmentHotkeyFunc = savedEquipmentHotkeyFunc
  helperConfig.cavebotHotkeyFunc = savedCavebotHotkeyFunc
  helperConfig.recordingHotkeyFunc = savedRecordingHotkeyFunc
  helperConfig.scriptsStopAllHotkeyFunc = savedScriptsStopAllHotkeyFunc
  helperConfig.smartFollowHotkeyFunc = savedSmartFollowHotkeyFunc

  -- Restaurar estado do helper enabled
  if result.helperAutomaticFunctionsEnabled ~= nil then
    helperAutomaticFunctionsEnabled = result.helperAutomaticFunctionsEnabled
  end

  -- Restaurar estado do shortcuts visible
  if result.shortcutsVisible ~= nil then
    _Helper.Shortcut.setVisible(result.shortcutsVisible)
  end

  -- Ensure new keys exist if loading old config
  if helperConfig.autoFollow == nil then helperConfig.autoFollow = false end
  if helperConfig.autoBless == nil then helperConfig.autoBless = false end
  if helperConfig.advertisingChannel == nil then helperConfig.advertisingChannel = false end
  if helperConfig.advertisingText == nil then helperConfig.advertisingText = "" end
  if helperConfig.scripts == nil then helperConfig.scripts = {} end
  if codeDisableShooterOnFollow ~= nil then
    helperConfig.disableShooterOnFollow = codeDisableShooterOnFollow
  else
    helperConfig.disableShooterOnFollow = false
  end

  -- spells
  if not helperConfig.spells then
    helperConfig.spells = {
      { id = 0, percent = 80 },
      { id = 0, percent = 80 },
      { id = 0, percent = 80 }
    }
  end
  if #helperConfig.spells < 3 then
    table.insert(helperConfig.spells, { id = 0, percent = 0 })
  end
  for _, k in pairs(helperConfig.spells) do
    if k.percent == 0 then
      k.percent = 80
    end
  end

  -- potions
  if not helperConfig.potions then
    helperConfig.potions = {
      { id = 0, percent = 50, priority = 0 },
      { id = 0, percent = 50, priority = 0 },
      { id = 0, percent = 50, priority = 0 }
    }
  end
  for _, k in pairs(helperConfig.potions) do
    if k.percent == 0 then k.percent = 50 end
    if not k.priority then k.priority = 0 end
    if not k.id then k.id = 0 end
  end

  if not helperConfig.training then
    helperConfig.training = { { id = 0, percent = 0, enabled = false } }
  end
  if not helperConfig.haste then
    helperConfig.haste = { { id = 0, enabled = false, safecast = false } }
  end
  if not helperConfig.itemTimer then
    helperConfig.itemTimer = {
      { itemId = 0, intervalSeconds = 60, enabled = false },
      { itemId = 0, intervalSeconds = 60, enabled = false }
    }
  elseif not helperConfig.itemTimer[1] then
    local old = helperConfig.itemTimer
    helperConfig.itemTimer = {
      { itemId = old.itemId or 0, intervalSeconds = old.intervalSeconds or 60, enabled = old.enabled or false },
      { itemId = 0, intervalSeconds = 60, enabled = false }
    }
  elseif not helperConfig.itemTimer[2] then
    helperConfig.itemTimer[2] = { itemId = 0, intervalSeconds = 60, enabled = false }
  end
  if not helperConfig.exetaRes or not helperConfig.exetaRes[1] then
    helperConfig.exetaRes = { { id = 0, minCreatures = 1, creatureName = "", enabled = false } }
  end
  if not helperConfig.ampRes or not helperConfig.ampRes[1] then
    helperConfig.ampRes = { { id = 0, minCreatures = 1, enabled = false } }
  end
  if not helperConfig.utito then
    helperConfig.utito = { { id = 0, enabled = false, safecast = false } }
  end
  local defaultVocHealing = {
    knight = { enabled = false, percent = 90, priority = 5 },
    paladin = { enabled = false, percent = 90, priority = 4 },
    sorcerer = { enabled = false, percent = 90, priority = 3 },
    druid = { enabled = false, percent = 90, priority = 2 },
    monk = { enabled = false, percent = 90, priority = 1 },
  }
  if not helperConfig.friendhealing or helperConfig.friendhealing[1] ~= nil then
    helperConfig.friendhealing = deepCopy(defaultVocHealing)
  end
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.friendhealing[voc] then
      helperConfig.friendhealing[voc] = deepCopy(def)
    end
    local v = helperConfig.friendhealing[voc]
    if v.enabled == nil then v.enabled = false end
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  if not helperConfig.gransiohealing or helperConfig.gransiohealing[1] ~= nil then
    helperConfig.gransiohealing = deepCopy(defaultVocHealing)
  end
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.gransiohealing[voc] then
      helperConfig.gransiohealing[voc] = deepCopy(def)
    end
    local v = helperConfig.gransiohealing[voc]
    if v.enabled == nil then v.enabled = false end
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  if not helperConfig.masreshealing or helperConfig.masreshealing[1] ~= nil then
    helperConfig.masreshealing = deepCopy(defaultVocHealing)
  end
  for voc, def in pairs(defaultVocHealing) do
    if not helperConfig.masreshealing[voc] then
      helperConfig.masreshealing[voc] = deepCopy(def)
    end
    local v = helperConfig.masreshealing[voc]
    if v.enabled == nil then v.enabled = false end
    if not v.percent then v.percent = 90 end
    if not v.priority then v.priority = def.priority end
  end
  if helperConfig.masreshealing.extended == nil then
    helperConfig.masreshealing.extended = false
  end
  if not helperConfig.shooterProfiles then
    helperConfig.selectedShooterProfile = "Default"
    helperConfig.shooterProfiles = { ["Default"] = defaultShooterProfile }
  end
  -- Validate selectedShooterProfile exists, fallback to Default if not
  if not helperConfig.selectedShooterProfile or not helperConfig.shooterProfiles[helperConfig.selectedShooterProfile] then
    helperConfig.selectedShooterProfile = "Default"
    -- Ensure Default profile exists
    if not helperConfig.shooterProfiles["Default"] then
      helperConfig.shooterProfiles["Default"] = deepCopy(defaultShooterProfile)
    end
  end
  for _, profile in pairs(helperConfig.shooterProfiles) do
    if not profile.autoTargetMode then
      profile.autoTargetMode = (g_helperCore and g_helperCore.getAutoTargetModeId and g_helperCore.getAutoTargetModeId("F")) or 6
    end
  end

  if helperConfig.autoEatFood == nil then
    helperConfig.autoEatFood = false
  end
  if helperConfig.autoReconnect == nil then
    helperConfig.autoReconnect = false
  end
  if helperConfig.autoChangeGold == nil then
    helperConfig.autoChangeGold = false
  end
  if helperConfig.magicShooterEnabled == nil then
    helperConfig.magicShooterEnabled = false
  end
  if helperConfig.magicShooterOnHold == nil then
    helperConfig.magicShooterOnHold = false
  end
  if helperConfig.disableInProtectZone == nil then
    helperConfig.disableInProtectZone = true
  end
  if helperConfig.autoTargetEnabled == nil then
    helperConfig.autoTargetEnabled = false
  end
  if not helperConfig.autoTargetMode then
    helperConfig.autoTargetMode = (g_helperCore and g_helperCore.getAutoTargetModeId and g_helperCore.getAutoTargetModeId("F")) or 6
  end
  if not helperConfig.currentLockedTargetId then
    helperConfig.currentLockedTargetId = 0
  end
  if helperConfig.keepWayDistance == nil then
    helperConfig.keepWayDistance = 0
  end
  if helperConfig.avoidWaves == nil then
    helperConfig.avoidWaves = false
  end
  if helperConfig.ignoreMonsterList == nil then
    helperConfig.ignoreMonsterList = ""
  end
  if helperConfig.priorityMonsterList == nil then
    helperConfig.priorityMonsterList = ""
  end

  -- Initialize quiverRefill defaults if not present
  if not helperConfig.quiverRefill then
    helperConfig.quiverRefill = {
      enabled = false,
      itemId = 0,
      minValue = 50,
      refillValue = 100
    }
  else
    -- Ensure all fields have defaults
    if helperConfig.quiverRefill.enabled == nil then
      helperConfig.quiverRefill.enabled = false
    end
    if not helperConfig.quiverRefill.itemId then
      helperConfig.quiverRefill.itemId = 0
    end
    if not helperConfig.quiverRefill.minValue then
      helperConfig.quiverRefill.minValue = 50
    end
    if not helperConfig.quiverRefill.refillValue then
      helperConfig.quiverRefill.refillValue = 100
    end
  end

  -- Initialize magicShield defaults if not present
  if not helperConfig.magicShield then
    helperConfig.magicShield = {
      utamoEnabled = false,
      exanaEnabled = false,
      potionEnabled = false,
      utamoHpPercent = 80,
      exanaHpPercent = 90
    }
  else
    -- Ensure all fields have defaults
    if helperConfig.magicShield.utamoEnabled == nil then
      helperConfig.magicShield.utamoEnabled = false
    end
    if helperConfig.magicShield.exanaEnabled == nil then
      helperConfig.magicShield.exanaEnabled = false
    end
    if helperConfig.magicShield.potionEnabled == nil then
      helperConfig.magicShield.potionEnabled = false
    end
    if not helperConfig.magicShield.utamoHpPercent then
      helperConfig.magicShield.utamoHpPercent = 80
    end
    if not helperConfig.magicShield.exanaHpPercent then
      helperConfig.magicShield.exanaHpPercent = 90
    end
  end

  local expectedHpFoods = {
    { id = 11586, enabled = false, percent = 80, priority = 1 },
    { id = 9079,  enabled = false, percent = 80, priority = 2 },
    { id = 29414, enabled = false, percent = 80, priority = 3 },
    { id = 28485, enabled = false, percent = 80, priority = 4 },
  }
  local expectedManaFoods = {
    { id = 29415, enabled = false, percent = 60, priority = 1 },
    { id = 28484, enabled = false, percent = 60, priority = 2 },
    { id = 9086,  enabled = false, percent = 60, priority = 3 },
  }
  if not helperConfig.specialFoods then
    helperConfig.specialFoods = {}
  end
  local oldHp = helperConfig.specialFoods.hp or {}
  local oldHpById = {}
  for _, f in pairs(oldHp) do
    if f.id then oldHpById[f.id] = f end
  end
  helperConfig.specialFoods.hp = {}
  for i, def in ipairs(expectedHpFoods) do
    local saved = oldHpById[def.id]
    helperConfig.specialFoods.hp[i] = {
      id = def.id,
      enabled = saved and saved.enabled or false,
      percent = (saved and saved.percent and saved.percent > 0) and saved.percent or def.percent,
      priority = (saved and saved.priority and saved.priority > 0) and saved.priority or def.priority,
    }
  end
  local oldMana = helperConfig.specialFoods.mana or {}
  local oldManaById = {}
  for _, f in pairs(oldMana) do
    if f.id then oldManaById[f.id] = f end
  end
  helperConfig.specialFoods.mana = {}
  for i, def in ipairs(expectedManaFoods) do
    local saved = oldManaById[def.id]
    helperConfig.specialFoods.mana[i] = {
      id = def.id,
      enabled = saved and saved.enabled or false,
      percent = (saved and saved.percent and saved.percent > 0) and saved.percent or def.percent,
      priority = (saved and saved.priority and saved.priority > 0) and saved.priority or def.priority,
    }
  end
  if not helperConfig.healingTargetMode then
    helperConfig.healingTargetMode = "party"
  end

  return true
end

-- Wrapper function for Exercise Event (OTUI compatibility)
-- NOTE: Exercise training now uses its own cycle event in _Helper.ExerciseTraining
-- The eventTable polling is disabled to prevent redundant checks
function checkExerciseEvent()
  -- Delegated to the ExerciseTraining class which has its own cycle event
  -- This function is kept for backwards compatibility but the eventTable action is disabled
end

-- Wrapper function for getting exercise dummy
function getExerciseDummy()
  if modules.game_helper and modules.game_helper.tools then
    return modules.game_helper.tools.getExerciseDummy()
  end
  return nil
end

-- Disabled: Exercise training now uses its own cycle event via _Helper.ExerciseTraining
-- eventTable.checkExerciseEvent.action = checkExerciseEvent

-- Check and equip items (rings/amulets) based on health conditions
function checkEquipItems()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end

  -- Call the equip module's check function
  if modules.game_helper and modules.game_helper.equip and modules.game_helper.equip.checkEquipItems then
    modules.game_helper.equip.checkEquipItems()
  end
end

eventTable.checkEquipItems.action = checkEquipItems

-- Check and refill quiver for paladins
function checkQuiverRefill()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end

  -- Call the tools module's check function
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkQuiverRefill then
    modules.game_helper.tools.checkQuiverRefill()
  end
end

eventTable.checkQuiverRefill.action = checkQuiverRefill

-- Check and manage magic shield for mages
function checkMagicShield()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end

  -- Call the tools module's check function
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkMagicShield then
    modules.game_helper.tools.checkMagicShield()
  end
end

eventTable.checkMagicShield.action = checkMagicShield

function checkItemTimer()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkItemTimer then
    modules.game_helper.tools.checkItemTimer()
  end
end
eventTable.checkItemTimer.action = checkItemTimer

function checkExetaRes()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkExetaRes then
    modules.game_helper.tools.checkExetaRes()
  end
end
eventTable.checkExetaRes.action = checkExetaRes

function checkAmpRes()
  if not g_game.isOnline() or not helperAutomaticFunctionsEnabled then return end
  if modules.game_helper and modules.game_helper.tools and modules.game_helper.tools.checkAmpRes then
    modules.game_helper.tools.checkAmpRes()
  end
end
eventTable.checkAmpRes.action = checkAmpRes

-- Wrapper function for assigning exercise event (OTUI compatibility)
function assignExerciseEvent(button)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.assignExerciseEvent(button)
  end
end

-- Wrapper function for assign exercise callback (OTUI compatibility)
function onAssignExercise(self, mousePosition, mouseButton, button)
  if modules.game_helper and modules.game_helper.tools then
    modules.game_helper.tools.onAssignExercise(self, mousePosition, mouseButton, button)
  end
end

function onCheckPotionPriority(button)
  local index = tonumber(button:getId():match("%d+"))
  local current = helperConfig.potions[index + 1].priority or 0
  local newPriority
  if current == 0 then
    newPriority = 1
  elseif current == 1 then
    newPriority = 2
  else
    newPriority = 1
  end
  helperConfig.potions[index + 1].priority = newPriority
  button:setImageSource("/images/ui/checkboxcircle")
  if newPriority == 1 then
    button:setImageColor("#d94a3a")
    button:setTooltip("This potion is healing health...")
  else
    button:setImageColor("#3a8ad9")
    button:setTooltip("This potion is healing mana...")
  end
  rebuildHealingCache()
end

function onPotionPriorityMouse(self, mousePosition, mouseButton)
  local index = tonumber(self:getId():match("%d+"))
  local current = helperConfig.potions[index + 1].priority or 0
  local newPriority = (current == 1) and 2 or 1
  helperConfig.potions[index + 1].priority = newPriority
  self:setImageSource("/images/ui/checkboxcircle")
  if newPriority == 1 then
    self:setImageColor("#d94a3a")
    self:setTooltip("This potion is healing health...")
  else
    self:setImageColor("#3a8ad9")
    self:setTooltip("This potion is healing mana...")
  end
  rebuildHealingCache()
end

local function initSpecialFoodsWindow()
  if not specialFoodsWindow or not helperConfig then return end

  local hpFoods = helperConfig.specialFoods and helperConfig.specialFoods.hp or {}
  for i, food in ipairs(hpFoods) do
    local slotIdx = i - 1
    local slot = specialFoodsWindow:recursiveGetChildById("hpFoodSlot" .. slotIdx)
    if slot and food.id and food.id ~= 0 then
      local existing = slot:getChildById('foodItem')
      if existing then existing:destroy() end
      local itemWidget = g_ui.createWidget('FoodItem', slot)
      itemWidget:setItemId(food.id)
      itemWidget:setId('foodItem')
    end
    local checkbox = specialFoodsWindow:recursiveGetChildById("hpFoodEnable" .. slotIdx)
    if checkbox then
      checkbox:setChecked(food.enabled or false)
    end
    local percentLabel = specialFoodsWindow:recursiveGetChildById("hpFoodPercentLabel" .. slotIdx)
    if percentLabel then
      percentLabel:setText(food.percent .. "%")
    end
    local priorityLabel = specialFoodsWindow:recursiveGetChildById("hpFoodPriorityLabel" .. slotIdx)
    if priorityLabel then
      priorityLabel:setText(tostring(food.priority or i))
    end
  end

  local manaFoods = helperConfig.specialFoods and helperConfig.specialFoods.mana or {}
  for i, food in ipairs(manaFoods) do
    local slotIdx = i - 1
    local slot = specialFoodsWindow:recursiveGetChildById("manaFoodSlot" .. slotIdx)
    if slot and food.id and food.id ~= 0 then
      local existing = slot:getChildById('foodItem')
      if existing then existing:destroy() end
      local itemWidget = g_ui.createWidget('FoodItem', slot)
      itemWidget:setItemId(food.id)
      itemWidget:setId('foodItem')
    end
    local checkbox = specialFoodsWindow:recursiveGetChildById("manaFoodEnable" .. slotIdx)
    if checkbox then
      checkbox:setChecked(food.enabled or false)
    end
    local percentLabel = specialFoodsWindow:recursiveGetChildById("manaFoodPercentLabel" .. slotIdx)
    if percentLabel then
      percentLabel:setText(food.percent .. "%")
    end
    local priorityLabel = specialFoodsWindow:recursiveGetChildById("manaFoodPriorityLabel" .. slotIdx)
    if priorityLabel then
      priorityLabel:setText(tostring(food.priority or i))
    end
  end
end

modules.game_helper = modules.game_helper or {}
do
  modules.game_helper.specialFoodsOpen = function()
    if specialFoodsWindow then
      specialFoodsWindow:destroy()
      specialFoodsWindow = nil
    end
    specialFoodsWindow = g_ui.createWidget('SpecialFoodsWindow', g_ui.getRootWidget())
    initSpecialFoodsWindow()
  end

  modules.game_helper.specialFoodsClose = function()
    if specialFoodsWindow then
      specialFoodsWindow:destroy()
      specialFoodsWindow = nil
    end
  end

  modules.game_helper.toggleSpecialFood = function(category, index, checked)
    if not helperConfig or not helperConfig.specialFoods then return end
    if not helperConfig.specialFoods[category] then return end
    if not helperConfig.specialFoods[category][index] then return end
    helperConfig.specialFoods[category][index].enabled = checked
    saveSettings()
  end

  modules.game_helper.updateSpecialFoodPercent = function(category, index, delta)
    if not helperConfig or not helperConfig.specialFoods then return end
    if not helperConfig.specialFoods[category] then return end
    if not helperConfig.specialFoods[category][index] then return end

    local food = helperConfig.specialFoods[category][index]
    local newPercent = (food.percent or 50) + delta
    if newPercent < 5 then newPercent = 5 end
    if newPercent > 99 then newPercent = 99 end
    food.percent = newPercent

    if specialFoodsWindow then
      local prefix = category == "hp" and "hpFoodPercentLabel" or "manaFoodPercentLabel"
      local label = specialFoodsWindow:recursiveGetChildById(prefix .. (index - 1))
      if label then
        label:setText(newPercent .. "%")
      end
    end

    saveSettings()
  end

  modules.game_helper.updateSpecialFoodPriority = function(category, index, delta)
    if not helperConfig or not helperConfig.specialFoods then return end
    if not helperConfig.specialFoods[category] then return end
    if not helperConfig.specialFoods[category][index] then return end

    local maxPriority = #helperConfig.specialFoods[category]
    local food = helperConfig.specialFoods[category][index]
    local newPriority = (food.priority or 1) + delta
    if newPriority < 1 then newPriority = 1 end
    if newPriority > maxPriority then newPriority = maxPriority end
    food.priority = newPriority

    if specialFoodsWindow then
      local prefix = category == "hp" and "hpFoodPriorityLabel" or "manaFoodPriorityLabel"
      local label = specialFoodsWindow:recursiveGetChildById(prefix .. (index - 1))
      if label then
        label:setText(tostring(newPriority))
      end
    end

    saveSettings()
  end

  modules.game_helper.onEnableVocFriend = function(vocation, checked)
    if helperConfig.friendhealing and helperConfig.friendhealing[vocation] then
      helperConfig.friendhealing[vocation].enabled = checked
      saveSettings()
    end
  end

  modules.game_helper.onEnableVocGranSio = function(vocation, checked)
    if helperConfig.gransiohealing and helperConfig.gransiohealing[vocation] then
      helperConfig.gransiohealing[vocation].enabled = checked
      saveSettings()
    end
  end

  modules.game_helper.onEnableVocMasRes = function(vocation, checked)
    if helperConfig.masreshealing and helperConfig.masreshealing[vocation] then
      helperConfig.masreshealing[vocation].enabled = checked
      saveSettings()
    end
  end

  modules.game_helper.onMasResExtendedChange = function(checked)
    if helperConfig.masreshealing then
      helperConfig.masreshealing.extended = checked
      saveSettings()
    end
  end

  modules.game_helper.updateVocFriendPercent = function(vocation, newPercent)
    if helperConfig.friendhealing and helperConfig.friendhealing[vocation] then
      helperConfig.friendhealing[vocation].percent = tonumber(newPercent)
      saveSettings()
    end
  end

  modules.game_helper.updateVocGranSioPercent = function(vocation, newPercent)
    if helperConfig.gransiohealing and helperConfig.gransiohealing[vocation] then
      helperConfig.gransiohealing[vocation].percent = tonumber(newPercent)
      saveSettings()
    end
  end

  modules.game_helper.updateVocMasResPercent = function(vocation, newPercent)
    if helperConfig.masreshealing and helperConfig.masreshealing[vocation] then
      helperConfig.masreshealing[vocation].percent = tonumber(newPercent)
      saveSettings()
    end
  end

  modules.game_helper.updateVocFriendPriority = function(vocation, newPriority)
    if helperConfig.friendhealing and helperConfig.friendhealing[vocation] then
      helperConfig.friendhealing[vocation].priority = tonumber(newPriority)
      saveSettings()
    end
  end

  modules.game_helper.updateVocGranSioPriority = function(vocation, newPriority)
    if helperConfig.gransiohealing and helperConfig.gransiohealing[vocation] then
      helperConfig.gransiohealing[vocation].priority = tonumber(newPriority)
      saveSettings()
    end
  end

  modules.game_helper.updateVocMasResPriority = function(vocation, newPriority)
    if helperConfig.masreshealing and helperConfig.masreshealing[vocation] then
      helperConfig.masreshealing[vocation].priority = tonumber(newPriority)
      saveSettings()
    end
  end
end

function botStatus()
  if not helper or not helper.contentPanel then
    return
  end

  local helperStatus = helper.contentPanel:recursiveGetChildById("helperStatus")
  local helperStatusLabel = helper.contentPanel:recursiveGetChildById("helperStatusLabel")
  local setKeyButton = helper.contentPanel:recursiveGetChildById("setKeyHelperButton")

  if not helperStatusLabel then
    return
  end

  -- VISUAL STATUS
  if helperAutomaticFunctionsEnabled then
    if helperStatus then
      helperStatus:setImageSource("/images/store/icon-yes")
      helperStatus:setTooltip("Enabled - Click to DISABLE auto functions OR LOAD config")
    end
    helperStatusLabel:setText("Enabled")
    helperStatusLabel:setColor("#3acb3a")
    if setKeyButton then
      setKeyButton:setText("On")
      setKeyButton:setColor("#3acb3a")
    end
  else
    if helperStatus then
      helperStatus:setImageSource("/images/store/icon-no")
      helperStatus:setTooltip("Disabled - Click to ENABLE auto functions OR LOAD config")
    end
    helperStatusLabel:setText("Disabled")
    helperStatusLabel:setColor("#d94a3a")
    if setKeyButton then
      setKeyButton:setText("Off")
      setKeyButton:setColor("#d94a3a")
    end
  end

  -- helperStatus = Toggle + Load Config
  if helperStatus and not helperStatus.clickHandlerSetup then
    helperStatus.onClick = function()
      -- Toggle status atual
      helperAutomaticFunctionsEnabled = not helperAutomaticFunctionsEnabled

      -- SEMPRE carrega config ao clicar (mesmo toggle)
      loadSettings()
      if healingPanel and toolsPanel then
        onLoadHelperData()
      end

      modules.game_textmessage.displayGameMessage("Helper toggled + Config LOADED!")

      botStatus() -- Refresh visual
      -- Sincronizar com shortcut panel
      _Helper.Shortcut.syncButton('shortcutHelper', helperAutomaticFunctionsEnabled)
    end
    helperStatus.clickHandlerSetup = true
  end
end

function toggleNextWindow()
  local widgetList = {
    "healingMenu",
    "toolsMenu",
    "scriptsMenu",
    "shooterMenu",
    "equipMenu",
    "cavebotMenu",
  }

  local selectedIndex = nil
  for i, widget in ipairs(widgetList) do
    if widget == lastActiveMenu then
      selectedIndex = i
      break
    end
  end

  if not selectedIndex then
    selectedIndex = 1
  end

  local nextWidgetId = (selectedIndex == #widgetList and 1 or selectedIndex + 1)
  loadMenu(widgetList[nextWidgetId])
end

function toggleHelperFunctions()
  helperAutomaticFunctionsEnabled = not helperAutomaticFunctionsEnabled

  if helper then
    botStatus()
  end

  -- Sincronizar com shortcut panel
  _Helper.Shortcut.syncButton('shortcutHelper', helperAutomaticFunctionsEnabled)

  if saveSettings then
    saveSettings()
  end
end

function manageHotkeys(typo)
  if not helper then
    return
  end
  helper:hide()

  local rootWidget = g_ui.getRootWidget()
  if not rootWidget then
    helper:show(true)
    return
  end

  -- Esconde a janela de settings do cavebot se estiver configurando Recording
  if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
    modules.game_helper.cavebot.hideSettingsWindow()
  end

  local assignWindow = g_ui.createWidget('ActionAssignWindow', rootWidget)
  if not assignWindow then
    helper:show(true)
    -- Restaura a janela de settings do cavebot se foi escondida
    if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.showSettingsWindow()
    end
    return
  end

  assignWindow:setText(tostring(typo))

  local displayLabel = assignWindow:recursiveGetChildById('display')
  local descLabel = assignWindow:recursiveGetChildById('desc')
  local buttonOk = assignWindow:recursiveGetChildById('buttonOk')
  local buttonClose = assignWindow:recursiveGetChildById('buttonClose')
  local buttonClear = assignWindow:recursiveGetChildById('buttonClear')

  if not displayLabel or not descLabel or not buttonOk or not buttonClose then
    assignWindow:destroy()
    helper:show(true)
    return
  end

  -- Mapa de keyCodes para caracteres
  local keyCodeMap = {
    [49] = "1",
    [50] = "2",
    [51] = "3",
    [52] = "4",
    [53] = "5",
    [54] = "6",
    [55] = "7",
    [56] = "8",
    [57] = "9",
    [48] = "0",
    [65] = "A",
    [66] = "B",
    [67] = "C",
    [68] = "D",
    [69] = "E",
    [70] = "F",
    [71] = "G",
    [72] = "H",
    [73] = "I",
    [74] = "J",
    [75] = "K",
    [76] = "L",
    [77] = "M",
    [78] = "N",
    [79] = "O",
    [80] = "P",
    [81] = "Q",
    [82] = "R",
    [83] = "S",
    [84] = "T",
    [85] = "U",
    [86] = "V",
    [87] = "W",
    [88] = "X",
    [89] = "Y",
    [90] = "Z",
    [43] = "Plus", -- KeyPlus (regular +)
    [45] = "-",    -- KeyMinus (regular -)
    [141] = "Num0",
    [142] = "Num1",
    [143] = "Num2",
    [144] = "Num3",
    [145] = "Num4",
    [146] = "Num5",
    [147] = "Num6",
    [148] = "Num7",
    [149] = "Num8",
    [150] = "Num9",
    [151] = "NumEnter",
    [152] = "NumPlus",
    [153] = "NumMinus",
    [154] = "NumMultiply",
    [155] = "NumDivide",
    [156] = "NumDecimal",
  }

  local capturedKeyCode = nil
  local capturedKeyChar = ""

  -- Obter hotkey atual da função sendo configurada
  local currentHotkey = nil
  if typo == "Enable/Disable Helper" then
    currentHotkey = helperConfig.hotkeyCode
  elseif typo == "Enable/Disable Auto Target" then
    currentHotkey = helperConfig.autoTargetHotkeyCode
  elseif typo == "Enable/Disable Magic Shooter" then
    currentHotkey = helperConfig.magicShooterHotkeyCode
  elseif typo == "Enable/Disable Target and Magic Shooter" then
    currentHotkey = helperConfig.targetMagicShooterHotkeyCode
  elseif typo == "Change Shooter Preset" then
    currentHotkey = helperConfig.presetHotkeyCode
  elseif typo == "Enable/Disable Equipment" then
    currentHotkey = helperConfig.equipmentHotkeyCode
  elseif typo == "Enable/Disable Cavebot" then
    currentHotkey = helperConfig.cavebotHotkeyCode
  elseif typo == "Toggle Recording" then
    currentHotkey = helperConfig.recordingHotkeyCode
  elseif typo == "Stop all scripts" then
    currentHotkey = helperConfig.scriptsStopAllHotkeyCode
  elseif typo == "Enable/Disable Follow" then
    currentHotkey = helperConfig.smartFollowHotkeyCode
  end

  -- Mostrar hotkey atual ou placeholder
  if currentHotkey and currentHotkey ~= "" then
    displayLabel:setText(currentHotkey)
    capturedKeyChar = currentHotkey
    -- Habilitar botão Clear se há hotkey configurada
    if buttonClear then
      buttonClear:setEnabled(true)
    end
  else
    displayLabel:setText("(press a key)")
    -- Desabilitar botão Clear se não há hotkey configurada
    if buttonClear then
      buttonClear:setEnabled(false)
    end
  end

  descLabel:setText("Assign hotkey to: " .. tostring(typo))

  -- Função para verificar se hotkey está em uso por outra função do helper
  local function isHotkeyInUseByHelper(hotkey, currentType)
    if currentType ~= "Enable/Disable Helper" and helperConfig.hotkeyCode == hotkey then
      return "Enable/Disable Helper"
    end
    if currentType ~= "Enable/Disable Auto Target" and helperConfig.autoTargetHotkeyCode == hotkey then
      return "Enable/Disable Auto Target"
    end
    if currentType ~= "Enable/Disable Magic Shooter" and helperConfig.magicShooterHotkeyCode == hotkey then
      return "Enable/Disable Magic Shooter"
    end
    if currentType ~= "Enable/Disable Target and Magic Shooter" and helperConfig.targetMagicShooterHotkeyCode == hotkey then
      return "Enable/Disable Target and Magic Shooter"
    end
    if currentType ~= "Change Shooter Preset" and helperConfig.presetHotkeyCode == hotkey then
      return "Change Shooter Preset"
    end
    if currentType ~= "Enable/Disable Equipment" and helperConfig.equipmentHotkeyCode == hotkey then
      return "Enable/Disable Equipment"
    end
    if currentType ~= "Enable/Disable Cavebot" and helperConfig.cavebotHotkeyCode == hotkey then
      return "Enable/Disable Cavebot"
    end
    if currentType ~= "Toggle Recording" and helperConfig.recordingHotkeyCode == hotkey then
      return "Toggle Recording"
    end
    if currentType ~= "Stop all scripts" and helperConfig.scriptsStopAllHotkeyCode == hotkey then
      return "Stop all scripts"
    end
    if currentType ~= "Enable/Disable Follow" and helperConfig.smartFollowHotkeyCode == hotkey then
      return "Enable/Disable Follow"
    end
    return nil
  end

  assignWindow.onKeyDown = function(widget, keyCode, keyboardModifiers, keyText)
    -- Ignora teclas de navegação
    if keyCode == KeyUp or keyCode == KeyDown or keyCode == KeyLeft or keyCode == KeyRight then
      return false
    end
    local keyCombo = determineKeyComboDesc(keyCode, keyboardModifiers, keyText)
    local resetCombo = { "Shift", "Ctrl", "Alt" }
    if table.contains(resetCombo, keyCombo) then
      assignWindow.display:setText('')
      assignWindow.warning:setVisible(false)
      assignWindow.buttonOk:setEnabled(true)
      return true
    end
    -- Converte keyCode para caractere legível
    local displayText = keyCombo or keyCodeMap[keyCode] or tostring(keyCode)

    -- Verifica se está bloqueada pelo sistema
    if table.contains(AssignBlockedKeys, keyCombo) then
      assignWindow.warning:setVisible(true)
      assignWindow.warning:setText("This hotkey is already in use and cannot be overwritten.")
      assignWindow.buttonOk:setEnabled(false)
      -- Verifica se está em uso por outra função do helper
    else
      local conflictWith = isHotkeyInUseByHelper(displayText, typo)
      if conflictWith then
        assignWindow.warning:setVisible(true)
        local formattedTypo = conflictWith:gsub("Enable/Disable ", "")
        assignWindow.warning:setText(string.format(
          "This hotkey is already in use by: %s.\nIf you want to proceed, the previous assignment\nwill be cleared.",
          formattedTypo))
        -- Permite clicar OK para transferir a hotkey (será removida da outra função)
        assignWindow.buttonOk:setEnabled(true)
      else
        assignWindow.warning:setVisible(false)
        assignWindow.buttonOk:setEnabled(true)
      end
    end

    capturedKeyCode = keyCode
    capturedKeyChar = displayText
    displayLabel:setText(displayText)
    return true
  end

  buttonOk.onClick = function()
    local keyComboDesc = tostring(displayLabel:getText())

    -- Se o campo está vazio, remove a hotkey da função
    if not keyComboDesc or keyComboDesc == "" or keyComboDesc == "(pressione uma tecla)" or keyComboDesc == "(press a key)" then
      if typo == "Enable/Disable Helper" then
        if helperConfig.hotkeyCode and helperConfig.hotkeyCode ~= "" then
          if helperConfig.hotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.hotkeyCode, helperConfig.hotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.hotkeyCode)
          end
          helperConfig.hotkeyCode = ""
          helperConfig.hotkeyFunc = nil
        end
      elseif typo == "Enable/Disable Auto Target" then
        if helperConfig.autoTargetHotkeyCode and helperConfig.autoTargetHotkeyCode ~= "" then
          if helperConfig.autoTargetHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.autoTargetHotkeyCode, helperConfig.autoTargetHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.autoTargetHotkeyCode)
          end
          helperConfig.autoTargetHotkeyCode = ""
          helperConfig.autoTargetHotkeyFunc = nil
        end
      elseif typo == "Enable/Disable Magic Shooter" then
        if helperConfig.magicShooterHotkeyCode and helperConfig.magicShooterHotkeyCode ~= "" then
          if helperConfig.magicShooterHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.magicShooterHotkeyCode, helperConfig.magicShooterHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.magicShooterHotkeyCode)
          end
          helperConfig.magicShooterHotkeyCode = ""
          helperConfig.magicShooterHotkeyFunc = nil
        end
      elseif typo == "Enable/Disable Target and Magic Shooter" then
        if helperConfig.targetMagicShooterHotkeyCode and helperConfig.targetMagicShooterHotkeyCode ~= "" then
          if helperConfig.targetMagicShooterHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.targetMagicShooterHotkeyCode, helperConfig
              .targetMagicShooterHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.targetMagicShooterHotkeyCode)
          end
          helperConfig.targetMagicShooterHotkeyCode = ""
          helperConfig.targetMagicShooterHotkeyFunc = nil
        end
      elseif typo == "Change Shooter Preset" then
        if helperConfig.presetHotkeyCode and helperConfig.presetHotkeyCode ~= "" then
          if helperConfig.presetHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.presetHotkeyCode, helperConfig.presetHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.presetHotkeyCode)
          end
          helperConfig.presetHotkeyCode = ""
          helperConfig.presetHotkeyFunc = nil
        end
      elseif typo == "Enable/Disable Equipment" then
        if helperConfig.equipmentHotkeyCode and helperConfig.equipmentHotkeyCode ~= "" then
          if helperConfig.equipmentHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.equipmentHotkeyCode, helperConfig.equipmentHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.equipmentHotkeyCode)
          end
          helperConfig.equipmentHotkeyCode = ""
          helperConfig.equipmentHotkeyFunc = nil
        end
      elseif typo == "Enable/Disable Cavebot" then
        if helperConfig.cavebotHotkeyCode and helperConfig.cavebotHotkeyCode ~= "" then
          if helperConfig.cavebotHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.cavebotHotkeyCode, helperConfig.cavebotHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.cavebotHotkeyCode)
          end
          helperConfig.cavebotHotkeyCode = ""
          helperConfig.cavebotHotkeyFunc = nil
        end
      elseif typo == "Toggle Recording" then
        if helperConfig.recordingHotkeyCode and helperConfig.recordingHotkeyCode ~= "" then
          if helperConfig.recordingHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.recordingHotkeyCode, helperConfig.recordingHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.recordingHotkeyCode)
          end
          helperConfig.recordingHotkeyCode = ""
          helperConfig.recordingHotkeyFunc = nil
        end
      elseif typo == "Stop all scripts" then
        if helperConfig.scriptsStopAllHotkeyCode and helperConfig.scriptsStopAllHotkeyCode ~= "" then
          if helperConfig.scriptsStopAllHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.scriptsStopAllHotkeyCode, helperConfig.scriptsStopAllHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.scriptsStopAllHotkeyCode)
          end
          helperConfig.scriptsStopAllHotkeyCode = ""
          helperConfig.scriptsStopAllHotkeyFunc = nil
        end
      elseif typo == "Enable/Disable Follow" then
        if helperConfig.smartFollowHotkeyCode and helperConfig.smartFollowHotkeyCode ~= "" then
          if helperConfig.smartFollowHotkeyFunc then
            g_keyboard.unbindKeyDown(helperConfig.smartFollowHotkeyCode, helperConfig.smartFollowHotkeyFunc)
          else
            g_keyboard.unbindKeyDown(helperConfig.smartFollowHotkeyCode)
          end
          helperConfig.smartFollowHotkeyCode = ""
          helperConfig.smartFollowHotkeyFunc = nil
        end
      end

      saveSettings()
      assignWindow:destroy()
      helper:show(true)
      return
    end

    if not g_keyboard then
      assignWindow:destroy()
      helper:show(true)
      return
    end

    -- Remove hotkey de outras funções se estiver em conflito (transfere para a nova função)
    local function clearConflictingHotkey(hotkey)
      if helperConfig.hotkeyCode == hotkey then
        if helperConfig.hotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.hotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.hotkeyCode = ""
        helperConfig.hotkeyFunc = nil
      end
      if helperConfig.autoTargetHotkeyCode == hotkey then
        if helperConfig.autoTargetHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.autoTargetHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.autoTargetHotkeyCode = ""
        helperConfig.autoTargetHotkeyFunc = nil
      end
      if helperConfig.magicShooterHotkeyCode == hotkey then
        if helperConfig.magicShooterHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.magicShooterHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.magicShooterHotkeyCode = ""
        helperConfig.magicShooterHotkeyFunc = nil
      end
      if helperConfig.targetMagicShooterHotkeyCode == hotkey then
        if helperConfig.targetMagicShooterHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.targetMagicShooterHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.targetMagicShooterHotkeyCode = ""
        helperConfig.targetMagicShooterHotkeyFunc = nil
      end
      if helperConfig.presetHotkeyCode == hotkey then
        if helperConfig.presetHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.presetHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.presetHotkeyCode = ""
        helperConfig.presetHotkeyFunc = nil
      end
      if helperConfig.equipmentHotkeyCode == hotkey then
        if helperConfig.equipmentHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.equipmentHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.equipmentHotkeyCode = ""
        helperConfig.equipmentHotkeyFunc = nil
      end
      if helperConfig.cavebotHotkeyCode == hotkey then
        if helperConfig.cavebotHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.cavebotHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.cavebotHotkeyCode = ""
        helperConfig.cavebotHotkeyFunc = nil
      end
      if helperConfig.recordingHotkeyCode == hotkey then
        if helperConfig.recordingHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.recordingHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.recordingHotkeyCode = ""
        helperConfig.recordingHotkeyFunc = nil
      end
      if helperConfig.scriptsStopAllHotkeyCode == hotkey then
        if helperConfig.scriptsStopAllHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.scriptsStopAllHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.scriptsStopAllHotkeyCode = ""
        helperConfig.scriptsStopAllHotkeyFunc = nil
      end
      if helperConfig.smartFollowHotkeyCode == hotkey then
        if helperConfig.smartFollowHotkeyFunc then
          g_keyboard.unbindKeyDown(hotkey, helperConfig.smartFollowHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(hotkey)
        end
        helperConfig.smartFollowHotkeyCode = ""
        helperConfig.smartFollowHotkeyFunc = nil
      end
    end

    -- Registra a hotkey para toggle das funcionalidades automáticas do helper
    if typo == "Enable/Disable Helper" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.hotkeyCode and helperConfig.hotkeyCode ~= "" then
        -- Passa a função para garantir que apenas ela seja removida
        if helperConfig.hotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.hotkeyCode, helperConfig.hotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.hotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle
      local toggleFunc = function()
        helperAutomaticFunctionsEnabled = not helperAutomaticFunctionsEnabled
        botStatus()
        -- Sincronizar com shortcut panel
        _Helper.Shortcut.syncButton('shortcutHelper', helperAutomaticFunctionsEnabled)
      end

      -- Armazena e vincula a hotkey usando a string (ex: "Ctrl+1")
      helperConfig.hotkeyCode = keyComboDesc
      helperConfig.hotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Enable/Disable Auto Target" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.autoTargetHotkeyCode and helperConfig.autoTargetHotkeyCode ~= "" then
        -- Passa a função para garantir que apenas ela seja removida
        local oldKey = helperConfig.autoTargetHotkeyCode
        local oldFunc = helperConfig.autoTargetHotkeyFunc
        if oldFunc then
          g_keyboard.unbindKeyDown(oldKey, oldFunc)
        else
          g_keyboard.unbindKeyDown(oldKey)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle auto target
      local toggleFunc = function()
        local widget = enableButtons and enableButtons:recursiveGetChildById("enableAutoTarget")
        if widget then
          widget:setChecked(not widget:isChecked())
          toggleAutoTarget(widget)
        end
      end

      -- Armazena e vincula a hotkey usando a string (ex: "Ctrl+1")
      helperConfig.autoTargetHotkeyCode = keyComboDesc
      helperConfig.autoTargetHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Enable/Disable Magic Shooter" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.magicShooterHotkeyCode and helperConfig.magicShooterHotkeyCode ~= "" then
        -- Passa a função para garantir que apenas ela seja removida
        if helperConfig.magicShooterHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.magicShooterHotkeyCode, helperConfig.magicShooterHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.magicShooterHotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle magic shooter
      local toggleFunc = function()
        local widget = enableButtons and enableButtons:recursiveGetChildById("enableMagicShooter")
        if widget then
          widget:setChecked(not widget:isChecked())
          toggleMagicShooter(widget)
        end
      end

      -- Armazena e vincula a hotkey usando a string (ex: "Ctrl+2")
      helperConfig.magicShooterHotkeyCode = keyComboDesc
      helperConfig.magicShooterHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Enable/Disable Target and Magic Shooter" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.targetMagicShooterHotkeyCode and helperConfig.targetMagicShooterHotkeyCode ~= "" then
        -- Passa a função para garantir que apenas ela seja removida
        if helperConfig.targetMagicShooterHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.targetMagicShooterHotkeyCode, helperConfig.targetMagicShooterHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.targetMagicShooterHotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle simultâneo de Auto Target e Magic Shooter (inverte ambos os estados)
      local toggleFunc = function()
        local autoTargetWidget = enableButtons and enableButtons:recursiveGetChildById("enableAutoTarget")
        local magicShooterWidget = enableButtons and enableButtons:recursiveGetChildById("enableMagicShooter")

        if autoTargetWidget then
          autoTargetWidget:setChecked(not autoTargetWidget:isChecked())
          toggleAutoTarget(autoTargetWidget)
        end

        if magicShooterWidget then
          magicShooterWidget:setChecked(not magicShooterWidget:isChecked())
          toggleMagicShooter(magicShooterWidget)
        end
      end

      -- Armazena e vincula a hotkey
      helperConfig.targetMagicShooterHotkeyCode = keyComboDesc
      helperConfig.targetMagicShooterHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Change Shooter Preset" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.presetHotkeyCode and helperConfig.presetHotkeyCode ~= "" then
        -- Passa a função para garantir que apenas ela seja removida
        if helperConfig.presetHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.presetHotkeyCode, helperConfig.presetHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.presetHotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para Change Shooter Preset
      local toggleFunc = function()
        toggleShooterPreset(nil, false)
        if modules.game_helper and modules.game_helper.magicShooter then
          modules.game_helper.magicShooter.updateRulesList()
        end
      end

      -- Armazena e vincula a hotkey
      helperConfig.presetHotkeyCode = keyComboDesc
      helperConfig.presetHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Enable/Disable Equipment" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.equipmentHotkeyCode and helperConfig.equipmentHotkeyCode ~= "" then
        -- Passa a função para garantir que apenas ela seja removida
        if helperConfig.equipmentHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.equipmentHotkeyCode, helperConfig.equipmentHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.equipmentHotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle equipment
      local toggleFunc = function()
        if modules.game_helper and modules.game_helper.equip then
          local enabled = modules.game_helper.equip.isEnabled()
          modules.game_helper.equip.toggleEquipment(not enabled)
          -- Update checkbox
          local equipPanel = modules.game_helper.equip.getPanel()
          if equipPanel then
            local enableEquipmentPanel = equipPanel:getChildById('enableEquipmentPanel')
            if enableEquipmentPanel then
              local enableCheckbox = enableEquipmentPanel:getChildById('enableEquipment')
              if enableCheckbox then
                enableCheckbox:setChecked(not enabled)
              end
            end
          end
        end
      end

      -- Armazena e vincula a hotkey
      helperConfig.equipmentHotkeyCode = keyComboDesc
      helperConfig.equipmentHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Enable/Disable Cavebot" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.cavebotHotkeyCode and helperConfig.cavebotHotkeyCode ~= "" then
        if helperConfig.cavebotHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.cavebotHotkeyCode, helperConfig.cavebotHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.cavebotHotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle cavebot
      local toggleFunc = function()
        if modules.game_helper and modules.game_helper.cavebot then
          local enabled = modules.game_helper.cavebot.isEnabled()
          modules.game_helper.cavebot.toggle(not enabled)
        end
      end

      -- Armazena e vincula a hotkey
      helperConfig.cavebotHotkeyCode = keyComboDesc
      helperConfig.cavebotHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Toggle Recording" then
      -- SEMPRE limpa hotkey antiga desta função primeiro
      if helperConfig.recordingHotkeyCode and helperConfig.recordingHotkeyCode ~= "" then
        if helperConfig.recordingHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.recordingHotkeyCode, helperConfig.recordingHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.recordingHotkeyCode)
        end
      end
      -- Limpa a nova hotkey de outras funções que possam estar usando
      clearConflictingHotkey(keyComboDesc)

      -- Cria closure para toggle recording
      local toggleFunc = function()
        if modules.game_helper and modules.game_helper.cavebot then
          modules.game_helper.cavebot.toggleRecording()
        end
      end

      -- Armazena e vincula a hotkey
      helperConfig.recordingHotkeyCode = keyComboDesc
      helperConfig.recordingHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    elseif typo == "Stop all scripts" then
      if helperConfig.scriptsStopAllHotkeyCode and helperConfig.scriptsStopAllHotkeyCode ~= "" then
        if helperConfig.scriptsStopAllHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.scriptsStopAllHotkeyCode, helperConfig.scriptsStopAllHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.scriptsStopAllHotkeyCode)
        end
      end
      clearConflictingHotkey(keyComboDesc)
      local stopFunc = function()
        if modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.toggleAllActiveScripts then
          modules.game_helper.scripts.toggleAllActiveScripts()
        elseif modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.stopAllActiveScripts then
          modules.game_helper.scripts.stopAllActiveScripts()
        end
      end
      helperConfig.scriptsStopAllHotkeyCode = keyComboDesc
      helperConfig.scriptsStopAllHotkeyFunc = stopFunc
      g_keyboard.bindKeyDown(keyComboDesc, stopFunc)
      saveSettings()
    elseif typo == "Enable/Disable Follow" then
      if helperConfig.smartFollowHotkeyCode and helperConfig.smartFollowHotkeyCode ~= "" then
        if helperConfig.smartFollowHotkeyFunc then
          g_keyboard.unbindKeyDown(helperConfig.smartFollowHotkeyCode, helperConfig.smartFollowHotkeyFunc)
        else
          g_keyboard.unbindKeyDown(helperConfig.smartFollowHotkeyCode)
        end
      end
      clearConflictingHotkey(keyComboDesc)
      local toggleFunc = function()
        local panel = _Helper.getToolsPanel and _Helper.getToolsPanel()
        local widget = panel and panel:recursiveGetChildById("smartFollow")
        if widget then
          widget:setChecked(not widget:isChecked())
        end
      end
      helperConfig.smartFollowHotkeyCode = keyComboDesc
      helperConfig.smartFollowHotkeyFunc = toggleFunc
      g_keyboard.bindKeyDown(keyComboDesc, toggleFunc)
      saveSettings()
    end

    assignWindow:destroy()
    helper:show(true)
    -- Restaura a janela de settings do cavebot se foi escondida
    if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.showSettingsWindow()
    end
  end

  buttonClose.onClick = function()
    assignWindow:destroy()
    helper:show(true)
    -- Restaura a janela de settings do cavebot se foi escondida
    if typo == "Toggle Recording" and modules.game_helper and modules.game_helper.cavebot then
      modules.game_helper.cavebot.showSettingsWindow()
    end
  end

  -- Handler para o botão Clear - limpa o campo e mostra aviso de remoção
  if buttonClear then
    buttonClear.onClick = function()
      -- Obter hotkey atual que será removida
      local hotkeyToRemove = nil
      if typo == "Enable/Disable Helper" then
        hotkeyToRemove = helperConfig.hotkeyCode
      elseif typo == "Enable/Disable Auto Target" then
        hotkeyToRemove = helperConfig.autoTargetHotkeyCode
      elseif typo == "Enable/Disable Magic Shooter" then
        hotkeyToRemove = helperConfig.magicShooterHotkeyCode
      elseif typo == "Enable/Disable Target and Magic Shooter" then
        hotkeyToRemove = helperConfig.targetMagicShooterHotkeyCode
      elseif typo == "Change Shooter Preset" then
        hotkeyToRemove = helperConfig.presetHotkeyCode
      elseif typo == "Enable/Disable Equipment" then
        hotkeyToRemove = helperConfig.equipmentHotkeyCode
      elseif typo == "Enable/Disable Cavebot" then
        hotkeyToRemove = helperConfig.cavebotHotkeyCode
      elseif typo == "Toggle Recording" then
        hotkeyToRemove = helperConfig.recordingHotkeyCode
      elseif typo == "Stop all scripts" then
        hotkeyToRemove = helperConfig.scriptsStopAllHotkeyCode
      elseif typo == "Enable/Disable Follow" then
        hotkeyToRemove = helperConfig.smartFollowHotkeyCode
      end

      displayLabel:setText("(press a key)")
      capturedKeyCode = nil
      capturedKeyChar = ""

      -- Mostrar aviso se havia uma hotkey configurada
      if hotkeyToRemove and hotkeyToRemove ~= "" then
        assignWindow.warning:setVisible(true)
        assignWindow.warning:setText("Hotkey '" .. hotkeyToRemove .. "' will be removed if you confirm.")
      else
        assignWindow.warning:setVisible(false)
      end

      assignWindow.buttonOk:setEnabled(true)
    end
  end

  assignWindow.onDestroy = function(widget)
    helper:show(true)
  end
end

function onDropSpell(widget, spellWords)
  local spellData = Spells.getSpellDataByWords(spellWords)
  if not spellData then
    return
  end

  local isHealingPanel = string.match(widget:getId(), "^spellButton%d*")
  local isTrainingPanel = string.match(widget:getId(), "^spellTrainingButton")
  local isHastePanel = string.match(widget:getId(), "^hasteButton")
  local isUtitoPanel = string.match(widget:getId(), "^utitoButton")
  local isAttackPanel = string.match(widget:getId(), "^attackSpellButton%d*")
  local profile = getShooterProfile()

  if isHealingPanel then
    onSetupDropSpell(widget, spellData, { 2 }, helperConfig.spells)
  elseif isTrainingPanel or isHastePanel or isUtitoPanel then
    onSetupDropSupport(widget, spellData, isHastePanel, isUtitoPanel)
  elseif isAttackPanel then
    onSetupDropSpell(widget, spellData, { 1, 4, 8 }, profile.spells)
  end
end

function onSetupDropSpell(button, spellData, groups, tableToAssign)
  local groupIds = Spells.getGroupIds(spellData)
  local playerVocation = translateVocation(player:getVocation())
  local profile = getShooterProfile()

  if containsAnyGroup(groupIds, groups) and table.contains(spellData.vocations, playerVocation) and not HelperSpellData.getIgnoredSpellsIds()[spellData.id] then
    local spell = Spells.getSpellDataById(spellData.id)
    _Helper.setSpellIcon(button, spellData.id)
    button:setBorderColorTop("#1b1b1b")
    button:setBorderColorLeft("#1b1b1b")
    button:setBorderColorRight("#757575")
    button:setBorderColorBottom("#757575")
    button:setBorderWidth(1)
    button:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    local slotID = tonumber(button:getId():match("%d+"))
    if button:getId():find("attackSpellButton") then
      profile.spells[slotID + 1].id = tonumber(spellData.id)
    else
      tableToAssign[slotID + 1].id = tonumber(spellData.id)
    end

    if button:getId():find("attackSpellButton") then
      local creaturesMin = shooterPanel:recursiveGetChildById("countMinCreature" .. slotID)
      local forceCast = shooterPanel:recursiveGetChildById("conditionSetting" .. slotID)
      local selfCast = shooterPanel:recursiveGetChildById("selfCast" .. slotID)
      if table.contains(bothCastTypeSpells, spell.id) then -- divine grenade self cast
        if not selfCast then
          selfCast = g_ui.createWidget('CheckBox', creaturesMin:getParent())
          local style = {
            ["width"] = 12,
            ["anchors.top"] = "countMinCreature" .. slotID .. ".top",
            ["anchors.left"] = "countMinCreature" .. slotID .. ".right",
            ["margin-top"] = 6,
            ["margin-left"] = 5
          }
          selfCast:mergeStyle(style)
          selfCast:setId('selfCast' .. slotID)
          selfCast:setTooltip('Cast on yourself')
          selfCast:setVisible(true)
          selfCast.onCheckChange = function() toggleSelfCast(selfCast:getId():match("%d+"), selfCast:isChecked()) end
        end
      end

      if selfCast and not table.contains(bothCastTypeSpells, spell.id) then
        profile.spells[slotID + 1].selfCast = false
        selfCast:destroy()
      end

      if (spell.range > 0 or not spell.area) and not table.contains(bothCastTypeSpells, spell.id) then
        profile.spells[slotID + 1].creatures = 1
        creaturesMin:setCurrentOption("1+")
        creaturesMin:disable()
        if forceCast then
          forceCast:setChecked(profile.spells[slotID + 1].forceCast)
          forceCast:setVisible(true)
        end
      else
        creaturesMin:enable()
        if forceCast then
          forceCast:setChecked(false)
          forceCast:setVisible(false)
          profile.spells[slotID + 1].forceCast = false
        end
      end
    end
  end
end

function onSetupDropSupport(widget, spellData, hasteSpell, utitoSpell)
  local playerVocation = translateVocation(player:getVocation())
  local hasteWhiteList = HelperSpellData.getHasteWhiteList()
  local utitoWhiteList = HelperSpellData.getUtitoWhiteList()
  local trainingHealSpellsSet = HelperSpellData.getTrainingHealSpellsSet()
  local allowedTrainingSpells = trainingHealSpellsSet[playerVocation] or {}

  if hasteSpell and not table.contains(hasteWhiteList[playerVocation] or {}, spellData.id) then
    return
  end

  if utitoSpell and not table.contains(utitoWhiteList[playerVocation] or {}, spellData.id) then
    return
  end

  if not hasteSpell and not utitoSpell and not allowedTrainingSpells[spellData.id] then
    return
  end

  if allowedTrainingSpells[spellData.id] or table.contains(hasteWhiteList[playerVocation] or {}, spellData.id) or table.contains(utitoWhiteList[playerVocation] or {}, spellData.id) then
    _Helper.setSpellIcon(widget, spellData.id)
    widget:setBorderColorTop("#1b1b1b")
    widget:setBorderColorLeft("#1b1b1b")
    widget:setBorderColorRight("#757575")
    widget:setBorderColorBottom("#757575")
    widget:setBorderWidth(1)
    widget:setTooltip("Spell: " .. spellData.name .. "\nWords: " .. spellData.words)

    local slotID = tonumber(widget:getId():match("%d+"))
    if hasteSpell then
      -- Usa o modulo AutoHaste para configurar
      local helperConfigLocal = _Helper.getHelperConfig and _Helper.getHelperConfig() or helperConfig
      helperConfigLocal.haste[1].id = tonumber(spellData.id)
    elseif utitoSpell then
      -- Usa o modulo AutoUtito para configurar
      local helperConfigLocal = _Helper.getHelperConfig and _Helper.getHelperConfig() or helperConfig
      helperConfigLocal.utito[1].id = tonumber(spellData.id)
    else
      helperConfig.training[1].id = tonumber(spellData.id)
      if helperConfig.training[1].percent == 0 then
        helperConfig.training[1].percent = 100
        updateTrainingPercent('spellTrainingButton0', helperConfig.training[1].percent)
      end
    end
  end
end

function onSearchTextChange(text, window)
  if not window or window:isDestroyed() then return end
  local spellList = window:recursiveGetChildById('spellList')
  if not spellList then return end
  for _, child in pairs(spellList:getChildren()) do
    local name = child:getText():lower()
    if name:find(text:lower()) or text == '' or #text < 3 then
      child:setVisible(true)
    else
      child:setVisible(false)
    end
  end
end

function onClearSearchText()
  local search = window:recursiveGetChildById('searchText')
  search:setText('')
end

-- Função para remover todas as hotkeys do helper (usado antes de registrar para evitar duplicatas)
function unregisterAllHelperHotkeys()
  if not g_keyboard then return end

  -- Remove hotkey do Helper toggle
  if helperConfig.hotkeyCode and helperConfig.hotkeyCode ~= "" and helperConfig.hotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.hotkeyCode, helperConfig.hotkeyFunc)
  end

  -- Remove hotkey do Auto Target toggle
  if helperConfig.autoTargetHotkeyCode and helperConfig.autoTargetHotkeyCode ~= "" and helperConfig.autoTargetHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.autoTargetHotkeyCode, helperConfig.autoTargetHotkeyFunc)
  end

  -- Remove hotkey do Magic Shooter toggle
  if helperConfig.magicShooterHotkeyCode and helperConfig.magicShooterHotkeyCode ~= "" and helperConfig.magicShooterHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.magicShooterHotkeyCode, helperConfig.magicShooterHotkeyFunc)
  end

  -- Remove hotkey do Target and Magic Shooter toggle
  if helperConfig.targetMagicShooterHotkeyCode and helperConfig.targetMagicShooterHotkeyCode ~= "" and helperConfig.targetMagicShooterHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.targetMagicShooterHotkeyCode, helperConfig.targetMagicShooterHotkeyFunc)
  end

  -- Remove hotkey do Preset cycle
  if helperConfig.presetHotkeyCode and helperConfig.presetHotkeyCode ~= "" and helperConfig.presetHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.presetHotkeyCode, helperConfig.presetHotkeyFunc)
  end

  -- Remove hotkey do Equipment toggle
  if helperConfig.equipmentHotkeyCode and helperConfig.equipmentHotkeyCode ~= "" and helperConfig.equipmentHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.equipmentHotkeyCode, helperConfig.equipmentHotkeyFunc)
  end

  -- Remove hotkey do Cavebot toggle
  if helperConfig.cavebotHotkeyCode and helperConfig.cavebotHotkeyCode ~= "" and helperConfig.cavebotHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.cavebotHotkeyCode, helperConfig.cavebotHotkeyFunc)
  end

  -- Remove hotkey do Recording toggle
  if helperConfig.recordingHotkeyCode and helperConfig.recordingHotkeyCode ~= "" and helperConfig.recordingHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.recordingHotkeyCode, helperConfig.recordingHotkeyFunc)
  end

  -- Remove hotkey Stop all scripts
  if helperConfig.scriptsStopAllHotkeyCode and helperConfig.scriptsStopAllHotkeyCode ~= "" and helperConfig.scriptsStopAllHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.scriptsStopAllHotkeyCode, helperConfig.scriptsStopAllHotkeyFunc)
  end

  if helperConfig.smartFollowHotkeyCode and helperConfig.smartFollowHotkeyCode ~= "" and helperConfig.smartFollowHotkeyFunc then
    g_keyboard.unbindKeyDown(helperConfig.smartFollowHotkeyCode, helperConfig.smartFollowHotkeyFunc)
  end

  -- Limpa as referências das funções
  helperConfig.hotkeyFunc = nil
  helperConfig.autoTargetHotkeyFunc = nil
  helperConfig.magicShooterHotkeyFunc = nil
  helperConfig.targetMagicShooterHotkeyFunc = nil
  helperConfig.presetHotkeyFunc = nil
  helperConfig.equipmentHotkeyFunc = nil
  helperConfig.cavebotHotkeyFunc = nil
  helperConfig.recordingHotkeyFunc = nil
  helperConfig.scriptsStopAllHotkeyFunc = nil
  helperConfig.smartFollowHotkeyFunc = nil
end

-- Função para registrar as hotkeys salvas após carregar config
function registerSavedHotkeys()
  if not g_keyboard then return end

  -- Registra hotkey do Helper toggle
  if helperConfig.hotkeyCode and helperConfig.hotkeyCode ~= "" then
    local toggleFunc = function()
      helperAutomaticFunctionsEnabled = not helperAutomaticFunctionsEnabled
      botStatus()
      _Helper.Shortcut.syncButton('shortcutHelper', helperAutomaticFunctionsEnabled)
    end
    helperConfig.hotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.hotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Auto Target toggle
  if helperConfig.autoTargetHotkeyCode and helperConfig.autoTargetHotkeyCode ~= "" then
    local toggleFunc = function()
      local widget = enableButtons and enableButtons:recursiveGetChildById("enableAutoTarget")
      if widget then
        widget:setChecked(not widget:isChecked())
        toggleAutoTarget(widget)
      end
    end
    helperConfig.autoTargetHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.autoTargetHotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Magic Shooter toggle
  if helperConfig.magicShooterHotkeyCode and helperConfig.magicShooterHotkeyCode ~= "" then
    local toggleFunc = function()
      local widget = enableButtons and enableButtons:recursiveGetChildById("enableMagicShooter")
      if widget then
        widget:setChecked(not widget:isChecked())
        toggleMagicShooter(widget)
      end
    end
    helperConfig.magicShooterHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.magicShooterHotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Target and Magic Shooter toggle (ambos juntos)
  if helperConfig.targetMagicShooterHotkeyCode and helperConfig.targetMagicShooterHotkeyCode ~= "" then
    local toggleFunc = function()
      local autoTargetWidget = enableButtons and enableButtons:recursiveGetChildById("enableAutoTarget")
      local magicShooterWidget = enableButtons and enableButtons:recursiveGetChildById("enableMagicShooter")

      if autoTargetWidget then
        autoTargetWidget:setChecked(not autoTargetWidget:isChecked())
        toggleAutoTarget(autoTargetWidget)
      end

      if magicShooterWidget then
        magicShooterWidget:setChecked(not magicShooterWidget:isChecked())
        toggleMagicShooter(magicShooterWidget)
      end
    end
    helperConfig.targetMagicShooterHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.targetMagicShooterHotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Preset cycle
  if helperConfig.presetHotkeyCode and helperConfig.presetHotkeyCode ~= "" then
    local toggleFunc = function()
      toggleShooterPreset(nil, false)
    end
    helperConfig.presetHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.presetHotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Equipment toggle
  if helperConfig.equipmentHotkeyCode and helperConfig.equipmentHotkeyCode ~= "" then
    local toggleFunc = function()
      if modules.game_helper and modules.game_helper.equip then
        local enabled = modules.game_helper.equip.isEnabled()
        modules.game_helper.equip.toggleEquipment(not enabled)
        -- Update checkbox
        local equipPanel = modules.game_helper.equip.getPanel()
        if equipPanel then
          local enableEquipmentPanel = equipPanel:getChildById('enableEquipmentPanel')
          if enableEquipmentPanel then
            local enableCheckbox = enableEquipmentPanel:getChildById('enableEquipment')
            if enableCheckbox then
              enableCheckbox:setChecked(not enabled)
            end
          end
        end
      end
    end
    helperConfig.equipmentHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.equipmentHotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Cavebot toggle
  if helperConfig.cavebotHotkeyCode and helperConfig.cavebotHotkeyCode ~= "" then
    local toggleFunc = function()
      if modules.game_helper and modules.game_helper.cavebot then
        local enabled = modules.game_helper.cavebot.isEnabled()
        modules.game_helper.cavebot.toggle(not enabled)
      end
    end
    helperConfig.cavebotHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.cavebotHotkeyCode, toggleFunc)
  end

  -- Registra hotkey do Recording toggle
  if helperConfig.recordingHotkeyCode and helperConfig.recordingHotkeyCode ~= "" then
    local toggleFunc = function()
      if modules.game_helper and modules.game_helper.cavebot then
        modules.game_helper.cavebot.toggleRecording()
      end
    end
    helperConfig.recordingHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.recordingHotkeyCode, toggleFunc)
  end

  if helperConfig.scriptsStopAllHotkeyCode and helperConfig.scriptsStopAllHotkeyCode ~= "" then
    local stopFunc = function()
      if modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.toggleAllActiveScripts then
        modules.game_helper.scripts.toggleAllActiveScripts()
      elseif modules.game_helper and modules.game_helper.scripts and modules.game_helper.scripts.stopAllActiveScripts then
        modules.game_helper.scripts.stopAllActiveScripts()
      end
    end
    helperConfig.scriptsStopAllHotkeyFunc = stopFunc
    g_keyboard.bindKeyDown(helperConfig.scriptsStopAllHotkeyCode, stopFunc)
  end

  if helperConfig.smartFollowHotkeyCode and helperConfig.smartFollowHotkeyCode ~= "" then
    local toggleFunc = function()
      local panel = _Helper.getToolsPanel and _Helper.getToolsPanel()
      local widget = panel and panel:recursiveGetChildById("smartFollow")
      if widget then
        widget:setChecked(not widget:isChecked())
      end
    end
    helperConfig.smartFollowHotkeyFunc = toggleFunc
    g_keyboard.bindKeyDown(helperConfig.smartFollowHotkeyCode, toggleFunc)
  end
end
