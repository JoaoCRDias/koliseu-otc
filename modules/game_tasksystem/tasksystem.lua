-- ========================================================================
-- Task Board Module
-- Sistema completo de Tasks com 3 abas:
--   1) Bounty Tasks  (3 cards de monstros, reroll, dificuldade, talisman)
--   2) Weekly Tasks   (kill tasks + delivery tasks + progresso semanal)
--   3) Hunting Shop   (loja de outfits, addons, montarias)
-- ========================================================================

local taskWindow = nil
local taskButton = nil
local currentTab = "bounty"       -- Aba ativa: "bounty" | "weekly" | "shop"
local selectedDifficulty = 1      -- Indice da dificuldade selecionada (1=Iniciante,2=Adepto,3=Experiente,4=Mestre,5=Boss)

-- Dados recebidos do servidor
local bountyTasks = {}            -- 3 cards de Bounty Tasks
local talismanData = {}           -- 4 slots de upgrade do Talisman
local weeklyKillTasks = {}        -- 6 kill tasks semanais
local weeklyDeliveryTasks = {}    -- 6 delivery tasks semanais
local weeklyProgress = {}         -- Progresso semanal (completadas, multiplicador)
local weeklyRewards = {}          -- Recompensas semanais
local shopItems = {}              -- Itens da Hunting Shop
local exchangeItems = {}          -- Itens trocaveis por Mystic Tokens
local currencies = {taskTokens = 0, silverTokens = 0, goldTokens = 0}

-- Lista Preferida
local preferredListWindow = nil
local allDifficultyMonsters = {}
local currentPreferred = {}
local currentUnwanted = {}
local prefMaxSlots = 10
local prefUnlockedTiers = 0

local OPCODE_TASK = 216

local DIFFICULTIES = {
    {name = "Iniciante", key = "beginner"},
    {name = "Adepto",    key = "adept"},
    {name = "Experiente",key = "expert"},
    {name = "Mestre",    key = "master"},
    {name = "Boss",      key = "boss"}
}

-- ========================================================================
-- FUNCOES AUXILIARES
-- ========================================================================
function formatNumber(num)
    if not num then return "0" end
    num = tonumber(num) or 0
    if num >= 1000000 then
        return string.format("%.1fM", num / 1000000)
    elseif num >= 1000 then
        return string.format("%.1fK", num / 1000)
    end
    return tostring(math.floor(num))
end

function formatGold(num)
    if not num then return "0" end
    num = tonumber(num) or 0
    if num >= 1000000000 then
        local val = num / 1000000000
        if val == math.floor(val) then
            return tostring(math.floor(val)) .. 'kkk'
        end
        return string.format("%.1fkkk", val)
    elseif num >= 1000000 then
        local val = num / 1000000
        if val == math.floor(val) then
            return tostring(math.floor(val)) .. 'kk'
        end
        return string.format("%.1fkk", val)
    elseif num >= 1000 then
        local val = num / 1000
        if val == math.floor(val) then
            return tostring(math.floor(val)) .. 'k'
        end
        return string.format("%.1fk", val)
    end
    return tostring(math.floor(num))
end

function formatNumberFull(num)
    if not num then return "0" end
    num = tonumber(num) or 0
    local s = tostring(math.floor(num))
    local result = ""
    local len = #s
    for i = 1, len do
        result = result .. s:sub(i, i)
        if (len - i) % 3 == 0 and i < len then
            result = result .. "."
        end
    end
    return result
end

-- ========================================================================
-- INICIALIZACAO
-- ========================================================================
function init()
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.registerExtendedOpcode(OPCODE_TASK, parseOpcode)

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    ProtocolGame.unregisterExtendedOpcode(OPCODE_TASK)

    destroyWindow()

    if taskButton then
        taskButton:destroy()
        taskButton = nil
    end
end

function onGameStart()
    createWindow()
    createButton()
end

function onGameEnd()
    destroyWindow()
    if taskButton then
        taskButton:destroy()
        taskButton = nil
    end
    bountyTasks = {}
    talismanData = {}
    weeklyKillTasks = {}
    weeklyDeliveryTasks = {}
    weeklyProgress = {}
    weeklyRewards = {}
    shopItems = {}
    currencies = {taskTokens = 0, silverTokens = 0, goldTokens = 0}
    allDifficultyMonsters = {}
    currentPreferred = {}
    currentUnwanted = {}
    prefMaxSlots = 10
    prefUnlockedTiers = 0
end

-- ========================================================================
-- CRIACAO DA JANELA
-- ========================================================================
function createWindow()
    destroyWindow()

    taskWindow = g_ui.displayUI('tasksystem')
    if taskWindow then
        taskWindow:setVisible(false)
        setupMainTabs()
        setupBountyControls()
        switchTab("bounty")
    end
end

function destroyWindow()
    closePreferredList()
    if taskWindow then
        taskWindow:destroy()
        taskWindow = nil
    end
end

function createButton()
    if taskButton then
        taskButton:destroy()
        taskButton = nil
    end

    -- Botao no painel lateral (mainpanel)
    if modules.game_mainpanel and modules.game_mainpanel.addStoreButton then
        taskButton = modules.game_mainpanel.addStoreButton(
            'taskBoardButton',
            tr('Task Board - Cace monstros e ganhe recompensas!'),
            '/modules/game_tasksystem/images/task_large',
            toggleWindow,
            false
        )
        if taskButton then
            taskButton:setText('Tasks')
            taskButton:setTextOffset(topoint('0 2'))
            taskButton:setFont('verdana-11px-rounded')
            taskButton:setColor('#ffffff')
        end
    end
end

-- ========================================================================
-- COMUNICACAO COM SERVIDOR
-- ========================================================================
function sendOpcode(data)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(OPCODE_TASK, json.encode(data))
    end
end

function parseOpcode(protocol, opcode, buffer)
    local data = json.decode(buffer)
    if not data then return end

    local handlers = {
        -- Bounty Tasks
        bountyTaskList     = onBountyTaskList,
        bountyTaskStarted  = onBountyTaskStarted,
        bountyTaskFinished = onBountyTaskFinished,
        rerollResult       = onRerollResult,
        buyRerollResult    = onBuyRerollResult,
        claimDailyResult   = onClaimDailyResult,
        talismanData       = onTalismanData,
        talismanUpgraded   = onTalismanUpgraded,
        killUpdate         = onKillUpdate,
        -- Lista Preferida
        preferredListData  = onPreferredListData,
        preferredListUpdate= onPreferredListUpdate,
        -- Weekly Tasks
        weeklyTaskList     = onWeeklyTaskList,
        weeklyDeliverResult= onWeeklyDeliverResult,
        weeklyProgressData = onWeeklyProgressData,
        -- Hunting Shop
        shopList           = onShopList,
        shopBuyResult      = onShopBuyResult,
        -- Troca de itens
        exchangeList       = onExchangeList,
        exchangeResult     = onExchangeResult,
        -- Geral
        currencies         = onCurrenciesUpdate,
        message            = onServerMessage,
        -- Abertura remota (servidor pede para abrir o painel, ex: via !task no CIP e no OTC)
        openPanel          = function(data)
            if not taskWindow then createWindow() end
            if taskWindow then
                taskWindow:setVisible(true)
                taskWindow:raise()
                taskWindow:focus()
                switchTab(data.tab or "bounty")
            end
        end,
    }

    local handler = handlers[data.action]
    if handler then
        handler(data)
    end
end

-- ========================================================================
-- ABAS PRINCIPAIS
-- ========================================================================
function setupMainTabs()
    if not taskWindow then return end

    local tabBounty  = taskWindow:recursiveGetChildById('tabBountyTasks')
    local tabWeekly  = taskWindow:recursiveGetChildById('tabWeeklyTasks')
    local tabShop    = taskWindow:recursiveGetChildById('tabHuntingShop')

    if tabBounty then tabBounty.onClick = function() switchTab("bounty") end end
    if tabWeekly then tabWeekly.onClick = function() switchTab("weekly") end end
    if tabShop   then tabShop.onClick   = function() switchTab("shop")   end end
end

function switchTab(tabName)
    if not taskWindow then return end

    currentTab = tabName

    local tabBounty  = taskWindow:recursiveGetChildById('tabBountyTasks')
    local tabWeekly  = taskWindow:recursiveGetChildById('tabWeeklyTasks')
    local tabShop    = taskWindow:recursiveGetChildById('tabHuntingShop')

    local contentBounty = taskWindow:getChildById('bountyTasksContent')
    local contentWeekly = taskWindow:getChildById('weeklyTasksContent')
    local contentShop   = taskWindow:getChildById('huntingShopContent')

    if tabBounty then tabBounty:setOn(tabName == "bounty") end
    if tabWeekly then tabWeekly:setOn(tabName == "weekly") end
    if tabShop   then tabShop:setOn(tabName == "shop")     end

    if contentBounty then contentBounty:setVisible(tabName == "bounty") end
    if contentWeekly then contentWeekly:setVisible(tabName == "weekly") end
    if contentShop   then contentShop:setVisible(tabName == "shop")     end

    -- Solicitar dados ao servidor ao trocar de aba
    if tabName == "bounty" then
        requestBountyData()
    elseif tabName == "weekly" then
        requestWeeklyData()
    elseif tabName == "shop" then
        requestShopData()
        requestExchangeData()
    end
end

-- ========================================================================
-- ABA 1: BOUNTY TASKS
-- ========================================================================
function setupBountyControls()
    if not taskWindow then return end

    local content = taskWindow:getChildById('bountyTasksContent')
    if not content then return end

    -- ComboBox de dificuldade
    local controlBar = content:getChildById('controlBar')
    if controlBar then
        local combo = controlBar:getChildById('difficultyCombo')
        if combo then
            combo:clearOptions()
            for i, diff in ipairs(DIFFICULTIES) do
                combo:addOption(diff.name)
            end
            combo:setCurrentIndex(selectedDifficulty)
            combo.onOptionChange = function(widget)
                selectedDifficulty = widget:getCurrentIndex()
                requestBountyData()
            end
        end

        local preferredBtn = controlBar:getChildById('preferredListBtn')
        if preferredBtn then
            preferredBtn.onClick = function()
                openPreferredList()
            end
        end

        local rerollBtn = controlBar:getChildById('rerollTasksBtn')
        if rerollBtn then
            rerollBtn.onClick = function()
                sendOpcode({action = "rerollBountyTasks", difficulty = DIFFICULTIES[selectedDifficulty].key})
            end
        end

        local buyRerollBtn = controlBar:getChildById('buyRerollBtn')
        if buyRerollBtn then
            buyRerollBtn.onClick = function()
                sendOpcode({action = "buyReroll", amount = 1, difficulty = DIFFICULTIES[selectedDifficulty].key})
            end
        end

        local claimBtn = controlBar:getChildById('claimDailyBtn')
        if claimBtn then
            claimBtn.onClick = function()
                sendOpcode({action = "claimDaily"})
            end
        end
    end

    -- Botoes dos 3 cards
    local cardsPanel = content:getChildById('bountyCardsPanel')
    if cardsPanel then
        for i = 1, 3 do
            local card = cardsPanel:getChildById('bountyCard' .. i)
            if card then
                local selectBtn = card:getChildById('selectButton')
                if selectBtn then
                    selectBtn.onClick = function()
                        selectBountyTask(i)
                    end
                end
                local cancelBtn = card:getChildById('cancelButton')
                if cancelBtn then
                    cancelBtn.onClick = function()
                        cancelBountyTask(i)
                    end
                end
            end
        end
    end

    -- Botoes de upgrade do talisman
    local talismanPanel = content:getChildById('talismanPanel')
    if talismanPanel then
        for i = 1, 4 do
            local slot = talismanPanel:getChildById('talismanSlot' .. i)
            if slot then
                local upgradeBtn = slot:getChildById('upgradeButton')
                if upgradeBtn then
                    upgradeBtn.onClick = function()
                        sendOpcode({action = "upgradeTalisman", slotIndex = i})
                    end
                end
            end
        end
    end
end

function requestBountyData()
    sendOpcode({action = "getBountyTasks", difficulty = DIFFICULTIES[selectedDifficulty].key})
end

function requestCurrencies()
    sendOpcode({action = "requestCurrencies"})
end

function onBountyTaskList(data)
    bountyTasks = data.tasks or {}
    currencies = data.currencies or currencies
    talismanData = data.talisman or talismanData
    updateBountyCards()
    updateTalismanSlots()
    updateBottomBar()

    -- Atualizar contagem de rerolls e custo de compra
    if taskWindow then
        local content = taskWindow:getChildById('bountyTasksContent')
        if content then
            local controlBar = content:getChildById('controlBar')
            if controlBar then
                local countLabel = controlBar:getChildById('rerollCountLabel')
                if countLabel then
                    local rerolls = data.rerolls or 0
                    countLabel:setText(tostring(rerolls))
                    if rerolls <= 0 then
                        countLabel:setColor('#ff4444')
                    elseif rerolls <= 2 then
                        countLabel:setColor('#ffcc00')
                    else
                        countLabel:setColor('#44ee44')
                    end
                end
                local costLabel = controlBar:getChildById('buyRerollCostLabel')
                if costLabel then
                    costLabel:setText(formatGold(data.rerollCost or 10000000) .. ' gold')
                end
            end
        end
    end
end

function updateBountyCards()
    if not taskWindow then return end

    local content = taskWindow:getChildById('bountyTasksContent')
    if not content then return end

    local cardsPanel = content:getChildById('bountyCardsPanel')
    if not cardsPanel then return end

    for i = 1, 3 do
        local card = cardsPanel:getChildById('bountyCard' .. i)
        if card then
            local task = bountyTasks[i]
            if task then
                updateBountyCard(card, task)
                card:setVisible(true)
            else
                card:setVisible(false)
            end
        end
    end
end

function updateBountyCard(card, task)
    if not card or not task then return end

    -- Nome do monstro
    local header = card:getChildById('headerBanner')
    if header then
        local nameLabel = header:getChildById('monsterName')
        if nameLabel then
            nameLabel:setText(task.monsterName or "Desconhecido")
        end
    end

    -- Creature sprite
    local creatureWidget = card:getChildById('monsterCreature')
    if creatureWidget and task.looktype then
        creatureWidget:setOutfit({type = task.looktype})
    end

    -- Kills
    local killsLabel = card:getChildById('killsLabel')
    if killsLabel then
        killsLabel:setText(tostring(task.kills or 0) .. " / " .. tostring(task.total or 0) .. " abates")
    end

    -- Recompensas
    local rewardPanel = card:getChildById('rewardPanel')
    if rewardPanel then
        local expLabel = card:recursiveGetChildById('expReward')
        if expLabel then
            expLabel:setText(formatNumberFull(task.expReward or 0) .. ' XP')
        end

        -- Task Token: texto (icone ja esta fixo no OTUI com item-id 51996)
        local taskTokenLabel = card:recursiveGetChildById('taskTokenReward')
        if taskTokenLabel then
            taskTokenLabel:setText(task.taskTokenText or '')
        end

        -- Random Token: mostra icone Gold ou Silver conforme o tipo
        local goldIcon = card:recursiveGetChildById('randomTokenIconGold')
        local silverIcon = card:recursiveGetChildById('randomTokenIconSilver')
        local GOLD_TOKEN_CLIENT_ID = 22721
        if goldIcon and silverIcon and task.randomTokenId then
            if task.randomTokenId == GOLD_TOKEN_CLIENT_ID then
                goldIcon:setVisible(true)
                silverIcon:setVisible(false)
            else
                goldIcon:setVisible(false)
                silverIcon:setVisible(true)
            end
        end

        local randomTokenLabel = card:recursiveGetChildById('randomTokenReward')
        if randomTokenLabel then
            randomTokenLabel:setText(task.randomTokenText or '')
            -- Cor diferente: gold token = dourado, silver token = prata
            if task.randomTokenId == GOLD_TOKEN_CLIENT_ID then
                randomTokenLabel:setColor('#ffcc00')
            else
                randomTokenLabel:setColor('#c0c0c0')
            end
        end
    end

    -- Botoes de selecao e cancelar
    local selectBtn = card:getChildById('selectButton')
    local cancelBtn = card:getChildById('cancelButton')
    if selectBtn and cancelBtn then
        if task.started then
            if (task.kills or 0) >= (task.total or 1) then
                selectBtn:setText(tr('Resgatar'))
                selectBtn:setEnabled(true)
                cancelBtn:setVisible(false)
                selectBtn:removeAnchor(AnchorLeft)
                selectBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
                selectBtn:setMarginLeft(8)
            else
                selectBtn:setText(tr('Em Progresso'))
                selectBtn:setEnabled(false)
                cancelBtn:setVisible(true)
                selectBtn:removeAnchor(AnchorLeft)
                selectBtn:addAnchor(AnchorLeft, 'cancelButton', AnchorRight)
                selectBtn:setMarginLeft(4)
            end
        else
            selectBtn:setText(tr('Selecionar Tarefa'))
            selectBtn:setEnabled(true)
            cancelBtn:setVisible(false)
            selectBtn:removeAnchor(AnchorLeft)
            selectBtn:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            selectBtn:setMarginLeft(8)
        end
    end
end

function selectBountyTask(index)
    local task = bountyTasks[index]
    if not task then return end

    if task.started and (task.kills or 0) >= (task.total or 1) then
        sendOpcode({action = "finishBountyTask", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = task.monsterId})
    elseif not task.started then
        sendOpcode({action = "startBountyTask", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = task.monsterId})
    end
end

function cancelBountyTask(index)
    local task = bountyTasks[index]
    if not task then return end

    if task.started and (task.kills or 0) < (task.total or 1) then
        sendOpcode({action = "cancelBountyTask", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = task.monsterId})
    end
end

function onBountyTaskStarted(data)
    showMessage(data.message or "Tarefa iniciada!")
    -- Servidor ja envia bountyTaskList atualizado apos iniciar
end

function onBountyTaskFinished(data)
    showMessage(data.message or "Tarefa concluida! Recompensa resgatada!")
    -- Servidor ja envia bountyTaskList atualizado apos finalizar
end

function onRerollResult(data)
    if data.success then
        bountyTasks = data.tasks or bountyTasks
        currencies = data.currencies or currencies
        updateBountyCards()
        updateBottomBar()
        showMessage("Tarefas reroladas com sucesso!")
    else
        showMessage(data.message or "Erro ao rerollar tarefas!")
    end
end

function onBuyRerollResult(data)
    if data.success then
        showMessage(data.message or "Reroll comprado com sucesso!")
        -- Atualizar contagem de rerolls
        if taskWindow then
            local content = taskWindow:getChildById('bountyTasksContent')
            if content then
                local controlBar = content:getChildById('controlBar')
                if controlBar then
                    local countLabel = controlBar:getChildById('rerollCountLabel')
                    if countLabel then
                        local rerolls = data.rerolls or 0
                        countLabel:setText(tostring(rerolls))
                        if rerolls <= 0 then
                            countLabel:setColor('#ff4444')
                        elseif rerolls <= 2 then
                            countLabel:setColor('#ffcc00')
                        else
                            countLabel:setColor('#44ee44')
                        end
                    end
                end
            end
        end
    else
        showMessage(data.message or "Erro ao comprar reroll!")
    end
end
function onClaimDailyResult(data)
    showMessage(data.message or "Diaria coletada!")
    currencies = data.currencies or currencies
    updateBottomBar()
end

function onKillUpdate(data)
    if not data.monsterId then return end
    for i, task in ipairs(bountyTasks) do
        if task.monsterId == data.monsterId then
            task.kills = data.kills
            task.total = data.total
            break
        end
    end
    if currentTab == "bounty" then
        updateBountyCards()
    end
end

-- ========================================================================
-- LISTA PREFERIDA
-- ========================================================================
function openPreferredList()
    sendOpcode({action = "openPreferredList", difficulty = DIFFICULTIES[selectedDifficulty].key})
end

function closePreferredList()
    if preferredListWindow then
        preferredListWindow:destroy()
        preferredListWindow = nil
    end
end

function onPreferredListData(data)
    allDifficultyMonsters = data.monsters or {}
    currentPreferred = data.preferred or {}
    currentUnwanted = data.unwanted or {}
    prefMaxSlots = data.maxSlots or 10
    prefUnlockedTiers = data.unlockedTiers or 0
    showPreferredListWindow()
end

function onPreferredListUpdate(data)
    currentPreferred = data.preferred or currentPreferred
    currentUnwanted = data.unwanted or currentUnwanted
    prefMaxSlots = data.maxSlots or prefMaxSlots
    prefUnlockedTiers = data.unlockedTiers or prefUnlockedTiers
    if preferredListWindow then
        populateMonsterList()
        updatePreferredSlots()
        updateUnwantedSlots()
        updateAdditionalSlots()
    end
end

function showPreferredListWindow()
    if preferredListWindow then
        preferredListWindow:destroy()
        preferredListWindow = nil
    end

    preferredListWindow = g_ui.createWidget('PreferredListWindow', g_ui.getRootWidget())
    if not preferredListWindow then return end

    setupPreferredControls()
    populateMonsterList()
    updatePreferredSlots()
    updateUnwantedSlots()
    updateAdditionalSlots()

    preferredListWindow:setVisible(true)
    preferredListWindow:raise()
    preferredListWindow:focus()
end

function setupPreferredControls()
    if not preferredListWindow then return end

    -- Busca
    local searchInput = preferredListWindow:recursiveGetChildById('searchInput')
    if searchInput then
        searchInput.onTextChange = function(widget, text, oldText)
            populateMonsterList()
        end
    end

    local clearSearchBtn = preferredListWindow:recursiveGetChildById('clearSearchBtn')
    if clearSearchBtn then
        clearSearchBtn.onClick = function()
            if searchInput then
                searchInput:setText('')
            end
            populateMonsterList()
        end
    end

    -- Limpar Preferidos
    local clearPrefBtn = preferredListWindow:recursiveGetChildById('clearPreferredBtn')
    if clearPrefBtn then
        clearPrefBtn.onClick = function()
            sendOpcode({action = "clearPreferred", difficulty = DIFFICULTIES[selectedDifficulty].key})
        end
    end

    -- Limpar Indesejados
    local clearUnwBtn = preferredListWindow:recursiveGetChildById('clearUnwantedBtn')
    if clearUnwBtn then
        clearUnwBtn.onClick = function()
            sendOpcode({action = "clearUnwanted", difficulty = DIFFICULTIES[selectedDifficulty].key})
        end
    end

    -- Fechar
    local closeBtn = preferredListWindow:getChildById('closePreferredBtn')
    if closeBtn then
        closeBtn.onClick = function()
            closePreferredList()
        end
    end
end

function populateMonsterList()
    if not preferredListWindow then return end

    local scrollArea = preferredListWindow:recursiveGetChildById('monsterScrollArea')
    if not scrollArea then return end

    -- Limpar lista
    local children = scrollArea:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Ler filtro de busca
    local filter = ""
    local searchInput = preferredListWindow:recursiveGetChildById('searchInput')
    if searchInput then
        filter = (searchInput:getText() or ""):lower()
    end

    -- Sets para lookup rapido
    local prefSet = {}
    for _, m in ipairs(currentPreferred) do
        prefSet[m.monsterId] = true
    end
    local unwantedSet = {}
    for _, m in ipairs(currentUnwanted) do
        unwantedSet[m.monsterId] = true
    end

    for _, monster in ipairs(allDifficultyMonsters) do
        local name = monster.name or ""
        if filter == "" or name:lower():find(filter, 1, true) then
            local row = g_ui.createWidget('PreferredMonsterRow', scrollArea)
            if row then
                local creature = row:getChildById('creatureSprite')
                if creature and monster.looktype then
                    creature:setOutfit({type = monster.looktype})
                end

                local nameLabel = row:getChildById('monsterNameLabel')
                if nameLabel then
                    nameLabel:setText(name)
                    if prefSet[monster.id] then
                        nameLabel:setColor('#44ee44')
                    elseif unwantedSet[monster.id] then
                        nameLabel:setColor('#ff4444')
                    else
                        nameLabel:setColor('#cccccc')
                    end
                end

                local mId = monster.id
                local mInPref = prefSet[mId]
                local mInUnw = unwantedSet[mId]

                -- Clique esquerdo: preferidos | Clique direito: indesejados
                row.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseLeftButton then
                        if mInPref then
                            sendOpcode({action = "removePreferred", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = mId})
                        else
                            sendOpcode({action = "addPreferred", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = mId})
                        end
                        return true
                    elseif mouseButton == MouseRightButton then
                        if mInUnw then
                            sendOpcode({action = "removeUnwanted", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = mId})
                        else
                            sendOpcode({action = "addUnwanted", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = mId})
                        end
                        return true
                    end
                    return false
                end
            end
        end
    end
end

function updatePreferredSlots()
    if not preferredListWindow then return end

    local grid = preferredListWindow:recursiveGetChildById('preferredGrid')
    if not grid then return end

    -- Limpar slots
    local children = grid:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Criar slots
    for i = 1, prefMaxSlots do
        local slot = g_ui.createWidget('PreferredCreatureSlot', grid)
        if slot then
            local monster = currentPreferred[i]
            if monster then
                local creature = slot:getChildById('slotCreature')
                if creature then
                    creature:setOutfit({type = monster.looktype})
                    creature:setVisible(true)
                end
                local mId = monster.monsterId
                slot.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseLeftButton then
                        sendOpcode({action = "removePreferred", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = mId})
                        return true
                    end
                    return false
                end
            end
        end
    end

    -- Atualizar contador
    local countLabel = preferredListWindow:recursiveGetChildById('preferredCountLabel')
    if countLabel then
        countLabel:setText(tostring(#currentPreferred) .. "/" .. tostring(prefMaxSlots))
    end
end

function updateUnwantedSlots()
    if not preferredListWindow then return end

    local grid = preferredListWindow:recursiveGetChildById('unwantedGrid')
    if not grid then return end

    -- Limpar slots
    local children = grid:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Criar slots
    for i = 1, prefMaxSlots do
        local slot = g_ui.createWidget('PreferredCreatureSlot', grid)
        if slot then
            local monster = currentUnwanted[i]
            if monster then
                local creature = slot:getChildById('slotCreature')
                if creature then
                    creature:setOutfit({type = monster.looktype})
                    creature:setVisible(true)
                end
                local mId = monster.monsterId
                slot.onMouseRelease = function(widget, mousePos, mouseButton)
                    if mouseButton == MouseLeftButton then
                        sendOpcode({action = "removeUnwanted", difficulty = DIFFICULTIES[selectedDifficulty].key, monsterId = mId})
                        return true
                    end
                    return false
                end
            end
        end
    end

    -- Atualizar contador
    local countLabel = preferredListWindow:recursiveGetChildById('unwantedCountLabel')
    if countLabel then
        countLabel:setText(tostring(#currentUnwanted) .. "/" .. tostring(prefMaxSlots))
    end
end

function updateAdditionalSlots()
    if not preferredListWindow then return end

    local panel = preferredListWindow:recursiveGetChildById('additionalSlotsPanel')
    if not panel then return end

    -- Limpar rows
    local children = panel:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    local costs = {300, 600, 900, 1200}

    for tier = 1, 4 do
        local row = g_ui.createWidget('PreferredUnlockRow', panel)
        if row then
            local costLabel = row:getChildById('unlockCostLabel')
            if costLabel then
                costLabel:setText(tostring(costs[tier]))
            end

            local countLabel = row:getChildById('unlockSlotsCount')
            if countLabel then
                countLabel:setText("+" .. tostring(tier * 5))
            end

            local btn = row:getChildById('unlockBtn')
            if btn then
                if tier <= prefUnlockedTiers then
                    btn:setText(tr('Desbloqueado'))
                    btn:setEnabled(false)
                    if costLabel then
                        costLabel:setColor('#666666')
                    end
                else
                    local tierIdx = tier
                    btn.onClick = function()
                        sendOpcode({action = "unlockPrefSlots", difficulty = DIFFICULTIES[selectedDifficulty].key, tier = tierIdx})
                    end
                end
            end
        end
    end
end

-- ID do Silver Token no cliente (para icone do talisma)
local SILVER_TOKEN_CLIENT_ID = 22516

-- Talisman
function updateTalismanSlots()
    if not taskWindow then return end

    local content = taskWindow:getChildById('bountyTasksContent')
    if not content then return end

    local talismanPanel = content:getChildById('talismanPanel')
    if not talismanPanel then return end

    local slotNames = {
        "Dano Contra Criaturas",
        "Dano Reduzido Recebido",
        "Mais Loot",
        "Chance de Bestiario Duplo"
    }

    for i = 1, 4 do
        local slot = talismanPanel:getChildById('talismanSlot' .. i)
        if slot then
            local data = talismanData[i] or {}

            local nameLabel = slot:getChildById('talismanName')
            if nameLabel then
                nameLabel:setText(slotNames[i] or ("Slot " .. i))
            end

            local valueLabel = slot:getChildById('talismanValue')
            if valueLabel then
                valueLabel:setText("Atual: " .. tostring(data.currentValue or "0%"))
            end

            local upgradeBtn = slot:getChildById('upgradeButton')
            if upgradeBtn then
                if data.canUpgrade then
                    upgradeBtn:setText(tr('Melhorar'))
                else
                    upgradeBtn:setText(tr('Maximo'))
                end
                upgradeBtn:setEnabled(data.canUpgrade ~= false)
            end

            -- Icone de Silver Token no custo
            local costIcon = slot:getChildById('upgradeCostIcon')
            if costIcon then
                if data.canUpgrade and data.cost and data.cost > 0 then
                    costIcon:setItemId(SILVER_TOKEN_CLIENT_ID)
                    costIcon:setVisible(true)
                else
                    costIcon:setVisible(false)
                end
            end

            local costLabel = slot:getChildById('upgradeCost')
            if costLabel then
                if data.canUpgrade and data.cost and data.cost > 0 then
                    costLabel:setText(tostring(data.cost))
                else
                    costLabel:setText('')
                end
            end
        end
    end
end

function onTalismanData(data)
    talismanData = data.slots or {}
    updateTalismanSlots()
end

function onTalismanUpgraded(data)
    if data.success then
        showMessage(data.message or "Talisma melhorado!")
        talismanData = data.slots or talismanData
        currencies = data.currencies or currencies
        updateTalismanSlots()
        updateBottomBar()
    else
        showMessage(data.message or "Erro ao melhorar talisma!")
    end
end

-- ========================================================================
-- ABA 2: WEEKLY TASKS
-- ========================================================================
function requestWeeklyData()
    sendOpcode({action = "getWeeklyTasks"})
end

function onWeeklyTaskList(data)
    weeklyKillTasks = data.killTasks or {}
    weeklyDeliveryTasks = data.deliveryTasks or {}
    weeklyProgress = data.progress or {}
    weeklyRewards = data.rewards or {}
    currencies = data.currencies or currencies

    updateWeeklyKillCards()
    updateWeeklyDeliveryCards()
    updateWeeklyProgress()
    updateWeeklyRewards()
    updateBottomBar()

    -- XP por task
    if taskWindow then
        local content = taskWindow:getChildById('weeklyTasksContent')
        if content then
            local xpLabel = content:getChildById('weeklyXpLabel')
            if xpLabel then
                xpLabel:setText("Cada task recompensa voce com " .. formatNumberFull(data.xpPerTask or 0) .. " XP.")
            end
        end
    end
end

function updateWeeklyKillCards()
    if not taskWindow then return end

    local content = taskWindow:getChildById('weeklyTasksContent')
    if not content then return end

    local section = content:getChildById('killTasksSection')
    if not section then return end

    local grid = section:getChildById('killTasksGrid')
    if not grid then return end

    -- Limpar cards existentes
    local children = grid:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Criar 6 kill task cards
    for i = 1, 6 do
        local task = weeklyKillTasks[i]
        local card = g_ui.createWidget('WeeklyKillCard', grid)
        if card and task then
            local nameLabel = card:getChildById('monsterName')
            if nameLabel then
                nameLabel:setText(task.monsterName or "")
            end

            local creature = card:getChildById('creature')
            if creature and task.looktype then
                creature:setOutfit({type = task.looktype})
            end

            local killProgress = card:getChildById('killProgress')
            if killProgress then
                killProgress:setText(tostring(task.kills or 0))
                if (task.kills or 0) >= (task.total or 1) then
                    killProgress:setColor("#00ff00")
                else
                    killProgress:setColor("#ff4444")
                end
            end

            local killsOf = card:getChildById('killsOf')
            if killsOf then
                killsOf:setText("de " .. tostring(task.total or 0))
            end
        elseif card then
            card:setVisible(false)
        end
    end
end

function updateWeeklyDeliveryCards()
    if not taskWindow then return end

    local content = taskWindow:getChildById('weeklyTasksContent')
    if not content then return end

    local section = content:getChildById('deliveryTasksSection')
    if not section then return end

    local grid = section:getChildById('deliveryTasksGrid')
    if not grid then return end

    -- Limpar cards existentes
    local children = grid:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Criar 6 delivery task cards
    for i = 1, 6 do
        local task = weeklyDeliveryTasks[i]
        local card = g_ui.createWidget('WeeklyDeliveryCard', grid)
        if card and task then
            local nameLabel = card:getChildById('itemName')
            if nameLabel then
                nameLabel:setText(task.itemName or "")
            end

            local itemWidget = card:getChildById('itemWidget')
            if itemWidget and task.itemId then
                itemWidget:setItemId(task.itemId)
            end

            local countLabel = card:getChildById('deliveryCount')
            if countLabel then
                countLabel:setText("de " .. tostring(task.total or 0))
            end

            local deliverBtn = card:getChildById('deliverButton')
            if deliverBtn then
                local taskIndex = i
                deliverBtn.onClick = function()
                    sendOpcode({action = "deliverWeeklyTask", index = taskIndex})
                end
                deliverBtn:setEnabled(task.canDeliver == true)
            end
        elseif card then
            card:setVisible(false)
        end
    end
end

function updateWeeklyProgress()
    if not taskWindow then return end

    local content = taskWindow:getChildById('weeklyTasksContent')
    if not content then return end

    local progressPanel = content:getChildById('weeklyProgressPanel')
    if not progressPanel then return end

    -- Atualizar barra de progresso
    local bgBar = progressPanel:getChildById('progressBarBg')
    if bgBar then
        local fillBar = bgBar:getChildById('progressBarFill')
        if fillBar then
            local completed = weeklyProgress.completedTasks or 0
            local maxTasks = weeklyProgress.maxTasks or 18
            local percent = math.min(1, completed / math.max(1, maxTasks))
            local totalWidth = bgBar:getWidth() - 2
            fillBar:setWidth(math.floor(totalWidth * percent))
        end
    end
end

function updateWeeklyRewards()
    if not taskWindow then return end

    local content = taskWindow:getChildById('weeklyTasksContent')
    if not content then return end

    local rewardsPanel = content:getChildById('weeklyRewardsPanel')
    if not rewardsPanel then return end

    local r1Panel = rewardsPanel:getChildById('weeklyReward1')
    if r1Panel then
        local r1Value = r1Panel:getChildById('reward1Value')
        if r1Value then
            r1Value:setText(tostring(weeklyRewards.gold or 0))
        end
    end

    local r2Panel = rewardsPanel:getChildById('weeklyReward2')
    if r2Panel then
        local r2Value = r2Panel:getChildById('reward2Value')
        if r2Value then
            r2Value:setText(tostring(weeklyRewards.items or 0))
        end
    end
end

function onWeeklyDeliverResult(data)
    showMessage(data.message or "Entrega realizada!")
    if data.success then
        requestWeeklyData()
    end
end

function onWeeklyProgressData(data)
    weeklyProgress = data.progress or weeklyProgress
    updateWeeklyProgress()
end

-- ========================================================================
-- ABA 3: HUNTING TASK SHOP
-- ========================================================================
function requestShopData()
    sendOpcode({action = "getShopList"})
end

function onShopList(data)
    print("[Task Shop] Recebido shopList do servidor com " .. #(data.items or {}) .. " itens")
    shopItems = data.items or {}
    currencies = data.currencies or currencies
    updateShopGrid()
    updateBottomBar()
end

function updateShopGrid()
    if not taskWindow then return end

    local content = taskWindow:getChildById('huntingShopContent')
    if not content then return end

    local scrollPanel = content:getChildById('shopScrollPanel')
    if not scrollPanel then return end

    -- Limpar itens existentes
    local children = scrollPanel:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Se nao tem itens, mostrar mensagem
    if #shopItems == 0 then
        local emptyLabel = g_ui.createWidget('Label', scrollPanel)
        if emptyLabel then
            emptyLabel:setId('emptyShopLabel')
            emptyLabel:setText('Nenhum item disponivel. Reinicie o servidor para carregar a loja.')
            emptyLabel:setColor('#aaaaaa')
            emptyLabel:setTextAlign(AlignCenter)
            emptyLabel:setFont('verdana-11px-rounded')
        end
        return
    end

    -- Criar cards de shop com dados do servidor
    for i, item in ipairs(shopItems) do
        local card = g_ui.createWidget('ShopItemCard', scrollPanel)
        if card then
            -- Icone do item via UIItem
            local itemIcon = card:getChildById('shopItemIcon')
            if itemIcon and item.id then
                itemIcon:setItemId(item.id)
            end

            -- Nome do item (vindo do servidor)
            local nameLabel = card:getChildById('shopItemName')
            if nameLabel then
                nameLabel:setText(item.name or "Item")
            end

            -- Preco em Task Tokens (linha verde com icone)
            local priceInfo = card:getChildById('shopPriceInfo')
            if priceInfo then
                priceInfo:setText(tostring(item.price or 0) .. 'x Task Token')
            end

            -- Sistema de quantidade
            local qty = 1
            local unitPrice = item.price or 0
            local qtyLabel = card:getChildById('qtyLabel')
            local totalCostLabel = card:getChildById('totalCostLabel')
            local buyBtn = card:getChildById('buyButton')

            local function updateQtyDisplay()
                if qtyLabel then qtyLabel:setText(tostring(qty)) end
                if totalCostLabel then totalCostLabel:setText('= ' .. tostring(qty * unitPrice)) end
            end
            updateQtyDisplay()

            local minusBtn = card:getChildById('qtyMinusBtn')
            if minusBtn then
                minusBtn.onClick = function()
                    if qty > 1 then
                        qty = qty - 1
                        updateQtyDisplay()
                    end
                end
            end

            local plusBtn = card:getChildById('qtyPlusBtn')
            if plusBtn then
                plusBtn.onClick = function()
                    if qty < 100 then
                        qty = qty + 1
                        updateQtyDisplay()
                    end
                end
            end

            -- Botao de compra
            if buyBtn then
                local itemId = item.id
                buyBtn.onClick = function()
                    sendOpcode({action = "buyShopItem", itemId = itemId, amount = qty})
                end
                buyBtn:setEnabled(item.canBuy ~= false)
            end
        end
    end
end

function onShopBuyResult(data)
    if data.success then
        showMessage(data.message or "Item comprado com sucesso!")
        currencies = data.currencies or currencies
        updateBottomBar()
        requestShopData()
        requestExchangeData()
    else
        showMessage(data.message or "Erro ao comprar item!")
    end
end

-- ========================================================================
-- TROCA DE ITENS POR MYSTIC TOKENS
-- ========================================================================
function requestExchangeData()
    sendOpcode({action = "getExchangeList"})
end

function onExchangeList(data)
    exchangeItems = data.items or {}
    currencies = data.currencies or currencies
    updateExchangeGrid()
    updateBottomBar()
end

function updateExchangeGrid()
    if not taskWindow then return end

    local content = taskWindow:getChildById('huntingShopContent')
    if not content then return end

    local scrollPanel = content:getChildById('exchangeScrollPanel')
    if not scrollPanel then return end

    -- Limpar itens existentes
    local children = scrollPanel:getChildren()
    for _, child in ipairs(children) do
        child:destroy()
    end

    -- Se nao tem itens, mostrar mensagem
    if #exchangeItems == 0 then
        local emptyLabel = g_ui.createWidget('Label', scrollPanel)
        if emptyLabel then
            emptyLabel:setText('Nenhum item trocavel no seu inventario.')
            emptyLabel:setColor('#888888')
            emptyLabel:setTextAlign(AlignCenter)
            emptyLabel:setFont('verdana-11px-rounded')
            emptyLabel:setHeight(30)
        end
        return
    end

    -- Criar linhas de itens trocaveis
    for i, item in ipairs(exchangeItems) do
        local row = g_ui.createWidget('ExchangeItemRow', scrollPanel)
        if row then
            local maxCount = item.count or 1
            local pricePerUnit = item.tokenPrice or 0
            local itemId = item.id

            -- Icone do item
            local itemIcon = row:getChildById('exchangeItemIcon')
            if itemIcon and itemId then
                itemIcon:setItemId(itemId)
            end

            -- Nome completo do item
            local nameLabel = row:getChildById('exchangeItemName')
            if nameLabel then
                nameLabel:setText(item.name or "Item")
            end

            -- Quantidade que possui
            local countLabel = row:getChildById('exchangeItemCount')
            if countLabel then
                countLabel:setText('Possui: ' .. tostring(maxCount))
            end

            -- Campo de quantidade
            local qtyInput = row:getChildById('exchangeQtyInput')
            if qtyInput then
                qtyInput:setText(tostring(maxCount))
            end

            -- Funcao para atualizar preco com base na quantidade
            local function updateRowPrice()
                if not qtyInput then return end
                local qty = tonumber(qtyInput:getText()) or 1
                if qty < 1 then qty = 1 end
                if qty > maxCount then qty = maxCount end
                qtyInput:setText(tostring(qty))
                local priceLabel = row:getChildById('exchangeItemPrice')
                if priceLabel then
                    priceLabel:setText(tostring(qty * pricePerUnit))
                end
            end

            -- Botao -
            local minusBtn = row:getChildById('exchangeMinusBtn')
            if minusBtn then
                minusBtn.onClick = function()
                    local qty = tonumber(qtyInput:getText()) or 1
                    qty = math.max(1, qty - 1)
                    qtyInput:setText(tostring(qty))
                    updateRowPrice()
                end
            end

            -- Botao +
            local plusBtn = row:getChildById('exchangePlusBtn')
            if plusBtn then
                plusBtn.onClick = function()
                    local qty = tonumber(qtyInput:getText()) or 1
                    qty = math.min(maxCount, qty + 1)
                    qtyInput:setText(tostring(qty))
                    updateRowPrice()
                end
            end

            -- Atualizar preco ao digitar no campo
            if qtyInput then
                qtyInput.onTextChange = function()
                    updateRowPrice()
                end
            end

            -- Preco inicial
            updateRowPrice()

            -- Botao de trocar
            local exchangeBtn = row:getChildById('exchangeButton')
            if exchangeBtn then
                exchangeBtn.onClick = function()
                    local qty = tonumber(qtyInput:getText()) or 1
                    if qty < 1 then qty = 1 end
                    if qty > maxCount then qty = maxCount end
                    sendOpcode({action = "exchangeItem", itemId = itemId, amount = qty})
                end
            end
        end
    end
end

function onExchangeResult(data)
    if data.success then
        showMessage(data.message or "Troca realizada com sucesso!")
        currencies = data.currencies or currencies
        updateBottomBar()
        requestExchangeData()
    else
        showMessage(data.message or "Erro ao trocar item!")
    end
end

-- ========================================================================
-- BARRA INFERIOR (moedas)
-- ========================================================================
function updateBottomBar()
    if not taskWindow then return end

    local taskLabel = taskWindow:recursiveGetChildById('taskTokensValue')
    if taskLabel then
        taskLabel:setText(formatNumberFull(currencies.taskTokens or 0))
    end

    local silverLabel = taskWindow:recursiveGetChildById('silverTokensValue')
    if silverLabel then
        silverLabel:setText(formatNumberFull(currencies.silverTokens or 0))
    end

    local goldTokenLabel = taskWindow:recursiveGetChildById('goldTokensValue')
    if goldTokenLabel then
        goldTokenLabel:setText(formatNumberFull(currencies.goldTokens or 0))
    end
end

function onCurrenciesUpdate(data)
    currencies = {
        taskTokens   = data.taskTokens or currencies.taskTokens,
        silverTokens = data.silverTokens or currencies.silverTokens,
        goldTokens   = data.goldTokens or currencies.goldTokens
    }
    updateBottomBar()
end

-- ========================================================================
-- MENSAGENS
-- ========================================================================
function onServerMessage(data)
    showMessage(data.text or "", data.color)
end

function showMessage(text, color)
    -- Exibir via modules.game_textmessage se disponivel, senao log
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
        modules.game_textmessage.displayStatusMessage(text)
    else
        print("[Task Board] " .. tostring(text))
    end
end

-- ========================================================================
-- JANELA
-- ========================================================================
function toggleWindow()
    if not g_game.isOnline() then
        return
    end

    if not taskWindow then
        createWindow()
    end

    if taskWindow then
        if taskWindow:isVisible() then
            taskWindow:setVisible(false)
        else
            taskWindow:setVisible(true)
            taskWindow:raise()
            taskWindow:focus()
            -- Atualizar currencies ao abrir
            requestCurrencies()
            -- Recarregar dados da aba ativa
            if currentTab == "bounty" then
                requestBountyData()
            elseif currentTab == "weekly" then
                requestWeeklyData()
            elseif currentTab == "shop" then
                requestShopData()
                requestExchangeData()
            end
        end
    end
end
