BundlesWindow = nil
BundlesConfirmationWindow = nil

local BUNDLES_OPCODE = 253
local bundlesBarWidget = nil

local enums = {
    types = {
        blue = 1,
        orange = 2,
        purple = 3,
        green = 4,
        red = 5,
        gold = 255
    },
    rewards = {
        item = 0,
        coin = 1,
        outfit = 2,
        mount = 3,
    }
}

local colors = {
    [enums.types.blue] = {
        title = "#e2ffef",
        time = "#62f6fe"
    },
    [enums.types.orange] = {
        title = "#fff2d4",
        time = "#fed762ff"
    },
    [enums.types.purple] = {
        title = "#ffdbfe",
        time = "#f962fe"
    },
    [enums.types.green] = {
        title = "#dbffdb",
        time = "#62f962"
    },
    [enums.types.red] = {
        title = "#ffdbdb",
        time = "#f96262"
    },
    [enums.types.gold] = {
        title = "#ffd700",
        time = "#ffcc00"
    }
}

local discount = {
    [enums.types.blue] = {
        color = "#c7fcf9",
        background = "#007b2a",
        background2 = "#00cc8a"
    },
    [enums.types.orange] = {
        color = "#fcecc7",
        background = "#811e00",
        background2 = "#cc4a00"
    },
    [enums.types.purple] = {
        color = "#f3c7fc",
        background = "#2e007e",
        background2 = "#8a00cc"
    },
    [enums.types.green] = {
        color = "#dbffdb",
        background = "#62f962",
        background2 = "#00cc8a"
    },
    [enums.types.red] = {
        color = "#ffdbdb",
        background = "#f96262",
        background2 = "#cc0000"
    },
    [enums.types.gold] = {
        color = "#ffd700",
        background = "#ffcc00",
        background2 = "#ffaa00"
    },

}

function init()
    g_ui.importStyle('styles/bundles_button')

    BundlesWindow = g_ui.displayUI('bundles')
    BundlesWindow:hide()

    BundlesWindow.coinBalance = 0

    pcall(function()
        ProtocolGame.unregisterExtendedJSONOpcode(BUNDLES_OPCODE)
    end)
    ProtocolGame.registerExtendedJSONOpcode(BUNDLES_OPCODE, onBundlesOpcode)

    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    if g_game.isOnline() then
        onGameStart()
    end
end

function terminate()
    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd
    })

    destroyBundlesBarWidget()

    pcall(function()
        ProtocolGame.unregisterExtendedJSONOpcode(BUNDLES_OPCODE)
    end)

    if BundlesConfirmationWindow ~= nil then
        BundlesConfirmationWindow:destroy()
        BundlesConfirmationWindow = nil
    end

    if BundlesWindow then
        BundlesWindow:destroy()
        BundlesWindow = nil
    end
end

function onGameStart()
    scheduleEvent(function()
        if g_game.isOnline() then
            createBundlesBarWidget()
        end
    end, 500)
end

function onGameEnd()
    destroyBundlesBarWidget()
    hide()
end

function onBundlesBarClick()
    if BundlesWindow and BundlesWindow:isVisible() then
        hide()
    else
        requestBundlesList()
    end
end

function createBundlesBarWidget()
    if bundlesBarWidget then
        return
    end

    local mainRightPanel = modules.game_interface.getMainRightPanel()
    if not mainRightPanel then
        return
    end

    bundlesBarWidget = g_ui.createWidget('BundlesBarWidget')
    if not bundlesBarWidget then
        return
    end

    local children = mainRightPanel:getChildren()
    local insertIndex = #children + 1
    for i, child in ipairs(children) do
        if child:getId() == 'minimapWindow' then
            insertIndex = i + 1
            for j = insertIndex, #children do
                local cid = children[j]:getId()
                if cid == 'BattlePassBarWidget' or cid == 'battlePassBarBtn' or cid == 'BundlesBarWidget' or cid == 'bundlesBarBtn' then
                    insertIndex = j + 1
                end
            end
            break
        end
    end

    mainRightPanel:insertChild(insertIndex, bundlesBarWidget)

    if mainRightPanel.fitAllChildren then
        mainRightPanel:fitAllChildren()
    end
end

function destroyBundlesBarWidget()
    if bundlesBarWidget then
        bundlesBarWidget:destroy()
        bundlesBarWidget = nil
        local mainRightPanel = modules.game_interface.getMainRightPanel()
        if mainRightPanel and mainRightPanel.fitAllChildren then
            mainRightPanel:fitAllChildren()
        end
    end
end

function requestBundlesList()
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedJSONOpcode(BUNDLES_OPCODE, { action = "list" })
    end
end

local function bundlesBuy(bundleId)
    local protocolGame = g_game.getProtocolGame()
    if protocolGame then
        protocolGame:sendExtendedJSONOpcode(BUNDLES_OPCODE, { action = "buy", bundleId = bundleId })
    end
end

function onBundlesOpcode(protocol, opcode, data)
    if not data or not data.action then return end

    if data.action == "list" then
        onBundles(data.balance or 0, data.goldBalance or 0, data.list or {})
    elseif data.action == "error" then
        local message = data.message or "An error occurred."
        displayErrorBox("Bundles", message)
    elseif data.action == "success" then
        local message = data.message or "Purchase successful!"
        modules.game_textmessage.displayStatusMessage(message)
    end
end

function show()
    if BundlesWindow and not BundlesWindow:isVisible() then
        BundlesWindow:show()
        BundlesWindow:raise()
        BundlesWindow:focus()
    end
end

function hide()
    if BundlesConfirmationWindow ~= nil then
        if not BundlesConfirmationWindow:isDestroyed() then
            BundlesConfirmationWindow:hide()
            BundlesConfirmationWindow:destroy()
        end
        BundlesConfirmationWindow = nil
    end

    if BundlesWindow and BundlesWindow:isVisible() then
        BundlesWindow:hide()
    end
end

function applyColorBundle(widget, factor)
    local r = math.max(0, math.min(255, math.floor(widget.glowPulse.original.r * factor + 0.5)))
    local g = math.max(0, math.min(255, math.floor(widget.glowPulse.original.g * factor + 0.5)))
    local b = math.max(0, math.min(255, math.floor(widget.glowPulse.original.b * factor + 0.5)))
    if widget.glowPulse.useBorder then
        widget:setBorderColor(string.format('#%02X%02X%02X', r, g, b))
    else
        widget:setColor(string.format('#%02X%02X%02X', r, g, b))
    end
end

function tickBundle(widget)
    if not widget or widget:isDestroyed() or not widget.glowPulse or not widget.glowPulse.running then
        if widget and widget.glowPulse and widget.glowPulse.original then
            local c = widget.glowPulse.original
            if widget.glowPulse.useBorder then
                widget:setBorderColor(string.format('#%02X%02X%02X', c.r, c.g, c.b))
            else
                widget:setColor(string.format('#%02X%02X%02X', c.r, c.g, c.b))
            end
        end

        return
    end

    local t = widget.glowPulse.step / widget.glowPulse.steps
    local factor = widget.glowPulse.minFactor + (widget.glowPulse.maxFactor - widget.glowPulse.minFactor) * t
    applyColorBundle(widget, factor)

    widget.glowPulse.step = widget.glowPulse.step + widget.glowPulse.direction

    if widget.glowPulse.step >= widget.glowPulse.steps then
        widget.glowPulse.step = widget.glowPulse.steps
        widget.glowPulse.direction = -1
    elseif widget.glowPulse.step <= 0 then
        widget.glowPulse.step = 0
        widget.glowPulse.direction = 1
    end

    widget.glowPulse.event = scheduleEvent(function()
        tickBundle(widget)
    end, widget.glowPulse.delay)
end

function startGlowEffect(widget, useBorder)
    if not widget or widget:isDestroyed() then
        return
    end

    if widget.glowPulse and widget.glowPulse.event then
        return
    end

    local original = widget:getColor()
    if useBorder then
        original = widget:getBorderTopColor()
    end

    if not original then
        return
    end

    widget.glowPulse = {
        original = { r = original.r, g = original.g, b = original.b, a = original.a },
        step = 0,
        direction = 1,
        event = nil,
        running = true,

        minFactor = 0.55,
        maxFactor = 1.35,
        steps = 24,
        cycleTime = 1200,
        delay = (1200 / (24 * 2)),
        useBorder = useBorder
    }

    applyColorBundle(widget, widget.glowPulse.minFactor)
    widget.glowPulse.event = scheduleEvent(function()
        tickBundle(widget)
    end, widget.glowPulse.delay)
end

function stopGlowEffect(widget)
    if not widget or not widget.glowPulse then
        return
    end

    widget.glowPulse.running = false
    if widget.glowPulse.event then
        removeEvent(widget.glowPulse.event)
        widget.glowPulse.event = nil
    end

    if not widget:isDestroyed() and widget.glowPulse.original then
        local c = widget.glowPulse.original
        widget:setColor(string.format('#%02X%02X%02X', c.r, c.g, c.b))
    end
    widget.glowPulse = nil
end

local function formatPriceNumber(integer)
    if integer >= 1000 then
        return tostring(integer / 1000) .. "k"
    end

    return tostring(integer)
end

function closeConfirmation()
    if BundlesConfirmationWindow then
        if not BundlesConfirmationWindow:isDestroyed() then
            BundlesConfirmationWindow:hide()
            BundlesConfirmationWindow:destroy()
        end
        BundlesConfirmationWindow = nil
    end

    show()
end

local function timeLeftToAvailable(ts)
    local d = ts - os.time()
    if d <= 0 then return "0" end

    local days = math.floor(d / 86400)
    local hours = math.floor((d % 86400) / 3600)
    local mins = math.floor((d % 3600) / 60)

    if days >= 1 then
        return days .. " dias" .. (hours > 0 and " e " .. hours .. " horas" or "")
    elseif hours >= 1 then
        return hours .. " horas" .. (mins > 0 and " e " .. mins .. " minutos" or "")
    else
        return mins .. " minutos"
    end
end

function onBundles(balance, goldBalance, list)
    BundlesWindow.balance.regular:setText(comma_value(balance))
    BundlesWindow.goldBalance.regular:setText(comma_value(goldBalance))

    local hasGoldBundle = false
    BundlesWindow.list:destroyChildren()
    for index, bundle in ipairs(list) do
        local color = colors[bundle.type]
        if color ~= nil then
            local widget = nil
            if bundle.type ~= enums.types.gold then
                widget = g_ui.createWidget("BundleEntry", BundlesWindow.list)
            else
                widget = BundlesWindow.specialList:getChildByIndex(1)
                widget.list:destroyChildren()
                hasGoldBundle = true
            end

            local colorIndex = bundle.type
            if colorIndex == enums.types.gold then
                colorIndex = 2
            end

            widget:setImageClip(torect(((colorIndex - 1) * 104) .. " 0 104 104"))
            if bundle.type ~= enums.types.gold then
                widget.imageBackground:setImageClip(torect(((colorIndex - 1) * 104) .. " 0 104 104"))
            end
            widget.list:setImageClip(torect(((colorIndex - 1) * 104) .. " 0 104 104"))
            widget.buttonsBorder:setImageClip(torect(((colorIndex - 1) * 104) .. " 0 104 104"))
            if bundle.type ~= enums.types.gold then
                widget.title:setImageClip(torect(((colorIndex - 1) * 300) .. " 0 300 29"))
            end
            widget.rewardsTitle:setImageClip(torect(((colorIndex - 1) * 286) .. " 0 286 23"))

            if bundle.type ~= enums.types.gold then
                widget.soulbound:setImageClip(torect(((colorIndex - 1) * 77) .. " 0 77 21"))
                for i = 1, 5 do
                    widget['star' .. i]:setEnabled(i <= bundle.stars)
                end
            end

            for i = 1, 4 do
                widget['corner' .. i]:setImageClip(torect(((colorIndex - 1) * 37) .. " 0 37 37"))
            end

            if bundle.type ~= enums.types.gold then
                widget.title:setText(bundle.name)
                widget.title:setColor(color.title)
                widget.rewardsTitle.iconTimer:setImageSource("/resources/icon_timer_bundles_" .. bundle.type)
                widget.buttonsBorderEffect:setImageSource("/resources/bundles/bundle_small_gray_border_" .. bundle.type)
            end
            widget.rewardsTitle.timestamp:setColor(color.title)

            local lines = {}
            if bundle.originalPrice > os.time() and bundle.type == enums.types.gold then
                table.insert(lines, comma_value(bundle.price))
                table.insert(lines, "#c0c0c0")
            elseif bundle.type ~= enums.types.gold and bundle.originalPrice > 0 and bundle.originalPrice ~= bundle.price then
                table.insert(lines, "De ")
                table.insert(lines, "#777878")
                table.insert(lines, comma_value(bundle.originalPrice))
                table.insert(lines, "#e26b6bff")
                table.insert(lines, " por ")
                table.insert(lines, "#777878")
                table.insert(lines, comma_value(bundle.price))
                table.insert(lines, "#6be277ff")
            else
                table.insert(lines, comma_value(bundle.price))
                table.insert(lines, "#6be277ff")
            end
            widget.buttonsBorder.balance.text:setColoredText(lines)

            if widget.imageBackground ~= nil and bundle.image ~= '' then
                local storeUrl = ""
                if modules.game_store and modules.game_store.getStoreUrl then
                    storeUrl = modules.game_store.getStoreUrl()
                end
                local uri = storeUrl .. bundle.image
                if uri ~= nil and uri ~= '' and uri:sub(1, 4):lower() == "http" then
                    HTTP.downloadImage(uri, function(path, err)
                        if widget == nil or widget:isDestroyed() or err then
                            return
                        end
                        widget.imageBackground.image:setImageSource(path)
                    end)
                end
            end

            startGlowEffect(widget.rewardsTitle.timestamp)

            for _, block in ipairs(bundle.rewards) do
                local reward = g_ui.createWidget("BundleItem", widget.list)

                reward.ribbon:setEnabled(not(block.special))

                if block.type == enums.rewards.item then
                    reward.count:clearText()

                    reward.item:show()
                    reward.item:setItemId(block.item)
                    if block.count > 1 then
                        reward.count:setText(formatPriceNumber(block.count))
                    end
                    local ok, name = pcall(function() return reward.item:getItem():getName() end)
                    reward:setTooltip(comma_value(block.count) .. "x " .. (ok and name or tostring(block.item)))
                elseif block.type == enums.rewards.coin then
                    reward.count:clearText()

                    reward.item:show()
                    reward.item:setItemId(37317)
                    reward.count:setText(formatPriceNumber(block.count))
                    local ok, name = pcall(function() return reward.item:getItem():getName() end)
                    reward:setTooltip(comma_value(block.count) .. "x " .. (ok and name or "Coins"))
                elseif block.type == enums.rewards.outfit then
                    reward.count:clearText()

                    reward.creature:show()
                    local outfit = g_game.getLocalPlayer():getOutfit()
                    outfit.type = block.lookTypes[1].lookType
                    outfit.category = ThingCategoryCreature
                    outfit.mount = 0
                    reward.creature:setOutfit(outfit)
                    reward.creature:setDirection(2)
                    reward.creature:setIdleAnimate(true)
                    reward:setTooltip(block.lookTypes[1].name)
                elseif block.type == enums.rewards.mount then
                    reward.count:clearText()

                    reward.creature:show()
                    local outfit = g_game.getLocalPlayer():getOutfit()
                    outfit.type = block.lookTypes[1].lookType
                    outfit.category = ThingCategoryCreature
                    outfit.mount = 0
                    reward.creature:setOutfit(outfit)
                    reward.creature:setDirection(2)
                    reward.creature:setIdleAnimate(true)
                    reward:setTooltip(block.lookTypes[1].name)
                end
            end

            if widget.ribbon ~= nil then
                if bundle.originalPrice > 0 then
                    if bundle.originalPrice ~= bundle.price then
                        local lines = {}
                        table.insert(lines, (math.ceil(100 - (bundle.price * 100) / bundle.originalPrice)) .. "% ")
                        table.insert(lines, "green")
                        table.insert(lines, "OFF")
                        table.insert(lines, "white")
                        widget.ribbon.text:setColoredText(lines)
                        widget.ribbon:setImageClip(torect(((colorIndex - 1) * 77) .. " 0 77 27"))
                        widget.ribbon:show()
                    else
                        widget.ribbon:hide()
                    end
                else
                    widget.ribbon:hide()
                end
            end

            local currentBalance = balance
            if bundle.type == enums.types.gold then
                currentBalance = goldBalance
            end
            if bundle.originalPrice > os.time() and bundle.type == enums.types.gold then
                widget.buttonsBorder.buy:setEnabled(false)
                widget.buttonsBorder.buy:setText(timeLeftToAvailable(bundle.originalPrice))
                widget.buttonsBorder.balance.text:setColor("#c0c0c0")
                widget.buttonsBorder.buy.onLeftClick = nil
            elseif bundle.price > currentBalance then
                widget.buttonsBorder.buy:setEnabled(false)
                widget.buttonsBorder.buy:setText('Adquirir ja!')
                widget.buttonsBorder.balance.text:setColor("#d33c3cff")
                widget.buttonsBorder.buy.onLeftClick = nil
            else
                widget.buttonsBorder.buy:setEnabled(true)
                widget.buttonsBorder.buy:setText('Adquirir ja!')
                widget.buttonsBorder.balance.text:setColor("#6be277ff")
                widget.buttonsBorder.buy.onLeftClick = function()
                    if bundle.type ~= enums.types.gold then
                        if BundlesConfirmationWindow ~= nil then
                            BundlesConfirmationWindow:destroy()
                            BundlesConfirmationWindow = nil
                        end

                        BundlesWindow:hide()

                        BundlesConfirmationWindow = g_ui.displayUI('confirm')
                        BundlesConfirmationWindow:hide()

                        BundlesConfirmationWindow.header:setText("Tem certeza que quer comprar o pacote '" .. bundle.name .. "'?")
                        BundlesConfirmationWindow.item:setItemId(bundle.chest)
                        BundlesConfirmationWindow.name:setText(bundle.name)
                        BundlesConfirmationWindow.price:setText(comma_value(bundle.price))

                        BundlesConfirmationWindow.buy.onLeftClick = function()
                            closeConfirmation()
                            show()
                            bundlesBuy(bundle.id)
                        end

                        BundlesConfirmationWindow:show()
                        BundlesConfirmationWindow:raise()
                        BundlesConfirmationWindow:focus()
                    else
                        if BundlesConfirmationWindow ~= nil then
                            BundlesConfirmationWindow:destroy()
                            BundlesConfirmationWindow = nil
                        end

                        local yesCallback = function()
                            if BundlesConfirmationWindow ~= nil then
                                BundlesConfirmationWindow:hide()
                                BundlesConfirmationWindow:destroy()
                                BundlesConfirmationWindow = nil
                            end

                            BundlesWindow:show()
                            BundlesWindow:focus()
                            bundlesBuy(bundle.id)
                        end

                        local noCallback = function()
                            if BundlesConfirmationWindow ~= nil then
                                BundlesConfirmationWindow:hide()
                                BundlesConfirmationWindow:destroy()
                                BundlesConfirmationWindow = nil
                            end

                            BundlesWindow:show()
                            BundlesWindow:focus()
                        end

                        BundlesWindow:hide()
                        BundlesConfirmationWindow = displayGeneralBox("Confirmar compra", "Tem certeza que quer comprar o pacote '" .. bundle.name .. "'?\n\nSerá debitado " .. comma_value(bundle.price) .. " gold coins e a proxima compra estara disponivel na proxima semana.", {
                        { text = 'No', callback = noCallback },
                        { text = 'Yes', callback = yesCallback },
                        anchor = AnchorHorizontalCenter
                        }, yesCallback, noCallback)
                    end
                end
            end
        end
    end

    if BundlesWindow.list:getChildCount() > 3 then
        BundlesWindow:setWidth(1310)
    else
        BundlesWindow:setWidth(1290)
    end

    if hasGoldBundle then
        BundlesWindow.specialList:getChildByIndex(1):show()
    else
        BundlesWindow.specialList:getChildByIndex(1):hide()
    end

    show()
end
