if not MapFinder then
    MapFinder = {
        widget = nil,
        localRouteWidgets = {},
        localWaypointWidgets = {}
    }
    MapFinder.__index = MapFinder
end

local self = MapFinder

function MapFinder.init()
end

function MapFinder:ensureWidget()
    if self.widget then return true end
    if not HuntFinder.widget then return false end
    self.widget = HuntFinder.widget:recursiveGetChildById('minimap')
    if not self.widget then return false end

    self.widget:load()
    self.widget:setZoom(2)
    self.widget.onFloorChange = function(widget, newPos, oldPos)
        self:onFloorChange(widget, newPos, oldPos)
    end
    return true
end

function MapFinder:clear()
    self:clearLocalRoute()
    if self.widget then
        self.widget:destroyChildren()
    end
    self.widget = nil
end

function MapFinder:onFloorChange(widget, newPos, oldPos)
    if not self.widget then return end
end

function MapFinder:setHuntPosition(position)
    if not self:ensureWidget() then return end
    if not position or (position.x == 0 and position.y == 0 and position.z == 0) then
        return
    end
    self.widget:setCameraPosition(position)
    if self.widget.setCrossPosition then
        self.widget:setCrossPosition(position)
    end
end

function MapFinder:setPath(coordinates)
    if modules.game_minimap then
        modules.game_minimap.setPath(coordinates)
    end
end

local function applyDirection(pos, dir)
    local newPos = {x = pos.x, y = pos.y, z = pos.z}
    if dir == 0 then newPos.y = newPos.y - 1
    elseif dir == 1 then newPos.x = newPos.x + 1
    elseif dir == 2 then newPos.y = newPos.y + 1
    elseif dir == 3 then newPos.x = newPos.x - 1
    elseif dir == 4 then newPos.x = newPos.x + 1; newPos.y = newPos.y - 1
    elseif dir == 5 then newPos.x = newPos.x + 1; newPos.y = newPos.y + 1
    elseif dir == 6 then newPos.x = newPos.x - 1; newPos.y = newPos.y + 1
    elseif dir == 7 then newPos.x = newPos.x - 1; newPos.y = newPos.y - 1
    end
    return newPos
end

local function flattenRouteCoordinates(routeCoords)
    local waypoints = {}

    if routeCoords[1] and routeCoords[1].x then
        return routeCoords
    end

    local floors = {}
    for floorKey, _ in pairs(routeCoords) do
        table.insert(floors, floorKey)
    end
    table.sort(floors)

    for _, floorKey in ipairs(floors) do
        local segments = routeCoords[floorKey]
        if type(segments) == "table" then
            for _, segment in ipairs(segments) do
                if type(segment) == "table" then
                    for _, waypoint in ipairs(segment) do
                        if waypoint.x then
                            table.insert(waypoints, {x = waypoint.x, y = waypoint.y, z = waypoint.z})
                        end
                    end
                end
            end
        end
    end

    return waypoints
end

function MapFinder:clearLocalRoute()
    for _, w in ipairs(self.localRouteWidgets) do
        if w and w.destroy then w:destroy() end
    end
    self.localRouteWidgets = {}

    for _, w in ipairs(self.localWaypointWidgets) do
        if w and w.destroy then w:destroy() end
    end
    self.localWaypointWidgets = {}
end

function MapFinder:drawLocalRoute(points)
    if not self.widget or not points then return end

    local cameraZ = nil
    local camPos = self.widget:getCameraPosition()
    if camPos then cameraZ = camPos.z end

    for _, pos in ipairs(points) do
        if pos.x and pos.y and pos.z then
            if not cameraZ or pos.z == cameraZ then
                local dot = g_ui.createWidget('UIWidget', self.widget)
                dot:setSize({width = 3, height = 3})
                dot:setBackgroundColor("#FFFF00")
                dot:setPhantom(true)
                self.widget:centerInPosition(dot, pos)
                table.insert(self.localRouteWidgets, dot)
            end
        end
    end
end

function MapFinder:drawLocalWaypoints(waypoints)
    if not self.widget or not waypoints then return end

    for _, pos in ipairs(waypoints) do
        if pos.x and pos.y and pos.z then
            local wp = g_ui.createWidget('UIWidget', self.widget)
            wp:setSize({width = 11, height = 11})
            wp:setIcon('/images/game/minimap/waypoint')
            wp:setPhantom(true)
            self.widget:centerInPosition(wp, pos)
            table.insert(self.localWaypointWidgets, wp)
        end
    end
end

function MapFinder:setLocalRoutePath(routeCoords)
    if not self:ensureWidget() then return end

    self:clearLocalRoute()

    if not routeCoords then return end

    local waypoints = flattenRouteCoordinates(routeCoords)
    if #waypoints == 0 then return end

    self:drawLocalWaypoints(waypoints)

    local cameraPos = self.widget:getCameraPosition()
    if cameraPos and #waypoints >= 2 then
        local success, expanded = pcall(function()
            return self:expandRouteWithPathfinding(waypoints)
        end)
        if success and expanded and #expanded > 0 then
            self:drawLocalRoute(expanded)
        else
            self:drawLocalRoute(waypoints)
        end
    end
end

function MapFinder:expandRouteWithPathfinding(waypoints)
    if not waypoints or #waypoints < 2 then
        return waypoints or {}
    end

    local expandedPath = {}
    local pointSampleRate = 3

    for i = 1, #waypoints - 1 do
        local startPos = waypoints[i]
        local endPos = waypoints[i + 1]

        if not startPos or not startPos.x or not endPos or not endPos.x then
            goto continue
        end

        table.insert(expandedPath, {x = startPos.x, y = startPos.y, z = startPos.z})

        if startPos.z ~= endPos.z then
            goto continue
        end

        local success, path = pcall(function()
            return g_map.findPath(startPos, endPos, 10000, 0)
        end)

        if success and path and #path > 0 then
            local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
            local stepCount = 0

            for _, dir in ipairs(path) do
                currentPos = applyDirection(currentPos, dir)
                stepCount = stepCount + 1

                if stepCount % pointSampleRate == 0 then
                    table.insert(expandedPath, {x = currentPos.x, y = currentPos.y, z = currentPos.z})
                end
            end
        end

        ::continue::
    end

    local lastWaypoint = waypoints[#waypoints]
    if lastWaypoint and lastWaypoint.x then
        table.insert(expandedPath, {x = lastWaypoint.x, y = lastWaypoint.y, z = lastWaypoint.z})
    end

    return expandedPath
end

function MapFinder:setRoutePath(routePath)
    if modules.game_minimap then
        if routePath and table.size(routePath) > 0 then
            local waypoints = flattenRouteCoordinates(routePath)

            if #waypoints == 0 then return end

            if #waypoints == 1 then
                local player = g_game.getLocalPlayer()
                if player then
                    local playerPos = player:getPosition()
                    table.insert(waypoints, 1, {x = playerPos.x, y = playerPos.y, z = playerPos.z})
                end
            end

            local success, expandedRoute = pcall(function()
                return self:expandRouteWithPathfinding(waypoints)
            end)

            if success and expandedRoute then
                modules.game_minimap.setRoutePath(expandedRoute)
            else
                modules.game_minimap.setRoutePath(waypoints)
            end
            return
        end

        local player = g_game.getLocalPlayer()
        if not player then return end

        local startPos = player:getPosition()
        local endPos = self.huntPosition

        if startPos and endPos and endPos.x ~= 0 then
            local path = g_map.findPath(startPos, endPos, 50000, 0)
            if path and #path > 0 then
                local points = {}
                local currentPos = {x = startPos.x, y = startPos.y, z = startPos.z}
                table.insert(points, {x = currentPos.x, y = currentPos.y, z = currentPos.z})

                for _, dir in ipairs(path) do
                    currentPos = applyDirection(currentPos, dir)
                    table.insert(points, {x = currentPos.x, y = currentPos.y, z = currentPos.z})
                end

                modules.game_minimap.setRoutePath(points)
            end
        end
    end
end
