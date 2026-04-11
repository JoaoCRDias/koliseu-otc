# Helper Module — Map & Spatial System

## spectators Table

```lua
local spectators = {}
```

`spectators` is a module-level table keyed by creature ID (`[creature:getId()] = creature`). It tracks every visible **monster** on the current floor. It is populated and pruned exclusively through two creature event callbacks registered in `init()`:

```lua
connect(Creature, {
  onAppear    = onCreatureAppear,
  onDisappear = onCreatureDisappear,
})
```

### onCreatureAppear

```lua
function onCreatureAppear(creature)
  if creature:isPlayer() then return end
  if creature:getHealthPercent() <= 0 then return end
  if not spectators[creature:getId()] and creature:isMonster() then
    spectators[creature:getId()] = creature
  end
end
```

Rules for insertion:
- Players are excluded (early return).
- Dead creatures (healthPercent <= 0) are excluded.
- Only monsters (`creature:isMonster()`) are inserted.
- Summons are not explicitly excluded (the commented-out guard `-- if creature:isSummon() then return end` was removed), so summons that are classified as monsters may appear in the table.

### onCreatureDisappear

```lua
function onCreatureDisappear(creature)
  if spectators[creature:getId()] then
    spectators[creature:getId()] = nil
  end
end
```

The entry is simply set to `nil` — Lua garbage-collects it. This fires for any creature type so it is safe even for players (their IDs were never inserted).

---

## g_map.getSpectators — Used in checkAutoTarget

`checkAutoTarget` does **not** use the module-level `spectators` table. Instead it queries the map directly:

```lua
local specs = g_map.getSpectators(position, false)
for i, creature in pairs(specs) do
  if creature:isMonster() then
    table.insert(creatureList, {position = creature:getPosition(), creature = creature})
  end
end
```

- `position` is the local player's current position.
- The second argument `false` means "include only visible tiles" (not extended range).
- The result is filtered to monsters only before being inserted into the local `creatureList`.

This means `checkAutoTarget` always works with a fresh snapshot from the tile map, not the cached `spectators` table.

---

## g_map.getSpectators — Used in checkMagicShooter

`checkMagicShooter` uses the module-level `spectators` table (event-driven, not a fresh query):

```lua
for i, creature in pairs(spectators) do
  if creature:getPosition().z == position.z and getDistanceBetween(position, creature:getPosition()) <= 6 then
    creaturesAround = creaturesAround + 1
  end
  table.insert(creatureList, {position = creature:getPosition(), creature = creature})
end
```

All monsters in `spectators` are included in the AoE count list regardless of floor, but `creaturesAround` only increments for same-Z creatures within distance 6. The `creatureList` is passed to `countAttackableCreatures` and `findBestTarget`.

---

## g_map.isSightClear — Line of Sight Check

```lua
g_map.isSightClear(pos1, pos2)
```

Returns `true` if there is no wall or obstacle blocking the straight line between two positions. Used in three places:

| Location                   | pos1              | pos2                     | Purpose                                      |
|----------------------------|-------------------|--------------------------|----------------------------------------------|
| `checkAutoTarget`          | player position   | creature position        | Filter out monsters behind walls             |
| `countAttackableCreatures` | caster position   | each area-cell position  | Only count creatures the caster can see      |
| `findBestTarget` (runes)   | player position   | creature position        | Verify rune can reach best target            |
| `onFriendHealing`          | player position   | party member position    | Only heal members in line of sight           |
| `getExerciseDummy`         | dummy position    | player position          | Find the closest reachable exercise dummy    |

---

## g_map.getCreatureById — Resolving Target IDs

```lua
g_map.getCreatureById(id)
```

Used in `checkAutoTarget` to resolve a creature reference from the stored numeric ID:

```lua
local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0
  and g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil
```

And again after target selection to convert the chosen candidate ID into an attackable creature:

```lua
target = g_map.getCreatureById(closestTarget.id)
```

If the creature has despawned between detection and attack, `g_map.getCreatureById` returns `nil` and `g_game.attack` is never called.

---

## isWithinReach — Reach Check

```lua
local function isWithinReach(playerPos, targetPos)
  if type(targetPos) ~= "table" then return false end
  local deltaX = math.abs(playerPos.x - targetPos.x)
  local deltaY = math.abs(playerPos.y - targetPos.y)
  local withinX = deltaX <= 7
  local withinY = deltaY <= 5
  return withinX and withinY and playerPos.z == targetPos.z
end
```

- Asymmetric reach: **7 tiles** on X axis, **5 tiles** on Y axis.
- Z must match exactly — no cross-floor targeting.
- Called for every candidate creature before it is added to target lists or healed.
- Also called in `findBestTarget` to verify a rune can be thrown to the candidate tile.
- When `targetPos` is not a table (e.g. creature returned something unexpected), returns `false` safely.

---

## getDistanceBetween — Chebyshev Distance

```lua
local function getDistanceBetween(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end
```

Computes the Chebyshev (chessboard) distance — the larger of the absolute X and Y deltas. This is the standard Tibia tile distance used for melee/ranged range checks. Z is **not** included; floor checks are done separately.

Used in:
- `checkAutoTarget` — computing `creatureDistance` for closest/farthest targeting modes.
- `checkMagicShooter` — counting `creaturesAround` within distance 6.
- `getExerciseDummy` — sorting dummy candidates by proximity.

---

## positionCompare — Exact Position Equality

```lua
local function positionCompare(position1, position2)
  if not position1 or not position2 then return false end
  return position1.x == position2.x
     and position1.y == position2.y
     and position1.z == position2.z
end
```

Compares all three coordinates (X, Y, Z). Used inside `countAttackableCreatures` to check whether a creature in the `creatureList` occupies a specific area cell being evaluated.

---

## creature:getPosition() Usage Pattern

Position objects are plain Lua tables with fields `{x, y, z}`. The pattern used throughout:

```lua
local position = creature:getPosition()
-- position.x, position.y, position.z are integers
```

Stored in `creatureList` entries as:

```lua
{ position = creature:getPosition(), creature = creature }
```

This means the position is snapshotted at the time the list is built. If a creature moves during a 100ms cycle, the position may be stale until the next cycle.

---

## creature:canBeSeen() — Visibility Check in Magic Shooter

```lua
if not positionTarget or positionTarget.z ~= position.z or not target:canBeSeen() then
  goto continue
end
```

Used in `checkMagicShooter` for targeted spells. Even if a creature is in `spectators`, if it cannot currently be seen (e.g. it moved to a hidden tile), the spell is skipped.

---

## creatureList Construction Pattern

Both `checkMagicShooter` and `checkAutoTarget` build a local `creatureList` at the start of each cycle:

```lua
local creatureList = {}
-- checkMagicShooter (uses spectators):
for i, creature in pairs(spectators) do
  table.insert(creatureList, {position = creature:getPosition(), creature = creature})
end

-- checkAutoTarget (uses g_map.getSpectators):
local specs = g_map.getSpectators(position, false)
for i, creature in pairs(specs) do
  if creature:isMonster() then
    table.insert(creatureList, {position = creature:getPosition(), creature = creature})
  end
end
```

The list format `{position, creature}` is required by `countAttackableCreatures` and `findBestTarget`, which iterate it to match grid cells with creature locations.

---

## getRelativePosition — Large Creature Adjustment

```lua
function getRelativePosition(targetPos)
  local playerPos = player:getPosition()
  local relativePos = {x = targetPos.x, y = targetPos.y, z = targetPos.z}
  if playerPos.x < targetPos.x and playerPos.y < targetPos.y then
    relativePos.x = relativePos.x - 1; relativePos.y = relativePos.y - 1
  elseif (playerPos.x < targetPos.x and playerPos.y > targetPos.y) or playerPos.x < targetPos.x then
    relativePos.x = relativePos.x - 1
  elseif (playerPos.x > targetPos.x and playerPos.y < targetPos.y) or playerPos.y < targetPos.y then
    relativePos.y = relativePos.y - 1
  end
  return relativePos
end
```

Called in `checkMagicShooter` when `target:getCollisionSquare() > 1` — meaning the target occupies more than one tile (a large creature). The position is shifted by -1 on one or both axes toward the player, so AoE spells aimed at large monsters land on the correct tile.

---

## rotateArea — Direction-Aware AoE

```lua
local function rotateArea(area, direction)
```

Takes a 2D area array and rotates it to match the player's facing direction:
- `Directions.North` — no rotation (area is defined facing North)
- `Directions.South` — 180-degree flip (both axes reversed)
- `Directions.East` — 90-degree clockwise rotation
- `Directions.West` — 90-degree counter-clockwise rotation
- Diagonal directions (`SouthEast`, `NorthEast`) are normalized to `East`; `SouthWest` and `NorthWest` to `West` before rotation.

Used by `countAttackableCreatures` to align the spell's hit pattern with the actual player direction before mapping area cells to world positions.
