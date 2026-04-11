# BTCBot Training Module

## Status: NOT IMPLEMENTED

BTCBot does not include a training module. This is a known feature gap compared to the Helper system.

---

## What Is Missing

A training module would typically automate the following workflow:

1. Detect an exercise dummy or training partner in range.
2. Check that player mana is above a configured threshold before casting.
3. Repeatedly cast a designated training spell (e.g., `exori ico` for Knights, `exevo vis lux` for Sorcerers).
4. Optionally use mana potions to sustain the training session.
5. Stop when stamina, mana, or time limits are reached.

---

## Helper's Training Implementation (Reference)

In the existing Helper system (`mods/game_helper/helper.lua`, around line 1994), training is implemented as a standalone macro with the following logic:

- **Exercise dummy detection**: scans nearby tiles for objects with specific item IDs that correspond to training dummies.
- **`checkTrainingSpell`**: validates that the configured spell is appropriate for the player's vocation and current level.
- **Mana threshold**: only casts when mana is above the configured minimum percentage to avoid running completely dry.
- **Cooldown awareness**: respects the global spell cooldown before re-casting.

The Helper training system is part of the monolithic `helper.lua` script and is tightly coupled to the Helper UI, making it non-trivial to extract.

---

## BTCBot Alternative: Manual Macro / Time Module

Until a dedicated training module is built, the `BTCTime` module can partially substitute for simple training use cases:

```
BTCTime slot:
  itemId = <training item ID>
  interval = <seconds between uses>
```

This approach is limited: it uses items on a timer rather than responding to mana levels or detecting training targets.

For spell casting, the existing `BTCAttack` module can be configured with a training spell, but it requires an active attack target (creature) — it will not cast at a dummy.

---

## Suggested Implementation Path

A future `BTCTraining` module would follow the standard BTCBot pattern:

```lua
BTCTraining = BTCTraining or {}

BTCTraining.defaultConfig = {
  enabled = false,
  spell = "exori ico",
  manaThreshold = 30,    -- minimum mana % before casting
  targetId = 0,          -- exercise dummy item ID (0 = auto-detect)
}

function BTCTraining.execute()
  if not BTCTraining.config.enabled then return end
  -- 1. Find exercise dummy nearby
  -- 2. Check mana >= manaThreshold
  -- 3. Check spell cooldown
  -- 4. g_game.talk(spell)
end
```

It would be inserted into the `BTCBot.execute()` loop between `BTCMana` and `BTCAttack`.

---

## References

- Helper training logic: `mods/game_helper/helper.lua` (approximately line 1994)
- BTCTime module (closest current alternative): `mods/game_bot/btcbot/time.lua`
- Implementation guide: `NEXTMOVEHELPERTOBTC.md` (if present)
