# Game Flow Implementation

## Overview
Set up the game flow: GameStartScreen → LevelSelect → Main Game, with a settings panel accessible from the start screen.

## Scene Flow

```
GameStartScreen (Main Scene)
    ├── Start Button → LevelSelect
    └── Settings Button → Toggle Settings Panel

LevelSelect
    ├── Easy Button → Main Game (easy difficulty)
    ├── Medium Button → Main Game (medium difficulty)
    ├── Hard Button → Main Game (hard difficulty)
    └── Return Button → GameStartScreen

Main Game (existing)
    └── (Your main gameplay scene)
```

## Files Created

### 1. `Scripts/game_start_screen.gd`
Main menu controller that handles:
- **Start Button**: Navigates to `LevelSelect.tscn`
- **Settings Button**: Toggles settings panel visibility
- **Title Label**: Automatically made VFX-aware for jitter effect

### 2. `Scripts/level_select.gd`
Level selection controller that handles:
- **Easy/Medium/Hard Buttons**: Load main game (difficulty selection ready for future implementation)
- **Return Button**: Goes back to GameStartScreen
- **TODO**: Pass selected difficulty to main game scene

## Files Modified

### 1. `project.godot`
- Changed main scene from `uid://ctfxrhcbqydwj` (main.tscn) to `res://Scenes/GameStartScreen.tscn`
- Game now starts at the title screen instead of directly in gameplay

### 2. `Scenes/GameStartScreen.tscn`
- Attached `game_start_screen.gd` script to root node
- Added `vfx_aware_label.gd` to Title label for VFX responsiveness
- Settings panel already exists in scene, just needed wiring

### 3. `Scenes/LevelSelect.tscn`
- Attached `level_select.gd` script to root Control node
- Buttons now functional and connected

## How It Works

### GameStartScreen
1. Player sees the "Low & Behold" title with jitter effect
2. **Start Button**: Loads level select screen
3. **Settings Button**: Shows/hides settings panel overlay
4. Settings panel allows adjusting:
   - Music volume (0-100)
   - SFX volume (0-100)
   - Visual effects toggle (On/Off)

### LevelSelect
1. Shows 3 cards representing difficulty levels:
   - **2 Swap** (green) - Easy
   - **6 Draw** (yellow) - Medium
   - **10 Swap** (red) - Hard
2. Clicking a difficulty button loads the main game
3. Return button goes back to start screen

### Settings Integration
- Settings panel works on start screen
- Settings persist across all scenes (handled by SettingsManager autoload)
- VFX toggle affects:
  - Title jitter on start screen
  - All text labels with jitter shader
  - Card animations
  - Background scrolling

## Button Connections

**GameStartScreen:**
- `StartButton.pressed` → `_on_start_pressed()` → Load LevelSelect
- `Settings.pressed` → `_on_settings_pressed()` → Toggle settings panel

**LevelSelect:**
- `EasyButton.pressed` → `_on_easy_pressed()` → Load main game
- `MediumButton.pressed` → `_on_medium_pressed()` → Load main game
- `HardButton2.pressed` → `_on_hard_pressed()` → Load main game
- `ReturnButton.pressed` → `_on_return_pressed()` → Load GameStartScreen

## Future Enhancements

### Difficulty Implementation
Currently, all difficulty buttons load the same main game scene. To implement difficulty:

1. **Create a global difficulty variable** (in an autoload or GameManager):
```gdscript
# In a GameManager autoload
var current_difficulty: String = "medium"
```

2. **Update level_select.gd** to set it:
```gdscript
func _start_game(_difficulty: String) -> void:
    GameManager.current_difficulty = _difficulty
    get_tree().change_scene_to_file("res://Scenes/main.tscn")
```

3. **Use in main game** to adjust gameplay:
```gdscript
# In main.gd
func _ready():
    match GameManager.current_difficulty:
        "easy":
            # Easier AI, more cards, etc.
        "medium":
            # Balanced gameplay
        "hard":
            # Challenging AI, fewer cards, etc.
```

## Testing

1. **Run the game** - should start at GameStartScreen
2. **Click Start** - should go to LevelSelect
3. **Click Settings** - should show/hide settings panel
4. **Click difficulty** - should load main game
5. **Settings persist** - adjust settings, start game, settings should be saved
6. **VFX toggle** - turn off VFX, title should stop jittering

## Scene Paths

- Main scene: `res://Scenes/GameStartScreen.tscn`
- Level select: `res://Scenes/LevelSelect.tscn`
- Main game: `res://Scenes/main.tscn`
- Settings panel: `res://Scenes/settingsPanel.tscn` (instanced in GameStartScreen)

All working and ready to test! 🎮
