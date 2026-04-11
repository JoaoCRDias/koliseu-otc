--[[
  SMART FOLLOW — lado do servidor (OPCIONAL)

  O cliente ja' anda com autoWalk sem precisar disto. Usa este ficheiro apenas se:
  - Quiseres guardar no servidor se o jogador tem "smart follow" ligado (anti-cheat / logs), ou
  - O teu servidor exige extended opcodes registados para nao desligar o jogador.

  Cliente: ExtendedIds.SmartFollow = 8 (modules/gamelib/const.lua). Ajusta o numero em baixo se mudares.

  Canary / TFS (exemplo generico):
  1) Em data/XML/features.xml (ou equivalente), garante extended opcodes activos para OTClient.
  2) Regista o opcode 8 (ou o que usares) para o jogador no login.
  3) Cria um creaturescript / evento ExtendedOpcode que receba buffer "1" ou "0".

  Exemplo minimal (adapta nomes de API ao teu engine):

  local SMART_FOLLOW_OPCODE = 8

  local ec = EventCallback
  ec.onExtendedOpcode = function(player, opcode, buffer)
    if opcode ~= SMART_FOLLOW_OPCODE then
      return true
    end
    -- opcional: player:setStorageValue(xxx, buffer == "1" and 1 or 0)
    return true
  end
  ec:register()
--]]

local SMART_FOLLOW_OPCODE = 8

-- Descomenta e adapta ao teu servidor:
--[[
function onExtendedOpcode(player, opcode, buffer)
  if opcode ~= SMART_FOLLOW_OPCODE then
    return
  end
  -- buffer: "1" = ligado, "0" = desligado
end
--]]
