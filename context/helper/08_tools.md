# Helper Module — Tools: Haste, Auto-Eat, Gold Change

## checkAutoHaste()

- **Source lines:** ~2766–2804
- **Event interval:** 500 ms
- **Event assignment:** `eventTable.checkAutoHaste.action = checkAutoHaste`

```lua
local lastHaste = 0  -- module-level, tracks when haste was last cast

function checkAutoHaste()
  if not hotkeyHelperStatus then return end

  local localPlayer = g_game.getLocalPlayer()
  if not localPlayer or helperConfig.haste[1].id == 0 then
    return true
  end

  if not helperConfig.haste[1].enabled then
    return true
  end

  if not helperConfig.haste[1].safecast and player:isInProtectionZone() then
    return true
  end

  local spellId = helperConfig.haste[1].id
  local spell = Spells.getSpellByClientId(spellId)
  if not spell or spell.id == 0 then
    return false
  end

  if not checkHealthPriority() then
    return
  end

  local currentMillis = g_clock.millis()
  local nextTime = lastHaste + spell.duration

  if currentMillis < nextTime then
    return
  end

  g_game.talk(spell.words, true)
  lastHaste = currentMillis
end
```

### Guard Sequence

| Guard                             | Description                                                     |
|-----------------------------------|-----------------------------------------------------------------|
| `hotkeyHelperStatus`              | Master on/off gate                                              |
| `localPlayer == nil`              | No player object available                                      |
| `haste[1].id == 0`                | No haste spell assigned                                         |
| `haste[1].enabled == false`       | Haste is toggled off                                            |
| `not safecast and isInPZ`         | Skip in PZ unless safecast is enabled                           |
| `Spells.getSpellByClientId` nil   | Spell not found in spell data                                   |
| `checkHealthPriority()` false     | Player needs healing — skip haste this cycle                    |
| `currentMillis < lastHaste + duration` | Haste buff is still active — no need to recast            |

### Duration-Based Timing

The haste cooldown uses `spell.duration` from the spell data object rather than the server spell cooldown system. `lastHaste` stores the millisecond timestamp of the last cast. The next cast is allowed when:

```
g_clock.millis() >= lastHaste + spell.duration
```

This means haste is re-cast as soon as the buff is expected to expire, not when the spell group cooldown clears. The `lastHaste` variable is module-level (`local lastHaste = 0`) and resets to 0 when the client restarts (not persisted), so the first cast on login happens immediately.

### Haste Slot Structure

```lua
helperConfig.haste = {
  { id = 0, enabled = false, safecast = false }
}
```

| Field      | Type    | Description                                                  |
|------------|---------|--------------------------------------------------------------|
| `id`       | number  | Client spell ID of the haste spell (0 = none assigned)       |
| `enabled`  | boolean | Whether auto-haste is active                                 |
| `safecast` | boolean | If true, haste is cast even while in a Protection Zone       |

### hasteWhiteList

Only spells in `hasteWhiteList[vocation]` can be assigned to the haste slot. See [05_spells.md](05_spells.md) for the full per-vocation list.

### Toggle Functions

```lua
function toggleAutoHaste(checked)
  if helperConfig.training[1].enabled then
    toolsPanel:recursiveGetChildById("enableTraining0"):setChecked(false)
    -- Note: does NOT set training[1].enabled = false in helperConfig
    -- Only unchecks the UI widget; the config is not explicitly cleared here
  end
  helperConfig.haste[1].enabled = checked
end

function toggleAutoHastePz(checked)
  helperConfig.haste[1].safecast = checked
end
```

---

## checkHealthPriority()

```lua
function checkHealthPriority()
  if not hotkeyHelperStatus then return end
  for _, spell in ipairs(helperConfig.spells) do
    local healthPercent = (player:getHealth() / player:getMaxHealth()) * 100
    if spell.id ~= 0 and healthPercent <= tonumber(spell.percent) then
      return false
    end
  end
  return true
end
```

Returns `false` if **any** configured healing spell condition is currently triggered (i.e., HP% <= the spell's threshold). Returns `true` (safe to cast support spells) when the player is healthy enough that no healing spell would fire.

Used as a gate in:
- `checkAutoHaste()` — skip haste when healing is needed.
- `useAutoSio()` — skip friend healing when self-healing is needed.
- `useAutoGranSio()` — same.
- `useAutoTioSio()` — same.
- `useAutoUH()` — same.

This ensures self-preservation takes priority over any support or enhancement casting.

---

## autoEatFood()

- **Source lines:** ~2028–2053
- **Called from:** `routineChecks()` (1000ms interval), only when `player:getRegenerationTime() <= 500`

```lua
function autoEatFood()
  if not g_game.isOnline() or not player or not helperConfig.autoEatFood then
    return
  end

  local cooldown = getSpellCooldown(foodConfig.id)
  if cooldown >= g_clock.millis() then
    return true
  end

  for _, id in pairs(infiniteFoodIds) do
    if player:getInventoryCount(id) > 0 then
      g_game.useInventoryItem(id)
      spellsCooldown[foodConfig.id] = g_clock.millis() + foodConfig.exhaustion
      return
    end
  end

  for _, id in pairs(foodIds) do
    if player:getInventoryCount(id) > 0 then
      g_game.useInventoryItem(id)
      spellsCooldown[foodConfig.id] = g_clock.millis() + foodConfig.exhaustion
      break
    end
  end
end
```

### Logic

1. `helperConfig.autoEatFood` must be true.
2. A 1000ms food cooldown is enforced via `spellsCooldown["food"]`.
3. Checks `infiniteFoodIds` first (reusable food — does not consume). If found, uses it and returns.
4. Falls back to `foodIds` (consumable food). Uses the first item found in inventory.

The `routineChecks` trigger condition `player:getRegenerationTime() <= 500` means food is only considered when the player's regeneration timer is nearly expired (below 500ms). This prevents eating food constantly when regeneration is already full.

### foodIds — 39 Consumable Food Items

```lua
local foodIds = {
  3577, 3578, 3579, 3581, 3582, 3583, 3585, 3586, 3587,
  3588, 3589, 3592, 3595, 3597, 3600, 3601, 3602, 3606,
  3607, 3723, 3724, 3725, 3728, 3731, 3732, 8011, 8014,
  8016, 8017, 12310, 14085, 17457, 17820, 17821, 21143,
  21144, 21146, 23535, 23545
}
```

### infiniteFoodIds — 9 Reusable Food Items

```lua
local infiniteFoodIds = {
  61615, 61672, 61930, 62184, 62267, 62268, 63235, 63314, 63723
}
```

These are food items that can be used repeatedly without being consumed (event/special items). Checked first — if the player has any, consumable food is never touched.

### Toggle

```lua
function toggleAutoEat(checked)
  helperConfig.autoEatFood = checked
end
```

---

## autoChangeGold()

- **Source lines:** ~2055–2078
- **Called from:** `routineChecks()` (1000ms interval)

```lua
function autoChangeGold()
  if not g_game.isOnline() or not player or not helperConfig.autoChangeGold then
    return
  end
  doChangeGold(moneyIds)
end

function doChangeGold(moneyIds)
  local containers = g_game.getContainers()
  for index, container in pairs(containers) do
    if not container.lootContainer then  -- skip monster loot containers
      for i, item in ipairs(container:getItems()) do
        if item:getCount() == 100 then
          for m, moneyId in ipairs(moneyIds) do
            if item:getId() == moneyId then
              return g_game.use(item)
            end
          end
        end
      end
    end
  end
end
```

### Logic

1. `helperConfig.autoChangeGold` must be true.
2. Iterates all open containers.
3. Skips containers flagged as `lootContainer` (e.g., a monster corpse being looted by another bot).
4. For each item with exactly count 100, checks if it is gold (3031) or platinum (3035).
5. Calls `g_game.use(item)` — this converts 100 gold coins into 1 platinum coin, or 100 platinum coins into 1 gold coin (game mechanic).
6. Returns after the first match (only one conversion per 1000ms cycle).

```lua
local moneyIds = { 3031, 3035 }  -- gold coin, platinum coin
```

### Toggle

```lua
function toogleChangeGold(checked)
  helperConfig.autoChangeGold = checked
end
```

Note the typo in the function name: `toogleChangeGold` (double "o"). This is the actual function name in the code.

---

## routineChecks()

- **Source lines:** ~2094–2103
- **Event interval:** 1000 ms
- **Event assignment:** `eventTable.routineChecks.action = routineChecks`

```lua
function routineChecks()
  if not hotkeyHelperStatus then return end
  if player then
    if player:getRegenerationTime() <= 500 then
      autoEatFood()
    end
    autoChangeGold()
  end
end
```

The routine checks function is the 1-second orchestrator for background maintenance tasks:
- `autoEatFood()` is called only when regeneration time is nearly depleted.
- `autoChangeGold()` is called unconditionally (it has its own `helperConfig.autoChangeGold` guard inside).

Both sub-functions have their own feature flag checks, so `routineChecks` does not need to check them separately.

---

## Tools Panel Summary

| Feature            | Config Key                  | Toggle Function           | Interval      |
|--------------------|-----------------------------|--------------------------|--------------  |
| Auto-Eat Food      | `autoEatFood`               | `toggleAutoEat(checked)` | 1000ms (conditional) |
| Auto-Change Gold   | `autoChangeGold`            | `toogleChangeGold(checked)` | 1000ms      |
| Auto-Haste         | `haste[1].enabled`          | `toggleAutoHaste(checked)` | 500ms       |
| Haste in PZ        | `haste[1].safecast`         | `toggleAutoHastePz(checked)` | (flag only) |
| Training Spell     | `training[1].enabled`       | (checkbox widget directly) | 100ms (via checkMana) |
| Exercise Dummy     | `autoTrainingCheck` widget  | (checkbox widget directly) | 10000ms     |
