Forge.History = {}

local History = Forge.History
History.mainWindow = nil

local HISTORY_COLORS = { '#414141', '#484848' }

local ACTION_TYPE_FUSION = 0
local ACTION_TYPE_TRANSFER = 1

function History:get()
	return self
end

function History:createButton()
	local buttonPanel = g_ui.createWidget('ForgeButton', Forge.mainWindow)
	buttonPanel:addAnchor(AnchorTop, 'FusionButton', AnchorTop)
	buttonPanel:addAnchor(AnchorLeft, 'ConversionButton', AnchorRight)
	buttonPanel:setId('HistoryButton')
	self.buttonPanel = buttonPanel
	self.mainButton = buttonPanel:getChildById('button')
	self.mainButton:setText("History")

	local iconWidget = buttonPanel:getChildById('icon')
	iconWidget:setImageSource("/images/game/forge/icon-history")
	if not self.mainWindow then
		g_ui.importStyle('History')
		self.mainWindow = g_ui.createWidget('HistoryWindow', Forge.mainWindow)
		self.mainWindow:addAnchor(AnchorTop, 'TransferButton', AnchorBottom)
		self.mainWindow:addAnchor(AnchorLeft, 'FusionButton', AnchorLeft)
		self.mainWindow:addAnchor(AnchorRight, 'parent', AnchorRight)

		self.historyMenu = self.mainWindow:getChildById('historyMenu')
		self.historyList = self.historyMenu:getChildById('historyList')
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
		g_game.sendForgeHistory(1)
	end
	self:init()
end

local function getActionText(actionType)
	if actionType == ACTION_TYPE_FUSION then
		return "Fusion"
	elseif actionType == ACTION_TYPE_TRANSFER then
		return "Transfer"
	else
		return "Conversion"
	end
end

local function getActionColor(actionType)
	if actionType == ACTION_TYPE_FUSION or actionType == ACTION_TYPE_TRANSFER then
		return "#BFBFBF"
	else
		return "#2791F5"
	end
end

local function parseDetails(details)
	if not details then
		return ""
	end

	local result = details:match("Successful")
	if result then return "Successful" end

	result = details:match("Unsuccessful")
	if result then return "Unsuccessful" end

	return details:gsub("<br>", " "):gsub("<.->", "")
end

function History:parse(currentPage, lastPage, data)
	self.currentPage = currentPage
	self.lastPage = lastPage
	self.data = data

	self.historyList:destroyChildren()

	for id, info in ipairs(data) do
		local widget = g_ui.createWidget('ForgeHistoryWidget', self.historyList)
		local backgroundColor = HISTORY_COLORS[((id - 1) % #HISTORY_COLORS) + 1]

		if id == 1 then
			widget:setMarginTop(16)
		end

		widget:setBackgroundColor(backgroundColor)

		local dateLabel = widget:getChildById('date')
		dateLabel:setText(info.date)
		dateLabel:setColor("#BFBFBF")

		local actionType = tonumber(info.action)
		local actionLabel = widget:getChildById('action')
		actionLabel:setText(getActionText(actionType))
		actionLabel:setColor(getActionColor(actionType))

		local detailsLabel = widget:getChildById('details')
		detailsLabel:setText(parseDetails(info.details))
		detailsLabel:setColor("#BFBFBF")
	end
end

function History:init()
end
