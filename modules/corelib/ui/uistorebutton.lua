UIStoreButton = extends(UIButton, 'UIStoreButton')

function UIStoreButton.create()
    local button = UIStoreButton.internalCreate()
    return button
end

function UIStoreButton:onStyleApply(styleName, styleNode)
    for name, value in pairs(styleNode) do
        if name == 'buttoncolor' then
            self.hasButtonColors = true
            addEvent(function() self:setButtonColor(value) end)
        end
    end
end

function UIStoreButton:setButtonColor(value)
    if not self.hasButtonColors then return end
    if value == 'yellow' then
        self:setImageSource('/images/store/button_yellow')
    elseif value == 'green' then
        self:setImageSource('/images/store/button_green')
    elseif value == 'red' then
        self:setImageSource('/images/store/button_red')
    else
        self:setImageSource('/images/store/button_blue')
    end
end
