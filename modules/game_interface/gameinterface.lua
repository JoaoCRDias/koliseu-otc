gameRootPanel = nil
gameMapPanel = nil
gameMainRightPanel = nil
gameRightPanel = nil
gameRightExtraPanel = nil
gameRightExtraPanel2 = nil
gameRightExtraPanel3 = nil
gameLeftPanel = nil
gameLeftExtraPanel = nil
gameLeftExtraPanel2 = nil
gameLeftExtraPanel3 = nil
gameSelectedPanel = nil
panelsList = {}
panelsRadioGroup = nil
gameTopPanel = nil
gameBottomStatsBarPanel = nil
gameBottomPanel = nil
showTopMenuButton = nil
logoutButton = nil
logOutMainButton = nil
mouseGrabberWidget = nil
countWindow = nil
logoutWindow = nil
exitWindow = nil
bottomSplitter = nil
limitedZoom = false
currentViewMode = 0
leftIncreaseSidePanels = nil
leftDecreaseSidePanels = nil
rightIncreaseSidePanels = nil
rightDecreaseSidePanels = nil

gameBottomActionPanel = nil
gameLeftActionPanel = nil
gameRightActionPanel = nil
gameBottomLockPanel = nil
gameRightLockPanel = nil
gameLeftLockPanel = nil

hookedMenuOptions = {}
focusReason = {}
local lastStopAction = 0

local mobileConfig = {
    mobileWidthJoystick = 0,
    mobileWidthShortcuts = 0,
    mobileHeightJoystick = 0,
    mobileHeightShortcuts = 0
}

-- Smart Follow (game_helper): mesmo fluxo Balrorg/Hylian apos g_game.follow
local function notifySmartFollowAfterFollow(creature)
    if creature and modules.game_helper and modules.game_helper.notifySmartFollowFollowTarget then
        modules.game_helper.notifySmartFollowFollowTarget(creature)
    end
end

function refreshSidePanelButtons()
    if not leftIncreaseSidePanels or not modules.client_options then
        return
    end
    local leftFull = modules.client_options.getOption('showLeftPanel') and
        modules.client_options.getOption('showLeftExtraPanel') and
        modules.client_options.getOption('showLeftExtraPanel2') and
        modules.client_options.getOption('showLeftExtraPanel3')
    leftIncreaseSidePanels:setEnabled(not leftFull)
    if g_platform.isMobile() then
        leftDecreaseSidePanels:setEnabled(false)
    else
        local hasLeftPanels = modules.client_options.getOption('showLeftPanel') or
            modules.client_options.getOption('showLeftExtraPanel') or
            modules.client_options.getOption('showLeftExtraPanel2') or
            modules.client_options.getOption('showLeftExtraPanel3')
        leftDecreaseSidePanels:setEnabled(hasLeftPanels)
    end
    local rightFull = modules.client_options.getOption('showRightExtraPanel') and
        modules.client_options.getOption('showRightExtraPanel2') and
        modules.client_options.getOption('showRightExtraPanel3')
    rightIncreaseSidePanels:setEnabled(not rightFull)
    rightDecreaseSidePanels:setEnabled(modules.client_options.getOption('showRightExtraPanel') or
        modules.client_options.getOption('showRightExtraPanel2') or
        modules.client_options.getOption('showRightExtraPanel3'))
end

function init()
    g_ui.importStyle('styles/countwindow')
    g_ui.importStyle('styles/countStashWindow')
    connect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onLoginAdvice = onLoginAdvice
    }, true)

    -- Call load AFTER game window has been created and
    -- resized to a stable state, otherwise the saved
    -- settings can get overridden by false onGeometryChange
    -- events
    if g_app.hasUpdater() then
        connect(g_app, {
            onUpdateFinished = load,
        })
    else
        connect(g_app, {
            onRun = load,
        })
    end

    connect(g_app, {
        onExit = save
    })

    gameRootPanel = g_ui.displayUI('gameinterface')
    gameRootPanel:hide()
    gameRootPanel:lower()
    gameRootPanel.onGeometryChange = updateStretchShrink

    mouseGrabberWidget = gameRootPanel:getChildById('mouseGrabber')
    mouseGrabberWidget.onMouseRelease = onMouseGrabberRelease

    bottomSplitter = gameRootPanel:getChildById('bottomSplitter')
    gameMapPanel = gameRootPanel:getChildById('gameMapPanel')
    gameMainRightPanel = gameRootPanel:getChildById('gameMainRightPanel')
    gameRightPanel = gameRootPanel:getChildById('gameRightPanel')
    gameRightExtraPanel = gameRootPanel:getChildById('gameRightExtraPanel')
    gameRightExtraPanel2 = gameRootPanel:getChildById('gameRightExtraPanel2')
    gameRightExtraPanel3 = gameRootPanel:getChildById('gameRightExtraPanel3')
    gameLeftExtraPanel = gameRootPanel:getChildById('gameLeftExtraPanel')
    gameLeftExtraPanel2 = gameRootPanel:getChildById('gameLeftExtraPanel2')
    gameLeftExtraPanel3 = gameRootPanel:getChildById('gameLeftExtraPanel3')
    gameLeftPanel = gameRootPanel:getChildById('gameLeftPanel')
    gameBottomPanel = gameRootPanel:getChildById('gameBottomPanel')
    gameTopPanel = gameRootPanel:getChildById('gameTopPanel')
    gameBottomStatsBarPanel = gameRootPanel:getChildById('gameBottomStatsBarPanel')

    leftIncreaseSidePanels = gameRootPanel:getChildById('leftIncreaseSidePanels')
    leftDecreaseSidePanels = gameRootPanel:getChildById('leftDecreaseSidePanels')
    rightIncreaseSidePanels = gameRootPanel:getChildById('rightIncreaseSidePanels')
    rightDecreaseSidePanels = gameRootPanel:getChildById('rightDecreaseSidePanels')

    gameBottomActionPanel = gameRootPanel:getChildById('gameBottomActionPanel')
    gameRightActionPanel = gameRootPanel:getChildById('gameRightActionPanel')
    gameLeftActionPanel = gameRootPanel:getChildById('gameLeftActionPanel')
    gameBottomLockPanel = gameRootPanel:recursiveGetChildById('bottomLock')
    gameRightLockPanel = gameRootPanel:recursiveGetChildById('rightLock')
    gameLeftLockPanel = gameRootPanel:recursiveGetChildById('leftLock')

    refreshSidePanelButtons()

    if g_platform.isMobile() then
        gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
        gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
    end

    panelsList = { {
        panel = gameRightPanel,
        checkbox = gameRootPanel:getChildById('gameSelectRightColumn')
    }, {
        panel = gameRightExtraPanel,
        checkbox = gameRootPanel:getChildById('gameSelectRightExtraColumn')
    }, {
        panel = gameRightExtraPanel2,
        checkbox = gameRootPanel:getChildById('gameSelectRightExtraColumn2')
    }, {
        panel = gameRightExtraPanel3,
        checkbox = gameRootPanel:getChildById('gameSelectRightExtraColumn3')
    }, {
        panel = gameLeftPanel,
        checkbox = gameRootPanel:getChildById('gameSelectLeftColumn')
    }, {
        panel = gameLeftExtraPanel,
        checkbox = gameRootPanel:getChildById('gameSelectLeftExtraColumn')
    }, {
        panel = gameLeftExtraPanel2,
        checkbox = gameRootPanel:getChildById('gameSelectLeftExtraColumn2')
    }, {
        panel = gameLeftExtraPanel3,
        checkbox = gameRootPanel:getChildById('gameSelectLeftExtraColumn3')
    } }

    panelsRadioGroup = UIRadioGroup.create()
    for k, v in pairs(panelsList) do
        panelsRadioGroup:addWidget(v.checkbox)
        connect(v.checkbox, {
            onCheckChange = onSelectPanel
        })
    end
    panelsRadioGroup:selectWidget(panelsList[1].checkbox)

    logoutButton = modules.client_topmenu.addTopRightToggleButton('logoutButton', tr('Exit'), '/images/topbuttons/logout',
        tryLogout, true)

    gameMapPanel.onClick = toggleInternalFocus
    gameRightPanel.onClick = toggleInternalFocus
    gameRightExtraPanel.onClick = toggleInternalFocus
    gameRightExtraPanel2.onClick = toggleInternalFocus
    gameRightExtraPanel3.onClick = toggleInternalFocus
    gameLeftExtraPanel.onClick = toggleInternalFocus
    gameLeftExtraPanel2.onClick = toggleInternalFocus
    gameLeftExtraPanel3.onClick = toggleInternalFocus
    gameLeftPanel.onClick = toggleInternalFocus
    gameBottomPanel.onClick = toggleInternalFocus

    showTopMenuButton = gameMapPanel:getChildById('showTopMenuButton')
    showTopMenuButton.onClick = function()
        modules.client_topmenu.toggle()
    end

    bindKeys()

    if g_game.isOnline() then
        show()
    end

    StatsBar.init()
end

function bindKeys()
    local keyboardDelay = g_settings.getNumber("keyboardDelay")
    if keyboardDelay <= 0 then keyboardDelay = 200 end
    gameRootPanel:setAutoRepeatDelay(keyboardDelay)

    g_keyboard.bindKeyPress('Ctrl+=', function()
        gameMapPanel:zoomIn()
    end, gameRootPanel)
    g_keyboard.bindKeyPress('Ctrl+-', function()
        gameMapPanel:zoomOut()
    end, gameRootPanel)

    Keybind.new("Movement", "Stop All Actions", "Escape", "", true)
    Keybind.bind("Movement", "Stop All Actions", {
        {
            type = KEY_PRESS,
            callback = function()
                if lastStopAction + 50 > g_clock.millis() then return end
                lastStopAction = g_clock.millis()
                g_game.cancelAttackAndFollow()
            end,
        }
    }, gameRootPanel)

    Keybind.new("Misc", "Logout", "Ctrl+L", "Ctrl+Q")
    Keybind.bind("Misc", "Logout", {
        {
            type = KEY_PRESS,
            callback = function() tryLogout(false) end,
        }
    }, gameRootPanel)

    Keybind.new("UI", "Clear All Texts", "Ctrl+W", "")
    Keybind.bind("UI", "Clear All Texts", {
        {
            type = KEY_DOWN,
            callback = function()
                g_map.cleanTexts()
                modules.game_textmessage.clearMessages()
            end,
        }
    }, gameRootPanel)

    Keybind.new("Combat", "Toggle Chase Mode", "", "")
    Keybind.bind("Combat", "Toggle Chase Mode", {
        {
            type = KEY_DOWN,
            callback = toggleChaseMode,
        }
    }, gameRootPanel)

    g_keyboard.bindKeyDown('Ctrl+.', nextViewMode, gameRootPanel)
end

function terminate()
    StatsBar.terminate()

    hide()
    if g_app.hasUpdater() then
        disconnect(g_app, {
            onUpdateFinished = load,
        })
    else
        disconnect(g_app, {
            onRun = load,
        })
    end
    disconnect(g_app, {
        onExit = save,
    })

    hookedMenuOptions = {}

    disconnect(g_game, {
        onGameStart = onGameStart,
        onGameEnd = onGameEnd,
        onLoginAdvice = onLoginAdvice
    })

    for k, v in pairs(panelsList) do
        disconnect(v.checkbox, {
            onCheckChange = onSelectPanel
        })
    end

    logoutButton:destroy()
    gameRootPanel:destroy()
    Keybind.delete("Movement", "Stop All Actions")
    Keybind.delete("Misc", "Logout")
    Keybind.delete("UI", "Clear All Texts")
    Keybind.delete("Combat", "Toggle Chase Mode")
end

function onGameStart()
    show()

    refreshSidePanelButtons()

    if g_platform.isMobile() then
        gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
        gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
    end

    -- Initialize horizontal left panel based on saved option
    showLeftHorizontalPanel(modules.client_options.getOption('showHorizontalLeftPanel'))

    -- Initialize horizontal right panel based on saved option
    showRightHorizontalPanel(modules.client_options.getOption('showHorizontalRightPanel'))

    -- Restore widgets to horizontal panels from saved settings
    -- Use scheduleEvent to ensure all modules have been initialized
    scheduleEvent(function()
        restoreHorizontalPanelWidgets()
    end, 25)

    scheduleEvent(function()
        if modules.game_minimap and modules.game_minimap.tryAutoPlaceMinimapForHorizontalPanels then
            modules.game_minimap.tryAutoPlaceMinimapForHorizontalPanels()
        end
    end, 35)

    -- Auto-fit gameMainRightPanel height after all modules loaded
    scheduleEvent(function()
        if gameMainRightPanel and gameMainRightPanel.fitAllChildren then
            gameMainRightPanel:fitAllChildren()
        end
    end, 50)
end

function onGameEnd()
    hide()
end

function show()
    connect(g_app, {
        onClose = tryExit
    })
    modules.client_background.hide()
    -- Fundo de login fica por baixo do jogo (evita textura da tela inicial por cima dos painéis)
    if modules.client_background.getBackground then
        local bg = modules.client_background.getBackground()
        if bg then
            bg:lower()
        end
    end
    gameRootPanel:raise()
    gameRootPanel:show()
    gameRootPanel:focus()
    gameMapPanel:followCreature(g_game.getLocalPlayer())

    updateStretchShrink()
    logoutButton:setTooltip(tr('Logout'))

    setupViewMode(0)
    if g_platform.isMobile() then
        mobileConfig.mobileWidthJoystick = modules.game_joystick.getPanel():getWidth()
        mobileConfig.mobileWidthShortcuts = modules.game_shortcuts.getPanel():getWidth()
        mobileConfig.mobileHeightJoystick = modules.game_joystick.getPanel():getHeight()
        mobileConfig.mobileHeightShortcuts = modules.game_shortcuts.getPanel():getHeight()
        setupViewMode(1)
        setupViewMode(2)
    end

    addEvent(function()
        if not limitedZoom or g_game.isGM() then
            gameMapPanel:setMaxZoomOut(513)
            gameMapPanel:setLimitVisibleRange(false)
        else
            gameMapPanel:setMaxZoomOut(11)
            gameMapPanel:setLimitVisibleRange(true)
        end
    end)
end

function hide()
    setupViewMode(0)

    disconnect(g_app, {
        onClose = tryExit
    })
    logoutButton:setTooltip(tr('Exit'))

    if logoutWindow then
        logoutWindow:destroy()
        logoutWindow = nil
    end
    if exitWindow then
        exitWindow:destroy()
        exitWindow = nil
    end
    if countWindow then
        countWindow:destroy()
        countWindow = nil
    end
    gameRootPanel:hide()
    gameRootPanel:lower()
    modules.client_background.show()
end

function save()
    local settings = {}
    settings.splitterMarginBottom = bottomSplitter:getMarginBottom()
    g_settings.setNode('game_interface', settings)
end

function load()
    local settings = g_settings.getNode('game_interface')
    if settings then
        if settings.splitterMarginBottom then
            bottomSplitter:setMarginBottom(settings.splitterMarginBottom)
        end
    end
end

function onLoginAdvice(message)
    displayInfoBox(tr('For Your Information'), message)
end

function forceExit()
    g_game.cancelLogin()
    scheduleEvent(exit, 10)
    return true
end

function tryExit()
    if exitWindow then
        return true
    end

    local exitFunc = function()
        g_game.safeLogout()
        forceExit()
    end
    local logoutFunc = function()
        g_game.safeLogout()
        exitWindow:destroy()
        exitWindow = nil
    end
    local cancelFunc = function()
        exitWindow:destroy()
        exitWindow = nil
    end

    exitWindow = displayGeneralBox(tr('Exit'), tr(
            'If you shut down the program, your character might stay in the game.\nClick on \'Logout\' to ensure that you character leaves the game properly.\nClick on \'Exit\' if you want to exit the program without logging out your character.'),
        {
            {
                text = tr('Force Exit'),
                callback = exitFunc
            },
            {
                text = tr('Logout'),
                callback = logoutFunc
            },
            {
                text = tr('Cancel'),
                callback = cancelFunc
            },
            anchor = AnchorHorizontalCenter
        }, logoutFunc, cancelFunc)

    g_keyboard.bindKeyPress("E", exitFunc, exitWindow)
    g_keyboard.bindKeyPress("L", logoutFunc, exitWindow)
    g_keyboard.bindKeyPress("Escape", cancelFunc, exitWindow)
    return true
end

function tryLogout(prompt)
    if type(prompt) ~= 'boolean' then
        prompt = true
    end
    if not g_game.isOnline() then
        exit()
        return
    end

    if logoutWindow then
        return
    end

    local msg, yesCallback
    if not g_game.isConnectionOk() then
        msg =
        'Your connection is failing, if you logout now your character will be still online, do you want to force logout?'

        yesCallback = function()
            g_game.forceLogout()
            if logoutWindow then
                logoutWindow:destroy()
                logoutWindow = nil
            end
        end
    else
        msg = 'Are you sure you want to logout?'

        yesCallback = function()
            g_game.safeLogout()
            if logoutWindow then
                logoutWindow:destroy()
                logoutWindow = nil
            end
        end
    end

    local noCallback = function()
        logoutWindow:destroy()
        logoutWindow = nil
    end

    if prompt then
        logoutWindow = displayGeneralBox(tr('Logout'), tr(msg), {
            {
                text = tr('No'),
                callback = noCallback
            },
            {
                text = tr('Yes'),
                callback = yesCallback
            },
            anchor = AnchorHorizontalCenter
        }, yesCallback, noCallback)
    else
        yesCallback()
    end
end

function updateStretchShrink()
    if modules.client_options.getOption('dontStretchShrink') and not alternativeView then
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })

        -- Set gameMapPanel size to height = 11 * 32 + 2
        bottomSplitter:setMarginBottom(bottomSplitter:getMarginBottom() + (gameMapPanel:getHeight() - 32 * 11) - 10)
    end
    -- Update action bar layout when window geometry changes
    if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
        addEvent(function()
            modules.game_actionbar.updateVisibleWidgetsExternal()
        end)
    end
end

function onMouseGrabberRelease(self, mousePosition, mouseButton)
    if selectedThing == nil then
        return false
    end
    if mouseButton == MouseLeftButton then
        local clickedWidget = gameRootPanel:recursiveGetChildByPos(mousePosition, false)
        if clickedWidget then
            if selectedType == 'use' then
                onUseWith(clickedWidget, mousePosition)
            elseif selectedType == 'trade' then
                onTradeWith(clickedWidget, mousePosition)
            end
        end
    end

    selectedThing = nil
    g_mouse.popCursor('target')
    self:ungrabMouse()
    return true
end

function onUseWith(clickedWidget, mousePosition)
    if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            if selectedThing:isFluidContainer() or selectedThing:isMultiUse() then
                g_game.useWith(selectedThing, tile:getTopMultiUseThing())
            else
                g_game.useWith(selectedThing, tile:getTopUseThing())
            end
        end
    elseif clickedWidget:getClassName() == 'UIItem' and not clickedWidget:isVirtual() then
        g_game.useWith(selectedThing, clickedWidget:getItem())
    elseif clickedWidget:getClassName() == 'UICreatureButton' then
        local creature = clickedWidget:getCreature()
        if creature then
            g_game.useWith(selectedThing, creature)
        end
    end
end

function onTradeWith(clickedWidget, mousePosition)
    if clickedWidget:getClassName() == 'UIGameMap' then
        local tile = clickedWidget:getTile(mousePosition)
        if tile then
            g_game.requestTrade(selectedThing, tile:getTopCreature())
        end
    elseif clickedWidget:getClassName() == 'UICreatureButton' then
        local creature = clickedWidget:getCreature()
        if creature then
            g_game.requestTrade(selectedThing, creature)
        end
    end
end

function startUseWith(thing)
    if not thing then
        return
    end
    if g_ui.isMouseGrabbed() then
        if selectedThing then
            selectedThing = thing
            selectedType = 'use'
        end
        return
    end
    selectedType = 'use'
    selectedThing = thing
    mouseGrabberWidget:grabMouse()
    g_mouse.pushCursor('target')
end

function startTradeWith(thing)
    if not thing then
        return
    end
    if g_ui.isMouseGrabbed() then
        if selectedThing then
            selectedThing = thing
            selectedType = 'trade'
        end
        return
    end
    selectedType = 'trade'
    selectedThing = thing
    mouseGrabberWidget:grabMouse()
    g_mouse.pushCursor('target')
end

function isMenuHookCategoryEmpty(category)
    if category then
        for _, opt in pairs(category) do
            if opt then
                return false
            end
        end
    end
    return true
end

-- addMenuHook aceita um objeto com as seguintes propriedades:
-- {
--   category = "categoria",      -- (obrigatório) categoria do hook
--   option = "Nome da Opção",    -- (obrigatório) texto exibido no menu
--   callback = function() end,   -- (obrigatório) função executada ao clicar
--   condition = function() end,  -- (opcional) função que retorna true/false para mostrar a opção
--   shortcut = "Ctrl+X",         -- (opcional) atalho de teclado
--   color = "#FFFFFF"            -- (opcional) cor do texto
-- }
function addMenuHook(opts)
    if not opts.category or not opts.option then
        return
    end

    if not hookedMenuOptions[opts.category] then
        hookedMenuOptions[opts.category] = {}
    end

    hookedMenuOptions[opts.category][opts.option] = {
        callback = opts.callback,
        condition = opts.condition or function() return true end,
        shortcut = opts.shortcut,
        color = opts.color
    }
end

-- removeMenuHook aceita um objeto:
-- { category = "categoria", option = "Nome da Opção" }
-- Se option não for passado, remove toda a categoria
function removeMenuHook(opts)
    if not opts.category then
        return
    end

    if not opts.option then
        hookedMenuOptions[opts.category] = {}
    else
        if hookedMenuOptions[opts.category] then
            hookedMenuOptions[opts.category][opts.option] = nil
        end
    end
end

local ITEM_LOOT_POUCH_ID = 23721
local REWARD_CHEST_ID = 19250
local rewardChestIds = { [REWARD_CHEST_ID] = true }

-- Client ids extra de item-raiz de container que contam como depot (além de Item:isDepot() no C++, ex. 3499).
-- Se o Stow não aparecer, abre o locker e coloca aqui o id do item do container (não o do arco na mochila).
local EXTRA_DEPOT_CONTAINER_ITEM_IDS = {
    -- [35000] = true,
}

-- Stow só com contexto de depósito: janela do stash, item raiz com isDepot / ids acima, ou nome da janela.
-- Não exigimos isSupplyStashAvailable() aqui: muitos OTs não enviam o pacote no depot; o servidor valida o Stow.
local function containerNameLooksLikeDepotContext(name)
    if not name or name == "" then
        return false
    end
    local n = name:lower()
    local hints = { "locker", "depot", "depot box" }
    for _, hint in ipairs(hints) do
        if n:find(hint, 1, true) then
            return true
        end
    end
    return false
end

local function containerRootItemIsDepotLike(ci)
    if not ci then
        return false
    end
    if ci.isDepot and ci:isDepot() then
        return true
    end
    local rootId = ci:getId()
    return EXTRA_DEPOT_CONTAINER_ITEM_IDS[rootId] == true
end

local function isSupplyStashDepotContextActive()
    local function isPlayerNearDepotLocker()
        local player = g_game.getLocalPlayer()
        if not player then
            return false
        end
        local pos = player:getPosition()
        if not pos then
            return false
        end

        -- Tibia behavior: Stow actions are available when you're standing next to a depot/locker,
        -- even if the inbox/container isn't open.
        for dx = -1, 1 do
            for dy = -1, 1 do
                local tile = g_map.getTile({ x = pos.x + dx, y = pos.y + dy, z = pos.z })
                if tile then
                    local topUse = tile:getTopUseThing()
                    if topUse and topUse.isDepot and topUse:isDepot() then
                        return true
                    end

                    local items = tile:getItems()
                    if items then
                        for _, item in ipairs(items) do
                            if item and item.isDepot and item:isDepot() then
                                return true
                            end
                        end
                    end
                end
            end
        end
        return false
    end

    if isPlayerNearDepotLocker() then
        return true
    end

    local stashMod = modules.game_stash
    if stashMod and stashMod.stashWindow and not stashMod.stashWindow:isHidden() then
        return true
    end
    local containers = g_game.getContainers()
    if not containers then
        return false
    end
    for _, container in pairs(containers) do
        if containerRootItemIsDepotLike(container:getContainerItem()) then
            return true
        end
        if containerNameLooksLikeDepotContext(container:getName()) then
            return true
        end
    end
    return false
end

function createThingMenu(menuPosition, lookThing, useThing, creatureThing)
    if not g_game.isOnline() then
        return
    end

    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    local classic = modules.client_options.getOption('classicControl')
    local smartLeftClick = modules.client_options.getOption('smartLeftClick')
    local mobile = g_platform.isMobile()
    local shortcut = nil

    if not classic and not mobile and not smartLeftClick then
        shortcut = '(Shift)'
    else
        shortcut = nil
    end
    if lookThing then
        menu:addOption(tr('Look'), function()
            g_game.look(lookThing)
        end, shortcut)

        if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
            menu:addOption(tr('Inspect'), function() g_game.inspectionNormalObject(lookThing:getPosition()) end)
            if lookThing.isCyclopediaItem and lookThing:isCyclopediaItem() then
                menu:addOption(tr('Cyclopedia'),
                    function() modules.game_cyclopedia.Cyclopedia.Items.onRedirect(lookThing:getId()) end)
            end
            if lookThing.getProficiencyId and lookThing:getProficiencyId() > 0 then
                menu:addOption(tr('Weapon Proficiency'),
                    function() modules.game_proficiency.requestOpenWindow(lookThing) end)
            end
        end
    end

    if not classic and not mobile then
        shortcut = '(Ctrl)'
    else
        shortcut = nil
    end
    if useThing then
        if useThing:isContainer() then
            if useThing:getParentContainer() then
                menu:addOption(tr('Open'), function()
                    g_game.open(useThing, useThing:getParentContainer())
                end, shortcut)
                menu:addOption(tr('Open in new window'), function()
                    g_game.open(useThing)
                end)
            else
                menu:addOption(tr('Open'), function()
                    g_game.open(useThing)
                end, shortcut)
            end
        else
            if useThing:isMultiUse() then
                menu:addOption(tr('Use with ...'), function()
                    startUseWith(useThing)
                end, shortcut)
            else
                menu:addOption(tr('Use'), function()
                    g_game.use(useThing)
                end, shortcut)
            end
        end

        if useThing:isRotateable() then
            menu:addOption(tr('Rotate'), function()
                g_game.rotate(useThing)
            end)
        end

        local onWrapItem = function()
            g_game.wrap(useThing)
        end
        if useThing:isWrapable() then
            menu:addOption(tr('Wrap'), onWrapItem)
        end
        if useThing:isUnwrapable() then
            menu:addOption(tr('Unwrap'), onWrapItem)
        end

        if rewardChestIds[useThing:getId()] and g_game.requestRewardChestCollect then
            menu:addOption(tr('Collect all'),
                function()
                    g_game.requestRewardChestCollect(useThing:getPosition(), useThing:getId(),
                        useThing:getStackPos())
                end)
        end

        if g_game.getFeature(GameBrowseField) and useThing:getPosition().x ~= 0xffff then
            menu:addOption(tr('Browse Field'), function()
                g_game.browseField(useThing:getPosition())
            end)
        end
        if useThing:isLyingCorpse() and g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot and useThing:getPosition().x ~= 0xffff then
            menu.addOption(menu, tr("Loot corpse"), function()
                g_game.sendQuickLoot(1, useThing)
            end)
        end
    end

    if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
        menu:addSeparator()
        menu:addOption(tr('Trade with ...'), function()
            startTradeWith(lookThing)
        end)
    end

    if lookThing then
        local parentContainer = lookThing:getParentContainer()
        if parentContainer and parentContainer:hasParent() then
            menu:addOption(tr('Move up'), function()
                g_game.moveToParentContainer(lookThing, lookThing:getCount())
            end)
        end
    end

    if creatureThing then
        local localPlayer = g_game.getLocalPlayer()
        menu:addSeparator()

        if creatureThing:isLocalPlayer() then
            menu:addOption(tr(g_game.getClientVersion() >= 1000 and "Customise Character" or "Set Outfit"), function()
                g_game.requestOutfit()
            end)

            if g_game.getFeature(GamePrey) then
                menu:addOption(tr('Prey Dialog'), function()
                    modules.game_prey.show()
                end)
            end

            if g_game.getFeature(GamePlayerMounts) then
                if not localPlayer:isMounted() then
                    menu:addOption(tr('Mount'), function()
                        localPlayer:mount()
                    end)
                else
                    menu:addOption(tr('Dismount'), function()
                        localPlayer:dismount()
                    end)
                end
            end

            if creatureThing:isPartyMember() then
                if creatureThing:isPartyLeader() then
                    if creatureThing:isPartySharedExperienceActive() then
                        menu:addOption(tr('Disable Shared Experience'), function()
                            g_game.partyShareExperience(false)
                        end)
                    else
                        menu:addOption(tr('Enable Shared Experience'), function()
                            g_game.partyShareExperience(true)
                        end)
                    end
                end
                menu:addOption(tr('Leave Party'), function()
                    g_game.partyLeave()
                end)
            end
        else
            local localPosition = localPlayer:getPosition()
            if not classic and not mobile then
                shortcut = '(Alt)'
            else
                shortcut = nil
            end
            if creatureThing:getPosition().z == localPosition.z then
                if g_game.getAttackingCreature() ~= creatureThing then
                    menu:addOption(tr('Attack'), function()
                        g_game.attack(creatureThing)
                    end, shortcut)
                else
                    menu:addOption(tr('Stop Attack'), function()
                        g_game.cancelAttack()
                    end, shortcut)
                end

                if g_game.getFollowingCreature() ~= creatureThing then
                    menu:addOption(tr('Follow'), function()
                        g_game.follow(creatureThing)
                        notifySmartFollowAfterFollow(creatureThing)
                    end)
                else
                    menu:addOption(tr('Stop Follow'), function()
                        g_game.cancelFollow()
                    end)
                end
            end

            if creatureThing:isPlayer() then
                menu:addSeparator()
                local creatureName = creatureThing:getName()
                menu:addOption(tr('Message to %s', creatureName), function()
                    g_game.openPrivateChannel(creatureName)
                end)
                if modules.game_console.getOwnPrivateTab() then
                    menu:addOption(tr('Invite to private chat'), function()
                        g_game.inviteToOwnChannel(creatureName)
                    end)
                    menu:addOption(tr('Exclude from private chat'), function()
                        g_game.excludeFromOwnChannel(creatureName)
                    end) -- [TODO] must be removed after message's popup labels been implemented
                end
                if not localPlayer:hasVip(creatureName) then
                    menu:addOption(tr('Add to VIP list'), function()
                        g_game.addVip(creatureName)
                    end)
                end

                if modules.game_console.isIgnored(creatureName) then
                    menu:addOption(tr('Unignore') .. ' ' .. creatureName, function()
                        modules.game_console.removeIgnoredPlayer(creatureName)
                    end)
                else
                    menu:addOption(tr('Ignore') .. ' ' .. creatureName, function()
                        modules.game_console.addIgnoredPlayer(creatureName)
                    end)
                end

                local localPlayerShield = localPlayer:getShield()
                local creatureShield = creatureThing:getShield()

                if localPlayerShield == ShieldNone or localPlayerShield == ShieldWhiteBlue then
                    if creatureShield == ShieldWhiteYellow then
                        menu:addOption(tr('Join %s\'s Party', creatureThing:getName()), function()
                            g_game.partyJoin(creatureThing:getId())
                        end)
                    else
                        menu:addOption(tr('Invite to Party'), function()
                            g_game.partyInvite(creatureThing:getId())
                        end)
                    end
                elseif localPlayerShield == ShieldWhiteYellow then
                    if creatureShield == ShieldWhiteBlue then
                        menu:addOption(tr('Revoke %s\'s Invitation', creatureThing:getName()), function()
                            g_game.partyRevokeInvitation(creatureThing:getId())
                        end)
                    end
                elseif localPlayerShield == ShieldYellow or localPlayerShield == ShieldYellowSharedExp or
                    localPlayerShield == ShieldYellowNoSharedExpBlink or localPlayerShield == ShieldYellowNoSharedExp then
                    if creatureShield == ShieldWhiteBlue then
                        menu:addOption(tr('Revoke %s\'s Invitation', creatureThing:getName()), function()
                            g_game.partyRevokeInvitation(creatureThing:getId())
                        end)
                    elseif creatureShield == ShieldBlue or creatureShield == ShieldBlueSharedExp or creatureShield ==
                        ShieldBlueNoSharedExpBlink or creatureShield == ShieldBlueNoSharedExp then
                        menu:addOption(tr('Pass Leadership to %s', creatureThing:getName()), function()
                            g_game.partyPassLeadership(creatureThing:getId())
                        end)
                    else
                        menu:addOption(tr('Invite to Party'), function()
                            g_game.partyInvite(creatureThing:getId())
                        end)
                    end
                end
            end
        end

        if modules.game_ruleviolation.hasWindowAccess() and creatureThing:isPlayer() then
            menu:addSeparator()
            menu:addOption(tr('Rule Violation'), function()
                modules.game_ruleviolation.show(creatureThing:getName())
            end)
        end

        menu:addSeparator()
        menu:addOption(tr('Copy Name'), function()
            g_window.setClipboardText(creatureThing:getName())
        end)
    end

    -- hooked menu options
    for _, category in pairs(hookedMenuOptions) do
        if not isMenuHookCategoryEmpty(category) then
            menu:addSeparator()
            for name, opt in pairs(category) do
                if opt and opt.condition(menuPosition, lookThing, useThing, creatureThing) then
                    local optionWidget = menu:addOption(name, function()
                        opt.callback(menuPosition, lookThing, useThing, creatureThing)
                    end, opt.shortcut)
                    if optionWidget and opt.color then
                        optionWidget:setColor(opt.color)
                    end
                end
            end
        end
    end

    if modules.game_bot and useThing and useThing:isItem() then
        menu:addSeparator()
        local useThingId = useThing:getId()
        menu:addOption("ID: " .. useThingId, function() g_window.setClipboardText(useThingId) end)
    end

    if g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot and lookThing and not lookThing:isCreature() and lookThing:isPickupable() and lookThing:getId() ~= ITEM_LOOT_POUCH_ID then
        local quickLoot = modules.game_quickloot.QuickLoot
        menu.addSeparator(menu)

        if lookThing:isContainer() then
            menu.addOption(menu, tr("Manage Loot Containers"), function()
                quickLoot.toggle()
            end)
        end

        local lootExists = quickLoot.lootExists(lookThing:getId())
        local optionText = lootExists and "Remove from" or "Add to"
        local actionFunction = lootExists and quickLoot.removeLootList or quickLoot.addLootList

        menu.addOption(menu, tr(optionText .. " loot list"), function()
            actionFunction(lookThing:getId())
        end)

        if modules.game_npctrade.inWhiteList then
            if not modules.game_npctrade.inWhiteList(lookThing:getId()) then
                menu:addOption(tr('Add to Quick Sell BlackList'),
                    function() modules.game_npctrade.addToWhitelist(lookThing:getId()) end)
            else
                menu:addOption(tr('Remove from Quick Sell BlackList'),
                    function() modules.game_npctrade.removeItemInList(lookThing:getId()) end)
            end
        end
    end

    if g_game.getClientVersion() >= 1410 then
        if lookThing and not lookThing:isCreature() and not lookThing:isNotMoveable() and lookThing:isPickupable() then
            local player = g_game.getLocalPlayer()
            -- Contexto depot (locker/stash aberto); não depender só de isSupplyStashAvailable (OTs custom).
            if player and isSupplyStashDepotContextActive() then
                local itemTier = lookThing:getTier() or 0
                if itemTier <= 0 then
                    -- O alvo do Stow é lookThing; useThing pode ser outro em alguns cliques.
                    if not isGoldCoin(lookThing:getId()) and lookThing:isMarketable() then
                        menu:addSeparator()
                        menu:addOption(tr("Stow"), function()
                            stashItem(lookThing)
                        end)
                        menu:addOption(tr("Stow all items of this type"), function()
                            g_game.stashStowItem(lookThing:getPosition(), lookThing:getId(), 0,
                                lookThing:getStackPos(), 2) -- SUPPLY_STASH_ACTION_STOW_STACK
                        end)
                    end
                    local isContainer = lookThing:isContainer()
                    if isContainer then
                        menu:addOption(tr('Stow container\'s content'), function()
                            if modules.client_options.getOption('stowContainer') and
                                modules.game_stash and modules.game_stash.stowContainerContent then
                                modules.game_stash.stowContainerContent(useThing, nil,
                                    false)
                            else
                                g_game.stashStowItem(lookThing:getPosition(), lookThing:getId(), 0,
                                    lookThing:getStackPos(), 1) -- SUPPLY_STASH_ACTION_STOW_CONTAINER
                            end
                        end)
                    end
                end
            end
        end
    end

    menu:display(menuPosition)
end

function processMouseAction(menuPosition, mouseButton, autoWalkPos, lookThing, useThing, creatureThing, attackCreature)
    local keyboardModifiers = g_keyboard.getModifiers()

    if g_platform.isMobile() then
        if mouseButton == MouseRightButton then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        end
        local shortcut = modules.game_shortcuts.getShortcut()
        if shortcut == "look" then
            if lookThing then
                modules.game_shortcuts.resetShortcuts()
                g_game.look(lookThing)
                return true
            end
            return true
        elseif shortcut == "use" then
            if useThing then
                modules.game_shortcuts.resetShortcuts()
                if useThing:isContainer() then
                    if useThing:getParentContainer() then
                        g_game.open(useThing, useThing:getParentContainer())
                    else
                        g_game.open(useThing)
                    end
                    return true
                elseif useThing:isMultiUse() then
                    startUseWith(useThing)
                    return true
                else
                    g_game.use(useThing)
                    return true
                end
            end
            return true
        elseif shortcut == "attack" then
            if attackCreature and attackCreature ~= player then
                modules.game_shortcuts.resetShortcuts()
                g_game.attack(attackCreature)
                return true
            elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                modules.game_shortcuts.resetShortcuts()
                g_game.attack(creatureThing)
                return true
            end
            return true
        elseif shortcut == "follow" then
            if attackCreature and attackCreature ~= player then
                modules.game_shortcuts.resetShortcuts()
                g_game.follow(attackCreature)
                notifySmartFollowAfterFollow(attackCreature)
                return true
            elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                modules.game_shortcuts.resetShortcuts()
                g_game.follow(creatureThing)
                notifySmartFollowAfterFollow(creatureThing)
                return true
            end
            return true
        elseif not autoWalkPos and useThing then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        end
    elseif not modules.client_options.getOption('classicControl') then
        local smartLeftClick = modules.client_options.getOption('smartLeftClick')

        if smartLeftClick and mouseButton == MouseLeftButton and keyboardModifiers == KeyboardNoModifier then
            local player = g_game.getLocalPlayer()

            -- Handle creature attacks first
            if attackCreature and attackCreature ~= player then
                g_game.attack(attackCreature)
                return true
            elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                g_game.attack(creatureThing)
                return true
            elseif useThing then
                -- Handle interactive items first, without looking at them
                if useThing:isUsable() then
                    -- Only use the item, don't look at it
                    if useThing:isContainer() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                        else
                            g_game.open(useThing)
                        end
                        return true
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end

                -- Standard handling for other usable items
                -- For containers (including corpses), only execute quicklooting with Smart Left-Click
                -- Exception: If container has a parent container, open it instead of quicklooting
                if useThing:isContainer() or useThing:isLyingCorpse() then
                    -- Prioritize containers/corpses even if there are creatures on the same tile
                    if useThing:getParentContainer() then
                        -- For containers inside other containers, we want to open them, not quickloot
                        g_game.open(useThing, useThing:getParentContainer())
                        return true
                    elseif useThing:isPickupable() then
                        -- For pickupable containers like quivers, backpacks, etc., open them instead of quicklooting
                        g_game.open(useThing)
                        return true
                    elseif g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                        -- For containers in the world (not inside another container), quickloot
                        g_game.sendQuickLoot(1, useThing)
                        return true
                    end
                elseif useThing:isMultiUse() then
                    startUseWith(useThing)
                    return true
                else
                    local useResult = g_game.use(useThing)

                    if useResult ~= nil then
                        return true
                    end
                end

                -- If we couldn't use the item through any of the above methods,
                -- but it's pickupable, try to pick it up (like in Classic Control mode)
                if useThing:isPickupable() then
                    g_game.move(useThing, useThing:getPosition(), 1)
                    return true
                end

                -- If we couldn't use or pick up the item, try to walk to its position if possible
                local position = useThing:getPosition()
                if position and position.x ~= 0 and autoWalkPos then
                    local player = g_game.getLocalPlayer()
                    player:autoWalk(autoWalkPos)
                    return true
                end

                return true
            end

            -- Only look at things if no usable item was found
            if lookThing and lookThing ~= useThing then
                local lookPosition = lookThing:getPosition()
                local lookTile = nil

                if lookPosition and lookPosition.x ~= 0 then
                    lookTile = g_map.getTile(lookPosition)
                end

                -- For walkable tiles, we want to walk
                if lookTile and lookTile:isWalkable() and autoWalkPos then
                    local player = g_game.getLocalPlayer()
                    player:autoWalk(autoWalkPos)
                    return true
                else
                    -- Only look at the thing if we haven't used it already
                    g_game.look(lookThing)
                    return true
                end
            end

            if autoWalkPos then
                local player = g_game.getLocalPlayer()
                player:autoWalk(autoWalkPos)
                return true
            end
        end

        if keyboardModifiers == KeyboardNoModifier and mouseButton == MouseRightButton then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        elseif lookThing and keyboardModifiers == KeyboardShiftModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.look(lookThing)
            return true
        elseif useThing and keyboardModifiers == KeyboardCtrlModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            local smartLeftClick = modules.client_options.getOption('smartLeftClick')

            if smartLeftClick then
                local player = g_game.getLocalPlayer()
                -- For containers in the world, Ctrl+Left Click opens them even if there's a creature
                if (useThing:isContainer() or useThing:isLyingCorpse()) and not useThing:getParentContainer() then
                    g_game.open(useThing)
                    return true
                else
                    createThingMenu(menuPosition, lookThing, useThing, creatureThing)
                    return true
                end
            else
                if useThing:isContainer() then
                    if useThing:getParentContainer() then
                        g_game.open(useThing, useThing:getParentContainer())
                    else
                        g_game.open(useThing)
                    end
                    return true
                elseif useThing:isMultiUse() then
                    startUseWith(useThing)
                    return true
                else
                    g_game.use(useThing)
                    return true
                end
            end
            return true
        elseif useThing and useThing:isContainer() and keyboardModifiers == KeyboardCtrlShiftModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.open(useThing)
            return true
        elseif attackCreature and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(attackCreature)
            return true
        elseif creatureThing and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(creatureThing)
            return true
        end

        -- classic control
    else
        local lootControlMode = modules.client_options.getOption('lootControlMode')
        local player = g_game.getLocalPlayer()

        -- ###############################
        -- ### MODE 0: LOOT RIGHT CLICK ##
        -- ###############################
        if lootControlMode == 0 then
            -- Right click with no modifiers: main loot functionality
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
                -- Handle creature attacks first (match Smart Left-Click behavior)
                if attackCreature and attackCreature ~= player then
                    g_game.attack(attackCreature)
                    return true
                elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                    g_game.attack(creatureThing)
                    return true
                elseif useThing then
                    -- Reward chest: use directly
                    if rewardChestIds[useThing:getId()] then
                        g_game.use(useThing)
                        return true
                    end
                    -- For containers/corpses
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        -- For containers inside other containers, we want to open them
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                            return true
                        elseif useThing:isPickupable() then
                            -- For pickupable containers like quivers, backpacks, etc., open them instead of quicklooting
                            g_game.open(useThing)
                            return true
                        elseif table.find({ 3497, 3498, 3499, 3500, 3502, 12902 }, useThing:getId()) then
                            -- For depot chests, lockers, depot boxes, inbox, etc., always open them
                            g_game.open(useThing)
                            return true
                        elseif g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                            -- For containers in the world, quickloot
                            g_game.sendQuickLoot(1, useThing)
                            return true
                        else
                            g_game.open(useThing)
                            return true
                        end
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end

                -- Handle pickupable items if no container/corpse was handled
                if lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
                    g_game.move(lookThing, lookThing:getPosition(), 1)
                    return true
                end
            end

            -- SHIFT+Right click: opens containers without quicklooting
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardShiftModifier then
                if useThing then
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                        else
                            g_game.open(useThing)
                        end
                        return true
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end
            end

            -- #################################
            -- ### MODE 1: LOOT SHIFT+RIGHT  ###
            -- #################################
        elseif lootControlMode == 1 then
            -- Right click with no modifiers: use or open containers
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
                -- Handle creature attacks first
                if attackCreature and attackCreature ~= player then
                    g_game.attack(attackCreature)
                    return true
                elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                    g_game.attack(creatureThing)
                    return true
                elseif useThing then
                    -- For containers
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                        else
                            g_game.open(useThing)
                        end
                        return true
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end
            end

            -- SHIFT+Right click: quickloot on containers
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardShiftModifier then
                if useThing and (useThing:isContainer() or useThing:isLyingCorpse()) then
                    if g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                        g_game.sendQuickLoot(1, useThing)
                        return true
                    end
                end

                -- Handle pickupable items
                if lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
                    g_game.move(lookThing, lookThing:getPosition(), 1)
                    return true
                end
            end

            -- #############################
            -- ### MODE 2: LOOT LEFT     ###
            -- #############################
        elseif lootControlMode == 2 then
            -- Left click with no modifiers: ONLY for loot functionality
            if mouseButton == MouseLeftButton and keyboardModifiers == KeyboardNoModifier then
                -- ONLY for quicklooting and picking up items, NOT for attacking
                if useThing then
                    -- ONLY quickloot containers/corpses in the game world
                    if (useThing:isContainer() or useThing:isLyingCorpse()) and not useThing:getParentContainer() then
                        -- Only handle containers that are in the game world (not in inventory)
                        if table.find({ 3497, 3498, 3499, 3500, 3502, 12902 }, useThing:getId()) then
                            -- For depot chests, lockers, depot boxes, inbox, etc., always open them
                            g_game.open(useThing)
                            return true
                        elseif g_game.getFeature(GameThingQuickLoot) and modules.game_quickloot then
                            g_game.sendQuickLoot(1, useThing)
                            return true
                        else
                            g_game.open(useThing)
                            return true
                        end
                    end
                end

                -- Handle pickupable items in the game world
                if lookThing and not lookThing:isCreature() and lookThing:isPickupable() then
                    g_game.move(lookThing, lookThing:getPosition(), 1)
                    return true
                end
            end

            -- Right click for Loot: Left mode - use items instead of showing context menu
            if mouseButton == MouseRightButton and keyboardModifiers == KeyboardNoModifier then
                -- Handle creature attacks first
                if attackCreature and attackCreature ~= player then
                    g_game.attack(attackCreature)
                    return true
                elseif creatureThing and creatureThing ~= player and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z then
                    g_game.attack(creatureThing)
                    return true
                    -- Use the item if it's a container in inventory or use other items
                elseif useThing then
                    if useThing:isContainer() or useThing:isLyingCorpse() then
                        if useThing:getParentContainer() then
                            g_game.open(useThing, useThing:getParentContainer())
                            return true
                        else
                            g_game.open(useThing)
                            return true
                        end
                    elseif useThing:isMultiUse() then
                        startUseWith(useThing)
                        return true
                    else
                        g_game.use(useThing)
                        return true
                    end
                end

                -- Only show context menu when no usable item is present
                if not useThing then
                    createThingMenu(menuPosition, lookThing, useThing, creatureThing)
                    return true
                end
            end
        end

        -- Common key combinations for all Classic Control modes
        if useThing and useThing:isContainer() and keyboardModifiers == KeyboardCtrlShiftModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.open(useThing)
            return true
        elseif lookThing and keyboardModifiers == KeyboardShiftModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.look(lookThing)
            return true
        elseif lookThing and ((g_mouse.isPressed(MouseLeftButton) and mouseButton == MouseRightButton) or
                (g_mouse.isPressed(MouseRightButton) and mouseButton == MouseLeftButton)) then
            g_game.look(lookThing)
            return true
        elseif useThing and keyboardModifiers == KeyboardCtrlModifier and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            createThingMenu(menuPosition, lookThing, useThing, creatureThing)
            return true
        elseif attackCreature and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(attackCreature)
            return true
        elseif creatureThing and autoWalkPos and creatureThing:getPosition().z == autoWalkPos.z and g_keyboard.isAltPressed() and
            (mouseButton == MouseLeftButton or mouseButton == MouseRightButton) then
            g_game.attack(creatureThing)
            return true
        end
    end

    local player = g_game.getLocalPlayer()
    player:stopAutoWalk()

    if autoWalkPos and keyboardModifiers == KeyboardNoModifier and mouseButton == MouseLeftButton then
        -- In Classic Control with Loot: Left option, we want to avoid walking when trying to loot
        local classicControl = modules.client_options.getOption('classicControl')
        local lootControlMode = modules.client_options.getOption('lootControlMode')

        if classicControl and lootControlMode == 2 then
            -- Check if there's a corpse or item we should be looting instead of walking
            -- If not, proceed with autowalk
            local isCorpseOrContainer = useThing and (useThing:isContainer() or useThing:isLyingCorpse())

            if not isCorpseOrContainer and
                not (lookThing and not lookThing:isCreature() and lookThing:isPickupable()) then
                player:autoWalk(autoWalkPos)
                if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
                    g_game.setChaseMode(DontChase)
                end
            end
        else
            player:autoWalk(autoWalkPos)
            if g_game.isAttacking() and g_game.getChaseMode() == ChaseOpponent then
                g_game.setChaseMode(DontChase)
            end
        end
        return true
    end

    return false
end

function handleItemInteraction(item, widget, callback, cancelCallback)
    local count = math.min(10000, item:getCount())
    local itembox = widget:recursiveGetChildById('item')
    local scrollbar = widget:recursiveGetChildById('countScrollBar')
    itembox:setItemId(item:getId())
    itembox:setItemCount(count)
    scrollbar:setMaximum(count)
    scrollbar:setMinimum(1)
    scrollbar:setValue(count)

    local spinbox = widget:recursiveGetChildById('spinBox')
    spinbox:setMaximum(count)
    spinbox:setMinimum(0)
    spinbox:setValue(0)
    spinbox:hideButtons()
    spinbox:focus()
    spinbox.firstEdit = true

    local spinBoxValueChange = function(self, value)
        spinbox.firstEdit = false
        scrollbar:setValue(value)
    end
    spinbox.onValueChange = spinBoxValueChange

    local check = function()
        if spinbox.firstEdit then
            spinbox:setValue(spinbox:getMaximum())
            spinbox.firstEdit = false
        end
    end
    g_keyboard.bindKeyPress('Up', function()
        check()
        spinbox:upSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Down', function()
        check()
        spinbox:downSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Right', function()
        check()
        spinbox:upSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('Left', function()
        check()
        spinbox:downSpin()
    end, spinbox)
    g_keyboard.bindKeyPress('PageUp', function()
        check()
        spinbox:setValue(spinbox:getValue() + 10)
    end, spinbox)
    g_keyboard.bindKeyPress('PageDown', function()
        check()
        spinbox:setValue(spinbox:getValue() - 10)
    end, spinbox)

    scrollbar.onValueChange = function(self, value)
        itembox:setItemCount(value)
        spinbox.onValueChange = nil
        spinbox:setValue(value)
        spinbox.onValueChange = spinBoxValueChange
    end
    local okButton = widget:recursiveGetChildById('buttonOk')
    local cancelButton = widget:recursiveGetChildById('buttonCancel')

    local function cleanupAndDestroy()
        -- Unbind keyboard events
        g_keyboard.unbindKeyPress('Up', spinbox)
        g_keyboard.unbindKeyPress('Down', spinbox)
        g_keyboard.unbindKeyPress('Right', spinbox)
        g_keyboard.unbindKeyPress('Left', spinbox)
        g_keyboard.unbindKeyPress('PageUp', spinbox)
        g_keyboard.unbindKeyPress('PageDown', spinbox)

        -- Clear callbacks to release references
        spinbox.onValueChange = nil
        scrollbar.onValueChange = nil
        scrollbar.onClick = nil
        widget.onEnter = nil
        widget.onEscape = nil
        okButton.onClick = nil
        cancelButton.onClick = nil

        -- Clear scrollbar button references
        local decrementButton = scrollbar:getChildById('decrementButton')
        local incrementButton = scrollbar:getChildById('incrementButton')
        if decrementButton then decrementButton.onClick = nil end
        if incrementButton then incrementButton.onClick = nil end

        -- Destroy the widget
        widget:destroy()
    end

    local moveFunc = function()
        local itemCount = itembox:getItemCount()
        cleanupAndDestroy()
        callback(itemCount)
    end

    local cancelFunc = function()
        cleanupAndDestroy()
        if cancelCallback then
            cancelCallback()
        end
    end

    widget.onEnter = moveFunc
    widget.onEscape = cancelFunc
    okButton.onClick = moveFunc
    cancelButton.onClick = cancelFunc
end

function stashItem(item)
    local count = item:getCount()
    if count == 1 then
        g_game.stashStowItem(item:getPosition(), item:getId(), count,
            item:getStackPos(), 0)
        return
    end
    countWindow = g_ui.createWidget('CountWindow', rootWidget)
    countWindow:setText("Stow Items")

    handleItemInteraction(item, countWindow, function(amount)
        g_game.stashStowItem(item:getPosition(), item:getId(), amount,
            item:getStackPos(), 0)
        countWindow = nil
    end, function()
        countWindow = nil
    end)
end

function moveStackableItem(item, toPos)
    if countWindow then
        return
    end
    if g_keyboard.isShiftPressed() then
        g_game.move(item, toPos, 1)
        return
    elseif g_keyboard.isCtrlPressed() and modules.client_options.getOption('moveStack') then
        g_game.move(item, toPos, item:getCount())
        return
    end

    countWindow = g_ui.createWidget('CountWindow', rootWidget)
    countWindow:setText("Move Items")
    handleItemInteraction(item, countWindow, function(count)
        g_game.move(item, toPos, count)
        countWindow = nil
    end, function()
        countWindow = nil
    end)
end

function onSelectPanel(self, checked)
    if checked then
        for k, v in pairs(panelsList) do
            if v.checkbox == self then
                gameSelectedPanel = v.panel
                break
            end
        end
    end
end

function getRootPanel()
    return gameRootPanel
end

function getMapPanel()
    return gameMapPanel
end

function getRightPanel()
    return gameRightPanel
end

function getMainRightPanel()
    return gameMainRightPanel
end

function fitMainRightPanel()
    if gameMainRightPanel and gameMainRightPanel.fitAllChildren then
        gameMainRightPanel:fitAllChildren()
    end
end

function getLeftPanel()
    return gameLeftPanel
end

function getContainerPanel()
    local containerPanel = g_settings.getNumber("containerPanel")
    if containerPanel >= 4 then
        containerPanel = containerPanel - 4
        return gameRightPanel:getChildByIndex(math.min(containerPanel, gameRightPanel:getChildCount()))
    end
    if gameLeftPanel:getChildCount() == 0 then
        return getRightPanel()
    end
    return gameLeftPanel:getChildByIndex(math.min(containerPanel, gameLeftPanel:getChildCount()))
end

function getRightExtraPanel()
    return gameRightExtraPanel
end

function getLeftExtraPanel()
    return gameLeftExtraPanel
end

function getLeftExtraPanel2()
    return gameLeftExtraPanel2
end

function getLeftExtraPanel3()
    return gameLeftExtraPanel3
end

function getRightExtraPanel2()
    return gameRightExtraPanel2
end

function getRightExtraPanel3()
    return gameRightExtraPanel3
end

function getSelectedPanel()
    return gameSelectedPanel
end

function getBottomPanel()
    return gameBottomPanel
end

function getShowTopMenuButton()
    return showTopMenuButton
end

function getGameTopStatsBar()
    return gameTopPanel
end

function getGameBottomStatsBar()
    return gameBottomStatsBarPanel
end

function getGameMapPanel()
    return gameMapPanel
end

function getBottomActionPanel()
    return gameBottomActionPanel
end

function getLeftActionPanel()
    return gameLeftActionPanel
end

function getRightActionPanel()
    return gameRightActionPanel
end

function getBottomLockPanel()
    return gameBottomLockPanel
end

function getRightLockPanel()
    return gameRightLockPanel
end

function getLeftLockPanel()
    return gameLeftLockPanel
end

function getBottomSplitter()
    return bottomSplitter
end

function findContentPanelAvailable(child, minContentHeight)
    if gameSelectedPanel and gameSelectedPanel:isVisible() and gameSelectedPanel:fits(child, minContentHeight, 0) >= 0 then
        return gameSelectedPanel
    end

    for k, v in pairs(panelsList) do
        if v.panel ~= gameSelectedPanel and v.panel:isVisible() and v.panel:fits(child, minContentHeight, 0) >= 0 then
            return v.panel
        end
    end

    return gameSelectedPanel
end

function nextViewMode()
    setupViewMode((currentViewMode + 1) % 3)
end

function setupViewMode(mode)
    if mode == currentViewMode then
        return
    end

    refreshSidePanelButtons()

    if g_platform.isMobile() then
        gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
        gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
    end

    if currentViewMode == 2 then
        gameMapPanel:addAnchor(AnchorLeft, 'gameLeftPanel', AnchorRight)
        gameMapPanel:addAnchor(AnchorRight, 'gameRightPanel', AnchorLeft)
        gameMapPanel:addAnchor(AnchorBottom, 'bottomSplitter', AnchorTop)
        gameMapPanel:addAnchor(AnchorTop, 'gameTopPanel', AnchorBottom)
        gameRootPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
        gameLeftPanel:setOn(modules.client_options.getOption('showLeftPanel'))
        gameRightExtraPanel:setOn(modules.client_options.getOption('showRightExtraPanel'))
        gameRightExtraPanel2:setOn(modules.client_options.getOption('showRightExtraPanel2'))
        gameRightExtraPanel3:setOn(modules.client_options.getOption('showRightExtraPanel3'))
        gameLeftExtraPanel:setOn(modules.client_options.getOption('showLeftExtraPanel'))
        gameLeftExtraPanel2:setOn(modules.client_options.getOption('showLeftExtraPanel2'))
        gameLeftExtraPanel3:setOn(modules.client_options.getOption('showLeftExtraPanel3'))
        gameLeftPanel:setImageColor('white')
        gameRightPanel:setImageColor('white')
        gameRightExtraPanel:setImageColor('white')
        gameRightExtraPanel2:setImageColor('white')
        gameRightExtraPanel3:setImageColor('white')
        gameLeftExtraPanel:setImageColor('white')
        gameLeftExtraPanel2:setImageColor('white')
        gameLeftExtraPanel3:setImageColor('white')
        gameLeftPanel:setMarginTop(0)
        gameRightPanel:setMarginTop(0)
        gameRightExtraPanel:setMarginTop(0)
        gameRightExtraPanel2:setMarginTop(0)
        gameRightExtraPanel3:setMarginTop(0)
        gameLeftExtraPanel:setMarginTop(0)
        gameLeftExtraPanel2:setMarginTop(0)
        gameLeftExtraPanel3:setMarginTop(0)
        gameBottomPanel:setImageColor('white')
        if g_platform.isMobile() then
            gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
            gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
        end
    end

    if mode == 0 then
        gameMapPanel:setKeepAspectRatio(true)
        gameMapPanel:setLimitVisibleRange(false)
        gameMapPanel:setZoom(11)
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })
        if g_platform.isMobile() then
            gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
            gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
        end
    elseif mode == 1 then
        gameMapPanel:setKeepAspectRatio(false)
        gameMapPanel:setLimitVisibleRange(true)
        gameMapPanel:setZoom(11)
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })
        if g_platform.isMobile() then
            gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
            gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
        end
    elseif mode == 2 then
        local limit = limitedZoom and not g_game.isGM()
        gameMapPanel:setLimitVisibleRange(limit)
        gameMapPanel:setZoom(11)
        gameMapPanel:setVisibleDimension({
            width = 15,
            height = 11
        })
        gameMapPanel:fill('parent')
        gameRootPanel:fill('parent')
        gameLeftPanel:setImageColor('alpha')
        gameRightPanel:setImageColor('alpha')
        gameRightExtraPanel:setImageColor('alpha')
        gameRightExtraPanel2:setImageColor('alpha')
        gameRightExtraPanel3:setImageColor('alpha')
        gameLeftExtraPanel:setImageColor('alpha')
        gameLeftExtraPanel2:setImageColor('alpha')
        gameLeftExtraPanel3:setImageColor('alpha')
        gameLeftPanel:setOn(true)
        gameLeftPanel:setVisible(true)
        gameRightPanel:setOn(true)
        gameRightExtraPanel:setOn(false)
        gameRightExtraPanel:setVisible(false)
        gameRightExtraPanel2:setOn(false)
        gameRightExtraPanel2:setVisible(false)
        gameRightExtraPanel3:setOn(false)
        gameRightExtraPanel3:setVisible(false)
        gameLeftExtraPanel:setOn(false)
        gameLeftExtraPanel:setVisible(false)
        gameLeftExtraPanel2:setOn(false)
        gameLeftExtraPanel2:setVisible(false)
        gameLeftExtraPanel3:setOn(false)
        gameLeftExtraPanel3:setVisible(false)
        gameMapPanel:setOn(true)
        gameBottomPanel:setImageColor('#ffffff88')
        if g_platform.isMobile() then
            gameRightPanel:setMarginBottom(mobileConfig.mobileHeightShortcuts)
            gameLeftPanel:setMarginBottom(mobileConfig.mobileHeightJoystick)
        end
    end

    currentViewMode = mode
    testExtendedView(mode)
end

function limitZoom()
    limitedZoom = true
end

function updateStatsBar(dimension, placement)
    StatsBar.updateCurrentStats(dimension, placement)
    StatsBar.updateStatsBarOption()
end

function onIncreaseLeftPanels()
    leftDecreaseSidePanels:setEnabled(true)
    if not modules.client_options.getOption('showLeftPanel') then
        modules.client_options.setOption('showLeftPanel', true)
        refreshSidePanelButtons()
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if not modules.client_options.getOption('showLeftExtraPanel') then
        modules.client_options.setOption('showLeftExtraPanel', true)
        refreshSidePanelButtons()

        -- Update horizontal left panel width if active
        if modules.client_options.getOption('showHorizontalLeftPanel') then
            addEvent(function()
                setLeftHorizontalWidth()
            end)
        end

        -- Update action bars when left extra panel is shown
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if not modules.client_options.getOption('showLeftExtraPanel2') then
        modules.client_options.setOption('showLeftExtraPanel2', true)
        refreshSidePanelButtons()

        if modules.client_options.getOption('showHorizontalLeftPanel') then
            addEvent(function()
                setLeftHorizontalWidth()
            end)
        end

        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if not modules.client_options.getOption('showLeftExtraPanel3') then
        modules.client_options.setOption('showLeftExtraPanel3', true)
        refreshSidePanelButtons()

        if modules.client_options.getOption('showHorizontalLeftPanel') then
            addEvent(function()
                setLeftHorizontalWidth()
            end)
        end

        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
    end
end

local function movePanel(mainpanel)
    for _, widget in pairs(mainpanel:getChildren()) do
        if widget then
            local panel = modules.game_interface.findContentPanelAvailable(widget, widget:getMinimumHeight())
            if panel then
                if not panel:hasChild(widget) then
                    widget:close()
                    panel:addChild(widget)
                else
                    print("Error: Attempt to add a widget that already exists in the target panel")
                end
            else
                print("Warning: No suitable panel found for widget, unable to move")
            end
        end
    end
end

function onDecreaseLeftPanels()
    if modules.client_options.getOption('showLeftExtraPanel3') then
        modules.client_options.setOption('showLeftExtraPanel3', false)
        movePanel(gameLeftExtraPanel3)
        refreshSidePanelButtons()

        if modules.client_options.getOption('showHorizontalLeftPanel') then
            addEvent(function()
                setLeftHorizontalWidth()
            end)
        end

        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if modules.client_options.getOption('showLeftExtraPanel2') then
        modules.client_options.setOption('showLeftExtraPanel2', false)
        movePanel(gameLeftExtraPanel2)
        refreshSidePanelButtons()

        if modules.client_options.getOption('showHorizontalLeftPanel') then
            addEvent(function()
                setLeftHorizontalWidth()
            end)
        end

        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if modules.client_options.getOption('showLeftExtraPanel') then
        modules.client_options.setOption('showLeftExtraPanel', false)
        movePanel(gameLeftExtraPanel)
        refreshSidePanelButtons()
        if g_platform.isMobile() then
            leftDecreaseSidePanels:setEnabled(false)
        end

        -- Update horizontal left panel width if active
        if modules.client_options.getOption('showHorizontalLeftPanel') then
            addEvent(function()
                setLeftHorizontalWidth()
            end)
        end

        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        return
    end

    if not g_platform.isMobile() then
        if modules.client_options.getOption('showLeftPanel') then
            -- Prevent closing left panel if horizontal left panel is active
            if modules.client_options.getOption('showHorizontalLeftPanel') then
                return
            end

            modules.client_options.setOption('showLeftPanel', false)
            movePanel(gameLeftPanel)
            refreshSidePanelButtons()
            -- Update action bars when left panel is hidden
            if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
                addEvent(function()
                    modules.game_actionbar.updateVisibleWidgetsExternal()
                end)
            end
            return
        end
    end
end

function onIncreaseRightPanels()
    rightDecreaseSidePanels:setEnabled(true)

    if not modules.client_options.getOption('showRightExtraPanel') then
        modules.client_options.setOption('showRightExtraPanel', true)
        refreshSidePanelButtons()
        addEvent(function()
            setRightHorizontalWidth()
        end)
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        if modules.game_helper and modules.game_helper.updateShortcutPanelPosition then
            addEvent(function()
                modules.game_helper.updateShortcutPanelPosition()
            end)
        end
        return
    end

    if not modules.client_options.getOption('showRightExtraPanel2') then
        modules.client_options.setOption('showRightExtraPanel2', true)
        refreshSidePanelButtons()
        addEvent(function()
            setRightHorizontalWidth()
        end)
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        if modules.game_helper and modules.game_helper.updateShortcutPanelPosition then
            addEvent(function()
                modules.game_helper.updateShortcutPanelPosition()
            end)
        end
        return
    end

    if not modules.client_options.getOption('showRightExtraPanel3') then
        modules.client_options.setOption('showRightExtraPanel3', true)
        refreshSidePanelButtons()
        rightIncreaseSidePanels:setEnabled(false)
        addEvent(function()
            setRightHorizontalWidth()
        end)
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        if modules.game_helper and modules.game_helper.updateShortcutPanelPosition then
            addEvent(function()
                modules.game_helper.updateShortcutPanelPosition()
            end)
        end
    end
end

function onDecreaseRightPanels()
    rightIncreaseSidePanels:setEnabled(true)

    if modules.client_options.getOption('showRightExtraPanel3') then
        modules.client_options.setOption('showRightExtraPanel3', false)
        movePanel(gameRightExtraPanel3)
        refreshSidePanelButtons()
        addEvent(function()
            setRightHorizontalWidth()
        end)
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        if modules.game_helper and modules.game_helper.updateShortcutPanelPosition then
            addEvent(function()
                modules.game_helper.updateShortcutPanelPosition()
            end)
        end
        return
    end

    if modules.client_options.getOption('showRightExtraPanel2') then
        modules.client_options.setOption('showRightExtraPanel2', false)
        movePanel(gameRightExtraPanel2)
        refreshSidePanelButtons()
        addEvent(function()
            setRightHorizontalWidth()
        end)
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        if modules.game_helper and modules.game_helper.updateShortcutPanelPosition then
            addEvent(function()
                modules.game_helper.updateShortcutPanelPosition()
            end)
        end
        return
    end

    if modules.client_options.getOption('showRightExtraPanel') then
        modules.client_options.setOption('showRightExtraPanel', false)
        movePanel(gameRightExtraPanel)
        refreshSidePanelButtons()
        addEvent(function()
            setRightHorizontalWidth()
        end)
        if modules.game_actionbar and modules.game_actionbar.updateVisibleWidgetsExternal then
            addEvent(function()
                modules.game_actionbar.updateVisibleWidgetsExternal()
            end)
        end
        if modules.game_helper and modules.game_helper.updateShortcutPanelPosition then
            addEvent(function()
                modules.game_helper.updateShortcutPanelPosition()
            end)
        end
    end
end

function setupOptionsMainButton()
    if logOutMainButton then
        return
    end

    logOutMainButton = modules.game_mainpanel.addSpecialToggleButton('logoutButton', tr('Exit'),
        '/images/options/button_logout',
        tryLogout)
end

function checkAndOpenLeftPanel()
    leftDecreaseSidePanels:setEnabled(true)
    if not modules.client_options.getOption('showLeftPanel') then
        modules.client_options.setOption('showLeftPanel', true)
        return
    end
end

function testExtendedView(mode)
    local extendedView = mode == 2
    if extendedView then
        local buttons = { leftIncreaseSidePanels, rightIncreaseSidePanels, rightDecreaseSidePanels,
            leftDecreaseSidePanels }
        for _, button in ipairs(buttons) do
            button:hide()
        end

        if not g_platform.isMobile() then
            gameBottomPanel:breakAnchors()
            gameBottomPanel:bindRectToParent()
            gameBottomPanel:setDraggable(true)
        else
            gameBottomPanel:setWidth(g_window.getWidth() - mobileConfig.mobileWidthJoystick -
                mobileConfig.mobileWidthShortcuts)
            gameBottomPanel:setPosition({
                x = mobileConfig.mobileWidthJoystick,
                y = gameBottomPanel:getY()
            })
        end
        gameBottomPanel:getChildById('rightResizeBorder'):setMaximum(gameBottomPanel:getWidth())
        gameBottomPanel:getChildById('bottomResizeBorder'):enable()
        gameBottomPanel:getChildById('rightResizeBorder'):enable()
        gameMainRightPanel:setHeight(0)
        gameMainRightPanel:setImageColor('alpha')
        gameBottomPanel:addAnchor(AnchorTop, 'gameBottomActionPanel', AnchorBottom)
        gameBottomPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        gameLeftActionPanel:setImageSource(nil)
        gameRightActionPanel:setImageSource(nil)
        gameLeftActionPanel:setBorderWidthRight(0)
        gameRightActionPanel:setBorderWidthLeft(0)
    else
        -- Reset to normal view
        -- gameMainRightPanel:setHeight(200)
        gameMainRightPanel:setMarginTop(0)
        gameMainRightPanel:setImageColor('white')
        gameLeftActionPanel:setImageSource('/images/ui/actionbar/actionbar_background-light')
        gameRightActionPanel:setImageSource('/images/ui/actionbar/actionbar_background-light')
        gameLeftActionPanel:setBorderWidthRight(1)
        gameRightActionPanel:setBorderWidthLeft(1)
        if gameMainRightPanel.fitAllChildren then
            gameMainRightPanel:fitAllChildren()
        else
            -- opcional: deixa 0 e quem usa (módulos) ajusta
            gameMainRightPanel:setHeight(0)
        end

        gameLeftActionPanel:setImageSource('/images/ui/actionbar/actionbar_background-light')
        gameRightActionPanel:setImageSource('/images/ui/actionbar/actionbar_background-light')
        gameLeftActionPanel:setBorderWidthRight(1)
        gameRightActionPanel:setBorderWidthLeft(1)

        local buttons = { leftIncreaseSidePanels, rightIncreaseSidePanels, rightDecreaseSidePanels,
            leftDecreaseSidePanels }

        for _, button in ipairs(buttons) do
            button:setMarginTop(0)
            button:show()
        end

        -- Reset bottom panel
        gameBottomPanel:setDraggable(false)

        -- Set anchors
        if not g_platform.isMobile() then
            gameBottomPanel:breakAnchors()
            gameBottomPanel:addAnchor(AnchorLeft, 'gameLeftExtraPanel3', AnchorRight)
            gameBottomPanel:addAnchor(AnchorRight, 'gameRightExtraPanel3', AnchorLeft)
            gameBottomPanel:addAnchor(AnchorTop, 'gameBottomCooldownPanel', AnchorBottom)
            gameBottomPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end
        gameBottomPanel:getChildById('bottomResizeBorder'):disable()
        gameBottomPanel:getChildById('rightResizeBorder'):disable()

        -- Move children back to gameMainRightPanel
        local children = gameRightPanel:getChildren()
        for _, child in ipairs(children) do
            if child.moveOnlyToMain then
                child:setParent(gameMainRightPanel)
            end
        end
    end
    addEvent(function()
        if modules.game_console and modules.game_console.setExtendedView then
            modules.game_console.setExtendedView(extendedView)
        end
        if modules.game_minimap and modules.game_minimap.extendedView then
            modules.game_minimap.extendedView(extendedView)
        end
        if modules.game_healthinfo and modules.game_healthinfo.extendedView then
            modules.game_healthinfo.extendedView(extendedView)
        end
        if modules.game_inventory and modules.game_inventory.extendedView then
            modules.game_inventory.extendedView(extendedView)
        end
        if modules.client_topmenu and modules.client_topmenu.extendedView then
            modules.client_topmenu.extendedView(extendedView)
        end
        if modules.game_mainpanel and modules.game_mainpanel.toggleExtendedViewButtons then
            modules.game_mainpanel.toggleExtendedViewButtons(extendedView)
        end
    end)
end

function toggleInternalFocus()
    for reason, _ in pairs(focusReason) do
        if reason == 'bosscooldown' then
            modules.game_analyser.toggleBossCDFocus(false)
        end
    end
end

function isInternalLocked()
    if not focusReason or table.empty(focusReason) then
        return false
    end
    return true
end

function toggleFocus(value, reason)
    if not reason then
        reason = ''
    end
    if not value then
        getBottomPanel():focus()
        if not reason then
            reason = ''
        end

        focusReason[reason] = nil
    else
        focusReason[reason] = true
    end

    if not value and #focusReason ~= 0 then
        return
    end

    gameRightPanel:setFocusable(value)
    gameLeftPanel:setFocusable(value)
    gameRightExtraPanel:setFocusable(value)
    gameRightExtraPanel2:setFocusable(value)
    if gameRightExtraPanel3 then
        gameRightExtraPanel3:setFocusable(value)
    end
    gameLeftExtraPanel:setFocusable(value)
    gameLeftExtraPanel2:setFocusable(value)
    if gameLeftExtraPanel3 then
        gameLeftExtraPanel3:setFocusable(value)
    end
end

function getHorizontalLeftPanel()
    if not horizontalLeftPanel then
        return createHorizontalLeftPanel()
    end
    return horizontalLeftPanel
end

function getHorizontalRightPanel()
    if not horizontalRightPanel then
        return createHorizontalRightPanel()
    end
    return horizontalRightPanel
end

function createHorizontalRightPanel()
    if horizontalRightPanel then return horizontalRightPanel end
    if not gameRootPanel then
        return nil
    end

    -- Create the panel (GameSidePanel) — balrog v3
    horizontalRightPanel = g_ui.createWidget('GameSidePanel', gameRootPanel)
    horizontalRightPanel:setId('horizontalRightPanel')
    horizontalRightPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
    horizontalRightPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    horizontalRightPanel:setHeight(0)
    horizontalRightPanel:setWidth(0)
    horizontalRightPanel:setFocusable(false)
    horizontalRightPanel:setVisible(true)
    horizontalRightPanel:setPhantom(true) -- [FIX] Start as phantom when empty to allow drops through to panels below


    return horizontalRightPanel
end

function createHorizontalLeftPanel()
    if horizontalLeftPanel then return horizontalLeftPanel end
    if not gameRootPanel then
        return nil
    end

    -- Create the panel (GameSidePanel) — balrog v3
    horizontalLeftPanel = g_ui.createWidget('GameSidePanel', gameRootPanel)
    horizontalLeftPanel:setId('horizontalLeftPanel')
    horizontalLeftPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
    horizontalLeftPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
    horizontalLeftPanel:setHeight(0)
    horizontalLeftPanel:setWidth(0)
    horizontalLeftPanel:setFocusable(false)
    horizontalLeftPanel:setVisible(true)
    horizontalLeftPanel:setPhantom(true) -- [FIX] Start as phantom when empty to allow drops through to panels below


    return horizontalLeftPanel
end

function showRightHorizontalPanel(visible)
    -- Create panel dynamically if needed
    local panel = horizontalRightPanel
    if not panel then
        panel = createHorizontalRightPanel()
    end

    if not panel then
        return
    end

    if visible then
        panel:setHeight(200) -- FIXED HEIGHT (balrog v3)
        setRightHorizontalWidth()

        -- Adjust gameMainRightPanel to anchor below the horizontal panel
        if gameMainRightPanel then
            gameMainRightPanel:breakAnchors()
            gameMainRightPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
            gameMainRightPanel:addAnchor(AnchorTop, 'horizontalRightPanel', AnchorBottom)

            -- Auto-fit height after minimap moved to horizontal panel
            scheduleEvent(function()
                if gameMainRightPanel and gameMainRightPanel.fitAllChildren then
                    gameMainRightPanel:fitAllChildren()
                end
            end, 50)
        end

        -- Adjust extra panel if it exists
        if gameRightExtraPanel then
            gameRightExtraPanel:breakAnchors()
            gameRightExtraPanel:addAnchor(AnchorRight, 'gameRightPanel', AnchorLeft)
            gameRightExtraPanel:addAnchor(AnchorTop, 'horizontalRightPanel', AnchorBottom)
            gameRightExtraPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Adjust extra panel 2 if it exists
        if gameRightExtraPanel2 then
            gameRightExtraPanel2:breakAnchors()
            gameRightExtraPanel2:addAnchor(AnchorRight, 'gameRightExtraPanel', AnchorLeft)
            gameRightExtraPanel2:addAnchor(AnchorTop, 'horizontalRightPanel', AnchorBottom)
            gameRightExtraPanel2:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Adjust extra panel 3 if it exists
        if gameRightExtraPanel3 then
            gameRightExtraPanel3:breakAnchors()
            gameRightExtraPanel3:addAnchor(AnchorRight, 'gameRightExtraPanel2', AnchorLeft)
            gameRightExtraPanel3:addAnchor(AnchorTop, 'horizontalRightPanel', AnchorBottom)
            gameRightExtraPanel3:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end
    else
        -- Move minimap to first available panel before hiding horizontal panel
        if modules.game_minimap and modules.game_minimap.moveMinimapToFirstAvailablePanel then
            -- Check if minimap is in this horizontal panel
            local children = panel:getChildren()
            for _, child in pairs(children) do
                if child:getId() == "minimapWindow" then
                    modules.game_minimap.moveMinimapToFirstAvailablePanel()
                    break
                end
            end
        end

        panel:setHeight(0)
        panel:setWidth(0)

        -- Restore gameMainRightPanel to anchor to parent top
        if gameMainRightPanel then
            gameMainRightPanel:breakAnchors()
            gameMainRightPanel:addAnchor(AnchorRight, 'parent', AnchorRight)
            gameMainRightPanel:addAnchor(AnchorTop, 'parent', AnchorTop)

            -- Auto-fit height after children moved back
            if gameMainRightPanel.fitAllChildren then
                gameMainRightPanel:fitAllChildren()
            end
        end

        -- Restore extra panel
        if gameRightExtraPanel then
            gameRightExtraPanel:breakAnchors()
            gameRightExtraPanel:addAnchor(AnchorRight, 'gameRightPanel', AnchorLeft)
            gameRightExtraPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameRightExtraPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Restore extra panel 2
        if gameRightExtraPanel2 then
            gameRightExtraPanel2:breakAnchors()
            gameRightExtraPanel2:addAnchor(AnchorRight, 'gameRightExtraPanel', AnchorLeft)
            gameRightExtraPanel2:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameRightExtraPanel2:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Restore extra panel 3
        if gameRightExtraPanel3 then
            gameRightExtraPanel3:breakAnchors()
            gameRightExtraPanel3:addAnchor(AnchorRight, 'gameRightExtraPanel2', AnchorLeft)
            gameRightExtraPanel3:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameRightExtraPanel3:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end
    end
end

function showLeftHorizontalPanel(visible)
    -- Create panel dynamically if needed
    local panel = horizontalLeftPanel
    if not panel then
        panel = createHorizontalLeftPanel()
    end

    if not panel then
        return
    end

    if visible then
        panel:setHeight(200) -- FIXED HEIGHT (balrog v3)
        setLeftHorizontalWidth()

        -- Adjust gameLeftPanel to anchor below the horizontal panel
        if gameLeftPanel then
            gameLeftPanel:breakAnchors()
            gameLeftPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            gameLeftPanel:addAnchor(AnchorTop, 'horizontalLeftPanel', AnchorBottom)
            gameLeftPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Adjust extra panel if it exists
        if gameLeftExtraPanel then
            gameLeftExtraPanel:breakAnchors()
            gameLeftExtraPanel:addAnchor(AnchorLeft, 'gameLeftPanel', AnchorRight)
            gameLeftExtraPanel:addAnchor(AnchorTop, 'horizontalLeftPanel', AnchorBottom)
            gameLeftExtraPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Adjust extra panel 2 if it exists
        if gameLeftExtraPanel2 then
            gameLeftExtraPanel2:breakAnchors()
            gameLeftExtraPanel2:addAnchor(AnchorLeft, 'gameLeftExtraPanel', AnchorRight)
            gameLeftExtraPanel2:addAnchor(AnchorTop, 'horizontalLeftPanel', AnchorBottom)
            gameLeftExtraPanel2:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Adjust extra panel 3 if it exists
        if gameLeftExtraPanel3 then
            gameLeftExtraPanel3:breakAnchors()
            gameLeftExtraPanel3:addAnchor(AnchorLeft, 'gameLeftExtraPanel2', AnchorRight)
            gameLeftExtraPanel3:addAnchor(AnchorTop, 'horizontalLeftPanel', AnchorBottom)
            gameLeftExtraPanel3:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end
    else
        -- Move minimap to first available panel before hiding horizontal panel
        if modules.game_minimap and modules.game_minimap.moveMinimapToFirstAvailablePanel then
            -- Check if minimap is in this horizontal panel
            local children = panel:getChildren()
            for _, child in pairs(children) do
                if child:getId() == "minimapWindow" then
                    modules.game_minimap.moveMinimapToFirstAvailablePanel()
                    break
                end
            end
        end

        panel:setHeight(0)
        panel:setWidth(0)

        -- Restore gameLeftPanel to anchor to parent top
        if gameLeftPanel then
            gameLeftPanel:breakAnchors()
            gameLeftPanel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            gameLeftPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameLeftPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Restore extra panel
        if gameLeftExtraPanel then
            gameLeftExtraPanel:breakAnchors()
            gameLeftExtraPanel:addAnchor(AnchorLeft, 'gameLeftPanel', AnchorRight)
            gameLeftExtraPanel:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameLeftExtraPanel:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Restore extra panel 2
        if gameLeftExtraPanel2 then
            gameLeftExtraPanel2:breakAnchors()
            gameLeftExtraPanel2:addAnchor(AnchorLeft, 'gameLeftExtraPanel', AnchorRight)
            gameLeftExtraPanel2:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameLeftExtraPanel2:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end

        -- Restore extra panel 3
        if gameLeftExtraPanel3 then
            gameLeftExtraPanel3:breakAnchors()
            gameLeftExtraPanel3:addAnchor(AnchorLeft, 'gameLeftExtraPanel2', AnchorRight)
            gameLeftExtraPanel3:addAnchor(AnchorTop, 'parent', AnchorTop)
            gameLeftExtraPanel3:addAnchor(AnchorBottom, 'parent', AnchorBottom)
        end
    end
end

-- Set horizontal panel width based on actual visible side panels width
function setRightHorizontalWidth()
    if not horizontalRightPanel then return end

    -- Calculate total width based on the RIGHT side panels that exist
    -- The horizontal panel should span the same width as the vertical panels below it
    local totalWidth = 0

    -- Get width of gameRightPanel (main right sidebar)
    if gameRightPanel and gameRightPanel:isOn() and gameRightPanel:getWidth() > 0 then
        totalWidth = totalWidth + gameRightPanel:getWidth()
    end

    -- Add extra panel width if visible and on
    if gameRightExtraPanel and gameRightExtraPanel:isOn() and gameRightExtraPanel:getWidth() > 0 then
        totalWidth = totalWidth + gameRightExtraPanel:getWidth()
    end

    -- Add extra panel 2 width if visible and on
    if gameRightExtraPanel2 and gameRightExtraPanel2:isOn() and gameRightExtraPanel2:getWidth() > 0 then
        totalWidth = totalWidth + gameRightExtraPanel2:getWidth()
    end

    -- Add extra panel 3 width if visible and on
    if gameRightExtraPanel3 and gameRightExtraPanel3:isOn() and gameRightExtraPanel3:getWidth() > 0 then
        totalWidth = totalWidth + gameRightExtraPanel3:getWidth()
    end

    -- Fallback: if no width calculated, use default
    if totalWidth == 0 then
        totalWidth = 178 -- default single panel width
    end

    horizontalRightPanel:setWidth(totalWidth)
end

function setLeftHorizontalWidth()
    if not horizontalLeftPanel then return end

    -- Calculate total width based on the LEFT side panels
    local totalWidth = 0

    -- Get width of gameLeftPanel (main left sidebar)
    if gameLeftPanel and gameLeftPanel:isOn() and gameLeftPanel:getWidth() > 0 then
        totalWidth = totalWidth + gameLeftPanel:getWidth()
    end

    -- Add extra panel width if visible and on
    if gameLeftExtraPanel and gameLeftExtraPanel:isOn() and gameLeftExtraPanel:getWidth() > 0 then
        totalWidth = totalWidth + gameLeftExtraPanel:getWidth()
    end

    -- Add extra panel 2 width if visible and on
    if gameLeftExtraPanel2 and gameLeftExtraPanel2:isOn() and gameLeftExtraPanel2:getWidth() > 0 then
        totalWidth = totalWidth + gameLeftExtraPanel2:getWidth()
    end

    -- Add extra panel 3 width if visible and on
    if gameLeftExtraPanel3 and gameLeftExtraPanel3:isOn() and gameLeftExtraPanel3:getWidth() > 0 then
        totalWidth = totalWidth + gameLeftExtraPanel3:getWidth()
    end

    -- Fallback: if no width calculated, use default
    if totalWidth == 0 then
        totalWidth = 178 -- default single panel width
    end

    horizontalLeftPanel:setWidth(totalWidth)

    -- Auto-resize minimap if it's in the horizontal panel
    local children = horizontalLeftPanel:getChildren()
    for _, child in pairs(children) do
        if child:getId() == "minimapWindow" then
            child:setWidth(totalWidth)
            break
        end
    end
end

-- Check if widgets overflow the horizontal panel and move them (RTC-style)
function checkHorizontalPanel(widget)
    if not widget then return end

    local relativeHeight = 0
    local totalHeight = widget:getHeight() + 10 -- margin de erro

    local moveWidgets = {}
    local children = widget:getChildren()
    for _, child in pairs(children) do
        relativeHeight = relativeHeight + child:getHeight()
        if relativeHeight > totalHeight then
            table.insert(moveWidgets, child)
        end
    end

    for _, w in pairs(moveWidgets) do
        if gameRightPanel then
            addEvent(function() w:setParent(gameRightPanel) end)
        end
    end
end

-- Restore widgets to horizontal panels from saved CharMiniWindows settings
function restoreHorizontalPanelWidgets()
    local char = g_game.getCharacterName()
    if not char or #char == 0 then
        return
    end

    local settings = g_settings.getNode('CharMiniWindows')
    if not settings or not settings[char] then
        return
    end

    -- Collect widgets that should be in horizontal panels
    local widgetsToRestore = {}
    for widgetId, widgetSettings in pairs(settings[char]) do
        if widgetSettings.parentId == 'horizontalLeftPanel' or widgetSettings.parentId == 'horizontalRightPanel' then
            table.insert(widgetsToRestore, {
                id = widgetId,
                parentId = widgetSettings.parentId,
                index = widgetSettings.index or 1
            })
        end
    end

    -- Sort by index to restore in correct order
    table.sort(widgetsToRestore, function(a, b)
        return a.index < b.index
    end)

    -- Restore each widget to its horizontal panel
    for _, widgetInfo in ipairs(widgetsToRestore) do
        local widget = rootWidget:recursiveGetChildById(widgetInfo.id)
        if widget then
            if widgetInfo.parentId == 'horizontalRightPanel' and modules.client_options and not modules.client_options.getOption('showHorizontalRightPanel') then
                if widgetInfo.id == 'minimapWindow' and modules.game_minimap and modules.game_minimap.moveMinimapToFirstAvailablePanel then
                    modules.game_minimap.moveMinimapToFirstAvailablePanel()
                end
            else
                local targetPanel = nil
                if widgetInfo.parentId == 'horizontalLeftPanel' then
                    targetPanel = getHorizontalLeftPanel()
                elseif widgetInfo.parentId == 'horizontalRightPanel' then
                    targetPanel = getHorizontalRightPanel()
                end

                if targetPanel then
                    local currentParent = widget:getParent()

                    if currentParent ~= targetPanel then
                        if currentParent then
                            currentParent:removeChild(widget)
                            if currentParent.fitAllChildren then
                                currentParent:fitAllChildren()
                            end
                        end
                        targetPanel:addChild(widget)
                    end

                    targetPanel:setPhantom(false)

                    if widgetInfo.parentId == 'horizontalLeftPanel' then
                        showLeftHorizontalPanel(true)
                        if widgetInfo.id == 'minimapWindow' and modules.game_minimap and modules.game_minimap.expandMinimapForHorizontalPanel then
                            modules.game_minimap.expandMinimapForHorizontalPanel(targetPanel)
                        else
                            scheduleEvent(function()
                                if widget and not widget:isDestroyed() and targetPanel and not targetPanel:isDestroyed() then
                                    local w, h = targetPanel:getWidth(), targetPanel:getHeight()
                                    if w > 0 and h > 0 then
                                        widget:setWidth(w)
                                        widget:setHeight(math.max(1, h - 5))
                                    end
                                end
                            end, 1)
                        end
                    elseif widgetInfo.parentId == 'horizontalRightPanel' then
                        showRightHorizontalPanel(true)
                        if widgetInfo.id == 'minimapWindow' then
                            if modules.game_minimap and modules.game_minimap.expandMinimapForHorizontalPanel then
                                modules.game_minimap.expandMinimapForHorizontalPanel(targetPanel)
                            else
                                widget:setWidth(targetPanel:getWidth())
                                widget:setHeight(targetPanel:getHeight())
                            end
                        end
                    end

                    targetPanel:saveChildren()
                end
            end
        end
    end
end

function toggleChaseMode()
    if g_game.getChaseMode() == ChaseOpponent then
        g_game.setChaseMode(DontChase)
    else
        g_game.setChaseMode(ChaseOpponent)
    end
end
