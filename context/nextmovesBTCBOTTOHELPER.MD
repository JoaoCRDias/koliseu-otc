# Melhorias do BTCBot para o Helper — Features a Importar

This document catalogs features that exist in BTCBot but are absent or significantly weaker in the Helper. For each feature, the source location in BTCBot is identified, the current gap in the Helper is described, and a concrete implementation path is outlined.

---

## 1. Ring/Amulet Auto-Swap System

### What It Is
Automatically equips or unequips a ring or amulet based on the player's current HP% or MP%. When the stat drops below the configured threshold the item is moved from the backpack to the equipment slot; when it recovers above the threshold the item is returned to the backpack.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/equipment.lua`
- **Module:** `BTCEquipment`
- **Key functions:** `BTCEquipment.execute()`, `BTCEquipment.equipItem()`, `BTCEquipment.unequipItem()`, `BTCEquipment.findItemInContainers()`, `BTCEquipment.getEquippedItem()`
- **Config structure:**
  ```lua
  BTCEquipment.defaultConfig = {
    enabled = false,
    slots = {
      { enabled=false, itemId=0, type="ring",   condition="life", threshold=80 },
      { enabled=false, itemId=0, type="ring",   condition="life", threshold=50 },
      { enabled=false, itemId=0, type="amulet", condition="life", threshold=80 },
      { enabled=false, itemId=0, type="amulet", condition="mana", threshold=50 },
    }
  }
  -- Inventory slot constants:
  -- SLOT_FINGER = 9   (ring)
  -- SLOT_NECKLACE = 2 (amulet)
  ```
- **Execution interval:** 500ms cooldown per slot action (`BTCEquipment.actionCooldown = 500`)

### What the Helper Currently Lacks
The Helper has no equipment automation whatsoever. The user must manually drag rings and amulets to and from equipment slots. There is no entry in `helperConfig` for equipment slots, and `eventTable` has no equipment event.

### How to Implement in the Helper

**Step 1 — Extend `helperConfig`:**
```lua
helperConfig.equipment = {
  { enabled=false, itemId=0, type="ring",   condition="life", threshold=80 },
  { enabled=false, itemId=0, type="ring",   condition="life", threshold=50 },
  { enabled=false, itemId=0, type="amulet", condition="life", threshold=80 },
  { enabled=false, itemId=0, type="amulet", condition="mana", threshold=50 },
}
```

**Step 2 — Add an event to `eventTable`:**
```lua
eventTable.checkEquipment = { interval = 500, action = nil }
```

**Step 3 — Implement `checkEquipment()`:**
```lua
local equipLastAction = {}
local SLOT_FINGER    = 9
local SLOT_NECKLACE  = 2

local function getInventorySlotForType(slotType)
  if slotType == "ring"   then return SLOT_FINGER end
  if slotType == "amulet" then return SLOT_NECKLACE end
  return nil
end

local function findItemInContainers(itemId)
  for _, container in pairs(g_game.getContainers()) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == itemId then return item end
    end
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
    if (now - (equipLastAction[i] or 0)) < 500 then goto continue end

    local currentPct = (slot.condition == "mana") and mpPct or hpPct
    local invSlot    = getInventorySlotForType(slot.type)
    if not invSlot then goto continue end

    local equipped = localPlayer:getInventoryItem(invSlot)

    if currentPct <= slot.threshold then
      -- Need to equip
      if not equipped or equipped:getId() ~= slot.itemId then
        local item = findItemInContainers(slot.itemId)
        if item then
          g_game.move(item, {x=65535, y=invSlot, z=0}, 1)
          equipLastAction[i] = now
        end
      end
    else
      -- Need to unequip
      if equipped and equipped:getId() == slot.itemId then
        local containers = g_game.getContainers()
        for _, container in pairs(containers) do
          if container:getItemsCount() < container:getCapacity() then
            local destPos = container:getPosition()
            g_game.move(equipped, {x=65535, y=64+container:getId(), z=container:getItemsCount()}, 1)
            equipLastAction[i] = now
            break
          end
        end
      end
    end
    ::continue::
  end
end

eventTable.checkEquipment.action = checkEquipment
```

**Step 4 — Add UI:** Four rows in the tools panel, each with an item picker (item ID), a type dropdown (ring/amulet), a condition dropdown (life/mana), and a numeric threshold field.

---

## 2. CaveBot / Waypoint Navigation

### What It Is
A full waypoint-based navigation system. The user records a path (or enters coordinates manually), then the bot walks the path automatically, interacting with stairs/ropes/holes, looping the route, and pausing when monsters are present.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/cavebot.lua`
- **Module:** `BTCCaveBot`
- **Waypoint types:** `walk`, `use`, `usewith`, `label`, `stand`, `rope`, `shovel`, `stairs`
- **Key config fields:** `waypoints`, `currentIndex`, `loopEnabled`, `minMonstersToStop`
- **Stuck detection:** `BTCCaveBot.stuckCount`, `BTCCaveBot.samePositionCount` — resets to waypoint 1 after 30 failures (~3s)
- **Recording:** `BTCCaveBot.recordingEnabled` flag + `onMove` callback stores each new tile

### What the Helper Currently Lacks
The Helper has no navigation automation of any kind. It is a purely reactive bot (healing, attacking, casting) with no ability to move the character.

### How to Implement in the Helper
This is the largest new module. It should be built as a separate sub-module (`helperCaveBot`) following the same pattern as BTCBot.

**Step 1 — Data structure:**
```lua
helperConfig.cavebot = {
  enabled         = false,
  waypoints       = {},      -- { type, x, y, z, extra }
  currentIndex    = 1,
  loopEnabled     = true,
  minMonstersToStop = 1,
}
```

**Step 2 — Event:**
```lua
eventTable.checkCaveBot = { interval = 200, action = nil }
```

**Step 3 — Recording:** Connect to `onWalk` or poll player position every tick. If recording is active and the player moved at least 1 tile, append a `walk` waypoint.

**Step 4 — Execution loop:**
```lua
function checkCaveBot()
  if not hotkeyHelperStatus then return end
  local cfg = helperConfig.cavebot
  if not cfg.enabled or #cfg.waypoints == 0 then return end

  -- Pause if monsters present
  local localPlayer = g_game.getLocalPlayer()
  local pos = localPlayer:getPosition()
  if cfg.minMonstersToStop > 0 then
    local specs = g_map.getSpectators(pos, false)
    local monsterCount = 0
    for _, c in pairs(specs) do
      if c:isMonster() then monsterCount = monsterCount + 1 end
    end
    if monsterCount >= cfg.minMonstersToStop then return end
  end

  local wp = cfg.waypoints[cfg.currentIndex]
  if not wp then return end

  if wp.type == "walk" then
    -- Use pathfinder or single-step walk
    walkToPosition({x=wp.x, y=wp.y, z=wp.z})
  elseif wp.type == "use" then
    local tile = g_map.getTile({x=wp.x, y=wp.y, z=wp.z})
    if tile then g_game.useWith(tile:getTopUseThing(), nil) end
  elseif wp.type == "rope" then
    -- Use rope on hole
  elseif wp.type == "shovel" then
    -- Use shovel on dirt
  end

  -- Advance when arrived
  if positionCompare(pos, {x=wp.x, y=wp.y, z=wp.z}) then
    cfg.currentIndex = cfg.currentIndex + 1
    if cfg.currentIndex > #cfg.waypoints then
      cfg.currentIndex = cfg.loopEnabled and 1 or #cfg.waypoints
    end
  end
end
```

**Step 5 — Stuck detection:** Track last position each tick; if the same position persists for 30 cycles, reset `currentIndex = 1`.

---

## 3. Dedicated Mana Module

### What It Is
A standalone mana-potion module with its own 3 slots, independent cooldown, and independent enable toggle. Mana is treated as a first-class concern separate from HP healing.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/mana.lua`
- **Module:** `BTCMana`
- **Config:**
  ```lua
  BTCMana.defaultConfig = {
    enabled = true,
    slot1 = { enabled=true,  itemId=268,   mpPercent=80 },
    slot2 = { enabled=false, itemId=238,   mpPercent=60 },
    slot3 = { enabled=false, itemId=23373, mpPercent=40 },
  }
  ```
- **Cooldown:** `BTCMana.manaCooldown = 1000` ms (independent from healing)

### What the Helper Currently Lacks
The Helper merges mana potions into the general `checkHealthHealing` / `checkMana` flow. The `checkMana` event (100ms interval) runs independently but the config slots for mana are stored alongside health potions in `helperConfig.potions`. Health evaluation takes priority in `checkHealthPriority()`, which means under heavy HP damage mana potions can be delayed or skipped.

There is no independent enable/disable for mana recovery separate from the global `hotkeyHelperStatus`.

### How to Implement in the Helper

**Step 1 — Add dedicated mana config (separate from `potions`):**
```lua
helperConfig.manaSlots = {
  { id=0, percent=80, enabled=false },
  { id=0, percent=60, enabled=false },
  { id=0, percent=40, enabled=false },
}
helperConfig.manaEnabled = true
```

**Step 2 — Separate the mana event:**
The existing `eventTable.checkMana` at 100ms can remain but its action should be replaced with a dedicated function that reads `helperConfig.manaSlots` rather than mixing logic with health potions.

```lua
function checkManaDedicated()
  if not hotkeyHelperStatus then return end
  if not helperConfig.manaEnabled then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local mpPct = (localPlayer:getMana() / localPlayer:getMaxMana()) * 100

  for _, slot in ipairs(helperConfig.manaSlots) do
    if slot.enabled and slot.id ~= 0 and mpPct <= slot.percent then
      -- Check potion exhaustion using potionConfig
      -- g_game.useInventoryItem(slot.id)
      break
    end
  end
end
```

**Step 3 — Add a "Mana" enable toggle button** in the healing panel alongside the existing health spell/potion controls.

---

## 4. Per-Character Config Persistence

### What It Is
Configurations are saved to a JSON file keyed by character name. When the player logs in with a different character, the bot automatically loads that character's saved settings instead of using a shared config.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/config.lua`
- **Module:** `BTCConfig`
- **Key functions:**
  - `BTCConfig.getCharName()` — returns `player:getName()` or `"default"`
  - `BTCConfig.loadForCurrentChar()` — loads from `BTCConfig.allData[charName]`
  - `BTCConfig.save()` — encodes `allData` (all chars) to `/btcbot_settings.json`
  - `BTCConfig.checkCharacterChange()` — called each tick; reloads if char name changed
- **Storage:** Single JSON file `btcbot_settings.json`, structure: `{ "CharName1": {...}, "CharName2": {...} }`

### What the Helper Currently Lacks
The Helper's `saveSettings()` and `loadSettings()` functions save/load a single shared config. There is no key by character name, so the same config is used for every character on every account.

### How to Implement in the Helper

**Step 1 — Modify `saveSettings()`:**
```lua
function saveSettings()
  local charName = "default"
  if g_game.isOnline() then
    local p = g_game.getLocalPlayer()
    if p then charName = p:getName() end
  end

  local filePath = "/helper_settings.json"
  local allData = {}

  -- Load existing data first (other chars)
  if g_resources.fileExists(filePath) then
    local ok, decoded = pcall(json.decode, g_resources.readFileContents(filePath))
    if ok and type(decoded) == "table" then allData = decoded end
  end

  allData[charName] = helperConfig
  g_resources.writeFileContents(filePath, json.encode(allData, 2))
end
```

**Step 2 — Modify `loadSettings()`:**
```lua
function loadSettings()
  local charName = "default"
  if g_game.isOnline() then
    local p = g_game.getLocalPlayer()
    if p then charName = p:getName() end
  end

  local filePath = "/helper_settings.json"
  if g_resources.fileExists(filePath) then
    local ok, allData = pcall(json.decode, g_resources.readFileContents(filePath))
    if ok and allData and allData[charName] then
      -- Merge loaded config into helperConfig (deep merge)
      for k, v in pairs(allData[charName]) do
        helperConfig[k] = v
      end
    end
  end
end
```

**Step 3 — Auto-reload on character change:** Call `loadSettings()` inside the `onGameStart` / `online()` handler, which already fires when a character logs in.

---

## 5. Support Spell Condition Cures

### What It Is
Automatically detects when the player has a harmful status condition (poisoned, burning, electrified, bleeding, cursed) and casts the appropriate cure spell.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/tools.lua`
- **Module:** `BTCTools`
- **Cure spell list:**
  ```lua
  cureSpells = {
    { words="exana amp res", name="Remove Curse",         voc={3,4,13,14} },
    { words="exana pox",     name="Cure Poison",          voc={1,2,3,4,5,11,12,13,14,15} },
    { words="exana flam",    name="Cure Burning",         voc={1,2,3,4,11,12,13,14} },
    { words="exana vis",     name="Cure Electrification", voc={1,2,3,4,11,12,13,14} },
    { words="exana kor",     name="Cure Bleeding",        voc={1,11} },
  }
  ```
- **Condition detection:** Via player state bitmask constants:
  ```lua
  local STATE_PARALYZE = 32
  -- Others checked via player:getStates() bit operations
  ```

### What the Helper Currently Lacks
The Helper has no condition-cure logic. The `ignoredSpellsIds` table explicitly excludes cure spells (IDs 144, 146, 29, 145, 147) from the magic shooter, meaning they cannot even be configured as attack spells.

### How to Implement in the Helper

**Step 1 — Add cure config to `helperConfig`:**
```lua
helperConfig.cures = {
  poison      = { enabled=false, spellId=29  },
  burning     = { enabled=false, spellId=145 },
  electrified = { enabled=false, spellId=146 },
  bleeding    = { enabled=false, spellId=144 },
  curse       = { enabled=false, spellId=147 },
}
```

**Step 2 — Add event:**
```lua
eventTable.checkCures = { interval = 500, action = nil }
```

**Step 3 — Implement `checkCures()`:** Map condition name to the player state constant and check `player:getStates()`.

```lua
-- Condition bit flags (OTClient protocol values)
local CONDITION_BITS = {
  poison      = 2,
  burning     = 8,
  electrified = 16384,
  bleeding    = 32768,
  curse       = 131072,
}

function checkCures()
  if not hotkeyHelperStatus then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local states = localPlayer:getStates()

  for condName, cfg in pairs(helperConfig.cures) do
    if cfg.enabled and cfg.spellId ~= 0 then
      local bit = CONDITION_BITS[condName]
      if bit and (states and bit.band(states, bit) ~= 0) then
        local spell = Spells.getSpellByClientId(cfg.spellId)
        if spell and not isSpellOnCooldown(spell) then
          g_game.talk(spell.words, true)
          return  -- One cure per cycle
        end
      end
    end
  end
end

eventTable.checkCures.action = checkCures
```

**Note:** Verify the exact bit values against the server's protocol implementation for this OT.

---

## 6. Familiar Summons

### What It Is
Automatically re-summons the player's vocation-specific familiar when it has expired or is absent.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/tools.lua`
- **Module:** `BTCTools`
- **Familiar spells:**
  ```lua
  familiars = {
    { words="utevo res dru", name="Summon Grovebeast",   voc={4,14}, duration=900000 },
    { words="utevo res sor", name="Summon Skullfrost",   voc={3,13}, duration=900000 },
    { words="utevo res kni", name="Summon Emberwing",    voc={1,11}, duration=900000 },
    { words="utevo res pal", name="Summon Thundergiant", voc={2,12}, duration=900000 },
  }
  ```
- Triggered as part of `BTCTools.execute()` when `config.familiar.enabled` is true

### What the Helper Currently Lacks
No familiar automation. The haste whitelist (`hasteWhiteList`) only handles speed spells by vocation; there is no parallel structure for familiars.

### How to Implement in the Helper

**Step 1 — Add to `helperConfig`:**
```lua
helperConfig.familiar = { enabled=false }
```

**Step 2 — Add logic inside `checkAutoHaste()`** or as a new `checkFamiliar` event (1000ms interval):

```lua
local familiarSpells = {
  [1]  = "utevo res kni", [11] = "utevo res kni",
  [2]  = "utevo res pal", [12] = "utevo res pal",
  [3]  = "utevo res sor", [13] = "utevo res sor",
  [4]  = "utevo res dru", [14] = "utevo res dru",
}

function checkFamiliar()
  if not hotkeyHelperStatus then return end
  if not helperConfig.familiar.enabled then return end
  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer then return end

  local voc = localPlayer:getVocation()
  local words = familiarSpells[voc]
  if not words then return end

  -- Check if familiar is already summoned (scan spectators for creature owned by player)
  local pos = localPlayer:getPosition()
  local specs = g_map.getSpectators(pos, false)
  for _, c in pairs(specs) do
    if c:isSummon() and c:getMaster() == localPlayer then return end
  end

  -- Cast familiar spell
  local spell = Spells.getSpellByWords(words)
  if spell and not isSpellOnCooldown(spell) then
    if localPlayer:getMana() >= spell.mana then
      g_game.talk(words, true)
    end
  end
end
```

---

## 7. Advanced Friend Healing

### What It Is
A configurable friend-healing module with a named friend list, party awareness, multiple spell slots with different HP thresholds, priority ordering, and mass healing support.

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/healfriend.lua`
- **Module:** `BTCHealFriend`
- **Config:**
  ```lua
  BTCHealFriend.defaultConfig = {
    enabled = false,
    healParty = true,
    healFriendList = {},   -- Array of character names
    slot1 = { enabled=true,  spell="exura sio",         hpPercent=70, priority=1 },
    slot2 = { enabled=true,  spell="exura sio",         hpPercent=40, priority=2 },
    slot3 = { enabled=false, spell="exura gran mas res", hpPercent=60, minFriendsInRange=2 },
  }
  ```
- Each slot has an independent enable flag, an HP threshold, and a priority value.

### What the Helper Currently Lacks
The Helper has `friendhealing` and `gransiohealing` arrays (2 slots each), each with `name`, `percent`, and `enabled`. This covers the basic use case, but:

- No `healParty` toggle — the party scan is always active when the player is a party member
- No mass healing slot with `minFriendsInRange` logic
- No priority ordering across friend + party targets
- Friend names must be entered individually; there is no bulk import

### Improvement Path
1. Add a `healParty` boolean to `helperConfig` to allow disabling party scanning independently.
2. Add a third healing slot (`gransio2`) or unify all friend healing slots into a single array with priority fields.
3. Add `minFriendsInRange` to the mass-heal slot so it only fires when enough allies are nearby.
4. Add a party scan loop that iterates all party members (not just named friends) and picks the one with the lowest HP that is below threshold.

---

## 8. Modular On/Off Per Feature

### What It Is
Each major module (healing, mana, attack, tools, equipment, cavebot) has its own independent `enabled` flag and a matching UI toggle button. Disabling one module does not affect the others.

### Where It Is in BTCBot
Every BTCBot module stores `enabled` in its config:
```lua
BTCAttack.defaultConfig   = { enabled = true,  ... }
BTCMana.defaultConfig     = { enabled = true,  ... }
BTCTools.defaultConfig    = { enabled = false, ... }
BTCEquipment.defaultConfig= { enabled = false, ... }
BTCCaveBot.defaultConfig  = { enabled = false, ... }
BTCHealFriend.defaultConfig={ enabled = false, ... }
```
Each module's `execute()` checks its own `config.enabled` first.

### What the Helper Currently Lacks
The Helper has a single global toggle: `hotkeyHelperStatus` (bound to the Pause key). Every event function checks `if not hotkeyHelperStatus then return end` at the top. There is no way to, for example, keep healing active while disabling the auto-target.

The only sub-feature toggles present are:
- `helperConfig.magicShooterEnabled`
- `helperConfig.autoTargetEnabled`
- `helperConfig.autoEatFood`
- `helperConfig.autoChangeGold`
- Per-slot `enabled` in `helperConfig.haste` and `helperConfig.friendhealing`

### Implementation
**Step 1 — Add feature flags to `helperConfig`:**
```lua
helperConfig.features = {
  healingEnabled    = true,
  manaEnabled       = true,
  friendHealEnabled = true,
  hasteEnabled      = true,
  curesEnabled      = false,
  equipmentEnabled  = false,
  familiarEnabled   = false,
  cavebotEnabled    = false,
}
```

**Step 2 — Guard each event with its feature flag:**
```lua
function checkHealthHealing()
  if not hotkeyHelperStatus then return end
  if not helperConfig.features.healingEnabled then return end
  -- ...
end
```

**Step 3 — Add individual toggle buttons** in the helper UI for each feature, separate from the global on/off.

---

## 9. Time-Based Item Usage

### What It Is
Use a configurable item from the inventory on a fixed timer interval (e.g., use a burst arrow every 5 seconds, use an enchanted item every 30 seconds).

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/time.lua`
- **Module:** `BTCTime`
- **Config:** 5 slots, each with `itemId`, `interval` (seconds), `enabled`, `name`
- **Execution:** Checks `g_clock.millis() - lastUseTime[i] >= slot.interval * 1000`, then calls `g_game.useInventoryItem(slot.itemId)`

### What the Helper Currently Lacks
No time-based item usage. The exercise dummy training (`checkTrainingSpell`) is interval-based but is specific to training weapons on dummies, not general item use.

### How to Implement in the Helper

**Step 1 — Add to `helperConfig`:**
```lua
helperConfig.timedItems = {
  { enabled=false, itemId=0, interval=60, lastUsed=0 },
  { enabled=false, itemId=0, interval=60, lastUsed=0 },
  { enabled=false, itemId=0, interval=60, lastUsed=0 },
  { enabled=false, itemId=0, interval=60, lastUsed=0 },
  { enabled=false, itemId=0, interval=60, lastUsed=0 },
}
```

**Step 2 — Add event:**
```lua
eventTable.checkTimedItems = { interval = 250, action = nil }
```

**Step 3 — Implement:**
```lua
function checkTimedItems()
  if not hotkeyHelperStatus then return end
  local now = g_clock.millis()
  for i, slot in ipairs(helperConfig.timedItems) do
    if slot.enabled and slot.itemId ~= 0 then
      if (now - (slot.lastUsed or 0)) >= (slot.interval * 1000) then
        g_game.useInventoryItem(slot.itemId)
        slot.lastUsed = now
      end
    end
  end
end

eventTable.checkTimedItems.action = checkTimedItems
```

**Note:** `lastUsed` should not be persisted to the saved config (reset to 0 on load) to avoid stale timestamps after restarts.

---

## 10. Attack Targeting: Priority and Ignore Lists

### What It Is
Two creature-name lists that filter what the auto-targeter selects:
- **Priority list:** Always target these creatures first, regardless of mode
- **Ignore list:** Never target these creatures

### Where It Is in BTCBot
- **File:** `mods/game_bot/btcbot/attack.lua`
- **Config:**
  ```lua
  BTCAttack.defaultConfig = {
    priorityList = {},   -- Array of creature name strings
    ignoreList   = {},   -- Array of creature name strings
    -- ...
  }
  ```
- In `BTCAttack.execute()`: the creature list is filtered by `ignoreList` before any mode logic; creatures in `priorityList` are promoted to the front.

### What the Helper Currently Lacks
`checkAutoTarget()` builds `creatureList` from `g_map.getSpectators()` without any name-based filtering. Every visible monster on the same floor within reach is a candidate. There is no way to skip trash mobs or to prioritize named bosses.

### How to Implement in the Helper

**Step 1 — Add to `helperConfig` (inside or alongside `shooterProfiles`):**
```lua
helperConfig.creaturePriorityList = {}  -- e.g. {"Demon", "Medusa"}
helperConfig.creatureIgnoreList   = {}  -- e.g. {"Rat", "Cave Rat"}
```

**Step 2 — Filter in `checkAutoTarget()`:**

Before the main loop over `specs`, add:

```lua
-- Build filtered creature list
local filteredSpecs = {}
for i, creature in pairs(specs) do
  if creature:isMonster() then
    local name = creature:getName()
    -- Check ignore list
    local ignored = false
    for _, ignoredName in ipairs(helperConfig.creatureIgnoreList) do
      if name == ignoredName then ignored = true; break end
    end
    if not ignored then
      table.insert(filteredSpecs, creature)
    end
  end
end

-- Check priority list first
for _, priorityName in ipairs(helperConfig.creaturePriorityList) do
  for _, creature in ipairs(filteredSpecs) do
    if creature:getName() == priorityName then
      local pos = creature:getPosition()
      if isWithinReach(position, pos) and g_map.isSightClear(position, pos) then
        if not (currentTarget and currentTarget:getId() == creature:getId()) then
          g_game.attack(creature)
        end
        return  -- Priority target found — skip mode logic
      end
    end
  end
end

-- Continue with normal mode logic using filteredSpecs
```

**Step 3 — Add UI:** Two scrollable text lists in the shooter panel (or a dedicated sub-panel) for adding/removing creature names to each list.
