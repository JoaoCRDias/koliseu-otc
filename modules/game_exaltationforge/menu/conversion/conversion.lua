ACTION_FUSION_TYPE = 0
ACTION_TRANSFER_TYPE = 1
ACTION_DUST_TO_SLIVER = 2
ACTION_SLIVER_TO_CORE = 3
ACTION_INCREASE_DUST_LIMIT = 4

Forge.Conversion = {}

local Conversion = Forge.Conversion
Conversion.mainWindow = nil

function Conversion:get()
	return self
end

function Conversion:createButton()
	local buttonPanel = g_ui.createWidget('ForgeButton', Forge.mainWindow)
	buttonPanel:addAnchor(AnchorTop, 'FusionButton', AnchorTop)
	buttonPanel:addAnchor(AnchorLeft, 'TransferButton', AnchorRight)
	buttonPanel:setId('ConversionButton')
	self.buttonPanel = buttonPanel
	self.mainButton = buttonPanel:getChildById('button')
	self.mainButton:setText("Conversion")

	local iconWidget = buttonPanel:getChildById('icon')
	iconWidget:setImageSource("/images/game/forge/icon-conversion")
	if not self.mainWindow then
		g_ui.importStyle('Conversion')
		self.mainWindow = g_ui.createWidget('ConversionWindow', Forge.mainWindow)
		self.mainWindow:addAnchor(AnchorTop, 'TransferButton', AnchorBottom)
		self.mainWindow:addAnchor(AnchorLeft, 'FusionButton', AnchorLeft)
		self.mainWindow:addAnchor(AnchorRight, 'parent', AnchorRight)
		self.mainWindow:addAnchor(AnchorBottom, 'parent', AnchorBottom)
	end
	self.mainButton.onClick = function(widget, mousePos, mouseButton)
		if Forge.currentPanel then
			Forge.currentPanel:setVisible(false)
		end

		if Forge.currentButton then
			Forge.currentButton:setEnabled(true)
		end

		Forge.currentPanel = self.mainWindow
		Forge.currentButton = self.mainButton
		self.mainWindow:setVisible(true)
		self.mainButton:setEnabled(false)
		Forge.firstTooltip:setVisible(false)
		Forge.secondTooltip:setVisible(true)

		self.widgetStorage.dustRewardWidget:setItemId(Forge.itemIds.SLIVER)
		self.widgetStorage.sliverRewardWidget:setItemId(Forge.itemIds.EXALTED_CORE)
		self.widgetStorage.sliver_forgeItem:setItemId(Forge.itemIds.SLIVER)
	end
	self:init()
end

function Conversion:updateLimitCost()
	local currentDustLevel = Forge.dustLevel or 100
	local dustCost = currentDustLevel - 75
	local currentDust = Forge.currentDust or 0
	local _dustEnough = currentDust >= dustCost

	local currentLimitWidget = self.widgetStorage.currentLimit
	local newLimitWidget = self.widgetStorage.newLimit
	local newCostWidget = self.widgetStorage.limitCost
	local button = self.widgetStorage.DustLimitProcced
	local opacity = 0.3
	local image1 = self.widgetStorage.imageFirst
	local image2 = self.widgetStorage.imageSecond

	-- Check if maxDust has reached maxDustCap
	local maxDustCap = Forge.maxDustCap or 225
	local isAtMaxCap = currentDust >= maxDustCap

	-- Get additional widgets for showing/hiding
	local limitCostIcon = self.widgetStorage.limitCostIcon
	local raiseLimitPanel = self.widgetStorage.raiseLimitPanel
	local raiseLimitFirstIcon = self.widgetStorage.raiseLimitFirstIcon
	local raiseLimitSecondIcon = self.widgetStorage.raiseLimitSecondIcon

	-- Get label widget for "Raise limit from" / "Maximum Reached"
	local raiseLimitLabel = self.widgetStorage.raiseLimitLabel

	if isAtMaxCap then
		-- Dust limit is at maximum cap, show "Maximum Reached" message
		if raiseLimitLabel then raiseLimitLabel:setText("Maximum Reached") end

		-- Hide the "X to Y" panel since we reached max
		if raiseLimitPanel then raiseLimitPanel:setVisible(false) end

		-- Show cost value but disabled
		newCostWidget:setText(dustCost)
		newCostWidget:setColor(Forge.colors.missing)
		if limitCostIcon then limitCostIcon:setVisible(true) end

		button:setEnabled(false)
		button:setOpacity(opacity)
		image1:setImageSource('/images/game/forge/dust2')
		image2:setImageSource('/images/game/forge/dust2')
	else
		-- Normal state - show "Raise limit from" and cost/limit values
		if raiseLimitLabel then raiseLimitLabel:setText("Raise limit from") end

		if raiseLimitPanel then raiseLimitPanel:setVisible(true) end

		newCostWidget:setText(dustCost)
		if limitCostIcon then limitCostIcon:setVisible(true) end

		currentLimitWidget:setText(currentDustLevel)
		newLimitWidget:setText(currentDustLevel + 1)
		if raiseLimitFirstIcon then raiseLimitFirstIcon:setVisible(true) end
		if raiseLimitSecondIcon then raiseLimitSecondIcon:setVisible(true) end

		if _dustEnough then
			newCostWidget:setColor(Forge.colors.enough)
			button:setEnabled(true)
			button:setOpacity(1)
			image1:setImageSource('/images/game/forge/dust')
			image2:setImageSource('/images/game/forge/dust')
		else
			newCostWidget:setColor(Forge.colors.missing)
			button:setEnabled(false)
			button:setOpacity(opacity)
			image1:setImageSource('/images/game/forge/dust2')
			image2:setImageSource('/images/game/forge/dust2')
		end
	end
end

function Conversion:updateDustToSliver()
	if not Forge.data or not Forge.data.config then return end

	local config = Forge.data.config
	local dustPercent = config.dustPercent or 100
	local dustToSliver = config.dustToSliver or 100
	local dustRequired = dustToSliver * dustPercent
	local dustReward = dustToSliver

	local dustRequiredWidget = self.widgetStorage.dustRequired
	local dustRewardWidget = self.widgetStorage.dustReward
	local dustButtonProcced = self.widgetStorage.dustButtonProcced
	local rewardItem = self.widgetStorage.dustRewardWidget

	dustRequiredWidget:setText(dustRequired)
	dustRewardWidget:setText(dustReward)

	local _dustEnough = Forge:getResourceBalance("dust") >= dustRequired
	local opacity = 0.3

	if not _dustEnough then
		dustRequiredWidget:setColor(Forge.colors.missing)
		dustButtonProcced:setEnabled(false)
		dustButtonProcced:setOpacity(opacity)
		rewardItem:setOpacity(opacity)
	else
		dustRequiredWidget:setColor(Forge.colors.enough)
		dustButtonProcced:setEnabled(true)
		dustButtonProcced:setOpacity(1)
		rewardItem:setOpacity(1)
	end
end

function Conversion:updateSliverToCore()
	if not Forge.data or not Forge.data.config then return end

	local config = Forge.data.config
	local sliverRequired = config.sliverToCore or 100
	local sliverReward = 1

	local sliverRequiredWidget = self.widgetStorage.sliverRequired
	local sliverRewardWidget = self.widgetStorage.sliverReward
	local sliverButtonProcced = self.widgetStorage.sliverButtonProcced
	local sliverRewardItem = self.widgetStorage.sliverRewardWidget

	sliverRequiredWidget:setText(sliverRequired)
	sliverRewardWidget:setText(sliverReward)

	local _sliverEnough = Forge:getResourceBalance("sliver") >= sliverRequired
	local opacity = 0.3

	if not _sliverEnough then
		sliverRequiredWidget:setColor(Forge.colors.missing)
		sliverButtonProcced:setEnabled(false)
		sliverButtonProcced:setOpacity(opacity)
		sliverRewardItem:setOpacity(opacity)
	else
		sliverRequiredWidget:setColor(Forge.colors.enough)
		sliverButtonProcced:setEnabled(true)
		sliverButtonProcced:setOpacity(1)
		sliverRewardItem:setOpacity(1)
	end
end

function Conversion:init()
	self.widgetStorage = {}
	local mainWindow = self.mainWindow
	local mainPanel = mainWindow
	local convert_dustPanel = mainPanel:getChildById('convertDustPanel')
	local dust_forgeItemWidget = convert_dustPanel:getChildById('forgeItem')
	local dust_countPanel = dust_forgeItemWidget:getChildById('countPanel')
	local dust_countValue = dust_countPanel:getChildById('value')

	--EXCALTATION_FORGE_SYSTEM:addResourceWidget(RESOURCE_DUST, false, dust_countValue)

	local dust_rewardAmountWidget = convert_dustPanel:getChildById('forgeTextWithIcon')
	local dust_rewardAmountValue = dust_rewardAmountWidget:getChildById('value')
	--dust_rewardAmountValue:setText("6666")

	self.widgetStorage.dustRequired = dust_countValue
	self.widgetStorage.dustReward = dust_rewardAmountValue

	local dust_countIcon = dust_countPanel:getChildById('icon')
	dust_countIcon:setImageSource('/images/game/forge/icon-currency-dust')
	local dust_rewardWidget = convert_dustPanel:getChildById('rewardItem')
	dust_rewardWidget:setItemId(Forge.itemIds.SLIVER)

	self.widgetStorage.dustRewardWidget = dust_rewardWidget

	local dust_buttonProcced = convert_dustPanel:getChildById('convertDustProcced')
	dust_buttonProcced.onClick = function()
		g_game.sendForgeAction(ACTION_DUST_TO_SLIVER, false, nil, nil, nil)
	end

	self.widgetStorage.dustButtonProcced = dust_buttonProcced


	local convert_sliverPanel = mainPanel:getChildById('convertSliverPanel')
	local sliver_forgeItemWidget = convert_sliverPanel:getChildById('forgeItem')
	local sliver_forgeItemImage = sliver_forgeItemWidget:getChildById('image')
	sliver_forgeItemImage:setVisible(false)
	local sliver_forgeItem = sliver_forgeItemWidget:getChildById('item')
	sliver_forgeItem:setItemId(Forge.itemIds.SLIVER)
	self.widgetStorage.sliver_forgeItem = sliver_forgeItem
	local sliver_rewardWidget = convert_sliverPanel:getChildById('rewardItem')
	self.widgetStorage.sliverRewardWidget = sliver_rewardWidget
	sliver_rewardWidget:setItemId(Forge.itemIds.EXALTED_CORE)
	local sliver_rewardAmountWidget = convert_sliverPanel:getChildById('forgeTextWithIcon')
	local sliver_rewardAmountValue = sliver_rewardAmountWidget:getChildById('value')
	--sliver_rewardAmountValue:setText("6666")
	local sliver_rewardAmountIcon = sliver_rewardAmountWidget:getChildById('icon')
	sliver_rewardAmountIcon:setImageSource('/images/game/forge/icon-currency-exaltedcore')

	local sliver_countPanel = sliver_forgeItemWidget:getChildById('countPanel')
	local sliver_countValue = sliver_countPanel:getChildById('value')

	self.widgetStorage.sliverRequired = sliver_countValue
	self.widgetStorage.sliverReward = sliver_rewardAmountValue

	local sliver_buttonProcced = convert_sliverPanel:getChildById('sliverButtonProcced')
	sliver_buttonProcced.onClick = function()
		g_game.sendForgeAction(ACTION_SLIVER_TO_CORE, false, nil, nil, nil)
	end
	self.widgetStorage.sliverButtonProcced = sliver_buttonProcced
	self.widgetStorage.sliverRewardWidget = sliver_rewardWidget

	local dustLimitPanel = mainPanel:getChildById('dustLimitPanel')
	local dustLimit_forgeItemWidget = dustLimitPanel:getChildById('forgeItem')
	local dustLimit_forgeItemImage = dustLimit_forgeItemWidget:getChildById('image')
	local dustLimit_countPanel = dustLimit_forgeItemWidget:getChildById('countPanel')
	local dustLimit_countValue = dustLimit_countPanel:getChildById('value')
	local dustLimit_countIcon = dustLimit_countPanel:getChildById('icon')

	--dustLimit_countValue:setText('66666')
	dustLimit_countIcon:setImageSource('/images/game/forge/icon-currency-dust')

	local dustLimit_raiseLimitPanel = dustLimitPanel:getChildById('ForgeTextWithIcon2')
	local dustLimit_raiseLimitFirstValue = dustLimit_raiseLimitPanel:getChildById('value')
	local dustLimit_raiseLimitFirstIcon = dustLimit_raiseLimitPanel:getChildById('icon')
	dustLimit_raiseLimitFirstIcon:setImageSource('/images/game/forge/icon-currency-dust')
	--dustLimit_raiseLimitFirstValue:setText('66666')
	local dustLimit_raiseLimitSecondValue = dustLimit_raiseLimitPanel:getChildById('value2')
	local dustLimit_raiseLimitSecondIcon = dustLimit_raiseLimitPanel:getChildById('icon2')
	dustLimit_raiseLimitSecondIcon:setImageSource('/images/game/forge/icon-currency-dust')
	--dustLimit_raiseLimitSecondValue:setText('66666')

	self.widgetStorage.currentLimit = dustLimit_raiseLimitFirstValue
	self.widgetStorage.newLimit = dustLimit_raiseLimitSecondValue
	self.widgetStorage.limitCost = dustLimit_countValue
	self.widgetStorage.limitCostIcon = dustLimit_countIcon
	self.widgetStorage.raiseLimitPanel = dustLimit_raiseLimitPanel
	self.widgetStorage.raiseLimitFirstIcon = dustLimit_raiseLimitFirstIcon
	self.widgetStorage.raiseLimitSecondIcon = dustLimit_raiseLimitSecondIcon
	self.widgetStorage.raiseLimitLabel = dustLimitPanel:getChildById('raiseLimitLabel')

	local DustLimitProcced = dustLimitPanel:getChildById('DustLimitProcced')
	DustLimitProcced.onClick = function()
		g_game.sendForgeAction(ACTION_INCREASE_DUST_LIMIT, false, nil, nil, nil)
	end
	self.widgetStorage.DustLimitProcced = DustLimitProcced
	self.widgetStorage.imageFirst = dustLimitPanel:getChildById('DustLimitButtonImage1')
	self.widgetStorage.imageSecond = dustLimitPanel:getChildById('DustLimitButtonImage2')
end

function Conversion:showWindow()
	if Forge.currentPanel then
		Forge.currentPanel:setVisible(false)
	end

	if Forge.currentButton then
		Forge.currentButton:setEnabled(true)
	end

	Forge.currentPanel = self.mainWindow
	Forge.currentButton = self.mainButton
	self.mainWindow:setVisible(true)
	self.mainButton:setEnabled(false)
end

function Conversion:parseResourcesChange(data)
	self:updateDustToSliver()
	self:updateSliverToCore()
end
