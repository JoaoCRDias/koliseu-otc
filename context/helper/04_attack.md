# Helper Module — Magic Shooter (RTCaster)

## checkMagicShooter() — Function Overview

- **Source lines:** ~2424–2612
- **Event interval:** 100 ms
- **Event assignment:** `eventTable.checkMagicShooter.action = checkMagicShooter`

`checkMagicShooter` is the core attack automation. It evaluates all configured spells and runes in priority order and casts them when conditions are met.

---

## Guard Conditions

```lua
function checkMagicShooter()
  if not hotkeyHelperStatus then return end
  if not helperConfig.magicShooterEnabled then return end

  local profile = getShooterProfile()
  local myCharacter = g_game.getLocalPlayer()
  if not myCharacter then return end
```

### PZ Auto-Disable

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

Entering PZ immediately disables the magic shooter and displays a message.

### Follow Detection Auto-Disable

```lua
local following = g_game.getFollowingCreature()
if following then
  local widget = enableButtons:recursiveGetChildById("enableMagicShooter")
  if widget then
    widget:setChecked(false)
    toggleMagicShooter(widget, "Follow detected!\nRTCaster disabled.")
    return
  end
end
```

If the player is following a creature, the magic shooter disables itself. This prevents the bot from shooting while the player is manually following something.

---

## creatureList and creaturesAround

After guards pass, the function builds a snapshot:

```lua
local position, direction = myCharacter:getPosition(), myCharacter:getDirection()
local creatureList = {}
local creaturesAround = 0

for i, creature in pairs(spectators) do
  if creature:getPosition().z == position.z
     and getDistanceBetween(position, creature:getPosition()) <= 6 then
    creaturesAround = creaturesAround + 1
  end
  table.insert(creatureList, {position = creature:getPosition(), creature = creature})
end
```

- `creaturesAround`: count of monsters on the same floor within 6 tiles. Used to suppress single-target spells when multiple monsters are present (unless `forceCast` is set).
- `creatureList`: all monsters from `spectators`, regardless of floor or distance. Passed to area calculations.
- `direction`: used by `rotateArea` and `countAttackableCreatures` to orient AoE patterns.

---

## Unified Spell + Rune List

All 5 spell slots and 2 rune slots are merged into a single `unifiedList`:

```lua
local unifiedList = {}

for i, shooter in ipairs(profile.spells) do
  local spell = shooter.id ~= 0 and Spells.getSpellByClientId(shooter.id) or nil
  if spell then
    table.insert(unifiedList, {type = "spell", spell = spell, config = shooter})
  end
end

for i, runeConfig in ipairs(profile.runes) do
  local runeSpell = Spells.getRuneSpellByItem(runeConfig.id)
  if runeSpell then
    table.insert(unifiedList, {type = "rune", rune = runeSpell, config = runeConfig})
  end
end

unifiedList = sortMagicShooterByPriority(unifiedList)
```

Entries with `id == 0` or spells/runes not found in the Spells module are excluded.

---

## Shooter Profiles System

### defaultShooterProfile Structure

```lua
local defaultShooterProfile = {
  spells = {
    {id = 0, percent = 0, creatures = 1, priority = 1, forceCast = false, selfCast = false},
    {id = 0, percent = 0, creatures = 1, priority = 2, forceCast = false, selfCast = false},
    {id = 0, percent = 0, creatures = 1, priority = 3, forceCast = false, selfCast = false},
    {id = 0, percent = 0, creatures = 1, priority = 4, forceCast = false, selfCast = false},
    {id = 0, percent = 0, creatures = 1, priority = 5, forceCast = false, selfCast = false},
  },
  runes = {
    {id = 0, creatures = 1, priority = 6, forceCast = false},
    {id = 0, creatures = 1, priority = 7, forceCast = false},
  },
  autoTargetMode = autoTargetModes['F']
}
```

### Spell Slot Fields

| Field       | Type    | Description                                                        |
|-------------|---------|--------------------------------------------------------------------|
| `id`        | number  | Client spell ID (0 = empty slot)                                   |
| `percent`   | number  | Minimum mana% required to cast (0 = no minimum)                    |
| `creatures` | number  | Minimum creatures the AoE must hit before casting                  |
| `priority`  | number  | Lower = higher priority (1 is highest)                             |
| `forceCast` | boolean | If true, bypass the multi-target safety check for single-target spells |
| `selfCast`  | boolean | If true, cast at self position instead of target (bothCastTypeSpells) |

### Rune Slot Fields

| Field       | Type    | Description                                           |
|-------------|---------|-------------------------------------------------------|
| `id`        | number  | Item ID of the rune (0 = empty slot)                  |
| `creatures` | number  | Minimum creatures the AoE rune must hit               |
| `priority`  | number  | Lower = higher priority (default 6 and 7)             |
| `forceCast` | boolean | If true, use rune even with only 1 creature in range  |

### Profile Management Functions

| Function                         | Description                                                             |
|----------------------------------|-------------------------------------------------------------------------|
| `getShooterProfile()`            | Returns `helperConfig.shooterProfiles[selectedShooterProfile]` or default |
| `getShooterProfileCount()`       | Counts total profiles                                                   |
| `loadShooterProfileByName(name)` | Switches active profile, updates UI and `helperConfig.autoTargetMode`   |
| `toggleShooterPreset(widget)`    | If widget: load selected option; if nil: cycle to next profile          |
| `removeProfile()`                | Deletes current profile after confirmation (blocks if only 1 remains)   |
| `sendRenameOrAddWindow(isRename)`| Opens a window to create or rename a profile                            |

Profile names must be 1–7 alphanumeric characters, no spaces or special characters.

---

## sortMagicShooterByPriority

```lua
local function sortMagicShooterByPriority(list)
  table.sort(list, function(a, b)
    if a.config.priority and b.config.priority then
      return a.config.priority < b.config.priority
    else
      return false
    end
  end)

  local harmonyCount = player:getHarmony()
  if harmonyCount >= 5 then
    -- Move the first "spender" spell to the front
    for i, item in ipairs(list) do
      if item.spell and item.spell.spender then
        local spenderSpell = table.remove(list, i)
        table.insert(list, 1, spenderSpell)
        break
      end
    end
  end
  return list
end
```

After normal priority sort, if the player has 5 or more harmony points, the first `spender` spell found is promoted to index 1 — ensuring it fires before everything else.

---

## Spell Casting Flow (per entry in unifiedList)

For each `entry` where `entry.type == "spell"`:

1. **`autoTargetOnHold` check** — `goto continue` if true.
2. **Get current attack target** — `g_game.getAttackingCreature()`.
3. **Mana check** — `player:getMana() < spell.mana` → skip.
4. **Targetable check** — A spell is "targetable" if `spell.range > 0` or its ID is in `bothCastTypeSpells`. If targetable and no target and `selfCast` is false → skip.
5. **Vocation check** — `translateVocation(myCharacter:getVocation())` must be in `spell.vocations` → skip if not.
6. **Harmony check** — If `spell.spender` is set, player must have `harmony >= 5` → skip if not.
7. **Mana% check** — `manaPercent >= config.percent` must hold to proceed.
8. **Target visibility + range** (for targetable, non-selfCast):
   - `positionTarget.z ~= position.z` → skip (different floor).
   - `target:canBeSeen()` must be true.
   - For large creatures (`target:getCollisionSquare() > 1`), adjust `positionTarget` via `getRelativePosition`.
   - If `getDistanceBetween(position, positionTarget) <= spell.range`: if spell has `area`, count creatures via `countAttackableCreatures`; otherwise `reachableCreatures = 1`.
9. **AoE self-cast** (for non-targetable spells with `area`):
   - `countAttackableCreatures(position, direction, spell.area, creatureList, false)`.
   - If also in `bothCastTypeSpells` and count >= `config.creatures`: set `castOnFoot = true`.
10. **Minimum creatures check** — `reachableCreatures >= config.creatures`.
11. **Multi-target safety** (for non-AoE spells, non-forceCast, non-bothCastTypeSpells):
    - If `creaturesAround > 1` → skip (avoids using single-target spells in a crowd).
12. **Cooldown check** — `isSpellOnCooldown(spell)` → skip.
13. **Cast** — `g_game.talk(spell.words, true, castOnFoot)`.
14. **Pre-cooldown** — immediately set 500ms cooldown on spell ID and all groups:
    ```lua
    onSpellCooldown(spell.id, 500)
    for group,_ in pairs(spell.group) do
      onSpellGroupCooldown(group, 500)
    end
    ```

---

## bothCastTypeSpells

```lua
local bothCastTypeSpells = { 258 }
```

Spell ID 258 can be cast both on a target and at self (feet). When in this list:
- The spell is considered "targetable" by the `spell.range > 0 OR bothCastTypeSpells` check.
- If the AoE hits enough creatures at the player's own position (`castOnFoot = true`), it is cast at feet.
- A `selfCast` checkbox appears in the UI for these spells.

---

## Rune Casting Flow (per entry in unifiedList)

For each `entry` where `entry.type == "rune"`:

1. **`helperConfig.magicShooterOnHold` check** — `goto continue` if true. This prevents rune use while a potion is being used (potion sets `magicShooterOnHold = true` then back to `false`).
2. **Inventory count** — `myCharacter:getInventoryCount(config.id)` must be > 0.
3. **Target selection:**
   - If rune has `area`: use `findBestTarget(position, direction, runeSpell.area, creatureList, config.creatures)`.
   - If no area: use current attack target if in reach and in sight.
4. **Multi-target safety** (non-area runes): if `creaturesAround > 1` and not `forceCast` → skip.
5. **Cooldown check** — `isSpellOnCooldown(runeSpell)` → skip.
6. **Use** — `g_game.useInventoryItemWith(config.id, bestTarget, 0, true)`.
7. **Pre-cooldown** — `onSpellGroupCooldown(runeSpell.group, 500)`.

---

## countAttackableCreatures

```lua
local function countAttackableCreatures(casterPos, direction, area, creatureList, ranged)
```

Rotates the area pattern to match `direction`, then for each cell in the area matrix:
- If cell value is `1` (a hit cell), or `ranged == true` and cell is `3` or `2` (caster cell) — the cell is active.
- Computes world position of the cell relative to the caster.
- Counts how many creatures in `creatureList` are at that position AND have line of sight from the caster.

Returns the total hit count.

---

## findBestTarget

```lua
local function findBestTarget(position, direction, area, creatureList, minCreatures)
```

For each creature in `creatureList`:
- Must pass `isWithinReach` and `g_map.isSightClear`.
- Calls `countAttackableCreatures` with that creature's position as the caster (ranged = true).
- Keeps track of the candidate that hits the most creatures.
- Only candidates hitting `>= minCreatures` are eligible.

Returns `(bestTarget creature, maxCreaturesHit)`.

---

## toggleMagicShooter(widget, message)

```lua
function toggleMagicShooter(widget, message)
  local shooterTracker = helperTracker:recursiveGetChildById("shooterStatus")
  if not widget then
    widget = shooterPanel:recursiveGetChildById("enableMagicShooter")
    widget:setChecked(not widget:isChecked())
  end
  helperConfig.magicShooterEnabled = widget:isChecked()
  modules.game_textmessage.displayGameMessage(message or
    string.format("RTCaster is %s.", (helperConfig.magicShooterEnabled and "enabled" or "disabled")))
  shooterTracker:setText(helperConfig.magicShooterEnabled and "Active" or "Inactive")
  shooterTracker:setColor(helperConfig.magicShooterEnabled and "#44ad25" or "#D33C3C")
end
```

Updates `helperConfig.magicShooterEnabled`, shows a game message, and updates the HelperTracker. The `message` parameter is used for auto-disable messages (PZ, follow detection).

---

## toggleShooterPreset()

When called without a widget (from the keybind):
1. Builds a sorted list of all profile names.
2. Finds the index of `selectedShooterProfile` in the list.
3. Advances to `nextIndex = i % amount + 1` (wraps around).
4. Calls `loadShooterProfileByName(option)` and updates the presets combobox.
5. Shows game message: "RTCaster profile switched to \<name\>."

When called with a widget (from the UI combobox onChange):
1. Reads `widget:getCurrentOption().text`.
2. Calls `loadShooterProfileByName(option)`.

---

## Pre-Cooldown Mechanism

After every successful spell or rune cast, a 500ms pre-cooldown is set immediately:

```lua
-- Spell:
onSpellCooldown(spell.id, 500)
for group,_ in pairs(spell.group) do
  onSpellGroupCooldown(group, 500)
end

-- Rune:
onSpellGroupCooldown(runeSpell.group, 500)
```

This prevents the same spell from being cast twice within one server-response cycle. The actual cooldown from the server (via `onSpellCooldown` event) will overwrite the pre-cooldown when it arrives.
