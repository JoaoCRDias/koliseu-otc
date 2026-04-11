# BTCBot Tools Module

**File:** `mods/game_bot/btcbot/tools.lua`
**Global:** `BTCTools`

---

## Overview

The Tools module handles automatic casting of support spells: speed buffs, Magic Shield, combat stance buffs, condition cures, and familiar summoning. Each spell type has its own `enabled` toggle and is cast only when the corresponding player state is not already active. All casts are guarded by a 1000 ms per-spell-type cooldown.

---

## Default Configuration

```lua
BTCTools.defaultConfig = {
  enabled = false,
  haste        = { enabled = false, spell = "utani hur" },
  magicShield  = { enabled = false, spell = "utamo vita" },
  utitoTempo   = { enabled = false, spell = "utito tempo" },
  utamoTempo   = { enabled = false, spell = "utamo tempo" },
  sharpshooter = { enabled = false, spell = "utito tempo san" },
  swiftFoot    = { enabled = false, spell = "utamo tempo san" },
  protector    = { enabled = false, spell = "utamo tempo" },
  bloodRage    = { enabled = false, spell = "utito tempo" },
  charge       = { enabled = false, spell = "utani tempo hur" },
  strongHaste  = { enabled = false, spell = "utani gran hur" },
}
```

Config is persisted via `BTCConfig.get("tools")` / `BTCConfig.set("tools", ...)`.

---

## Player State Constants

BTCTools uses `bit.band` (or `bit32.band` on older Lua versions) to check active player states from `player:getStates()`.

```lua
local STATE_HASTE       = 64
local STATE_MANASHIELD  = 16
local STATE_NEWMANASHIELD = 67108864   -- newer protocol Magic Shield state
local STATE_PARTYBUFF   = 4096
local STATE_PARALYZE    = 32
```

### `BTCTools.hasState(state)`

Core check function:
```lua
local bitlib = bit or bit32
return bitlib.band(states, state) > 0
```

---

## State Detection Functions

| Function | State Bit | Description |
|----------|-----------|-------------|
| `BTCTools.hasHaste()` | `64` | Returns `true` if Haste is active |
| `BTCTools.hasManaShield()` | `16` OR `67108864` | Checks both old and new Magic Shield states |
| `BTCTools.hasPartyBuff()` | `4096` | Blood Rage, Protector, Sharpshooter, Swift Foot all share this bit |
| `BTCTools.isParalyzed()` | `32` | Returns `true` if paralyzed |

Note: `hasManaShield()` checks both state values because different server versions use different bits. It returns `true` if either is set.

---

## Supported Spell Categories

### Haste Spells

| Words | Name | Mana | Level | Vocation | Duration |
|-------|------|------|-------|----------|----------|
| `utani hur` | Haste | 60 | 14 | All | 33000 ms |
| `utani gran hur` | Strong Haste | 100 | 20 | Sorcerer, Druid (3,4,13,14) | 22000 ms |
| `utani tempo hur` | Charge | 100 | 25 | Knight (1,11) | 5000 ms |

`castHaste()` checks `hasHaste()` before casting. If Haste is already active, the function returns `false` immediately.

### Magic Shield

| Words | Name | Mana | Level | Vocation | Duration |
|-------|------|------|-------|----------|----------|
| `utamo vita` | Magic Shield | 50 | 14 | Sorcerer, Druid (3,4,13,14) | 200000 ms |

`castManaShield()` checks `hasManaShield()` before casting. Checks both state bits.

### Attack Buffs

| Words | Name | Mana | Level | Vocation | Duration |
|-------|------|------|-------|----------|----------|
| `utito tempo` | Blood Rage | 290 | 60 | Knight (1,11) | 10000 ms |
| `utito tempo san` | Sharpshooter | 450 | 60 | Paladin (2,12) | 10000 ms |

### Defense Buffs

| Words | Name | Mana | Level | Vocation | Duration |
|-------|------|------|-------|----------|----------|
| `utamo tempo` | Protector | 200 | 55 | Knight (1,11) | 13000 ms |
| `utamo tempo san` | Swift Foot | 400 | 55 | Paladin (2,12) | 10000 ms |

Attack and defense buffs use `castBuff()`, which checks `hasPartyBuff()`. If the `STATE_PARTYBUFF` bit is already set, no buff is cast (since all these buffs share the same state bit, only one can be active at a time).

### Condition Cure Spells

| Words | Name | Mana | Level | Vocation |
|-------|------|------|-------|----------|
| `exana pox` | Cure Poison | 30 | 10 | All |
| `exana flam` | Cure Burning | 30 | 30 | Knight, Pal, Sor, Dru (1,2,3,4,11,12,13,14) |
| `exana vis` | Cure Electrification | 30 | 22 | Knight, Pal, Sor, Dru (1,2,3,4,11,12,13,14) |
| `exana kor` | Cure Bleeding | 30 | 45 | Knight (1,11) |
| `exana amp res` | Remove Curse | 300 | 100 | Sorcerer, Druid (3,4,13,14) |

### Cancel Spells

| Words | Name | Mana | Level | Vocation |
|-------|------|------|-------|----------|
| `uteta reeq` | Cancel Invisibility | 200 | 26 | All |
| `uteta res eq` | Cancel Magic Shield | 50 | 14 | Sorcerer, Druid (3,4,13,14) |

### Familiars

| Words | Name | Mana | Level | Vocation | Duration |
|-------|------|------|-------|----------|----------|
| `utevo res dru` | Summon Grovebeast | 3000 | 200 | Druid (4,14) | 900000 ms |
| `utevo res sor` | Summon Skullfrost | 3000 | 200 | Sorcerer (3,13) | 900000 ms |
| `utevo res kni` | Summon Emberwing | 3000 | 200 | Knight (1,11) | 900000 ms |
| `utevo res pal` | Summon Thundergiant | 3000 | 200 | Paladin (2,12) | 900000 ms |

### Paladin Special

| Words | Name | Mana | Level | Vocation |
|-------|------|------|-------|----------|
| `utevo grav san` | Divine Dazzle | 80 | 250 | Paladin (2,12) |

---

## `BTCTools.canCast(spellKey)`

Returns `true` if at least `spellCooldown` (1000 ms) has elapsed since the last cast of this spell type.

```lua
BTCTools.spellCooldown = 1000

function BTCTools.canCast(spellKey)
  local now = g_clock.millis()
  local lastCast = BTCTools.lastCastTime[spellKey] or 0
  return (now - lastCast) >= BTCTools.spellCooldown
end
```

The `spellKey` is a string identifier per spell type (e.g., `"haste"`, `"magicShield"`, `"bloodRage"`). This prevents one module from spamming casts across multiple ticks.

---

## `BTCTools.getSpellInfo(spellWords)`

Searches all categories in `BTCTools.supportSpells` for a spell matching the given words string. Returns the spell definition table or `nil`.

```lua
local info = BTCTools.getSpellInfo("utani hur")
-- Returns: { words="utani hur", name="Haste", mana=60, level=14, voc={...}, duration=33000 }
```

---

## `BTCTools.canUseSpell(spellInfo)`

Checks if the current player vocation is in the spell's `voc` array. Returns `true` if the player vocation matches or if vocation is `0` (offline/unknown).

---

## Cast Functions

### `BTCTools.castHaste(spellKey, spellWords)`

1. Check `hasHaste()` — return if already active.
2. Check `canCast(spellKey)`.
3. Look up mana cost via `getSpellInfo`.
4. Check `player:getMana() >= mana`.
5. Check `canUseSpell`.
6. Call `g_game.talk(spellWords)` and update `lastCastTime`.

### `BTCTools.castManaShield(spellKey, spellWords)`

Same pattern as `castHaste`, but checks `hasManaShield()` instead.

### `BTCTools.castBuff(spellKey, spellWords)` (inferred from pattern)

Same pattern, checks `hasPartyBuff()`.

---

## Execution Flow

`BTCTools.execute()` iterates over all enabled spell categories in the config and calls the appropriate cast function for each. The 1000 ms per-spell-key cooldown ensures that no category spams the server even when mana is available and the state check passes.
