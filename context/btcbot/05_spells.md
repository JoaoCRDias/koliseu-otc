# BTCBot Spell Reference

## Vocation Constants

| Client ID | Vocation | Promoted ID | Promoted Name |
|-----------|----------|-------------|---------------|
| 1 | Knight | 11 | Elite Knight |
| 2 | Paladin | 12 | Royal Paladin |
| 3 | Sorcerer | 13 | Master Sorcerer |
| 4 | Druid | 14 | Elder Druid |
| 5 | Monk | 15 | Exalted Monk |

`BTCAttack.getPlayerVocation()` returns the value from `player:getVocation()`. The module accepts both base and promoted vocation IDs in all spell `voc` arrays.

---

## Attack Spells by Vocation

### Knight (voc: 1, 11)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exori` | Berserk | 3000 | 115 |
| `exori gran` | Fierce Berserk | 3000 | 340 |
| `exori mas` | Groundshaker | 4000 | 160 |
| `exori min` | Front Sweep | 6000 | 200 |
| `exori ico` | Brutal Strike | 6000 | 30 |
| `exori gran ico` | Annihilation | 8000 | 300 |
| `exori hur` | Whirlwind Throw | 6000 | 40 |
| `exori amp kor` | Executioner's Throw | 12000 | 225 |

### Paladin (voc: 2, 12)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exori con` | Ethereal Spear | 2000 | 25 |
| `exori san` | Divine Missile | 2000 | 20 |
| `exevo mas san` | Divine Caldera | 3000 | 160 |
| `exori gran con` | Strong Ethereal Spear | 4000 | 55 |
| `exevo tempo mas san` | Divine Grenade | 1000 | 160 |
| `utori san` | Holy Flash | 40000 | 30 |

### Sorcerer (voc: 3, 13)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exevo flam hur` | Fire Wave | 4000 | 25 |
| `exevo vis hur` | Energy Wave | 8000 | 170 |
| `exevo vis lux` | Energy Beam | 4000 | 40 |
| `exevo gran vis lux` | Great Energy Beam | 6000 | 110 |
| `exevo gran mas flam` | Hell's Core | 7000 | 1100 |
| `exevo gran mas vis` | Rage of the Skies | 6000 | 600 |
| `exori mort` | Death Strike | 2000 | 20 |
| `exori moe` | Soul Strike | 2000 | 20 |
| `exevo max mort` | Doom | 30000 | 600 |
| `exori kor` | Inflict Wound | 30000 | 30 |

### Druid (voc: 4, 14)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exevo tera hur` | Terra Wave | 4000 | 170 |
| `exevo frigo hur` | Ice Wave | 4000 | 25 |
| `exevo gran frigo hur` | Strong Ice Wave | 8000 | 170 |
| `exevo gran mas tera` | Wrath of Nature | 4000 | 700 |
| `exevo gran mas frigo` | Eternal Winter | 4000 | 1050 |
| `exevo ulus tera` | Terra Burst | 6000 | 230 |
| `exevo ulus frigo` | Ice Burst | 8000 | 230 |

### Sorcerer and Druid Shared (voc: 3, 4, 13, 14)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exori vis` | Energy Strike | 2000 | 20 |
| `exori flam` | Flame Strike | 2000 | 20 |
| `exori frigo` | Ice Strike | 2000 | 20 |
| `exori tera` | Terra Strike | 2000 | 20 |

### Monk (voc: 5, 15)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exori infir pug` | Swift Jab | 2000 | 3 |
| `exori pug` | Double Jab | 4000 | 30 |
| `exori infir nia` | Tiger Clash | 8000 | 18 |
| `exori nia` | Greater Tiger Clash | 8000 | 50 |
| `exori mas pug` | Flurry of Blows | 2000 | 110 |
| `exori gran mas pug` | Greater Flurry of Blows | 3000 | 300 |
| `exori amp pug` | Mystic Repulse | 14000 | 150 |
| `exori med pug` | Chained Penance | 3000 | 180 |
| `exori mas nia` | Sweeping Takedown | 3000 | 195 |
| `exori gran pug` | Forceful Uppercut | 40000 | 325 |
| `exori gran nia` | Devastating Knockout | 12000 | 210 |
| `exori gran mas nia` | Spiritual Outburst | 3000 | 425 |

### All Vocations (voc: 0, 1, 2, 3, 4, 5, 11, 12, 13, 14, 15)

| Words | Name | Cooldown (ms) | Mana |
|-------|------|--------------|------|
| `exori infir vis` | Apprentice's Strike | 2000 | 8 |

---

## Healing Spells by Vocation

Defined in `BTCHealing.healSpells` (`btcbot/healing.lua`):

### Sorcerer / Druid / Paladin (voc: 2, 3, 4, 12, 13, 14)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `exura infir` | Magic Patch | 6 | 1 |
| `exura` | Light Healing | 20 | 8 |

### Sorcerer / Druid / Paladin / Monk (voc: 2, 3, 4, 5, 12, 13, 14, 15)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `exura gran` | Intense Healing | 70 | 20 |

### Sorcerer / Druid only (voc: 3, 4, 13, 14)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `exura vita` | Ultimate Healing | 160 | 30 |
| `exura max vita` | Restoration | 260 | 300 |

### Paladin (voc: 2, 12)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `exura san` | Divine Healing | 160 | 35 |
| `exura gran san` | Salvation | 210 | 60 |

### Knight (voc: 1, 11)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `exura infir ico` | Bruise Bane | 10 | 1 |
| `exura ico` | Wound Cleansing | 40 | 8 |
| `exura gran ico` | Intense Wound Cleansing | 200 | 80 |
| `exura med ico` | Fair Wound Cleansing | 90 | 300 |

### Monk (voc: 5, 15)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `exura gran tio` | Spirit Mend | 210 | 80 |
| `exura mas nia` | Mass Spirit Mend (AoE) | 250 | 150 |

### Knight / Paladin Regeneration (voc: 1, 2, 11, 12)

| Words | Name | Mana | Level |
|-------|------|------|-------|
| `utura` | Recovery | 75 | 50 |
| `utura gran` | Intense Recovery | 165 | 100 |

---

## Attack Rune Item IDs

Defined in `BTCAttack.attackRunes` (`btcbot/attack.lua`):

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

---

## `BTCAttack.getAvailableSpells()`

Reads from the client's `SpellInfo["Default"]` table at runtime. Filters spells by:

1. **Attack group**: only spells with `group[1]` present (group ID 1 = attack group).
2. **Vocation match**: uses the voc mapping table to convert the player's client vocation ID to SpellInfo vocation IDs.

Returns a list sorted by `level` ascending. Each entry contains:

```lua
{
  name     = "Berserk",
  words    = "exori",
  cooldown = 3000,       -- from info.exhaustion
  mana     = 115,        -- from info.mana
  spellId  = <server id>,
  iconId   = <client sprite id>,
  groups   = {1},        -- cooldown group IDs
  level    = 25,
}
```

---

## `BTCHealing.getAvailableSpells()`

Reads from the static `BTCHealing.healSpells` table and filters by `player:getVocation()`. Returns an array of matching spell definitions. If vocation is `0` (offline), all spells are returned.

---

## Friend Healing Spells

Defined in `BTCHealFriend.healSpells` (`btcbot/healfriend.lua`):

| Words | Voc | Mana | Level | AoE | Range |
|-------|-----|------|-------|-----|-------|
| `exura sio` | Druid (4, 14) | 120 | 18 | No | 7 |
| `exura gran sio` | Druid (4, 14) | 210 | 60 | No | 7 |
| `exura gran mas res` | Druid (4, 14) | 150 | 36 | Yes | 5 |
| `exura mas nia` | Monk (5, 15) | 250 | 150 | Yes | 5 |
