-- ===== HELPER AUTO TARGET =====
-- Modulo separado para gerenciar o Auto Target do Helper

-- Garante que _Helper existe (sera definido em helper.lua, mas pode ser carregado antes)
if not _Helper then
  _Helper = {}
end

_Helper.AutoTarget = {}

-- ===== CONFIGURACOES LOCAIS =====

local autoTargetModes = {
  ["A"] = 1, -- Closest
  ["B"] = 2, -- Farthest
  ["C"] = 3, -- Lowest Health
  ["D"] = 4, -- Highest Health
  ["E"] = 5, -- Best (most creatures in area)
  ["F"] = 6, -- Closest + Lowest Health (default)
  ["G"] = 7, -- Closest + Highest Health
  ["H"] = 8, -- Farthest + Lowest Health
  ["I"] = 9, -- Farthest + Highest Health
  ["J"] = 10 -- My Priority and Ordered List
}

-- Optimization Caches
local reusableCreatureList = {}
local reusableMonsters = {}
local reusableEntries = {}
for i=1,100 do reusableEntries[i] = {position={x=0,y=0,z=0}, creature=nil} end
local reusableTargets = {
  closest = { id = nil, distance = 99 },
  farthest = { id = nil, distance = -1 },
  lowestHealth = { id = nil, health = 100 },
  highestHealth = { id = nil, health = -1 },
  best = { id = nil, creatures = 0 },
  closestLowestHealth = { id = nil, distance = 99, health = 100 },
  closestHighestHealth = { id = nil, distance = 99, health = -1 },
  farthestLowestHealth = { id = nil, distance = -1, health = 100 },
  farthestHighestHealth = { id = nil, distance = -1, health = -1 }
}

-- ===== FUNCOES DO AUTO TARGET =====

-- Retorna se o auto target esta ativo
_Helper.AutoTarget.isActive = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    return helperConfig.autoTargetEnabled
  end
  return false
end

-- Toggle para habilitar/desabilitar o Auto Target
_Helper.AutoTarget.toggle = function(widget)
  local shooterPanel = _Helper.getShooterPanel and _Helper.getShooterPanel()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()

  if not widget then
    if shooterPanel then
      widget = shooterPanel:recursiveGetChildById("enableAutoTarget")
    elseif enableButtons then
      widget = enableButtons:recursiveGetChildById("enableAutoTarget")
    end
    if not widget then
      return
    end
    widget:setChecked(not widget:isChecked())
  end

  -- Se estiver tentando ativar e autoTargetOnHold esta travado, destrava
  local autoTargetOnHold = _Helper.getAutoTargetOnHold and _Helper.getAutoTargetOnHold()
  if widget:isChecked() and autoTargetOnHold then
    if _Helper.setAutoTargetOnHold then
      _Helper.setAutoTargetOnHold(false)
    end
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoTargetEnabled = widget:isChecked()

    if not helperConfig.autoTargetEnabled then
      helperConfig.currentLockedTargetId = 0
      g_game.cancelAttack()
    else
      -- Quando ativar, buscar e atacar um alvo imediatamente
      scheduleEvent(function()
        _Helper.AutoTarget.check()
      end, 1000)
    end
  end

  modules.game_textmessage.displayGameMessage(
    string.format("Auto Target is %s.", (helperConfig and helperConfig.autoTargetEnabled and "enabled" or "disabled"))
  )

  -- Sincronizar com shortcut panel
  if _Helper.Shortcut and _Helper.Shortcut.syncButton then
    _Helper.Shortcut.syncButton('shortcutAutoTarget', helperConfig and helperConfig.autoTargetEnabled)
  end

  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

local function getOppositeDirection(dir)
  if dir == nil then return nil end
  local d = tonumber(dir)
  if d == nil or d < 0 or d > 3 then return nil end
  return (d + 2) % 4
end

local dirOffsets = {
  [0] = { x = 0, y = -1 },
  [1] = { x = 1, y = 0 },
  [2] = { x = 0, y = 1 },
  [3] = { x = -1, y = 0 },
  [4] = { x = 1, y = -1 },
  [5] = { x = 1, y = 1 },
  [6] = { x = -1, y = 1 },
  [7] = { x = -1, y = -1 }
}

local function isDirectionWalkable(pos, dir, myCharacter)
  local off = dirOffsets[dir]
  if not off then return false end
  local checkPos = { x = pos.x + off.x, y = pos.y + off.y, z = pos.z }
  local tile = g_map.getTile(checkPos)
  if not tile then return false end
  if not tile.isWalkable then return false end
  if not tile:isWalkable(true) then return false end
  if myCharacter then
    local creatures = tile.getCreatures and tile:getCreatures()
    if creatures and #creatures > 0 then
      for i = 1, #creatures do
        local c = creatures[i]
        if c and c ~= myCharacter then return false end
      end
    end
  end
  return true
end

local function pickWalkableDirection(myPos, preferredDir, targetPos, runAway, myCharacter, optModeId, optCreatureEntries, optTargetCreatureId, optGetDistanceBetween, optIsWithinReach)
  local getDistanceBetween = optGetDistanceBetween or _Helper.getDistanceBetween
  local currentDist = targetPos and getDistanceBetween and getDistanceBetween(myPos, targetPos) or 0

  if preferredDir ~= nil then
    local d = tonumber(preferredDir)
    if d and d >= 0 and d <= 7 and isDirectionWalkable(myPos, d, myCharacter) then
      if runAway and targetPos and getDistanceBetween then
        local off = dirOffsets[d]
        local nextPos = { x = myPos.x + off.x, y = myPos.y + off.y, z = myPos.z }
        local nextDist = getDistanceBetween(nextPos, targetPos)
        if nextDist and nextDist >= currentDist then return d end
      else
        return d
      end
    end
  end

  local bestDir = nil
  local bestDist = runAway and -1 or 999
  local candidates = {}

  for dir = 0, 7 do
    if not isDirectionWalkable(myPos, dir, myCharacter) then
    elseif not targetPos or not getDistanceBetween then
      bestDir = dir
      break
    else
      local off = dirOffsets[dir]
      local nextPos = { x = myPos.x + off.x, y = myPos.y + off.y, z = myPos.z }
      local nextDist = getDistanceBetween(nextPos, targetPos)
      if not nextDist then
      elseif runAway then
        if nextDist >= currentDist then
          if optModeId and optCreatureEntries and optTargetCreatureId and optIsWithinReach then
            candidates[#candidates + 1] = { dir = dir, nextDist = nextDist, nextPos = nextPos }
          elseif bestDir == nil or nextDist > bestDist then
            bestDir = dir
            bestDist = nextDist
          end
        end
      else
        if nextDist <= currentDist then
          if optModeId and optCreatureEntries and optTargetCreatureId and optIsWithinReach then
            candidates[#candidates + 1] = { dir = dir, nextDist = nextDist, nextPos = nextPos }
          elseif bestDir == nil or nextDist < bestDist then
            bestDir = dir
            bestDist = nextDist
          end
        end
      end
    end
  end

  if optModeId and optCreatureEntries and optTargetCreatureId and optIsWithinReach and #candidates > 0 then
    for _, cand in ipairs(candidates) do
      local idFromPos = getBestCreatureIdByMode(cand.nextPos, optCreatureEntries, optModeId, getDistanceBetween, optIsWithinReach)
      if idFromPos == optTargetCreatureId then
        return cand.dir
      end
    end
    for _, cand in ipairs(candidates) do
      if runAway then
        if bestDir == nil or cand.nextDist > bestDist then bestDir = cand.dir; bestDist = cand.nextDist end
      else
        if bestDir == nil or cand.nextDist < bestDist then bestDir = cand.dir; bestDist = cand.nextDist end
      end
    end
  end

  if bestDir ~= nil then return bestDir end

  if runAway and targetPos and getDistanceBetween then
    for dir = 0, 7 do
      if isDirectionWalkable(myPos, dir, myCharacter) then
        local off = dirOffsets[dir]
        local nextPos = { x = myPos.x + off.x, y = myPos.y + off.y, z = myPos.z }
        local nextDist = getDistanceBetween(nextPos, targetPos)
        if nextDist and (bestDir == nil or nextDist > bestDist) then
          bestDir = dir
          bestDist = nextDist
        end
      end
    end
  end

  return bestDir
end

local keepWayTolerance = 1

local function getBestCreatureIdByMode(fromPos, creatureEntries, modeId, getDistanceBetween, isWithinReach)
  if not fromPos or not creatureEntries or not modeId or not getDistanceBetween or not isWithinReach then return nil end
  local c, f, lh, hh, clh, chh, flh, fhh
  c = { id = nil, dist = 99 }; f = { id = nil, dist = -1 }
  lh = { id = nil, health = 100 }; hh = { id = nil, health = -1 }
  clh = { id = nil, dist = 99, health = 100 }; chh = { id = nil, dist = 99, health = -1 }
  flh = { id = nil, dist = -1, health = 100 }; fhh = { id = nil, dist = -1, health = -1 }
  for _, entry in pairs(creatureEntries) do
    local pos = entry.position
    local creature = entry.creature
    if not pos or pos.z ~= fromPos.z then goto next end
    if not isWithinReach(fromPos, pos) then goto next end
    if not creature or creature:isDead() then goto next end
    local health = creature:getHealthPercent()
    local d = getDistanceBetween(fromPos, pos) or 99
    if d < c.dist then c = { id = creature:getId(), dist = d } end
    if d > f.dist then f = { id = creature:getId(), dist = d } end
    if health < lh.health then lh = { id = creature:getId(), health = health } end
    if health > hh.health then hh = { id = creature:getId(), health = health } end
    if d < clh.dist or (d == clh.dist and health < clh.health) then clh = { id = creature:getId(), dist = d, health = health } end
    if d < chh.dist or (d == chh.dist and health > chh.health) then chh = { id = creature:getId(), dist = d, health = health } end
    if d > flh.dist or (d == flh.dist and health < flh.health) then flh = { id = creature:getId(), dist = d, health = health } end
    if d > fhh.dist or (d == fhh.dist and health > fhh.health) then fhh = { id = creature:getId(), dist = d, health = health } end
    ::next::
  end
  if modeId == autoTargetModes["A"] then return c.id end
  if modeId == autoTargetModes["B"] then return f.id end
  if modeId == autoTargetModes["C"] then return lh.id end
  if modeId == autoTargetModes["D"] then return hh.id end
  if modeId == autoTargetModes["F"] then return clh.id end
  if modeId == autoTargetModes["G"] then return chh.id end
  if modeId == autoTargetModes["H"] then return flh.id end
  if modeId == autoTargetModes["I"] then return fhh.id end
  return c.id
end

_Helper.AutoTarget.checkKeepWay = function(myCharacter, myPos, targetCreature, keepWayDistance, optModeId, optCreatureEntries)
  if not myCharacter or not myPos or not targetCreature or keepWayDistance <= 0 then return end
  local targetPos = targetCreature:getPosition()
  if not targetPos or targetPos.z ~= myPos.z then return end
  local getDistanceBetween = _Helper.getDistanceBetween
  if not getDistanceBetween then return end
  local dist = getDistanceBetween(myPos, targetPos)
  if dist == nil then return end
  if dist >= keepWayDistance - keepWayTolerance and dist <= keepWayDistance + keepWayTolerance then
    return
  end
  local getDirectionTo = _Helper.getDirectionTo
  if not getDirectionTo then return end
  local isWithinReach = _Helper.isWithinReach
  local preferredDir = nil
  if dist < keepWayDistance - keepWayTolerance then
    local dirToTarget = getDirectionTo(myPos, targetPos)
    if dirToTarget ~= nil then
      preferredDir = getOppositeDirection(dirToTarget)
    else
      preferredDir = getDirectionTo(targetPos, myPos)
    end
    preferredDir = pickWalkableDirection(myPos, preferredDir, targetPos, true, myCharacter, optModeId, optCreatureEntries, targetCreature:getId(), getDistanceBetween, isWithinReach)
  elseif dist > keepWayDistance + keepWayTolerance then
    preferredDir = getDirectionTo(myPos, targetPos)
    preferredDir = pickWalkableDirection(myPos, preferredDir, targetPos, false, myCharacter, optModeId, optCreatureEntries, targetCreature:getId(), getDistanceBetween, isWithinReach)
  end
  if preferredDir == nil then return end
  if g_game and g_game.walk then
    if scheduleEvent then
      scheduleEvent(function() g_game.walk(preferredDir) end, 0)
    else
      g_game.walk(preferredDir)
    end
  end
end

local function creatureFacesPlayer(creatureDir, dirFromCreatureToPlayer)
  if creatureDir == nil or dirFromCreatureToPlayer == nil then return false end
  local c = tonumber(creatureDir)
  local card = tonumber(dirFromCreatureToPlayer)
  if c == nil or card == nil or card < 0 or card > 3 then return false end
  if c == card then return true end
  if c == 4 and (card == 0 or card == 1) then return true end
  if c == 5 and (card == 1 or card == 2) then return true end
  if c == 6 and (card == 2 or card == 3) then return true end
  if c == 7 and (card == 0 or card == 3) then return true end
  return false
end

local perpendicularDirs = {
  [0] = { 1, 3 },
  [1] = { 0, 2 },
  [2] = { 1, 3 },
  [3] = { 0, 2 }
}

_Helper.AutoTarget.checkAvoidWaves = function(myCharacter, myPos, targetCreature)
  if not myCharacter or not myPos or not targetCreature then return end
  local targetPos = targetCreature:getPosition()
  if not targetPos or targetPos.z ~= myPos.z then return end
  local creatureDir = targetCreature.getDirection and targetCreature:getDirection()
  if creatureDir == nil then return end
  local getDirectionTo = _Helper.getDirectionTo
  if not getDirectionTo then return end
  local dirFromCreatureToPlayer = getDirectionTo(targetPos, myPos)
  if not creatureFacesPlayer(creatureDir, dirFromCreatureToPlayer) then return end
  local card = tonumber(dirFromCreatureToPlayer)
  if not card or card < 0 or card > 3 then return end
  local sides = perpendicularDirs[card]
  if not sides then return end
  local sideDir = nil
  for _, d in ipairs(sides) do
    if isDirectionWalkable(myPos, d, myCharacter) then
      sideDir = d
      break
    end
  end
  if sideDir == nil then return end
  if g_game and g_game.walk then
    if scheduleEvent then
      scheduleEvent(function() g_game.walk(sideDir) end, 0)
    else
      g_game.walk(sideDir)
    end
  end
end

-- Atualiza o modo de auto target
_Helper.AutoTarget.updateMode = function(mode)
  local modeId = autoTargetModes[mode]
  if not modeId then
    return
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if helperConfig then
    helperConfig.autoTargetMode = modeId
  end

  local getShooterProfile = _Helper.getShooterProfile
  if getShooterProfile then
    local profile = getShooterProfile()
    if profile then
      profile.autoTargetMode = modeId
    end
  end

  -- Show/hide priority monster list based on mode J and adjust layout
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if enableButtons then
    local priorityMonsterLabel = enableButtons:recursiveGetChildById("priorityMonsterLabel")
    local priorityMonsterInput = enableButtons:recursiveGetChildById("priorityMonsterInput")
    local applyPriorityButton = enableButtons:recursiveGetChildById("applyPriorityButton")
    local enableAutoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
    local ignoreMonsterInput = enableButtons:recursiveGetChildById("ignoreMonsterInput")

    local showPriorityList = (mode == "J")
    if priorityMonsterLabel then priorityMonsterLabel:setVisible(showPriorityList) end
    if priorityMonsterInput then priorityMonsterInput:setVisible(showPriorityList) end
    if applyPriorityButton then applyPriorityButton:setVisible(showPriorityList) end

    -- Dynamically adjust enableAutoTarget anchor based on priority list visibility
    if enableAutoTarget then
      enableAutoTarget:removeAnchor(AnchorTop)
      if showPriorityList and priorityMonsterInput then
        enableAutoTarget:addAnchor(AnchorTop, priorityMonsterInput:getId(), AnchorBottom)
      elseif ignoreMonsterInput then
        enableAutoTarget:addAnchor(AnchorTop, ignoreMonsterInput:getId(), AnchorBottom)
      end
    end

    -- Adjust panel height based on priority list visibility
    local enableButtonsPanel = enableButtons:getParent() and enableButtons or enableButtons
    if enableButtonsPanel then
      enableButtonsPanel:setHeight(showPriorityList and 260 or 220)
    end
  end

  -- Salvar configuracao
  if _Helper.saveSettings then
    _Helper.saveSettings()
  end
end

-- Valida se uma criatura pode ser alvo do auto target
_Helper.AutoTarget.isValidCreature = function(creature)
  if not creature:isMonster() then return false end
  if creature:getMasterId() ~= 0 then return false end
  if creature:getHealthPercent() <= 0 then return false end
  return true
end

-- Verifica se uma criatura está na lista de ignorados (centralized check)
-- Deve ser chamada ANTES de qualquer seleção/validação de alvo
_Helper.AutoTarget.isIgnoredCreature = function(creature, ignoreTable)
  if not creature then return true end
  local creatureName = creature:getName()
  if not creatureName then return false end
  -- Use provided table or fetch fresh one
  ignoreTable = ignoreTable or (_Helper.getIgnoreMonsterTable and _Helper.getIgnoreMonsterTable() or {})
  return ignoreTable[creatureName:lower()] == true
end

-- Funcao principal que verifica e seleciona alvo
_Helper.AutoTarget.check = function()
  local helperAutomaticFunctionsEnabled = _Helper.isHelperAutomaticFunctionsEnabled and
      _Helper.isHelperAutomaticFunctionsEnabled()
  if not helperAutomaticFunctionsEnabled then return end

  -- PZ Guard: handles state transitions and blocks actions while in PZ
  -- Must be called before enabled check to detect PZ exit and restore state
  if _Helper.handlePZState then
    local shouldContinue = _Helper.handlePZState()
    if not shouldContinue then
      return
    end
  end

  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.autoTargetEnabled then return end

  local autoTargetOnHold = _Helper.getAutoTargetOnHold and _Helper.getAutoTargetOnHold()
  if autoTargetOnHold then return end

  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end

  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()

  local afkTime = _Helper.getAfkTime and _Helper.getAfkTime() or 180
  local timer = 0
  if g_ui.getActionTimer then
    timer = g_ui.getActionTimer()
  end
  if timer > afkTime then
    if enableButtons then
      local widget = enableButtons:recursiveGetChildById("enableAutoTarget")
      if widget then
        widget:setChecked(false)
        _Helper.AutoTarget.toggle(widget)
        return
      end
    end
    return
  end

  local position = myCharacter:getPosition()

  local attackingCreature = g_game.getAttackingCreature and g_game.getAttackingCreature()
  if attackingCreature then
    helperConfig.currentLockedTargetId = attackingCreature:getId()
  elseif not attackingCreature and helperConfig.currentLockedTargetId and helperConfig.currentLockedTargetId ~= 0 then
    local stillExists = g_map.getCreatureById(helperConfig.currentLockedTargetId)
    if not stillExists then
      helperConfig.currentLockedTargetId = 0
    end
  end

  local ignoreMonsterTable = _Helper.getIgnoreMonsterTable and _Helper.getIgnoreMonsterTable() or {}
  local isIgnoredCreature = _Helper.AutoTarget.isIgnoredCreature

  local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0 and
      g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil

  local targetPos = currentLockedTarget and currentLockedTarget:getPosition()
  if currentLockedTarget and targetPos and targetPos.z ~= position.z then
    helperConfig.currentLockedTargetId = 0
    currentLockedTarget = nil
    if g_game.cancelAttack then g_game.cancelAttack() end
  end

  local isWithinReach = _Helper.isWithinReach

  -- If current target exists but is now ignored, clear it and cancel attack
  if currentLockedTarget and isIgnoredCreature(currentLockedTarget, ignoreMonsterTable) then
    helperConfig.currentLockedTargetId = 0
    g_game.cancelAttack()
  end

  -- Reset reusable targeting tables
  reusableTargets.closest.id = nil; reusableTargets.closest.distance = 99
  reusableTargets.farthest.id = nil; reusableTargets.farthest.distance = -1
  reusableTargets.lowestHealth.id = nil; reusableTargets.lowestHealth.health = 100
  reusableTargets.highestHealth.id = nil; reusableTargets.highestHealth.health = -1
  reusableTargets.best.id = nil; reusableTargets.best.creatures = 0
  reusableTargets.closestLowestHealth.id = nil; reusableTargets.closestLowestHealth.distance = 99; reusableTargets.closestLowestHealth.health = 100
  reusableTargets.closestHighestHealth.id = nil; reusableTargets.closestHighestHealth.distance = 99; reusableTargets.closestHighestHealth.health = -1
  reusableTargets.farthestLowestHealth.id = nil; reusableTargets.farthestLowestHealth.distance = -1; reusableTargets.farthestLowestHealth.health = 100
  reusableTargets.farthestHighestHealth.id = nil; reusableTargets.farthestHighestHealth.distance = -1; reusableTargets.farthestHighestHealth.health = -1

  local closestTarget = reusableTargets.closest
  local farthestTarget = reusableTargets.farthest
  local lowestHealthTarget = reusableTargets.lowestHealth
  local highestHealthTarget = reusableTargets.highestHealth
  local bestTarget = reusableTargets.best
  local closestLowestHealthTarget = reusableTargets.closestLowestHealth
  local closestHighestHealthTarget = reusableTargets.closestHighestHealth
  local farthestLowestHealthTarget = reusableTargets.farthestLowestHealth
  local farthestHighestHealthTarget = reusableTargets.farthestHighestHealth


  local area = SpellAreas.AREA_CIRCLE3X3
  -- Paladin usa AREA_CIRCLE2X2 (diamond arrow area)
  if myCharacter:isPaladin() then
    area = SpellAreas.AREA_CIRCLE2X2
  end

  local spectators = _Helper.getSpectators and _Helper.getSpectators() or {}
  
  -- Use reusable table
  for k in pairs(reusableCreatureList) do reusableCreatureList[k] = nil end
  local creatureList = reusableCreatureList
  
  for i, creature in pairs(spectators) do
    -- Verificar se é um monstro válido (ignorar players, NPCs, summons, etc.)
    if not _Helper.AutoTarget.isValidCreature(creature) then
      goto continue
    end

    local creaturePos = creature:getPosition()
    if creaturePos then
      local entry = reusableEntries[#creatureList + 1]
      if not entry then
        entry = {position={x=0,y=0,z=0}, creature=nil}
        reusableEntries[#creatureList + 1] = entry
      end
      entry.position.x = creaturePos.x
      entry.position.y = creaturePos.y
      entry.position.z = creaturePos.z
      entry.creature = creature
      table.insert(creatureList, entry)
    end
    ::continue::
  end

  local getDistanceBetween = _Helper.getDistanceBetween
  local countAttackableCreatures = _Helper.countAttackableCreatures
  local positionCompare = _Helper.positionCompare

    -- Use reusable table
    for k in pairs(reusableMonsters) do reusableMonsters[k] = nil end
    local monsters = reusableMonsters
    local maxCreaturesHit = 0

    for i, creatureData in pairs(creatureList) do
      if not isWithinReach or not isWithinReach(position, creatureData.position) or not g_map.isSightClear(position, creatureData.position) then
        goto continue
      end

      -- Verificar se o monstro está na lista de ignorados (usando função centralizada)
      if isIgnoredCreature(creatureData.creature, ignoreMonsterTable) then
        goto continue
      end

      local health = creatureData.creature:getHealthPercent()
      if lowestHealthTarget.id == nil then -- just to make sure it will target someone at 100% health
        lowestHealthTarget = { id = creatureData.creature:getId(), health = health }
      end
      if health < lowestHealthTarget.health then
        lowestHealthTarget = { id = creatureData.creature:getId(), health = health }
      end
      if health > highestHealthTarget.health then
        highestHealthTarget = { id = creatureData.creature:getId(), health = health }
      end
      local creatureDistance = getDistanceBetween and getDistanceBetween(position, creatureData.position) or 99
      if creatureDistance < closestTarget.distance then
        closestTarget = { id = creatureData.creature:getId(), distance = creatureDistance }
      end
      if creatureDistance > farthestTarget.distance then
        farthestTarget = { id = creatureData.creature:getId(), distance = creatureDistance }
      end
      if (creatureDistance < closestLowestHealthTarget.distance) or
          (creatureDistance == closestLowestHealthTarget.distance and health < closestLowestHealthTarget.health) then
        closestLowestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
      end
      if (creatureDistance < closestHighestHealthTarget.distance) or
          (creatureDistance == closestHighestHealthTarget.distance and health > closestHighestHealthTarget.health) then
        closestHighestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
      end
      if (creatureDistance > farthestLowestHealthTarget.distance) or
          (creatureDistance == farthestLowestHealthTarget.distance and health < farthestLowestHealthTarget.health) then
        farthestLowestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
      end
      if (creatureDistance > farthestHighestHealthTarget.distance) or
          (creatureDistance == farthestHighestHealthTarget.distance and health > farthestHighestHealthTarget.health) then
        farthestHighestHealthTarget = { id = creatureData.creature:getId(), distance = creatureDistance, health = health }
      end
      if countAttackableCreatures then
        local creaturesHit = countAttackableCreatures(creatureData.position, 1, area, creatureList, true)
        if creaturesHit > maxCreaturesHit then
          maxCreaturesHit = creaturesHit
          bestTarget.id = creatureData.creature:getId()
          bestTarget.creatures = creaturesHit
        end
      end
      table.insert(monsters, creatureData.creature)
      ::continue::
    end


  -- Mode J: Priority list targeting
  local priorityListTarget = nil
  if helperConfig.autoTargetMode == autoTargetModes["J"] then
    local priorityList = _Helper.AutoTarget.getPriorityMonsterList()
    local bestPriorityIndex = 999999
    local bestPriorityDistance = 999

    for _, monster in ipairs(monsters) do
      local monsterName = monster:getName()
      if monsterName then
        local lowerName = monsterName:lower()
        for priorityIndex, priorityName in ipairs(priorityList) do
          if lowerName == priorityName then
            local monsterDistance = getDistanceBetween and getDistanceBetween(position, monster:getPosition()) or 99
            -- Select monster with highest priority (lowest index)
            -- If same priority, select closest one
            if priorityIndex < bestPriorityIndex or
                (priorityIndex == bestPriorityIndex and monsterDistance < bestPriorityDistance) then
              bestPriorityIndex = priorityIndex
              bestPriorityDistance = monsterDistance
              priorityListTarget = monster
            end
            break
          end
        end
      end
    end

    -- If no priority monster found, fallback to closest target
    if not priorityListTarget and closestTarget.id then
      priorityListTarget = g_map.getCreatureById(closestTarget.id)
    end
  end

  local currentTarget = g_game.getAttackingCreature()
  local target = nil
  if helperConfig.autoTargetMode == autoTargetModes["A"] then
    target = g_map.getCreatureById(closestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["B"] then
    target = g_map.getCreatureById(farthestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["C"] then
    target = g_map.getCreatureById(lowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["D"] then
    target = g_map.getCreatureById(highestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["E"] and bestTarget.id ~= nil then
    target = g_map.getCreatureById(bestTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["F"] then
    target = g_map.getCreatureById(closestLowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["G"] then
    target = g_map.getCreatureById(closestHighestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["H"] then
    target = g_map.getCreatureById(farthestLowestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["I"] then
    target = g_map.getCreatureById(farthestHighestHealthTarget.id)
  elseif helperConfig.autoTargetMode == autoTargetModes["J"] then
    target = priorityListTarget
  end

  if target then
    if helperConfig then helperConfig.currentLockedTargetId = target:getId() end

    if g_game.getFollowingCreature() then
      return
    end

    local keepWay = (helperConfig.keepWayDistance or 0)
    if keepWay > 0 then
      _Helper.AutoTarget.checkKeepWay(myCharacter, position, target, keepWay, helperConfig.autoTargetMode, creatureList)
    end

    if not (currentTarget and currentTarget:getId() == target:getId()) then
      local safeDoThing = _Helper.safeDoThing
      if safeDoThing then safeDoThing(false) end
      g_game.attack(target)
      if safeDoThing then safeDoThing(true) end
    end
  else
    if helperConfig then helperConfig.currentLockedTargetId = 0 end
    if g_game.cancelAttack then g_game.cancelAttack() end
  end

  -- Limpeza: remover referências a objetos C++ para permitir GC
  for i = 1, #reusableEntries do
    reusableEntries[i].creature = nil
  end
  for k in pairs(reusableMonsters) do reusableMonsters[k] = nil end
end

-- Reset do checkbox de auto target no UI
_Helper.AutoTarget.resetCheckbox = function()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not enableButtons then return end

  local enableAutoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
  if enableAutoTarget then
    enableAutoTarget:setChecked(false)
  end
end

-- Carrega o estado do autoTarget para o UI
_Helper.AutoTarget.loadToUI = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not helperConfig or not enableButtons then return end

  local enableAutoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
  if enableAutoTarget then
    enableAutoTarget:setChecked(helperConfig.autoTargetEnabled or false)
  end

  local currentModeKey = "A"
  local autoTargetMode = enableButtons:recursiveGetChildById("autoTargetMode")
  if autoTargetMode then
    for k, v in pairs(autoTargetModes) do
      if v == helperConfig.autoTargetMode then
        currentModeKey = k
        autoTargetMode:setCurrentOption(k)
        break
      end
    end
  end

  -- Show/hide priority monster list based on mode J and adjust layout
  local priorityMonsterLabel = enableButtons:recursiveGetChildById("priorityMonsterLabel")
  local priorityMonsterInput = enableButtons:recursiveGetChildById("priorityMonsterInput")
  local applyPriorityButton = enableButtons:recursiveGetChildById("applyPriorityButton")
  local ignoreMonsterInput = enableButtons:recursiveGetChildById("ignoreMonsterInput")

  local showPriorityList = (currentModeKey == "J")
  if priorityMonsterLabel then priorityMonsterLabel:setVisible(showPriorityList) end
  if priorityMonsterInput then priorityMonsterInput:setVisible(showPriorityList) end
  if applyPriorityButton then applyPriorityButton:setVisible(showPriorityList) end

  -- Dynamically adjust enableAutoTarget anchor based on priority list visibility
  if enableAutoTarget then
    enableAutoTarget:removeAnchor(AnchorTop)
    if showPriorityList and priorityMonsterInput then
      enableAutoTarget:addAnchor(AnchorTop, priorityMonsterInput:getId(), AnchorBottom)
    elseif ignoreMonsterInput then
      enableAutoTarget:addAnchor(AnchorTop, ignoreMonsterInput:getId(), AnchorBottom)
    end
  end

  -- Adjust panel height based on priority list visibility
  enableButtons:setHeight(showPriorityList and 260 or 220)

  -- Load priority monster list text
  if priorityMonsterInput and helperConfig.priorityMonsterList then
    priorityMonsterInput:setText(helperConfig.priorityMonsterList)
  end

  local keepWayDistanceInput = enableButtons:recursiveGetChildById("keepWayDistance")
  if keepWayDistanceInput then
    keepWayDistanceInput:setText(tostring(helperConfig.keepWayDistance or 0))
  end
  local avoidWavesCheck = enableButtons:recursiveGetChildById("avoidWavesCheck")
  if avoidWavesCheck then
    avoidWavesCheck:setChecked(helperConfig.avoidWaves == true)
  end
end

_Helper.AutoTarget.getModes = function()
  if g_helperCore and g_helperCore.getAutoTargetModesTable then
    return g_helperCore.getAutoTargetModesTable()
  end
  return autoTargetModes
end

_Helper.AutoTarget.getModeId = function(modeKey)
  if g_helperCore and g_helperCore.getAutoTargetModeId then
    return g_helperCore.getAutoTargetModeId(modeKey)
  end
  return autoTargetModes[modeKey]
end

-- Apply priority monster list
_Helper.AutoTarget.applyPriorityList = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  local enableButtons = _Helper.getEnableButtons and _Helper.getEnableButtons()
  if not helperConfig or not enableButtons then return end

  local priorityMonsterInput = enableButtons:recursiveGetChildById("priorityMonsterInput")
  if not priorityMonsterInput then return end

  local text = priorityMonsterInput:getText() or ""

  -- Remove numbers from input (only letters, spaces and commas allowed)
  local sanitizedText = text:gsub("%d", "")

  -- Update the input field with sanitized text (without numbers)
  if sanitizedText ~= text then
    priorityMonsterInput:setText(sanitizedText)
    modules.game_textmessage.displayGameMessage("Numbers removed from priority list.")
  end

  -- Save the sanitized list
  helperConfig.priorityMonsterList = sanitizedText

  if _Helper.saveSettings then
    _Helper.saveSettings()
  end

  -- Update button state via magic_shooter_panel module
  if modules.game_helper and modules.game_helper.magicShooter and modules.game_helper.magicShooter.loadPriorityMonsterList then
    modules.game_helper.magicShooter.loadPriorityMonsterList()
  end

  modules.game_textmessage.displayGameMessage("Priority monster list applied.")
end

-- Parse priority monster list into ordered array (first = highest priority)
_Helper.AutoTarget.getPriorityMonsterList = function()
  local helperConfig = _Helper.getHelperConfig and _Helper.getHelperConfig()
  if not helperConfig or not helperConfig.priorityMonsterList then
    return {}
  end

  local priorityList = {}
  local text = helperConfig.priorityMonsterList or ""

  for monsterName in string.gmatch(text, "([^,]+)") do
    -- Trim whitespace and convert to lowercase
    monsterName = monsterName:match("^%s*(.-)%s*$"):lower()
    if monsterName ~= "" then
      table.insert(priorityList, monsterName)
    end
  end

  return priorityList
end

-- ===== FIM HELPER AUTO TARGET =====
