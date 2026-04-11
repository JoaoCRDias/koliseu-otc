# Shortcut Panel System

## Overview

The Shortcut Panel is a floating UI panel that provides quick access to toggle helper features. It appears to the left of the right-side game panels and synchronizes with the main helper panel controls.

## Panel Position Logic

```
┌──────────────────────────────────────────────────────────────────────────┐
│                            GAME SCREEN                                   │
│                                                                          │
│                                          ┌─────────────────────────────┐ │
│                                          │                             │ │
│                                          │   gameRightActionPanel      │ │
│                                          │   (if action bars active)   │ │
│                                          │                             │ │
│    ┌──────────┐                          ├─────────────────────────────┤ │
│    │ Shortcut │ ◄── Anchored to ──────── │                             │ │
│    │  Panel   │     leftmost panel       │   gameRightExtraPanel       │ │
│    │          │                          │   (if enabled)              │ │
│    └──────────┘                          │                             │ │
│                                          ├─────────────────────────────┤ │
│                                          │                             │ │
│                                          │   gameRightPanel            │ │
│                                          │   (always present)          │ │
│                                          │                             │ │
│                                          └─────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────────────┘
```

## Panel Anchor Priority

```
getLeftmostRightPanel():

    Has active right action bars?
              │
       ┌──────┴──────┐
       │             │
      Yes            No
       │             │
       ▼             ▼
┌─────────────┐  gameRightExtraPanel.isOn()?
│   Anchor to │           │
│ RightAction │    ┌──────┴──────┐
│   Panel     │   Yes            No
└─────────────┘    │             │
                   ▼             ▼
          ┌─────────────┐ ┌─────────────┐
          │  Anchor to  │ │  Anchor to  │
          │ RightExtra  │ │  RightPanel │
          │   Panel     │ │  (default)  │
          └─────────────┘ └─────────────┘
```

## Lifecycle Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                          LOGIN                                  │
│  online() → scheduleEvent(1000ms)                               │
│    └─ if shortcutsVisible → createPanel()                       │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                     PANEL CREATED                               │
│  createPanel():                                                 │
│    ├─ Create widget 'HelperShortcutPanel'                       │
│    ├─ Set anchors (vertical center + left of right panel)       │
│    └─ syncPanelState() (sync all button states)                 │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                    DURING GAMEPLAY                              │
│  User clicks button → onButtonChange()                          │
│    └─ Sync with main helper panel checkboxes                    │
│                                                                 │
│  Helper panel changes → syncButton()                            │
│    └─ Update shortcut panel button state                        │
└─────────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────────┐
│                         LOGOUT                                  │
│  offline() → destroyPanel()                                     │
└─────────────────────────────────────────────────────────────────┘
```

## Button Synchronization

```
                    ┌─────────────────────┐
                    │   Shortcut Panel    │
                    │                     │
                    │  ┌───────────────┐  │
                    │  │ shortcutHelper│◄─┼──── Toggle Helper On/Off
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │shortcutTarget │◄─┼──── Toggle Auto Target
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │shortcutShooter│◄─┼──── Toggle Magic Shooter
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │ shortcutHaste │◄─┼──── Toggle Auto Haste
                    │  └───────────────┘  │
                    │  ┌───────────────┐  │
                    │  │shortcutTrain  │◄─┼──── Toggle Mana Training
                    │  └───────────────┘  │
                    └─────────────────────┘
                              │
                              │ Two-way sync
                              ▼
                    ┌─────────────────────┐
                    │    Helper Panel     │
                    │    (Main Window)    │
                    │                     │
                    │  Shooter Panel:     │
                    │   - enableAutoTarget│
                    │   - enableMagicShoot│
                    │                     │
                    │  Tools Panel:       │
                    │   - enableHaste0    │
                    │   - enableTraining0 │
                    └─────────────────────┘
```

## Button Click Flow (onButtonChange)

```
onButtonChange(button)
        │
        ├─ updateMark(button, isChecked)
        │
        └─ Which button?
                │
    ┌───────────┼───────────┬───────────┬───────────┐
    │           │           │           │           │
    ▼           ▼           ▼           ▼           ▼
 Helper    AutoTarget   Shooter     Haste     Training
    │           │           │           │           │
    ▼           ▼           ▼           ▼           ▼
┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐ ┌────────┐
│ Set    │ │ Sync   │ │ Sync   │ │ Sync   │ │ Sync   │
│ Helper │ │ shooter│ │ shooter│ │ tools  │ │ tools  │
│ Enabled│ │ panel  │ │ panel  │ │ panel  │ │ panel  │
│ + icon │ │checkbox│ │checkbox│ │checkbox│ │checkbox│
│+status │ │        │ │        │ │        │ │        │
└────────┘ └────────┘ └────────┘ └────────┘ └────────┘
```

## Key Functions

| Function                      | Description                                    |
| ----------------------------- | ---------------------------------------------- |
| `toggle(checked)`             | Show/hide the shortcut panel                   |
| `isVisible()`                 | Returns current visibility state               |
| `setVisible(value)`           | Sets visibility state (without updating UI)    |
| `createPanel()`               | Creates the panel widget and sets anchors      |
| `destroyPanel()`              | Destroys the panel widget                      |
| `updatePosition()`            | Recalculates and updates panel anchors         |
| `syncPanelState()`            | Syncs all button states with helperConfig      |
| `syncButton(id, enabled)`     | Syncs a specific button state                  |
| `updateMark(button, enabled)` | Shows/hides the green mark indicator           |
| `onButtonChange(button)`      | Handles button click and syncs with main panel |
| `getPanel()`                  | Returns the panel widget reference             |

## Visual States

```
Button States:

  ┌─────────┐      ┌─────────┐
  │         │      │    ●    │  ◄── Green mark (visible when enabled)
  │   OFF   │      │   ON    │
  │         │      │         │
  └─────────┘      └─────────┘
   unchecked        checked
```

## Files

- `classes/shortcut_panel.lua` - Main module with all Shortcut Panel logic
- `styles/helper_shortcut.otui` - UI definition for the panel widget
- `helper.lua` - Contains lifecycle hooks (createPanel on login, destroyPanel on logout)
