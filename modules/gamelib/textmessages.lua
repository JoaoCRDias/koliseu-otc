local messageModeCallbacks = {}

function g_game.onTextMessage(messageMode, message)
    local modeKey = tonumber(messageMode) or messageMode
    local callbacks = messageModeCallbacks[modeKey]
    if callbacks and next(callbacks) then
        for _, callback in pairs(callbacks) do
            callback(modeKey, message)
        end
        return
    end

    -- Fallback: game_textmessage já mapeia MessageTypes (Look, Status, Failure, etc.)
    if modules.game_textmessage and modules.game_textmessage.displayMessage then
        modules.game_textmessage.displayMessage(modeKey, message)
        return
    end

    perror(string.format('Unhandled onTextMessage message mode %s: %s', tostring(modeKey), message))
end

function registerMessageMode(messageMode, callback)
    local modeKey = tonumber(messageMode) or messageMode
    if not messageModeCallbacks[modeKey] then
        messageModeCallbacks[modeKey] = {}
    end

    table.insert(messageModeCallbacks[modeKey], callback)
    return true
end

function unregisterMessageMode(messageMode, callback)
    local modeKey = tonumber(messageMode) or messageMode
    if not messageModeCallbacks[modeKey] then
        return false
    end

    local ok = table.removevalue(messageModeCallbacks[modeKey], callback)
    if ok and not next(messageModeCallbacks[modeKey]) then
        messageModeCallbacks[modeKey] = nil
    end
    return ok
end
