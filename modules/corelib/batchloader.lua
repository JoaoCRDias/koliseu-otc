--[[
    BatchLoader - Reusable batch widget creation for scroll lists.

    Prevents UI freezes by creating widgets in small batches via scheduleEvent,
    instead of creating all widgets at once in a single frame.

    Automatically cancels any previous loader on the same container,
    so callers don't need to track loader instances manually.

    Usage:
        BatchLoader.create({
            container = myScrollList,
            items = sortedItems,
            batchSize = 10,         -- optional, default 10
            delayMs = 10,           -- optional, default 10
            createWidget = function(item, index)
                local row = g_ui.createWidget('MyRow', myScrollList)
                row:setText(item.name)
            end,
            onFinish = function()   -- optional
                -- called when all items are created
            end
        })

        -- To cancel all loaders (e.g. on window close):
        BatchLoader.cancel(myScrollList)
]]

BatchLoader = {}
BatchLoader.__index = BatchLoader

-- Active loaders indexed by container widget
local activeLoaders = {}

function BatchLoader.create(opts)
    local container = opts.container

    -- Auto-cancel previous loader on same container
    if container and activeLoaders[container] then
        activeLoaders[container]:_cancel()
    end

    local self = setmetatable({}, BatchLoader)
    self.container = container
    self.items = opts.items or {}
    self.batchSize = opts.batchSize or 10
    self.delayMs = opts.delayMs or 10
    self.createWidget = opts.createWidget
    self.onFinish = opts.onFinish
    self._event = nil
    self._cancelled = false

    if container then
        activeLoaders[container] = self
    end

    self:_loadBatch(1)
    return self
end

function BatchLoader:_loadBatch(startIndex)
    if self._cancelled then return end
    if not self.container then return end

    local endIndex = math.min(startIndex + self.batchSize - 1, #self.items)
    for i = startIndex, endIndex do
        if self._cancelled then return end
        self.createWidget(self.items[i], i)
    end

    if endIndex < #self.items then
        self._event = scheduleEvent(function()
            self._event = nil
            self:_loadBatch(endIndex + 1)
        end, self.delayMs)
    else
        self:_cleanup()
        if self.onFinish then
            self.onFinish()
        end
    end
end

function BatchLoader:_cancel()
    self._cancelled = true
    if self._event then
        removeEvent(self._event)
        self._event = nil
    end
    self:_cleanup()
end

function BatchLoader:_cleanup()
    if self.container and activeLoaders[self.container] == self then
        activeLoaders[self.container] = nil
    end
end

-- Static method: cancel the active loader for a given container
function BatchLoader.cancel(container)
    if container and activeLoaders[container] then
        activeLoaders[container]:_cancel()
    end
end
