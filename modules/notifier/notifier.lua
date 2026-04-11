local NOTIFIER_OPCODE = 204

local notifierPanel = nil
local notifierContainer = nil

local activeNotifications = {}
local pendingQueue = {}

local MAX_VISIBLE = 3
local DEFAULT_DURATION = 5000
local RAID_DURATION = 10000
local FADE_TIME = 300
local MAX_TEXT_LENGTH = 25

local IMAGE_PATHS = {
    ["raid"] = "/images/game/notifier/raid",
    ["xp_boost"] = "/modules/game_shop/images/XP_Boost",
    ["store_xp_boost"] = "/modules/game_shop/images/XP_Boost",
    ["onslaught"] = "/images/game/analyzer/misc/onslaught",
    ["ruse"] = "/images/game/analyzer/misc/ruse",
    ["momentum"] = "/images/game/analyzer/misc/momentum",
    ["transcendence"] = "/images/game/analyzer/misc/transcendence",
    ["critical"] = "/images/game/analyzer/misc/critical",
    ["damage"] = "/images/game/analyzer/misc/damage",
    ["double_kill_bounty"] = "/game_store/images/icons/64/double_bounty_klill",
    ["double_kill_weekly"] = "/game_store/images/icons/64/double_weekly_kill",
    ["reduced_weekly_items"] = "/game_store/images/icons/64/reduced_items",
}

local SOURCE_OPTION_MAP = {
    raid = 'notifyRaids',
    beast_scroll = 'notifyBeastScroll',
    kill_bonus = 'notifyKillBonus',
    concoctions = 'notifyConcoctions',
    foods = 'notifyFoods',
    potions = 'notifyPotions',
    xp_boost = 'notifyXpBoost',
    store_xp_boost = 'notifyXpBoost',
    task_bounty_kill_boost = 'notifyKillBonus',
    task_weekly_kill_boost = 'notifyKillBonus',
    task_reduced_weekly_items = 'notifyKillBonus',
}

Notifier = {}

local function createUI()
    if notifierPanel then
        return
    end
    local rootPanel = modules.game_interface.getRootPanel()
    if not rootPanel then
        return
    end
    notifierPanel = g_ui.loadUI('notifier', rootPanel)
    notifierContainer = notifierPanel:getChildById('notifierContainer')
end

local function destroyUI()
    for _, notif in ipairs(activeNotifications) do
        removeEvent(notif.dismissEvent)
        removeEvent(notif.destroyEvent)
        g_effects.cancelFade(notif.widget)
        notif.widget:destroy()
    end
    activeNotifications = {}
    pendingQueue = {}

    if notifierPanel then
        notifierPanel:destroy()
        notifierPanel = nil
        notifierContainer = nil
    end
end

local function showNextFromQueue()
    if #pendingQueue == 0 then
        return
    end
    if #activeNotifications >= MAX_VISIBLE then
        return
    end

    local data = table.remove(pendingQueue, 1)
    Notifier.show(data)
end

local function dismissNotification(widget)
    for i, notif in ipairs(activeNotifications) do
        if notif.widget == widget then
            removeEvent(notif.dismissEvent)
            removeEvent(notif.destroyEvent)
            table.remove(activeNotifications, i)
            break
        end
    end

    g_effects.cancelFade(widget)
    g_effects.fadeOut(widget, FADE_TIME)

    scheduleEvent(function()
        if widget then
            widget:destroy()
        end
        showNextFromQueue()
    end, FADE_TIME + 50)
end

local function isNotificationEnabled(data)
    if not modules.client_options or not modules.client_options.getOption then
        return true
    end
    if modules.client_options.getOption('showCustomNotificationWindow') == false then
        return false
    end
    local optionKey = SOURCE_OPTION_MAP[data.source]
    if optionKey then
        return modules.client_options.getOption(optionKey) ~= false
    end
    return true
end

local function onExtendedOpcode(protocol, opcode, buffer)
    local ok, data = pcall(json.decode, buffer)
    if not ok or not data then
        return
    end

    if not isNotificationEnabled(data) then
        return
    end

    Notifier.show(data)
end

function init()
    ProtocolGame.registerExtendedOpcode(NOTIFIER_OPCODE, onExtendedOpcode)

    connect(g_game, {
        onGameStart = createUI,
        onGameEnd = destroyUI
    })
end

function terminate()
    ProtocolGame.unregisterExtendedOpcode(NOTIFIER_OPCODE)

    disconnect(g_game, {
        onGameStart = createUI,
        onGameEnd = destroyUI
    })

    destroyUI()
end

function Notifier.show(data)
    if not notifierContainer then
        return
    end

    local duration = tonumber(data.duration) or ((data.source == "raid") and RAID_DURATION or DEFAULT_DURATION)

    if #activeNotifications >= MAX_VISIBLE then
        table.insert(pendingQueue, data)
        return
    end

    local widget = g_ui.createWidget('NotifierItem', notifierContainer)
    widget:setOpacity(0)

    local iconWidget = widget:getChildById('icon')
    local itemIconWidget = widget:getChildById('itemIcon')
    local outfitIconWidget = widget:getChildById('outfitIcon')

    local notifType = data.type or "image"

    if notifType == "item" and data.itemId and itemIconWidget then
        itemIconWidget:setVisible(true)
        itemIconWidget:setItemId(data.itemId)
    elseif notifType == "outfit" and data.outfit and outfitIconWidget then
        outfitIconWidget:setVisible(true)
        outfitIconWidget:setOutfit(data.outfit)
    elseif notifType == "image" and data.imageId and iconWidget then
        local path = IMAGE_PATHS[data.imageId]
        if path then
            iconWidget:setVisible(true)
            iconWidget:setImageSource(path)
        end
    end

    local titleWidget = widget:getChildById('title')
    if titleWidget then
        titleWidget:setText((data.title or ''):trim())
    end

    local descWidget = widget:getChildById('description')
    if descWidget then
        local desc = (data.description or ''):trim()
        if #desc > MAX_TEXT_LENGTH then
            desc = desc:sub(1, MAX_TEXT_LENGTH):trim() .. '...'
        end
        descWidget:setText(desc)
        descWidget:setTooltip(data.description or '')
    end

    g_effects.fadeIn(widget, FADE_TIME)

    local notif = {
        widget = widget,
        dismissEvent = nil,
        destroyEvent = nil
    }

    notif.dismissEvent = scheduleEvent(function()
        dismissNotification(widget)
    end, duration)

    table.insert(activeNotifications, notif)
end
