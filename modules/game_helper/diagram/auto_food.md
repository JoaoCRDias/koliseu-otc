# Auto Food System Flow

## Overview

The Auto Food system automatically uses food items when the player's regeneration time is low. It uses a polling approach via `routineChecks` (every 2500ms) combined with a cooldown to prevent spam.

## System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                     routineChecks (every 2500ms)                │
│                                                                 │
│  if helperAutomaticFunctionsEnabled then                        │
│    if currentPlayer:getRegenerationTime() <= 500 then           │
│      _Helper.AutoFood.check()                                   │
│    end                                                          │
│  end                                                            │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    _Helper.AutoFood.check()                     │
│                                                                 │
│  1. Verify autoEatFood is enabled                               │
│  2. Verify cooldown has expired                                 │
│  3. Search for infinite food items (priority)                   │
│  4. Search for normal food items                                │
│  5. Use food item and set cooldown                              │
└─────────────────────────────────────────────────────────────────┘
```

## Check Function Flow

```
_Helper.AutoFood.check()
  │
  ├─ Online? ─────────────────────────── No ──→ return
  │
  ├─ autoEatFood enabled? ────────────── No ──→ return
  │
  ├─ Cooldown expired? ───────────────── No ──→ return true
  │       (cooldown >= g_clock.millis())
  │
  ├─ Player exists? ──────────────────── No ──→ return
  │
  ├─ Has infinite food in inventory? ─── Yes ─→ USE & SET COOLDOWN → return
  │       (infiniteFoodIds)
  │
  └─ Has normal food in inventory? ───── Yes ─→ USE & SET COOLDOWN → break
        (foodIds)
```

## Timing Diagram

```
Time ─────────────────────────────────────────────────────────────────────→

routineChecks interval: 2500ms
│                    │                    │                    │
▼                    ▼                    ▼                    ▼
┌────┐               ┌────┐               ┌────┐               ┌────┐
│chk │               │chk │               │chk │               │chk │
└────┘               └────┘               └────┘               └────┘

Example scenario (food gives 5000ms regeneration):

t=0      : regenerationTime = 0 (hungry)     → check() → EAT FOOD
t=0+     : regenerationTime = 5000
t=2500   : regenerationTime = 2500           → condition <= 500 FALSE (skip)
t=5000   : regenerationTime = 0              → condition <= 500 TRUE
t=5000   : check() → EAT FOOD
t=5000+  : regenerationTime = 5000
...and so on
```

## Cooldown Protection

```
┌─────────────────────────────────────────────────────────────────┐
│                    Food Cooldown System                         │
├─────────────────────────────────────────────────────────────────┤
│  foodConfig = { id = "food", exhaustion = 3000 }                │
│                                                                 │
│  After eating:                                                  │
│    spellsCooldown["food"] = g_clock.millis() + 1000             │
│                                                                 │
│  Before eating:                                                 │
│    if getSpellCooldown("food") >= g_clock.millis() then         │
│      return (still on cooldown)                                 │
│    end                                                          │
├─────────────────────────────────────────────────────────────────┤
│  PURPOSE: Prevent spam if routineChecks runs faster or          │
│           if regenerationTime doesn't update immediately        │
└─────────────────────────────────────────────────────────────────┘
```

## Food Priority

```
┌─────────────────────────────────────────────────────────────────┐
│                      Food Priority Order                        │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  1. INFINITE FOOD (checked first - premium items)               │
│     └─ infiniteFoodIds: 61615, 61672, 61930, 62184, 62267,      │
│                         62268, 63235, 63314, 63723, 49702       │
│                                                                 │
│  2. NORMAL FOOD (checked second)                                │
│     └─ foodIds: 3577, 3578, 3579, 3581, 3582, 3583, 3585,       │
│                 3586, 3587, 3588, 3589, 3592, 3595, 3597,       │
│                 3600, 3601, 3602, 3606, 3607, 3723, 3724,       │
│                 3725, 3728, 3731, 3732, 8011, 8014, 8016,       │
│                 8017, 12310, 14085, 17457, 17820, 17821,        │
│                 21143, 21144, 21146, 23535, 23545               │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

## Toggle Function Flow

```
toggleAutoEat(checked)  [wrapper in helper.lua]
      │
      ▼
_Helper.AutoFood.toggle(checked)
      │
      ├─ Set helperConfig.autoEatFood = checked
      │
      └─ Save settings
```

## UI Integration

```
┌─────────────────────────────────────────────────────────────────┐
│                        UI Functions                             │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  resetCheckbox():                                               │
│    └─ toolsPanel → eatFood checkbox → setChecked(false)         │
│                                                                 │
│  loadToUI():                                                    │
│    └─ toolsPanel → eatFood checkbox →                           │
│         setChecked(helperConfig.autoEatFood)                    │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│  OTUI Callback:                                                 │
│    @onCheckChange: toggleAutoEat(self:isChecked())              │
│                                                                 │
│  Note: OTUI is sandboxed, so it calls the wrapper function      │
│        toggleAutoEat() which then calls _Helper.AutoFood.toggle │
└─────────────────────────────────────────────────────────────────┘
```

## Key Functions

| Function                 | Location      | Description                     |
| ------------------------ | ------------- | ------------------------------- |
| `toggle(checked)`        | auto_food.lua | Enable/disable auto food eating |
| `check()`                | auto_food.lua | Main logic to find and use food |
| `resetCheckbox()`        | auto_food.lua | Reset UI checkbox to unchecked  |
| `loadToUI()`             | auto_food.lua | Load saved state to UI checkbox |
| `getFoodIds()`           | auto_food.lua | Getter for normal food IDs      |
| `getInfiniteFoodIds()`   | auto_food.lua | Getter for infinite food IDs    |
| `getFoodConfig()`        | auto_food.lua | Getter for food config          |
| `toggleAutoEat(checked)` | helper.lua    | Wrapper for OTUI compatibility  |

## Configuration

```lua
-- In helperConfig (helper.lua)
helperConfig = {
  autoEatFood = false,  -- Whether auto food eating is active
  -- ...
}

-- In auto_food.lua (local)
local foodConfig = { id = "food", exhaustion = 1000 }
```

## Files

- `classes/auto_food.lua` - Main module with all Auto Food logic
- `helper.lua` - Contains routineChecks polling and wrapper functions

## Comparison: Auto Food vs Auto Haste

| Aspect       | Auto Food                            | Auto Haste                    |
| ------------ | ------------------------------------ | ----------------------------- |
| Trigger      | Polling (routineChecks every 2500ms) | Event-driven (onStatesChange) |
| Condition    | regenerationTime <= 500              | Player loses haste buff       |
| Cooldown     | 1000ms (internal)                    | Spell cooldown                |
| Priority     | Infinite food > Normal food          | Single spell                  |
| Self-cleanup | N/A (polling based)                  | Stops cycle when has haste    |
