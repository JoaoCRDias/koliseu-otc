--[[
  Spell Data Module for game_helper
  Loads spell configuration data from JSON file once at initialization
]]

HelperSpellData = {}

local dataLoaded = false

-- Tabelas de dados (carregadas uma vez)
local spellFilterByVocation = {}
local healingSpellFilter = {}
local hasteWhiteList = {}
local utitoWhiteList = {}
local trainingHealSpells = {}        -- map: vocationId -> array de spellIds permitidos para treino
local trainingHealSpellsSet = {}     -- map: vocationId -> set para lookup O(1)
local ignoredSpellsIds = {}
local supportSpellsWhitelist = {}    -- map: vocationId -> array de spellIds
local supportSpellsWhitelistSet = {} -- map: vocationId -> set para lookup O(1)
local potionWhitelist = {}
local rangedMonsterSpells = {}       -- array de spellIds que usam filtro rangedMonsterNames
local rangedMonsterSpellsSet = {}    -- set para lookup O(1)
local exposeWeaknessSpellsSet = {}
local sapStrengthSpellsSet = {}
local buffDurationSpells = {}        -- map: spellId -> duration in ms (buff ativo, ex.: utamo tempo 10s)

function HelperSpellData.load()
  if dataLoaded then
    return true
  end

  local jsonPath = "/modules/game_helper/spelldata.json"

  if not g_resources.fileExists(jsonPath) then
    g_logger.error("[HelperSpellData] spelldata.json not found at: " .. jsonPath)
    return false
  end

  local content = g_resources.readFileContents(jsonPath)
  if not content or content == "" then
    g_logger.error("[HelperSpellData] Failed to read spelldata.json")
    return false
  end

  local status, data = pcall(function()
    return json.decode(content)
  end)

  if not status or not data then
    g_logger.error("[HelperSpellData] Failed to parse spelldata.json: " .. tostring(data))
    return false
  end

  -- Converter chaves string para number em spellFilterByVocation
  if data.spellFilterByVocation then
    for k, v in pairs(data.spellFilterByVocation) do
      spellFilterByVocation[tonumber(k)] = v
    end
  end

  -- Converter chaves string para number em healingSpellFilter
  if data.healingSpellFilter then
    for k, v in pairs(data.healingSpellFilter) do
      healingSpellFilter[tonumber(k)] = v
    end
  end

  -- Converter chaves string para number em hasteWhiteList
  if data.hasteWhiteList then
    for k, v in pairs(data.hasteWhiteList) do
      hasteWhiteList[tonumber(k)] = v
    end
  end

  -- Converter chaves string para number em utitoWhiteList
  if data.utitoWhiteList then
    for k, v in pairs(data.utitoWhiteList) do
      utitoWhiteList[tonumber(k)] = v
    end
  end

  -- Converter trainingHealSpells para map por vocação + set para lookup O(1)
  if data.trainingHealSpells then
    for k, v in pairs(data.trainingHealSpells) do
      local vocId = tonumber(k)
      trainingHealSpells[vocId] = v
      trainingHealSpellsSet[vocId] = {}
      for _, spellId in ipairs(v) do
        trainingHealSpellsSet[vocId][spellId] = true
      end
    end
  end

  -- Converter array para set (tabela com chaves) em ignoredSpellsIds
  if data.ignoredSpellsIds then
    for _, spellId in ipairs(data.ignoredSpellsIds) do
      ignoredSpellsIds[spellId] = true
    end
  end

  -- Converter supportSpellsWhitelist para map por vocação + set para lookup O(1)
  if data.supportSpellsWhitelist then
    for k, v in pairs(data.supportSpellsWhitelist) do
      local vocId = tonumber(k)
      supportSpellsWhitelist[vocId] = v
      supportSpellsWhitelistSet[vocId] = {}
      for _, spellId in ipairs(v) do
        supportSpellsWhitelistSet[vocId][spellId] = true
      end
    end
  end

  -- potionWhitelist já é array, copiar diretamente
  if data.potionWhitelist then
    potionWhitelist = data.potionWhitelist
  end

  -- Anexar CustomPotionIds (do init.lua) ao potionWhitelist
  if CustomPotionIds and type(CustomPotionIds) == "table" then
    for _, potion in ipairs(CustomPotionIds) do
      -- Verificar se já não existe no potionWhitelist (evitar duplicatas)
      local exists = false
      for _, existing in ipairs(potionWhitelist) do
        if existing.id == potion.id then
          exists = true
          break
        end
      end
      if not exists then
        table.insert(potionWhitelist, potion)
      end
    end
  end

  -- rangedMonsterSpells: array de spellIds + set para lookup O(1)
  if data.rangedMonsterSpells then
    rangedMonsterSpells = data.rangedMonsterSpells
    for _, spellId in ipairs(data.rangedMonsterSpells) do
      rangedMonsterSpellsSet[spellId] = true
    end
  end

  -- exposeWeaknessSpells: set para lookup O(1)
  if data.exposeWeaknessSpells then
    for _, spellId in ipairs(data.exposeWeaknessSpells) do
      exposeWeaknessSpellsSet[spellId] = true
    end
  end

  -- sapStrengthSpells: set para lookup O(1)
  if data.sapStrengthSpells then
    for _, spellId in ipairs(data.sapStrengthSpells) do
      sapStrengthSpellsSet[spellId] = true
    end
  end

  if data.buffDurationSpells then
    for k, v in pairs(data.buffDurationSpells) do
      buffDurationSpells[tonumber(k)] = v
    end
  end

  dataLoaded = true
  return true
end

function HelperSpellData.isLoaded()
  return dataLoaded
end

function HelperSpellData.getSpellFilterByVocation()
  return spellFilterByVocation
end

function HelperSpellData.getHealingSpellFilter()
  return healingSpellFilter
end

function HelperSpellData.getHasteWhiteList()
  return hasteWhiteList
end

function HelperSpellData.getUtitoWhiteList()
  return utitoWhiteList
end

function HelperSpellData.getTrainingHealSpells()
  return trainingHealSpells
end

function HelperSpellData.getTrainingHealSpellsSet()
  return trainingHealSpellsSet
end

function HelperSpellData.getIgnoredSpellsIds()
  return ignoredSpellsIds
end

function HelperSpellData.getPotionWhitelist()
  return potionWhitelist
end

function HelperSpellData.getSupportSpellsWhitelist()
  return supportSpellsWhitelist
end

function HelperSpellData.getSupportSpellsWhitelistSet()
  return supportSpellsWhitelistSet
end

-- Funções utilitárias
function HelperSpellData.getSpellsForVocation(vocationId)
  return spellFilterByVocation[vocationId] or {}
end

function HelperSpellData.getHasteSpellsForVocation(vocationId)
  return hasteWhiteList[vocationId] or {}
end

function HelperSpellData.isTrainingSpellAllowed(spellId, vocationId)
  local vocSet = trainingHealSpellsSet[vocationId]
  if not vocSet then return false end
  return vocSet[spellId] == true
end

function HelperSpellData.getTrainingSpellsForVocation(vocationId)
  return trainingHealSpells[vocationId] or {}
end

function HelperSpellData.isHealingSpellForVocation(spellId, vocationId)
  local vocations = healingSpellFilter[spellId]
  if not vocations then
    return false
  end
  for _, voc in ipairs(vocations) do
    if voc == vocationId then
      return true
    end
  end
  return false
end

function HelperSpellData.getHealingSpellsForVocation(vocationId)
  local result = {}
  for spellId, vocations in pairs(healingSpellFilter) do
    for _, voc in ipairs(vocations) do
      if voc == vocationId then
        result[spellId] = true
        break
      end
    end
  end
  return result
end

function HelperSpellData.isSupportSpellAllowed(spellId, vocationId)
  local vocSet = supportSpellsWhitelistSet[vocationId]
  if not vocSet then return false end
  return vocSet[spellId] == true
end

function HelperSpellData.getSupportSpellsForVocation(vocationId)
  return supportSpellsWhitelist[vocationId] or {}
end

function HelperSpellData.getRangedMonsterSpells()
  return rangedMonsterSpells
end

function HelperSpellData.isRangedMonsterSpell(spellId)
  return rangedMonsterSpellsSet[spellId] == true
end

function HelperSpellData.isExposeWeaknessSpell(spellId)
  return exposeWeaknessSpellsSet[spellId] == true
end

function HelperSpellData.isSapStrengthSpell(spellId)
  return sapStrengthSpellsSet[spellId] == true
end

function HelperSpellData.getBuffDuration(spellId)
  return buffDurationSpells[spellId] or 0
end

-- Knight/EK: Chivalrous Challenge (237, exeta amp res). Paladin/RP: Divine Dazzle (238, exana amp res).
function HelperSpellData.getAmpResSpellForVocation(vocationId)
  if vocationId == 1 or vocationId == 11 then return 237 end
  if vocationId == 2 or vocationId == 12 then return 238 end
  return nil
end

function HelperSpellData.getAmpResSpellsForVocation(vocationId)
  local id = HelperSpellData.getAmpResSpellForVocation(vocationId)
  if id then return { id } end
  return {}
end
