# Helper Module — Spell System

## Spells Module Integration

The Helper uses the shared `Spells` module (from `modules.gamelib`) to look up spell data. Two primary lookup functions are used:

### Spells.getSpellByClientId(id)

```lua
local spell = Spells.getSpellByClientId(tonumber(spellId))
```

Returns a spell object or `nil` if not found. The returned object includes (minimum fields used by the Helper):

| Field       | Type    | Description                                                       |
|-------------|---------|-------------------------------------------------------------------|
| `id`        | number  | Spell client ID (same as input)                                   |
| `words`     | string  | Spell incantation (e.g. `"exura"`, `"exori"`), used in `g_game.talk()` |
| `mana`      | number  | Mana cost                                                         |
| `soul`      | number  | Soul cost (0 = none)                                              |
| `duration`  | number  | Effect duration in ms — used by `checkAutoHaste` for re-cast timing |
| `range`     | number  | Spell range (0 = non-targeted / self-cast)                        |
| `area`      | table   | 2D area pattern, or nil for single-target spells                  |
| `group`     | table   | Map of `{groupId = true}` — all cooldown groups this spell belongs to |
| `vocations` | table   | Array of vocation IDs that can use this spell                     |
| `source`    | any     | Source item required (soul spells)                                |
| `spender`   | boolean | If true, this is a harmony-spending spell                         |

### Spells.getRuneSpellByItem(itemId)

```lua
local runeSpell = Spells.getRuneSpellByItem(runeConfig.id)
```

Returns a rune spell object or `nil`. Rune spell objects have similar fields but also include:

| Field      | Type    | Description                                    |
|------------|---------|------------------------------------------------|
| `name`     | string  | Rune name (used for tooltip)                   |
| `area`     | table   | AoE pattern (nil for single-target runes)      |
| `group`    | number  | Single group ID (not a table like spells)      |
| `vocations`| table   | Allowed vocations (checked before rune cast)   |

---

## Cooldown System

The Helper maintains its own cooldown tables independent of the server UI:

```lua
local spellsCooldown = {}  -- [spellId or "food" or "potion"] = timestamp
local groupsCooldown = {}  -- [groupId] = timestamp
```

### Cooldown Functions

```lua
local function getSpellCooldown(spellId)
  return spellsCooldown[spellId] or 0
end

local function getGroupSpellCooldown(groupId)
  return groupsCooldown[groupId] or 0
end
```

Both return 0 if no cooldown is stored, meaning "not on cooldown" by default.

### Server-Driven Cooldown Events

The Helper connects to game events to receive server cooldown notifications:

```lua
function onSpellCooldown(spellId, delay)
  spellsCooldown[spellId] = g_clock.millis() + delay
end

function onSpellGroupCooldown(groupId, delay)
  groupsCooldown[groupId] = g_clock.millis() + delay
end
```

These are fired by the server after a spell is cast and override any pre-cooldown already set.

### isSpellOnCooldown(spell)

```lua
function isSpellOnCooldown(spell)
  if getSpellCooldown(spell.id) >= g_clock.millis() then
    return true
  end

  if type(spell.group) == "table" then
    for group, _ in pairs(spell.group) do
      if getGroupSpellCooldown(group) >= g_clock.millis() then
        return true
      end
    end
  else
    if getGroupSpellCooldown(spell.group) >= g_clock.millis() then
      return true
    end
  end

  return false
end
```

Checks both the spell's individual cooldown and all group cooldowns. If any is still active (timestamp >= current millis), the spell is considered on cooldown. Handles both the case where `spell.group` is a table (most spells) and a scalar (rune spells).

### Pre-Cooldown (500ms)

Immediately after casting, before the server response arrives:

```lua
onSpellCooldown(spell.id, 500)
for group,_ in pairs(spell.group) do
  onSpellGroupCooldown(group, 500)
end
```

This 500ms window prevents the same spell from being queued twice on the next 100ms cycle tick while waiting for the server's actual cooldown response.

---

## onMultiUseCooldown

```lua
function onMultiUseCooldown(time)
  multiUseExDelay = g_clock.millis() + time
end
```

Tracks cooldowns for `useInventoryItemWith` actions (potions, runes, exercise weapons). During `usePotion()`:

```lua
if multiUseExDelay > g_clock.millis() then
  return true  -- block potion use
end
```

This prevents stacking potion uses when the server signals an exhaustion delay.

---

## Special Spell IDs and Lists

### ignoredSpellsIds

Spells excluded from the **healing** spell selector. They cannot be placed in healing slots.

| ID  | Spell                    |
|-----|--------------------------|
| 144 | Cure Bleeding            |
| 146 | Cure Electrification     |
| 29  | Cure Poison              |
| 145 | Cure Burning             |
| 147 | Cure Curse               |
| 160 | Utura Gran               |
| 159 | Utura                    |
| 128 | Utura Mas Sio            |
| 141 | utori (variant)          |
| 138 | utori (variant)          |
| 139 | utori (variant)          |
| 140 | utori (variant)          |
| 143 | utori (variant)          |
| 142 | utori (variant)          |
| 84  | Exura Sio                |
| 242 | Exura Gran Sio           |
| 297 | (Tio Sio)                |
| 274 | (support spell)          |
| 275 | (support spell)          |
| 276 | (support spell)          |
| 296 | (support spell)          |

### ignoredTrainingSpells

Spells excluded from the **training** spell selector. A superset of `ignoredSpellsIds`, adding combat and support spells that are inappropriate as training spells:

| ID  | Notes                      |
|-----|----------------------------|
| 144–147, 160, 159, 128, 138–143 | Same as ignoredSpellsIds |
| 170 | (combat spell)             |
| 123 | (support spell)            |
| 239 | (support spell)            |
| 241 | (support spell)            |
| 242 | Gran Sio                   |
| 125 | (support spell)            |
| 82  | (support spell)            |
| 84  | Sio                        |
| 1   | (spell)                    |
| 2   | (spell)                    |
| 158 | (spell)                    |
| 172 | (spell)                    |
| 36  | (spell)                    |
| 277 | (spell)                    |

### bothCastTypeSpells

```lua
local bothCastTypeSpells = { 258 }
```

ID 258 is the only spell that can be cast either on-target or at self. In `checkMagicShooter`, when this spell is in a slot, the code evaluates both casting modes and selects the one that hits the most creatures.

---

## hasteWhiteList

Per-vocation list of allowed haste spell IDs. Used in `assignTrainingSpell(button, isHaste=true)` and `onSetupDropSupport` to restrict which spells appear in the haste selector:

```lua
local hasteWhiteList = {
  [9] = {6, 39},   -- Monk (EM): spell IDs 6 and 39
  [8] = {6, 131},  -- Knight (EK): spell IDs 6 and 131
  [7] = {6, 134},  -- Paladin (RP): spell IDs 6 and 134
  [6] = {6, 39},   -- Druid (ED): spell IDs 6 and 39
  [5] = {6, 39},   -- Sorcerer (MS): spell IDs 6 and 39
  [0] = {},        -- Rookgaard: no haste spells
}
```

Vocation IDs here are the translated values from `translateVocation()`:

| Raw Vocation ID (game) | Translated ID | Name          |
|------------------------|---------------|---------------|
| 1 or 11                | 8             | Knight (EK)   |
| 2 or 12                | 7             | Paladin (RP)  |
| 3 or 13                | 5             | Sorcerer (MS) |
| 4 or 14                | 6             | Druid (ED)    |
| 5 or 15                | 9             | Monk (EM)     |
| other                  | 0             | Rookgaard     |

---

## potionWhitelist

The 12 recognized potions. Used to validate potion drops and determine potion type (health vs. mana):

```lua
local potionWhitelist = {
  {id = 268,   name = "Mana Potion",            type = "mana"},
  {id = 237,   name = "Strong Mana Potion",      type = "mana"},
  {id = 238,   name = "Great Mana Potion",       type = "mana"},
  {id = 23373, name = "Ultimate Mana Potion",    type = "mana"},
  {id = 266,   name = "Health Potion",           type = "health"},
  {id = 236,   name = "Strong Health Potion",    type = "health"},
  {id = 239,   name = "Great Health Potion",     type = "health"},
  {id = 7643,  name = "Ultimate Health Potion",  type = "health"},
  {id = 23375, name = "Supreme Health Potion",   type = "health"},
  {id = 7642,  name = "Great Spirit Potion",     type = "health"},
  {id = 23374, name = "Ultimate Spirit Potion",  type = "health"},
  {id = 7876,  name = "Small Health Potion",     type = "health"},
}
```

Functions:
- `isHealthPotion(potionId)` — returns true if type == "health"
- `isManaPotion(potionId)` — returns true if type == "mana"
- `getPotionInfoById(itemId)` — returns `(true, name)` or `(false, "Unknown Potion")`

Note: Great Spirit (7642) and Ultimate Spirit (23374) are typed as "health" by default, but the UI allows toggling their `priority` field to treat them as mana potions.

---

## translateVocation

Defined in `modules/corelib/util.lua`. Converts the game's raw vocation integer to the internal vocation index used throughout the Helper:

```lua
function translateVocation(id)
  if id == 1 or id == 11 then return 8  -- EK
  elseif id == 2 or id == 12 then return 7  -- RP
  elseif id == 3 or id == 13 then return 5  -- MS
  elseif id == 4 or id == 14 then return 6  -- ED
  elseif id == 5 or id == 15 then return 9  -- EM/Monk
  end
  return 0  -- Rookgaard / unknown
end
```

The doubled IDs (11–15) are promoted vocations (master/advanced). Both raw and promoted map to the same translated ID.

---

## Harmony Point Check

```lua
if spell.spender and harmonyCount < 5 then
  goto continue
end
```

Harmony points are retrieved via `player:getHarmony()` at the top of the `checkMagicShooter` loop. If a spell has `spender = true`, the player must have at least 5 harmony points for it to fire. Additionally, if harmony >= 5, `sortMagicShooterByPriority` promotes the spender spell to index 1 in the unified list so it fires before other spells in the same cycle.

---

## Food and Potion Exhaustion Config

```lua
local foodConfig   = {id = "food",   exhaustion = 1000}
local potionConfig = {id = "potion", exhaustion = 1000}
```

These use string keys in `spellsCooldown` to track the last use time:
- `spellsCooldown["food"]` — set after `autoEatFood` uses an item. 1000ms exhaustion.
- `spellsCooldown["potion"]` — set after `usePotion` uses a potion. 1000ms exhaustion.
