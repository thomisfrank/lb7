extends SubViewportContainer
## Tutorial page controller
##
## Shows the "How to Play" screen with options to go back to menu or quick start an Easy game.

const LOG = preload("res://Scripts/logger.gd")

@onready var back_to_menu_button = $SubViewport/Control/BackToMenu/AspectRatioContainer/TextureButton
@onready var get_started_button = $SubViewport/Control/GetStarted/AspectRatioContainer/TextureButton

# Track original shader material for VFX toggle
var original_shader_material: ShaderMaterial = null


func _ready() -> void:
	# Connect buttons
	if back_to_menu_button:
		back_to_menu_button.pressed.connect(_on_back_to_menu_pressed)
	
	if get_started_button:
		get_started_button.pressed.connect(_on_get_started_pressed)
	
	# Set button texts
	var back_label = $SubViewport/Control/BackToMenu/AspectRatioContainer/Label
	if back_label:
		back_label.text = "Back to Menu"
	
	var start_label = $SubViewport/Control/GetStarted/AspectRatioContainer/Label
	if start_label:
		start_label.text = "Get Started"
	
	# Store original shader material and connect to VFX settings
	original_shader_material = self.material
	var settings_mgr = get_node_or_null("/root/SettingsManager")
	if settings_mgr and settings_mgr.has_signal("visual_effects_changed"):
		settings_mgr.visual_effects_changed.connect(_on_visual_effects_changed)
		# Apply current setting immediately
		_on_visual_effects_changed(settings_mgr.visual_effects_enabled)


func _on_back_to_menu_pressed() -> void:
	LOG.tracking("Back to Menu button pressed - returning to start screen")
	get_tree().change_scene_to_file("res://Scenes/GameStartScreen.tscn")


func _on_get_started_pressed() -> void:
	LOG.tracking("Get Started button pressed - quick starting Easy game")
	# Start an Easy difficulty game
	get_tree().change_scene_to_file("res://Scenes/main.tscn")


## Handle visual effects toggle (accessibility)
func _on_visual_effects_changed(enabled: bool) -> void:
	if enabled:
		# Restore original shader material
		self.material = original_shader_material
	else:
		# Disable all post-processing effects for accessibility
		self.material = null
	
	print("DEBUG: Tutorial page VFX post-processing ", "enabled" if enabled else "disabled")
