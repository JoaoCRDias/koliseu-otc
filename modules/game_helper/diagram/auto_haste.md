# Auto Haste System Flow

## Overview

The Auto Haste system uses an event-driven approach with a temporary cycle event instead of continuous polling. This is more efficient as it only actively tries to cast haste when needed.

## System Flow Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                          LOGIN                                  │
│  scheduleEvent(1500ms) → AutoHaste.onLogin()                    │
│    └─ If player doesn't have haste → startCycle()               │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    CYCLE EVENT (500ms)                          │
│  hasteCycleFunction():                                          │
│    ├─ If has haste → stopCycle() (self-destructs)               │
│    └─ If no haste → check() (attempts to cast)                  │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DURING GAMEPLAY                              │
│                                                                 │
│  onStatesChange detects haste removed:                          │
│    hadHaste && !hasHaste → onHasteLost() → startCycle()         │
│                                                                 │
│  User toggles Auto Haste ON:                                    │
│    toggle(true) + no haste → startCycle()                       │
│                                                                 │
│  User toggles Auto Haste OFF:                                   │
│    toggle(false) → stopCycle()                                  │
│                                                                 │
│  User toggles PZ Cast ON (while in PZ):                         │
│    togglePz(true) + in PZ + enabled + no haste → startCycle()   │
│                                                                 │
│  User toggles PZ Cast OFF (while in PZ):                        │
│    togglePz(false) + in PZ → stopCycle()                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         LOGOUT                                  │
│  AutoHaste.onLogout() → stopCycle()                             │
└─────────────────────────────────────────────────────────────────┘
```

## Cycle Event Control

```
┌─────────────────────────────────────────────────────────────────┐
│                  hasteCycleEvent (single instance)              │
├─────────────────────────────────────────────────────────────────┤
│  STARTS (startCycle):                                           │
│    • onLogin() - player has no haste                            │
│    • onHasteLost() - haste buff expired                         │
│    • toggle(true) - user enabled, no haste                      │
│    • togglePz(true) - user enabled PZ cast, in PZ, no haste     │
├─────────────────────────────────────────────────────────────────┤
│  STOPS (stopCycle):                                             │
│    • hasteCycleFunction() - player got haste (self-destruct)    │
│    • toggle(false) - user disabled                              │
│    • togglePz(false) - user disabled PZ cast while in PZ        │
│    • onLogout() - player logged out                             │
├─────────────────────────────────────────────────────────────────┤
│  PROTECTION:                                                    │
│    • startCycle() checks if already running (no duplicates)     │
│    • if hasteCycleEvent then return end                         │
│    • startCycle() checks if spell id != 0 (no spell = no start) │
│    • toggle(true) rejects if no spell selected (shows message)  │
└─────────────────────────────────────────────────────────────────┘
```

## State Machine

```
                    ┌──────────────┐
                    │    IDLE      │
                    │ (no cycle)   │
                    └──────┬───────┘
                           │
     ┌─────────────────────┼─────────────────────┐
     │           │         │         │           │
     ▼           ▼         ▼         ▼           ▼
┌────────┐ ┌─────────┐ ┌───────┐ ┌───────┐ ┌──────────┐
│ Login  │ │  Haste  │ │Toggle │ │Toggle │ │TogglePz  │
│(no buf)│ │ Expired │ │  ON   │ │Pz ON  │ │ in PZ    │
└───┬────┘ └────┬────┘ └───┬───┘ └───┬───┘ └────┬─────┘
    │           │          │         │          │
    └───────────┴──────────┴────┬────┴──────────┘
                                │
                                ▼
                       ┌─────────────────┐
                       │  CYCLE ACTIVE   │
                       │  (every 500ms)  │
                       └────────┬────────┘
                                │
              ┌─────────────────┼─────────────────┐
              │                 │                 │
              ▼                 ▼                 ▼
     ┌────────────────┐ ┌──────────────┐ ┌──────────────┐
     │  Cast Success  │ │ Cast Failed  │ │ User Action  │
     │  (has haste)   │ │ (exhausted,  │ │ toggle(false)│
     │                │ │  in PZ, etc) │ │ togglePz(f)  │
     └───────┬────────┘ └──────┬───────┘ └──────┬───────┘
             │                 │                │
             ▼                 │                ▼
    ┌─────────────────┐        │       ┌─────────────────┐
    │   stopCycle()   │        │       │   stopCycle()   │
    │  (self-destruct)│        │       │  (user action)  │
    └────────┬────────┘        │       └────────┬────────┘
             │                 │                │
             ▼                 │                ▼
        ┌──────────┐           │           ┌──────────┐
        │   IDLE   │◄──────────┘           │   IDLE   │
        └──────────┘    (keeps trying)     └──────────┘
```

## Toggle Functions Flow

### toggle(checked) - Enable/Disable Auto Haste

```
toggle(checked)
      │
      ├─ Set helperConfig.haste[1].enabled = checked
      │
      ├─ Sync shortcut panel button
      │
      └─ checked?
              │
       ┌──────┴──────┐
       │             │
      Yes            No
       │             │
       ▼             ▼
  Has haste?    stopCycle()
       │
  ┌────┴────┐
  │         │
 Yes        No
  │         │
  ▼         ▼
(nothing) startCycle()
```

### togglePz(checked) - Enable/Disable PZ Cast

```
togglePz(checked)
      │
      ├─ Set helperConfig.haste[1].safecast = checked
      │
      └─ In Protection Zone?
              │
       ┌──────┴──────┐
       │             │
      Yes            No
       │             │
       ▼             ▼
   checked?      (nothing)
       │
  ┌────┴────┐
  │         │
 Yes        No
  │         │
  ▼         ▼
enabled?  stopCycle()
  │
 Yes
  │
  ▼
has haste?
  │
 No
  │
  ▼
startCycle()
```

## Key Functions

| Function              | Description                                                 |
| --------------------- | ----------------------------------------------------------- |
| `toggle(checked)`     | Enable/disable Auto Haste, rejects if no spell selected     |
| `togglePz(checked)`   | Enable/disable PZ cast, manages cycle if in PZ              |
| `startCycle()`        | Starts the temporary cycle event (if not already running)   |
| `stopCycle()`         | Stops and removes the cycle event                           |
| `check()`             | Main logic to verify conditions and cast haste spell        |
| `onLogin()`           | Called on game start to check initial state                 |
| `onLogout()`          | Called on game end to cleanup                               |
| `onHasteLost()`       | Called by onStatesChange when haste buff expires            |
| `onSetupDropSupport()`| Handles spell drop on button, saves spell ID                |
| `isCycleActive()`     | Returns true if cycle event is currently running            |

## Check Function Flow

```
check()
  │
  ├─ Helper enabled? ─────────────────── No ──→ return
  │
  ├─ Player exists? ──────────────────── No ──→ return
  │
  ├─ Haste config exists? ────────────── No ──→ return
  │
  ├─ Haste spell configured (id != 0)? ─ No ──→ return
  │
  ├─ Auto Haste enabled? ─────────────── No ──→ return
  │
  ├─ In Protection Zone? ─────────────── Yes ─→ return (if safecast disabled)
  │
  ├─ Spell data valid? ───────────────── No ──→ return
  │
  ├─ Already has haste buff? ─────────── Yes ─→ return
  │
  ├─ Health priority (needs healing)? ── Yes ─→ return
  │
  ├─ Spell on cooldown? ──────────────── Yes ─→ return
  │
  └─ All checks passed ──→ CAST SPELL
```

## Enable Guard (Spell Required)

### Problem (Before Fix)

```
1. User opens Tools tab
2. User enables Auto Haste (checkbox ON)
3. No spell selected yet → confusing state
4. User selects a haste spell
5. Nothing happens → must disable + re-enable
```

### Solution (After Fix)

```
toggle(true) now:
  │
  ├─ Check if spell id == 0
  │
  └─ If no spell selected:
          │
          ├─ Show error message: "Select a haste spell first!"
          │
          ├─ Uncheck the checkbox in UI
          │
          ├─ Sync shortcut panel to unchecked
          │
          └─ Return false (reject enable)
```

### toggle() Flow with Guard

```
toggle(checked)
      │
      ├─ Config exists? ─────────────────── No ──→ return false
      │
      ├─ checked AND spell id == 0? ─────── Yes ─→ REJECT
      │         │                                    │
      │         │                          ┌─────────┘
      │         │                          ▼
      │         │                   Show error message
      │         │                   Uncheck UI checkbox
      │         │                   Sync shortcut panel
      │         │                   return false
      │         │
      │         No
      │         │
      │         ▼
      └─ Continue with normal toggle logic...
```

### Expected Behavior (After Fix)

- User **must** select a spell before enabling Auto Haste
- Attempting to enable without spell shows clear error message
- Checkbox automatically unchecks if no spell selected
- No confusing "enabled but not working" state possible
- The feature behaves predictably and intuitively

## Advantages Over Previous System

| Aspect            | Old (eventTable polling) | New (event-driven)           |
| ----------------- | ------------------------ | ---------------------------- |
| CPU Usage         | Constant every 500ms     | Only when needed             |
| Reactivity        | Delayed (up to 500ms)    | Immediate on state change    |
| Self-cleanup      | Never stops              | Auto-stops when haste active |
| Login handling    | Starts immediately       | Checks if already has haste  |
| Toggle response   | Next poll cycle          | Immediate start/stop         |
| PZ awareness      | None                     | Responds to PZ cast toggle   |
| Enable guard      | None (confusing state)   | Rejects if no spell selected |

## Files

- `classes/auto_haste.lua` - Main module with all Auto Haste logic
- `helper.lua` - Contains onStatesChange connect and lifecycle hooks
