-- RGB em hex (R,G,B,A 0-255)
local function rgbToHex(r, g, b, a)
    a = a or 255
    return string.format("#%.2X%.2X%.2X%.2X", r, g, b, a)
end

-- HSV → RGB (h em graus 0..360, s e v 0..1)
local function hsvToRgb(h, s, v)
    h = h % 360
    local c = v * s
    local x = c * (1 - math.abs((h / 60) % 2 - 1))
    local m = v - c
    local r, g, b = 0, 0, 0
    if h < 60 then
        r, g, b = c, x, 0
    elseif h < 120 then
        r, g, b = x, c, 0
    elseif h < 180 then
        r, g, b = 0, c, x
    elseif h < 240 then
        r, g, b = 0, x, c
    elseif h < 300 then
        r, g, b = x, 0, c
    else
        r, g, b = c, 0, x
    end
    return math.floor((r + m) * 255 + 0.5), math.floor((g + m) * 255 + 0.5), math.floor((b + m) * 255 + 0.5)
end

-- Gradiente RGB em loop: roda o matiz no espectro (arco-íris suave no nome inteiro)
-- GRADIENT_HUE_SPEED: graus de matiz por segundo (maior = mais rápido)
local GRADIENT_HUE_SPEED = 45
local GRADIENT_SATURATION = 0.82
local GRADIENT_VALUE = 1.0

local function rgbGradientHex(elapsedMs)
    local hue = (elapsedMs * 0.001 * GRADIENT_HUE_SPEED) % 360
    local r, g, b = hsvToRgb(hue, GRADIENT_SATURATION, GRADIENT_VALUE)
    return rgbToHex(r, g, b, 255)
end

-- Configuration
-- animateNameColor: gradiente RGB (ciclo de cores) no nome — precisa setCustomNameColor no cliente
-- nameColor: cor fixa quando não anima
local TAG_TEMPLATES = {
    ["STREAMER"] = { text = "STREAMER", tagColor = "#A55EEA" },
    ["GOD"]      = { text = "GOD", tagColor = "#ffffffff", animateNameColor = true },
    ["GM"]       = { text = "GM", tagColor = "#ffffffff", animateNameColor = true },
    ["TUTOR"]    = { text = "TUTOR", tagColor = "#FFA500FF", nameColor = "#FFFFFFFF" }
}

local GROUP_TYPE_TAGS = {
    [2] = "TUTOR",
    [3] = "TUTOR",
    [4] = "GM",
    [5] = "GM",
    [6] = "GOD",
    [7] = "GOD"
}

local activeCreatures = {}
local updateEvent = nil
local TICK_MS = 48

local function safeClearCustomNameColor(creature)
    if creature and creature.clearCustomNameColor then
        creature:clearCustomNameColor()
    end
end

local function safeSetCustomNameColor(creature, hex)
    if creature and creature.setCustomNameColor and hex then
        creature:setCustomNameColor(hex)
    end
end

local function safeClearNameHighlight(creature)
    if creature and creature.clearNameHighlight then
        creature:clearNameHighlight()
    end
end

local function clearCreatureTag(creature)
    if not creature then return end
    local cid = creature:getId()
    if activeCreatures[cid] then
        creature:clearText()
        safeClearNameHighlight(creature)
        safeClearCustomNameColor(creature)
        activeCreatures[cid] = nil
    end
end

local function syncGroupTag(creature)
    if not creature or not creature:isPlayer() then return end

    local groupType = creature:getGroupType()
    local templateKey = GROUP_TYPE_TAGS[groupType]

    clearCreatureTag(creature)

    if not templateKey then return end

    local template = TAG_TEMPLATES[templateKey]
    if not template then return end

    creature:setText(template.text, template.tagColor)

    if template.animateNameColor then
        safeSetCustomNameColor(creature, rgbGradientHex(g_clock.millis()))
    elseif template.nameColor then
        safeSetCustomNameColor(creature, template.nameColor)
    else
        safeClearCustomNameColor(creature)
    end

    activeCreatures[creature:getId()] = {
        creature = creature,
        template = template
    }
end

local function tickAnimatedNames()
    for _, data in pairs(activeCreatures) do
        local creature = data.creature
        local template = data.template
        if creature and not creature:isDead() and template and template.animateNameColor then
            safeSetCustomNameColor(creature, rgbGradientHex(g_clock.millis()))
        end
    end
    updateEvent = scheduleEvent(tickAnimatedNames, TICK_MS)
end

function onCreatureAppear(creature)
    if not creature then return end
    if not creature:isPlayer() then return end
    syncGroupTag(creature)
end

function onCreatureDisappear(creature)
    if not creature then return end
    clearCreatureTag(creature)
end

function onGroupTypeChange(creature)
    if not creature then return end
    if not creature:isPlayer() then return end
    syncGroupTag(creature)
end

function init()
    activeCreatures = {}

    connect(Creature, {
        onAppear = onCreatureAppear,
        onDisappear = onCreatureDisappear,
        onGroupTypeChange = onGroupTypeChange
    })

    scheduleEvent(function()
        local mapPanel = modules.game_interface.getMapPanel()
        if mapPanel then
            for _, creature in ipairs(mapPanel:getSpectators()) do
                onCreatureAppear(creature)
            end
        end
    end, 200)

    tickAnimatedNames()
end

function terminate()
    if updateEvent then
        updateEvent:cancel()
        updateEvent = nil
    end

    disconnect(Creature, {
        onAppear = onCreatureAppear,
        onDisappear = onCreatureDisappear,
        onGroupTypeChange = onGroupTypeChange
    })

    for _, data in pairs(activeCreatures) do
        local creature = data.creature
        if creature then
            creature:clearText()
            safeClearNameHighlight(creature)
            safeClearCustomNameColor(creature)
        end
    end
    activeCreatures = {}
end
