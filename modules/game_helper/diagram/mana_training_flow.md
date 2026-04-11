# Mana Training - Flow Diagram

## Overview

Mana Training is a reactive system that automatically casts spells when the player's mana
reaches a configured percentage. Unlike Auto Haste, it doesn't use cycle events - it's triggered
only when mana changes.

---

## Execution Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            EVENT: Mana Changed                              │
│                          (onPlayerManaChange)                               │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                              checkMana()                                    │
│                           helper.lua:3256                                   │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼                                   ▼
        ┌───────────────────┐               ┌────────────────────┐
        │ checkManaHealing()│               │checkTrainingSpell()│
        │  (Mana Potions)   │               │   (Wrapper)        │
        └───────────────────┘               └────────────────────┘
                                                    │
                                                    ▼
                                    ┌───────────────────────────┐
                                    │ _Helper.ManaTraining.check│
                                    │  mana_training.lua:46     │
                                    └───────────────────────────┘
```

---

## Priority Logic: Auto Haste vs Mana Training

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    _Helper.ManaTraining.check(mana, maxMana)                │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
                        ┌─────────────────────────┐
                        │  Is Training            │
                        │  enabled?               │
                        └─────────────────────────┘
                           │              │
                          NO             YES
                           │              │
                           ▼              ▼
                    ┌──────────┐  ┌─────────────────────────┐
                    │  RETURN  │  │  Is Auto Haste          │
                    │  false   │  │  enabled AND            │
                    └──────────┘  │  configured (id != 0)?  │
                                  └─────────────────────────┘
                                       │              │
                                      NO             YES
                                       │              │
                                       │              ▼
                                       │    ┌─────────────────────────┐
                                       │    │  Does player have       │
                                       │    │  Haste state active?    │
                                       │    └─────────────────────────┘
                                       │         │              │
                                       │        YES            NO
                                       │         │              │
                                       │         │              ▼
                                       │         │    ┌──────────────────────┐
                                       │         │    │  RETURN false        │
                                       │         │    │  (Priority: Haste)   │
                                       │         │    └──────────────────────┘
                                       │         │
                                       ▼         ▼
                              ┌─────────────────────────┐
                              │  Current mana >= config │
                              │  percent threshold?     │
                              └─────────────────────────┘
                                   │              │
                                  NO             YES
                                   │              │
                                   ▼              ▼
                            ┌──────────┐  ┌─────────────────────────┐
                            │  RETURN  │  │  castHealingSpell()     │
                            │  false   │  │  Cast the spell!        │
                            └──────────┘  └─────────────────────────┘
```

---

## Priority Explanation

### Problem

When the player loses the Haste buff and both Auto Haste and Mana Training are enabled,
both try to cast spells at the same time, causing conflict.

### Solution

Mana Training checks if:

1. Auto Haste is enabled (`helperConfig.haste[1].enabled`)
2. Auto Haste has a spell configured (`helperConfig.haste[1].id != 0`)
3. Player does NOT have the Haste state (`!localPlayer:hasState(PlayerStates.Haste)`)

If ALL conditions are true, Mana Training **does NOT cast** and returns `false`,
allowing Auto Haste to recover the buff first.

---

## Module Architecture

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              helper.otmod                                   │
│  scripts: [ ..., classes/auto_haste, classes/mana_training, helper ]        │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
            ┌─────────────────────────┼─────────────────────────┐
            ▼                         ▼                         ▼
┌───────────────────┐    ┌───────────────────────┐    ┌─────────────────┐
│  auto_haste.lua   │    │  mana_training.lua    │    │   helper.lua    │
│                   │    │                       │    │                 │
│ _Helper.AutoHaste │    │ _Helper.ManaTraining  │    │  Wrapper Funcs  │
│   .toggle()       │    │   .toggle()           │    │  Getters/Setters│
│   .check()        │    │   .updatePercent()    │    │  helperConfig   │
│   .startCycle()   │    │   .loadToUI()         │    │                 │
│   .stopCycle()    │    │   .resetButton()      │    │                 │
│   .onHasteLost()  │    │   ...                 │    │                 │
│   ...             │    │   ...                 │    │                 │
└───────────────────┘    └───────────────────────┘    └─────────────────┘
         │                         │                         │
         └─────────────────────────┼─────────────────────────┘
                                   ▼
                    ┌───────────────────────────┐
                    │        _Helper            │
                    │   (Global Namespace)      │
                    │                           │
                    │  .getHelperConfig()       │
                    │  .getToolsPanel()         │
                    │  .castHealingSpell()      │
                    │  .saveSettings()          │
                    │  .Shortcut                │
                    │  .AutoHaste               │
                    │  .ManaTraining            │
                    └───────────────────────────┘
```

---

## \_Helper.ManaTraining Module Functions

| Function                 | Description                                      |
| ------------------------ | ------------------------------------------------ |
| `toggle(buttonId, chk)`  | Enable/disable mana training, rejects if no spell |
| `updatePercent(id, %)`   | Update the minimum mana percentage               |
| `check(mana, maxMana)`   | Check and cast spell (with haste priority)       |
| `resetButton()`          | Reset the training button in UI                  |
| `removeAction(button)`   | Remove training configuration                    |
| `loadToUI()`             | Load config data to UI                           |
| `collectStates()`        | Collect current states for saving                |
| `saveAndRestoreStates()` | Restore saved states after reset                 |

---

## helperConfig Configuration

```lua
helperConfig = {
    training = {
        {
            id = 0,           -- Spell ID (0 = none)
            percent = 100,    -- Minimum mana percentage to cast
            enabled = false   -- Whether mana training is active
        }
    },
    haste = {
        {
            id = 0,           -- Haste spell ID
            enabled = false,  -- Whether auto haste is active
            safecast = false  -- Whether to cast in Protection Zone
        }
    }
}
```

---

## Shortcut Panel Synchronization

```
┌───────────────────┐         ┌───────────────────┐
│  Shortcut Panel   │ ◄─────► │  Tools Panel      │
│ (shortcutTraining)│         │  (enableTraining0)│
└───────────────────┘         └───────────────────┘
         │                             │
         │   _Helper.Shortcut          │   OTUI Callback
         │   .syncButton()             │   onEnableTraining()
         │                             │
         └──────────────┬──────────────┘
                        ▼
              ┌───────────────────┐
              │ _Helper.ManaTraning│
              │     .toggle()      │
              └───────────────────┘
```

When the user clicks on the shortcut or the panel checkbox, both synchronize
through `_Helper.Shortcut.syncButton()` and `_Helper.ManaTraining.toggle()`.

---

## Enable Guard (Spell Required)

### Problem (Before Fix)

```
1. User opens Tools tab
2. User enables Mana Training (checkbox ON)
3. No spell selected yet → confusing state
4. User selects a training spell
5. Nothing happens → must disable + re-enable
```

### Solution (After Fix)

```
toggle(buttonId, true) now:
  │
  ├─ Check if spell id == 0
  │
  └─ If no spell selected:
          │
          ├─ Show error message: "Select a training spell first!"
          │
          ├─ Uncheck the checkbox in UI
          │
          ├─ Sync shortcut panel to unchecked (if slot 0)
          │
          └─ Return false (reject enable)
```

### toggle() Flow with Guard

```
toggle(buttonId, checked)
      │
      ├─ Config exists? ─────────────────── No ──→ return false
      │
      ├─ checked AND spell id == 0? ─────── Yes ─→ REJECT
      │         │                                    │
      │         │                          ┌─────────┘
      │         │                          ▼
      │         │                   Show error message
      │         │                   Uncheck UI checkbox
      │         │                   Sync shortcut panel (slot 0)
      │         │                   return false
      │         │
      │         No
      │         │
      │         ▼
      └─ Continue with normal toggle logic...
```

### Expected Behavior (After Fix)

- User **must** select a spell before enabling Mana Training
- Attempting to enable without spell shows clear error message
- Checkbox automatically unchecks if no spell selected
- No confusing "enabled but not working" state possible
- The feature behaves predictably and intuitively
