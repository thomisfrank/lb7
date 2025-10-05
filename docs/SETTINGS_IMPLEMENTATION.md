# Settings System Implementation

## Overview
Implemented a complete settings system for controlling music volume, SFX volume, and visual effects filtering. The system persists settings to disk and provides real-time updates across all game elements.

## Files Created

### 1. `Scripts/settings_manager.gd` (Autoload)
- Global settings manager that stores and persists preferences
- Handles music/SFX volume (0-100 range)
- Controls visual effects on/off toggle
- Saves to `user://settings.cfg` automatically
- Emits signals when settings change

**Key Methods:**
- `set_music_volume(volume: float)` - Updates music volume and saves
- `set_sfx_volume(volume: float)` - Updates SFX volume and saves
- `set_visual_effects(enabled: bool)` - Toggles VFX and saves

### 2. `Scripts/settings_panel.gd`
- UI controller for the settings panel
- Connects sliders and checkboxes to SettingsManager
- Updates label text ("On"/"Off") for VFX toggle

### 3. `Scripts/vfx_aware_label.gd`
- Helper script for Labels with animated shaders
- Automatically listens to VFX changes
- Can be attached to any Label using TextJitter shader

## Files Modified

### Shaders (added `animation_speed` parameter to all)
1. **`Scripts/Shaders/DynamicCardBackground.gdshader`**
   - Added `animation_speed` uniform (0-2, default 1.0)
   - Multiplied TIME by animation_speed for blob movement
   - When speed = 0, gradient is frozen (still visible, just not moving)

2. **`Scripts/Shaders/TextJitter.gdshader`**
   - Added `animation_speed` uniform
   - Freezes jitter when animation_speed = 0

3. **`Scripts/Shaders/DynamicBackgrounds.gdshader`**
   - Added `animation_speed` uniform
   - Stops scrolling when animation_speed = 0

### Core Scripts

4. **`Scripts/CardFramework/Core/card.gd`**
   - Added VFX change listener in `_ready()`
   - New methods:
     - `_on_visual_effects_changed(enabled: bool)`
     - `_apply_visual_effects_state(enabled: bool)`
   - Sets `animation_speed` on front and back card shaders
   - **Important:** Keeps gradients visible, just freezes movement

5. **`Scripts/backgrounds.gd`**
   - Added VFX change listener
   - New methods:
     - `_on_visual_effects_changed(enabled: bool)`
     - `_apply_vfx_to_all_backgrounds(enabled: bool)`
   - Applies animation_speed to all background texture shaders

6. **`project.godot`**
   - Added `SettingsManager="*res://Scripts/settings_manager.gd"` to autoload section

7. **`Scenes/settingsPanel.tscn`**
   - Attached `settings_panel.gd` script to root Control node
   - Script connects to sliders and toggle button

## How to Use

### In Settings Panel (Already Set Up)
The settings panel at `Scenes/settingsPanel.tscn` is fully wired:
- Music volume slider (0-100)
- SFX volume slider (0-100)
- Visual effects checkbox (On/Off with label)

Just instantiate this scene in your start screen or pause menu!

### For Text Labels with Shaders
To make any jittering text respond to VFX settings:
1. Attach `vfx_aware_label.gd` to the Label node
2. Done! It will automatically freeze/resume based on settings

### For Custom Elements
Listen to the SettingsManager signals:
```gdscript
func _ready():
    SettingsManager.music_volume_changed.connect(_on_music_changed)
    SettingsManager.sfx_volume_changed.connect(_on_sfx_changed)
    SettingsManager.visual_effects_changed.connect(_on_vfx_changed)
```

## Visual Effects Behavior

**When VFX is ON (default):**
- Card gradients animate with moving blobs
- Background textures scroll
- Text jitters
- All shaders run normally

**When VFX is OFF:**
- Card gradients stay visible but frozen (no blob movement)
- Background textures stop scrolling
- Text stops jittering
- **All visual elements remain visible, just static**

This is perfect for users who want the styled look but find the motion distracting!

## Audio Bus Setup

The settings manager expects these audio buses:
- `Music` - for music tracks (coming soon)
- `SFX` or `Master` - for sound effects (falls back to Master if SFX doesn't exist)

Volume conversion uses linear-to-dB scaling:
- 0 volume = muted completely
- 1-100 = scales from ~-40dB to 0dB

## Persistence

Settings auto-save to `user://settings.cfg` whenever changed. The file location:
- **Windows:** `%APPDATA%/Godot/app_userdata/lb7/settings.cfg`
- **macOS:** `~/Library/Application Support/Godot/app_userdata/lb7/settings.cfg`
- **Linux:** `~/.local/share/godot/app_userdata/lb7/settings.cfg`

## Current Errors (Expected)

The linter shows "SettingsManager not declared" errors in:
- `settings_panel.gd`
- `card.gd`
- `backgrounds.gd`
- `vfx_aware_label.gd`

**These will resolve automatically** when you reload the project in Godot, as the autoload registration in `project.godot` makes SettingsManager globally available.

## Next Steps

1. **Test in Godot:** Open the project and verify no runtime errors
2. **Add to Start Screen:** Instance `settingsPanel.tscn` in your main menu
3. **Add Music:** When you add music tracks, assign them to the "Music" audio bus
4. **Optional:** Attach `vfx_aware_label.gd` to any jittering labels that weren't automatically updated

## Notes

- All cards automatically respond to VFX changes (no additional setup needed)
- All backgrounds automatically respond to VFX changes
- Settings persist across game sessions
- Sliders use 0-100 range (user-friendly percentages)
- Audio conversion handles dB scaling internally
