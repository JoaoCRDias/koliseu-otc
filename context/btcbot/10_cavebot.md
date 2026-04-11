# BTCBot CaveBot Module

**File:** `mods/game_bot/btcbot/cavebot.lua`
**Global:** `BTCCaveBot`

---

## Overview

BTCCaveBot is a waypoint-based navigation system. It moves the player through a pre-defined list of positions, handles floor transitions (stairs, ropes, shovels), uses world objects, and can stop to fight monsters before continuing. Recording mode captures player movement automatically.

---

## Default Configuration

```lua
BTCCaveBot.defaultConfig = {
  enabled = false,
  walkDelay = 100,
  waypoints = {},
  currentIndex = 1,
  loopEnabled = true,
  minMonstersToStop = 1,   -- 0 = never stop for monsters
}
```

`currentIndex` and `enabled` are always reset to `1` / `false` on load (they are not persisted across sessions).

---

## Waypoint Types

| Type | Constant | Purpose |
|------|----------|---------|
| `"walk"` | `WALK` | Move the player to this position using pathfinding |
| `"use"` | `USE` | Use a world object at this position (lever, hole, door) |
| `"usewith"` | `USEWITH` | Use an inventory item on an object at this position |
| `"label"` | `LABEL` | Named jump target; no movement action |
| `"stand"` | `STAND` | Wait at this position until the condition clears |
| `"rope"` | `ROPE` | Use Rope (item ID 3003) on a rope spot hole |
| `"shovel"` | `SHOVEL` | Use Shovel (item ID 3457) on a hole tile |
| `"stairs"` | `STAIRS` | Step directly onto the stair tile to change floors |

Rope and Shovel item IDs:
```lua
BTCCaveBot.ROPE_ID   = 3003
BTCCaveBot.SHOVEL_ID = 3457
```

---

## Waypoint Data Structure

Each waypoint in `config.waypoints` is a table:

```lua
{
  type  = "walk",    -- one of the WaypointTypes constants
  x     = 1050,      -- world X coordinate
  y     = 985,       -- world Y coordinate
  z     = 7,         -- floor (Z level)
  extra = "",        -- label name (for LABEL type) or additional data
}
```

---

## Waypoint Management Functions

### `BTCCaveBot.addWaypoint(waypointType, x, y, z, extra)`

Appends a new waypoint to the list, saves config, and refreshes the UI list.

### `BTCCaveBot.removeWaypoint(index)`

Removes the waypoint at the given 1-based index. Adjusts `currentIndex` and `selectedIndex` if they exceed the new list length.

### `BTCCaveBot.removeSelectedWaypoint()`

Removes the currently selected waypoint in the UI.

### `BTCCaveBot.moveWaypointUp(index)` / `BTCCaveBot.moveWaypointDown(index)`

Swaps the waypoint at `index` with the one above or below. Updates `currentIndex` if the executing or adjacent waypoint is affected.

### `BTCCaveBot.moveSelectedUp()` / `BTCCaveBot.moveSelectedDown()`

Operate on the UI-selected waypoint index.

### `BTCCaveBot.clearWaypoints()`

Removes all waypoints, resets `currentIndex` to 1, saves, and refreshes UI.

---

## Loop / Stop Modes

| Config | Value | Behavior |
|--------|-------|---------|
| `loopEnabled` | `true` | After the last waypoint, wrap back to waypoint 1 and repeat indefinitely |
| `loopEnabled` | `false` | Stop CaveBot after completing all waypoints once |

---

## Monster Threshold: `shouldStopForMonsters()`

Controls whether the bot pauses navigation to fight before continuing.

```lua
function BTCCaveBot.shouldStopForMonsters()
  local minMonsters = BTCCaveBot.config.minMonstersToStop or 1

  -- 0 = never stop
  if minMonsters <= 0 then return false end

  local monsterCount = BTCCaveBot.countMonstersNearby()

  if monsterCount < minMonsters then
    BTCCaveBot.monsterStuckTime = nil
    return false
  end

  -- Monsters present — check if actively attacking
  local attackedCreature = g_game.getAttackingCreature()
  if attackedCreature then return true end

  -- Monsters visible but no attack target — start a 3-second timer
  -- If no attack target after 3 seconds, assume unreachable and resume walking
  if (now - BTCCaveBot.monsterStuckTime) > 3000 then
    return false   -- resume cavebot
  end

  return true  -- still waiting for attack lock
end
```

Setting `minMonstersToStop = 0` makes CaveBot ignore all monsters and walk through without pausing.

---

## Stuck Detection

Two independent stuck counters:

| Variable | Threshold | Reset Trigger | Action on Threshold |
|----------|-----------|---------------|---------------------|
| `retryCount` | 10 per waypoint | Successful step | Advance to next waypoint |
| `stuckCount` / `maxStuckCount` | 30 failed moves | Position change detected | Reset `currentIndex` to 1 |

The `samePositionCount` counter tracks how many consecutive ticks the player was at the same position. When `maxStuckCount` (30) is reached — equivalent to approximately 3 seconds of being completely stuck — the bot resets to waypoint 1.

---

## Walk Timing

| Parameter | Value | Description |
|-----------|-------|-------------|
| `walkCooldown` | 200 ms | Minimum time between walk commands |
| `walkDelay` (config) | 100 ms | Default config value (used for future tuning) |

---

## `BTCCaveBot.execute()`

Main navigation loop:

1. Check online, config initialized, enabled.
2. Check waypoints list is not empty.
3. Call `shouldStopForMonsters()` — if returns `true`, return without moving.
4. Call `executeCurrentWaypoint()`.

### `executeCurrentWaypoint()`

Dispatches to the appropriate executor based on `waypoints[currentIndex].type`:

- `WALK` → `executeWalk(waypoint)` — pathfinding-based walk to position.
- `USE` → `executeUse(waypoint)` — use world object at position.
- `USEWITH` → use inventory item on target position.
- `LABEL` → `executeLabel(waypoint)` — jump to another label by name.
- `STAND` → `executeStand(waypoint)` — wait at position.
- `ROPE` → `executeRope(waypoint)` — use rope on hole.
- `SHOVEL` → `executeShovel(waypoint)` — use shovel on hole.
- `STAIRS` → `executeStairs(waypoint)` — walk onto stair tile.

---

## Recording Mode

### `BTCCaveBot.toggleRecording()`

Enables or disables path recording. Returns the new state.

```lua
BTCCaveBot.toggleRecording()
```

### `BTCCaveBot.checkRecording()`

Called every 100 ms by `BTCBot.execute()` **even when the bot is disabled**, to ensure recording works independently.

Recording logic:
- When the player moves 3 or more tiles from the last recorded position, a `WALK` waypoint is automatically added.
- When the player changes Z-level (floor change via stairs/rope/hole), a `STAIRS` waypoint is added at the last known position on the previous floor, then a `WALK` waypoint at the new position.

Distance threshold for recording: 3 tiles (Chebyshev distance).

---

## Emplacement System

When manually adding waypoints, an "emplacement" offset can be applied to position the waypoint relative to the player's current tile.

```lua
BTCCaveBot.EmplacementTypes = {
  CENTER    = "center",    -- offset (0, 0)
  NORTH     = "north",     -- offset (0, -1)
  SOUTH     = "south",     -- offset (0, +1)
  EAST      = "east",      -- offset (+1, 0)
  WEST      = "west",      -- offset (-1, 0)
  NORTHEAST = "northeast", -- offset (+1, -1)
  NORTHWEST = "northwest", -- offset (-1, -1)
  SOUTHEAST = "southeast", -- offset (+1, +1)
  SOUTHWEST = "southwest", -- offset (-1, +1)
}
```

`BTCCaveBot.addCurrentPositionWaypoint(waypointType, extra)` reads the current emplacement, applies the offset to the player's position, and adds the waypoint at the resulting coordinates.

---

## UI: Waypoint List

The waypoint list widget (`BTCCaveBot.waypointListWidget`) shows up to 5 waypoints at a time using a sliding window. Auto-scroll behavior:

- **Bot running**: the window follows `currentIndex` (the actively executing waypoint).
- **Bot stopped**: the window follows `selectedIndex` (the UI-highlighted waypoint).

Waypoint display format in the list:

```
[prefix] [index] [TYPE] [x,y,z or label text]
```

Prefix symbols:
- `>>` — currently executing AND selected.
- `> ` — currently executing (bot running).
- `* ` — selected (bot stopped).

---

## Complete Configuration Reference

```lua
{
  enabled = false,             -- reset to false on load
  walkDelay = 100,             -- ms (reserved for timing tuning)
  waypoints = { ... },         -- array of waypoint objects
  currentIndex = 1,            -- reset to 1 on load
  loopEnabled = true,          -- repeat waypoints or stop
  minMonstersToStop = 1,       -- 0 = never stop; N = stop when N+ monsters nearby
}
```
