# BTCBot Follow / Movement Modes

## Overview

BTCBot does not have a dedicated "follow" module. Movement behavior is entirely managed by the `BTCTargeting` module, which operates on the currently attacked creature returned by `g_game.getAttackingCreature()`. There is no concept of following a specific player or maintaining formation with party members.

---

## Available Movement Modes

### Stand (`moveMode = "stand"`)

The player does not move automatically. `BTCTargeting.execute()` returns immediately when this mode is set. This is the default and is appropriate for:

- Sorcerers and Druids casting area spells.
- Paladins using ranged attacks.
- Any situation where staying at a fixed position is desired.

### Approach (`moveMode = "approach"`)

The player moves one step per 200 ms cooldown toward the currently attacked creature, trying to reach an adjacent tile (Chebyshev distance <= 1). Primarily designed for Knights who must stand on top of monsters.

The approach algorithm (`BTCTargeting.findApproachPosition`) tries candidate tiles in priority order:
1. Direct diagonal toward target.
2. Horizontal direct.
3. Vertical direct.
4. Alternative diagonals for obstacle avoidance.

---

## Movement Conditions

### `onlyWhenAttacking`

When `true` (default), the player only moves if `g_game.getAttackingCreature()` returns a non-nil, alive target. If `false`, the player approaches even without a locked attack target (not commonly useful).

### `allowDiagonal`

When `true` (default), diagonal walk directions (NE, NW, SE, SW) are used. When `false`, all movement is converted to the dominant cardinal direction before calling `g_game.walk()`.

### CaveBot Deference

When CaveBot is active and navigating (i.e., `BTCCaveBot.shouldStopForMonsters()` returns `false`), Targeting yields entirely and does not issue any walk commands. This prevents the two systems from conflicting over player movement.

---

## Filtering What to Attack (Attack Module)

The `BTCAttack` config controls which creatures become valid attack targets:

| Config | Default | Effect |
|--------|---------|--------|
| `attackMonsters` | `true` | Monsters are valid targets |
| `attackPlayers` | `false` | Players are valid targets |
| `attackRange` | `8` | Detection radius in tiles |
| `priorityList` | `{}` | Names attacked first |
| `ignoreList` | `{}` | Names never attacked |

The attack module sets the attacking creature via `g_game.setAttackingCreature()` when `autoAttack = true`. Targeting then uses that locked creature as its movement reference.

---

## `g_game.getAttackingCreature()`

Used by both `BTCTargeting` and `BTCCaveBot.shouldStopForMonsters()` to determine the current attack target. This is the canonical source of truth for "is the player currently fighting something."

```lua
local target = g_game.getAttackingCreature()
if target and not target:isDead() then
  -- valid attack target
end
```

---

## Comparison with Helper Auto-Target Modes

Helper/vBot implements 8 distinct targeting/follow modes. BTCTargeting covers a subset:

| Helper Mode | BTCBot Equivalent |
|------------|-----------------|
| Stand Still | `moveMode = "stand"` |
| Approach (go on top) | `moveMode = "approach"` |
| Keep Distance | Not implemented |
| Lure (flee when close) | Not implemented |
| Follow player | Not implemented |
| Chase (auto-follow attack target) | Partial — approach mode without locking |
| Diagonal Lure | Not implemented |
| Custom distance | Not implemented |

---

## Missing Features (vs. Helper)

- **Locked target concept**: BTCBot has no mechanism to "lock" a specific creature ID and exclusively attack it across ticks.
- **Multi-mode selection**: only two movement modes exist (stand / approach).
- **Keep-distance mode**: there is no mode that maintains a specific tile distance from the target.
- **Party follow**: no automatic movement toward a party leader.
- **Flee mode**: no retreat logic when HP drops below a threshold.

These features are tracked as a gap for future implementation. See `NEXTMOVEHELPERTOBTC.md` for the migration guide if applicable.

---

## Example: Setting Up Approach Mode for a Knight

1. Open the BTCBot panel, go to the Targeting tab.
2. Set movement mode to **Approach**.
3. Enable **Only when attacking** (recommended — avoids random movement when idle).
4. Enable **Allow diagonal** (recommended for smooth movement).
5. In the Attack tab, ensure `attackMonsters = true` and configure at least one spell slot.

When a monster enters range, Attack will lock it as the attack target. Targeting will then move the player one step at a time toward that creature until they are adjacent.
