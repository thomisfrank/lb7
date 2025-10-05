# Options Panel & Surrender Feature Implementation

## Overview
Added an options/settings panel to the main game scene that pauses gameplay, and a surrender button that allows the player to forfeit the game immediately with a custom "You gave up!" message.

## Features Implemented

### 1. **Options Button**
- Opens the settings panel during gameplay
- **Pauses the entire game** using `get_tree().paused = true`
- Prevents player from missing anything while adjusting settings

### 2. **Settings Panel in Game**
- Reuses the same settings panel from the start screen
- Contains:
  - Music volume slider
  - SFX volume slider
  - Visual effects toggle
  - **NEW: Surrender button**

### 3. **Surrender Button**
- Immediately ends the game
- Player automatically loses
- **Special message:** "You gave up!" instead of "You've lost..."
- Displays final stats and best round hand

### 4. **Click Outside to Close**
- Clicking anywhere outside the settings panel closes it
- Clicking the surrender button also closes the panel (before ending game)
- **Unpauses the game** when panel closes

## Files Modified

### 1. **`Scripts/main.gd`**

**Added:**
- `@onready var options_button` - Reference to options button
- `@onready var settings_panel` - Reference to settings panel in game
- `@onready var surrender_button` - Reference to surrender button
- `var game_surrendered: bool` - Flag to track if player surrendered

**New Functions:**
```gdscript
_on_options_pressed()     # Opens panel and pauses game
_on_surrender_pressed()   # Surrenders and ends game
_close_options_panel()    # Closes panel and unpauses game
```

**Updated `_input()`:**
- Added click-outside-to-close logic for settings panel
- Checks if click is outside panel rect and closes if so

### 2. **`Scripts/round_manager.gd`**

**Added:**
- `const LOG` - Logger import (was missing)

**New Function:**
```gdscript
surrender_game()  # Called when player surrenders
                  # Sets surrender flag and calls end_game()
```

**Updated `end_game()`:**
- Checks for `game_surrendered` flag from main_node
- Calls special surrender method if available
- Passes surrender state to game over screen

### 3. **`Scripts/game_over_screen.gd`**

**New Functions:**
```gdscript
show_game_over_surrender(...)  # Public method for surrender game over
_show_game_over_internal(...)  # Internal method used by both versions
```

**Updated `_set_player_status()`:**
- Added `surrendered: bool = false` parameter
- Shows **"You gave up!"** when surrendered
- Shows normal win/loss/tie messages otherwise

## Scene Structure

```
main.tscn
└── UILayer
    └── OptionsButton (TextureButton)
        └── Settings Panel (instance of settingsPanel.tscn)
            ├── [Music/SFX sliders, VFX toggle]
            └── SurrenderButton (Button)
```

## How It Works

### Opening Options Panel:
1. Player clicks options button
2. `_on_options_pressed()` called
3. Settings panel becomes visible
4. **Game tree paused** (`get_tree().paused = true`)
5. Player can adjust settings or surrender

### Closing Options Panel:
1. Player clicks outside panel rectangle
2. `_input()` detects click outside bounds
3. `_close_options_panel()` called
4. Panel hidden
5. **Game tree unpaused** (`get_tree().paused = false`)

### Surrendering:
1. Player clicks "Surrender" button
2. `_on_surrender_pressed()` called
3. Sets `game_surrendered = true`
4. Closes options panel
5. Calls `round_manager.surrender_game()`
6. Round manager calls `end_game()`
7. Game over screen checks surrender flag
8. Shows "You gave up!" message with stats

## Pause Behavior

When the settings panel is open:
- ✅ All gameplay paused
- ✅ Cards can't be moved
- ✅ AI doesn't take turns
- ✅ Timers stop
- ✅ Settings changes still work (not affected by pause)
- ✅ Click detection still works (to close panel)

When panel closes:
- ✅ Game resumes exactly where it left off
- ✅ All timers continue
- ✅ Turn state preserved

## Messages

| Condition | Message |
|-----------|---------|
| Player wins | "You Win!" |
| Player loses normally | "You've lost..." |
| Tie | "It's a tie" |
| **Player surrenders** | **"You gave up!"** |

## Testing Checklist

- [ ] Options button opens panel and pauses game
- [ ] Settings (volume/VFX) work while panel open
- [ ] Clicking outside panel closes it and unpauses
- [ ] Surrender button ends game immediately
- [ ] "You gave up!" message shows on surrender
- [ ] Final stats display correctly after surrender
- [ ] Game doesn't continue after surrender
- [ ] Panel works at different points in game (start of turn, mid-turn, etc.)

## Notes

- Settings persist across surrender (saved to config file)
- Surrender counts as a loss in game stats
- Panel uses same settings instance as start screen
- Pause is global (`get_tree().paused`) not scene-specific
- Click detection uses `get_global_rect()` for accurate bounds

All done and ready to test! 🎮
