extends Node
## Global settings manager for game preferences (volume, visual effects, etc.)
##
## This autoload manages persistent game settings and provides signals for
## settings changes so UI and game elements can react accordingly.

const LOG = preload("res://Scripts/logger.gd")

# Settings values (0-100 for volumes, bool for VFX)
var music_volume: float = 100.0
var sfx_volume: float = 100.0
var visual_effects_enabled: bool = true

# Signals emitted when settings change
signal music_volume_changed(new_volume: float)
signal sfx_volume_changed(new_volume: float)
signal visual_effects_changed(enabled: bool)

# Config file for persistence
const SETTINGS_FILE = "user://settings.cfg"


func _ready() -> void:
	load_settings()


## Load settings from config file
func load_settings() -> void:
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	
	if err == OK:
		music_volume = config.get_value("audio", "music_volume", 100.0)
		sfx_volume = config.get_value("audio", "sfx_volume", 100.0)
		visual_effects_enabled = config.get_value("graphics", "visual_effects", true)
		LOG.tracking_args(["Loaded settings:", music_volume, sfx_volume, visual_effects_enabled])
		
		# Apply the loaded settings
		_apply_music_volume()
		_apply_sfx_volume()
		_apply_visual_effects()
	else:
		LOG.tracking_args(["No settings file found, using defaults"])


## Save settings to config file
func save_settings() -> void:
	var config = ConfigFile.new()
	config.set_value("audio", "music_volume", music_volume)
	config.set_value("audio", "sfx_volume", sfx_volume)
	config.set_value("graphics", "visual_effects", visual_effects_enabled)
	
	var err = config.save(SETTINGS_FILE)
	if err != OK:
		push_error("Failed to save settings: %d" % err)
	else:
		LOG.tracking_args(["Settings saved"])


## Set music volume (0-100)
func set_music_volume(volume: float) -> void:
	music_volume = clamp(volume, 0.0, 100.0)
	_apply_music_volume()
	music_volume_changed.emit(music_volume)
	save_settings()


## Set SFX volume (0-100)
func set_sfx_volume(volume: float) -> void:
	sfx_volume = clamp(volume, 0.0, 100.0)
	_apply_sfx_volume()
	sfx_volume_changed.emit(sfx_volume)
	save_settings()


## Toggle visual effects on/off
func set_visual_effects(enabled: bool) -> void:
	visual_effects_enabled = enabled
	_apply_visual_effects()
	LOG.log_args(["VFX setting changed to:", "ON" if enabled else "OFF", "- emitting signal"])
	visual_effects_changed.emit(visual_effects_enabled)
	save_settings()


## Apply music volume to the Music audio bus
func _apply_music_volume() -> void:
	var bus_idx = AudioServer.get_bus_index("Music")
	if bus_idx >= 0:
		# Convert 0-100 range to decibels (-80 to 0 dB)
		# At 0 volume, mute completely
		if music_volume <= 0:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			# Linear to dB conversion: lerp from -40dB to 0dB
			var db = linear_to_db(music_volume / 100.0)
			AudioServer.set_bus_volume_db(bus_idx, db)


## Apply SFX volume to the SFX audio bus (or Master if SFX bus doesn't exist)
func _apply_sfx_volume() -> void:
	# Try SFX bus first, fall back to Master
	var bus_idx = AudioServer.get_bus_index("SFX")
	if bus_idx < 0:
		bus_idx = AudioServer.get_bus_index("Master")
	
	if bus_idx >= 0:
		# Convert 0-100 range to decibels
		if sfx_volume <= 0:
			AudioServer.set_bus_mute(bus_idx, true)
		else:
			AudioServer.set_bus_mute(bus_idx, false)
			var db = linear_to_db(sfx_volume / 100.0)
			AudioServer.set_bus_volume_db(bus_idx, db)


## Apply visual effects setting
## This emits a signal that cards, backgrounds, and text can listen to
func _apply_visual_effects() -> void:
	# The signal emission is the main mechanism - individual nodes will listen
	LOG.tracking_args(["Visual effects:", "enabled" if visual_effects_enabled else "disabled"])
