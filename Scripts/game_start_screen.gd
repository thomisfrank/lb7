extends Node
## Game start screen controller
##
## Manages the main menu with Start button (goes to level select) and 
## Settings button (toggles settings panel).

const LOG = preload("res://Scripts/logger.gd")

@onready var settings_panel = $SubViewportContainer/SubViewport/UILayer/"Settings Panel"
@onready var start_button = $SubViewportContainer/SubViewport/UILayer/VBoxContainer/StartButton/AspectRatioContainer/TextureButton
@onready var settings_button = $SubViewportContainer/SubViewport/UILayer/VBoxContainer/Settings
@onready var title_label = $SubViewportContainer/SubViewport/UILayer/VBoxContainer/Title


func _ready() -> void:
	# Connect buttons
	if start_button:
		start_button.pressed.connect(_on_start_pressed)
	
	if settings_button:
		settings_button.pressed.connect(_on_settings_pressed)
	
	# Ensure settings panel is hidden initially
	if settings_panel:
		settings_panel.visible = false
	
	# Set start button text
	var start_label = $SubViewportContainer/SubViewport/UILayer/VBoxContainer/StartButton/AspectRatioContainer/Label
	if start_label:
		start_label.text = "START"
	
	# Attach VFX-aware script to title if it has a shader
	if title_label and title_label.material:
		# Title already has the shader material, just need to make it VFX-aware
		# We can do this by adding the script dynamically if needed
		var vfx_script = load("res://Scripts/vfx_aware_label.gd")
		if vfx_script and not title_label.get_script():
			title_label.set_script(vfx_script)


func _input(event: InputEvent) -> void:
	# Close settings panel when clicking outside of it
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if settings_panel and settings_panel.visible:
			# Get the click position in global coordinates
			var click_pos = get_viewport().get_mouse_position()
			# Get the settings panel rect in global coordinates
			var panel_rect = settings_panel.get_global_rect()
			# If click is outside the panel, close it
			if not panel_rect.has_point(click_pos):
				settings_panel.visible = false
				LOG.tracking("Settings panel closed by clicking outside")


func _on_start_pressed() -> void:
	LOG.tracking("Start button pressed - loading level select")
	get_tree().change_scene_to_file("res://Scenes/LevelSelect.tscn")


func _on_settings_pressed() -> void:
	if settings_panel:
		settings_panel.visible = not settings_panel.visible
		LOG.tracking_args(["Settings panel toggled:", "visible" if settings_panel.visible else "hidden"])
