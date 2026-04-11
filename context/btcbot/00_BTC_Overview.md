# BTCBot Overview

## What BTCBot Is

BTCBot is a modular, custom automation system located at `mods/game_bot/btcbot/`. It is designed as a replacement for or complement to the existing Helper/vBot systems, offering a clean separation of concerns through independent feature modules and a unified per-character JSON configuration store.

---

## Architecture

### Main Execution Loop

`BTCBot.execute()` is the central scheduler. It is started by `BTCBot.init()` via `scheduleEvent(BTCBot.execute, 100)`, meaning it fires approximately 10 times per second (every 100 ms). The loop re-schedules itself at the end of every tick — it never stops, even when the bot is disabled, because the CaveBot recording subsystem must continue running independently.

```lua
-- btcbot.lua
BTCBot.executeEvent = scheduleEvent(BTCBot.execute, 100)
```

When the player is offline, the loop skips all module execution but still re-schedules itself. When `BTCBot.enabled` is `false`, only `BTCCaveBot.checkRecording()` runs — all other modules are bypassed.

---

## Module Execution Order

Each tick, modules are called in the following fixed sequence:

| Order | Module | Global Table | Purpose |
|-------|--------|-------------|---------|
| 1 | Healing | `BTCHealing` | Self-heal via spell or potion |
| 2 | Heal Friend | `BTCHealFriend` | Heal party members or named friends |
| 3 | Mana | `BTCMana` | Auto-use mana potions |
| 4 | Attack | `BTCAttack` | Cast attack spells / use runes |
| 5 | Targeting | `BTCTargeting` | Movement toward current attack target |
| 6 | Tools | `BTCTools` | Cast support buffs (haste, shield, etc.) |
| 7 | Equipment | `BTCEquipment` | Auto-equip/unequip rings and amulets |
| 8 | CaveBot | `BTCCaveBot` | Navigate via waypoints |
| 9 | Time | `BTCTime` | Use timed items at fixed intervals |

After all modules execute, the loop reschedules itself:
```lua
BTCBot.executeEvent = scheduleEvent(BTCBot.execute, 100)
```

---

## Module Structure

Every module follows the same contract:

- **Global table**: e.g., `BTCHealing`, `BTCAttack`
- **`defaultConfig`**: table of default settings
- **`init()`**: called at load time; loads config from `BTCConfig`
- **`loadConfig()` / `saveConfig()`**: read/write via `BTCConfig.get(key)` / `BTCConfig.set(key, value)`
- **`execute()`**: called every 100 ms by the main loop
- **`createUI(parent)`**: builds the module's settings panel
- **`getStatus()`**: returns a short status string for the main UI

Each module can be enabled or disabled independently via its config `enabled` flag. Disabling a module causes its `execute()` to return immediately without doing anything.

---

## Config System

`BTCConfig` (defined in `btcbot/config.lua`) is the shared persistence layer. Key characteristics:

- **File path**: `/btcbot_settings.json` (inside the OTC user data directory)
- **Per-character storage**: the JSON root is keyed by character name. Each character has its own settings object.
- **API**:
  - `BTCConfig.get(key)` — returns the value for the current character
  - `BTCConfig.set(key, value)` — saves a value and immediately writes the file
  - `BTCConfig.reset()` — clears config for the current character
  - `BTCConfig.resetAll()` — clears config for all characters
  - `BTCConfig.checkCharacterChange()` — detects if the logged-in character changed and reloads
- **Auto-detection**: when the character name changes between calls to `getCharName()`, configs are automatically reloaded for the new character.

```lua
-- Reading a module config
local saved = BTCConfig.get("healing")

-- Writing a module config
BTCConfig.set("healing", BTCHealing.config)
```

Each module passes its own key string (e.g., `"attack"`, `"tools"`, `"cavebot"`).

---

## Shared Functions Layer

The `mods/game_bot/functions/` directory provides a scripting context available to Lua bot scripts via the `G.botContext` (`context`) object. Relevant files include:

| File | Exposes |
|------|---------|
| `player.lua` | `context.hp`, `context.mana`, `context.hppercent`, `context.pos`, `context.say`, `context.use`, `context.usewith`, `context.walk`, etc. |
| `map.lua` | `context.getSpectators`, `context.findPath`, `context.autoWalk`, `context.findAllPaths`, `context.canShoot`, `context.isTrapped`, `context.getCreatureById`, `context.getCreatureByName` |
| `main.lua` | `context.macro`, `context.hotkey`, `context.schedule` |

BTCBot modules do **not** use `context` directly — they call `g_game`, `g_map`, and `g_clock` APIs directly. The `context` layer is available for user-authored Lua scripts in the older bot panel system.

---

## How to Enable Modules Individually

Each module has an `enabled` boolean in its config. To enable a module independently:

1. Open the BTCBot UI panel.
2. Navigate to the module's tab.
3. Toggle the ON/OFF button for that module.
4. The config is saved immediately to `btcbot_settings.json`.

Programmatically:
```lua
BTCHealing.config.enabled = true
BTCHealing.saveConfig()
```

The main bot toggle (`BTCBot.enable()` / `BTCBot.disable()`) gates all modules at once but does not modify individual module configs.

---

## File Structure

```
mods/game_bot/btcbot/
  btcbot.lua        -- Main loop, module orchestration
  config.lua        -- Per-character JSON persistence
  healing.lua       -- Self-healing (3 slots: spell/potion)
  healfriend.lua    -- Party/friend healing
  mana.lua          -- Mana potion automation (3 slots)
  attack.lua        -- Attack spells and runes (6 slots)
  targeting.lua     -- Movement modes (stand / approach)
  tools.lua         -- Support buffs (haste, shield, buffs)
  equipment.lua     -- Auto ring/amulet based on HP/MP %
  cavebot.lua       -- Waypoint navigation system
  time.lua          -- Timed item usage (5 slots)
```

---

## Comparison with Helper (Monolithic vs. Modular)

| Aspect | BTCBot | Helper / vBot |
|--------|--------|---------------|
| Architecture | Modular — each feature is an independent Lua table | Monolithic — single large script file |
| Config storage | Per-character JSON file (`btcbot_settings.json`) | Mixed — uses `g_settings` and per-script storage |
| Enable/disable | Per-module granular toggle | Global enable/disable with feature flags |
| Attack system | 6 configurable spell slots with cooldown tracking | Target list with priority and multiple auto modes |
| Movement | Stand or Approach toward current target | 8 distinct targeting/follow modes |
| Training | Not implemented | Implemented (exercise dummy detection, mana threshold) |
| CaveBot | Built-in with recording mode | Separate module (cavebot_1.3 / vBot_4.8) |
| Execution rate | 100 ms fixed | Variable, macro-based |
| Vocation filtering | Present on all spell lists | Present in vBot/Helper |
