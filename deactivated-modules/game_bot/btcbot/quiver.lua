--[[
  BTC Bot - Quiver Management

  Reabastece automaticamente o quiver (aljava) com flechas/projéteis
  quando a quantidade cai abaixo do threshold configurado.

  Funcionamento:
  - Detecta o quiver na mão direita (SLOT_RIGHT = 5) - primary
  - Fallback: procura container com "quiver" no nome
  - Quando contagem < refillBelow -> move municão da backpack para o quiver
  - Enche completamente (até a capacidade do quiver)
]]

BTCQuiver = BTCQuiver or {}

-- Configuração padrão
BTCQuiver.defaultConfig = {
  enabled    = false,
  itemId     = 3447,  -- Arrow
  refillBelow = 100,  -- Reabastece quando tiver menos que isso
}

-- Lista de munições disponíveis no popup (icon selector)
BTCQuiver.ammoList = {
  -- Arrows
  { id = 3447,  name = "Arrow" },
  { id = 762,   name = "Poison Arrow" },
  { id = 761,   name = "Shiver Arrow" },
  { id = 763,   name = "Burning Arrow" },
  { id = 7364,  name = "Flaming Arrow" },
  { id = 7365,  name = "Sniper Arrow" },
  { id = 21470, name = "Crystalline Arrow" },
  { id = 16142, name = "Envenomed Arrow" },
  -- Bolts / Outros
  { id = 3448,  name = "Bolt" },
  { id = 3449,  name = "Power Bolt" },
  { id = 3450,  name = "Piercing Bolt" },
  { id = 16141, name = "Drill Bolt" },
  { id = 25757, name = "Vortex Bolt" },
  { id = 35901, name = "Spectral Bolt" },
  { id = 35902, name = "Onyx Arrow" },
  { id = 15793, name = "Prismatic Arrow" },
}

-- Controles
BTCQuiver.config         = nil
BTCQuiver.lastActionTime = 0
BTCQuiver.actionCooldown = 600   -- ms entre cada move

-- ============================================================
-- INIT / CONFIG
-- ============================================================

function BTCQuiver.init()
  BTCQuiver.config = BTCQuiver.loadConfig()
end

function BTCQuiver.loadConfig()
  local saved = BTCConfig.get("quiver")
  if saved then return saved end
  return {
    enabled     = BTCQuiver.defaultConfig.enabled,
    itemId      = BTCQuiver.defaultConfig.itemId,
    refillBelow = BTCQuiver.defaultConfig.refillBelow,
  }
end

function BTCQuiver.saveConfig()
  BTCConfig.set("quiver", BTCQuiver.config)
end

-- ============================================================
-- HELPERS
-- ============================================================

-- Encontra o container do quiver:
-- 1) Mão direita (SLOT_RIGHT = 5) se for um container
-- 2) Fallback: container com "quiver" no nome
function BTCQuiver.findQuiverContainer()
  if not g_game.isOnline() then return nil end
  local player = g_game.getLocalPlayer()
  if not player then return nil end

  local containers = g_game.getContainers()

  -- Primary: mão direita
  local rightItem = player:getInventoryItem(5)  -- SLOT_RIGHT
  if rightItem then
    for _, container in pairs(containers) do
      local cItem = container:getContainerItem()
      if cItem and cItem:getId() == rightItem:getId() then
        return container
      end
    end
  end

  -- Fallback: nome contém "quiver"
  for _, container in pairs(containers) do
    if container:getName():lower():find("quiver") then
      return container
    end
  end

  return nil
end

-- Conta a quantidade do item desejado dentro do quiver
function BTCQuiver.countAmmoInQuiver(quiverContainer, itemId)
  if not quiverContainer or not itemId or itemId == 0 then return 0 end
  local count = 0
  for slot = 0, quiverContainer:getItemsCount() - 1 do
    local item = quiverContainer:getItem(slot)
    if item and item:getId() == itemId then
      count = count + (item:getCount() or 1)
    end
  end
  return count
end

-- Procura o item de munição em containers abertos (exceto o quiver)
function BTCQuiver.findAmmoInContainers(itemId, excludeContainer)
  if not itemId or itemId == 0 then return nil end
  local containers = g_game.getContainers()
  for _, container in pairs(containers) do
    if container ~= excludeContainer then
      for slot = 0, container:getItemsCount() - 1 do
        local item = container:getItem(slot)
        if item and item:getId() == itemId then
          return item
        end
      end
    end
  end
  return nil
end

function BTCQuiver.canAct()
  return (g_clock.millis() - BTCQuiver.lastActionTime) >= BTCQuiver.actionCooldown
end

-- Retorna o nome da munição pelo ID
function BTCQuiver.getAmmoName(itemId)
  for _, ammo in ipairs(BTCQuiver.ammoList) do
    if ammo.id == itemId then return ammo.name end
  end
  return "Item #" .. tostring(itemId)
end

-- ============================================================
-- EXECUTE (loop principal)
-- ============================================================

function BTCQuiver.execute()
  if not BTCQuiver.config or not BTCQuiver.config.enabled then return end
  if not g_game.isOnline() then return end
  if not BTCQuiver.canAct() then return end

  local itemId = BTCQuiver.config.itemId
  if not itemId or itemId == 0 then return end

  local refillBelow = BTCQuiver.config.refillBelow or 100

  -- Encontra o quiver
  local quiver = BTCQuiver.findQuiverContainer()
  if not quiver then return end

  -- Quiver cheio? (sem espaço para mais stacks)
  if quiver:getItemsCount() >= quiver:getCapacity() then return end

  -- Conta munição atual
  local ammoCount = BTCQuiver.countAmmoInQuiver(quiver, itemId)
  if ammoCount >= refillBelow then return end

  -- Encontra munição na backpack e move para o quiver
  local ammoItem = BTCQuiver.findAmmoInContainers(itemId, quiver)
  if ammoItem then
    local destPos = quiver:getSlotPosition(quiver:getItemsCount())
    g_game.move(ammoItem, destPos, ammoItem:getCount())
    BTCQuiver.lastActionTime = g_clock.millis()
  end
end

-- ============================================================
-- UI
-- ============================================================

function BTCQuiver.createUI(parent)
  parent:destroyChildren()

  local desc = g_ui.createWidget('Label', parent)
  desc:setText('Reabastece o quiver automaticamente.')
  desc:setColor('#888888')
  desc:setHeight(16)
  desc:setMarginTop(5)
  desc:setMarginBottom(5)

  -- Linha: Seleção de munição
  local ammoRow = g_ui.createWidget('Panel', parent)
  ammoRow:setLayout(UIHorizontalLayout.create(ammoRow))
  ammoRow:getLayout():setSpacing(5)
  ammoRow:setHeight(36)
  ammoRow:setMarginTop(5)

  local ammoLbl = g_ui.createWidget('Label', ammoRow)
  ammoLbl:setText('Munição:')
  ammoLbl:setColor('#aaaaaa')
  ammoLbl:setWidth(55)

  local ammoPreview = g_ui.createWidget('UIItem', ammoRow)
  ammoPreview:setSize({width = 34, height = 34})
  ammoPreview:setVirtual(true)
  local curAmmoId = BTCQuiver.config.itemId or 3447
  if curAmmoId > 0 then ammoPreview:setItemId(curAmmoId) end

  local selectBtn = g_ui.createWidget('Button', ammoRow)
  selectBtn:setText('...')
  selectBtn:setWidth(26)
  selectBtn:setTooltip('Clique e depois clique num item do jogo')

  local ammoName = g_ui.createWidget('Label', ammoRow)
  ammoName:setText(BTCQuiver.getAmmoName(curAmmoId))
  ammoName:setColor('#00BFFF')
  ammoName:setWidth(140)

  selectBtn.onClick = function()
    BTCItemSelector.start(function(itemId)
      BTCQuiver.config.itemId = itemId
      BTCQuiver.saveConfig()
      ammoPreview:setItemId(itemId)
      ammoName:setText(BTCQuiver.getAmmoName(itemId))
    end)
  end

  -- Linha: Threshold
  local threshRow = g_ui.createWidget('Panel', parent)
  threshRow:setLayout(UIHorizontalLayout.create(threshRow))
  threshRow:getLayout():setSpacing(5)
  threshRow:setHeight(26)
  threshRow:setMarginTop(5)

  local threshLbl = g_ui.createWidget('Label', threshRow)
  threshLbl:setText('Reabastecer quando <')
  threshLbl:setColor('#aaaaaa')
  threshLbl:setWidth(140)

  local minusBtn = g_ui.createWidget('Button', threshRow)
  minusBtn:setText('-')
  minusBtn:setWidth(22)

  local threshValue = g_ui.createWidget('Label', threshRow)
  threshValue:setText(tostring(BTCQuiver.config.refillBelow or 100))
  threshValue:setColor('#00BFFF')
  threshValue:setTextAlign(AlignCenter)
  threshValue:setWidth(40)

  local plusBtn = g_ui.createWidget('Button', threshRow)
  plusBtn:setText('+')
  plusBtn:setWidth(22)

  local unitLbl = g_ui.createWidget('Label', threshRow)
  unitLbl:setText('unidades')
  unitLbl:setColor('#666666')
  unitLbl:setWidth(60)

  minusBtn.onClick = function()
    local val = (BTCQuiver.config.refillBelow or 100) - 10
    if val < 10 then val = 10 end
    BTCQuiver.config.refillBelow = val
    BTCQuiver.saveConfig()
    threshValue:setText(tostring(val))
  end

  plusBtn.onClick = function()
    local val = (BTCQuiver.config.refillBelow or 100) + 10
    if val > 2000 then val = 2000 end
    BTCQuiver.config.refillBelow = val
    BTCQuiver.saveConfig()
    threshValue:setText(tostring(val))
  end

  local sep2 = g_ui.createWidget('HorizontalSeparator', parent)
  sep2:setMarginTop(8)
  sep2:setMarginBottom(5)

  local tipLbl = g_ui.createWidget('Label', parent)
  tipLbl:setText('O quiver deve estar aberto (container visivel) para funcionar.')
  tipLbl:setColor('#666666')
  tipLbl:setHeight(16)
end

return BTCQuiver
