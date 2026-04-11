polopagWindow = nil
offersContent = nil
categoryTabBar = nil
selectedOffer = nil
polopagConfigLoading = false
pendingCategory = nil

-- Global variables (module scope)
-- Config is loaded remotely from Services.polopagConfig

local function applyRemoteConfig(payload)
  if not Services then
    Services = {}
  end

  local data = payload
  if type(payload) ~= "table" then
    return false
  end

  if type(payload.data) == "table" then
    data = payload.data
  elseif type(payload.result) == "table" then
    data = payload.result
  end

  local offers = data.offers or data.polopagOffers
  if type(offers) ~= "table" then
    return false
  end

  Services.polopagOffers = offers

  local apiUrl = data.apiUrl or data.polopag or data.api
  if type(apiUrl) == "string" and apiUrl ~= "" then
    Services.polopag = apiUrl
  end

  return true
end

local function requestRemoteConfig(category)
  if polopagConfigLoading then
    pendingCategory = category or pendingCategory
    return
  end

  if not Services or type(Services.polopagConfig) ~= "string" or Services.polopagConfig == "" then
    g_logger.error("[Polopag] Services.polopagConfig is empty. Configure endpoint in init.lua/config.ini.")
    return
  end

  polopagConfigLoading = true
  pendingCategory = category or pendingCategory

  HTTP.getJSON(Services.polopagConfig, function(response, err)
    polopagConfigLoading = false

    if err then
      g_logger.error("[Polopag] Failed to load remote config: " .. tostring(err))
      return
    end

    if not response or type(response) ~= "table" then
      g_logger.error("[Polopag] Empty or invalid remote config response.")
      return
    end

    if not applyRemoteConfig(response) then
      g_logger.error("[Polopag] Invalid payload format. Expected { offers: [...], apiUrl: '...' }.")
      return
    end

    if polopagWindow and offersContent and pendingCategory then
      local categoryToRender = pendingCategory
      pendingCategory = nil
      refreshOffers(categoryToRender)
    end
  end)
end

function refreshOffers(category)
  offersContent:destroyChildren()
  
  if not Services then
    Services = {}
  end

  if not Services.polopagOffers or #Services.polopagOffers == 0 then
    requestRemoteConfig(category)
    g_logger.warning("[Polopag] Waiting remote offers from Services.polopagConfig.")
    selectedOffer = nil
    polopagWindow:getChildById('buyButton'):setEnabled(false)
    return
  end

  for i, offer in ipairs(Services.polopagOffers) do
    if offer.category == category then
      local widget = g_ui.createWidget('PolopagOffer', offersContent)
      widget:setId('offer_' .. offer.id)
      
      -- Setup UI
      widget:getChildById('name'):setText(offer.name)
      widget:getChildById('price'):setText('R$ ' .. string.format("%.2f", offer.price))

      -- Setup Custom Icon if available (for now using generic)
      -- widget:getChildById('image'):setImageSource(offer.icon) if we had icons
      
      widget.offerData = offer
      
      -- Info Button Logic
      local infoBtn = widget:getChildById('infoButton')
      infoBtn.onClick = function()
          local desc = offer.description or tr('No description available.')
          displayInfoBox(offer.name, desc)
      end
      
      widget.onClick = function()
          selectOffer(widget)
      end
    end
  end
  selectedOffer = nil
  polopagWindow:getChildById('buyButton'):setEnabled(false)
end

function selectOffer(widget)
  -- Deselect others
  for _, child in pairs(offersContent:getChildren()) do
      child:setChecked(false)
      if child:getChildById('selectionOverlay') then
        child:getChildById('selectionOverlay'):setVisible(false)
      end
  end
  widget:setChecked(true)
  if widget:getChildById('selectionOverlay') then
    widget:getChildById('selectionOverlay'):setVisible(true)
  end
  selectedOffer = widget.offerData
  polopagWindow:getChildById('buyButton'):setEnabled(true)
end

function init()
  connect(g_game, { onGameEnd = destroy })
  
  polopagWindow = g_ui.displayUI('polopag')
  polopagWindow:hide()
  
  offersContent = polopagWindow:getChildById('offersPanel'):getChildById('offersContent')
  
  -- Default Selection
  selectCategory('Tibia Coins')
end

function selectCategory(category)
  refreshOffers(category)
  
  -- Update visual state of buttons
  local panel = polopagWindow:getChildById('categoryPanel')
  local btnCoins = panel:getChildById('btnTibiaCoins')
  local btnPack = panel:getChildById('btnPacotes')
  
  if category == 'Tibia Coins' then
    btnCoins:setEnabled(false) -- disabled looks "pressed" or active usually
    btnPack:setEnabled(true)
  else
    btnCoins:setEnabled(true)
    btnPack:setEnabled(false)
  end
end

function terminate()
  disconnect(g_game, { onGameEnd = destroy })
  if polopagWindow then polopagWindow:destroy() polopagWindow = nil end
end

function destroy()
  if polopagWindow then polopagWindow:hide() end
end

function toggle()
  if not polopagWindow then return end
  if polopagWindow:isVisible() then
    polopagWindow:hide()
  else
    polopagWindow:show()
    polopagWindow:raise()
    polopagWindow:focus()
    -- Reset to first tab if needed, or keep state
    if selectedOffer then
       -- optional: keep selection
    end
  end
end

function buySelectedOffer()
  local offer = selectedOffer
  if not offer then return end
  
  local player = g_game.getLocalPlayer()
  if not player then return end

  if not Services or type(Services.polopag) ~= "string" or Services.polopag == "" then
    displayErrorBox(tr('Error'), tr('Polopag API URL not configured (Services.polopag).'))
    return
  end
  
  local buyButton = polopagWindow:getChildById('buyButton')
  buyButton:setEnabled(false)
  buyButton:setText(tr('Processing...'))
  
  local data = {
    character_name = player:getName(),
    offer_id = offer.id,
    amount = offer.price,
    coins = offer.coins,
    reference = player:getName() .. '_' .. os.time()
  }
  
  HTTP.postJSON(Services.polopag, data, function(response, err)
    buyButton:setEnabled(true)
    buyButton:setText(tr('Generate PIX Code'))
    
    if err then
      displayErrorBox(tr('Error'), tr('Failed to communicate with server: ') .. tostring(err))
      return
    end

    if not response then
       displayErrorBox(tr('Error'), tr('Empty response from server. Check server logs.'))
       return
    end
    
    g_logger.info("Server Response: " .. json.encode(response))

    if response.status == 'success' then
      showPaymentDetails(response)
    else
      local msg = response.message or 'Unknown error'
      if response.debug_msg then
         msg = msg .. '\nDebug: ' .. response.debug_msg
      end
      displayErrorBox(tr('Error'), tr('Payment creation failed: ') .. msg)
    end
  end)
end

function showPaymentDetails(data)
  local panel = polopagWindow:getChildById('paymentPanel')
  panel:setVisible(true)
  
  local qrCode = panel:recursiveGetChildById('qrCodeImage') -- Using recursive cause it's nested
  
  local b64 = data.qrcode_base64
  if b64:find('data:image') then
    b64 = b64:gsub('data:image/.-;base64,', '')
  end
  
  local b = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/'
  local function dec(data)
      data = string.gsub(data, '[^'..b..'=]', '')
      return (data:gsub('.', function(x)
          if (x == '=') then return '' end
          local r,f='',(b:find(x)-1)
          for i=6,1,-1 do r=r..(f%2^i-f%2^(i-1)>0 and '1' or '0') end
          return r;
      end):gsub('%d%d%d?%d?%d?%d?%d?%d?', function(x)
          if (#x ~= 8) then return '' end
          local c=0
          for i=1,8 do c=c+(x:sub(i,i)=='1' and 2^(8-i) or 0) end
          return string.char(c)
      end))
  end
  
  local path = '/polopag_qr.png'
  local content = dec(b64)
  if g_resources.writeFileContents then
      g_resources.writeFileContents(path, content)
  else
      displayErrorBox(tr('Error'), tr('Cannot save QR code: write function missing'))
  end
  qrCode:setImageSource(path)
  
  panel.copyPasteCode = data.copypaste
  
  local statusLabel = panel:recursiveGetChildById('statusLabel')
  statusLabel:setText(tr('Payment Created! Waiting...'))
  statusLabel:setColor('#FFA500')
end

function copyPixCode()
  local panel = polopagWindow:getChildById('paymentPanel')
  if panel.copyPasteCode then
    g_window.setClipboardText(panel.copyPasteCode)
    displayInfoBox(tr('Success'), tr('PIX Code copied to clipboard!'))
  end
end

function closePayment()
    polopagWindow:getChildById('paymentPanel'):setVisible(false)
end
