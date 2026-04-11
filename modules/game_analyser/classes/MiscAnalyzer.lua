if not MiscAnalyzer then
	MiscAnalyzer = {
		launchTime = 0,
		session = 0,
		charmEffects = {},
		ImbuementData = {},
		SpecialSkillData = {},
		BountyTalismanData = {},
		currentOverView = "none",

		-- private
		window = nil,
	}

	MiscAnalyzer.__index = MiscAnalyzer
end

local ImbuementSkills = {
	[1] = { name = "Critical Hit", icon = "critical" },
	[2] = { name = "Mana Leech", healing = "mana points", shortLenght = 5, placeholder = "Mana Gain", icon = "mana-leech" },
	[3] = { name = "Life Leech", healing = "health points", shortLenght = 6, placeholder = "Life Gain", icon = "life-leech" }
}

local SpecialSkills = {
	[1] = { name = "Onslaught" },
	[2] = { name = "Ruse" },
	[3] = { name = "Momentum" },
	[4] = { name = "Transcendence" }
}

local BountyTalismanStats = {
	[0] = { name = "Damage", placeholder = "Dmg Dealt", shortLength = 5, icon = "bounty-talisman-damage" },
	[2] = { name = "More Loot", placeholder = "More Loot", shortLength = 5, icon = "bounty-talisman-more-loot" },
	[3] = { name = "Double Kill", placeholder = "Double Kill", shortLength = 5, icon = "bounty-talisman-double-kill" },
}

local CharmNames = {
	[0] = "Wound",
	[1] = "Enflame",
	[2] = "Poison",
	[3] = "Freeze",
	[4] = "Zap",
	[5] = "Curse",
	[6] = "Cripple",
	[7] = "Parry",
	[8] = "Dodge",
	[9] = "Adrenaline Burst",
	[10] = "Numb",
	[11] = "Cleanse",
	[12] = "Bless",
	[13] = "Scavenge",
	[14] = "Gut",
	[15] = "Low Blow",
	[16] = "Divine Wrath",
	[17] = "Vampiric Embrace",
	[18] = "Void's Call",
	[19] = "Savage Blow",
	[20] = "Fatal Hold",
	[21] = "Void Inversion",
	[22] = "Carnage",
	[23] = "Overpower",
	[24] = "Overflux"
}

function MiscAnalyzer:create()
	MiscAnalyzer.launchTime = 0
	MiscAnalyzer.session = 0
	MiscAnalyzer.charmEffects = {}
	MiscAnalyzer.ImbuementData = {}
	MiscAnalyzer.SpecialSkillData = {}
	MiscAnalyzer.BountyTalismanData = {}
	MiscAnalyzer.currentOverView = "none"

	MiscAnalyzer.window = openedWindows['miscButton']

	local toggleFilterButton = MiscAnalyzer.window:recursiveGetChildById('toggleFilterButton')
	if toggleFilterButton then
		toggleFilterButton:setVisible(false)
	end

	local newWindowButton = MiscAnalyzer.window:recursiveGetChildById('newWindowButton')
	if newWindowButton then
		newWindowButton:setVisible(false)
	end

	local contextMenuButton = MiscAnalyzer.window:recursiveGetChildById('contextMenuButton')
	local minimizeButton = MiscAnalyzer.window:recursiveGetChildById('minimizeButton')

	if contextMenuButton and minimizeButton then
		contextMenuButton:setVisible(true)
		contextMenuButton:breakAnchors()
		contextMenuButton:addAnchor(AnchorTop, minimizeButton:getId(), AnchorTop)
		contextMenuButton:addAnchor(AnchorRight, minimizeButton:getId(), AnchorLeft)
		contextMenuButton:setMarginRight(7)
		contextMenuButton:setMarginTop(0)

		contextMenuButton.onClick = function(widget, mousePos)
			local pos = mousePos or g_window.getMousePosition()
			return onMiscAnalyzerExtra(pos)
		end
	end

	local lockButton = MiscAnalyzer.window:recursiveGetChildById('lockButton')

	if lockButton and contextMenuButton then
		lockButton:setVisible(true)
		lockButton:breakAnchors()
		lockButton:addAnchor(AnchorTop, contextMenuButton:getId(), AnchorTop)
		lockButton:addAnchor(AnchorRight, contextMenuButton:getId(), AnchorLeft)
		lockButton:setMarginRight(2)
		lockButton:setMarginTop(0)
	end
end

function MiscAnalyzer:reset()
	MiscAnalyzer.launchTime = g_clock.millis()
	MiscAnalyzer.session = 0
	MiscAnalyzer.charmEffects = {}
	MiscAnalyzer.ImbuementData = {}
	MiscAnalyzer.SpecialSkillData = {}
	MiscAnalyzer.currentOverView = "none"

	MiscAnalyzer:updateWindow(true)
end

function MiscAnalyzer:getPerHourValue(value)
	local session = MiscAnalyzer.session
	if session == 0 then
		return 0
	end

	local sessionDuration = math.max(1, os.time() - session)
	if sessionDuration <= 0 then
		return 0
	end

	local hitsPerSecond = value / sessionDuration
	local hitsPerHour = hitsPerSecond * 3600

	return format_thousand(math.floor(hitsPerHour + 0.5))
end

function MiscAnalyzer:updateWindow(updateScroll, ignoreVisible)
	if not MiscAnalyzer.window:isVisible() and not ignoreVisible then
		return
	end

	local player = g_game.getLocalPlayer()
	if not player then
		return
	end

	local contentsPanel = MiscAnalyzer.window.contentsPanel
	local session = MiscAnalyzer.session
	if session == 0 then
		contentsPanel.session:setText("00:00h")
	else
		local duration = math.max(1, os.time() - session)
		local hours = math.floor(duration / 3600)
		local minutes = math.floor((duration % 3600) / 60)
		local sessionTimeStr = string.format("%02d:%02dh", hours, minutes)
		if sessionTimeStr ~= contentsPanel.session:getText() then
			contentsPanel.session:setText(sessionTimeStr)
		end
	end

	MiscAnalyzer:updateCharms(contentsPanel)
	MiscAnalyzer:updateImbuements(contentsPanel)
	MiscAnalyzer:updateSpecialSkills(contentsPanel)
	MiscAnalyzer:updateBountyTalisman(contentsPanel)
end

function MiscAnalyzer:updateCharms(contentsPanel)
	local widgets = {}
	local charmTypes = contentsPanel.charmTypes
	local charmEffects = MiscAnalyzer.charmEffects

	for _, child in pairs(charmTypes:getChildren()) do
		child.toBeRemoved = true
	end

	if table.empty(charmEffects) then
		if charmTypes:getChildCount() > 0 then
			charmTypes:destroyChildren()
			g_ui.createWidget('EmptyData', charmTypes)
		end
	else
		for effect, count in pairs(charmEffects) do
			local widget = charmTypes:getChildById("CharmEffects_" .. effect)
			local name = CharmNames[effect] or "Unknown"

			if not widget then
				widget = g_ui.createWidget('MiscTracker', charmTypes)
				widget:setId("CharmEffects_" .. effect)
				widget.effects:setImageSource(string.format("/images/game/analyzer/charm_runes/charm_%d", effect))
			end
			widget.name:setText(name)
			widget.total:setText(count)
			widget.tooltip:setTooltip(string.format("Charm: %s\nActive: %d", name, count))
			widget.toBeRemoved = false
			table.insert(widgets, { id = effect, widget = widget })
		end
	end

	for _, child in pairs(charmTypes:getChildren()) do
		if child.toBeRemoved then
			child:destroy()
		end
	end

	table.sort(widgets, function(a, b) return a.id < b.id end)

	for index, entry in ipairs(widgets) do
		charmTypes:moveChildToIndex(entry.widget, index)
	end
end

function MiscAnalyzer:updateImbuements(contentsPanel)
	local widgets = {}
	local imbuementTypes = contentsPanel.imbuementTypes
	local imbuementData = MiscAnalyzer.ImbuementData

	for _, child in pairs(imbuementTypes:getChildren()) do
		child.toBeRemoved = true
	end

	if table.empty(imbuementData) then
		if imbuementTypes:getChildCount() > 0 then
			imbuementTypes:destroyChildren()
			g_ui.createWidget('EmptyData', imbuementTypes)
		end
	else
		for id, amount in pairs(imbuementData) do
			local widget = imbuementTypes:getChildById("imbuement_" .. id)
			local data = ImbuementSkills[id]

			if not widget then
				widget = g_ui.createWidget('MiscTracker', imbuementTypes)
				widget:setId("imbuement_" .. id)
				widget.effects:setImageSource(string.format("/images/game/analyzer/misc/%s", data.icon))
			end

			if id > 1 then
				local converted = numberToStr(amount)
				widget.total:setText(numberToStr(amount))
				widget.tooltip:setTooltip(string.format(
				"Your %s has healed you a total of %s %s\n\nYou're healing %s %s per hour", data.name:lower(),
					format_thousand(amount), data.healing, MiscAnalyzer:getPerHourValue(amount), data.healing))
				widget.name:setText(data.placeholder)

				if #converted > data.shortLenght then
					widget.name:setText(short_text(data.placeholder, 7))
				end
			else
				widget.name:setText(data.name)
				widget.total:setText(format_thousand(amount))
				widget.tooltip:setTooltip(string.format(
				"Your %s has activated %s times\n\nCurrently activating %s times per hour", data.name:lower(),
					format_thousand(amount), MiscAnalyzer:getPerHourValue(amount)))
			end

			widget.tooltip.onClick = function()
				local overViewPanel = contentsPanel.overviewPanel
				local currentView = MiscAnalyzer.currentOverView

				if currentView == data.name then
					overViewPanel:setVisible(not overViewPanel:isVisible())
				else
					overViewPanel:setVisible(true)
				end

				MiscAnalyzer.currentOverView = data.name
				overViewPanel:recursiveGetChildById('description'):setText(widget.tooltip:getTooltip())
			end

			widget.toBeRemoved = false
			table.insert(widgets, { id = id, widget = widget })

			-- Update overview panel
			local overViewPanel = contentsPanel.overviewPanel
			if MiscAnalyzer.currentOverView == data.name and overViewPanel:isVisible() then
				overViewPanel:recursiveGetChildById('description'):setText(widget.tooltip:getTooltip())
			end
		end
	end

	for _, child in pairs(imbuementTypes:getChildren()) do
		if child.toBeRemoved then
			child:destroy()
		end
	end

	if not table.empty(imbuementData) then
		table.sort(widgets, function(a, b) return a.id < b.id end)

		for index, entry in ipairs(widgets) do
			imbuementTypes:moveChildToIndex(entry.widget, index)
		end
	end
end

function MiscAnalyzer:updateSpecialSkills(contentsPanel)
	local widgets = {}
	local specialTypes = contentsPanel.specialTypes
	local specialData = MiscAnalyzer.SpecialSkillData

	for _, child in pairs(specialTypes:getChildren()) do
		child.toBeRemoved = true
	end

	if table.empty(specialData) then
		if specialTypes:getChildCount() > 0 then
			specialTypes:destroyChildren()
			g_ui.createWidget('EmptyData', specialTypes)
		end
	else
		for id, amount in pairs(specialData) do
			local widget = specialTypes:getChildById("special_" .. id)
			local data = SpecialSkills[id]

			if not widget then
				widget = g_ui.createWidget('MiscTracker', specialTypes)
				widget:setId("special_" .. id)
				widget.effects:setImageSource(string.format("/images/game/analyzer/misc/%s", data.name:lower()))
			end
			widget.name:setText(data.name)

			widget.total:setText(amount)
			widget.tooltip:setTooltip(string.format(
			"Your %s has activated %s times\n\nCurrently activating %s times per hour", data.name:lower(),
				format_thousand(amount), MiscAnalyzer:getPerHourValue(amount)))

			widget.tooltip.onClick = function()
				local overViewPanel = contentsPanel.overviewPanel
				local currentView = MiscAnalyzer.currentOverView

				if currentView == data.name then
					overViewPanel:setVisible(not overViewPanel:isVisible())
				else
					overViewPanel:setVisible(true)
				end

				MiscAnalyzer.currentOverView = data.name
				overViewPanel:recursiveGetChildById('description'):setText(widget.tooltip:getTooltip())
			end

			widget.toBeRemoved = false
			table.insert(widgets, { id = id, widget = widget })

			-- Update overview panel
			local overViewPanel = contentsPanel.overviewPanel
			if MiscAnalyzer.currentOverView == data.name and overViewPanel:isVisible() then
				overViewPanel:recursiveGetChildById('description'):setText(widget.tooltip:getTooltip())
			end
		end
	end

	for _, child in pairs(specialTypes:getChildren()) do
		if child.toBeRemoved then
			child:destroy()
		end
	end

	if not table.empty(specialData) then
		table.sort(widgets, function(a, b) return a.id < b.id end)

		for index, entry in ipairs(widgets) do
			specialTypes:moveChildToIndex(entry.widget, index)
		end
	end
end

function MiscAnalyzer:onCharmActivated(charmId)
	if not CharmNames[charmId] then
		return
	end

	local count = MiscAnalyzer.charmEffects[charmId] or 0
	MiscAnalyzer.charmEffects[charmId] = count + 1
end

function MiscAnalyzer:onImbuementActivated(imbuementId, amount)
	if not ImbuementSkills[imbuementId] then
		return
	end

	if imbuementId > 1 then
		local data = MiscAnalyzer.ImbuementData[imbuementId] or 0
		MiscAnalyzer.ImbuementData[imbuementId] = data + amount
	else
		local count = MiscAnalyzer.ImbuementData[imbuementId] or 0
		MiscAnalyzer.ImbuementData[imbuementId] = count + 1
	end
end

function MiscAnalyzer:onSpecialSkillActivated(skillId)
	if not SpecialSkills[skillId + 1] then
		return
	end

	local count = MiscAnalyzer.SpecialSkillData[skillId + 1] or 0
	MiscAnalyzer.SpecialSkillData[skillId + 1] = count + 1
end

function MiscAnalyzer:onBountyTalismanActivated(statType, amount)
	if not BountyTalismanStats[statType] then
		return
	end

	local data = MiscAnalyzer.BountyTalismanData[statType] or 0
	MiscAnalyzer.BountyTalismanData[statType] = data + amount
end

function MiscAnalyzer:updateBountyTalisman(contentsPanel)
	local widgets = {}
	local bountyTypes = contentsPanel.bountyTalismanTypes
	local bountyData = MiscAnalyzer.BountyTalismanData

	for _, child in pairs(bountyTypes:getChildren()) do
		child.toBeRemoved = true
	end

	if table.empty(bountyData) then
		if bountyTypes:getChildCount() > 0 then
			bountyTypes:destroyChildren()
			g_ui.createWidget('EmptyData', bountyTypes)
		end
	else
		for statType, amount in pairs(bountyData) do
			local widget = bountyTypes:getChildById("bounty_" .. statType)
			local data = BountyTalismanStats[statType]

			if not widget then
				widget = g_ui.createWidget('MiscTracker', bountyTypes)
				widget:setId("bounty_" .. statType)
				widget.effects:setImageSource(string.format("/images/game/analyzer/misc/%s", data.icon))
			end

			local converted = numberToStr(amount)
			widget.total:setText(converted)
			widget.name:setText(data.placeholder)

			if #converted > data.shortLength then
				widget.name:setText(short_text(data.placeholder, 7))
			end

			if statType == 0 then
				widget.tooltip:setTooltip(string.format(
				"Your Bounty Talisman has dealt %s extra damage\n\nDealing %s extra damage per hour",
					format_thousand(amount), MiscAnalyzer:getPerHourValue(amount)))
			else
				widget.tooltip:setTooltip(string.format(
				"Your %s has activated %s times\n\nCurrently activating %s times per hour", data.name:lower(),
					format_thousand(amount), MiscAnalyzer:getPerHourValue(amount)))
			end

			widget.tooltip.onClick = function()
				local overViewPanel = contentsPanel.overviewPanel
				local currentView = MiscAnalyzer.currentOverView

				if currentView == data.name then
					overViewPanel:setVisible(not overViewPanel:isVisible())
				else
					overViewPanel:setVisible(true)
				end

				MiscAnalyzer.currentOverView = data.name
				overViewPanel:recursiveGetChildById('description'):setText(widget.tooltip:getTooltip())
			end

			widget.toBeRemoved = false
			table.insert(widgets, { id = statType, widget = widget })

			local overViewPanel = contentsPanel.overviewPanel
			if MiscAnalyzer.currentOverView == data.name and overViewPanel:isVisible() then
				overViewPanel:recursiveGetChildById('description'):setText(widget.tooltip:getTooltip())
			end
		end
	end

	for _, child in pairs(bountyTypes:getChildren()) do
		if child.toBeRemoved then
			child:destroy()
		end
	end

	if not table.empty(bountyData) then
		table.sort(widgets, function(a, b) return a.id < b.id end)

		for index, entry in ipairs(widgets) do
			bountyTypes:moveChildToIndex(entry.widget, index)
		end
	end
end

function MiscAnalyzer:resetSessionData()
	MiscAnalyzer.charmEffects = {}
	MiscAnalyzer.ImbuementData = {}
	MiscAnalyzer.SpecialSkillData = {}
	MiscAnalyzer.BountyTalismanData = {}
	MiscAnalyzer.session = os.time()
	MiscAnalyzer.window:recursiveGetChildById("overviewPanel"):setVisible(false)
	MiscAnalyzer:updateWindow()
end

function MiscAnalyzer:resetCharmData()
	MiscAnalyzer.charmEffects = {}
	MiscAnalyzer.window:recursiveGetChildById("overviewPanel"):setVisible(false)
	MiscAnalyzer:updateWindow()
end

function MiscAnalyzer:resetImbuementData()
	MiscAnalyzer.ImbuementData = {}
	MiscAnalyzer.window:recursiveGetChildById("overviewPanel"):setVisible(false)
	MiscAnalyzer:updateWindow()
end

function MiscAnalyzer:resetSpecialData()
	MiscAnalyzer.SpecialSkillData = {}
	MiscAnalyzer.window:recursiveGetChildById("overviewPanel"):setVisible(false)
	MiscAnalyzer:updateWindow()
end

function MiscAnalyzer:resetBountyTalismanData()
	MiscAnalyzer.BountyTalismanData = {}
	MiscAnalyzer.window:recursiveGetChildById("overviewPanel"):setVisible(false)
	MiscAnalyzer:updateWindow()
end

function MiscAnalyzer:clipboardData()
	local contentsPanel = MiscAnalyzer.window.contentsPanel

	local text = "- Session: " .. contentsPanel.session:getText() .. "\n\n"
	text = text .. "\nCharm Data:\n"
	for _, child in pairs(contentsPanel.charmTypes:getChildren()) do
		if child.total then
			text = text .. "- " .. child.name:getText() .. ": " .. child.total:getText() .. "\n"
		end
	end

	text = text .. "\nImbuement Data:\n"
	for _, child in pairs(contentsPanel.imbuementTypes:getChildren()) do
		if child.total then
			text = text .. "- " .. child.name:getText() .. ": " .. child.total:getText() .. "\n"
		end
	end

	text = text .. "\nItem Upgrade:\n"
	for _, child in pairs(contentsPanel.specialTypes:getChildren()) do
		if child.total then
			text = text .. "- " .. child.name:getText() .. ": " .. child.total:getText() .. "\n"
		end
	end

	text = text .. "\nBounty Talisman:\n"
	for _, child in pairs(contentsPanel.bountyTalismanTypes:getChildren()) do
		if child.total then
			text = text .. "- " .. child.name:getText() .. ": " .. child.total:getText() .. "\n"
		end
	end

	g_window.setClipboardText(text)
end

function onMiscAnalyzerExtra(mousePosition)
	if cancelNextRelease then
		cancelNextRelease = false
		return false
	end

	local menu = g_ui.createWidget('PopupMenu')
	menu:setGameMenu(true)

	menu:addOption(tr('Reset Session Data'), function() MiscAnalyzer:resetSessionData() end)
	menu:addSeparator()

	menu:addOption(tr('Reset Charm Data'), function() MiscAnalyzer:resetCharmData() end)
	menu:addOption(tr('Reset Imbuement Data'), function() MiscAnalyzer:resetImbuementData() end)
	menu:addOption(tr('Reset Item Upgrade'), function() MiscAnalyzer:resetSpecialData() end)
	menu:addOption(tr('Reset Bounty Talisman'), function() MiscAnalyzer:resetBountyTalismanData() end)

	menu:addSeparator()
	menu:addOption(tr('Copy to Clipboard'), function() MiscAnalyzer:clipboardData() end)
	menu:display(mousePosition)
	return true
end
