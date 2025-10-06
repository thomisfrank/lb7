# ai_opponent.gd
# AI opponent for the card game with difficulty levels

extends Node

class_name AIOpponent

enum Difficulty { EASY, MEDIUM, HARD }

var difficulty: Difficulty = Difficulty.MEDIUM
var opponent_hand: Node  # Hand container
var player_hand: Node    # Hand container
var deck: Node           # Pile container
var discard_pile: Node   # Pile container

const LOG = preload("res://Scripts/logger.gd")

## Main AI decision function
## Returns: {"type": "play_card", "card": Card} or {"type": "pass"}
func decide_action(actions_remaining: int) -> Dictionary:
	if not opponent_hand or not opponent_hand._held_cards:
		return {"type": "pass"}
	
	match difficulty:
		Difficulty.EASY:
			return _decide_easy(actions_remaining)
		Difficulty.MEDIUM:
			return _decide_medium(actions_remaining)
		Difficulty.HARD:
			return _decide_hard(actions_remaining)
	
	return {"type": "pass"}


## EASY: Random decisions with 40% pass chance
func _decide_easy(_actions_remaining: int) -> Dictionary:
	# 40% chance to just pass
	if randf() < 0.4:
		return {"type": "pass"}

	# Play random card if available (exclude locked cards)
	if opponent_hand and opponent_hand.get_card_count() > 0:
		var cards = opponent_hand._held_cards.duplicate()
		# Filter out locked cards
		var available_cards = []
		for card in cards:
			if card and not card.has_meta("is_locked"):
				available_cards.append(card)
		
		if available_cards.is_empty():
			return {"type": "pass"}
		
		var random_card = available_cards[randi() % available_cards.size()]
		return {"type": "play_card", "card": random_card}

	return {"type": "pass"}


## MEDIUM: Strategic decisions with 20% mistake rate
func _decide_medium(actions_remaining: int) -> Dictionary:
	# 20% chance to make suboptimal move (play like Easy AI)
	if randf() < 0.2:
		return _decide_easy(actions_remaining)
	
	# Try to find best move
	var best_move = _find_best_move(actions_remaining)
	return best_move


## HARD: Optimal play with 5% mistake rate
func _decide_hard(actions_remaining: int) -> Dictionary:
	# Only 5% chance to make mistake
	if randf() < 0.05:
		return _decide_medium(actions_remaining)
	
	
	# Optimal decision-making
	var best_move = _find_optimal_move(actions_remaining)
	return best_move


## Helper: Calculate total hand value
func _calculate_hand_value(hand: Node) -> int:
	var total = 0
	if not hand or not "_held_cards" in hand:
		return 0
	
	for card in hand._held_cards:
		if card and "value" in card:
			total += _get_numeric_value(card.value)
	return total


## Helper: Convert card value to number
func _get_numeric_value(value: String) -> int:
	if value.is_valid_int():
		return int(value)
	
	match value.to_upper():
		"A": return 1
		"J": return 11
		"Q": return 12
		"K": return 13
		_: return int(value) if value.is_valid_int() else 0


## Find best move based on card effects (Medium AI)
func _find_best_move(actions_remaining: int) -> Dictionary:
	var cards = opponent_hand._held_cards.duplicate()
	# Filter out locked cards
	var available_cards = []
	for card in cards:
		if card and not card.has_meta("is_locked"):
			available_cards.append(card)
	
	if available_cards.is_empty():
		return {"type": "pass"}
	
	var highest_card = null
	var highest_value = -1
	var best_draw_card = null
	var best_swap_card = null
	
	# Identify card types and values
	for card in available_cards:
		var card_value = _get_numeric_value(card.value)
		
		if card.card_name.begins_with("Draw_"):
			if not best_draw_card or card_value > _get_numeric_value(best_draw_card.value):
				best_draw_card = card
		elif card.card_name.begins_with("Swap_"):
			if not best_swap_card or card_value > _get_numeric_value(best_swap_card.value):
				best_swap_card = card
		else:
			# Regular card - track highest
			if card_value > highest_value:
				highest_value = card_value
				highest_card = card
	
	var hand_value = _calculate_hand_value(opponent_hand)
	
	# Strategy: Draw if we have high-value Draw cards (8+)
	if best_draw_card and _get_numeric_value(best_draw_card.value) >= 8:
		if deck and deck.get_card_count() > 0:
			return {"type": "play_card", "card": best_draw_card}
	
	# Strategy: Swap if we have high-value Swap cards (7+)
	if best_swap_card and _get_numeric_value(best_swap_card.value) >= 7:
		return {"type": "play_card", "card": best_swap_card}
	
	# Strategy: Pass only if hand is excellent (< 15 points)
	# or if hand is good (< 22 points) and this is the second action
	if hand_value < 15:
		return {"type": "pass"}
	
	if hand_value <= 22 and actions_remaining == 1:
		return {"type": "pass"}
	
	# Default: Play highest card if it's > 6
	if highest_card and highest_value > 6:
		return {"type": "play_card", "card": highest_card}
	
	# Otherwise pass
	return {"type": "pass"}


## Find optimal move (Hard AI)
func _find_optimal_move(actions_remaining: int) -> Dictionary:
	var cards = opponent_hand._held_cards.duplicate()
	# Filter out locked cards
	var available_cards = []
	for card in cards:
		if card and not card.has_meta("is_locked"):
			available_cards.append(card)
	
	if available_cards.is_empty():
		return {"type": "pass"}
	
	var hand_value = _calculate_hand_value(opponent_hand)
	
	# Evaluate each possible card play
	var best_card = null
	var best_expected_value = hand_value  # Current hand value is baseline
	
	for card in available_cards:
		var expected_value = _evaluate_card_play(card, hand_value)
		
		# Lower is better (we want to minimize hand value)
		if expected_value < best_expected_value:
			best_expected_value = expected_value
			best_card = card
	
	# Decide: play best card or pass?
	var improvement = hand_value - best_expected_value
	
	# Pass if improvement is minimal and hand is already decent
	if improvement < 2 and hand_value <= 24:
		return {"type": "pass"}

	# Pass if hand is already very good
	if hand_value <= 16 and actions_remaining == 2:
		return {"type": "pass"}

	if best_card:
		return {"type": "play_card", "card": best_card}

	return {"type": "pass"}


## Evaluate expected value of playing a card
func _evaluate_card_play(card: Card, current_hand_value: int) -> float:
	var card_value = _get_numeric_value(card.value)
	
	if card.card_name.begins_with("Draw_"):
		# Expected value: remove this card, add average deck card
		var avg_deck_value = _estimate_deck_average()
		var expected_new_value = current_hand_value - card_value + avg_deck_value
		return expected_new_value
	
	elif card.card_name.begins_with("Swap_"):
		# Expected value: swap this high card for estimated low card from player
		# Assume we can get a card worth ~3-5 points
		var expected_swap_gain = card_value - 4.0  # Average low card
		var expected_new_value = current_hand_value - expected_swap_gain
		return expected_new_value
	
	# For regular cards, we can't play them to improve hand
	return current_hand_value


## Estimate average value of remaining deck
func _estimate_deck_average() -> float:
	# Simple heuristic: average card is around 6-7 points
	# Could be improved by tracking what's been played
	return 6.5


## Choose which player card to swap with (for SWAP effect)
## AI cannot see player's cards, so this is always a blind guess
func choose_swap_target() -> Card:
	if not player_hand or not "_held_cards" in player_hand:
		return null
	
	var player_cards = player_hand._held_cards.duplicate()
	if player_cards.is_empty():
		return null
	
	# Filter out null cards
	var valid_cards = []
	for card in player_cards:
		if card and is_instance_valid(card):
			valid_cards.append(card)
	
	if valid_cards.is_empty():
		return null
	
	# AI cannot see player's cards - always pick randomly
	# Difficulty affects decision to swap, not which card to pick
	return valid_cards[randi() % valid_cards.size()]


## Find the lowest value card in a hand
func _find_lowest_card(hand: Node) -> Card:
	if not hand or not "_held_cards" in hand:
		return null
	
	var lowest_card = null
	var lowest_value = 999
	
	for card in hand._held_cards:
		if not card:
			continue
		
		var value = _get_numeric_value(card.value)
		if value < lowest_value:
			lowest_value = value
			lowest_card = card
	
	return lowest_card


## Set difficulty level
func set_difficulty(new_difficulty: Difficulty) -> void:
	difficulty = new_difficulty
	match difficulty:
		Difficulty.EASY:
			pass
		Difficulty.MEDIUM:
			pass
		Difficulty.HARD:
			pass
