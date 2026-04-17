local statsBarTop
local statsBarBottom

local statsBars = {}
local statsBarDeepInfo = {}

local statsBarsPlacements = {
    "Top",
    "Bottom"
}

local statsBarsDimensions = {
    Large = {
        height = 35
    },
    Default = {
        height = 35
    },
    Parallel = {
        height = 55
    },
    Compact = {
        height = 20
    }
}

local firstCall = true

local currentStats = {
    dimension = "hide",
    placement = "hide"
}

local skillsLineHeight = 20
local skillsTuples = {
    { skill = nil,             key = 'experience', icon = '/images/icons/icon_experience', placement = 'center', order = 0, name = "Level" },
    { skill = nil,             key = 'magic',      icon = '/images/icons/icon_magic',      placement = 'left',   order = 1, name = "Magic Level" },
    { skill = Skill.Axe,       key = 'axe',        icon = '/images/icons/icon_axe',        placement = 'right',  order = 1, name = "Axe Fighting Skill" },
    { skill = Skill.Club,      key = 'club',       icon = '/images/icons/icon_club',       placement = 'left',   order = 2, name = "Club Fighting Skill" },
    { skill = Skill.Distance,  key = 'distance',   icon = '/images/icons/icon_distance',   placement = 'right',  order = 2, name = "Distance Fighting Skill" },
    { skill = Skill.Fist,      key = 'fist',       icon = '/images/icons/icon_fist',       placement = 'left',   order = 3, name = "Fist Fighting Skill" },
    { skill = Skill.Shielding, key = 'shielding',  icon = '/images/icons/icon_shielding',  placement = 'right',  order = 3, name = "Shielding Fighting Skill" },
    { skill = Skill.Sword,     key = 'sword',      icon = '/images/icons/icon_sword',      placement = 'left',   order = 4, name = "Sword Fighting Skill" },
    { skill = Skill.Fishing,   key = 'fishing',    icon = '/images/icons/icon_fishing',    placement = 'right',  order = 4, name = "Fishing Fighting Skill" },
}

StatsBar = {}
local lastProficiencyCache = {}

function getConfigurations()
    local configs = {}
    for _, statsBar in pairs(statsBars) do
        for _, placement in ipairs(statsBarsPlacements) do
            for dimension, _ in pairs(statsBarsDimensions) do
                local dimensionOnPlacement = tostring(dimension):lower() .. "On" .. placement
                local key = "statsBar" .. placement:gsub("^%l", string.upper)
                if statsBar[key] then
                    table.insert(configs, statsBar[key][dimensionOnPlacement])
                end
            end
        end
    end
    return configs
end

local function reloadSkillsTab(skills, parent)
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local tuples = {}
    for i = 1, #skillsTuples do
        local skillTuple = skillsTuples[i]
        if skillTuple and g_settings.getBoolean('top_statsbar_' .. skillTuple.key) then
            table.insert(tuples, skillTuple)
        end
    end

    local statsBar = StatsBar.getCurrentStatsBar()
    if not statsBar then
        return
    end

    statsBar:setHeight(statsBar:getHeight() - skills:getHeight())

    parent:setHeight(parent:getHeight() - (40 + skills:getHeight()))
    skills:setHeight(0)
    skills:destroyChildren()
    local lines = 0
    local lastPlacement = 'left'
    for i = 1, #tuples do
        local skillTuple = tuples[i]
        local widget = g_ui.createWidget('TopStatsSkillElement', skills)
        widget:setId('statsbar_skill_' .. skillTuple.key)
        widget:addAnchor(AnchorTop, 'parent', AnchorTop)
        if lastPlacement == 'left' then
            widget:setMarginTop(lines * skillsLineHeight)
        else
            widget:setMarginTop((lines - 1) * skillsLineHeight)
        end
        widget.level = widget:getChildById('level')
        widget.icon = widget:getChildById('icon')
        widget.bar = widget:getChildById('bar')

        widget.icon:setImageSource(skillTuple.icon)
        widget.icon:setTooltip(skillTuple.name)

        widget.bar.statsGrade = 4
        widget.bar.statsGradeColor = '#070707ff'
        widget.bar:reloadBorder()

        widget.bar.showText = false
        if skillTuple.key == 'experience' then
            widget.bar.statsType = 'experience'
        else
            widget.bar.statsType = 'skill'
        end

        if skillTuple.placement == 'center' or (i == #tuples and lastPlacement == 'left') then
            widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            widget:addAnchor(AnchorRight, 'parent', AnchorRight)
            lines = lines + 1
        elseif lastPlacement == 'left' then
            widget:addAnchor(AnchorLeft, 'parent', AnchorLeft)
            widget:addAnchor(AnchorRight, 'parent', AnchorHorizontalCenter)
            lines = lines + 1
            lastPlacement = 'right'
        elseif lastPlacement == 'right' then
            widget:addAnchor(AnchorRight, 'parent', AnchorRight)
            widget:addAnchor(AnchorLeft, 'parent', AnchorHorizontalCenter)
            lastPlacement = 'left'
        end

        if skillTuple.key == 'experience' then
            widget.level:setText(player:getLevel())
            widget.bar:setValue(player:getLevelPercent(), 100)
        elseif skillTuple.key == 'magic' then
            widget.level:setText(player:getMagicLevel())
            widget.bar:setValue(player:getMagicLevelPercent(), 100)
        else
            widget.level:setText(player:getSkillLevel(skillTuple.skill))
            widget.bar:setValue(player:getSkillLevelPercent(skillTuple.skill), 100)
        end
    end

    skills:setHeight((lines * skillsLineHeight) + 5)
    parent:setHeight(40 + skills:getHeight())
    statsBar:setHeight(statsBar:getHeight() + skills:getHeight())
end

function StatsBar.getAllStatsBarWithPosition()
    local statsBarsWithPosition = {}
    for _, statsBar in pairs(statsBars) do
        for _, placement in ipairs(statsBarsPlacements) do
            for dimension, _ in pairs(statsBarsDimensions) do
                local dimensionOnPlacement = tostring(dimension):lower() .. "On" .. placement
                if statsBar[dimensionOnPlacement] then
                    statsBarsWithPosition[#statsBarsWithPosition + 1] = statsBar[dimensionOnPlacement]
                end
            end
        end
    end

    return statsBarsWithPosition
end

function StatsBar.getCurrentStatsBarWithPosition()
    if currentStats.dimension == 'hide' or currentStats.placement == 'hide' then
        return nil
    end
    local placement = currentStats.placement:gsub("^%l", string.upper)
    local fullPosition = currentStats.dimension .. "On" .. placement
    local statsBar = StatsBar.getCurrentStatsBar()
    if not statsBar then
        return nil
    end

    if statsBar[fullPosition] then
        return statsBar[fullPosition]
    else
        print("No stats bar with position found for:", statsBar)
    end

    return nil
end

function StatsBar.getCurrentStatsBar()
    if currentStats.dimension == 'hide' or currentStats.placement == 'hide' then
        return nil
    end
    local placement = currentStats.placement:gsub("^%l", string.upper)
    local statsBar = "statsBar" .. placement

    if statsBars[statsBar] then
        return statsBars[statsBar]
    else
        print("No stats bar found for:", statsBar)
    end

    return nil
end

function StatsBar.reloadCurrentStatsBarQuickInfo()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local bar = StatsBar.getCurrentStatsBarWithPosition()
    if not bar then
        return
    end

    local mana = player:getMana()
    local maxMana = player:getMaxMana()

    bar.health:setValue(player:getHealth(), player:getMaxHealth())

    local manashield = 0
    local maxManaShield = 0

    if player.getManaShield then
        manashield = player:getManaShield()
    end

    if not bar.mana.defaultHeight then
        bar.mana.defaultHeight = bar.mana:getHeight()
    end

    bar.mana:setValue(mana, maxMana)

    if player.getMaxManaShield then
        maxManaShield = player:getMaxManaShield()
    end
    local shouldShowManaShield = manashield > 0 and maxManaShield > 0
    if shouldShowManaShield then
        local fullHeight = bar.mana.defaultHeight
        local manaHeight = math.floor(fullHeight / 2)
        local shieldHeight = math.max(1, fullHeight - manaHeight)

        bar.mana.showText = false
        if bar.mana.text then
            bar.mana.text:hide()
        end

        bar.mana:setHeight(manaHeight)

        bar.manashield:show()
        bar.manashield:setMarginTop(0)
        bar.manashield:setHeight(shieldHeight)
        bar.manashield:setValue(manashield, maxManaShield)
        if bar.manashield.text then
            bar.manashield.text:setWidth(400)
            local textOffset = math.floor(manaHeight / 2)
            local manaText = string.format('%d/%d (%d/%d)', mana, maxMana, manashield, maxManaShield)
            if not bar.manashield or not bar.manashield.text then
                return
            end
            bar.manashield.text:setMarginTop(-textOffset)
            bar.manashield.text:setMarginBottom(0)
            bar.manashield.text:show()
            bar.manashield.text:raise()
            bar.manashield.showText = true
            bar.manashield.manaShieldText = manaText
        end
    else
        bar.mana.showText = true

        if bar.mana.defaultHeight then
            bar.mana:setHeight(bar.mana.defaultHeight)
        end

        bar.manashield:setMarginTop(0)
        bar.manashield:setHeight(0)
        bar.manashield:hide()
        bar.manashield.showText = true
        if bar.manashield.text then
            bar.manashield.text:hide()
            bar.manashield.text:setMarginTop(0)
            bar.manashield.text:setMarginBottom(0)
        end
    end

    if not shouldShowManaShield and bar.mana.text then
        bar.mana.text:show()
    end
end

local function loadIcon(bitChanged, content, topmenu)
    local icon = g_ui.createWidget('ConditionWidget', content)
    icon:setId(Icons[bitChanged].id)
    icon:setImageSource("/images/game/states/player-state-flags")
    icon:setImageClip(((Icons[bitChanged].clip - 1) * 9) .. ' 0 9 9')
    local tooltip = Icons[bitChanged].tooltip
    if tooltip == "You are GoshnarTaint" then
        tooltip = "Goshnar's Lairs Penalties:\n" ..
            "- 10% chance of creature teleportation to you\n" ..
            "- 0.5% chance of new creature spawn when hitting another\n" ..
            "- 15% increased damage received\n" ..
            "- 10% chance of creature full heal instead of dying\n" ..
            "- Lose 10% of current HP and mana every 10 seconds"
    end
    icon:setTooltip(tooltip)
    icon:setImageSize(tosize("9 9"))
    icon:setMarginRight(-1)
    if topmenu then
        icon:setMarginTop(5)
        icon:setMarginLeft(2)
        icon:setMarginRight(-2)
    end
    return icon
end

local function getStatsBarsIconContent()
    local iconContents = {}
    local statsBars = StatsBar.getAllStatsBarWithPosition()

    for _, statsBar in ipairs(statsBars) do
        iconContents[#iconContents + 1] = { content = statsBar.icons, loadIconTransparent = true }
    end

    iconContents[#iconContents + 1] = { content = modules.game_inventory.getIconsPanelOn(), loadIconTransparent = false }
    iconContents[#iconContents + 1] = { content = modules.game_inventory.getIconsPanelOff(), loadIconTransparent = false }

    return iconContents
end

local function toggleIcon(bitChanged)
    local contents = getStatsBarsIconContent()

    local iconId = Icons[bitChanged]
    if not iconId then
        g_logger.warning(string.format("No icon ID %s (%s)  found. Check Icons array in modules/gamelib/player.lua.",
            tostring(bitChanged), tostring(math.log(bitChanged) / math.log(2))))
        return
    end
    for _, contentData in ipairs(contents) do
        local icon = contentData.content:getChildById(iconId.id)
        if icon then
            icon:destroy()
        else
            icon = loadIcon(bitChanged, contentData.content, contentData.loadIconTransparent)
            icon:setParent(contentData.content)
        end
    end
end

function processIcon(id, action, createIfMissing)
    for _, contentData in ipairs(getStatsBarsIconContent()) do
        local icon = contentData.content:getChildById(id)
        if icon then
            action(icon)
        elseif createIfMissing then
            icon = loadIcon(id, contentData.content, contentData.loadIconTransparent)
            icon:setParent(contentData.content)
            action(icon)
        end
    end
end

function StatsBar.reloadCurrentStatsBarQuickInfo_state(localPlayer, now, old)
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    if now == old then
        return
    end
    Player.iterateChangedStates(now, old, function(bitChanged)
        toggleIcon(bitChanged)
    end)
end

local function loadBakragoreIcon(iconLevel, content, topmenu)
    local iconData = BakragoreIcons[iconLevel]
    if not iconData then
        return nil
    end

    local icon = g_ui.createWidget('ConditionWidget', content)
    icon:setId(iconData.id)
    icon:setImageSource("/images/game/states/player-state-flags")
    icon:setImageClip(((iconData.clip - 1) * 9) .. ' 0 9 9')

    local bonusPercent = 0
    if iconLevel >= 1 and iconLevel <= 4 then
        local bonuses = { 7.8, 15.6, 23.4, 31.2 }
        bonusPercent = bonuses[iconLevel]
    elseif iconLevel == 5 then
        bonusPercent = 0
    elseif iconLevel >= 6 and iconLevel <= 9 then
        local bonuses = { 33.5, 45.8, 60.1, 82.7 }
        bonusPercent = bonuses[iconLevel - 5]
    end

    local tooltip = iconData.tooltip
    if bonusPercent > 0 then
        tooltip = tooltip .. string.format("\n+%.1f%% Experience Bonus", bonusPercent)
    end

    icon:setTooltip(tooltip)
    icon:setImageSize(tosize("9 9"))
    icon:setMarginRight(-1)
    if topmenu then
        icon:setMarginTop(5)
        icon:setMarginLeft(2)
        icon:setMarginRight(-2)
    end
    return icon
end

local function updateBakragoreIcon(iconLevel)
    local contents = getStatsBarsIconContent()

    for _, contentData in ipairs(contents) do
        for i = 1, 9 do
            local iconData = BakragoreIcons[i]
            if iconData then
                local existingIcon = contentData.content:getChildById(iconData.id)
                if existingIcon then
                    existingIcon:destroy()
                end
            end
        end
    end

    if iconLevel and iconLevel > 0 then
        local iconData = BakragoreIcons[iconLevel]
        if iconData then
            for _, contentData in ipairs(contents) do
                local icon = loadBakragoreIcon(iconLevel, contentData.content, contentData.loadIconTransparent)
                if icon then
                    icon:setParent(contentData.content)
                end
            end
        end
    end
end

function StatsBar.reloadBakragoreIcon(localPlayer, newIcon, oldIcon)
    if newIcon == oldIcon then
        return
    end
    updateBakragoreIcon(newIcon)
end

function StatsBar.reloadCurrentStatsBarDeepInfo()
    local player = g_game.getLocalPlayer()
    if not player then
        return
    end

    local bar = StatsBar.getCurrentStatsBarWithPosition()
    if not bar then
        return
    end

    for _, skillTuple in ipairs(skillsTuples) do
        local widget = bar:recursiveGetChildById('statsbar_skill_' .. skillTuple.key)
        if widget then
            if skillTuple.key == 'experience' then
                widget.level:setText(player:getLevel())
                widget.bar:setValue(player:getLevelPercent(), 100)
            elseif skillTuple.key == 'magic' then
                widget.level:setText(player:getMagicLevel())
                widget.bar:setValue(player:getMagicLevelPercent(), 100)
            else
                widget.level:setText(player:getSkillLevel(skillTuple.skill))
                widget.bar:setValue(player:getSkillLevelPercent(skillTuple.skill), 100)
            end
        end
    end
end

function constructStatsBar(dimension, placement)
    local validDimension = dimension
    local validPlacement = placement

    local dimensionCapitalized = dimension:gsub("^%l", string.upper)
    if not statsBarsDimensions[dimensionCapitalized] or dimension:lower() == "hide" then
        validDimension = "Default"
        dimensionCapitalized = "Default"
    end

    local placementCapitalized = placement:gsub("^%l", string.upper)
    local isValidPlacement = false
    for _, p in ipairs(statsBarsPlacements) do
        if p == placementCapitalized then
            isValidPlacement = true
            break
        end
    end
    if not isValidPlacement or placement:lower() == "hide" then
        validPlacement = "top"
        placementCapitalized = "Top"
    end

    local dimensionString = validDimension:gsub("^%u", string.lower)
    StatsBar.updateCurrentStats(dimensionString, validPlacement)

    local dimensionOnPlacement = dimensionString:gsub("^%u", string.lower) .. "On" .. placementCapitalized
    local statsBar = statsBars["statsBar" .. placementCapitalized]

    if statsBar and statsBar[dimensionOnPlacement] then
        local targetHeight = statsBarsDimensions[dimensionCapitalized].height
        statsBar:setHeight(targetHeight)
        statsBar[dimensionOnPlacement]:setHeight(targetHeight)
        statsBar[dimensionOnPlacement]:show()
        statsBar[dimensionOnPlacement]:setPhantom(false)
        statsBar[dimensionOnPlacement].health = statsBar[dimensionOnPlacement]:getChildById('health')
        statsBar[dimensionOnPlacement].mana = statsBar[dimensionOnPlacement]:getChildById('mana')
        statsBar[dimensionOnPlacement].manashield = statsBar[dimensionOnPlacement]:getChildById('manashield')
        statsBar[dimensionOnPlacement].skills = statsBar[dimensionOnPlacement]:getChildById('skills')

        reloadSkillsTab(statsBar[dimensionOnPlacement].skills, statsBar[dimensionOnPlacement])
        StatsBar.reloadCurrentStatsBarQuickInfo()
        StatsBar.switchCurrentLayout()

        StatsBar.saveSettings()

        if modules.game_interface and modules.game_interface.setCustomisableStatusBarsVisible then
            modules.game_interface.setCustomisableStatusBarsVisible(true, validPlacement, statsBar:getHeight())
        end
    end
end

function StatsBar.updateCurrentStats(dimension, placement)
    currentStats = {
        dimension = dimension,
        placement = placement
    }
end

local function openDropMenu(mousePos)
    local menu = g_ui.createWidget('PopupMenu')
    menu:setGameMenu(true)

    local current = StatsBar.getCurrentStatsBarWithPosition()

    local menuOptions = getStatsBarMenuOptions(current)

    for _, option in ipairs(menuOptions) do
        menu:addOption(tr(option.label), function()
            StatsBar.hideAll()
            constructStatsBar(option.dimension, option.placement)
        end)
    end

    menu:addSeparator()

    local current = StatsBar.getCurrentStatsBarWithPosition()
    if current and current.skills then
        for _, skillTuple in ipairs(skillsTuples) do
            local skillKey = skillTuple.key
            local isChecked = g_settings.getBoolean('top_statsbar_' .. skillKey)
            menu:addCheckBox(tr(skillTuple.name), isChecked, function(widget, checked)
                local newValue = not checked
                g_settings.set('top_statsbar_' .. skillKey, newValue)
                local currentStats = StatsBar.getCurrentStatsBarWithPosition()
                if currentStats and currentStats.skills then
                    reloadSkillsTab(currentStats.skills, currentStats)
                    local statsBar = StatsBar.getCurrentStatsBar()
                    if statsBar and modules.game_interface and modules.game_interface.updateActionPanelsForStatsBarHeight then
                        modules.game_interface.updateActionPanelsForStatsBarHeight(statsBar:getHeight())
                    end
                end
            end)
        end
    end

    menu:addSeparator()

    local showCustomisableStatusBarsValue = modules.client_options.getOption('showCustomisableStatusBars')
    menu:addCheckBox(tr('Show Customisable Status Bars'), showCustomisableStatusBarsValue, function(widget, checked)
        local newValue = not checked
        if not newValue then
            StatsBar.hideAll()
            g_settings.set('statsbar_dimension', 'hide')
        end
        modules.client_options.setOption('showCustomisableStatusBars', newValue)
    end)

    local showStatusBarsValue = modules.client_options.getOption('showStatusBars')
    menu:addCheckBox(tr('Show Status Bars'), showStatusBarsValue, function(widget, checked)
        local newValue = not checked
        modules.client_options.setOption('showStatusBars', newValue)
    end)

    menu:display(mousePos)
end

function shouldAddStatsBarOption(current, placement, style)
    local id = current:getId()
    return string.find(id, placement) and id ~= style
end

function getStatsBarMenuOptions(current)
    local optionsMenu = {}

    for _, placement in ipairs(statsBarsPlacements) do
        for dimension, _ in pairs(statsBarsDimensions) do
            local style = tostring(dimension):gsub("^%u", string.lower) .. 'On' .. placement
            if shouldAddStatsBarOption(current, placement, style) then
                optionsMenu[#optionsMenu + 1] = {
                    label = 'Switch to ' .. tostring(dimension) .. ' Style',
                    dimension = dimension,
                    placement = placement:gsub("^%u", string.lower),
                    style = style
                }
            end
        end
    end

    for _, placement in ipairs(statsBarsPlacements) do
        if not string.find(current:getId(), placement) then
            optionsMenu[#optionsMenu + 1] = {
                label = 'Switch to ' .. placement .. ' Style',
                dimension = currentStats.dimension:gsub("^%l", string.upper),
                placement = placement:gsub("^%u", string.lower),
                construct = constructStatsBar,
                style = current:getId()
            }
        end
    end

    return optionsMenu
end

local function onStatsMousePress(tab, mousePos, mouseButton)
    if mouseButton == MouseRightButton then
        openDropMenu(mousePos)
        return true
    end
end

function StatsBar.reloadCurrentTab()
    if currentStats.dimension == "hide" then
        return
    end

    local dimension = currentStats.dimension:gsub("^%l", string.upper)

    if statsBarsDimensions[dimension] then
        return constructStatsBar(dimension, currentStats.placement)
    else
        print("No stats bars dimensions found: ", dimension, " on reloadCurrentTab()")
        return
    end
end

function StatsBar.updateStatsBarOption(dimension)
    StatsBar.hideAll()
    StatsBar.firstLoadSettings()

    if currentStats.dimension ~= "hide" and dimension ~= "hide" then
        StatsBar.reloadCurrentTab()
    end
end

local function getSettingOrDefault(setting, default)
    local value = g_settings.getString(setting)
    return value ~= "" and value or default
end

local function setSetting(setting, value)
    g_settings.set(setting, value)
end

function StatsBar.loadSettings()
    local dim = nil
    local place = nil

    if modules.game_sidebars and modules.game_sidebars.getStatsBarConfig then
        local statsBarConfig = modules.game_sidebars.getStatsBarConfig()
        if statsBarConfig then
            dim = statsBarConfig.dimension
            place = statsBarConfig.placement
        end
    end

    if not dim or dim == "" then
        dim = getSettingOrDefault('statsbar_dimension', "compact")
    end
    if not place or place == "" then
        place = getSettingOrDefault('statsbar_placement', "top")
    end

    currentStats = {
        dimension = dim,
        placement = place
    }
end

function StatsBar.saveSettings()
    setSetting('statsbar_dimension', currentStats.dimension)
    setSetting('statsbar_placement', currentStats.placement)
end

function StatsBar.firstLoadSettings()
    if firstCall then
        local dim = nil
        local place = nil

        if modules.game_sidebars and modules.game_sidebars.getStatsBarConfig then
            local statsBarConfig = modules.game_sidebars.getStatsBarConfig()
            if statsBarConfig then
                dim = statsBarConfig.dimension
                place = statsBarConfig.placement
            end
        end

        if not dim or dim == "" then
            dim = getSettingOrDefault("statsbar_dimension", "compact")
        end
        if not place or place == "" then
            place = getSettingOrDefault("statsbar_placement", "top")
        end

        currentStats.dimension = dim
        currentStats.placement = place

        firstCall = false
    end

    StatsBar.saveSettings()
    StatsBar.loadSettings()
end

function StatsBar.OnGameEnd()
    if not rawget(_G, "IMPORT_MODE_NO_SAVE") then
        StatsBar.saveSettings()
    end
    StatsBar.hideAll()

    modules.game_inventory.getIconsPanelOn():destroyChildren()
    modules.game_inventory.getIconsPanelOff():destroyChildren()

    StatsBar.destroyAllIcons()
end

function StatsBar.OnGameStart()
    StatsBar.loadSettings()

    local showCustomisableStatusBars = true
    if modules.client_options and modules.client_options.getOption then
        showCustomisableStatusBars = modules.client_options.getOption('showCustomisableStatusBars')
        if showCustomisableStatusBars == nil then
            showCustomisableStatusBars = true
        end
    end

    if showCustomisableStatusBars then
        if currentStats.dimension == "hide" then
            local dimension = g_settings.getString('statsbar_dimension_saved')
            if not dimension or dimension == '' then
                dimension = 'compact'
            end
            local placement = g_settings.getString('statsbar_placement_saved')
            if not placement or placement == '' then
                placement = 'top'
            end
            currentStats.dimension = dimension
            currentStats.placement = placement
            g_settings.set('statsbar_dimension', dimension)
            g_settings.set('statsbar_placement', placement)

            if modules.game_sidebars and modules.game_sidebars.getStatsBarConfig then
                local statsBarConfig = modules.game_sidebars.getStatsBarConfig()
                if statsBarConfig then
                    statsBarConfig.dimension = dimension
                    statsBarConfig.placement = placement
                end
            end
        end
        StatsBar.reloadCurrentTab()
    else
        StatsBar.hideAll()
    end

    if not table.empty(lastProficiencyCache) then
        StatsBar.onUpdateProficiencyData(
            lastProficiencyCache.itemCache,
            lastProficiencyCache.hasUnnusedPerk,
            lastProficiencyCache.thingType,
            lastProficiencyCache.shouldHighlight
        )
    end
end

function createStatsBarWidgets(statsBar)
    local widget = statsBar
    for _, placement in ipairs(statsBarsPlacements) do
        for dimension, _ in pairs(statsBarsDimensions) do
            local elementName = tostring(dimension):gsub("^%u", string.lower) .. "On" .. placement
            widget[elementName] = statsBar:getChildById(elementName)
        end
    end
    widget.onMousePress = onStatsMousePress
    return widget
end

function StatsBar.init()
    statsBarTop = modules.game_interface.getGameTopStatsBar()
    statsBarBottom = modules.game_interface.getGameBottomStatsBar()

    statsBars = {
        statsBarTop = statsBarTop,
        statsBarBottom = statsBarBottom
    }

    if not statsBarTop then
        return
    end

    if not statsBarBottom then
        return
    end

    for _, statBar in pairs(statsBars) do
        statBar = createStatsBarWidgets(statBar)
    end

    statsBarDeepInfo = {
        onExperienceChange = StatsBar.reloadCurrentStatsBarDeepInfo,
        onLevelChange = StatsBar.reloadCurrentStatsBarDeepInfo,
        onHealthChange = StatsBar.reloadCurrentStatsBarQuickInfo,
        onManaChange = StatsBar.reloadCurrentStatsBarQuickInfo,
        onManaShieldChange = StatsBar.reloadCurrentStatsBarQuickInfo,
        onMagicLevelChange = StatsBar.reloadCurrentStatsBarDeepInfo,
        onBaseMagicLevelChange = StatsBar.reloadCurrentStatsBarDeepInfo,
        onSkillChange = StatsBar.reloadCurrentStatsBarDeepInfo,
        onBaseSkillChange = StatsBar.reloadCurrentStatsBarDeepInfo,
        onStatesChange = StatsBar.reloadCurrentStatsBarQuickInfo_state,
        onBakragoreIconChange = StatsBar.reloadBakragoreIcon,
        onHarmonyChange = StatsBar.onHarmonyChange,
        onSereneChange = StatsBar.onSereneChange,
        onVocationChange = StatsBar.onVocationChange
    }

    StatsBar.hideAll()
    connect(LocalPlayer, statsBarDeepInfo)
    connect(g_game, {
        onGameStart = StatsBar.OnGameStart,
        onGameEnd = StatsBar.OnGameEnd
    })
end

function StatsBar.hideAll()
    for _, bar in pairs(statsBars) do
        for _, placement in pairs(statsBarsPlacements) do
            for dimension, _ in pairs(statsBarsDimensions) do
                local key = tostring(dimension):lower() .. "On" .. placement
                if bar[key] and bar[key].skills then
                    bar[key].skills:destroyChildren()
                    bar[key].skills:setHeight(0)
                    bar[key]:setHeight(0)
                    bar[key]:hide()
                end
            end
        end
        bar:setHeight(0)
    end

    if modules.game_interface and modules.game_interface.setCustomisableStatusBarsVisible then
        modules.game_interface.setCustomisableStatusBarsVisible(false)
    end
end

function StatsBar.destroyAllIcons()
    for _, bar in pairs(statsBars) do
        for _, placement in pairs(statsBarsPlacements) do
            for dimension, _ in pairs(statsBarsDimensions) do
                local key = tostring(dimension):lower() .. "On" .. placement
                if bar[key] and bar[key].skills then
                    bar[key].icons:destroyChildren()
                end
            end
        end
        bar:setHeight(0)
    end
end

function StatsBar.destroyAllBars()
    for _, bar in pairs(statsBars) do
        bar:destroy()
    end
end

function StatsBar.terminate()
    if not rawget(_G, "IMPORT_MODE_NO_SAVE") then
        StatsBar.saveSettings()
    end

    disconnect(LocalPlayer, statsBarDeepInfo)
    disconnect(g_game, {
        onGameStart = StatsBar.OnGameStart,
        onGameEnd = StatsBar.OnGameEnd
    })

    StatsBar.destroyAllBars()
end

function StatsBar.onHungryChange(regenerationTime, alert)
    local contents = getStatsBarsIconContent()
    local info = Icons[PlayerStates.Hungry]
    if regenerationTime <= alert then
        for _, contentData in ipairs(contents) do
            local icon = contentData.content:getChildById(info.id)
            if not icon then
                icon = g_ui.createWidget('ConditionWidget', contentData.content)
                icon:setId(info.id)
                icon:setImageSource("/images/game/states/player-state-flags")
                icon:setImageClip(((info.clip - 1) * 9) .. ' 0 9 9')
                icon:setTooltip(info.tooltip)
                icon:setImageSize(tosize("9 9"))
                if contentData.loadIconTransparent then
                    icon:setMarginTop(5)
                end
            end
        end
    else
        for _, contentData in ipairs(contents) do
            local icon = contentData.content:getChildById(info.id)
            if icon then
                icon:destroy()
                icon = nil
            end
        end
    end
end

function StatsBar.switchCurrentLayout()
    local statsBar = StatsBar.getCurrentStatsBarWithPosition and StatsBar.getCurrentStatsBarWithPosition()

    if table.empty(lastProficiencyCache) then
        if statsBar then
            local percentBar = statsBar:recursiveGetChildById('starProgress')
            local percentLabel = statsBar:recursiveGetChildById('proficiencyLabel')
            if percentBar then percentBar:setVisible(false) end
            if percentLabel then percentLabel:setVisible(false) end
        end
        return
    end

    if currentStats.dimension == "large" or currentStats.dimension == "compact" or currentStats.dimension == "parallel" then
        local statsBar = StatsBar.getCurrentStatsBarWithPosition and StatsBar.getCurrentStatsBarWithPosition()
        if statsBar then
            local percentBar = statsBar:recursiveGetChildById('starProgress')
            local percentLabel = statsBar:recursiveGetChildById('proficiencyLabel')
            local proficiencyIcon = statsBar:recursiveGetChildById('proficiencyIcon')
            local proficiencyBg = statsBar:recursiveGetChildById('proficiencyBg')
            if percentBar then percentBar:setVisible(false) end
            if percentLabel then percentLabel:setVisible(false) end
            if proficiencyIcon then proficiencyIcon:setVisible(false) end
            if proficiencyBg then proficiencyBg:setVisible(false) end
            if not table.empty(lastProficiencyCache) then
                local highlightButton = statsBar:recursiveGetChildById('highlightProficiencyButton')
                if highlightButton then
                    highlightButton:setVisible(lastProficiencyCache.shouldHighlight)
                end
            end
        end
    end

    StatsBar.onUpdateProficiencyData(lastProficiencyCache.itemCache, lastProficiencyCache.hasUnnusedPerk,
        lastProficiencyCache.thingType, lastProficiencyCache.shouldHighlight)
end

function onUpdateProficiencyWidget(hidePercentBar)
    local statsBar = StatsBar.getCurrentStatsBarWithPosition()
    if not statsBar then return end

    local statsPanel = statsBar:recursiveGetChildById('stats')
    local proficiencyPanel = statsBar:recursiveGetChildById('proficiencyPanel')
    local proficiencyButton = statsBar:recursiveGetChildById('proficiencyButton')

    if not proficiencyPanel or not proficiencyButton then
        return
    end

    if currentStats.dimension == "large" or currentStats.dimension == "compact" or currentStats.dimension == "parallel" then
        proficiencyButton:setVisible(not hidePercentBar)
        proficiencyPanel:setVisible(not hidePercentBar)
        local percentBar = statsBar:recursiveGetChildById('starProgress')
        local percentLabel = statsBar:recursiveGetChildById('proficiencyLabel')
        local proficiencyIcon = statsBar:recursiveGetChildById('proficiencyIcon')
        local proficiencyBg = statsBar:recursiveGetChildById('proficiencyBg')
        if percentBar then percentBar:setVisible(false) end
        if percentLabel then percentLabel:setVisible(false) end
        if proficiencyIcon then proficiencyIcon:setVisible(false) end
        if proficiencyBg then proficiencyBg:setVisible(false) end
        if not table.empty(lastProficiencyCache) then
            local highlightButton = statsBar:recursiveGetChildById('highlightProficiencyButton')
            if highlightButton then
                highlightButton:setVisible(lastProficiencyCache.hasUnnusedPerk)
            end
        end
        return
    end

    if currentStats.dimension == "default" then
        if hidePercentBar then
            if statsPanel then
                statsPanel:setMarginRight(45)
            end
            proficiencyPanel:setSize(tosize("0 13"))
            proficiencyButton:setMarginRight(-4)
        else
            if statsPanel then
                statsPanel:setMarginRight(-14)
            end
            proficiencyPanel:setSize(tosize("103 13"))
            proficiencyPanel:setMarginRight(8)
            proficiencyButton:setMarginRight(3)
        end
    end
end

function StatsBar.onUpdateProficiencyData(itemCache, hasUnnusedPerk, thingType, shouldHighlight)
    if itemCache and thingType then
        lastProficiencyCache = {
            itemCache = itemCache,
            hasUnnusedPerk = hasUnnusedPerk,
            thingType = thingType,
            shouldHighlight =
                shouldHighlight
        }
    end

    local statsBar = StatsBar.getCurrentStatsBarWithPosition and StatsBar.getCurrentStatsBarWithPosition()
    if not statsBar or not itemCache or not thingType then return end

    local highlightButton = statsBar:recursiveGetChildById('highlightProficiencyButton')
    local percentBar = statsBar:recursiveGetChildById('starProgress')
    local percentLabel = statsBar:recursiveGetChildById('proficiencyLabel')
    local proficiencyIcon = statsBar:recursiveGetChildById('proficiencyIcon')

    if currentStats.dimension == "large" or currentStats.dimension == "compact" or currentStats.dimension == "parallel" then
        if percentBar then percentBar:setVisible(false) end
        if percentLabel then percentLabel:setVisible(false) end
        if proficiencyIcon then proficiencyIcon:setVisible(false) end
        local proficiencyBg = statsBar:recursiveGetChildById('proficiencyBg')
        if proficiencyBg then proficiencyBg:setVisible(false) end
        if not highlightButton then
            highlightButton = statsBar:recursiveGetChildById('highlightProficiencyButton')
        end
        if highlightButton then
            highlightButton:setVisible(shouldHighlight)
        end

        lastProficiencyCache = {
            itemCache = itemCache,
            hasUnnusedPerk = hasUnnusedPerk,
            thingType = thingType,
            shouldHighlight =
                shouldHighlight
        }
        return
    end

    if not modules.game_proficiency or
        not modules.game_proficiency.ProficiencyData or
        type(modules.game_proficiency.ProficiencyData) ~= 'table' then
        if highlightButton then highlightButton:setVisible(false) end
        if percentBar then percentBar:setVisible(false) end
        if percentLabel then percentLabel:setVisible(false) end
        if proficiencyIcon then proficiencyIcon:setVisible(false) end
        return
    end

    local proficiencyId = thingType:getProficiencyId()
    if not proficiencyId or proficiencyId == 0 then return end

    local perkCount = modules.game_proficiency.ProficiencyData:getPerkLaneCount(proficiencyId) or 0
    if perkCount == 0 then
        if percentBar then percentBar:setVisible(false) end
        if percentLabel then percentLabel:setVisible(false) end
        return
    end

    local item = Item.create(thingType:getId())
    if not item then return end

    local currentExperience = itemCache.exp or 0

    local maxAvailableLevel = perkCount + 2
    local weaponLevel = modules.game_proficiency.ProficiencyData:getCurrentLevelByExp(item, currentExperience, true)
    local nextLevel = math.min(maxAvailableLevel, weaponLevel + 1)
    local percent = modules.game_proficiency.ProficiencyData:getLevelPercent(currentExperience, nextLevel, item)
    local maxLevelExperience = modules.game_proficiency.ProficiencyData:getMaxExperienceByLevel(nextLevel, item)

    if percentBar then
        percentBar:setVisible(true)
        percentBar:setPercent(percent)
        percentBar:setTooltip(string.format("Proficiency Progress: %s / %s", comma_value(currentExperience),
            comma_value(maxLevelExperience)))
    end

    if percentLabel then
        percentLabel:setVisible(true)
        percentLabel:setText(percent .. "%")
    end

    if highlightButton then
        highlightButton:setVisible(shouldHighlight)
    end

    if proficiencyIcon then
        proficiencyIcon:setOn(shouldHighlight)
    end

    lastProficiencyCache = {
        itemCache = itemCache,
        hasUnnusedPerk = hasUnnusedPerk,
        thingType = thingType,
        shouldHighlight =
            shouldHighlight
    }
end

function StatsBar.onProficiencyJsonLoaded()
    if not table.empty(lastProficiencyCache) then
        StatsBar.onUpdateProficiencyData(
            lastProficiencyCache.itemCache,
            lastProficiencyCache.hasUnnusedPerk,
            lastProficiencyCache.thingType,
            lastProficiencyCache.shouldHighlight
        )
    end
end

function StatsBar.clearProficiencyCache()
    lastProficiencyCache = {}
    local statsBar = StatsBar.getCurrentStatsBarWithPosition and StatsBar.getCurrentStatsBarWithPosition()
    if statsBar then
        local percentBar = statsBar:recursiveGetChildById('starProgress')
        local percentLabel = statsBar:recursiveGetChildById('proficiencyLabel')
        local highlightButton = statsBar:recursiveGetChildById('highlightProficiencyButton')
        local proficiencyIcon = statsBar:recursiveGetChildById('proficiencyIcon')

        if currentStats.dimension == "large" or currentStats.dimension == "compact" or currentStats.dimension == "parallel" then
            if percentBar then percentBar:setVisible(false) end
            if percentLabel then percentLabel:setVisible(false) end
            if proficiencyIcon then proficiencyIcon:setVisible(false) end
        else
            if percentBar then
                percentBar:setVisible(true)
                percentBar:setPercent(0)
                percentBar:setTooltip("")
            end
            if percentLabel then
                percentLabel:setVisible(true)
                percentLabel:setText("0%")
            end
        end

        if highlightButton then
            highlightButton:setVisible(false)
        end
        if proficiencyIcon then
            proficiencyIcon:setOn(false)
        end
    end
end

function StatsBar.setProficiencyHighlight(visible)
    local statsBar = StatsBar.getCurrentStatsBarWithPosition and StatsBar.getCurrentStatsBarWithPosition()
    if statsBar then
        local highlightButton = statsBar:recursiveGetChildById('highlightProficiencyButton')
        if highlightButton then
            highlightButton:setVisible(visible)
        end
    end
    if lastProficiencyCache then
        lastProficiencyCache.shouldHighlight = visible
    end
end

function StatsBar.onHarmonyChange(localPlayer, harmony)
    local statsBarsWithPosition = StatsBar.getAllStatsBarWithPosition()
    if not statsBarsWithPosition then return end

    for _, statsBar in ipairs(statsBarsWithPosition) do
        local monkStats = statsBar:recursiveGetChildById('monkStats')
        if monkStats then
            local harmonies = monkStats:recursiveGetChildById('harmonies')
            if harmonies then
                local children = harmonies:getChildren()
                for i, child in ipairs(children) do
                    child:setOn(i <= harmony)
                    child:setTooltip(string.format('%d/5 Harmony', harmony))
                end
            end
        end
    end
end

function StatsBar.onSereneChange(localPlayer, serene)
    local statsBarsWithPosition = StatsBar.getAllStatsBarWithPosition()
    if not statsBarsWithPosition then return end

    for _, statsBar in ipairs(statsBarsWithPosition) do
        local monkStats = statsBar:recursiveGetChildById('monkStats')
        if monkStats then
            local sereneWidget = monkStats:recursiveGetChildById('serene')
            if sereneWidget then
                sereneWidget:setOn(serene)
                if serene then
                    sereneWidget:setTooltip(
                        'Serene: Active\nYou have 5 or fewer adjacent entities and no visible party members.')
                else
                    sereneWidget:setTooltip(
                        'Serene: Inactive\nRequires 5 or fewer adjacent entities and no visible party members.')
                end
            end
        end
    end
end

function StatsBar.onVocationChange(localPlayer, vocationId)
    local statsBarsWithPosition = StatsBar.getAllStatsBarWithPosition()
    if not statsBarsWithPosition then return end

    local isMonk = localPlayer:isMonk()

    for _, statsBar in ipairs(statsBarsWithPosition) do
        local monkStats = statsBar:recursiveGetChildById('monkStats')
        if monkStats then
            monkStats:setEnabled(isMonk)
        end
    end
end
