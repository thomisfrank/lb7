extends Control
## RoundCounter
## Displays and updates the current round number

@onready var round_label: Label = $PanelContainer/"#"

var current_round: int = 1


func _ready() -> void:
	update_display()


## Updates the round number display
func update_display() -> void:
	if round_label:
		round_label.text = str(current_round) + " "


## Sets the round number and updates the display
func set_round(round_number: int) -> void:
	current_round = round_number
	update_display()


## Increments the round counter by 1
func increment_round() -> void:
	current_round += 1
	update_display()


## Resets the round counter to 1
func reset() -> void:
	current_round = 1
	update_display()


## Returns the current round number
func get_current_round() -> int:
	return current_round
