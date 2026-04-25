-- Gem System OTC module
-- Janela unificada para operacoes de gem slot (insert/swap/destroy/createSlot).
-- Comunica com o servidor via extended opcode 109.
-- Autoridade: servidor. Cliente apenas renderiza snapshots.

local CODE = 109

local window = nil
local tabsPanel = nil
local centerPanel = nil
local rightList = nil
local rightInfoPanel = nil
local itemsList = nil

local fetchInFlight = false
local lastFetchRequestMs = 0
local FETCH_REQUEST_COOLDOWN_MS = 1500

local selectedTab = "insert"
local selectedItemUid = 0
local selectedSlot = nil
local selectedGemId = nil

local playerItems = {}
local playerGems = {}
local playerMoney = 0
local lunarRelicCount = 0
local lunarRelicClientId = 40912
local currentItem = nil

local TAB_LABELS = {
    insert = "Insert",
    swap = "Swap",
    destroy = "Destroy",
    createSlot = "Create Slot",
}

local TAB_ICONS = {
    insert = 63241,
    swap = 63245,
    destroy = 63249,
    createSlot = 40912,
}

local TAB_DESCRIPTIONS = {
    insert = "Selecione um slot vazio e uma gema para inseri-la.",
    swap = "Selecione um slot preenchido e uma gema de nivel igual ou superior para substituir. A gema antiga retorna ao seu inventario.",
    destroy = "Selecione um slot preenchido para destruir a gema. A gema nao retorna ao inventario.",
    createSlot = "Crie um novo gem slot consumindo 1 Lunar Relic + o custo progressivo em gold.",
}

local TAB_WARNINGS = {
    destroy = "ATENCAO: A gema sera DESTRUIDA e NAO retornara ao inventario.",
}

local GOLD_ITEM_ID = 3031

-- =============================================================================
-- Utils
-- =============================================================================

local function nowMs()
    return (g_clock and g_clock.millis and g_clock.millis()) or 0
end

local function commaValue(amount)
    local formatted = tostring(amount or 0)
    while true do
        local replaced
        formatted, replaced = string.gsub(formatted, "^(-?%d+)(%d%d%d)", "%1.%2")
        if replaced == 0 then
            break
        end
    end
    return formatted
end

local function uiItemSpriteId(rawId)
    local id = tonumber(rawId) or 0
    if id <= 0 then
        return 0
    end
    if g_things and g_things.getThingType then
        local tt = g_things.getThingType(id, ThingCategoryItem)
        if tt and tt.getId then
            local tid = tt:getId()
            if tid and tid > 0 then
                return tid
            end
        end
    end
    return id
end

local function sendOpcode(payload)
    local protocolGame = g_game.getProtocolGame()
    if not protocolGame then
        return false
    end
    protocolGame:sendExtendedOpcode(CODE, json.encode(payload))
    return true
end

local function confirm(message, onConfirm)
    if type(displayGeneralBox) == "function" then
        local box
        local buttons = {
            { text = tr("Confirm"), callback = function()
                if box then box:destroy() end
                onConfirm()
            end },
            { text = tr("Cancel"), callback = function()
                if box then box:destroy() end
            end },
        }
        box = displayGeneralBox(tr("Gem System"), message, buttons, buttons[1].callback, buttons[2].callback)
        return
    end
    onConfirm()
end

-- =============================================================================
-- Lifecycle
-- =============================================================================

function init()
    connect(g_game, { onGameStart = create, onGameEnd = destroy })

    ProtocolGame.registerExtendedOpcode(CODE, onExtendedOpcode)

    if g_game.isOnline() then
        create()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = create, onGameEnd = destroy })

    ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)

    destroy()
end

function create()
    if window then
        return
    end

    window = g_ui.displayUI("game_gem_system")
    window:hide()

    tabsPanel = window:getChildById("tabs")
    centerPanel = window:getChildById("centerPanel")
    itemsList = window:getChildById("itemsList")
    rightList = window:getChildById("rightList")
    rightInfoPanel = window:getChildById("rightInfoPanel")
end

function destroy()
    if window then
        tabsPanel = nil
        centerPanel = nil
        itemsList = nil
        rightList = nil
        rightInfoPanel = nil

        selectedTab = "insert"
        selectedItemUid = 0
        selectedSlot = nil
        selectedGemId = nil
        playerItems = {}
        playerGems = {}
        playerMoney = 0
        lunarRelicCount = 0
        currentItem = nil
        fetchInFlight = false

        window:destroy()
        window = nil
    end
end

-- =============================================================================
-- Opcode
-- =============================================================================

function requestFetch()
    local now = nowMs()
    if fetchInFlight and now - lastFetchRequestMs < FETCH_REQUEST_COOLDOWN_MS then
        return
    end
    lastFetchRequestMs = now
    fetchInFlight = true

    if not sendOpcode({ action = "fetch", data = { uid = selectedItemUid or 0 } }) then
        fetchInFlight = false
    end
end

function onExtendedOpcode(protocol, code, buffer)
    if not window then
        return false
    end

    local status, payload = pcall(function() return json.decode(buffer) end)
    if not status or type(payload) ~= "table" then
        return false
    end

    local action = payload.action
    local data = payload.data

    if action == "items" then
        playerItems = data or {}
        refreshItemsList()
        return true
    end

    if action == "gems" then
        playerGems = data or {}
        refreshRightPanel()
        return true
    end

    if action == "money" then
        playerMoney = tonumber(data) or 0
        refreshBalance()
        return true
    end

    if action == "relic" then
        if data then
            lunarRelicCount = tonumber(data.count) or 0
            lunarRelicClientId = tonumber(data.clientId) or 40912
            refreshRightPanel()
        end
        return true
    end

    if action == "item" then
        currentItem = data
        if data and data.uid then
            selectedItemUid = data.uid
        end
        refreshCenterPanel()
        refreshRightPanel()
        return true
    end

    if action == "show" then
        fetchInFlight = false
        if data then
            selectedItemUid = tonumber(data.uid) or 0
            if data.tab and TAB_LABELS[data.tab] then
                selectedTab = data.tab
            end
        end
        applyTabButtons()
        refreshCenterPanel()
        refreshRightPanel()
        show()
        return true
    end

    if action == "result" then
        fetchInFlight = false
        if data then
            local msg = data.message or ""
            if msg ~= "" then
                if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
                    modules.game_textmessage.displayGameMessage(msg)
                else
                    g_logger.info("[GemSystem] " .. msg)
                end
            end
            if not data.ok then
                selectedSlot = nil
            end
        end
        return true
    end

    return false
end

-- =============================================================================
-- UI refresh
-- =============================================================================

function applyTabButtons()
    if not tabsPanel then return end
    for tabKey, _ in pairs(TAB_LABELS) do
        local btnId = "tab" .. (tabKey:gsub("^%l", string.upper))
        local btn = tabsPanel:getChildById(btnId)
        if btn and btn.setOn then
            btn:setOn(tabKey == selectedTab)
        end
    end
end

function refreshItemsList()
    if not itemsList then return end
    itemsList:destroyChildren()

    for _, entry in ipairs(playerItems) do
        local w = g_ui.createWidget("GemItemListEntry", itemsList)
        w:setId(tostring(entry.uid))
        local itemWidget = w:getChildById("item")
        if itemWidget then
            itemWidget:setItemId(uiItemSpriteId(entry.clientId or entry.itemId))
        end
        local nameWidget = w:getChildById("name")
        if nameWidget then
            nameWidget:setText(entry.name or ("item " .. tostring(entry.itemId)))
        end
        local slotsWidget = w:getChildById("slots")
        if slotsWidget then
            slotsWidget:setText(string.format("Gems %d/%d", entry.slotsUsed or 0, entry.slotsTotal or 0))
        end
        if entry.uid == selectedItemUid then
            w:focus()
        end
    end
end

local function setSlotFrame(frame, slotData, isActive)
    if not frame then return end
    if slotData and slotData.filled and slotData.gem then
        local spriteId = uiItemSpriteId(slotData.gem.clientId or slotData.gem.id)
        frame:setItemId(spriteId)
        if frame.setItemCount then frame:setItemCount(1) end
        if frame.setTooltip then
            local tip = string.format("%s Lv%d", slotData.gem.element or "?", slotData.gem.level or 0)
            if slotData.gem.percent then
                tip = tip .. string.format(" (%.0f%%)", slotData.gem.percent)
            end
            frame:setTooltip(tip)
        end
    else
        frame:setItemId(0)
        if frame.setTooltip then
            frame:setTooltip(slotData and slotData.locked and "Locked" or "Empty slot")
        end
    end
    if frame.setOn then
        frame:setOn(isActive == true)
    end
end

function refreshCenterPanel()
    if not centerPanel then return end
    local iconWidget = centerPanel:getChildById("itemIcon")
    local nameWidget = centerPanel:getChildById("itemName")
    local subtitleWidget = centerPanel:getChildById("itemSubtitle")
    local descWidget = centerPanel:getChildById("tabDescription")
    local warnWidget = centerPanel:getChildById("warningLabel")
    local actionBtn = centerPanel:getChildById("actionButton")
    local actionLabel = actionBtn and actionBtn:recursiveGetChildById("actionLabel") or nil
    local actionIcon = actionBtn and actionBtn:recursiveGetChildById("actionIcon") or nil

    if actionLabel then actionLabel:setText(TAB_LABELS[selectedTab] or "Action") end
    if actionIcon then actionIcon:setItemId(uiItemSpriteId(TAB_ICONS[selectedTab] or 0)) end
    if descWidget then descWidget:setText(TAB_DESCRIPTIONS[selectedTab] or "") end
    if warnWidget then warnWidget:setText(TAB_WARNINGS[selectedTab] or "") end

    if not currentItem then
        if iconWidget then iconWidget:setItemId(0) end
        if nameWidget then nameWidget:setText("No item selected") end
        if subtitleWidget then subtitleWidget:setText("Selecione um item na lista a esquerda.") end
        for i = 1, 3 do
            local frame = centerPanel:recursiveGetChildById("slot" .. i)
            setSlotFrame(frame, { filled = false, locked = true }, false)
            local lbl = centerPanel:recursiveGetChildById("slot" .. i .. "Label")
            if lbl then lbl:setText(tostring(i)) end
        end
        refreshCost()
        refreshBalance()
        return
    end

    if iconWidget then
        iconWidget:setItemId(uiItemSpriteId(currentItem.clientId or currentItem.itemId))
        if iconWidget.setItemCount then iconWidget:setItemCount(1) end
    end
    if nameWidget then nameWidget:setText(currentItem.name or "?") end
    if subtitleWidget then
        subtitleWidget:setText(string.format("Slots disponiveis: %d / %d",
            currentItem.slotsTotal or 0, currentItem.slotsMax or 3))
    end

    for i = 1, 3 do
        local slotData = currentItem.slots and currentItem.slots[i] or { filled = false, locked = true }
        local frame = centerPanel:recursiveGetChildById("slot" .. i)
        local isActive = (selectedSlot == i)
        setSlotFrame(frame, slotData, isActive)
        local lbl = centerPanel:recursiveGetChildById("slot" .. i .. "Label")
        if lbl then
            if slotData.locked then
                lbl:setText("Locked")
                lbl:setColor("#7a7a7a")
            elseif slotData.filled and slotData.gem then
                lbl:setText(string.format("Lv%d", slotData.gem.level or 0))
                lbl:setColor("#ffd27f")
            else
                lbl:setText("Empty")
                lbl:setColor("#afafaf")
            end
        end
    end

    refreshCost()
    refreshBalance()
end

function refreshCost()
    if not centerPanel then return end
    local totalCost = centerPanel:recursiveGetChildById("totalCost")
    local costIcon = centerPanel:recursiveGetChildById("costIcon")
    if costIcon then costIcon:setItemId(uiItemSpriteId(GOLD_ITEM_ID)) end
    if not totalCost then return end

    local cost = 0
    if currentItem and currentItem.costs then
        if selectedTab == "insert" then
            cost = currentItem.costs.insert or 0
        elseif selectedTab == "swap" then
            cost = currentItem.costs.swap or 0
        elseif selectedTab == "destroy" then
            cost = currentItem.costs.destroy or 0
        elseif selectedTab == "createSlot" then
            cost = currentItem.costs.createSlot or 0
        end
    end
    totalCost:setText(commaValue(cost))
end

function refreshBalance()
    if not centerPanel then return end
    local balanceLabel = centerPanel:recursiveGetChildById("playerBalance")
    local balanceIcon = centerPanel:recursiveGetChildById("balanceIcon")
    if balanceIcon then balanceIcon:setItemId(uiItemSpriteId(GOLD_ITEM_ID)) end
    if balanceLabel then balanceLabel:setText(commaValue(playerMoney)) end
end

function refreshRightPanel()
    if not window then return end

    if selectedTab == "insert" or selectedTab == "swap" then
        if rightInfoPanel then rightInfoPanel:hide() end
        if rightList then
            rightList:show()
            rightList:setText(selectedTab == "insert" and "Available Gems" or "Swap To")
            rightList:destroyChildren()
            local minLevel = 0
            if selectedTab == "swap" and currentItem and selectedSlot then
                local sd = currentItem.slots and currentItem.slots[selectedSlot]
                if sd and sd.filled and sd.gem then
                    minLevel = sd.gem.level or 0
                end
            end
            for _, gem in ipairs(playerGems) do
                local w = g_ui.createWidget("GemListEntry", rightList)
                w:setId(tostring(gem.id))
                local itemWidget = w:getChildById("item")
                if itemWidget then
                    itemWidget:setItemId(uiItemSpriteId(gem.clientId or gem.id))
                end
                local nameWidget = w:getChildById("name")
                if nameWidget then nameWidget:setText(gem.name or ("Gem " .. gem.id)) end
                local infoWidget = w:getChildById("info")
                if infoWidget then
                    infoWidget:setText(string.format("Lv%d  x%d", gem.level or 0, gem.count or 0))
                end
                if selectedTab == "swap" and (gem.level or 0) < minLevel then
                    w:disable()
                    w:setTooltip(string.format("Gema precisa ser nivel %d ou maior.", minLevel))
                end
                if selectedGemId == gem.id then
                    w:focus()
                end
            end
        end
        return
    end

    if selectedTab == "destroy" then
        if rightInfoPanel then rightInfoPanel:hide() end
        if rightList then
            rightList:show()
            rightList:setText("Filled Slots")
            rightList:destroyChildren()
            if currentItem and currentItem.slots then
                for i, slotData in ipairs(currentItem.slots) do
                    if slotData.filled and slotData.gem then
                        local w = g_ui.createWidget("GemListEntry", rightList)
                        w:setId("slot_" .. i)
                        w.gemSystemSlot = i
                        local itemWidget = w:getChildById("item")
                        if itemWidget then
                            itemWidget:setItemId(uiItemSpriteId(slotData.gem.clientId or slotData.gem.id))
                        end
                        local nameWidget = w:getChildById("name")
                        if nameWidget then
                            nameWidget:setText(string.format("Slot %d - %s Lv%d", i,
                                slotData.gem.element or "?", slotData.gem.level or 0))
                        end
                        local infoWidget = w:getChildById("info")
                        if infoWidget then infoWidget:setText("Clique para selecionar") end
                        if selectedSlot == i then
                            w:focus()
                        end
                    end
                end
            end
        end
        return
    end

    if selectedTab == "createSlot" then
        if rightList then rightList:hide() end
        if rightInfoPanel then
            rightInfoPanel:show()
            local infoIcon = rightInfoPanel:getChildById("infoIcon")
            if infoIcon then infoIcon:setItemId(uiItemSpriteId(lunarRelicClientId)) end
            local infoTitle = rightInfoPanel:getChildById("infoTitle")
            if infoTitle then infoTitle:setText("Create Slot") end
            local infoText = rightInfoPanel:getChildById("infoText")
            if infoText then
                local nextCost = (currentItem and currentItem.costs and currentItem.costs.createSlot) or 0
                if nextCost > 0 then
                    infoText:setText(string.format(
                        "Proximo slot custa %s gold + 1 Lunar Relic.",
                        commaValue(nextCost)))
                else
                    infoText:setText("Este item ja possui o maximo de gem slots.")
                end
            end
            local relicLabel = rightInfoPanel:getChildById("infoRelicLabel")
            if relicLabel then relicLabel:setText(string.format("Lunar Relic: %d", lunarRelicCount)) end
        end
        return
    end
end

-- =============================================================================
-- User actions
-- =============================================================================

function selectTab(tab)
    if not TAB_LABELS[tab] then return end
    selectedTab = tab
    selectedSlot = nil
    selectedGemId = nil
    applyTabButtons()
    refreshCenterPanel()
    refreshRightPanel()
end

function selectItem(uid)
    local parsed = tonumber(uid)
    if not parsed then return end
    selectedItemUid = parsed
    selectedSlot = nil
    selectedGemId = nil

    for _, entry in ipairs(playerItems) do
        if entry.uid == parsed then
            entry._focus = true
        end
    end

    sendOpcode({ action = "selectItem", data = { uid = parsed } })
end

function selectSlot(slotIndex)
    if not currentItem or not currentItem.slots then return end
    local slotData = currentItem.slots[slotIndex]
    if not slotData or slotData.locked then return end
    selectedSlot = slotIndex
    refreshCenterPanel()
    refreshRightPanel()
end

function selectGem(gemId)
    -- selectGem eh chamada pelas entradas da lista direita. Quando a tab
    -- e "destroy", o id tem o prefixo "slot_" - vamos reaproveitar esse
    -- click para fixar o slot de destruicao.
    if selectedTab == "destroy" then
        local sid = tostring(gemId or ""):match("^slot_(%d+)$")
        if sid then
            selectSlot(tonumber(sid))
            return
        end
    end

    local parsed = tonumber(gemId)
    if not parsed then return end
    selectedGemId = parsed
    refreshRightPanel()
end

function executeAction()
    if not selectedItemUid or selectedItemUid == 0 then
        return
    end

    if selectedTab == "insert" then
        if not selectedSlot then
            displayWarn("Selecione um slot vazio no item antes de inserir.")
            return
        end
        if not selectedGemId then
            displayWarn("Escolha uma gema na lista a direita.")
            return
        end
        sendOpcode({ action = "insert", data = {
            uid = selectedItemUid, slot = selectedSlot, gemId = selectedGemId,
        } })
        return
    end

    if selectedTab == "swap" then
        if not selectedSlot then
            displayWarn("Selecione um slot preenchido antes de trocar.")
            return
        end
        if not selectedGemId then
            displayWarn("Escolha a nova gema (level >= ao atual).")
            return
        end
        confirm("A gema antiga sera devolvida ao seu inventario.\nDeseja trocar por esta nova gema?", function()
            sendOpcode({ action = "swap", data = {
                uid = selectedItemUid, slot = selectedSlot, gemId = selectedGemId,
            } })
        end)
        return
    end

    if selectedTab == "destroy" then
        if not selectedSlot then
            displayWarn("Selecione um slot preenchido para destruir a gema.")
            return
        end
        confirm("A gema sera DESTRUIDA e NAO retornara ao inventario.\nDeseja continuar?", function()
            sendOpcode({ action = "destroy", data = {
                uid = selectedItemUid, slot = selectedSlot,
            } })
        end)
        return
    end

    if selectedTab == "createSlot" then
        sendOpcode({ action = "createSlot", data = { uid = selectedItemUid } })
        return
    end
end

function displayWarn(msg)
    if modules.game_textmessage and modules.game_textmessage.displayGameMessage then
        modules.game_textmessage.displayGameMessage(msg)
    else
        g_logger.warning("[GemSystem] " .. msg)
    end
end

-- =============================================================================
-- Show / Hide
-- =============================================================================

function show()
    if not window then
        create()
    end
    if not window then return end
    window:show()
    window:raise()
    window:focus()
end

function hide()
    if window then
        window:hide()
    end
end
