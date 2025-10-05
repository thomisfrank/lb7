extends Control
## GameStateScreen
## Displays game state messages like "Round #", "Your Turn", "Opponent's Turn"

@onready var label: Label = $CenterContainer/Label
@onready var color_rect: ColorRect = $CenterContainer/ColorRect

@export var display_duration: float = 1.0  # How long to show the message in seconds
@export var fade_in_duration: float = 0.2
@export var fade_out_duration: float = 0.2

var _current_tween: Tween


func _ready() -> void:
	# Start hidden
	visible = false
	modulate.a = 0.0


## Shows a game state message for the configured duration
func show_message(message: String) -> void:
	print("GameStateScreen: show_message called with '", message, "'")
	if label:
		label.text = message
	else:
		print("GameStateScreen: label is null!")
		return
	
	# Cancel any existing tween
	if _current_tween:
		_current_tween.kill()
	
	# Make visible
	visible = true
	print("GameStateScreen: Setting visible=true, starting animation")
	
	# Create fade in/out sequence
	_current_tween = create_tween()
	_current_tween.tween_property(self, "modulate:a", 1.0, fade_in_duration)
	_current_tween.tween_interval(display_duration)
	_current_tween.tween_property(self, "modulate:a", 0.0, fade_out_duration)
	_current_tween.tween_callback(_on_animation_complete)


## Shows "Round #" message
func show_round(round_number: int) -> void:
	print("GameStateScreen: show_round called with round ", round_number)
	show_message("Round " + str(round_number))


## Shows "Your Turn" message
func show_your_turn() -> void:
	show_message("Your Turn")


## Shows "Opponent's Turn" message
func show_opponent_turn() -> void:
	show_message("Opponent's Turn")


## Called when the animation completes
func _on_animation_complete() -> void:
	visible = false


## Immediately hides the screen
func hide_immediately() -> void:
	if _current_tween:
		_current_tween.kill()
	visible = false
	modulate.a = 0.0
