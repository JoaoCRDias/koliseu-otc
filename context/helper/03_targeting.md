# Helper Module — Auto Target System

## checkAutoTarget() — Function Overview

- **Source lines:** ~2614–2752
- **Event interval:** 250 ms
- **Event assignment:** `eventTable.checkAutoTarget.action = checkAutoTarget`

`checkAutoTarget` selects and attacks the best monster each cycle according to the configured targeting mode.

---

## Guard Conditions (early-return chain)

The function has a strict sequence of guards before any targeting logic runs:

```lua
function checkAutoTarget()
  if not hotkeyHelperStatus then return end           -- master on/off
  if not helperConfig.autoTargetEnabled then return end  -- feature toggle
  if autoTargetOnHold then return end                 -- manual hold

  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end

  if myCharacter:isInProtectionZone() then            -- PZ auto-disable
    local autoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
    if autoTarget then
      autoTarget:setChecked(false)
      toggleAutoTarget(autoTarget)
      return
    end
  end
```

### PZ Auto-Disable
When the player enters a Protection Zone, `checkAutoTarget` unregisters itself: it unchecks the `enableAutoTarget` widget and calls `toggleAutoTarget()`, which sets `helperConfig.autoTargetEnabled = false` and cancels any active attack.

---

## Locked Target Logic

Before computing any target candidates, the function checks if a locked target is still valid:

```lua
local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0
  and g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil

if currentLockedTarget
    and not currentLockedTarget:isDead()
    and isWithinReach(position, currentLockedTarget:getPosition()) then
  return  -- skip selection, keep attacking the locked target
end
```

If `currentLockedTargetId` is nonzero, the creature still exists on the map, is alive, and is within reach — the function returns immediately without changing the attack. This allows the player (or another system) to manually lock a target that will not be superseded by the auto-selector until it dies or moves out of reach.

---

## creatureList Construction

`checkAutoTarget` uses a **fresh** query from `g_map.getSpectators`, not the cached `spectators` table:

```lua
local specs = g_map.getSpectators(position, false)
for i, creature in pairs(specs) do
  if creature:isMonster() then
    table.insert(creatureList, {position = creature:getPosition(), creature = creature})
  end
end
```

This ensures dead/disappeared creatures are never considered.

---

## AoE Area for Mode E (Best Target)

```lua
local area = SpellAreas.AREA_CIRCLE3X3
if translateVocation(myCharacter:getVocation()) == 7 then  -- Paladin (voc 7)
  area = SpellAreas.AREA_CIRCLE2X2
end
```

Mode E evaluates how many creatures each candidate would hit with a circle AoE. The area size is vocation-specific:
- All vocations except Paladin: `AREA_CIRCLE3X3`
- Paladin (voc 7 / Royal Paladin): `AREA_CIRCLE2X2`

---

## Filter: isWithinReach + isSightClear

Only creatures that pass both checks enter the candidate pool:

```lua
if not isWithinReach(position, creatureData.position)
   or not g_map.isSightClear(position, creatureData.position) then
  goto continue
end
```

`isWithinReach` enforces the asymmetric 7×5 tile reach. `isSightClear` excludes creatures blocked by walls. Creatures that fail either check are completely skipped — they do not update any of the 9 candidate variables.

---

## 9 Target Candidate Variables

After filtering, each valid creature updates all applicable candidate slots in a single pass:

```lua
local closestTarget              = {id = nil, distance = 99}
local farthestTarget             = {id = nil, distance = -1}
local lowestHealthTarget         = {id = nil, health = 100}
local highestHealthTarget        = {id = nil, health = -1}
local bestTarget                 = {id = nil, creatures = 0}
local closestLowestHealthTarget  = {id = nil, distance = 99, health = 100}
local closestHighestHealthTarget = {id = nil, distance = 99, health = -1}
local farthestLowestHealthTarget = {id = nil, distance = -1, health = 100}
local farthestHighestHealthTarget= {id = nil, distance = -1, health = -1}
```

### Update Logic Per Creature

| Candidate                     | Update Condition                                                                            |
|-------------------------------|---------------------------------------------------------------------------------------------|
| `closestTarget`               | `creatureDistance < closestTarget.distance`                                                 |
| `farthestTarget`              | `creatureDistance > farthestTarget.distance`                                                |
| `lowestHealthTarget`          | `health < lowestHealthTarget.health` (first valid creature is always set)                   |
| `highestHealthTarget`         | `health > highestHealthTarget.health`                                                       |
| `bestTarget`                  | `creaturesHit > maxCreaturesHit` (from `countAttackableCreatures` with AoE area)            |
| `closestLowestHealthTarget`   | closer distance OR same distance AND lower health                                           |
| `closestHighestHealthTarget`  | closer distance OR same distance AND higher health                                          |
| `farthestLowestHealthTarget`  | farther distance OR same distance AND lower health                                          |
| `farthestHighestHealthTarget` | farther distance OR same distance AND higher health                                         |

Note on `lowestHealthTarget`: the code sets it for the first valid creature unconditionally (`if lowestHealthTarget.id == nil`) to ensure a 100%-health creature is still targeted if it is the only one available.

---

## Target Mode Selection Table

The `autoTargetModes` table maps letter codes to integer IDs:

```lua
local autoTargetModes = {
  ["A"] = 1, ["B"] = 2, ["C"] = 3, ["D"] = 4,
  ["E"] = 5, ["F"] = 6, ["G"] = 7, ["H"] = 8
}
-- Note: "I" (= 9) is used in checkAutoTarget but is NOT in the autoTargetModes
-- initialization table. It is referenced directly as autoTargetModes["I"] in
-- checkAutoTarget, so it evaluates to nil and that elseif branch never fires
-- unless the table is updated externally.
```

Wait — checking the code at line 2742:
```lua
elseif helperConfig.autoTargetMode == autoTargetModes["I"] then
  target = g_map.getCreatureById(farthestHighestHealthTarget.id)
```

The `autoTargetModes` table does not define `"I"`, so `autoTargetModes["I"]` is `nil`. This branch is unreachable unless `helperConfig.autoTargetMode` is manually set to `nil`, which would be a bug condition. The effectively active modes are A through H.

### Mode Summary

| Mode | Key in Code | Target Selected                          | Tie-break                          |
|------|-------------|------------------------------------------|------------------------------------|
| A    | `"A"` → 1   | `closestTarget`                          | Min Chebyshev distance             |
| B    | `"B"` → 2   | `farthestTarget`                         | Max Chebyshev distance             |
| C    | `"C"` → 3   | `lowestHealthTarget`                     | Min healthPercent                  |
| D    | `"D"` → 4   | `highestHealthTarget`                    | Max healthPercent                  |
| E    | `"E"` → 5   | `bestTarget`                             | Max creatures hit by AoE           |
| F    | `"F"` → 6   | `closestLowestHealthTarget` (**default**)| Min distance, then min HP          |
| G    | `"G"` → 7   | `closestHighestHealthTarget`             | Min distance, then max HP          |
| H    | `"H"` → 8   | `farthestLowestHealthTarget`             | Max distance, then min HP          |
| (I)  | `"I"` → nil | `farthestHighestHealthTarget`            | (unreachable — see note above)     |

---

## Attack Dispatch

```lua
local currentTarget = g_game.getAttackingCreature()
-- ... target selected via mode ...
if target and not (currentTarget and currentTarget:getId() == target:getId()) then
  g_game.attack(target)
end
```

`g_game.attack(target)` is only called when the selected target **differs** from the currently attacking creature. If the best candidate is already under attack, no action is taken, avoiding redundant network messages.

---

## toggleAutoTarget(widget)

```lua
function toggleAutoTarget(widget)
  local targetTracker = helperTracker:recursiveGetChildById("targetStatus")
  if not widget then
    widget = shooterPanel:recursiveGetChildById("enableAutoTarget")
    widget:setChecked(not widget:isChecked())
  end
  helperConfig.autoTargetEnabled = widget:isChecked()
  if not helperConfig.autoTargetEnabled and helperConfig.currentLockedTargetId > 0 then
    helperConfig.currentLockedTargetId = 0
    g_game.cancelAttack()
  end
  modules.game_textmessage.displayGameMessage(...)
  targetTracker:setText(...)
  targetTracker:setColor(...)
end
```

Key behaviors on **disable**:
- Clears `currentLockedTargetId` to 0.
- Calls `g_game.cancelAttack()` to stop any active attack.
- Updates the HelperTracker status label to "Inactive" (red).

Can be called with a widget (from UI click or keybind) or without a widget (programmatic toggle — creates its own widget reference internally).

---

## updateAutoTargetMode(mode)

```lua
function updateAutoTargetMode(mode)
  local modeId = autoTargetModes[mode]
  if not modeId then return end
  helperConfig.autoTargetMode = modeId
  local profile = getShooterProfile()
  if profile then
    profile.autoTargetMode = modeId
  end
end
```

The targeting mode is stored in **two places**: `helperConfig.autoTargetMode` (used by `checkAutoTarget`) and `profile.autoTargetMode` (persisted per shooter profile). When a profile is loaded via `loadShooterProfileByName`, the profile's `autoTargetMode` is written back to `helperConfig.autoTargetMode`, so profiles can have different default modes.

---

## autoTargetOnHold

```lua
local autoTargetOnHold = false
```

A module-level local boolean. When `true`, `checkAutoTarget` returns immediately at the third guard (`if autoTargetOnHold then return end`). It also causes `checkMagicShooter` to skip all spells/runes within its iteration loop (`goto continue`). This variable is currently set at declaration and not toggled by any exposed UI function — it is reserved for future manual-hold / override functionality.
