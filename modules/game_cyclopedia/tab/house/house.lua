---------------------------
-- House Cyclopedia Module
-- Using g_things for static data + g_game for dynamic data
---------------------------

local UI = nil

Cyclopedia.House = Cyclopedia.House or {}

-- Local state
local lastSelectedHouse = nil
local currentHouseList = {}
local houseList = {}
local currentStateSort = 1
local currentStatusSort = 1
local showGuildHalls = false
local currentTownName = ""
local infoWindow = nil
local placeBidWindow = nil

-- Error messages for bid button
local bidButtonError = {
    [3] = "Characters on the beginner's island are not allowed to rent houses.",
    [7] = "The transfer has already been accepted.",
    [11] =
    "A character of your account already holds the highest bid for\nanother house. You may only bid for one house at the same time.",
    [12] = "The characters of your account already own 1 houses. You may\nonly own 1 house at the same time.",
    [13] =
    "A character of this account has already accepted a house transfer.\nYou need to wait until the first transfer has been completed before you can transfer this house."
}

-- Message types for house actions
local messageTypes = {
    [1] = { -- bid
        [0] = "Your bid was successful. You are currently holding the highest bid.",
        [1] =
        "You have successfully placed a bid but you are not holding the highest bid. Another character's bid limit was\nhigher than your maximum."
    },
    [2] = { -- move out
        [0] = "You have successfully initiated your move out."
    },
    [3] = { -- transfer
        [0] = "You have successfully initiated the transfer of your house.",
        [2] = "Setting up a house transfer failed.\nYou are not the owner of this house.",
        [4] = "Setting up a house transfer failed.\nA character with this name does not exist.",
        [8] = "Setting up a house transfer failed.\nA guildhall may only be transferred to a leader of an active guild.",
        [10] = "Setting up a house transfer failed.\nThe characters of this account may not rent more houses.",
        [12] =
        "Setting up a house transfer failed.\nThis character cannot accept a house transfer because a character of this account is currently bidding for a house.",
        [15] = "Setting up a house transfer failed.\nThe transfer has already been accepted.",
        [16] = "Setting up a house transfer failed.\nCharacters on the beginner's island are not allowed to rent houses.",
        [21] = "Setting up a house transfer failed.\nInternal error."
    },
    [4] = { -- cancel move out
        [0] = "You have successfully cancelled your move out. You will keep the house."
    },
    [5] = { -- cancel transfer
        [0] = "You have successfully cancelled the transfer. You will keep the house.",
        [21] = "An internal error has occurred."
    },
    [6] = { -- accept transfer
        [0] = "You have successfully accepted the transfer.",
        [2] = "Accepting the transfer failed.\nThis character is not the designated new owner of this house.",
        [3] =
        "Accepting the transfer failed.\nYou cannot accept a house transfer as long as one of your characters is bidding for a house.",
        [7] = "Accepting the transfer failed.\nThe transfer has already been accepted.",
        [8] = "Accepting the transfer failed.\nCharacters on the beginner's island are not allowed to rent houses.",
        [11] = "Accepting the transfer failed.\nYou may not rent more houses.",
        [21] = "An internal error has occurred."
    },
    [7] = { -- reject transfer
        [0] = "You rejected the house transfer successfully.\nThe old owner will keep the house.",
        [21] = "An internal error has occurred."
    }
}

-- Cleanup function
function Cyclopedia.House.cleanup()
    UI = nil
    lastSelectedHouse = nil
    currentHouseList = {}
    houseList = {}
    infoWindow = nil
    placeBidWindow = nil
    Cyclopedia.House.Loaded = false

    disconnect(g_game, {
        onCyclopediaHouseList = Cyclopedia.House.onRecvHousesData,
        onCyclopediaHouseAuctionMessage = Cyclopedia.House.onRecvHouseMessage
    })
end

function Cyclopedia.House.resetWindow()
    showGuildHalls = false
    currentTownName = ""
    currentStateSort = 1
    currentStatusSort = 1
    lastSelectedHouse = nil
    currentHouseList = {}
    houseList = {}
    infoWindow = nil
end

-- Build city list dynamically from g_things.getHouseCities()
function Cyclopedia.buildCityList()
    local cityList = {
        [0] = { Title = "Own Houses" }
    }

    local cities = g_things.getHouseCities()
    table.sort(cities, function(a, b)
        return a < b
    end)

    for i, city in ipairs(cities) do
        cityList[i] = { Title = city }
    end

    return cityList
end

Cyclopedia.StateList = {
    { Title = "All States" },
    { Title = "Auctioned" },
    { Title = "Rented" }
}

Cyclopedia.SortList = {
    { Title = "Sort by name" },
    { Title = "Sort by size" },
    { Title = "Sort by rent" },
    { Title = "Sort by bid" },
    { Title = "Sort by auction end" }
}

-- Main show function
function showHouse()
    UI = g_ui.loadUI("house", contentContainer)
    if not UI then
        g_logger.error("Failed to load house UI")
        return
    end
    UI:show()

    controllerCyclopedia.ui.CharmsBase:setVisible(false)
    controllerCyclopedia.ui.GoldBase:setVisible(true)
    controllerCyclopedia.ui.BestiaryTrackerButton:setVisible(false)
    if g_game.getClientVersion() >= 1410 then
        controllerCyclopedia.ui.CharmsBase1410:setVisible(false)
    end

    if not Cyclopedia.House.Loaded then
        -- State filter
        for i = 1, #Cyclopedia.StateList do
            UI.checkboxBackground.allStates:addOption(Cyclopedia.StateList[i].Title, i)
        end
        UI.checkboxBackground.allStates.onOptionChange = Cyclopedia.House.onStateSort

        -- City list (dynamic from g_things)
        local cityList = Cyclopedia.buildCityList()
        for i = 0, #cityList do
            UI.checkboxBackground.ownHouses:addOption(cityList[i].Title, i)
        end
        UI.checkboxBackground.ownHouses.onOptionChange = Cyclopedia.House.selectTown

        -- Sort options
        for i = 1, #Cyclopedia.SortList do
            UI.checkboxBackground.sortName:addOption(Cyclopedia.SortList[i].Title, i)
        end
        UI.checkboxBackground.sortName.onOptionChange = Cyclopedia.House.onStatusSort

        Cyclopedia.House.Loaded = true
    end

    -- Set defaults
    UI.checkboxBackground.allStates:setOption("All States", true)
    UI.checkboxBackground.ownHouses:setOption("Own Houses", true)
    UI.checkboxBackground.sortName:setOption("Sort by name", true)
    UI.checkboxBackground.checkHouses:setChecked(true)
    UI.checkboxBackground.checkGuildhalls:setChecked(false)

    -- Initial load
    Cyclopedia.House.selectTown(UI.checkboxBackground.ownHouses, "Own Houses", 0)
end

-- Select town/city - sends request to server
function Cyclopedia.House.selectTown(widget, text, index)
    if not UI or not UI.mapViewBackground then
        return
    end

    Cyclopedia.House.resetData()
    currentTownName = text or ""

    lastSelectedHouse = nil
    currentHouseList = {}

    if UI.mapViewBackground.minimap and UI.mapViewBackground.minimapContainer.noSelectedBackground.noSelected then
        UI.mapViewBackground.minimapContainer.noSelectedBackground.noSelected:setText("")
    end

    if UI.bidHouseWindow and UI.bidHouseWindow:isVisible() then
        UI.selectedBackground:setVisible(true)
        UI.bidHouseWindow:setVisible(false)
    end

    -- Send request to server (type 0 = request house list for town)
    -- IMPORTANT: Server expects empty string for "Own Houses" to return player's owned/bidding houses
    local serverTownName = currentTownName
    if currentTownName == "Own Houses" then
        serverTownName = ""
    end
    g_game.sendCyclopediaHouseAuction(0, 0, 0, 0, serverTownName)
    Cyclopedia.House.setupMinimap(0)
end

-- Called when server sends house list data
function Cyclopedia.House.onRecvHousesData(houses)
    if not UI or not UI.mapViewBackground then
        return
    end

    local panelHouse = UI.selectedBackground.panelHouse
    panelHouse:destroyChildren()

    local staticHouseList = g_things.getHouseList()

    for _, data in ipairs(Cyclopedia.House.sortDataByStatus(houses)) do
        -- Find static data by houseId
        local static = nil
        for _, h in ipairs(staticHouseList) do
            if h.id == data.houseId then
                static = h
                break
            end
        end

        if not static then
            goto continue
        end

        -- Filter by guildhall
        if (showGuildHalls and not static.isGuildHall) or (not showGuildHalls and static.isGuildHall) then
            goto continue
        end

        -- Filter by state (0 = available/auctioned, 2/3/4 = rented variants)
        if currentStateSort == 2 and data.state ~= 0 then
            goto continue
        end
        if currentStateSort == 3 and (data.state ~= 2 and data.state ~= 3 and data.state ~= 4) then
            goto continue
        end

        local widget = g_ui.createWidget('HouseData', panelHouse)
        widget.main:setText(static.name)
        widget.main.sizeValueText:setText(static.sqms .. " sqm")
        widget.main.maxBedsValueText:setText(static.beds)
        widget.main.rentValueText:setText(math.floor(static.rent / 1000) .. " k")

        if data.state == 0 then
            -- Available/Auctioned
            local statusText = ""
            if not data.bidderName or #data.bidderName == 0 then
                statusText = "{auctioned, #00f000} {(no bid yet), #c0c0c0}"
            else
                local timeLeft = math.max(0, data.bidEnd - os.time())
                local timeLeftStr = ""

                if timeLeft == 0 then
                    timeLeftStr = "Expired"
                else
                    local hours = math.floor(timeLeft / 3600)
                    local minutes = math.floor((timeLeft % 3600) / 60)
                    local seconds = timeLeft % 60

                    if hours > 0 then
                        timeLeftStr = hours .. "h " .. minutes .. "min"
                    elseif minutes > 0 then
                        timeLeftStr = minutes .. "min " .. seconds .. "s"
                    else
                        timeLeftStr = seconds .. "s"
                    end
                end
                statusText = "{auctioned, #00f000} {(Bid: " .. comma_value(data.highestBid) .. " Ends in: " .. timeLeftStr .. "), #c0c0c0}"
            end
            widget.main.statusValueText:setColoredText(statusText)
        elseif data.state == 2 or data.state == 3 or data.state == 4 then
            -- Rented (2), Transfer (3), Moveout (4)
            widget.main.statusValueText:setText("rented by " .. (data.owner or ""))
            widget.main.statusValueText:setColor("#c0c0c0")
            local player = g_game.getLocalPlayer()
            local playerName = player and player:getName() or nil
            if playerName and data.owner == playerName then
                widget.main.imageOwnHouse:setVisible(true)
            end
        end

        widget.main:setActionId(data.houseId)
        currentHouseList[data.houseId] = { mainData = data, staticData = static }

        ::continue::
    end

    if #panelHouse:getChildren() == 0 then
        panelHouse:setText("No result.")
        if UI.mapViewBackground.minimap and UI.mapViewBackground.minimapContainer.noSelectedBackground.noSelected then
            UI.mapViewBackground.minimapContainer.noSelectedBackground.noSelected:setText("No house selected")
        end
        Cyclopedia.House.setupMinimap(0)
    else
        if not UI.bidHouseWindow or not UI.bidHouseWindow:isVisible() then
            local firstChild = panelHouse:getChildren()[1]
            if firstChild and firstChild.main then
                Cyclopedia.House.onSelectHouse(firstChild.main)
            end
            panelHouse:setText("")
        end
    end

    houseList = houses
end

-- Called when server sends house auction message
function Cyclopedia.House.onRecvHouseMessage(houseId, bidType, messageType)
    if infoWindow ~= nil then
        return
    end

    if not controllerCyclopedia or not controllerCyclopedia.ui then
        return
    end

    controllerCyclopedia.ui:hide()

    local message = messageTypes[bidType] and messageTypes[bidType][messageType] or "Unknown message"

    local okFunction = function()
        g_game.sendCyclopediaHouseAuction(0, 0, 0, 0, currentTownName)
        Cyclopedia.House.updateHouseView(bidType)

        if bidType == 2 and messageType == 0 then
            if UI.moveDate then UI.moveDate:setVisible(false) end
            UI.selectedBackground:setVisible(true)
        elseif bidType == 3 and messageType == 0 then
            if UI.configureHouseTransfer then UI.configureHouseTransfer:setVisible(false) end
            UI.selectedBackground:setVisible(true)
        elseif bidType == 4 then
            if UI.keepHouse then UI.keepHouse:setVisible(false) end
            UI.selectedBackground:setVisible(true)
        elseif bidType == 5 then
            if UI.cancelTransferHouse then UI.cancelTransferHouse:setVisible(false) end
            UI.selectedBackground:setVisible(true)
        elseif bidType == 7 and messageType == 0 then
            if UI.rejectTransferHouse then UI.rejectTransferHouse:setVisible(false) end
            UI.selectedBackground:setVisible(true)
        end

        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
        infoWindow:destroy()
        infoWindow = nil
    end

    infoWindow = displayGeneralBox(tr('Summary'), tr("%s", message), { { text = tr('Ok'), callback = okFunction } },
        okFunction)
end

function Cyclopedia.House.updateHouseView(bidType)
    if not lastSelectedHouse then
        return
    end

    Cyclopedia.House.onSelectHouse(lastSelectedHouse)
    if bidType == 1 then
        Cyclopedia.House.onBidButton(nil)
    end
end

-- Select a house
function Cyclopedia.House.onSelectHouse(widget)
    if lastSelectedHouse then
        lastSelectedHouse:setBorderWidth(0)
        lastSelectedHouse:setBorderColor('alpha')
    end

    lastSelectedHouse = widget
    widget:setBorderWidth(2)
    widget:setBorderColor('white')

    Cyclopedia.House.setupMinimap(widget:getActionId())
    if UI.mapViewBackground.minimap and UI.mapViewBackground.minimapContainer.noSelectedBackground.noSelected then
        UI.mapViewBackground.minimapContainer.noSelectedBackground.noSelected:setText("")
    end

    -- Hide all action panels
    if UI.moveDate then UI.moveDate:setVisible(false) end
    if UI.keepHouse then UI.keepHouse:setVisible(false) end
    if UI.cancelTransferHouse then UI.cancelTransferHouse:setVisible(false) end
    if UI.rejectTransferHouse then UI.rejectTransferHouse:setVisible(false) end
    if UI.acceptTransferHouse then UI.acceptTransferHouse:setVisible(false) end
    if UI.configureHouseTransfer then UI.configureHouseTransfer:setVisible(false) end

    if not UI.selectedBackground:isVisible() then
        UI.selectedBackground:setVisible(true)
    end

    Cyclopedia.House.resetData()

    local dataList = currentHouseList[widget:getActionId()]
    if not dataList then
        return
    end

    local currentInfo = dataList.mainData
    local static = dataList.staticData
    if not currentInfo or not static then
        return
    end

    -- Update panel info based on state
    local panel = UI.mapViewBackground:recursiveGetChildById("panelTextsRents")
    if not panel then return end

    if panel.rental then
        panel.rental.imageOwnHouseRental:setVisible(false)
    end

    if currentInfo.state == 0 then
        -- Available/Auctioned
        if panel.bidButton then
            panel.bidButton:setEnabled(true)
            panel.bidButton:setVisible(true)
            panel.bidButton:setTooltip("")

            if currentInfo.canBidError and currentInfo.canBidError ~= 0 then
                panel.bidButton:setEnabled(false)
                panel.bidButton:setTooltip(bidButtonError[currentInfo.canBidError] or "Error")
            end
        end

        if currentInfo.bidderName and #currentInfo.bidderName > 0 and panel.bidInfo then
            panel.bidInfo:setVisible(true)
            panel.bidInfo.bidderName:setText(currentInfo.bidderName)
            panel.bidInfo.endValue:setText(Cyclopedia.House.formatDate(currentInfo.bidEnd))
            panel.bidInfo.highestBidValue:setText(comma_value(currentInfo.highestBid))

            -- Show player's own bid limit if they are the current bidder
            if currentInfo.bidOwner then
                if panel.bidInfo.yourLimitLabel then
                    panel.bidInfo.yourLimitLabel:setVisible(true)
                    panel.bidInfo.yourLimitValue:setVisible(true)
                    panel.bidInfo.yourLimitValue:setText(comma_value(currentInfo.holderLimit))
                    if panel.bidInfo.yourLimitGold then
                        panel.bidInfo.yourLimitGold:setVisible(true)
                    end
                end
            else
                if panel.bidInfo.yourLimitLabel then
                    panel.bidInfo.yourLimitLabel:setVisible(false)
                end
                if panel.bidInfo.yourLimitValue then
                    panel.bidInfo.yourLimitValue:setVisible(false)
                end
                if panel.bidInfo.yourLimitGold then
                    panel.bidInfo.yourLimitGold:setVisible(false)
                end
            end
        elseif panel.noBidHouseHeader then
            panel.noBidHouseHeader:setVisible(true)
            if panel.noBidHouseText then
                panel.noBidHouseText:setVisible(true)
            end
        end
    elseif currentInfo.state == 2 or currentInfo.state == 3 or currentInfo.state == 4 then
        -- Rented / Transfer / Moveout
        if panel.rental then
            panel.rental:setVisible(true)
            panel.rental.tenantValue:setText(currentInfo.owner or "")
            panel.rental.paidValue:setText(Cyclopedia.House.formatDate(currentInfo.paidUntil))

            local player = g_game.getLocalPlayer()
            local playerName = player and player:getName() or nil

            if playerName and currentInfo.state == 4 and currentInfo.owner == playerName then
                -- Moveout pending
                panel.rental.imageOwnHouseRental:setVisible(true)
                if panel.rental.moveImage then
                    panel.rental.moveImage:setVisible(true)
                    if panel.rental.moveImage.moveValue then
                        panel.rental.moveImage.moveValue:setText(Cyclopedia.House.formatDate(currentInfo.scheduleTime))
                    end
                end
                if panel.rental.keepButton then panel.rental.keepButton:setVisible(true) end
            elseif playerName and currentInfo.state == 2 and currentInfo.rented and currentInfo.owner == playerName then
                -- Own house, can move out or transfer
                panel.rental.imageOwnHouseRental:setVisible(true)
                if panel.rental.moveButton then panel.rental.moveButton:setVisible(true) end
                if panel.rental.transferButton then panel.rental.transferButton:setVisible(true) end
            elseif currentInfo.state == 3 then
                -- Transfer pending
                if panel.rental.pendingImage then
                    panel.rental.pendingImage:setVisible(true)
                    if panel.rental.pendingImage.newOwnerValue then
                        panel.rental.pendingImage.newOwnerValue:setText(currentInfo.targetPlayer or "")
                    end
                    if panel.rental.pendingImage.dateValue then
                        panel.rental.pendingImage.dateValue:setText(Cyclopedia.House.formatDate(currentInfo.scheduleTime))
                    end
                    if panel.rental.pendingImage.priceValue then
                        panel.rental.pendingImage.priceValue:setText(comma_value(currentInfo.transferValue))
                    end
                end

                if playerName and currentInfo.owner == playerName then
                    -- Owner can cancel transfer
                    if panel.rental.cancelTransferButton then
                        panel.rental.cancelTransferButton:setVisible(true)
                        panel.rental.cancelTransferButton:setOn(true)
                        panel.rental.cancelTransferButton:setTooltip("")
                        if currentInfo.ownerError and currentInfo.ownerError > 0 then
                            panel.rental.cancelTransferButton:setOn(false)
                            panel.rental.cancelTransferButton:setTooltip(bidButtonError[currentInfo.ownerError] or
                                "Error")
                        end
                    end
                elseif playerName and currentInfo.targetPlayer == playerName then
                    -- Target can accept/reject transfer
                    if currentInfo.canBidError and currentInfo.canBidError > 0 then
                        if panel.rental.acceptTransferButton then
                            panel.rental.acceptTransferButton:setOn(false)
                            panel.rental.acceptTransferButton:setTooltip(bidButtonError[currentInfo.canBidError] or
                                "Error")
                        end
                        if panel.rental.rejectTransferButton then
                            panel.rental.rejectTransferButton:setOn(false)
                            panel.rental.rejectTransferButton:setTooltip(bidButtonError[currentInfo.canBidError] or
                                "Error")
                        end
                    else
                        if panel.rental.acceptTransferButton then
                            panel.rental.acceptTransferButton:setOn(true)
                            panel.rental.acceptTransferButton:setTooltip("")
                        end
                        if panel.rental.rejectTransferButton then
                            panel.rental.rejectTransferButton:setOn(true)
                            panel.rental.rejectTransferButton:setTooltip("")
                        end
                    end

                    if panel.rental.acceptTransferButton then panel.rental.acceptTransferButton:setVisible(true) end
                    if panel.rental.rejectTransferButton then panel.rental.rejectTransferButton:setVisible(true) end
                end
            end
        end
    end

    Cyclopedia.House.lastSelectedHouse = widget
end

-- Setup minimap to show house location
function Cyclopedia.House.setupMinimap(houseId)
    if not UI or not UI.mapViewBackground then
        return
    end

    local minimapContainer = UI.mapViewBackground.minimapContainer
    if not minimapContainer then
        return
    end

    local minimap = minimapContainer.minimap
    local noSelectedBackground = minimapContainer.noSelectedBackground

    if not minimap then
        return
    end

    if houseId == 0 or not houseId then
        -- No house selected, show black background with label
        minimap:setVisible(false)
        if noSelectedBackground then
            noSelectedBackground:setVisible(true)
            if noSelectedBackground.noSelected then
                noSelectedBackground.noSelected:setText(tr("No house selected"))
            end
        end
        return
    end

    -- Get house static data for position
    local houseData = g_things.getHouseById(houseId)
    if not houseData or not houseData.position then
        minimap:setVisible(false)
        if noSelectedBackground then
            noSelectedBackground:setVisible(true)
            if noSelectedBackground.noSelected then
                noSelectedBackground.noSelected:setText(tr("House location not available"))
            end
        end
        return
    end

    -- Hide black background, show minimap
    if noSelectedBackground then
        noSelectedBackground:setVisible(false)
    end
    minimap:setVisible(true)

    -- Set minimap camera to house position
    local pos = houseData.position
    minimap:setCameraPosition(pos)
    minimap:setZoom(2) -- Zoom level for good visibility
end

-- Reset panel data
function Cyclopedia.House.resetData()
    if not UI or not UI.mapViewBackground then
        return
    end

    local panel = UI.mapViewBackground:recursiveGetChildById("panelTextsRents")
    if not panel then return end

    if panel.bidButton then panel.bidButton:setVisible(false) end
    if panel.noBidHouseHeader then panel.noBidHouseHeader:setVisible(false) end
    if panel.noBidHouseText then panel.noBidHouseText:setVisible(false) end
    if panel.rental then panel.rental:setVisible(false) end
    if panel.bidInfo then panel.bidInfo:setVisible(false) end
    if panel.rental and panel.rental.moveButton then panel.rental.moveButton:setVisible(false) end
    if panel.rental and panel.rental.transferButton then panel.rental.transferButton:setVisible(false) end
    if panel.rental and panel.rental.moveImage then panel.rental.moveImage:setVisible(false) end
    if panel.rental and panel.rental.keepButton then panel.rental.keepButton:setVisible(false) end
    if panel.rental and panel.rental.acceptTransferButton then panel.rental.acceptTransferButton:setVisible(false) end
    if panel.rental and panel.rental.rejectTransferButton then panel.rental.rejectTransferButton:setVisible(false) end
    if panel.rental and panel.rental.cancelTransferButton then panel.rental.cancelTransferButton:setVisible(false) end
    if panel.rental and panel.rental.pendingImage then panel.rental.pendingImage:setVisible(false) end
end

-- State sort
function Cyclopedia.House.onStateSort(widget, text, index)
    currentStateSort = index or 1
    Cyclopedia.House.onRecvHousesData(houseList)
end

-- Status sort
function Cyclopedia.House.onStatusSort(widget, text, index)
    currentStatusSort = index or 1
    Cyclopedia.House.onRecvHousesData(houseList)
end

-- Sort data by status
function Cyclopedia.House.sortDataByStatus(houses)
    local staticHouseList = g_things.getHouseList()

    -- Build lookup table for O(1) access
    local staticById = {}
    for _, h in ipairs(staticHouseList) do
        staticById[h.id] = h
    end

    table.sort(houses, function(a, b)
        local a_static = staticById[a.houseId]
        local b_static = staticById[b.houseId]

        if not a_static and not b_static then
            return false
        elseif not a_static then
            return false
        elseif not b_static then
            return true
        end

        if currentStatusSort == 1 then
            return a_static.name < b_static.name
        elseif currentStatusSort == 2 then
            return a_static.sqms < b_static.sqms
        elseif currentStatusSort == 3 then
            return a_static.rent < b_static.rent
        elseif currentStatusSort == 4 then
            return (a.highestBid or 0) > (b.highestBid or 0)
        elseif currentStatusSort == 5 then
            return (a.bidEnd or 0) > (b.bidEnd or 0)
        end
        return false
    end)

    return houses
end

-- Toggle house/guildhall filter
function Cyclopedia.House.toggleHouseChecked(guildHall)
    UI.checkboxBackground.checkHouses:setChecked(not guildHall)
    UI.checkboxBackground.checkGuildhalls:setChecked(guildHall)
    showGuildHalls = guildHall
    Cyclopedia.House.onRecvHousesData(houseList)
end

-- Format date
function Cyclopedia.House.formatDate(timestamp)
    if not timestamp or timestamp == 0 then
        return "N/A"
    end
    local t = os.date("*t", timestamp)
    local months = { "Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec" }
    local hour = string.format("%02d", t.hour)
    local min = string.format("%02d", t.min)
    return months[t.month] .. " " .. t.day .. ", " .. hour .. ":" .. min .. " SA"
end

-- Helper function for comma formatting
function comma_value(n)
    if not n then return "0" end
    local left, num, right = string.match(n, '^([^%d]*%d)(%d*)(.-)$')
    if not left then return tostring(n) end
    return left .. (num:reverse():gsub('(%d%d%d)', '%1,'):reverse()) .. right
end

-- Open bid window
function Cyclopedia.House.onBidButton(button)
    if not lastSelectedHouse or (button and not button:isEnabled()) then
        return
    end

    local selectHouseId = lastSelectedHouse:getActionId()
    local dataList = currentHouseList[selectHouseId]
    if not dataList then
        return
    end

    local static = dataList.staticData
    local currentInfo = dataList.mainData
    if not static or not currentInfo then
        return
    end

    local bidWindow = UI.bidHouseWindow
    if not bidWindow then
        return
    end

    -- Set house information
    bidWindow.limitBox:setText("0")
    bidWindow.nameValue:setText(static.name or "")
    bidWindow.sizeValue:setText((static.sqms or 0) .. " sqm")
    bidWindow.bedsValue:setText(static.beds or 0)
    bidWindow.rentValue:setText(math.floor((static.rent or 0) / 1000) .. " k")

    -- Set auction information
    if not currentInfo.bidderName or #currentInfo.bidderName == 0 then
        -- No bid yet
        bidWindow.currentAuction:setVisible(false)
        bidWindow.thereFar:setVisible(true)
    else
        -- Has existing bid
        bidWindow.thereFar:setVisible(false)
        bidWindow.currentAuction:setVisible(true)
        bidWindow.currentAuction.highestBidder:setText(currentInfo.bidderName)
        bidWindow.currentAuction.endTime:setText(Cyclopedia.House.formatDate(currentInfo.bidEnd))
        bidWindow.currentAuction.highestBid:setText(comma_value(currentInfo.highestBid))

        -- Show player's own bid limit if they are the current bidder
        if currentInfo.bidOwner then
            bidWindow.currentAuction.yourLimitLabel:setVisible(true)
            bidWindow.currentAuction.yourLimitValue:setVisible(true)
            bidWindow.currentAuction.yourLimitValue:setText(comma_value(currentInfo.holderLimit))
            bidWindow.currentAuction.yourLimitGold:setVisible(true)
            bidWindow.limitBox:setText(tostring(currentInfo.holderLimit or 0))
        else
            bidWindow.currentAuction.yourLimitLabel:setVisible(false)
            bidWindow.currentAuction.yourLimitValue:setVisible(false)
            bidWindow.currentAuction.yourLimitGold:setVisible(false)
        end
    end

    -- Reset validation icons
    bidWindow.infoRed:setVisible(false)
    bidWindow.infoRed:setTooltip("")
    bidWindow.infoOrange:setVisible(false)
    bidWindow.infoOrange:setTooltip("")
    bidWindow.confirmBid:setEnabled(true)
    bidWindow.confirmBid:setTooltip("")

    -- Show bid window, hide house list
    UI.bidHouseWindow:setVisible(true)
    UI.selectedBackground:setVisible(false)
end

-- Cancel bid window
function Cyclopedia.House.onCancelBidWindow()
    if UI.bidHouseWindow then
        UI.bidHouseWindow:setVisible(false)
    end
    if UI.selectedBackground then
        UI.selectedBackground:setVisible(true)
    end
end

-- Validate bid input
function Cyclopedia.House.onBidChangeValue(widget)
    local currentText = widget:getText()
    if #currentText == 0 then
        return
    end

    -- Remove non-numeric characters
    currentText = currentText:gsub("[^%d]", "")
    widget:setText(currentText)

    -- Limit to 11 digits
    if #currentText > 11 then
        currentText = currentText:sub(1, 11)
        widget:setText(currentText)
    end

    local numericValue = tonumber(currentText) or 0
    if numericValue >= 99999999999 then
        currentText = "99999999999"
        widget:setText(currentText)
        numericValue = 99999999999
    end

    if not lastSelectedHouse then
        return
    end

    local selectHouseId = lastSelectedHouse:getActionId()
    local dataList = currentHouseList[selectHouseId]
    if not dataList then
        return
    end

    local static = dataList.staticData
    local currentInfo = dataList.mainData
    if not static or not currentInfo then
        return
    end

    local bidWindow = UI.bidHouseWindow
    local player = g_game.getLocalPlayer()
    local bankMoney = player and player:getResourceBalance(ResourceTypes.BANK_BALANCE) or 0

    -- Reset validation state
    bidWindow.infoRed:setVisible(false)
    bidWindow.infoRed:setTooltip("")
    bidWindow.infoOrange:setVisible(false)
    bidWindow.infoOrange:setTooltip("")
    bidWindow.limitBox:setColor("#c0c0c0")
    bidWindow.confirmBid:setEnabled(true)
    bidWindow.confirmBid:setTooltip("")

    -- Check if bid is lower than current highest
    if numericValue < (currentInfo.highestBid or 0) then
        bidWindow.infoOrange:setVisible(true)
        bidWindow.infoOrange:setTooltip("Your bid limit must be higher than the current highest bid.")
    end

    -- Check if player has enough money (bid + rent)
    local rent = static.rent or 0
    if numericValue + rent > bankMoney then
        bidWindow.infoRed:setVisible(true)
        bidWindow.infoRed:setTooltip("Your account balance is too low to pay the bid and the rent for the\nfirst month.")
        bidWindow.limitBox:setColor("#d33c3c")
        bidWindow.confirmBid:setEnabled(false)
        bidWindow.confirmBid:setTooltip("You need to fill in the form correctly")
    end
end

-- Place bid
function Cyclopedia.House.onPlaceBid(button)
    if button and not button:isEnabled() then
        return
    end

    if not lastSelectedHouse then
        return
    end

    local selectHouseId = lastSelectedHouse:getActionId()
    local dataList = currentHouseList[selectHouseId]
    if not dataList then
        return
    end

    local static = dataList.staticData
    local currentInfo = dataList.mainData
    if not static or not currentInfo then
        return
    end

    local limit = tonumber(UI.bidHouseWindow.limitBox:getText()) or 0

    -- Hide cyclopedia and show confirmation dialog
    if controllerCyclopedia and controllerCyclopedia.ui then
        controllerCyclopedia.ui:hide()
    end

    local rentK = math.floor((static.rent or 0) / 1000) .. " k"
    local houseName = static.name or "House"

    local yesFunction = function()
        -- Send bid to server (type 1 = bid)
        g_game.sendCyclopediaHouseAuction(1, selectHouseId, 0, limit, "")
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
        if placeBidWindow then
            placeBidWindow:destroy()
            placeBidWindow = nil
        end
    end

    local noFunction = function()
        if controllerCyclopedia and controllerCyclopedia.ui then
            controllerCyclopedia.ui:show()
        end
        if placeBidWindow then
            placeBidWindow:destroy()
            placeBidWindow = nil
        end
    end

    local message = tr(
        "Do you really want to bid on the house '%s'?\n\nYou have set your bid limit to %s.\nWhen the auction ends, the winning bid plus the rent of %s for the first month will be debited from your\nbank account.",
        houseName, comma_value(limit), rentK)

    placeBidWindow = displayGeneralBox(tr('Confirm House Action'), message,
        { { text = tr('Yes'), callback = yesFunction }, { text = tr('No'), callback = noFunction } },
        yesFunction, noFunction)
end

-- Connect protocol events to our handlers
connect(g_game, {
    onCyclopediaHouseList = Cyclopedia.House.onRecvHousesData,
    onCyclopediaHouseAuctionMessage = Cyclopedia.House.onRecvHouseMessage
})
