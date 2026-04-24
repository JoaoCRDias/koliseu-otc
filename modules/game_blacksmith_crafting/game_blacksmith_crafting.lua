-- Blacksmith Crafting OTC module
-- Adaptado do game_crafting (Oen) para o sistema Blacksmith + Lead Metal Bar.
-- Comunica com o servidor via extended opcode 108.

local CODE = 108
local imagesPath = "/modules/game_blacksmith_crafting/images"

local window = nil
local categoriesPanel = nil
local craftPanel = nil
local itemsList = nil
local forgeButton = nil
local fetchInFlight = false
local lastFetchRequestMs = 0
local lastButtonToggleMs = 0
local FETCH_REQUEST_COOLDOWN_MS = 1200
local TOGGLE_COOLDOWN_MS = 250

local selectedCategory = nil
local selectedCraftId = nil

local Crafts = { blacksmith = {}, leadbar = {} }
local playerMoney = 0
local playerBars = 0
local playerVip = false

local CATEGORY_LABELS = {
    blacksmith = "Blacksmith",
    leadbar = "Lead Metal Bar",
}

local GOLD_ITEM_ID = 3031
local LEAD_BAR_ITEM_ID = 63401

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

--- UIItem:setItemId usa o id local do cliente. O servidor pode enviar id de servidor (Canary sem getClientId).
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

local function hasEnoughAmount(playerAmount, requiredAmount)
    return (tonumber(playerAmount) or 0) >= (tonumber(requiredAmount) or 0)
end

local function isCraftReady(craft, category)
    if not craft then
        return false
    end

    if not hasEnoughAmount(craft.playerHasSource, 1) then
        return false
    end

    if category == "leadbar" then
        if not hasEnoughAmount(playerBars, craft.bars) then
            return false
        end
    else
        if not hasEnoughAmount(playerMoney, craft.goldCost) then
            return false
        end
    end

    if craft.visualMaterials and type(craft.visualMaterials) == "table" then
        for _, vm in ipairs(craft.visualMaterials) do
            if not hasEnoughAmount(vm.player, vm.count) then
                return false
            end
        end
    end

    return true
end

local function applyCraftReadyHighlight(widget, isReady)
    if not widget or not widget.setBorderWidth or not widget.setBorderColor then
        return
    end

    if isReady then
        widget:setBorderWidth(1)
        widget:setBorderColor("#39d353")
    else
        widget:setBorderWidth(0)
        widget:setBorderColor("alpha")
    end
end

function init()
    connect(g_game, { onGameStart = create, onGameEnd = destroy })

    ProtocolGame.registerExtendedOpcode(CODE, onExtendedOpcode)

    forgeButton = modules.game_mainpanel.addVerticalToggleButton(
        "blacksmithCraftingButton",
        tr("Blacksmith Crafting"),
        imagesPath .. "/forja",
        function()
            local now = nowMs()
            if now - lastButtonToggleMs < TOGGLE_COOLDOWN_MS then
                return
            end
            lastButtonToggleMs = now

            if not window then
                create()
            end
            if window and window:isVisible() then
                hide()
            else
                if (not fetchInFlight) and (now - lastFetchRequestMs >= FETCH_REQUEST_COOLDOWN_MS) then
                    requestFetch()
                end
                show()
                if selectedCategory then
                    selectItem(selectedCraftId or 1)
                end
            end
        end,
        false,
        4
    )

    if g_game.isOnline() then
        create()
    end
end

function terminate()
    disconnect(g_game, { onGameStart = create, onGameEnd = destroy })

    ProtocolGame.unregisterExtendedOpcode(CODE, onExtendedOpcode)

    if forgeButton then
        forgeButton:destroy()
        forgeButton = nil
    end

    destroy()
end

function create()
    if window then
        return
    end

    window = g_ui.displayUI("game_blacksmith_crafting")
    window:hide()

    categoriesPanel = window:getChildById("categories")
    craftPanel = window:getChildById("craftPanel")
    itemsList = window:getChildById("itemsList")
end

function destroy()
    if window then
        categoriesPanel = nil
        craftPanel = nil
        itemsList = nil

        selectedCategory = nil
        selectedCraftId = nil
        Crafts = { blacksmith = {}, leadbar = {} }
        playerMoney = 0
        playerBars = 0
        playerVip = false

        window:destroy()
        window = nil
    end
end

-- Funcao do modulo (nao local) para ficar visivel como `requestFetch` em callbacks
-- executados em escopos que nao preservam upvalues (ex.: addVerticalToggleButton).
function requestFetch()
    local now = nowMs()
    if fetchInFlight and now - lastFetchRequestMs < FETCH_REQUEST_COOLDOWN_MS then
        return
    end
    lastFetchRequestMs = now
    fetchInFlight = true

    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(CODE, json.encode({ action = "fetch" }))
    else
        fetchInFlight = false
    end
end

function onExtendedOpcode(protocol, code, buffer)
    if not window then
        return false
    end

    local status, jsonData = pcall(function()
        return json.decode(buffer)
    end)

    if not status then
        g_logger.error("[BlacksmithCrafting] JSON decode error")
        return false
    end

    local action = jsonData.action
    local data = jsonData.data

    if action == "fetch" then
        fetchInFlight = false
        Crafts[data.category] = Crafts[data.category] or {}
        -- Primeira pagina da categoria (id 1) reseta a lista
        if data.crafts and #data.crafts > 0 and data.crafts[1].id == 1 then
            Crafts[data.category] = {}
        end
        for i = 1, #data.crafts do
            table.insert(Crafts[data.category], data.crafts[i])
        end

        if not selectedCategory then
            selectCategory("blacksmith")
        elseif selectedCategory == data.category then
            refreshList()
        end
    elseif action == "money" then
        playerMoney = tonumber(data) or 0
        refreshBalance()
    elseif action == "bars" then
        playerBars = tonumber(data) or 0
        refreshBalance()
        if selectedCategory == "leadbar" and selectedCraftId then
            selectItem(selectedCraftId)
        end
    elseif action == "vip" then
        playerVip = data == true
        refreshVipBadge()
    elseif action == "show" then
        if #Crafts.blacksmith == 0 and #Crafts.leadbar == 0 then
            requestFetch()
        end
        show()
        if selectedCategory then
            selectItem(selectedCraftId or 1)
        end
    elseif action == "crafted" then
        onItemCrafted()
    end

    return true
end

function refreshVipBadge()
    if not window then
        return
    end
    local badge = window:recursiveGetChildById("vipBadge")
    if badge then
        badge:setText(playerVip and "VIP Pricing" or "")
    end
end

function refreshBalance()
    if not craftPanel then
        return
    end
    local balanceLabel = craftPanel:recursiveGetChildById("playerBalance")
    if not balanceLabel then
        return
    end

    local balanceLabelTitle = craftPanel:getChildById("balanceLabel")
    local balanceIcon = craftPanel:recursiveGetChildById("balanceIcon")
    if selectedCategory == "leadbar" then
        balanceLabelTitle:setText("Bars")
        if balanceIcon then
            balanceIcon:setItemId(uiItemSpriteId(LEAD_BAR_ITEM_ID))
        end
        balanceLabel:setText(commaValue(playerBars))
    else
        balanceLabelTitle:setText("Balance")
        if balanceIcon then
            balanceIcon:setItemId(uiItemSpriteId(GOLD_ITEM_ID))
        end
        balanceLabel:setText(commaValue(playerMoney))
    end
end

function refreshList()
    if not selectedCategory or not itemsList then
        return
    end

    itemsList:destroyChildren()
    selectedCraftId = nil

    local list = Crafts[selectedCategory] or {}
    local sortedEntries = {}
    for i = 1, #list do
        table.insert(sortedEntries, { index = i, craft = list[i] })
    end

    table.sort(sortedEntries, function(a, b)
        local aReady = isCraftReady(a.craft, selectedCategory)
        local bReady = isCraftReady(b.craft, selectedCategory)
        if aReady ~= bReady then
            return aReady
        end

        local aName = (a.craft and a.craft.sourceName or ""):lower()
        local bName = (b.craft and b.craft.sourceName or ""):lower()
        if aName ~= bName then
            return aName < bName
        end

        return a.index < b.index
    end)

    for i = 1, #sortedEntries do
        local entry = sortedEntries[i]
        local craft = entry.craft
        local craftReady = isCraftReady(craft, selectedCategory)
        local w = g_ui.createWidget("ItemListItem")
        w:setId(entry.index)
        applyCraftReadyHighlight(w, craftReady)
        local sourceDisplayName = craft.sourceName or "Unknown"
        local resultDisplayName = craft.resultName or "Unknown"
        w:getChildById("item"):setItemId(uiItemSpriteId(craft.sourceClientId or craft.sourceId))
        w:getChildById("name"):setText(sourceDisplayName)

        local reqText = "-> " .. resultDisplayName
        if (craft.requiredTier or 0) > 0 or (craft.requiredLevel or 0) > 0 then
            reqText = string.format("-> %s | Tier %d+ / Lv %d+", resultDisplayName, craft.requiredTier or 0, craft.requiredLevel or 0)
        else
            reqText = "-> " .. resultDisplayName
        end
        w:getChildById("level"):setText(reqText)
        w:setTooltip(string.format("Upgrade result: %s", resultDisplayName))

        itemsList:addChild(w)

        if i == 1 then
            w:focus()
            selectItem(entry.index)
        end
    end
end

function selectCategory(category)
    if not window or not Crafts[category] then
        return
    end

    if selectedCategory then
        local oldBtn = categoriesPanel:getChildById(selectedCategory .. "Cat")
        if oldBtn then
            oldBtn:setOn(false)
        end
    end

    local newBtn = categoriesPanel:getChildById(category .. "Cat")
    if newBtn then
        newBtn:setOn(true)
    end

    selectedCategory = category
    refreshBalance()
    refreshList()
end

function selectItem(id)
    local craftId = tonumber(id)
    if not craftId or not selectedCategory then
        return
    end
    selectedCraftId = craftId

    local craft = Crafts[selectedCategory] and Crafts[selectedCategory][craftId]
    if not craft then
        return
    end

    -- Slot 1: item de origem (qty 1)
    local mat1 = craftPanel:getChildById("material1")
    mat1:setItemId(uiItemSpriteId(craft.sourceClientId or craft.sourceId))
    if mat1.setTooltip then
        mat1:setTooltip(craft.sourceName or "")
    end
    local count1 = craftPanel:getChildById("count1")
    local playerHasSource = craft.playerHasSource or 0
    count1:setText(playerHasSource .. "\n1")
    if playerHasSource >= 1 then
        count1:setColor("#FFFFFF")
    else
        count1:setColor("#FF0000")
    end

    -- Slots 2 e 3: materiais visuais adicionais
    local materialWidgets = {
        {
            item = craftPanel:getChildById("material2"),
            count = craftPanel:getChildById("count2"),
            line = craftPanel:getChildById("craftLine2"),
        },
        {
            item = craftPanel:getChildById("material3"),
            count = craftPanel:getChildById("count3"),
            line = craftPanel:getChildById("craftLine3"),
        },
    }

    local visualMaterials = {}
    if selectedCategory == "leadbar" and (craft.bars or 0) > 0 then
        table.insert(visualMaterials, {
            id = LEAD_BAR_ITEM_ID,
            count = craft.bars or 0,
            player = playerBars,
            name = "Lead Metal Bar",
        })
    end

    if craft.visualMaterials and type(craft.visualMaterials) == "table" then
        for _, vm in ipairs(craft.visualMaterials) do
            table.insert(visualMaterials, vm)
        end
    end

    for i = 1, #materialWidgets do
        local slot = materialWidgets[i]
        local vm = visualMaterials[i]
        if vm then
            slot.item:setItemId(uiItemSpriteId(vm.id))
            if slot.item.setTooltip then
                slot.item:setTooltip(vm.name or ("Item " .. tostring(vm.id)))
            end
            local playerAmount = tonumber(vm.player) or 0
            local requiredAmount = tonumber(vm.count) or 0
            slot.count:setText(playerAmount .. "\n" .. requiredAmount)
            if playerAmount >= requiredAmount then
                slot.count:setColor("#FFFFFF")
            else
                slot.count:setColor("#FF0000")
            end
            slot.item:show()
            slot.count:show()
            if slot.line then slot.line:show() end
        else
            slot.item:setItem(nil)
            slot.count:setText("")
            slot.item:hide()
            slot.count:hide()
            if slot.line then slot.line:hide() end
        end
    end

    -- Resultado
    local outcome = craftPanel:getChildById("craftOutcome")
    outcome:setItemId(uiItemSpriteId(craft.resultClientId or craft.resultId))
    outcome:setItemCount(1)
    if outcome.setTooltip then
        outcome:setTooltip(string.format("Creates: %s", craft.resultName or "Unknown"))
    end

    -- Requisitos (tier / level)
    local reqLabel = craftPanel:getChildById("requirementsLabel")
    if reqLabel then
        if (craft.requiredTier or 0) > 0 or (craft.requiredLevel or 0) > 0 then
            reqLabel:setText(string.format("Requires Tier %d+ / Lv %d+", craft.requiredTier or 0, craft.requiredLevel or 0))
        else
            reqLabel:setText("No tier/level requirement")
        end
    end

    -- Custo e balance
    local costLabel = craftPanel:getChildById("costLabel")
    local costPanel = craftPanel:recursiveGetChildById("costPanel")
    local costIcon = craftPanel:recursiveGetChildById("costIcon")
    local totalCost = craftPanel:recursiveGetChildById("totalCost")

    if selectedCategory == "leadbar" then
        -- Evita duplicidade visual de custo no leadbar:
        -- custo exigido ja aparece nos materiais (slot Lead Metal Bar).
        if costLabel then
            costLabel:hide()
        end
        if costPanel then
            costPanel:hide()
        end
    else
        if costLabel then
            costLabel:setText("Total Cost")
            costLabel:show()
        end
        if costPanel then
            costPanel:show()
        end
        if costIcon then
            costIcon:setItemId(uiItemSpriteId(GOLD_ITEM_ID))
        end
        if totalCost then
            totalCost:setText(commaValue(craft.goldCost or 0))
        end
    end

    refreshBalance()
end

function onItemCrafted()
    if not craftPanel or not selectedCraftId then
        return
    end

    for i = 1, 3 do
        local w = craftPanel:getChildById("craftLine" .. i)
        if w and w:isVisible() then
            w:setImageSource("/images/blacksmith_crafting/craft_line" .. i .. "on")
            local idx = i
            scheduleEvent(function()
                if not craftPanel then
                    return
                end
                local wl = craftPanel:getChildById("craftLine" .. idx)
                if wl then
                    wl:setImageSource("/images/blacksmith_crafting/craft_line" .. (idx == 2 and 5 or idx))
                end
            end, 850)
        end
    end

    local button = craftPanel:getChildById("craftButton")
    if button then
        button:disable()
        scheduleEvent(function()
            if craftPanel then
                local btn = craftPanel:getChildById("craftButton")
                if btn then
                    btn:enable()
                end
            end
        end, 860)
    end
end

function onSearch()
    scheduleEvent(function()
        if not window then
            return
        end
        local searchInput = window:recursiveGetChildById("searchInput")
        local text = searchInput:getText():lower()
        local children = itemsList:getChildCount()
        if #text >= 1 then
            for i = children, 1, -1 do
                local child = itemsList:getChildByIndex(i)
                local name = child:getChildById("name"):getText():lower()
                if name:find(text, 1, true) then
                    child:show()
                else
                    child:hide()
                end
            end
        else
            for i = children, 1, -1 do
                local child = itemsList:getChildByIndex(i)
                child:show()
            end
        end
    end, 25)
end

function craftItem()
    if not selectedCategory or not selectedCraftId then
        return
    end
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedOpcode(CODE, json.encode({
            action = "craft",
            data = { category = selectedCategory, craftId = selectedCraftId },
        }))
    end
end

function show()
    if not window then
        return
    end
    window:show()
    window:raise()
    window:focus()
end

function hide()
    if not window then
        return
    end
    window:hide()
end
