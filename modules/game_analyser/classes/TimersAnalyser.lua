if not TimersAnalyser then
	TimersAnalyser = {
		timers = {},
		widgets = {},
		window = nil,
		tickEvent = nil,
	}

	TimersAnalyser.__index = TimersAnalyser
end

local ImageMapping = {
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

local CategoryNames = {
	[0] = "Kill Bonus",
	[1] = "Item Upgrade",
	[2] = "Concoctions",
	[3] = "Foods",
	[4] = "Potions",
	[5] = "XP Boost",
}

local CategorySortOrder = {
	[0] = 0, -- Kill Bonus
	[5] = 1, -- XP Boost
	[3] = 2, -- Foods
	[2] = 3, -- Concoctions
	[4] = 4, -- Potions
	[1] = 5, -- Item Upgrade (last)
}

local CategoryOptionMap = {
	[0] = "notifyKillBonus",
	[2] = "notifyConcoctions",
	[3] = "notifyFoods",
	[4] = "notifyPotions",
	[5] = "notifyXpBoost",
}

local function isCategoryEnabled(category)
	if modules.client_options and modules.client_options.getOption then
		if modules.client_options.getOption('showCustomNotificationWindow') == false then
			return false
		end
		local optionKey = CategoryOptionMap[category]
		if optionKey then
			return modules.client_options.getOption(optionKey) ~= false
		end
	end
	return true
end

local function canNotify(category)
	return isCategoryEnabled(category) and modules.notifier and modules.notifier.Notifier
end

local GRID_COLS = 4
local CELL_H = 56
local CELL_SPACING = 3
local INFINITE_DURATION = 4294967295 -- 0xFFFFFFFF

local function timerKey(entry)
	if entry.keyType == 0 then
		return "s_" .. tostring(entry.key)
	else
		return "i_" .. tostring(entry.key)
	end
end

local function computeGridHeight(entryCount)
	if entryCount == 0 then return 0 end
	local rows = math.ceil(entryCount / GRID_COLS)
	return rows * CELL_H + (rows - 1) * CELL_SPACING
end

function TimersAnalyser:create()
	TimersAnalyser.timers = {}
	TimersAnalyser.widgets = {}

	TimersAnalyser.window = openedWindows['timersButton']

	if not TimersAnalyser.window then
		return
	end

	TimersAnalyser.window.onVisibilityChange = function(widget, visible)
		TimersAnalyser:onVisibilityChange(visible)
	end

	local toggleFilterButton = TimersAnalyser.window:recursiveGetChildById('toggleFilterButton')
	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
	end

	local newWindowButton = TimersAnalyser.window:recursiveGetChildById('newWindowButton')
	if newWindowButton then
		newWindowButton:setVisible(false)
	end

	local contextMenuButton = TimersAnalyser.window:recursiveGetChildById('contextMenuButton')
	if contextMenuButton then
		contextMenuButton:setVisible(false)
	end

	local lockButton = TimersAnalyser.window:recursiveGetChildById('lockButton')
	local minimizeButton = TimersAnalyser.window:recursiveGetChildById('minimizeButton')

	if lockButton and minimizeButton then
		lockButton:setVisible(true)
		lockButton:breakAnchors()
		lockButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
		lockButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
		lockButton:setMarginRight(2)
		lockButton:setMarginTop(0)
	end
end

function TimersAnalyser:reset()
	TimersAnalyser.timers = {}
	TimersAnalyser:stopTickEvent()
	TimersAnalyser:rebuildWidgets()
end

function TimersAnalyser:onUpdateActiveTimers(entries)
	if not entries then
		return
	end

	local receivedAt = os.time()

	local newByKey = {}
	for _, entry in ipairs(entries) do
		newByKey[timerKey(entry)] = entry
	end

	local hasRemoved = false
	for i = #TimersAnalyser.timers, 1, -1 do
		local timer = TimersAnalyser.timers[i]
		if timer.clientSide then
			-- skip client-side timers (e.g. XP Boost)
		else
			local tKey = timerKey(timer)
			local newEntry = newByKey[tKey]
			if newEntry then
				timer.remaining = newEntry.remaining
				timer.receivedAt = receivedAt
				newByKey[tKey] = nil
			else
				-- Timer removed by server (expired)
				if canNotify(timer.category) then
					local catName = CategoryNames[timer.category] or "Timer"
					local data = {
						title = catName,
						description = 'Expired: ' .. (timer.value or ''),
					}
					if timer.keyType == 1 then
						data.type = "item"
						data.itemId = timer.key
					else
						data.type = "image"
						data.imageId = timer.key
					end
					modules.notifier.Notifier.show(data)
				end
				hasRemoved = true
				table.remove(TimersAnalyser.timers, i)
			end
		end
	end

	local hasNew = false
	for _, entry in ipairs(entries) do
		local tKey = timerKey(entry)
		if newByKey[tKey] then
			hasNew = true
			table.insert(TimersAnalyser.timers, {
				category = entry.category or 0,
				keyType = entry.keyType,
				key = entry.key,
				value = entry.value,
				remaining = entry.remaining,
				receivedAt = receivedAt,
			})
		end
	end

	if not TimersAnalyser.window or not TimersAnalyser.window:isVisible() then
		return
	end

	if #TimersAnalyser.timers == 0 then
		TimersAnalyser:rebuildWidgets()
		TimersAnalyser:stopTickEvent()
	elseif hasNew or hasRemoved then
		TimersAnalyser:rebuildWidgets()
		TimersAnalyser:scheduleNextTick()
	else
		TimersAnalyser:updateCountdowns()
		TimersAnalyser:scheduleNextTick()
	end
end

function TimersAnalyser:onStoreExpBoostTimeChange(newTime)
	local tKey = "s_store_xp_boost"

	if not newTime or newTime <= 0 then
		-- Remove existing XP Boost timer
		local removedTimer = nil
		for i = #TimersAnalyser.timers, 1, -1 do
			if timerKey(TimersAnalyser.timers[i]) == tKey then
				removedTimer = TimersAnalyser.timers[i]
				table.remove(TimersAnalyser.timers, i)
				break
			end
		end
		if removedTimer and canNotify(removedTimer.category) then
			modules.notifier.Notifier.show({
				title = "XP Boost",
				description = "Expired: Store XP Boost",
				type = "image",
				imageId = "store_xp_boost",
			})
		end
		if TimersAnalyser.window and TimersAnalyser.window:isVisible() then
			TimersAnalyser:rebuildWidgets()
		end
		return
	end

	-- Update existing or insert new
	local found = false
	for _, timer in ipairs(TimersAnalyser.timers) do
		if timerKey(timer) == tKey then
			timer.remaining = newTime
			found = true
			break
		end
	end

	if not found then
		table.insert(TimersAnalyser.timers, 1, {
			category = 5,
			keyType = 0,
			key = "store_xp_boost",
			value = "Store XP Boost",
			remaining = newTime,
			clientSide = true,
		})
	end

	if not TimersAnalyser.window or not TimersAnalyser.window:isVisible() then
		return
	end

	if not found then
		TimersAnalyser:rebuildWidgets()
	else
		-- Update widget directly
		local widget = TimersAnalyser.widgets[tKey]
		if widget then
			TimersAnalyser:applyTimerStyle(widget, newTime)
		end
	end
end

function TimersAnalyser:rebuildWidgets()
	if not TimersAnalyser.window then
		return
	end

	local contentsPanel = TimersAnalyser.window.contentsPanel
	if not contentsPanel then
		return
	end

	contentsPanel:destroyChildren()
	TimersAnalyser.widgets = {}

	if #TimersAnalyser.timers == 0 then
		local emptyLabel = g_ui.createWidget('Label', contentsPanel)
		emptyLabel:setId('emptyLabel')
		emptyLabel:setText(tr('No active timers'))
		emptyLabel:setColor('$var-text-cip-color')
		emptyLabel:setFont('$var-cip-font-mono-rounded')
		emptyLabel:setTextAlign(AlignCenter)
		emptyLabel:addAnchor(AnchorTop, 'parent', AnchorTop)
		emptyLabel:addAnchor(AnchorLeft, 'parent', AnchorLeft)
		emptyLabel:addAnchor(AnchorRight, 'parent', AnchorRight)
		emptyLabel:setTextAutoResize(true)
		return
	end

	-- Group timers by category
	local groups = {}
	for _, timer in ipairs(TimersAnalyser.timers) do
		local cat = timer.category or 0
		if not groups[cat] then
			groups[cat] = {}
		end
		table.insert(groups[cat], timer)
	end

	-- Sort categories by their numeric value
	local sortedCats = {}
	for cat, _ in pairs(groups) do
		table.insert(sortedCats, cat)
	end
	table.sort(sortedCats, function(a, b)
		return (CategorySortOrder[a] or a) < (CategorySortOrder[b] or b)
	end)

	local prevWidgetId = nil

	for idx, cat in ipairs(sortedCats) do
		local catTimers = groups[cat]
		local catName = CategoryNames[cat] or "Other"

		-- Separator before header (except first category)
		if idx > 1 then
			local sep = g_ui.createWidget('TimerCategorySeparator', contentsPanel)
			local sepId = 'cat_sep_' .. cat
			sep:setId(sepId)
			sep:addAnchor(AnchorTop, prevWidgetId, AnchorBottom)
			sep:addAnchor(AnchorLeft, 'parent', AnchorLeft)
			sep:addAnchor(AnchorRight, 'parent', AnchorRight)
			prevWidgetId = sepId
		end

		-- Category header label
		local header = g_ui.createWidget('TimerCategoryLabel', contentsPanel)
		local headerId = 'cat_header_' .. cat
		header:setId(headerId)
		header:setText(catName)
		if prevWidgetId then
			header:addAnchor(AnchorTop, prevWidgetId, AnchorBottom)
		else
			header:addAnchor(AnchorTop, 'parent', AnchorTop)
		end
		header:addAnchor(AnchorLeft, 'parent', AnchorLeft)
		header:addAnchor(AnchorRight, 'parent', AnchorRight)
		prevWidgetId = headerId

		-- Grid panel for this category's timers
		local grid = g_ui.createWidget('TimersGridPanel', contentsPanel)
		local gridId = 'cat_grid_' .. cat
		grid:setId(gridId)
		if prevWidgetId then
			grid:addAnchor(AnchorTop, prevWidgetId, AnchorBottom)
		else
			grid:addAnchor(AnchorTop, 'parent', AnchorTop)
		end
		grid:addAnchor(AnchorLeft, 'parent', AnchorLeft)
		grid:addAnchor(AnchorRight, 'parent', AnchorRight)

		-- Create timer entry widgets
		for _, timer in ipairs(catTimers) do
			local widget = g_ui.createWidget('TimerEntry', grid)
			local tKey = timerKey(timer)
			widget:setId("timer_" .. tKey)

			if timer.keyType == 0 then
				local imagePath = ImageMapping[timer.key]
				if imagePath then
					widget.icon:setImageSource(imagePath)
					if timer.key == "store_xp_boost" or timer.key == "xp_boost" then
						widget.icon:setSize({ width = 32, height = 32 })
					else
						widget.icon:setSize({ width = 22, height = 22 })
					end
				end
			else
				-- Item sprite via UIItem
				widget.icon:setVisible(false)
				widget.itemIcon:setVisible(true)
				widget.itemIcon:setItemId(timer.key)
			end

			local remaining = timer.remaining
			if not timer.clientSide and remaining < INFINITE_DURATION then
				local elapsed = os.time() - timer.receivedAt
				remaining = math.max(0, remaining - elapsed)
			end
			TimersAnalyser:applyTimerStyle(widget, remaining)
			widget.background:setTooltip(timer.value)

			TimersAnalyser.widgets[tKey] = widget
		end

		-- Set grid height based on entry count
		grid:setHeight(computeGridHeight(#catTimers))

		prevWidgetId = gridId
	end
end

function TimersAnalyser:applyTimerStyle(widget, remaining)
	widget.countdown:setText(TimersAnalyser:formatTime(remaining))

	if remaining >= INFINITE_DURATION then
		-- Permanent / infinite
		widget.countdown:setColor('#c8a2ff')
		widget.background:setBorderColor('#c8a2ff')
	elseif remaining < 60 then
		widget.countdown:setColor('#ff8985')
		widget.background:setBorderColor('#ff8985')
	elseif remaining < 300 then
		widget.countdown:setColor('#f5ff85')
		widget.background:setBorderColor('#f5ff85')
	else
		widget.countdown:setColor('#72da74')
		widget.background:setBorderColor('#72da74')
	end
end

function TimersAnalyser:updateCountdowns()
	if not TimersAnalyser.window or not TimersAnalyser.window:isVisible() then
		return
	end

	local expired = false
	for i = #TimersAnalyser.timers, 1, -1 do
		local timer = TimersAnalyser.timers[i]
		if not timer.clientSide and timer.remaining < INFINITE_DURATION then
			local elapsed = os.time() - timer.receivedAt
			local remaining = math.max(0, timer.remaining - elapsed)
			if remaining <= 0 then
				-- Notify before removing
				if canNotify(timer.category) then
					local catName = CategoryNames[timer.category] or "Timer"
					local data = {
						title = catName,
						description = 'Expired: ' .. (timer.value or ''),
					}
					if timer.keyType == 1 then
						data.type = "item"
						data.itemId = timer.key
					else
						data.type = "image"
						data.imageId = timer.key
					end
					modules.notifier.Notifier.show(data)
				end
				table.remove(TimersAnalyser.timers, i)
				expired = true
			else
				local tKey = timerKey(timer)
				local widget = TimersAnalyser.widgets[tKey]
				if widget then
					TimersAnalyser:applyTimerStyle(widget, remaining)
				end
			end
		end
	end

	if expired then
		TimersAnalyser:rebuildWidgets()
	end
end

function TimersAnalyser:formatTime(seconds)
	if seconds >= INFINITE_DURATION then
		return "Inf."
	elseif seconds <= 0 then
		return "<1m"
	elseif seconds < 600 then
		local min = math.floor(seconds / 60)
		local sec = seconds % 60
		return string.format("%d:%02d", min, sec)
	elseif seconds <= 3600 then
		local minutes = math.floor(seconds / 60)
		return minutes .. "m"
	else
		local hours = math.floor(seconds / 3600)
		local minutes = math.floor((seconds % 3600) / 60)
		if minutes == 0 then
			return hours .. "h"
		end
		return string.format("%dh%02d", hours, minutes)
	end
end

function TimersAnalyser:scheduleNextTick()
	TimersAnalyser:stopTickEvent()

	if #TimersAnalyser.timers == 0 then
		return
	end

	local minRemaining = math.huge
	for _, timer in ipairs(TimersAnalyser.timers) do
		if not timer.clientSide then
			local elapsed = os.time() - timer.receivedAt
			local remaining = math.max(0, timer.remaining - elapsed)
			if remaining > 0 and remaining < minRemaining then
				minRemaining = remaining
			end
		end
	end

	if minRemaining == math.huge then
		return
	end

	local interval = minRemaining < 600 and 1000 or 10000

	TimersAnalyser.tickEvent = scheduleEvent(function()
		TimersAnalyser.tickEvent = nil
		if not g_game.isOnline() then return end

		local ok, err = pcall(function()
			TimersAnalyser:updateCountdowns()
		end)
		if not ok then
			g_logger.warning("[TimersAnalyser] tick error: " .. tostring(err))
		end

		TimersAnalyser:scheduleNextTick()
	end, interval)
end

function TimersAnalyser:stopTickEvent()
	if TimersAnalyser.tickEvent then
		removeEvent(TimersAnalyser.tickEvent)
		TimersAnalyser.tickEvent = nil
	end
end

function TimersAnalyser:onVisibilityChange(visible)
	if visible then
		TimersAnalyser:rebuildWidgets()
		TimersAnalyser:scheduleNextTick()
	else
		TimersAnalyser:stopTickEvent()
	end
end
