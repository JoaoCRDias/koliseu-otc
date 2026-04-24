--- Walk module - reescrita minimalista inspirada no RTC.
--- Filosofia: unico driver de continuacao do hold e o auto-repeat de KeyPress + nextWalkDir
--- + addEvent em onWalkFinish. Zero watchdog, zero retry, zero stall detection. O server e
--- soberano; se o preWalk ficar preso, o adjustInvalidPos no C++ corrige. Rubber-band deixa
--- de ser mascarado por camadas de retry que colidem entre si.
if WALK_DEBUG == nil then WALK_DEBUG = false end

local function WDLOG(fmt, ...)
 if not WALK_DEBUG then return end
 local args = { ... }
 local msg
 if #args > 0 then
  local ok, formatted = pcall(string.format, fmt, ...)
  msg = ok and formatted or tostring(fmt)
 else
  msg = tostring(fmt)
 end
 g_logger.info(string.format('[WALK %d] %s', g_clock.millis() % 100000, msg))
end

local DIR_NAME = { [North]='N', [East]='E', [South]='S', [West]='W',
 [NorthEast]='NE', [SouthEast]='SE', [SouthWest]='SW', [NorthWest]='NW' }
local function dname(d) return DIR_NAME[d] or tostring(d) end

local smartWalkDirs = {}
local smartWalkDir = nil
local walkEvent = nil
local nextWalkDir = nil
local lastWalkDir = nil
local lastTurn = 0
local lastWalk = 0
local lastFinishedStep = 0
local walkLock = 0
local lastSpellLockTime = 0
local stairsResumeEvent = nil

local keys = {
 { "Up", North },
 { "Right", East },
 { "Down", South },
 { "Left", West },
 { "Numpad8", North },
 { "Numpad9", NorthEast },
 { "Numpad6", East },
 { "Numpad3", SouthEast },
 { "Numpad2", South },
 { "Numpad1", SouthWest },
 { "Numpad4", West },
 { "Numpad7", NorthWest },
}

local wasdMovementKeys = { "W", "D", "S", "A", "E", "Q", "C", "Z" }

local NUMPAD_WALK_WHITELIST = {
 Numpad1 = true, Numpad2 = true, Numpad3 = true,
 Numpad4 = true, Numpad6 = true,
 Numpad7 = true, Numpad8 = true, Numpad9 = true,
}

local walkKeyByDir = {}

local keyDownAt = {}
local function heldForMs(dir)
 local t = keyDownAt[dir]
 if not t then return 0 end
 return g_clock.millis() - t
end

local CARDINAL_TURN_KEYS = {
 { 'Up', North },
 { 'Right', East },
 { 'Down', South },
 { 'Left', West },
}

local ROTATE_OPT_KEYS = {
 { opt = 'rotateWithCtrl', part = 'Ctrl' },
 { opt = 'rotateWithAlt', part = 'Alt' },
 { opt = 'rotateWithShift', part = 'Shift' },
}

local MOD_SORT_RANK = { Ctrl = 1, Alt = 2, Shift = 3 }

local function generateAllRotatePrefixStrings()
 local out = {}
 for mask = 1, 7 do
  local parts = {}
  for i = 1, 3 do
   if bit.band(mask, bit.lshift(1, i - 1)) ~= 0 then
    table.insert(parts, ROTATE_OPT_KEYS[i].part)
   end
  end
  table.sort(parts, function(a, b) return MOD_SORT_RANK[a] < MOD_SORT_RANK[b] end)
  table.insert(out, table.concat(parts, '+'))
 end
 return out
end

local ALL_ROTATE_PREFIXES = generateAllRotatePrefixStrings()

local function isWasdWalkMode()
 local console = modules.game_console
 return console and console.isEnabledWASD and console.isEnabledWASD()
end

local function shouldSuppressWalkForConsoleChatInput(key)
 if key == 'Up' or key == 'Down' or key == 'Left' or key == 'Right' then
  return false
 end
 if NUMPAD_WALK_WHITELIST[key] then
  return false
 end
 local console = modules.game_console
 if not console or not console.isChatEnabled or not console.getConsole then
  return false
 end
 if not g_game.isOnline() or not console.isChatEnabled() then
  return false
 end
 local te = console.getConsole()
 if not te or te:isDestroyed() or not te:isVisible() then
  return false
 end
 if not te:isFocused() then
  return false
 end
 return true
end

local function isWalkKeyPressed()
 for _, keyDir in ipairs(keys) do
  if g_keyboard.isKeyPressed(keyDir[1]) then
   return true
  end
 end
 if isWasdWalkMode() then
  for _, keyName in ipairs(wasdMovementKeys) do
   if g_keyboard.isKeyPressed(keyName) then
    return true
   end
  end
 end
 return false
end

local function isDirectionPressed(dir)
 local mp = walkKeyByDir[dir]
 if not mp then return false end
 for k, _ in pairs(mp) do
  if g_keyboard.isKeyPressed(k) then return true end
 end
 return false
end

local function releaseCompetingWalkKeys(newKey)
 if not g_window or not g_window.releaseKey or not getKeyCode then
  return
 end
 for _, keyDir in ipairs(keys) do
  local key = keyDir[1]
  if key ~= newKey and g_keyboard.isKeyPressed(key) then
   g_window.releaseKey(getKeyCode(key))
  end
 end
end

WalkController = Controller:new()

local changeWalkDir
local walk
local pickFirstPressedDir

local function stopSmartWalk()
 smartWalkDirs = {}
 smartWalkDir = nil
 nextWalkDir = nil
end

local function canChangeFloor(pos, deltaZ)
 if deltaZ == 0 then
  return false
 end
 local player = g_game.getLocalPlayer()
 if not player then
  return false
 end

 local toPos = {x = pos.x, y = pos.y, z = pos.z + deltaZ}
 local toTile = g_map.getTile(toPos)
 if not toTile then
  return false
 end

 if deltaZ > 0 then
  return toTile:isWalkable() and (toTile:hasElevation(3) or toTile:hasFloorChange())
 end
 local fromTile = g_map.getTile(player:getPosition())
 return fromTile and fromTile:hasElevation(3) and toTile:isWalkable()
end

local originalGameTalk = nil

local function applySpellWalkLock()
 local player = g_game.getLocalPlayer()
 if not player then return end
 if not player:isWalking() and not player:isPreWalking() then return end
 local now = g_clock.millis()
 local halfStep = math.max(30, math.floor((player:getStepDuration() or 100) / 2))
 if now - lastSpellLockTime < halfStep then return end
 lastSpellLockTime = now
 player:lockWalk(halfStep)
end

local function getConfiguredKeyboardDelay()
 if not modules.client_options or not modules.client_options.getOption then
  return 250
 end
 return modules.client_options.getOption('hotkeyDelay') or 250
end

local function getMovementKeyboardDelay()
 local configured = tonumber(getConfiguredKeyboardDelay()) or 250
 if configured < 1 then
  configured = 1
 end
 return configured
end

function applyKeyboardDelay(delay)
 local configuredDelay = tonumber(delay) or getConfiguredKeyboardDelay()
 if configuredDelay < 1 then
  configuredDelay = 1
 end
 local resolvedDelay = configuredDelay

 local root = modules.game_interface and modules.game_interface.getRootPanel
  and modules.game_interface.getRootPanel()
 if root and root.setAutoRepeatDelay then
  root:setAutoRepeatDelay(resolvedDelay)
 end

 for _, keyDir in ipairs(keys) do
  g_keyboard.setKeyDelay(keyDir[1], resolvedDelay)
 end
 for _, keyName in ipairs(wasdMovementKeys) do
  g_keyboard.setKeyDelay(keyName, resolvedDelay)
 end
end

pickFirstPressedDir = function()
 if smartWalkDir and isDirectionPressed(smartWalkDir) then
  return smartWalkDir
 end
 for _, keyDir in ipairs(keys) do
  if isDirectionPressed(keyDir[2]) then
   return keyDir[2]
  end
 end
 return nil
end

walk = function(dir)
 local player = g_game.getLocalPlayer()
 if not player or g_game.isDead() or player:isDead() then
  WDLOG('walk(%s) ABORT: no player or dead', dname(dir))
  return
 end

 if dir == lastWalkDir and not isWalkKeyPressed() then
  if player.stopAutoWalk then
   player:stopAutoWalk()
  end
  g_game.stop()
  nextWalkDir = nil
  return
 end

 if player:isWalkLocked() then
  nextWalkDir = nil
  return
 end

 local states = player:getStates()
 if states then
  local rooted = 524288
  if bit.band(states, rooted) ~= 0 then
   nextWalkDir = nil
   return
  end
 end

 if g_game.isFollowing() then
  g_game.cancelFollow()
 end

 if player:isAutoWalking() then
  g_game.stop()
  if player.stopAutoWalk then
   player:stopAutoWalk()
  end
  player:lockWalk(player:getStepDuration() + 50)
  return
 end

 if not player:canWalk() then
  if lastWalkDir ~= dir and isDirectionPressed(dir)
     and g_keyboard.getModifiers() == KeyboardNoModifier then
   nextWalkDir = dir
  end
  return
 end

 local stepDur = player:getStepDuration()
 if lastWalk and stepDur and stepDur > 0
    and (g_clock.millis() - lastWalk) < (stepDur - 10) then
  if dir ~= lastWalkDir and isDirectionPressed(dir)
     and g_keyboard.getModifiers() == KeyboardNoModifier then
   nextWalkDir = dir
  end
  return
 end

 if nextWalkDir and nextWalkDir ~= lastWalkDir then
  dir = nextWalkDir
 end

 local toPos = Position.translatedToDirection(player:getPosition(), dir)
 local toTile = g_map.getTile(toPos)
 local isFloorChange = canChangeFloor(toPos, 1) or canChangeFloor(toPos, -1)

 if walkLock >= g_clock.millis() and lastWalkDir == dir then
  nextWalkDir = nil
  return
 end

 if toTile and not toTile:isWalkable() and not isFloorChange then
  local alwaysTurn = true
  local opts = modules.client_options
  if opts and opts.getOption then
   local v = opts.getOption('alwaysTurnToDirection')
   if v ~= nil then
    alwaysTurn = v
   end
  end
  if alwaysTurn and player:getDirection() ~= dir then
   if walkEvent then removeEvent(walkEvent); walkEvent = nil end
   g_game.turn(dir)
   if changeWalkDir then changeWalkDir(dir) end
   lastTurn = g_clock.millis()
   player:lockWalk(g_settings.getNumber('walkTurnDelay'))
  end
  return
 end

 nextWalkDir = nil
 lastWalkDir = dir
 lastWalk = g_clock.millis()

 if g_game.getFeature(GameAllowPreWalk) and toTile and toTile:isWalkable()
    and not isFloorChange then
  player:preWalk(dir)
 end

 WDLOG('walk(%s) -> g_game.walk()', dname(dir))
 g_game.walk(dir)
 return true
end

function smartWalk(dir)
 if walkEvent then removeEvent(walkEvent); walkEvent = nil end
 walkEvent = addEvent(function()
  walkEvent = nil
  if g_keyboard.getModifiers() == KeyboardNoModifier and isWalkKeyPressed() then
   walk(smartWalkDir or dir)
  end
 end)
end

changeWalkDir = function(dir, pop)
 while table.removevalue(smartWalkDirs, dir) do end

 if pop then
  if #smartWalkDirs == 0 then
   stopSmartWalk()
   return
  end
 else
  table.insert(smartWalkDirs, 1, dir)
 end

 smartWalkDir = smartWalkDirs[1]

 if modules.client_options.getOption('smartWalk') and #smartWalkDirs > 1 then
  local diagonalMap = {
   [North] = { [West] = NorthWest, [East] = NorthEast },
   [South] = { [West] = SouthWest, [East] = SouthEast },
   [West] = { [North] = NorthWest, [South] = SouthWest },
   [East] = { [North] = NorthEast, [South] = SouthEast }
  }
  for _, d in ipairs(smartWalkDirs) do
   if diagonalMap[smartWalkDir] and diagonalMap[smartWalkDir][d] then
    smartWalkDir = diagonalMap[smartWalkDir][d]
    break
   end
  end
 end
end

local function turn(dir, repeated)
 local player = g_game.getLocalPlayer()
 if not player then return end
 if player:isWalking() and player:getDirection() == dir then
  return
 end

 if walkEvent then removeEvent(walkEvent); walkEvent = nil end

 local TURN_DELAY_REPEATED = 150
 local TURN_DELAY_DEFAULT = 50
 local delay = repeated and TURN_DELAY_REPEATED or TURN_DELAY_DEFAULT

 if lastTurn + delay < g_clock.millis() then
  g_game.turn(dir)
  changeWalkDir(dir)
  lastTurn = g_clock.millis()
  player:lockWalk(g_settings.getNumber('walkTurnDelay'))
 end
end

local function onTeleport(player, newPos, oldPos)
 if not newPos or not oldPos then
  return
 end

 local offsetX = Position.offsetX(newPos, oldPos)
 local offsetY = Position.offsetY(newPos, oldPos)
 local offsetZ = Position.offsetZ(newPos, oldPos)

 local TELEPORT_DELAY = g_settings.getNumber('walkTeleportDelay')
 local STAIRS_DELAY = math.max(g_settings.getNumber('walkStairsDelay'), 150)
 local isLongTeleport = (math.abs(offsetX) >= 3 or math.abs(offsetY) >= 3
                         or math.abs(offsetZ) >= 2)
 local delay = isLongTeleport and TELEPORT_DELAY or STAIRS_DELAY

 walkLock = g_clock.millis() + delay
 player:lockWalk(delay)
 nextWalkDir = nil

 if walkEvent then removeEvent(walkEvent); walkEvent = nil end
 if stairsResumeEvent then removeEvent(stairsResumeEvent); stairsResumeEvent = nil end

 if offsetZ ~= 0 and not isLongTeleport then
  local resumeDelay = delay + 30
  stairsResumeEvent = scheduleEvent(function()
   stairsResumeEvent = nil
   if g_keyboard.getModifiers() ~= KeyboardNoModifier then return end
   if not isWalkKeyPressed() then return end
   local d = pickFirstPressedDir()
   if d then walk(d) end
  end, resumeDelay)
 end
end

local function onWalkFinish(player)
 lastFinishedStep = g_clock.millis()
 local dir = nextWalkDir or pickFirstPressedDir()
 if not dir then return end

 if walkEvent then removeEvent(walkEvent) end
 walkEvent = addEvent(function()
  walkEvent = nil
  if g_keyboard.getModifiers() ~= KeyboardNoModifier then
   nextWalkDir = nil
   return
  end

  if not isDirectionPressed(dir) then
   nextWalkDir = nil
   return
  end

  if dir == lastWalkDir and heldForMs(dir) < getMovementKeyboardDelay() then
   nextWalkDir = nil
   return
  end

  walk(dir)
 end)
end

local function onCancelWalk(player)
 player:lockWalk(50)
 nextWalkDir = nil
 if walkEvent then removeEvent(walkEvent); walkEvent = nil end
end

local function onAutoWalk(player)
end

function bindWalkKey(key, dir)
 local gameRootPanel = modules.game_interface.getRootPanel()

 walkKeyByDir[dir] = walkKeyByDir[dir] or {}
 walkKeyByDir[dir][key] = true

 local function arrowWalkModifiersOk()
  return g_keyboard.getModifiers() == KeyboardNoModifier
 end

 g_keyboard.bindKeyDown(key, function()
  if shouldSuppressWalkForConsoleChatInput(key) then
   return
  end
  if not arrowWalkModifiersOk() then
   return
  end
  releaseCompetingWalkKeys(key)
  g_keyboard.setKeyDelay(key, getMovementKeyboardDelay())
  if not keyDownAt[dir] then
   keyDownAt[dir] = g_clock.millis()
  end
  changeWalkDir(dir)
  if walkEvent then removeEvent(walkEvent); walkEvent = nil end
  walk(smartWalkDir or dir)
 end, gameRootPanel, true)

 g_keyboard.bindKeyUp(key, function()
  if shouldSuppressWalkForConsoleChatInput(key) then
   return
  end
  if not arrowWalkModifiersOk() then
   return
  end
  g_keyboard.setKeyDelay(key, getMovementKeyboardDelay())
  changeWalkDir(dir, true)
  if not isDirectionPressed(dir) then
   keyDownAt[dir] = nil
   if nextWalkDir == dir then
    nextWalkDir = nil
    if walkEvent then removeEvent(walkEvent); walkEvent = nil end
   end
  end
 end, gameRootPanel, true)

 g_keyboard.bindKeyPress(key, function(widget, keyCode, autoRepeatTicks)
  if shouldSuppressWalkForConsoleChatInput(key) then
   return
  end
  local ticks = tonumber(autoRepeatTicks) or 0
  if ticks <= 0 then return end
  if not arrowWalkModifiersOk() then
   return
  end
  walk(smartWalkDir or dir)
 end, gameRootPanel)
end

function bindTurnKey(key, dir)
 local gameRootPanel = modules.game_interface.getRootPanel()
 g_keyboard.bindKeyDown(key, function() turn(dir, false) end, gameRootPanel)
 g_keyboard.bindKeyPress(key, function() turn(dir, true) end, gameRootPanel)
 g_keyboard.bindKeyUp(key, function()
  local player = g_game.getLocalPlayer()
  if player then player:lockWalk(200) end
 end, gameRootPanel)
end

function unbindWalkKey(key)
 local gameRootPanel = modules.game_interface.getRootPanel()
 g_keyboard.unbindKeyDown(key, gameRootPanel)
 g_keyboard.unbindKeyUp(key, gameRootPanel)
 g_keyboard.unbindKeyPress(key, gameRootPanel)
 for _, mp in pairs(walkKeyByDir) do
  mp[key] = nil
 end
end

function unbindTurnKey(key)
 local gameRootPanel = modules.game_interface.getRootPanel()
 g_keyboard.unbindKeyDown(key, gameRootPanel)
 g_keyboard.unbindKeyPress(key, gameRootPanel)
 g_keyboard.unbindKeyUp(key, gameRootPanel)
end

function unbindAllRotateTurnKeys()
 for _, prefix in ipairs(ALL_ROTATE_PREFIXES) do
  for _, ck in ipairs(CARDINAL_TURN_KEYS) do
   unbindTurnKey(prefix .. '+' .. ck[1])
  end
 end
end

local function getRotateOptionBool(id)
 local opts = modules.client_options
 if opts and opts.getOption then
  local v = opts.getOption(id)
  if type(v) == 'boolean' then
   return v
  end
 end
 return id == 'rotateWithCtrl'
end

function refreshTurnModifierKeys()
 unbindAllRotateTurnKeys()
 local enabledParts = {}
 for _, row in ipairs(ROTATE_OPT_KEYS) do
  if getRotateOptionBool(row.opt) then
   table.insert(enabledParts, row.part)
  end
 end
 local n = #enabledParts
 if n == 0 then
  return
 end
 for mask = 1, bit.lshift(1, n) - 1 do
  local parts = {}
  for i = 1, n do
   if bit.band(mask, bit.lshift(1, i - 1)) ~= 0 then
    table.insert(parts, enabledParts[i])
   end
  end
  table.sort(parts, function(a, b) return MOD_SORT_RANK[a] < MOD_SORT_RANK[b] end)
  local prefix = table.concat(parts, '+')
  for _, ck in ipairs(CARDINAL_TURN_KEYS) do
   bindTurnKey(prefix .. '+' .. ck[1], ck[2])
  end
 end
end

local function bindKeys()
 applyKeyboardDelay(getConfiguredKeyboardDelay())
 for _, keyDir in ipairs(keys) do
  bindWalkKey(keyDir[1], keyDir[2])
 end
 refreshTurnModifierKeys()
end

local function unbindKeys()
 for _, keyDir in ipairs(keys) do
  unbindWalkKey(keyDir[1])
 end
 unbindAllRotateTurnKeys()
end

function WalkController:onInit()
 bindKeys()
 if _G.setWalkDebug == nil then
  _G.setWalkDebug = function(on)
   WALK_DEBUG = on and true or false
   g_logger.info('[WALK] debug = ' .. tostring(WALK_DEBUG))
  end
 end
end

function WalkController:onTerminate()
 unbindKeys()
end

function WalkController:onGameStart()
 local player = g_game.getLocalPlayer()
 if player then
  player:lockWalk(300)
 end
 nextWalkDir = nil
 lastWalkDir = nil
 lastFinishedStep = 0
 lastWalk = 0
 walkLock = 0
 if walkEvent then removeEvent(walkEvent); walkEvent = nil end
 if stairsResumeEvent then removeEvent(stairsResumeEvent); stairsResumeEvent = nil end

 self:registerEvents(g_game, {
  onTeleport = onTeleport,
  onAutoWalk = onAutoWalk
 })

 self:registerEvents(LocalPlayer, {
  onCancelWalk = onCancelWalk,
  onWalkFinish = onWalkFinish,
  onAutoWalk = onAutoWalk
 })

 modules.game_interface.getRootPanel().onFocusChange = stopSmartWalk
 if modules.game_joystick and modules.game_joystick.addOnJoystickMoveListener then
  modules.game_joystick.addOnJoystickMoveListener(function(dir) g_game.walk(dir) end)
 end

 if not g_game.isOfficialTibia() then
  g_game.enableFeature(GameForceFirstAutoWalkStep)
 else
  g_game.disableFeature(GameForceFirstAutoWalkStep)
 end

 if not originalGameTalk then
  originalGameTalk = g_game.talk
  g_game.talk = function(message)
   applySpellWalkLock()
   return originalGameTalk(message)
  end
 end

 refreshTurnModifierKeys()
end

function WalkController:onGameEnd()
 smartWalkDirs = {}
 smartWalkDir = nil
 nextWalkDir = nil
 lastWalkDir = nil
 lastFinishedStep = 0
 lastWalk = 0
 walkLock = 0
 keyDownAt = {}
 if walkEvent then removeEvent(walkEvent); walkEvent = nil end
 if stairsResumeEvent then removeEvent(stairsResumeEvent); stairsResumeEvent = nil end
 if originalGameTalk then
  g_game.talk = originalGameTalk
  originalGameTalk = nil
 end
end
