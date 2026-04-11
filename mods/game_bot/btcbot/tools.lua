--[[
  BTC Bot - Sistema de Tools (Suporte)
  
  Magias de suporte automaticas:
  - Haste (utani hur, utani gran hur, utani tempo hur)
  - Magic Shield (utamo vita)
  - Buff spells (utito tempo, utamo tempo, etc)
]]

BTCTools = BTCTools or {}

-- Configuracao padrao
BTCTools.defaultConfig = {
  enabled = false,
  
  -- Haste (correr mais rapido)
  haste = {
    enabled = false,
    spell = "utani hur"
  },
  
  -- Magic Shield (formato simples como ring/amulet)
  magicShield = {
    utamoVita = { enabled = false, condition = "life", operator = "<=", threshold = 80 },
    itemShield = { enabled = false, itemId = 35563, condition = "life", operator = "<=", threshold = 80 },
    exanaVita = { enabled = false, condition = "life", operator = "<=", threshold = 80 },
  },
  
  -- Utito Tempo (buff de ataque melee - Knight)
  utitoTempo = {
    enabled = false,
    spell = "utito tempo"
  },
  
  -- Utamo Tempo (buff de defesa - Knight)
  utamoTempo = {
    enabled = false,
    spell = "utamo tempo"
  },
  
  -- Sharpshooter (buff de ataque - Paladin)
  sharpshooter = {
    enabled = false,
    spell = "utito tempo san"
  },
  
  -- Swift Foot (velocidade de ataque - Paladin)
  swiftFoot = {
    enabled = false,
    spell = "utamo tempo san"
  },
  
  -- Protector (buff de defesa geral)
  protector = {
    enabled = false,
    spell = "utamo tempo"
  },
  
  -- Blood Rage (buff de ataque - Knight)
  bloodRage = {
    enabled = false,
    spell = "utito tempo"
  },
  
  -- Charge (Knight)
  charge = {
    enabled = false,
    spell = "utani tempo hur"
  },
  
  -- Strong Haste
  strongHaste = {
    enabled = false,
    spell = "utani gran hur"
  }
}

-- Spells de suporte por tipo
BTCTools.supportSpells = {
  -- Haste spells (velocidade de movimento)
  haste = {
    { words = "utani hur", name = "Haste", mana = 60, level = 14, voc = {1,2,3,4,5,11,12,13,14,15}, duration = 33000 },
    { words = "utani gran hur", name = "Strong Haste", mana = 100, level = 20, voc = {3,4,13,14}, duration = 22000 },
    { words = "utani tempo hur", name = "Charge", mana = 100, level = 25, voc = {1,11}, duration = 5000 },
  },
  
  -- Magic Shield
  magicShield = {
    { words = "utamo vita", name = "Magic Shield", mana = 50, level = 14, voc = {3,4,13,14}, duration = 200000 },
  },
  
  -- Buff de ataque
  attackBuff = {
    { words = "utito tempo", name = "Blood Rage", mana = 290, level = 60, voc = {1,11}, duration = 10000 },
    { words = "utito tempo san", name = "Sharpshooter", mana = 450, level = 60, voc = {2,12}, duration = 10000 },
  },
  
  -- Buff de defesa
  defenseBuff = {
    { words = "utamo tempo", name = "Protector", mana = 200, level = 55, voc = {1,11}, duration = 13000 },
    { words = "utamo tempo san", name = "Swift Foot", mana = 400, level = 55, voc = {2,12}, duration = 10000 },
  },
  
  -- Curas e Remocoes de debuff
  cureSpells = {
    { words = "exana amp res", name = "Remove Curse", mana = 300, level = 100, voc = {3,4,13,14}, duration = 0 },
    { words = "exana pox", name = "Cure Poison", mana = 30, level = 10, voc = {1,2,3,4,5,11,12,13,14,15}, duration = 0 },
    { words = "exana flam", name = "Cure Burning", mana = 30, level = 30, voc = {1,2,3,4,11,12,13,14}, duration = 0 },
    { words = "exana vis", name = "Cure Electrification", mana = 30, level = 22, voc = {1,2,3,4,11,12,13,14}, duration = 0 },
    { words = "exana kor", name = "Cure Bleeding", mana = 30, level = 45, voc = {1,11}, duration = 0 },
  },
  
  -- Cancelamentos
  cancelSpells = {
    { words = "uteta reeq", name = "Cancel Invisibility", mana = 200, level = 26, voc = {1,2,3,4,5,11,12,13,14,15}, duration = 0 },
    { words = "uteta res eq", name = "Cancel Magic Shield", mana = 50, level = 14, voc = {3,4,13,14}, duration = 0 },
  },
  
  -- Familiares
  familiars = {
    { words = "utevo res dru", name = "Summon Grovebeast", mana = 3000, level = 200, voc = {4,14}, duration = 900000 },
    { words = "utevo res sor", name = "Summon Skullfrost", mana = 3000, level = 200, voc = {3,13}, duration = 900000 },
    { words = "utevo res kni", name = "Summon Emberwing", mana = 3000, level = 200, voc = {1,11}, duration = 900000 },
    { words = "utevo res pal", name = "Summon Thundergiant", mana = 3000, level = 200, voc = {2,12}, duration = 900000 },
  },
  
  -- Paladin especiais
  paladinSupport = {
    { words = "utevo grav san", name = "Divine Dazzle", mana = 80, level = 250, voc = {2,12}, duration = 0 },
  },
}

-- Variaveis de controle
BTCTools.config = nil
BTCTools.lastCastTime = {}    -- Guarda ultimo cast para evitar spam
BTCTools.spellCooldown = 1000  -- Cooldown minimo entre casts (1 segundo)

-- Constantes dos PlayerStates (valores fixos do protocolo)
local STATE_HASTE = 64
local STATE_MANASHIELD = 16
local STATE_NEWMANASHIELD = 67108864  -- Novo Magic Shield (versoes mais novas)
local STATE_PARTYBUFF = 4096
local STATE_PARALYZE = 32

-- Inicializa o modulo
function BTCTools.init()
  BTCTools.config = BTCTools.loadConfig()
end

-- Carrega configuracao salva ou usa padrao
function BTCTools.loadConfig()
  local saved = BTCConfig.get("tools")
  if saved then
    if saved.magicShield then
      if not saved.magicShield.utamoVita then
        saved.magicShield.utamoVita = { enabled = saved.magicShield.enabled or false, condition = "life", threshold = 80 }
      end
      if not saved.magicShield.itemShield then
        if saved.magicShield.item35563 then
          saved.magicShield.itemShield = saved.magicShield.item35563
          saved.magicShield.itemShield.itemId = saved.magicShield.itemShield.itemId or 35563
          saved.magicShield.item35563 = nil
        else
          saved.magicShield.itemShield = { enabled = false, itemId = 35563, condition = "life", threshold = 80 }
        end
      end
      if not saved.magicShield.itemShield.itemId then
        saved.magicShield.itemShield.itemId = 35563
      end
      if not saved.magicShield.itemShield.condition then
        saved.magicShield.itemShield.condition = "life"
      end
      if not saved.magicShield.exanaVita then
        saved.magicShield.exanaVita = { enabled = false, condition = "life", threshold = 80 }
      elseif not saved.magicShield.exanaVita.condition then
        saved.magicShield.exanaVita.condition = "life"
      end
      saved.magicShield.enabled = nil
    end
    return saved
  end
  return table.copy(BTCTools.defaultConfig)
end

-- Salva configuracao
function BTCTools.saveConfig()
  BTCConfig.set("tools", BTCTools.config)
end

-- Retorna vocacao do player
function BTCTools.getPlayerVocation()
  if not g_game.isOnline() then return 0 end
  local player = g_game.getLocalPlayer()
  if not player then return 0 end
  return player:getVocation() or 0
end

-- Verifica se player tem a vocacao para usar a spell
function BTCTools.canUseSpell(spellInfo)
  local voc = BTCTools.getPlayerVocation()
  if voc == 0 then return true end  -- Se nao conseguir pegar voc, permite
  
  for _, v in ipairs(spellInfo.voc) do
    if v == voc then
      return true
    end
  end
  return false
end

-- Verifica se o player tem um estado/buff ativo usando bit.band
function BTCTools.hasState(state)
  if not g_game.isOnline() then return false end
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  local states = player:getStates()
  if not states or states == 0 then return false end
  
  -- Usa bit ou bit32
  local bitlib = bit or bit32
  if not bitlib then return false end
  
  return bitlib.band(states, state) > 0
end

-- Verifica se tem Haste ativo
function BTCTools.hasHaste()
  return BTCTools.hasState(STATE_HASTE)
end

-- Verifica se tem Magic Shield ativo (verifica ambos os estados: antigo e novo)
function BTCTools.hasManaShield()
  -- Verifica o estado antigo (16) e o novo (67108864)
  if BTCTools.hasState(STATE_MANASHIELD) then
    return true
  end
  if BTCTools.hasState(STATE_NEWMANASHIELD) then
    return true
  end
  return false
end

-- Verifica se tem PartyBuff ativo (Blood Rage, Protector, Sharpshooter, Swift Foot)
-- Todos esses buffs usam o mesmo icone PartyBuff
function BTCTools.hasPartyBuff()
  -- Verifica o estado PartyBuff (4096)
  if BTCTools.hasState(STATE_PARTYBUFF) then
    return true
  end
  return false
end

-- Verifica se esta paralyzed
function BTCTools.isParalyzed()
  return BTCTools.hasState(STATE_PARALYZE)
end

-- Verifica se passou cooldown desde ultimo cast
function BTCTools.canCast(spellKey)
  local now = g_clock.millis()
  local lastCast = BTCTools.lastCastTime[spellKey] or 0
  return (now - lastCast) >= BTCTools.spellCooldown
end

-- Obtem info da spell pelo words
function BTCTools.getSpellInfo(spellWords)
  for category, spells in pairs(BTCTools.supportSpells) do
    for _, spell in ipairs(spells) do
      if spell.words == spellWords then
        return spell
      end
    end
  end
  return nil
end

-- Casta spell de Haste (verifica se nao tem haste ativo)
function BTCTools.castHaste(spellKey, spellWords)
  if not g_game.isOnline() then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  -- Se ja tem haste, nao precisa castar
  if BTCTools.hasHaste() then
    return false
  end
  
  -- Verifica cooldown para evitar spam
  if not BTCTools.canCast(spellKey) then
    return false
  end
  
  local spellInfo = BTCTools.getSpellInfo(spellWords)
  if not spellInfo then return false end
  
  -- Verifica mana
  local mana = player:getMana()
  if mana < spellInfo.mana then return false end
  
  -- Verifica vocacao
  if not BTCTools.canUseSpell(spellInfo) then return false end
  
  -- Casta
  g_game.talk(spellWords)
  BTCTools.lastCastTime[spellKey] = g_clock.millis()
  
  return true
end

function BTCTools.getHealthPercent()
  local player = g_game.getLocalPlayer()
  if not player then return 100 end
  local max = player:getMaxHealth()
  if max == 0 then return 100 end
  return math.floor((player:getHealth() / max) * 100)
end

function BTCTools.getManaPercent()
  local player = g_game.getLocalPlayer()
  if not player then return 100 end
  local max = player:getMaxMana()
  if max == 0 then return 100 end
  return math.floor((player:getMana() / max) * 100)
end

function BTCTools.getCurrentPercent(condition)
  if condition == "mana" then
    return BTCTools.getManaPercent()
  end
  return BTCTools.getHealthPercent()
end

function BTCTools.tryCastUtamoVita()
  if not g_game.isOnline() then return false end
  local ms = BTCTools.config.magicShield
  if not ms or not ms.utamoVita or not ms.utamoVita.enabled then return false end
  if BTCTools.hasManaShield() then return false end
  if not BTCTools.canCast("utamoVita") then return false end

  local cur = BTCTools.getCurrentPercent(ms.utamoVita.condition or "life")
  local op = ms.utamoVita.operator or "<="
  local condMet = (op == ">=") and (cur >= (ms.utamoVita.threshold or 80)) or (cur <= (ms.utamoVita.threshold or 80))
  if not condMet then return false end

  local spellInfo = BTCTools.getSpellInfo("utamo vita")
  if not spellInfo then return false end
  local player = g_game.getLocalPlayer()
  if not player or player:getMana() < spellInfo.mana then return false end
  if not BTCTools.canUseSpell(spellInfo) then return false end

  g_game.talk("utamo vita")
  BTCTools.lastCastTime["utamoVita"] = g_clock.millis()
  return true
end

function BTCTools.tryMagicShieldItem()
  if not g_game.isOnline() then return false end
  local ms = BTCTools.config.magicShield
  if not ms or not ms.itemShield or not ms.itemShield.enabled then return false end
  local itemId = ms.itemShield.itemId or 35563
  if itemId == 0 then return false end
  if BTCTools.hasManaShield() then return false end
  if not BTCTools.canCast("magicShieldItem") then return false end

  local cur = BTCTools.getCurrentPercent(ms.itemShield.condition or "life")
  local op = ms.itemShield.operator or "<="
  local condMet = (op == ">=") and (cur >= (ms.itemShield.threshold or 80)) or (cur <= (ms.itemShield.threshold or 80))
  if not condMet then return false end

  g_game.useInventoryItem(itemId)
  BTCTools.lastCastTime["magicShieldItem"] = g_clock.millis()
  return true
end

function BTCTools.tryMagicShieldExanaVita()
  if not g_game.isOnline() then return false end
  local ms = BTCTools.config.magicShield
  if not ms or not ms.exanaVita or not ms.exanaVita.enabled then return false end
  if not BTCTools.canCast("magicShieldExanaVita") then return false end

  local cur = BTCTools.getCurrentPercent(ms.exanaVita.condition or "life")
  local op = ms.exanaVita.operator or "<="
  local condMet = (op == ">=") and (cur >= (ms.exanaVita.threshold or 80)) or (cur <= (ms.exanaVita.threshold or 80))
  if not condMet then return false end

  g_game.talk("exana vita")
  BTCTools.lastCastTime["magicShieldExanaVita"] = g_clock.millis()
  return true
end

-- Casta spell de Buff (verifica se nao tem party buff ativo)
function BTCTools.castBuff(spellKey, spellWords)
  if not g_game.isOnline() then return false end
  
  local player = g_game.getLocalPlayer()
  if not player then return false end
  
  -- Se ja tem party buff, nao precisa castar
  if BTCTools.hasPartyBuff() then
    return false
  end
  
  -- Verifica cooldown para evitar spam
  if not BTCTools.canCast(spellKey) then
    return false
  end
  
  local spellInfo = BTCTools.getSpellInfo(spellWords)
  if not spellInfo then return false end
  
  -- Verifica mana
  local mana = player:getMana()
  if mana < spellInfo.mana then return false end
  
  -- Verifica vocacao
  if not BTCTools.canUseSpell(spellInfo) then return false end
  
  -- Casta
  g_game.talk(spellWords)
  BTCTools.lastCastTime[spellKey] = g_clock.millis()
  
  return true
end

-- Funcao principal de execucao
function BTCTools.execute()
  if not g_game.isOnline() then return end
  if not BTCTools.config or not BTCTools.config.enabled then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end
  
  -- ========== HASTE SPELLS (verificam hasHaste) ==========
  
  -- Haste (utani hur)
  if BTCTools.config.haste and BTCTools.config.haste.enabled then
    BTCTools.castHaste("haste", BTCTools.config.haste.spell)
  end
  
  -- Strong Haste (utani gran hur)
  if BTCTools.config.strongHaste and BTCTools.config.strongHaste.enabled then
    BTCTools.castHaste("strongHaste", BTCTools.config.strongHaste.spell)
  end
  
  -- Charge (utani tempo hur)
  if BTCTools.config.charge and BTCTools.config.charge.enabled then
    BTCTools.castHaste("charge", BTCTools.config.charge.spell)
  end
  
  -- ========== MAGIC SHIELD ==========
  local ms = BTCTools.config.magicShield
  if ms then
    if ms.utamoVita and ms.utamoVita.enabled then
      BTCTools.tryCastUtamoVita()
    end
    if ms.itemShield and ms.itemShield.enabled then
      BTCTools.tryMagicShieldItem()
    end
    if ms.exanaVita and ms.exanaVita.enabled then
      BTCTools.tryMagicShieldExanaVita()
    end
  end
  
  -- ========== BUFF SPELLS (verificam hasPartyBuff) ==========
  
  -- Utito Tempo / Blood Rage
  if BTCTools.config.utitoTempo and BTCTools.config.utitoTempo.enabled then
    BTCTools.castBuff("utitoTempo", BTCTools.config.utitoTempo.spell)
  end
  
  -- Utamo Tempo / Protector
  if BTCTools.config.utamoTempo and BTCTools.config.utamoTempo.enabled then
    BTCTools.castBuff("utamoTempo", BTCTools.config.utamoTempo.spell)
  end
  
  -- Sharpshooter
  if BTCTools.config.sharpshooter and BTCTools.config.sharpshooter.enabled then
    BTCTools.castBuff("sharpshooter", BTCTools.config.sharpshooter.spell)
  end
  
  -- Swift Foot
  if BTCTools.config.swiftFoot and BTCTools.config.swiftFoot.enabled then
    BTCTools.castBuff("swiftFoot", BTCTools.config.swiftFoot.spell)
  end
end

-- Retorna lista de spells de haste disponiveis para a vocacao
function BTCTools.getAvailableHasteSpells()
  local voc = BTCTools.getPlayerVocation()
  local available = {}
  
  for _, spell in ipairs(BTCTools.supportSpells.haste) do
    if voc == 0 then
      table.insert(available, spell)
    else
      for _, v in ipairs(spell.voc) do
        if v == voc then
          table.insert(available, spell)
          break
        end
      end
    end
  end
  
  return available
end

-- Cria a interface de configuracao
function BTCTools.createUI(parent)
  parent:destroyChildren()
  
  -- ========== SECAO HASTE ==========
  local hasteLabel = g_ui.createWidget('Label', parent)
  hasteLabel:setText('Velocidade (Haste)')
  hasteLabel:setColor('#ffaa00')
  hasteLabel:setHeight(18)
  hasteLabel:setMarginTop(5)
  
  -- Haste normal
  BTCTools.createSpellRow(parent, "haste", "Haste", "utani hur")
  
  -- Strong Haste
  BTCTools.createSpellRow(parent, "strongHaste", "Strong Haste", "utani gran hur")
  
  -- Charge (Knight)
  BTCTools.createSpellRow(parent, "charge", "Charge", "utani tempo hur")
  
  -- Separador
  local sep1 = g_ui.createWidget('HorizontalSeparator', parent)
  sep1:setMarginTop(10)
  sep1:setMarginBottom(8)
  
  -- ========== SECAO MAGIC SHIELD ==========
  local shieldLabel = g_ui.createWidget('Label', parent)
  shieldLabel:setText('Magic Shield')
  shieldLabel:setColor('#ffaa00')
  shieldLabel:setHeight(18)

  BTCTools.createMagicShieldUI(parent)
  
  -- Separador
  local sep2 = g_ui.createWidget('HorizontalSeparator', parent)
  sep2:setMarginTop(10)
  sep2:setMarginBottom(8)
  
  -- ========== SECAO BUFF KNIGHT ==========
  local knightLabel = g_ui.createWidget('Label', parent)
  knightLabel:setText('Buff Knight')
  knightLabel:setColor('#ffaa00')
  knightLabel:setHeight(18)
  
  -- Blood Rage (utito tempo)
  BTCTools.createSpellRow(parent, "utitoTempo", "Blood Rage", "utito tempo")
  
  -- Protector (utamo tempo)
  BTCTools.createSpellRow(parent, "utamoTempo", "Protector", "utamo tempo")
  
  -- Separador
  local sep3 = g_ui.createWidget('HorizontalSeparator', parent)
  sep3:setMarginTop(10)
  sep3:setMarginBottom(8)
  
  -- ========== SECAO BUFF PALADIN ==========
  local paladinLabel = g_ui.createWidget('Label', parent)
  paladinLabel:setText('Buff Paladin')
  paladinLabel:setColor('#ffaa00')
  paladinLabel:setHeight(18)
  
  -- Sharpshooter
  BTCTools.createSpellRow(parent, "sharpshooter", "Sharpshooter", "utito tempo san")
  
  -- Swift Foot
  BTCTools.createSpellRow(parent, "swiftFoot", "Swift Foot", "utamo tempo san")
end

function BTCTools.createMagicShieldUI(parent)
  local ms = BTCTools.config.magicShield
  if not ms then return end
  if not ms.utamoVita then
    ms.utamoVita = { enabled = false, condition = "life", threshold = 80 }
  end
  if not ms.itemShield then
    ms.itemShield = { enabled = false, itemId = 35563, condition = "life", threshold = 80 }
  end
  if not ms.exanaVita then
    ms.exanaVita = { enabled = false, condition = "life", threshold = 80 }
  end

  BTCTools.createMagicShieldRow(parent, ms.utamoVita, "utamo vita")
  BTCTools.createMagicShieldItemRow(parent, ms.itemShield)
  BTCTools.createMagicShieldRow(parent, ms.exanaVita, "exana vita")
end

function BTCTools.createMagicShieldItemRow(parent, cfg)
  if not cfg then return end

  local row = g_ui.createWidget('Panel', parent)
  row:setLayout(UIHorizontalLayout.create(row))
  row:getLayout():setSpacing(5)
  row:setHeight(36)
  row:setMarginTop(3)

  local checkBox = g_ui.createWidget('CheckBox', row)
  checkBox:setText(' Item')
  checkBox:setChecked(cfg.enabled)
  checkBox:setWidth(50)
  checkBox.onCheckChange = function(widget, checked)
    cfg.enabled = checked
    BTCTools.saveConfig()
  end

  local itemPreview = g_ui.createWidget('UIItem', row)
  itemPreview:setSize({width = 34, height = 34})
  itemPreview:setVirtual(true)
  if cfg.itemId and cfg.itemId > 0 then
    itemPreview:setItemId(cfg.itemId)
  end

  local selectBtn = g_ui.createWidget('Button', row)
  selectBtn:setText('...')
  selectBtn:setWidth(26)
  selectBtn:setTooltip('Selecionar item')
  selectBtn.onClick = function()
    BTCItemSelector.start(function(itemId)
      cfg.itemId = itemId
      BTCTools.saveConfig()
      itemPreview:setItemId(itemId)
    end)
  end

  local condCombo = g_ui.createWidget('ComboBox', row)
  condCombo:setWidth(50)
  condCombo:addOption('Life')
  condCombo:addOption('Mana')
  if (cfg.condition or "life") == "mana" then
    condCombo:setCurrentIndex(2)
  else
    condCombo:setCurrentIndex(1)
  end
  condCombo.onOptionChange = function(widget, option)
    cfg.condition = option:lower()
    BTCTools.saveConfig()
  end

  local opCombo = g_ui.createWidget('ComboBox', row)
  opCombo:setWidth(45)
  opCombo:addOption('<=')
  opCombo:addOption('>=')
  opCombo:setCurrentOption(cfg.operator == ">=" and ">=" or "<=")
  opCombo.onOptionChange = function(widget, option)
    cfg.operator = option
    BTCTools.saveConfig()
  end

  local thresholdInput = g_ui.createWidget('TextEdit', row)
  thresholdInput:setWidth(35)
  thresholdInput:setText(tostring(cfg.threshold or 80))
  thresholdInput.onTextChange = function(widget, text)
    local value = tonumber(text) or 80
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    cfg.threshold = value
    BTCTools.saveConfig()
  end

  local percentLabel = g_ui.createWidget('Label', row)
  percentLabel:setText('%')
  percentLabel:setColor('#888888')
  percentLabel:setWidth(14)
end

function BTCTools.createMagicShieldRow(parent, cfg, displayName)
  if not cfg then return end

  local row = g_ui.createWidget('Panel', parent)
  row:setLayout(UIHorizontalLayout.create(row))
  row:getLayout():setSpacing(5)
  row:setHeight(26)
  row:setMarginTop(3)

  local checkBox = g_ui.createWidget('CheckBox', row)
  checkBox:setText(' ' .. displayName)
  checkBox:setChecked(cfg.enabled)
  checkBox:setWidth(105)
  checkBox.onCheckChange = function(widget, checked)
    cfg.enabled = checked
    BTCTools.saveConfig()
  end

  local condCombo = g_ui.createWidget('ComboBox', row)
  condCombo:setWidth(58)
  condCombo:addOption('Life')
  condCombo:addOption('Mana')
  if (cfg.condition or "life") == "mana" then
    condCombo:setCurrentIndex(2)
  else
    condCombo:setCurrentIndex(1)
  end
  condCombo.onOptionChange = function(widget, option)
    cfg.condition = option:lower()
    BTCTools.saveConfig()
  end

  local opCombo = g_ui.createWidget('ComboBox', row)
  opCombo:setWidth(45)
  opCombo:addOption('<=')
  opCombo:addOption('>=')
  opCombo:setCurrentOption(cfg.operator == ">=" and ">=" or "<=")
  opCombo.onOptionChange = function(widget, option)
    cfg.operator = option
    BTCTools.saveConfig()
  end

  local thresholdInput = g_ui.createWidget('TextEdit', row)
  thresholdInput:setWidth(40)
  thresholdInput:setText(tostring(cfg.threshold or 80))
  thresholdInput.onTextChange = function(widget, text)
    local value = tonumber(text) or 80
    if value < 0 then value = 0 end
    if value > 100 then value = 100 end
    cfg.threshold = value
    BTCTools.saveConfig()
  end

  local percentLabel = g_ui.createWidget('Label', row)
  percentLabel:setText('%')
  percentLabel:setColor('#888888')
  percentLabel:setWidth(18)
end

-- Cria uma linha de configuracao de spell
function BTCTools.createSpellRow(parent, configKey, displayName, defaultSpell)
  local config = BTCTools.config[configKey] or { enabled = false, spell = defaultSpell }
  
  local row = g_ui.createWidget('Panel', parent)
  row:setHeight(24)
  row:setMarginTop(3)
  
  -- Checkbox ON/OFF com as words da spell
  local checkBox = g_ui.createWidget('CheckBox', row)
  checkBox:setText(' ' .. (config.spell or defaultSpell))
  checkBox:setChecked(config.enabled)
  checkBox:addAnchor(AnchorLeft, 'parent', AnchorLeft)
  checkBox:addAnchor(AnchorRight, 'parent', AnchorRight)
  checkBox:addAnchor(AnchorVerticalCenter, 'parent', AnchorVerticalCenter)
  
  checkBox.onCheckChange = function(widget, checked)
    if not BTCTools.config[configKey] then
      BTCTools.config[configKey] = { enabled = false, spell = defaultSpell }
    end
    BTCTools.config[configKey].enabled = checked
    BTCTools.saveConfig()
  end
end

return BTCTools
