--[[
  BTC Bot - Sistema de Configuracao
  Salva e carrega configuracoes do bot usando arquivo JSON
  Configuracoes sao salvas POR PERSONAGEM (cada char tem suas configs)
]]

BTCConfig = BTCConfig or {}

-- Storage interno
BTCConfig.data = {}
BTCConfig.allData = {}  -- Dados de todos os personagens
BTCConfig.filePath = "/btcbot_settings.json"
BTCConfig.currentCharName = nil

-- Obtem o nome do personagem atual
function BTCConfig.getCharName()
  if g_game.isOnline() then
    local player = g_game.getLocalPlayer()
    if player then
      return player:getName()
    end
  end
  return "default"
end

-- Inicializa o sistema de config
function BTCConfig.init()
  BTCConfig.loadAll()
  BTCConfig.loadForCurrentChar()
end

-- Carrega configs para o personagem atual
function BTCConfig.loadForCurrentChar()
  local charName = BTCConfig.getCharName()
  BTCConfig.currentCharName = charName
  
  if BTCConfig.allData[charName] then
    BTCConfig.data = BTCConfig.allData[charName]
    print("[BTCConfig] Configuracoes carregadas para: " .. charName)
  else
    BTCConfig.data = {}
    print("[BTCConfig] Novo personagem detectado: " .. charName)
  end
end

-- Obtem um valor da configuracao
function BTCConfig.get(key)
  return BTCConfig.data[key]
end

-- Define um valor na configuracao
function BTCConfig.set(key, value)
  BTCConfig.data[key] = value
  BTCConfig.save()
end

-- Salva todas as configuracoes em arquivo JSON
function BTCConfig.save()
  local status, result = pcall(function()
    local charName = BTCConfig.getCharName()
    BTCConfig.allData[charName] = BTCConfig.data
    local jsonStr = json.encode(BTCConfig.allData, 2)
    g_resources.writeFileContents(BTCConfig.filePath, jsonStr)
  end)
  if not status then
    print("[BTCConfig] Erro ao salvar: " .. tostring(result))
  end
end

-- Carrega dados de todos os personagens
function BTCConfig.loadAll()
  local status, result = pcall(function()
    if g_resources.fileExists(BTCConfig.filePath) then
      local content = g_resources.readFileContents(BTCConfig.filePath)
      if content and content ~= "" then
        BTCConfig.allData = json.decode(content)
      end
    end
  end)
  if not status then
    print("[BTCConfig] Erro ao carregar: " .. tostring(result))
    BTCConfig.allData = {}
  end
end

-- Reseta configuracoes do personagem atual
function BTCConfig.reset()
  BTCConfig.data = {}
  BTCConfig.save()
end

-- Reseta configuracoes de TODOS os personagens
function BTCConfig.resetAll()
  BTCConfig.allData = {}
  BTCConfig.data = {}
  BTCConfig.save()
end

-- Obtem lista de personagens com config salva
function BTCConfig.getSavedCharacters()
  local chars = {}
  for name, _ in pairs(BTCConfig.allData) do
    table.insert(chars, name)
  end
  return chars
end

-- Verifica se trocou de personagem e recarrega configs
function BTCConfig.checkCharacterChange()
  local currentChar = BTCConfig.getCharName()
  if currentChar ~= BTCConfig.currentCharName then
    print("[BTCConfig] Personagem trocado! Recarregando configs...")
    BTCConfig.loadForCurrentChar()
    return true
  end
  return false
end

return BTCConfig
