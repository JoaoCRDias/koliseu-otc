# Helper Module — Overview

## What the Helper Is

The Helper is a single-file automation module for the OTClient (RadBR fork). It lives at:

```
mods/game_helper/helper.lua   (~4080 lines)
```

It provides a fully self-contained set of gameplay automation features:
- Health and mana healing (spells + potions)
- Friend/party healing
- Auto-haste
- Magic shooter (RTCaster) — automated spell and rune casting
- Auto-target — automated target selection with 9 selectable modes
- Auto-eat food
- Auto-change gold to platinum (and reverse)
- Training spell automation
- Exercise dummy automation

The module exposes a floating helper window with three tabs (Healing, Tools, Shooter) and a detachable HelperTracker widget that shows live status.

---

## Architecture: Event-Driven Cycle

All automation runs through a single repeating cycle event started on login:

```lua
helperEvents.helperCycleEvent = cycleEvent(helperCycleEvent, helperEvents.helperCycleTimer)
-- helperCycleTimer = 50 (ms)
```

The master loop function `helperCycleEvent()` runs every 50 ms. On each tick it increments every timer in the `timers` table by 50. When a timer reaches or exceeds its configured interval, the timer resets to 0 and the corresponding action function is called via `pcall` (so a single broken event cannot stop the cycle).

```lua
function helperCycleEvent()
  for eventName, eventData in pairs(eventTable) do
    timers[eventName] = timers[eventName] + helperEvents.helperCycleTimer
    if timers[eventName] >= eventData.interval then
      timers[eventName] = 0
      local func = eventData.action
      if func and type(func) == "function" then
        local ok, err = pcall(func)
        -- errors are logged via g_logger.warning, not re-raised
      end
    end
  end
end
```

---

## eventTable Structure

Each entry in `eventTable` has two fields:

| Field      | Type       | Purpose                                          |
|------------|------------|--------------------------------------------------|
| `interval` | number (ms)| How often the action runs, relative to the 50ms tick |
| `action`   | function   | The function to call when the interval elapses   |

Each action is assigned immediately after its function is defined in the file, e.g.:

```lua
eventTable.checkHealthHealing.action = checkHealthHealing
```

### Registered Events and Intervals

| Event Name           | Interval  | Action Function         |
|----------------------|-----------|-------------------------|
| `checkHealthHealing` | 250 ms    | `checkHealthHealing()`  |
| `checkMana`          | 100 ms    | `checkMana()`           |
| `routineChecks`      | 1000 ms   | `routineChecks()`       |
| `checkFriendHealing` | 250 ms    | `checkFriendHealing()`  |
| `checkAutoHaste`     | 500 ms    | `checkAutoHaste()`      |
| `checkMagicShooter`  | 100 ms    | `checkMagicShooter()`   |
| `checkAutoTarget`    | 250 ms    | `checkAutoTarget()`     |
| `checkExerciseEvent` | 10000 ms  | `checkExerciseEvent()`  |

The corresponding `timers` table tracks accumulated time for each event:

```lua
local timers = {
  checkHealthHealing = 0,
  checkMana = 0,
  routineChecks = 0,
  checkFriendHealing = 0,
  checkAutoHaste = 0,
  checkMagicShooter = 0,
  checkAutoTarget = 0,
  checkExerciseEvent = 0
}
```

---

## helperConfig Global Structure

`helperConfig` is the single global table persisted to JSON per-character. All automation state lives here.

```lua
helperConfig = {
  -- Health healing spells (3 slots)
  spells = {
    { id = 0, percent = 80 },
    { id = 0, percent = 80 },
    { id = 0, percent = 80 }
  },

  -- Potions (3 slots, health or mana, with priority flag)
  potions = {
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 },
    { id = 0, percent = 50, priority = 0 }
  },

  -- Training spell (1 slot)
  training = {
    { id = 0, percent = 0, enabled = false }
  },

  -- Auto-haste (1 slot)
  haste = {
    { id = 0, enabled = false, safecast = false }
  },

  -- Friend healing via Sio/UH/Tio Sio (2 slots)
  friendhealing = {
    { name = "", percent = 0, enabled = false },
    { name = "", percent = 0, enabled = false }
  },

  -- Friend healing via Gran Sio (2 slots)
  gransiohealing = {
    { name = "", percent = 0, enabled = false },
    { name = "", percent = 0, enabled = false }
  },

  -- Shooter profiles (named map, at least "Default" always present)
  shooterProfiles = {
    ["Default"] = defaultShooterProfile
  },
  selectedShooterProfile = "Default",

  -- Feature flags
  terms = false,
  autoEatFood = false,
  autoChangeGold = false,
  magicShooterEnabled = false,
  magicShooterOnHold = false,  -- temporary pause for rune/potion use
  autoTargetEnabled = false,
  autoTargetMode = 6,          -- default = mode F (closestLowestHealth)
  currentLockedTargetId = 0    -- 0 = no lock
}
```

### Potion Priority Field

| Value | Meaning                                   |
|-------|-------------------------------------------|
| 0     | Unset / neutral (follows type: health/mana) |
| 1     | Force treat as health potion (Great Spirit / Ultimate Spirit) |
| 2     | Force treat as mana potion (Great Spirit / Ultimate Spirit)   |

---

## hotkeyHelperStatus — Master On/Off Switch

```lua
local hotkeyHelperStatus = false
```

This local boolean is the **master gate** for all automation. Nearly every event function begins with:

```lua
if not hotkeyHelperStatus then return end
```

It is toggled by the `botStatus()` function, which is wired to the **Pause** key by default via the Keybind API. Toggling it displays a game message ("Helper Status: Enabled / Disabled") and updates both the helper window status indicator and the HelperTracker widget.

---

## Keybind API Integration

On `init()`, the Helper registers 5 keybinds via the `Keybind` API (OTClient Redemption):

| Action Name                              | Default Key | Callback                                    |
|------------------------------------------|-------------|---------------------------------------------|
| Enable/Disable Helper                    | Pause       | `botStatus()`                               |
| Enable/Disable Auto Target               | (none)      | toggle `enableAutoTarget` + `toggleAutoTarget()` |
| Enable/Disable Magic Shooter             | (none)      | toggle `enableMagicShooter` + `toggleMagicShooter()` |
| Enable/Disable Target and Magic Shooter  | (none)      | toggle both simultaneously                  |
| Change Shooter Preset                    | (none)      | `toggleShooterPreset()`                     |

All keybinds use `KEY_PRESS` type and are bound to the root widget. They are cleaned up in `terminate()` via `Keybind.delete()`.

A custom hotkey assignment UI (`manageHotkeys()`) is also available in the Helper UI, which opens an `ActionAssignWindow` dialog and writes the chosen key to both Chat-On and Chat-Off modes.

---

## Dependencies

| Module / Global          | Usage                                                    |
|--------------------------|----------------------------------------------------------|
| `modules.game_interface` | Root panel, `addToPanels` for HelperTracker             |
| `Spells`                 | `getSpellByClientId`, `getRuneSpellByItem`, cooldown     |
| `SpellAreas`             | `AREA_CIRCLE3X3`, `AREA_CIRCLE2X2`, `AREA_SQUAREWAVE*`   |
| `SpellInfo.Default`      | Spell name/data table for assignSpell UI                 |
| `SpelllistSettings`      | Icon file source path for spell buttons                  |
| `SpellIcons`             | Maps icon index to client spell ID for image lookup      |
| `g_map`                  | `getSpectators`, `isSightClear`, `getCreatureById`, `findItemsById` |
| `g_game`                 | `getLocalPlayer`, `attack`, `talk`, `useInventoryItem*`  |
| `g_clock`                | `millis()` — used for all cooldown timestamps            |
| `g_resources`            | `writeFileContents` / `readFileContents` for save/load   |
| `modules.game_party_list`| `getUpcomingPartyMembers()` for friend healing           |
| `LoadedPlayer`           | `getId()`, `isLoaded()` — for per-character save path   |
| `json`                   | `encode` / `decode` for settings persistence            |

---

## Key Local Variables

| Variable              | Type    | Purpose                                               |
|-----------------------|---------|-------------------------------------------------------|
| `player`              | userdata| Local player reference, refreshed in `online()`      |
| `spectators`          | table   | Map of `[creatureId] = creature` for monsters on screen |
| `spellsCooldown`      | table   | `[spellId or "food"/"potion"] = expiryTimestamp`      |
| `groupsCooldown`      | table   | `[groupId] = expiryTimestamp`                         |
| `timers`              | table   | Accumulated ms per event name                         |
| `multiUseExDelay`     | number  | Timestamp until next use-with action is allowed       |
| `autoTargetOnHold`    | boolean | When true, skips both auto-target and magic shooter   |
| `lastHaste`           | number  | Timestamp of last haste cast (local in haste section) |

---

## Lifecycle

```
init()
  └── connect signals (LocalPlayer, g_game, Creature)
  └── register keybinds
  └── build UI panels (helper, helperTracker, helperRules)
  └── if already online → online()

online()   (triggered by onGameStart)
  └── player = g_game.getLocalPlayer()
  └── reset()            -- clear all UI slots
  └── loadSettings()     -- read helperConfig from JSON
  └── loadProfileOptions() -- populate presets combobox
  └── onLoadHelperData() -- restore UI from helperConfig
  └── helperCycleEvent = cycleEvent(helperCycleEvent, 50ms)

  [50ms loop: helperCycleEvent() dispatches all events]

offline()  (triggered by onGameEnd)
  └── removeEvent(helperCycleEvent)
  └── hide()
  └── helperTracker:close()

terminate()
  └── Keybind.delete (all 5 binds)
  └── disconnect all signals
  └── helper:destroy()
```

Settings are saved to `/characterdata/<playerId>/helper.json` on `hide()` and loaded on `online()`.
