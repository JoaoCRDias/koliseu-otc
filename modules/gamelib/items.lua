-- to-do
-- change to ItemsDatabase.setTier(UIitem) to UIitem:setTier()
-- move this to "\modules\gamelib\ui\uiitem.lua" or "\modules\game_interface\widgets\uiitem.lua" why are 2 ?
ItemsDatabase = {}

ItemsDatabase.rarityColors = {
    ["yellow"] = TextColors.yellow,
    ["purple"] = TextColors.purple,
    ["blue"] = TextColors.blue,
    ["green"] = TextColors.green,
    ["grey"] = TextColors.grey,
}

local function getColorForValue(value)
    if value >= 1000000 then
        return "yellow"
    elseif value >= 100000 then
        return "purple"
    elseif value >= 10000 then
        return "blue"
    elseif value >= 1000 then
        return "green"
    elseif value >= 50 then
        return "grey"
    end
    return nil
end

local function getClipForValue(value)
    if value >= 1000000 then
        return "128 0 32 32"
    elseif value >= 100000 then
        return "96 0 32 32"
    elseif value >= 10000 then
        return "64 0 32 32"
    elseif value >= 1000 then
        return "32 0 32 32"
    elseif value >= 50 then
        return "0 0 32 32"
    end
    return ""
end

local RARITY_TO_CORNER_PNG = {
    yellow = '/images/ui/rarity_corner_gold.png',
    purple = '/images/ui/rarity_corner_purple.png',
    blue = '/images/ui/rarity_corner_blue.png',
    green = '/images/ui/rarity_corner_green.png',
    grey = '/images/ui/rarity_corner_white.png',
    white = '/images/ui/rarity_corner_white.png',
}

function ItemsDatabase.getClipAndImagePath(item)
    if not item then
        return nil, nil, nil
    end

    local frameOption = modules.client_options.getOption('framesRarity')
    if frameOption == "none" then
        return nil, nil, nil
    end

    local useCornerPng = false
    if modules.client_options and modules.client_options.getOption then
        useCornerPng = modules.client_options.getOption('lootRarityCornerSprites') == true
    end

    local imagePath = '/images/ui/item'
    local clip = nil

    local price = 0
    if type(item) == "number" then
        price = item
    else
        local ok, p = pcall(function()
            return item:getMeanPrice()
        end)
        if not ok then
            return nil, nil, nil
        end
        price = tonumber(p) or 0
    end

    do
        local itemRarity = getColorForValue(price)
        if itemRarity then
            if useCornerPng then
                local cornerPath = RARITY_TO_CORNER_PNG[itemRarity]
                if cornerPath then
                    return nil, cornerPath, { cornerPng = true }
                end
            end
            clip = getClipForValue(price)
            if clip ~= "" then
                if frameOption == "frames" then
                    imagePath = "/images/ui/rarity_frames"
                elseif frameOption == "corners" then
                    imagePath = "/images/ui/containerslot-coloredges"
                end
            else
                clip = nil
            end
        end
    end

    local clipObject = nil
    if clip then
        local x, y, w, h = clip:match("(%d+) (%d+) (%d+) (%d+)")
        clipObject = { x = tonumber(x), y = tonumber(y), width = tonumber(w), height = tonumber(h) }
    end

    return clip, imagePath, clipObject
end

function ItemsDatabase.setRarityItem(widget, item, style)
    if not g_game.getFeature(GameColorizedLootValue) or not widget then
        return
    end

    if not widget.setRaritySource then
        return
    end

    local clip, imagePath, clipObject = ItemsDatabase.getClipAndImagePath(item)

    if clip and imagePath then
        widget:setRaritySource(imagePath)
        widget:setRarityClip(clipObject)
    else
        widget:clearRarity()
    end

    if style then
        widget:setStyle(style)
    end
end

function ItemsDatabase.clearRarityItem(widget)
    if not widget then
        return
    end

    -- Clear rarity overlay
    if widget.clearRarity then
        widget:clearRarity()
    end

    -- Clear tier widget
    if widget.tier then
        widget.tier:setVisible(false)
        widget.tier:setImageClip(nil)
    end

    -- Clear charges and duration
    if widget.charges then
        widget.charges:setText("")
    end
    if widget.duration then
        widget.duration:setText("")
    end
end

function ItemsDatabase.getColorForRarity(rarity)
    return ItemsDatabase.rarityColors[rarity] or TextColors.white
end

function ItemsDatabase.setColorLootMessage(text, baseColor)
    baseColor = baseColor or TextColors.green

    local highlightLoot = true
    if modules and modules.client_options and modules.client_options.getOption then
        local ok, value = pcall(modules.client_options.getOption, 'lootHighlight')
        if ok and value == false then
            highlightLoot = false
        end
    end

    -- Build fully colored text where every part has explicit color
    local coloredText = ''
    local searchPos = 1

    while true do
        local braceStart, braceEnd, match = string.find(text, '{([^}]+)}', searchPos)
        if not braceStart then
            -- Add remaining text with base color
            local remaining = string.sub(text, searchPos)
            if #remaining > 0 then
                coloredText = coloredText .. '{' .. remaining .. ', ' .. baseColor .. '}'
            end
            break
        end

        -- Add text before this item with base color
        local beforeItem = string.sub(text, searchPos, braceStart - 1)
        if #beforeItem > 0 then
            coloredText = coloredText .. '{' .. beforeItem .. ', ' .. baseColor .. '}'
        end

        -- Parse the item: format is "itemId|itemName"
        local id, itemName = match:match("(%d+)|(.+)")
        if id and itemName then
            local itemId = tonumber(id)
            local itemColor = baseColor

            if highlightLoot and itemId then
                local thingType = g_things.getThingType(itemId, ThingCategoryItem)
                if thingType then
                    local itemInfo = thingType:getMeanPrice()
                    if itemInfo then
                        local rarity = getColorForValue(itemInfo)
                        if rarity then
                            itemColor = ItemsDatabase.getColorForRarity(rarity)
                        end
                    end
                end
            end

            coloredText = coloredText .. '{' .. itemName .. ', ' .. itemColor .. '}'
        else
            -- No itemId|itemName format, just use the match as-is with base color
            coloredText = coloredText .. '{' .. match .. ', ' .. baseColor .. '}'
        end

        searchPos = braceEnd + 1
    end

    return coloredText
end

local TIER_MAX = 15
local TIER_SMALL = { width = 9, height = 8 }
local TIER_BIG = { width = 18, height = 16 }

local function normalizeTier(tier)
    local t = math.floor(tonumber(tier) or 1)
    if t < 1 then
        t = 1
    elseif t > TIER_MAX then
        t = TIER_MAX
    end
    return t
end

function ItemsDatabase.getTierClip(tier)
    local t = normalizeTier(tier)
    local xOffset = (t - 1) * TIER_SMALL.width
    return {
        x = xOffset,
        y = 0,
        width = TIER_SMALL.width,
        height = TIER_SMALL.height
    }
end

function ItemsDatabase.getTierClipBig(tier)
    local t = normalizeTier(tier)
    local xOffset = (t - 1) * TIER_BIG.width
    return {
        x = xOffset,
        y = 0,
        width = TIER_BIG.width,
        height = TIER_BIG.height
    }
end

function ItemsDatabase.setTier(widget, item, isSmall)
    if not g_game.getFeature(GameThingUpgradeClassification) or not widget or not widget.tier then
        return
    end
    if isSmall == nil then
        isSmall = true
    end
    local tier = type(item) == "number" and item or (item and item:getTier()) or 0
    if tier <= 0 then
        widget.tier:setVisible(false)
        return
    end
    local config
    if isSmall then
        local normalizedTier = math.min(math.max(tier, 1), 10)
        config = {
            xOffset = (normalizedTier - 1) * 9,
            width = 10,
            height = 9,
            size = "10 9",
            source = '/images/inventory/tiers-strip'
        }
    else
        local normalizedTier = math.min(math.max(tier, 1), 18)
        local xOffset = (normalizedTier - 1) * 18 + 1
        config = {
            xOffset = xOffset,
            width = 18,
            height = 16,
            size = "18 16",
            source = '/images/inventory/tiers-strip-big'
        }
    end

    widget.tier:setImageClip({
        x = config.xOffset,
        y = 0,
        width = config.width,
        height = config.height
    })
    widget.tier:setSize(config.size)
    widget.tier:setImageSource(config.source)
    widget.tier:setImageSize(config.size)
    widget.tier:setVisible(true)
end

function ItemsDatabase.setCharges(widget, item, style)
    if not g_game.getFeature(GameThingCounter) or not widget then
        return
    end

    if item and item:getCharges() > 0 then
        widget.charges:setText(item:getCharges())
    else
        widget.charges:setText("")
    end

    if style then
        widget:setStyle(style)
    end
end


function ItemsDatabase.setDuration(widget, item, style)
    if not g_game.getFeature(GameThingClock) or not widget then
        return
    end

    if item and item:getDurationTime() > 0 then
        local durationTimeLeft = item:getDurationTime()
        local hours = math.floor(durationTimeLeft / 3600)
        local minutes = math.floor((durationTimeLeft % 3600) / 60)
        local seconds = math.floor(durationTimeLeft % 60)
        if hours > 0 then
            widget.duration:setText(string.format("%dh%02d", hours, minutes))
        elseif minutes > 0 then
            widget.duration:setText(string.format("%dm", minutes))
        else
            widget.duration:setText(string.format("%ds", seconds))
        end
    else
        widget.duration:setText("")
    end

    if style then
        widget:setStyle(style)
    end
end
