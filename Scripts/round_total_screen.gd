extends Control
## RoundTotalScreen
## Shows end-of-round scoring with card-by-card reveals and win/loss animations

@onready var panel: Panel = $Panel
@onready var player_total_label: Label = $Panel/PlayerRoundTotal
@onready var opponent_total_label: Label = $Panel/OpponentRoundTotal
@onready var player_hand: Hand = $Panel/CardManager/OpponentHand
@onready var opponent_hand: Hand = %PlayerHand
@onready var win_condition_label: Label = $Panel/WinCondition
@onready var player_new_score_label: Label = $Panel/PlayerNewScore
@onready var opponent_new_score_label: Label = %OpponentNewScore2

@export var card_reveal_delay: float = 1.5  # Time between each card reveal
@export var card_fade_in_duration: float = 0.8  # How long each card takes to fade in
@export var win_condition_delay: float = 2.0  # Delay after last card before showing win/loss
@export var score_count_duration: float = 2.0  # How long the winner's score counts up
@export var final_score_delay: float = 1.0  # Delay before showing loser's score

var player_round_total: int = 0
var opponent_round_total: int = 0
var player_cards: Array = []
var opponent_cards: Array = []
var is_animating: bool = false


func _ready() -> void:
	# Start hidden
	visible = false
	modulate.a = 0.0


## Shows the round results with card reveals and animations
func show_round_results(
	p_cards: Array,
	opp_cards: Array,
	p_previous_score: int,
	opp_previous_score: int
) -> void:
	if is_animating:
		return
	
	is_animating = true
	
	# Clear any existing cards from display hands
	_clear_display_hands()
	
	# Store card references
	player_cards = p_cards.duplicate()
	opponent_cards = opp_cards.duplicate()
	
	# Reset totals
	player_round_total = 0
	opponent_round_total = 0
	
	# Set initial labels
	if player_total_label:
		player_total_label.text = "0"
	if opponent_total_label:
		opponent_total_label.text = "0"
	if win_condition_label:
		win_condition_label.text = ""
	if player_new_score_label:
		player_new_score_label.text = str(p_previous_score)
	if opponent_new_score_label:
		opponent_new_score_label.text = str(opp_previous_score)
	
	# Move cards to the display hands
	_move_cards_to_display_hands()
	
	# Hide all cards initially
	_hide_all_cards()
	
	# Fade in the screen
	visible = true
	var fade_tween = create_tween()
	fade_tween.tween_property(self, "modulate:a", 1.0, 0.5)
	fade_tween.tween_callback(_start_card_reveals)


## Clears any existing cards from display hands
func _clear_display_hands() -> void:
	if player_hand and player_hand.has_method("clear_cards"):
		player_hand.clear_cards()
	if opponent_hand and opponent_hand.has_method("clear_cards"):
		opponent_hand.clear_cards()


## Moves cards from game hands to display hands
func _move_cards_to_display_hands() -> void:
	# Move player cards
	if player_hand:
		for card in player_cards:
			if card and is_instance_valid(card):
				# Unlock card to remove any lock overlays from gameplay
				if card.has_method("unlock"):
					card.unlock()
				# Remove from current container
				if card.card_container and card.card_container.has_method("remove_card"):
					card.card_container.remove_card(card)
				# Add to display hand
				player_hand.add_card(card)
		# Update layout after adding all cards
		if player_hand.has_method("update_card_ui"):
			player_hand.update_card_ui()
	
	# Move opponent cards
	if opponent_hand:
		for card in opponent_cards:
			if card and is_instance_valid(card):
				# Unlock card to remove any lock overlays from gameplay
				if card.has_method("unlock"):
					card.unlock()
				# Remove from current container
				if card.card_container and card.card_container.has_method("remove_card"):
					card.card_container.remove_card(card)
				# Add to display hand
				opponent_hand.add_card(card)
		# Update layout after adding all cards
		if opponent_hand.has_method("update_card_ui"):
			opponent_hand.update_card_ui()


## Hides all cards in both hands
func _hide_all_cards() -> void:
	if player_hand:
		for card in player_hand._held_cards:
			if card:
				card.modulate.a = 0.0
	
	if opponent_hand:
		for card in opponent_hand._held_cards:
			if card:
				card.modulate.a = 0.0


## Starts the card reveal sequence
func _start_card_reveals() -> void:
	var max_cards = max(player_cards.size(), opponent_cards.size())
	
	for i in range(max_cards):
		await get_tree().create_timer(card_reveal_delay).timeout
		_reveal_card_at_index(i)
	
	# After all cards are revealed, show win condition
	await get_tree().create_timer(win_condition_delay).timeout
	_show_win_condition()


## Reveals and scores a card at the given index for both players
func _reveal_card_at_index(index: int) -> void:
	# Reveal player card
	if player_hand:
			var cards_in_hand = player_hand._held_cards
			if index < cards_in_hand.size() and cards_in_hand[index]:
				var card_node = cards_in_hand[index]
				var tween = create_tween()
				tween.tween_property(card_node, "modulate:a", 1.0, card_fade_in_duration)
	
	# Reveal opponent card
	if opponent_hand:
		var cards_in_hand = opponent_hand._held_cards
		if index < cards_in_hand.size() and cards_in_hand[index]:
			var card_node = cards_in_hand[index]
			var tween = create_tween()
			tween.tween_property(card_node, "modulate:a", 1.0, card_fade_in_duration)
	
	# Update totals with card values from the actual displayed cards
	if player_hand and index < player_hand._held_cards.size():
		var displayed_player_card = player_hand._held_cards[index]
		if displayed_player_card and "value" in displayed_player_card:
			var card_value = int(displayed_player_card.value)  # Convert string to int
			player_round_total += card_value
			_animate_total_update(player_total_label, player_round_total)
	
	if opponent_hand and index < opponent_hand._held_cards.size():
		var displayed_opponent_card = opponent_hand._held_cards[index]
		if displayed_opponent_card and "value" in displayed_opponent_card:
			var card_value = int(displayed_opponent_card.value)  # Convert string to int
			opponent_round_total += card_value
			_animate_total_update(opponent_total_label, opponent_round_total)


## Animates a total label updating to a new value
func _animate_total_update(label: Label, new_value: int) -> void:
	if label:
		# Simple pop effect
		var original_scale = label.scale
		var tween = create_tween()
		tween.tween_property(label, "scale", original_scale * 1.2, 0.1)
		tween.tween_property(label, "scale", original_scale, 0.1)
		label.text = str(new_value)


## Determines and shows the win condition
func _show_win_condition() -> void:
	var condition_text: String
	var player_won: bool = false
	var opponent_won: bool = false
	
	# Lower score wins in this game (golf-style scoring)
	if player_round_total < opponent_round_total:
		condition_text = "You Win!"
		player_won = true
	elif opponent_round_total < player_round_total:
		condition_text = "You've lost..."
		opponent_won = true
	else:
		condition_text = "It's a tie"
	
	# Show win condition
	if win_condition_label:
		win_condition_label.text = condition_text
		var tween = create_tween()
		tween.tween_property(win_condition_label, "modulate:a", 0.0, 0.0)
		tween.tween_property(win_condition_label, "modulate:a", 1.0, 0.3)
	
	# Update scores
	await get_tree().create_timer(0.5).timeout
	
	# Animate winner's score counting up
	if player_won:
		await _count_up_score(player_new_score_label, player_round_total)
		await get_tree().create_timer(final_score_delay).timeout
		# Show opponent's score (no change)
		_flash_label(opponent_new_score_label)
	elif opponent_won:
		await _count_up_score(opponent_new_score_label, opponent_round_total)
		await get_tree().create_timer(final_score_delay).timeout
		# Show player's score (no change)
		_flash_label(player_new_score_label)
	else:
		# Tie - both scores stay the same, just flash them
		_flash_label(player_new_score_label)
		await get_tree().create_timer(final_score_delay).timeout
		_flash_label(opponent_new_score_label)
	
	is_animating = false
	# Signal or callback that animation is complete can go here


## Animates a score counting up
func _count_up_score(label: Label, points_to_add: int) -> void:
	if not label:
		return
	
	var start_score = int(label.text)
	var end_score = start_score + points_to_add
	var steps = 20  # Number of steps in the count animation
	var step_duration = score_count_duration / steps
	
	for i in range(steps + 1):
		var progress = float(i) / float(steps)
		var current_score = int(lerp(start_score, end_score, progress))
		label.text = str(current_score)
		
		# Small scale pulse effect
		var original_scale = label.scale
		var tween = create_tween()
		tween.tween_property(label, "scale", original_scale * 1.1, step_duration * 0.5)
		tween.tween_property(label, "scale", original_scale, step_duration * 0.5)
		
		await get_tree().create_timer(step_duration).timeout


## Simple flash effect for a label
func _flash_label(label: Label) -> void:
	if not label:
		return
	
	var original_scale = label.scale
	var tween = create_tween()
	tween.tween_property(label, "scale", original_scale * 1.3, 0.2)
	tween.tween_property(label, "scale", original_scale, 0.2)


## Hides the screen
func hide_screen() -> void:
	var tween = create_tween()
	tween.tween_property(self, "modulate:a", 0.0, 0.3)
	tween.tween_callback(func(): visible = false)


## Returns the round totals for both players
func get_round_totals() -> Dictionary:
	return {
		"player": player_round_total,
		"opponent": opponent_round_total
	}
