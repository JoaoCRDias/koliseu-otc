DailyReward = {}
DailyReward.__index = DailyReward

DailyReward.freeRewards = {}
DailyReward.premiumRewards = {}
DailyReward.descriptions = {}

local rewardFreeBase = "Rewards for Free Account: %s"
local rewardPremiumBase = "Rewards for Premium Account: %s"
local potionList = "\nPick %d item from the list. Among \nother items it contains: %s"
local preyText = "<li>%dx Prey Wildcard</li>"
local boostText = "<li>%d minutes 50%% XP Boost</li>"

local function makeDailyRewardText(dailyReward)
    local text = ''
    if dailyReward.redeemMode == 1 then
        local ss = ''
        for i, items in pairs(dailyReward.selectableItems) do
            if ss == '' then
                ss = '\n' .. items.name
            elseif i < 3 then
                ss = ss .. ', ' .. (i % 2 == 0 and '\n' or '') .. items.name
            else
                ss = ss .. '...'
                break
            end
        end
        local amount = dailyReward.itemsToSelect or -1
        return string.format(potionList, amount, ss)
    else
        local bonusType = dailyReward.bundleItems[1] or {}
        if bonusType.name == "Prey Wildcards" then
            return string.format(preyText, bonusType.count)
        elseif bonusType.name == "XP Boost" then
            return string.format(boostText, bonusType.itemId)
        end
    end
    return text
end

function DailyReward:onDailyReward(freeRewards, premiumRewards, descriptions)
    DailyReward.freeRewards = freeRewards
    DailyReward.premiumRewards = premiumRewards
    DailyReward.descriptions = descriptions
    DailyReward:configureRewardDescriptions()
end

function DailyReward:configureRewardDescriptions()
    -- Check if rewards data has been received
    if not DailyReward.freeRewards or #DailyReward.freeRewards == 0 then
        return
    end

    for i = 0, 6 do
        local widget = dailyRewardWindow.miniWindowDailyReward.dailyReward:recursiveGetChildById("dailyButton_" .. i)
        if widget then
            widget.freeRewards = DailyReward.freeRewards[i + 1]
            widget.premiumRewards = DailyReward.premiumRewards[i + 1]

            -- Only configure if rewards exist for this day
            if widget.freeRewards then
                if widget.freeRewards.redeemMode == 1 then
                    widget:setIcon("/images/game/dailyreward/icon-reward-pickitems")
                else
                    local bonusType = widget.freeRewards.bundleItems[1] or {}
                    if bonusType.name == "Prey Wildcards" then
                        widget:setIcon("/images/game/dailyreward/icon-reward-fixeditems")
                    elseif bonusType.name == "XP Boost" then
                        widget:setIcon("/images/game/dailyreward/icon-reward-xpboost")
                    end
                end

                widget.onHoverChange =
                    function(selfWidget, hovered)
                        dailyRewardWindow.Description.tooltipTodo:setText("")
                        dailyRewardWindow.Description.freeDesc.freeDescLabel:setText("")
                        dailyRewardWindow.Description.freeDesc.freeDescLabel:setFormatedText("")
                        dailyRewardWindow.Description.premDesc.premiumDescLabel:setText("")
                        dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText("")
                        if hovered and selfWidget.freeRewards then
                            dailyRewardWindow.Description.freeDesc.freeDescLabel:setFormatedText(string.format(
                                rewardFreeBase, makeDailyRewardText(selfWidget.freeRewards)))
                            dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText(string.format(
                                rewardPremiumBase, makeDailyRewardText(selfWidget.premiumRewards)))
                        end
                    end
            end
        end
    end

    for i = 0, 5 do
        local widget = dailyRewardWindow.miniWindowBonuses.preyBonus:recursiveGetChildById("bonusStreak_" .. i)
        if widget then
            widget.textTooltip = DailyReward.descriptions[i + 1]
            widget.onHoverChange =
                function(selfWidget, hovered)
                    dailyRewardWindow.Description.tooltipTodo:setText("")
                    dailyRewardWindow.Description.freeDesc.freeDescLabel:setText("")
                    dailyRewardWindow.Description.premDesc.premiumDescLabel:setText("")
                    dailyRewardWindow.Description.premDesc.premiumDescLabel:setFormatedText("")
                    if hovered then
                        dailyRewardWindow.Description.tooltipTodo:setText(selfWidget.textTooltip)
                    end
                end
        end
    end
end

function DailyReward:onOpenRewardWall(fromShrine, nextRewardTime, currentIndex, message, jokerToken, serverSave,
                                      dayStreakLevel)
end
