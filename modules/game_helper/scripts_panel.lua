local scripts = {}

modules.game_helper = modules.game_helper or {}
modules.game_helper.scripts = scripts

local scriptsPanelContainer = nil
local savedScriptsList = nil
local activeScriptsList = nil
local editorWindow = nil
local scriptCodeEdit = nil
local activeScripts = {}
local selectedSavedIndex = nil
local selectedActiveIndex = nil
local editingSavedIndex = nil
local editingActiveIndex = nil
local lastExecutedActiveIndex = nil
local SAVED_PREFIX = "saved_"
local ACTIVE_PREFIX = "active_"
local EXAMPLES_PREFIX = "example_"
local ACTIVE_SCRIPT_INTERVAL_MS = 5000
local ACTIVE_SCRIPT_STAGGER_MS = 600
local nextActiveScriptId = 0
local selectedExampleIndex = nil
local docWindow = nil
local lastToggleRunningIds = {}

local SCRIPT_LIB_DOC = [=[# Script Library (Bot Helper)

Functions available in the **Scripts** tab and in cavebot **Action** waypoints.

---

### 1. `say(text)`

Sends a message on the NPC channel ("hi", "trade", etc.).

```lua
say("hi")
say("trade")
```

---

### 2. `wait(time)`

Pause in **milliseconds**. Maximum 5000 ms per call. Quando o script tem `wait`, ele é dividido em passos; use `return false` num passo para não executar os passos seguintes.

```lua
say("hi")
wait(500)
say("trade")
```

---

### 3. `useItem(itemId)`

Uses an inventory item by ID.

```lua
useItem(2274)
useItem(7618)
```

---

### 4. `moveItem(containerId, slot, toX, toY, toZ, count)`

Moves an item from a container to a position on the map. `count` is optional (default 1).

```lua
moveItem(0, 2, 100, 100, 7, 5)
```

---

### 5. `moveItemById(itemId, toX, toY, toZ, count)`

Finds the item by ID in any open container and moves it to the map. `count` is optional.

```lua
local pos = getPosition()
if pos then moveItemById(2274, pos.x, pos.y, pos.z, 10) end
```

---

### 6. `getFreeCapacity()`

Returns free capacity in **oz**, or `nil`.

```lua
local cap = getFreeCapacity()
```

---

### 7. `hasEnoughCap(minCap)`

Returns `true` if free capacity is ≥ `minCap`.

```lua
if not hasEnoughCap(10000) then return end
useItem(63338)
```

---

### 8. `getItemCount(itemId)`

Returns the total number of the item (inventory + open containers).

```lua
if getItemCount(2274) < 10 then
  say("hi"); wait(500); say("trade"); wait(500)
  npcTradeBuy(2274, 100)
end
```

---

### 9. Player functions

Return `nil` if the player is not available.

| Function | Returns |
|----------|---------|
| `getHealth()` | Current health |
| `getMana()` | Current mana |
| `getMaxHealth()` | Max health |
| `getMaxMana()` | Max mana |
| `getHealthPercent()` | Health % (0–100) |
| `getManaPercent()` | Mana % (0–100) |
| `getLevel()` | Level |
| `getPosition()` | `{ x, y, z }` |

Direction constants: `DirectionNorth` (0), `DirectionEast` (1), `DirectionSouth` (2), `DirectionWest` (3).

---

### 10. `getCreaturesNearby(range)`

Returns the number of **monsters** (vivos) próximos do jogador. `range` opcional (raio em tiles; padrão 1).

```lua
local n = getCreaturesNearby(1)
```

---

### 11. `hasLessCreaturesNearby(maxCount, range)`

Retorna `true` se houver **menos** que `maxCount` monstros por perto. `range` opcional (padrão 1). Útil para só executar o script quando estiver "seguro" (poucos bichos).

```lua
if not hasLessCreaturesNearby(3) then return false end
```

---

```lua
if getHealthPercent() and getHealthPercent() < 50 then useItem(7618) end
```

---

### 12. `modalAnswer(id, buttonId, choice)`

Responds to a modal window (e.g. "Select an option"). `buttonId` 255 = default.

```lua
modalAnswer(1, 1, 0)
```

---

### 13. `simulateKey(keyCode)`

Simulates a key press on the focused widget. Constants: `KeyEnter`, `KeyEscape`, `KeyUp`, `KeyDown`, `KeyLeft`, `KeyRight`, `KeySpace`.

```lua
useItem(63338)
scheduleEvent(function() simulateKey(KeyEnter) end, 500)
```

---

### 14. `clickSelectButton()`

Clicks the "Select" button in the interface (modals, dialogs).

```lua
useItem(63338)
scheduleEvent(function() clickSelectButton() end, 500)
```

---

### 15. `npcTradeBuy(itemRef, quantity)`

Buys from the NPC trade window (**Buy** tab open). `itemRef` = item name or ID.

```lua
npcTradeBuy("avalanche rune", 100)
npcTradeBuy(2274, 50)
```

---

### 16. `npcTradeSell(itemRef, quantity)`

Sells in the trade window (**Sell** tab open).

```lua
npcTradeSell("avalanche rune", 100)
```

---

### 17. `closeNpcTradeWindow()`

Closes the NPC Trade window (e.g. the one in the character column). Use after a buy/sell to close the trade.

```lua
npcTradeBuy(2274, 100)
wait(200)
closeNpcTradeWindow()
```

---

### 18. `scheduleEvent(func, delay)`

Schedules execution of `func` after `delay` milliseconds.

```lua
scheduleEvent(function() say("trade") end, 400)
```

---

### 19. `gotoid(id)`

Sets the cavebot current waypoint to index `id` (1-based). Only has effect with cavebot enabled.

```lua
gotoid(10)
```

---]=]

local SCRIPT_EXAMPLES = {
  {
    name = tr("Seller Loot"),
    code = [[-- Se cap >= MIN_CAP não continua. Só usa se tiver menos que MAX_NEARBY monstros por perto.
local MIN_CAP = 10000
local MAX_NEARBY = 3
local cap = getFreeCapacity()
if cap ~= nil and cap >= MIN_CAP then return false end
if not hasLessCreaturesNearby(MAX_NEARBY) then return false end
useItem(63338)
wait(300)
simulateKey(KeyEnter)]]
  },
  {
    name = tr("Rune Refiller"),
    code = [[-- Se current < MIN_RUNES abre e compra BUY_QTY. MIN_RUNES = limite; BUY_QTY = qtd a comprar.
RUNE_ID = 3161
MIN_RUNES = 100
BUY_QTY = 1000
current = getItemCount(RUNE_ID)
if current >= MIN_RUNES then return false end
useItem(63340)
wait(1200)
npcTradeBuy(RUNE_ID, BUY_QTY)
wait(400)
closeNpcTradeWindow()]]
  },
  {
    name = tr("Potion Refiller"),
    code = [[-- Se current < MIN_POTIONS abre e compra BUY_QTY.
POTION_ID = 7618
MIN_POTIONS = 5
BUY_QTY = 50
current = getItemCount(POTION_ID)
if current >= MIN_POTIONS then return false end
useItem(63340)
wait(1200)
npcTradeBuy(POTION_ID, BUY_QTY)
wait(400)
closeNpcTradeWindow()]]
  },
  {
    name = tr("Ammunition Refiller"),
    code = [[-- Se current < MIN_AMMO abre e compra BUY_QTY.
AMMO_ID = 3447
MIN_AMMO = 50
BUY_QTY = 200
current = getItemCount(AMMO_ID)
if current >= MIN_AMMO then return false end
useItem(63339)
wait(1200)
npcTradeBuy(AMMO_ID, BUY_QTY)
wait(400)
closeNpcTradeWindow()]]
  },
  {
    name = tr("Open bronze chest"),
    code = [[-- Só usa se tiver a chave (62060) e o baú (62062). Usa chave no baú.
KEY_ID = 62060
CHEST_ID = 62062
if getItemCount(KEY_ID) < 1 then return false end
if getItemCount(CHEST_ID) < 1 then return false end
useItemOn(KEY_ID, CHEST_ID)
wait(500)]]
  },
  {
    name = tr("Open Silver Chest"),
    code = [[-- Só usa se tiver a chave (62059) e o baú (62063). Usa chave no baú.
KEY_ID = 62059
CHEST_ID = 62063
if getItemCount(KEY_ID) < 1 then return false end
if getItemCount(CHEST_ID) < 1 then return false end
useItemOn(KEY_ID, CHEST_ID)
wait(500)]]
  },
  {
    name = tr("Open Golden Chest"),
    code = [[-- Só usa se tiver a chave (62058) e o baú (62064). Usa chave no baú.
KEY_ID = 62058
CHEST_ID = 62064
if getItemCount(KEY_ID) < 1 then return false end
if getItemCount(CHEST_ID) < 1 then return false end
useItemOn(KEY_ID, CHEST_ID)
wait(500)]]
  },
}

local function getHelperConfig()
  return _Helper and _Helper.getHelperConfig and _Helper.getHelperConfig() or nil
end

local function findAndClickButtonByText(widget, searchLower)
  if not widget then return false end
  if widget.isDestroyed and widget:isDestroyed() then return false end
  local text = nil
  if widget.getText and type(widget.getText) == "function" then
    text = widget:getText()
  end
  if (not text or text == "") and widget.getCaption and type(widget.getCaption) == "function" then
    text = widget:getCaption()
  end
  if text and type(text) == "string" and widget.onClick and type(widget.onClick) == "function" then
    if string.lower(text):find(searchLower, 1, true) then
      pcall(function() widget.onClick(widget) end)
      return true
    end
  end
  local n = widget.getChildCount and widget:getChildCount() or 0
  for i = 1, n do
    local child = widget.getChildByIndex and widget:getChildByIndex(i)
    if child and findAndClickButtonByText(child, searchLower) then
      return true
    end
  end
  return false
end

function scripts.clickSelectButton()
  local root = g_ui.getRootWidget()
  if not root then return false end
  if findAndClickButtonByText(root, "select") then return true end
  if findAndClickButtonByText(root, "selecionar") then return true end
  local btn = root:recursiveGetChildById("SelectButton")
  if btn and btn.onClick and type(btn.onClick) == "function" then
    pcall(function() btn.onClick(btn) end)
    return true
  end
  local mod = modules.game_modaldialog
  if mod and mod.modalDialog and not mod.modalDialog:isDestroyed() then
    local panel = mod.modalDialog:getChildById("buttonsPanel")
    if panel then
      for i = 1, panel:getChildCount() do
        local b = panel:getChildByIndex(i)
        if b and b.getText and b.onClick then
          local t = (b:getText() or ""):lower()
          if t:find("select", 1, true) or t:find("selecionar", 1, true) then
            pcall(function() b.onClick(b) end)
            return true
          end
        end
      end
    end
  end
  return false
end

local function getScriptsPanel()
  if scriptsPanelContainer then return scriptsPanelContainer end
  local root = g_ui.getRootWidget()
  if not root then return nil end
  local helperWindow = root:recursiveGetChildById('helperWindow')
  if not helperWindow then return nil end
  scriptsPanelContainer = helperWindow:recursiveGetChildById('scriptsPanelContainer')
  return scriptsPanelContainer
end

local function getSavedListWidget()
  if savedScriptsList then return savedScriptsList end
  local panel = getScriptsPanel()
  if not panel then return nil end
  savedScriptsList = panel:recursiveGetChildById('savedScriptsList')
  return savedScriptsList
end

local function getActiveListWidget()
  if activeScriptsList then return activeScriptsList end
  local panel = getScriptsPanel()
  if not panel then return nil end
  activeScriptsList = panel:recursiveGetChildById('activeScriptsList')
  return activeScriptsList
end

local function getExamplesListWidget()
  local panel = getScriptsPanel()
  if not panel then return nil end
  return panel:recursiveGetChildById('examplesList')
end

local function bindScriptsPanelButtons()
  local panel = getScriptsPanel()
  if not panel then return end
  local deleteBtn = panel:recursiveGetChildById('deleteSavedScriptButton')
  if deleteBtn then deleteBtn.onClick = function() scripts.deleteSavedScript() end end
  local runBtn = panel:recursiveGetChildById('runSavedScriptButton')
  if runBtn then runBtn.onClick = function() scripts.runSavedScript() end end
  local editSavedBtn = panel:recursiveGetChildById('editSavedScriptButton')
  if editSavedBtn then editSavedBtn.onClick = function() scripts.editSavedScript() end end
  local saveActiveBtn = panel:recursiveGetChildById('saveActiveScriptButton')
  if saveActiveBtn then saveActiveBtn.onClick = function() scripts.saveActiveScript() end end
  local editActiveBtn = panel:recursiveGetChildById('editActiveScriptButton')
  if editActiveBtn then editActiveBtn.onClick = function() scripts.editActiveScript() end end
  local startBtn = panel:recursiveGetChildById('startActiveScriptButton')
  if startBtn then startBtn.onClick = function() scripts.startActiveScript() end end
  local stopBtn = panel:recursiveGetChildById('stopActiveScriptButton')
  if stopBtn then stopBtn.onClick = function() scripts.stopActiveScript() end end
  local removeBtn = panel:recursiveGetChildById('removeActiveScriptButton')
  if removeBtn then removeBtn.onClick = function() scripts.removeActiveScript() end end
  local importExampleBtn = panel:recursiveGetChildById('examplesImportButton')
  if importExampleBtn then importExampleBtn.onClick = function() scripts.importExampleScript() end end
end

function scripts.loadToUI()
  bindScriptsPanelButtons()
  local savedList = getSavedListWidget()
  local activeList = getActiveListWidget()
  if not savedList or not activeList then return end

  local cfg = getHelperConfig()
  local saved = (cfg and cfg.scripts) and cfg.scripts or {}

  savedList:destroyChildren()
  for i, s in ipairs(saved) do
    local name = (type(s) == "table" and s.name) or ("Script " .. i)
    local label = g_ui.createWidget('Label', savedList)
    label:setId(SAVED_PREFIX .. tostring(i))
    label:setText(name)
    label:setMarginTop(2)
    label:setPhantom(false)
    label:setFocusable(true)
    if i == selectedSavedIndex then
      label:setColor('#ffff00')
      label:setFont('verdana-11px-rounded')
    else
      label:setColor('#dfdfdf')
      label:setFont('verdana-11px-antialised')
    end
    label.onClick = function()
      selectedSavedIndex = i
      scripts.loadToUI()
    end
    label.onMousePress = function(self, mousePos, mouseButton)
      if mouseButton == MouseRightButton then
        selectedSavedIndex = i
        scripts.loadToUI()
        local menu = g_ui.createWidget('PopupMenu')
        menu:setGameMenu(true)
        menu:addOption(tr('Delete'), function() scripts.deleteSavedScript() end)
        menu:display(mousePos)
        return true
      end
    end
  end

  activeList:destroyChildren()
  for i, s in ipairs(activeScripts) do
    local name = (s and s.name) or ("Active " .. i)
    local running = s and s.loopEvent
    local prefix = running and "ON  " or "OFF "
    local label = g_ui.createWidget('Label', activeList)
    label:setId(ACTIVE_PREFIX .. tostring(i))
    label:setText(prefix .. name)
    label:setMarginTop(2)
    label:setPhantom(false)
    label:setFocusable(true)
    if i == selectedActiveIndex then
      label:setColor('#ffff00')
      label:setFont('verdana-11px-rounded')
    elseif running then
      label:setColor('#98e698')
      label:setFont('verdana-11px-antialised')
    else
      label:setColor('#9a9a9a')
      label:setFont('verdana-11px-antialised')
    end
    label.onClick = function()
      selectedActiveIndex = i
      scripts.loadToUI()
    end
  end

  local examplesList = getExamplesListWidget()
  if examplesList and not examplesList:isDestroyed() then
    examplesList:destroyChildren()
    for i, ex in ipairs(SCRIPT_EXAMPLES) do
      local name = (ex and ex.name) or ("Example " .. i)
      local label = g_ui.createWidget('Label', examplesList)
      label:setId(EXAMPLES_PREFIX .. tostring(i))
      label:setText(name)
      label:setMarginTop(2)
      label:setPhantom(false)
      label:setFocusable(true)
      if i == selectedExampleIndex then
        label:setColor('#ffff00')
        label:setFont('verdana-11px-rounded')
      else
        label:setColor('#dfdfdf')
        label:setFont('verdana-11px-antialised')
      end
      label.onClick = function()
        selectedExampleIndex = i
        scripts.loadToUI()
      end
    end
  end
end

function scripts.importExampleScript()
  if not selectedExampleIndex or selectedExampleIndex < 1 or selectedExampleIndex > #SCRIPT_EXAMPLES then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select an example first."))
    end
    return
  end
  local ex = SCRIPT_EXAMPLES[selectedExampleIndex]
  if not ex or not ex.code then return end
  scripts.addToActive(ex.name or ("Example " .. selectedExampleIndex), ex.code or "", false)
  scripts.loadToUI()
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Example imported. Select it and click Start to run."))
  end
end

function scripts.openEditor(initialCode, initialName)
  local root = g_ui.getRootWidget()
  if not root then return end
  if (not initialCode or initialCode == "") and (not initialName or initialName == "") then
    editingSavedIndex = nil
    editingActiveIndex = nil
    lastExecutedActiveIndex = nil
  end

  if editorWindow and not editorWindow:isDestroyed() then
    editorWindow:show()
    editorWindow:raise()
    scriptCodeEdit = editorWindow:recursiveGetChildById('scriptCode')
    local scriptNameEdit = editorWindow:recursiveGetChildById('scriptNameEdit')
    if scriptCodeEdit then scriptCodeEdit:setText(initialCode or "") end
    if scriptNameEdit then scriptNameEdit:setText(initialName or "") end
    if scriptCodeEdit then scriptCodeEdit:focus() end
    return
  end

  editorWindow = g_ui.createWidget('ScriptEditorWindow', root)
  if not editorWindow then return end

  scriptCodeEdit = editorWindow:recursiveGetChildById('scriptCode')
  local scriptNameEdit = editorWindow:recursiveGetChildById('scriptNameEdit')
  if scriptCodeEdit then
    scriptCodeEdit:setText(initialCode or "")
  end
  if scriptNameEdit then
    scriptNameEdit:setText(initialName or "")
  end

  editorWindow.onDestroy = function()
    editorWindow = nil
    scriptCodeEdit = nil
  end

  editorWindow:show()
  if scriptCodeEdit then scriptCodeEdit:focus() end
end

function scripts.okFromEditor()
  if not editorWindow or editorWindow:isDestroyed() then return end
  local scriptCodeEdit = editorWindow:recursiveGetChildById('scriptCode')
  local scriptNameEdit = editorWindow:recursiveGetChildById('scriptNameEdit')
  if not scriptCodeEdit then return end
  local code = scriptCodeEdit:getText()
  if not code or code:match("^%s*$") then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Empty script."))
    end
    return
  end
  local name = (scriptNameEdit and scriptNameEdit:getText() and scriptNameEdit:getText():match("^%s*(.-)%s*$") ~= "") and scriptNameEdit:getText():match("^%s*(.-)%s*$") or ("Script " .. os.date("%H%M%S"))
  if editingActiveIndex and editingActiveIndex >= 1 and editingActiveIndex <= #activeScripts then
    local old = activeScripts[editingActiveIndex]
    activeScripts[editingActiveIndex] = { name = name, code = code, id = old and old.id, loopEvent = old and old.loopEvent }
    editingActiveIndex = nil
    scripts.loadToUI()
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(tr("Script saved."))
    end
  elseif editingSavedIndex and editingSavedIndex >= 1 then
    scripts.saveScriptWithName(name, code, editingSavedIndex)
    editingSavedIndex = nil
    scripts.loadToUI()
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(tr("Script saved."))
    end
  end
  if editorWindow and not editorWindow:isDestroyed() then
    editorWindow:hide()
  end
end

function scripts.saveFromEditor()
  if not editorWindow or editorWindow:isDestroyed() then return end
  local scriptCodeEdit = editorWindow:recursiveGetChildById('scriptCode')
  local scriptNameEdit = editorWindow:recursiveGetChildById('scriptNameEdit')
  if not scriptCodeEdit then return end
  local code = scriptCodeEdit:getText()
  if not code or code:match("^%s*$") then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Empty script."))
    end
    return
  end
  local name = (scriptNameEdit and scriptNameEdit:getText() and scriptNameEdit:getText():match("^%s*(.-)%s*$") ~= "") and scriptNameEdit:getText():match("^%s*(.-)%s*$") or ("Script " .. os.date("%H%M%S"))
  local replaceIdx = editingSavedIndex
  editingSavedIndex = nil
  scripts.saveScriptWithName(name, code, replaceIdx)
  scripts.loadToUI()
  if editorWindow and not editorWindow:isDestroyed() then
    editorWindow:hide()
  end
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Script saved."))
  end
end

function scripts.getFreeCapacity()
  if g_helperCore and g_helperCore.getScriptFreeCapacity then
    local ok, n = pcall(g_helperCore.getScriptFreeCapacity, g_helperCore)
    if ok and type(n) == "number" and n >= 0 then return n end
  end
  if not g_game or not g_game.getLocalPlayer then return nil end
  local player = g_game.getLocalPlayer()
  if not player then return nil end
  local cap
  local ok, res = pcall(function()
    if player.getFreeCapacity then return player:getFreeCapacity() end
    return nil
  end)
  if ok and res ~= nil then cap = res end
  if cap == nil then return nil end
  local n = tonumber(cap)
  return (n and n >= 0) and n or nil
end

local function getPlayer()
  if not g_game or not g_game.getLocalPlayer then return nil end
  return g_game.getLocalPlayer()
end

function scripts.getHealth()
  if g_helperCore and g_helperCore.getScriptHealth then
    local ok, v = pcall(g_helperCore.getScriptHealth, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local p = getPlayer()
  if not p or not p.getHealth then return nil end
  local ok, v = pcall(function() return p:getHealth() end)
  return (ok and v ~= nil) and tonumber(v) or nil
end

function scripts.getMana()
  if g_helperCore and g_helperCore.getScriptMana then
    local ok, v = pcall(g_helperCore.getScriptMana, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local p = getPlayer()
  if not p or not p.getMana then return nil end
  local ok, v = pcall(function() return p:getMana() end)
  return (ok and v ~= nil) and tonumber(v) or nil
end

function scripts.getMaxHealth()
  if g_helperCore and g_helperCore.getScriptMaxHealth then
    local ok, v = pcall(g_helperCore.getScriptMaxHealth, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local p = getPlayer()
  if not p or not p.getMaxHealth then return nil end
  local ok, v = pcall(function() return p:getMaxHealth() end)
  return (ok and v ~= nil) and tonumber(v) or nil
end

function scripts.getMaxMana()
  if g_helperCore and g_helperCore.getScriptMaxMana then
    local ok, v = pcall(g_helperCore.getScriptMaxMana, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local p = getPlayer()
  if not p or not p.getMaxMana then return nil end
  local ok, v = pcall(function() return p:getMaxMana() end)
  return (ok and v ~= nil) and tonumber(v) or nil
end

function scripts.getHealthPercent()
  if g_helperCore and g_helperCore.getScriptHealthPercent then
    local ok, v = pcall(g_helperCore.getScriptHealthPercent, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local cur, max = scripts.getHealth(), scripts.getMaxHealth()
  if cur == nil or max == nil or max == 0 then return nil end
  return math.floor((cur / max) * 100)
end

function scripts.getManaPercent()
  if g_helperCore and g_helperCore.getScriptManaPercent then
    local ok, v = pcall(g_helperCore.getScriptManaPercent, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local cur, max = scripts.getMana(), scripts.getMaxMana()
  if cur == nil or max == nil or max == 0 then return nil end
  return math.floor((cur / max) * 100)
end

function scripts.getLevel()
  if g_helperCore and g_helperCore.getScriptLevel then
    local ok, v = pcall(g_helperCore.getScriptLevel, g_helperCore)
    if ok and type(v) == "number" then return v end
  end
  local p = getPlayer()
  if not p or not p.getLevel then return nil end
  local ok, v = pcall(function() return p:getLevel() end)
  return (ok and v ~= nil) and tonumber(v) or nil
end

function scripts.getPosition()
  if g_helperCore and g_helperCore.getScriptPosition then
    local ok, pos = pcall(g_helperCore.getScriptPosition, g_helperCore)
    if ok and pos and pos.x ~= nil then return { x = tonumber(pos.x), y = tonumber(pos.y), z = tonumber(pos.z) } end
  end
  local p = getPlayer()
  if not p or not p.getPosition then return nil end
  local ok, pos = pcall(function() return p:getPosition() end)
  if not ok or not pos or not pos.x then return nil end
  return { x = tonumber(pos.x), y = tonumber(pos.y), z = tonumber(pos.z) }
end

function scripts.getCreaturesNearby(range)
  local pos = scripts.getPosition()
  if not pos or not g_map then return 0 end
  range = tonumber(range)
  if not range or range < 1 then range = 1 end
  local spectators = (g_map.getSpectatorsInRange and g_map.getSpectatorsInRange(pos, false, range, range)) or g_map.getSpectators(pos, false) or {}
  local count = 0
  local player = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  for _, creature in ipairs(spectators) do
    if creature and creature ~= player and creature.isMonster and creature:isMonster() and (not creature.isDead or not creature:isDead()) then
      count = count + 1
    end
  end
  return count
end

function scripts.hasLessCreaturesNearby(maxCount, range)
  maxCount = tonumber(maxCount)
  if not maxCount or maxCount < 0 then return true end
  return scripts.getCreaturesNearby(range) < maxCount
end

function scripts.modalAnswer(id, buttonId, choice, closeAfterAnswer)
  if not g_game or not g_game.answerModalDialog then return false end
  id = tonumber(id)
  buttonId = tonumber(buttonId) or 255
  choice = tonumber(choice) or 0
  if id == nil then return false end
  pcall(function() g_game.answerModalDialog(id, buttonId, choice) end)
  return true
end

function scripts.say(text)
  if not g_game then return false end
  local s = tostring(text or "")
  if s == "" then return true end
  local npcMode = (MessageModes and MessageModes.NpcTo) or 11
  if g_game.talkChannel then
    pcall(function() g_game.talkChannel(npcMode, 0, s) end)
    return true
  end
  if g_game.talk then
    pcall(function() g_game.talk(s) end)
    return true
  end
  return false
end

function scripts.useItem(itemId)
  if not g_game or not g_game.useInventoryItem then return false end
  local id = tonumber(itemId)
  if not id then return false end
  pcall(function() g_game.useInventoryItem(id) end)
  return true
end

local function findItemObject(itemId)
  local id = tonumber(itemId)
  if not id or not g_game then return nil end
  local player = g_game.getLocalPlayer and g_game.getLocalPlayer()
  if player and player.getInventoryItem then
    for slot = 1, 10 do
      local item = player:getInventoryItem(slot)
      if item and item.getId and item:getId() == id then return item end
    end
  end
  if g_game.getContainers then
    for _, container in pairs(g_game.getContainers()) do
      if container.getItem and container.getItemsCount then
        for slot = 0, container:getItemsCount() - 1 do
          local item = container:getItem(slot)
          if item and item.getId and item:getId() == id then return item end
        end
      end
    end
  end
  return nil
end

function scripts.useItemOn(itemIdUsed, itemIdTarget)
  if not g_game or not g_game.useInventoryItemWith then return false end
  local used = tonumber(itemIdUsed)
  local target = tonumber(itemIdTarget)
  if not used or not target then return false end
  local targetItem = findItemObject(target)
  if not targetItem then return false end
  pcall(function() g_game.useInventoryItemWith(used, targetItem) end)
  return true
end

local function resolveNpcTradeItem(ref, tradeType)
  local mod = modules.game_npctrade
  if not mod or not mod.tradeItems then return nil end

  local BUY = rawget(_G, "BUY") or 1
  local SELL = rawget(_G, "SELL") or 2
  local t = tradeType or (mod.getCurrentTradeType and mod.getCurrentTradeType()) or BUY
  local list = mod.tradeItems and mod.tradeItems[t]
  if not list or type(list) ~= "table" or #list == 0 then return nil end

  local refType = type(ref)

  -- Search by numeric item id using npctrade helper if available
  if refType == "number" then
    if mod.getTradeItemData then
      local data = mod.getTradeItemData(ref, t)
      if data and data.ptr then return data end
    end
    for _, item in ipairs(list) do
      if item.ptr and item.ptr.getId and item.ptr:getId() == ref then
        return item
      end
    end
    return nil
  end

  -- Otherwise search by (partial) item name, case-insensitive
  local target = tostring(ref or ""):lower()
  if target == "" then return nil end
  for _, item in ipairs(list) do
    if item.name and type(item.name) == "string" then
      local nameLower = item.name:lower()
      if nameLower == target or nameLower:find(target, 1, true) then
        return item
      end
    end
  end
  return nil
end

function scripts.npcTradeBuy(itemRef, quantity)
  if not g_game or not g_game.buyItem then return false end
  local mod = modules.game_npctrade
  if not mod or not mod.getCurrentTradeType or mod.getCurrentTradeType() ~= (rawget(_G, "BUY") or 1) then
    return false
  end
  local entry = resolveNpcTradeItem(itemRef, rawget(_G, "BUY") or 1)
  if not entry or not entry.ptr then return false end
  local qty = math.max(1, tonumber(quantity) or 1)
  pcall(function() g_game.buyItem(entry.ptr, qty, false, false) end)
  return true
end

function scripts.npcTradeSell(itemRef, quantity)
  if not g_game or not g_game.sellItem then return false end
  local mod = modules.game_npctrade
  if not mod or not mod.getCurrentTradeType or mod.getCurrentTradeType() ~= (rawget(_G, "SELL") or 2) then
    return false
  end
  local entry = resolveNpcTradeItem(itemRef, rawget(_G, "SELL") or 2)
  if not entry or not entry.ptr then return false end
  local qty = math.max(1, tonumber(quantity) or 1)
  pcall(function() g_game.sellItem(entry.ptr, qty, false, {}) end)
  return true
end

function scripts.closeNpcTradeWindow()
  local mod = modules.game_npctrade
  if not mod then return false end
  if mod.closeNpcTrade then
    pcall(function() mod.closeNpcTrade() end)
    return true
  end
  if mod.hide then
    pcall(function() mod.hide() end)
    return true
  end
  return false
end

function scripts.moveItem(containerId, slot, toX, toY, toZ, count)
  if not g_game or not g_game.move or not g_game.getContainers then return false end
  local containers = g_game.getContainers()
  if not containers then return false end
  local container = nil
  for _, c in pairs(containers) do
    if c.getId and c:getId() == tonumber(containerId) then
      container = c
      break
    end
  end
  if not container or not container.getItem then return false end
  local slotIdx = tonumber(slot)
  if slotIdx == nil or slotIdx < 0 then return false end
  local item = container:getItem(slotIdx)
  if not item or not item.getId then return false end
  local toPos
  local cnt = 1
  if type(toX) == "table" then
    toPos = toX
    cnt = math.max(1, tonumber(toY) or 1)
  else
    toPos = { x = tonumber(toX), y = tonumber(toY), z = tonumber(toZ) }
    if toPos.x == nil or toPos.y == nil or toPos.z == nil then return false end
    cnt = math.max(1, tonumber(count) or 1)
  end
  local maxCount = item.getCount and item:getCount() or 1
  cnt = math.min(cnt, maxCount)
  pcall(function() g_game.move(item, toPos, cnt) end)
  return true
end

function scripts.getItemCount(itemId)
  local id = tonumber(itemId)
  if not id then return 0 end
  if g_helperCore and g_helperCore.getScriptItemCount then
    local ok, n = pcall(g_helperCore.getScriptItemCount, g_helperCore, id)
    if ok and type(n) == "number" and n >= 0 then return n end
  end
  local player = g_game and g_game.getLocalPlayer and g_game.getLocalPlayer()
  if player and player.getInventoryCount then
    local ok, n = pcall(function() return player:getInventoryCount(id, 0) end)
    if ok and type(n) == "number" then return n end
  end
  local total = 0
  if g_game and g_game.getContainers then
    for _, container in pairs(g_game.getContainers()) do
      if container.getItem and container.getItemsCount then
        for slot = 0, container:getItemsCount() - 1 do
          local item = container:getItem(slot)
          if item and item.getId and item:getId() == id then
            total = total + (item.getCount and item:getCount() or 1)
          end
        end
      end
    end
  end
  if player and player.getInventoryItem then
    for slot = 1, 10 do
      local item = player:getInventoryItem(slot)
      if item and item.getId and item:getId() == id then
        total = total + (item.getCount and item:getCount() or 1)
      end
    end
  end
  return total
end

function scripts.moveItemById(itemId, toX, toY, toZ, count)
  if not g_game or not g_game.move or not g_game.getContainers then return false end
  local id = tonumber(itemId)
  if not id then return false end
  local cnt = math.max(1, tonumber(count) or 1)
  local toPos = { x = tonumber(toX), y = tonumber(toY), z = tonumber(toZ) }
  if toPos.x == nil or toPos.y == nil or toPos.z == nil then return false end
  for _, container in pairs(g_game.getContainers()) do
    if container.getItem and container.getItemsCount then
      for slot = 0, container:getItemsCount() - 1 do
        local item = container:getItem(slot)
        if item and item.getId and item:getId() == id then
          local maxCount = item.getCount and item:getCount() or 1
          local moveQty = math.min(cnt, maxCount)
          pcall(function() g_game.move(item, toPos, moveQty) end)
          return true
        end
      end
    end
  end
  return false
end

function scripts.executeScript(code, onComplete)
  if not code or type(code) ~= "string" then return false, "invalid code" end

  local env = {}
  env.g_game = g_game
  env.g_ui = g_ui
  env.g_map = g_map
  env.g_clock = g_clock
  local scheduledCount = 0
  local SCHEDULED_MAX = (g_helperCore and g_helperCore.getScriptMaxScheduledCount) and g_helperCore.getScriptMaxScheduledCount() or 50
  env.scheduleEvent = function(f, delay)
    if scheduledCount >= SCHEDULED_MAX then return nil end
    scheduledCount = scheduledCount + 1
    return scheduleEvent(function()
      scheduledCount = scheduledCount - 1
      if scheduledCount < 0 then scheduledCount = 0 end
      if type(f) == "function" then pcall(f) end
    end, delay or 0)
  end
  env.pcall = pcall
  env.pairs = pairs
  env.ipairs = ipairs
  env.next = next
  env.type = type
  env.tonumber = tonumber
  env.tostring = tostring
  env.string = string
  env.table = table
  env.math = math
  env._VERSION = _VERSION
  env.bit = bit
  env.tr = tr
  env.clickSelectButton = scripts.clickSelectButton
  env.getFreeCapacity = function()
    return scripts.getFreeCapacity()
  end
  env.hasEnoughCap = function(minCap)
    local cap = scripts.getFreeCapacity()
    if cap == nil then return false end
    return cap >= (tonumber(minCap) or 0)
  end
  env.getItemCount = function(itemId)
    return scripts.getItemCount(itemId) or 0
  end
  env.getHealth = function() return scripts.getHealth() end
  env.getMana = function() return scripts.getMana() end
  env.getMaxHealth = function() return scripts.getMaxHealth() end
  env.getMaxMana = function() return scripts.getMaxMana() end
  env.getHealthPercent = function() return scripts.getHealthPercent() end
  env.getManaPercent = function() return scripts.getManaPercent() end
  env.getLevel = function() return scripts.getLevel() end
  env.getPosition = function() return scripts.getPosition() end
  env.getCreaturesNearby = function(range) return scripts.getCreaturesNearby(range) end
  env.hasLessCreaturesNearby = function(maxCount, range) return scripts.hasLessCreaturesNearby(maxCount, range) end
  env.modalAnswer = function(id, buttonId, choice, closeAfterAnswer)
    return scripts.modalAnswer(id, buttonId, choice, closeAfterAnswer)
  end
  env.DirectionNorth = 0
  env.DirectionEast = 1
  env.DirectionSouth = 2
  env.DirectionWest = 3
  env.say = function(text)
    return scripts.say(text)
  end
  env.useItem = function(itemId)
    return scripts.useItem(itemId)
  end
  env.useItemOn = function(itemIdUsed, itemIdTarget)
    return scripts.useItemOn(itemIdUsed, itemIdTarget)
  end
  env.npcTradeBuy = function(itemRef, quantity)
    return scripts.npcTradeBuy(itemRef, quantity)
  end
  env.npcTradeSell = function(itemRef, quantity)
    return scripts.npcTradeSell(itemRef, quantity)
  end
  env.closeNpcTradeWindow = function()
    return scripts.closeNpcTradeWindow()
  end
  env.KeyEnter = 5
  env.KeyEscape = 1
  env.KeyUp = 14
  env.KeyDown = 15
  env.KeyLeft = 16
  env.KeyRight = 17
  env.KeySpace = 32
  env.simulateKey = function(keyCode)
    if not g_ui or not g_ui.getKeyboardReceiver then return false end
    local receiver = g_ui.getKeyboardReceiver()
    if not receiver or not receiver.simulateKeyDown then return false end
    local mod = 0
    pcall(function()
      receiver:simulateKeyDown(keyCode, mod)
      receiver:simulateKeyPress(keyCode, mod, 0)
      receiver:simulateKeyUp(keyCode, mod)
    end)
    return true
  end
  env.moveItem = function(...) return scripts.moveItem(...) end
  env.moveItemById = function(itemId, toX, toY, toZ, count)
    return scripts.moveItemById(itemId, toX, toY, toZ, count)
  end
  env.gotoid = function(id)
    if modules.game_helper and modules.game_helper.cavebot and modules.game_helper.cavebot.gotoid then
      return modules.game_helper.cavebot.gotoid(id)
    end
    return false
  end
  if g_helperCore and g_helperCore.filterScriptEnv then
    env = g_helperCore.filterScriptEnv(env)
  end
  env.getCreaturesNearby = function(range) return scripts.getCreaturesNearby(range) end
  env.hasLessCreaturesNearby = function(maxCount, range) return scripts.hasLessCreaturesNearby(maxCount, range) end
  env.useItemOn = function(itemIdUsed, itemIdTarget) return scripts.useItemOn(itemIdUsed, itemIdTarget) end
  local WAIT_MAX_MS = (g_helperCore and g_helperCore.getScriptMaxWaitMs) and g_helperCore.getScriptMaxWaitMs() or 5000
  env.wait = function() end

  local function compileChunk(chunkCode)
    local fn, err
    if loadstring then
      fn, err = loadstring(chunkCode, "=(script)")
    else
      fn, err = load(chunkCode, "=(script)", "t", env)
    end
    if not fn then return nil, err end
    if setfenv and env then setfenv(fn, env) end
    return fn, nil
  end

  local steps = {}
  local current = {}
  local hasWait = false
  for line in (code .. "\n"):gmatch("(.-)\r?\n") do
    local ms = line:match("^%s*wait%s*%(%s*(%-?%d+)%s*%)%s*;?%s*$")
    if ms then
      local chunk = table.concat(current, "\n")
      if chunk:match("%S") then
        table.insert(steps, { code = chunk })
      end
      local delay = tonumber(ms) or 0
      if g_helperCore and g_helperCore.clampScriptWaitMs then
        delay = g_helperCore.clampScriptWaitMs(delay)
      else
        if delay < 0 then delay = 0 end
        if delay > WAIT_MAX_MS then delay = WAIT_MAX_MS end
      end
      table.insert(steps, { waitMs = delay })
      current = {}
      hasWait = true
    else
      table.insert(current, line)
    end
  end
  local lastChunk = table.concat(current, "\n")
  if lastChunk:match("%S") then
    table.insert(steps, { code = lastChunk })
  end

  if not hasWait then
    local fn, err = compileChunk(code)
    if not fn then return false, err end
    local ok, runErr = pcall(fn)
    if not ok and runErr and modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      pcall(function() modules.game_textmessage.displayFailureMessage(tostring(runErr)) end)
    end
    if type(onComplete) == "function" then onComplete() end
    return ok
  end

  local index = 1
  local function runNext()
    if index > #steps then
      if type(onComplete) == "function" then onComplete() end
      return
    end
    local step = steps[index]
    index = index + 1
    if step.waitMs ~= nil then
      scheduleEvent(runNext, step.waitMs)
      return
    end
    if step.code and step.code:match("%S") then
      local fn, err = compileChunk(step.code)
      if not fn then
        if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
          pcall(function() modules.game_textmessage.displayFailureMessage(tostring(err)) end)
        end
        if type(onComplete) == "function" then onComplete() end
        return
      end
      local ok, runErr = pcall(fn)
      if not ok then
        if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
          pcall(function() modules.game_textmessage.displayFailureMessage(tostring(runErr)) end)
        end
        if type(onComplete) == "function" then onComplete() end
        return
      end
      if runErr == false then
        if type(onComplete) == "function" then onComplete() end
        return
      end
    end
    scheduleEvent(runNext, 0)
    return
  end
  scheduleEvent(runNext, 0)
  return true
end

local function findActiveScriptById(id)
  for i, entry in ipairs(activeScripts) do
    if entry.id == id then return i, entry end
  end
  return nil, nil
end

function scripts.runActiveScriptLoop(id)
  local idx, entry = findActiveScriptById(id)
  if not entry or not entry.code or entry.code == "" then return end
  local function scheduleNext()
    entry.loopEvent = scheduleEvent(function() scripts.runActiveScriptLoop(id) end, ACTIVE_SCRIPT_INTERVAL_MS)
  end
  scripts.executeScript(entry.code, scheduleNext)
end

function scripts.addToActive(name, code, startImmediately)
  nextActiveScriptId = nextActiveScriptId + 1
  local id = nextActiveScriptId
  local entry = { name = name or "Script", code = code or "", id = id, loopEvent = nil }
  table.insert(activeScripts, entry)
  if startImmediately ~= false then
    local delay = (id % 10) * ACTIVE_SCRIPT_STAGGER_MS
    entry.loopEvent = scheduleEvent(function() scripts.runActiveScriptLoop(id) end, delay)
  end
end

function scripts.saveScriptWithName(name, code, replaceIndex)
  local cfg = getHelperConfig()
  if not cfg then return end
  if not cfg.scripts then cfg.scripts = {} end
  name = name or "Script"
  code = code or ""
  if replaceIndex and replaceIndex >= 1 and replaceIndex <= #cfg.scripts then
    cfg.scripts[replaceIndex] = { name = name, code = code }
  else
    table.insert(cfg.scripts, { name = name, code = code })
  end
  if _Helper and _Helper.saveSettings then _Helper.saveSettings() end
end

function scripts.runSavedScript()
  if not selectedSavedIndex then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select a script first."))
    end
    return
  end
  local idx = selectedSavedIndex

  local cfg = getHelperConfig()
  if not cfg or not cfg.scripts or not cfg.scripts[idx] then return end
  local s = cfg.scripts[idx]
  local code = (type(s) == "table" and s.code) or s
  local name = (type(s) == "table" and s.name) or ("Script " .. idx)
  local ok, err = scripts.executeScript(code)
  if ok then
    scripts.addToActive(name, code)
    scripts.loadToUI()
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(tr("Script executed."))
    end
  else
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Error: ") .. tostring(err))
    end
  end
end

function scripts.deleteSavedScript()
  if not selectedSavedIndex then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select a script first."))
    end
    return
  end
  local idx = selectedSavedIndex
  local cfg = getHelperConfig()
  if not cfg then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Could not access config."))
    end
    return
  end
  if not cfg.scripts then cfg.scripts = {} end
  if idx < 1 or idx > #cfg.scripts then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Invalid script index."))
    end
    return
  end
  table.remove(cfg.scripts, idx)
  if _Helper and _Helper.saveSettings then _Helper.saveSettings() end
  if selectedSavedIndex == idx then
    selectedSavedIndex = nil
  elseif selectedSavedIndex > idx then
    selectedSavedIndex = selectedSavedIndex - 1
  end
  scripts.loadToUI()
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Script deleted."))
  end
end

function scripts.saveActiveScript()
  if not selectedActiveIndex or not activeScripts[selectedActiveIndex] then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select an active script first."))
    end
    return
  end
  local idx = selectedActiveIndex

  local s = activeScripts[idx]
  local name = s.name or ("Script " .. os.date("%H%M%S"))
  scripts.saveScriptWithName(name, s.code)
  scripts.loadToUI()
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Script saved."))
  end
end

function scripts.editSavedScript()
  if not selectedSavedIndex then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select a script first."))
    end
    return
  end
  local cfg = getHelperConfig()
  if not cfg or not cfg.scripts or not cfg.scripts[selectedSavedIndex] then return end
  local s = cfg.scripts[selectedSavedIndex]
  local name = (type(s) == "table" and s.name) or ("Script " .. selectedSavedIndex)
  local code = (type(s) == "table" and s.code) or ""
  editingSavedIndex = selectedSavedIndex
  editingActiveIndex = nil
  scripts.openEditor(code, name)
end

function scripts.editActiveScript()
  if not selectedActiveIndex or not activeScripts[selectedActiveIndex] then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select an active script first."))
    end
    return
  end
  editingActiveIndex = selectedActiveIndex
  editingSavedIndex = nil
  local s = activeScripts[selectedActiveIndex]
  scripts.openEditor(s.code or "", s.name or "")
end

function scripts.startActiveScript()
  if not selectedActiveIndex or not activeScripts[selectedActiveIndex] then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select an active script first."))
    end
    return
  end
  local entry = activeScripts[selectedActiveIndex]
  if entry.loopEvent then
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(tr("Script is already running."))
    end
    return
  end
  local id = entry.id
  if not entry.code or entry.code == "" then return end
  scripts.executeScript(entry.code)
  entry.loopEvent = scheduleEvent(function() scripts.runActiveScriptLoop(id) end, ACTIVE_SCRIPT_INTERVAL_MS)
  scripts.loadToUI()
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Script started."))
  end
end

function scripts.stopActiveScript()
  if not selectedActiveIndex then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select an active script first."))
    end
    return
  end
  local entry = activeScripts[selectedActiveIndex]
  if not entry then return end
  if entry.loopEvent then
    removeEvent(entry.loopEvent)
    entry.loopEvent = nil
  end
  scripts.loadToUI()
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Script stopped."))
  end
end

function scripts.stopAllActiveScripts()
  local count = 0
  for _, entry in ipairs(activeScripts) do
    if entry and entry.loopEvent then
      removeEvent(entry.loopEvent)
      entry.loopEvent = nil
      count = count + 1
    end
  end
  scripts.loadToUI()
  if count > 0 and modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("All scripts stopped."))
  end
end

function scripts.toggleAllActiveScripts()
  local running = {}
  local runningCount = 0
  for _, entry in ipairs(activeScripts) do
    if entry and entry.loopEvent then
      running[entry.id] = true
      runningCount = runningCount + 1
    end
  end

  if runningCount > 0 then
    lastToggleRunningIds = running
    scripts.stopAllActiveScripts()
    return
  end

  local toStart = lastToggleRunningIds
  local started = 0

  for _, entry in ipairs(activeScripts) do
    if entry and not entry.loopEvent and entry.code and entry.code ~= "" then
      if (next(toStart) == nil) or toStart[entry.id] == true then
        local delay = (entry.id % 10) * ACTIVE_SCRIPT_STAGGER_MS
        entry.loopEvent = scheduleEvent(function() scripts.runActiveScriptLoop(entry.id) end, delay)
        started = started + 1
      end
    end
  end

  scripts.loadToUI()
  if started > 0 then
    lastToggleRunningIds = {}
    if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
      modules.game_textmessage.displayStatusMessage(tr("All scripts started."))
    end
  end
end

function scripts.removeActiveScript()
  if not selectedActiveIndex then
    if modules.game_textmessage and modules.game_textmessage.displayFailureMessage then
      modules.game_textmessage.displayFailureMessage(tr("Select an active script first."))
    end
    return
  end
  local idx = selectedActiveIndex
  local entry = activeScripts[idx]
  if entry and entry.loopEvent then
    removeEvent(entry.loopEvent)
    entry.loopEvent = nil
  end
  table.remove(activeScripts, idx)
  if selectedActiveIndex == idx then
    selectedActiveIndex = nil
  elseif selectedActiveIndex > idx then
    selectedActiveIndex = selectedActiveIndex - 1
  end
  if lastExecutedActiveIndex == idx then
    lastExecutedActiveIndex = nil
  elseif lastExecutedActiveIndex and lastExecutedActiveIndex > idx then
    lastExecutedActiveIndex = lastExecutedActiveIndex - 1
  end
  if editingActiveIndex == idx then
    editingActiveIndex = nil
  elseif editingActiveIndex and editingActiveIndex > idx then
    editingActiveIndex = editingActiveIndex - 1
  end
  scripts.loadToUI()
  if modules.game_textmessage and modules.game_textmessage.displayStatusMessage then
    modules.game_textmessage.displayStatusMessage(tr("Script removed from active."))
  end
end

function scripts.closeEditor()
  lastExecutedActiveIndex = nil
  if editorWindow and not editorWindow:isDestroyed() then
    editorWindow:hide()
  end
end

function scripts.openDocWindow()
  local root = g_ui.getRootWidget()
  if not root then return end
  if docWindow and not docWindow:isDestroyed() then
    docWindow:show()
    docWindow:raise()
    local docText = docWindow:recursiveGetChildById('docText')
    if docText then docText:setText(SCRIPT_LIB_DOC) end
    return
  end
  docWindow = g_ui.createWidget('ScriptsDocWindow', root)
  if not docWindow then return end
  local docText = docWindow:recursiveGetChildById('docText')
  if docText then
    docText:setText(SCRIPT_LIB_DOC)
    if docText.setEditable then docText:setEditable(false) end
  end
  docWindow.onDestroy = function()
    docWindow = nil
  end
  docWindow:show()
end

function scripts.closeDocWindow()
  if docWindow and not docWindow:isDestroyed() then
    docWindow:hide()
  end
end

function scripts.init(helperWindow)
  scriptsPanelContainer = helperWindow and helperWindow.contentPanel and helperWindow.contentPanel:getChildById('scriptsPanelContainer') or nil
  savedScriptsList = nil
  activeScriptsList = nil
  activeScripts = {}
  bindScriptsPanelButtons()
  scripts.loadToUI()
end

function scripts.terminate()
  for _, entry in ipairs(activeScripts) do
    if entry and entry.loopEvent then
      removeEvent(entry.loopEvent)
    end
  end
  if editorWindow and not editorWindow:isDestroyed() then
    editorWindow:destroy()
  end
  editorWindow = nil
  scriptCodeEdit = nil
  if docWindow and not docWindow:isDestroyed() then
    docWindow:destroy()
  end
  docWindow = nil
  scriptsPanelContainer = nil
  savedScriptsList = nil
  activeScriptsList = nil
  activeScripts = {}
end

return scripts
