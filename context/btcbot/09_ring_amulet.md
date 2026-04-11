# BTCBot Equipment Module (Ring / Amulet)

**File:** `mods/game_bot/btcbot/equipment.lua`
**Global:** `BTCEquipment`

---

## Overview

The Equipment module automatically equips and unequips rings and amulets based on the player's current HP or mana percentage. The logic is threshold-based: when the tracked value drops to or below the threshold the item is equipped; when it rises above the threshold the item is moved back to a backpack.

---

## Default Configuration

```lua
BTCEquipment.defaultConfig = {
  enabled = false,
  slots = {
    { enabled = false, itemId = 0, type = "ring",   condition = "life", threshold = 80 },
    { enabled = false, itemId = 0, type = "ring",   condition = "life", threshold = 50 },
    { enabled = false, itemId = 0, type = "amulet", condition = "life", threshold = 80 },
    { enabled = false, itemId = 0, type = "amulet", condition = "mana", threshold = 50 },
  }
}
```

Config is persisted via `BTCConfig.get("equipment")` / `BTCConfig.set("equipment", ...)`.

---

## Inventory Slot Constants

```lua
BTCEquipment.SLOT_HEAD      = 1
BTCEquipment.SLOT_NECKLACE  = 2   -- Amulet
BTCEquipment.SLOT_BACKPACK  = 3
BTCEquipment.SLOT_ARMOR     = 4
BTCEquipment.SLOT_RIGHT     = 5
BTCEquipment.SLOT_LEFT      = 6
BTCEquipment.SLOT_LEGS      = 7
BTCEquipment.SLOT_FEET      = 8
BTCEquipment.SLOT_FINGER    = 9   -- Ring
BTCEquipment.SLOT_AMMO      = 10
```

`SLOT_FINGER` (9) is the ring slot. `SLOT_NECKLACE` (2) is the amulet slot. These are the only two slots the module writes to.

---

## Slot Configuration Fields

| Field | Type | Description |
|-------|------|-------------|
| `enabled` | bool | Whether this slot is active |
| `itemId` | number | Client item ID of the ring or amulet |
| `type` | string | `"ring"` or `"amulet"` |
| `condition` | string | `"life"` (HP%) or `"mana"` (MP%) |
| `threshold` | number | Percentage threshold (0–100) |

---

## Threshold Logic

For each enabled slot, every tick:

```
currentValue = HP% if condition == "life", else MP%

if currentValue <= threshold:
    equipItem()    -- move from backpack to ring/amulet slot
else:
    unequipItem()  -- move from ring/amulet slot to backpack
```

This creates a reactive equip/unequip cycle. For example, with `condition = "life"` and `threshold = 80`:
- HP falls to 75% → item is equipped.
- HP recovers to 85% → item is removed.

---

## Value Functions

### `BTCEquipment.getHealthPercent()`

```lua
return math.floor((player:getHealth() / player:getMaxHealth()) * 100)
```

Returns `100` if offline or max health is `0`.

### `BTCEquipment.getManaPercent()`

```lua
return math.floor((player:getMana() / player:getMaxMana()) * 100)
```

Returns `100` if offline or max mana is `0`.

### `BTCEquipment.getCurrentValue(condition)`

Dispatcher:
```lua
if condition == "life"  then return getHealthPercent()
if condition == "mana"  then return getManaPercent()
-- else returns 100
```

---

## Cooldown

`BTCEquipment.canAct(slotIndex)` enforces a 500 ms cooldown per slot index to prevent flooding the server with item move requests.

```lua
BTCEquipment.actionCooldown = 500   -- ms

function BTCEquipment.canAct(slotIndex)
  local now = g_clock.millis()
  local lastAction = BTCEquipment.lastActionTime[slotIndex] or 0
  return (now - lastAction) >= BTCEquipment.actionCooldown
end
```

Each successful `equipItem` or `unequipItem` call updates `BTCEquipment.lastActionTime[slotIndex]`.

---

## Item Search

### `BTCEquipment.findItemInContainers(itemId)`

Iterates all open containers via `g_game.getContainers()`. For each container, scans all slots for an item matching `itemId`. Returns `(item, container)` on success, `(nil, nil)` on failure.

```lua
local item, container = BTCEquipment.findItemInContainers(3051)
```

### `BTCEquipment.findOpenContainer()`

Returns the first container with available capacity (`getItemsCount() < getCapacity()`). Falls back to the first container if all are full.

---

## Equipped Item Checks

### `BTCEquipment.getEquippedItem(slotType)`

Reads `player:getInventoryItem(inventorySlot)` for the appropriate slot (ring or amulet). Returns the item object or `nil`.

### `BTCEquipment.isItemEquipped(itemId, slotType)`

```lua
local equippedItem = BTCEquipment.getEquippedItem(slotType)
return equippedItem and equippedItem:getId() == itemId
```

---

## Equip / Unequip

### `BTCEquipment.equipItem(slotIndex, slot)`

1. Check `canAct(slotIndex)`.
2. Return if already equipped (`isItemEquipped`).
3. Find item in containers (`findItemInContainers`).
4. Build destination position: `{x = 65535, y = inventorySlot, z = 0}` — this is the standard OTC inventory slot address format.
5. Call `g_game.move(item, destPos, 1)`.
6. Update cooldown.

### `BTCEquipment.unequipItem(slotIndex, slot)`

1. Check `canAct(slotIndex)`.
2. Return if not equipped (`isItemEquipped` is false).
3. Get equipped item object.
4. Find open container.
5. Build destination as the next free slot in the container: `container:getSlotPosition(container:getItemsCount())`.
6. Call `g_game.move(equippedItem, destPos, 1)`.
7. Update cooldown.

---

## `BTCEquipment.execute()`

Called every 100 ms by the main loop:

```lua
for i, slot in ipairs(BTCEquipment.config.slots) do
  if slot.enabled and slot.itemId and slot.itemId > 0 then
    local currentValue = BTCEquipment.getCurrentValue(slot.condition)
    local threshold = slot.threshold or 80

    if currentValue <= threshold then
      BTCEquipment.equipItem(i, slot)
    else
      BTCEquipment.unequipItem(i, slot)
    end
  end
end
```

All 4 slots are evaluated independently every tick, subject to their per-slot cooldowns.

---

## Common Item IDs

As noted in the Equipment UI source code:

| Item ID | Name |
|---------|------|
| 3051 | Energy Ring |
| 3048 | Might Ring |
| 3081 | SSA (Stone Skin Amulet, alternate) |
| 3083 | Stone Skin Amulet |

---

## Example Configurations

**Energy Ring on low HP (Knight survival):**
```
type = "ring", condition = "life", threshold = 60, itemId = 3051
```
Equips Energy Ring when HP <= 60%. Removes it when HP > 60%.

**Might Ring always (melee damage):**
```
type = "ring", condition = "life", threshold = 100, itemId = 3048
```
Since HP is always <= 100%, this keeps the Might Ring permanently equipped until overridden.

**Stone Skin Amulet on critical HP:**
```
type = "amulet", condition = "life", threshold = 40, itemId = 3083
```
Equips SSA when HP <= 40%.
