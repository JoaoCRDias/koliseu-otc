# BTCBot Map & Pathfinding API

## Overview

Map and pathfinding utilities are exposed through `G.botContext` (referred to as `context` in all function files). These functions are defined in `mods/game_bot/functions/map.lua` and wrap lower-level C++ engine calls (`g_map`, `g_game`). BTCBot modules call the engine APIs directly; the `context` functions are available for user Lua scripts running inside the older bot panel.

---

## Spectator / Creature Lookup

### `context.getSpectators(pos, multifloor)`

Wraps `g_map.getSpectators`. Returns all creatures currently visible from a given position.

```lua
-- All spectators around player position, same floor only
local creatures = context.getSpectators()

-- Specific position
local creatures = context.getSpectators({x=1000, y=1000, z=7})

-- Multi-floor (includes floors above/below)
local creatures = context.getSpectators(true)

-- Pattern match on creature name
local creatures = context.getSpectators("Dragon")
```

**Parameter resolution logic:**
- If `param1` is a `table` (position), it is used as the center position.
- If `param1` is a `userdata` (creature), that creature's position and direction are used.
- If `param1` is a `string`, calls `g_map.getSpectatorsByPattern(pos, pattern, direction)`.
- If `param1` is `true`, sets `multifloor = true`.

---

### `context.getCreatureById(id, multifloor)`

Iterates spectators around the player and returns the first creature matching the given numeric ID.

```lua
local creature = context.getCreatureById(12345)
local creature = context.getCreatureById(12345, true)  -- multifloor
```

Returns `nil` if not found.

---

### `context.getCreatureByName(name, multifloor)`

Case-insensitive name search among all spectators.

```lua
local dragon = context.getCreatureByName("Dragon")
```

Returns `nil` if not found.

---

## Pathfinding

### `context.findPath(startPos, destPos, maxDist, params)`

A* pathfinding from `startPos` to `destPos`. Returns a list of direction constants, or `nil` if no path exists.

- Both positions must be on the same Z-level (`startPos.z == destPos.z`).
- Default `maxDist` is `100` if not provided.
- Internally calls `context.findAllPaths` and then translates the result.

```lua
local dirs = context.findPath(
  context.pos(),
  {x=1050, y=1050, z=7},
  50,
  { ignoreCreatures = true, precision = 2 }
)
if dirs then
  g_game.autoWalk(dirs, {x=0,y=0,z=0})
end
```

---

### `context.findAllPaths(start, maxDist, params)`

Finds all reachable positions from `start` up to `maxDist` tiles away. Returns a path map table where keys are position strings (`"x,y,z"`) and values are node arrays.

```lua
local paths = context.findAllPaths(
  context.pos(),
  30,
  { ignoreNonWalkable = false }
)
```

Alias: `context.findEveryPath`

---

### `context.autoWalk(destination, maxDist, params)`

Finds a path to `destination` and immediately issues `g_game.autoWalk`. Returns `true` if a path was found and issued, `false` otherwise.

```lua
local success = context.autoWalk({x=1050, y=1050, z=7}, 50)
```

Can also accept a pre-computed direction list:
```lua
context.autoWalk({North, North, East, South})
```

---

## Pathfinding Parameters

All pathfinding functions accept an optional `params` table. Supported keys:

| Parameter | Type | Description |
|-----------|------|-------------|
| `ignoreLastCreature` | bool | Ignore the creature on the last tile of the path |
| `ignoreCreatures` | bool | Treat tiles with creatures as walkable |
| `ignoreNonPathable` | bool | Ignore non-pathable tile flags |
| `ignoreNonWalkable` | bool | Ignore non-walkable tile flags |
| `ignoreStairs` | bool | Do not use stairs/holes in path |
| `ignoreCost` | bool | All tiles have equal cost |
| `allowUnseen` | bool | Allow pathing through tiles not currently loaded |
| `allowOnlyVisibleTiles` | bool | Restrict to visible tiles only |
| `precision` | number | Expand search radius by N tiles around destination if exact tile is unreachable |
| `marginMin` | number | Minimum distance margin from destination (used with `marginMax`) |
| `marginMax` | number | Maximum distance margin from destination |
| `maxDistanceFrom` | table | `{pos, maxDist}` or `{x,y,z,maxDist}` — restrict to tiles near a reference |
| `destination` | string | Set automatically by `findPath` as `"x,y,z"` |

Boolean values are converted to `1`/`0` internally before being passed to the engine.

---

## Line-of-Sight and Tile Checks

### `context.canShoot(pos, distance)`

Returns whether a tile at `pos` can be targeted with a ranged attack from the player's position.

```lua
local canHit = context.canShoot({x=1005, y=1005, z=7}, 7)
```

Default distance is `5` if not provided. Wraps `tile:canShoot(distance)`.

---

### `context.isTrapped(creature)`

Returns `true` if the creature (defaults to local player) is completely surrounded by non-walkable tiles in all 8 cardinal and diagonal directions.

```lua
if context.isTrapped() then
  -- player is boxed in
end
```

Checks all 8 surrounding tiles using `tile:isWalkable(false)`.

---

## BTCTargeting Map Utilities

`BTCTargeting` (in `btcbot/targeting.lua`) provides two internal map helpers used exclusively for movement logic:

### `BTCTargeting.isWalkable(pos)`

Checks if a tile position can be walked on, ignoring creature presence.

```lua
-- From targeting.lua
local tile = g_map.getTile(pos)
if not tile then return true end  -- unloaded tile assumed walkable
return tile:isWalkable(true)      -- true = ignore creatures
```

Returns `true` if the tile is not loaded (assumed passable) or if `tile:isWalkable(true)` returns true.

---

### `BTCTargeting.getDistance(pos1, pos2)`

Calculates the Chebyshev (chessboard) distance between two positions. This is the standard distance metric used in Tibia — diagonal movement counts as 1 tile.

```lua
local dist = BTCTargeting.getDistance(playerPos, targetPos)
-- dist = math.max(math.abs(dx), math.abs(dy))
```

Returns `999` if either position is `nil`.

---

## Summary Table

| Function | Source | Wraps | Returns |
|----------|--------|-------|---------|
| `context.getSpectators(pos, mf)` | `map.lua` | `g_map.getSpectators` | creature list |
| `context.getCreatureById(id, mf)` | `map.lua` | spectator scan | creature or nil |
| `context.getCreatureByName(name, mf)` | `map.lua` | spectator scan | creature or nil |
| `context.findPath(s, d, dist, p)` | `map.lua` | `g_map.findEveryPath` | direction list or nil |
| `context.findAllPaths(s, dist, p)` | `map.lua` | `g_map.findEveryPath` | path map table |
| `context.autoWalk(dest, dist, p)` | `map.lua` | `g_game.autoWalk` | bool |
| `context.canShoot(pos, dist)` | `map.lua` | `tile:canShoot` | bool |
| `context.isTrapped(creature)` | `map.lua` | `tile:isWalkable` | bool |
| `BTCTargeting.isWalkable(pos)` | `targeting.lua` | `g_map.getTile` | bool |
| `BTCTargeting.getDistance(p1, p2)` | `targeting.lua` | math | number |
