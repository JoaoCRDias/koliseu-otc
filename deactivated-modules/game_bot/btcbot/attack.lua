--[[
  BTC Bot - Sistema de Attack
  
  Auto-attack em monstros
  6 slots de spells de ataque com cooldown tracking
  Lista de prioridade e ignore
]]

BTCAttack = BTCAttack or {}

-- Configuracao padrao
BTCAttack.defaultConfig = {
  enabled = true,
  autoAttack = true,
  attackPlayers = false,
  attackMonsters = true,
  attackRange = 8,  -- Range de deteccao de monstros na tela
  -- 6 slots de ataque (spell ou rune)
  -- type = "spell" ou "rune"
  -- spellId = id do servidor (para cooldown)
  -- iconId = clientId do sprite (para renderizacao)
  -- itemId = id do item (para runas)
  spells = {
    { enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0, harmony = "any" },
    { enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0, harmony = "any" },
    { enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0, harmony = "any" },
    { enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0, harmony = "any" },
    { enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0, harmony = "any" },
    { enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0, harmony = "any" },
  },
  -- Listas de targeting
  priorityList = {},
  ignoreList = {},
  -- Target mode: A-I (see getAttackableCreaturesSmart)
  targetMode = "F",
  lockedTargetId = 0,
}

-- Lista de runas de ataque
BTCAttack.attackRunes = {
  { itemId = 3155, name = "Sudden Death Rune", shortName = "SD" },
  { itemId = 3161, name = "Heavy Magic Missile", shortName = "HMM" },
  { itemId = 3180, name = "Fireball Rune", shortName = "FB" },
  { itemId = 3178, name = "Great Fireball Rune", shortName = "GFB" },
  { itemId = 3191, name = "Explosion Rune", shortName = "Explosion" },
  { itemId = 3200, name = "Thunderstorm Rune", shortName = "Thunderstorm" },
  { itemId = 3202, name = "Stoneshower Rune", shortName = "Stoneshower" },
  { itemId = 3198, name = "Avalanche Rune", shortName = "Avalanche" },
  { itemId = 3164, name = "Icicle Rune", shortName = "Icicle" },
  { itemId = 3149, name = "Energy Bomb Rune", shortName = "Energy Bomb" },
  { itemId = 3175, name = "Fire Bomb Rune", shortName = "Fire Bomb" },
}

-- Lista de spells de ataque disponiveis (dados do servidor)
-- VOCACOES (clientid): Knight=1, Paladin=2, Sorcerer=3, Druid=4, Monk=5, EK=11, RP=12, MS=13, ED=14, ExMonk=15
BTCAttack.attackSpells = {
  -- ===== KNIGHT (clientid 1 base, 11 promoted) =====
  { words = "exori", name = "Berserk", cooldown = 3000, mana = 115, voc = {1,11} },
  { words = "exori gran", name = "Fierce Berserk", cooldown = 3000, mana = 340, voc = {1,11} },
  { words = "exori mas", name = "Groundshaker", cooldown = 4000, mana = 160, voc = {1,11} },
  { words = "exori min", name = "Front Sweep", cooldown = 6000, mana = 200, voc = {1,11} },
  { words = "exori ico", name = "Brutal Strike", cooldown = 6000, mana = 30, voc = {1,11} },
  { words = "exori gran ico", name = "Annihilation", cooldown = 8000, mana = 300, voc = {1,11} },
  { words = "exori hur", name = "Whirlwind Throw", cooldown = 6000, mana = 40, voc = {1,11} },
  { words = "exori amp kor", name = "Executioner's Throw", cooldown = 12000, mana = 225, voc = {1,11} },
  
  -- ===== PALADIN (clientid 2 base, 12 promoted) =====
  { words = "exori con", name = "Ethereal Spear", cooldown = 2000, mana = 25, voc = {2,12} },
  { words = "exori san", name = "Divine Missile", cooldown = 2000, mana = 20, voc = {2,12} },
  { words = "exevo mas san", name = "Divine Caldera", cooldown = 3000, mana = 160, voc = {2,12} },
  { words = "exori gran con", name = "Strong Ethereal Spear", cooldown = 4000, mana = 55, voc = {2,12} },
  { words = "exevo tempo mas san", name = "Divine Grenade", cooldown = 1000, mana = 160, voc = {2,12} },
  { words = "utori san", name = "Holy Flash", cooldown = 40000, mana = 30, voc = {2,12} },
  
  -- ===== SORCERER (clientid 3 base, 13 promoted) =====
  { words = "exevo flam hur", name = "Fire Wave", cooldown = 4000, mana = 25, voc = {3,13} },
  { words = "exevo vis hur", name = "Energy Wave", cooldown = 8000, mana = 170, voc = {3,13} },
  { words = "exevo vis lux", name = "Energy Beam", cooldown = 4000, mana = 40, voc = {3,13} },
  { words = "exevo gran vis lux", name = "Great Energy Beam", cooldown = 6000, mana = 110, voc = {3,13} },
  { words = "exevo gran mas flam", name = "Hell's Core", cooldown = 7000, mana = 1100, voc = {3,13} },
  { words = "exevo gran mas vis", name = "Rage of the Skies", cooldown = 6000, mana = 600, voc = {3,13} },
  { words = "exori mort", name = "Death Strike", cooldown = 2000, mana = 20, voc = {3,13} },
  { words = "exori moe", name = "Soul Strike", cooldown = 2000, mana = 20, voc = {3,13} },
  { words = "exevo max mort", name = "Doom", cooldown = 30000, mana = 600, voc = {3,13} },
  { words = "exori kor", name = "Inflict Wound", cooldown = 30000, mana = 30, voc = {3,13} },
  
  -- ===== DRUID (clientid 4 base, 14 promoted) =====
  { words = "exevo tera hur", name = "Terra Wave", cooldown = 4000, mana = 170, voc = {4,14} },
  { words = "exevo frigo hur", name = "Ice Wave", cooldown = 4000, mana = 25, voc = {4,14} },
  { words = "exevo gran frigo hur", name = "Strong Ice Wave", cooldown = 8000, mana = 170, voc = {4,14} },
  { words = "exevo gran mas tera", name = "Wrath of Nature", cooldown = 4000, mana = 700, voc = {4,14} },
  { words = "exevo gran mas frigo", name = "Eternal Winter", cooldown = 4000, mana = 1050, voc = {4,14} },
  { words = "exevo ulus tera", name = "Terra Burst", cooldown = 6000, mana = 230, voc = {4,14} },
  { words = "exevo ulus frigo", name = "Ice Burst", cooldown = 8000, mana = 230, voc = {4,14} },
  
  -- ===== SORCERER + DRUID (compartilhadas) =====
  { words = "exori vis", name = "Energy Strike", cooldown = 2000, mana = 20, voc = {3,4,13,14} },
  { words = "exori flam", name = "Flame Strike", cooldown = 2000, mana = 20, voc = {3,4,13,14} },
  { words = "exori frigo", name = "Ice Strike", cooldown = 2000, mana = 20, voc = {3,4,13,14} },
  { words = "exori tera", name = "Terra Strike", cooldown = 2000, mana = 20, voc = {3,4,13,14} },
  
  -- ===== MONK (clientid 5 base, 15 promoted/exalted) =====
  { words = "exori infir pug", name = "Swift Jab", cooldown = 2000, mana = 3, voc = {5,15} },
  { words = "exori pug", name = "Double Jab", cooldown = 4000, mana = 30, voc = {5,15} },
  { words = "exori infir nia", name = "Tiger Clash", cooldown = 8000, mana = 18, voc = {5,15} },
  { words = "exori nia", name = "Greater Tiger Clash", cooldown = 8000, mana = 50, voc = {5,15} },
  { words = "exori mas pug", name = "Flurry of Blows", cooldown = 2000, mana = 110, voc = {5,15} },
  { words = "exori gran mas pug", name = "Greater Flurry of Blows", cooldown = 3000, mana = 300, voc = {5,15} },
  { words = "exori amp pug", name = "Mystic Repulse", cooldown = 14000, mana = 150, voc = {5,15} },
  { words = "exori med pug", name = "Chained Penance", cooldown = 3000, mana = 180, voc = {5,15} },
  { words = "exori mas nia", name = "Sweeping Takedown", cooldown = 3000, mana = 195, voc = {5,15} },
  { words = "exori gran pug", name = "Forceful Uppercut", cooldown = 40000, mana = 325, voc = {5,15} },
  { words = "exori gran nia", name = "Devastating Knockout", cooldown = 12000, mana = 210, voc = {5,15} },
  { words = "exori gran mas nia", name = "Spiritual Outburst", cooldown = 3000, mana = 425, voc = {5,15} },
  
  -- ===== GERAL (todas vocacoes) =====
  { words = "exori infir vis", name = "Apprentice's Strike", cooldown = 2000, mana = 8, voc = {0,1,2,3,4,5,11,12,13,14,15} },
}

-- Variaveis de controle
BTCAttack.config = nil
BTCAttack.lastAttackTime = 0
BTCAttack.attackCooldown = 100  -- 100ms entre tentativas de uso de spell (rapido)
BTCAttack.spellPopup = nil
BTCAttack.lastSpellSlot = 0  -- Para rotacao de spells

-- UI references para cooldown visual
BTCAttack.spellSlotWidgets = {}

-- Inicializa o modulo
function BTCAttack.init()
  BTCAttack.config = BTCAttack.loadConfig()
  -- Migra configs antigas quando player estiver online (SpellInfo disponivel)
  BTCAttack.migrateOldConfigs()
end

-- Migra configs antigas que nao tem spellId
function BTCAttack.migrateOldConfigs()
  if not BTCAttack.config or not BTCAttack.config.spells then return end
  if not SpellInfo or not SpellInfo["Default"] then return end
  
  local migrated = false
  for i, spell in ipairs(BTCAttack.config.spells) do
    if spell.words and spell.words ~= "" and (not spell.spellId or spell.spellId == 0) then
      local spellData = BTCAttack.getSpellDataByWords(spell.words)
      if spellData then
        spell.spellId = spellData.spellId
        spell.iconId = spellData.iconId
        spell.groups = spellData.groups
        migrated = true
      end
    end
  end
  
  if migrated then
    BTCAttack.saveConfig()
  end
end

-- Carrega configuracao salva ou usa padrao
function BTCAttack.loadConfig()
  local saved = BTCConfig.get("attack")
  if saved then
    -- Garante que lastUsed esta zerado e harmony existe
    if saved.spells then
      for i, spell in ipairs(saved.spells) do
        spell.lastUsed = 0
        if spell.harmony == nil then
          spell.harmony = "any"
        end
      end
    end
    -- Garante que campo enabled existe (para configs antigas)
    if saved.enabled == nil then
      saved.enabled = true
    end
    return saved
  end
  return table.copy(BTCAttack.defaultConfig)
end

-- Salva configuracao
function BTCAttack.saveConfig()
  BTCConfig.set("attack", BTCAttack.config)
end

-- Retorna vocacao do player
function BTCAttack.getPlayerVocation()
  if not g_game.isOnline() then return 0 end
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  return player:getVocation() or 0
end

-- Retorna lista de spells de ataque do cliente filtrada pela vocacao atual
function BTCAttack.getAvailableSpells()
  local voc = BTCAttack.getPlayerVocation()
  local available = {}
  local profile = "Default"
  
  -- Usa dados do cliente
  if not SpellInfo or not SpellInfo[profile] then
    return available
  end
  
  -- Mapeia vocações do cliente para o formato do SpellInfo
  -- Cliente retorna: 1=Knight, 2=Paladin, 3=Sorcerer, 4=Druid, 5=Monk, 11=EK, 12=RP, 13=MS, 14=ED, 15=ExMonk
  -- SpellInfo usa: 1=Sorcerer, 2=Druid, 3=Paladin, 4=Knight, 5=MS, 6=ED, 7=RP, 8=EK, 9=Monk, 10=ExMonk
  local vocMap = {
    [1] = {4, 8},    -- Cliente Knight -> SpellInfo 4 Knight, 8 Elite Knight
    [2] = {3, 7},    -- Cliente Paladin -> SpellInfo 3 Paladin, 7 Royal Paladin
    [3] = {1, 5},    -- Cliente Sorcerer -> SpellInfo 1 Sorcerer, 5 Master Sorcerer
    [4] = {2, 6},    -- Cliente Druid -> SpellInfo 2 Druid, 6 Elder Druid
    [5] = {9, 10},   -- Cliente Monk -> SpellInfo 9 Monk, 10 Exalted Monk
    [11] = {4, 8},   -- Cliente Elite Knight
    [12] = {3, 7},   -- Cliente Royal Paladin
    [13] = {1, 5},   -- Cliente Master Sorcerer
    [14] = {2, 6},   -- Cliente Elder Druid
    [15] = {9, 10},  -- Cliente Exalted Monk
  }
  
  local myVocs = vocMap[voc] or {}
  
  -- Percorre todas as spells do cliente
  local count = 0
  for spellName, info in pairs(SpellInfo[profile]) do
    count = count + 1
    -- Verifica se é spell de ataque (group 1 = attack)
    local isAttack = false
    if info.group then
      for groupId, _ in pairs(info.group) do
        if groupId == 1 then
          isAttack = true
          break
        end
      end
    end
    
    -- Verifica vocação
    local hasVoc = (voc == 0)  -- Se voc 0, mostra todas
    if not hasVoc and info.vocations then
      for _, v in ipairs(info.vocations) do
        for _, mv in ipairs(myVocs) do
          if v == mv then
            hasVoc = true
            break
          end
        end
        if hasVoc then break end
      end
    end
    
    if isAttack and hasVoc then
      -- spellId = id do servidor (usado para verificar cooldown real)
      -- iconId = clientId para sprite sheet (obtido via SpellIcons ou clientId explicito)
      local spellId = info.id or 0
      local iconId = 0
      
      -- Primeiro tenta usar clientId explicito
      if info.clientId then
        iconId = info.clientId
      -- Senão, busca na tabela SpellIcons usando o nome do icone
      elseif info.icon and SpellIcons and SpellIcons[info.icon] then
        iconId = SpellIcons[info.icon][1]  -- [1] é o clientId
      -- Fallback: usa o id (pode não ser correto para todas as spells)
      else
        iconId = info.id or 0
      end
      
      -- Pega os grupos de cooldown da spell
      local groups = {}
      if info.group then
        for groupId, _ in pairs(info.group) do
          table.insert(groups, groupId)
        end
      end
      
      table.insert(available, {
        name = spellName,
        words = info.words,
        cooldown = info.exhaustion or 2000,
        mana = info.mana or 0,
        spellId = spellId,  -- ID do servidor para cooldown
        iconId = iconId,    -- ClientId para sprite sheet
        groups = groups,    -- Grupos de cooldown
        level = info.level or 0
      })
    end
  end
  
  -- Ordena por level
  table.sort(available, function(a, b) return a.level < b.level end)
  
  return available
end

-- Verifica se pode atacar (cooldown global entre acoes)
function BTCAttack.canAttack()
  local now = g_clock.millis()
  return (now - BTCAttack.lastAttackTime) >= BTCAttack.attackCooldown
end

-- Verifica se spell esta em cooldown (usa cooldown REAL do servidor via iconId)
function BTCAttack.isSpellReady(slotIndex)
  if not BTCAttack.config or not BTCAttack.config.spells then return false end
  local spell = BTCAttack.config.spells[slotIndex]
  if not spell or not spell.enabled then return false end
  if not spell.words or spell.words == "" then return false end
  
  -- Usa o sistema de cooldown do servidor se disponível
  if modules.game_cooldown then
    -- Verifica cooldown da spell pelo iconId (ID visual usado pelo servidor)
    local iconId = spell.iconId or spell.spellId or 0
    if iconId > 0 then
      if modules.game_cooldown.isCooldownIconActive(iconId) then
        return false -- Spell está em cooldown
      end
    end
    
    -- Verifica cooldown do grupo de ataque (groupId = 1)
    if modules.game_cooldown.isGroupCooldownIconActive(1) then
      return false -- Grupo de ataque está em cooldown
    end
    
    return true -- Spell pronta!
  end
  
  -- Fallback: usa sistema local de tempo
  local now = g_clock.millis()
  local elapsed = now - (spell.lastUsed or 0)
  return elapsed >= spell.cooldown
end

-- Retorna tempo restante do cooldown em ms
function BTCAttack.getSpellCooldownRemaining(slotIndex)
  if not BTCAttack.config or not BTCAttack.config.spells then return 0 end
  local spell = BTCAttack.config.spells[slotIndex]
  if not spell then return 0 end
  
  local now = g_clock.millis()
  local elapsed = now - (spell.lastUsed or 0)
  local remaining = spell.cooldown - elapsed
  
  return remaining > 0 and remaining or 0
end

-- Retorna porcentagem do cooldown (0-100)
function BTCAttack.getSpellCooldownPercent(slotIndex)
  if not BTCAttack.config or not BTCAttack.config.spells then return 0 end
  local spell = BTCAttack.config.spells[slotIndex]
  if not spell or spell.cooldown <= 0 then return 0 end
  
  local remaining = BTCAttack.getSpellCooldownRemaining(slotIndex)
  return (remaining / spell.cooldown) * 100
end

-- Usa uma spell ou runa
function BTCAttack.useSpell(slotIndex)
  if not g_game.isOnline() then return false end
  
  local spell = BTCAttack.config.spells[slotIndex]
  if not spell or not spell.enabled then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  -- Verifica se e runa
  if spell.type == "rune" and spell.itemId and spell.itemId > 0 then
    return BTCAttack.useRune(slotIndex)
  end
  
  -- E uma spell normal
  -- Verifica mana
  if player:getMana() < spell.manaCost then
    return false
  end
  
  -- Fala a spell
  g_game.talk(spell.words)
  spell.lastUsed = g_clock.millis()
  BTCAttack.lastAttackTime = g_clock.millis()
  
  return true
end

-- Usa uma runa de ataque no target atual
function BTCAttack.useRune(slotIndex)
  if not g_game.isOnline() then return false end
  
  local spell = BTCAttack.config.spells[slotIndex]
  if not spell or not spell.enabled then return false end
  if not spell.itemId or spell.itemId == 0 then return false end
  
  -- Pega target atual
  local target = g_game.getAttackingCreature()
  if not target or target:isDead() then return false end
  
  -- Procura a runa no inventario
  local hasRune = BTCAttack.findRuneInInventory(spell.itemId)
  if not hasRune then return false end
  
  -- Usa a runa no target
  g_game.useInventoryItemWith(spell.itemId, target, 0)
  spell.lastUsed = g_clock.millis()
  BTCAttack.lastAttackTime = g_clock.millis()
  
  return true
end

-- Procura uma runa no inventario (verifica se existe)
function BTCAttack.findRuneInInventory(itemId)
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  -- Verifica em todos os slots de inventario
  for i = InventorySlotFirst, InventorySlotPurse do
    local item = player:getInventoryItem(i)
    if item then
      if item:getId() == itemId then
        return true
      end
    end
  end
  
  -- Verifica em containers abertos
  local containers = g_game.getContainers()
  if containers then
    for _, container in pairs(containers) do
      if container then
        local itemCount = container:getItemsCount()
        for i = 0, itemCount - 1 do
          local item = container:getItem(i)
          if item and item:getId() == itemId then
            return true
          end
        end
      end
    end
  end
  
  return false
end

-- Encontra monstro mais proximo para atacar
function BTCAttack.findTarget()
  if not g_game.isOnline() then return nil end
  
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  
  local playerPos = player:getPosition()
  if not playerPos then return nil end
  
  -- Pega criaturas na tela
  local mapPanel = modules.game_interface.getMapPanel()
  if not mapPanel then return nil end
  
  local spectators = mapPanel:getSpectators()
  if not spectators then return nil end
  
  local bestTarget = nil
  local bestDistance = BTCAttack.config.attackRange + 1
  local bestPriority = 0
  
  for _, creature in ipairs(spectators) do
    if BTCAttack.isValidTarget(creature, playerPos) then
      local creaturePos = creature:getPosition()
      local distance = BTCAttack.getDistance(playerPos, creaturePos)
      local priority = BTCAttack.getCreaturePriority(creature)
      
      -- Prioridade > distancia
      if priority > bestPriority or (priority == bestPriority and distance < bestDistance) then
        bestTarget = creature
        bestDistance = distance
        bestPriority = priority
      end
    end
  end
  
  return bestTarget
end

-- Verifica se criatura e um alvo valido
function BTCAttack.isValidTarget(creature, playerPos)
  if not creature then return false end
  if creature:isLocalPlayer() then return false end
  if creature:isDead() then return false end
  if not creature:canBeSeen() then return false end
  
  local creaturePos = creature:getPosition()
  if not creaturePos then return false end
  if creaturePos.z ~= playerPos.z then return false end
  
  -- Verifica distancia
  local distance = BTCAttack.getDistance(playerPos, creaturePos)
  if distance > BTCAttack.config.attackRange then return false end
  
  -- Verifica tipo de criatura
  if creature:isMonster() then
    if not BTCAttack.config.attackMonsters then return false end
  elseif creature:isPlayer() then
    if not BTCAttack.config.attackPlayers then return false end
  elseif creature:isNpc() then
    return false -- Nunca ataca NPCs
  end
  
  -- Verifica lista de ignore
  local creatureName = creature:getName():lower()
  for _, ignoreName in ipairs(BTCAttack.config.ignoreList or {}) do
    if creatureName == ignoreName:lower() then
      return false
    end
  end
  
  -- Verifica se o monstro esta acessivel (nao atras de parede)
  if not BTCAttack.isReachable(playerPos, creaturePos) then
    return false
  end
  
  return true
end

-- Verifica se existe caminho ate a criatura (nao esta atras de parede)
function BTCAttack.isReachable(playerPos, targetPos)
  if not playerPos or not targetPos then return false end
  
  -- Mesmo andar obrigatorio
  if playerPos.z ~= targetPos.z then return false end
  
  -- Se o monstro esta visivel na tela, pode targetar
  -- O jogo cuida do resto (pathfinding, etc)
  return true
end

-- Verifica linha de visao entre duas posicoes (simplificado)
function BTCAttack.hasLineOfSight(pos1, pos2)
  if not pos1 or not pos2 then return false end
  if pos1.z ~= pos2.z then return false end
  return true
end

-- Retorna prioridade da criatura (maior = mais prioritario)
function BTCAttack.getCreaturePriority(creature)
  if not creature then return 0 end
  
  local creatureName = creature:getName():lower()
  
  -- Verifica lista de prioridade
  for i, priorityName in ipairs(BTCAttack.config.priorityList or {}) do
    if creatureName == priorityName:lower() then
      return 100 - i -- Maior prioridade para os primeiros da lista
    end
  end
  
  return 1 -- Prioridade padrao
end

-- Calcula distancia entre duas posicoes
function BTCAttack.getDistance(pos1, pos2)
  local dx = math.abs(pos1.x - pos2.x)
  local dy = math.abs(pos1.y - pos2.y)
  return math.max(dx, dy)
end

-- =============================================
-- TARGET MODES (9 modos inspirados no Helper)
-- =============================================

local function btcDist(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

local function btcInReach(playerPos, targetPos)
  if type(targetPos) ~= "table" then return false end
  return math.abs(playerPos.x - targetPos.x) <= 7
     and math.abs(playerPos.y - targetPos.y) <= 5
     and playerPos.z == targetPos.z
end

BTCAttack.SpellAreas = {
  AREA_CIRCLE3X3 = {
    {-1,-1},{0,-1},{1,-1},
    {-1, 0},{0, 0},{1, 0},
    {-1, 1},{0, 1},{1, 1},
  },
  AREA_CIRCLE2X2 = {
    {0,-1},
    {-1,0},{0,0},{1,0},
    {0, 1},
  },
}

function BTCAttack.countAttackableCreatures(pos, area, creatureList)
  local count = 0
  for _, offset in ipairs(area) do
    local checkX = pos.x + offset[1]
    local checkY = pos.y + offset[2]
    for _, cd in ipairs(creatureList) do
      if cd.position.x == checkX
      and cd.position.y == checkY
      and cd.position.z == pos.z then
        count = count + 1
      end
    end
  end
  return count
end

function BTCAttack.getAttackableCreaturesSmart(playerPos, creatureList)
  local closest         = { id=nil, distance=99    }
  local farthest        = { id=nil, distance=-1    }
  local lowestHP        = { id=nil, health=101     }
  local highestHP       = { id=nil, health=-1      }
  local closestLowest   = { id=nil, distance=99,  health=101 }
  local closestHighest  = { id=nil, distance=99,  health=-1  }
  local farthestLowest  = { id=nil, distance=-1,  health=101 }
  local farthestHighest = { id=nil, distance=-1,  health=-1  }
  local bestAoE         = { id=nil, creatures=0   }

  local voc = BTCAttack.getPlayerVocation()
  local area = BTCAttack.SpellAreas.AREA_CIRCLE3X3
  if voc == 2 or voc == 12 then
    area = BTCAttack.SpellAreas.AREA_CIRCLE2X2
  end

  for _, cd in ipairs(creatureList) do
    local creature = cd.creature
    local pos      = cd.position

    if not btcInReach(playerPos, pos)         then goto skip end
    if not g_map.isSightClear(playerPos, pos) then goto skip end

    local dist   = btcDist(playerPos, pos)
    local health = creature:getHealthPercent()
    local cid    = creature:getId()

    if lowestHP.id == nil then
      lowestHP = { id=cid, health=health }
    end
    if health < lowestHP.health  then lowestHP  = { id=cid, health=health } end
    if health > highestHP.health then highestHP = { id=cid, health=health } end

    if dist < closest.distance  then closest  = { id=cid, distance=dist } end
    if dist > farthest.distance then farthest = { id=cid, distance=dist } end

    if dist < closestLowest.distance
    or (dist == closestLowest.distance and health < closestLowest.health) then
      closestLowest = { id=cid, distance=dist, health=health }
    end

    if dist < closestHighest.distance
    or (dist == closestHighest.distance and health > closestHighest.health) then
      closestHighest = { id=cid, distance=dist, health=health }
    end

    if dist > farthestLowest.distance
    or (dist == farthestLowest.distance and health < farthestLowest.health) then
      farthestLowest = { id=cid, distance=dist, health=health }
    end

    if dist > farthestHighest.distance
    or (dist == farthestHighest.distance and health > farthestHighest.health) then
      farthestHighest = { id=cid, distance=dist, health=health }
    end

    local hits = BTCAttack.countAttackableCreatures(pos, area, creatureList)
    if hits > bestAoE.creatures then
      bestAoE = { id=cid, creatures=hits }
    end

    ::skip::
  end

  return {
    A = closest,
    B = farthest,
    C = lowestHP,
    D = highestHP,
    E = bestAoE,
    F = closestLowest,
    G = closestHighest,
    H = farthestLowest,
    I = farthestHighest,
  }
end

-- Funcao principal de execucao
function BTCAttack.execute()
  if not g_game.isOnline() then return end
  if not BTCAttack.config or not BTCAttack.config.enabled then return end

  local player = g_game.getLocalPlayer()
  if not player then return end

  -- PZ safety: nunca ataca em Protection Zone (PlayerStates.Pigeon = PZ icon)
  if PlayerStates and PlayerStates.Pigeon and player:hasState(PlayerStates.Pigeon) then return end

  -- Follow safety: nao ataca enquanto estiver seguindo uma criatura
  if g_game.getFollowingCreature() then return end

  -- CaveBot integration: so ataca quando tiver mobs suficientes
  if BTCCaveBot and BTCCaveBot.config and BTCCaveBot.config.enabled then
    if not BTCCaveBot.shouldStopForMonsters() then
      local currentTarget = g_game.getAttackingCreature()
      if currentTarget then
        g_game.cancelAttack()
      end
      return
    end
  end

  local playerPos = player:getPosition()
  if not playerPos then return end

  -- === LOCKED TARGET CHECK ===
  local lockedId = BTCAttack.config.lockedTargetId or 0
  if lockedId ~= 0 then
    local locked = g_map.getCreatureById(lockedId)
    if locked and not locked:isDead() and btcInReach(playerPos, locked:getPosition()) then
      local current = g_game.getAttackingCreature()
      if not current or current:getId() ~= locked:getId() then
        g_game.attack(locked)
      end
      goto spellEvaluation
    else
      BTCAttack.config.lockedTargetId = 0
    end
  end

  do
    -- === BUILD CREATURE LIST ===
    local creatureList = {}
    local mapPanel = modules.game_interface.getMapPanel()
    local spectators = mapPanel and mapPanel:getSpectators() or {}

    for _, c in ipairs(spectators) do
      if not c:isLocalPlayer() and not c:isDead() and c:canBeSeen() then
        local validType = false
        if c:isMonster() and BTCAttack.config.attackMonsters then validType = true end
        if c:isPlayer() and BTCAttack.config.attackPlayers then validType = true end

        if validType then
          local cPos = c:getPosition()
          if cPos and cPos.z == playerPos.z then
            local dist = BTCAttack.getDistance(playerPos, cPos)
            if dist <= BTCAttack.config.attackRange then
              local ignored = false
              local cName = c:getName():lower()
              for _, name in ipairs(BTCAttack.config.ignoreList or {}) do
                if cName == name:lower() then ignored = true; break end
              end
              if not ignored then
                table.insert(creatureList, { position=cPos, creature=c })
              end
            end
          end
        end
      end
    end

    -- === PRIORITY LIST (attack first regardless of mode) ===
    for _, priorityName in ipairs(BTCAttack.config.priorityList or {}) do
      local pLower = priorityName:lower()
      for _, cd in ipairs(creatureList) do
        if cd.creature:getName():lower() == pLower then
          if btcInReach(playerPos, cd.position) and g_map.isSightClear(playerPos, cd.position) then
            local current = g_game.getAttackingCreature()
            if not current or current:getId() ~= cd.creature:getId() then
              g_game.attack(cd.creature)
            end
            goto spellEvaluation
          end
        end
      end
    end

    -- === MODE-BASED SELECTION ===
    if #creatureList > 0 then
      local results = BTCAttack.getAttackableCreaturesSmart(playerPos, creatureList)
      local mode    = BTCAttack.config.targetMode or "F"
      local chosen  = results[mode]

      if chosen and chosen.id then
        local target  = g_map.getCreatureById(chosen.id)
        local current = g_game.getAttackingCreature()
        if target and (not current or current:getId() ~= target:getId()) then
          g_game.attack(target)
        end
      end
    else
      -- Sem criaturas validas — limpa target se tiver um morto/invalido
      local current = g_game.getAttackingCreature()
      if current and current:isDead() then
        g_game.cancelAttack()
      end
    end
  end

  ::spellEvaluation::
  local attackingCreature = g_game.getAttackingCreature()
  if attackingCreature and not attackingCreature:isDead() then
    BTCAttack.executeSpells()
  end
end

-- Chase automatico: anda ate o monstro atacado
function BTCAttack.chaseTarget(player, target)
  if not player or not target then return end
  if player:isWalking() then return end
  
  local now = g_clock.millis()
  if (now - BTCAttack.lastAttackTime) < 200 then return end
  
  local playerPos = player:getPosition()
  local targetPos = target:getPosition()
  if not playerPos or not targetPos then return end
  if playerPos.z ~= targetPos.z then return end
  
  local dx = math.abs(playerPos.x - targetPos.x)
  local dy = math.abs(playerPos.y - targetPos.y)
  local dist = math.max(dx, dy)
  
  -- Se ja esta adjacente (dist <= 1), nao precisa mover
  if dist <= 1 then return end
  
  -- Tenta pathfinding ate posicao adjacente ao monstro
  local path = g_map.findPath(playerPos, targetPos, 20, 0)
  if path and #path > 0 then
    -- Remove ultimo passo para ficar adjacente (nao em cima)
    if #path > 1 then
      table.remove(path, #path)
    end
    g_game.autoWalk(path, playerPos)
    BTCAttack.lastAttackTime = now
  else
    -- Pathfinding falhou, tenta andar direto na direcao do monstro
    local moveX = 0
    local moveY = 0
    if targetPos.x > playerPos.x then moveX = 1
    elseif targetPos.x < playerPos.x then moveX = -1 end
    if targetPos.y > playerPos.y then moveY = 1
    elseif targetPos.y < playerPos.y then moveY = -1 end
    
    local dir = nil
    if moveX == 0 and moveY == -1 then dir = North
    elseif moveX == 1 and moveY == -1 then dir = NorthEast
    elseif moveX == 1 and moveY == 0 then dir = East
    elseif moveX == 1 and moveY == 1 then dir = SouthEast
    elseif moveX == 0 and moveY == 1 then dir = South
    elseif moveX == -1 and moveY == 1 then dir = SouthWest
    elseif moveX == -1 and moveY == 0 then dir = West
    elseif moveX == -1 and moveY == -1 then dir = NorthWest
    end
    
    if dir then
      g_game.walk(dir, false)
      BTCAttack.lastAttackTime = now
    end
  end
end

-- Executa spells de ataque (Sistema de Rotacao)
function BTCAttack.executeSpells()
  -- Cooldown global minimo entre acoes (100ms para nao spammar)
  if not BTCAttack.canAttack() then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  -- Conta quantos slots estao habilitados e guarda na ordem
  local enabledSlots = {}
  for i = 1, 6 do
    local spell = BTCAttack.config.spells[i]
    if spell and spell.enabled and spell.words and spell.words ~= "" then
      table.insert(enabledSlots, i)
    end
  end
  
  if #enabledSlots == 0 then return end
  
  -- Sistema de Rotacao Circular:
  -- Procura a proxima spell disponivel a partir do ultimo slot usado
  
  -- Encontra o indice do ultimo slot usado na lista de slots habilitados
  local lastUsedIndex = 0
  for idx, slotNum in ipairs(enabledSlots) do
    if slotNum == BTCAttack.lastSpellSlot then
      lastUsedIndex = idx
      break
    end
  end
  
  -- Tenta cada slot em ordem circular, comecando do proximo apos o ultimo usado
  for attempt = 1, #enabledSlots do
    -- Calcula o indice circular (1-based)
    local idx = ((lastUsedIndex + attempt - 1) % #enabledSlots) + 1
    local slotIndex = enabledSlots[idx]
    local spell = BTCAttack.config.spells[slotIndex]
    
    -- Verifica harmony minima (somente se configurado diferente de "any")
    if spell.harmony and spell.harmony ~= "any" then
      local requiredHarmony = tonumber(spell.harmony)
      if requiredHarmony and player:getHarmony() < requiredHarmony then
        -- Harmony insuficiente, pula este slot
        goto continue
      end
    end

    -- Verifica se a spell esta pronta (cooldown do servidor)
    if BTCAttack.isSpellReady(slotIndex) then
      -- Verifica mana
      if player:getMana() >= (spell.manaCost or 0) then
        -- Tenta usar a spell
        if BTCAttack.useSpell(slotIndex) then
          BTCAttack.lastSpellSlot = slotIndex
          return -- Usou uma spell, para aqui
        end
      end
    end

    ::continue::
  end
  
  -- Nenhuma spell disponivel no momento (todas em cooldown ou sem mana)
end

-- Fecha popup se existir
function BTCAttack.closePopup()
  if BTCAttack.spellPopup then
    BTCAttack.spellPopup:destroy()
    BTCAttack.spellPopup = nil
  end
end

-- Obtem clip da spell pelo words (busca direto do SpellInfo)
function BTCAttack.getSpellClipByWords(words)
  if not words or words == "" then return nil end
  
  local profile = "Default"
  if not SpellInfo or not SpellInfo[profile] then return nil end
  
  -- Busca a spell pelo words
  for spellName, data in pairs(SpellInfo[profile]) do
    if data.words and data.words:lower() == words:lower() then
      -- Encontrou! O id JÁ é o iconId no SpellInfo
      if data.id and Spells and Spells.getImageClip then
        return Spells.getImageClip(data.id, profile)
      end
      break
    end
  end
  
  return nil
end

-- Mostra modal de selecao de spell com scroll
function BTCAttack.showSpellPopup(anchorWidget, slotIndex, onSelect)
  BTCAttack.closePopup()
  
  local spells = BTCAttack.getAvailableSpells()
  if #spells == 0 then 
    return 
  end
  
  -- Pega configuracoes de icones
  local profile = "Default"
  local iconFile = "/images/game/spells/defaultspells"
  if SpelllistSettings and SpelllistSettings[profile] then
    iconFile = SpelllistSettings[profile].iconFile or iconFile
  end
  
  -- Cria janela
  local modal = g_ui.createWidget('MainWindow', rootWidget)
  modal:setId('attackSpellModal')
  modal:setText('Attack Spells (' .. #spells .. ')')
  modal:setSize({width = 280, height = 400})
  modal:centerIn('parent')
  BTCAttack.spellPopup = modal
  
  -- Cria VerticalScrollBar
  local scrollBar = g_ui.createWidget('VerticalScrollBar', modal)
  scrollBar:setId('spellScrollBar')
  scrollBar:addAnchor(AnchorTop, 'parent', AnchorTop)
  scrollBar:addAnchor(AnchorRight, 'parent', AnchorRight)
  scrollBar:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  scrollBar:setMarginBottom(35)
  scrollBar:setStep(28)
  
  -- Cria TextList
  local list = g_ui.createWidget('TextList', modal)
  list:setId('spellList')
  list:addAnchor(AnchorTop, 'parent', AnchorTop)
  list:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  list:addAnchor(AnchorRight, 'spellScrollBar', AnchorLeft)
  list:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  list:setMarginBottom(35)
  list:setMarginRight(1)
  list:setBackgroundColor('#222222')
  list:setVerticalScrollBar(scrollBar)
  
  -- Adiciona cada spell como item estilo menu
  for i, spell in ipairs(spells) do
    -- Container do item (igual BotMenuButton)
    local item = g_ui.createWidget('Panel', list)
    item:setId('spell_' .. i)
    item:setHeight(26)
    item:setMarginBottom(2)
    item:setBackgroundColor('#363636')
    item:setBorderWidth(1)
    item:setBorderColor('#2a2a2a')
    
    -- Icone da spell (usando 20x20)
    local icon = g_ui.createWidget('UIWidget', item)
    icon:setId('icon')
    icon:setSize({width = 20, height = 20})
    icon:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    icon:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    icon:setMarginLeft(6)
    icon:setImageSource(iconFile)
    icon:setPhantom(true)
    
    -- Busca o clip correto da spell usando o iconId diretamente
    if spell.iconId and spell.iconId > 0 and Spells and Spells.getImageClip then
      local clip = Spells.getImageClip(spell.iconId, profile)
      if clip then
        icon:setImageClip(clip)
        icon:setImageSize({width = 20, height = 20})
      end
    end
    
    -- Nome da spell
    local nameLabel = g_ui.createWidget('Label', item)
    nameLabel:setText(spell.words)
    nameLabel:setColor('#c0c0c0')
    nameLabel:setFont('verdana-11px-rounded')
    nameLabel:addAnchor(AnchorLeft, 'icon', AnchorRight)
    nameLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
    nameLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    nameLabel:setMarginLeft(8)
    nameLabel:setPhantom(true)
    
    -- Tooltip
    item:setTooltip(spell.name .. '\nCooldown: ' .. spell.cooldown/1000 .. 's\nMana: ' .. spell.mana)
    
    -- Guarda referencia
    item.spell = spell
    
    -- Hover effect
    item.onHoverChange = function(widget, hovered)
      if hovered then
        widget:setBackgroundColor('#4a4a6a')
        widget:setBorderColor('#6a6a8a')
        nameLabel:setColor('#ffffff')
      else
        widget:setBackgroundColor('#363636')
        widget:setBorderColor('#2a2a2a')
        nameLabel:setColor('#c0c0c0')
      end
    end
    
    -- Click
    item.onMouseRelease = function(widget, mousePos, button)
      if button == MouseLeftButton then
        if onSelect then
          onSelect(widget.spell)
        end
        BTCAttack.closePopup()
        return true
      end
      return false
    end
  end
  
  -- Botao Cancelar
  local cancelBtn = g_ui.createWidget('Button', modal)
  cancelBtn:setText('Cancel')
  cancelBtn:setSize({width = 80, height = 25})
  cancelBtn:addAnchor(AnchorBottom, 'parent', AnchorBottom)
  cancelBtn:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
  cancelBtn:setMarginBottom(5)
  cancelBtn.onClick = function()
    BTCAttack.closePopup()
  end
end

-- Popup de selecao de runa
BTCAttack.runePopup = nil

-- Fecha popup de runa se existir
function BTCAttack.closeRunePopup()
  if BTCAttack.runePopup then
    BTCAttack.runePopup:destroy()
    BTCAttack.runePopup = nil
  end
end

-- Mostra popup de selecao de runa com icones (igual ao healing potions)
function BTCAttack.showRunePopup(itemContainer, slotIndex, config, onSelect)
  BTCAttack.closeRunePopup()
  
  local runeCount = #BTCAttack.attackRunes
  local itemSize = 42
  local spacing = 5
  local padding = 8
  local popupWidth = (itemSize * runeCount) + (spacing * (runeCount - 1)) + (padding * 2)
  local popupHeight = itemSize + (padding * 2)
  
  -- Cria popup panel
  local popup = g_ui.createWidget("Panel", rootWidget)
  popup:setId("attackRunePopup")
  BTCAttack.runePopup = popup
  
  -- Estilo do popup
  popup:setBackgroundColor("#2a2a2a")
  popup:setWidth(popupWidth)
  popup:setHeight(popupHeight)
  
  -- Layout horizontal para os icones (igual healing)
  popup:setLayout(UIHorizontalLayout.create(popup))
  popup:getLayout():setSpacing(spacing)
  popup:setPaddingLeft(padding)
  popup:setPaddingRight(padding)
  popup:setPaddingTop(padding)
  popup:setPaddingBottom(padding)
  
  -- Adiciona cada runa
  for idx, rune in ipairs(BTCAttack.attackRunes) do
    -- Container individual para cada runa (quadrado)
    local runeBox = g_ui.createWidget("Button", popup)
    runeBox:setSize({width = itemSize, height = itemSize})
    runeBox:setText("")
    
    -- Visual diferente se selecionado
    if config.itemId == rune.itemId then
      runeBox:setBackgroundColor("#442200")
      runeBox:setBorderWidth(2)
      runeBox:setBorderColor("#FF8800")
    end
    
    -- Icone do item centralizado
    local itemWidget = g_ui.createWidget("UIItem", runeBox)
    itemWidget:setSize({width = 32, height = 32})
    itemWidget:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    itemWidget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemWidget:setVirtual(true)
    itemWidget:setPhantom(true)
    itemWidget:setItemId(rune.itemId)
    
    -- Tooltip no container
    runeBox:setTooltip(rune.name)
    
    -- Clique no quadrado seleciona a runa
    runeBox.onClick = function()
      config.itemId = rune.itemId
      config.type = "rune"
      config.words = rune.shortName
      if onSelect then
        onSelect(rune)
      end
      BTCAttack.closeRunePopup()
    end
  end
  
  -- Posiciona o popup perto do itemContainer
  local pos = itemContainer:getPosition()
  popup:setPosition({x = pos.x - 20, y = pos.y + 44})
  
  -- Fecha ao clicar fora
  popup:raise()
  popup:focus()
  
  -- Timer para fechar se clicar fora
  popup.onFocusChange = function(widget, focused)
    if not focused then
      scheduleEvent(function()
        BTCAttack.closeRunePopup()
      end, 100)
    end
  end
end

-- UI reference para o container principal
BTCAttack.mainContainer = nil

-- Cria a UI do modulo
function BTCAttack.createUI(container)
  if not container then return end
  
  -- Guarda referencia ao container principal
  BTCAttack.mainContainer = container
  
  container:destroyChildren()
  BTCAttack.spellSlotWidgets = {}
  
  -- =============================================
  -- SECAO: TARGETING & MOVEMENT (integrado aqui)
  -- =============================================
  BTCAttack.createTargetingUI(container)
  
  local profile = "Default"
  local iconFile = "/images/game/spells/defaultspells"
  if SpelllistSettings and SpelllistSettings[profile] then
    iconFile = SpelllistSettings[profile].iconFile or iconFile
  end
  
  -- Titulo
  local title = g_ui.createWidget("Label", container)
  title:setText("Auto Attack & Spells")
  title:setTextAlign(AlignCenter)
  title:setFont("verdana-11px-rounded")
  title:setColor("#FF6B6B")
  title:setHeight(20)
  title:setMarginBottom(8)

  -- === SECAO: TARGET MODE ===
  local modeRow = g_ui.createWidget("Panel", container)
  modeRow:setHeight(26)
  modeRow:setMarginBottom(5)

  local modeLabel = g_ui.createWidget("Label", modeRow)
  modeLabel:setText("Target Mode:")
  modeLabel:setColor("#aaaaaa")
  modeLabel:setWidth(80)
  modeLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  modeLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local modeCombo = g_ui.createWidget("ComboBox", modeRow)
  modeCombo:setWidth(180)
  modeCombo:addAnchor(AnchorLeft, 'prev', AnchorRight)
  modeCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  modeCombo:setMarginLeft(5)

  local modeOptions = {
    { value="A", label="A - Closest" },
    { value="B", label="B - Farthest" },
    { value="C", label="C - Lowest HP" },
    { value="D", label="D - Highest HP" },
    { value="E", label="E - Best AoE" },
    { value="F", label="F - Closest + Low HP" },
    { value="G", label="G - Closest + High HP" },
    { value="H", label="H - Farthest + Low HP" },
    { value="I", label="I - Farthest + High HP" },
  }

  for _, opt in ipairs(modeOptions) do
    modeCombo:addOption(opt.label, opt.value)
  end

  local currentMode = BTCAttack.config.targetMode or "F"
  for i, opt in ipairs(modeOptions) do
    if opt.value == currentMode then
      modeCombo:setCurrentIndex(i)
      break
    end
  end

  modeCombo.onOptionChange = function(widget, text, data)
    BTCAttack.config.targetMode = data
    BTCAttack.saveConfig()
  end

  -- === SECAO: TARGETS ===
  local attackSection = g_ui.createWidget("Panel", container)
  attackSection:setHeight(30)
  attackSection:setMarginBottom(5)
  
  -- Checkboxes: Monsters / Players (mesma linha)
  local targetsRow = g_ui.createWidget("Panel", attackSection)
  targetsRow:setHeight(26)
  targetsRow:addAnchor(AnchorTop, 'parent', AnchorTop)
  targetsRow:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  targetsRow:addAnchor(AnchorRight, 'parent', AnchorRight)
  
  local monstersBtn = g_ui.createWidget("Button", targetsRow)
  monstersBtn:setText(BTCAttack.config.attackMonsters and "[X]" or "[ ]")
  monstersBtn:setWidth(28)
  monstersBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  monstersBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local monstersLabel = g_ui.createWidget("Label", targetsRow)
  monstersLabel:setText("Monsters")
  monstersLabel:setColor("#cccccc")
  monstersLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  monstersLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  monstersLabel:setMarginLeft(3)
  
  monstersBtn.onClick = function()
    BTCAttack.config.attackMonsters = not BTCAttack.config.attackMonsters
    monstersBtn:setText(BTCAttack.config.attackMonsters and "[X]" or "[ ]")
    BTCAttack.saveConfig()
  end
  
  local playersBtn = g_ui.createWidget("Button", targetsRow)
  playersBtn:setText(BTCAttack.config.attackPlayers and "[X]" or "[ ]")
  playersBtn:setWidth(28)
  playersBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  playersBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  playersBtn:setMarginLeft(15)
  
  local playersLabel = g_ui.createWidget("Label", targetsRow)
  playersLabel:setText("Players")
  playersLabel:setColor("#cccccc")
  playersLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  playersLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  playersLabel:setMarginLeft(3)
  
  playersBtn.onClick = function()
    BTCAttack.config.attackPlayers = not BTCAttack.config.attackPlayers
    playersBtn:setText(BTCAttack.config.attackPlayers and "[X]" or "[ ]")
    BTCAttack.saveConfig()
  end

  -- === SECAO: IGNORE LIST ===
  local ignoreSep = g_ui.createWidget("HorizontalSeparator", container)
  ignoreSep:setMarginTop(3)
  ignoreSep:setMarginBottom(5)

  local ignoreTitle = g_ui.createWidget("Label", container)
  ignoreTitle:setText("Ignore List")
  ignoreTitle:setColor("#ff4444")
  ignoreTitle:setMarginBottom(3)

  -- Linha de input + botao Add
  local ignoreInputRow = g_ui.createWidget("Panel", container)
  ignoreInputRow:setHeight(26)
  ignoreInputRow:setMarginBottom(3)

  local ignoreInput = g_ui.createWidget("TextEdit", ignoreInputRow)
  ignoreInput:setId("ignoreInput")
  ignoreInput:setWidth(170)
  ignoreInput:setHeight(22)
  ignoreInput:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  ignoreInput:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  ignoreInput:setTooltip("Nome do monstro para ignorar")

  local addIgnoreBtn = g_ui.createWidget("Button", ignoreInputRow)
  addIgnoreBtn:setText("Add")
  addIgnoreBtn:setWidth(40)
  addIgnoreBtn:setHeight(22)
  addIgnoreBtn:setColor("#00ff00")
  addIgnoreBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  addIgnoreBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  addIgnoreBtn:setMarginLeft(5)

  local removeIgnoreBtn = g_ui.createWidget("Button", ignoreInputRow)
  removeIgnoreBtn:setText("Del")
  removeIgnoreBtn:setWidth(40)
  removeIgnoreBtn:setHeight(22)
  removeIgnoreBtn:setColor("#ff4444")
  removeIgnoreBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  removeIgnoreBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  removeIgnoreBtn:setMarginLeft(3)

  -- Lista visual dos ignorados
  local ignoreListPanel = g_ui.createWidget("Panel", container)
  ignoreListPanel:setHeight(60)
  ignoreListPanel:setMarginBottom(5)
  ignoreListPanel:setBackgroundColor("#1a1a1a")

  local ignoreListLayout = UIVerticalLayout.create(ignoreListPanel)
  ignoreListLayout:setSpacing(1)
  ignoreListPanel:setLayout(ignoreListLayout)
  ignoreListPanel:setPaddingTop(2)
  ignoreListPanel:setPaddingLeft(4)
  ignoreListPanel:setPaddingRight(4)

  BTCAttack.ignoreListPanel = ignoreListPanel
  BTCAttack.ignoreSelectedName = nil

  local function refreshIgnoreList()
    ignoreListPanel:destroyChildren()
    BTCAttack.ignoreSelectedName = nil
    local list = BTCAttack.config.ignoreList or {}
    if #list == 0 then
      local emptyLabel = g_ui.createWidget("Label", ignoreListPanel)
      emptyLabel:setText("(vazio)")
      emptyLabel:setColor("#666666")
      emptyLabel:setHeight(16)
    else
      for _, name in ipairs(list) do
        local itemBtn = g_ui.createWidget("Button", ignoreListPanel)
        itemBtn:setText(name)
        itemBtn:setHeight(18)
        itemBtn:setTextAlign(AlignLeft)
        itemBtn:setColor("#ff8888")
        itemBtn:setBackgroundColor("#2a2a2a")
        itemBtn.onClick = function()
          BTCAttack.ignoreSelectedName = name
          for _, child in ipairs(ignoreListPanel:getChildren()) do
            child:setBackgroundColor("#2a2a2a")
          end
          itemBtn:setBackgroundColor("#443333")
        end
      end
    end
  end

  refreshIgnoreList()

  addIgnoreBtn.onClick = function()
    local name = ignoreInput:getText()
    if not name or name == "" then return end
    if not BTCAttack.config.ignoreList then BTCAttack.config.ignoreList = {} end
    for _, existing in ipairs(BTCAttack.config.ignoreList) do
      if existing:lower() == name:lower() then return end
    end
    table.insert(BTCAttack.config.ignoreList, name)
    BTCAttack.saveConfig()
    ignoreInput:setText("")
    refreshIgnoreList()
  end

  removeIgnoreBtn.onClick = function()
    local nameToRemove = BTCAttack.ignoreSelectedName
    if not nameToRemove then
      nameToRemove = ignoreInput:getText()
    end
    if not nameToRemove or nameToRemove == "" then return end
    if not BTCAttack.config.ignoreList then return end
    for i, existing in ipairs(BTCAttack.config.ignoreList) do
      if existing:lower() == nameToRemove:lower() then
        table.remove(BTCAttack.config.ignoreList, i)
        BTCAttack.saveConfig()
        ignoreInput:setText("")
        refreshIgnoreList()
        return
      end
    end
  end

  -- Separador
  local sep1 = g_ui.createWidget("HorizontalSeparator", container)
  sep1:setMarginTop(3)
  sep1:setMarginBottom(5)

  -- === SECAO: ATTACK - 6 slots (Rune ou Spell) ===
  local spellsTitle = g_ui.createWidget("Label", container)
  spellsTitle:setText("Attack Slots (6) - Rune or Spell")
  spellsTitle:setColor("#aaaaaa")
  spellsTitle:setMarginBottom(5)
  
  -- Cria 6 slots usando a mesma logica do Healing (com escolha de tipo)
  for i = 1, 6 do
    BTCAttack.createAttackSlotUI(container, i, iconFile)
  end
  
  -- Info de vocacao
  local vocInfo = g_ui.createWidget("Label", container)
  vocInfo:setMarginTop(5)
  local voc = BTCAttack.getPlayerVocation()
  -- Usando clientid: Knight=1, Paladin=2, Sorcerer=3, Druid=4, Monk=5, EK=11, RP=12, MS=13, ED=14, ExMonk=15
  local vocNames = {[0]="None", [1]="Knight", [2]="Paladin", [3]="Sorcerer", [4]="Druid", [5]="Monk", [11]="Elite Knight", [12]="Royal Paladin", [13]="Master Sorcerer", [14]="Elder Druid", [15]="Exalted Monk"}
  vocInfo:setText("Voc: " .. (vocNames[voc] or ("ID:" .. voc)) .. " (" .. #BTCAttack.getAvailableSpells() .. " spells)")
  vocInfo:setColor("#666666")
  vocInfo:setFont("verdana-11px-rounded")
end

-- Cria UI de um slot de ataque (Runa OU Spell - igual ao Healing)
function BTCAttack.createAttackSlotUI(parent, slotIndex, iconFile)
  local spell = BTCAttack.config.spells[slotIndex] or {
    enabled = false, type = "spell", words = "", cooldown = 2000, manaCost = 0, itemId = 0, lastUsed = 0
  }
  -- Garante que tem o campo type
  if not spell.type then spell.type = "spell" end
  
  local profile = "Default"
  
  -- Linha 1: Botao ON/OFF + Tipo (Spell/Rune)
  local row1 = g_ui.createWidget('Panel', parent)
  row1:setHeight(22)
  row1:setMarginTop(3)
  
  local toggleBtn = g_ui.createWidget('Button', row1)
  toggleBtn:setWidth(35)
  toggleBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  toggleBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  -- Funcao para atualizar visual do botao
  local function updateToggleBtn()
    if spell.enabled then
      toggleBtn:setText('ON')
      toggleBtn:setColor('#00ff00')
    else
      toggleBtn:setText('OFF')
      toggleBtn:setColor('#ff4444')
    end
  end
  updateToggleBtn()
  
  toggleBtn.onClick = function()
    -- Só pode ligar se tem algo configurado
    if spell.type == "spell" and (spell.words == "" or not spell.words) then return end
    if spell.type == "rune" and (spell.itemId == 0 or not spell.itemId) then return end
    
    spell.enabled = not spell.enabled
    updateToggleBtn()
    BTCAttack.config.spells[slotIndex] = spell
    BTCAttack.saveConfig()
  end
  
  local typeCombo = g_ui.createWidget('ComboBox', row1)
  typeCombo:setWidth(70)
  typeCombo:addAnchor(AnchorRight, 'parent', AnchorRight)
  typeCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  typeCombo:addOption('Spell')
  typeCombo:addOption('Rune')
  typeCombo:setCurrentOption(spell.type == "rune" and "Rune" or "Spell")
  
  typeCombo.onOptionChange = function(widget, option)
    spell.type = option == "Rune" and "rune" or "spell"
    spell.enabled = false
    spell.words = ""
    spell.itemId = 0
    spell.cooldown = 2000
    spell.manaCost = 0
    spell.spellId = 0
    spell.iconId = 0
    spell.groups = nil
    spell.lastUsed = 0
    BTCAttack.config.spells[slotIndex] = spell
    BTCAttack.saveConfig()
    -- Usa a referencia guardada ao container principal
    if BTCAttack.mainContainer then
      BTCAttack.createUI(BTCAttack.mainContainer)
    end
  end
  
  -- Linha 2: Spell (ComboBox com popup) ou Rune (Icone clicavel)
  local row2 = g_ui.createWidget('Panel', parent)
  row2:setHeight(36)
  row2:setMarginTop(3)
  
  if spell.type == "spell" then
    -- SPELL: usa icone clicavel + nome
    local spellLabel = g_ui.createWidget('Label', row2)
    spellLabel:setText('Spell:')
    spellLabel:setColor('#aaaaaa')
    spellLabel:setWidth(45)
    spellLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    spellLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    
    -- Container do icone - BUTTON CLICAVEL
    local itemContainer = g_ui.createWidget("Button", row2)
    itemContainer:setId("attackSpellContainer_" .. slotIndex)
    itemContainer:setWidth(36)
    itemContainer:setHeight(34)
    itemContainer:setText("")
    itemContainer:addAnchor(AnchorLeft, 'prev', AnchorRight)
    itemContainer:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemContainer:setMarginLeft(5)
    
    -- Icone da spell (32x32)
    local iconWidget = g_ui.createWidget("UIWidget", itemContainer)
    iconWidget:setId("attackSpellIcon_" .. slotIndex)
    iconWidget:setSize({width = 32, height = 32})
    iconWidget:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    iconWidget:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    iconWidget:setPhantom(true)
    
    -- Se tem spell configurada, mostra o icone
    if spell.words and spell.words ~= "" then
      iconWidget:setImageSource(iconFile)
      -- Busca iconId pelo words
      if SpellInfo and SpellInfo[profile] then
        for spellName, data in pairs(SpellInfo[profile]) do
          if data.words and data.words:lower() == spell.words:lower() then
            -- Obtem o iconId corretamente via SpellIcons ou clientId explicito
            local iconId = 0
            if data.clientId then
              iconId = data.clientId
            elseif data.icon and SpellIcons and SpellIcons[data.icon] then
              iconId = SpellIcons[data.icon][1]  -- [1] é o clientId
            else
              iconId = data.id or 0
            end
            
            if iconId and Spells and Spells.getImageClip then
              local clip = Spells.getImageClip(iconId, profile)
              if clip then
                iconWidget:setImageClip(clip)
              end
            end
            break
          end
        end
      end
    end
    
    -- Busca nome da spell
    local spellDisplayName = (spell.words and spell.words ~= "") and spell.words or "[Click to select]"
    
    -- Label com nome/words da spell
    local nameLabel = g_ui.createWidget('Label', row2)
    nameLabel:setId("attackSpellName_" .. slotIndex)
    nameLabel:setText(spellDisplayName)
    nameLabel:setColor((spell.words and spell.words ~= "") and '#ff6600' or '#666666')
    nameLabel:setWidth(130)
    nameLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
    nameLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    nameLabel:setMarginLeft(8)
    
    -- Tooltip
    if spell.words and spell.words ~= "" then
      itemContainer:setTooltip(spell.words .. "\nCD: " .. spell.cooldown/1000 .. "s | MP: " .. spell.manaCost)
    else
      itemContainer:setTooltip("Click to select spell")
    end
    
    -- Clique no container abre popup de spells
    itemContainer.onClick = function()
      BTCAttack.showSpellPopup(itemContainer, slotIndex, function(selectedSpell)
        spell.words = selectedSpell.words
        spell.cooldown = selectedSpell.cooldown
        spell.manaCost = selectedSpell.mana
        spell.spellId = selectedSpell.spellId
        spell.iconId = selectedSpell.iconId
        spell.groups = selectedSpell.groups
        spell.lastUsed = 0
        spell.enabled = true
        BTCAttack.config.spells[slotIndex] = spell
        
        -- Atualiza visual
        updateToggleBtn()
        
        -- Atualiza icone
        iconWidget:setImageSource(iconFile)
        if selectedSpell.iconId and selectedSpell.iconId > 0 and Spells and Spells.getImageClip then
          local clip = Spells.getImageClip(selectedSpell.iconId, profile)
          if clip then
            iconWidget:setImageClip(clip)
          end
        end
        
        -- Atualiza nome
        nameLabel:setText(selectedSpell.words)
        nameLabel:setColor('#ff6600')
        
        itemContainer:setTooltip(selectedSpell.words .. "\nCD: " .. selectedSpell.cooldown/1000 .. "s | MP: " .. selectedSpell.mana)
        BTCAttack.saveConfig()
      end)
    end
    
    -- Armazena referencias
    BTCAttack.spellSlotWidgets[slotIndex] = {
      row = row2,
      enabledBtn = toggleBtn,
      icon = iconWidget,
      nameLabel = nameLabel
    }
    
  else
    -- RUNE: usa icone clicavel (igual as potions no healing)
    local runeLabel = g_ui.createWidget('Label', row2)
    runeLabel:setText('Rune:')
    runeLabel:setColor('#aaaaaa')
    runeLabel:setWidth(45)
    runeLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    runeLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    
    -- Container do icone - BUTTON CLICAVEL
    local itemContainer = g_ui.createWidget("Button", row2)
    itemContainer:setId("attackRuneContainer_" .. slotIndex)
    itemContainer:setWidth(36)
    itemContainer:setHeight(34)
    itemContainer:setText("")
    itemContainer:addAnchor(AnchorLeft, 'prev', AnchorRight)
    itemContainer:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemContainer:setMarginLeft(5)
    
    -- Icone do item (UIItem) - centralizado com anchors
    local itemBox = g_ui.createWidget("UIItem", itemContainer)
    itemBox:setId("attackRuneIcon_" .. slotIndex)
    itemBox:setSize({width = 32, height = 32})
    itemBox:addAnchor(AnchorHorizontalCenter, 'parent', AnchorHorizontalCenter)
    itemBox:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    itemBox:setVirtual(true)
    itemBox:setPhantom(true)
    
    -- Se tem runa configurada, mostra o icone
    if spell.itemId and spell.itemId > 0 then
      itemBox:setItemId(spell.itemId)
    end
    
    -- Busca nome da runa
    local runeName = "[Click to select]"
    local runeShortName = ""
    for _, r in ipairs(BTCAttack.attackRunes) do
      if r.itemId == spell.itemId then
        runeName = r.name
        runeShortName = r.shortName
        break
      end
    end
    
    -- Label com nome da runa
    local nameLabel = g_ui.createWidget('Label', row2)
    nameLabel:setId("attackRuneName_" .. slotIndex)
    nameLabel:setText((spell.itemId and spell.itemId > 0) and runeName or "[Click to select]")
    nameLabel:setColor((spell.itemId and spell.itemId > 0) and '#ff8800' or '#666666')
    nameLabel:setWidth(130)
    nameLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
    nameLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
    nameLabel:setMarginLeft(8)
    
    -- Tooltip
    if spell.itemId and spell.itemId > 0 then
      itemContainer:setTooltip(runeName)
    else
      itemContainer:setTooltip("Click to select rune")
    end
    
    -- Clique no botao abre popup
    itemContainer.onClick = function()
      BTCAttack.showRunePopup(itemContainer, slotIndex, spell, function(selectedRune)
        spell.itemId = selectedRune.itemId
        spell.words = selectedRune.shortName
        spell.type = "rune"
        spell.cooldown = 2000  -- Cooldown padrao para runas
        spell.manaCost = 0     -- Runas nao gastam mana
        spell.enabled = true
        BTCAttack.config.spells[slotIndex] = spell
        
        -- Atualiza visual
        updateToggleBtn()
        itemBox:setItemId(selectedRune.itemId)
        itemContainer:setTooltip(selectedRune.name)
        nameLabel:setText(selectedRune.name)
        nameLabel:setColor('#ff8800')
        
        BTCAttack.saveConfig()
      end)
    end
    
    -- Armazena referencias
    BTCAttack.spellSlotWidgets[slotIndex] = {
      row = row2,
      enabledBtn = toggleBtn,
      icon = itemBox,
      nameLabel = nameLabel
    }
  end
  
  -- Linha 3: Harmony (minimo de harmony para usar a spell)
  local row3 = g_ui.createWidget('Panel', parent)
  row3:setHeight(22)
  row3:setMarginTop(3)

  local harmonyLabel = g_ui.createWidget('Label', row3)
  harmonyLabel:setText('Harmony:')
  harmonyLabel:setColor('#aaaaaa')
  harmonyLabel:setWidth(60)
  harmonyLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  harmonyLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  harmonyLabel:setTooltip("Harmony minima para usar esta spell.\n'any' = usa independente da Harmony.\n'1' a '5' = usa somente quando Harmony >= valor.")

  local harmonyCombo = g_ui.createWidget('ComboBox', row3)
  harmonyCombo:setWidth(70)
  harmonyCombo:addAnchor(AnchorLeft, 'prev', AnchorRight)
  harmonyCombo:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  harmonyCombo:setMarginLeft(5)
  harmonyCombo:addOption('any')
  harmonyCombo:addOption('1')
  harmonyCombo:addOption('2')
  harmonyCombo:addOption('3')
  harmonyCombo:addOption('4')
  harmonyCombo:addOption('5')
  harmonyCombo:setCurrentOption(spell.harmony or 'any')

  harmonyCombo.onOptionChange = function(widget, option)
    spell.harmony = option
    BTCAttack.config.spells[slotIndex] = spell
    BTCAttack.saveConfig()
  end

  -- Separador entre slots (exceto ultimo)
  if slotIndex < 6 then
    local sep = g_ui.createWidget('HorizontalSeparator', parent)
    sep:setMarginTop(3)
    sep:setMarginBottom(3)
  end
end

-- Mantém a função antiga para compatibilidade (redireciona para a nova)
function BTCAttack.createSpellSlotUI(parent, slotIndex, iconFile)
  BTCAttack.createAttackSlotUI(parent, slotIndex, iconFile)
end

-- Busca dados completos da spell pelo words (para migrar configs antigas)
function BTCAttack.getSpellDataByWords(words)
  if not words or words == "" then return nil end
  
  local profile = "Default"
  if not SpellInfo or not SpellInfo[profile] then return nil end
  
  for spellName, info in pairs(SpellInfo[profile]) do
    if info.words and info.words:lower() == words:lower() then
      local groups = {}
      if info.group then
        for groupId, _ in pairs(info.group) do
          table.insert(groups, groupId)
        end
      end
      
      -- Obtem o iconId corretamente via SpellIcons ou clientId explicito
      local iconId = 0
      if info.clientId then
        iconId = info.clientId
      elseif info.icon and SpellIcons and SpellIcons[info.icon] then
        iconId = SpellIcons[info.icon][1]  -- [1] é o clientId
      else
        iconId = info.id or 0
      end
      
      return {
        name = spellName,
        words = info.words,
        cooldown = info.exhaustion or 2000,
        mana = info.mana or 0,
        spellId = info.id or 0,
        iconId = iconId,
        groups = groups,
        level = info.level or 0
      }
    end
  end
  return nil
end

-- Atualiza visual de cooldown dos slots (chamado pelo loop principal)
function BTCAttack.updateCooldownUI()
  -- Atualiza indicador visual de cooldown para cada slot
  for i = 1, 6 do
    local slotWidgets = BTCAttack.spellSlotWidgets[i]
    if slotWidgets and slotWidgets.enabledBtn and slotWidgets.icon then
      local spell = BTCAttack.config and BTCAttack.config.spells and BTCAttack.config.spells[i]
      if spell and spell.enabled and spell.words ~= "" then
        if BTCAttack.isSpellReady(i) then
          -- Spell pronta - cor normal
          slotWidgets.enabledBtn:setColor('#00ff00')
          slotWidgets.icon:setOpacity(1.0)
        else
          -- Spell em cooldown - indicador visual
          slotWidgets.enabledBtn:setColor('#ffaa00')
          slotWidgets.icon:setOpacity(0.5)
        end
      end
    end
  end
end

-- =============================================
-- SECAO DE TARGETING INTEGRADA NA ABA ATTACK
-- =============================================

-- Cria UI de Targeting dentro do painel de Attack
function BTCAttack.createTargetingUI(container)
  if not container then return end
  if not BTCTargeting or not BTCTargeting.config then return end
  
  -- Titulo
  local title = g_ui.createWidget("Label", container)
  title:setText("Targeting & Movement")
  title:setTextAlign(AlignCenter)
  title:setFont("verdana-11px-rounded")
  title:setColor("#9B59B6")
  title:setHeight(20)
  title:setMarginBottom(5)
  
  -- === MODO DE MOVIMENTO ===
  local modeLabel = g_ui.createWidget("Label", container)
  modeLabel:setText("Modo de Movimento:")
  modeLabel:setColor("#ffffff")
  modeLabel:setMarginBottom(5)
  
  -- Botoes de modo (horizontais)
  local modeRow = g_ui.createWidget("Panel", container)
  modeRow:setHeight(30)
  modeRow:setMarginBottom(5)
  
  local modeLayout = UIHorizontalLayout.create(modeRow)
  modeLayout:setSpacing(5)
  modeRow:setLayout(modeLayout)
  
  -- Funcao para atualizar visual dos botoes
  local modeButtons = {}
  local function updateModeButtons()
    for mode, btn in pairs(modeButtons) do
      if BTCTargeting.config.moveMode == mode then
        btn:setColor('#00ff00')
      else
        btn:setColor('#888888')
      end
    end
  end
  
  -- Botao STAND (parado)
  local standBtn = g_ui.createWidget("Button", modeRow)
  standBtn:setText("Parado")
  standBtn:setWidth(60)
  standBtn:setHeight(26)
  modeButtons["stand"] = standBtn
  
  standBtn.onClick = function()
    BTCTargeting.config.moveMode = "stand"
    BTCTargeting.saveConfig()
    updateModeButtons()
  end
  
  -- Botao APPROACH (ir para cima - Knight)
  local approachBtn = g_ui.createWidget("Button", modeRow)
  approachBtn:setText("Approach")
  approachBtn:setWidth(70)
  approachBtn:setHeight(26)
  approachBtn:setTooltip("Ir para cima do monstro (Knight)")
  modeButtons["approach"] = approachBtn
  
  approachBtn.onClick = function()
    BTCTargeting.config.moveMode = "approach"
    BTCTargeting.saveConfig()
    updateModeButtons()
  end

  -- Botao KITING (manter distancia)
  local kitingBtn = g_ui.createWidget("Button", modeRow)
  kitingBtn:setText("Kiting")
  kitingBtn:setWidth(55)
  kitingBtn:setHeight(26)
  kitingBtn:setTooltip("Manter distancia dos monstros (Mage/RP)")
  modeButtons["kiting"] = kitingBtn

  kitingBtn.onClick = function()
    BTCTargeting.config.moveMode = "kiting"
    BTCTargeting.saveConfig()
    updateModeButtons()
  end

  updateModeButtons()

  -- === KITING DISTANCE ===
  local kitDistRow = g_ui.createWidget("Panel", container)
  kitDistRow:setHeight(26)
  kitDistRow:setMarginBottom(3)

  local kitDistLabel = g_ui.createWidget("Label", kitDistRow)
  kitDistLabel:setText("Kiting Dist:")
  kitDistLabel:setColor("#aaaaaa")
  kitDistLabel:setWidth(70)
  kitDistLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  kitDistLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)

  local kitMinusBtn = g_ui.createWidget("Button", kitDistRow)
  kitMinusBtn:setText("-")
  kitMinusBtn:setWidth(24)
  kitMinusBtn:setHeight(22)
  kitMinusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitMinusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitMinusBtn:setMarginLeft(5)

  local kitValueLabel = g_ui.createWidget("Label", kitDistRow)
  kitValueLabel:setText(tostring(BTCTargeting.config.kitingDistance or 3))
  kitValueLabel:setColor("#00ff00")
  kitValueLabel:setTextAlign(AlignCenter)
  kitValueLabel:setWidth(24)
  kitValueLabel:setHeight(22)
  kitValueLabel:setBackgroundColor("#333333")
  kitValueLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitValueLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitValueLabel:setMarginLeft(3)

  local kitPlusBtn = g_ui.createWidget("Button", kitDistRow)
  kitPlusBtn:setText("+")
  kitPlusBtn:setWidth(24)
  kitPlusBtn:setHeight(22)
  kitPlusBtn:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitPlusBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitPlusBtn:setMarginLeft(3)

  local kitInfoLabel = g_ui.createWidget("Label", kitDistRow)
  kitInfoLabel:setText("tiles")
  kitInfoLabel:setColor("#888888")
  kitInfoLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  kitInfoLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  kitInfoLabel:setMarginLeft(5)

  kitMinusBtn.onClick = function()
    local v = math.max(1, (BTCTargeting.config.kitingDistance or 3) - 1)
    BTCTargeting.config.kitingDistance = v
    kitValueLabel:setText(tostring(v))
    BTCTargeting.saveConfig()
  end

  kitPlusBtn.onClick = function()
    local v = math.min(7, (BTCTargeting.config.kitingDistance or 3) + 1)
    BTCTargeting.config.kitingDistance = v
    kitValueLabel:setText(tostring(v))
    BTCTargeting.saveConfig()
  end

  -- === OPCOES ===
  -- Checkbox: Apenas quando atacando
  local onlyAttackRow = g_ui.createWidget("Panel", container)
  onlyAttackRow:setHeight(26)
  onlyAttackRow:setMarginBottom(3)
  
  local onlyAttackBtn = g_ui.createWidget("Button", onlyAttackRow)
  onlyAttackBtn:setText(BTCTargeting.config.onlyWhenAttacking and "[X]" or "[ ]")
  onlyAttackBtn:setWidth(28)
  onlyAttackBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  onlyAttackBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local onlyAttackLabel = g_ui.createWidget("Label", onlyAttackRow)
  onlyAttackLabel:setText("Apenas quando atacando")
  onlyAttackLabel:setColor("#cccccc")
  onlyAttackLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  onlyAttackLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  onlyAttackLabel:setMarginLeft(5)
  
  onlyAttackBtn.onClick = function()
    BTCTargeting.config.onlyWhenAttacking = not BTCTargeting.config.onlyWhenAttacking
    onlyAttackBtn:setText(BTCTargeting.config.onlyWhenAttacking and "[X]" or "[ ]")
    BTCTargeting.saveConfig()
  end
  
  -- Checkbox: Permitir diagonal
  local diagRow = g_ui.createWidget("Panel", container)
  diagRow:setHeight(26)
  diagRow:setMarginBottom(5)
  
  local diagBtn = g_ui.createWidget("Button", diagRow)
  diagBtn:setText(BTCTargeting.config.allowDiagonal and "[X]" or "[ ]")
  diagBtn:setWidth(28)
  diagBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  diagBtn:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  local diagLabel = g_ui.createWidget("Label", diagRow)
  diagLabel:setText("Permitir movimento diagonal")
  diagLabel:setColor("#cccccc")
  diagLabel:addAnchor(AnchorLeft, 'prev', AnchorRight)
  diagLabel:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  diagLabel:setMarginLeft(5)
  
  diagBtn.onClick = function()
    BTCTargeting.config.allowDiagonal = not BTCTargeting.config.allowDiagonal
    diagBtn:setText(BTCTargeting.config.allowDiagonal and "[X]" or "[ ]")
    BTCTargeting.saveConfig()
  end
  
  -- Separador entre Targeting e Attack
  local sepTA = g_ui.createWidget("HorizontalSeparator", container)
  sepTA:setMarginTop(5)
  sepTA:setMarginBottom(10)
end

-- Lock/unlock de target manualmente (via hotkey ou context menu)
function BTCAttack.setLockedTarget(creatureId)
  if not BTCAttack.config then return end
  BTCAttack.config.lockedTargetId = creatureId or 0
end

function BTCAttack.clearLockedTarget()
  BTCAttack.setLockedTarget(0)
end

-- Retorna status do modulo
function BTCAttack.getStatus()
  local enabled = BTCAttack.config and BTCAttack.config.enabled
  return enabled and "ON" or "OFF"
end

-- Inicializa
BTCAttack.init()
