# Helper Module — Follow, Hold, and PZ Modes

## currentLockedTargetId

```lua
helperConfig.currentLockedTargetId = 0  -- 0 = no locked target
```

`currentLockedTargetId` is a numeric field in `helperConfig` that stores the creature ID of a manually locked attack target. It is persisted to JSON alongside all other settings.

### Locked Target Behavior in checkAutoTarget

At the start of each `checkAutoTarget` execution, the locked target is resolved:

```lua
local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0
  and g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil

if currentLockedTarget
    and not currentLockedTarget:isDead()
    and isWithinReach(position, currentLockedTarget:getPosition()) then
  return
end
```

All three conditions must be true for the lock to suppress auto-selection:
1. `currentLockedTargetId ~= 0` — a lock is set.
2. `g_map.getCreatureById()` returns a valid creature (not nil — not despawned).
3. `not isDead()` — the creature has health > 0.
4. `isWithinReach(position, ...)` — within the 7×5 tile attack window.

If the locked creature dies, disappears, or walks out of reach, the lock is effectively bypassed and the function proceeds with normal target selection. The `currentLockedTargetId` value is not automatically cleared in this case — it is only explicitly cleared when `toggleAutoTarget` is called with the feature being disabled.

### Clearing the Lock

```lua
function toggleAutoTarget(widget)
  helperConfig.autoTargetEnabled = widget:isChecked()
  if not helperConfig.autoTargetEnabled and helperConfig.currentLockedTargetId > 0 then
    helperConfig.currentLockedTargetId = 0
    g_game.cancelAttack()
  end
  ...
end
```

When auto-target is **disabled**:
- `currentLockedTargetId` is reset to 0.
- `g_game.cancelAttack()` stops any active attack.

When auto-target is re-enabled, `currentLockedTargetId` starts at 0 (no lock). On `online()`, it is always reset:

```lua
helperConfig.currentLockedTargetId = 0
```

---

## autoTargetOnHold

```lua
local autoTargetOnHold = false
```

`autoTargetOnHold` is a module-level local (not persisted). When `true`, it halts both `checkAutoTarget` and all spell/rune iterations in `checkMagicShooter`.

### Effect on checkAutoTarget

```lua
function checkAutoTarget()
  if not hotkeyHelperStatus then return end
  if not helperConfig.autoTargetEnabled then return end
  if autoTargetOnHold then return end  -- <-- hard stop
  ...
end
```

### Effect on checkMagicShooter

Inside the `unifiedList` iteration loop:

```lua
for _, entry in ipairs(unifiedList) do
  if autoTargetOnHold then
    goto continue  -- skip this entry entirely
  end
  ...
end
```

Every single entry (spell or rune) is skipped for as long as `autoTargetOnHold` is `true`. This means the entire shooter is paused, not just target selection.

### Current Usage

`autoTargetOnHold` is declared as `false` and is not toggled by any UI-exposed function in the current codebase. It is reserved for future manual-hold functionality or could be set programmatically from external modules. No setter function or keybind currently changes it at runtime.

---

## Follow Detection in checkMagicShooter

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

If `g_game.getFollowingCreature()` returns a creature (the player is following something), the magic shooter is automatically **disabled and unchecked**. The message "Follow detected! RTCaster disabled." is shown in the game chat.

This is a safety measure — not a movement mode. The Helper has no follow-based movement system. It uses follow detection purely as a signal to disable the shooter, preventing the bot from firing while the player has manual follow active.

This check is performed **after** the PZ check and **before** the spectator snapshot is built. Once disabled, the shooter will not re-enable automatically when follow stops — the player must re-enable it manually.

---

## PZ Auto-Disable

Both `checkAutoTarget` and `checkMagicShooter` check `myCharacter:isInProtectionZone()`:

### In checkMagicShooter

```lua
if myCharacter:isInProtectionZone() then
  local caster = enableButtons:recursiveGetChildById("enableMagicShooter")
  if caster then
    caster:setChecked(false)
    toggleMagicShooter(caster, "Entering in a Protection Zone!\nRTCaster disabled.")
    return
  end
end
```

### In checkAutoTarget

```lua
if myCharacter:isInProtectionZone() then
  local autoTarget = enableButtons:recursiveGetChildById("enableAutoTarget")
  if autoTarget then
    autoTarget:setChecked(false)
    toggleAutoTarget(autoTarget)
    return
  end
end
```

Both disable the respective feature and uncheck the UI button. The auto-target disable also calls `g_game.cancelAttack()` (via `toggleAutoTarget`). Neither re-enables automatically when the player leaves the PZ.

Auto-haste has a softer PZ check — it does not disable itself, it simply skips casting:

```lua
if not helperConfig.haste[1].safecast and player:isInProtectionZone() then
  return true  -- skip this cycle only
end
```

If `safecast` is false and the player is in PZ, haste is skipped. If `safecast` is true, haste continues to cast in PZ.

---

## magicShooterOnHold — Temporary Rune Pause

```lua
helperConfig.magicShooterOnHold = false
```

A boolean in `helperConfig` (persisted to JSON but always reset to `false` on load). Used to temporarily suppress rune casting during potion use:

```lua
-- In usePotion():
helperConfig.magicShooterOnHold = true
g_game.useInventoryItemWith(potionId, player, 0, true)
helperConfig.magicShooterOnHold = false

-- In useAutoUH():
helperConfig.magicShooterOnHold = true
g_game.useInventoryItemWith(runeId, target, 0, true)
helperConfig.magicShooterOnHold = false
```

The rune block in `checkMagicShooter`:
```lua
elseif entry.type == "rune" then
  if helperConfig.magicShooterOnHold then
    goto continue
  end
```

Since all game operations in OTClient are synchronous within the Lua execution context, setting the flag before a `useInventoryItemWith` call and clearing it immediately after is sufficient to prevent the rune loop from firing in the same execution frame.

---

## Comparison: Helper vs. BTCBot Movement Modes

The Helper has **no movement system**. There is no stand-and-fight mode, no approach-to-target mode, no waypoint following, and no pathfinding.

| Feature                  | Helper         | BTCBot (game_bot)                             |
|--------------------------|----------------|-----------------------------------------------|
| Auto-attack targeting    | Yes (9 modes)  | Yes (separate targeting logic)                |
| Auto-cast spells         | Yes            | Yes                                           |
| Movement to target       | No             | Yes (approach mode, pathfinding)              |
| Waypoint navigation      | No             | Yes (cavebot)                                 |
| Follow mode              | Detect + disable | Separate follow/stand modes                  |
| Stand/lure               | No             | Yes (stand_lure module)                       |

The Helper assumes the player is already in the correct position. The follow detection feature exists solely to prevent the shooter from firing while the player is manually following a creature — it does not implement any "follow and attack" automation.
