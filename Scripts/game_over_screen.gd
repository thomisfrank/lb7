extends Control
## GameOverScreen
## Shows final game results with win/loss status, final score, stats, and best round hand

@onready var player_status_label: Label = $transparentBG/PlayerStatus
@onready var final_score_label: Label = $transparentBG/Score/FinalScore
@onready var best_round_score_label: Label = %BestRoundScore
@onready var best_round_hand: Hand = $transparentBG/CardManager/HandFromBestRound
@onready var swap_stat_label: Label = $transparentBG/Stats/Numbers/StatNumber
@onready var draw_stat_label: Label = $transparentBG/Stats/Numbers/StatNumber2
@onready var pass_stat_label: Label = $transparentBG/Stats/Numbers/StatNumber3
@onready var play_again_button: PanelContainer = $transparentBG/Buttons/PlayAgainButton
@onready var quit_button: Button = $transparentBG/Buttons/QuitButton

@export var card_reveal_delay: float = 0.5  # Time between each card reveal
@export var card_fade_in_duration: float = 0.3  # How long each card fades in

var best_round_cards: Array = []
var is_animating: bool = false


func _ready() -> void:
	# Start hidden
	visible = false
	modulate.a = 0.0
	
	# Set button text
	if play_again_button and play_again_button.has_node("Label"):
		play_again_button.get_node("Label").text = "Play Again"


## Shows the game over screen with all game stats
func show_game_over(
	player_won: bool,
	player_final_score: int,
	opponent_final_score: int,
	best_round_score: int,
	best_round_hand_cards: Array,
	swaps_used: int,
	draws_used: int,
	passes_taken: int
) -> void:
	if is_animating:
		return
	
	is_animating = true
	best_round_cards = best_round_hand_cards.duplicate()
	
	# Set win/loss status
	_set_player_status(player_won, player_final_score, opponent_final_score)
	
	# Set final score
	if final_score_label:
		final_score_label.text = str(player_final_score) + " - " + str(opponent_final_score)
	
	# Set best round score
	if best_round_score_label:
		best_round_score_label.text = str(best_round_score)
	
	# Set stats
	if swap_stat_label:
		swap_stat_label.text = str(swaps_used)
	if draw_stat_label:
		draw_stat_label.text = str(draws_used)
	if pass_stat_label:
		pass_stat_label.text = str(passes_taken)
	
	# Hide all cards in best round hand initially
	_hide_all_cards()
	
	# Fade in the screen
	visible = true
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	fade_tween.tween_callback(_start_card_reveals)


## Sets the player status text based on win/loss/tie
func _set_player_status(_player_won: bool, player_score: int, opponent_score: int) -> void:
	if not player_status_label:
		return
	
	var status_text: String
	
	if player_score > opponent_score:
		status_text = "You Win!"
	elif opponent_score > player_score:
		status_text = "You've lost..."
	else:
		status_text = "It's a tie"
	
	player_status_label.text = status_text


## Hides all cards in the best round hand
func _hide_all_cards() -> void:
	if best_round_hand:
		for card in best_round_hand.get_cards():
			if card:
				card.modulate.a = 0.0


## Starts the card reveal sequence for best round hand
func _start_card_reveals() -> void:
	if best_round_cards.is_empty():
		is_animating = false
		return
	
	for i in range(best_round_cards.size()):
		await get_tree().create_timer(card_reveal_delay).timeout
		_reveal_card_at_index(i)
	
	is_animating = false


## Reveals a card at the given index
func _reveal_card_at_index(index: int) -> void:
	if not best_round_hand:
		return
	
	var cards_in_hand = best_round_hand.get_cards()
	if index < cards_in_hand.size() and cards_in_hand[index]:
		var card_node = cards_in_hand[index]
		var tween = create_tween()
		tween.tween_property(card_node, "modulate:a", 1.0, card_fade_in_duration)
		
		# Add a little pop effect
		var original_scale = card_node.scale
		var scale_tween = create_tween()
		scale_tween.tween_property(card_node, "scale", original_scale * 1.1, card_fade_in_duration * 0.5)
		scale_tween.tween_property(card_node, "scale", original_scale, card_fade_in_duration * 0.5)


## Hides the screen
func hide_screen() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): visible = false)
