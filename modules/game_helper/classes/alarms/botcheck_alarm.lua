-- ===== HELPER BOTCHECK ALARM =====
-- Modulo para gerenciar o alarme de bot check do Helper
-- Registra opcode 230 e toca alarme em loop ate o servidor enviar "stop"

if not _Helper then
  _Helper = {}
end

_Helper.BotCheckAlarm = {}

-- ===== CONFIGURACOES LOCAIS =====

local OPCODE_BOTCHECK_ALERT = 230
local SOUND_FILE = '/sounds/gm_detected.ogg'
local LOOP_INTERVAL = 3000 -- 3 segundos entre toques

local loopEvent = nil
local isAlertActive = false
local soundPreloaded = false

local function ensurePreloaded()
  if not soundPreloaded and g_sounds then
    g_sounds.preload(SOUND_FILE)
    soundPreloaded = true
  end
end

-- ===== FUNCOES DO BOTCHECK ALARM =====

local function playAlertSound()
  if not isAlertActive then
    return
  end

  g_sounds.stopAlarm()

  if g_sounds then
    ensurePreloaded()
    g_sounds.playAlarm(SOUND_FILE)
  end
end

local function scheduleLoop()
  if not isAlertActive then
    return
  end

  loopEvent = scheduleEvent(function()
    if isAlertActive then
      playAlertSound()
      scheduleLoop()
    end
  end, LOOP_INTERVAL)
end

_Helper.BotCheckAlarm.start = function()
  if isAlertActive then
    return
  end

  isAlertActive = true

  playAlertSound()
  scheduleLoop()

  pcall(function()
    if modules.game_helper and modules.game_helper.cavebot then
      if modules.game_helper.cavebot.isEnabled() then
        modules.game_helper.cavebot.toggleButtonPress()
      end
    end
  end)

  pcall(function()
    if _Helper.SmartFollow then
      if _Helper.SmartFollow.isEnabled() then
        _Helper.SmartFollow.resetCheckbox()
      end
    end
  end)

  local config = _Helper.AlarmSettings.getConfig()
  if config.flash_window and config.flash_window.enabled then
    g_window.flashWindow(0)
  end
end

_Helper.BotCheckAlarm.stop = function()
  if not isAlertActive then
    return
  end

  isAlertActive = false

  if loopEvent then
    removeEvent(loopEvent)
    loopEvent = nil
  end

  g_sounds.stopAlarm()
end

-- Handler do opcode
_Helper.BotCheckAlarm.onExtendedOpcode = function(protocol, opcode, buffer)
  local command = buffer
  if buffer and buffer.trim then
    command = buffer:trim()
  end

  if command == "start" then
    _Helper.BotCheckAlarm.start()
  elseif command == "stop" then
    _Helper.BotCheckAlarm.stop()
  end
end

-- Registra o opcode (chamado no init do helper)
_Helper.BotCheckAlarm.register = function()
  ensurePreloaded()
  pcall(function() ProtocolGame.unregisterExtendedOpcode(OPCODE_BOTCHECK_ALERT) end)
  ProtocolGame.registerExtendedOpcode(OPCODE_BOTCHECK_ALERT, _Helper.BotCheckAlarm.onExtendedOpcode)
end

-- Desregistra o opcode (chamado no terminate do helper)
_Helper.BotCheckAlarm.unregister = function()
  _Helper.BotCheckAlarm.stop()
  pcall(function()
    ProtocolGame.unregisterExtendedOpcode(OPCODE_BOTCHECK_ALERT)
  end)
end

-- Reset state (chamado no offline/logout)
_Helper.BotCheckAlarm.resetCheckbox = function()
  _Helper.BotCheckAlarm.stop()
end

-- ===== FIM HELPER BOTCHECK ALARM =====
