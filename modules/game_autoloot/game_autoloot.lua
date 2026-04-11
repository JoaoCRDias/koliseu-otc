AutoLoot = {}

local autolootState = 0
local AUTOLOOT_ITEM_ID = 23721
local AUTOLOOT_OPCODE = 200

-- Função auxiliar para verificar se um item é o de autoloot
function AutoLoot.isAutolootItem(thing)
    if not thing then
        return false
    end

    local success, itemId = pcall(function()
        if thing.getId then
            return thing:getId()
        end
        return nil
    end)

    return success and itemId == AUTOLOOT_ITEM_ID
end

function AutoLoot.init()
    connect(g_game, {
        onGameStart = AutoLoot.onGameStart,
        onGameEnd = AutoLoot.onGameEnd
    })

    if Container then
        connect(Container, {
            onOpen = AutoLoot.onContainerOpen,
            onClose = AutoLoot.onContainerClose
        })
    end

    ProtocolGame.registerExtendedOpcode(AUTOLOOT_OPCODE, AutoLoot.onExtendedOpcode)

    -- Sistema de menu usando addMenuHook com suporte a cores
    if modules.game_interface and modules.game_interface.addMenuHook then
        -- Hook para "Enable Auto Loot" (verde)
        modules.game_interface.addMenuHook({
            category = 'autoloot',
            option = tr('Enable Auto Loot'),
            callback = function(menuPosition, lookThing, useThing, creatureThing)
                g_game.talk('!autoloot on')
            end,
            condition = function(menuPosition, lookThing, useThing, creatureThing)
                local itemToCheck = useThing or lookThing
                local isItem = AutoLoot.isAutolootItem(itemToCheck)
                return isItem and autolootState == 0
            end,
            color = '#00FF00'
        })

        -- Hook para "Disable Auto Loot" (vermelho)
        modules.game_interface.addMenuHook({
            category = 'autoloot',
            option = tr('Disable Auto Loot'),
            callback = function(menuPosition, lookThing, useThing, creatureThing)
                g_game.talk('!autoloot off')
            end,
            condition = function(menuPosition, lookThing, useThing, creatureThing)
                local itemToCheck = useThing or lookThing
                local isItem = AutoLoot.isAutolootItem(itemToCheck)
                return isItem and autolootState > 0
            end,
            color = '#FF0000'
        })
    end

    -- Se já estiver no jogo, atualizar borda imediatamente
    if g_game.isOnline() then
        AutoLoot.updateItemBorder()
    end
end

function AutoLoot.terminate()
    disconnect(g_game, {
        onGameStart = AutoLoot.onGameStart,
        onGameEnd = AutoLoot.onGameEnd
    })

    if Container then
        disconnect(Container, {
            onOpen = AutoLoot.onContainerOpen,
            onClose = AutoLoot.onContainerClose
        })
    end

    ProtocolGame.unregisterExtendedOpcode(AUTOLOOT_OPCODE)

    -- Remove hooks de menu (remove toda a categoria de uma vez)
    if modules.game_interface and modules.game_interface.removeMenuHook then
        modules.game_interface.removeMenuHook({ category = 'autoloot' })
    end
end

function AutoLoot.onGameStart()
    AutoLoot.updateItemBorder()
    -- Solicita o estado inicial do servidor após um pequeno delay
    scheduleEvent(function()
        if g_game.isOnline() then
            -- Envia um comando vazio para solicitar o estado atual
            -- O servidor deve responder com o estado atual
            g_game.talk('!autoloot')
        end
    end, 1000) -- 1 segundo de delay para garantir que o cliente está pronto
end

function AutoLoot.onGameEnd()
    autolootState = 0
    AutoLoot.updateItemBorder()
end

function AutoLoot.updateAutolootState(state)
    autolootState = state or 0
    AutoLoot.updateItemBorder()
end

-- Verifica se existe um container "Store" aberto
function AutoLoot.isStoreContainerOpen()
    local containers = g_game.getContainers()
    if containers then
        for _, container in pairs(containers) do
            local name = container:getName()
            if name and string.find(string.lower(name), "store") then
                return true
            end
        end
    end
    return false
end

function AutoLoot.onContainerOpen(container, previousContainer)
    local name = container:getName()
    if name and string.find(string.lower(name), "store") then
        scheduleEvent(function() AutoLoot.updateItemBorder() end, 100)
    end
end

function AutoLoot.onContainerClose(container, previousContainer)
    local name = container:getName()
    if name and string.find(string.lower(name), "store") then
        AutoLoot.clearItemBorder()
    end
end

function AutoLoot.clearItemBorder()
    -- Remove borda do widget se existir
    if AutoLoot.currentBorderWidget then
        pcall(function()
            AutoLoot.currentBorderWidget:setBorderWidth(0)
        end)
        AutoLoot.currentBorderWidget = nil
    end
end

function AutoLoot.updateItemBorder()
    -- Só aplica borda se o container Store estiver aberto
    if not AutoLoot.isStoreContainerOpen() then
        AutoLoot.clearItemBorder()
        return
    end

    local itemWidget = AutoLoot.findItemWidget(AUTOLOOT_ITEM_ID)
    if itemWidget then
        AutoLoot.currentBorderWidget = itemWidget
        if autolootState > 0 then
            itemWidget:setBorderColor('green')
            itemWidget:setBorderWidth(2)
        else
            itemWidget:setBorderColor('red')
            itemWidget:setBorderWidth(2)
        end
    end
end

function AutoLoot.findItemWidget(itemId)
    -- Procura nos slots de equipamento
    if modules.game_inventory and modules.game_inventory.inventoryController then
        local player = g_game.getLocalPlayer()
        if player then
            local inventoryController = modules.game_inventory.inventoryController
            if inventoryController and inventoryController.ui then
                local getSlotPanelBySlot = {
                    [InventorySlotHead] = function(ui) return ui.helmet, ui.helmet.helmet end,
                    [InventorySlotNeck] = function(ui) return ui.amulet, ui.amulet.amulet end,
                    [InventorySlotBack] = function(ui) return ui.backpack, ui.backpack.backpack end,
                    [InventorySlotBody] = function(ui) return ui.armor, ui.armor.armor end,
                    [InventorySlotRight] = function(ui) return ui.shield, ui.shield.shield end,
                    [InventorySlotLeft] = function(ui) return ui.sword, ui.sword.sword end,
                    [InventorySlotLeg] = function(ui) return ui.legs, ui.legs.legs end,
                    [InventorySlotFeet] = function(ui) return ui.boots, ui.boots.boots end,
                    [InventorySlotFinger] = function(ui) return ui.ring, ui.ring.ring end,
                    [InventorySlotAmmo] = function(ui) return ui.tools, ui.tools.tools end
                }

                local ui = inventoryController.ui.onPanel:isVisible() and inventoryController.ui.onPanel or
                    inventoryController.ui.offPanel

                for slot = InventorySlotFirst, InventorySlotPurse do
                    local item = player:getInventoryItem(slot)
                    if item and item:getId() == itemId then
                        local getSlotInfo = getSlotPanelBySlot[slot]
                        if getSlotInfo then
                            local slotPanel, _ = getSlotInfo(ui)
                            if slotPanel and slotPanel.item then
                                return slotPanel.item
                            end
                        end
                    end
                end
            end
        end
    end

    -- Procura em containers abertos
    if modules.game_containers then
        local containers = g_game.getContainers()
        if containers then
            for containerId, container in pairs(containers) do
                if container and container.itemsPanel then
                    for slot = 0, container:getSize() - 1 do
                        local item = container:getItem(slot)
                        if item and item:getId() == itemId then
                            local widget = container.itemsPanel:getChildById('item' .. slot)
                            if widget then
                                return widget
                            end
                        end
                    end
                end
            end
        end
    end

    return nil
end

function AutoLoot.onExtendedOpcode(protocol, opcode, buffer)
    if opcode == AUTOLOOT_OPCODE then
        local state = tonumber(buffer)
        if state then
            AutoLoot.updateAutolootState(state)
        end
    end
end
