leftHealthCircle = nil
leftHealthCircleFront = nil
leftHarmonySlots = {}  -- Array de 5 slots de harmony para Monk (1-5)
leftSereneCircle = nil -- Widget para o círculo serene do Monk
rightHealthCircle = nil
rightHealthCircleFront = nil
rightManaShieldFront = nil -- Widget para mana shield (camada intermediária)
mapPanel = nil

local harmonyRetryEvent = nil

-- Current health circle size ('small', 'default', 'large')
local currentHealthCircleSize = 'default'

-- Size dimensions mapping
local sizeDimensions = {
    small = { width = 35, height = 126 },
    default = { width = 58, height = 211 },
    large = { width = 79, height = 292 }
}

-- Dimensões da textura da imagem (esquerda) - will be updated based on size
local healthCircleTextureWidth = 58
local healthCircleTextureHeight = 211

-- Dimensões da textura da imagem (direita) - right_empty/right_full
local rightHealthCircleTextureWidth = 58
local rightHealthCircleTextureHeight = 211

-- Dimensões das imagens de mana shield - default-minimal/maximal_white
local manaShieldTextureWidth = 58
local manaShieldTextureHeight = 211

-- Dimensões para Monk
local monkHealthCircleTextureWidth = 58
local monkHealthCircleTextureHeight = 211

-- Distância customizada dos arcos (separada da engine)
local customArcDistance = 0

-- Opacidade customizada dos arcos (0-100%)
local customArcOpacity = 100

local displayArcs = true

-- Estado salvo do harmony (para restaurar ao reativar os arcos)
local savedHarmonyState = {
    harmony = 0,
    maxHarmony = 0,
    isSerene = false,
}

-- Função helper para verificar se é Monk
local function isMonk()
    if not g_game.isOnline() then
        return false
    end
    local player = g_game.getLocalPlayer()
    if not player or not player.isMonk then
        return false
    end

    return player:isMonk()
end

-- Helper function to get image path prefix based on current size
local function getSizePrefix()
    return currentHealthCircleSize
end

-- Helper function to update all dimension variables based on current size
local function updateDimensionsForSize()
    local dims = sizeDimensions[currentHealthCircleSize] or sizeDimensions['default']
    healthCircleTextureWidth = dims.width
    healthCircleTextureHeight = dims.height
    rightHealthCircleTextureWidth = dims.width
    rightHealthCircleTextureHeight = dims.height
    manaShieldTextureWidth = dims.width
    manaShieldTextureHeight = dims.height
    monkHealthCircleTextureWidth = dims.width
    monkHealthCircleTextureHeight = dims.height
end

-- Função helper para obter dimensões corretas
local function getHealthDimensions()
    if isMonk() then
        return monkHealthCircleTextureWidth, monkHealthCircleTextureHeight
    else
        return healthCircleTextureWidth, healthCircleTextureHeight
    end
end

-- Função para atualizar as imagens baseado na vocação
function updateHealthImages()
    if not leftHealthCircle or not leftHealthCircleFront then
        return
    end

    local sizePrefix = getSizePrefix()

    if isMonk() then
        -- Monk usa duas imagens: bg (fundo) e maximal (frente colorida)
        leftHealthCircle:setImageSource(string.format('/data/images/game/healthcircle/monk/%s/left/%s-bg-full-monk',
            sizePrefix, sizePrefix))
        leftHealthCircle:setOpacity(customArcOpacity / 100) -- Aumenta opacidade para Monk
        leftHealthCircleFront:setImageSource(string.format('/data/images/game/healthcircle/monk/%s/left/%s-maximal-monk',
            sizePrefix, sizePrefix))
        leftHealthCircleFront:setOpacity(customArcOpacity / 100) -- Aumenta opacidade para Monk
    else
        -- Outras vocações usam left_empty e left_full
        leftHealthCircle:setImageSource(string.format('/data/images/game/healthcircle/%s-left_empty', sizePrefix))
        leftHealthCircle:setOpacity(customArcOpacity / 100)      -- Opacidade padrão
        leftHealthCircleFront:setImageSource(string.format('/data/images/game/healthcircle/%s-left_full', sizePrefix))
        leftHealthCircleFront:setOpacity(customArcOpacity / 100) -- Opacidade padrão
    end
end

-- Função auxiliar para aplicar a opacidade em todos os arcos
local function applyOpacityToAllArcs()
    -- Converte de 0-100 (porcentagem) para 0-1 (valor de opacidade do OTClient)
    local opacity = customArcOpacity / 100

    if leftHealthCircle then
        leftHealthCircle:setOpacity(opacity)
    end
    if leftHealthCircleFront then
        leftHealthCircleFront:setOpacity(opacity)
    end
    if rightHealthCircle then
        rightHealthCircle:setOpacity(opacity)
    end
    if rightHealthCircleFront then
        rightHealthCircleFront:setOpacity(opacity)
    end

    if leftHarmonySlots and #leftHarmonySlots > 0 then
        for i = 1, 5 do
            if leftHarmonySlots[i] then
                leftHarmonySlots[i]:setOpacity(opacity)
            end
        end
    end

    if leftSereneCircle then
        leftSereneCircle:setOpacity(opacity)
    end

    if rightManaShieldFront then
        rightManaShieldFront:setOpacity(opacity)
    end
end

function handleShowArc(value)
    -- Atualiza a variável global de display
    if not g_game.isOnline() then return end
    displayArcs = value

    -- Arcos principais (sempre disponíveis)
    if leftHealthCircle then
        leftHealthCircle:setVisible(value)
    end
    if leftHealthCircleFront then
        leftHealthCircleFront:setVisible(value)
    end
    if rightHealthCircle then
        rightHealthCircle:setVisible(value)
    end
    if rightHealthCircleFront then
        rightHealthCircleFront:setVisible(value)
    end


    -- Harmony slots (apenas para Monk)
    if value and isMonk() and leftHarmonySlots and #leftHarmonySlots > 0 then
        onHarmonyChange(nil, savedHarmonyState.harmony, savedHarmonyState.maxHarmony, 0, 0)
    else
        -- DESATIVANDO ou não é Monk: Oculta todos os harmony slots
        if leftHarmonySlots and #leftHarmonySlots > 0 then
            for i = 1, 5 do
                if leftHarmonySlots[i] then
                    leftHarmonySlots[i]:setVisible(false)
                end
            end
        end
    end

    -- Serene circle (apenas para Monk)
    if leftSereneCircle then
        if value and isMonk() then
            -- REATIVANDO: Força atualização do serene para restaurar o estado
            onSereneChange(nil, savedHarmonyState.isSerene)
        else
            leftSereneCircle:setVisible(false)
        end
    end

    -- Mana shield (apenas se estiver ativo no player)
    if rightManaShieldFront then
        if value and g_game.isOnline() then
            local player = g_game.getLocalPlayer()
            if player and player.getManaShield and player.getMaxManaShield then
                local manaShield = player:getManaShield()
                local maxManaShield = player:getMaxManaShield()
                -- Mostra apenas se tiver mana shield ativo
                rightManaShieldFront:setVisible(manaShield and maxManaShield and manaShield > 0)
            else
                rightManaShieldFront:setVisible(false)
            end
        else
            rightManaShieldFront:setVisible(false)
        end
    end
end

function updateOpacity(opacityPercent)
    -- Salva a opacidade customizada
    customArcOpacity = opacityPercent or 100

    -- Aplica a opacidade em todos os arcos
    applyOpacityToAllArcs()
end

function setArcDistance(distance)
    -- Atualiza a distância customizada dos arcos
    customArcDistance = distance or 0

    -- Reaplica o posicionamento com a nova distância
    onGeometryChange()

    -- Reaplica a opacidade (pois onGeometryChange pode resetar)
    applyOpacityToAllArcs()
end

function setHealthCircleSize(size)
    -- Validate and set the size
    if size ~= 'small' and size ~= 'default' and size ~= 'large' then
        size = 'default'
    end

    currentHealthCircleSize = size

    -- Update dimension variables based on new size
    updateDimensionsForSize()

    -- Reload images with new size
    updateHealthImages()

    -- Reposition and resize all widgets
    onGeometryChange()

    -- Reapply opacity
    applyOpacityToAllArcs()
end

function init()
    -- Conecta ao evento de mudança de geometria do mapa
    connect(g_game, {
        onGameStart = onGameStart,
    })

    onGameStart()
end

function onGameStart()
    -- Desconecta eventos antigos se existirem
    -- if mapPanel then
    --     disconnect(mapPanel, {
    --         onGeometryChange = onGeometryChange,
    --     })
    -- end

    -- pcall(function()
    --     disconnect(LocalPlayer, {
    --         onHealthChange = onHealthChange,
    --         onManaChange = onManaChange,
    --         onVocationChange = onGeometryChange,
    --         onHarmonyChange = onHarmonyChange,
    --         onSereneChange = onSereneChange,
    --     })
    -- end)

    -- Destroi widgets anteriores se existirem (evita duplicação)
    if leftHealthCircle then
        leftHealthCircle:destroy()
        leftHealthCircle = nil
    end
    if leftHealthCircleFront then
        leftHealthCircleFront:destroy()
        leftHealthCircleFront = nil
    end

    if leftHarmonySlots then
        for i = 1, 5 do
            if leftHarmonySlots[i] then
                leftHarmonySlots[i]:destroy()
                leftHarmonySlots[i] = nil
            end
        end
        leftHarmonySlots = {}
    end
    if leftSereneCircle then
        leftSereneCircle:destroy()
        leftSereneCircle = nil
    end
    if rightHealthCircle then
        rightHealthCircle:destroy()
        rightHealthCircle = nil
    end
    if rightHealthCircleFront then
        rightHealthCircleFront:destroy()
        rightHealthCircleFront = nil
    end
    if rightManaShieldFront then
        rightManaShieldFront:destroy()
        rightManaShieldFront = nil
    end

    -- Obtém o painel do mapa
    mapPanel = modules.game_interface.getMapPanel()

    -- Destroi qualquer widget órfão que possa existir no mapPanel
    if mapPanel then
        -- Tenta buscar por ID e destruir
        local orphans = {
            mapPanel:getChildById('leftHealthCircle'),
            mapPanel:getChildById('leftHealthCircleFront'),
            mapPanel:getChildById('leftSereneCircle'),
            mapPanel:getChildById('rightHealthCircle'),
            mapPanel:getChildById('rightHealthCircleFront'),
            mapPanel:getChildById('rightManaShieldFront'),
        }

        -- Adiciona os 5 slots de harmony
        for i = 1, 5 do
            table.insert(orphans, mapPanel:getChildById('leftHarmonySlot' .. i))
        end

        for _, widget in ipairs(orphans) do
            if widget then
                widget:destroy()
            end
        end
    end

    -- Importa os estilos do OTUI
    g_ui.importStyle("game_healthcircle.otui")

    -- Cria os widgets do health circle à esquerda
    leftHealthCircle = g_ui.createWidget('LeftHealthCircle', mapPanel)
    leftHealthCircleFront = g_ui.createWidget('LeftHealthCircleFront', mapPanel)

    -- Cria os 5 widgets de harmony slots (Monk)
    leftHarmonySlots = {}
    for i = 1, 5 do
        leftHarmonySlots[i] = g_ui.createWidget('LeftHealthCircle', mapPanel)
        leftHarmonySlots[i]:setId('leftHarmonySlot' .. i)
        leftHarmonySlots[i]:setVisible(false) -- Inicia invisível
    end

    -- Cria o widget de serene (Monk)
    leftSereneCircle = g_ui.createWidget('LeftHealthCircle', mapPanel)
    leftSereneCircle:setId('leftSereneCircle')
    leftSereneCircle:setVisible(false) -- Inicia invisível

    -- Atualiza as imagens baseado na vocação
    updateHealthImages()

    -- Cria os widgets do health circle à direita
    rightHealthCircle = g_ui.createWidget('RightHealthCircle', mapPanel)
    rightManaShieldFront = g_ui.createWidget('RightHealthCircleFront', mapPanel)
    rightManaShieldFront:setId('rightManaShieldFront')
    rightManaShieldFront:setVisible(false) -- Inicia invisível
    rightHealthCircleFront = g_ui.createWidget('RightHealthCircleFront', mapPanel)

    connect(mapPanel, {
        onGeometryChange = onGeometryChange,
    })
    connect(LocalPlayer, {
        onHealthChange = onHealthChange,
        onManaChange = onManaChange,
        onVocationChange = onGeometryChange,
        onHarmonyChange = onHarmonyChange,
        onSereneChange = onSereneChange,
        onManaShieldChange = onManaShieldChange,
    })

    -- Carrega configurações salvas do usuário
    local savedOpacity = g_settings.getNumber('opacityScrollbar')
    if savedOpacity and savedOpacity > 0 then
        customArcOpacity = savedOpacity
    end

    local savedDisplayArcs = g_settings.getBoolean('showHealthManaCircle')
    if savedDisplayArcs ~= nil then
        displayArcs = savedDisplayArcs
        handleShowArc(displayArcs)
    end

    local savedDistance = g_settings.getNumber('distFromCenScrollbar')
    if savedDistance then
        customArcDistance = savedDistance
    end

    -- Load saved health circle size
    local savedSize = g_settings.getString('healthCircleSize')
    if savedSize and (savedSize == 'small' or savedSize == 'default' or savedSize == 'large') then
        currentHealthCircleSize = savedSize
        updateDimensionsForSize()
        updateHealthImages()
    end

    -- Posiciona inicialmente
    onGeometryChange()

    -- Atualiza a vida e mana se já estiver no jogo
    if g_game.isOnline() then
        local player = g_game.getLocalPlayer()
        if player then
            onHealthChange(player, player:getHealth(), player:getMaxHealth())

            -- Verifica imediatamente se tem mana shield para decidir qual caminho seguir
            local hasManaShield = false
            if player.getManaShield and player.getMaxManaShield then
                local manaShield = player:getManaShield()
                local maxManaShield = player:getMaxManaShield()
                if manaShield and maxManaShield and manaShield > 0 then
                    hasManaShield = true
                end
            end

            if hasManaShield then
                -- Tem mana shield - aguarda 50ms e atualiza com as imagens corretas
                scheduleEvent(function()
                    if not g_game.isOnline() then
                        return
                    end

                    local p = g_game.getLocalPlayer()
                    if not p then
                        return
                    end

                    if p.getManaShield and p.getMaxManaShield then
                        local manaShield = p:getManaShield()
                        local maxManaShield = p:getMaxManaShield()
                        if manaShield and maxManaShield and manaShield > 0 then
                            onManaShieldChange(p, manaShield, maxManaShield)
                        end
                    end
                end, 50)
            else
                -- Não tem mana shield - atualiza mana normalmente
                onManaChange(player, player:getMana(), player:getMaxMana())
            end

            -- Atualiza harmony se for Monk
            if player.getHarmony and player.getMaxHarmony then
                local harmony = player:getHarmony()
                local maxHarmony = player:getMaxHarmony()
                if maxHarmony and maxHarmony > 0 then
                    onHarmonyChange(player, harmony, maxHarmony, 0, 0)
                end
            end

            -- Atualiza serene se for Monk
            if player.isSerene then
                local serene = player:isSerene()
                onSereneChange(serene)
            end
        end
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
    })

    if mapPanel then
        disconnect(mapPanel, {
            onGeometryChange = onGeometryChange,
        })
    end

    disconnect(LocalPlayer, {
        onHealthChange = onHealthChange,
        onManaChange = onManaChange,
        onVocationChange = onGeometryChange,
        onHarmonyChange = onHarmonyChange,
        onSereneChange = onSereneChange,
        onManaShieldChange = onManaShieldChange,
    })

    -- Destroi os widgets
    if leftHealthCircle then
        leftHealthCircle:destroy()
        leftHealthCircle = nil
    end

    if leftHealthCircleFront then
        leftHealthCircleFront:destroy()
        leftHealthCircleFront = nil
    end

    if leftHarmonySlots then
        for i = 1, 5 do
            if leftHarmonySlots[i] then
                leftHarmonySlots[i]:destroy()
                leftHarmonySlots[i] = nil
            end
        end
        leftHarmonySlots = {}
    end

    if leftSereneCircle then
        leftSereneCircle:destroy()
        leftSereneCircle = nil
    end

    if rightHealthCircle then
        rightHealthCircle:destroy()
        rightHealthCircle = nil
    end

    if rightHealthCircleFront then
        rightHealthCircleFront:destroy()
        rightHealthCircleFront = nil
    end

    if rightManaShieldFront then
        rightManaShieldFront:destroy()
        rightManaShieldFront = nil
    end

    mapPanel = nil
end

function onHarmonyChange(player, harmony, maxHarmony, oldHarmony, oldMaxHarmony)
    -- Se ainda não é Monk mas recebeu harmony, aguarda 100ms e tenta novamente
    if not isMonk() then
        if maxHarmony and maxHarmony > 0 then
            if not harmonyRetryEvent then
                harmonyRetryEvent = scheduleEvent(function()
                    harmonyRetryEvent = nil
                    onHarmonyChange(player, harmony, maxHarmony, oldHarmony, oldMaxHarmony)
                end, 100)
            end
        end
        return
    end

    -- Cancelar qualquer retentativa pendente se já é Monk
    if harmonyRetryEvent then
        removeEvent(harmonyRetryEvent)
        harmonyRetryEvent = nil
    end

    if not leftHarmonySlots or #leftHarmonySlots == 0 then
        g_logger.warning("[onHarmonyChange] Harmony slots not initialized!")
        return
    end

    -- Calcula o nível de harmony (1-5)
    local harmonyLevel = 0
    if maxHarmony > 0 then
        harmonyLevel = math.ceil((harmony / maxHarmony) * 5)
        harmonyLevel = math.max(0, math.min(5, harmonyLevel))
    end

    -- Salva o estado atual do harmony para restaurar depois
    savedHarmonyState.harmony = harmony
    savedHarmonyState.maxHarmony = maxHarmony

    -- Atualiza cada slot individualmente
    local sizePrefix = getSizePrefix()
    for i = 1, 5 do
        if leftHarmonySlots[i] then
            if i <= harmonyLevel then
                -- Configura o slot se estiver dentro do nível de harmony
                local slotImage = string.format('/data/images/game/healthcircle/monk/%s/left/%s-slot-%d-monk',
                    sizePrefix, sizePrefix, i)
                leftHarmonySlots[i]:setImageSource(slotImage)
                leftHarmonySlots[i]:setImageColor('$var-text-cip-color-orange') -- Cor laranja para slots de harmony
                -- Só mostra se displayArcs estiver ativo
                leftHarmonySlots[i]:setVisible(displayArcs)
                leftHarmonySlots[i]:setOpacity(customArcOpacity / 100)
            else
                -- Esconde o slot se estiver acima do nível de harmony
                leftHarmonySlots[i]:setVisible(false)
            end
        end
    end
end

function onSereneChange(player, serene)
    -- Se ainda não é Monk mas recebeu serene=true, aguarda 100ms e tenta novamente
    if not isMonk() then
        if serene then
            scheduleEvent(function()
                onSereneChange(player, serene)
            end, 100)
        end
        return
    end

    if not leftSereneCircle then
        g_logger.warning("[onSereneChange] Serene circle not initialized!")
        return
    end

    if serene then
        -- Configura o círculo serene roxo
        local sizePrefix = getSizePrefix()
        leftSereneCircle:setImageSource(string.format(
            '/data/images/game/healthcircle/monk/%s/left/%s-circle-purple-monk', sizePrefix, sizePrefix))
        leftSereneCircle:setImageColor('#FC8CFF') -- Cor roxa
        leftSereneCircle:setOpacity(customArcOpacity / 100)
        -- Só mostra se displayArcs estiver ativo
        leftSereneCircle:setVisible(displayArcs)
    else
        -- Esconde o círculo serene
        leftSereneCircle:setVisible(false)
    end

    savedHarmonyState.isSerene = serene
end

function onHealthChange(player, health, maxHealth)
    if not leftHealthCircle or not leftHealthCircleFront then
        return
    end

    if not g_game.isOnline() or maxHealth <= 0 then
        return
    end

    -- Calcula a porcentagem de vida
    local healthPercent = math.floor(health / maxHealth * 100)

    -- Obtém dimensões corretas baseado na vocação
    local currentWidth, currentHeight = getHealthDimensions()
    local imageHeight = currentHeight

    if imageHeight <= 0 or currentHeight <= 0 then
        return
    end

    -- Calcula quantos pixels devem estar vazios (parte de cima)
    local emptyPixels = math.floor(imageHeight * (1 - (healthPercent / 100)))
    local filledPixels = imageHeight - emptyPixels

    -- Calcula o clipping da textura
    local textureClipStart = math.floor(currentHeight * emptyPixels / imageHeight)
    textureClipStart = math.max(0, math.min(textureClipStart, currentHeight))
    local textureClipHeight = currentHeight - textureClipStart

    -- Posição Y base (mesma do leftHealthCircle)
    local baseY = leftHealthCircle:getY()

    -- Atualiza a parte cheia (front)
    leftHealthCircleFront:setY(baseY + emptyPixels)
    leftHealthCircleFront:setHeight(filledPixels)

    -- Clipping da imagem (largura completa para todas vocações)
    leftHealthCircleFront:setImageClip({
        x = 0,
        y = textureClipStart,
        width = currentWidth,
        height = textureClipHeight
    })

    leftHealthCircleFront:setOpacity(customArcOpacity / 100)

    -- Define a cor baseada na porcentagem de vida (todas vocações)
    if healthPercent > 94 then
        leftHealthCircleFront:setImageColor('#00C000FF')
    elseif healthPercent > 59 then
        leftHealthCircleFront:setImageColor('#60c060FF')
    elseif healthPercent > 29 then
        leftHealthCircleFront:setImageColor('#c0c000FF')
    elseif healthPercent > 9 then
        leftHealthCircleFront:setImageColor('#c03030FF')
    elseif healthPercent > 3 then
        leftHealthCircleFront:setImageColor('#c00000FF')
    else
        leftHealthCircleFront:setImageColor('#600000FF')
    end
end

function onManaChange(player, mana, maxMana)
    if not rightHealthCircle or not rightHealthCircleFront then
        return
    end

    if not g_game.isOnline() or maxMana <= 0 then
        return
    end

    -- Verifica se mana shield está ativo
    local manaShield = 0
    if player.getManaShield then
        manaShield = player:getManaShield()
    end
    local hasManaShield = manaShield > 0 or (rightManaShieldFront and rightManaShieldFront:isVisible())

    -- Calcula a porcentagem de mana
    local manaPercent = math.floor(mana / maxMana * 100)

    local sizePrefix = getSizePrefix()

    if hasManaShield then
        -- Mana shield ativo - usa dimensões baseadas no tamanho atual (maximal_white)
        -- Configura as imagens imediatamente
        rightHealthCircle:setImageSource(string.format('/data/images/game/healthcircle/%s-bg-full', sizePrefix))
        rightHealthCircle:setOpacity(customArcOpacity / 100)
        rightHealthCircle:setWidth(manaShieldTextureWidth)
        rightHealthCircle:setHeight(manaShieldTextureHeight)

        rightHealthCircleFront:setImageSource(string.format('/data/images/game/healthcircle/%s-maximal_white', sizePrefix))
        rightHealthCircleFront:setWidth(manaShieldTextureWidth)

        local imageHeight = manaShieldTextureHeight

        if imageHeight <= 0 or manaShieldTextureHeight <= 0 then
            return
        end

        -- Calcula quantos pixels devem estar vazios (parte de cima)
        local emptyPixels = math.floor(imageHeight * (1 - (manaPercent / 100)))
        local filledPixels = imageHeight - emptyPixels

        -- Calcula o clipping da textura
        local textureClipStart = math.floor(manaShieldTextureHeight * emptyPixels / imageHeight)
        textureClipStart = math.max(0, math.min(textureClipStart, manaShieldTextureHeight))
        local textureClipHeight = manaShieldTextureHeight - textureClipStart

        -- Posição Y base (mesma do rightHealthCircle)
        local baseY = rightHealthCircle:getY()

        -- Atualiza a camada de mana (maximal_white - azul)
        rightHealthCircleFront:setY(baseY + emptyPixels)
        rightHealthCircleFront:setHeight(filledPixels)
        rightHealthCircleFront:setImageClip({
            x = 0,
            y = textureClipStart,
            width = manaShieldTextureWidth,
            height = textureClipHeight
        })
        rightHealthCircleFront:setImageColor('$var-text-cip-store-timed')
        rightHealthCircleFront:setOpacity(customArcOpacity / 100)
    else
        -- Mana shield inativo - usa dimensões baseadas no tamanho atual (right_full)
        -- Configura as imagens imediatamente
        rightHealthCircle:setImageSource(string.format('/data/images/game/healthcircle/%s-right_empty', sizePrefix))
        rightHealthCircle:setOpacity(customArcOpacity / 100)
        rightHealthCircle:setWidth(rightHealthCircleTextureWidth)
        rightHealthCircle:setHeight(rightHealthCircleTextureHeight)

        rightHealthCircleFront:setImageSource(string.format('/data/images/game/healthcircle/%s-right_full', sizePrefix))
        rightHealthCircleFront:setWidth(rightHealthCircleTextureWidth)

        local imageHeight = rightHealthCircleTextureHeight

        if imageHeight <= 0 or rightHealthCircleTextureHeight <= 0 then
            return
        end

        -- Calcula quantos pixels devem estar vazios (parte de cima)
        local emptyPixels = math.floor(imageHeight * (1 - (manaPercent / 100)))
        local filledPixels = imageHeight - emptyPixels

        -- Calcula o clipping da textura
        local textureClipStart = math.floor(rightHealthCircleTextureHeight * emptyPixels / imageHeight)
        textureClipStart = math.max(0, math.min(textureClipStart, rightHealthCircleTextureHeight))
        local textureClipHeight = rightHealthCircleTextureHeight - textureClipStart

        -- Posição Y base (mesma do rightHealthCircle)
        local baseY = rightHealthCircle:getY()

        -- Atualiza a parte cheia (front)
        rightHealthCircleFront:setY(baseY + emptyPixels)
        rightHealthCircleFront:setHeight(filledPixels)
        rightHealthCircleFront:setImageClip({
            x = 0,
            y = textureClipStart,
            width = rightHealthCircleTextureWidth,
            height = textureClipHeight
        })
        rightHealthCircleFront:setImageColor('$var-text-cip-store-timed')
    end
end

function onManaShieldChange(player, manaShield, maxManaShield)
    if not rightHealthCircle or not rightHealthCircleFront or not rightManaShieldFront then
        return
    end

    if not g_game.isOnline() then
        return
    end

    -- Se mana shield está ativo (> 0)
    if manaShield > 0 and maxManaShield > 0 then
        -- Configura a camada de mana shield (minimal_white com cor roxa)
        local sizePrefix = getSizePrefix()
        rightManaShieldFront:setImageSource(string.format('/data/images/game/healthcircle/%s-minimal_white', sizePrefix))
        rightManaShieldFront:setVisible(true)
        rightManaShieldFront:setWidth(manaShieldTextureWidth)

        -- Calcula a porcentagem de mana shield
        local manaShieldPercent = math.floor(manaShield / maxManaShield * 100)

        -- Dimensões das imagens de mana shield (58x211)
        local imageHeight = manaShieldTextureHeight

        if imageHeight <= 0 or manaShieldTextureHeight <= 0 then
            return
        end

        -- Calcula quantos pixels devem estar vazios (parte de cima) para mana shield
        local emptyPixels = math.floor(imageHeight * (1 - (manaShieldPercent / 100)))
        local filledPixels = imageHeight - emptyPixels

        -- Calcula o clipping da textura
        local textureClipStart = math.floor(manaShieldTextureHeight * emptyPixels / imageHeight)
        textureClipStart = math.max(0, math.min(textureClipStart, manaShieldTextureHeight))
        local textureClipHeight = manaShieldTextureHeight - textureClipStart

        -- Posição Y base (mesma do rightHealthCircle)
        local baseY = rightHealthCircle:getY()

        -- Atualiza a camada de mana shield (minimal_white - ciano)
        rightManaShieldFront:setY(baseY + emptyPixels)
        rightManaShieldFront:setHeight(filledPixels)
        rightManaShieldFront:setImageClip({
            x = 0,
            y = textureClipStart,
            width = manaShieldTextureWidth,
            height = textureClipHeight
        })
        rightManaShieldFront:setImageColor('#7F00A9') -- Cor roxa para mana shield
        rightManaShieldFront:setOpacity(customArcOpacity / 100)

        -- Atualiza a camada de mana através do onManaChange
        local mana = player:getMana()
        local maxMana = player:getMaxMana()
        if maxMana > 0 then
            onManaChange(player, mana, maxMana)
        end
    else
        -- Mana shield desativado - restaura configuração padrão
        rightManaShieldFront:setVisible(false)

        -- Força recálculo da mana com as imagens padrão (onManaChange configura tudo)
        local mana = player:getMana()
        local maxMana = player:getMaxMana()
        if maxMana > 0 then
            onManaChange(player, mana, maxMana)
        end
    end
end

function onGeometryChange()
    if not mapPanel or not leftHealthCircle or not leftHealthCircleFront then
        return
    end

    -- Atualiza as imagens baseado na vocação
    updateHealthImages()

    -- Tamanho da imagem (esquerda) - usa dimensões corretas baseado na vocação
    local leftImageWidth, leftImageHeight = getHealthDimensions()

    -- Tamanho da imagem (direita)
    local rightImageWidth = rightHealthCircleTextureWidth
    local rightImageHeight = rightHealthCircleTextureHeight

    -- Calcula barDistance (igual ao healthcircle)
    local barDistance = 100
    if not (math.floor(mapPanel:getHeight() / 2 * 0.2) < 100) then
        barDistance = math.floor(mapPanel:getHeight() / 2 * 0.2)
    end

    -- Aplica a distância customizada dos arcos
    barDistance = barDistance + customArcDistance

    -- Verifica o modo de visualização
    local currentViewMode = modules.game_interface.currentViewMode

    local leftX, leftY, rightX, rightY

    if currentViewMode == 2 then
        -- Modo 2: posicionamento relativo ao centro do mapa
        leftX = math.floor(mapPanel:getWidth() / 2 - barDistance - leftImageWidth)
        leftY = mapPanel:getHeight() / 2 - leftImageHeight / 2

        rightX = math.floor(mapPanel:getWidth() / 2 + barDistance)
        rightY = mapPanel:getHeight() / 2 - rightImageHeight / 2
    else
        -- Modo padrão: posicionamento absoluto (igual ao healthcircle)
        leftX = mapPanel:getX() + mapPanel:getWidth() / 2 - leftImageWidth - barDistance
        leftY = mapPanel:getY() + mapPanel:getHeight() / 2 - leftImageHeight / 2

        rightX = mapPanel:getX() + mapPanel:getWidth() / 2 + barDistance
        rightY = mapPanel:getY() + mapPanel:getHeight() / 2 - rightImageHeight / 2
    end

    -- Posiciona barra esquerda
    leftHealthCircle:setX(leftX)
    leftHealthCircle:setY(leftY)
    leftHealthCircle:setWidth(leftImageWidth)
    leftHealthCircle:setHeight(leftImageHeight)


    leftHealthCircleFront:setX(leftX)
    leftHealthCircleFront:setWidth(leftImageWidth)

    -- Posiciona harmony slots (Monk) - todos os 5 slots na mesma posição (sobrepostos)
    if leftHarmonySlots and #leftHarmonySlots > 0 then
        for i = 1, 5 do
            if leftHarmonySlots[i] then
                if isMonk() then
                    -- Posiciona todos os slots na mesma posição (sobrepostos)
                    leftHarmonySlots[i]:setX(leftX)
                    leftHarmonySlots[i]:setY(leftY)
                    leftHarmonySlots[i]:setWidth(leftImageWidth)
                    leftHarmonySlots[i]:setHeight(leftImageHeight)
                else
                    -- Esconde todos se não for Monk
                    leftHarmonySlots[i]:setVisible(false)
                end
            end
        end
    end

    -- Posiciona círculo serene (Monk) - sobreposto à barra de vida
    if leftSereneCircle then
        if isMonk() then
            -- Posiciona na mesma posição da barra de vida
            leftSereneCircle:setX(leftX)
            leftSereneCircle:setY(leftY)
            leftSereneCircle:setWidth(leftImageWidth)
            leftSereneCircle:setHeight(leftImageHeight)
        else
            -- Esconde se não for Monk
            leftSereneCircle:setVisible(false)
        end
    end

    -- Posiciona barra direita
    if rightHealthCircle and rightHealthCircleFront then
        rightHealthCircle:setX(rightX)
        rightHealthCircle:setY(rightY)
        rightHealthCircle:setWidth(rightImageWidth)
        rightHealthCircle:setHeight(rightImageHeight)

        rightHealthCircleFront:setX(rightX)
        rightHealthCircleFront:setWidth(rightImageWidth)

        -- Posiciona a camada de mana shield (mesma posição da camada de mana)
        if rightManaShieldFront then
            rightManaShieldFront:setX(rightX)
            rightManaShieldFront:setWidth(rightImageWidth)
        end
    end

    -- Atualiza a vida e mana para recalcular as posições
    if g_game.isOnline() then
        local player = g_game.getLocalPlayer()
        if player then
            onHealthChange(player, player:getHealth(), player:getMaxHealth())
            onManaChange(player, player:getMana(), player:getMaxMana())
        end
    end

    -- Reaplica a opacidade customizada (centralizada)
    applyOpacityToAllArcs()
end
