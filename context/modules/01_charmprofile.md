# Charm Profiles — Architecture & Implementation

## Overview

The Charm Profiles system allows players to save multiple creature-assignment presets for their charms and switch between them. It uses extended opcode 245 (JSON) for client-server communication.

---

## Key Design Principles

### Tiers are Global, Assignments are Per-Profile

| Property | Scope | Source |
|---|---|---|
| Charm tier (1/2/3) | Global — shared across all profiles | Server (`formattedCharmsData`) |
| Charm points balance | Global — same for all profiles | Server (`player:getResourceBalance`) |
| Creature assignment (`raceId`) | Per-profile | Local profile data (`profile.charms`) |

**Consequence:** Unlocking or upgrading a charm ALWAYS sends `g_game.BuyCharmRune` to the server regardless of which profile is selected. Only "Select Creature" and "Remove/Clear" operations are profile-specific.

---

## Files

| File | Role |
|---|---|
| `modules/game_cyclopedia/tab/charms/charm_profile.lua` | Business logic, state, protocol (opcode 245) |
| `modules/game_cyclopedia/tab/charms/charms.lua` | UI rendering, charm list, button callbacks |
| `data/scripts/charmProfile.lua` *(server)* | Crystal15x server-side opcode 245 handler |

---

## Client-Side State (`charm_profile.lua`)

```lua
profilesList      -- array of { name, charms, majorUsed, minorUsed }
profilesLoaded    -- true once server has responded to "list" action
currentApplied    -- name of the currently applied profile
pendingSelectProfile -- profile to select in combo on next refreshProfileUI
```

### Important State Flags

- `profilesLoaded = false` → `ensureLocalDefault()` is active (client-side fallback)
- `profilesLoaded = true` → server manages profiles; `ensureLocalDefault()` becomes a no-op
- `pendingSelectProfile` → consumed once by `refreshProfileUI` to override combo selection

---

## Protocol (Opcode 245)

All messages are JSON, sent via `protocolGame:sendExtendedJSONOpcode(245, data)`.

### Client → Server

| `action` | Extra fields | Description |
|---|---|---|
| `list` | — | Request all profiles |
| `save` | `name`, `charms[]` | Create or update a profile |
| `apply` | `name` | Set active profile |
| `delete` | `name` | Delete a profile |
| `rename` | `oldName`, `newName` | Rename a profile |
| `cost` | `name` | Request gold cost to apply profile |
| `charge_remove` | — | Charge gold for removing a creature from a charm |
| `charge_reset` | — | Charge gold for resetting all charms in a profile |

### Server → Client

| `action` | Key fields | Description |
|---|---|---|
| `list` | `profiles[]`, `activeProfile` | Full profile list + active profile name |
| `saved` | `name` | Confirmation; client re-requests `list` |
| `applied` | `name`, `message` | Confirmation message |
| `deleted` | `name` | Confirmation; client re-requests `list` |
| `renamed` | `oldName`, `newName` | Confirmation; client re-requests `list` |
| `cost` | `name`, `cost` | Gold cost to apply (always 0 in this server) |
| `charged` | — | Gold was charged; fires `pendingChargeCallback` |
| `error` | `message` | Error message to display |

### Profile Charms Payload (`charms[]`)

Each entry in the `charms` array:
```json
{ "charmId": 5, "tier": 2, "raceId": 1234 }
```
- `charmId` — internal charm ID (matches `charmRune_t` enum)
- `tier` — charm tier (1/2/3); stored for reference, but display always uses server tier
- `raceId` — creature race ID assigned to this charm slot; `0` = unassigned

---

## Server-Side (`Crystal15x/data/scripts/charmProfile.lua`)

Uses Crystal15x's `CreatureEvent` + `player:kv()` system:

```lua
-- Extended opcode handler
local charmProfileEvent = CreatureEvent("CharmProfileExtended")
function charmProfileEvent.onExtendedOpcode(player, opcode, buffer) ... end
charmProfileEvent:type("extendedopcode")
charmProfileEvent:register()

-- Login event: registers the handler per player
local charmProfileLogin = CreatureEvent("CharmProfileLogin")
function charmProfileLogin.onLogin(player)
    player:registerEvent("CharmProfileExtended")
    return true
end
charmProfileLogin:type("login")
charmProfileLogin:register()
```

Storage: `player:kv():set("charm-profiles", { profiles = {...}, activeProfile = "..." })`

The KV store supports nested Lua tables (ArrayType + MapType via C++ `ValueWrapper`).

---

## UI Flow

### On Login / Open Cyclopedia

1. `showCharms()` → `CharmProfile.init()` → `CharmProfile.requestList()` (sends `list` to server)
2. `CharmProfile.ensureLocalDefault(...)` → creates local "Default" profile immediately so combo is not empty while server responds
3. Server responds with `list` → `onOpcode` sets `profilesLoaded = true`, `currentApplied`, `pendingSelectProfile`
4. `onListReceived` callback → `refreshProfileUI()` → populates combo, calls `previewProfile(selectedName)`

### `previewProfile(profileName)`

Runs for **every** profile selection (applied or not):

1. Reads `Cyclopedia.formattedCharmsData` for tiers (always server data)
2. Reads `CharmProfile.buildCharmLookup(profileName)` for raceId assignments
3. Merges both into a lookup table and updates all charm widgets
4. Calls `CharmProfile.clearPreview()` — charm point display always shows real server balance
5. Re-selects the previously selected charm via `Cyclopedia.selectCharm`

### `loadCharms(charmsData)` (called on every server charm data packet)

1. Updates `Cyclopedia.formattedCharmsData`
2. Recreates all charm widgets from server data (no profile merge)
3. At end: calls `previewProfile(currentComboSelection)` to overlay profile raceIds

### Unlock / Upgrade Button

Always calls `g_game.BuyCharmRune(...)` — never local/preview. After server processes it, it sends back updated charm data → `loadCharms` → `previewProfile` updates the display.

### Select Creature / Remove / Clear (in non-applied profile)

Calls `CharmProfile.updateLocalCharm(profileName, charmId, tier, raceId)` which:
- Updates `profile.charms` locally
- Auto-saves to server via `sendAction("save", ...)`
- Triggers `previewProfile` for visual update

---

## `ensureLocalDefault(charmsPayload)` — Client Fallback

Called from `loadCharms()` and `showCharms()`. Only runs when `profilesLoaded == false`.

Creates a local "Default" profile from the server's charm data so the UI is usable even if the server doesn't implement opcode 245. Once the server responds, `profilesLoaded = true` and this becomes a no-op.

---

## Common Pitfalls

| Problem | Root Cause | Fix |
|---|---|---|
| Combo selects "Default" instead of active profile after relog | `ensureLocalDefault` runs before server responds and sets combo to "Default"; server response needs `pendingSelectProfile` | Set `pendingSelectProfile = data.activeProfile` in "list" handler |
| Charm points show 0/0 on non-applied profiles | `mergeCharmsDataWithProfile` used profile's `majorUsed` (often 0) for max calculation | `clearPreview()` always; use `player:getResourceBalance` for max |
| Unlock button disabled on non-applied profiles | `mergeCharmsDataWithProfile` overrode server tier with profile tier (0 for new charms) | `previewProfile` always uses `formattedCharmsData` tiers |
| Creature sprites missing on Default after relog | `refreshProfileUI` only called `previewProfile` when `matched=false` | Always call `previewProfile(currentName)` in `refreshProfileUI` |
| Unlocking in one profile doesn't show in other profiles | Unlock was local-only via `updateLocalCharm` in preview mode | Unlock/Upgrade always server-side via `g_game.BuyCharmRune` |
| Minor charm echoes not credited after major unlock | Unlock was local, never sent to server | Same fix as above |
