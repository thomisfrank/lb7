extends Control
## Settings panel UI controller
##
## Manages the settings panel UI elements (sliders, checkboxes) and syncs them
## with the SettingsManager autoload.

const LOG = preload("res://Scripts/logger.gd")

# UI element references
@onready var music_slider: HSlider = $TextureRect/MusicVolumeSlider
@onready var sfx_slider: HSlider = $TextureRect/SFXVolumeSlider
@onready var vfx_toggle: TextureButton = $TextureRect/ColorRect/TextureButton
@onready var vfx_label: Label = %VFXLabel2


func _ready() -> void:
	# Wait for autoloads to be ready
	await get_tree().process_frame
	
	# Get settings manager
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if not settings_mgr:
		push_error("SettingsManager autoload not found!")
		return
	
	# Initialize sliders and checkbox from current settings
	music_slider.value = settings_mgr.music_volume
	sfx_slider.value = settings_mgr.sfx_volume
	vfx_toggle.button_pressed = settings_mgr.visual_effects_enabled
	_update_vfx_label()
	
	# Connect UI signals
	music_slider.value_changed.connect(_on_music_volume_changed)
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	vfx_toggle.toggled.connect(_on_vfx_toggled)


func _on_music_volume_changed(value: float) -> void:
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_music_volume(value)


func _on_sfx_volume_changed(value: float) -> void:
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_sfx_volume(value)


func _on_vfx_toggled(button_pressed: bool) -> void:
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr:
		settings_mgr.set_visual_effects(button_pressed)
	_update_vfx_label()


func _update_vfx_label() -> void:
	if vfx_label:
		vfx_label.text = "On" if vfx_toggle.button_pressed else "Off"
