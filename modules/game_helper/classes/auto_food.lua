-- ===== HELPER AUTO FOOD =====
-- Modulo separado para gerenciar o Auto Food Eating do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.AutoFood = {}

-- ===== CONFIGURACOES LOCAIS =====

local foodConfig = { id = "food", exhaustion = 3000 }



-- ===== FUNCOES DO AUTO FOOD =====

-- Toggle para habilitar/desabilitar o Auto Food
_Helper.AutoFood.toggle = function(checked)
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoEatFood = checked
  end
  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Funcao principal que verifica e usa comida
_Helper.AutoFood.check = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not g_game.isOnline() or not helperConfig or not helperConfig.autoEatFood then
    return
  end

  local getSpellCooldown = _Helper.getSpellCooldown
  if not getSpellCooldown then
    return
  end

  local cooldown = getSpellCooldown(foodConfig.id)
  if cooldown >= g_clock.millis() then
    return true
  end

  local currentPlayer = g_game.getLocalPlayer()
  if not currentPlayer then
    return
  end

  local safeDoThing = _Helper.safeDoThing
  local setSpellCooldown = _Helper.setSpellCooldown

  -- Prioridade: infinite food items
  for _, id in pairs(InfiniteFoodIds) do
    if currentPlayer:getInventoryCount(id) > 0 then
      if safeDoThing then safeDoThing(false) end
      g_game.useInventoryItem(id)
      if safeDoThing then safeDoThing(true) end
      if setSpellCooldown then
        setSpellCooldown(foodConfig.id, g_clock.millis() + foodConfig.exhaustion)
      end
      return
    end
  end

  -- Normal food items
  for _, id in pairs(FoodIds) do
    if currentPlayer:getInventoryCount(id) > 0 then
      if safeDoThing then safeDoThing(false) end
      g_game.useInventoryItem(id)
      if safeDoThing then safeDoThing(true) end
      if setSpellCooldown then
        setSpellCooldown(foodConfig.id, g_clock.millis() + foodConfig.exhaustion)
      end
      break
    end
  end
end

-- Reset do eatFood checkbox no UI
_Helper.AutoFood.resetCheckbox = function()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not toolsPanel then return end

  local eatFood = toolsPanel:recursiveGetChildById("eatFood")
  if eatFood then
    eatFood:setChecked(false)
  end
end

-- Carrega o estado do autoEatFood para o UI
_Helper.AutoFood.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local toolsPanel = _Helper.getToolsPanel and _Helper.getToolsPanel()
  if not helperConfig or not toolsPanel then return end

  local eatFood = toolsPanel:recursiveGetChildById("eatFood")
  if eatFood then
    eatFood:setChecked(helperConfig.autoEatFood or false)
  end
end

-- Getter para foodIds (caso outros modulos precisem)
_Helper.AutoFood.getFoodIds = function()
  return FoodIds
end

-- Getter para infiniteFoodIds (caso outros modulos precisem)
_Helper.AutoFood.getInfiniteFoodIds = function()
  return InfiniteFoodIds
end

-- Getter para foodConfig (caso outros modulos precisem)
_Helper.AutoFood.getFoodConfig = function()
  return foodConfig
end

-- ===== FIM HELPER AUTO FOOD =====
