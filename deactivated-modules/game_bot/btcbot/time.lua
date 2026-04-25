--[[
  BTC Bot - Modulo Time (Uso Temporizado de Itens)

  - 5 slots de item temporizado (seleção visual via BotItem)
  - Intervalo em segundos ou minutos (seletor por slot)
]]

BTCTime = BTCTime or {}

-- Configuracao padrao
BTCTime.defaultConfig = {
  enabled = false,
  slots = {
    { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" },
    { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" },
    { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" },
    { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" },
    { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" },
  },
}

-- Timers de controle
BTCTime.lastUseTime = { 0, 0, 0, 0, 0 }

-- Config atual
BTCTime.config = nil

-- Inicializa o modulo
function BTCTime.init()
  BTCTime.config = BTCTime.loadConfig()
  BTCTime.lastUseTime = { 0, 0, 0, 0, 0 }
end

-- Carrega configuracao salva ou usa padrao
function BTCTime.loadConfig()
  local saved = BTCConfig.get("time")
  if saved then
    if not saved.slots then
      saved.slots = {}
    end
    while #saved.slots < 5 do
      table.insert(saved.slots, { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" })
    end
    for i = 1, 5 do
      local s = saved.slots[i]
      if s and s.intervalUnit ~= "min" and s.intervalUnit ~= "sec" then
        s.intervalUnit = "sec"
      end
    end
    return saved
  end
  local cfg = {
    enabled = false,
    slots = {},
  }
  for i = 1, 5 do
    cfg.slots[i] = { enabled = false, itemId = 0, interval = 60, intervalUnit = "sec" }
  end
  return cfg
end

-- Salva configuracao
function BTCTime.saveConfig()
  BTCConfig.set("time", BTCTime.config)
end

-- Intervalo em milissegundos conforme unidade do slot
function BTCTime.getSlotIntervalMs(slot)
  if not slot or not slot.interval or slot.interval < 1 then return 60000 end
  local unit = slot.intervalUnit or "sec"
  if unit == "min" then
    return slot.interval * 60 * 1000
  end
  return slot.interval * 1000
end

-- Encontra e usa um item pelo ID
function BTCTime.useItemById(itemId)
  if not g_game.isOnline() then return false end
  local player = g_game.getLocalPlayer()
  if not player then return false end
  g_game.useInventoryItem(itemId)
  return true
end

-- ============================================================
-- EXECUTE (loop principal)
-- ============================================================

function BTCTime.execute()
  if not BTCTime.config or not BTCTime.config.enabled then return end
  if not g_game.isOnline() then return end

  local now = g_clock.millis()

  for i = 1, 5 do
    local slot = BTCTime.config.slots[i]
    if slot and slot.enabled and slot.itemId and slot.itemId > 0 then
      local intervalMs = BTCTime.getSlotIntervalMs(slot)
      if intervalMs > 0 then
        local lastUse = BTCTime.lastUseTime[i] or 0
        if (now - lastUse) >= intervalMs then
          if BTCTime.useItemById(slot.itemId) then
            BTCTime.lastUseTime[i] = now
          end
        end
      end
    end
  end
end

-- ============================================================
-- UI
-- ============================================================

function BTCTime.createUI(parent)
  parent:destroyChildren()

  local descLabel = g_ui.createWidget('Label', parent)
  descLabel:setText('Use itens automaticamente em intervalos de tempo.')
  descLabel:setColor('#888888')
  descLabel:setHeight(16)
  descLabel:setMarginTop(5)
  descLabel:setMarginBottom(5)

  for i = 1, 5 do
    BTCTime.createSlotUI(parent, i)
  end
end

-- ============================================================
-- SLOT TEMPORIZADO (BotItem + intervalo + unidade)
-- ============================================================

function BTCTime.createSlotUI(parent, slotIndex)
  local slot = BTCTime.config.slots[slotIndex]
  if not slot then return end
  if not slot.intervalUnit then slot.intervalUnit = "sec" end

  local slotPanel = g_ui.createWidget('Panel', parent)
  slotPanel:setLayout(UIVerticalLayout.create(slotPanel))
  slotPanel:setHeight(45)
  slotPanel:setMarginTop(5)
  slotPanel:setBackgroundColor('#1a1a1a')
  slotPanel:setPadding(5)

  local row1 = g_ui.createWidget('Panel', slotPanel)
  row1:setLayout(UIHorizontalLayout.create(row1))
  row1:getLayout():setSpacing(5)
  row1:setHeight(34)

  local enableCheck = g_ui.createWidget('CheckBox', row1)
  enableCheck:setText('Slot ' .. slotIndex)
  enableCheck:setChecked(slot.enabled)
  enableCheck:setWidth(60)
  enableCheck.onCheckChange = function(widget, checked)
    BTCTime.config.slots[slotIndex].enabled = checked
    BTCTime.saveConfig()
  end

  local itemPreview = g_ui.createWidget('UIItem', row1)
  itemPreview:setSize({width = 34, height = 34})
  itemPreview:setVirtual(true)
  if slot.itemId and slot.itemId > 0 then
    itemPreview:setItemId(slot.itemId)
  end

  local selectBtn = g_ui.createWidget('Button', row1)
  selectBtn:setText('...')
  selectBtn:setWidth(26)
  selectBtn:setTooltip('Selecionar item')
  selectBtn.onClick = function()
    BTCItemSelector.start(function(itemId)
      BTCTime.config.slots[slotIndex].itemId = itemId
      BTCTime.saveConfig()
      itemPreview:setItemId(itemId)
    end)
  end

  local timeInput = g_ui.createWidget('TextEdit', row1)
  timeInput:setWidth(45)
  timeInput:setText(tostring(slot.interval))

  local unitCombo = g_ui.createWidget('ComboBox', row1)
  unitCombo:setWidth(72)
  unitCombo:addOption('Seg', 'sec')
  unitCombo:addOption('Min', 'min')
  if (slot.intervalUnit or "sec") == "min" then
    unitCombo:setCurrentIndex(2)
  else
    unitCombo:setCurrentIndex(1)
  end

  timeInput.onTextChange = function(widget, text)
    local newInterval = tonumber(text) or 60
    if newInterval < 1 then newInterval = 1 end
    BTCTime.config.slots[slotIndex].interval = newInterval
    BTCTime.saveConfig()
  end

  unitCombo.onOptionChange = function(widget, text, data)
    local u = data
    if not u and text then
      u = (text == "Min" or text:lower():find("min")) and "min" or "sec"
    end
    BTCTime.config.slots[slotIndex].intervalUnit = u or "sec"
    BTCTime.saveConfig()
  end
end

return BTCTime
