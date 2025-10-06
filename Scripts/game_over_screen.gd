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
	
	# Allow this screen to process even when game tree is paused
	process_mode = Node.PROCESS_MODE_ALWAYS
	
	# Set button text
	if play_again_button and play_again_button.has_node("AspectRatioContainer/Label"):
		play_again_button.get_node("AspectRatioContainer/Label").text = "Play Again"


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
	_show_game_over_internal(
		player_won,
		player_final_score,
		opponent_final_score,
		best_round_score,
		best_round_hand_cards,
		swaps_used,
		draws_used,
		passes_taken,
		false  # not surrendered
	)


## Shows the game over screen when player surrenders
func show_game_over_surrender(
	player_final_score: int,
	opponent_final_score: int,
	best_round_score: int,
	best_round_hand_cards: Array,
	swaps_used: int,
	draws_used: int,
	passes_taken: int
) -> void:
	_show_game_over_internal(
		false,  # player didn't win (surrendered)
		player_final_score,
		opponent_final_score,
		best_round_score,
		best_round_hand_cards,
		swaps_used,
		draws_used,
		passes_taken,
		true  # surrendered
	)


## Internal method to show game over screen
func _show_game_over_internal(
	player_won: bool,
	player_final_score: int,
	opponent_final_score: int,
	best_round_score: int,
	best_round_hand_cards: Array,
	swaps_used: int,
	draws_used: int,
	passes_taken: int,
	surrendered: bool
) -> void:
	print("DEBUG GAME_OVER_SCREEN: Received", best_round_hand_cards.size(), "cards for best round")
	print("DEBUG GAME_OVER_SCREEN: Best round score:", best_round_score)
	
	# Early exit if already animating
	if is_animating:
		print("DEBUG GAME_OVER_SCREEN: Already animating, exiting")
		return
	
	is_animating = true
	best_round_cards = best_round_hand_cards.duplicate()
	print("DEBUG GAME_OVER_SCREEN: Stored", best_round_cards.size(), "cards in best_round_cards")
	
	# Set win/loss status
	_set_player_status(player_won, player_final_score, opponent_final_score, surrendered)
	
	# Set final score
	if final_score_label:
		final_score_label.text = str(player_final_score) + " - " + str(opponent_final_score)
	
	# Set best round score (999 means no rounds won)
	if best_round_score_label:
		if best_round_score >= 999:
			best_round_score_label.text = "N/A"
		else:
			best_round_score_label.text = str(best_round_score)
	
	# Set stats
	if swap_stat_label:
		swap_stat_label.text = str(swaps_used)
	if draw_stat_label:
		draw_stat_label.text = str(draws_used)
	if pass_stat_label:
		pass_stat_label.text = str(passes_taken)

	# Play final game outcome sound (if SoundManager autoload is present)
	var sm = get_node_or_null("/root/SoundManager")
	if sm:
		if surrendered:
			sm.play_game_lost()
		elif player_won:
			sm.play_game_win()
		elif player_final_score > opponent_final_score:
			sm.play_game_win()
		elif opponent_final_score > player_final_score:
			sm.play_game_lost()
		else:
			sm.play_game_tied()

	# Hide all cards in best round hand initially
	_hide_all_cards()
	
	# Fade in the screen
	visible = true
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.3)
	fade_tween.tween_callback(_start_card_reveals)


## Sets the player status text based on win/loss/tie/surrender
func _set_player_status(_player_won: bool, player_score: int, opponent_score: int, surrendered: bool = false) -> void:
	if not player_status_label:
		return
	
	var status_text: String
	
	if surrendered:
		status_text = "You gave up!"
	elif player_score > opponent_score:
		status_text = "You Win!"
	elif opponent_score > player_score:
		status_text = "You've lost..."
	else:
		status_text = "It's a tie"
	
	player_status_label.text = status_text


## Populates the display hand with copies of the best round cards
func _populate_display_hand() -> void:
	print("DEBUG GAME_OVER_SCREEN: _populate_display_hand() called")
	print("DEBUG GAME_OVER_SCREEN: best_round_hand node:", best_round_hand)
	print("DEBUG GAME_OVER_SCREEN: best_round_cards.size():", best_round_cards.size())
	
	# Populate if we have a destination hand and cards
	if not best_round_hand or best_round_cards.is_empty():
		print("DEBUG GAME_OVER_SCREEN: Cannot populate - hand is null or cards empty")
		return
	
	# Clear any existing cards in the display hand
	if "_held_cards" in best_round_hand:
		print("DEBUG GAME_OVER_SCREEN: Clearing", best_round_hand._held_cards.size(), "existing cards")
		for card in best_round_hand._held_cards.duplicate():
			if card:
				card.queue_free()
		best_round_hand._held_cards.clear()
	
	# Create visual copies of the best round cards
	for i in range(best_round_cards.size()):
		var original_card = best_round_cards[i]
		print("DEBUG GAME_OVER_SCREEN: Processing card", i, ":", original_card)
		if original_card and is_instance_valid(original_card):
			# Card is already a duplicate, just use it directly
			original_card.modulate.a = 0.0  # Start hidden
			
			# Ensure card shows front face
			original_card.show_front = true
			
			# Unlock the card to remove any lock overlays from gameplay
			if original_card.has_method("unlock"):
				original_card.unlock()
			
			# Add to display hand
			if best_round_hand.has_node("Cards"):
				print("DEBUG GAME_OVER_SCREEN: Adding card", i, "to Cards node")
				best_round_hand.get_node("Cards").add_child(original_card)
				if "_held_cards" in best_round_hand:
					best_round_hand._held_cards.append(original_card)
					print("DEBUG GAME_OVER_SCREEN: Card added. Total cards in display hand:", best_round_hand._held_cards.size())
			else:
				print("DEBUG GAME_OVER_SCREEN: ERROR - best_round_hand has no 'Cards' child node!")
		else:
			print("DEBUG GAME_OVER_SCREEN: WARNING - Card", i, "is null or invalid!")


## Hides all cards in the best round hand
func _hide_all_cards() -> void:
	if best_round_hand and "_held_cards" in best_round_hand:
		for card in best_round_hand._held_cards:
			if card:
				card.modulate.a = 0.0


## Starts the card reveal sequence for best round hand
func _start_card_reveals() -> void:
	print("DEBUG GAME_OVER_SCREEN: _start_card_reveals() called")
	print("DEBUG GAME_OVER_SCREEN: best_round_cards has", best_round_cards.size(), "cards")
	
	if best_round_cards.is_empty():
		print("DEBUG GAME_OVER_SCREEN: best_round_cards is EMPTY, cannot reveal")
		is_animating = false
		return
	
	# Create visual copies of the best round cards in the display hand
	_populate_display_hand()

	# Ensure display hand cards are ordered left-to-right before revealing
	if best_round_hand and "_held_cards" in best_round_hand:
		print("DEBUG GAME_OVER_SCREEN: Sorting", best_round_hand._held_cards.size(), "cards in display hand")
		best_round_hand._held_cards.sort_custom(Callable(self, "_compare_node_x"))

	for i in range(best_round_cards.size()):
		await get_tree().create_timer(card_reveal_delay).timeout
		_reveal_card_at_index(i)
	
	is_animating = false


## Reveals a card at the given index
func _reveal_card_at_index(index: int) -> void:
	if not best_round_hand or not "_held_cards" in best_round_hand:
		return
	
	var cards_in_hand = best_round_hand._held_cards
	if index < cards_in_hand.size() and cards_in_hand[index]:
		var card_node = cards_in_hand[index]
		# Play a reveal SFX for this card (if available)
		var sm = get_node_or_null("/root/SoundManager")
		if sm:
			sm.play_reveal()
		var tween = create_tween()
		tween.tween_property(card_node, "modulate:a", 1.0, card_fade_in_duration)
		
		# Add a little pop effect
		var original_scale = card_node.scale
		var scale_tween = create_tween()
		scale_tween.tween_property(card_node, "scale", original_scale * 1.1, card_fade_in_duration * 0.5)
		scale_tween.tween_property(card_node, "scale", original_scale, card_fade_in_duration * 0.5)


## Helper comparator for sorting cards by global x position (left-to-right)
func _compare_node_x(a: Node, b: Node) -> int:
	# If either node is null, keep order
	if not a or not b:
		return 0
	var ax = 0.0
	var bx = 0.0
	if a.has_method("get_global_position"):
		ax = a.get_global_position().x
	elif a.has_method("get_global_rect") and a.get_global_rect():
		ax = a.get_global_rect().position.x
	if b.has_method("get_global_position"):
		bx = b.get_global_position().x
	elif b.has_method("get_global_rect") and b.get_global_rect():
		bx = b.get_global_rect().position.x
	if ax < bx:
		return -1
	elif ax > bx:
		return 1
	return 0


## Hides the screen
func hide_screen() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): visible = false)
