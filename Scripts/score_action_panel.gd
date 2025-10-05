extends Control
## ScoreActionPanel
## Manages player score display and action tracking

@onready var score_label: Label = $BG/ScorePanel/Score
@onready var action1_icon: TextureRect = $BG/Action1
@onready var action2_icon: TextureRect = $BG/Action2
@onready var no_action1_icon: TextureRect = $BG/NoAction1
@onready var no_action2_icon: TextureRect = $BG/NoAction2
@onready var pass_button: PanelContainer = $BG/PassButton
@onready var pass_button_label: Label = $BG/PassButton/AspectRatioContainer/Label

const MAX_ACTIONS: int = 2

var current_score: int = 0
var actions_remaining: int = 0  # Start with 0 so NoAction icons show by default
var is_player_panel: bool = true  # Set to false for opponent panel


func _ready() -> void:
	update_score_display()
	update_action_display()  # This will show NoAction icons since actions_remaining = 0
	hide_pass_button()
	
	# Set pass button text
	if pass_button_label:
		pass_button_label.text = "Pass"


## Updates the score display
func update_score_display() -> void:
	if score_label:
		# Format score with leading zeros (00, 01, 02, etc.)
		score_label.text = "%02d" % current_score


## Sets the score to a specific value
func set_score(new_score: int) -> void:
	current_score = new_score
	update_score_display()


## Adds points to the current score
func add_score(points: int) -> void:
	current_score += points
	update_score_display()


## Resets the score to 0
func reset_score() -> void:
	current_score = 0
	update_score_display()


## Returns the current score
func get_score() -> int:
	return current_score


## Updates the action icons based on remaining actions
func update_action_display() -> void:
	# Show/hide action icons based on remaining actions
	# Default is NoAction, switch to Action based on remaining actions
	if action1_icon and no_action1_icon:
		action1_icon.visible = actions_remaining >= 1
		no_action1_icon.visible = actions_remaining < 1
	
	if action2_icon and no_action2_icon:
		action2_icon.visible = actions_remaining >= 2
		no_action2_icon.visible = actions_remaining < 2


## Uses one action (called when a card is played)
func use_action() -> bool:
	if actions_remaining > 0:
		actions_remaining -= 1
		update_action_display()
		return true
	return false


## Resets actions to maximum
func reset_actions() -> void:
	actions_remaining = MAX_ACTIONS
	update_action_display()


## Clears all remaining actions (used when player passes)
func clear_actions() -> void:
	actions_remaining = 0
	update_action_display()


## Returns the number of remaining actions
func get_actions_remaining() -> int:
	return actions_remaining


## Checks if the player has actions remaining
func has_actions() -> bool:
	return actions_remaining > 0


## Shows the pass button (only for player panel during their turn)
func show_pass_button() -> void:
	if is_player_panel and pass_button:
		# Slide in animation - you can adjust this later
		pass_button.visible = true
		pass_button.modulate.a = 0.0
		var tween = create_tween()
		tween.tween_property(pass_button, "modulate:a", 1.0, 0.3)


## Hides the pass button
func hide_pass_button() -> void:
	if pass_button:
		var tween = create_tween()
		tween.tween_property(pass_button, "modulate:a", 0.0, 0.3)
		tween.tween_callback(func(): pass_button.visible = false)


## Sets whether this is a player panel (true) or opponent panel (false)
func set_is_player_panel(is_player: bool) -> void:
	is_player_panel = is_player
	# Opponent panels should never show the pass button
	if not is_player_panel:
		hide_pass_button()
