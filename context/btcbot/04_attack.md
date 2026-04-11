# BTCBot Attack Module

**File:** `mods/game_bot/btcbot/attack.lua`
**Global:** `BTCAttack`

---

## Overview

The Attack module manages automated combat spells and attack runes. It provides 6 independent, configurable spell slots. Each slot can be a typed spell (cast by saying spell words via `g_game.talk`) or an attack rune (used via `g_game.useInventoryItemWith`). The module handles cooldown tracking using real server-side spell cooldown data where available, and falls back to client-side timers.

---

## Default Configuration

```lua
BTCAttack.defaultConfig = {
  enabled = true,
  autoAttack = true,
  attackPlayers = false,
  attackMonsters = true,
  attackRange = 8,        -- tile radius for monster/player detection
  spells = {
    -- 6 slots, all disabled by default
    { enabled = false, type = "spell", words = "", cooldown = 2000,
      manaCost = 0, spellId = 0, iconId = 0, itemId = 0, lastUsed = 0 },
    -- ... (slots 2-6 identical)
  },
  priorityList = {},      -- creature names to attack first
  ignoreList = {},        -- creature names to never attack
}
```

Config is loaded from `BTCConfig.get("attack")` and `lastUsed` timestamps are always reset to `0` on load (so cooldowns do not persist across sessions).

---

## Spell Slot Fields

Each spell slot in `config.spells` has the following fields:

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Whether this slot is active |
| `type` | string | `"spell"` or `"rune"` |
| `words` | string | Spell incantation (for type `"spell"`) |
| `cooldown` | number | Client-side cooldown in ms (fallback) |
| `manaCost` | number | Mana required to cast |
| `spellId` | number | Server-side spell ID (used for real cooldown check) |
| `iconId` | number | Client sprite ID for UI cooldown bar rendering |
| `itemId` | number | Item ID for rune slots |
| `lastUsed` | number | Timestamp of last cast (reset on init) |

---

## `BTCAttack.execute()`

The main attack loop, called every 100 ms. After execution, `BTCAttack.updateCooldownUI()` is also called by the orchestrator to refresh the visual cooldown bars.

**Execution flow:**
1. Check online status and `config.enabled`.
2. Check global attack cooldown (`canAttack()` — 100 ms between attempts).
3. Retrieve current attack target via `g_game.getAttackingCreature()`.
4. For each enabled spell slot (in order 1 → 6):
   - Check `isSpellReady(slotIndex)` (server cooldown or client-side timer).
   - Check mana availability.
   - Execute the spell.
   - Break after first successful cast.

---

## Attack Range and Targeting Flags

| Config | Default | Description |
|--------|---------|-------------|
| `attackRange` | `8` | Radius in tiles to scan for valid targets |
| `attackMonsters` | `true` | Include monsters in target scan |
| `attackPlayers` | `false` | Include players in target scan |
| `autoAttack` | `true` | Automatically select and set attack target |

---

## Priority and Ignore Lists

- **`priorityList`**: list of creature names (strings). When scanning for targets, creatures matching names in this list are preferred.
- **`ignoreList`**: list of creature names. Creatures matching names here are never selected as targets, even if they are within `attackRange`.

---

## Cooldown Tracking

### Server-Side (preferred)

`BTCAttack.isSpellReady(slotIndex)` first attempts to use the real server cooldown data via the client's `SpellInfo` system. It uses `spell.spellId` and `spell.groups` (spell group IDs, e.g., group 1 = attack group) to check if the spell's group is currently on cooldown.

### Client-Side (fallback)

If `spellId` is `0` or `SpellInfo` is unavailable, the module falls back to comparing `g_clock.millis() - spell.lastUsed >= spell.cooldown`.

### Global Attack Cooldown

A separate 100 ms guard (`BTCAttack.attackCooldown`) prevents more than one spell attempt per tick, even if multiple slots are ready.

```lua
BTCAttack.attackCooldown = 100   -- ms between cast attempts
```

---

## `BTCAttack.getAvailableSpells()`

Returns a filtered list of attack spells available to the current character's vocation. Uses the client's `SpellInfo["Default"]` table and filters by:

1. `group == 1` (attack group only).
2. Vocation match using a mapping table that converts client vocation IDs to SpellInfo vocation IDs.

**Vocation ID mapping (client → SpellInfo):**

| Client ID | Vocation | SpellInfo IDs |
|-----------|----------|---------------|
| 1 | Knight | 4, 8 (EK) |
| 2 | Paladin | 3, 7 (RP) |
| 3 | Sorcerer | 1, 5 (MS) |
| 4 | Druid | 2, 6 (ED) |
| 5 | Monk | 9, 10 (ExMonk) |
| 11-15 | Promoted | same as base |

The result is sorted by spell level ascending.

---

## `BTCAttack.getPlayerVocation()`

Reads vocation from the local player object:
```lua
return player:getVocation() or 0
```
Returns `0` if offline.

---

## Attack Runes

The following rune item IDs are built into the module's `BTCAttack.attackRunes` table:

| Item ID | Short Name | Full Name |
|---------|-----------|-----------|
| 3155 | SD | Sudden Death Rune |
| 3161 | HMM | Heavy Magic Missile |
| 3180 | FB | Fireball Rune |
| 3178 | GFB | Great Fireball Rune |
| 3191 | Explosion | Explosion Rune |
| 3200 | Thunderstorm | Thunderstorm Rune |
| 3202 | Stoneshower | Stoneshower Rune |
| 3198 | Avalanche | Avalanche Rune |
| 3164 | Icicle | Icicle Rune |
| 3149 | Energy Bomb | Energy Bomb Rune |
| 3175 | Fire Bomb | Fire Bomb Rune |

Rune slots use `g_game.useInventoryItemWith(itemId, target, 0)` where `target` is the attacking creature object.

---

## Config Migration

`BTCAttack.migrateOldConfigs()` runs at init time. For any saved spell slot that has `words` set but `spellId == 0`, it attempts to look up the spell in `SpellInfo` by words and backfill `spellId`, `iconId`, and `groups`. This keeps old configs compatible after the real-cooldown system was added.

---

## UI Cooldown Bars

`BTCAttack.spellSlotWidgets` holds references to the 6 spell slot UI widgets. `BTCAttack.updateCooldownUI()` is called by the main orchestrator after `execute()` to visually update the cooldown progress for each slot using the `iconId` sprite.

---

## Auto-Attack vs. Target Selection

`autoAttack = true` means the module will call `g_game.setAttackingCreature()` automatically when a valid target is found in range. If `autoAttack = false`, the module only casts if a target is already set (e.g., player manually clicked a creature).

The attack system does not implement "locked target" semantics — it scans for the best available target each tick based on `priorityList`, `ignoreList`, `attackMonsters`, `attackPlayers`, and `attackRange`.
