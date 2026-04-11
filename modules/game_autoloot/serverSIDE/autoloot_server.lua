-- AutoLoot Server Side
-- Opcode: 200
-- Envia o estado do AutoLoot para o cliente via extended opcode

local AUTOLOOT_OPCODE = 200

-- Função auxiliar para enviar extended opcode ao jogador
local function sendAutolootState(player, state)
    if not player or not player:isPlayer() then
        return false
    end

    -- Verifica se o jogador está usando OTClient
    if not player:isUsingOtClient() then
        return false
    end

    -- Usa o método correto para enviar extended opcode
    player:sendExtendedOpcode(AUTOLOOT_OPCODE, tostring(state))
    return true
end

-- Função para obter o estado atual do AutoLoot do jogador
local function getAutolootState(player)
    if not player then
        return 0
    end
    
    -- Retorna o valor da feature AutoLoot
    -- 0 = off, 1 = on regular, 2 = all (incluindo bosses)
    return player:getFeature(Features.AutoLoot) or 0
end

-- TalkAction modificado para enviar opcode após mudança
local feature = TalkAction("!autoloot")

local validValues = {
    -- "all",
    "on",
    "off",
}

function feature.onSay(player, words, param)
    if not player:isVip() then
        player:sendCancelMessage("Only VIP players can use this command.")
        return true
    end

    if not table.contains(validValues, param) then
        local validValuesStr = table.concat(validValues, "/")
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "!autoloot [" .. validValuesStr .. "]")
        return true
    end

    local newState = 0
    if param == "all" then
        player:setFeature(Features.AutoLoot, 2)
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "AutoLoot is now enabled for all kills (including bosses).")
        newState = 2
    elseif param == "on" then
        player:setFeature(Features.AutoLoot, 1)
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "AutoLoot is now enabled for all regular kills (no bosses).")
        newState = 1
    elseif param == "off" then
        player:setFeature(Features.AutoLoot, 0)
        player:sendTextMessage(MESSAGE_EVENT_ADVANCE, "AutoLoot is now disabled.")
        newState = 0
    end

    -- Envia o novo estado para o cliente via extended opcode
    sendAutolootState(player, newState)

    return true
end

feature:separator(" ")
feature:groupType("normal")
feature:register()

-- Envia o estado inicial quando o jogador entra no jogo
local autolootLoginEvent = CreatureEvent("AutoLootLogin")

function autolootLoginEvent.onLogin(player)
    if not player or not player:isPlayer() then
        return true
    end

    -- Aguarda um delay maior para garantir que o cliente está totalmente pronto
    addEvent(function()
        if player and player:isPlayer() then
            local state = getAutolootState(player)
            sendAutolootState(player, state)
        end
    end, 1000) -- 1 segundo de delay

    return true
end

autolootLoginEvent:register()
 