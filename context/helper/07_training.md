# Helper Module — Training System

## checkTrainingSpell(mana, maxMana)

- **Source lines:** ~1994–2006
- **Called from:** `checkMana()` (100ms interval)

```lua
function checkTrainingSpell(mana, maxMana)
  local trainingSpell = helperConfig.training[1]
  if not trainingSpell or not trainingSpell.enabled then
    return false
  end

  local manaPercent = (mana / maxMana) * 100
  if manaPercent < tonumber(trainingSpell.percent) then
    return false
  end

  castHealingSpell(trainingSpell.id)
end
```

### Logic

1. Reads slot 1 from `helperConfig.training` (only one slot exists).
2. Returns immediately if the slot is not enabled.
3. Computes current mana percentage.
4. If mana% is below the threshold → returns false (does not cast).
5. If mana% meets the threshold → calls `castHealingSpell(id)`.

The training spell is cast **when mana is high enough** (above the configured percent). This is the opposite of healing (which casts when stats are low). The pattern is: train when you have mana to spare, stop when mana runs low.

### Training Slot Structure

```lua
helperConfig.training = {
  { id = 0, percent = 0, enabled = false }
}
```

| Field     | Type    | Description                                                  |
|-----------|---------|--------------------------------------------------------------|
| `id`      | number  | Client spell ID (0 = no spell assigned)                      |
| `percent` | number  | Mana% threshold — cast when mana >= this value               |
| `enabled` | boolean | Whether training is active                                   |

Only index `[1]` is used. The system does not support multiple training spells simultaneously.

---

## assignTrainingSpell(button, isHaste)

Opens a spell selection window filtered to the player's vocation. When `isHaste = false`:
- Filters to spells in spell groups 2 or 3 (training/mana-consuming groups).
- Excludes spells in `hasteWhiteList` (those are haste spells, not training).
- Excludes spells in `ignoredTrainingSpells`.

When a spell is selected and confirmed:
```lua
helperConfig.training[1].id = tonumber(spellId)
if helperConfig.training[1].percent == 0 then
  helperConfig.training[1].percent = 100
  updateTrainingPercent('spellTrainingButton0', 100)
end
```

If no percent was set, it defaults to 100% (cast whenever any mana is available).

---

## toggleAutoEat and toggleAutoHaste Exclusivity

```lua
function toggleAutoHaste(checked)
  if helperConfig.training[1].enabled then
    toolsPanel:recursiveGetChildById("enableTraining0"):setChecked(false)
  end
  helperConfig.haste[1].enabled = checked
end
```

Enabling auto-haste automatically **disables** the training spell if it was active. The reverse is not enforced in code — enabling training does not disable haste. The assumption is that haste and training consume the same mana pool and haste takes priority.

---

## ignoredTrainingSpells

See [05_spells.md](05_spells.md) for the full list. Key principle: spells that are purely support (cures, buffs, friend-healing) or that belong to the haste whitelist are excluded from the training selector. This ensures only mana-consuming attack or utility spells (like "exori vis", "exevo gran vis lux") appear in the training slot.

The exclusion is applied in `assignTrainingSpell` during list construction:
```lua
if table.contains(spellData.vocations, playerVocation) and not ignoredTrainingSpells[spellData.id] then
  -- add to selection list
end
```

---

## checkExerciseEvent — Exercise Dummy Automation

- **Source lines:** ~3444–3509
- **Event interval:** 10000 ms (10 seconds)
- **Event assignment:** `eventTable.checkExerciseEvent.action = checkExerciseEvent`

```lua
function checkExerciseEvent()
  if not toolsPanel then return end
  local w = toolsPanel:recursiveGetChildById("autoTrainingCheck")
  if not w or type(w.isChecked) ~= "function" then return end
  if not w:isChecked() then return end

  local autoTrainingItem = toolsPanel:recursiveGetChildById("autoTrainingItem")
  local itemBox = autoTrainingItem and autoTrainingItem.potionItem
  if not itemBox or itemBox:getItemId() == 0 then
    w:setChecked(false)
    return
  end

  local itemId = itemBox:getItemId()
  if player:getInventoryCount(itemId, 0) == 0 then
    w:setChecked(false)
    return
  end

  local dummy = getExerciseDummy()
  if not dummy then
    modules.game_textmessage.displayGameMessage("No exercise dummy found.")
    w:setChecked(false)
    return
  end

  g_game.useInventoryItemWith(itemId, dummy)
end
```

### Logic

1. Check if `autoTrainingCheck` widget is checked — if not, skip.
2. Verify an exercise weapon is assigned in the `autoTrainingItem` slot.
3. Verify the player has the exercise weapon in inventory.
4. Find the closest visible exercise dummy via `getExerciseDummy()`.
5. If no dummy found: show message and uncheck the widget.
6. Use the exercise weapon on the dummy: `g_game.useInventoryItemWith(itemId, dummy)`.

If any condition fails, the feature disables itself (unchecks the widget) rather than silently doing nothing.

### getExerciseDummy()

```lua
function getExerciseDummy()
  local playerPos = player:getPosition()
  local itemList = {}
  for _, id in pairs(exerciseDummies) do
    local items = g_map.findItemsById(id, 5)  -- search radius 5
    if items then
      for pos, ptr in pairs(items) do
        if pos.z == playerPos.z then
          itemList[#itemList + 1] = {position = pos, item = ptr}
        end
      end
    end
  end

  table.sort(itemList, function(a, b)
    return getDistanceBetween(playerPos, a.position) < getDistanceBetween(playerPos, b.position)
  end)

  for _, data in pairs(itemList) do
    if g_map.isSightClear(data.position, playerPos) then
      return data.item
    end
  end
  return nil
end
```

- Searches the map within radius 5 for any item ID in `exerciseDummies`.
- Filters to same floor (same Z as player).
- Sorts by Chebyshev distance (closest first).
- Returns the first dummy that has line of sight to the player.

---

## exerciseDummies ID List (29 items)

```lua
local exerciseDummies = {
  28558, 28559, 28560, 28561, 28562, 28563, 28564, 28565,
  61621, 61622, 61623, 61624, 61698, 61699, 61892, 61893,
  61974, 61975, 62118, 62119, 62191, 62192, 62228, 62229,
  62294, 62295, 63249, 63250, 63713
}
```

These are the tile item IDs of exercise dummies that can be targeted.

---

## exercises ID List (34 items)

```lua
local exercises = {
  28552, 28553, 28554, 28555, 28556, 28557, 35279, 35280,
  35281, 35282, 35283, 35284, 35285, 35286, 35287, 35288,
  35289, 35290, 44064, 44065, 44066, 44067, 50292, 50293,
  50294, 50295, 62101, 62102, 62103, 62104, 62105, 62106,
  62107, 63492
}
```

These are the item IDs of exercise weapons (the items the player uses on the dummy). Validated in `onAssignExercise` using `table.find(exercises, exerciseId)`.

---

## assignExerciseEvent — Assigning an Exercise Weapon

```lua
function assignExerciseEvent(button)
  g_mouse.updateGrabber(mouseGrabberWidget, 'target')
  mouseGrabberWidget:grabMouse()
  helper:hide()
  g_mouse.pushCursor('target')
  mouseGrabberWidget.onMouseRelease = function(self, mousePosition, mouseButton)
    onAssignExercise(self, mousePosition, mouseButton, button)
  end
end
```

Enters "click-to-assign" mode. On mouse release, `onAssignExercise` checks if the clicked item is in the `exercises` table and assigns it to the `autoTrainingItem` slot widget.

---

## Training Percent Update

```lua
function updateTrainingPercent(buttonId, newPercent)
  local buttonIndex = string.match(buttonId, "%d+")
  buttonIndex = tonumber(buttonIndex)
  local trainingConfig = helperConfig.training[buttonIndex + 1]
  if trainingConfig and trainingConfig.percent then
    trainingConfig.percent = tonumber(newPercent)
  end
end
```

Called from UI increment/decrement buttons and from `assignTrainingSpell` when auto-defaulting to 100%.

---

## Mana Percent Threshold Semantics

| Feature         | Cast when mana is... | Purpose                              |
|-----------------|----------------------|--------------------------------------|
| Mana healing    | Below threshold      | Restore mana to full                 |
| Training spell  | Above threshold      | Spend excess mana productively       |
| Haste           | No mana% check       | Cast when duration expires           |

The training system uses mana% as a ceiling gate: if mana drops below the configured percent, the training spell stops firing, allowing mana healing to run without contention.
