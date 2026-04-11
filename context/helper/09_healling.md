# Helper Module — Healing System

## checkHealthHealing()

- **Source lines:** ~1813–1863
- **Event interval:** 250 ms
- **Event assignment:** `eventTable.checkHealthHealing.action = checkHealthHealing`

```lua
function checkHealthHealing()
  if not hotkeyHelperStatus then
    return false
  end

  local health, maxHealth = g_game.getLocalPlayer():getHealth(), g_game.getLocalPlayer():getMaxHealth()
  local healthPercent = (health / maxHealth) * 100
  ...
end
```

### Potion Healing Logic

Potions are sorted by `percent` (ascending), with ties broken by `priority` (ascending):

```lua
local prioritizedPotions = {}
for _, potion in pairs(helperConfig.potions) do
  table.insert(prioritizedPotions, potion)
end
table.sort(prioritizedPotions, function(a, b)
  if a.percent == b.percent then
    return a.priority < b.priority
  else
    return a.percent < b.percent
  end
end)

for _, potion in ipairs(prioritizedPotions) do
  if hasItemInBackpack(potion.id)
     and isHealthPotion(potion.id)
     and healthPercent <= potion.percent then
    usePotion(potion.id)
  end
end
```

All matching potions fire in the sorted order (not just the first one). If multiple health potions have overlapping thresholds, they may all attempt to fire in the same 250ms tick. Each `usePotion` call checks the 1000ms potion cooldown internally, so at most one potion per 1000ms will actually execute.

### Spell Healing Logic

Spells are sorted by `percent` ascending, ties broken by `id` ascending:

```lua
table.sort(prioritizedSpells, function(a, b)
  if a.percent == b.percent then
    return a.id < b.id
  else
    return a.percent < b.percent
  end
end)

for _, spell in ipairs(prioritizedSpells) do
  if ignoredSpellsIds[spell.id] then
    goto skipSpell
  end
  if healthPercent <= spell.percent then
    castHealingSpell(spell.id)
  end
  ::skipSpell::
end
```

Spells in `ignoredSpellsIds` are skipped (the slot is effectively disabled for healing). All remaining spells whose threshold is met attempt to cast.

### helperConfig.spells — 3 Slots

```lua
helperConfig.spells = {
  { id = 0, percent = 80 },
  { id = 0, percent = 80 },
  { id = 0, percent = 80 }
}
```

| Field     | Type   | Description                                        |
|-----------|--------|----------------------------------------------------|
| `id`      | number | Client spell ID (0 = empty)                        |
| `percent` | number | HP% threshold — cast when HP <= this value         |

### helperConfig.potions — 3 Slots

```lua
helperConfig.potions = {
  { id = 0, percent = 50, priority = 0 },
  { id = 0, percent = 50, priority = 0 },
  { id = 0, percent = 50, priority = 0 }
}
```

| Field      | Type   | Description                                                     |
|------------|--------|-----------------------------------------------------------------|
| `id`       | number | Potion item ID (0 = empty)                                      |
| `percent`  | number | HP% or mana% threshold                                          |
| `priority` | number | 0 = unset, 1 = force health, 2 = force mana (Spirit potions)   |

---

## castHealingSpell(spellId)

```lua
function castHealingSpell(spellId)
  local spell = Spells.getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then
    return false
  end

  if (isSpellOnCooldown(spell)) then
    return false
  end

  if spell.soul > 0 then
    if player:getSoul() < spell.soul then
      return false
    end
    if spell.source and not hasItemInBackpack(spell.source) then
      return false
    end
  end

  g_game.talk(spell.words, true)
  return true
end
```

### Checks Performed

1. Spell exists in data (not nil, not id 0).
2. Spell is not on individual or group cooldown.
3. If the spell has a soul cost: player must have enough soul points, and if a source item is required (some summoning/soul spells), the item must be in the backpack.
4. Casts via `g_game.talk(spell.words, true)`.

Note: `castHealingSpell` does **not** set a pre-cooldown itself. The pre-cooldown (500ms) is only set in `checkMagicShooter`. Healing spells rely entirely on the server-driven `onSpellCooldown` event to prevent double-casts.

---

## usePotion(potionId)

```lua
function usePotion(potionId)
  local player = g_game.getLocalPlayer()
  if not player then return end

  local cooldown = getSpellCooldown(potionConfig.id)
  if cooldown > g_clock.millis() then
    return true
  end

  if multiUseExDelay > g_clock.millis() then
    return true
  end

  helperConfig.magicShooterOnHold = true

  local potionCount = player:getInventoryCount(potionId)
  if potionCount > 0 then
    g_game.useInventoryItemWith(potionId, player, 0, true)
    spellsCooldown[potionConfig.id] = g_clock.millis() + potionConfig.exhaustion
  end

  helperConfig.magicShooterOnHold = false
end
```

### Flow

1. Check 1000ms potion cooldown (`spellsCooldown["potion"]`).
2. Check `multiUseExDelay` — blocks if the server signaled a use-with exhaustion.
3. Set `magicShooterOnHold = true` to suppress rune casting during the use action.
4. Check inventory count > 0.
5. Call `g_game.useInventoryItemWith(potionId, player, 0, true)` — use potion on self.
6. Set 1000ms potion cooldown.
7. Clear `magicShooterOnHold = false`.

---

## hasItemInBackpack(id)

```lua
function hasItemInBackpack(potionId)
  return player and type(player) == "userdata" and player:getInventoryCount(potionId, 0) > 0
end
```

Calls `getInventoryCount(id, 0)` — the second argument `0` scans all backpack slots. Returns true if count > 0. The `type(player) == "userdata"` guard ensures the player object is a valid game object (not a table replacement or nil).

---

## checkMana()

- **Source lines:** ~2080–2092
- **Event interval:** 100 ms
- **Event assignment:** `eventTable.checkMana.action = checkMana`

```lua
function checkMana()
  if not g_game.isOnline() or not player or not hotkeyHelperStatus then return end

  local mana = player:getMana()
  local maxMana = player:getMaxMana()
  checkManaHealing(mana, maxMana)
  checkTrainingSpell(mana, maxMana)
end
```

Delegates to both mana healing and training at 100ms interval. Both sub-functions receive the same mana values to avoid calling `player:getMana()` twice.

---

## checkManaHealing(mana, maxMana)

```lua
function checkManaHealing(mana, maxMana)
  local manaPercent = (mana / maxMana) * 100

  -- Normalize percent values
  for i, potion in ipairs(helperConfig.potions) do
    if isManaPotion(potion.id) then
      helperConfig.potions[i].percent = tonumber(potion.percent) or 0
    end
  end

  -- Health priority check
  local healthPotionPriority = false
  for _, potion in ipairs(helperConfig.potions) do
    local healthPercent = (player:getHealth() / player:getMaxHealth()) * 100
    if hasItemInBackpack(potion.id) and isHealthPotion(potion.id) and healthPercent <= potion.percent then
      healthPotionPriority = true
    end
  end

  if healthPotionPriority then
    return  -- health potion needed — skip mana healing
  end

  -- Collect and sort mana potions
  local prioritizedManaPotions = {}
  for _, potion in ipairs(helperConfig.potions) do
    if isManaPotion(potion.id) or potion.priority == 2 then
      table.insert(prioritizedManaPotions, potion)
    end
  end
  table.sort(prioritizedManaPotions, function(a, b)
    return a.percent < b.percent
  end)

  for _, potion in ipairs(prioritizedManaPotions) do
    if hasItemInBackpack(potion.id) and manaPercent <= potion.percent then
      usePotion(potion.id)
      return  -- only one mana potion per cycle
    end
  end
end
```

### Key Behaviors

- **Health priority gate:** if any health potion threshold is currently triggered (HP low enough that a health potion would fire), `checkManaHealing` skips entirely. Health always takes priority over mana restoration.
- **priority == 2 inclusion:** Great Spirit (7642) and Ultimate Spirit (23374) with priority 2 are included as mana potions.
- **Early return after first match:** unlike `checkHealthHealing`, mana healing stops after the first successful `usePotion` call per cycle.

---

## Friend Healing System

### checkFriendHealing()

- **Source lines:** ~2754–2762
- **Event interval:** 250 ms

```lua
function checkFriendHealing()
  if not hotkeyHelperStatus then return end
  local localPlayer = g_game.getLocalPlayer()
  if localPlayer and localPlayer:isPartyMember() then
    onFriendHealing(localPlayer)
  end
end
```

Only runs if the player is in a party (`isPartyMember()`). Delegates to `onFriendHealing`.

### onFriendHealing(localPlayer)

```lua
function onFriendHealing(localPlayer)
  if not hotkeyHelperStatus then return end

  local primaryHealing   = helperConfig.friendhealing[1]
  local secondaryHealing = helperConfig.friendhealing[2]
  local gransioHealing1  = helperConfig.gransiohealing[1]
  local gransioHealing2  = helperConfig.gransiohealing[2]

  local position = localPlayer:getPosition()
  local partyMembers = modules.game_party_list.getUpcomingPartyMembers()

  -- Sort so the primary healing target is checked first
  table.sort(partyMembers, function(a, b)
    if a:getName() == primaryHealing.name then return true
    elseif b:getName() == primaryHealing.name then return false
    else return a:getName() < b:getName()
    end
  end)

  for _, member in ipairs(partyMembers) do
    if not member:isPlayer() then goto continue end

    local memberHealth = member:getHealthPercent()
    local isInSight = g_map.isSightClear(position, member:getPosition())
                   and isWithinReach(position, member:getPosition())

    if not isInSight then goto continue end

    -- Gran Sio slots (Druid only — checked for all vocations, spell guard handles it)
    if gransioHealing1.enabled and member:getName() == gransioHealing1.name
       and memberHealth <= gransioHealing1.percent then
      useAutoGranSio(member)
    end
    if gransioHealing2.enabled and member:getName() == gransioHealing2.name
       and memberHealth <= gransioHealing2.percent then
      useAutoGranSio(member)
    end

    -- Primary Sio/UH/TioSio slot
    if primaryHealing.enabled then
      if member:getName() == primaryHealing.name and memberHealth <= primaryHealing.percent
         and member:isPartyMember() then
        if translateVocation(localPlayer:getVocation()) == 5 then
          useAutoUH(member)          -- Sorcerer uses UH rune
        elseif translateVocation(localPlayer:getVocation()) == 9 then
          useAutoTioSio(member)      -- Monk uses Tio Sio (spellId 297)
        else
          useAutoSio(member)         -- Others use Sio (spellId 84)
        end
      end
    end

    -- Secondary Sio/UH/TioSio slot
    if secondaryHealing.enabled then
      if member:getName() == secondaryHealing.name and memberHealth <= secondaryHealing.percent
         and member:isPartyMember() then
        -- same vocation dispatch as above
      end
    end

    ::continue::
  end
end
```

### Healing Dispatch by Vocation

| Vocation ID (translated) | Friend Heal Method  | Spell/Item Used            |
|--------------------------|---------------------|----------------------------|
| 5 (Sorcerer / MS)        | `useAutoUH(target)` | UH rune, item ID 3160       |
| 9 (Monk / EM)            | `useAutoTioSio(target)` | spell ID 297            |
| 6 (Druid / ED)           | `useAutoSio(target)` | spell ID 84 (exura sio)   |
| 7 (Paladin / RP)         | `useAutoSio(target)` | spell ID 84               |
| 8 (Knight / EK)          | `useAutoSio(target)` | spell ID 84               |

Gran Sio (spell ID 242) is dispatched independently of vocation via the `gransiohealing` slots — primarily intended for Druids who have this spell.

### Friend Healing Config Structures

```lua
-- friendhealing: 2 slots — primary and secondary target via Sio/UH/TioSio
helperConfig.friendhealing = {
  { name = "", percent = 0, enabled = false },
  { name = "", percent = 0, enabled = false }
}

-- gransiohealing: 2 slots — targets for Gran Sio
helperConfig.gransiohealing = {
  { name = "", percent = 0, enabled = false },
  { name = "", percent = 0, enabled = false }
}
```

| Field     | Type    | Description                                                  |
|-----------|---------|--------------------------------------------------------------|
| `name`    | string  | Exact name of the party member to heal                       |
| `percent` | number  | HP% threshold — heal when member's HP <= this value          |
| `enabled` | boolean | Whether this slot is active                                  |

---

## Friend Healing Spell Functions

### useAutoSio(target)

```lua
function useAutoSio(target)
  local spellId = 84
  local spell = Spells.getSpellByClientId(tonumber(spellId))
  if not spell or spell.id == 0 then return false end
  if not checkHealthPriority() then return end
  if (isSpellOnCooldown(spell)) then return false end
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
end
```

Casts `exura sio "Name"`. Hard-coded to spell ID 84.

### useAutoGranSio(target)

```lua
function useAutoGranSio(target)
  local spellId = 242
  local spell = Spells.getSpellByClientId(spellId)
  if not spell or spell.id == 0 then return false end
  if not checkHealthPriority() then return end
  if (isSpellOnCooldown(spell)) then return false end
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
end
```

Casts Gran Sio. Hard-coded to spell ID 242.

### useAutoTioSio(target)

```lua
function useAutoTioSio(target)
  local spellId = 297
  local spell = Spells.getSpellByClientId(spellId)
  if not spell or spell.id == 0 then return false end
  if not checkHealthPriority() then return end
  if (isSpellOnCooldown(spell)) then return false end
  g_game.talk(string.format("%s \"%s\"", spell.words, target:getName()), true)
end
```

Tio Sio spell for Monks. Hard-coded to spell ID 297.

### useAutoUH(target)

```lua
function useAutoUH(target)
  local runeId = 3160
  local rune = Spells.getRuneSpellByItem(runeId)
  if not rune then return false end

  if not checkHealthPriority() then return end

  helperConfig.magicShooterOnHold = true
  if hasItemInBackpack(runeId) then
    g_game.useInventoryItemWith(runeId, target, 0, true)
  end
  helperConfig.magicShooterOnHold = false
end
```

Uses an Ultimate Healing rune (item ID 3160) on the target. Sets `magicShooterOnHold` around the use call to suppress any concurrent rune casting from the magic shooter.

---

## All Friend Healing Checks

Every friend heal function (`useAutoSio`, `useAutoGranSio`, `useAutoTioSio`, `useAutoUH`) has the same guard structure:

1. `checkHealthPriority()` — skip if the local player needs self-healing.
2. `isSpellOnCooldown(spell)` — skip if the spell is on group/individual cooldown.
3. The target must already be verified as in-sight and in-reach by `onFriendHealing` before the function is called.

---

## potionWhitelist (reference)

The 12 recognized potions and their types:

| ID    | Name                   | Type   |
|-------|------------------------|--------|
| 268   | Mana Potion            | mana   |
| 237   | Strong Mana Potion     | mana   |
| 238   | Great Mana Potion      | mana   |
| 23373 | Ultimate Mana Potion   | mana   |
| 266   | Health Potion          | health |
| 236   | Strong Health Potion   | health |
| 239   | Great Health Potion    | health |
| 7643  | Ultimate Health Potion | health |
| 23375 | Supreme Health Potion  | health |
| 7642  | Great Spirit Potion    | health |
| 23374 | Ultimate Spirit Potion | health |
| 7876  | Small Health Potion    | health |

Great Spirit (7642) and Ultimate Spirit (23374) are `type = "health"` by default, but can be toggled to behave as mana potions via the priority button (sets `priority = 2`).

---

## Healing Priority Summary

| Priority | Action                                    | Interval |
|----------|-------------------------------------------|----------|
| 1 (highest) | Health potion (checkHealthHealing)    | 250ms    |
| 2        | Healing spell (checkHealthHealing)        | 250ms    |
| 3        | Mana potion (checkManaHealing, only if no health potion needed) | 100ms |
| 4        | Training spell (checkTrainingSpell)       | 100ms    |
| 5        | Friend healing (checkFriendHealing)       | 250ms    |
| 6        | Auto-haste (checkAutoHaste, if HP OK)     | 500ms    |
