# BTCBot Targeting Module

**File:** `mods/game_bot/btcbot/targeting.lua`
**Global:** `BTCTargeting`

---

## Overview

The Targeting module controls the player's automatic movement in relation to the current attack target. It does not perform target selection — that is handled by `BTCAttack`. Targeting only decides whether and how to move the player closer to whatever creature `g_game.getAttackingCreature()` returns.

---

## Configuration

```lua
BTCTargeting.defaultConfig = {
  enabled = false,
  moveMode = "stand",          -- "stand" or "approach"
  onlyWhenAttacking = true,    -- only move when actively attacking a creature
  allowDiagonal = true,        -- allow diagonal movement steps
}
```

Config is persisted via `BTCConfig.get("targeting")` / `BTCConfig.set("targeting", ...)`.

---

## Movement Modes

### `"stand"` (default)

The player does not move automatically. Targeting's `execute()` returns immediately when `moveMode == "stand"`. This is appropriate for mages, paladins, and any ranged playstyle.

### `"approach"`

The player moves toward the currently attacked creature, trying to reach an adjacent tile (Chebyshev distance = 1). This is the primary mode for Knights who need to be on top of monsters to deal damage. The module calculates the best adjacent tile using `findApproachPosition()` and issues a single-step walk command per cooldown interval.

> Note: a legacy `"keepDistance"` mode was present in earlier versions but has been removed. Any saved config with `moveMode = "keepDistance"` is automatically reset to `"stand"` on load.

---

## `BTCTargeting.execute()`

Called every 100 ms by the main BTCBot loop. Execution flow:

1. Check `g_game.isOnline()`.
2. Check `config.moveMode` — return if `"stand"`.
3. Check `BTCAttack.config.enabled` — Targeting only moves when Attack is active.
4. Check `BTCTargeting.canMove()` — 200 ms movement cooldown.
5. Check `player:isWalking()` — skip if already walking.
6. **CaveBot integration check**: if CaveBot is active and `BTCCaveBot.shouldStopForMonsters()` returns `false`, Targeting does not interfere with CaveBot navigation.
7. Check `g_game.getAttackingCreature()` — if `onlyWhenAttacking` is true and no target is set, return.
8. Verify target is alive and on the same Z-level.
9. In `"approach"` mode: call `findApproachPosition()`, then `moveTo()` with the result.

---

## `BTCTargeting.findApproachPosition(playerPos, targetPos)`

Calculates the best tile to walk to in order to get adjacent to the target. Returns `nil` if the player is already adjacent (distance <= 1).

**Priority order of candidate tiles:**

1. Direct diagonal toward target (if both dx and dy are non-zero and `allowDiagonal` is true).
2. Horizontal move toward target.
3. Vertical move toward target.
4. Two alternative diagonals for obstacle avoidance (horizontal direction + ±1 vertical).
5. Two more alternatives (vertical direction + ±1 horizontal).

The first candidate that passes `BTCTargeting.isWalkable(pos)` is returned. If none pass the walkability check, the primary diagonal/cardinal direction is returned anyway (the server will block invalid moves).

---

## `BTCTargeting.moveTo(pos)`

Executes a single walk step toward `pos`.

1. Checks that the player is not already walking (`player:isWalking()`).
2. Computes the direction constant from the delta between `playerPos` and `pos`.
3. If `allowDiagonal` is `false`, converts diagonal directions to the dominant cardinal direction using `math.abs(dx) >= math.abs(dy)`.
4. Calls `g_game.walk(dir)`.
5. Updates `lastMoveTime` to the current millisecond timestamp.

Supported direction mappings:

| dx, dy | Direction |
|--------|-----------|
| 0, -1 | North |
| 1, -1 | NorthEast |
| 1, 0 | East |
| 1, 1 | SouthEast |
| 0, 1 | South |
| -1, 1 | SouthWest |
| -1, 0 | West |
| -1, -1 | NorthWest |

---

## `BTCTargeting.canMove()`

Returns `true` if at least `moveCooldown` (200 ms) has elapsed since the last move command.

```lua
function BTCTargeting.canMove()
  local now = g_clock.millis()
  return (now - BTCTargeting.lastMoveTime) >= BTCTargeting.moveCooldown
end
```

The 200 ms cooldown prevents flooding the server with walk packets when the player is already in motion.

---

## `BTCTargeting.getDistance(pos1, pos2)`

Chebyshev distance: `math.max(math.abs(dx), math.abs(dy))`. This matches Tibia's tile distance model where diagonal moves are distance 1.

---

## `BTCTargeting.isWalkable(pos)`

Checks the tile at `pos` via `g_map.getTile(pos)`. If the tile is not loaded, returns `true` (assumed walkable). Otherwise calls `tile:isWalkable(true)` — the `true` argument means creature presence is ignored.

---

## CaveBot Integration

Targeting explicitly yields to CaveBot when CaveBot is active and navigating:

```lua
if BTCCaveBot and BTCCaveBot.config and BTCCaveBot.config.enabled then
  if not BTCCaveBot.shouldStopForMonsters() then
    return  -- CaveBot is walking, targeting must not interfere
  end
end
```

This prevents the approach logic from fighting CaveBot's walk commands.

---

## Config Structure Reference

```lua
{
  enabled = false,           -- module on/off (not used to gate execution, Attack.enabled is used instead)
  moveMode = "stand",        -- "stand" | "approach"
  onlyWhenAttacking = true,  -- require g_game.getAttackingCreature() to return non-nil
  allowDiagonal = true,      -- permit NE/NW/SE/SW walk directions
}
```

---

## Comparison with Helper

| Feature | BTCTargeting | Helper Auto-Target |
|---------|-------------|-------------------|
| Movement toward target | Yes (approach mode) | No built-in auto-approach |
| Movement modes | 2 (stand, approach) | 8 modes (lure, standstill, etc.) |
| Diagonal toggle | Yes | N/A |
| CaveBot awareness | Yes (yields when CaveBot walks) | Depends on config |
| Only when attacking | Yes (configurable) | N/A |
| Distance-keeping | Not implemented | Not applicable |
