# HowTo: Implement BTCBot Features in the Helper

## Overview

This guide covers five BTCBot features that are absent from the Helper and explains exactly how to port each one. Each section references the relevant BTCBot source, describes what needs to change in `helper.lua` and `helperConfig`, and provides the implementation code.

**Features covered:**

1. Ring/Amulet Auto-Swap (BTCEquipment)
2. Per-Character JSON Config (BTCConfig)
3. Condition Cures (BTCTools)
4. Time-Based Item Usage (BTCTime)
5. Priority and Ignore Lists for Auto-Target (BTCAttack)

---

## Feature 1: Ring/Amulet Auto-Swap

### Reference
- **BTCBot file:** `mods/game_bot/btcbot/equipment.lua`
- **Module:** `BTCEquipment`
- **Key functions:** `BTCEquipment.execute()`, `BTCEquipment.equipItem()`, `BTCEquipment.unequipItem()`, `BTCEquipment.findItemInContainers()`, `BTCEquipment.getEquippedItem()`

### What the Feature Does
Each slot in the config defines an item (ring or amulet), a condition (HP% or MP%), and a threshold. When the condition value falls to or below the threshold, the item is equipped from the backpack. When it rises above, the item is moved back to the backpack. There are 4 independent slots (2 ring, 2 amulet by default). The action cooldown is 500ms per slot.

### Inventory Slot Constants (from `equipment.lua` lines 51–59)
```lua
SLOT_NECKLACE = 2   -- amulet
SLOT_FINGER   = 9   -- ring
```
These are the `InventorySlot` enum values used with `player:getInventoryItem(slot)` and the destination position `{x=65535, y=slot, z=0}` for `g_game.move()`.

### Step 1: Add to `helperConfig`

In `helper.lua`, inside the `helperConfig` table definition (around line 134), add:

```lua
helperConfig.equipment = {
  { enabled=false, itemId=0, type="ring",   condition="life", threshold=80 },
  { enabled=false, itemId=0, type="ring",   condition="life", threshold=50 },
  { enabled=false, itemId=0, type="amulet", condition="life", threshold=80 },
  { enabled=false, itemId=0, type="amulet", condition="mana", threshold=50 },
}
```

### Step 2: Add the Event to `eventTable`

In the `eventTable` definition (around line 71):

```lua
eventTable.checkEquipment = { interval = 500, action = nil }
```

### Step 3: Implement `checkEquipment()`

Add this function after the other check functions in `helper.lua`. Place it before the `eventTable.checkEquipment.action = checkEquipment` assignment.

```lua
-- Inventory slot IDs for equipment
local EQUIP_SLOT_RING   = 9
local EQUIP_SLOT_AMULET = 2

local equipLastAction = {}

local function getEquipInventorySlot(slotType)
  if slotType == "ring"   then return EQUIP_SLOT_RING   end
  if slotType == "amulet" then return EQUIP_SLOT_AMULET end
  return nil
end

local function findItemForEquip(itemId)
  for _, container in pairs(g_game.getContainers()) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == itemId then
        return item, container
      end
    end
  end
  return nil, nil
end

local function findOpenContainerForUnequip()
  for _, container in pairs(g_game.getContainers()) do
    if container:getItemsCount() < container:getCapacity() then
      return container
    end
  end
  -- Fallback: return first container even if full
  for _, container in pairs(g_game.getContainers()) do
    return container
  end
  return nil
end

function checkEquipment()
  if not hotkeyHelperStatus then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local hpPct = (localPlayer:getHealth() / localPlayer:getMaxHealth()) * 100
  local mpPct = (localPlayer:getMana()   / localPlayer:getMaxMana())   * 100
  local now   = g_clock.millis()

  for i, slot in ipairs(helperConfig.equipment) do
    if not slot.enabled or slot.itemId == 0 then goto continue end

    -- Per-slot 500ms cooldown (mirrors BTCEquipment.actionCooldown)
    if (now - (equipLastAction[i] or 0)) < 500 then goto continue end

    local currentPct  = (slot.condition == "mana") and mpPct or hpPct
    local inventorySlot = getEquipInventorySlot(slot.type)
    if not inventorySlot then goto continue end

    local equipped = localPlayer:getInventoryItem(inventorySlot)

    if currentPct <= slot.threshold then
      -- EQUIP: only if the right item is not already in the slot
      if not equipped or equipped:getId() ~= slot.itemId then
        local item = findItemForEquip(slot.itemId)
        if item then
          -- Destination: inventory slot position
          local destPos = { x=65535, y=inventorySlot, z=0 }
          g_game.move(item, destPos, 1)
          equipLastAction[i] = now
        end
      end
    else
      -- UNEQUIP: only if our item is currently equipped
      if equipped and equipped:getId() == slot.itemId then
        local container = findOpenContainerForUnequip()
        if container then
          -- Move to first open slot in container
          local destPos = container:getSlotPosition(container:getItemsCount())
          g_game.move(equipped, destPos, 1)
          equipLastAction[i] = now
        end
      end
    end

    ::continue::
  end
end

eventTable.checkEquipment.action = checkEquipment
```

### Step 4: Add UI

In the helper's tools panel (alongside the existing training and haste rows), add 4 rows. Each row contains:

| Control | Purpose |
|---------|---------|
| Item sprite button | Opens item picker, sets `slot.itemId` |
| Dropdown: ring / amulet | Sets `slot.type` |
| Dropdown: life / mana | Sets `slot.condition` |
| Numeric stepper (0–100) | Sets `slot.threshold` |
| Enable checkbox | Sets `slot.enabled` |

Save to `helperConfig.equipment[i]` on any change, then call `saveSettings()`.

### Key Functions to Port from BTCEquipment

| BTCEquipment function | Helper equivalent |
|-----------------------|-------------------|
| `BTCEquipment.findItemInContainers(id)` | `findItemForEquip(id)` (above) |
| `BTCEquipment.getEquippedItem(type)` | `localPlayer:getInventoryItem(slot)` |
| `BTCEquipment.equipItem(i, slot)` | Move with `g_game.move(item, destPos, 1)` |
| `BTCEquipment.unequipItem(i, slot)` | Move equipped item back to container |
| `BTCEquipment.getInventorySlot(type)` | `getEquipInventorySlot(type)` (above) |
| `BTCEquipment.canAct(i)` | `(now - equipLastAction[i]) < 500` |

---

## Feature 2: Per-Character JSON Config

### Reference
- **BTCBot file:** `mods/game_bot/btcbot/config.lua`
- **Module:** `BTCConfig`
- **Key functions:** `BTCConfig.getCharName()`, `BTCConfig.loadForCurrentChar()`, `BTCConfig.save()`, `BTCConfig.checkCharacterChange()`
- **Storage:** Single file `/btcbot_settings.json` containing all characters as a top-level JSON object: `{ "CharName": { ... }, ... }`

### What the Feature Does
Settings are keyed by character name. Each character has independent bot config. When the player logs in (or changes character), the correct config loads automatically.

### How BTCConfig Works (config.lua lines 1–119)

```
loadAll()              → reads the entire JSON file into BTCConfig.allData
loadForCurrentChar()   → copies allData[charName] into BTCConfig.data
get(key)               → reads BTCConfig.data[key]
set(key, value)        → writes BTCConfig.data[key], then calls save()
save()                 → encodes allData (with current char updated) back to JSON file
checkCharacterChange() → detects if getName() != currentCharName, calls loadForCurrentChar()
```

### Step 1: Modify `saveSettings()`

Find the existing `saveSettings()` function in `helper.lua` and replace its body:

```lua
function saveSettings()
  local charName = "default"
  if g_game.isOnline() then
    local p = g_game.getLocalPlayer()
    if p then charName = p:getName() end
  end

  local filePath = "/helper_settings.json"

  -- Load existing data for other characters
  local allData = {}
  if g_resources.fileExists(filePath) then
    local ok, decoded = pcall(json.decode, g_resources.readFileContents(filePath))
    if ok and type(decoded) == "table" then
      allData = decoded
    end
  end

  -- Build saveable config (strip non-serializable values)
  local saveableConfig = deepCopy(helperConfig)
  -- Reset runtime-only values
  saveableConfig.currentLockedTargetId = 0

  allData[charName] = saveableConfig

  local ok, err = pcall(function()
    g_resources.writeFileContents(filePath, json.encode(allData, 2))
  end)
  if not ok then
    print("[Helper] Error saving settings: " .. tostring(err))
  end
end
```

### Step 2: Modify `loadSettings()`

Find the existing `loadSettings()` function and replace its body:

```lua
function loadSettings()
  local charName = "default"
  if g_game.isOnline() then
    local p = g_game.getLocalPlayer()
    if p then charName = p:getName() end
  end

  local filePath = "/helper_settings.json"
  if not g_resources.fileExists(filePath) then return end

  local ok, allData = pcall(json.decode, g_resources.readFileContents(filePath))
  if not ok or type(allData) ~= "table" then
    print("[Helper] Error loading settings: invalid JSON")
    return
  end

  local charData = allData[charName]
  if not charData then
    print("[Helper] No saved config for character: " .. charName)
    return
  end

  -- Deep merge: preserve defaults for keys not present in saved data
  for k, v in pairs(charData) do
    if type(v) == "table" and type(helperConfig[k]) == "table" then
      for k2, v2 in pairs(v) do
        helperConfig[k][k2] = v2
      end
    else
      helperConfig[k] = v
    end
  end

  print("[Helper] Config loaded for: " .. charName)
end
```

### Step 3: Hook into Game Start

In the `online()` function (called from `onGameStart`), add a call to `loadSettings()` so the correct character config loads at login:

```lua
function online()
  player = g_game.getLocalPlayer()
  loadSettings()   -- ADD THIS LINE
  -- ... rest of online() function
end
```

### Step 4: JSON File Path

The BTCBot uses `/btcbot_settings.json`. Use a separate path for the Helper to avoid conflicts:
- Helper: `/helper_settings.json`

Both files live in the OTClient user data directory (`g_resources` root).

### Migration

If existing users have settings saved in the old single-character format, detect the format on load:

```lua
-- In loadSettings(), after decoding:
if allData and not allData[charName] and allData.spells then
  -- Old flat format detected — treat it as the "default" character
  allData = { ["default"] = allData }
end
```

---

## Feature 3: Condition Cures

### Reference
- **BTCBot file:** `mods/game_bot/btcbot/tools.lua`
- **Module:** `BTCTools`
- **Cure spell list (tools.lua lines 104–110):**
  ```lua
  cureSpells = {
    { words="exana amp res", name="Remove Curse",         voc={3,4,13,14} },
    { words="exana pox",     name="Cure Poison",          voc={1,2,3,4,5,11,12,13,14,15} },
    { words="exana flam",    name="Cure Burning",         voc={1,2,3,4,11,12,13,14} },
    { words="exana vis",     name="Cure Electrification", voc={1,2,3,4,11,12,13,14} },
    { words="exana kor",     name="Cure Bleeding",        voc={1,11} },
  }
  ```
- **State constants (tools.lua lines 137–141):**
  ```lua
  local STATE_HASTE        = 64
  local STATE_MANASHIELD   = 16
  local STATE_PARALYZE     = 32
  ```
- **Condition detection:** Uses `player:getStates()` with bitwise AND.

### What the Feature Does
Polls the player's condition states every 500ms. When a curable condition is detected and the corresponding cure is enabled, the cure spell is cast (one per cycle).

### Step 1: Add Cure Config to `helperConfig`

Inside the `helperConfig` table (around line 134):

```lua
helperConfig.cures = {
  poison      = { enabled=false },
  burning     = { enabled=false },
  electrified = { enabled=false },
  bleeding    = { enabled=false },
  curse       = { enabled=false },
}
```

The spell IDs are resolved at runtime via `Spells.getSpellByClientId()`. Use the `ignoredSpellsIds` table's existing spell IDs as a reference:

| Condition | Client Spell ID (from ignoredSpellsIds) |
|-----------|----------------------------------------|
| Bleeding  | 144 |
| Electrified | 146 |
| Poison    | 29 |
| Burning   | 145 |
| Curse     | 147 |

### Step 2: Add Event

```lua
eventTable.checkCures = { interval = 500, action = nil }
```

### Step 3: Implement `checkCures()`

Player condition states are returned by `player:getStates()` as a bitmask integer. The exact bit values depend on the server protocol. Common values:

```lua
-- Verify these against the OT server's protocol implementation:
local CONDITION_POISON      = 2
local CONDITION_BURNING     = 8
local CONDITION_ELECTRIFIED = 16384
local CONDITION_BLEEDING    = 32768
local CONDITION_CURSE       = 131072
```

```lua
-- Maps condition name to { spellId, conditionBit }
local cureMap = {
  poison      = { spellId=29,  bit=CONDITION_POISON      },
  burning     = { spellId=145, bit=CONDITION_BURNING     },
  electrified = { spellId=146, bit=CONDITION_ELECTRIFIED },
  bleeding    = { spellId=144, bit=CONDITION_BLEEDING    },
  curse       = { spellId=147, bit=CONDITION_CURSE       },
}

function checkCures()
  if not hotkeyHelperStatus then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local states = localPlayer:getStates()
  if not states or states == 0 then return end

  for condName, info in pairs(cureMap) do
    local cfg = helperConfig.cures[condName]
    if cfg and cfg.enabled then
      -- Test if condition bit is set
      if bit.band(states, info.bit) ~= 0 then
        local spell = Spells.getSpellByClientId(info.spellId)
        if spell and not isSpellOnCooldown(spell) then
          if localPlayer:getMana() >= spell.mana then
            g_game.talk(spell.words, true)
            return  -- One cure per cycle to avoid spell conflicts
          end
        end
      end
    end
  end
end

eventTable.checkCures.action = checkCures
```

**Important:** The `ignoredSpellsIds` table (lines 211–233) prevents cure spells from being used as attack spells in the magic shooter. The `checkCures` function is a separate event that bypasses this restriction intentionally.

### Step 4: Add UI

In the tools panel, add a "Condition Cures" section with five checkboxes:
- [ ] Cure Poison (exana pox)
- [ ] Cure Burning (exana flam)
- [ ] Cure Electrification (exana vis)
- [ ] Cure Bleeding (exana kor)
- [ ] Remove Curse (exana amp res)

Each checkbox maps directly to `helperConfig.cures[condName].enabled`.

---

## Feature 4: Time-Based Item Usage

### Reference
- **BTCBot file:** `mods/game_bot/btcbot/time.lua`
- **Module:** `BTCTime`
- **Config structure (time.lua lines 13–22):**
  ```lua
  BTCTime.defaultConfig = {
    enabled = false,
    slots = {
      { enabled=false, itemId=0, interval=60, name="" },
      -- 5 slots total
    }
  }
  ```
- **Timers:** `BTCTime.lastUseTime = {0, 0, 0, 0, 0}` (reset on init, not persisted)
- **Execution:** `g_clock.millis() - lastUseTime[i] >= slot.interval * 1000` triggers `g_game.useInventoryItem(slot.itemId)`

### What the Feature Does
Use a specific inventory item every N seconds. Useful for enchanted items, burst arrows, special potions, or any consumable with a player-defined interval.

### Step 1: Add to `helperConfig`

```lua
helperConfig.timedItems = {
  { enabled=false, itemId=0, interval=60, name="" },
  { enabled=false, itemId=0, interval=60, name="" },
  { enabled=false, itemId=0, interval=60, name="" },
  { enabled=false, itemId=0, interval=60, name="" },
  { enabled=false, itemId=0, interval=60, name="" },
}
```

Also add a module-level enable flag:
```lua
helperConfig.timedItemsEnabled = false
```

### Step 2: Add Event

```lua
eventTable.checkTimedItems = { interval = 250, action = nil }
```

A 250ms poll interval is fine — the actual item use rate is controlled by each slot's `interval` field (in seconds).

### Step 3: Add Runtime Timer State

Add a module-level table (not persisted to JSON):
```lua
local timedItemLastUse = {}
```

Initialize it in `online()` or `init()`:
```lua
for i = 1, 5 do timedItemLastUse[i] = 0 end
```

### Step 4: Implement `checkTimedItems()`

```lua
function checkTimedItems()
  if not hotkeyHelperStatus then return end
  if not helperConfig.timedItemsEnabled then return end

  local now = g_clock.millis()

  for i, slot in ipairs(helperConfig.timedItems) do
    if not slot.enabled or slot.itemId == 0 then goto continue end
    if slot.interval <= 0 then goto continue end

    local elapsed = now - (timedItemLastUse[i] or 0)
    if elapsed >= (slot.interval * 1000) then
      -- Use the item
      g_game.useInventoryItem(slot.itemId)
      timedItemLastUse[i] = now
    end
    ::continue::
  end
end

eventTable.checkTimedItems.action = checkTimedItems
```

### Step 5: Add UI

In the tools panel, add a "Timed Items" section with 5 rows. Each row contains:

| Control | Value stored |
|---------|-------------|
| Item sprite button (opens picker) | `slot.itemId` |
| Text label (optional name) | `slot.name` |
| Interval input (seconds, min=1) | `slot.interval` |
| Enable checkbox | `slot.enabled` |

Module-level enable toggle: `helperConfig.timedItemsEnabled`

### Integration with Auto-Eat Food

The existing `autoEatFood()` function in the Helper is a specialized time-based feature. It can remain as-is, since it uses regeneration time rather than a fixed interval. The new `checkTimedItems` is for general-purpose items.

---

## Feature 5: Priority and Ignore Lists for Auto-Target

### Reference
- **BTCBot file:** `mods/game_bot/btcbot/attack.lua`
- **Config (attack.lua lines 31–33):**
  ```lua
  priorityList = {},  -- Array of creature name strings
  ignoreList   = {},  -- Array of creature name strings
  ```
- **Usage in execute():** Creature list is filtered by `ignoreList` before mode logic. Creatures in `priorityList` cause an immediate early return with that creature as the target.

### What the Feature Does
- **Ignore list:** Creatures whose name appears here are never targeted, even if they are the only visible monster.
- **Priority list:** Creatures whose name appears here are targeted before any mode logic runs. If multiple priority creatures are visible, the first match wins.

### Step 1: Add to `helperConfig`

```lua
helperConfig.creaturePriorityList = {}  -- e.g. {"Demon", "Vampire"}
helperConfig.creatureIgnoreList   = {}  -- e.g. {"Rat", "Cave Rat"}
```

These can also be stored per shooter profile if the Helper's profile system should carry them:
```lua
defaultShooterProfile.priorityList = {}
defaultShooterProfile.ignoreList   = {}
```

### Step 2: Add Helper Functions

```lua
local function isCreatureIgnored(creatureName)
  for _, name in ipairs(helperConfig.creatureIgnoreList) do
    if name == creatureName then return true end
  end
  return false
end

local function isCreaturePriority(creatureName)
  for _, name in ipairs(helperConfig.creaturePriorityList) do
    if name == creatureName then return true end
  end
  return false
end
```

### Step 3: Modify `checkAutoTarget()`

The function currently builds `creatureList` from `g_map.getSpectators()` (lines 2666–2671). After the spectators loop, add the filter and priority check.

**Filtering (add after building `creatureList`):**
```lua
-- Filter out ignored creatures before mode logic
local filteredList = {}
for _, cd in ipairs(creatureList) do
  if not isCreatureIgnored(cd.creature:getName()) then
    table.insert(filteredList, cd)
  end
end
creatureList = filteredList  -- Replace for all subsequent processing
```

**Priority check (add before the `closestTarget`/`farthestTarget` loop):**
```lua
-- Check priority list first — attack immediately if a priority target is in reach
for _, priorityName in ipairs(helperConfig.creaturePriorityList) do
  for _, cd in ipairs(creatureList) do
    if cd.creature:getName() == priorityName then
      local pos = cd.position
      if isWithinReach(position, pos) and g_map.isSightClear(position, pos) then
        local current = g_game.getAttackingCreature()
        if not current or current:getId() ~= cd.creature:getId() then
          g_game.attack(cd.creature)
        end
        return  -- Priority target found — skip mode selection
      end
    end
  end
end

-- Continue with normal mode selection using filtered creatureList...
```

**Full modified function structure:**
```
checkAutoTarget()
  1. Guards (hotkeyHelperStatus, autoTargetEnabled, autoTargetOnHold, PZ, locked target)
  2. Build spectators list → creatureList (monsters only)
  3. Filter: remove ignored creatures
  4. Check priority list → early return if priority creature in reach
  5. Single-pass mode loop (existing code, but over filtered creatureList)
  6. Mode selection → g_game.attack(target)
```

### Step 4: Add UI

In the shooter panel or a dedicated sub-panel, add two scrollable list widgets:

**Priority List:**
```
[+] [Input: creature name] [Add]
List:
  "Demon"    [X Remove]
  "Vampire"  [X Remove]
```

**Ignore List:**
```
[+] [Input: creature name] [Add]
List:
  "Rat"      [X Remove]
  "Cave Rat" [X Remove]
```

Each "Add" button does:
```lua
local name = inputWidget:getText()
if name ~= "" then
  table.insert(helperConfig.creaturePriorityList, name)
  saveSettings()
  refreshListWidget()
end
```

Each "Remove" button does:
```lua
table.remove(helperConfig.creaturePriorityList, index)
saveSettings()
refreshListWidget()
```

The lists should be preserved per shooter profile if that integration is desired. In that case, store them in `helperConfig.shooterProfiles[profileName].priorityList` and `ignoreList`, and read them via `getShooterProfile()` inside `checkAutoTarget()`.

---

## Summary Table

| Feature | helperConfig key | New event | Event interval | BTCBot source |
|---------|-----------------|-----------|----------------|---------------|
| Equipment auto-swap | `equipment` array | `checkEquipment` | 500ms | equipment.lua |
| Per-char JSON config | (modifies save/load) | none | on login | config.lua |
| Condition cures | `cures` table | `checkCures` | 500ms | tools.lua |
| Timed item usage | `timedItems` array | `checkTimedItems` | 250ms | time.lua |
| Priority/ignore lists | `creaturePriorityList`, `creatureIgnoreList` | (modifies checkAutoTarget) | — | attack.lua |
