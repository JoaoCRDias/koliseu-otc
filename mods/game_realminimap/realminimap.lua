minimapWidget = nil
minimapButton = nil
minimapWindow = nil
fullmapView = false
loaded = false
oldZoom = nil
oldPos = nil

local flagToFilePath = {
  ["up"] = "data/images/game/minimap/flag18.png",
  ["flag"] = "data/images/game/minimap/flag9.png",
  ["skull"] = "data/images/game/minimap/flag12.png",
  ["crossmark"] = "data/images/game/minimap/flag4.png",
  ["star"] = "data/images/game/minimap/flag3.png",
  ["sword"] = "data/images/game/minimap/flag8.png",
  ["red up"] = "data/images/game/minimap/flag14.png",
  ["?"] = "data/images/game/minimap/flag1.png",
  ["checkmark"] = "data/images/game/minimap/flag0.png",
  ["red left"] = "data/images/game/minimap/flag17.png",
  ["red right"] = "data/images/game/minimap/flag16.png",
  ["!"] = "data/images/game/minimap/flag2.png",
  ["down"] = "data/images/game/minimap/flag19.png",
  ["mouth"] = "data/images/game/minimap/flag6.png",
  ["lock"] = "data/images/game/minimap/flag10.png",
  ["red down"] = "data/images/game/minimap/flag15.png",
  ["bag"] = "data/images/game/minimap/flag11.png",
  ["cross"] = "data/images/game/minimap/flag5.png",
  ["spear"] = "data/images/game/minimap/flag7.png",
  ["$"] = "data/images/game/minimap/flag13.png",
}

function init()
  minimapWindow = g_ui.displayUI('realminimap')

  minimapWidget = minimapWindow:recursiveGetChildById('realMinimap')
  if not g_realMinimap then
    g_realMinimap = minimapWidget
  end

  connect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  connect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  if g_game.isOnline() then
    online()
  end
end

function terminate()
  disconnect(g_game, {
    onGameStart = online,
    onGameEnd = offline,
  })

  disconnect(LocalPlayer, {
    onPositionChange = updateCameraPosition
  })

  minimapWindow:destroy()
  if minimapButton then
    minimapButton:destroy()
  end
end

function toggle()
  if not minimapButton then return end

  if minimapButton:isOn() then
    minimapWindow:hide()
    minimapButton:setOn(false)
  else
    minimapWindow:show()
    minimapButton:setOn(true)
  end
end

function onClose()
  if minimapButton then
    minimapButton:setOn(false)
  end
  minimapWindow:hide()
end

function online()
  local benchmark = g_clock.millis()
  loadMap()
  updateCameraPosition()
  print("Real Minimap loaded in " .. (g_clock.millis() - benchmark) / 1000 .. " seconds.")
end

function offline()
end

function updateCameraPosition()
  local pos = minimapWidget:getCameraPosition()
end

function loadMap()
  print("Loading real minimap map data!")

  local isSatellite = false
  for i = 1, 2 do
    if i == 2 then
      isSatellite = true
    end

    local dirPath = '/data/minimap' .. (isSatellite and '/satellite' or '')
    local files = g_resources.listDirectoryFiles(dirPath)
    if not files then goto continue_dir end

    local fileAmount = #files
    for index, filePath in pairs(files) do
      if g_resources.isFileType(filePath, 'png') then
        local barSeparated = filePath:split('/')
        local fileName = barSeparated[#barSeparated]
        local regex = regexMatch(fileName, string.format([[%s-([0-9]+)-([0-9]+)-([0-9]+)-([0-9]+)-([0-9a-zA-Z]+)\.bmp\.lzma\.png]], (isSatellite and 'satellite' or 'minimap')))

        local firstMatch = regex and regex[1]
        if firstMatch then
          local refSize = tonumber(firstMatch[2])
          local tilesPerPixel = refSize / 32
          local posX = tonumber(firstMatch[3])
          local posY = tonumber(firstMatch[4])
          local posZ = tonumber(firstMatch[5])

          posX = posX * 32
          posY = posY * 32

          local fromScale = 0
          local toScale = 100

          if tilesPerPixel == 2 then
            fromScale = 0
            toScale = 1
          elseif tilesPerPixel == 1 then
            fromScale = 1
            toScale = 100
          elseif tilesPerPixel == 0.5 then
            fromScale = 2
            toScale = 100
          end

          local fullPath = dirPath .. '/' .. filePath
          if g_realMinimap and g_realMinimap.loadImage and type(g_realMinimap.loadImage) == 'function' then
            g_realMinimap.loadImage(fullPath, isSatellite and "satellite" or "fullMinimap", {x = posX, y = posY, z = posZ}, tilesPerPixel, fromScale, toScale)
          else
            g_minimap.loadImage(fullPath, {x = posX, y = posY, z = posZ}, tilesPerPixel)
          end

          print(string.format("[%d/%d] loading map sector: %d %d %d, tilesPerPixel = %f", index, fileAmount, posX, posY, posZ, tilesPerPixel))
        end
      end
    end

    ::continue_dir::
  end

  if regions then
    for _, region in pairs(regions) do
      if g_realMinimap and g_realMinimap.loadRegion then
        local imageId = g_realMinimap:loadRegion(region.image, region.fromPos, 1, 0, 64, region.markedColor)

        minimapWidget:addCustomMouseEvent(MouseLeftButton, region.fromPos, region.toPos, function(self, mapPos, mousePos)
          if not self:hasClickedRegion(imageId, mapPos) then
            return false
          end

          if minimapWidget.selectedRegion then
            if minimapWidget.selectedRegion.id == imageId then
              g_realMinimap:disableRegion(minimapWidget.selectedRegion.id)
              minimapWidget.selectedRegion = nil
              return true
            end

            g_realMinimap:disableRegion(minimapWidget.selectedRegion.id)
            minimapWidget.selectedRegion = nil
          end

          minimapWidget.selectedRegion = {region = region, id = imageId}
          g_realMinimap:enableRegion(imageId)
          return true
        end, true)
      end
    end
  end

  minimapWidget:setCameraPosition({x = 31000, y = 31000, z = 7})

  minimapWidget.view = "fullMinimap"
  minimapWidget:setCurrentView("fullMinimap")

  minimapWidget.onFloorChange = function(self, newPos, oldPos)
    if newPos.z > 7 then
      minimapWidget:setCurrentView("minimap")
      minimapWidget:setBackgroundColor("#000000ff")
    else
      minimapWidget:setCurrentView(minimapWidget.view)
      minimapWidget:setBackgroundColor("#336699ff")
    end
  end
end
