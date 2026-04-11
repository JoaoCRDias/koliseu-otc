# Melhorias do Helper para o BTCBot — Features a Importar

This document catalogs features that exist in the Helper but are absent or significantly weaker in BTCBot. For each feature, the source location in the Helper is identified, the current gap in BTCBot is described, and a concrete implementation path is outlined.

---

## 1. Eight+ Auto-Target Modes (checkAutoTarget)

### What It Is
A mode-based auto-targeting system that selects attack targets using one of nine distinct strategies, computed from a single pass over the visible creature list.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Function:** `checkAutoTarget()` (lines 2614–2752)
- **Mode table (line 14):**

| Mode | Value | Behavior |
|------|-------|----------|
| A | 1 | Closest target |
| B | 2 | Farthest target |
| C | 3 | Lowest HP% target |
| D | 4 | Highest HP% target |
| E | 5 | Best AoE position (max creatures in circle) |
| F | 6 | Closest + lowest HP (default) |
| G | 7 | Closest + highest HP |
| H | 8 | Farthest + lowest HP |
| I | 9 | Farthest + highest HP |

- **Algorithm:** All nine candidate variables are updated in a single `for` loop over `creatureList`. Mode E uses `countAttackableCreatures()` with `SpellAreas.AREA_CIRCLE3X3` (or `AREA_CIRCLE2X2` for paladins by vocation check).
- **Per-profile storage:** `defaultShooterProfile.autoTargetMode` stores the mode per shooter profile.

### What BTCBot Currently Lacks
`BTCAttack.execute()` calls `g_game.attack(target)` on the closest or first visible monster. There is no `targetMode` field in `BTCAttack.defaultConfig`, no multi-category variable tracking, and no AoE-efficiency calculation.

### How to Implement in BTCBot

**Step 1 — Add `targetMode` to `BTCAttack.defaultConfig`:**
```lua
BTCAttack.defaultConfig = {
  -- existing fields ...
  targetMode = "F",  -- Default: closest + lowest HP
}
```

**Step 2 — Port `getAttackableCreaturesSmart()`** (adapted from the Helper's `checkAutoTarget` loop):
```lua
function BTCAttack.getAttackableCreaturesSmart(playerPos, creatureList)
  local closest         = { id=nil, distance=99 }
  local farthest        = { id=nil, distance=-1 }
  local lowestHP        = { id=nil, health=100 }
  local highestHP       = { id=nil, health=-1 }
  local closestLowest   = { id=nil, distance=99,  health=100 }
  local closestHighest  = { id=nil, distance=99,  health=-1  }
  local farthestLowest  = { id=nil, distance=-1,  health=100 }
  local farthestHighest = { id=nil, distance=-1,  health=-1  }
  local bestAoE         = { id=nil, creatures=0 }

  local area = SpellAreas and SpellAreas.AREA_CIRCLE3X3 or nil

  for _, cd in ipairs(creatureList) do
    local creature = cd.creature
    local pos      = cd.position
    if not isWithinReach(playerPos, pos) then goto continue end
    if not g_map.isSightClear(playerPos, pos) then goto continue end

    local dist   = math.max(math.abs(playerPos.x - pos.x), math.abs(playerPos.y - pos.y))
    local health = creature:getHealthPercent()

    if lowestHP.id == nil then lowestHP = { id=creature:getId(), health=health } end
    if health < lowestHP.health        then lowestHP        = { id=creature:getId(), health=health } end
    if health > highestHP.health       then highestHP       = { id=creature:getId(), health=health } end
    if dist   < closest.distance       then closest         = { id=creature:getId(), distance=dist } end
    if dist   > farthest.distance      then farthest        = { id=creature:getId(), distance=dist } end

    if dist < closestLowest.distance or (dist == closestLowest.distance and health < closestLowest.health) then
      closestLowest = { id=creature:getId(), distance=dist, health=health }
    end
    if dist < closestHighest.distance or (dist == closestHighest.distance and health > closestHighest.health) then
      closestHighest = { id=creature:getId(), distance=dist, health=health }
    end
    if dist > farthestLowest.distance or (dist == farthestLowest.distance and health < farthestLowest.health) then
      farthestLowest = { id=creature:getId(), distance=dist, health=health }
    end
    if dist > farthestHighest.distance or (dist == farthestHighest.distance and health > farthestHighest.health) then
      farthestHighest = { id=creature:getId(), distance=dist, health=health }
    end

    if area then
      local hits = countAttackableCreatures(pos, 1, area, creatureList, true)
      if hits > bestAoE.creatures then
        bestAoE = { id=creature:getId(), creatures=hits }
      end
    end
    ::continue::
  end

  return {
    A = closest, B = farthest, C = lowestHP, D = highestHP, E = bestAoE,
    F = closestLowest, G = closestHighest, H = farthestLowest, I = farthestHighest,
  }
end
```

**Step 3 — Use in `BTCAttack.execute()`:**
```lua
local results = BTCAttack.getAttackableCreaturesSmart(playerPos, creatureList)
local mode    = BTCAttack.config.targetMode or "F"
local chosen  = results[mode]
if chosen and chosen.id then
  local target = g_map.getCreatureById(chosen.id)
  if target then g_game.attack(target) end
end
```

**Step 4 — Add ComboBox to BTCAttack UI:**
```
Mode A – Closest
Mode B – Farthest
Mode C – Lowest HP
Mode D – Highest HP
Mode E – Best AoE
Mode F – Closest + Lowest HP  (default)
Mode G – Closest + Highest HP
Mode H – Farthest + Lowest HP
Mode I – Farthest + Highest HP
```

---

## 2. Magic Shooter with Priority + Creature Count

### What It Is
A spell-casting system where each slot has: a minimum mana%, a minimum creature count threshold, a priority ordering, a `forceCast` flag (bypass creature count), and a `selfCast` flag (cast at self, not target). Slots are sorted by priority before evaluation each cycle.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Function:** `checkMagicShooter()` (lines 2424–2612)
- **Profile config (lines 37–50):**
  ```lua
  defaultShooterProfile = {
    spells = {
      { id=0, percent=0, creatures=1, priority=1, forceCast=false, selfCast=false },
      -- up to 5 spell slots
    },
    runes = {
      { id=0, creatures=1, priority=6, forceCast=false },
      -- 2 rune slots
    },
    autoTargetMode = autoTargetModes['F']
  }
  ```
- **Sorting:** `sortMagicShooterByPriority(unifiedList)` orders spells + runes by their `priority` field.
- **Creature count:** `countAttackableCreatures()` checks how many creatures fall within the spell's AoE area. The slot fires only if `reachableCreatures >= config.creatures`.
- **selfCast:** If true and the spell has a range, cast at self position (for self-target buffs used mid-combat).
- **forceCast:** If true, bypass the `creaturesAround > 1` safety check.

### What BTCBot Currently Lacks
`BTCAttack.defaultConfig.spells` has 6 slots. Each slot tracks `lastUsed` and `cooldown`, but there is no `creatures` count check, no `priority` field for slot ordering, and no `forceCast`/`selfCast` flags. Spells are tried in array order (slot 1 first) regardless of mana or creature conditions.

### How to Implement in BTCBot

**Step 1 — Extend each spell slot in `BTCAttack.defaultConfig`:**
```lua
spells = {
  {
    enabled=false, type="spell", words="", cooldown=2000,
    manaCost=0, spellId=0, iconId=0, itemId=0, lastUsed=0,
    -- NEW FIELDS:
    mpPercent   = 0,       -- Minimum mana% to cast
    creatures   = 1,       -- Minimum creatures in AoE
    priority    = 1,       -- Lower number = higher priority
    forceCast   = false,   -- Ignore creature count check
    selfCast    = false,   -- Target self instead of attack target
  },
  -- repeat for all 6 slots with priority 1-6
}
```

**Step 2 — Sort before execution:**
```lua
local function sortByPriority(spells)
  table.sort(spells, function(a, b) return (a.priority or 99) < (b.priority or 99) end)
  return spells
end
```

**Step 3 — Add creature count logic:**
```lua
-- Inside BTCAttack.execute(), after checking cooldown:
if slot.creatures > 1 and SpellAreas then
  local area = SpellAreas.AREA_CIRCLE3X3
  local hits = countAttackableCreatures(targetPos, 1, area, creatureList, true)
  if hits < slot.creatures and not slot.forceCast then
    goto continue
  end
end
```

**Step 4 — Add mana% check:**
```lua
local mpPct = (player:getMana() / player:getMaxMana()) * 100
if mpPct < (slot.mpPercent or 0) then goto continue end
```

---

## 3. Shooter Profiles — Save/Load Named Configs

### What It Is
Multiple named shooter profiles that can be created, renamed, deleted, and switched at runtime. Each profile independently stores all spell slots, rune slots, and the auto-target mode. A hotkey cycles through saved profiles.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Config (lines 160–163):**
  ```lua
  helperConfig.shooterProfiles = {
    ["Default"] = defaultShooterProfile
  }
  helperConfig.selectedShooterProfile = "Default"
  ```
- **Profile switching:** `toggleShooterPreset()` function, bound to the "Change Shooter Preset" keybind.
- **Profile access:** `getShooterProfile()` returns `helperConfig.shooterProfiles[helperConfig.selectedShooterProfile]`.

### What BTCBot Currently Lacks
`BTCAttack.config` is a flat structure — one config per character. There is no concept of multiple named profiles, no profile selector in the UI, and no hotkey to cycle between them.

### How to Implement in BTCBot

**Step 1 — Restructure `BTCAttack.config`:**
```lua
BTCAttack.defaultConfig = {
  enabled = true,
  -- ...other fields...
  selectedProfile = "Default",
  profiles = {
    ["Default"] = {
      spells   = { -- 6 spell slots -- },
      priorityList = {},
      ignoreList   = {},
      targetMode   = "F",
    }
  }
}
```

**Step 2 — Helper function:**
```lua
function BTCAttack.getActiveProfile()
  local name = BTCAttack.config.selectedProfile or "Default"
  return BTCAttack.config.profiles[name]
end
```

**Step 3 — UI:** Add a ComboBox populated from `BTCAttack.config.profiles` keys, with "New Profile", "Rename", and "Delete" buttons. On selection change, reload the spell slot widgets from the chosen profile.

**Step 4 — Hotkey:** Register a keybind that calls:
```lua
function BTCAttack.cycleProfile()
  local names = {}
  for k in pairs(BTCAttack.config.profiles) do table.insert(names, k) end
  table.sort(names)
  local current = BTCAttack.config.selectedProfile
  for i, name in ipairs(names) do
    if name == current then
      local next = names[(i % #names) + 1]
      BTCAttack.config.selectedProfile = next
      BTCAttack.saveConfig()
      -- Refresh UI
      return
    end
  end
end
```

---

## 4. SpellAreas — AoE Pattern Calculation

### What It Is
A module that defines AoE patterns as 2D area tables and provides two utility functions: `countAttackableCreatures()` (how many creatures a spell hits at a given position/direction) and `findBestTarget()` (which position maximizes creatures hit). Used by both `checkMagicShooter` and `checkAutoTarget`.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua` and a separate `SpellAreas` module referenced via `SpellAreas.AREA_CIRCLE3X3`, `SpellAreas.AREA_CIRCLE2X2`, etc.
- **Usage in `checkAutoTarget` (line 2659):**
  ```lua
  local area = SpellAreas.AREA_CIRCLE3X3
  if translateVocation(myCharacter:getVocation()) == 7 then  -- Paladin
    area = SpellAreas.AREA_CIRCLE2X2
  end
  ```
- **Usage in `checkMagicShooter` (lines 2542–2553):** `countAttackableCreatures()` is called for every spell with a defined `spell.area` to determine how many creatures fall within range.
- **`findBestTarget()` (lines 2587–2590):** Iterates possible target positions and returns the one with the maximum creature hit count.

### What BTCBot Currently Lacks
No `SpellAreas` module reference, no `countAttackableCreatures()` function, no `findBestTarget()` function. `BTCAttack.execute()` fires spells at the current attack target without any AoE efficiency consideration.

### How to Implement in BTCBot

**Step 1 — Ensure `SpellAreas` is accessible:** If the module is already loaded globally in the client, simply reference it. Otherwise, copy the area definitions into `BTCAttack`.

**Step 2 — Port `countAttackableCreatures()`** from `helper.lua` into a shared utility or directly into `btcbot.lua`:
```lua
-- Count how many creatures from creatureList are hit by area centered at pos
function BTCAttack.countCreaturesInArea(centerPos, direction, area, creatureList, useDirection)
  -- Delegates to the existing SpellAreas + creatureList logic
  -- (copy implementation from helper.lua countAttackableCreatures)
  return countAttackableCreatures(centerPos, direction, area, creatureList, useDirection)
end
```

**Step 3 — Port `findBestTarget()`:** Iterate each creature position as a potential AoE center, call `countCreaturesInArea`, return the position with the most hits.

**Step 4 — Use in attack slot evaluation** when `slot.creatures > 1` (see Feature 2 above).

---

## 5. Auto-Eat Food

### What It Is
Automatically uses food items from the player's inventory when the regeneration timer drops to 500ms or less. Supports 39 consumable food IDs and 9 infinite-use food items.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Function:** `autoEatFood()` (called from `routineChecks` event, 1000ms interval)
- **Config flag:** `helperConfig.autoEatFood = false`
- **Food IDs (lines 175–186):**
  - 39 regular food items (`foodIds` table): 3577–23545 range
  - 9 infinite food items (`infiniteFoodIds` table): 61615–63723 range
- **Logic:** `player:getRegenerationTime() <= 500` triggers a scan of open containers for a matching food ID, then calls `g_game.use(item)`.

### What BTCBot Currently Lacks
No food automation whatsoever. `BTCTools` has no food entry, and `BTCTime` could be used manually but requires the user to configure the item ID and interval — it does not check regeneration time.

### How to Implement in BTCBot

**Option A — Add to `BTCTools`:**
```lua
-- In BTCTools.defaultConfig:
autoEatFood = { enabled = false }

-- New function in BTCTools:
function BTCTools.checkAutoEatFood()
  if not BTCTools.config.autoEatFood.enabled then return end
  local player = g_game.getLocalPlayer()
  if not player then return end
  if player:getRegenerationTime() > 500 then return end

  -- Try infinite food first
  for _, id in ipairs(infiniteFoodIds) do
    local item = player:getInventoryItem(id)  -- or scan containers
    if item then g_game.use(item); return end
  end
  -- Then regular food
  for _, id in ipairs(foodIds) do
    -- scan containers
    for _, container in pairs(g_game.getContainers()) do
      for slot = 0, container:getItemsCount() - 1 do
        local item = container:getItem(slot)
        if item and item:getId() == id then
          g_game.use(item); return
        end
      end
    end
  end
end
```

**Option B — Add to `BTCTime`:** Add a dedicated "food" slot that checks regeneration time instead of a fixed interval.

The `foodIds` and `infiniteFoodIds` arrays can be copied directly from `helper.lua` lines 175–186.

---

## 6. Auto-Change Gold

### What It Is
Converts stacks of 100 gold coins to platinum coins automatically by calling `g_game.use()` on a stack of 100 gold.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Function:** `autoChangeGold()` (called from `routineChecks` event, 1000ms interval)
- **Config flag:** `helperConfig.autoChangeGold = false`
- **Item IDs (line 203):** `moneyIds = { 3031, 3035 }` (gold coin, platinum coin)
- **Logic:** Scans containers for item ID 3031 (gold coin); if a stack of count >= 100 is found, calls `g_game.use(item)` which triggers the server-side conversion.

### What BTCBot Currently Lacks
No gold management. This is a pure quality-of-life feature with no combat implications.

### How to Implement in BTCBot
Add to `BTCTools` config and execution:
```lua
-- In BTCTools.defaultConfig:
autoChangeGold = { enabled = false }

-- In BTCTools.execute() or a new periodic check:
function BTCTools.checkAutoChangeGold()
  if not BTCTools.config.autoChangeGold.enabled then return end
  for _, container in pairs(g_game.getContainers()) do
    for slot = 0, container:getItemsCount() - 1 do
      local item = container:getItem(slot)
      if item and item:getId() == 3031 and item:getCount() >= 100 then
        g_game.use(item)
        return
      end
    end
  end
end
```

---

## 7. Exercise Dummy Training

### What It Is
Detects exercise dummies on the map, moves to one if needed, and uses a training weapon on it when the player's mana exceeds a configured threshold. This keeps training active during downtime.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Function:** `checkTrainingSpell()` via `eventTable.checkExerciseEvent` (10000ms interval)
- **Config:** `helperConfig.training = { {id=0, percent=0, enabled=false} }`
- **Dummy IDs (lines 188–193):** 30 exercise dummy object IDs (28558–63713)
- **Exercise weapon IDs (lines 195–201):** 34 training weapon IDs (28552–63492)
- **Logic:** If `player:getMana() / player:getMaxMana() * 100 >= slot.percent`, scan surrounding tiles for a dummy, then call `g_game.useWith(exerciseWeapon, dummy)`.

### What BTCBot Currently Lacks
No training automation. `BTCTools` handles buff spells and cure spells but nothing related to exercise dummies.

### How to Implement in BTCBot
Create a new `BTCTraining` module or add to `BTCTools`:
```lua
-- Add to BTCTools.defaultConfig:
training = {
  enabled    = false,
  weaponId   = 0,    -- Training weapon item ID
  mpPercent  = 100,  -- Only train when mana >= this %
}

-- Execution:
function BTCTools.checkTraining()
  if not BTCTools.config.training.enabled then return end
  local player = g_game.getLocalPlayer()
  if not player then return end

  local mpPct = (player:getMana() / player:getMaxMana()) * 100
  if mpPct < BTCTools.config.training.mpPercent then return end

  -- Find training weapon in inventory
  local weapon = findItemInContainers(BTCTools.config.training.weaponId)
  if not weapon then return end

  -- Find exercise dummy on visible tiles
  local playerPos = player:getPosition()
  local specs = g_map.getSpectators(playerPos, false)
  -- (scan tile objects for exercise dummy IDs, use g_game.useWith)
end
```

The `exerciseDummies` and `exercises` ID tables can be copied from `helper.lua` lines 188–201.

---

## 8. selfCast / forceCast Flags

### What It Is
Per-spell-slot flags that modify firing behavior:
- `selfCast`: Cast the spell targeting self (player's own position) rather than the current attack target.
- `forceCast`: Ignore the minimum creature count requirement and fire regardless.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Defined in `defaultShooterProfile` (line 39):**
  ```lua
  { id=0, percent=0, creatures=1, priority=1, forceCast=false, selfCast=false }
  ```
- **Used in `checkMagicShooter()` (lines 2516–2560):**
  - `selfCast` causes the function to skip the `not target` guard and use `castOnFoot=true`
  - `forceCast` bypasses the `creaturesAround > 1` safety check

### What BTCBot Currently Lacks
No such flags in `BTCAttack.defaultConfig.spells` slots.

### How to Implement in BTCBot
Add `forceCast` and `selfCast` to each spell slot definition (see Feature 2 above for the full slot structure). In `BTCAttack.execute()`:
```lua
-- selfCast: use player's own position as the target
if slot.selfCast then
  g_game.talk(slot.words, true)  -- talk with castOnFoot equivalent
  goto continue
end

-- forceCast: skip creature count check
if not slot.forceCast and slot.creatures > 1 then
  -- ... creature count logic
end
```

---

## 9. Harmony Point Gate

### What It Is
A pre-cast check for certain spells that require the player to have at least 5 Harmony points. If `spell.spender` is true and `player:getHarmony() < 5`, the spell is skipped.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Check in `checkMagicShooter()` (lines 2491, 2525–2527):**
  ```lua
  local harmonyCount = player:getHarmony()
  -- ...
  if spell.spender and harmonyCount < 5 then
    goto continue
  end
  ```
- The `spender` field is part of the spell data returned by `Spells.getSpellByClientId()`.

### What BTCBot Currently Lacks
`BTCAttack.execute()` checks mana cost but has no awareness of Harmony points. Spells with a `spender` flag would fire and fail server-side if harmony is insufficient.

### How to Implement in BTCBot
In `BTCAttack.execute()`, before calling `g_game.talk()`:
```lua
-- Check harmony requirement
local spellData = SpellInfo and SpellInfo["Default"] and SpellInfo["Default"][slot.spellId]
if spellData and spellData.spender then
  local player = g_game.getLocalPlayer()
  if player and player:getHarmony() < 5 then
    goto continue
  end
end
```

This requires the `spellData.spender` flag to be present in the `SpellInfo` table populated at login.

---

## 10. Follow Detection → Auto-Disable Shooter

### What It Is
If the player is currently following a creature (`g_game.getFollowingCreature()` returns non-nil), the magic shooter is automatically disabled and a notification message is shown.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Check in `checkMagicShooter()` (lines 2452–2460):**
  ```lua
  local following = g_game.getFollowingCreature()
  if following then
    local widget = enableButtons:recursiveGetChildById("enableMagicShooter")
    if widget then
      widget:setChecked(false)
      toggleMagicShooter(widget, "Follow detected!\nRTCaster disabled.")
      return
    end
  end
  ```

### What BTCBot Currently Lacks
`BTCAttack.execute()` has no follow detection. If the player manually follows a creature while the bot is active, spells continue to fire.

### How to Implement in BTCBot
Add at the top of `BTCAttack.execute()`:
```lua
-- Disable attack if player is following
if g_game.getFollowingCreature() then
  -- Optionally auto-disable: BTCAttack.config.enabled = false; BTCAttack.saveConfig()
  -- Or just skip this cycle silently:
  return
end
```

Whether to permanently disable or just skip the cycle depends on desired UX. The Helper permanently disables and shows a notification; a softer approach would be to skip silently and resume when following stops.

---

## 11. PZ Auto-Disable Per Feature

### What It Is
When the player enters a Protection Zone, each feature that should not operate in PZ automatically disables itself (with a status message).

### Where It Is in the Helper
- **`checkMagicShooter()` (lines 2432–2439):**
  ```lua
  if myCharacter:isInProtectionZone() then
    -- Unchecks the magic shooter button and calls toggleMagicShooter()
  end
  ```
- **`checkAutoTarget()` (lines 2622–2629):** Same pattern — uncheck button and call `toggleAutoTarget()`.

### What BTCBot Currently Lacks
No PZ detection in any module. `BTCAttack`, `BTCTools`, `BTCEquipment` all continue to operate inside PZ.

### How to Implement in BTCBot
Add to the top of each relevant `execute()` function:
```lua
local player = g_game.getLocalPlayer()
if player and player:isInProtectionZone() then
  return  -- Silent skip, or optionally auto-disable config.enabled
end
```

Modules where PZ checks are most important:
- `BTCAttack.execute()` — never attack in PZ
- `BTCEquipment.execute()` — no need to swap items in PZ
- `BTCCaveBot.execute()` — depends on intended behavior (may be fine to continue walking)

---

## 12. Locked Target System

### What It Is
A "lock" on a specific creature ID. While the locked target is alive and within reach, the auto-targeter always focuses it instead of running normal mode logic. The lock is set externally (e.g., user clicks a creature) and clears when the target dies.

### Where It Is in the Helper
- **File:** `mods/game_helper/helper.lua`
- **Config (line 172):** `helperConfig.currentLockedTargetId = 0`
- **Check in `checkAutoTarget()` (lines 2644–2647):**
  ```lua
  local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0
    and g_map.getCreatureById(helperConfig.currentLockedTargetId)
    or nil
  if currentLockedTarget
    and not currentLockedTarget:isDead()
    and isWithinReach(position, currentLockedTarget:getPosition())
  then
    return  -- Keep attacking locked target, skip mode logic
  end
  ```
- The lock is set by right-clicking a creature and selecting "Lock Target" (via a context menu or hotkey, implementation varies).

### What BTCBot Currently Lacks
No concept of a locked target. If the current attack target dies, `BTCAttack.execute()` simply picks the next available creature based on proximity.

### How to Implement in BTCBot

**Step 1 — Add to config:**
```lua
BTCAttack.config.lockedTargetId = 0
```

**Step 2 — Priority check in `execute()`:**
```lua
-- Before running mode selection:
if BTCAttack.config.lockedTargetId ~= 0 then
  local locked = g_map.getCreatureById(BTCAttack.config.lockedTargetId)
  if locked and not locked:isDead() then
    local playerPos = player:getPosition()
    if isWithinReach(playerPos, locked:getPosition()) then
      local current = g_game.getAttackingCreature()
      if not current or current:getId() ~= locked:getId() then
        g_game.attack(locked)
      end
      goto spellLoop  -- Skip target selection, go straight to spell evaluation
    end
  end
  -- Locked target gone — clear the lock
  BTCAttack.config.lockedTargetId = 0
end
```

**Step 3 — Expose `lockedTargetId` setter:** Add a button or right-click context on the battle list entry to set the locked target ID, and a "Clear Lock" button in the UI.
