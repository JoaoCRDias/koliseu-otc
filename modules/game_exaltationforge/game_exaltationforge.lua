Forge = {}

Forge.resourceTypes = {
	["money"] = 0,
	["dust"] = 70,
	["sliver"] = 71,
	["core"] = 72
}

Forge.itemIds = {
	SLIVER = 37109,
	EXALTED_CORE = 37110
}

Forge.colors = {
	enough = "#C0C0C0",
	missing = "#D33C3C"
}

-- Timing constants (in milliseconds)
Forge.timing = {
	RESULT_DELAY = 200,
	SHADER_DELAY = 10,
	FLASH_DURATION = 350,
	PULSE_DURATION = 5400,
	SHADER_CLEANUP_DELAY = 5800,
	ARROW_SPEED = 0.90
}

-- Shader names
Forge.shaders = {
	PULSE = 'Item - ForgePulse',
	FLASH = 'Item - ForgeFlash',
	FLASH_RED = 'Item - ForgeFlashRed'
}

local ACTION_FUSION_TYPE = 0
local ACTION_TRANSFER_TYPE = 1

local Fusion = nil
local Transfer = nil
local Conversion = nil
local History = nil

-- Local function declarations
local onResourcesBalanceChange
local onResourceBalance
local onOpenExaltationForge
local onPlayerResourcesChange
local onResultExaltationForge
local onForgeHistory
local animateArrows

function init()
	Forge.mainButton = modules.game_mainpanel.addToggleButton("forgeButton", tr("Exaltation Forge"),
		"/images/options/forge", function() Forge:displayPreview() end, false, 17)

	Forge.mainButton:setOn(false)

	Forge.mainWindow = g_ui.displayUI("game_exaltationforge")
	Forge.mainWindow:setId("forge")
	Forge.mainWindow:setVisible(false)
	Forge.firstTooltip = Forge.mainWindow:getChildById('firstTooltip')
	Forge.secondTooltip = Forge.mainWindow:getChildById('secondTooltip')
	Forge.goldBalancePanel = Forge.mainWindow:getChildById('goldBalancePanel')
	Forge.goldBalanceValue = Forge.goldBalancePanel:getChildById('value')
	Forge.dustBalancePanel = Forge.mainWindow:getChildById('dustBalancePanel')
	Forge.dustBalanceValue = Forge.dustBalancePanel:getChildById('value')
	Forge.sliverBalancePanel = Forge.mainWindow:getChildById('sliverBalancePanel')
	Forge.sliverBalanceValue = Forge.sliverBalancePanel:getChildById('value')
	Forge.coreBalancePanel = Forge.mainWindow:getChildById('coreBalancePanel')
	Forge.coreBalanceValue = Forge.coreBalancePanel:getChildById('value')

	local closeWidget = Forge.mainWindow:getChildById('close')
	closeWidget.onClick = function()
		Forge:close()
	end

	Fusion = Forge.Fusion:get()
	Transfer = Forge.Transfer:get()
	Conversion = Forge.Conversion:get()
	History = Forge.History:get()

	Forge.Fusion:createButton()
	Forge.Transfer:createButton()
	Forge.Conversion:createButton()
	Forge.History:createButton()

	connect(g_game, {
		onOpenExaltationForge = onOpenExaltationForge,
		onResultExaltationForge = onResultExaltationForge,
		onItemClasses = onPlayerResourcesChange,
		onForgeHistory = onForgeHistory,
		onResourceBalance = onResourceBalance,
		onGameEnd = function() Forge:close() end,
		onResourcesBalanceChange = onResourcesBalanceChange
	})
end

onResourcesBalanceChange = function(balance, oldBalance, resource)
	if resource == ResourceTypes.BANK_BALANCE then
		Forge.goldBalanceValue:setText(Forge:formatNumber(balance))
	elseif resource == ResourceTypes.FORGE_DUST then
		Forge.currentDust = balance
		Forge.dustBalanceValue:setText(string.format("%d/%d", balance, (Forge.dustLevel or 0)))
		Forge:updateDustHighlight()
		Forge.Conversion:updateLimitCost()
		Forge.Conversion:updateDustToSliver()
	elseif resource == ResourceTypes.FORGE_SLIVER then
		Forge.sliverBalanceValue:setText(balance)
		Forge.Conversion:updateSliverToCore()
	elseif resource == ResourceTypes.FORGE_CORE then
		Forge.coreBalanceValue:setText(balance)
	end
end

onResourceBalance = function()
	Forge:updateResources()
end

function Forge:updateResources()
	self.goldBalanceValue:setText(self:formatNumber(self:getResourceBalance('money')))
	self.dustBalanceValue:setText((self.currentDust or 0) .. "/" .. (self.dustLevel or 0))
	self.sliverBalanceValue:setText(self:getResourceBalance('sliver'))
	self.coreBalanceValue:setText(self:getResourceBalance('core'))
	self:updateDustHighlight()
end

function Forge:updateDustHighlight()
	if not self.mainButton then
		return
	end
	local currentDust = self.currentDust or 0
	local maxDust = self.dustLevel or 0
	local isDustFull = maxDust > 0 and currentDust >= maxDust
	self.mainButton:setHighlight(isDustFull)
end

function Forge:close()
	if self.mainWindow then
		self.mainWindow:setVisible(false)
	end
	if self.mainButton then
		self.mainButton:setOn(false)
	end
	if self.resultWindow then
		self.resultWindow:setVisible(false)
	end
end

function Forge:get()
	return self
end

function Forge:displayPreview()
	if not self.mainWindow:isVisible() then
		g_game.sendResourceBalance()
		self.mainWindow:setVisible(true)
		self.mainButton:setOn(true)
		self.mainWindow:focus()
		Conversion:showWindow()
		Forge.preview = true
		Fusion:clearItems()
		Transfer:clearItems()
	else
		self.mainWindow:setVisible(false)
		self.mainButton:setOn(false)
	end
end

function Forge:formatNumber(n)
	local function addThousandsSeparator(str)
		local result = str:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if result:sub(1, 1) == "," then
			result = result:sub(2)
		end
		return result
	end

	if n >= 1000000000 then
		local value = math.floor(n / 1000000)
		return addThousandsSeparator(tostring(value)) .. " kk"
	else
		return addThousandsSeparator(tostring(n))
	end
end

function Forge:updateWidget(resourceType, widget, value, invertEnabledState)
	local balance = Forge:getResourceBalance(resourceType)
	value = tonumber(value)
	if not value then return end

	local hasEnough = balance >= value
	widget:setColor(hasEnough and Forge.colors.enough or Forge.colors.missing)

	if invertEnabledState then
		widget:setEnabled(not hasEnough)
	end
end

function Forge:setWidget(widget, value, hasEnough)
	widget:setText(value)
	widget:setColor(hasEnough and Forge.colors.enough or Forge.colors.missing)
end

function Forge:getResourceBalance(str)
	local t = self.resourceTypes[str]
	if not t then
		return 0
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return 0
	end

	if str == "money" then
		return player:getTotalMoney()
	end
	return player:getResourceBalance(t)
end

function Forge:ProcessFlash(item, widget, item2, widget2, descWidget, description, success)
	local timing = Forge.timing
	local shaders = Forge.shaders

	g_shaders.createFragmentShader(shaders.PULSE, "menu/shaders/forge.frag", true)

	scheduleEvent(function()
		animateArrows()
		item:setShader(shaders.PULSE)

		scheduleEvent(function()
			if success then
				widget:setVisible(false)
			end
			descWidget:setColoredText(description)
			descWidget:setVisible(true)

			local flashShader = success and shaders.FLASH or shaders.FLASH_RED
			local shaderPath = success and "menu/shaders/flash.frag" or "menu/shaders/red flash.frag"

			g_shaders.createFragmentShader(flashShader, shaderPath, true)

			scheduleEvent(function()
				item2:setShader(flashShader)
				scheduleEvent(function()
					if success then
						item2:setShader(nil)
						widget2:setColor(nil)
					else
						widget2:setVisible(false)
						item:setShader(nil)
						widget:setColor(nil)
					end
				end, timing.FLASH_DURATION)
			end, timing.SHADER_DELAY)
		end, timing.PULSE_DURATION)
	end, timing.SHADER_DELAY)

	scheduleEvent(function()
		if g_shaders and g_shaders.removeShader then
			g_shaders.removeShader(shaders.PULSE)
			g_shaders.removeShader(shaders.FLASH)
			g_shaders.removeShader(shaders.FLASH_RED)
		end
	end, timing.SHADER_CLEANUP_DELAY)
end

local function setupResultItems(resultWindow, leftItemId, rightItemId, leftTier, rightTier)
	local rightItem = Item.create(rightItemId)
	local rightWidget = resultWindow:recursiveGetChildById('previewItem2')
	rightItem:setTier(rightTier)
	rightWidget:setItem(rightItem)
	ItemsDatabase.setTier(rightWidget, rightItem)
	rightWidget:setColor("black")

	local leftWidget = resultWindow:recursiveGetChildById('previewItem1')
	local leftItem = Item.create(leftItemId)
	leftItem:setTier(leftTier)
	leftWidget:setItem(leftItem)
	ItemsDatabase.setTier(leftWidget, leftItem)

	return leftItem, leftWidget, rightItem, rightWidget
end

function Forge:displayResult(actionType, convergence, success, leftItemId, rightItemId, leftTier, rightTier)
	if self.resultWindow then
		self.resultWindow:destroy()
		self.resultWindow = nil
	end
	self.resultWindow = g_ui.displayUI("result")
	self.resultWindow:setVisible(false)
	local resultWindow = self.resultWindow

	local closeWidget = resultWindow:getChildById('close')
	closeWidget.onClick = function()
		resultWindow:setVisible(false)
		self.mainWindow:setVisible(true)
		if actionType == ACTION_TRANSFER_TYPE then
			Transfer:showWindow()
		end
	end

	local isFusion = actionType == ACTION_FUSION_TYPE
	local isTransfer = actionType == ACTION_TRANSFER_TYPE

	if not isFusion and not isTransfer then
		self.resultWindow:setVisible(true)
		return
	end

	-- Set window title
	local titlePrefix = convergence == 1 and "Convergence " or ""
	local titleSuffix = isFusion and "Fusion Result" or "Tier Transfer Result"
	resultWindow:setText(titlePrefix .. titleSuffix)

	-- Set result text
	local actionName = isFusion and "fusion attempt" or "transfer"
	local text = success
		and string.format("Your %s was {successful, #44AD25}.", actionName)
		or string.format("Your %s {failed, #D33C3C}.", actionName)

	local descWidget = resultWindow:recursiveGetChildById('resultText')
	local leftItem, leftWidget, rightItem, rightWidget = setupResultItems(
		resultWindow, leftItemId, rightItemId, leftTier, rightTier
	)

	scheduleEvent(function()
		self:ProcessFlash(leftItem, leftWidget, rightItem, rightWidget, descWidget, text, success)
	end, Forge.timing.RESULT_DELAY)

	self.resultWindow:setVisible(true)
end

onOpenExaltationForge = function(data)
	Forge.preview = false
	Forge.dustLevel = data.maxDust
	Fusion:parseData(data)
	Transfer:parseData(data)
end

onPlayerResourcesChange = function(data)
	Forge.data = data
	Forge.dustLevel = data.config.maxDust or 100
	Forge.maxDustCap = data.config.maxDustCap or 225
	Forge.Conversion:updateLimitCost()
	Forge:updateResources()
	Fusion:parseResourcesChange(data)
	Conversion:parseResourcesChange(data)
end

onResultExaltationForge = function(data)
	local success = data.success == 1

	scheduleEvent(function()
		Forge.mainWindow:setVisible(false)
	end, Forge.timing.SHADER_DELAY)

	Forge:displayResult(data.actionType, data.convergence, success, data.leftItemId, data.rightItemId, data.leftTier,
		data.rightTier)

	if data.actionType == ACTION_FUSION_TYPE then
		Fusion:parseResult(data)
	elseif data.actionType == ACTION_TRANSFER_TYPE then
		Transfer:parseResult(data)
	end
end

onForgeHistory = function(currentPage, lastPage, data)
	History:parse(currentPage, lastPage, data)
end

animateArrows = function()
	if not Forge.resultWindow then
		return
	end

	local arrow1 = Forge.resultWindow:recursiveGetChildById('arrowsIcon1')
	local arrow2 = Forge.resultWindow:recursiveGetChildById('arrowsIcon2')
	local arrow3 = Forge.resultWindow:recursiveGetChildById('arrowsIcon3')

	if not arrow1 or not arrow2 or not arrow3 then
		return
	end

	local speed = Forge.timing.ARROW_SPEED
	local arrowEmpty = '/images/game/forge/icon-arrow-rightlarge'
	local arrowFilled = '/images/game/forge/icon-arrow-rightlarge-filled'

	local function runSequence()
		arrow1:setImageSource(arrowEmpty)
		arrow2:setImageSource(arrowEmpty)
		arrow3:setImageSource(arrowEmpty)

		scheduleEvent(function() arrow1:setImageSource(arrowFilled) end, 100 * speed)
		scheduleEvent(function() arrow2:setImageSource(arrowFilled) end, 350 * speed)
		scheduleEvent(function() arrow3:setImageSource(arrowFilled) end, 600 * speed)

		scheduleEvent(function() arrow1:setImageSource(arrowEmpty) end, 1600 * speed)
		scheduleEvent(function() arrow2:setImageSource(arrowEmpty) end, 1850 * speed)
		scheduleEvent(function() arrow3:setImageSource(arrowEmpty) end, 2100 * speed)
	end

	local sequenceDuration = 2200 * speed

	for i = 0, 2 do
		scheduleEvent(runSequence, 100 * speed + i * sequenceDuration)
	end
end

function terminate()
	disconnect(g_game, {
		onOpenExaltationForge = onOpenExaltationForge,
		onResultExaltationForge = onResultExaltationForge,
		onItemClasses = onPlayerResourcesChange,
		onForgeHistory = onForgeHistory,
		onResourceBalance = onResourceBalance,
		onGameEnd = function() Forge:close() end,
		onResourcesBalanceChange = onResourcesBalanceChange
	})

	-- Cleanup resources
	if Forge.resultWindow then
		Forge.resultWindow:destroy()
		Forge.resultWindow = nil
	end

	if Forge.mainWindow then
		Forge.mainWindow:destroy()
		Forge.mainWindow = nil
	end

	if Forge.mainButton then
		Forge.mainButton:destroy()
		Forge.mainButton = nil
	end

	-- Clear references
	Fusion = nil
	Transfer = nil
	Conversion = nil
	History = nil
end
