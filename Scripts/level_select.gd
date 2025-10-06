extends Control
## Level select screen controller
##
## Allows player to choose difficulty level (Easy, Medium, Hard) or return to main menu.

const LOG = preload("res://Scripts/logger.gd")

@onready var easy_button = $SubViewportContainer/SubViewport/UILayer/EasyButton/AspectRatioContainer/TextureButton
@onready var medium_button = $SubViewportContainer/SubViewport/UILayer/MediumButton/AspectRatioContainer/TextureButton
@onready var hard_button = $SubViewportContainer/SubViewport/UILayer/HardButton2/AspectRatioContainer/TextureButton
@onready var return_button = $SubViewportContainer/SubViewport/UILayer/ReturnButton/AspectRatioContainer/TextureButton
@onready var viewport_container: SubViewportContainer = $SubViewportContainer

# Card references
@onready var easy_card = $"SubViewportContainer/SubViewport/UILayer/CardReps/2Swap_easy"
@onready var medium_card = $"SubViewportContainer/SubViewport/UILayer/CardReps/6Draw_med"
@onready var hard_card = $"SubViewportContainer/SubViewport/UILayer/CardReps/10Swap_hard"

# Track original shader material for VFX toggle
var original_shader_material: ShaderMaterial = null


func _ready() -> void:
	# Connect difficulty buttons
	if easy_button:
		easy_button.pressed.connect(_on_easy_pressed)
	
	if medium_button:
		medium_button.pressed.connect(_on_medium_pressed)
	
	if hard_button:
		hard_button.pressed.connect(_on_hard_pressed)
	
	if return_button:
		return_button.pressed.connect(_on_return_pressed)
	
	# Connect card clicks
	if easy_card:
		easy_card.gui_input.connect(_on_easy_card_input)
	
	if medium_card:
		medium_card.gui_input.connect(_on_medium_card_input)
	
	if hard_card:
		hard_card.gui_input.connect(_on_hard_card_input)
	
	# Set button labels
	_set_button_text("EasyButton", "EASY")
	_set_button_text("MediumButton", "MEDIUM")
	_set_button_text("HardButton2", "HARD")
	_set_button_text("ReturnButton", "BACK")
	
	# Store original shader material and connect to VFX settings
	if viewport_container:
		original_shader_material = viewport_container.material
		var settings_mgr = get_node_or_null("/root/SettingsManager")
		if settings_mgr and settings_mgr.has_signal("visual_effects_changed"):
			settings_mgr.visual_effects_changed.connect(_on_visual_effects_changed)
			# Apply current setting immediately
			_on_visual_effects_changed(settings_mgr.visual_effects_enabled)


func _set_button_text(button_name: String, text: String) -> void:
	var label_path = "SubViewportContainer/SubViewport/UILayer/" + button_name + "/AspectRatioContainer/Label"
	var label = get_node_or_null(label_path)
	if label:
		label.text = text


func _on_easy_pressed() -> void:
	LOG.tracking("Easy difficulty selected")
	_start_game("easy")


func _on_medium_pressed() -> void:
	LOG.tracking("Medium difficulty selected")
	_start_game("medium")


func _on_hard_pressed() -> void:
	LOG.tracking("Hard difficulty selected")
	_start_game("hard")


func _start_game(_difficulty: String) -> void:
	# Store difficulty in a global or pass it to the main game scene
	# For now, we'll just load the main game scene
	# You can extend this to pass the difficulty parameter
	get_tree().change_scene_to_file("res://Scenes/main.tscn")
	# TODO: Pass difficulty to main game scene when it's set up to receive it


func _on_return_pressed() -> void:
	LOG.tracking("Return to main menu")
	get_tree().change_scene_to_file("res://Scenes/GameStartScreen.tscn")


## Card click handlers
func _on_easy_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_easy_pressed()


func _on_medium_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_medium_pressed()


func _on_hard_card_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_on_hard_pressed()


## Handle visual effects toggle (accessibility)
func _on_visual_effects_changed(enabled: bool) -> void:
	if not viewport_container:
		return
	
	if enabled:
		# Restore original shader material
		viewport_container.material = original_shader_material
	else:
		# Disable all post-processing effects for accessibility
		viewport_container.material = null
	
	print("DEBUG: Level select VFX post-processing ", "enabled" if enabled else "disabled")

