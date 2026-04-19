if not MapFinder then
    MapFinder = {
        widget = nil
    }
    MapFinder.__index = MapFinder
end

local self = MapFinder

function MapFinder.init()
    local ok, err = pcall(function()
        self.widget = HuntFinder.widget:recursiveGetChildById('minimap')
        if not self.widget then
            g_logger.error("[HuntFinder] MapFinder init: minimap widget not found")
            return
        end

        if RealMap and RealMap.setRegion then
            pcall(function() RealMap.setRegion(self.widget) end)
        end

        if g_game.getLocalPlayer() and g_game.getLocalPlayer():getPosition() then
            self.widget:setCameraPosition(g_game.getLocalPlayer():getPosition())
            if self.widget.setCrossPosition then
                self.widget:setCrossPosition(g_game.getLocalPlayer():getPosition())
            end
        end
        self.widget:setZoom(2)

        self.widget.view = "minimap"
        self.widget:setBackgroundColor("#274DA6")
        self.widget.onFloorChange = function(widget, newPos, oldPos)
            self:onFloorChange(widget, newPos, oldPos)
        end
    end)
    if not ok then
        g_logger.error("[HuntFinder] MapFinder.init crashed: " .. tostring(err))
    end
end

function MapFinder:clear()
    if not self.widget then
        return
    end

    self.widget:destroyChildren()
    self.widget = nil
end

function MapFinder:onFloorChange(widget, newPos, oldPos)
    if not self.widget then return end
    if newPos.z > 7 then
        self.widget.view = "minimap"
        self.widget:setBackgroundColor("#000000ff")
    else
        self.widget.view = "minimap"
        self.widget:setBackgroundColor("#274DA6")
    end
end

function MapFinder:setHuntPosition(position)
    if not self.widget then return end
    if (position.x == 0 and position.y == 0 and position.z == 0) then
        return
    end
    self.widget:setCameraPosition(position)
    MapFinder:onFloorChange(self.widget, position, {x = 0, y = 0, z = 0})
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
        print("[HuntFinder] Coords already flat format")
        return routeCoords
    end

    local floors = {}
    for floorKey, _ in pairs(routeCoords) do
        table.insert(floors, floorKey)
    end
    table.sort(floors)

    print("[HuntFinder] Found " .. #floors .. " floors in route data")

    for _, floorKey in ipairs(floors) do
        local segments = routeCoords[floorKey]
        if type(segments) == "table" then
            for segIdx, segment in ipairs(segments) do
                if type(segment) == "table" then
                    for wpIdx, waypoint in ipairs(segment) do
                        if waypoint.x then
                            table.insert(waypoints, {x = waypoint.x, y = waypoint.y, z = waypoint.z})
                        end
                    end
                end
            end
        end
    end

    print("[HuntFinder] Flattened to " .. #waypoints .. " waypoints")
    return waypoints
end

function MapFinder:clearLocalPath()
    if self.widget and self.widget.clearPath then
        self.widget:clearPath()
    end
end

function MapFinder:addLocalPath(coordinates)
    if not self.widget then return end

    local function addPointsRecursive(tbl)
        for k, v in pairs(tbl) do
            if type(v) == 'table' then
                if v.x and v.y and v.z then
                    if self.widget.addPathPoint then
                        self.widget:addPathPoint(v)
                    end
                else
                    addPointsRecursive(v)
                end
            end
        end
    end

    addPointsRecursive(coordinates)
end

function MapFinder:addLocalWaypoints(waypoints)
    if not self.widget then return end
    for _, wp in ipairs(waypoints) do
        if wp.x and wp.y and wp.z then
            if self.widget.addWaypoint then
                self.widget:addWaypoint(wp)
            end
        end
    end
end

function MapFinder:setLocalRoutePath(routeCoords)
    if not self.widget then return end

    self:clearLocalPath()

    if not routeCoords then return end

    if routeCoords[1] and routeCoords[1].x then
        for _, wp in ipairs(routeCoords) do
            if self.widget.addWaypoint then self.widget:addWaypoint(wp) end
            if self.widget.addPathPoint then self.widget:addPathPoint(wp) end
        end
        return
    end

    for floorKey, floorSegments in pairs(routeCoords) do
        local floor = tonumber(floorKey)
        if floor and type(floorSegments) == "table" then
            if self.widget.makeWaypoints then self.widget:makeWaypoints(floorSegments, floor) end
            if self.widget.makeRouth then self.widget:makeRouth(floorSegments, floor) end
        end
    end
end

function MapFinder:expandRouteWithPathfinding(waypoints)
    if not waypoints or #waypoints < 2 then
        return waypoints or {}
    end

    local expandedPath = {}
    local pointSampleRate = 3

    print("[HuntFinder] Expanding route with " .. #waypoints .. " waypoints")

    for i = 1, #waypoints - 1 do
        local startPos = waypoints[i]
        local endPos = waypoints[i + 1]

        if not startPos or not startPos.x or not endPos or not endPos.x then
            print("[HuntFinder] Invalid waypoint at index " .. i)
            goto continue
        end

        table.insert(expandedPath, {x = startPos.x, y = startPos.y, z = startPos.z})

        if startPos.z ~= endPos.z then
            print("[HuntFinder] Floor transition at waypoint " .. i .. ": z=" .. startPos.z .. " -> z=" .. endPos.z)
            goto continue
        end

        local pathFound = false

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
            pathFound = true
            print("[HuntFinder] Pathfinding success: " .. #path .. " steps between waypoints " .. i .. " and " .. (i+1))
        end

        ::continue::
    end

    local lastWaypoint = waypoints[#waypoints]
    if lastWaypoint and lastWaypoint.x then
        table.insert(expandedPath, {x = lastWaypoint.x, y = lastWaypoint.y, z = lastWaypoint.z})
    end

    print("[HuntFinder] Expanded path has " .. #expandedPath .. " points")

    return expandedPath
end

function MapFinder:setRoutePath(routePath)
    print("[HuntFinder] setRoutePath called")
    if modules.game_minimap then
        if routePath and table.size(routePath) > 0 then
            local waypoints = flattenRouteCoordinates(routePath)

            print("[HuntFinder] After flatten: " .. #waypoints .. " waypoints")

            if #waypoints == 0 then
                print("[HuntFinder] No valid waypoints found after flattening")
                return
            end

            if #waypoints == 1 then
                local player = g_game.getLocalPlayer()
                if player then
                    local playerPos = player:getPosition()
                    print("[HuntFinder] Only 1 waypoint, adding player at: " .. playerPos.x .. "," .. playerPos.y .. "," .. playerPos.z)
                    table.insert(waypoints, 1, {x = playerPos.x, y = playerPos.y, z = playerPos.z})
                end
            end

            local success, expandedRoute = pcall(function()
                return self:expandRouteWithPathfinding(waypoints)
            end)

            if success and expandedRoute then
                print("[HuntFinder] Expansion success, points: " .. #expandedRoute)
                modules.game_minimap.setRoutePath(expandedRoute)
            else
                print("[HuntFinder] Expansion failed: " .. tostring(expandedRoute))
                modules.game_minimap.setRoutePath(waypoints)
            end
            return
        end

        local player = g_game.getLocalPlayer()
        if not player then return end

        local startPos = player:getPosition()
        local endPos = self.huntPosition

        if startPos and endPos and endPos.x ~= 0 then
            local path, result = g_map.findPath(startPos, endPos, 50000, 0)
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
