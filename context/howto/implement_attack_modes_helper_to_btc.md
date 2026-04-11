# HowTo: Implement the Helper's Auto-Target Modes in BTCBot

## Overview

This guide walks through adding the Helper's nine auto-target modes to `BTCAttack`. Currently BTCBot attacks the nearest available monster with no strategy. The Helper implements a mode selector that computes nine candidate targets in a single pass and picks one based on the configured mode.

**Modes to add:**

| Mode | Description |
|------|-------------|
| A | Closest target |
| B | Farthest target |
| C | Lowest HP% target |
| D | Highest HP% target |
| E | Best AoE position (max creatures in spell circle) |
| F | Closest + Lowest HP (recommended default) |
| G | Closest + Highest HP |
| H | Farthest + Lowest HP |
| I | Farthest + Highest HP |

**Why this improves BTCBot:**
- Knights benefit from mode F or A (stay on the weakest close monster)
- Druids and Sorcerers benefit from mode E (maximize AoE damage)
- Paladins benefit from mode C (eliminate wounded targets to reduce incoming damage)
- Mode G is useful for training on a specific high-HP creature

---

## Understanding the Source

### How `checkAutoTarget()` Works in `helper.lua` (Lines 2614–2752)

The function runs on a 250ms interval. Every call:

1. **Guards:** Checks `hotkeyHelperStatus`, `autoTargetEnabled`, `autoTargetOnHold`, PZ, and the locked target.
2. **Single-pass computation:** Iterates every monster returned by `g_map.getSpectators()`, filters by `isWithinReach()` and `g_map.isSightClear()`, and updates all nine candidate variables simultaneously:
   ```lua
   -- All nine updated in the same loop iteration:
   closestTarget, farthestTarget,
   lowestHealthTarget, highestHealthTarget,
   bestTarget,                    -- Mode E
   closestLowestHealthTarget,     -- Mode F
   closestHighestHealthTarget,    -- Mode G
   farthestLowestHealthTarget,    -- Mode H
   farthestHighestHealthTarget    -- Mode I
   ```
3. **Mode selection:** After the loop, reads `helperConfig.autoTargetMode` (an integer 1–9) and resolves the corresponding variable to a creature ID.
4. **Attack:** Calls `g_game.attack(target)` only if the selected target differs from the currently attacking creature.

**Core loop (simplified from helper.lua lines 2676–2721):**
```lua
for i, creatureData in pairs(creatureList) do
  if not isWithinReach(position, creatureData.position) then goto continue end
  if not g_map.isSightClear(position, creatureData.position) then goto continue end

  local health = creatureData.creature:getHealthPercent()
  local dist   = getDistanceBetween(position, creatureData.position)

  -- Update all nine candidates in one pass:
  if lowestHealthTarget.id == nil then lowestHealthTarget = {...} end
  if health < lowestHealthTarget.health  then lowestHealthTarget  = {...} end
  if health > highestHealthTarget.health then highestHealthTarget = {...} end
  if dist < closestTarget.distance then closestTarget = {...} end
  if dist > farthestTarget.distance then farthestTarget = {...} end
  -- ... (closestLowest, closestHighest, farthestLowest, farthestHighest)

  -- Mode E: count creatures hit by a circle at this position
  local creaturesHit = countAttackableCreatures(creatureData.position, 1, area, creatureList, true)
  if creaturesHit > maxCreaturesHit then
    maxCreaturesHit = creaturesHit
    bestTarget = { id = creatureData.creature:getId(), creatures = creaturesHit }
  end
  ::continue::
end
```

**Key functions used:**
- `isWithinReach(playerPos, targetPos)` — returns true if within 7x5 tiles on the same floor
- `getDistanceBetween(p1, p2)` — Chebyshev distance (`math.max(|dx|, |dy|)`)
- `countAttackableCreatures(pos, dir, area, list, useTarget)` — counts creatures hit by an AoE area
- `SpellAreas.AREA_CIRCLE3X3` — 3x3 circle area table (used for most vocations); `AREA_CIRCLE2X2` for paladins

---

## Step 1: Add `targetMode` to `BTCAttack.defaultConfig`

Open `mods/game_bot/btcbot/attack.lua`. Inside `BTCAttack.defaultConfig`, add:

```lua
BTCAttack.defaultConfig = {
  enabled       = true,
  autoAttack    = true,
  attackPlayers = false,
  attackMonsters= true,
  attackRange   = 8,
  spells        = { ... },  -- existing
  priorityList  = {},
  ignoreList    = {},
  -- ADD THIS:
  targetMode    = "F",  -- Default: Closest + Lowest HP
}
```

The `targetMode` field stores a single uppercase letter A–I. It is saved to `BTCConfig` alongside the rest of the attack config via the existing `BTCAttack.saveConfig()` call.

---

## Step 2: Create `getAttackableCreaturesSmart()`

Add this function to `attack.lua`. It takes the player's position and a list of `{position, creature}` tables, and returns a table containing all nine mode results in one pass.

```lua
-- Helper: Chebyshev distance
local function btcDist(p1, p2)
  return math.max(math.abs(p1.x - p2.x), math.abs(p1.y - p2.y))
end

-- Helper: within 7x5 reach on same floor
local function btcInReach(playerPos, targetPos)
  if type(targetPos) ~= "table" then return false end
  return math.abs(playerPos.x - targetPos.x) <= 7
     and math.abs(playerPos.y - targetPos.y) <= 5
     and playerPos.z == targetPos.z
end

---
-- Returns { A, B, C, D, E, F, G, H, I }
-- Each field is { id = <creatureId or nil>, ... }
function BTCAttack.getAttackableCreaturesSmart(playerPos, creatureList)
  local closest         = { id=nil, distance=99    }
  local farthest        = { id=nil, distance=-1    }
  local lowestHP        = { id=nil, health=100     }
  local highestHP       = { id=nil, health=-1      }
  local closestLowest   = { id=nil, distance=99,  health=100 }
  local closestHighest  = { id=nil, distance=99,  health=-1  }
  local farthestLowest  = { id=nil, distance=-1,  health=100 }
  local farthestHighest = { id=nil, distance=-1,  health=-1  }
  local bestAoE         = { id=nil, creatures=0   }

  -- AoE area for mode E
  local area = (SpellAreas and SpellAreas.AREA_CIRCLE3X3) or nil

  for _, cd in ipairs(creatureList) do
    local creature = cd.creature
    local pos      = cd.position

    if not btcInReach(playerPos, pos)             then goto skip end
    if not g_map.isSightClear(playerPos, pos)     then goto skip end

    local dist   = btcDist(playerPos, pos)
    local health = creature:getHealthPercent()

    -- Modes C and D: HP-only
    if lowestHP.id == nil then
      lowestHP = { id=creature:getId(), health=health }
    end
    if health < lowestHP.health  then lowestHP  = { id=creature:getId(), health=health } end
    if health > highestHP.health then highestHP = { id=creature:getId(), health=health } end

    -- Modes A and B: distance-only
    if dist < closest.distance  then closest  = { id=creature:getId(), distance=dist } end
    if dist > farthest.distance then farthest = { id=creature:getId(), distance=dist } end

    -- Mode F: closest + lowest HP (primary sort: distance, tiebreak: health asc)
    if dist < closestLowest.distance
    or (dist == closestLowest.distance and health < closestLowest.health) then
      closestLowest = { id=creature:getId(), distance=dist, health=health }
    end

    -- Mode G: closest + highest HP (primary sort: distance, tiebreak: health desc)
    if dist < closestHighest.distance
    or (dist == closestHighest.distance and health > closestHighest.health) then
      closestHighest = { id=creature:getId(), distance=dist, health=health }
    end

    -- Mode H: farthest + lowest HP (primary sort: distance desc, tiebreak: health asc)
    if dist > farthestLowest.distance
    or (dist == farthestLowest.distance and health < farthestLowest.health) then
      farthestLowest = { id=creature:getId(), distance=dist, health=health }
    end

    -- Mode I: farthest + highest HP (primary sort: distance desc, tiebreak: health desc)
    if dist > farthestHighest.distance
    or (dist == farthestHighest.distance and health > farthestHighest.health) then
      farthestHighest = { id=creature:getId(), distance=dist, health=health }
    end

    -- Mode E: best AoE position
    if area and countAttackableCreatures then
      local hits = countAttackableCreatures(pos, 1, area, creatureList, true)
      if hits > bestAoE.creatures then
        bestAoE = { id=creature:getId(), creatures=hits }
      end
    end

    ::skip::
  end

  return {
    A = closest,
    B = farthest,
    C = lowestHP,
    D = highestHP,
    E = bestAoE,
    F = closestLowest,
    G = closestHighest,
    H = farthestLowest,
    I = farthestHighest,
  }
end
```

---

## Step 3: Integrate `countAttackableCreatures` for Mode E

Mode E requires `countAttackableCreatures` and `SpellAreas`. Check whether these are already accessible globally in the client context (they may be defined in the Helper's module scope).

If they are not globally available, copy `countAttackableCreatures` from `helper.lua` and paste it into `btcbot.lua` or a new shared utility file:

```lua
-- Counts how many creatures from creatureList fall within 'area' centered at pos
-- area: a 2D table of {dx, dy} offsets defining the AoE pattern
-- useTarget: if true, pos is a target position; if false, pos is player pos + direction
function countAttackableCreatures(pos, direction, area, creatureList, useTarget)
  local count = 0
  for _, offset in ipairs(area) do
    local checkX = pos.x + offset[1]
    local checkY = pos.y + offset[2]
    for _, cd in ipairs(creatureList) do
      if cd.position.x == checkX
      and cd.position.y == checkY
      and cd.position.z == pos.z then
        count = count + 1
      end
    end
  end
  return count
end
```

For `SpellAreas.AREA_CIRCLE3X3`, use a 3x3 square minus corners, or copy the exact definition from the `SpellAreas` module used by the Helper.

**Vocation-based area selection** (mirror the Helper's logic at line 2660):
```lua
local area = SpellAreas.AREA_CIRCLE3X3
local voc  = BTCAttack.getPlayerVocation()
if voc == 2 or voc == 12 then  -- Paladin
  area = SpellAreas.AREA_CIRCLE2X2
end
```

---

## Step 4: Modify `BTCAttack.execute()` to Use Target Mode

Inside the existing `BTCAttack.execute()` function, locate where the attack target is currently selected. Replace or augment it with:

```lua
function BTCAttack.execute()
  if not g_game.isOnline() then return end
  if not BTCAttack.config or not BTCAttack.config.enabled then return end

  local player = g_game.getLocalPlayer()
  if not player then return end

  -- PZ check (see Step 7)
  if player:isInProtectionZone() then return end

  -- Follow check (see Step 7)
  if g_game.getFollowingCreature() then return end

  local playerPos = player:getPosition()

  -- === LOCKED TARGET CHECK (Step 5) ===
  if BTCAttack.config.lockedTargetId and BTCAttack.config.lockedTargetId ~= 0 then
    local locked = g_map.getCreatureById(BTCAttack.config.lockedTargetId)
    if locked and not locked:isDead() and btcInReach(playerPos, locked:getPosition()) then
      local current = g_game.getAttackingCreature()
      if not current or current:getId() ~= locked:getId() then
        g_game.attack(locked)
      end
      goto spellEvaluation
    else
      BTCAttack.config.lockedTargetId = 0  -- Clear stale lock
    end
  end

  -- === BUILD CREATURE LIST ===
  local creatureList = {}
  local specs = g_map.getSpectators(playerPos, false)
  for _, c in pairs(specs) do
    if c:isMonster() and not c:isDead() then
      -- Apply ignore list
      local ignored = false
      for _, name in ipairs(BTCAttack.config.ignoreList or {}) do
        if c:getName() == name then ignored = true; break end
      end
      if not ignored then
        table.insert(creatureList, { position=c:getPosition(), creature=c })
      end
    end
  end

  -- === PRIORITY LIST (attack first regardless of mode) ===
  for _, priorityName in ipairs(BTCAttack.config.priorityList or {}) do
    for _, cd in ipairs(creatureList) do
      if cd.creature:getName() == priorityName then
        if btcInReach(playerPos, cd.position) and g_map.isSightClear(playerPos, cd.position) then
          local current = g_game.getAttackingCreature()
          if not current or current:getId() ~= cd.creature:getId() then
            g_game.attack(cd.creature)
          end
          goto spellEvaluation
        end
      end
    end
  end

  -- === MODE-BASED SELECTION ===
  local results = BTCAttack.getAttackableCreaturesSmart(playerPos, creatureList)
  local mode    = BTCAttack.config.targetMode or "F"
  local chosen  = results[mode]

  if chosen and chosen.id then
    local target  = g_map.getCreatureById(chosen.id)
    local current = g_game.getAttackingCreature()
    if target and (not current or current:getId() ~= target:getId()) then
      g_game.attack(target)
    end
  end

  ::spellEvaluation::
  -- ... existing spell slot evaluation code continues here ...
end
```

---

## Step 5: Add `lockedTargetId` Support

The locked target allows the user to pin a specific creature for focused attacks.

**Config field** (add to `BTCAttack.defaultConfig`):
```lua
lockedTargetId = 0,
```

**Pattern from helper.lua (lines 2644–2647):**
```lua
-- If locked target is alive and in reach, skip mode selection
local currentLockedTarget = helperConfig.currentLockedTargetId ~= 0
  and g_map.getCreatureById(helperConfig.currentLockedTargetId) or nil
if currentLockedTarget
  and not currentLockedTarget:isDead()
  and isWithinReach(position, currentLockedTarget:getPosition())
then
  return  -- Keep current attack, do not change target
end
```

**UI:** Add a "Lock" button next to each creature name in the battle list, or expose a `BTCAttack.setLockedTarget(id)` function callable from a hotkey or context menu.

**Auto-clear:** The lock clears automatically when the locked creature is dead or out of reach (handled in Step 4).

---

## Step 6: Add UI for Mode Selection

In `BTCAttack.createUI()` (or wherever the attack panel UI is built), add a ComboBox for target mode selection:

```lua
-- Mode selector label
local modeLabel = g_ui.createWidget("Label", container)
modeLabel:setText("Target Mode:")
modeLabel:setColor("#aaaaaa")

-- ComboBox
local modeCombo = g_ui.createWidget("ComboBox", container)
modeCombo:setWidth(180)

local modeOptions = {
  { value="A", label="A – Closest" },
  { value="B", label="B – Farthest" },
  { value="C", label="C – Lowest HP" },
  { value="D", label="D – Highest HP" },
  { value="E", label="E – Best AoE" },
  { value="F", label="F – Closest + Lowest HP" },
  { value="G", label="G – Closest + Highest HP" },
  { value="H", label="H – Farthest + Lowest HP" },
  { value="I", label="I – Farthest + Highest HP" },
}

for _, opt in ipairs(modeOptions) do
  modeCombo:addOption(opt.label, opt.value)
end

-- Set current selection
local currentMode = BTCAttack.config.targetMode or "F"
for i, opt in ipairs(modeOptions) do
  if opt.value == currentMode then
    modeCombo:setCurrentIndex(i)
    break
  end
end

-- On change handler
modeCombo.onOptionChange = function(widget, text, data)
  BTCAttack.config.targetMode = data
  BTCAttack.saveConfig()
end
```

---

## Step 7: Add PZ and Follow Safety Checks

Add these guards at the very top of `BTCAttack.execute()`, before any creature scanning:

```lua
-- Protection Zone: never attack in PZ
local player = g_game.getLocalPlayer()
if not player then return end
if player:isInProtectionZone() then return end

-- Follow detection: disable attacking while following a creature
-- Mirrors helper.lua lines 2452-2460
if g_game.getFollowingCreature() then
  -- Optional: auto-disable the module
  -- BTCAttack.config.enabled = false
  -- BTCAttack.saveConfig()
  return
end
```

**PZ pattern from helper.lua (lines 2432–2439):**
```lua
if myCharacter:isInProtectionZone() then
  local caster = enableButtons:recursiveGetChildById("enableMagicShooter")
  if caster then
    caster:setChecked(false)
    toggleMagicShooter(caster, "Entering in a Protection Zone!\nRTCaster disabled.")
    return
  end
end
```

For BTCBot, the equivalent would be to uncheck the Attack module's enable checkbox and call `BTCAttack.saveConfig()`, or simply return silently each cycle.

---

## Testing Checklist

Work through each item after implementing the changes:

- [ ] Mode A selects the monster with the smallest Chebyshev distance
- [ ] Mode B selects the monster with the largest Chebyshev distance
- [ ] Mode C selects the monster with the lowest `getHealthPercent()`
- [ ] Mode D selects the monster with the highest `getHealthPercent()`
- [ ] Mode E switches targets when a new grouping of monsters offers more AoE hits
- [ ] Mode F (default) prefers closer monsters and breaks ties with lower HP
- [ ] Mode G prefers closer monsters and breaks ties with higher HP
- [ ] Mode H prefers farther monsters and breaks ties with lower HP
- [ ] Mode I prefers farther monsters and breaks ties with higher HP
- [ ] Entering PZ stops all attack and target selection
- [ ] Activating follow on a creature stops attack and target selection
- [ ] A locked target is maintained until it dies or leaves reach
- [ ] Creatures in the ignore list are never selected
- [ ] Creatures in the priority list are always selected first, regardless of mode
- [ ] The mode ComboBox persists selection across sessions (saved in BTCConfig)
- [ ] Mode E falls back gracefully when `SpellAreas` or `countAttackableCreatures` is unavailable
- [ ] No Lua errors when `creatureList` is empty (no monsters visible)
- [ ] Target switches correctly at 250ms interval without causing spam-attack desync
